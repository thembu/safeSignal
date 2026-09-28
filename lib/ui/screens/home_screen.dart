import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../services/share_intake_service.dart';
import 'contacts_screen.dart';
import 'scenarios/ehailing_screen.dart';
import 'scenarios/domestic_screen.dart';
import 'scenarios/followed_screen.dart';
import 'scenarios/stranger_meeting_screen.dart';

class HomeScreen extends StatefulWidget {
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<String>? _shareSub;
  bool _openingEhailing = false;

  @override
  void initState() {
    super.initState();

    // Cold-start / pre-auth: a link was parked before we mounted.
    if (ShareIntakeService.instance.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEhailing());
    }

    // Runtime: a link comes in while we're sitting on the home screen.
    _shareSub = ShareIntakeService.instance.links.listen((_) => _openEhailing());
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _openEhailing() async {
    if (!mounted || _openingEhailing) return;
    _openingEhailing = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EhailingScreen(
          authService: widget.authService,
          contactsService: widget.contactsService,
          user: widget.user,
        ),
      ),
    );
    if (mounted) _openingEhailing = false;
  }

  void _openContacts() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactsScreen(
          contactsService: widget.contactsService,
          uid: widget.user.uid,
        ),
      ),
    );
  }

  void _openScenario(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final scenarios = <_Scenario>[
      _Scenario(
        title: 'E-hailing trip',
        subtitle: 'Uber, Bolt or similar',
        icon: Icons.local_taxi,
        color: Colors.deepPurple,
        onTap: _openEhailing,
      ),
      _Scenario(
        title: "I'm being followed",
        subtitle: 'Walking, driving, or on transit',
        icon: Icons.directions_walk,
        color: Colors.orange,
        onTap: () => _openScenario(FollowedScreen(user: widget.user)),
      ),
      _Scenario(
        title: 'Meeting a stranger',
        subtitle: 'First date or first meet-up',
        icon: Icons.people_outline,
        color: Colors.teal,
        onTap: () => _openScenario(const StrangerMeetingScreen()),
      ),
      _Scenario(
        title: 'Domestic / robbery',
        subtitle: 'Threat at home or in-progress incident',
        icon: Icons.home_outlined,
        color: Colors.red,
        onTap: () => _openScenario(const DomesticScreen()),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeSignal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'Trusted contacts',
            onPressed: _openContacts,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => widget.authService.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text(
                  'What do you need help with?',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                  children: [
                    for (final s in scenarios) _ScenarioCard(scenario: s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ... keep _Scenario and _ScenarioCard classes unchanged

class _Scenario {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _Scenario({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.scenario});
  final _Scenario scenario;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: scenario.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                backgroundColor: scenario.color.withOpacity(0.15),
                foregroundColor: scenario.color,
                radius: 24,
                child: Icon(scenario.icon, size: 28),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scenario.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scenario.subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}