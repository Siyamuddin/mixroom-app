import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/helpers/orientation_policy.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';

const String kMixroomShellBackgroundAsset =
    'assets/app_shell/shell_background.webp';
const String kMixroomShellBrandMarkAsset = 'assets/app_shell/brand_mark.png';
const String kMixroomShellWordmarkAsset = 'assets/app_shell/wordmark.png';
const String kMixroomShortWhiteLogoAsset = 'assets/short_white.png';
const String kMixroomShellHomeAsset = 'assets/app_shell/nav_home.svg';
const String kMixroomShellHomeActiveAsset =
    'assets/app_shell/nav_home_active.svg';
const String kMixroomShellPlatformAsset = 'assets/app_shell/nav_platform.svg';
const String kMixroomShellPlatformActiveAsset =
    'assets/app_shell/nav_platform_active.svg';
const String kMixroomShellAddAsset = 'assets/app_shell/nav_add.svg';
const String kMixroomShellProjectsAsset = 'assets/app_shell/nav_projects.svg';
const String kMixroomShellProjectsActiveAsset =
    'assets/app_shell/nav_projects_active.svg';
const String kMixroomShellAccountAsset = 'assets/app_shell/nav_account.svg';
const String kMixroomShellAccountActiveAsset =
    'assets/app_shell/nav_account_active.svg';
const String kMixroomShellFilterAsset = 'assets/app_shell/projects_filter.svg';
const String kMixroomShellImportAsset = 'assets/app_shell/import_icon.svg';
const String kMixroomShellCheckboxCheckedAsset =
    'assets/app_shell/checkbox_checked.svg';
const String kMixroomShellProfileAvatarAsset =
    'assets/app_shell/profile_avatar.svg';
const String kMixroomShellAccountProfileHeadAsset =
    'assets/app_shell/account_profile_head.svg';
const String kMixroomShellAccountEditPencilAsset =
    'assets/app_shell/account_edit_pencil.svg';
const String kMixroomShellAccountEditCheckAsset =
    'assets/app_shell/account_edit_check.svg';

const double kMixroomMainDockHeight = 80;
const double kMixroomMainDockOverlapInset = 98;
const double kMixroomDesktopRailWidth = 80;
const double kMixroomDesktopTitleBarHeight = 34;

const double _kMixroomBrandMarkAspectRatio = 2616 / 1644;
const double _kMixroomWordmarkAspectRatio = 4096 / 591;

enum MixroomMainTab {
  home,
  platform,
  projects,
  account,
}

BoxDecoration mixroomShellSurfaceDecoration({
  double radius = 24,
  Color color = const Color.fromRGBO(244, 244, 244, 0.18),
  bool strong = false,
}) {
  final topTone =
      Color.lerp(color, Colors.white, strong ? 0.12 : 0.07)!.withValues(
    alpha: strong ? 0.24 : 0.20,
  );
  final bottomTone =
      Color.lerp(color, const Color(0xFF08111B), strong ? 0.68 : 0.56)!
          .withValues(alpha: strong ? 0.78 : 0.68);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        topTone,
        Color.lerp(color, const Color(0xFF0B1726), 0.42)!.withValues(
          alpha: strong ? 0.46 : 0.38,
        ),
        bottomTone,
      ],
      stops: const [0.0, 0.38, 1.0],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Color.lerp(
        Colors.white.withValues(alpha: strong ? 0.17 : 0.13),
        const Color(0xFF7FD4FF),
        strong ? 0.18 : 0.08,
      )!,
      width: strong ? 1.0 : 0.9,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: strong ? 0.34 : 0.26),
        blurRadius: strong ? 30 : 22,
        spreadRadius: strong ? 2 : 0,
        offset: const Offset(0, 14),
      ),
      BoxShadow(
        color: const Color(0xFF2E9DFF).withValues(
          alpha: strong ? 0.10 : 0.05,
        ),
        blurRadius: strong ? 28 : 20,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

BoxDecoration mixroomShellDockDecoration() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.fromRGBO(39, 96, 156, 0.84),
        Color.fromRGBO(27, 72, 121, 0.92),
        Color.fromRGBO(118, 170, 220, 0.98),
      ],
      stops: <double>[0.05, 0.42, 1.0],
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(39)),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.14),
      width: 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.46),
        blurRadius: 34,
        spreadRadius: 6,
        offset: const Offset(0, -10),
      ),
    ],
  );
}

