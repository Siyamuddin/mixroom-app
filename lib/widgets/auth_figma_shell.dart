import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/helpers/glass_ui_tokens.dart';
import 'package:mixroom/helpers/orientation_policy.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:provider/provider.dart';

const String kMixroomSignInBackgroundAsset =
    'assets/auth/sign_in_background.webp';
const String kMixroomSignInBackgroundTileAsset =
    'assets/auth/sign_in_background_tile.png';
const String kMixroomLaunchBackgroundNoLogoTabletAsset =
    'assets/auth/launch_background_no_logo_tablet.png';
const String kMixroomLaunchSplashAsset = 'assets/mixroom_launch_screen.webp';
const String kMixroomBrandMarkAsset = 'assets/auth/brand_mark.png';
const String kMixroomWordmarkAsset = 'assets/auth/wordmark.png';
const String kMixroomGoogleSocialAsset = 'assets/auth/social_google.png';
const String kMixroomAppleSocialAsset = 'assets/auth/social_apple.png';
const String kMixroomKakaoSocialAsset = 'assets/auth/social_kakao.png';
const String kMixroomBackArrowAsset = 'assets/auth/back_arrow.png';
const String kMixroomCalendarIconAsset = 'assets/auth/calendar_icon.png';
const String kMixroomDropdownIconAsset = 'assets/auth/dropdown_icon.png';
const String kMixroomSendIconAsset = 'assets/auth/send_icon.png';
const String kMixroomResendIconAsset = 'assets/auth/resend_icon.png';
const String kMixroomCheckIconAsset = 'assets/auth/check_icon.png';
const String kMixroomEyeIconAsset = 'assets/auth/eye_icon.png';
const String kMixroomEyeOffIconAsset = 'assets/auth/eye_off_icon.png';
const String kMixroomLocaleFlagEnAsset = 'assets/auth/flag_en.svg';
const String kMixroomLocaleFlagKoAsset = 'assets/auth/flag_ko.svg';
const String kMixroomLocaleFlagJaAsset = 'assets/auth/flag_ja.svg';
const String kMixroomGoogleSocialIconAsset = 'assets/auth/icon_google.svg';
const String kMixroomAppleSocialIconAsset = 'assets/auth/icon_apple.svg';
const String kMixroomKakaoSocialIconAsset = 'assets/auth/icon_kakao.svg';

bool mixroomUseTabletLandscapeAuthLayout(BuildContext context) {
  final platform = PlatformCapabilities.current;
  final size = MediaQuery.sizeOf(context);
  return platform.isMobile &&
      isTabletLogicalSize(size) &&
      size.width >= size.height;
}

bool mixroomUseTabletDesktopAuthLayout(BuildContext context) {
  return PlatformCapabilities.current.isDesktop ||
      mixroomUseTabletLandscapeAuthLayout(context);
}

bool mixroomUseTabletDesktopAuthBackground(BuildContext context) {
  final platform = PlatformCapabilities.current;
  final size = MediaQuery.sizeOf(context);
  return platform.isDesktop || (platform.isMobile && isTabletLogicalSize(size));
}

class MixroomAuthBackground extends StatelessWidget {
  const MixroomAuthBackground({
    super.key,
    this.assetPath = kMixroomSignInBackgroundAsset,
  });

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final platform = PlatformCapabilities.current;
    final useLaunchBackgroundWithoutLogo =
        assetPath == kMixroomSignInBackgroundAsset &&
            mixroomUseTabletDesktopAuthBackground(context);
    if (useLaunchBackgroundWithoutLogo) {
      return const _MixroomLaunchBackgroundWithoutLogo();
    }

    final useDesktopSplashFit =
        assetPath == kMixroomLaunchSplashAsset && platform.isDesktop;
    return ColoredBox(
      color: const Color(0xFF090909),
      child: Image.asset(
        assetPath,
        fit: useDesktopSplashFit ? BoxFit.contain : BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: useDesktopSplashFit ? Alignment.center : Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class MixroomAuthPageScaffold extends StatelessWidget {
  const MixroomAuthPageScaffold({
    super.key,
    required this.body,
    this.resizeToAvoidBottomInset,
  });

  final Widget body;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        const _MixroomFullBleedAuthBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: body,
        ),
      ],
    );
  }
}

class _MixroomFullBleedAuthBackground extends StatelessWidget {
  const _MixroomFullBleedAuthBackground();

  @override
  Widget build(BuildContext context) {
    final displaySize = currentFlutterDisplayLogicalSize();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = displaySize == null
            ? constraints.maxWidth
            : math.max(constraints.maxWidth, displaySize.width);
        final height = displaySize == null
            ? constraints.maxHeight
            : math.max(constraints.maxHeight, displaySize.height);

        return OverflowBox(
          alignment: Alignment.center,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: const SizedBox.expand(
            child: MixroomAuthBackground(),
          ),
        );
      },
    );
  }
}

