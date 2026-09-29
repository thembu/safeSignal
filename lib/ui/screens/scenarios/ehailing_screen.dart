// lib/ui/screens/scenarios/ehailing_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/auth_service.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/contacts_service.dart';
import '../../../services/session_service.dart';
import '../../../services/share_intake_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../check_in_screen.dart';

class EhailingScreen extends StatefulWidget {
  final AuthService authService;
  final ContactsService contactsService;
  final User user;

  const EhailingScreen({
    super.key,
    required this.authService,
    required this.contactsService,
    required this.user,
  });

  @override
  State<EhailingScreen> createState() => _EhailingScreenState();
}

class _EhailingScreenState extends State<EhailingScreen> {
  late final SessionService _sessions;
  StreamSubscription<Session?>? _sub;
  StreamSubscription<String>? _shareSub;
  Session? _lastSeen;
  bool _prompting = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sessions = SessionService(uid: widget.user.uid);
    _initScheduler();
    _sub = _sessions.watchActiveSession().listen(_onSessionUpdate);
    _shareSub = ShareIntakeService.instance.links.listen(_onSharedLink);

    final pending = ShareIntakeService.instance.consumePending();
    if (pending != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onSharedLink(pending));
    }
  }

  Future<void> _initScheduler() async {
    await CheckInScheduler.instance.init(
      onTap: (sessionId) async {
        try {
          await _sessions.promptCheckIn(sessionId);
        } catch (_) {}
      },
    );
  }

  Future<bool> _ensurePermissions() async {
    final needed = [
      Permission.camera,
      Permission.microphone,
      Permission.location,
    ];

    final missing = <Permission>[];
    for (final p in needed) {
      if (!(await p.status).isGranted) missing.add(p);
    }
    if (missing.isEmpty) return true;

    if (mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permissions needed'),
          content: const Text(
            'SafeSignal needs camera, microphone and location to capture '
                'evidence if you are in danger. This only runs if you trigger '
                'an alert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Grant'),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
    }

    final results = await missing.request();
    return results.values.every((s) => s.isGranted);
  }

  Future<void> _onSharedLink(String link) async {
    if (!mounted) return;

    if (!_looksLikeTripLink(link)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Not a trip link?'),
          content: Text(
            'This doesn\'t look like an Uber or Bolt trip link:\n\n$link\n\n'
                'Start a session with it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    if (_lastSeen != null) {
      final choice = await showModalBottomSheet<_SharedLinkChoice>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip link received',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      link,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.autorenew),
                title: const Text('Cancel current session and start new'),
                onTap: () =>
                    Navigator.of(context).pop(_SharedLinkChoice.restart),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Ignore'),
                onTap: () =>
                    Navigator.of(context).pop(_SharedLinkChoice.ignore),
              ),
            ],
          ),
        ),
      );
      if (choice != _SharedLinkChoice.restart) return;
      if (!mounted) return;
    }

    final minutes = await _pickDuration();
    if (minutes == null) return;
    if (!mounted) return;

    if (!await _ensurePermissions()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await _sessions.startSession(
        durationMinutes: minutes,
        tripLink: link,
        mode: 'ehailing',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool _looksLikeTripLink(String url) {
    final lower = url.toLowerCase();
    return lower.contains('uber.com') || lower.contains('bolt.eu');
  }

  void _onSessionUpdate(Session? session) {
    _lastSeen = session;
    if (session == null) {
      CheckInScheduler.instance.cancel();
      return;
    }

    if (session.status == SessionStatus.active &&
        session.checkInDueAt != null) {
      CheckInScheduler.instance
          .schedule(sessionId: session.id, when: session.checkInDueAt!);
    }

    if (session.status == SessionStatus.active &&
        session.checkInDueAt != null &&
        DateTime.now().isAfter(session.checkInDueAt!)) {
      _sessions.promptCheckIn(session.id);
      return;
    }

    if ((session.status == SessionStatus.awaitingCheckIn ||
        session.status == SessionStatus.inGrace) &&
        !_prompting) {
      _openCheckIn(session);
    }
  }

  Future<void> _openCheckIn(Session session) async {
    _prompting = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StreamBuilder<Session>(
          stream: _sessions.watchSession(session.id),
          initialData: session,
          builder: (_, snap) => CheckInScreen(
            sessionService: _sessions,
            session: snap.data!,
          ),
        ),
      ),
    );
    _prompting = false;
  }

  Future<int?> _pickDuration() async {
    return showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Text(
                'Check in every…',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final m in [1, 20, 30, 45])
              ListTile(
                title: Text('$m minutes'),
                onTap: () => Navigator.of(context).pop(m),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _startSession() async {
    final minutes = await _pickDuration();
    if (minutes == null) return;
    if (!await _ensurePermissions()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await _sessions.startSession(
        durationMinutes: minutes,
        mode: 'ehailing',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSession(String id) async {
    setState(() => _busy = true);
    try {
      await _sessions.cancelSession(id);
      await CheckInScheduler.instance.cancel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'E-hailing safety',
      child: StreamBuilder<Session?>(
        stream: _sessions.watchActiveSession(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: session == null
                ? _IdleView(busy: _busy, onStart: _startSession)
                : _ActiveView(
              session: session,
              busy: _busy,
              onCancel: () => _cancelSession(session.id),
            ),
          );
        },
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.busy, required this.onStart});
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_taxi,
              size: 56,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Share your ride safely',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Share a trip link from Uber or Bolt to SafeSignal, or start a '
              'session without one. We\'ll ping you at intervals — miss a '
              'check-in and your contacts get alerted.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          label: 'Start session',
          icon: Icons.shield,
          onPressed: onStart,
          busy: busy,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Tip: use your ride app\'s share button and pick SafeSignal',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ActiveView extends StatelessWidget {
  const _ActiveView({
    required this.session,
    required this.busy,
    required this.onCancel,
  });
  final Session session;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          borderColor: AppColors.primary.withOpacity(0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(status: session.status),
              const SizedBox(height: AppSpacing.md),
              InfoRow(
                icon: Icons.play_arrow,
                label: 'Started',
                value: _fmt(session.startedAt),
              ),
              InfoRow(
                icon: Icons.timer_outlined,
                label: 'Check in every',
                value: '${session.durationMinutes} min',
              ),
              if (session.checkInDueAt != null)
                InfoRow(
                  icon: Icons.schedule,
                  label: 'Next check-in',
                  value: _fmt(session.checkInDueAt!),
                ),
            ],
          ),
        ),
        if (session.tripLink != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Trip link',
                      style: text.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  session.tripLink!,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppCard(
          background: AppColors.warningContainer.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              const Icon(Icons.vibration,
                  size: 20, color: AppColors.onWarningContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Shake phone hard to send emergency alert',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.onWarningContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SecondaryButton(
          label: 'Cancel session',
          icon: Icons.cancel_outlined,
          onPressed: onCancel,
          busy: busy,
        ),
      ],
    );
  }

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }
}

enum _SharedLinkChoice { restart, ignore }