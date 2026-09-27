// lib/ui/screens/check_in_screen.dart
//
// Full-screen "are you okay?" prompt. Now driven by whatever status
// arrives from Firestore — the server tick promotes stale sessions
// regardless of what the app is doing, so we mostly react to snapshots
// instead of driving transitions locally.
//
// The one thing this screen owns: the loud alarm. It starts when the
// session enters `inGrace` and stops on any exit (confirm okay,
// escalate, dispose).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session.dart';
import '../../../services/alarm_service.dart';
import '../../services/session_service.dart';

class CheckInScreen extends StatefulWidget {
  final SessionService sessionService;
  final Session session;

  const CheckInScreen({
    super.key,
    required this.sessionService,
    required this.session,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _busy = false;
  SessionStatus? _lastAlarmStatus;

  @override
  void initState() {
    super.initState();
    _syncAlarm(widget.session.status);
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant CheckInScreen old) {
    super.didUpdateWidget(old);
    if (old.session.status != widget.session.status) {
      _syncAlarm(widget.session.status);
    }
    if (old.session.status != widget.session.status ||
        old.session.checkInWindowEndsAt != widget.session.checkInWindowEndsAt ||
        old.session.graceEndsAt != widget.session.graceEndsAt) {
      _startTicker();
    }
  }

  /// Turns the alarm on/off based on the current status. Idempotent —
  /// safe to call on every snapshot.
  void _syncAlarm(SessionStatus status) {
    if (status == _lastAlarmStatus) return;
    _lastAlarmStatus = status;

    if (status == SessionStatus.inGrace) {
      AlarmService.instance.start();
    } else {
      // Any other status (active, awaitingCheckIn, checkedIn, escalated,
      // cancelled) means the alarm should not be going.
      AlarmService.instance.stop();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final deadline = _deadline();
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    setState(() => _remaining = left.isNegative ? Duration.zero : left);

    if (left.isNegative || left.inSeconds == 0) {
      _onDeadlineReached();
    }
  }

  DateTime? _deadline() {
    switch (widget.session.status) {
      case SessionStatus.awaitingCheckIn:
        return widget.session.checkInWindowEndsAt;
      case SessionStatus.inGrace:
        return widget.session.graceEndsAt;
      default:
        return null;
    }
  }

  /// Foreground fast-path: if we happen to be open when a deadline
  /// passes, promote right away instead of waiting for the server tick.
  /// The tick would do the same transition within ~60s anyway.
  Future<void> _onDeadlineReached() async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.session.status == SessionStatus.awaitingCheckIn) {
        HapticFeedback.vibrate();
        await widget.sessionService.enterGrace(widget.session.id);
      } else if (widget.session.status == SessionStatus.inGrace) {
        await widget.sessionService.escalate(widget.session.id);
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _confirmOkay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AlarmService.instance.stop();
      await widget.sessionService
          .confirmOkay(widget.session.id, widget.session.durationMinutes);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Never leave the alarm running after the screen is gone.
    AlarmService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inGrace = widget.session.status == SessionStatus.inGrace;
    final bg = inGrace ? Colors.red.shade900 : Colors.blueGrey.shade900;
    final title = inGrace ? 'Alerting contacts…' : 'Are you okay?';
    final subtitle = inGrace
        ? 'Tap "False alarm" to cancel before alerts are sent.'
        : 'Tap "I\'m okay" to confirm. Otherwise contacts will be notified.';
    final buttonLabel = inGrace ? 'False alarm' : "I'm okay";

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 32),
              Text(
                '${_remaining.inSeconds}s',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _busy ? null : _confirmOkay,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: Colors.white,
                  foregroundColor: bg,
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}