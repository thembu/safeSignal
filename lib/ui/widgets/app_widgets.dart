// lib/ui/widgets/app_widgets.dart
//
// Reusable building blocks for SafeSignal screens. Every scenario/setup/active
// screen should compose from these, not roll its own styled Container/Button.
//
// Contents:
//   PrimaryButton      — main CTA (calm teal, pill shape, 56dp min)
//   SafeButton         — "I'm okay" green confirmation
//   DangerButton       — SOS / send alert (red, 72dp min)
//   SecondaryButton    — outlined, secondary actions (cancel, back)
//   AppCard            — surface card (12dp radius, soft grey bg)
//   StatusPill         — colored badge for session state
//   InfoRow            — icon + label + value row (used inside AppCard)
//   SectionHeader      — small uppercase label above a group
//   ScreenScaffold     — Scaffold with consistent padding + safe area

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../models/session.dart';

// ============================================================================
// BUTTONS
// ============================================================================

/// Primary calm CTA. Use for "Start session", "Continue", "Confirm".
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = _buttonContent(label: label, icon: icon, busy: busy);
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Green "safe" confirmation. Use for "I'm okay", "Confirm safe arrival".
class SafeButton extends StatelessWidget {
  const SafeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.safe,
        foregroundColor: AppColors.onSafe,
      ),
      onPressed: busy ? null : onPressed,
      child: _buttonContent(label: label, icon: icon, busy: busy),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Escalation button. Red, oversized (72dp), for SOS / send alert / false alarm.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.danger,
        foregroundColor: AppColors.onDanger,
        minimumSize: const Size.fromHeight(AppTouchTargets.emergency),
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      onPressed: busy ? null : onPressed,
      child: _buttonContent(label: label, icon: icon, busy: busy),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined secondary action. Use for "Cancel", "Not now", "Back".
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: _buttonContent(label: label, icon: icon, busy: busy),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

Widget _buttonContent({
  required String label,
  IconData? icon,
  required bool busy,
}) {
  if (busy) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
  if (icon == null) return Text(label);
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: AppSpacing.sm),
      Text(label),
    ],
  );
}

// ============================================================================
// CARDS
// ============================================================================

/// Standard content card. Consistent padding, radius, and surface color.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderColor,
    this.background,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(padding: padding, child: child);
    final decoration = BoxDecoration(
      color: background ?? scheme.surfaceContainerHighest,
      borderRadius: AppShapes.cardRadius,
      border: borderColor != null
          ? Border.all(color: borderColor!, width: 1)
          : null,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: AppShapes.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.cardRadius,
          child: DecoratedBox(decoration: decoration, child: content),
        ),
      );
    }
    return DecoratedBox(decoration: decoration, child: content);
  }
}

// ============================================================================
// STATUS PILL
// ============================================================================

/// Colored badge that reflects session state. Auto-picks color from status.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, dot) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppShapes.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, Color, Color) _styleFor(SessionStatus s) {
    switch (s) {
      case SessionStatus.active:
        return ('Active', AppColors.primaryContainer,
        AppColors.onPrimaryContainer, AppColors.primary);
      case SessionStatus.awaitingCheckIn:
        return ('Waiting for check-in', AppColors.warningContainer,
        AppColors.onWarningContainer, AppColors.warning);
      case SessionStatus.inGrace:
        return ('Alerting soon', const Color(0xFFFEE2E2),
        const Color(0xFF7F1D1D), AppColors.danger);
      case SessionStatus.checkedIn:
        return ('Checked in', AppColors.safeContainer,
        AppColors.onSafeContainer, AppColors.safe);
      case SessionStatus.escalated:
        return ('Alerts sent', const Color(0xFFFEE2E2),
        const Color(0xFF7F1D1D), AppColors.danger);
      case SessionStatus.cancelled:
        return ('Cancelled', const Color(0xFFF1F5F9),
        const Color(0xFF475569), const Color(0xFF94A3B8));
    }
  }
}

// ============================================================================
// INFO ROW
// ============================================================================

/// Icon + label + value row. Use inside AppCard for session details.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SECTION HEADER
// ============================================================================

/// Small uppercase label used above a group of inputs or cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.sm,
        top: AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN SCAFFOLD
// ============================================================================

/// Scaffold with consistent horizontal padding, safe area, and optional AppBar.
/// Use as the outermost widget of any screen instead of raw Scaffold.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    this.bottomBar,
    this.backgroundColor,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final EdgeInsets padding;
  final Widget? bottomBar;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: title == null
          ? null
          : AppBar(
        title: Text(title!),
        leading: leading,
        actions: actions,
      ),
      body: SafeArea(
        top: title == null,
        child: Padding(padding: padding, child: child),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: bottomBar,
        ),
      ),
    );
  }
}