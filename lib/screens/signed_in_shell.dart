import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/desktop_auto_update_service.dart';
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
  late Future<AppVersionStatus?> _desktopVersionStatusFuture;
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
    _desktopVersionStatusFuture = _appUpdatePromptService.getVersionStatus();
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
          content: Text('Education access activated.'),
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
      if (DesktopAutoUpdateService.instance.isConfigured) {
        final launched = await DesktopAutoUpdateService.instance
            .checkForUpdates();
        if (!mounted) return;
        if (!launched) {
          showAppSnackBar(
            context,
            L10n.translate(context, 'Unable to check for updates right now.'),
          );
        }
        unawaited(
          AnalyticsService.instance.track(
            AnalyticsEvents.appUpdatePromptInteracted(
              action: launched ? 'update_native' : 'update_native_failed',
              promptType: decision.type.name,
              currentVersion: decision.currentVersion,
              latestVersion: decision.latestVersion,
              errorCode: launched ? null : 'native_updater_failed',
            ),
          ),
        );
        return;
      }

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
            onCheckForUpdates: _checkForDesktopUpdates,
          ),
        ),
      ],
    );
    if (!mounted) return;
    setState(() {
      _desktopVersionStatusFuture = _appUpdatePromptService.getVersionStatus();
    });
  }

  Future<void> _checkForDesktopUpdates() async {
    final launched = await DesktopAutoUpdateService.instance.checkForUpdates();
    if (!mounted || launched) return;
    showAppSnackBar(
      context,
      L10n.translate(context, 'Unable to check for updates right now.'),
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
        if (mixroomUsesPhoneLayout(context)) {
          return ProjectsScreen(
            key: const ValueKey<String>('phone_demo_projects'),
            scrollToTopSignal: _scrollToTopSignal,
            onUpgradeRequested: _openSubscriptionAccountTab,
            demoOnly: true,
          );
        }
        return _PlatformTab(scrollToTopSignal: _scrollToTopSignal);
      case MixroomMainTab.projects:
        return ProjectsScreen(
          key: const ValueKey<String>('projects_library'),
          scrollToTopSignal: _scrollToTopSignal,
          onUpgradeRequested: _openSubscriptionAccountTab,
          hideDemoProjects: mixroomUsesPhoneLayout(context),
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
                    child: FutureBuilder<AppVersionStatus?>(
                      future: _desktopVersionStatusFuture,
                      builder: (context, snapshot) {
                        final desktopUpdater =
                            DesktopAutoUpdateService.instance;
                        return ValueListenableBuilder<bool>(
                          valueListenable: desktopUpdater.updateAvailable,
                          builder: (context, nativeUpdateAvailable, _) {
                            final showUpdateDot =
                                desktopUpdater.isConfigured &&
                                (nativeUpdateAvailable ||
                                    snapshot.data?.isUpdateAvailable == true);
                            return MixroomMainSideRail(
                              selectedTab: _selectedTab,
                              onTabSelected: _setTab,
                              onAddTap: _createMusicProject,
                              onBrandTap: () =>
                                  _showRailInfo(desktopRailTopInset),
                              showBrandNotificationDot: showUpdateDot,
                              topContentInset: desktopRailTopInset,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _buildPage(_selectedTab)),
                        if (_activeAnnouncement != null &&
                            _activeAnnouncement!.showsBanner)
                          Positioned(
                            left: 0,
                            right: 0,
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
  const _MixroomRailInfoPopover({
    required this.updateService,
    required this.onCheckForUpdates,
  });

  final AppUpdatePromptService updateService;
  final Future<void> Function() onCheckForUpdates;

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

  void _checkForDesktopUpdates() {
    Navigator.of(context).pop();
    unawaited(widget.onCheckForUpdates());
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mixroom',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFF4F4F4),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      L10n.translate(context, 'AI-assisted music production'),
                      style: const TextStyle(
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
                message: L10n.translate(context, 'Close'),
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
              final String? statusText = loading
                  ? L10n.translate(context, 'Checking for updates…')
                  : canUpdate
                  ? L10n.translateWithParams(
                      context,
                      'Version {version} is available',
                      {'version': status!.latestVersion},
                    )
                  : status == null || !status.hasLatestVersion
                  ? null
                  : L10n.translate(context, 'You’re up to date');
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
                          version.isEmpty
                              ? L10n.translate(context, 'App version')
                              : L10n.translateWithParams(
                                  context,
                                  'Version {version}',
                                  {'version': version},
                                ),
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
                    if (statusText != null) ...[
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
                    ],
                    const SizedBox(height: 12),
                    _RailPopoverButton(
                      label: canUpdate
                          ? L10n.translate(context, 'Update Mixroom')
                          : L10n.translate(context, 'Check for updates'),
                      icon: canUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.refresh_rounded,
                      emphasized: canUpdate,
                      busy: loading,
                      onTap: loading
                          ? null
                          : DesktopAutoUpdateService.instance.isConfigured
                          ? _checkForDesktopUpdates
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
            title: L10n.translate(context, 'Mixroom website'),
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

String _homeCopy(BuildContext context, String english, String korean) {
  return L10n.getDeviceLocale(context).languageCode == 'ko' ? korean : english;
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
                    _HomeFaqSection(horizontalPadding: sidePadding),
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
            top: 0,
            height: 180,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF070B1C), Color(0x00070B1C)],
                  ),
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
                    child: Column(
                      children: [
                        Text(
                          _homeCopy(
                            context,
                            'Made anywhere. Heard everywhere.',
                            '나의 음악을 세상과 연결하다',
                          ),
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
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 660,
                          child: Text(
                            _homeCopy(
                              context,
                              'Mixroom is a cross-platform DAW that moves seamlessly from mobile to desktop. Bring everyone into one cloud project to collaborate and share ideas. And whenever you need a hand, your AI Co-producer is right there.',
                              'Mixroom은 모바일부터 데스크탑까지 하나로 이어지는 DAW입니다. 클라우드 프로젝트에서 작업하고 피드백을 나눠보세요. 도움이 필요한 순간에는 AI Co-producer를 활용할 수 있습니다.',
                            ),
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
          Text(
            _homeCopy(
              context,
              'Next-gen musicians.\nMeet your next-gen DAW.',
              '차세대 창작자에게 적합한\n차세대 DAW',
            ),
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 14),
          Text(
            _homeCopy(
              context,
              "First-timer or pro, there's room for your sound.",
              '음악을 처음 시작하는 사람부터 전문가까지 당신이 누구든 음악이 되도록.',
            ),
            textAlign: TextAlign.center,
            style: _HomeType.body,
          ),
          const SizedBox(height: 72),
          _HomeMediaPanel(
            imagePath: 'assets/app_shell/home_work.webp',
            title: _homeCopy(
              context,
              'A workspace that works your way.',
              '작업 환경에 맞춘 작업 환경',
            ),
            body: _homeCopy(
              context,
              'Make music without being tied to a time, place, or device. With cross-device MIDI and cloud-based projects, everyone behind the music can work together in one seamless flow.',
              '전문적으로 음악을 만드는 데 시간과 장소의 제약이 사라집니다. 기기를 가리지 않는 MIDI 작업 환경과 클라우드 기반 프로젝트로 음악을 만드는 사람이라면 누구든 함께 할 수 있어요.',
            ),
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
      _HomeDeviceData(
        image: 'assets/app_shell/home_mobile.webp',
        title: _homeCopy(
          context,
          'Your ideas move fast.\nNow your studio does too.',
          '아이디어 떠오를때 바로',
        ),
        body: _homeCopy(
          context,
          'With Mixroom on mobile, stay in the flow and keep making music wherever you go.',
          '언제 어디서나 이동중에도 창작에 집중할 수 있습니다.',
        ),
      ),
      _HomeDeviceData(
        image: 'assets/app_shell/home_tablet.webp',
        title: _homeCopy(
          context,
          'Create and edit.\nRight at your fingertips.',
          '창작과 편집,\n가장 자연스럽게.',
        ),
        body: _homeCopy(
          context,
          'A spacious display meets intuitive touch controls, striking the perfect balance between portability and productivity.',
          '넓은 화면과 터치 인터페이스를 동시에 활용해 휴대성과 작업 효율의 균형을 갖췄습니다.',
        ),
      ),
      _HomeDeviceData(
        image: 'assets/app_shell/home_desktop.webp',
        title: _homeCopy(
          context,
          'Everything you expect.\nSmarter where it counts.',
          '당연한건 당연하게',
        ),
        body: _homeCopy(
          context,
          'Keep the VST plug-ins and workflow you already know. Mixroom adds a smarter way to work, with MIDI and external hardware support built right in.',
          '기존에 사용하던 VST 플러그인과 작업 환경을 그대로 이어가세요. 더 스마트한 작업이 더해집니다. MIDI, 외장 하드웨어 연결은 기본이죠.',
        ),
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
        title: _homeCopy(
          context,
          'Share every living track.\nGive feedback. Create together.',
          '모든 트랙이 살아있는 그대로\n공유하고, 피드백하고, 함께 만드세요',
        ),
        body: _homeCopy(
          context,
          'Bring everyone into the process, from first idea to final mix.',
          '음악이 완성되는 모든 과정에 함께할 수 있도록.',
        ),
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
          Text(
            _homeCopy(
              context,
              'Focus on the music.\nMeet your conversational AI Co-producer.',
              '작업에 집중하세요\n스마트한 대화형 AI Co-producer',
            ),
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 680,
            child: Text(
              _homeCopy(
                context,
                'Ask for an edit, analyze a song, or get guidance in the moment. You decide the direction. Mixroom handles the execution.',
                '음악과 관련한 모든 타임라인에 든든한 AI 어시스턴트가 Mixroom에 있습니다. 필요한 순간 채팅 한번에 바로 도움받을 수 있도록 눈에 보이는 곳에서 대기 중이랍니다.',
              ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _HomeChatBubble(
                      text: _homeCopy(
                        context,
                        'Make this transition feel more natural.',
                        '이 전환이 더 자연스럽게 들리게 해줘.',
                      ),
                      user: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _HomeChatBubble(
                      text: _homeCopy(
                        context,
                        'I can smooth the automation and preserve the energy of the chorus.',
                        '오토메이션을 부드럽게 다듬으면서 후렴의 에너지는 그대로 유지할게요.',
                      ),
                      user: false,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _HomePromptBar(),
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
              _homeCopy(
                context,
                'Tell Mixroom what you want to hear…',
                'Mixroom에 원하는 사운드를 이야기해보세요…',
              ),
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
          Text(
            _homeCopy(
              context,
              'Sound production, without the barrier.',
              '사운드 제작의 장벽을 허물다.',
            ),
            textAlign: TextAlign.center,
            style: _HomeType.sectionTitle,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 700,
            child: Text(
              _homeCopy(
                context,
                'Move from a rough idea to a finished mix with a workflow trained around how producers actually work.',
                '실제 프로듀서의 노하우로 훈련된 AI Co-Producer와 함께 믹싱부터 마스터링까지, 음악을 완성해보세요. 마음에 들 때까지 모든 작업 과정을 안정적으로 진행할 수 있습니다.',
              ),
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
              Text(
                _homeCopy(context, 'PRICING', 'PRICING'),
                style: _HomeType.kicker,
              ),
              const SizedBox(height: 12),
              Text(
                _homeCopy(
                  context,
                  'Find the room your music needs.',
                  '음악에 맞는 플랜을 선택하세요.',
                ),
                style: _HomeType.sectionTitle,
              ),
              const SizedBox(height: 10),
              Text(
                _homeCopy(
                  context,
                  'Mixroom offers four standard subscription tiers, plus a custom Enterprise option, all designed to enhance the music creation and sharing experience.',
                  'Mixroom은 음악 제작과 공유하는 경험을 한 차원 끌어올리는 4가지 표준 구독 플랜과 맞춤형 Enterprise 옵션을 제공합니다.',
                ),
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
                scrollbarGutter: 14,
                railEdgeInset: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFaqSection extends StatefulWidget {
  const _HomeFaqSection({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  State<_HomeFaqSection> createState() => _HomeFaqSectionState();
}

class _HomeFaqSectionState extends State<_HomeFaqSection> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final items = <_HomeFaqData>[
      _HomeFaqData(
        question: _homeCopy(context, 'What is a DAW?', 'DAW가 뭔가요?'),
        answer: _homeCopy(
          context,
          'DAW stands for **Digital Audio Workstation**, the software used to create, record, edit, and produce music.',
          'DAW는 **Digital Audio Workstation**의 약자로, 음악을 만들고 녹음하고 편집하고 프로듀싱하는 데 사용하는 소프트웨어입니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(context, 'What is Mixroom?', 'Mixroom은 무엇인가요?'),
        answer: _homeCopy(
          context,
          'Mixroom is a **next-generation DAW with a built-in AI co-producer.** You tell it where you want the music to go, and it helps execute that direction. It works with you as a production partner, not a music generator.',
          'Mixroom은 **AI 코프로듀서가 내장된 차세대 DAW**입니다. 음악의 방향을 정하면 Mixroom이 그 방향대로 실행을 도와줍니다. 창작자의 역할을 대체하지 않고, 음악 생성기가 아닌 프로덕션 파트너로 함께합니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'How is this different from AI music generators?',
          'AI 음악 생성기와 어떻게 다른가요?',
        ),
        answer: _homeCopy(
          context,
          'Mixroom **does not generate music**. It helps you finish *your* music. You bring the idea, the taste, and the direction. Mixroom helps execute it.',
          'Mixroom은 **음악을 생성하지 않습니다.** 완성된 결과물을 대신 만드는 것이 아니라, 직접 만든 음악을 완성하도록 돕습니다. 아이디어와 취향, 방향성은 창작자가 정하고 Mixroom은 실행을 돕습니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Can I use Mixroom without music theory or production experience?',
          '음악 이론이나 프로듀싱 경험 없이 사용할 수 있나요?',
        ),
        answer: _homeCopy(
          context,
          "**Yes.** You don't need music theory or technical production knowledge. If you can describe a mood, a feeling, or the kind of sound you want, that's enough.",
          '**네.** 음악 이론, 기술적 프로덕션 지식, 플러그인이나 믹싱 도구에 대한 깊은 이해 없이도 시작할 수 있습니다. 분위기, 감정, 원하는 소리의 종류를 설명할 수 있다면 그것으로 충분합니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Will AI make changes on its own?',
          'AI가 마음대로 변경하거나 이해할 수 없는 작업을 하나요?',
        ),
        answer: _homeCopy(
          context,
          '**No.** Mixroom is not a black box. You give direction, it applies the change, and you review it. You can keep it, adjust it yourself, or undo it.',
          '**아닙니다.** Mixroom은 블랙박스가 아닙니다. 방향을 정하면 Mixroom이 변경을 적용하고 결과를 직접 검토할 수 있습니다. 그대로 유지하거나, 직접 조정하거나, 되돌릴 수 있습니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Will everything sound the same?',
          'AI가 개입하면 결과물이 비슷해지지 않나요?',
        ),
        answer: _homeCopy(
          context,
          '**No.** Mixroom responds to *your intent*. The outcome depends on your decisions, your taste, and your direction. Same tool, completely different results.',
          '**아닙니다.** 생성형 AI는 패턴 기반 출력이라 결과물이 비슷해지는 경향이 있습니다. Mixroom은 창작자의 의도에 반응하며, 결과물은 각자의 결정과 취향, 방향에 따라 달라집니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Will I lose the feeling of making it myself?',
          '직접 만든다는 감각을 잃지 않을까요?',
        ),
        answer: _homeCopy(
          context,
          '**No.** Mixroom does not take over the creative role. It removes repetitive work so you can focus on decisions that actually shape the music.',
          '**아닙니다.** Mixroom은 창작의 주도권을 가져가지 않습니다. 반복 작업을 제거하고 기술적 부담을 낮추어, 음악을 실제로 빚는 결정에 더 집중하도록 돕습니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Who owns the copyright?',
          '저작권은 누구에게 있나요?',
        ),
        answer: _homeCopy(
          context,
          'You do. **100%.** Mixroom does not generate results by recombining outside material or claim authorship over the output.',
          '창작자에게 **100%** 있습니다. Mixroom은 직접 만든 음악 위에서 비파괴 편집 방식으로 작동합니다. 외부 자료를 재조합해 결과물을 생성하지 않으며, 결과물에 대한 저작권을 주장하지 않습니다.',
        ),
      ),
      _HomeFaqData(
        question: _homeCopy(
          context,
          'Is Mixroom mobile-only?',
          'Mixroom은 모바일 전용인가요? 데스크탑 버전이 나오나요?',
        ),
        answer: _homeCopy(
          context,
          'Mixroom is a cross-platform DAW that runs on mobile, tablet, and desktop. With cloud sync, pick up your work anywhere on whichever device fits the moment.',
          'Mixroom은 모바일, 태블릿, 데스크톱에서 모두 사용할 수 있는 크로스 플랫폼 DAW입니다. 클라우드 연동을 통해 언제 어디서든 상황에 맞는 기기로 작업을 이어가세요.',
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFF070B1C),
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding,
        18,
        widget.horizontalPadding,
        72,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_homeCopy(context, 'FAQ', 'FAQ'), style: _HomeType.kicker),
              const SizedBox(height: 12),
              Text(
                _homeCopy(context, 'Frequently asked questions', '자주 묻는 질문'),
                style: _HomeType.sectionTitle,
              ),
              const SizedBox(height: 34),
              for (final entry in items.asMap().entries)
                _HomeFaqRow(
                  data: entry.value,
                  expanded: _expandedIndex == entry.key,
                  onTap: () => setState(() {
                    _expandedIndex = _expandedIndex == entry.key
                        ? null
                        : entry.key;
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFaqData {
  const _HomeFaqData({required this.question, required this.answer});

  final String question;
  final String answer;
}

class _HomeFaqRow extends StatelessWidget {
  const _HomeFaqRow({
    required this.data,
    required this.expanded,
    required this.onTap,
  });

  final _HomeFaqData data;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const answerStyle = TextStyle(
      fontFamily: 'Pretendard',
      color: Color(0xB8FFFFFF),
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.7,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.question,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFFF4F4F4),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    AnimatedRotation(
                      turns: expanded ? 0.125 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white.withValues(alpha: 0.72),
                        size: 23,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(right: 52, bottom: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: _homeFaqTextSpans(
                              data.answer,
                              answerStyle,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

List<InlineSpan> _homeFaqTextSpans(String source, TextStyle baseStyle) {
  final matches = RegExp(r'(\*\*.*?\*\*|\*.*?\*)').allMatches(source);
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: source.substring(cursor, match.start), style: baseStyle),
      );
    }
    final token = match.group(0)!;
    final bold = token.startsWith('**');
    spans.add(
      TextSpan(
        text: token.substring(bold ? 2 : 1, token.length - (bold ? 2 : 1)),
        style: baseStyle.copyWith(
          color: bold ? const Color(0xFFF4F4F4) : null,
          fontWeight: bold ? FontWeight.w700 : null,
          fontStyle: bold ? null : FontStyle.italic,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < source.length) {
    spans.add(TextSpan(text: source.substring(cursor), style: baseStyle));
  }
  return spans;
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
              Text(
                _homeCopy(context, 'Built with you.', '함께 만들어가는 Mixroom.'),
                style: _HomeType.sectionTitle,
              ),
              const SizedBox(height: 12),
              Text(
                _homeCopy(
                  context,
                  'Your feedback shapes what Mixroom becomes next.',
                  '여러분의 피드백이 Mixroom의 다음 모습을 만듭니다.',
                ),
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
