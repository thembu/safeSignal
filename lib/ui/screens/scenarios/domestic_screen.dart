// lib/ui/screens/scenarios/domestic_screen.dart
//
// Domestic / robbery flow. Two modes:
//   1. Immediate panic  — one tap creates a session already flipped to
//      `escalated`. No timer, no cancel window. Evidence capture +
//      escalation email fire via the existing top-level listener.
//   2. Anticipatory (decoy) — normal timed session with check-ins, but
//      the UI is a fake lock screen. Silent panic triggers:
//        - long-press anywhere for 2s  → escalateManual('long_press')
//        - shake                       → existing background handler
//      Escape hatch:
//        - triple-tap top-left corner  → exit decoy back to controls
//      When the session status flips (awaiting_check_in / in_grace) we
//      DO NOT push CheckInScreen — that would blow cover (loud alarm).
//      Server tick promotes to `escalated` on its own; silence is the
//      signal, per the design.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/session_service.dart';

class DomesticScreen extends StatefulWidget {
  final User user;
  const DomesticScreen({super.key, required this.user});

  @override
  State<DomesticScreen> createState() => _DomesticScreenState();
}

class _DomesticScreenState extends State<DomesticScreen> {
  late final SessionService _sessions =
  SessionService(uid: widget.user.uid);

  bool _busy = false;
  bool _hadActiveSession = false;
  bool _poppedForEnd = false;
  String? _lastHandledSessionId;

  @override
  void initState() {
    super.initState();
    _initScheduler();
  }

