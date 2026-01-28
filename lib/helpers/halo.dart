import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mix_change_highlighter.dart';

class Halo extends StatelessWidget {
  final MixChangeHighlighter highlighter;
  final HaloKey haloKey;
  final Widget child;
  final BorderRadius? borderRadius;

  const Halo({
    super.key,
    required this.highlighter,
    required this.haloKey,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<HaloKey>>(
      valueListenable: highlighter.active,
      builder: (context, active, _) {
        final on = active.contains(haloKey);

        // simple flicker/pulse (no controller needed)
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: on ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 220),
          builder: (context, v, _) {
            final pulse = 0.5 + 0.5 * math.sin(DateTime.now().millisecondsSinceEpoch / 120.0);
            final glow = v * (0.6 + 0.4 * pulse);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                borderRadius: borderRadius ?? BorderRadius.circular(12),
                boxShadow: glow <= 0.001
                    ? const []
                    : [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.22 * glow),
                          blurRadius: 18 * glow,
                          spreadRadius: 2 * glow,
                        ),
                      ],
              ),
              child: child,
            );
          },
        );
      },
    );
  }
}
