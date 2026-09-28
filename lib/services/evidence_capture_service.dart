// lib/services/evidence_capture_service.dart
//
// Watches for session status changes across the app. When status flips
// to `escalated`, captures evidence off-screen:
//   - up to 3 back-camera photos
//   - up to 3 front-camera photos
//   - 15s audio recording
//   - 10s back-camera video (no audio track — mic is held by AudioRecorder)
//   - Last-known GPS location
//
// Robustness notes:
//
// * We only listen for the MOST RECENT escalated session (ordered by
//   endedAt desc, limit 1). Old escalated sessions from previous runs
//   are ignored. If a genuine new emergency happens, it becomes the new
//   "most recent" and gets captured; we deal with one emergency at a
//   time by design.
//
// * A freshness window still guards against replaying a stale
//   most-recent session (e.g. if the app is reinstalled but the last
//   escalated session in Firestore is from days ago).
//
// * Before running, we write `evidenceCaptureStartedAt` to the session
//   doc as an idempotency marker. If the doc already has it, we skip.
//
// * Each photo uses a FRESH CameraController (init → warmup → 1 shot →
//   dispose). Reusing one controller for a burst caused CameraX to drop
//   the ImageCapture use-case mid-burst on some devices.
//
// * We ensure camera / mic / location permissions ourselves at capture
//   time.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/session.dart';

const int _kPhotoBurstCount = 3;
const Duration _kVideoDuration = Duration(seconds: 10);
const Duration _kAudioDuration = Duration(seconds: 15);

// Only capture sessions whose escalation happened within this window.
// Guards against replaying a stale escalation from a much earlier run.
const Duration _kFreshWindow = Duration(minutes: 2);

// Give the Activity time to resume after the foreground-service task
// calls launchApp() before we start binding CameraX.
const Duration _kResumeDelay = Duration(milliseconds: 1500);
// After CameraController.initialize(), give CameraX a moment to actually
// bind the use-cases before firing the shutter.
const Duration _kCameraWarmup = Duration(milliseconds: 800);
// Small pause between shots to let CameraX settle.
const Duration _kInterShotDelay = Duration(milliseconds: 250);

void _log(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[EvidenceCapture] $msg');
  }
}

class EvidenceCaptureService {
  EvidenceCaptureService._();
  static final instance = EvidenceCaptureService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final Set<String> _handled = {}; // in-memory dedupe
  String? _uid;

