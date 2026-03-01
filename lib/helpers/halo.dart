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
        final radius = borderRadius ?? BorderRadius.circular(12);

        // simple flicker/pulse (no controller needed)
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: on ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 220),
          builder: (context, v, _) {
            final pulse = 0.5 +
                0.5 * math.sin(DateTime.now().millisecondsSinceEpoch / 120.0);
            final glow = v * (0.6 + 0.4 * pulse);
            return Stack(
              fit: StackFit.passthrough,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: glow <= 0.001
                        ? const []
                        : [
                            BoxShadow(
                              color: const Color(0xFF9AD0FF)
                                  .withValues(alpha: 0.22 * glow),
                              blurRadius: 18 * glow,
                              spreadRadius: 2 * glow,
                            ),
                          ],
                  ),
                  child: child,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: glow <= 0.001
                          ? const BoxDecoration()
                          : BoxDecoration(
                              borderRadius: radius,
                              color: const Color(0xFF7CB6FF)
                                  .withValues(alpha: 0.08 * glow),
                              border: Border.all(
                                color: const Color(0xFFBFE2FF)
                                    .withValues(alpha: 0.86 * glow),
                                width: 1.8 + (1.2 * glow),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class MultiHalo extends StatelessWidget {
  final MixChangeHighlighter highlighter;
  final List<HaloKey> haloKeys;
  final Widget child;
  final BorderRadius? borderRadius;

  const MultiHalo({
    super.key,
    required this.highlighter,
    required this.haloKeys,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final unique = <HaloKey>{};
    final ordered = <HaloKey>[];
    for (final key in haloKeys) {
      if (unique.add(key)) {
        ordered.add(key);
      }
    }
    if (ordered.isEmpty) return child;

    Widget wrapped = child;
    for (final key in ordered) {
      wrapped = Halo(
        highlighter: highlighter,
        haloKey: key,
        borderRadius: borderRadius,
        child: wrapped,
      );
    }
    return wrapped;
  }
}
