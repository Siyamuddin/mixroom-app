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
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/remote_announcement_manager.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/app_update_policy.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/account_subscription_surface.dart';
import 'package:mixroom/widgets/remote_announcement_widgets.dart';
import 'package:mixroom/widgets/remote_welcome_onboarding_screen.dart';
import 'package:mixroom/widgets/soft_update_dialog.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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
    final hasSeenLocally = await appUser.hasSeenWelcomeOnboardingLocally(
      userId,
    );
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

    final action = await Navigator.of(context, rootNavigator: true)
        .push<String>(
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
    final announcement = await _remoteAnnouncementManager
        .installedAnnouncement();
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

    final showBanner = await _remoteAnnouncementManager.shouldShowBanner(
      announcement,
    );
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

  Future<void> _showRailInfo(double topInset) async {
    final size = MediaQuery.sizeOf(context);
    const popupWidth = 310.0;
    const popupHeight = 362.0;
    await showMenu<void>(
      context: context,
      color: const Color(0xFF0D1621),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      constraints: const BoxConstraints.tightFor(width: popupWidth),
      position: RelativeRect.fromLTRB(
        kMixroomDesktopRailWidth - 7,
        topInset,
        (size.width - kMixroomDesktopRailWidth - popupWidth + 7).clamp(
          8.0,
          double.infinity,
        ),
        (size.height - topInset - popupHeight).clamp(8.0, double.infinity),
      ),
      items: [
        _RailInfoPopupEntry(
          child: _MixroomRailInfoPopover(
            updateService: _appUpdatePromptService,
          ),
        ),
      ],
    );
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
    final entitlementService = context.read<EntitlementService>();
    final projectLimit = entitlementService.isEnforcementEnabled
        ? SubscriptionLimits.localProjectLimitFor(
            entitlementService.entitlement,
          )
        : SubscriptionLimits.paidLocalProjects;
    if (!await ProjectManager.canCreateNew(maxProjects: projectLimit)) {
      if (!mounted) return;
      if (projectLimit == SubscriptionLimits.freeLocalProjects) {
        unawaited(
          showAppUpgradeDialog(
            context: context,
            title: 'Upgrade for more projects',
            message:
                'Free includes 10 local projects. Export or delete one, or upgrade for more.',
            icon: Icons.folder_off_outlined,
            onUpgrade: _openSubscriptionAccountTab,
          ),
        );
        return;
      }
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
          onOpenAccountPlans: _openSubscriptionAccountTab,
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
    final useSideRail = mixroomUsesSideRailNavigation(context);
    final desktopRailTopInset = mixroomUsesDesktopRailNavigation ? 56.0 : 22.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        children: [
          if (useSideRail)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    top: false,
                    right: false,
                    child: MixroomMainSideRail(
                      selectedTab: _selectedTab,
                      onTabSelected: _setTab,
                      onAddTap: _createMusicProject,
                      onBrandTap: () => _showRailInfo(desktopRailTopInset),
                      topContentInset: desktopRailTopInset,
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 980,
                                  ),
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
            ),
          if (!useSideRail) ...[
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

class _RailInfoPopupEntry extends PopupMenuEntry<void> {
  const _RailInfoPopupEntry({required this.child});

  final Widget child;

  @override
  double get height => 362;

  @override
  bool represents(void value) => false;

  @override
  State<_RailInfoPopupEntry> createState() => _RailInfoPopupEntryState();
}

class _RailInfoPopupEntryState extends State<_RailInfoPopupEntry> {
  @override
  Widget build(BuildContext context) => widget.child;
}

class _MixroomRailInfoPopover extends StatefulWidget {
  const _MixroomRailInfoPopover({required this.updateService});

  final AppUpdatePromptService updateService;

  @override
  State<_MixroomRailInfoPopover> createState() =>
      _MixroomRailInfoPopoverState();
}

class _MixroomRailInfoPopoverState extends State<_MixroomRailInfoPopover> {
  late Future<AppVersionStatus?> _versionFuture;

  @override
  void initState() {
    super.initState();
    _versionFuture = widget.updateService.getVersionStatus();
  }

  void _checkAgain() {
    setState(() {
      _versionFuture = widget.updateService.getVersionStatus();
    });
  }

  Future<void> _openExternal(String rawUrl) async {
    Navigator.of(context).pop();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1621),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF31465D), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: const MixroomShellShortLogo(),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mixroom',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFF4F4F4),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'AI-assisted music production',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Close',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.055),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FutureBuilder<AppVersionStatus?>(
            future: _versionFuture,
            builder: (context, snapshot) {
              final status = snapshot.data;
              final loading = snapshot.connectionState != ConnectionState.done;
              final version = status?.currentVersion.trim() ?? '';
              final canUpdate = status?.isUpdateAvailable == true;
              final statusText = loading
                  ? 'Checking for updates…'
                  : canUpdate
                  ? 'Version ${status!.latestVersion} is available'
                  : status == null
                  ? 'Version information unavailable'
                  : 'You’re up to date';
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          version.isEmpty ? 'App version' : 'Version $version',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (canUpdate)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF74A1F5),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: canUpdate
                            ? const Color(0xFFBBD5FF)
                            : Colors.white.withValues(alpha: 0.56),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _RailPopoverButton(
                      label: canUpdate ? 'Update Mixroom' : 'Check for updates',
                      icon: canUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.refresh_rounded,
                      emphasized: canUpdate,
                      busy: loading,
                      onTap: loading
                          ? null
                          : canUpdate && status!.hasStoreUrl
                          ? () => _openExternal(status.storeUrl)
                          : _checkAgain,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _RailLinkRow(
            icon: Icons.language_rounded,
            title: 'Mixroom website',
            subtitle: 'mixroom.ai',
            onTap: () => _openExternal('https://mixroom.ai'),
          ),
          const SizedBox(height: 4),
          _RailLinkRow(
            icon: Icons.camera_alt_outlined,
            title: 'Instagram',
            subtitle: '@mixroom.ai',
            onTap: () => _openExternal('https://instagram.com/mixroom.ai'),
          ),
        ],
      ),
    );
  }
}

