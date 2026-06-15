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
        return _HaloFrame(
          active: active.contains(haloKey),
          strong: _isStrongHaloKey(haloKey),
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: child,
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

    return ValueListenableBuilder<Set<HaloKey>>(
      valueListenable: highlighter.active,
      builder: (context, active, _) {
        final isActive = ordered.any(active.contains);
        final isStrong = ordered.any(
          (key) => active.contains(key) && _isStrongHaloKey(key),
        );
        return _HaloFrame(
          active: isActive,
          strong: isStrong,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: child,
        );
      },
    );
  }
}

bool _isStrongHaloKey(HaloKey key) {
  final value = key.key.trim().toLowerCase();
  return value.endsWith(':strong') ||
      value.endsWith('_strong') ||
      value.contains(':strong:');
}

class _HaloFrame extends StatefulWidget {
  final bool active;
  final bool strong;
  final BorderRadius borderRadius;
  final Widget child;

  const _HaloFrame({
    required this.active,
    required this.strong,
    required this.borderRadius,
    required this.child,
  });

  @override
  State<_HaloFrame> createState() => _HaloFrameState();
}

class _HaloFrameState extends State<_HaloFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 980),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _HaloFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _pulseController
        ..value = 0.0
        ..repeat(reverse: true);
      return;
    }
    _pulseController
      ..stop()
      ..value = 0.0;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse =
            widget.active ? (0.78 + (_pulseController.value * 0.22)) : 0;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: widget.active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 160),
          builder: (context, visibility, __) {
            final glow = Curves.easeOut.transform(visibility) * pulse;
            final glowColor = widget.strong
                ? const Color(0xFFFFA23A)
                : const Color(0xFF8DD6FF);
            final fillColor = widget.strong
                ? const Color(0xFFFFA23A)
                : const Color(0xFF7CB6FF);
            final borderColor = widget.strong
                ? const Color(0xFFFFE0B8)
                : const Color(0xFFD7F0FF);
            final glowAlpha = widget.strong ? 0.36 : 0.18;
            final fillAlpha = widget.strong ? 0.10 : 0.05;
            final blur = widget.strong ? 28.0 : 16.0;
            final spread = widget.strong ? 4.0 : 1.6;
            final borderWidthBase = widget.strong ? 2.0 : 1.2;
            final borderWidthPulse = widget.strong ? 1.4 : 0.9;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    boxShadow: glow <= 0.001
                        ? const []
                        : [
                            BoxShadow(
                              color:
                                  glowColor.withValues(alpha: glowAlpha * glow),
                              blurRadius: blur * glow,
                              spreadRadius: spread * glow,
                            ),
                          ],
                  ),
                  child: widget.child,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: glow <= 0.001
                          ? const BoxDecoration()
                          : BoxDecoration(
                              borderRadius: widget.borderRadius,
                              color:
                                  fillColor.withValues(alpha: fillAlpha * glow),
                              border: Border.all(
                                color:
                                    borderColor.withValues(alpha: 0.9 * glow),
                                width:
                                    borderWidthBase + (borderWidthPulse * glow),
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
