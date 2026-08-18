import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Theming tuned for a driver glancing at the phone briefly (spec section 30/44):
/// large touch targets, high contrast, minimal decoration, no gratuitous animation.
class AppTheme {
  const AppTheme._();

  static const Color accentGreen = Color(0xFF1B8A4A);
  static const Color accentRed = Color(0xFFC62828);
  static const Color accentAmber = Color(0xFFB8860B);

  /// Fixed brand color for the app bar in both light and dark mode. Not
  /// [ColorScheme.primary] because M3's dark-theme primary is deliberately
  /// light (meant as foreground-on-dark-surface, not a block background) and
  /// would fail contrast against the white title text used here.
  static const Color brandHeader = Color(0xFF0B5FFF);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5FFF),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E0F12) : const Color(0xFFF6F7F9),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontSize: 17),
        bodyMedium: TextStyle(fontSize: 15),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      // Fully-rounded "pill" shape (not just a soft rectangle) for the
      // primary CTA — a driver's two most important taps (Start/Stop
      // automation) read as more premium and more obviously tappable as a
      // stadium button than a 16px-radius rectangle, and the elevated
      // shadow gives the button real lift off the page instead of sitting
      // flush with it.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          shape: const StadiumBorder(),
          elevation: 3,
          shadowColor: colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.5),
        ),
      ),
      // Elevation 0 on a card that's nearly the same tone as the scaffold
      // background (white-on-#F6F7F9, or dark-card-on-near-black) has almost
      // no visible edge on a real screen — a hairline border is what
      // actually separates "a card" from "a slightly different rectangle of
      // background". Kept subtle (low-alpha outlineVariant) so it reads as
      // definition, not a hard box. Radius widened from 20 to 24 for a
      // softer, more premium-feeling card shape.
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF17181C) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.7)),
        ),
        margin: EdgeInsets.zero,
      ),
      // A bold, brand-colored header instead of a bar that blends into the
      // scaffold is the single highest-impact change for making the app feel
      // designed rather than default Material — every screen now opens with
      // an unmistakable splash of color instead of grey-on-grey.
      appBarTheme: AppBarTheme(
        backgroundColor: brandHeader,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: Colors.white,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant.withValues(alpha: 0.6), space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF1F2126) : const Color(0xFFEDEFF3),
        selectedColor: colorScheme.primary.withValues(alpha: 0.18),
        disabledColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(fontWeight: FontWeight.w800, color: colorScheme.primary),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B1D22) : const Color(0xFFF0F1F4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? const Color(0xFF141519) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accentGreen : null,
        ),
      ),
    );
  }
}

/// Status colors kept separate from ThemeData so decision widgets (accept/reject
/// badges) stay legible regardless of the active brand seed color.
class StatusColors {
  const StatusColors._();

  static const Color accepted = AppTheme.accentGreen;
  static const Color rejected = AppTheme.accentRed;
  static const Color pendingOrUnknown = AppTheme.accentAmber;
  static const Color error = Color(0xFF8E24AA);

  /// Same blue as the app's own [ColorScheme] seed (0xFF0B5FFF) — ties the
  /// counter-offer outcome to the app's own brand color rather than
  /// introducing an unrelated fifth hue, since amber is already spoken for
  /// by [pendingOrUnknown].
  static const Color counterOffered = Color(0xFF0B5FFF);
}
