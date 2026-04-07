import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/remote_announcement_manager.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/remote_announcement_widgets.dart';
import 'package:mixroom/widgets/remote_welcome_onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key});

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  static const String _welcomeCampaignVersion = 'figma_onboarding_v1';
  static const String _welcomeMediaType = 'local_4step';
  static const String _welcomeMediaVersion = '2026-03-30';

  MixroomMainTab _selectedTab = MixroomMainTab.home;
  MixroomMainTab? _lastTrackedTab;
  bool _showAddMenu = false;
  bool _creatingProject = false;
  final RemoteAnnouncementManager _remoteAnnouncementManager =
      RemoteAnnouncementManager();
  bool _welcomeCheckStarted = false;
  bool _welcomeDialogOpen = false;
  RemoteAnnouncement? _activeAnnouncement;
  bool _announcementModalOpen = false;
  String? _trackedAnnouncementBannerVersion;
  AppUserService? _welcomeAppUserService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appUser = context.read<AppUserService>();
    if (identical(_welcomeAppUserService, appUser)) {
      return;
    }
    _welcomeAppUserService?.removeListener(_handleAppUserChanged);
    _welcomeAppUserService = appUser;
    appUser.addListener(_handleAppUserChanged);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
      unawaited(_initializeRemoteEntryContent());
    });
  }

  @override
  void dispose() {
    _welcomeAppUserService?.removeListener(_handleAppUserChanged);
    super.dispose();
  }

  void _handleAppUserChanged() {
    if (!mounted || _welcomeDialogOpen || _announcementModalOpen) {
      return;
    }
    unawaited(_initializeRemoteEntryContent());
  }

  Future<void> _initializeRemoteEntryContent() async {
    await _maybePresentRemoteWelcome();
    if (!mounted) return;
    await _refreshRemoteAnnouncementState(presentModal: true);
  }

  Future<void> _maybePresentRemoteWelcome() async {
    if (_welcomeCheckStarted || _welcomeDialogOpen) return;

    final appUser = context.read<AppUserService>();
    final current = appUser.current;
    if (current == null) {
      return;
    }

    final userId = current.userId;
    final hasSeenLocally =
        await appUser.hasSeenWelcomeOnboardingLocally(userId);
    if (!mounted) return;

    final refreshed = appUser.current;
    if (refreshed == null || refreshed.userId != userId) {
      return;
    }

    if (refreshed.hasSeenWelcomeOnboarding || hasSeenLocally) {
      return;
    }
    _welcomeCheckStarted = true;

    _welcomeDialogOpen = true;
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.welcomeOnboardingShown(
          campaignVersion: _welcomeCampaignVersion,
          mediaType: _welcomeMediaType,
          mediaVersion: _welcomeMediaVersion,
        ),
      ),
    );

    final action =
        await Navigator.of(context, rootNavigator: true).push<String>(
      PageRouteBuilder<String>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => RemoteWelcomeOnboardingScreen(
          onCompleted: () =>
              Navigator.of(context, rootNavigator: true).pop('primary'),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    _welcomeDialogOpen = false;
    if (!mounted || action != 'primary') {
      return;
    }

    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.welcomeOnboardingCompleted(
          campaignVersion: _welcomeCampaignVersion,
          mediaType: _welcomeMediaType,
          mediaVersion: _welcomeMediaVersion,
          action: 'primary',
        ),
      ),
    );
    await appUser.stageWelcomeOnboardingSeen();
  }

  Future<void> _refreshRemoteAnnouncementState({
    bool presentModal = false,
  }) async {
    if (_welcomeDialogOpen) return;
    final appUser = context.read<AppUserService>();
    final current = appUser.current;
    if (current == null) {
      return;
    }

    await _remoteAnnouncementManager.refreshInBackground();
    if (!mounted) return;
    final announcement =
        await _remoteAnnouncementManager.installedAnnouncement();
    if (!mounted) return;

    if (announcement == null ||
        !_remoteAnnouncementManager.isEligibleForUser(
          announcement: announcement,
          accountCreatedAtUtc: current.createdAt.toUtc(),
        )) {
      if (_activeAnnouncement != null) {
        setState(() {
          _activeAnnouncement = null;
          _trackedAnnouncementBannerVersion = null;
        });
      }
      return;
    }

    final showBanner =
        await _remoteAnnouncementManager.shouldShowBanner(announcement);
    final showModal = presentModal
        ? await _remoteAnnouncementManager.shouldShowModal(announcement)
        : false;
    if (!mounted) return;

    if (!showBanner && !showModal) {
      if (_activeAnnouncement != null) {
        setState(() {
          _activeAnnouncement = null;
          _trackedAnnouncementBannerVersion = null;
        });
      }
      return;
    }

    setState(() {
      _activeAnnouncement = announcement;
      if (!showBanner) {
        _trackedAnnouncementBannerVersion = null;
      }
    });

    if (showBanner &&
        _trackedAnnouncementBannerVersion != announcement.announcementVersion) {
      _trackedAnnouncementBannerVersion = announcement.announcementVersion;
      _remoteAnnouncementManager.trackShown(
        announcement: announcement,
        presentationMode: 'banner',
      );
    }

    if (showModal) {
      await _presentRemoteAnnouncementModal(announcement);
    }
  }

  Future<void> _presentRemoteAnnouncementModal(
    RemoteAnnouncement announcement,
  ) async {
    if (_announcementModalOpen || _welcomeDialogOpen || !mounted) {
      return;
    }
    _announcementModalOpen = true;
    await _remoteAnnouncementManager.markModalSeen(announcement);
    if (!mounted) {
      _announcementModalOpen = false;
      return;
    }
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    _remoteAnnouncementManager.trackShown(
      announcement: announcement,
      presentationMode: 'modal',
    );
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => RemoteAnnouncementDialog(
        announcement: announcement,
        onPrimaryPressed: () => rootNavigator.pop('primary'),
        onSecondaryPressed: () => rootNavigator.pop('secondary'),
      ),
    );
    _announcementModalOpen = false;
    if (!mounted) return;
    await _handleAnnouncementAction(
      announcement: announcement,
      action: action ?? 'dismissed',
    );
  }

  Future<void> _handleAnnouncementAction({
    required RemoteAnnouncement announcement,
    required String action,
  }) async {
    if (action == 'primary') {
      final url = announcement.primaryActionUrl.trim();
      if (url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!launched) {
            if (mounted) {
              showAppSnackBar(
                context,
                L10n.translate(context, 'Unable to open link right now.'),
              );
            }
            await _remoteAnnouncementManager.markDismissed(
              announcement: announcement,
              action: 'primary_launch_failed',
              errorCode: 'launch_failed',
            );
          } else {
            await _remoteAnnouncementManager.markDismissed(
              announcement: announcement,
              action: 'primary',
            );
          }
        } else {
          await _remoteAnnouncementManager.markDismissed(
            announcement: announcement,
            action: 'primary_invalid_url',
            errorCode: 'invalid_url',
          );
        }
      } else {
        await _remoteAnnouncementManager.markDismissed(
          announcement: announcement,
          action: 'primary',
        );
      }
    } else {
      await _remoteAnnouncementManager.markDismissed(
        announcement: announcement,
        action: action,
      );
    }
    if (!mounted) return;
    setState(() {
      _activeAnnouncement = null;
      _trackedAnnouncementBannerVersion = null;
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
      ProjectManager.notifyProjectLibraryChanged();
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
    context.watch<LocaleProvider>();
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPage(_selectedTab)),
          if (_activeAnnouncement != null && _activeAnnouncement!.showsBanner)
            Positioned(
              left: 18,
              right: 18,
              top: MediaQuery.of(context).padding.top + 10,
              child: SafeArea(
                bottom: false,
                child: RemoteAnnouncementBanner(
                  announcement: _activeAnnouncement!,
                  onPrimaryTap: () {
                    unawaited(
                      _handleAnnouncementAction(
                        announcement: _activeAnnouncement!,
                        action: 'primary',
                      ),
                    );
                  },
                  onDismissTap: () {
                    unawaited(
                      _handleAnnouncementAction(
                        announcement: _activeAnnouncement!,
                        action: 'dismissed',
                      ),
                    );
                  },
                ),
              ),
            ),
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = mixroomShellBottomPadding(context) +
        (keyboardInset > 0 ? keyboardInset + 16 : 0);
    return Stack(
      children: [
        const Positioned.fill(child: MixroomShellBackground()),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                27,
                0,
                27,
                bottomPadding,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 348),
                child: MixroomInlineFeedbackComposer(
                  onSubmit: onSubmitFeedback,
                  showBetaNotice: true,
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
