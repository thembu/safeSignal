// lib/services/location_ping_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LocationPingService {
  static Future<void> pingIfNeeded(String uid, String sessionId, {required String? mode}) async {
    // Skip for e-hailing — Uber link has live location
    if (mode == 'ehailing') return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('sessions').doc(sessionId)
          .update({
        'lastLocation': {'lat': pos.latitude, 'lng': pos.longitude},
        'lastLocationAt': Timestamp.now(),
      });
    } catch (_) { /* best effort */ }
  }
}