class _RailPopoverButton extends StatelessWidget {
  const _RailPopoverButton({
    required this.label,
    required this.icon,
    required this.emphasized,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool emphasized;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: emphasized
                ? const Color(0xFF4D83C5)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: emphasized
                  ? const Color(0xFF76A7E2)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                )
              else
                Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailLinkRow extends StatelessWidget {
  const _RailLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.72)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFF4F4F4),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Colors.white.withValues(alpha: 0.46),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.scrollToTopSignal,
    required this.onSubmitFeedback,
    required this.onOpenAccountPlans,
  });

  final int scrollToTopSignal;
  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  )
  onSubmitFeedback;
  final VoidCallback onOpenAccountPlans;

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
    final bottomPadding =
        mixroomShellBottomPadding(context) +
        (keyboardInset > 0 ? keyboardInset + 16 : 0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF070B1C))),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final sidePadding = wide ? 48.0 : 22.0;
              final heroHeight = (constraints.maxHeight * 0.9).clamp(
                600.0,
                880.0,
              );
              return SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Column(
                  children: [
                    _HomeHero(
                      height: heroHeight,
                      scrollController: _scrollController,
                      reduceMotion: reduceMotion,
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight * 0.58,
                      reduceMotion: reduceMotion,
                      child: _HomeIntroSection(
                        wide: wide,
                        horizontalPadding: sidePadding,
                      ),
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight + 420,
                      reduceMotion: reduceMotion,
                      child: _HomeDeviceSection(
                        wide: wide,
                        horizontalPadding: sidePadding,
                      ),
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight + (wide ? 1080 : 1510),
                      reduceMotion: reduceMotion,
                      child: _HomeCollaborationSection(
                        horizontalPadding: sidePadding,
                      ),
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight + (wide ? 1640 : 2050),
                      reduceMotion: reduceMotion,
                      child: _HomeAiSection(horizontalPadding: sidePadding),
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight + (wide ? 2140 : 2580),
                      reduceMotion: reduceMotion,
                      child: _HomeProductMotionSection(
                        horizontalPadding: sidePadding,
                      ),
                    ),
                    _HomeReveal(
                      controller: _scrollController,
                      revealAt: heroHeight + (wide ? 2700 : 3180),
                      reduceMotion: reduceMotion,
                      child: _HomeAccountPlansSection(
                        horizontalPadding: sidePadding,
                        onOpenAccountPlans: widget.onOpenAccountPlans,
                      ),
                    ),
                    _HomeFeedbackSection(
                      horizontalPadding: sidePadding,
                      bottomPadding: bottomPadding,
                      viewportHeight: constraints.maxHeight,
                      onSubmit: widget.onSubmitFeedback,
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

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.height,
    required this.scrollController,
    required this.reduceMotion,
  });

  final double height;
  final ScrollController scrollController;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.88,
                  colors: [
                    const Color(0xFF173166).withValues(alpha: 0.44),
                    const Color(0xFF070B1C),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 210,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.72, 1],
                    colors: [
                      Color(0x00070B1C),
                      Color(0xE6070B1C),
                      Color(0xFF070B1C),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 66),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.92 + value * 0.08,
                        child: child,
                      ),
                    ),
                    child: const MixroomShellBrandMark(
                      width: 82,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 64),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: scrollController,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: Image.asset(
                            'assets/app_shell/home_hero.webp',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        builder: (context, child) {
                          final offset = scrollController.hasClients
                              ? scrollController.offset
                              : 0.0;
                          final progress = (offset / height).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: reduceMotion ? 1 : 1 - progress * 0.34,
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                reduceMotion ? 0 : offset * 0.07,
                              ),
                              child: child,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                    duration: const Duration(milliseconds: 850),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 18 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Made anywhere. Heard everywhere.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            height: 1.18,
                            letterSpacing: -0.8,
                          ),
                        ),
                        SizedBox(height: 14),
                        SizedBox(
                          width: 660,
                          child: Text(
                            'Mixroom is a cross-platform DAW that moves seamlessly from mobile to desktop. Create together in the cloud, with your AI Co-producer always within reach.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Color(0xB8FFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            child: _HomeScrollCue(reduceMotion: reduceMotion),
          ),
        ],
      ),
    );
  }
}

