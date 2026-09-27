import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/auth_service.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/contacts_service.dart';
import '../../../services/session_service.dart';
import '../../../services/share_intake_service.dart';
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

// Drain any link parked before we were listening (e.g. cold-start pre-auth).
    final pending = ShareIntakeService.instance.consumePending();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedLink(pending));
    }

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


  Future<void> _onSharedLink(String link) async {
    if (!mounted) return;

    // Soft check: warn if the URL doesn't look like an e-hailing trip link,
    // but let the user continue anyway (useful for testing).
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

    // If a session is already active, ask what to do.
    if (_lastSeen != null) {
      final choice = await showModalBottomSheet<_SharedLinkChoice>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip link received',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(link, maxLines: 2, overflow: TextOverflow.ellipsis),
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

    setState(() => _busy = true);
    try {
      await _sessions.startSession(
        durationMinutes: minutes,
        tripLink: link,
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
    // Uber: uber.com, u.uber.com, trip.uber.com. Bolt: bolt.eu, m.bolt.eu.
    return lower.contains('uber.com') || lower.contains('bolt.eu');
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



  @override
  void dispose() {
    _sub?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-hailing safety'),
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

enum _SharedLinkChoice { restart, ignore }