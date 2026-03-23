import 'package:flutter/widgets.dart';

class AppResponsiveBody extends StatelessWidget {
  const AppResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 920,
    this.padding = EdgeInsets.zero,
    this.expandToHeight = false,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool expandToHeight;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget content = Padding(
          padding: padding,
          child: child,
        );

        if (expandToHeight && constraints.maxHeight.isFinite) {
          content = SizedBox(
            height: constraints.maxHeight,
            child: content,
          );
        }

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(
              width: double.infinity,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
