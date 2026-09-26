import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import 'contacts_screen.dart';

class HomeScreen extends StatelessWidget {
  final AuthService authService;
  final ContactsService contactsService;
  final User user;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.contactsService,
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  if (user.photoUrl != null)
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: NetworkImage(user.photoUrl!),
                    )
                  else
                    const Icon(Icons.shield, size: 64),
                  const SizedBox(height: 12),
                  if (user.displayName != null)
                    Text(user.displayName!,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(user.email ?? 'unknown'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Card(
              child: ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Trusted contacts'),
                subtitle: const Text('People alerted if you don\'t check in'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactsScreen(
                      contactsService: contactsService,
                      uid: user.uid,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}