class _HomeScrollCue extends StatefulWidget {
  const _HomeScrollCue({required this.reduceMotion});
  final bool reduceMotion;

  @override
  State<_HomeScrollCue> createState() => _HomeScrollCueState();
}

class _HomeScrollCueState extends State<_HomeScrollCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (!widget.reduceMotion) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, widget.reduceMotion ? 0 : _controller.value * 7),
        child: child,
      ),
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 30,
        color: Colors.white.withValues(alpha: 0.42),
      ),
    );
  }
}

class _HomeReveal extends StatelessWidget {
  const _HomeReveal({
    required this.controller,
    required this.revealAt,
    required this.reduceMotion,
    required this.child,
  });

  final ScrollController controller;
  final double revealAt;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final offset = controller.hasClients ? controller.offset : 0.0;
        final t = ((offset - revealAt + 180) / 180).clamp(0.0, 1.0);
        return Opacity(
          opacity: Curves.easeOut.transform(t),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - Curves.easeOutCubic.transform(t))),
            child: child,
          ),
        );
      },
    );
  }
}

class _HomeIntroSection extends StatelessWidget {
  const _HomeIntroSection({
    required this.wide,
    required this.horizontalPadding,
  });
  final bool wide;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        84,
        horizontalPadding,
        96,
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/app_shell/home_app_icon.png',
              width: 64,
              height: 64,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Next-gen musicians.\nMeet your next-gen DAW.',
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 14),
          const Text(
            "First-timer or pro, there's room for your sound.",
            textAlign: TextAlign.center,
            style: _HomeType.body,
          ),
          const SizedBox(height: 72),
          _HomeMediaPanel(
            imagePath: 'assets/app_shell/home_work.webp',
            title: 'A workspace that works your way.',
            body:
                'Make music without being tied to a time, place, or device. Cross-device tools and cloud projects keep everyone in one seamless flow.',
            maxWidth: wide ? 960 : 620,
          ),
        ],
      ),
    );
  }
}

