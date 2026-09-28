// lib/services/session_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

import '../models/session.dart';
import 'foreground_session_service.dart';

const kCheckInWindowSeconds = 60;
const kGraceSeconds = 60;

class SessionService {
  SessionService({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('users').doc(uid).collection('sessions');

  Future<String> startSession({
    required int durationMinutes,
    String? tripLink,
    String? mode,
  }) async {
    final now = DateTime.now();

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      fcmToken = null;
    }

    final liveSnap = await _sessions
        .where('status', whereIn: kLiveStatusStrings)
        .get();

    final batch = _db.batch();
    for (final doc in liveSnap.docs) {
      batch.update(doc.reference, {
        'status': 'cancelled',
        'endedAt': Timestamp.fromDate(now),
      });
    }

    final newDoc = _sessions.doc();
    batch.set(newDoc, {
      'startedAt': Timestamp.fromDate(now),
      'status': 'active',
      'durationMinutes': durationMinutes,
      'checkInDueAt':
      Timestamp.fromDate(now.add(Duration(minutes: durationMinutes))),
      if (tripLink != null) 'tripLink': tripLink,
      if (mode != null) 'mode': mode,
      if (fcmToken != null) 'fcmToken': fcmToken,
    });

    await batch.commit();

    // Initial location ping (skip for e-hailing — Uber/Bolt link carries live loc).
    await _pingLocation(newDoc.id, mode: mode);

    await ForegroundSessionService.instance.start(
      nextCheckInAt: now.add(Duration(minutes: durationMinutes)),
      uid: uid,
      sessionId: newDoc.id,
    );

    return newDoc.id;
  }

  Future<void> cancelSession(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'status': 'cancelled',
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });

    await ForegroundSessionService.instance.stop();
  }

  Future<void> promptCheckIn(String sessionId) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'awaiting_check_in',
      'checkInWindowEndsAt':
      Timestamp.fromDate(now.add(Duration(seconds: kCheckInWindowSeconds))),
    });

    // Ping on every check-in tick so lastLocation stays fresh.
    final mode = await _readMode(sessionId);
    await _pingLocation(sessionId, mode: mode);
  }

  Future<void> confirmOkay(String sessionId, int durationMinutes) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'active',
      'checkInDueAt':
      Timestamp.fromDate(now.add(Duration(minutes: durationMinutes))),
      'checkInWindowEndsAt': FieldValue.delete(),
      'graceEndsAt': FieldValue.delete(),
    });

    await ForegroundSessionService.instance.update(
      nextCheckInAt: now.add(Duration(minutes: durationMinutes)),
    );
  }

  Future<void> enterGrace(String sessionId) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'in_grace',
      'graceEndsAt':
      Timestamp.fromDate(now.add(Duration(seconds: kGraceSeconds))),
    });
  }

  Future<void> escalate(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'status': 'escalated',
      'triggerReason': 'missed_check_in',
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });

    await ForegroundSessionService.instance.stop();
  }

  Future<void> escalateManual(String sessionId,
      {required String reason}) async {
    await _sessions.doc(sessionId).update({
      'status': 'escalated',
      'triggerReason': reason,
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });

    await ForegroundSessionService.instance.stop();
  }

  Stream<Session?> watchActiveSession() {
    return _sessions
        .where('status', whereIn: kLiveStatusStrings)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return Session.fromFirestore(snap.docs.first);
    });
  }

  Stream<Session> watchSession(String sessionId) {
    return _sessions.doc(sessionId).snapshots().map(Session.fromFirestore);
  }

  // --- helpers ---

  Future<String?> _readMode(String sessionId) async {
    try {
      final snap = await _sessions.doc(sessionId).get();
      return snap.data()?['mode'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort GPS write to the session doc. Skipped for e-hailing where
  /// the Uber/Bolt trip link already carries live location for contacts.
  Future<void> _pingLocation(String sessionId, {String? mode}) async {
    if (mode == 'ehailing') return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _sessions.doc(sessionId).update({
        'lastLocation': {
          'lat': pos.latitude,
          'lng': pos.longitude,
        },
        'lastLocationAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (_) {
      // best effort — don't block the session on a failed ping
    }
  }
}