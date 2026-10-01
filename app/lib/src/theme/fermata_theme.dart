import 'package:flutter/material.dart';

/// Fermata's Material 3 theme, shaped towards Samsung One UI conventions.
///
/// The distinctive One UI traits, and where each one lives:
///
///  * large, bold, tightly-tracked headings, used for screen titles
///  * pill-shaped search fields, chips and primary buttons
///  * generously rounded cards (20-24dp rather than M3's default 12)
///  * a bottom navigation bar whose active indicator is a wide pill
///
/// Only the app chrome is themed this way. Score content renders at its native
/// resolution, so nothing here can affect how a page of music looks.
abstract final class FermataTheme {
  static const double _cardRadius = 22;
  static const double _pillRadius = 100;

  /// Brand seed. A deep indigo reads as "focused" without the clinical feel of
  /// a pure blue.
  static const Color seed = Color(0xFF4C5FD5);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: _textTheme(base.textTheme).titleLarge?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        side: WidgetStatePropertyAll(BorderSide.none),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_pillRadius),
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          base.textTheme.bodyLarge?.copyWith(fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_pillRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_pillRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_pillRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_pillRadius),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: base.textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        // The wide pill behind the active tab is the One UI signature.
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.35),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.4),
  );
}