class _MixroomLaunchBackgroundWithoutLogo extends StatelessWidget {
  const _MixroomLaunchBackgroundWithoutLogo();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF020402),
      child: Image.asset(
        kMixroomLaunchBackgroundNoLogoTabletAsset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class MixroomLaunchSplash extends StatelessWidget {
  const MixroomLaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF090909));
  }
}

class MixroomLocaleSelector extends StatelessWidget {
  const MixroomLocaleSelector({super.key});

  static const Map<String, String> _displayCodes = <String, String>{
    'en': 'EN',
    'ko': 'KR',
    'ja': 'JP',
  };

  static String _localeFlagAsset(Locale locale) {
    switch (locale.languageCode) {
      case 'ko':
        return kMixroomLocaleFlagKoAsset;
      case 'ja':
        return kMixroomLocaleFlagJaAsset;
      case 'en':
      default:
        return kMixroomLocaleFlagEnAsset;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final locale = L10n.resolveSupportedLocale(localeProvider.locale);
        final code = _displayCodes[locale.languageCode] ??
            locale.languageCode.toUpperCase();

        return PopupMenuButton<Locale>(
          tooltip: L10n.translate(context, 'Language'),
          onSelected: (selectedLocale) =>
              L10n.setLocale(context, selectedLocale),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 14),
          color: kMixroomGlassDropdownMenuColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: const Color.fromRGBO(0, 0, 0, 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(
              color: Color.fromRGBO(244, 244, 244, 0.12),
            ),
          ),
          constraints: const BoxConstraints(minWidth: 188),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context) {
            return L10n.supportedLocales.map((supportedLocale) {
              final itemCode = _displayCodes[supportedLocale.languageCode] ??
                  supportedLocale.languageCode.toUpperCase();
              final itemName = L10n.languageName(supportedLocale);
              return PopupMenuItem<Locale>(
                value: supportedLocale,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    _MixroomCircularGlassButton(
                      size: 40,
                      showShadow: false,
                      icon: SvgPicture.asset(
                        _localeFlagAsset(supportedLocale),
                        width: 21,
                        height: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$itemCode  $itemName',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFFF4F4F4),
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 15,
                  height: 22 / 15,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFFF4F4F4),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 10),
              _MixroomCircularGlassButton(
                size: 48,
                showShadow: false,
                icon: SvgPicture.asset(
                  _localeFlagAsset(locale),
                  width: 25,
                  height: 25,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MixroomBrandLockup extends StatelessWidget {
  const MixroomBrandLockup({
    super.key,
    this.showWelcome = true,
    this.showMark = true,
  });

  final bool showWelcome;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          Image.asset(
            kMixroomBrandMarkAsset,
            width: 100,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(height: 26),
        ],
        if (showWelcome) ...[
          Text(
            L10n.translate(context, 'Welcome to'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 15,
              height: 22 / 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Image.asset(
          kMixroomWordmarkAsset,
          width: 162,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(height: 8),
        Text(
          L10n.translate(context, 'Fast, AI-assisted music production'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color(0xFFF4F4F4),
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class MixroomAuthTopBar extends StatelessWidget {
  const MixroomAuthTopBar({
    super.key,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: onBack == null
                ? const SizedBox(width: 48, height: 48)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(244, 244, 244, 0.40),
                          Color.fromRGBO(25, 94, 160, 0.40),
                        ],
                        stops: [0.56, 1.0],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.25),
                          blurRadius: 15,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: onBack,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: SvgPicture.asset(
                              kMixroomBackArrowAsset,
                              width: 10,
                              height: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          IgnorePointer(
            child: Image.asset(
              kMixroomBrandMarkAsset,
              width: 76,
              height: 48,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: MixroomLocaleSelector(),
          ),
        ],
      ),
    );
  }
}

class MixroomAuthBackCircleButton extends StatelessWidget {
  const MixroomAuthBackCircleButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(244, 244, 244, 0.40),
                Color.fromRGBO(25, 94, 160, 0.40),
              ],
              stops: [0.56, 1.0],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Center(
                child: SvgPicture.asset(
                  kMixroomBackArrowAsset,
                  width: 10,
                  height: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomGlassPanel extends StatelessWidget {
  const MixroomGlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.borderColor = const Color.fromRGBO(244, 244, 244, 0.14),
  });

  final Widget child;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
            color: const Color.fromRGBO(244, 244, 244, 0.30),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class MixroomGlassDivider extends StatelessWidget {
  const MixroomGlassDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color.fromRGBO(244, 244, 244, 0.15),
      indent: 23,
      endIndent: 23,
    );
  }
}

class MixroomGlassTextFieldRow extends StatelessWidget {
  const MixroomGlassTextFieldRow({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
    this.suffix,
    this.trailingText,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffix;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final hasValue = controller.text.trim().isNotEmpty;
    return SizedBox(
      height: 58,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        readOnly: readOnly,
        onTap: onTap,
        cursorColor: Colors.white,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          color: Color(0xFFF4F4F4),
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 23,
            vertical: 16,
          ),
          hintText: hasValue ? null : (hintText ?? label),
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color(0xFFF4F4F4),
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w400,
          ),
          labelText: hasValue ? label : null,
          labelStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color.fromRGBO(244, 244, 244, 0.50),
            fontSize: 12,
            height: 18 / 12,
            fontWeight: FontWeight.w400,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: _MixroomGlassSuffix(
            trailingText: trailingText,
            suffix: suffix,
          ),
        ),
      ),
    );
  }
}

class MixroomSignInFieldsCard extends StatelessWidget {
  const MixroomSignInFieldsCard({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.hidePassword,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onTogglePasswordVisibility,
    this.onEmailSubmitted,
    this.onPasswordSubmitted,
    this.onEmailEditingComplete,
    this.emailFocusNode,
    this.passwordFocusNode,
    this.hasError = false,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool hidePassword;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onTogglePasswordVisibility;
  final ValueChanged<String>? onEmailSubmitted;
  final ValueChanged<String>? onPasswordSubmitted;
  final VoidCallback? onEmailEditingComplete;
  final FocusNode? emailFocusNode;
  final FocusNode? passwordFocusNode;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? const Color.fromRGBO(255, 126, 136, 0.65)
        : const Color.fromRGBO(244, 244, 244, 0.14);
    final platform = Theme.of(context).platform;
    final emailAction = platform == TargetPlatform.iOS
        ? TextInputAction.done
        : TextInputAction.next;
    return MixroomGlassPanel(
      borderColor: borderColor,
      child: Column(
        children: [
          _MixroomFieldRow(
            controller: emailController,
            focusNode: emailFocusNode,
            hintText: L10n.translate(context, 'Email or Username'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: emailAction,
            onChanged: onEmailChanged,
            onSubmitted: onEmailSubmitted,
            onEditingComplete: onEmailEditingComplete,
          ),
          const MixroomGlassDivider(),
          _MixroomFieldRow(
            controller: passwordController,
            focusNode: passwordFocusNode,
            hintText: L10n.translate(context, 'Password'),
            obscureText: hidePassword,
            textInputAction: TextInputAction.done,
            onChanged: onPasswordChanged,
            onSubmitted: onPasswordSubmitted,
            suffix: IconButton(
              onPressed: onTogglePasswordVisibility,
              splashRadius: 18,
              icon: SvgPicture.asset(
                hidePassword ? kMixroomEyeIconAsset : kMixroomEyeOffIconAsset,
                width: 20,
                height: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MixroomFieldRow extends StatelessWidget {
  const _MixroomFieldRow({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onEditingComplete,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        obscureText: obscureText,
        cursorColor: Colors.white,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          color: Color(0xFFF4F4F4),
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 23,
            vertical: 18,
          ),
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Color(0xFFF4F4F4),
            fontSize: 15,
            height: 22 / 15,
            fontWeight: FontWeight.w400,
          ),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

class _MixroomGlassSuffix extends StatelessWidget {
  const _MixroomGlassSuffix({
    required this.trailingText,
    required this.suffix,
  });

  final String? trailingText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    if ((trailingText ?? '').trim().isEmpty && suffix == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 13),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if ((trailingText ?? '').trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: suffix == null ? 0 : 10),
              child: Text(
                trailingText!,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 15,
                  height: 22 / 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

class _MixroomPressFeedback extends StatefulWidget {
  const _MixroomPressFeedback({
    required this.child,
    required this.enabled,
    this.pressScale = 0.965,
  });

  final Widget child;
  final bool enabled;
  final double pressScale;

  @override
  State<_MixroomPressFeedback> createState() => _MixroomPressFeedbackState();
}

class _MixroomPressFeedbackState extends State<_MixroomPressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) value = false;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.9 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class MixroomAuthConsentRow extends StatelessWidget {
  const MixroomAuthConsentRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.richLabel,
  }) : assert(label != null || richLabel != null);

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? richLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final textStyle = const TextStyle(
      fontFamily: 'Pretendard',
      color: Color.fromRGBO(244, 244, 244, 0.86),
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
    );

    return Semantics(
      button: true,
      checked: value,
      child: _MixroomPressFeedback(
        enabled: enabled,
        pressScale: 0.985,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => onChanged!(!value) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value
                          ? const Color.fromRGBO(244, 244, 244, 0.13)
                          : Colors.transparent,
                      border: Border.all(
                        color: value
                            ? const Color(0xFFF4F4F4)
                            : const Color.fromRGBO(244, 244, 244, 0.76),
                        width: 1.3,
                      ),
                    ),
                    child: value
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFFF4F4F4),
                            size: 11,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DefaultTextStyle(
                      style: textStyle,
                      child: richLabel ?? Text(label!),
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

class MixroomAuthInlineLink extends StatelessWidget {
  const MixroomAuthInlineLink({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          color: Color(0xFFF4F4F4),
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFF4F4F4),
        ),
      ),
    );
  }
}

class MixroomFieldActionIconButton extends StatelessWidget {
  const MixroomFieldActionIconButton({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.onPressed,
    required this.iconWidth,
    required this.iconHeight,
    this.turns = 0,
    this.offset = Offset.zero,
    this.disabledOpacity = 1,
  });

  final String assetPath;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double iconWidth;
  final double iconHeight;
  final double turns;
  final Offset offset;
  final double disabledOpacity;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(
      assetPath,
      width: iconWidth,
      height: iconHeight,
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: _MixroomPressFeedback(
        enabled: onPressed != null,
        pressScale: 0.88,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              radius: 19,
              onTap: onPressed,
              child: OverflowBox(
                minWidth: 0,
                minHeight: 0,
                maxWidth: 44,
                maxHeight: 44,
                child: Center(
                  child: Transform.translate(
                    offset: offset,
                    child: Opacity(
                      opacity: onPressed == null ? disabledOpacity : 1,
                      child: turns == 0
                          ? icon
                          : Transform.rotate(
                              angle: turns,
                              child: icon,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomPillButton extends StatelessWidget {
  const MixroomPillButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.width,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final double width;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return _MixroomPressFeedback(
      enabled: !disabled && !busy,
      child: SizedBox(
        width: width,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: disabled
                  ? const [
                      Color.fromRGBO(244, 244, 244, 0.22),
                      Color.fromRGBO(25, 94, 160, 0.22),
                    ]
                  : const [
                      Color.fromRGBO(244, 244, 244, 0.50),
                      Color.fromRGBO(25, 94, 160, 0.50),
                    ],
              stops: const [0.56, 1.0],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFF4F4F4),
                          ),
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFFF4F4F4),
                          fontSize: 18,
                          height: 22 / 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomSecondaryPillButton extends StatelessWidget {
  const MixroomSecondaryPillButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.width,
  });

  final String label;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return _MixroomPressFeedback(
      enabled: !disabled,
      child: SizedBox(
        width: width,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: disabled
                ? const Color.fromRGBO(244, 244, 244, 0.12)
                : const Color.fromRGBO(244, 244, 244, 0.20),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: disabled
                        ? const Color.fromRGBO(244, 244, 244, 0.52)
                        : const Color(0xFFF4F4F4),
                    fontSize: 18,
                    height: 22 / 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MixroomSocialIconButton extends StatelessWidget {
  const MixroomSocialIconButton({
    super.key,
    required this.assetPath,
    required this.semanticLabel,
    required this.onTap,
  });

  final String assetPath;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconAsset = switch (assetPath) {
      kMixroomGoogleSocialAsset => kMixroomGoogleSocialIconAsset,
      kMixroomAppleSocialAsset => kMixroomAppleSocialIconAsset,
      kMixroomKakaoSocialAsset => kMixroomKakaoSocialIconAsset,
      _ => assetPath,
    };
    final iconSize = switch (assetPath) {
      kMixroomGoogleSocialAsset => const Size(21.78, 22.22),
      kMixroomAppleSocialAsset => const Size(16.11, 23.38),
      kMixroomKakaoSocialAsset => const Size(24.96, 23.01),
      _ => const Size(22, 22),
    };
    final buttonChild = assetPath == kMixroomAppleSocialAsset
        ? SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.25),
                    blurRadius: 15,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: SvgPicture.asset(
                kMixroomAppleSocialAsset,
                width: 48,
                height: 48,
              ),
            ),
          )
        : _MixroomCircularGlassButton(
            size: 48,
            icon: SvgPicture.asset(
              iconAsset,
              width: iconSize.width,
              height: iconSize.height,
            ),
          );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: _MixroomPressFeedback(
        enabled: onTap != null,
        pressScale: 0.92,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? 0.45 : 1,
              child: buttonChild,
            ),
          ),
        ),
      ),
    );
  }
}

class _MixroomCircularGlassButton extends StatelessWidget {
  const _MixroomCircularGlassButton({
    required this.size,
    required this.icon,
    this.showShadow = true,
  });

  final double size;
  final Widget icon;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(244, 244, 244, 0.40),
              Color.fromRGBO(25, 94, 160, 0.40),
            ],
            stops: [0.56, 1.0],
          ),
          boxShadow: showShadow
              ? const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.25),
                    blurRadius: 15,
                    spreadRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(child: icon),
      ),
    );
  }
}
