import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  final AuthService authService;
  final User user;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSignal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (user.photoUrl != null)
              CircleAvatar(
                radius: 40,
                backgroundImage: NetworkImage(user.photoUrl!),
              )
            else
              const Icon(Icons.shield, size: 64),
            const SizedBox(height: 16),
            if (user.displayName != null)
              Text(user.displayName!,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            Text(user.email ?? 'unknown'),
            const SizedBox(height: 16),
            const Text('Trusted contacts screen goes here next.'),
          ],
        ),
      ),
    );
  }
}