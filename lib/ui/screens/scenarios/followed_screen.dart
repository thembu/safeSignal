import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/session_service.dart';
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
      backgroundColor: Colors.grey.shade900,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Check in every…',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            for (final m in [1, 3, 5, 10])
              ListTile(
                title: Text('$m minutes',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(m),
              ),
            const SizedBox(height: 8),
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
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text("I'm being followed"),
        ),
        body: StreamBuilder<Session?>(
          stream: _sessions.watchActiveSession(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final session = snap.data;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _onSessionUpdate(session));

            return Padding(
              padding: const EdgeInsets.all(24),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_walk,
              size: 64, color: Colors.orangeAccent),
          const SizedBox(height: 16),
          const Text(
            'Stay alert.\nCheck in silently.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 220,
            height: 60,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.shield),
              label: const Text('Start session',
                  style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.grey.shade900,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Session active',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 8),
                Text('Started at ${_fmt(session.startedAt)}',
                    style: const TextStyle(color: Colors.white70)),
                Text('Check in every ${session.durationMinutes} min',
                    style: const TextStyle(color: Colors.white70)),
                if (session.checkInDueAt != null)
                  Text('Next check-in: ${_fmt(session.checkInDueAt!)}',
                      style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                const Text(
                  '🤳 Shake phone hard to send emergency alert',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: busy ? null : onPanic,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Send alert now',
                style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onCancel,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancel session'),
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