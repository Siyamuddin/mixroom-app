import 'package:flutter/material.dart';

const Color kAccountGlassText = Color(0xFFF4F4F4);
const Color kAccountGlassMutedText = Color(0xB8F4F4F4);
const Color kAccountGlassSubtleText = Color(0x82F4F4F4);
const Color kAccountGlassBlue = Color(0xFF299AF2);
const Color kAccountGlassGreen = Color(0xFF65F39A);
const Color kAccountGlassYellow = Color(0xFFFFDF71);
const Color kAccountGlassDanger = Color(0xFFFF8188);

BoxDecoration accountGlassDecoration({
  double radius = 24,
  bool strong = false,
  bool selected = false,
  bool danger = false,
}) {
  final borderColor = danger
      ? kAccountGlassDanger.withValues(alpha: 0.48)
      : selected
      ? kAccountGlassBlue.withValues(alpha: 0.62)
      : Colors.white.withValues(alpha: strong ? 0.34 : 0.24);
  return BoxDecoration(
    color: strong
        ? const Color.fromRGBO(244, 244, 244, 0.24)
        : const Color.fromRGBO(244, 244, 244, 0.20),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: selected ? 1.1 : 0.8),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: strong ? 0.30 : 0.22),
        blurRadius: strong ? 22 : 16,
        offset: const Offset(0, 8),
      ),
      if (selected)
        BoxShadow(
          color: kAccountGlassBlue.withValues(alpha: 0.13),
          blurRadius: 24,
        ),
    ],
  );
}

class AccountGlassSurface extends StatelessWidget {
  const AccountGlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.strong = false,
    this.selected = false,
    this.danger = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: accountGlassDecoration(
        radius: radius,
        strong: strong,
        selected: selected,
        danger: danger,
      ),
      child: child,
    );
  }
}

class AccountSectionHeading extends StatelessWidget {
  const AccountSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: kAccountGlassText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: kAccountGlassSubtleText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class AccountGlassDivider extends StatelessWidget {
  const AccountGlassDivider({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(
        height: 0.8,
        color: Colors.white.withValues(alpha: 0.36),
      ),
    );
  }
}
