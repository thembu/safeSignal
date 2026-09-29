// lib/ui/screens/scenarios/date_screen.dart
//
// Replaces stranger_meeting_screen.dart. "Meeting a stranger" / date mode.
// Phase 1: pre-session setup form (person photo, name, how met, venue,
//          expected end, optional car photo + plate).
// Phase 2: active session UI (dark, panic + cancel, mirrors FollowedScreen).
// When the session ends (cancelled or escalated) the screen pops back to
// HomeScreen instead of falling back to the setup form.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../models/date_context.dart';
import '../../../models/session.dart';
import '../../../models/user.dart';
import '../../../services/check_in_scheduler.dart';
import '../../../services/date_context_service.dart';
import '../../../services/session_service.dart';
import '../check_in_screen.dart';

class DateScreen extends StatefulWidget {
  final User user;
  const DateScreen({super.key, required this.user});

  @override
  State<DateScreen> createState() => _DateScreenState();
}

class _DateScreenState extends State<DateScreen> {
  late final SessionService _sessions =
  SessionService(uid: widget.user.uid);
  late final DateContextService _dateCtx =
  DateContextService(uid: widget.user.uid);
  final _picker = ImagePicker();

  // --- form state ---
  final _nameCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  final _venueAddressCtrl = TextEditingController();
  final _howMetOtherCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  static const _howMetOptions = [
    'Tinder',
    'Hinge',
    'Bumble',
    'Grindr',
    'Instagram',
    'In person',
    'Other',
  ];
  String _howMet = 'Tinder';
  DateTime _expectedEnd = DateTime.now().add(const Duration(hours: 2));
  File? _personPhoto;
  File? _carPhoto;

  // --- session state ---
  bool _busy = false;
  bool _prompting = false;
  String? _lastHandledSessionId;
  bool _hadActiveSession = false;
  bool _poppedForEnd = false;

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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _venueNameCtrl.dispose();
    _venueAddressCtrl.dispose();
    _howMetOtherCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
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

