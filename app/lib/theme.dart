import 'package:flutter/material.dart';

/// The Alvyo look, as on the website: greyish greens, an orange accent,
/// Figtree for text and Bricolage Grotesque for headings. Light and dark
/// follow the phone's setting unless chosen (see AppSettings).
class AlvyoColors {
  const AlvyoColors._(this.accent);

  /// Filled buttons and the record button; text on it is [onAccent].
  final Color accent;
  static const onAccent = Color(0xFF1A0F08);

  static const light = AlvyoColors._(Color(0xFFF28A48));
  static const dark = AlvyoColors._(Color(0xFFFFA66B));

  static AlvyoColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const _display = 'Bricolage Grotesque';

ThemeData alvyoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? AlvyoColors.dark.accent : AlvyoColors.light.accent;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Color(0xFFFFA66B),
          onPrimary: AlvyoColors.onAccent,
          primaryContainer: Color(0xFF3A2616),
          onPrimaryContainer: Color(0xFFFFC59E),
          secondary: Color(0xFFA4B2A9),
          onSecondary: Color(0xFF0E1512),
          secondaryContainer: Color(0xFF24312A),
          onSecondaryContainer: Color(0xFFE9EFE9),
          tertiaryContainer: Color(0xFF2B1F16),
          onTertiaryContainer: Color(0xFFFFC59E),
          surface: Color(0xFF0E1512),
          onSurface: Color(0xFFE9EFE9),
          onSurfaceVariant: Color(0xFFA4B2A9),
          surfaceContainerLowest: Color(0xFF0B120E),
          surfaceContainerLow: Color(0xFF121B17),
          surfaceContainer: Color(0xFF16201B),
          surfaceContainerHigh: Color(0xFF1B2621),
          surfaceContainerHighest: Color(0xFF24312A),
          outline: Color(0xFF2E3D35),
          outlineVariant: Color(0xFF24312A),
        )
      : const ColorScheme.light(
          primary: Color(0xFFA94C18), // 4.5:1 also on surfaceContainerHigh, as accent-ink on the web
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFFDEEE3),
          onPrimaryContainer: Color(0xFF6B2E0C),
          secondary: Color(0xFF56645C),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFE8EDE6),
          onSecondaryContainer: Color(0xFF14201A),
          tertiaryContainer: Color(0xFFFDEEE3),
          onTertiaryContainer: Color(0xFF6B2E0C),
          surface: Color(0xFFF2F4EF),
          onSurface: Color(0xFF14201A),
          onSurfaceVariant: Color(0xFF56645C),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: Colors.white,
          surfaceContainerHigh: Color(0xFFE8EDE6),
          surfaceContainerHighest: Color(0xFFDCE3DC),
          outline: Color(0xFFD3DCD5),
          outlineVariant: Color(0xFFDCE3DC),
        );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Figtree');
  final text = base.textTheme;
  TextStyle? heading(TextStyle? s) =>
      s?.copyWith(fontFamily: _display, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  final line = BorderSide(color: scheme.outlineVariant);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displayLarge: heading(text.displayLarge),
      displayMedium: heading(text.displayMedium),
      displaySmall: heading(text.displaySmall),
      headlineLarge: heading(text.headlineLarge),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: heading(text.titleLarge),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: heading(text.titleLarge)?.copyWith(color: scheme.onSurface, fontSize: 24),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: line),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: AlvyoColors.onAccent,
        textStyle: const TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w600, fontSize: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: line),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: line),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      backgroundColor: scheme.surfaceContainerLow,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: accent,
      dividerColor: scheme.outlineVariant,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
