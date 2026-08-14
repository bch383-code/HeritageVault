import 'package:flutter/material.dart';

class HeritageTheme {
  static const Color antiqueGold = Color(0xFFC7A24B);
  static const Color walnut = Color(0xFF0B1F33);
  static const Color bronze = Color(0xFF6F9FC8);
  static const Color parchment = Color(0xFFE8EDF2);
  static const Color forest = Color(0xFF34495A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: walnut,
      brightness: Brightness.light,
      surface: parchment,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: walnut,
        secondary: antiqueGold,
        tertiary: const Color(0xFF34495A),
      ),
      scaffoldBackgroundColor: const Color(0xFFE8EDF2),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: walnut,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFFF1E7C8),
        selectedColor: Color(0xFFC7A24B),
        side: BorderSide(color: Color(0xFFD5BE7A)),
        labelStyle: TextStyle(color: Color(0xFF2A2418)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: antiqueGold,
        linearTrackColor: Color(0xFFD6DDE4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: walnut.withValues(alpha: 0.16)),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: bronze,
      brightness: Brightness.dark,
      surface: const Color(0xFF172532),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: const Color(0xFF8CB7DD),
        secondary: antiqueGold,
        tertiary: const Color(0xFFB8C3CD),
        surface: const Color(0xFF172532),
        onSurface: const Color(0xFFF4F7FA),
        surfaceContainerHighest: const Color(0xFF263746),
        outline: const Color(0xFF71808D),
        outlineVariant: const Color(0xFF3B4C5B),
      ),
      scaffoldBackgroundColor: const Color(0xFF071522),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Color(0xFF172532),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFF0B1F33),
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: antiqueGold,
        linearTrackColor: Color(0xFF314352),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFF2F3E4B),
        selectedColor: Color(0xFFC7A24B),
        side: BorderSide(color: Color(0xFF7A6740)),
        labelStyle: TextStyle(color: Color(0xFFF4F7FA)),
      ),
    );
  }
}
