import 'package:cloud_firestore/cloud_firestore.dart';

class TrustedContact {
  final String id;
  final String name;
  final String phone; // Stored as E.164, e.g. +27821234567
  final String email;

  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
  });

  factory TrustedContact.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return TrustedContact(
      id: doc.id,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'phone': phone,
    'email': email,
    'createdAt': FieldValue.serverTimestamp(),
  };
}