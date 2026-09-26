import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/contacts_service.dart';
import 'ui/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AuthService.initialize();
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