import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/contacts_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return HomeScreen(
            authService: authService,
            contactsService: contactsService,
            user: snapshot.data!,
          );
        }
        return AuthScreen(authService: authService);
      },
    );
  }
}