Widget _mixroomShellChromeOverlay({
  required double radius,
  bool intense = false,
}) {
  return IgnorePointer(
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: intense ? 0.065 : 0.04),
                  Colors.white.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: intense ? 0.08 : 0.05),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: Container(
            width: radius + 10,
            height: radius * 0.7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius - 2),
                bottomRight: Radius.circular(radius),
              ),
              gradient: RadialGradient(
                center: const Alignment(-0.95, -0.95),
                radius: 1.05,
                colors: [
                  Colors.white.withValues(alpha: intense ? 0.15 : 0.10),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

double mixroomShellBottomPadding(BuildContext context) {
  if (mixroomUsesSideRailNavigation(context)) {
    return 28;
  }
  return mixroomShellDockBottomInset(context) + kMixroomMainDockOverlapInset;
}

double mixroomShellDockBottomInset(BuildContext context) {
  // Use viewPadding so keyboard (viewInsets) changes do not shift the dock.
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return bottomPadding;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // Keep iOS dock slightly elevated without the overly high full safe-area lift.
    return (bottomPadding * 0.35).clamp(8.0, 14.0).toDouble();
  }
  return 0.0;
}

bool get mixroomUsesDesktopRailNavigation =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool mixroomUsesTabletLandscapeShell(BuildContext context) {
  final platform = PlatformCapabilities.current;
  final size = MediaQuery.sizeOf(context);
  final displaySize = currentFlutterDisplayLogicalSize();
  return platform.isMobile &&
      isTabletLogicalWindowOrDisplaySize(
        logicalWindowSize: size,
        logicalDisplaySize: displaySize,
      ) &&
      size.width >= size.height;
}

bool mixroomUsesSideRailNavigation(BuildContext context) {
  return mixroomUsesDesktopRailNavigation ||
      mixroomUsesTabletLandscapeShell(context);
}

class MixroomDesktopTitleBar extends StatelessWidget {
  const MixroomDesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMixroomDesktopTitleBarHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF070C12).withValues(alpha: 0.96),
                  const Color(0xFF070C12).withValues(alpha: 0.90),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.075),
                  width: 0.8,
                ),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class MixroomShellBackground extends StatelessWidget {
  const MixroomShellBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF06080D)),
        Image.asset(
          kMixroomShellBackgroundAsset,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(3, 5, 9, 0.22),
                Color.fromRGBO(6, 10, 17, 0.08),
                Color.fromRGBO(4, 8, 14, 0.42),
              ],
              stops: [0.0, 0.38, 1.0],
            ),
          ),
        ),
        Positioned(
          left: -120,
          bottom: -180,
          child: IgnorePointer(
            child: Container(
              width: 460,
              height: 460,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2D8CFF).withValues(alpha: 0.22),
                    const Color(0xFF2D8CFF).withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.34, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -100,
          top: -120,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8FE0FF).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const double _kMixroomLogoRasterOversample = 2.0;

int _mixroomRasterCacheExtent(BuildContext context, double logicalExtent) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  return (logicalExtent * devicePixelRatio * _kMixroomLogoRasterOversample)
      .round()
      .clamp(1, 8192);
}

class _MixroomShellRasterAsset extends StatelessWidget {
  const _MixroomShellRasterAsset({
    required this.assetPath,
    required this.aspectRatio,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
  });

