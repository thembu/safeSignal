// lib/services/fcm_service.dart
//
// Handles FCM messages from the tickSessions Cloud Function.
//
// The Cloud Function sends data-only messages with these `kind`s:
//   check_in_due    -> session moved to awaiting_check_in
//   grace_started   -> session moved to in_grace (LOUD alarm)
//
// We handle both foreground and background:
//   - Foreground: the Firestore stream already updates the UI, but we
//     also fire a local notification so the user gets a visible cue
//     when the app is open but not on the ehailing screen.
//   - Background: we MUST show a notification ourselves — data-only
//     messages don't auto-display. For grace_started we show a
//     full-screen intent with alarm sound + high priority so Android
//     wakes the screen and rings even on silent.
//
// Add to pubspec.yaml (already there in most cases):
//   firebase_messaging: ^15.0.0
//   flutter_local_notifications: ^17.0.0

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channels. Must match the IDs used when we `show()` a
/// notification, and must be created before use on Android 8+.
const _checkInChannelId = 'safesignal_checkin';
const _checkInChannelName = 'SafeSignal check-ins';

const _alarmChannelId = 'safesignal_alarm';
const _alarmChannelName = 'SafeSignal ALARM';

/// This function MUST be a top-level or static function so it can be
/// invoked from a background isolate. The @pragma is critical — without
/// it, tree-shaking will drop the function in release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Note: Firebase is auto-initialized on Android for background
  // handlers as of firebase_messaging 11+, so no Firebase.initializeApp
  // needed here.
  await FcmService._showFromRemoteMessage(message);
}

class FcmService {
  FcmService._();
  static final instance = FcmService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  /// Call once from main() after Firebase.initializeApp.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // 1. Init local notifications & create both channels.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      // Standard check-in channel — normal notification.
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _checkInChannelId,
        _checkInChannelName,
        description: 'Discreet check-in prompts',
        importance: Importance.max,
      ));

      // ALARM channel — critical for the grace state.
      //   - IMPORTANCE_MAX so it makes noise on silent
      //   - custom sound baked in (rawResourceAndroidNotificationSound)
      //   - bypasses DND with category=alarm on the notification
      // NOTE: channel settings are locked once created. If you change
      // them (e.g. sound), users have to uninstall or the channel keeps
      // the old settings. During dev, uninstall between changes.
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: 'Loud alarm when a check-in is missed',
        importance: Importance.max,
        playSound: true,
        // Put a `siren.mp3` in android/app/src/main/res/raw/siren.mp3
        // (raw resource name, no extension). Falls back to default
        // alarm sound if the file isn't there.
        sound: RawResourceAndroidNotificationSound('siren'),
        enableVibration: true,
        vibrationPattern: null, // uses default alarm pattern
      ));

      // Request notification permission on Android 13+
      await android.requestNotificationsPermission();
    }

    // 2. Register the background handler.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Foreground handler.
    FirebaseMessaging.onMessage.listen(_showFromRemoteMessage);

    // 4. Request FCM permission (iOS mostly, no-op on Android <13).
    await FirebaseMessaging.instance.requestPermission();

    if (kDebugMode) {
      final token = await FirebaseMessaging.instance.getToken();
      // ignore: avoid_print
      print('[FcmService] FCM token: $token');
    }
  }

  /// Renders the right notification based on message.data['kind'].
  static Future<void> _showFromRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final kind = data['kind'];
    final title = data['title'] ?? 'SafeSignal';
    final body = data['body'] ?? '';

    if (kDebugMode) {
      // ignore: avoid_print
      print('[FcmService] received kind=$kind title=$title body=$body');
    }

    if (kind == 'grace_started') {
      await _showAlarmNotification(title: title, body: body);
    } else if (kind == 'check_in_due') {
      await _showCheckInNotification(title: title, body: body);
    }
  }

  static Future<void> _showCheckInNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      1001,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _checkInChannelId,
          _checkInChannelName,
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
        ),
      ),
    );
  }

  static Future<void> _showAlarmNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      2001,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _alarmChannelId,
          _alarmChannelName,
          importance: Importance.max,
          priority: Priority.max,
          // The channel already declares the alarm sound, but setting
          // these on the notification too helps on some OEM skins.
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          // Sticky — user must interact to dismiss.
          ongoing: true,
          autoCancel: false,
        ),
      ),
    );
  }
}