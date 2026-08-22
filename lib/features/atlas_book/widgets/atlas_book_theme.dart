import 'package:flutter/material.dart';

/// Visual system for printable Atlas Book pages.
///
/// Keep book-page styling separate from the app shell so future themes can
/// change the finished book without changing the saved genealogy content.
abstract final class AtlasBookTheme {
  static const Color ivory = Color(0xFFF7F1E3);
  static const Color ivoryLight = Color(0xFFFCF8EE);
  static const Color espresso = Color(0xFF493A2D);
  static const Color warmBrown = Color(0xFF6A5138);
  static const Color antiqueGold = Color(0xFFA2874E);
  static const Color antiqueGoldSoft = Color(0xFFC9B98F);

  static BoxDecoration get pageDecoration => BoxDecoration(
        color: ivory,
        border: Border.all(
          color: antiqueGoldSoft.withValues(alpha: 0.72),
          width: 1.1,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ivoryLight,
            ivory,
            Color(0xFFF4EDDD),
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      );

  /// Uses platform serif fonts so no font asset is required.
  static TextStyle displayTitle(BuildContext context) {
    return Theme.of(context).textTheme.headlineMedium!.copyWith(
          color: antiqueGold,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          height: 1.15,
        );
  }

  static TextStyle subtitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          color: warmBrown,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        );
  }

  static TextStyle sectionTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          color: espresso,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
          fontWeight: FontWeight.w700,
        );
  }

  static TextStyle body(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          color: espresso,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
          height: 1.45,
        );
  }
}
