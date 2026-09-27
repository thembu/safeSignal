// lib/services/session_service.dart
//
// State transitions previously done here (promptCheckIn, enterGrace,
// escalate) are now driven by the `tickSessions` Cloud Function, so
// they still exist as methods (foreground app can promote a tiny bit
// earlier for a snappier UX) but the server will do the same work
// within ~60s regardless. Never rely on the app being open.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models/session.dart';
import 'foreground_session_service.dart';

/// Seconds the user has to tap "I'm okay" after a check-in prompt.
/// Must match CHECK_IN_WINDOW_SECONDS in functions/index.js.
const kCheckInWindowSeconds = 60;

/// Seconds the user has to cancel a false alarm before escalation fires.
/// Must match GRACE_SECONDS in functions/index.js.
const kGraceSeconds = 60;

class SessionService {
  SessionService({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('users').doc(uid).collection('sessions');

  /// Auto-cancels any live session, then creates a fresh one.
  ///
  /// Stores the current FCM token on the session doc so `tickSessions`
  /// can push directly to this device without extra lookups.
  Future<String> startSession({
    required int durationMinutes,
    String? tripLink,
  }) async {
    final now = DateTime.now();

    // Fetch FCM token up front. Best-effort: if it fails we still
    // start the session — the server-side timer keeps working, only
    // the "wake the phone" push is missing.
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
      if (fcmToken != null) 'fcmToken': fcmToken,
    });

    await batch.commit();
// Start the persistent notification

    await ForegroundSessionService.instance.start(
      nextCheckInAt: now.add(Duration(minutes: durationMinutes)),
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

  /// Foreground fast-path: if the app is open when the timer fires,
  /// promote immediately instead of waiting for the next server tick.
  /// The Cloud Function does the same transition within ~60s regardless.
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
// Update the persistent notification with the new check-in time

    await ForegroundSessionService.instance.update(
      nextCheckInAt: now.add(Duration(minutes: durationMinutes)),
    );
  }

  /// Foreground fast-path for the awaitingCheckIn -> inGrace transition.
  Future<void> enterGrace(String sessionId) async {
    final now = DateTime.now();
    await _sessions.doc(sessionId).update({
      'status': 'in_grace',
      'graceEndsAt':
      Timestamp.fromDate(now.add(Duration(seconds: kGraceSeconds))),
    });
  }

  /// Foreground fast-path for the inGrace -> escalated transition.
  /// The Cloud Function also does this; whichever runs first wins.
  Future<void> escalate(String sessionId) async {
    await _sessions.doc(sessionId).update({
      'status': 'escalated',
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
}