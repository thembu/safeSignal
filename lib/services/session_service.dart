import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/session.dart';

/// Seconds the user has to tap "I'm okay" after a check-in prompt.
const kCheckInWindowSeconds = 60;

/// Seconds the user has to cancel a false alarm before escalation fires.
const kGraceSeconds = 60;

class SessionService {
  SessionService({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('users').doc(uid).collection('sessions');

  /// Auto-cancels any live session, then creates a fresh one.
  Future<String> startSession({
    required int durationMinutes,
    String? tripLink,
  }) async {
    final now = DateTime.now();
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
    });

    await batch.commit();
    return newDoc.id;
  }

  Future<void> cancelSession(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'status': 'cancelled',
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Called when the scheduled check-in fires (either from notification tap
  /// or foreground timer). Moves status -> awaitingCheckIn with a 60s deadline.
  Future<void> promptCheckIn(String sessionId) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'awaiting_check_in',
      'checkInWindowEndsAt':
      Timestamp.fromDate(now.add(Duration(seconds: kCheckInWindowSeconds))),
    });
  }

  /// User tapped "I'm okay" (from either the awaitingCheckIn or inGrace state).
  /// Resets the cycle for another `durationMinutes` window.
  Future<void> confirmOkay(String sessionId, int durationMinutes) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'active',
      'checkInDueAt':
      Timestamp.fromDate(now.add(Duration(minutes: durationMinutes))),
      'checkInWindowEndsAt': FieldValue.delete(),
      'graceEndsAt': FieldValue.delete(),
    });
  }

  /// 60s check-in expired -> enter 60s grace before escalation.
  Future<void> enterGrace(String sessionId) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'in_grace',
      'graceEndsAt':
      Timestamp.fromDate(now.add(Duration(seconds: kGraceSeconds))),
    });
  }

  /// Grace window expired -> escalate. Cloud Function watches for this.
  Future<void> escalate(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'status': 'escalated',
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Stream of the current live session (active | awaiting | grace), or null.
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
}