  Future<ImageSource?> _chooseImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Add photo',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.white),
              title: const Text('Take photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
              const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choose from gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(bool isPerson) async {
    final src = await _chooseImageSource();
    if (src == null) return;
    try {
      final x = await _picker.pickImage(source: src, imageQuality: 80);
      if (x == null) return;
      final persisted = await _dateCtx.persistLocalCopy(
          File(x.path), isPerson ? 'person' : 'car');
      setState(() {
        if (isPerson) {
          _personPhoto = persisted;
        } else {
          _carPhoto = persisted;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load photo: $e')));
    }
  }

  Future<void> _pickEndTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expectedEnd),
    );
    if (t == null) return;
    final now = DateTime.now();
    var end = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (end.isBefore(now)) end = end.add(const Duration(days: 1));
    setState(() => _expectedEnd = end);
  }

  Future<void> _startSession() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _venueNameCtrl.text.trim().isEmpty ||
        _venueAddressCtrl.text.trim().isEmpty ||
        _personPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name, venue and a photo of them are required.'),
        ),
      );
      return;
    }

    final minutes = _expectedEnd.difference(DateTime.now()).inMinutes;
    if (minutes < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expected end must be at least 10 minutes from now.'),
        ),
      );
      return;
    }

    if (!await _ensurePermissions()) return;
    if (!mounted) return;

    setState(() => _busy = true);
    String? sessionId;
    try {
      final tempSessionId =
          'pending_${DateTime.now().millisecondsSinceEpoch}';
      final personUrl = await _dateCtx.uploadImage(
        sessionId: tempSessionId,
        file: _personPhoto!,
        kind: 'person',
      );
      String? carUrl;
      if (_carPhoto != null) {
        carUrl = await _dateCtx.uploadImage(
          sessionId: tempSessionId,
          file: _carPhoto!,
          kind: 'car',
        );
      }

      sessionId = await _sessions.startSession(
        durationMinutes: minutes,
        mode: 'date',
      );

      final ctx = DateContext(
        personName: _nameCtrl.text.trim(),
        howMet: _howMet,
        howMetOther:
        _howMet == 'Other' ? _howMetOtherCtrl.text.trim() : null,
        venueName: _venueNameCtrl.text.trim(),
        venueAddress: _venueAddressCtrl.text.trim(),
        expectedEndAt: _expectedEnd,
        personPhotoUrl: personUrl,
        carPhotoUrl: carUrl,
        carPlate: _plateCtrl.text.trim().isEmpty
            ? null
            : _plateCtrl.text.trim().toUpperCase(),
        createdAt: DateTime.now(),
      );
      await _dateCtx.writeContext(sessionId: sessionId, context: ctx);
    } catch (e, st) {
      if (!mounted) return;
      // ignore: avoid_print
      print('[DateScreen] startSession failed: $e\n$st');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not start: $e')));
      if (sessionId != null) {
        try {
          await _sessions.cancelSession(sessionId);
        } catch (_) {}
      }
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

  /// Guard against re-scheduling the same session on every rebuild.
  /// When a session that was previously active ends (session becomes null),
  /// pop this screen instead of falling back to the setup form.
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
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade900,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          labelStyle: TextStyle(color: Colors.grey.shade400),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E1116),
          elevation: 0,
          title: const Text('Meeting a stranger'),
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

            if (session == null) {
              // A session was active and just ended — we're mid-pop, don't
              // flash the setup form.
              if (_hadActiveSession) {
                return const Center(child: CircularProgressIndicator());
              }
              return _SetupForm(
                busy: _busy,
                nameCtrl: _nameCtrl,
                venueNameCtrl: _venueNameCtrl,
                venueAddressCtrl: _venueAddressCtrl,
                howMetOtherCtrl: _howMetOtherCtrl,
                plateCtrl: _plateCtrl,
                howMet: _howMet,
                howMetOptions: _howMetOptions,
                onHowMet: (v) => setState(() => _howMet = v),
                expectedEnd: _expectedEnd,
                onPickEndTime: _pickEndTime,
                personPhoto: _personPhoto,
                carPhoto: _carPhoto,
                onPickPerson: () => _pickPhoto(true),
                onPickCar: () => _pickPhoto(false),
                onStart: _startSession,
              );
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: _ActiveView(
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

class _SetupForm extends StatelessWidget {
  const _SetupForm({
    required this.busy,
    required this.nameCtrl,
    required this.venueNameCtrl,
    required this.venueAddressCtrl,
    required this.howMetOtherCtrl,
    required this.plateCtrl,
    required this.howMet,
    required this.howMetOptions,
    required this.onHowMet,
    required this.expectedEnd,
    required this.onPickEndTime,
    required this.personPhoto,
    required this.carPhoto,
    required this.onPickPerson,
    required this.onPickCar,
    required this.onStart,
  });

  final bool busy;
  final TextEditingController nameCtrl;
  final TextEditingController venueNameCtrl;
  final TextEditingController venueAddressCtrl;
  final TextEditingController howMetOtherCtrl;
  final TextEditingController plateCtrl;
  final String howMet;
  final List<String> howMetOptions;
  final ValueChanged<String> onHowMet;
  final DateTime expectedEnd;
  final VoidCallback onPickEndTime;
  final File? personPhoto;
  final File? carPhoto;
  final VoidCallback onPickPerson;
  final VoidCallback onPickCar;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.teal.withOpacity(0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.tealAccent),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Fill this in before you meet them. If '
                                'anything happens it gets sent to your '
                                'trusted contacts.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Who you\'re meeting'),
                  const SizedBox(height: 8),
                  _PhotoCard(
                    label: 'Photo of them',
                    required: true,
                    file: personPhoto,
                    onTap: onPickPerson,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration:
                    const InputDecoration(labelText: 'Their name *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: howMet,
                    dropdownColor: Colors.grey.shade900,
                    decoration:
                    const InputDecoration(labelText: 'How you met'),
                    items: howMetOptions
                        .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: const TextStyle(
                                color: Colors.white))))
                        .toList(),
                    onChanged: (v) => onHowMet(v ?? 'Tinder'),
                  ),
                  if (howMet == 'Other') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: howMetOtherCtrl,
                      decoration:
                      const InputDecoration(labelText: 'Specify'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _SectionLabel('Where and when'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: venueNameCtrl,
                    decoration:
                    const InputDecoration(labelText: 'Venue name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: venueAddressCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Venue address *'),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: onPickEndTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule,
                                color: Colors.tealAccent),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Expected end time',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            Text(
                              TimeOfDay.fromDateTime(expectedEnd)
                                  .format(context),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('If they picked you up (optional)'),
                  const SizedBox(height: 8),
                  _PhotoCard(
                    label: 'Car photo',
                    required: false,
                    file: carPhoto,
                    onTap: onPickCar,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: plateCtrl,
                    decoration: const InputDecoration(
                        labelText: 'License plate'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1116),
              border: Border(
                top: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal.shade700),
                onPressed: busy ? null : onStart,
                icon: busy
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.shield),
                label: Text(busy ? 'Starting…' : 'Start date session',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: Colors.tealAccent.shade100,
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.label,
    required this.required,
    required this.file,
    required this.onTap,
  });
  final String label;
  final bool required;
  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: file == null && required
                ? Colors.redAccent.withOpacity(0.4)
                : Colors.grey.shade800,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: file == null
                  ? Container(
                width: 76,
                height: 76,
                color: Colors.grey.shade800,
                child: const Icon(Icons.add_a_photo,
                    color: Colors.white54, size: 30),
              )
                  : Image.file(file!,
                  width: 76, height: 76, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    required ? '$label *' : label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file == null ? 'Tap to add' : 'Tap to replace',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.tealAccent.withOpacity(0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.tealAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Date session active',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(
                  icon: Icons.play_arrow,
                  label: 'Started',
                  value: _fmt(session.startedAt)),
              _InfoRow(
                  icon: Icons.timer,
                  label: 'Check in every',
                  value: '${session.durationMinutes} min'),
              if (session.checkInDueAt != null)
                _InfoRow(
                    icon: Icons.schedule,
                    label: 'Next check-in',
                    value: _fmt(session.checkInDueAt!)),
              const SizedBox(height: 12),
              const Text(
                '🤳 Shake phone hard to send emergency alert',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            onPressed: busy ? null : onPanic,
            icon: const Icon(Icons.warning_amber_rounded, size: 26),
            label: const Text('Send alert now',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onCancel,
          icon: const Icon(Icons.check),
          label: const Text("I'm safe — end session"),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

String _fmt(DateTime dt) {
  final l = dt.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}