class _HomeDeviceSection extends StatelessWidget {
  const _HomeDeviceSection({
    required this.wide,
    required this.horizontalPadding,
  });
  final bool wide;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final sections = [
      const _HomeDeviceData(
        image: 'assets/app_shell/home_mobile.webp',
        title: 'Your ideas move fast.\nNow your studio does too.',
        body:
            'Stay in the flow and keep making music wherever inspiration finds you.',
      ),
      const _HomeDeviceData(
        image: 'assets/app_shell/home_tablet.webp',
        title: 'Create and edit.\nRight at your fingertips.',
        body:
            'A spacious display and intuitive touch controls balance portability with real production power.',
      ),
      const _HomeDeviceData(
        image: 'assets/app_shell/home_desktop.webp',
        title: 'Everything you expect.\nSmarter where it counts.',
        body:
            'Keep your familiar plugins, MIDI, and hardware workflow. Add intelligence without giving up control.',
      ),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 28,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              _HomeDeviceStory(
                data: sections[i],
                wide: wide,
                reverse: i.isOdd,
                isPhone: i == 0,
              ),
              if (i != sections.length - 1) SizedBox(height: wide ? 108 : 88),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeDeviceData {
  const _HomeDeviceData({
    required this.image,
    required this.title,
    required this.body,
  });
  final String image;
  final String title;
  final String body;
}

class _HomeDeviceStory extends StatelessWidget {
  const _HomeDeviceStory({
    required this.data,
    required this.wide,
    required this.reverse,
    required this.isPhone,
  });
  final _HomeDeviceData data;
  final bool wide;
  final bool reverse;
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    final image = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: isPhone ? 450 : 380),
      child: Image.asset(data.image, fit: BoxFit.contain),
    );
    final copy = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          data.title,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: _HomeType.featureTitle,
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Text(
            data.body,
            textAlign: wide ? TextAlign.left : TextAlign.center,
            style: _HomeType.body,
          ),
        ),
      ],
    );
    if (!wide) {
      return Column(children: [image, const SizedBox(height: 32), copy]);
    }
    return Row(
      children: reverse
          ? [
              Expanded(child: copy),
              const SizedBox(width: 54),
              Expanded(child: image),
            ]
          : [
              Expanded(child: image),
              const SizedBox(width: 54),
              Expanded(child: copy),
            ],
    );
  }
}

class _HomeCollaborationSection extends StatelessWidget {
  const _HomeCollaborationSection({required this.horizontalPadding});
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        128,
        horizontalPadding,
        118,
      ),
      child: _HomeMediaPanel(
        imagePath: 'assets/app_shell/home_share.webp',
        title: 'Share every living track.\nGive feedback. Create together.',
        body: 'Bring everyone into the process, from first idea to final mix.',
        maxWidth: 980,
      ),
    );
  }
}

class _HomeAiSection extends StatelessWidget {
  const _HomeAiSection({required this.horizontalPadding});
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        110,
        horizontalPadding,
        128,
      ),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.18,
          stops: [0, 0.62, 1],
          colors: [Color(0x44275DA5), Color(0x00070B1C), Color(0x00070B1C)],
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Focus on the music.\nMeet your conversational AI Co-producer.',
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 680,
            child: Text(
              'Ask for an edit, analyze a song, or get guidance in the moment. You decide the direction. Mixroom handles the execution.',
              textAlign: TextAlign.center,
              style: _HomeType.body,
            ),
          ),
          const SizedBox(height: 42),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1826),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55215DAD),
                    blurRadius: 70,
                    spreadRadius: -20,
                    offset: Offset(0, 30),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _HomeChatBubble(
                      text: 'Make this transition feel more natural.',
                      user: true,
                    ),
                  ),
                  SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _HomeChatBubble(
                      text:
                          'I can smooth the automation and preserve the energy of the chorus.',
                      user: false,
                    ),
                  ),
                  SizedBox(height: 24),
                  _HomePromptBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeChatBubble extends StatelessWidget {
  const _HomeChatBubble({required this.text, required this.user});
  final String text;
  final bool user;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 390),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: user ? const Color(0xFF2F68B0) : const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: _HomeType.chat),
    );
  }
}

