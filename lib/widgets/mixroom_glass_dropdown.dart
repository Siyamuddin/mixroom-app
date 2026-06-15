import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

Future<T?> showMixroomGlassDropdown<T>({
  required BuildContext anchorContext,
  required Widget child,
  double verticalGap = 0,
  double horizontalInset = 12,
  double verticalInset = 6,
  double? minWidth,
  double? maxWidth,
  double? preferredHeight,
  bool preferAbove = false,
  double radius = 20,
  Color color = const Color.fromRGBO(244, 244, 244, 0.10),
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 1,
  ),
}) {
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (anchorBox == null || overlay == null) {
    return Future<T?>.value();
  }

  final anchorOffset = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
  final availableWidth = overlay.size.width - (horizontalInset * 2);
  final preferredWidth = anchorBox.size.width
      .clamp(minWidth ?? 0.0, maxWidth ?? availableWidth)
      .toDouble();
  final width = preferredWidth.clamp(0.0, availableWidth).toDouble();
  final left = anchorOffset.dx
      .clamp(horizontalInset, overlay.size.width - width - horizontalInset)
      .toDouble();
  final desiredHeight = preferredHeight;
  final belowTop = anchorOffset.dy + anchorBox.size.height + verticalGap;
  final belowSpace = math.max(
    0.0,
    overlay.size.height - verticalInset - belowTop,
  );
  final aboveSpace = math.max(
    0.0,
    anchorOffset.dy - verticalGap - verticalInset,
  );
  final desiredFitsBelow = desiredHeight == null || desiredHeight <= belowSpace;
  final opensAbove = preferAbove
      ? aboveSpace >= belowSpace * 0.55
      : !desiredFitsBelow && aboveSpace > belowSpace;
  final availableHeight = math.max(1.0, opensAbove ? aboveSpace : belowSpace);
  final heightLimit = desiredHeight == null
      ? availableHeight
      : math.min(desiredHeight, availableHeight);
  final topLimit = math.max(
    verticalInset,
    overlay.size.height - verticalInset - heightLimit,
  );
  final top = opensAbove
      ? (anchorOffset.dy - verticalGap - heightLimit)
          .clamp(verticalInset, topLimit)
          .toDouble()
      : belowTop.clamp(verticalInset, topLimit).toDouble();

  return Navigator.of(anchorContext).push<T>(
    _MixroomGlassDropdownRoute<T>(
      left: left,
      top: top,
      width: width.toDouble(),
      maxHeight: heightLimit,
      opensAbove: opensAbove,
      radius: radius,
      color: color,
      padding: padding,
      child: child,
    ),
  );
}

class _MixroomGlassDropdownRoute<T> extends PopupRoute<T> {
  _MixroomGlassDropdownRoute({
    required this.left,
    required this.top,
    required this.width,
    required this.maxHeight,
    required this.opensAbove,
    required this.radius,
    required this.color,
    required this.padding,
    required this.child,
  });

  final double left;
  final double top;
  final double width;
  final double maxHeight;
  final bool opensAbove;
  final double radius;
  final Color color;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss dropdown';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 170);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 110);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final attachedRadius = math.max(8.0, radius * 0.56);
    final menuRadius = opensAbove
        ? BorderRadius.vertical(
            top: Radius.circular(radius),
            bottom: Radius.circular(attachedRadius),
          )
        : BorderRadius.vertical(
            top: Radius.circular(attachedRadius),
            bottom: Radius.circular(radius),
          );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(0.0, opensAbove ? 0.025 : -0.025),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  alignment:
                      opensAbove ? Alignment.bottomCenter : Alignment.topCenter,
                  child: Material(
                    type: MaterialType.transparency,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: menuRadius,
                    child: ClipRRect(
                      borderRadius: menuRadius,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: menuRadius,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.13),
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 16,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: padding,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
