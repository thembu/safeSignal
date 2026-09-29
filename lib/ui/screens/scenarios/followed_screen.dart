// lib/ui/screens/scenarios/followed_screen.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../check_in_screen.dart';

class FollowedScreen extends StatefulWidget {
  final User user;

  const FollowedScreen({super.key, required this.user});

  @override
  State<FollowedScreen> createState() => _FollowedScreenState();
}

class _FollowedScreenState extends State<FollowedScreen> {
  late final SessionService _sessions =
  SessionService(uid: widget.user.uid);

  bool _busy = false;
  bool _prompting = false;
  Session? _lastSeen;

  @override
  void initState() {
    super.initState();
    _initScheduler();
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
    final needed = <Permission>[
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
                'evidence if you trigger an alert.',
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
            for (final m in [1, 3, 5, 10])
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
        mode: 'followed',
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

  Future<void> _panic(String id) async {
    setState(() => _busy = true);
    try {
      await _sessions.escalateManual(id, reason: 'panic_button');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send alert: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: "I'm being followed",
      child: StreamBuilder<Session?>(
        stream: _sessions.watchActiveSession(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _onSessionUpdate(session));

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: session == null
                ? _IdleView(busy: _busy, onStart: _startSession)
                : _ActiveView(
              session: session,
              busy: _busy,
              onCancel: () => _cancelSession(session.id),
              onPanic: () => _panic(session.id),
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
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.warningContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.directions_walk,
            size: 56,
            color: AppColors.warning,
          ),
        ).centered(),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Stay alert.\nCheck in silently.',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'We\'ll ping you at intervals. Miss a check-in and your '
              'contacts get alerted.',
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
      ],
    );
  }
}

class _ActiveView extends StatelessWidget {
  const _ActiveView({
    required this.session,
    required this.busy,
    required this.onCancel,
    required this.onPanic,
  });

  final Session session;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onPanic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        DangerButton(
          label: 'Send alert now',
          icon: Icons.warning_amber_rounded,
          onPressed: onPanic,
          busy: busy,
        ),
        const SizedBox(height: AppSpacing.sm),
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

extension _CenterEx on Widget {
  Widget centered() => Center(child: this);
}