class _HomePromptBar extends StatelessWidget {
  const _HomePromptBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 18, right: 6),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tell Mixroom what you want to hear…',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFF356BAE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeMediaPanel extends StatelessWidget {
  const _HomeMediaPanel({
    required this.imagePath,
    required this.title,
    required this.body,
    required this.maxWidth,
  });
  final String imagePath;
  final String title;
  final String body;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(imagePath, fit: BoxFit.contain),
          ),
          const SizedBox(height: 30),
          Text(
            title,
            textAlign: TextAlign.center,
            style: _HomeType.featureTitle,
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: _HomeType.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeProductMotionSection extends StatefulWidget {
  const _HomeProductMotionSection({required this.horizontalPadding});
  final double horizontalPadding;

  @override
  State<_HomeProductMotionSection> createState() =>
      _HomeProductMotionSectionState();
}

class _HomeProductMotionSectionState extends State<_HomeProductMotionSection> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/app_shell/home_feature.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    unawaited(_prepareVideo());
  }

  Future<void> _prepareVideo() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Keep the polished static frame if a platform cannot initialize video.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _ready && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : 16 / 9;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        36,
        widget.horizontalPadding,
        132,
      ),
      child: Column(
        children: [
          const Text(
            'Sound production, without the barrier.',
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 700,
            child: Text(
              'Move from a rough idea to a finished mix with a workflow trained around how producers actually work.',
              textAlign: TextAlign.center,
              style: _HomeType.body,
            ),
          ),
          const SizedBox(height: 42),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A1220),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x442B69BD),
                    blurRadius: 80,
                    spreadRadius: -28,
                    offset: Offset(0, 34),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _ready
                      ? ClipRect(
                          child: Transform.scale(
                            scale: 1.018,
                            child: VideoPlayer(_controller),
                          ),
                        )
                      : const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF74A1F5),
                            ),
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

class _HomeAccountPlansSection extends StatelessWidget {
  const _HomeAccountPlansSection({
    required this.horizontalPadding,
    required this.onOpenAccountPlans,
  });

  final double horizontalPadding;
  final VoidCallback onOpenAccountPlans;

