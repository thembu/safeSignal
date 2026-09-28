// lib/ui/auth_gate.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import '../services/evidence_capture_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void _log(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[AuthGate] $msg');
  }
}

class AuthGate extends StatelessWidget {
  final AuthService authService;
  final ContactsService contactsService;

  const AuthGate({
    super.key,
    required this.authService,
    required this.contactsService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        _log('build: connectionState=${snapshot.connectionState} '
            'hasData=${snapshot.hasData}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          final user = snapshot.data!;
          _log('user signed in: uid=${user.uid} — starting EvidenceCaptureService');
          EvidenceCaptureService.instance.start(user.uid);
          return HomeScreen(
            authService: authService,
            contactsService: contactsService,
            user: user,
          );
        }
        _log('no user — stopping EvidenceCaptureService');
        EvidenceCaptureService.instance.stop();
        return AuthScreen(authService: authService);
      },
    );
  }
}