import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';

const String kMixroomShellBackgroundAsset =
    'assets/app_shell/shell_background.webp';
const String kMixroomShellBrandMarkAsset = 'assets/app_shell/brand_mark.png';
const String kMixroomShellWordmarkAsset = 'assets/app_shell/wordmark.png';
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
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.white.withValues(alpha: strong ? 0.18 : 0.14),
      width: 0.9,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: strong ? 24 : 18,
        spreadRadius: strong ? 1 : 0,
        offset: const Offset(0, 10),
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
        Color.fromRGBO(32, 82, 132, 0.80),
        Color.fromRGBO(118, 170, 220, 0.98),
      ],
      stops: <double>[0.10, 1.0],
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(39)),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.12),
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
                  Colors.white.withValues(alpha: intense ? 0.045 : 0.03),
                  Colors.white.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: intense ? 0.06 : 0.045),
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
                  Colors.white.withValues(alpha: intense ? 0.11 : 0.075),
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
  return mixroomShellDockBottomInset(context) + kMixroomMainDockOverlapInset;
}

double mixroomShellDockBottomInset(BuildContext context) {
  final bottomPadding = MediaQuery.of(context).padding.bottom;
  if (defaultTargetPlatform == TargetPlatform.android) {
    return bottomPadding;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // Keep iOS dock slightly elevated without the overly high full safe-area lift.
    return (bottomPadding * 0.35).clamp(8.0, 14.0).toDouble();
  }
  return 0.0;
}

class MixroomShellBackground extends StatelessWidget {
  const MixroomShellBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF090909),
      child: Image.asset(
        kMixroomShellBackgroundAsset,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.high,
      ),
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
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
                    color: Colors.white.withValues(alpha: active ? 0.14 : 0.10),
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
          Image.asset(
            kMixroomShellBrandMarkAsset,
            width: 76,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          if (showWordmark) ...[
            const SizedBox(height: 22),
            Image.asset(
              kMixroomShellWordmarkAsset,
              width: 162,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
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
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onChanged(options[i]);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labelBuilder(options[i]),
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(
                                      alpha: options[i] == value ? 0.98 : 0.62,
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
  });

  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  ) onSubmit;
  final bool initialSubmitted;
  final bool compact;

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
    return Column(
      children: [
        if (widget.compact)
          Image.asset(
            kMixroomShellBrandMarkAsset,
            width: 54,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          )
        else
          MixroomShellWordmarkHeader(showWordmark: true),
        SizedBox(height: topGap),
        Text(
          L10n.translate(context, 'Feedback for'),
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
