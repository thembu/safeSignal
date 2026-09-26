import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print('[CheckInScheduler] $msg');
}

class CheckInScheduler {
  CheckInScheduler._();
  static final instance = CheckInScheduler._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  static const _checkInNotificationId = 1001;
  static const _channelId = 'safesignal_checkin';
  static const _channelName = 'SafeSignal check-ins';
  static const _channelDesc =
      'Discreet check-in prompts while a safety session is running';

  Future<void> init({
    required void Function(String sessionId) onTap,
  }) async {
    if (_initialised) {
      _log('init: already initialised, skipping');
      return;
    }
    _log('init: initialising timezones…');
    tzdata.initializeTimeZones();
    _log('init: local tz = ${tz.local.name}');

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    final ok = await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _log('onDidReceiveNotificationResponse: payload=${response.payload}');
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onTap(payload);
      },
    );
    _log('init: plugin.initialize returned $ok');

    final android = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) {
      _log('init: WARNING — could not resolve Android plugin impl');
    } else {
      final notifPerm = await android.requestNotificationsPermission();
      _log('init: requestNotificationsPermission -> $notifPerm');

      // Android 12+ needs SCHEDULE_EXACT_ALARM (user grantable on Android 14+).
      final exactPerm = await android.requestExactAlarmsPermission();
      _log('init: requestExactAlarmsPermission -> $exactPerm');
    }

    _initialised = true;
    _log('init: done');
  }

  Future<void> schedule({
    required String sessionId,
    required DateTime when,
  }) async {
    _log('schedule: sessionId=$sessionId when=$when (now=${DateTime.now()})');
    await cancel();

    final tzWhen = tz.TZDateTime.from(when, tz.local);
    _log('schedule: tzWhen=$tzWhen (${tzWhen.timeZoneName})');

    if (tzWhen.isBefore(tz.TZDateTime.now(tz.local))) {
      _log('schedule: WARNING — target time is in the past');
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
    );

    try {
      await _plugin.zonedSchedule(
        _checkInNotificationId,
        'SafeSignal check-in',
        'Tap to confirm you\'re okay',
        tzWhen,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: sessionId,
      );
      _log('schedule: zonedSchedule OK');
    } catch (e, st) {
      _log('schedule: zonedSchedule FAILED: $e\n$st');
      rethrow;
    }

    final pending = await _plugin.pendingNotificationRequests();
    _log('schedule: ${pending.length} pending notification(s):');
    for (final p in pending) {
      _log('  id=${p.id} title=${p.title} payload=${p.payload}');
    }
  }

  /// Fire a notification immediately — use to sanity-check the pipeline.
  Future<void> testFireNow() async {
    _log('testFireNow: firing immediate notification');
    await _plugin.show(
      9999,
      'SafeSignal test',
      'If you see this, notifications work',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
    _log('testFireNow: shown');
  }

  Future<void> cancel() async {
    await _plugin.cancel(_checkInNotificationId);
    _log('cancel: cancelled id=$_checkInNotificationId');
  }
}