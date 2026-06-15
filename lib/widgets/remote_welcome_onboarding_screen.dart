import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';

class RemoteWelcomeOnboardingScreen extends StatefulWidget {
  const RemoteWelcomeOnboardingScreen({
    super.key,
    required this.onCompleted,
  });

  final VoidCallback onCompleted;

  @override
  State<RemoteWelcomeOnboardingScreen> createState() =>
      _RemoteWelcomeOnboardingScreenState();
}

class _RemoteWelcomeOnboardingScreenState
    extends State<RemoteWelcomeOnboardingScreen> with TickerProviderStateMixin {
  static const Size _contentSize = Size(402, 720);
  static const Color _foreground = Color(0xFFF4F4F4);

  final PageController _pageController = PageController();

  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  late final AnimationController _arrowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1850),
  )..repeat();

  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _waveController.dispose();
    _arrowController.dispose();
    super.dispose();
  }

  bool get _isKorean {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'ko';
  }

  Future<void> _handlePrimaryPressed() async {
    if (_currentPage < 3) {
      await _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _isKorean ? _OnboardingCopy.ko : _OnboardingCopy.en;

    return PopScope(
      canPop: false,
      child: MixroomAuthPageScaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Expanded(
                child: _buildPageViewport(copy),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    _buildPageIndicators(),
                    const SizedBox(height: 18),
                    _buildPrimaryButton(copy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageViewport(_OnboardingCopy copy) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: PageView(
          controller: _pageController,
          onPageChanged: (value) {
            if (!mounted) return;
            setState(() => _currentPage = value);
          },
          children: [
            _buildScaledPage(_buildPageOne(copy)),
            _buildScaledPage(_buildPageTwo(copy)),
            _buildScaledPage(_buildPageThree(copy)),
            _buildScaledPage(_buildPageFour(copy)),
          ],
        ),
      ),
    );
  }

  Widget _buildScaledPage(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: _contentSize.width,
              height: _contentSize.height,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrimaryButton(_OnboardingCopy copy) {
    final isFinalPage = _currentPage == 3;
    final String label = isFinalPage ? copy.startButton : copy.nextButton;

    return SizedBox(
      width: 164,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: isFinalPage
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment(0, 1.25),
                  colors: [
                    Color.fromRGBO(244, 244, 244, 0.5),
                    Color.fromRGBO(25, 94, 160, 0.5),
                  ],
                  stops: [0.5, 1.0],
                )
              : null,
          color: isFinalPage ? null : const Color.fromRGBO(244, 244, 244, 0.2),
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
            onTap: _handlePrimaryPressed,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _foreground,
                  fontSize: 18,
                  height: 22 / 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
          width: isActive ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? _foreground
                : const Color.fromRGBO(244, 244, 244, 0.24),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _buildPageOne(_OnboardingCopy copy) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            final oscillation = math.sin(_waveController.value * math.pi * 2);
            final horizontal = oscillation * 2.2;
            final handRotate = oscillation * 0.08;
            final handLift = -oscillation.abs() * 1.6;
            return Stack(
              children: [
                Positioned(
                  left: 113.5 + horizontal,
                  top: 325.5,
                  width: 175,
                  height: 186,
                  child: Transform.translate(
                    offset: Offset(horizontal * 0.7, 0),
                    child: SvgPicture.asset(
                      _OnboardingAssets.heroWaveLines,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  left: 122.67,
                  top: 393.06,
                  width: 157.8,
                  height: 96.8,
                  child: Transform.translate(
                    offset: Offset(horizontal, handLift),
                    child: Transform.rotate(
                      angle: handRotate,
                      child: SvgPicture.asset(
                        _OnboardingAssets.heroHand,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 527.5,
          child: _titleText(copy.page1Title),
        ),
      ],
    );
  }

  Widget _buildPageTwo(_OnboardingCopy copy) {
    return Stack(
      children: [
        Positioned(
          left: 77.3,
          top: 225,
          width: 247.4,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: copy.page2TopRegular,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 22,
                    weight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: copy.page2TopBold,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 22,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 35.66,
          top: 296.46,
          width: 330.67,
          height: 278.08,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 50,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    children: [
                      Positioned(
                        left: -0.0371 * w,
                        top: -0.4244 * h,
                        width: 1.0743 * w,
                        height: 2.6465 * h,
                        child: Image.asset(
                          _OnboardingAssets.proMockup,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          left: 77.3,
          top: copy.page2BottomTop,
          width: 247.4,
          child: Column(
            children: [
              Text(
                copy.page2BottomLine1,
                textAlign: TextAlign.center,
                style: _textStyle(
                  fontSize: 25,
                  lineHeight: 28,
                  weight: copy.page2BottomLine1Weight,
                ),
              ),
              Text(
                copy.page2BottomLine2,
                textAlign: TextAlign.center,
                style: _textStyle(
                  fontSize: 25,
                  lineHeight: 28,
                  weight: copy.page2BottomLine2Weight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageThree(_OnboardingCopy copy) {
    return Stack(
      children: [
        Positioned(
          left: copy.page3TopLeft,
          top: 179,
          width: copy.page3TopWidth,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: copy.page3TopRegular,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 22,
                    weight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: copy.page3TopBold,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 22,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 35.66471862792969,
          top: 242.41015625,
          width: 330.669921875,
          height: 368.7052001953125,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Image.asset(
              _OnboardingAssets.aiChatMockup,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        Positioned(
          left: 77.3,
          top: 651,
          width: 247.4,
          child: Text(
            copy.page3Bottom,
            textAlign: TextAlign.center,
            style: _textStyle(
              fontSize: 25,
              lineHeight: 28,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageFour(_OnboardingCopy copy) {
    return Stack(
      children: [
        if (copy.page4TopSingleLine != null)
          Positioned(
            left: 0,
            right: 0,
            top: 227,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: copy.page4TopRegular,
                    style: _textStyle(
                      fontSize: 25,
                      lineHeight: 22,
                      weight: FontWeight.w400,
                    ),
                  ),
                  TextSpan(
                    text: copy.page4TopBold,
                    style: _textStyle(
                      fontSize: 25,
                      lineHeight: 22,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Positioned(
            left: 0,
            right: 0,
            top: 198,
            child: Column(
              children: [
                Text(
                  copy.page4TopLine1,
                  textAlign: TextAlign.center,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 32,
                    weight: FontWeight.w400,
                  ),
                ),
                Text(
                  copy.page4TopLine2,
                  textAlign: TextAlign.center,
                  style: _textStyle(
                    fontSize: 25,
                    lineHeight: 32,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        AnimatedBuilder(
          animation: _arrowController,
          builder: (context, child) {
            final t = _arrowController.value;
            final drift = 1.35 * math.sin((t * math.pi * 2) + 0.45);
            final pulseAlpha = 0.9 + (0.1 * math.sin(t * math.pi * 2));

            return Stack(
              children: [
                Positioned(
                  left: 70.5,
                  top: 316.958984375,
                  width: 77.86692810058594,
                  height: 93.49465942382812,
                  child: SvgPicture.asset(
                    _OnboardingAssets.lastPeopleLeft,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  left: 253.633544921875,
                  top: 316.958984375,
                  width: 77.86692810058594,
                  height: 93.49465942382812,
                  child: SvgPicture.asset(
                    _OnboardingAssets.lastPeopleRight,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  left: 271.146484375,
                  top: 328.41014099121094,
                  width: 42.84375,
                  height: 26.924741744995117,
                  child: Image.asset(
                    _OnboardingAssets.lastMixroomMark,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Positioned(
                  left: 166.2001953125,
                  top: 348.619140625,
                  width: 69.6005859375,
                  height: 63.26932144165039,
                  child: SvgPicture.asset(
                    _OnboardingAssets.lastArrowTop,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  left: 177.359375,
                  top: 434.98046875 + drift,
                  width: 47.2822265625,
                  height: 57.07421875,
                  child: Opacity(
                    opacity: pulseAlpha,
                    child: SvgPicture.asset(
                      _OnboardingAssets.lastArrowMid,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  left: 161.2626953125,
                  top: 511.20703125 + (drift * 1.25),
                  width: 63.37888717651367,
                  height: 71.298828125,
                  child: SvgPicture.asset(
                    _OnboardingAssets.lastMusicNote,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            );
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 651,
          child: _titleText(copy.page4Bottom, lineHeight: 28),
        ),
      ],
    );
  }

  Widget _titleText(
    String text, {
    double lineHeight = 22,
  }) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: _textStyle(
        fontSize: 25,
        lineHeight: lineHeight,
        weight: FontWeight.w600,
      ),
    );
  }

  TextStyle _textStyle({
    required double fontSize,
    required double lineHeight,
    required FontWeight weight,
  }) {
    return TextStyle(
      fontFamily: 'Pretendard',
      color: _foreground,
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: weight,
      shadows: const [
        Shadow(
          color: Colors.black,
          blurRadius: 50,
        ),
      ],
    );
  }
}

class _OnboardingAssets {
  static const String heroWaveLines =
      'assets/auth/onboarding/hero_wave_lines.svg';
  static const String heroHand = 'assets/auth/onboarding/hero_hand.svg';
  static const String proMockup = 'assets/auth/onboarding/pro_mockup.png';
  static const String aiChatMockup =
      'assets/auth/onboarding/ai_chat_mockup.png';
  static const String lastPeopleRight =
      'assets/auth/onboarding/p4_right_group.svg';
  static const String lastMixroomMark =
      'assets/auth/onboarding/p4_right_mark.png';
  static const String lastPeopleLeft =
      'assets/auth/onboarding/p4_left_group.svg';
  static const String lastArrowTop =
      'assets/auth/onboarding/p4_center_hand.svg';
  static const String lastArrowMid = 'assets/auth/onboarding/p4_arrow_mid.svg';
  static const String lastMusicNote = 'assets/auth/onboarding/p4_note.svg';
}

class _OnboardingCopy {
  const _OnboardingCopy({
    required this.page1Title,
    required this.page2TopRegular,
    required this.page2TopBold,
    required this.page2BottomLine1,
    required this.page2BottomLine2,
    required this.page2BottomLine1Weight,
    required this.page2BottomLine2Weight,
    required this.page2BottomTop,
    required this.page3TopRegular,
    required this.page3TopBold,
    required this.page3TopLeft,
    required this.page3TopWidth,
    required this.page3Bottom,
    required this.page4TopRegular,
    required this.page4TopBold,
    required this.page4TopSingleLine,
    required this.page4TopLine1,
    required this.page4TopLine2,
    required this.page4Bottom,
    required this.nextButton,
    required this.startButton,
  });

  final String page1Title;

  final String page2TopRegular;
  final String page2TopBold;
  final String page2BottomLine1;
  final String page2BottomLine2;
  final FontWeight page2BottomLine1Weight;
  final FontWeight page2BottomLine2Weight;
  final double page2BottomTop;

  final String page3TopRegular;
  final String page3TopBold;
  final double page3TopLeft;
  final double page3TopWidth;
  final String page3Bottom;

  final String page4TopRegular;
  final String page4TopBold;
  final String? page4TopSingleLine;
  final String page4TopLine1;
  final String page4TopLine2;
  final String page4Bottom;

  final String nextButton;
  final String startButton;

  static const _OnboardingCopy en = _OnboardingCopy(
    page1Title: 'New here?',
    page2TopRegular: 'Create like a ',
    page2TopBold: 'Pro.',
    page2BottomLine1: 'Full multi-track.',
    page2BottomLine2: 'Right on your phone.',
    page2BottomLine1Weight: FontWeight.w600,
    page2BottomLine2Weight: FontWeight.w400,
    page2BottomTop: 624,
    page3TopRegular: 'Say ',
    page3TopBold: 'what you want.',
    page3TopLeft: 77.3,
    page3TopWidth: 247.4,
    page3Bottom: 'AI makes it real.',
    page4TopRegular: 'No experience',
    page4TopBold: ' needed.',
    page4TopSingleLine: 'No experience needed.',
    page4TopLine1: '',
    page4TopLine2: '',
    page4Bottom: 'Start now.',
    nextButton: 'Next',
    startButton: 'Get Started!',
  );

  static const _OnboardingCopy ko = _OnboardingCopy(
    page1Title: '처음 뵙겠습니다',
    page2TopRegular: '그래도, ',
    page2TopBold: '프로처럼.',
    page2BottomLine1: '모바일에서 구현되는',
    page2BottomLine2: '풀 멀티트랙',
    page2BottomLine1Weight: FontWeight.w400,
    page2BottomLine2Weight: FontWeight.w600,
    page2BottomTop: 624,
    page3TopRegular: '모르는건 ',
    page3TopBold: 'AI에게 이야기하세요.',
    page3TopLeft: 35,
    page3TopWidth: 332,
    page3Bottom: '이제 어렵지 않을거에요.',
    page4TopRegular: '',
    page4TopBold: '',
    page4TopSingleLine: null,
    page4TopLine1: '입문자 / 숙련자',
    page4TopLine2: '당신이 누구든',
    page4Bottom: '시작해보세요.',
    nextButton: '다음',
    startButton: '시작하기',
  );
}
