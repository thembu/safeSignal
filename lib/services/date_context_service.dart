// lib/services/date_context_service.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/date_context.dart';

/// Uploads pre-session photos to Storage and writes the dateContext/info doc
/// under users/{uid}/sessions/{sessionId}/dateContext/info.
class DateContextService {
  DateContextService({
    required this.uid,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final String uid;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  /// image_picker returns temp cache paths (e.g. /cache/scaled_*.jpg) that
  /// Android may evict at any time. Copy to app documents dir so the file
  /// is guaranteed to exist when putFile reads it.
  Future<File> persistLocalCopy(File src, String kind) async {
    if (!await src.exists()) {
      throw StateError('Picked file no longer exists at ${src.path}');
    }
    final dir = await getApplicationDocumentsDirectory();
    final ext = _extOf(src.path);
    final dst = File(
      '${dir.path}/date_ctx_${kind}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    return src.copy(dst.path);
  }

  /// Uploads a local image file and returns the download URL.
  /// [kind] is 'person' or 'car'. File is copied to a persistent location
  /// first so cache eviction can't break the upload.
  Future<String> uploadImage({
    required String sessionId,
    required File file,
    required String kind,
  }) async {
    final persisted = await persistLocalCopy(file, kind);
    final ext = _extOf(persisted.path);
    final ref = _storage
        .ref()
        .child('users/$uid/sessions/$sessionId/date_context/$kind$ext');
    final task = await ref.putFile(persisted);
    if (task.state != TaskState.success) {
      throw StateError('Upload for $kind ended in state ${task.state}');
    }
    return ref.getDownloadURL();
  }

  /// Persist the DateContext doc.
  Future<void> writeContext({
    required String sessionId,
    required DateContext context,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('dateContext')
        .doc('info')
        .set(context.toMap());
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i == -1) return '.jpg';
    return path.substring(i).toLowerCase();
  }
}