  Future<void> _initScheduler() async {
    await CheckInScheduler.instance.init(
      onTap: (sessionId) async {
        // In decoy mode we still let the scheduler fire, but tapping the
        // silent local notification is treated as an "I'm ok" confirm —
        // safest interpretation, since the user tapped it themselves.
        try {
          await _sessions.confirmOkay(sessionId, 10);
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

  // -------------------- immediate panic --------------------

  Future<void> _immediatePanic() async {
    if (!await _ensurePermissions()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      // Reuse SessionService.startSession then flip to escalated in one go.
      // Duration is a placeholder — session is escalated immediately so it
      // never actually ticks down.
      final id = await _sessions.startSession(
        durationMinutes: 10,
        mode: 'domestic',
      );
      await _sessions.escalateManual(id, reason: 'immediate_panic');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send alert: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------- anticipatory (decoy) --------------------

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
              child: Text('Silent check-in every…',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            for (final m in [1, 3, 5, 10, 15])
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

  Future<void> _startAnticipatory() async {
    final minutes = await _pickDuration();
    if (minutes == null) return;
    if (!await _ensurePermissions()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await _sessions.startSession(
        durationMinutes: minutes,
        mode: 'domestic',
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

  Future<void> _silentPanic(String id, String reason) async {
    try {
      await _sessions.escalateManual(id, reason: reason);
    } catch (_) {
      // Silent — no snackbar, we're in decoy mode.
    }
  }

  // -------------------- session lifecycle --------------------

  void _onSessionUpdate(Session? session) {
    if (session == null) {
      if (_lastHandledSessionId != null) {
        CheckInScheduler.instance.cancel();
        _lastHandledSessionId = null;
      }
      if (_hadActiveSession && !_poppedForEnd && mounted) {
        _poppedForEnd = true;
        Navigator.of(context).maybePop();
      }
      return;
    }

    _hadActiveSession = true;
    final isNewSession = session.id != _lastHandledSessionId;
    _lastHandledSessionId = session.id;

    if (isNewSession &&
        session.status == SessionStatus.active &&
        session.checkInDueAt != null) {
      CheckInScheduler.instance
          .schedule(sessionId: session.id, when: session.checkInDueAt!);
    }

    // Intentionally do NOT push CheckInScreen for awaitingCheckIn/inGrace.
    // Decoy stays up; server tick handles promotion to escalated.
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StreamBuilder<Session?>(
          stream: _sessions.watchActiveSession(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final session = snap.data;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _onSessionUpdate(session));

            if (session == null) {
              return _IdleView(
                busy: _busy,
                onImmediate: _immediatePanic,
                onAnticipatory: _startAnticipatory,
              );
            }

            // Active session → fake lock screen decoy.
            return _DecoyLockScreen(
              onLongPressPanic: () =>
                  _silentPanic(session.id, 'long_press'),
              onExitDecoy: () => _showRealControls(session),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showRealControls(Session session) async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1a1a1a),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Session active (decoy on)',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'Started at ${_fmt(session.startedAt)} · '
                    'check in every ${session.durationMinutes} min',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                onPressed: () {
                  Navigator.of(context).pop();
                  _silentPanic(session.id, 'panic_button');
                },
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Send alert now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _cancelSession(session.id);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text("I'm safe — end session"),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to decoy'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }
}

// -------------------- idle: pick mode --------------------

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.busy,
    required this.onImmediate,
    required this.onAnticipatory,
  });
  final bool busy;
  final VoidCallback onImmediate;
  final VoidCallback onAnticipatory;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text('Domestic / robbery',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Pick the mode that fits.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _ModeCard(
              color: Colors.red.shade700,
              icon: Icons.warning_amber_rounded,
              title: 'It’s happening now',
              subtitle:
              'One-tap silent alert. Sends location + captures evidence '
                  'immediately. No cancel window.',
              busy: busy,
              onTap: onImmediate,
            ),
            const SizedBox(height: 16),
            _ModeCard(
              color: Colors.deepPurple.shade400,
              icon: Icons.lock_outline,
              title: 'I feel unsafe (decoy)',
              subtitle:
              'Shows a fake lock screen. Silent check-ins run in the '
                  'background. Long-press anywhere for 2s to fire the alert. '
                  'Triple-tap the top-left corner to exit the decoy.',
              busy: busy,
              onTap: onAnticipatory,
            ),
            const Spacer(),
            const Text(
              'Shake the phone hard at any time to trigger the alert.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade900,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                foregroundColor: color,
                radius: 28,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
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

// -------------------- decoy lock screen --------------------

class _DecoyLockScreen extends StatefulWidget {
  const _DecoyLockScreen({
    required this.onLongPressPanic,
    required this.onExitDecoy,
  });
  final VoidCallback onLongPressPanic;
  final VoidCallback onExitDecoy;

  @override
  State<_DecoyLockScreen> createState() => _DecoyLockScreenState();
}

class _DecoyLockScreenState extends State<_DecoyLockScreen> {
  Timer? _clockTicker;
  DateTime _now = DateTime.now();

  // triple-tap escape hatch tracking
  int _tapCount = 0;
  DateTime? _firstTapAt;

  @override
  void initState() {
    super.initState();
    _clockTicker = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    super.dispose();
  }

  void _onCornerTap() {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(milliseconds: 900)) {
      _firstTapAt = now;
      _tapCount = 1;
      return;
    }
    _tapCount += 1;
    if (_tapCount >= 3) {
      _tapCount = 0;
      _firstTapAt = null;
      widget.onExitDecoy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final weekday = _weekdayName(_now.weekday);
    final month = _monthName(_now.month);
    final dateStr = '$weekday, $month ${_now.day}';

    return PopScope(
      canPop: false, // trap system back — decoy stays up
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Long-press anywhere = silent panic.
        onLongPress: widget.onLongPressPanic,
        // Swipe up from bottom half = unlock into real controls.
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -600) widget.onExitDecoy();
        },
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                // Escape-hatch corner. Small, unlabelled, top-left.
                Positioned(
                  top: 0,
                  left: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onCornerTap,
                    child: const SizedBox(width: 56, height: 56),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    Text(
                      '$h:$m',
                      style: const TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateStr,
                      style: const TextStyle(
                          fontSize: 18, color: Colors.white70),
                    ),
                    const SizedBox(height: 40),
                    // Fake missed-notification line for realism.
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.phone_missed,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '3 missed calls',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          Text('12m ago',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Text(
                        'Swipe up to unlock',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _weekdayName(int w) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return names[(w - 1) % 7];
  }

  static String _monthName(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return names[(m - 1) % 12];
  }
}