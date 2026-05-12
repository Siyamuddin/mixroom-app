import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/app_update_prompt_service.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/remote_announcement_manager.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/app_update_policy.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/remote_announcement_widgets.dart';
import 'package:mixroom/widgets/remote_welcome_onboarding_screen.dart';
import 'package:mixroom/widgets/soft_update_dialog.dart';
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

  MixroomMainTab _selectedTab = MixroomMainTab.projects;
  MixroomMainTab? _lastTrackedTab;
  int _scrollToTopSignal = 0;
  bool _creatingProject = false;
  final AppUpdatePromptService _appUpdatePromptService =
      AppUpdatePromptService();
  final RemoteAnnouncementManager _remoteAnnouncementManager =
      RemoteAnnouncementManager();
  bool _welcomeCheckStarted = false;
  bool _welcomeDialogOpen = false;
  bool _appUpdateDialogOpen = false;
  RemoteAnnouncement? _activeAnnouncement;
  bool _announcementModalOpen = false;
  String? _trackedAnnouncementBannerVersion;
  AppUserService? _welcomeAppUserService;
  StreamSubscription<String>? _educationInviteLinkSub;
  final Set<String> _handledEducationInviteTokens = <String>{};
  bool _educationInviteAcceptBusy = false;

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
    _educationInviteLinkSub = OpenMixroomService.urlStream.listen(
      (url) => unawaited(_handleIncomingEducationInviteUrl(url)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
      final initialUrl = OpenMixroomService.consumeInitialUrlOnce();
      if (initialUrl != null && initialUrl.isNotEmpty) {
        unawaited(_handleIncomingEducationInviteUrl(initialUrl));
      }
      unawaited(_initializeEntryContent());
    });
  }

  @override
  void dispose() {
    _educationInviteLinkSub?.cancel();
    _welcomeAppUserService?.removeListener(_handleAppUserChanged);
    super.dispose();
  }

  Future<void> _handleIncomingEducationInviteUrl(String url) async {
    final token = _educationInviteTokenFromUrl(url);
    if (token == null ||
        token.isEmpty ||
        _educationInviteAcceptBusy ||
        _handledEducationInviteTokens.contains(token)) {
      return;
    }
    OpenMixroomService.clearInitialUrl(url);
    _educationInviteAcceptBusy = true;
    _handledEducationInviteTokens.add(token);
    try {
      await context.read<EntitlementService>().acceptEducationInvite(
            inviteToken: token,
          );
      if (!mounted) return;
      setState(() {
        _selectedTab = MixroomMainTab.account;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Education student seat activated.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      _handledEducationInviteTokens.remove(token);
      if (!mounted) return;
      setState(() {
        _selectedTab = MixroomMainTab.account;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not accept this education invite. Open Plan & Billing to try again.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    } finally {
      _educationInviteAcceptBusy = false;
    }
  }

  String? _educationInviteTokenFromUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final invite = uri.queryParameters['invite']?.trim();
      if (invite != null && invite.isNotEmpty) return invite;
      final segments = uri.pathSegments;
      final inviteIndex = segments.indexOf('invites');
      if (inviteIndex >= 0 && inviteIndex + 1 < segments.length) {
        final candidate = segments[inviteIndex + 1].trim();
        if (candidate.isNotEmpty) return candidate;
      }
    }
    return raw.replaceFirst('invite=', '').trim();
  }

  void _handleAppUserChanged() {
    if (!mounted ||
        _welcomeDialogOpen ||
        _appUpdateDialogOpen ||
        _announcementModalOpen) {
      return;
    }
    unawaited(_initializeEntryContent());
  }

  Future<void> _initializeEntryContent() async {
    await _maybePresentRemoteWelcome();
    if (!mounted) return;
    await _maybePresentAppUpdatePrompt();
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

  Future<void> _maybePresentAppUpdatePrompt() async {
    if (_welcomeDialogOpen || _appUpdateDialogOpen || _announcementModalOpen) {
      return;
    }

    final decision = await _appUpdatePromptService.evaluate();
    if (!mounted || decision == null || !decision.isUpdateAvailable) {
      return;
    }

    _appUpdateDialogOpen = true;
    await _appUpdatePromptService.markPromptShown(decision);
    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.appUpdatePromptShown(
          promptType: decision.type.name,
          currentVersion: decision.currentVersion,
          latestVersion: decision.latestVersion,
        ),
      ),
    );

    if (!mounted) {
      _appUpdateDialogOpen = false;
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: decision.type != AppUpdatePromptType.force,
      builder: (_) => SoftUpdateDialog(
        decision: decision,
        onUpdatePressed: () => rootNavigator.pop('update'),
        onLaterPressed: () => rootNavigator.pop('later'),
      ),
    );
    _appUpdateDialogOpen = false;
    if (!mounted) return;
    await _handleAppUpdateAction(decision, action ?? 'dismissed');
  }

  Future<void> _handleAppUpdateAction(
    AppUpdateDecision decision,
    String action,
  ) async {
    if (action == 'update') {
      final uri = Uri.tryParse(decision.storeUrl.trim());
      if (uri == null) {
        showAppSnackBar(
          context,
          L10n.translate(context, 'Update link is not configured yet.'),
        );
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.appUpdatePromptInteracted(
              action: 'update_invalid_url',
              promptType: decision.type.name,
              currentVersion: decision.currentVersion,
              latestVersion: decision.latestVersion,
              errorCode: 'invalid_url',
            ),
          ),
        );
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) {
        showAppSnackBar(
          context,
          L10n.translate(context, 'Unable to open the store right now.'),
        );
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.appUpdatePromptInteracted(
              action: 'update_launch_failed',
              promptType: decision.type.name,
              currentVersion: decision.currentVersion,
              latestVersion: decision.latestVersion,
              errorCode: 'launch_failed',
            ),
          ),
        );
        return;
      }

      unawaited(
        AnalyticsService.instance.track(
          AnalyticsEvents.appUpdatePromptInteracted(
            action: 'update',
            promptType: decision.type.name,
            currentVersion: decision.currentVersion,
            latestVersion: decision.latestVersion,
          ),
        ),
      );
      return;
    }

    unawaited(
      AnalyticsService.instance.track(
        AnalyticsEvents.appUpdatePromptInteracted(
          action: action,
          promptType: decision.type.name,
          currentVersion: decision.currentVersion,
          latestVersion: decision.latestVersion,
        ),
      ),
    );
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
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _scrollToTopSignal++;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedTab = tab;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _trackSelectedTab();
    });
  }

  void _openSubscriptionAccountTab() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    _setTab(MixroomMainTab.account);
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
            mode: 'Pro',
            onUpgradeRequested: _openSubscriptionAccountTab,
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

  Widget _buildPage(MixroomMainTab tab) {
    switch (tab) {
      case MixroomMainTab.home:
        return _HomeTab(
          scrollToTopSignal: _scrollToTopSignal,
          onSubmitFeedback: _submitHomeFeedback,
        );
      case MixroomMainTab.platform:
        return _PlatformTab(scrollToTopSignal: _scrollToTopSignal);
      case MixroomMainTab.projects:
        return ProjectsScreen(
          scrollToTopSignal: _scrollToTopSignal,
          onUpgradeRequested: _openSubscriptionAccountTab,
        );
      case MixroomMainTab.account:
        return AccountScreen(
          showTopBar: false,
          scrollToTopSignal: _scrollToTopSignal,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final useDesktopRail = mixroomUsesDesktopRailNavigation;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        children: [
          if (useDesktopRail)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    right: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
                      child: MixroomMainSideRail(
                        selectedTab: _selectedTab,
                        onTabSelected: _setTab,
                        onAddTap: _createMusicProject,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 28),
                            child: _buildPage(_selectedTab),
                          ),
                        ),
                        if (_activeAnnouncement != null &&
                            _activeAnnouncement!.showsBanner)
                          Positioned(
                            left: 0,
                            right: 28,
                            top: MediaQuery.of(context).padding.top + 10,
                            child: SafeArea(
                              bottom: false,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 980),
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
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
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
                addMenuOpen: false,
                onAddTap: _createMusicProject,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.scrollToTopSignal,
    required this.onSubmitFeedback,
  });

  final int scrollToTopSignal;
  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  ) onSubmitFeedback;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal) {
      _scrollToTop();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

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
              controller: _scrollController,
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
                  onSubmit: widget.onSubmitFeedback,
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

class _PlatformTab extends StatefulWidget {
  const _PlatformTab({
    required this.scrollToTopSignal,
  });

  final int scrollToTopSignal;

  @override
  State<_PlatformTab> createState() => _PlatformTabState();
}

class _PlatformTabState extends State<_PlatformTab> {
  late final Future<AppVersionStatus?> _versionStatusFuture;

  @override
  void initState() {
    super.initState();
    _versionStatusFuture = AppUpdatePromptService().getVersionStatus();
  }

  @override
  void didUpdateWidget(covariant _PlatformTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _openStore(String storeUrl) async {
    final uri = Uri.tryParse(storeUrl.trim());
    if (uri == null) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Update link is not configured yet.'),
      );
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    showAppSnackBar(
      context,
      L10n.translate(context, 'Unable to open the store right now.'),
    );
  }

  String _storeCtaLabel(BuildContext context) {
    if (kIsWeb) {
      return L10n.translate(context, 'Open Store');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return L10n.translate(context, 'Open in App Store');
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return L10n.translate(context, 'Open Store');
    }
    return L10n.translate(context, 'Open in Play Store');
  }

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
                        child: const MixroomShellBrandMark(width: 76),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: midGroupTop,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MixroomShellWordmark(
                            width: 162,
                            alignment: Alignment.center,
                          ),
                          const SizedBox(height: 22),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: FutureBuilder<AppVersionStatus?>(
                              future: _versionStatusFuture,
                              builder: (context, snapshot) {
                                final status = snapshot.data;
                                final currentVersion =
                                    status?.currentVersion.trim() ?? '';
                                final canUpdate = status != null &&
                                    status.isUpdateAvailable &&
                                    status.hasStoreUrl;
                                final statusLabel = switch (status) {
                                  null => L10n.translate(
                                      context,
                                      'Version unavailable',
                                    ),
                                  _ when status.isUpdateAvailable =>
                                    L10n.translate(
                                      context,
                                      'A newer version is ready!',
                                    ),
                                  _ when status.hasLatestVersion =>
                                    L10n.translate(
                                      context,
                                      'Latest version installed',
                                    ),
                                  _ => '',
                                };

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      L10n.translate(
                                        context,
                                        'App Version',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 18 / 13,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      currentVersion.isEmpty
                                          ? '...'
                                          : currentVersion,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFFF4F4F4),
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        height: 34 / 30,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    if (statusLabel.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        statusLabel,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Pretendard',
                                          color:
                                              status?.isUpdateAvailable == true
                                                  ? const Color(0xFFFFE4A8)
                                                  : Colors.white.withValues(
                                                      alpha: 0.78,
                                                    ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          height: 18 / 14,
                                        ),
                                      ),
                                    ],
                                    if (canUpdate) ...[
                                      const SizedBox(height: 12),
                                      FilledButton(
                                        onPressed: () =>
                                            _openStore(status.storeUrl),
                                        style: FilledButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFFF4F4F4),
                                          backgroundColor: const Color.fromRGBO(
                                            118,
                                            170,
                                            220,
                                            0.26,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          side: BorderSide(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            width: 0.8,
                                          ),
                                          elevation: 0,
                                          textStyle: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            height: 18 / 13,
                                          ),
                                        ),
                                        child: Text(
                                          _storeCtaLabel(context),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
