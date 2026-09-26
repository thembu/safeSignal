import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/check_in_scheduler.dart';
import '../../services/contacts_service.dart';
import '../../services/session_service.dart';
import 'check_in_screen.dart';
import 'contacts_screen.dart';

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
  late final SessionService _sessions;
  StreamSubscription<Session?>? _sub;
  Session? _lastSeen;
  bool _prompting = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sessions = SessionService(uid: widget.user.uid);
    _initScheduler();
    _sub = _sessions.watchActiveSession().listen(_onSessionUpdate);
  }

  Future<void> _initScheduler() async {
    await CheckInScheduler.instance.init(
      onTap: (sessionId) async {
        // Notification tapped -> mark as awaiting so UI opens the prompt.
        try {
          await _sessions.promptCheckIn(sessionId);
        } catch (_) {/* session may have ended */}
      },
    );
  }

  void _onSessionUpdate(Session? session) {
    _lastSeen = session;
    if (session == null) {
      CheckInScheduler.instance.cancel();
      return;
    }

    // Schedule (or reschedule) the OS notification whenever the due time changes.
    if (session.status == SessionStatus.active &&
        session.checkInDueAt != null) {
      CheckInScheduler.instance
          .schedule(sessionId: session.id, when: session.checkInDueAt!);
    }

    // Foreground: if timer already passed and we're still "active", promote it.
    if (session.status == SessionStatus.active &&
        session.checkInDueAt != null &&
        DateTime.now().isAfter(session.checkInDueAt!)) {
      _sessions.promptCheckIn(session.id);
      return;
    }

    // If awaiting or in grace, open the full-screen prompt.
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Check in every…',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final m in [10, 20, 30, 45])
              ListTile(
                title: Text('$m minutes'),
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
    setState(() => _busy = true);
    try {
      await _sessions.startSession(durationMinutes: minutes);
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

  void _openContacts() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ContactsScreen(contactsService: widget.contactsService , uid: widget.user.uid,),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: StreamBuilder<Session?>(
        stream: _sessions.watchActiveSession(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snap.data;
          return Padding(
            padding: const EdgeInsets.all(24),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No active session', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            height: 60,
            child: FilledButton.icon(
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
  });
  final Session session;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Session active',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Started at ${_fmt(session.startedAt)}'),
                Text('Check in every ${session.durationMinutes} min'),
                if (session.checkInDueAt != null)
                  Text('Next check-in: ${_fmt(session.checkInDueAt!)}'),
                if (session.tripLink != null) ...[
                  const SizedBox(height: 4),
                  Text('Trip: ${session.tripLink}'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
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