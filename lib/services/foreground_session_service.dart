// lib/services/foreground_session_service.dart
//
// Keeps a persistent, non-dismissible notification in the status bar
// while a SafeSignal session is active. The notification is quiet — no
// sound, no vibration — just a permanent visible reminder that the app
// is on guard, updated every minute with the next check-in time.
//
// The loud alarm at the grace step is a separate mechanism (see
// AlarmService); this service is only the ambient background presence.
//
// Requirements (pubspec.yaml):
//   flutter_foreground_task: ^8.0.0
//
// AndroidManifest.xml — inside <manifest> before <application>:
//   <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
//   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
//   <uses-permission android:name="android.permission.WAKE_LOCK"/>
//
// AndroidManifest.xml — inside <application>:
//   <service
//       android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
//       android:foregroundServiceType="dataSync"
//       android:exported="false"/>

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// The task callback that runs inside the foreground service isolate.
/// Must be top-level or static, and annotated so tree-shaking keeps it.
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SessionTaskHandler());
}

class _SessionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Nothing to do — initial notification is set by the start() call
    // in ForegroundSessionService.start().
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // We don't tick here — the main isolate updates the notification
    // via ForegroundSessionService.update() whenever session state
    // changes. This handler just needs to exist to keep the service
    // alive.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Nothing to clean up.
  }
}

class ForegroundSessionService {
  ForegroundSessionService._();
  static final instance = ForegroundSessionService._();

  bool _initialised = false;

  /// Call once from main() before runApp.
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
        channelImportance: NotificationChannelImportance.LOW, // quiet
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
        // Don't play sound/vibrate — this is a passive presence, not
        // an alert. The alarm at grace is a separate channel.
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

  /// Start the persistent notification. Call when a session begins.
  Future<void> start({required DateTime nextCheckInAt}) async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      // Already running from a previous session — just update.
      await update(nextCheckInAt: nextCheckInAt);
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 4242,
      notificationTitle: 'SafeSignal active',
      notificationText: _formatBody(nextCheckInAt),
      callback: _foregroundTaskCallback,
    );
    _log('started');
  }

  /// Update the persistent notification text. Call when checkInDueAt
  /// changes (session started, "I'm okay" tapped, etc).
  Future<void> update({required DateTime nextCheckInAt}) async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: 'SafeSignal active',
      notificationText: _formatBody(nextCheckInAt),
    );
  }

  /// Stop the persistent notification. Call when session ends
  /// (confirmOkay to final end, cancelled, escalated).
  Future<void> stop() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;
    await FlutterForegroundTask.stopService();
    _log('stopped');
  }

  String _formatBody(DateTime nextCheckInAt) {
    final hh = nextCheckInAt.hour.toString().padLeft(2, '0');
    final mm = nextCheckInAt.minute.toString().padLeft(2, '0');
    return 'Next check-in at $hh:$mm · Tap to view';
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ForegroundSessionService] $msg');
    }
  }
}