  final String assetPath;
  final double aspectRatio;
  final double? width;
  final double? height;
  final Alignment alignment;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final effectiveWidth =
        width ?? (height == null ? null : height! * aspectRatio);
    final effectiveHeight =
        height ?? (width == null ? null : width! / aspectRatio);
    return RepaintBoundary(
      child: Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        cacheWidth: effectiveWidth == null
            ? null
            : _mixroomRasterCacheExtent(context, effectiveWidth),
        cacheHeight: effectiveHeight == null
            ? null
            : _mixroomRasterCacheExtent(context, effectiveHeight),
      ),
    );
  }
}

class MixroomShellBrandMark extends StatelessWidget {
  const MixroomShellBrandMark({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return _MixroomShellRasterAsset(
      assetPath: kMixroomShellBrandMarkAsset,
      aspectRatio: _kMixroomBrandMarkAspectRatio,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}

class MixroomShellWordmark extends StatelessWidget {
  const MixroomShellWordmark({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.centerLeft,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return _MixroomShellRasterAsset(
      assetPath: kMixroomShellWordmarkAsset,
      aspectRatio: _kMixroomWordmarkAspectRatio,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}

class MixroomShellShortLogo extends StatelessWidget {
  const MixroomShellShortLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return _MixroomShellRasterAsset(
      assetPath: kMixroomShortWhiteLogoAsset,
      aspectRatio: _kMixroomBrandMarkAspectRatio,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}

class MixroomShellSurface extends StatelessWidget {
  const MixroomShellSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.color = const Color.fromRGBO(244, 244, 244, 0.18),
    this.strong = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Stack(
          children: [
            Container(
              padding: padding,
              decoration: mixroomShellSurfaceDecoration(
                radius: radius,
                color: color,
                strong: strong,
              ),
              child: child,
            ),
            Positioned.fill(
              child: _mixroomShellChromeOverlay(
                radius: radius,
                intense: strong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MixroomShellDialog extends StatelessWidget {
  const MixroomShellDialog({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.radius = 26,
    this.maxWidth = 420,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 18),
    this.alignment,
    this.color = const Color.fromRGBO(244, 244, 244, 0.14),
    this.strong = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double maxWidth;
  final EdgeInsets insetPadding;
  final AlignmentGeometry? alignment;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: alignment,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      insetPadding: insetPadding,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: MixroomShellSurface(
            radius: radius,
            strong: strong,
            color: color,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class MixroomShellDialogButton extends StatelessWidget {
  const MixroomShellDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool accent;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = accent
        ? const Color.fromRGBO(0, 149, 255, 0.52)
        : danger
            ? const Color.fromRGBO(255, 119, 119, 0.18)
            : Colors.white.withValues(alpha: 0.10);
    final foregroundColor =
        danger ? const Color(0xFFFFB4B4) : const Color(0xFFF4F4F4);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: MixroomShellSurface(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: backgroundColor,
        strong: accent,
        child: SizedBox(
          width: double.infinity,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: foregroundColor,
              fontSize: 15,
              height: 22 / 15,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomShellRoundButton extends StatelessWidget {
  const MixroomShellRoundButton({
    super.key,
    this.onTap,
    this.assetPath,
    this.icon,
    this.size = 48,
    this.iconExtent,
    this.active = false,
    this.activeWide = false,
    this.tint,
    this.fillColor,
  }) : assert(assetPath != null || icon != null);

  final VoidCallback? onTap;
  final String? assetPath;
  final Widget? icon;
  final double size;
  final double? iconExtent;
  final bool active;
  final bool activeWide;
  final Color? tint;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final width = activeWide ? 76.0 : size;
    final fill = fillColor ??
        (active
            ? (activeWide
                ? const Color.fromRGBO(0, 149, 255, 0.60)
                : const Color.fromRGBO(244, 244, 244, 0.60))
            : const Color.fromRGBO(244, 244, 244, 0.22));
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashFactory: InkRipple.splashFactory,
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return Colors.white.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Stack(
              children: [
                Container(
                  width: width,
                  height: size,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color:
                          Colors.white.withValues(alpha: active ? 0.14 : 0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: icon ??
                      SvgPicture.asset(
                        assetPath!,
                        width: iconExtent ?? (activeWide ? 16 : 20),
                        height: iconExtent ?? (activeWide ? 16 : 20),
                        colorFilter: tint == null
                            ? null
                            : ColorFilter.mode(tint!, BlendMode.srcIn),
                      ),
                ),
                Positioned.fill(
                  child: _mixroomShellChromeOverlay(
                    radius: 24,
                    intense: active || activeWide,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomShellWordmarkHeader extends StatelessWidget {
  const MixroomShellWordmarkHeader({
    super.key,
    this.showWordmark = false,
    this.topPadding = 58,
  });

  final bool showWordmark;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MixroomShellBrandMark(width: 76),
          if (showWordmark) ...[
            const SizedBox(height: 22),
            const MixroomShellWordmark(width: 162, alignment: Alignment.center),
          ],
        ],
      ),
    );
  }
}

class MixroomShellSegmentedControl<T> extends StatelessWidget {
  const MixroomShellSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexOf(value).clamp(0, options.length - 1);
    BorderRadius thumbRadiusForIndex(int index) {
      const outer = Radius.circular(18);
      const inner = Radius.circular(10);
      final isFirst = index == 0;
      final isLast = index == options.length - 1;
      return BorderRadius.only(
        topLeft: isFirst ? outer : inner,
        bottomLeft: isFirst ? outer : inner,
        topRight: isLast ? outer : inner,
        bottomRight: isLast ? outer : inner,
      );
    }

    return MixroomShellSurface(
      radius: 24,
      padding: const EdgeInsets.all(3),
      color: const Color.fromRGBO(244, 244, 244, 0.14),
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / options.length;
            return ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: segmentWidth * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color.fromRGBO(244, 244, 244, 0.25),
                            Color.fromRGBO(244, 244, 244, 0.17),
                          ],
                        ),
                        borderRadius: thumbRadiusForIndex(selectedIndex),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < options.length; i++)
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onChanged(options[i]);
                              },
                              borderRadius: thumbRadiusForIndex(i),
                              overlayColor:
                                  WidgetStateProperty.resolveWith<Color?>(
                                      (states) {
                                if (states.contains(WidgetState.pressed)) {
                                  return Colors.white.withValues(alpha: 0.12);
                                }
                                if (states.contains(WidgetState.hovered)) {
                                  return Colors.white.withValues(alpha: 0.06);
                                }
                                if (states.contains(WidgetState.focused)) {
                                  return Colors.white.withValues(alpha: 0.08);
                                }
                                return Colors.transparent;
                              }),
                              child: Container(
                                alignment: Alignment.center,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    labelBuilder(options[i]),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Colors.white.withValues(
                                        alpha:
                                            options[i] == value ? 0.98 : 0.62,
                                      ),
                                      fontSize: 15,
                                      fontWeight: options[i] == value
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class MixroomMainBottomDock extends StatelessWidget {
  const MixroomMainBottomDock({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
    this.addMenuOpen = false,
  });

  final MixroomMainTab selectedTab;
  final ValueChanged<MixroomMainTab> onTabSelected;
  final VoidCallback onAddTap;
  final bool addMenuOpen;

  String _iconForTab(MixroomMainTab tab, bool active) {
    switch (tab) {
      case MixroomMainTab.home:
        return active ? kMixroomShellHomeActiveAsset : kMixroomShellHomeAsset;
      case MixroomMainTab.platform:
        return active
            ? kMixroomShellPlatformActiveAsset
            : kMixroomShellPlatformAsset;
      case MixroomMainTab.projects:
        return active
            ? kMixroomShellProjectsActiveAsset
            : kMixroomShellProjectsAsset;
      case MixroomMainTab.account:
        return active
            ? kMixroomShellAccountActiveAsset
            : kMixroomShellAccountAsset;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = mixroomShellDockBottomInset(context);
    return IgnorePointer(
      ignoring: false,
      child: Container(
        height: kMixroomMainDockHeight + bottomInset,
        decoration: mixroomShellDockDecoration(),
        padding: EdgeInsets.fromLTRB(27, 7, 27, bottomInset + 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            MixroomShellRoundButton(
              assetPath: _iconForTab(
                  MixroomMainTab.home, selectedTab == MixroomMainTab.home),
              active: selectedTab == MixroomMainTab.home,
              onTap: () => onTabSelected(MixroomMainTab.home),
            ),
            MixroomShellRoundButton(
              assetPath: _iconForTab(MixroomMainTab.platform,
                  selectedTab == MixroomMainTab.platform),
              active: selectedTab == MixroomMainTab.platform,
              onTap: () => onTabSelected(MixroomMainTab.platform),
            ),
            MixroomShellRoundButton(
              icon: Icon(
                addMenuOpen ? Icons.close_rounded : Icons.add_rounded,
                color: const Color(0xFFF4F4F4),
                size: addMenuOpen ? 22 : 28,
              ),
              active: !addMenuOpen,
              activeWide: true,
              fillColor: addMenuOpen
                  ? const Color.fromRGBO(244, 244, 244, 0.34)
                  : null,
              onTap: onAddTap,
            ),
            MixroomShellRoundButton(
              assetPath: _iconForTab(MixroomMainTab.projects,
                  selectedTab == MixroomMainTab.projects),
              active: selectedTab == MixroomMainTab.projects,
              onTap: () => onTabSelected(MixroomMainTab.projects),
            ),
            MixroomShellRoundButton(
              assetPath: _iconForTab(MixroomMainTab.account,
                  selectedTab == MixroomMainTab.account),
              active: selectedTab == MixroomMainTab.account,
              onTap: () => onTabSelected(MixroomMainTab.account),
            ),
          ],
        ),
      ),
    );
  }
}

class MixroomMainSideRail extends StatelessWidget {
  const MixroomMainSideRail({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAddTap,
  });

  final MixroomMainTab selectedTab;
  final ValueChanged<MixroomMainTab> onTabSelected;
  final VoidCallback onAddTap;

  String _iconForTab(MixroomMainTab tab, bool active) {
    switch (tab) {
      case MixroomMainTab.home:
        return active ? kMixroomShellHomeActiveAsset : kMixroomShellHomeAsset;
      case MixroomMainTab.platform:
        return active
            ? kMixroomShellPlatformActiveAsset
            : kMixroomShellPlatformAsset;
      case MixroomMainTab.projects:
        return active
            ? kMixroomShellProjectsActiveAsset
            : kMixroomShellProjectsAsset;
      case MixroomMainTab.account:
        return active
            ? kMixroomShellAccountActiveAsset
            : kMixroomShellAccountAsset;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kMixroomDesktopRailWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF080E15).withValues(alpha: 0.96),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
          border: Border(
            right: BorderSide(
              color: Colors.white.withValues(alpha: 0.075),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 24,
              offset: const Offset(8, 0),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 22, 10, 12),
          child: Column(
            children: [
              Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111A25),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const MixroomShellShortLogo(),
              ),
              const SizedBox(height: 24),
              _MixroomDesktopRailIconButton(
                label: L10n.translate(context, 'Home'),
                active: selectedTab == MixroomMainTab.home,
                assetPath: _iconForTab(
                  MixroomMainTab.home,
                  selectedTab == MixroomMainTab.home,
                ),
                onTap: () => onTabSelected(MixroomMainTab.home),
              ),
              const SizedBox(height: 14),
              _MixroomDesktopRailIconButton(
                label: L10n.translate(context, 'Platform'),
                active: selectedTab == MixroomMainTab.platform,
                assetPath: _iconForTab(
                  MixroomMainTab.platform,
                  selectedTab == MixroomMainTab.platform,
                ),
                onTap: () => onTabSelected(MixroomMainTab.platform),
              ),
              const SizedBox(height: 14),
              _MixroomDesktopRailIconButton(
                label: L10n.translate(context, 'Projects'),
                active: selectedTab == MixroomMainTab.projects,
                assetPath: _iconForTab(
                  MixroomMainTab.projects,
                  selectedTab == MixroomMainTab.projects,
                ),
                onTap: () => onTabSelected(MixroomMainTab.projects),
              ),
              const SizedBox(height: 14),
              _MixroomDesktopRailIconButton(
                label: L10n.translate(context, 'Account'),
                active: selectedTab == MixroomMainTab.account,
                assetPath: _iconForTab(
                  MixroomMainTab.account,
                  selectedTab == MixroomMainTab.account,
                ),
                onTap: () => onTabSelected(MixroomMainTab.account),
              ),
              const Spacer(),
              _MixroomDesktopRailIconButton(
                label: L10n.translate(context, 'New Project'),
                active: true,
                emphasize: true,
                icon: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFFF4F4F4),
                  size: 28,
                ),
                onTap: onAddTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixroomDesktopRailIconButton extends StatefulWidget {
  const _MixroomDesktopRailIconButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.assetPath,
    this.icon,
    this.emphasize = false,
  }) : assert(assetPath != null || icon != null);

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? assetPath;
  final Widget? icon;
  final bool emphasize;

  @override
  State<_MixroomDesktopRailIconButton> createState() =>
      _MixroomDesktopRailIconButtonState();
}

class _MixroomDesktopRailIconButtonState
    extends State<_MixroomDesktopRailIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final emphasize = widget.emphasize;
    final activeColor = emphasize
        ? const Color(0xFF0A84FF)
        : const Color(0xFF132132).withValues(alpha: 0.98);
    final idleColor =
        _hovered ? Colors.white.withValues(alpha: 0.075) : Colors.transparent;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.96 : (_hovered ? 1.04 : 1.0),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    width: emphasize ? 48 : 49,
                    height: emphasize ? 46 : 48,
                    decoration: BoxDecoration(
                      color: active ? activeColor : idleColor,
                      borderRadius: BorderRadius.circular(emphasize ? 14 : 15),
                      border: Border.all(
                        color: active || _hovered
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.transparent,
                      ),
                      boxShadow: emphasize
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.34),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (active && !emphasize)
                    Positioned(
                      left: 4,
                      child: Container(
                        width: 3,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF48B8FF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: emphasize ? 28 : 24,
                    height: emphasize ? 28 : 24,
                    child: Center(
                      child: widget.icon ??
                          SvgPicture.asset(
                            widget.assetPath!,
                            width: 23,
                            height: 23,
                            colorFilter: ColorFilter.mode(
                              Colors.white.withValues(
                                alpha: active || _hovered ? 0.95 : 0.72,
                              ),
                              BlendMode.srcIn,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum MixroomFeedbackComposerState {
  feedback,
  bugReport,
}

class MixroomInlineFeedbackComposer extends StatefulWidget {
  const MixroomInlineFeedbackComposer({
    super.key,
    required this.onSubmit,
    this.initialSubmitted = false,
    this.compact = false,
    this.showBetaNotice = false,
  });

  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  ) onSubmit;
  final bool initialSubmitted;
  final bool compact;
  final bool showBetaNotice;

  @override
  State<MixroomInlineFeedbackComposer> createState() =>
      _MixroomInlineFeedbackComposerState();
}

class _MixroomInlineFeedbackComposerState
    extends State<MixroomInlineFeedbackComposer> {
  late final TextEditingController _controller;
  late final FocusNode _messageFocusNode;
  MixroomFeedbackComposerState _state = MixroomFeedbackComposerState.feedback;
  bool _allowEmailContact = false;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _messageFocusNode = FocusNode(debugLabel: 'inline_feedback_message');
    _submitted = widget.initialSubmitted;
  }

  @override
  void dispose() {
    _messageFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  FeedbackCategory get _category =>
      _state == MixroomFeedbackComposerState.bugReport
          ? FeedbackCategory.bugReport
          : FeedbackCategory.feedback;

  Future<void> _handleSubmit() async {
    _messageFocusNode.unfocus();
    final message = FeedbackTextSanitizer.sanitize(_controller.text);
    if (message.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _category,
        message,
        _allowEmailContact,
      );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _controller.clear();
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topGap = widget.compact ? 14.0 : 96.0;
    final betaNoticeTopGap =
        widget.showBetaNotice && !widget.compact ? 34.0 : 0.0;
    final betaNoticeBottomGap =
        widget.showBetaNotice && !widget.compact ? 40.0 : topGap;
    return Column(
      children: [
        if (widget.compact)
          const MixroomShellBrandMark(
            width: 54,
            fit: BoxFit.contain,
          )
        else
          MixroomShellWordmarkHeader(showWordmark: true),
        if (widget.showBetaNotice) ...[
          SizedBox(height: betaNoticeTopGap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 272),
            child: Text(
              L10n.translate(
                context,
                'There may be bugs or unexpected errors.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 18 / 13,
              ),
            ),
          ),
        ],
        SizedBox(height: betaNoticeBottomGap),
        Text(
          L10n.translate(context, 'Send Feedback'),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color(0xFFF4F4F4),
            fontSize: 18,
            fontWeight: FontWeight.w400,
            height: 22 / 18,
          ),
        ),
        const SizedBox(height: 12),
        MixroomShellSegmentedControl<MixroomFeedbackComposerState>(
          value: _state,
          options: const [
            MixroomFeedbackComposerState.feedback,
            MixroomFeedbackComposerState.bugReport,
          ],
          labelBuilder: (state) => L10n.translate(
            context,
            state == MixroomFeedbackComposerState.feedback
                ? 'Feedback'
                : 'Bug Report',
          ),
          onChanged: (next) {
            setState(() => _state = next);
          },
        ),
        const SizedBox(height: 22),
        MixroomShellSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: const Color.fromRGBO(244, 244, 244, 0.10),
          child: TextField(
            controller: _controller,
            focusNode: _messageFocusNode,
            minLines: 5,
            maxLines: 7,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _messageFocusNode.unfocus(),
            onEditingComplete: _messageFocusNode.unfocus,
            onTapOutside: (_) => _messageFocusNode.unfocus(),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 15,
              height: 22 / 15,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: _state == MixroomFeedbackComposerState.feedback
                  ? L10n.translate(
                      context,
                      'Tell us what is working, missing, or would make this better.',
                    )
                  : L10n.translate(
                      context,
                      'Describe the bug, what you expected, and what happened.',
                    ),
              hintStyle: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 15,
                height: 22 / 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _allowEmailContact = !_allowEmailContact);
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _allowEmailContact
                    ? SvgPicture.asset(
                        kMixroomShellCheckboxCheckedAsset,
                        width: 20,
                        height: 20,
                      )
                    : Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.65),
                            width: 1.4,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.translate(
                        context,
                        'Allow Mixroom to respond by email.',
                      ),
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFF4F4F4),
                        fontSize: 15,
                        height: 15 / 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.translate(
                        context,
                        'Optional. We may follow up using your account email about this submission.',
                      ),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 10,
                        height: 15 / 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        GestureDetector(
          onTap: _handleSubmit,
          child: MixroomShellSurface(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            color: const Color.fromRGBO(244, 244, 244, 0.58),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                _submitted
                    ? L10n.translate(context, 'Thank you for the feedback!')
                    : L10n.translate(
                        context,
                        _submitting ? 'Sending...' : 'Submit',
                      ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white.withValues(alpha: 0.96),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 22 / 15,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
