// lib/services/foreground_session_service.dart

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../firebase_options.dart';

const double _kSpikeThreshold = 25.0;
const int _kRequiredSpikes = 3;
const Duration _kSpikeWindow = Duration(milliseconds: 1500);
const Duration _kDebounce = Duration(seconds: 5);
const Duration _kCancelWindow = Duration(seconds: 5);

const int _kShakeNotifId = 7777;
const String _kShakeChannelId = 'safesignal_shake_cancel';
const String _kShakeChannelName = 'SafeSignal shake alert';

const String _kDataUid = 'uid';
const String _kDataSessionId = 'sessionId';
const String _kMsgCancel = 'cancel_shake';

void _p(String tag, String msg) {
  // ignore: avoid_print
  print('[$tag] $msg');
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SessionTaskHandler());
}

@pragma('vm:entry-point')
void _onNotifActionBg(NotificationResponse resp) {
  FlutterForegroundTask.sendDataToTask(_kMsgCancel);
}

class _SessionTaskHandler extends TaskHandler {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<DateTime> _spikes = [];
  DateTime? _lastFired;

  String? _uid;
  String? _sessionId;

  Timer? _cancelTimer;
  bool _awaitingCancel = false;

  final _notif = FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      _p('TaskHandler', 'Firebase init FAILED: $e');
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _notif.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotifActionBg,
        onDidReceiveBackgroundNotificationResponse: _onNotifActionBg,
      );
      final android = _notif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _kShakeChannelId,
          _kShakeChannelName,
          description: 'Confirm or cancel a shake-triggered alert',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
        await android.requestNotificationsPermission();
      }
    } catch (e) {
      _p('TaskHandler', 'notif init FAILED: $e');
    }

    try {
      _uid = await FlutterForegroundTask.getData<String>(key: _kDataUid);
      _sessionId =
      await FlutterForegroundTask.getData<String>(key: _kDataSessionId);
    } catch (e) {
      _p('TaskHandler', 'getData FAILED: $e');
    }

    _startShakeStream();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _accelSub?.cancel();
    _accelSub = null;
    _cancelTimer?.cancel();
    await _notif.cancel(_kShakeNotifId);
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data.containsKey(_kDataUid)) _uid = data[_kDataUid] as String?;
      if (data.containsKey(_kDataSessionId)) {
        _sessionId = data[_kDataSessionId] as String?;
      }
    } else if (data == _kMsgCancel) {
      _cancelPending();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'cancel_shake') _cancelPending();
  }

  void _startShakeStream() {
    _accelSub?.cancel();
    _spikes.clear();
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAccel);
  }

  void _onAccel(AccelerometerEvent e) {
    if (_awaitingCancel) return;
    final now = DateTime.now();
    if (_lastFired != null && now.difference(_lastFired!) < _kDebounce) return;

    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (magnitude < _kSpikeThreshold) return;

    _spikes.add(now);
    _spikes.removeWhere((t) => now.difference(t) > _kSpikeWindow);

    if (_spikes.length >= _kRequiredSpikes) {
      _lastFired = now;
      _spikes.clear();
      _onShakeDetected();
    }
  }

  Future<void> _onShakeDetected() async {
    if (_uid == null || _sessionId == null) return;
    _awaitingCancel = true;

    try {
      await _notif.show(
        _kShakeNotifId,
        'Shake detected',
        'Sending emergency alert in 5s. Tap CANCEL if false alarm.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kShakeChannelId,
            _kShakeChannelName,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            actions: const [
              AndroidNotificationAction(
                'cancel_shake',
                'CANCEL',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
        payload: 'cancel_shake',
      );
    } catch (e) {
      _p('TaskHandler', 'notif show FAILED: $e');
    }

    _cancelTimer?.cancel();
    _cancelTimer = Timer(_kCancelWindow, _fireEscalation);
  }

  Future<void> _cancelPending() async {
    if (!_awaitingCancel) return;
    _cancelTimer?.cancel();
    _awaitingCancel = false;
    await _notif.cancel(_kShakeNotifId);
  }

  Future<void> _fireEscalation() async {
    if (!_awaitingCancel) return;
    _awaitingCancel = false;
    await _notif.cancel(_kShakeNotifId);

    final uid = _uid, sessionId = _sessionId;
    if (uid == null || sessionId == null) return;

    // Bring app to foreground so evidence capture (camera) can run.
    try {
      FlutterForegroundTask.launchApp('/');
    } catch (e) {
      _p('TaskHandler', 'launchApp failed: $e');
    }

    // Give the app a moment to come to the front before flipping status.
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('sessions').doc(sessionId)
          .update({
        'status': 'escalated',
        'triggerReason': 'shake',
        'endedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      _p('TaskHandler', 'escalate write FAILED: $e');
    }
  }
}

class ForegroundSessionService {
  ForegroundSessionService._();
  static final instance = ForegroundSessionService._();

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safesignal_ongoing',
        channelName: 'SafeSignal active session',
        channelDescription:
        'Shown while a check-in session is running so you always '
            'know SafeSignal is watching.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> start({
    required DateTime nextCheckInAt,
    required String uid,
    required String sessionId,
  }) async {
    await FlutterForegroundTask.saveData(key: _kDataUid, value: uid);
    await FlutterForegroundTask.saveData(
        key: _kDataSessionId, value: sessionId);

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      FlutterForegroundTask.sendDataToTask({
        _kDataUid: uid,
        _kDataSessionId: sessionId,
      });
      await update(nextCheckInAt: nextCheckInAt);
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 4242,
      notificationTitle: 'SafeSignal active',
      notificationText: _formatBody(nextCheckInAt),
      callback: _foregroundTaskCallback,
    );
  }

  Future<void> update({required DateTime nextCheckInAt}) async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SafeSignal active',
      notificationText: _formatBody(nextCheckInAt),
    );
  }

  Future<void> stop() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;
    await FlutterForegroundTask.stopService();
  }

  String _formatBody(DateTime nextCheckInAt) {
    final hh = nextCheckInAt.hour.toString().padLeft(2, '0');
    final mm = nextCheckInAt.minute.toString().padLeft(2, '0');
    return 'Next check-in at $hh:$mm · Tap to view';
  }
}