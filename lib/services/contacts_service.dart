import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trusted_contact.dart';

class ContactsService {
  static const int maxContacts = 3;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _db.collection('users').doc(uid).collection('contacts');

  /// Stream of contacts for a user, ordered by creation time.
  Stream<List<TrustedContact>> watchContacts(String uid) {
    return _collection(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => TrustedContact.fromFirestore(d)).toList());
  }

  Future<void> addContact({
    required String uid,
    required String name,
    required String phone,
    required String email,
  }) async {
    // Guard against exceeding the cap on the client too (rules enforce it server-side).
    final existing = await _collection(uid).count().get();
    if ((existing.count ?? 0) >= maxContacts) {
      throw StateError('You can only have up to $maxContacts trusted contacts.');
    }

    await _collection(uid).add({
      'name': name,
      'phone': phone,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteContact({
    required String uid,
    required String contactId,
  }) async {
    await _collection(uid).doc(contactId).delete();
  }
}