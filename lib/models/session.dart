import 'package:cloud_firestore/cloud_firestore.dart';

enum SessionStatus {
  active,            // running, waiting for next check-in
  awaitingCheckIn,   // check-in prompt shown, 60s window
  inGrace,           // 60s check-in expired, 60s grace before escalation
  checkedIn,         // manually ended after successful check-in
  escalated,         // grace expired -> alerts fire
  cancelled,         // user cancelled
}

SessionStatus _statusFromString(String? s) {
  switch (s) {
    case 'active':
      return SessionStatus.active;
    case 'awaiting_check_in':
      return SessionStatus.awaitingCheckIn;
    case 'in_grace':
      return SessionStatus.inGrace;
    case 'checked_in':
      return SessionStatus.checkedIn;
    case 'escalated':
      return SessionStatus.escalated;
    case 'cancelled':
      return SessionStatus.cancelled;
    default:
      return SessionStatus.active;
  }
}

String statusToString(SessionStatus s) {
  switch (s) {
    case SessionStatus.active:
      return 'active';
    case SessionStatus.awaitingCheckIn:
      return 'awaiting_check_in';
    case SessionStatus.inGrace:
      return 'in_grace';
    case SessionStatus.checkedIn:
      return 'checked_in';
    case SessionStatus.escalated:
      return 'escalated';
    case SessionStatus.cancelled:
      return 'cancelled';
  }
}

/// Statuses treated as "still going" (session appears on HomeScreen active view).
const kLiveStatuses = <SessionStatus>{
  SessionStatus.active,
  SessionStatus.awaitingCheckIn,
  SessionStatus.inGrace,
};

const kLiveStatusStrings = <String>[
  'active',
  'awaiting_check_in',
  'in_grace',
];

class Session {
  final String id;
  final DateTime startedAt;
  final SessionStatus status;
  final int durationMinutes;
  final String? tripLink;
  final DateTime? checkInDueAt;       // when next check-in prompt fires
  final DateTime? checkInWindowEndsAt; // deadline to tap "I'm okay"
  final DateTime? graceEndsAt;         // deadline to cancel false alarm
  final DateTime? endedAt;

  Session({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.durationMinutes,
    this.tripLink,
    this.checkInDueAt,
    this.checkInWindowEndsAt,
    this.graceEndsAt,
    this.endedAt,
  });

  factory Session.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Session(
      id: doc.id,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _statusFromString(data['status'] as String?),
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 10,
      tripLink: data['tripLink'] as String?,
      checkInDueAt: (data['checkInDueAt'] as Timestamp?)?.toDate(),
      checkInWindowEndsAt:
      (data['checkInWindowEndsAt'] as Timestamp?)?.toDate(),
      graceEndsAt: (data['graceEndsAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
    );
  }
}