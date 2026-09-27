// lib/services/alarm_service.dart
//
// Loud alarm for the in_grace state: looping siren + repeating haptic
// buzz driven from Dart. Uses Flutter's built-in HapticFeedback so we
// avoid the `vibration` package entirely (which either needs the new
// v2 API + AndroidX 34, or uses removed Flutter v1 embedding).
//
// Requirements (pubspec.yaml):
//   audioplayers: ^6.0.0
//
// Assets:
//   assets/audio/siren.mp3
//   (register it under `flutter: assets:` in pubspec.yaml)
//
// No manifest permissions needed — HapticFeedback uses the OS's
// built-in vibrator via Flutter's SystemChannels and doesn't require
// the VIBRATE permission on Android for short haptic feedback.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AlarmService {
  AlarmService._();
  static final instance = AlarmService._();

  final AudioPlayer _player = AudioPlayer(playerId: 'safesignal_alarm');
  Timer? _hapticTimer;
  bool _running = false;

  bool get isRunning => _running;

  /// Start the loud alarm. Safe to call multiple times; no-op if already running.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _log('start');

    // ---- Audio ----
    try {
      // Play through the ALARM stream on Android so it bypasses
      // ringer-silent mode — the whole point of grace-state noise
      // is that a phone on silent in a bag still gets heard.
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/siren.mp3'));
    } catch (e, st) {
      _log('audio start failed: $e\n$st');
      // Fall through — haptics alone are better than nothing.
    }

    // ---- Haptics ----
    // HapticFeedback can't do a custom waveform, so we fake a pattern
    // by firing a heavy impact every ~600ms. Feels like a steady
    // aggressive buzz on real devices.
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  /// Stop everything. Safe to call multiple times.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _log('stop');

    _hapticTimer?.cancel();
    _hapticTimer = null;

    try {
      await _player.stop();
    } catch (_) {}
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AlarmService] $msg');
    }
  }
}