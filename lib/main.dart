// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:safe_signal/services/foreground_session_service.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/contacts_service.dart';
import 'services/fcm_service.dart';
import 'services/share_intake_service.dart';
import 'ui/auth_gate.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Future.wait([
    AuthService.initialize(),
    ShareIntakeService.instance.init(),
    ForegroundSessionService.instance.init(),
    FcmService.instance.init(),
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
      debugShowCheckedModeBanner: false,
      theme: buildCalmTheme(),
      // themeMode: ThemeMode.light forces light regardless of system setting.
      // Escalation screens (check-in, in-grace, SOS) opt into red styling
      // directly via AppColors.danger — they don't need a dark theme.
      themeMode: ThemeMode.light,
      home: AuthGate(
        authService: authService,
        contactsService: contactsService,
      ),
    );
  }
}