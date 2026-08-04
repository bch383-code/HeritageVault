import 'package:flutter/material.dart';

class HeritageTheme {
  static const Color walnut = Color(0xFF4A3728);
  static const Color bronze = Color(0xFF9A6B31);
  static const Color parchment = Color(0xFFF5F0E6);
  static const Color forest = Color(0xFF32483B);

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
        secondary: bronze,
        tertiary: forest,
      ),
      scaffoldBackgroundColor: const Color(0xFFFBF8F2),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.78),
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
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      appBarTheme: const AppBarTheme(elevation: 0),
    );
  }
}
