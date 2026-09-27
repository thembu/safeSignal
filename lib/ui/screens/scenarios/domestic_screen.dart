import 'package:flutter/material.dart';

/// Placeholder — "Domestic situation / robbery" flow.
/// TODO(team): implement silent panic trigger, background audio capture,
/// immediate escalation without check-in cycle.
class DomesticScreen extends StatelessWidget {
  const DomesticScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Domestic / robbery')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Domestic-situation flow coming soon.',
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