// lib/models/date_context.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Pre-session metadata captured before a "date" mode session starts.
/// Persisted at users/{uid}/sessions/{sessionId}/dateContext/info
/// and included in the escalation email.
class DateContext {
  final String personName;
  final String howMet;         // Tinder, Hinge, Bumble, Grindr, Instagram, In person, Other
  final String? howMetOther;   // filled when howMet == 'Other'
  final String venueName;
  final String venueAddress;
  final DateTime expectedEndAt;
  final String? personPhotoUrl;
  final String? carPhotoUrl;
  final String? carPlate;
  final DateTime createdAt;

  DateContext({
    required this.personName,
    required this.howMet,
    this.howMetOther,
    required this.venueName,
    required this.venueAddress,
    required this.expectedEndAt,
    this.personPhotoUrl,
    this.carPhotoUrl,
    this.carPlate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'personName': personName,
    'howMet': howMet,
    'howMetOther': howMetOther,
    'venueName': venueName,
    'venueAddress': venueAddress,
    'expectedEndAt': Timestamp.fromDate(expectedEndAt),
    'personPhotoUrl': personPhotoUrl,
    'carPhotoUrl': carPhotoUrl,
    'carPlate': carPlate,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory DateContext.fromMap(Map<String, dynamic> m) => DateContext(
    personName: m['personName'] as String? ?? '',
    howMet: m['howMet'] as String? ?? '',
    howMetOther: m['howMetOther'] as String?,
    venueName: m['venueName'] as String? ?? '',
    venueAddress: m['venueAddress'] as String? ?? '',
    expectedEndAt:
    (m['expectedEndAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    personPhotoUrl: m['personPhotoUrl'] as String?,
    carPhotoUrl: m['carPhotoUrl'] as String?,
    carPlate: m['carPlate'] as String?,
    createdAt:
    (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}