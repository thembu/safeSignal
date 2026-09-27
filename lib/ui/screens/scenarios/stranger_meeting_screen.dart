import 'package:flutter/material.dart';

/// Placeholder — "Meeting/date with a stranger" flow.
/// TODO(team): implement scheduled check-ins throughout the meeting,
/// share meeting location with trusted contact, safe-word trigger.
class StrangerMeetingScreen extends StatelessWidget {
  const StrangerMeetingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting a stranger')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Stranger-meeting flow coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}