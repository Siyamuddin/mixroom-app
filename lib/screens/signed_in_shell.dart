import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:provider/provider.dart';

class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key});

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  MixroomMainTab _selectedTab = MixroomMainTab.home;
  MixroomMainTab? _lastTrackedTab;
  bool _showAddMenu = false;
  bool _creatingProject = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
    });
  }

  void _trackSelectedTab() {
    if (_lastTrackedTab == _selectedTab) return;
    _lastTrackedTab = _selectedTab;
    final screenName = switch (_selectedTab) {
      MixroomMainTab.home => AnalyticsScreenNames.home,
      MixroomMainTab.platform => 'platform',
      MixroomMainTab.projects => AnalyticsScreenNames.projectsList,
      MixroomMainTab.account => AnalyticsScreenNames.settings,
    };
    unawaited(AnalyticsService.instance.trackScreen(screenName));
  }

  void _setTab(MixroomMainTab tab) {
    if (_selectedTab == tab) {
      setState(() => _showAddMenu = false);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedTab = tab;
      _showAddMenu = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
    });
  }

  Future<void> _submitHomeFeedback(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  ) async {
    final auth = context.read<AuthService>();
    await FeedbackService.instance.submit(
      auth: auth,
      request: FeedbackSubmissionRequest(
        category: category,
        source: FeedbackSource.home,
        message: message,
        allowEmailContact: allowEmailContact,
      ),
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      L10n.translate(context, 'Thank you for your submission!'),
    );
  }

  Future<void> _createMusicProject() async {
    if (_creatingProject) return;
    if (!await ProjectManager.canCreateNew()) {
      if (!mounted) return;
      showAppMessageDialog(
        context: context,
        title: L10n.translate(context, 'Project limit reached'),
        message: L10n.translate(
          context,
          'Delete a project to create or import a new one.',
        ),
        buttonLabel: L10n.translate(context, 'OK'),
        icon: Icons.folder_off_outlined,
      );
      return;
    }
    if (!mounted) return;
    _creatingProject = true;
    setState(() => _showAddMenu = false);
    final isProEntitled = context
        .read<EntitlementService>()
        .canUseCapability(SubscriptionCapability.proEditor);
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Creating project…'),
    );
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final dir = await ProjectManager.createNewProjectDir(
        name: L10n.translate(context, 'Untitled Project'),
      );
      final projectId = await ProjectManager.ensureProjectId(dir);
      unawaited(
        AnalyticsService.instance.track(
          AnalyticsEvents.projectCreated(
            projectId: projectId,
            initialTrackCount: 0,
          ),
        ),
      );
      await AnalyticsService.instance.trackFirstProjectCreated(
        projectId: projectId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            projectDir: dir,
            mode: isProEntitled ? 'Pro' : 'Basic',
            isProEntitled: isProEntitled,
          ),
        ),
      );
    } finally {
      _creatingProject = false;
      if (mounted) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
    }
  }

  void _showVideoProjectPlaceholder() {
    setState(() => _showAddMenu = false);
    showAppSnackBar(
      context,
      L10n.translate(context, 'Video projects are coming soon.'),
    );
  }

  Widget _buildPage(MixroomMainTab tab) {
    switch (tab) {
      case MixroomMainTab.home:
        return _HomeTab(onSubmitFeedback: _submitHomeFeedback);
      case MixroomMainTab.platform:
        return const _PlatformTab();
      case MixroomMainTab.projects:
        return const ProjectsScreen();
      case MixroomMainTab.account:
        return const AccountScreen(showTopBar: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPage(_selectedTab)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MixroomMainBottomDock(
              selectedTab: _selectedTab,
              onTabSelected: _setTab,
              addMenuOpen: _showAddMenu,
              onAddTap: () {
                setState(() => _showAddMenu = !_showAddMenu);
              },
            ),
          ),
          Positioned(
            left: 27,
            right: 27,
            bottom: mixroomShellDockBottomInset(context) +
                kMixroomMainDockHeight +
                12,
            child: IgnorePointer(
              ignoring: !_showAddMenu,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                opacity: _showAddMenu ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  offset: _showAddMenu ? Offset.zero : const Offset(0, 0.18),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: _showAddMenu ? 0.94 : 1.0,
                      end: _showAddMenu ? 1.0 : 0.94,
                    ),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        alignment: Alignment.bottomCenter,
                        child: child,
                      );
                    },
                    child: _AddProjectMenu(
                      onCreateMusicProject: _createMusicProject,
                      onCreateVideoProject: _showVideoProjectPlaceholder,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.onSubmitFeedback,
  });

  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  ) onSubmitFeedback;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: MixroomShellBackground()),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                27,
                0,
                27,
                mixroomShellBottomPadding(context),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 348),
                child: MixroomInlineFeedbackComposer(
                  onSubmit: onSubmitFeedback,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlatformTab extends StatelessWidget {
  const _PlatformTab();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: MixroomShellBackground()),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final midGroupTop = constraints.maxHeight * 0.41;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: mixroomShellBottomPadding(context),
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Image.asset(
                          kMixroomShellBrandMarkAsset,
                          width: 76,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: midGroupTop,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            kMixroomShellWordmarkAsset,
                            width: 162,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                          const SizedBox(height: 12),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 18,
                                height: 22 / 18,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${L10n.translate(context, 'Platform')} ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: L10n.translate(context, 'Coming Soon'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddProjectMenu extends StatelessWidget {
  const _AddProjectMenu({
    required this.onCreateMusicProject,
    required this.onCreateVideoProject,
  });

  final VoidCallback onCreateMusicProject;
  final VoidCallback onCreateVideoProject;

  @override
  Widget build(BuildContext context) {
    return MixroomShellSurface(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: const Color.fromRGBO(151, 184, 216, 0.58),
      strong: true,
      child: Row(
        children: [
          Expanded(
            child: _AddProjectMenuAction(
              label: L10n.translate(context, 'New Music Project'),
              icon: Icons.music_note_rounded,
              onTap: onCreateMusicProject,
            ),
          ),
          Container(
            width: 1,
            height: 54,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          Expanded(
            child: _AddProjectMenuAction(
              label: L10n.translate(context, 'New Video Project'),
              icon: Icons.video_library_outlined,
              onTap: onCreateVideoProject,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddProjectMenuAction extends StatelessWidget {
  const _AddProjectMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 13.5,
                    height: 1.15,
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
