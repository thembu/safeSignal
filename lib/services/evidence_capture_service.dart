// lib/services/evidence_capture_service.dart
//
// Watches for session status changes across the app. When status flips
// to `escalated`, captures evidence off-screen:
//   - 5 back-camera photos (burst)
//   - 5 front-camera photos (burst)
//   - 15s audio recording
//   - 10s back-camera video
//   - Last-known GPS location
// Each artifact is uploaded to Firebase Storage under
// users/{uid}/sessions/{sessionId}/... and its download URL is written
// to users/{uid}/sessions/{sessionId}/evidence/{artifactId}.
//
// This service is wired at the app root so it listens regardless of
// which screen the user is on.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/session.dart';

const int _kPhotoBurstCount = 5;
const Duration _kVideoDuration = Duration(seconds: 10);
const Duration _kAudioDuration = Duration(seconds: 15);

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
  final Set<String> _capturedSessions = {}; // dedupe
  String? _uid;

  void start(String uid) {
    if (_uid == uid && _sub != null) return;
    stop();
    _uid = uid;

    // Listen for sessions transitioning into escalated.
    _sub = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('sessions')
        .where('status', isEqualTo: 'escalated')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        final doc = change.doc;
        final id = doc.id;
        if (_capturedSessions.contains(id)) continue;
        _capturedSessions.add(id);
        _log('escalated session detected: $id — starting capture');
        _captureFor(uid, id).catchError((e) {
          _log('capture failed: $e');
        });
      }
    });
    _log('started for uid=$uid');
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
  }

  Future<void> _captureFor(String uid, String sessionId) async {
    // Fire location + audio + camera in parallel.
    final futures = <Future>[
      _captureLocation(uid, sessionId),
      _captureAudio(uid, sessionId),
      _captureCameras(uid, sessionId),
    ];
    await Future.wait(futures, eagerError: false);
    _log('capture complete for $sessionId');
  }

  // ---------- LOCATION ----------

  Future<void> _captureLocation(String uid, String sessionId) async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _log('location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      // Write onto the session doc so SMS/email can grab it fast.
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('sessions').doc(sessionId)
          .update({
        'lastLocation': {'lat': pos.latitude, 'lng': pos.longitude},
      });
      _log('location captured: ${pos.latitude},${pos.longitude}');
    } catch (e) {
      _log('location failed: $e');
    }
  }

  // ---------- AUDIO ----------

  Future<void> _captureAudio(String uid, String sessionId) async {
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        _log('audio permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/audio_$sessionId.m4a';
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
        path: path,
      );
      await Future.delayed(_kAudioDuration);
      final stopped = await rec.stop();
      if (stopped == null) return;
      final file = File(stopped);
      if (!await file.exists()) return;
      await _uploadAndRecord(
        uid: uid,
        sessionId: sessionId,
        file: file,
        storageName: 'audio.m4a',
        type: 'audio',
      );
    } catch (e) {
      _log('audio failed: $e');
    } finally {
      await rec.dispose();
    }
  }

  // ---------- CAMERAS ----------

  Future<void> _captureCameras(String uid, String sessionId) async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      _log('availableCameras failed: $e');
      return;
    }

    CameraDescription? back;
    CameraDescription? front;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.back) back ??= c;
      if (c.lensDirection == CameraLensDirection.front) front ??= c;
    }

    if (back != null) {
      await _capturePhotos(uid, sessionId, back, 'back');
      await _captureVideo(uid, sessionId, back);
    }
    if (front != null) {
      await _capturePhotos(uid, sessionId, front, 'front');
    }
  }

  Future<void> _capturePhotos(
      String uid, String sessionId, CameraDescription cam, String label) async {
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      for (int i = 0; i < _kPhotoBurstCount; i++) {
        try {
          final xfile = await controller.takePicture();
          final f = File(xfile.path);
          await _uploadAndRecord(
            uid: uid,
            sessionId: sessionId,
            file: f,
            storageName: 'photo_${label}_${i + 1}.jpg',
            type: 'photo',
            metadata: {'camera': label, 'index': i + 1},
          );
        } catch (e) {
          _log('photo $label #$i failed: $e');
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      _log('photo controller $label failed: $e');
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _captureVideo(
      String uid, String sessionId, CameraDescription cam) async {
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    try {
      await controller.initialize();
      await controller.startVideoRecording();
      await Future.delayed(_kVideoDuration);
      final xfile = await controller.stopVideoRecording();
      await _uploadAndRecord(
        uid: uid,
        sessionId: sessionId,
        file: File(xfile.path),
        storageName: 'video.mp4',
        type: 'video',
      );
    } catch (e) {
      _log('video failed: $e');
    } finally {
      await controller.dispose();
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
      _log('uploaded $storageName');
    } catch (e) {
      _log('upload $storageName failed: $e');
    }
  }
}