/// Domain-level user, decoupled from Firebase types.
class User {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const User({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });
}