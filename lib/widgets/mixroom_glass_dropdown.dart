import 'package:flutter/material.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

Future<T?> showMixroomGlassDropdown<T>({
  required BuildContext anchorContext,
  required Widget child,
  double verticalGap = 8,
  double horizontalInset = 12,
  double? minWidth,
  double? maxWidth,
  double radius = 20,
  Color color = const Color.fromRGBO(244, 244, 244, 0.18),
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 8,
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
  final top = (anchorOffset.dy + anchorBox.size.height + verticalGap)
      .clamp(horizontalInset, overlay.size.height - horizontalInset)
      .toDouble();

  return Navigator.of(anchorContext).push<T>(
    _MixroomGlassDropdownRoute<T>(
      left: left,
      top: top,
      width: width.toDouble(),
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
    required this.radius,
    required this.color,
    required this.padding,
    required this.child,
  });

  final double left;
  final double top;
  final double width;
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
  Duration get transitionDuration => const Duration(milliseconds: 120);

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
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
              alignment: Alignment.topCenter,
              child: Material(
                type: MaterialType.transparency,
                child: MixroomShellSurface(
                  radius: radius,
                  strong: false,
                  color: color,
                  padding: padding,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
