// lib/ui/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_service.dart';
import '../../services/share_intake_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import 'contacts_screen.dart';
import 'scenarios/date_screen.dart';
import 'scenarios/domestic_screen.dart';
import 'scenarios/ehailing_screen.dart';
import 'scenarios/followed_screen.dart';

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

    if (ShareIntakeService.instance.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEhailing());
    }

    _shareSub =
        ShareIntakeService.instance.links.listen((_) => _openEhailing());
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
        color: AppColors.primary,
        onTap: _openEhailing,
      ),
      _Scenario(
        title: "I'm being followed",
        subtitle: 'Walking, driving, or transit',
        icon: Icons.directions_walk,
        color: AppColors.warning,
        onTap: () => _openScenario(FollowedScreen(user: widget.user)),
      ),
      _Scenario(
        title: 'Meeting a stranger',
        subtitle: 'First date or first meet-up',
        icon: Icons.people_outline,
        color: AppColors.safe,
        onTap: () => _openScenario(DateScreen(user: widget.user)),
      ),
      _Scenario(
        title: 'Domestic / robbery',
        subtitle: 'Threat at home or in-progress',
        icon: Icons.home_outlined,
        color: AppColors.danger,
        onTap: () => _openScenario(DomesticScreen(user: widget.user)),
      ),
    ];

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ScreenScaffold(
      title: 'SafeSignal',
      actions: [
        IconButton(
          icon: const Icon(Icons.contacts_outlined),
          tooltip: 'Trusted contacts',
          onPressed: _openContacts,
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
          onPressed: () => widget.authService.signOut(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Hi ${_firstName(widget.user)} 👋',
            style: text.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'What do you need help with?',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.9,
              children: [
                for (final s in scenarios) _ScenarioCard(scenario: s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _firstName(User u) {
    final name = (u.displayName ?? '').trim();
    if (name.isEmpty) return 'there';
    return name.split(' ').first;
  }
}

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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: scenario.onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scenario.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
            ),
            child: Icon(scenario.icon, size: 28, color: scenario.color),
          ),
          const SizedBox(height: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scenario.title,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                scenario.subtitle,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}