import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session.dart';
import '../../services/session_service.dart';

/// Full-screen "are you okay?" prompt shown when a check-in fires.
/// Drives the awaitingCheckIn -> inGrace -> escalated state machine.
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

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant CheckInScreen old) {
    super.didUpdateWidget(old);
    if (old.session.status != widget.session.status ||
        old.session.checkInWindowEndsAt != widget.session.checkInWindowEndsAt ||
        old.session.graceEndsAt != widget.session.graceEndsAt) {
      _startTicker();
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

  Future<void> _onDeadlineReached() async {
    if (_busy) return;
    _busy = true;
    try {
      if (widget.session.status == SessionStatus.awaitingCheckIn) {
        // 60s check-in expired -> vibrate, enter grace
        HapticFeedback.vibrate();
        await widget.sessionService.enterGrace(widget.session.id);
      } else if (widget.session.status == SessionStatus.inGrace) {
        // Grace expired -> escalate (Cloud Function fires alerts)
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
    final buttonLabel = inGrace ? 'False alarm — cancel' : "I'm okay";
    final seconds = _remaining.inSeconds;

    return WillPopScope(
      onWillPop: () async => false, // no accidental back-out
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16)),
                  ],
                ),
                Center(
                  child: Text(
                    '${seconds}s',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 96,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 72,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: bg,
                    ),
                    onPressed: _busy ? null : _confirmOkay,
                    child: Text(buttonLabel,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}