import 'package:flutter/material.dart';

/// Placeholder — "I'm being followed" flow.
/// TODO(team): implement discreet alert with live location sharing,
/// route deviation detection, quick-call trusted contact.
class FollowedScreen extends StatelessWidget {
  const FollowedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("I'm being followed")),
      body: const _ComingSoon(
        icon: Icons.directions_walk,
        message: 'Followed-scenario flow coming soon.',
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}