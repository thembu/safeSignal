// lib/ui/screens/scenarios/date_screen.dart
//
// "Meeting a stranger" / date mode.
// Phase 1: setup form (person photo, name, how met, venue, expected end,
//          optional car photo + plate).
// Phase 2: active session UI (mirrors FollowedScreen).
// When the session ends the screen pops back to HomeScreen.

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
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
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

  final _nameCtrl = TextEditingController();
  final _venueNameCtrl = TextEditingController();
  final _venueAddressCtrl = TextEditingController();
  final _howMetOtherCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  static const _howMetOptions = [
    'Tinder', 'Hinge', 'Bumble', 'Grindr', 'Instagram', 'In person', 'Other',
  ];
  String _howMet = 'Tinder';
  DateTime _expectedEnd = DateTime.now().add(const Duration(hours: 2));
  File? _personPhoto;
  File? _carPhoto;

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
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Text(
                'Add photo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.sm),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting a stranger')),
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

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _ActiveView(
                session: session,
                busy: _busy,
                onCancel: () => _cancelSession(session.id),
                onPanic: () => _panic(session.id),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// SETUP FORM
// ============================================================================

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
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    background: AppColors.primaryContainer,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.primary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Fill this in before you meet them. If anything '
                                'happens it gets sent to your trusted contacts.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                color: AppColors.onPrimaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader("Who you're meeting"),
                  _PhotoCard(
                    label: 'Photo of them',
                    required: true,
                    file: personPhoto,
                    onTap: onPickPerson,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: nameCtrl,
                    decoration:
                    const InputDecoration(labelText: 'Their name *'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    value: howMet,
                    decoration:
                    const InputDecoration(labelText: 'How you met'),
                    items: howMetOptions
                        .map((o) =>
                        DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) => onHowMet(v ?? 'Tinder'),
                  ),
                  if (howMet == 'Other') ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: howMetOtherCtrl,
                      decoration:
                      const InputDecoration(labelText: 'Specify'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader('Where and when'),
                  TextField(
                    controller: venueNameCtrl,
                    decoration:
                    const InputDecoration(labelText: 'Venue name *'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: venueAddressCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Venue address *'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    onTap: onPickEndTime,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(child: Text('Expected end time')),
                        Text(
                          TimeOfDay.fromDateTime(expectedEnd).format(context),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(Icons.chevron_right,
                            color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader('If they picked you up (optional)'),
                  _PhotoCard(
                    label: 'Car photo',
                    required: false,
                    file: carPhoto,
                    onTap: onPickCar,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: plateCtrl,
                    decoration:
                    const InputDecoration(labelText: 'License plate'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: PrimaryButton(
              label: busy ? 'Starting…' : 'Start date session',
              icon: Icons.shield,
              onPressed: onStart,
              busy: busy,
            ),
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final missing = file == null && required;
    return AppCard(
      onTap: onTap,
      borderColor:
      missing ? AppColors.danger.withOpacity(0.4) : scheme.outlineVariant,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            child: file == null
                ? Container(
              width: 76,
              height: 76,
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.add_a_photo,
                  color: scheme.onSurfaceVariant, size: 30),
            )
                : Image.file(file!,
                width: 76, height: 76, fit: BoxFit.cover),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  required ? '$label *' : label,
                  style: text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  file == null ? 'Tap to add' : 'Tap to replace',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

// ============================================================================
// ACTIVE VIEW
// ============================================================================

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
        const Spacer(),
        DangerButton(
          label: 'Send alert now',
          icon: Icons.warning_amber_rounded,
          onPressed: onPanic,
          busy: busy,
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: "I'm safe — end session",
          icon: Icons.check,
          onPressed: onCancel,
          busy: busy,
        ),
      ],
    );
  }
}

String _fmt(DateTime dt) {
  final l = dt.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}