  String _platformKey() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }

  String _regionCode(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final countryCode =
        locale?.countryCode ??
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final normalized = (countryCode ?? '').trim().toUpperCase();
    return normalized.isEmpty ? 'US' : normalized;
  }

  BillingProvider _provider(String regionCode) {
    if (kIsWeb) {
      return regionCode == 'KR' ? BillingProvider.toss : BillingProvider.paddle;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => BillingProvider.apple,
      TargetPlatform.android => BillingProvider.google,
      _ => regionCode == 'KR' ? BillingProvider.toss : BillingProvider.paddle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final regionCode = _regionCode(context);
    return Container(
      width: double.infinity,
      color: const Color(0xFF070B1C),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        116,
        horizontalPadding,
        168,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('PRICING', style: _HomeType.kicker),
              const SizedBox(height: 12),
              const Text(
                'Find the room your music needs.',
                style: _HomeType.sectionTitle,
              ),
              const SizedBox(height: 10),
              const Text(
                'The same plans, pricing, and benefits available from your Account.',
                style: _HomeType.body,
              ),
              const SizedBox(height: 40),
              AccountPlansCarousel(
                entitlementService: context.watch<EntitlementService>(),
                iapService: context.watch<IapService>(),
                platformKey: _platformKey(),
                regionCode: regionCode,
                platformProvider: _provider(regionCode),
                onOpenAccountPlans: onOpenAccountPlans,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// TODO: Remove after downstream snapshots migrate to AccountPlansCarousel.
// ignore: unused_element
class _HomePricingSection extends StatefulWidget {
  const _HomePricingSection({
    required this.horizontalPadding,
    required this.reduceMotion,
  });
  final double horizontalPadding;
  final bool reduceMotion;

  @override
  State<_HomePricingSection> createState() => _HomePricingSectionState();
}

class _HomePricingSectionState extends State<_HomePricingSection> {
  final ScrollController _controller = ScrollController();
  double _cardStep = 300;

  static const _plans = <_HomePlanData>[
    _HomePlanData(
      name: 'Free',
      audience: 'Casual enthusiasts',
      price: '\$0',
      cadence: 'forever',
      accent: Color(0xFFB9C2D1),
      features: [
        '1 cloud project',
        'Core effects and instruments',
        'Light AI usage',
      ],
    ),
    _HomePlanData(
      name: 'Starter',
      audience: 'Aspiring producers',
      price: '\$14.99',
      cadence: 'per month',
      accent: Color(0xFF71B8FF),
      features: [
        '5 GB cloud storage',
        'High-quality exports',
        'Expanded AI usage',
      ],
    ),
    _HomePlanData(
      name: 'Producer',
      audience: 'Professional producers',
      price: '\$39.99',
      cadence: 'per month',
      accent: Color(0xFF9C8CFF),
      recommended: true,
      features: [
        '250 GB cloud storage',
        'Advanced reasoning AI',
        'Priority support',
      ],
    ),
    _HomePlanData(
      name: 'Studio',
      audience: 'Teams and studios',
      price: '\$99',
      cadence: 'per month',
      accent: Color(0xFFFFB96F),
      features: [
        '5 producer seats',
        '1 TB shared storage',
        'Team administration',
      ],
    ),
    _HomePlanData(
      name: 'Enterprise',
      audience: 'Labels and businesses',
      price: 'Custom',
      cadence: 'tailored to your team',
      accent: Color(0xFF76E0C0),
      features: [
        'Custom AI development',
        'API and white-label options',
        'Dedicated support',
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * _cardStep).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutQuart,
      ),
    );
  }

  void _snap() {
    if (!_controller.hasClients || _cardStep <= 0) return;
    final position = _controller.position;
    final target = (position.pixels / _cardStep).round() * _cardStep;
    unawaited(
      _controller.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _openPricing() async {
    await launchUrl(
      Uri.parse('https://www.mixroom.ai/#pricing'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        110,
        widget.horizontalPadding,
        144,
      ),
      color: const Color(0xFF070B1C),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PRICING', style: _HomeType.kicker),
                      SizedBox(height: 12),
                      Text(
                        'Find the room your music needs.',
                        style: _HomeType.sectionTitle,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Start free, then grow into more storage, AI, and collaboration.',
                        style: _HomeType.body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                _HomeCarouselButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => _move(-1),
                ),
                const SizedBox(width: 8),
                _HomeCarouselButton(
                  icon: Icons.arrow_forward_rounded,
                  onTap: () => _move(1),
                ),
              ],
            ),
            const SizedBox(height: 38),
            LayoutBuilder(
              builder: (context, constraints) {
                final visibleCount = constraints.maxWidth >= 920
                    ? 3
                    : constraints.maxWidth >= 600
                    ? 2
                    : 1;
                const gap = 16.0;
                final cardWidth = visibleCount == 1
                    ? (constraints.maxWidth * 0.88).clamp(260.0, 350.0)
                    : ((constraints.maxWidth - gap * (visibleCount - 1)) /
                              visibleCount)
                          .clamp(250.0, 346.0);
                _cardStep = cardWidth + gap;
                return NotificationListener<ScrollEndNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.horizontal) _snap();
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    physics: const BouncingScrollPhysics(),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => Row(
                        children: [
                          for (
                            var index = 0;
                            index < _plans.length;
                            index++
                          ) ...[
                            SizedBox(
                              width: cardWidth,
                              height: 420,
                              child: _HomePricingCard(
                                plan: _plans[index],
                                onTap: _openPricing,
                                scale:
                                    widget.reduceMotion ||
                                        !_controller.hasClients
                                    ? 1
                                    : (1 -
                                          (((_controller.offset / _cardStep) -
                                                      index)
                                                  .abs()
                                                  .clamp(0.0, 1.0) *
                                              0.035)),
                              ),
                            ),
                            if (index != _plans.length - 1)
                              const SizedBox(width: gap),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePlanData {
  const _HomePlanData({
    required this.name,
    required this.audience,
    required this.price,
    required this.cadence,
    required this.accent,
    required this.features,
    this.recommended = false,
  });
  final String name;
  final String audience;
  final String price;
  final String cadence;
  final Color accent;
  final List<String> features;
  final bool recommended;
}

class _HomePricingCard extends StatelessWidget {
  const _HomePricingCard({
    required this.plan,
    required this.onTap,
    required this.scale,
  });
  final _HomePlanData plan;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: plan.recommended
                ? plan.accent.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.10),
          ),
          boxShadow: plan.recommended
              ? [
                  BoxShadow(
                    color: plan.accent.withValues(alpha: 0.18),
                    blurRadius: 38,
                    spreadRadius: -12,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plan.recommended)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: plan.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'MOST POPULAR',
                  style: _HomeType.planBadge.copyWith(color: plan.accent),
                ),
              )
            else
              const SizedBox(height: 43),
            Text(
              plan.name,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(plan.audience, style: _HomeType.body.copyWith(fontSize: 13)),
            const SizedBox(height: 24),
            Text(
              plan.price,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(plan.cadence, style: _HomeType.body.copyWith(fontSize: 12)),
            const SizedBox(height: 24),
            for (final feature in plan.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 18, color: plan.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feature,
                        style: _HomeType.body.copyWith(
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: plan.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: plan.accent.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Text(
                    plan.name == 'Free' ? 'Included' : 'View plan',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeCarouselButton extends StatelessWidget {
  const _HomeCarouselButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

class _HomeFeedbackSection extends StatelessWidget {
  const _HomeFeedbackSection({
    required this.horizontalPadding,
    required this.bottomPadding,
    required this.viewportHeight,
    required this.onSubmit,
  });
  final double horizontalPadding;
  final double bottomPadding;
  final double viewportHeight;
  final Future<void> Function(
    FeedbackCategory category,
    String message,
    bool allowEmailContact,
  )
  onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        260,
        horizontalPadding,
        bottomPadding + viewportHeight * 0.30,
      ),
      color: const Color(0xFF070B1C),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Container(
                width: 1,
                height: 58,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0074A1F5), Color(0x9974A1F5)],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Built with you.', style: _HomeType.sectionTitle),
              const SizedBox(height: 12),
              const Text(
                'Your feedback shapes what Mixroom becomes next.',
                textAlign: TextAlign.center,
                style: _HomeType.body,
              ),
              const SizedBox(height: 18),
              MixroomInlineFeedbackComposer(
                onSubmit: onSubmit,
                compact: true,
                showBranding: false,
                showBetaNotice: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _HomeType {
  static const kicker = TextStyle(
    fontFamily: 'Pretendard',
    color: Color(0xFF74A1F5),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 2.2,
  );
  static const planBadge = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
  static const sectionTitle = TextStyle(
    fontFamily: 'Pretendard',
    color: Colors.white,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.28,
    letterSpacing: -0.7,
  );
  static const featureTitle = TextStyle(
    fontFamily: 'Pretendard',
    color: Colors.white,
    fontSize: 25,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.45,
  );
  static const body = TextStyle(
    fontFamily: 'Pretendard',
    color: Color(0x99FFFFFF),
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.7,
  );
  static const chat = TextStyle(
    fontFamily: 'Pretendard',
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );
}

class _PlatformTab extends StatefulWidget {
  const _PlatformTab({required this.scrollToTopSignal});

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

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                                final canUpdate =
                                    status != null &&
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
                                      L10n.translate(context, 'App Version'),
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
                                          foregroundColor: const Color(
                                            0xFFF4F4F4,
                                          ),
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
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
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
                                        child: Text(_storeCtaLabel(context)),
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
