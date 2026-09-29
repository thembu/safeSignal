// lib/ui/theme/app_theme.dart
//
// Single source of truth for SafeSignal's visual language.
//
// Two "modes" of styling exist in this app:
//   1. Calm (default)     — used on setup, home, active-session, idle screens.
//                           Light-first, teal primary, soft surfaces, rounded.
//   2. Escalation (accent) — semantic tokens applied ON TOP of the calm theme
//                           for check-in prompts, in-grace countdowns, SOS.
//                           Red backgrounds, white text, oversized buttons.
//
// The escalation "mode" is NOT a separate ThemeData. It's just semantic color
// tokens (AppColors.danger, AppColors.dangerContainer, etc.) that specific
// screens opt into by using them directly. This keeps navigation transitions
// smooth and avoids Theme rebuilds mid-session.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Semantic color tokens.
///
/// Prefer `Theme.of(context).colorScheme.*` for standard M3 roles
/// (primary, surface, onSurface, etc). Use `AppColors.*` only for
/// semantic states that don't map to standard M3 roles: safe, warning,
/// danger, and their containers.
class AppColors {
  AppColors._();

  // ---- Brand / calm primary ----
  static const Color primary = Color(0xFF0F766E);           // deep teal
  static const Color primaryContainer = Color(0xFFCCFBF1);  // pale teal
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF042F2C);

  // ---- Surfaces (light-first) ----
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);    // cards, inputs
  static const Color surfaceContainer = Color(0xFFF8FAFC);  // subtle sections
  static const Color onSurface = Color(0xFF0F172A);
  static const Color onSurfaceVariant = Color(0xFF475569);
  static const Color outline = Color(0xFFCBD5E1);
  static const Color outlineVariant = Color(0xFFE2E8F0);

  // ---- Semantic state colors ----
  // Safe = confirmed check-in, session ended cleanly, "I'm okay"
  static const Color safe = Color(0xFF16A34A);
  static const Color safeContainer = Color(0xFFDCFCE7);
  static const Color onSafe = Color(0xFFFFFFFF);
  static const Color onSafeContainer = Color(0xFF052E16);

  // Warning = timer running low, degraded signal, needs attention
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarning = Color(0xFF000000);
  static const Color onWarningContainer = Color(0xFF451A03);

  // Danger = escalation, SOS, in-grace countdown
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerContainer = Color(0xFF7F1D1D);   // full-bleed bg
  static const Color onDanger = Color(0xFFFFFFFF);
  static const Color onDangerContainer = Color(0xFFFFFFFF);

  // ---- Dark variants (for later — not wired in yet) ----
  static const Color darkSurface = Color(0xFF0F172A);
  static const Color darkSurfaceVariant = Color(0xFF1E293B);
  static const Color darkOnSurface = Color(0xFFF1F5F9);
}

/// Shape tokens.
class AppShapes {
  AppShapes._();

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;   // default: cards, inputs
  static const double radiusLg = 16.0;   // sheets, dialogs
  static const double radiusPill = 999.0; // primary CTAs

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius sheetRadius = BorderRadius.all(Radius.circular(radiusLg));
}

/// Spacing scale (4pt grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;
}

/// Touch target minimums. Larger than M3 default because SafeSignal
/// is used one-handed, in motion, potentially by a shaking user.
class AppTouchTargets {
  AppTouchTargets._();

  static const double primary = 56.0;    // main CTAs
  static const double emergency = 72.0;  // SOS / in-grace buttons
  static const double compact = 48.0;    // secondary actions
}

/// Builds the calm/default theme. Use this in `MaterialApp.theme`.
ThemeData buildCalmTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.primary,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.primaryContainer,
    onSecondaryContainer: AppColors.onPrimaryContainer,
    tertiary: AppColors.safe,
    onTertiary: AppColors.onSafe,
    error: AppColors.danger,
    onError: AppColors.onDanger,
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceContainerHighest: AppColors.surfaceVariant,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF1E293B),
    onInverseSurface: Color(0xFFF1F5F9),
    inversePrimary: Color(0xFF5EEAD4),
  );

  final textTheme = _buildTextTheme(colorScheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    textTheme: textTheme,

    // ---- App bar ----
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),

    // ---- Cards ----
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerHighest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.cardRadius),
      clipBehavior: Clip.antiAlias,
    ),

    // ---- Filled buttons (primary CTA) ----
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTouchTargets.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: const StadiumBorder(),
        textStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ---- Outlined buttons (secondary) ----
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTouchTargets.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: const StadiumBorder(),
        side: BorderSide(color: colorScheme.outline),
        textStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ---- Text buttons ----
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppTouchTargets.compact),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        textStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ---- Inputs ----
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: AppShapes.cardRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShapes.cardRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShapes.cardRadius,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppShapes.cardRadius,
        borderSide: BorderSide(color: colorScheme.error, width: 1),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    ),

    // ---- Dialogs ----
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.sheetRadius),
    ),

    // ---- Bottom sheets ----
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShapes.radiusLg),
        ),
      ),
    ),

    // ---- Snackbars ----
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppShapes.cardRadius),
    ),

    // ---- Dividers ----
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // ---- Progress indicators ----
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),

    // ---- Icons ----
    iconTheme: IconThemeData(
      color: colorScheme.onSurface,
      size: 24,
    ),
  );
}

/// Text theme. Uses system font for now (add `google_fonts` for Inter later).
TextTheme _buildTextTheme(Color onSurface) {
  return TextTheme(
    displayLarge: TextStyle(
      fontSize: 57, fontWeight: FontWeight.w400, color: onSurface, height: 1.12,
    ),
    displayMedium: TextStyle(
      fontSize: 45, fontWeight: FontWeight.w400, color: onSurface, height: 1.16,
    ),
    displaySmall: TextStyle(
      fontSize: 36, fontWeight: FontWeight.w400, color: onSurface, height: 1.22,
    ),
    headlineLarge: TextStyle(
      fontSize: 32, fontWeight: FontWeight.w600, color: onSurface, height: 1.25,
    ),
    headlineMedium: TextStyle(
      fontSize: 28, fontWeight: FontWeight.w600, color: onSurface, height: 1.29,
    ),
    headlineSmall: TextStyle(
      fontSize: 24, fontWeight: FontWeight.w600, color: onSurface, height: 1.33,
    ),
    titleLarge: TextStyle(
      fontSize: 22, fontWeight: FontWeight.w600, color: onSurface, height: 1.27,
    ),
    titleMedium: TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, color: onSurface, height: 1.5,
    ),
    titleSmall: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: onSurface, height: 1.43,
    ),
    bodyLarge: TextStyle(
      fontSize: 16, fontWeight: FontWeight.w400, color: onSurface, height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, color: onSurface, height: 1.43,
    ),
    bodySmall: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, color: onSurface, height: 1.33,
    ),
    labelLarge: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, color: onSurface, height: 1.43,
    ),
    labelMedium: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: onSurface, height: 1.33,
    ),
    labelSmall: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: onSurface, height: 1.45,
    ),
  );
}