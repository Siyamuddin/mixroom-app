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
        return _HaloFrame(
          active: isActive,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          child: child,
        );
      },
    );
  }
}

class _HaloFrame extends StatefulWidget {
  final bool active;
  final BorderRadius borderRadius;
  final Widget child;

  const _HaloFrame({
    required this.active,
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
                              color: const Color(0xFF8DD6FF)
                                  .withValues(alpha: 0.18 * glow),
                              blurRadius: 16 * glow,
                              spreadRadius: 1.6 * glow,
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
                              color: const Color(0xFF7CB6FF)
                                  .withValues(alpha: 0.05 * glow),
                              border: Border.all(
                                color: const Color(0xFFD7F0FF)
                                    .withValues(alpha: 0.78 * glow),
                                width: 1.2 + (0.9 * glow),
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