  void start(String uid) {
    if (_uid == uid && _sub != null) {
      _log('start: already listening for uid=$uid, skipping');
      return;
    }
    stop();
    _uid = uid;

    _log('start: attaching Firestore listener for uid=$uid '
        '(most recent escalated session only)');

    // Only the newest escalated session — old sessions from previous
    // runs are never surfaced.
    _sub = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('sessions')
        .where('status', isEqualTo: 'escalated')
        .orderBy('endedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) {
        _log('snapshot: no escalated sessions');
        return;
      }
      final doc = snap.docs.first;
      final id = doc.id;
      final data = doc.data();

      _log('snapshot: most recent escalated = $id');

      if (_handled.contains(id)) {
        _log('  skipping $id (already handled this run)');
        return;
      }

      // Idempotency: another client / earlier run may already have started.
      if (data['evidenceCaptureStartedAt'] != null) {
        _log('  skipping $id (evidenceCaptureStartedAt already set)');
        _handled.add(id);
        return;
      }

      // Freshness: don't replay ancient escalations.
      final endedAtTs = data['endedAt'];
      if (endedAtTs is Timestamp) {
        final age = DateTime.now().difference(endedAtTs.toDate());
        if (age > _kFreshWindow) {
          _log('  skipping $id (stale, escalated ${age.inMinutes}m ago)');
          _handled.add(id);
          return;
        }
      }

      _handled.add(id);
      _log('escalated session detected: $id — starting capture');
      _captureFor(uid, id).catchError((e, st) {
        _log('capture failed for $id: $e\n$st');
      });
    }, onError: (e, st) {
      _log('snapshot stream error: $e\n$st');
    });
    _log('started for uid=$uid');
  }

  void stop() {
    if (_sub != null) {
      _log('stop: cancelling subscription for uid=$_uid');
    }
    _sub?.cancel();
    _sub = null;
    _uid = null;
  }

  Future<void> _captureFor(String uid, String sessionId) async {
    _log('_captureFor: START uid=$uid sessionId=$sessionId');

    // Claim the session with a transaction — prevents another client
    // (or another app instance) from double-capturing.
    final sessionRef = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('sessions').doc(sessionId);
    try {
      final claimed = await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(sessionRef);
        final data = snap.data() ?? <String, dynamic>{};
        if (data['evidenceCaptureStartedAt'] != null) return false;
        tx.update(sessionRef, {
          'evidenceCaptureStartedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) {
        _log('_captureFor: $sessionId already claimed elsewhere, skipping');
        return;
      }
    } catch (e) {
      _log('_captureFor: claim failed: $e — proceeding anyway');
    }

    // Wait for the Activity to fully resume before touching CameraX.
    _log('_captureFor: waiting ${_kResumeDelay.inMilliseconds}ms for resume');
    await Future.delayed(_kResumeDelay);

    // Ensure runtime permissions ourselves; the UI flow might not have
    // been through if this fired from a cold-start escalation.
    await _ensureCapturePermissions();

    // Location has no shared hardware — kick it off in the background.
    unawaited(_captureLocation(uid, sessionId));

    // Cameras FIRST while the mic is free.
    await _captureCameras(uid, sessionId);

    // Then the audio recording — mic is guaranteed free.
    await _captureAudio(uid, sessionId);

    _log('capture complete for $sessionId');
  }

  Future<void> _ensureCapturePermissions() async {
    try {
      final needed = [
        Permission.camera,
        Permission.microphone,
        Permission.location,
      ];
      final missing = <Permission>[];
      for (final p in needed) {
        if (!(await p.status).isGranted) missing.add(p);
      }
      if (missing.isEmpty) {
        _log('_ensureCapturePermissions: all granted');
        return;
      }
      _log('_ensureCapturePermissions: requesting ${missing.length} permission(s)');
      final results = await missing.request();
      for (final entry in results.entries) {
        _log('  ${entry.key}: ${entry.value}');
      }
    } catch (e) {
      _log('_ensureCapturePermissions failed: $e');
    }
  }

  // ---------- LOCATION ----------

  Future<void> _captureLocation(String uid, String sessionId) async {
    _log('_captureLocation: start');
    try {
      final perm = await Geolocator.checkPermission();
      _log('_captureLocation: permission=$perm');
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _log('location permission denied');
        return;
      }

      // Fast path: last-known fix.
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          _log('location: lastKnown=${pos.latitude},${pos.longitude}');
          await _writeLocation(uid, sessionId, pos);
        }
      } catch (e) {
        _log('lastKnown failed: $e');
      }

      // Slow path: fresh fix, best-effort.
      try {
        final fresh = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
        _log('location: fresh=${fresh.latitude},${fresh.longitude}');
        await _writeLocation(uid, sessionId, fresh);
      } catch (e) {
        _log('getCurrentPosition failed (kept lastKnown if any): $e');
      }
    } catch (e, st) {
      _log('location failed: $e\n$st');
    }
  }

  Future<void> _writeLocation(
      String uid, String sessionId, Position pos) async {
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('sessions').doc(sessionId)
        .update({
      'lastLocation': {'lat': pos.latitude, 'lng': pos.longitude},
    });
  }

  // ---------- AUDIO ----------

  Future<void> _captureAudio(String uid, String sessionId) async {
    _log('_captureAudio: start');
    final rec = AudioRecorder();
    try {
      final hasPerm = await rec.hasPermission();
      _log('_captureAudio: hasPermission=$hasPerm');
      if (!hasPerm) {
        _log('audio permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/audio_$sessionId.m4a';
      _log('_captureAudio: starting recorder → $path');
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
        path: path,
      );
      _log('_captureAudio: recording for ${_kAudioDuration.inSeconds}s');
      await Future.delayed(_kAudioDuration);
      final stopped = await rec.stop();
      _log('_captureAudio: stopped, file=$stopped');
      if (stopped == null) return;
      final file = File(stopped);
      if (!await file.exists()) {
        _log('_captureAudio: file does not exist at $stopped');
        return;
      }
      _log('_captureAudio: file size=${await file.length()} bytes');
      await _uploadAndRecord(
        uid: uid,
        sessionId: sessionId,
        file: file,
        storageName: 'audio.m4a',
        type: 'audio',
      );
    } catch (e, st) {
      _log('audio failed: $e\n$st');
    } finally {
      await rec.dispose();
    }
  }

  // ---------- CAMERAS ----------

  Future<void> _captureCameras(String uid, String sessionId) async {
    _log('_captureCameras: start');
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
      _log('_captureCameras: found ${cameras.length} camera(s): '
          '${cameras.map((c) => c.lensDirection.name).join(", ")}');
    } catch (e, st) {
      _log('availableCameras failed: $e\n$st');
      return;
    }

    CameraDescription? back;
    CameraDescription? front;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.back) back ??= c;
      if (c.lensDirection == CameraLensDirection.front) front ??= c;
    }
    _log('_captureCameras: back=${back != null} front=${front != null}');

    // Strictly sequential — one controller lifecycle at a time.
    if (back != null) {
      await _capturePhotoBurst(uid, sessionId, back, 'back');
      await _captureVideo(uid, sessionId, back);
    }
    if (front != null) {
      await _capturePhotoBurst(uid, sessionId, front, 'front');
    }
  }

  /// Takes N photos, each with a FRESH controller. Reusing one controller
  /// across a burst caused CameraX to unbind the ImageCapture use-case
  /// mid-burst on Samsung devices.
  Future<void> _capturePhotoBurst(String uid, String sessionId,
      CameraDescription cam, String label) async {
    _log('_capturePhotoBurst $label: taking $_kPhotoBurstCount shots '
        '(one controller per shot)');
    for (int i = 0; i < _kPhotoBurstCount; i++) {
      await _captureOnePhoto(uid, sessionId, cam, label, i + 1);
      await Future.delayed(_kInterShotDelay);
    }
  }

  Future<void> _captureOnePhoto(String uid, String sessionId,
      CameraDescription cam, String label, int index) async {
    _log('_captureOnePhoto $label #$index: init controller');
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      _log('_captureOnePhoto $label #$index: initialized, warming up '
          '${_kCameraWarmup.inMilliseconds}ms');
      await Future.delayed(_kCameraWarmup);
      final xfile = await controller.takePicture();
      final f = File(xfile.path);
      _log('_captureOnePhoto $label #$index: captured '
          '${await f.length()} bytes');
      await _uploadAndRecord(
        uid: uid,
        sessionId: sessionId,
        file: f,
        storageName: 'photo_${label}_$index.jpg',
        type: 'photo',
        metadata: {'camera': label, 'index': index},
      );
    } catch (e, st) {
      _log('_captureOnePhoto $label #$index failed: $e\n$st');
    } finally {
      try {
        await controller.dispose();
      } catch (_) {}
      _log('_captureOnePhoto $label #$index: disposed');
    }
  }

  Future<void> _captureVideo(
      String uid, String sessionId, CameraDescription cam) async {
    _log('_captureVideo: initializing controller');
    // enableAudio: false — the mic is captured separately by AudioRecorder,
    // and requesting audio here caused init conflicts on some devices.
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      _log('_captureVideo: initialized, warming up '
          '${_kCameraWarmup.inMilliseconds}ms');
      await Future.delayed(_kCameraWarmup);
      _log('_captureVideo: recording ${_kVideoDuration.inSeconds}s');
      await controller.startVideoRecording();
      await Future.delayed(_kVideoDuration);
      final xfile = await controller.stopVideoRecording();
      final f = File(xfile.path);
      _log('_captureVideo: stopped, file size=${await f.length()} bytes');
      await _uploadAndRecord(
        uid: uid,
        sessionId: sessionId,
        file: f,
        storageName: 'video.mp4',
        type: 'video',
      );
    } catch (e, st) {
      _log('video failed: $e\n$st');
    } finally {
      try {
        await controller.dispose();
      } catch (_) {}
      _log('_captureVideo: controller disposed');
    }
  }

  // ---------- UPLOAD ----------

  Future<void> _uploadAndRecord({
    required String uid,
    required String sessionId,
    required File file,
    required String storageName,
    required String type,
    Map<String, dynamic>? metadata,
  }) async {
    final storagePath = 'users/$uid/sessions/$sessionId/$storageName';
    _log('_uploadAndRecord: uploading $storageName → $storagePath');
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('sessions').doc(sessionId)
          .collection('evidence')
          .add({
        'type': type,
        'storagePath': storagePath,
        'url': url,
        'createdAt': FieldValue.serverTimestamp(),
        if (metadata != null) ...metadata,
      });
      _log('uploaded $storageName ✓');
    } catch (e, st) {
      _log('upload $storageName failed: $e\n$st');
    }
  }
}