import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/screens/video_projects_placeholder.dart';
import 'package:mixroom/widgets/feedback_sheet.dart';
import 'package:provider/provider.dart';

class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key});

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  static const int _defaultTab = 1; // DAW first

  int _selectedIndex = _defaultTab;
  int? _lastTrackedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
      unawaited(_maybeShowWelcomeOnboarding());
    });
  }

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
    });
  }

  void _trackSelectedTab() {
    final capabilities = PlatformCapabilities.current;
    final hasVideo = capabilities.supportsVideoProjects;
    final trackedIndex = _selectedIndex;

    if (_lastTrackedIndex == trackedIndex) return;
    _lastTrackedIndex = trackedIndex;

    final screenName = switch (trackedIndex) {
      0 => AnalyticsScreenNames.home,
      1 => AnalyticsScreenNames.projectsList,
      2 when hasVideo => 'video_projects',
      _ => AnalyticsScreenNames.settings,
    };

    unawaited(AnalyticsService.instance.trackScreen(screenName));

    final isSettingsScreen = screenName == AnalyticsScreenNames.settings;
    if (!isSettingsScreen) return;

    final entitlementService = context.read<EntitlementService>();
    if (entitlementService.currentTier != PlanTier.free) return;

    unawaited(
      AnalyticsService.instance.trackScreen(
        AnalyticsScreenNames.paywall,
        properties: const <String, Object?>{
          'source': 'manual',
        },
        allowDuplicates: true,
      ),
    );
  }

  Future<void> _maybeShowWelcomeOnboarding() async {
    // Intentionally disabled for now; a redesigned onboarding flow will replace this.
    return;
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = PlatformCapabilities.current;
    final tabs = <_SignedInTab>[
      const _SignedInTab(icon: Icons.music_note_rounded),
      const _SignedInTab(icon: Icons.grid_view_rounded),
      if (capabilities.supportsVideoProjects)
        const _SignedInTab(icon: Icons.video_library_rounded),
      const _SignedInTab(icon: Icons.person_rounded),
    ];
    final pages = <Widget>[
      const _HomeComingSoonScreen(),
      const ProjectsScreen(),
      if (capabilities.supportsVideoProjects)
        const VideoProjectsPlaceholderView(),
      const AccountScreen(showTopBar: false),
    ];

    final maxIndex = tabs.length - 1;
    final clampedSelectedIndex = _selectedIndex.clamp(0, maxIndex);
    if (clampedSelectedIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIndex = clampedSelectedIndex);
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: clampedSelectedIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomDock(
          selectedIndex: clampedSelectedIndex,
          tabs: tabs,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}

class _WelcomeOnboardingStep {
  const _WelcomeOnboardingStep({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    this.detailLines = const <String>[],
    this.promptExamples = const <String>[],
  });

  final String id;
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final List<String> detailLines;
  final List<String> promptExamples;
}

enum _WelcomeOnboardingDecision {
  dismiss,
  startTour,
}

class _WelcomeOnboardingDialog extends StatefulWidget {
  const _WelcomeOnboardingDialog({
    required this.firstName,
  });

  final String firstName;

  @override
  State<_WelcomeOnboardingDialog> createState() =>
      _WelcomeOnboardingDialogState();
}

class _WelcomeOnboardingDialogState extends State<_WelcomeOnboardingDialog> {
  static const List<_WelcomeOnboardingStep> _steps = <_WelcomeOnboardingStep>[
    _WelcomeOnboardingStep(
      id: 'surface',
      eyebrow: 'Welcome',
      title: 'A DAW that stays readable.',
      body:
          'Mixroom keeps the core surface small: arrange clips, shape tracks, and move fast without hunting through giant menus.',
      icon: Icons.space_dashboard_rounded,
      accent: Color(0xFF7FD6FF),
      detailLines: <String>[
        'Timeline for arranging',
        'Transport for play, record, undo, and mix',
        'AI chat for edits, help, and walkthroughs',
      ],
    ),
    _WelcomeOnboardingStep(
      id: 'workflow',
      eyebrow: 'First Session',
      title: 'Your first three moves.',
      body:
          'Start simple. Press play, trim or move a clip, then shape the sound with gain, pan, or effects.',
      icon: Icons.timeline_rounded,
      accent: Color(0xFF9AF4C2),
      detailLines: <String>[
        'Drag clips to arrange',
        'Trim edges to clean starts and endings',
        'Hold gain, pan, or FX controls to automate movement',
      ],
    ),
    _WelcomeOnboardingStep(
      id: 'ai',
      eyebrow: 'Mixroom AI',
      title: 'Ask, edit, or learn in plain language.',
      body:
          'Use AI for mix changes, DAW edits, and quick explanations on the session in front of you. It is there to reduce friction, not to generate finished audio from scratch.',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFFFFC86B),
      detailLines: <String>[
        'Best for editing, mixing, and DAW guidance',
        'Works on the clips and arrangement already in your project',
        'Does not generate songs or rendered audio for you',
      ],
      promptExamples: <String>[
        'Bring the vocal up a little.',
        'Trim the intro by two bars.',
        'Show me where to add plugins.',
      ],
    ),
  ];

  int _stepIndex = 0;

  bool get _isLastStep => _stepIndex >= _steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = _steps[_stepIndex];
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dialogHeight =
              (constraints.maxHeight - 88.0).clamp(380.0, 520.0).toDouble();
          final tightShell = dialogHeight < 420;
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: tightShell ? 18 : 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 356),
                child: SizedBox(
                  height: dialogHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF122643).withValues(alpha: 0.98),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            tightShell ? 16 : 18,
                            tightShell ? 14 : 16,
                            tightShell ? 16 : 18,
                            tightShell ? 12 : 14,
                          ),
                          child: LayoutBuilder(
                            builder: (context, shellConstraints) {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Welcome to Mixroom',
                                              style: (tightShell
                                                      ? theme
                                                          .textTheme.titleLarge
                                                      : theme.textTheme
                                                          .headlineSmall)
                                                  ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${widget.firstName}, here is the shape of the app before you jump in.',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.68),
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.of(context)
                                            .pop(_WelcomeOnboardingDecision
                                                .dismiss),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: tightShell ? 8 : 10),
                                  Row(
                                    children: List<Widget>.generate(
                                      _steps.length,
                                      (index) => AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        curve: Curves.easeOutCubic,
                                        width: index == _stepIndex ? 24 : 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: index == _stepIndex
                                              ? step.accent
                                              : Colors.white
                                                  .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: tightShell ? 10 : 12),
                                  Expanded(
                                    child: _WelcomeOnboardingPanel(
                                      key: ValueKey<String>(step.id),
                                      step: step,
                                    ),
                                  ),
                                  SizedBox(height: tightShell ? 6 : 8),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(
                                          _WelcomeOnboardingDecision.dismiss,
                                        ),
                                        child: const Text(
                                          'Skip',
                                          style:
                                              TextStyle(color: Colors.white70),
                                        ),
                                      ),
                                      if (_stepIndex > 0)
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _stepIndex = (_stepIndex - 1)
                                                  .clamp(0, _steps.length - 1)
                                                  .toInt();
                                            });
                                          },
                                          child: const Text(
                                            'Back',
                                            style: TextStyle(
                                                color: Colors.white70),
                                          ),
                                        ),
                                      FilledButton(
                                        onPressed: () {
                                          if (_isLastStep) {
                                            Navigator.of(context).pop(
                                              _WelcomeOnboardingDecision
                                                  .startTour,
                                            );
                                            return;
                                          }
                                          setState(() {
                                            _stepIndex = (_stepIndex + 1)
                                                .clamp(0, _steps.length - 1)
                                                .toInt();
                                          });
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: step.accent,
                                          foregroundColor:
                                              const Color(0xFF07111F),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: tightShell ? 16 : 18,
                                            vertical: tightShell ? 9 : 11,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          _isLastStep
                                              ? 'Start Quick Tour'
                                              : 'Continue',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WelcomeOnboardingPanel extends StatelessWidget {
  const _WelcomeOnboardingPanel({
    super.key,
    required this.step,
  });

  final _WelcomeOnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF173050),
                const Color(0xFF122744),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.015)),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.018),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 420;
                final short = constraints.maxHeight < 300;
                final iconSize = compact ? 36.0 : 42.0;
                final titleStyle = compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.headlineSmall;
                final bodyStyle = compact
                    ? theme.textTheme.bodySmall
                    : theme.textTheme.bodyMedium;
                return SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: short ? 32.0 : iconSize,
                            height: short ? 32.0 : iconSize,
                            decoration: BoxDecoration(
                              color: step.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              step.icon,
                              color: step.accent,
                              size: short ? 17 : (compact ? 18 : 22),
                            ),
                          ),
                          SizedBox(height: short ? 5 : (compact ? 8 : 10)),
                          Text(
                            step.eyebrow.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: bodyStyle?.copyWith(
                              color: step.accent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              fontSize: short ? 10 : 11,
                            ),
                          ),
                          SizedBox(height: short ? 5 : (compact ? 7 : 8)),
                          Text(
                            step.title,
                            textAlign: TextAlign.center,
                            style: titleStyle?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                            ),
                          ),
                          SizedBox(height: short ? 4 : (compact ? 6 : 7)),
                          Text(
                            step.body,
                            textAlign: TextAlign.center,
                            style: bodyStyle?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                              height: 1.35,
                            ),
                          ),
                          if (step.detailLines.isNotEmpty) ...[
                            SizedBox(height: short ? 7 : (compact ? 10 : 12)),
                            Column(
                              children: step.detailLines
                                  .map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin:
                                                const EdgeInsets.only(top: 5),
                                            decoration: BoxDecoration(
                                              color: step.accent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              line,
                                              style: bodyStyle?.copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.9),
                                                fontWeight: FontWeight.w600,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                          if (step.promptExamples.isNotEmpty) ...[
                            SizedBox(height: short ? 6 : (compact ? 10 : 12)),
                            Text(
                              'Try prompts like:',
                              textAlign: TextAlign.center,
                              style: bodyStyle?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: short ? 7 : (compact ? 10 : 12)),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: short ? 6 : 8,
                              runSpacing: short ? 6 : 8,
                              children: step.promptExamples
                                  .map(
                                    (prompt) => Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal:
                                            short ? 7 : (compact ? 10 : 12),
                                        vertical: short ? 5 : (compact ? 7 : 8),
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '"$prompt"',
                                        style: bodyStyle?.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.92),
                                          fontWeight: FontWeight.w600,
                                          height: 1.2,
                                          fontSize: short ? 10 : null,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                            SizedBox(height: short ? 6 : (compact ? 8 : 10)),
                            Text(
                              'The quick tour will point out the exact areas in the editor next.',
                              textAlign: TextAlign.center,
                              style: bodyStyle?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildSignedInShellWelcomeDialogForTest({
  String firstName = 'Test',
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF0C1A32),
      body: Center(
        child: SizedBox.expand(
          child: _WelcomeOnboardingDialog(firstName: firstName),
        ),
      ),
    ),
  );
}

class _SignedInTab {
  const _SignedInTab({
    required this.icon,
  });

  final IconData icon;
}

class _BottomDock extends StatelessWidget {
  static const double _barHeight = 48;
  static const double _iconSize = 22;

  const _BottomDock({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_SignedInTab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1F3A),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final tab = tabs[index];
          final active = index == selectedIndex;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: Container(
                alignment: Alignment.center,
                height: _barHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: _iconSize,
                      color: active ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(height: 5),
                    if (active)
                      Container(
                        width: 18,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _HomeComingSoonScreen extends StatelessWidget {
  const _HomeComingSoonScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF0C1A32),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
            decoration: BoxDecoration(
              color: const Color(0xFF142845),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white70,
                  size: 52,
                ),
                const SizedBox(height: 14),
                Text(
                  L10n.translate(context, 'Home'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.translate(context, 'Audio platform coming soon.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      final authService = context.read<AuthService>();
                      final draft = await showFeedbackSheet(
                        context,
                        source: FeedbackSource.home,
                      );
                      if (draft == null || !context.mounted) return;
                      try {
                        await FeedbackService.instance.submit(
                          auth: authService,
                          request: FeedbackSubmissionRequest(
                            category: draft.category,
                            source: FeedbackSource.home,
                            message: draft.message,
                            allowEmailContact: draft.allowEmailContact,
                          ),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you for your submission!'),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceFirst('Bad state: ', ''),
                            ),
                          ),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16)),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.forum_outlined),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            L10n.translate(
                              context,
                              'Share feedback or report a bug',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
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
