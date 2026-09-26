import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';

/// Wraps FirebaseAuth + GoogleSignIn so the UI never touches SDK types.
class AuthService {
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  /// Call once at app startup (from main).
  static Future<void> initialize() async {
    await GoogleSignIn.instance.initialize();
  }

  /// Stream of the currently signed-in user, or null when signed out.
  Stream<User?> get authStateChanges =>
      _auth.authStateChanges().map(_mapUser);

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
  }) async {
    await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
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