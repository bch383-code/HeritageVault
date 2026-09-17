import 'package:flutter/material.dart';

class HeritageTheme {
  static const Color navy = Color(0xFF061725);
  static const Color deepNavy = Color(0xFF04111C);
  static const Color panel = Color(0xF0081E33);
  static const Color panelStrong = Color(0xFF0A2238);
  static const Color raisedNavy = Color(0xFF0C2942);

  static const Color antiqueGold = Color(0xFFC9A65A);
  static const Color agedGold = Color(0xFFAA8845);
  static const Color cream = Color(0xFFF3E9D1);
  static const Color text = Color(0xFFF4EFE5);
  static const Color mutedInk = Color(0xFFB7C2C9);
  static const Color archiveBlue = Color(0xFF7FAFDC);

  static ThemeData light() => dark();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: archiveBlue,
      onPrimary: deepNavy,
      primaryContainer: Color(0xFF0C3453),
      onPrimaryContainer: cream,
      secondary: antiqueGold,
      onSecondary: Color(0xFF181208),
      secondaryContainer: Color(0xFF2D271B),
      onSecondaryContainer: cream,
      tertiary: cream,
      onTertiary: deepNavy,
      surface: panelStrong,
      onSurface: text,
      surfaceContainerHighest: raisedNavy,
      onSurfaceVariant: mutedInk,
      outline: Color(0xFF5A6D79),
      outlineVariant: Color(0xFF304754),
      error: Color(0xFFE36B4D),
      onError: Color(0xFF2A0903),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: navy,
      dividerColor: antiqueGold.withValues(alpha: .20),
    );

    const heading = TextStyle(
      color: cream,
      fontWeight: FontWeight.w700,
      letterSpacing: .15,
    );

    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,

      textTheme: base.textTheme.copyWith(
        displayLarge: base.textTheme.displayLarge?.merge(heading),
        displayMedium: base.textTheme.displayMedium?.merge(heading),
        headlineLarge: base.textTheme.headlineLarge?.merge(heading),
        headlineMedium: base.textTheme.headlineMedium?.merge(heading),
        headlineSmall: base.textTheme.headlineSmall?.merge(heading),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: cream,
          fontWeight: FontWeight.w700,
          letterSpacing: .08,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: cream,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: antiqueGold,
          fontWeight: FontWeight.w700,
          letterSpacing: .55,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: text),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: text),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: mutedInk),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: cream,
          fontWeight: FontWeight.w700,
          letterSpacing: .18,
        ),
      ),

      iconTheme: const IconThemeData(
        color: mutedInk,
        size: 20,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: BorderSide(
            color: antiqueGold.withValues(alpha: .28),
            width: .8,
          ),
        ),
      ),

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Color(0xF2071A2B),
        foregroundColor: cream,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: cream,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
        iconTheme: IconThemeData(color: Color(0xFFD6DEE4)),
      ),

      dividerTheme: DividerThemeData(
        color: antiqueGold.withValues(alpha: .20),
        thickness: .8,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFF9AADB9),
        textColor: text,
        selectedColor: cream,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        dense: true,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF071A2B),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: mutedInk.withValues(alpha: .58)),
        labelStyle: const TextStyle(color: mutedInk),
        prefixIconColor: antiqueGold,
        suffixIconColor: antiqueGold,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(
            color: antiqueGold.withValues(alpha: .28),
            width: .8,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: BorderSide(
            color: antiqueGold.withValues(alpha: .28),
            width: .8,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: antiqueGold, width: 1),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF123956),
          foregroundColor: cream,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: BorderSide(
              color: antiqueGold.withValues(alpha: .36),
              width: .8,
            ),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: antiqueGold,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          side: BorderSide(
            color: antiqueGold.withValues(alpha: .42),
            width: .8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: .22,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: antiqueGold,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: .18,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF0B253A),
        selectedColor: const Color(0xFF223824),
        side: BorderSide(
          color: antiqueGold.withValues(alpha: .30),
          width: .8,
        ),
        labelStyle: const TextStyle(color: cream),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
        ),
      ),

      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: panelStrong,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: BorderSide(
            color: antiqueGold.withValues(alpha: .42),
            width: .8,
          ),
        ),
        titleTextStyle: const TextStyle(
          color: cream,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        elevation: 8,
        color: panelStrong,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(
            color: antiqueGold.withValues(alpha: .30),
            width: .8,
          ),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF0A2032),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: antiqueGold.withValues(alpha: .30),
            width: .8,
          ),
        ),
        textStyle: const TextStyle(color: cream),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: antiqueGold,
        linearTrackColor: Color(0xFF173044),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: panelStrong,
        contentTextStyle: const TextStyle(color: cream),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(
            color: antiqueGold.withValues(alpha: .28),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1)),
        side: BorderSide(
          color: antiqueGold.withValues(alpha: .58),
          width: 1,
        ),
      ),

      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(
          antiqueGold.withValues(alpha: .35),
        ),
      ),
    );
  }
}
