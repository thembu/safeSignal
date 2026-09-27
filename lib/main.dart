// lib/main.dart
//
// The only change vs your existing main.dart is adding `FcmService.instance.init()`
// after Firebase.initializeApp. Everything else you already had.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:safe_signal/services/foreground_session_service.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/contacts_service.dart';
import 'services/fcm_service.dart'; // NEW
import 'services/share_intake_service.dart';
import 'ui/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Order matters: AuthService and ShareIntakeService can run in parallel
  // with FcmService init, but keep them awaited so the app doesn't render
  // before Firebase is fully ready.
  await Future.wait([
    AuthService.initialize(),
    ShareIntakeService.instance.init(),
    ForegroundSessionService.instance.init(),  // NEW
    FcmService.instance.init(), // NEW — registers background handler + channels
  ]);

  runApp(MyApp(
    authService: AuthService(),
    contactsService: ContactsService(),
  ));
}

class MyApp extends StatelessWidget {
  final AuthService authService;
  final ContactsService contactsService;

  const MyApp({
    super.key,
    required this.authService,
    required this.contactsService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeSignal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: AuthGate(
        authService: authService,
        contactsService: contactsService,
      ),
    );
  }
}