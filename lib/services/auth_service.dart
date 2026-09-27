import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';

/// Wraps FirebaseAuth + GoogleSignIn so the UI never touches SDK types.
class AuthService {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Call once at app startup (from main).
  static Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
  }

  /// Stream of the currently signed-in user, or null when signed out.
  /// Also upserts the profile doc on every auth state change so existing
  /// users get backfilled the first time they open this build.
  Stream<User?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser).asyncMap((u) async {
        if (u != null) {
          // Fire-and-forget — don't block the stream on Firestore write.
          _upsertProfile(u).catchError((_) {});
        }
        return u;
      });

  User? get currentUser => _mapUser(_auth.currentUser);

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    if (displayName != null && displayName.isNotEmpty) {
      await cred.user?.updateDisplayName(displayName);
      await cred.user?.reload();
    }
  }

  Future<void> signInWithGoogle() async {
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final credential = fb.GoogleAuthProvider.credential(idToken: auth.idToken);
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  /// Merge-writes user profile fields to users/{uid}. Safe to call every
  /// sign-in — existing fields (like manually-set displayName) are kept.
  Future<void> _upsertProfile(User u) async {
    final ref = _db.collection('users').doc(u.uid);
    final data = <String, dynamic>{
      'uid': u.uid,
      if (u.email != null) 'email': u.email,
      if (u.displayName != null && u.displayName!.isNotEmpty)
        'displayName': u.displayName,
      if (u.photoUrl != null) 'photoUrl': u.photoUrl,
      'lastSignInAt': FieldValue.serverTimestamp(),
    };

    // Only set createdAt if the doc doesn't exist yet.
    final snap = await ref.get();
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await ref.set(data, SetOptions(merge: true));
  }

  User? _mapUser(fb.User? user) {
    if (user == null) return null;
    return User(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }
}