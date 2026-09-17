import 'package:flutter/material.dart';

class HeritageBackdrop extends StatelessWidget {
  const HeritageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF061421),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A2A47),
                  Color(0xFF071A2B),
                  Color(0xFF05131F),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.34,
              child: Image.asset(
                'assets/branding/heirloom_atlas_beta_heritage_atmosphere.png',
                fit: BoxFit.cover,
                alignment: Alignment.topRight,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xC7071A2B),
                    Color(0x8F071A2B),
                    Color(0x4A071A2B),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
