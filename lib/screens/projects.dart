import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/helpers/desktop_file_ingress_service.dart';
import 'package:mixroom/helpers/cloud_open_resolver.dart';
import 'package:mixroom/helpers/cloud_project_service.dart';
import 'package:mixroom/helpers/cloud_sync_preferences.dart';
import 'package:mixroom/helpers/export_save_dialog.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/project_compatibility_service.dart';
import 'package:mixroom/helpers/project_family.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/project_version_store.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/helpers/track_row_icons.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/widgets/app_responsive_body.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class _NoSwipeMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _NoSwipeMaterialPageRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

class _ProjectLibraryPageScrollPhysics extends PageScrollPhysics {
  const _ProjectLibraryPageScrollPhysics({super.parent});

  @override
  _ProjectLibraryPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ProjectLibraryPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 1, stiffness: 620, damping: 48);
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    this.scrollToTopSignal = 0,
    this.onUpgradeRequested,
    this.demoOnly = false,
    this.hideDemoProjects = false,
  });

  final int scrollToTopSignal;
  final VoidCallback? onUpgradeRequested;
  final bool demoOnly;
  final bool hideDemoProjects;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

const double kActionCardHeight = 72;
const double _kProjectLibraryPageHorizontalGutter = 8;
const double _kProjectLibrarySideRailInset = 8;

enum _ProjectSortMode { recent, alphabetical }

enum _ProjectLibraryTab { yourProjects, cloudProjects, demoProjects }

enum _LocalCloudConflictChoice { keepDevice, takeCloud, keepBoth }

enum _FamilyDeleteScope { mix, song }

class _LocalCloudStatusPresentation {
  const _LocalCloudStatusPresentation({
    required this.label,
    required this.statusLabel,
    required this.icon,
    required this.color,
  });

  final String label;
  final String statusLabel;
  final IconData icon;
  final Color color;
}

class _ProjectListEntry {
  _ProjectListEntry.family(this.family)
    : bundledDemo = null,
      cloudProject = null,
      isBundledDemo = false;

  const _ProjectListEntry.bundledDemo(this.bundledDemo)
    : family = null,
      cloudProject = null,
      isBundledDemo = true;

  const _ProjectListEntry.cloud(this.cloudProject)
    : family = null,
      bundledDemo = null,
      isBundledDemo = false;

  final ProjectFamilyGroup? family;
  final BundledDemoProjectAsset? bundledDemo;
  final CloudProjectAccessItem? cloudProject;
  final bool isBundledDemo;

  bool get isCloudProject => cloudProject != null;
}

class _CloudProjectDestination {
  const _CloudProjectDestination.personal()
    : workspaceId = '',
      organizationId = '',
      label = 'Personal Cloud',
      subtitle = 'Only you can access this project',
      icon = Icons.person_rounded,
      canWrite = true,
      status = 'active';

  const _CloudProjectDestination.workspace({
    required this.workspaceId,
    required this.organizationId,
    required this.label,
    required this.subtitle,
    required this.canWrite,
    required this.status,
  }) : icon = canWrite ? Icons.groups_2_rounded : Icons.lock_rounded;

  final String workspaceId;
  final String organizationId;
  final String label;
  final String subtitle;
  final IconData icon;
  final bool canWrite;
  final String status;

  bool get isPersonal => workspaceId.isEmpty;
  bool get isReadOnly => !canWrite;
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  static const Key _projectsScreenKey = Key('projects_screen');
  static const Key _renameDialogKey = ValueKey('projects_rename_dialog');
  static const Key _renameFieldKey = ValueKey('projects_rename_field');
  static const Key _renameCancelKey = ValueKey('projects_rename_cancel');
  static const Key _renameSaveKey = ValueKey('projects_rename_save');
  static const Key _deleteDialogKey = ValueKey('projects_delete_dialog');
  static const Key _deleteCancelKey = ValueKey('projects_delete_cancel');
  static const Key _deleteConfirmKey = ValueKey('projects_delete_confirm');
  static const Key _deleteThisMixKey = ValueKey('projects_delete_this_mix');
  static const Key _deleteWholeSongKey = ValueKey('projects_delete_whole_song');
  static List<ProjectMeta>? _cachedProjects;
  static List<BundledDemoProjectAsset>? _cachedBundledDemoProjects;
  List<ProjectMeta> _projects = [];
  List<BundledDemoProjectAsset> _bundledDemoProjects = [];
  List<CloudProjectAccessItem> _cloudProjects = [];
  CloudProjectStorageSummary? _cloudStorage;
  bool _loading = true;
  bool _cloudLoading = false;
  CloudSyncMode _cloudSyncMode = CloudSyncMode.auto;
  String _selectedCloudWorkspaceId = '';
  bool _filePickerInFlight = false;
  final CloudProjectService _cloudProjectService = CloudProjectService();
  StreamSubscription<String>? _importSub;
  StreamSubscription<List<DesktopFileDropItem>>? _desktopDropSub;
  Future<void>? _projectRefreshInFlight;
  bool _projectRefreshQueued = false;
  bool _queuedProjectRefreshIncludeCloud = false;
  bool _queuedProjectRefreshShowBlockingLoader = false;
  Set<String> _observedCloudProjectSyncs = const <String>{};
  final Set<String> _settlingCloudProjectSyncs = <String>{};
  Future<void>? _cloudRefreshInFlight;
  String? _loadError;
  String? _cloudError;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'projects_search');
  late final PageController _libraryPageController;
  late final Map<_ProjectLibraryTab, ScrollController>
  _libraryScrollControllers;
  final GlobalKey _projectToolsButtonKey = GlobalKey();
  final GlobalKey<TooltipState> _cloudSyncTooltipKey =
      GlobalKey<TooltipState>();
  _ProjectSortMode _sortMode = _ProjectSortMode.recent;
  _ProjectLibraryTab _libraryTab = _ProjectLibraryTab.yourProjects;
  final Set<String> _selectedProjectPaths = <String>{};
  final Set<String> _selectedBundledDemoAssetPaths = <String>{};
  final Set<String> _expandedFamilyIds = <String>{};
  final Set<String> _cloudProjectsInFlight = <String>{};
  final ProjectVersionStore _projectVersionStore = const ProjectVersionStore();
  bool _selectionModePinned = false;
  bool _demoTileView = true;

  String _projectActionKeyToken(String name) =>
      Uri.encodeComponent(name.trim());

  String _friendlyLoadError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('path_provider') ||
        raw.contains('getapplicationdocumentspath') ||
        raw.contains('shared_preferences') ||
        raw.contains('channel-error')) {
      return 'Projects are temporarily unavailable on this device. Please try again in a moment.';
    }
    return 'We couldn\'t load your projects right now. Please try again.';
  }

  String _cleanCloudError(Object error) {
    final raw = error.toString();
    final marker = raw.indexOf('): ');
    if (marker >= 0 && marker + 3 < raw.length) {
      return raw.substring(marker + 3).trim();
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }

  bool get _cloudProjectsFeatureEnabled {
    try {
      return context.read<EntitlementService>().areCloudProjectsEnabled;
    } catch (_) {
      return false;
    }
  }

  void _clearCloudProjectState() {
    _cloudProjects = <CloudProjectAccessItem>[];
    _cloudStorage = null;
    _cloudError = null;
    _cloudLoading = false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.demoOnly) {
      _libraryTab = _ProjectLibraryTab.demoProjects;
    }
    _libraryPageController = PageController(initialPage: _libraryTab.index);
    _libraryScrollControllers = {
      for (final tab in _ProjectLibraryTab.values) tab: ScrollController(),
    };
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    ProjectManager.projectLibraryRevision.addListener(
      _handleProjectLibraryChanged,
    );
    _observedCloudProjectSyncs = Set<String>.from(
      ProjectManager.cloudProjectSyncInFlight.value,
    );
    ProjectManager.cloudProjectSyncInFlight.addListener(
      _handleCloudProjectSyncActivityChanged,
    );
    final cachedProjects = _cachedProjects;
    final cachedBundledDemoProjects = _cachedBundledDemoProjects;
    if (cachedProjects != null && cachedBundledDemoProjects != null) {
      _projects = List<ProjectMeta>.from(cachedProjects);
      _bundledDemoProjects = List<BundledDemoProjectAsset>.from(
        cachedBundledDemoProjects,
      );
      _loading = false;
      unawaited(_refresh(showBlockingLoader: false));
    } else {
      _refresh();
    }
    unawaited(_loadCloudPreferences());

    // Cold start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = OpenMixroomService.consumeInitialPathOnce();
      if (initial != null) {
        await _importProjectFromIncomingFile(File(initial));
      }
      final pendingDrops = DesktopFileIngressService.consumePendingBatches();
      for (final items in pendingDrops) {
        await _handleDesktopFinderDrop(items);
      }
    });

    // Warm start
    _importSub = OpenMixroomService.stream.listen((path) async {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _importProjectFromIncomingFile(File(path));
      });
    });
    _desktopDropSub = DesktopFileIngressService.stream.listen((items) async {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _handleDesktopFinderDrop(items);
      });
    });
  }

  @override
  void didUpdateWidget(covariant ProjectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal) {
      _scrollCurrentLibraryTabToTop();
    }
  }

  Future<void> _loadCloudPreferences() async {
    final mode = await CloudSyncPreferences.loadMode();
    final workspaceId = await CloudSyncPreferences.loadDefaultWorkspaceId();
    if (!mounted) return;
    setState(() {
      _cloudSyncMode = mode;
      _selectedCloudWorkspaceId = workspaceId;
    });
  }

  Future<void> _setCloudSyncMode(CloudSyncMode mode) async {
    if (_cloudSyncMode == mode) return;
    setState(() => _cloudSyncMode = mode);
    await CloudSyncPreferences.saveMode(mode);
  }

  Future<void> _setSelectedCloudWorkspace(String workspaceId) async {
    final normalized = workspaceId.trim();
    if (_selectedCloudWorkspaceId == normalized) return;
    setState(() => _selectedCloudWorkspaceId = normalized);
    await CloudSyncPreferences.saveDefaultWorkspaceId(normalized);
  }

  @override
  void dispose() {
    _importSub?.cancel();
    _desktopDropSub?.cancel();
    ProjectManager.projectLibraryRevision.removeListener(
      _handleProjectLibraryChanged,
    );
    ProjectManager.cloudProjectSyncInFlight.removeListener(
      _handleCloudProjectSyncActivityChanged,
    );
    _cloudProjectService.close();
    _libraryPageController.dispose();
    for (final controller in _libraryScrollControllers.values) {
      controller.dispose();
    }
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollCurrentLibraryTabToTop() {
    final controller = _libraryScrollControllers[_libraryTab];
    if (controller == null || !controller.hasClients) return;
    unawaited(
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleProjectLibraryChanged() {
    if (!mounted) return;
    unawaited(_refresh());
  }

  void _handleCloudProjectSyncActivityChanged() {
    if (!mounted) return;
    final current = Set<String>.from(
      ProjectManager.cloudProjectSyncInFlight.value,
    );
    final completed = _observedCloudProjectSyncs.difference(current);
    _observedCloudProjectSyncs = current;
    _settlingCloudProjectSyncs.addAll(completed);
    setState(() {});
    if (completed.isNotEmpty) {
      unawaited(_finishSettlingCloudProjectSyncs(completed));
    }
  }

  Future<void> _finishSettlingCloudProjectSyncs(Set<String> projectIds) async {
    await _refresh(includeCloud: true, showBlockingLoader: false);
    if (!mounted) return;
    _settlingCloudProjectSyncs.removeAll(projectIds);
    setState(() {});
  }

  Future<void> _handleDesktopFinderDrop(List<DesktopFileDropItem> items) async {
    if (!Platform.isMacOS || items.isEmpty) return;
    final mixroomItems = items.where((item) => item.isMixroom).toList();
    if (mixroomItems.isEmpty) return;
    for (final item in mixroomItems) {
      if (!mounted) return;
      await _importProjectFromIncomingFile(File(item.path));
    }
  }

  Future<void> _refresh({
    bool includeCloud = false,
    bool showBlockingLoader = true,
  }) {
    _projectRefreshQueued = true;
    _queuedProjectRefreshIncludeCloud |= includeCloud;
    _queuedProjectRefreshShowBlockingLoader |= showBlockingLoader;

    final active = _projectRefreshInFlight;
    if (active != null) return active;

    final task = _drainProjectRefreshes();
    _projectRefreshInFlight = task;
    return task.whenComplete(() {
      if (identical(_projectRefreshInFlight, task)) {
        _projectRefreshInFlight = null;
      }
    });
  }

  Future<void> _drainProjectRefreshes() async {
    while (mounted && _projectRefreshQueued) {
      final includeCloud = _queuedProjectRefreshIncludeCloud;
      final showBlockingLoader = _queuedProjectRefreshShowBlockingLoader;
      _projectRefreshQueued = false;
      _queuedProjectRefreshIncludeCloud = false;
      _queuedProjectRefreshShowBlockingLoader = false;
      await _refreshOnce(
        includeCloud: includeCloud,
        showBlockingLoader: showBlockingLoader,
      );
    }
  }

  Future<void> _refreshOnce({
    required bool includeCloud,
    required bool showBlockingLoader,
  }) async {
    final shouldShowBlockingLoader =
        showBlockingLoader && _projects.isEmpty && _bundledDemoProjects.isEmpty;
    if (shouldShowBlockingLoader) {
      setState(() {
        _loading = true;
        _loadError = null;
        _cloudError = null;
      });
    } else {
      setState(() {
        _loadError = null;
        _cloudError = null;
      });
    }
    try {
      _projects = await ProjectManager.listProjects();
      final bundledDemoProjects =
          await ProjectManager.listBundledDemoProjectAssets();
      final dismissedDemoAssetPaths =
          await ProjectManager.listDismissedBundledDemoAssetPaths();
      final importedDemoAssetPaths = _projects
          .map((project) => project.bundledDemoAssetPath)
          .whereType<String>()
          .toSet();
      _bundledDemoProjects = bundledDemoProjects
          .where(
            (demo) =>
                !importedDemoAssetPaths.contains(demo.assetPath) &&
                !dismissedDemoAssetPaths.contains(demo.assetPath),
          )
          .toList(growable: false);
      _cachedProjects = List<ProjectMeta>.from(_projects);
      _cachedBundledDemoProjects = List<BundledDemoProjectAsset>.from(
        _bundledDemoProjects,
      );
      if (!mounted) return;
      _seedCloudProjectsFromEntitlementCache();
      if (mounted) {
        setState(() => _loading = false);
      }
      if (!_cloudProjectsFeatureEnabled) {
        _clearCloudProjectState();
        if (_libraryTab == _ProjectLibraryTab.cloudProjects) {
          _setLibraryTab(_ProjectLibraryTab.yourProjects);
        }
        if (mounted) {
          setState(() {});
        }
        return;
      }
      final hasCloudLinkedLocalProjects = _projects.any(
        (project) => (project.cloudProjectId ?? '').trim().isNotEmpty,
      );
      final signedIn = context.read<AuthService>().isSignedIn;
      if (includeCloud ||
          _libraryTab == _ProjectLibraryTab.cloudProjects ||
          hasCloudLinkedLocalProjects ||
          (signedIn && _projects.isNotEmpty && _cloudProjects.isEmpty)) {
        await _refreshCloudProjectsSilently();
      }
      await _persistCloudLinksForLocalMatches();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _projects = <ProjectMeta>[];
      _bundledDemoProjects = <BundledDemoProjectAsset>[];
      _cloudProjects = <CloudProjectAccessItem>[];
      _loadError = _friendlyLoadError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _seedCloudProjectsFromEntitlementCache() {
    if (!_cloudProjectsFeatureEnabled) {
      _clearCloudProjectState();
      return;
    }
    final snapshot = context.read<EntitlementService>().cloudProjectsAccess;
    if (snapshot == null) return;
    _cloudProjects = snapshot.cloudProjects;
    _cloudStorage = snapshot.storage;
    _cloudError = null;
  }

  Future<void> _refreshCloudProjectsSilently({bool showLoading = true}) async {
    if (_cloudRefreshInFlight != null) {
      await _cloudRefreshInFlight;
      return;
    }
    final completer = Completer<void>();
    _cloudRefreshInFlight = completer.future;
    if (!_cloudProjectsFeatureEnabled) {
      _clearCloudProjectState();
      _cloudRefreshInFlight = null;
      completer.complete();
      return;
    }
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn) {
      _clearCloudProjectState();
      _cloudRefreshInFlight = null;
      completer.complete();
      return;
    }
    if (showLoading) {
      _cloudLoading = true;
    }
    try {
      final snapshot = await _cloudProjectService.listProjects(auth: auth);
      _cloudProjects = snapshot.cloudProjects;
      _cloudStorage = snapshot.storage;
      _cloudError = null;
    } catch (e) {
      _cloudError = _cleanCloudError(e);
    } finally {
      if (showLoading) {
        _cloudLoading = false;
      }
      _cloudRefreshInFlight = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _persistCloudLinksForLocalMatches() async {
    if (!_cloudProjectsFeatureEnabled) return;
    if (_projects.isEmpty || _cloudProjects.isEmpty) return;
    for (final cloud in _cloudProjects) {
      if (!cloud.isBundleStorage) continue;
      final local = _localProjectForCloud(cloud);
      if (local == null) continue;
      final currentCloudProjectId = (local.cloudProjectId ?? '').trim();
      if (currentCloudProjectId == cloud.projectId &&
          local.cloudDocumentRevision == cloud.documentRevision) {
        continue;
      }
      try {
        final json = await ProjectManager.readProjectJson(local.dir);
        final jsonCloudProjectId =
            (json['cloudProjectId'] ?? json['cloud_project_id'] ?? '')
                .toString()
                .trim();
        final rawJsonCloudRevision =
            json['cloudDocumentRevision'] ?? json['cloud_document_revision'];
        final jsonCloudRevision = rawJsonCloudRevision is num
            ? rawJsonCloudRevision.toInt()
            : int.tryParse((rawJsonCloudRevision ?? '').toString().trim());
        if (jsonCloudProjectId == cloud.projectId &&
            jsonCloudRevision == cloud.documentRevision) {
          continue;
        }
        // A cloud-list refresh only discovers that a newer revision exists.
        // It must not mark an older local bundle as current without first
        // downloading that bundle. Doing so can make a mobile opener select
        // stale plugin source instead of its compatible audio projection.
        if (jsonCloudProjectId == cloud.projectId &&
            jsonCloudRevision != null &&
            jsonCloudRevision != cloud.documentRevision) {
          continue;
        }
        json['cloudProjectId'] = cloud.projectId;
        json['cloudDocumentRevision'] = cloud.documentRevision;
        json['cloudSyncedAt'] = (cloud.updatedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String();
        await ProjectManager.writeProjectJson(local.dir, json);
      } catch (error) {
        debugPrint('Failed to persist local cloud project link: $error');
      }
    }
  }

  Future<void> _openProject(
    Directory dir, {
    AudioEditorInitialAction? initialAction,
    bool checkCloud = true,
  }) async {
    if (!checkCloud || initialAction != null) {
      await _pushEditor(dir, initialAction: initialAction);
      return;
    }

    final meta = _projectMetaForDirectory(dir);
    final linkedCloudProjectId = (meta?.cloudProjectId ?? '').trim();
    var signedIn = false;
    try {
      signedIn = context.read<AuthService>().isSignedIn;
    } catch (_) {}

    if (meta == null ||
        linkedCloudProjectId.isEmpty ||
        !_cloudProjectsFeatureEnabled ||
        !signedIn) {
      await _pushEditor(dir);
      return;
    }

    await _openLinkedLocalProject(meta);
  }

  ProjectMeta? _projectMetaForDirectory(Directory dir) {
    final path = p.normalize(dir.path);
    for (final project in _projects) {
      if (p.normalize(project.dir.path) == path) return project;
    }
    return null;
  }

  Future<void> _pushEditor(
    Directory dir, {
    AudioEditorInitialAction? initialAction,
    bool includeCloud = false,
  }) async {
    showLoadingDialog(
      context,
      message: L10n.translate(
        context,
        initialAction == null ? 'Opening project…' : 'Preparing export…',
      ),
    );

    // TODO: also an arbitrary delay to hide the blocking UI lag involved in opening the project
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    await Navigator.push(
      context,
      _NoSwipeMaterialPageRoute(
        builder: (_) => AudioEditorScreen(
          mode: 'Pro',
          projectDir: dir,
          initialAction: initialAction,
          onUpgradeRequested: widget.onUpgradeRequested,
        ),
      ),
    );
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await _refresh(includeCloud: includeCloud);
  }

  Future<void> _openLinkedLocalProject(ProjectMeta meta) async {
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Checking for updates…'),
    );
    CloudProjectAccessItem? cloud;
    try {
      final auth = context.read<AuthService>();
      final snapshot = await _cloudProjectService
          .listProjects(auth: auth)
          .timeout(kCloudOpenCheckTimeout);
      if (!mounted) return;
      setState(() {
        _cloudProjects = snapshot.cloudProjects;
        _cloudStorage = snapshot.storage;
        _cloudError = null;
      });
      cloud = _cloudProjectForLocal(meta);
    } catch (error) {
      debugPrint('Cloud update check failed: $error');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          "Couldn't check for cloud updates. Opened the copy on this device.",
        ),
        tone: AppPopupTone.warning,
      );
      if (!isNetworkUnavailableError(error)) {
        debugPrint('Cloud update check failed with non-network error: $error');
      }
      await _pushEditor(meta.dir);
      return;
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (!mounted) return;
    await _applyLocalOpenAction(meta: meta, cloud: cloud);
  }

  Future<void> _applyLocalOpenAction({
    required ProjectMeta meta,
    required CloudProjectAccessItem? cloud,
  }) async {
    switch (resolveLocalOpenAction(project: meta, cloud: cloud)) {
      case LocalOpenAction.openLocal:
        await _pushEditor(meta.dir);
      case LocalOpenAction.updateInPlace:
        await _updateLocalProjectFromCloud(local: meta, cloud: cloud!);
      case LocalOpenAction.askUser:
        final choice = await _showLocalCloudConflictDialog();
        if (!mounted) return;
        switch (choice) {
          case _LocalCloudConflictChoice.keepDevice:
            await _pushEditor(meta.dir);
          case _LocalCloudConflictChoice.takeCloud:
            await _updateLocalProjectFromCloud(local: meta, cloud: cloud!);
          case _LocalCloudConflictChoice.keepBoth:
            await _keepBothLocalAndCloud(local: meta, cloud: cloud!);
          case null:
            return;
        }
    }
  }

  Future<void> _updateLocalProjectFromCloud({
    required ProjectMeta local,
    required CloudProjectAccessItem cloud,
  }) async {
    if (_cloudProjectsInFlight.contains(cloud.projectId)) return;
    setState(() => _cloudProjectsInFlight.add(cloud.projectId));
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Downloading update…'),
    );
    try {
      await _projectVersionStore.maybeCreateSnapshot(
        projectDir: local.dir,
        reason: ProjectVersionReason.cloudUpdate,
        minInterval: Duration.zero,
      );
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final downloaded = await _cloudProjectService.downloadBundle(
        auth: auth,
        project: cloud,
      );
      await ProjectBundleImport.updateProjectFromMixroomBundle(
        projectDir: local.dir,
        bundleFile: downloaded.file,
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );
      await _writeCloudLinkMetadata(
        projectDir: local.dir,
        cloud: downloaded.project,
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      await _pushEditor(local.dir, includeCloud: true);
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Cloud download failed. Your project was left unchanged')}: ${_cleanCloudError(e)}',
        tone: AppPopupTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _cloudProjectsInFlight.remove(cloud.projectId));
      } else {
        _cloudProjectsInFlight.remove(cloud.projectId);
      }
    }
  }

  Future<void> _writeCloudLinkMetadata({
    required Directory projectDir,
    required CloudProjectAccessItem cloud,
  }) async {
    final json = await ProjectManager.readProjectJson(projectDir);
    json['cloudProjectId'] = cloud.projectId;
    if (cloud.workspaceId.trim().isNotEmpty) {
      json['cloudWorkspaceId'] = cloud.workspaceId.trim();
    } else {
      json.remove('cloudWorkspaceId');
    }
    if (cloud.organizationId.trim().isNotEmpty) {
      json['cloudOrganizationId'] = cloud.organizationId.trim();
    } else {
      json.remove('cloudOrganizationId');
    }
    json['cloudDocumentRevision'] = cloud.documentRevision;
    json['cloudSyncedAt'] = DateTime.now().toUtc().toIso8601String();
    json['cloudChangeFingerprint'] =
        ProjectCompatibilityService.cloudChangeFingerprint(json);
    json.remove('cloudSourceFingerprint');
    await ProjectManager.writeProjectJson(projectDir, json);
    await ProjectCompatibilityService.rebaseForImportedProject(
      projectDir: projectDir,
      sourceProject: json,
    );
  }

  Future<void> _keepBothLocalAndCloud({
    required ProjectMeta local,
    required CloudProjectAccessItem cloud,
  }) async {
    final canCreate = await ProjectManager.canCreateNew(
      maxProjects: _localProjectLimit(),
    );
    if (!mounted) return;
    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }
    final suffix = L10n.translate(context, ' (this device)');
    final renamedDir = await ProjectManager.renameProject(
      local.dir,
      '${local.name}$suffix',
    );
    final json = await ProjectManager.readProjectJson(renamedDir);
    ProjectManager.stripCloudSyncMetadata(json);
    ProjectManager.stripFamilyMetadata(json);
    ProjectManager.assignFreshProjectId(json);
    await ProjectManager.writeProjectJson(renamedDir, json);
    await _refresh();
    if (!mounted) return;
    await _downloadAndOpenNewCloudCopy(cloud);
  }

  Future<void> _downloadAndOpenNewCloudCopy(
    CloudProjectAccessItem cloud,
  ) async {
    final canCreate = await ProjectManager.canCreateNew(
      maxProjects: _localProjectLimit(),
    );
    if (!mounted) return;
    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }
    if (_cloudProjectsInFlight.contains(cloud.projectId)) return;
    setState(() => _cloudProjectsInFlight.add(cloud.projectId));
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Downloading from cloud…'),
    );
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final downloaded = await _cloudProjectService.downloadBundle(
        auth: auth,
        project: cloud,
      );
      final newDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: downloaded.file,
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );
      final json = await ProjectManager.readProjectJson(newDir);
      json['name'] = _downloadedCloudProjectDisplayName(
        cloud: cloud,
        resolvedName: (json['name'] ?? cloud.name).toString(),
      );
      await ProjectManager.writeProjectJson(newDir, json);
      await _writeCloudLinkMetadata(
        projectDir: newDir,
        cloud: downloaded.project,
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: 'Pro',
            projectDir: newDir,
            onUpgradeRequested: widget.onUpgradeRequested,
          ),
        ),
      );
      if (!mounted) return;
      await _refresh(includeCloud: true);
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Cloud download failed')}: ${_cleanCloudError(e)}',
        tone: AppPopupTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _cloudProjectsInFlight.remove(cloud.projectId));
      } else {
        _cloudProjectsInFlight.remove(cloud.projectId);
      }
    }
  }

  Future<FilePickerResult?> _pickFilesSafely({
    required FileType type,
    List<String>? allowedExtensions,
    bool withData = false,
  }) async {
    if (_filePickerInFlight) return null;
    _filePickerInFlight = true;
    try {
      // Avoid presenting a native picker during an active Flutter route transition.
      await SchedulerBinding.instance.endOfFrame;
      return await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        withData: withData,
      );
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
      try {
        return await FilePicker.platform.pickFiles(
          type: type,
          allowedExtensions: allowedExtensions,
          withData: withData,
        );
      } on PlatformException catch (retryError) {
        if (retryError.code == 'multiple_request') return null;
        rethrow;
      }
    } finally {
      _filePickerInFlight = false;
    }
  }

  Future<void> _renameProject(ProjectMeta meta) async {
    final controller = TextEditingController(text: meta.name);
    final focusNode = FocusNode(debugLabel: 'projects_rename');
    var focusScheduled = false;
    var dialogClosing = false;

    void closeWithResult(BuildContext ctx, String? result) {
      if (dialogClosing) return;
      dialogClosing = true;
      focusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ctx.mounted) return;
        Navigator.of(ctx).pop(result);
      });
    }

    try {
      final res = await showDialog<String>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          if (!focusScheduled) {
            focusScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!focusNode.canRequestFocus) return;
              focusNode.requestFocus();
            });
          }
          return MediaQuery.removeViewInsets(
            context: ctx,
            removeBottom: true,
            child: Dialog(
              key: _renameDialogKey,
              alignment: Alignment.topCenter,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: MixroomShellSurface(
                  radius: 30,
                  strong: true,
                  color: const Color.fromRGBO(244, 244, 244, 0.14),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(164, 194, 255, 0.16),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.drive_file_rename_outline_rounded,
                              color: Color(0xFFA4C2FF),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.translate(ctx, 'Rename Project'),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFFF4F4F4),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  L10n.translate(
                                    ctx,
                                    'Update the project title shown in your library.',
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(244, 244, 244, 0.10),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: TextField(
                          key: _renameFieldKey,
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            final value = controller.text.trim();
                            if (value.isNotEmpty) {
                              closeWithResult(ctx, value);
                            }
                          },
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: L10n.translate(ctx, 'Project name'),
                            hintStyle: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Colors.white.withValues(alpha: 0.46),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.folder_open_rounded,
                              size: 18,
                              color: Color(0xFFA4C2FF),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 46,
                              minHeight: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              key: _renameCancelKey,
                              onPressed: () => closeWithResult(ctx, null),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFF4F4F4),
                                backgroundColor: const Color.fromRGBO(
                                  244,
                                  244,
                                  244,
                                  0.08,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                              ),
                              child: Text(L10n.translate(ctx, 'Cancel')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: _renameSaveKey,
                              onPressed: () =>
                                  closeWithResult(ctx, controller.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary.withValues(
                                  alpha: 0.94,
                                ),
                                foregroundColor: cs.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(L10n.translate(ctx, 'Save')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (res == null) return;
      final newName = res.trim();
      if (newName.isEmpty) return;

      try {
        final renamedDir = await ProjectManager.renameProject(
          meta.dir,
          newName,
        );
        if (!projectIsFrozenMix(meta)) {
          await _renameLinkedFrozenMixIfFollowing(
            original: meta,
            oldName: meta.name,
            newName: newName,
          );
        }
        await _restoreCloudScopedDisplayNameIfAllowed(
          original: meta,
          renamedDir: renamedDir,
          requestedName: newName,
        );
        await _refresh();

        if (!mounted) return;
        showAppSnackBar(
          context,
          L10n.translate(context, 'Project renamed'),
          tone: AppPopupTone.success,
        );
      } catch (e) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          '${L10n.translate(context, 'Rename failed')}: $e',
          tone: AppPopupTone.error,
        );
      }
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        controller.dispose();
        focusNode.dispose();
      });
    }
  }

  String _projectSelectionKey(ProjectMeta meta) => meta.dir.path;

  bool _isSelected(ProjectMeta meta) =>
      _selectedProjectPaths.contains(_projectSelectionKey(meta));

  bool _isBundledDemoSelected(BundledDemoProjectAsset demo) =>
      _selectedBundledDemoAssetPaths.contains(demo.assetPath);

  int get _selectedEntryCount =>
      _selectedProjectPaths.length + _selectedBundledDemoAssetPaths.length;

  bool get _selectionMode => _selectionModePinned || _selectedEntryCount > 0;

  List<ProjectFamilyGroup> _visibleProjectGroups() {
    final query = _searchController.text.trim();
    final filtered = groupProjectsByFamily(
      _projects,
    ).where((group) => group.matchesQuery(query)).toList();
    switch (_sortMode) {
      case _ProjectSortMode.alphabetical:
        filtered.sort(
          (a, b) => a.displayProject.name.toLowerCase().compareTo(
            b.displayProject.name.toLowerCase(),
          ),
        );
        break;
      case _ProjectSortMode.recent:
        filtered.sort((a, b) => b.sortOpenedAt.compareTo(a.sortOpenedAt));
        break;
    }
    return filtered;
  }

  ProjectFamilyGroup _familyGroupContaining(ProjectMeta meta) {
    for (final group in groupProjectsByFamily(_projects)) {
      if (group.members.any((member) => member.dir.path == meta.dir.path)) {
        return group;
      }
    }
    return ProjectFamilyGroup(members: <ProjectMeta>[meta]);
  }

  void _toggleFamilyExpansion(ProjectFamilyGroup group) {
    final familyId = group.familyId;
    if (familyId == null || !group.canExpand) return;
    setState(() {
      if (_expandedFamilyIds.contains(familyId)) {
        _expandedFamilyIds.remove(familyId);
      } else {
        _expandedFamilyIds.add(familyId);
      }
    });
  }

  bool _isFamilyExpanded(ProjectFamilyGroup group) {
    final familyId = group.familyId;
    if (familyId == null) return false;
    return _expandedFamilyIds.contains(familyId);
  }

  bool _isFamilySelected(ProjectFamilyGroup group) {
    return group.members.every(_isSelected);
  }

  void _toggleFamilySelection(ProjectFamilyGroup group) {
    setState(() {
      final selected = _isFamilySelected(group);
      for (final member in group.members) {
        final key = _projectSelectionKey(member);
        if (selected) {
          _selectedProjectPaths.remove(key);
        } else {
          _selectedProjectPaths.add(key);
        }
      }
    });
  }

  List<BundledDemoProjectAsset> _visibleBundledDemoProjects() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _bundledDemoProjects.where((demo) {
      if (query.isEmpty) return true;
      return demo.name.toLowerCase().contains(query);
    }).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  ProjectMeta? _localProjectForCloud(CloudProjectAccessItem cloud) {
    for (final project in _projects) {
      if ((project.cloudProjectId ?? '').trim() == cloud.projectId) {
        return project;
      }
    }
    for (final project in _projects) {
      if (project.projectId.trim().isNotEmpty &&
          project.projectId == cloud.localProjectId) {
        return project;
      }
      if (project.projectId.trim().isNotEmpty &&
          project.projectId == cloud.projectId) {
        return project;
      }
    }
    return null;
  }

  CloudProjectAccessItem? _cloudProjectForLocal(ProjectMeta meta) {
    final cloudProjectId = (meta.cloudProjectId ?? '').trim();
    if (cloudProjectId.isNotEmpty) {
      for (final project in _cloudProjects) {
        if (!project.isBundleStorage) continue;
        if (project.projectId == cloudProjectId) {
          return project;
        }
      }
    }
    for (final project in _cloudProjects) {
      if (!project.isBundleStorage) continue;
      if (meta.projectId.trim().isNotEmpty &&
          project.localProjectId == meta.projectId) {
        return project;
      }
      if (meta.projectId.trim().isNotEmpty &&
          project.projectId == meta.projectId) {
        return project;
      }
    }
    return null;
  }

  List<_CloudProjectDestination> _availableCloudDestinations(
    EntitlementService entitlement,
  ) {
    final organizationsById = {
      for (final org in entitlement.effectiveOrganizations)
        org.organizationId: org,
    };
    final seenWorkspaceIds = <String>{''};
    final destinations = <_CloudProjectDestination>[
      const _CloudProjectDestination.personal(),
    ];
    for (final workspace in entitlement.effectiveWorkspaces) {
      final workspaceId = workspace.workspaceId.trim();
      if (workspaceId.isEmpty || !seenWorkspaceIds.add(workspaceId)) continue;
      final organization = organizationsById[workspace.organizationId];
      final orgName = (organization?.name ?? '').trim();
      final planLabel = (organization?.planLabel ?? '').trim();
      final canWrite = workspace.canWrite && (organization?.canWrite ?? true);
      final label = orgName.isNotEmpty ? orgName : workspace.name;
      destinations.add(
        _CloudProjectDestination.workspace(
          workspaceId: workspaceId,
          organizationId: workspace.organizationId,
          label: label.isEmpty ? 'Shared Cloud' : label,
          subtitle: canWrite
              ? (planLabel.isEmpty ? 'Shared cloud project space' : planLabel)
              : 'Read-only cloud storage',
          canWrite: canWrite,
          status: workspace.status.trim().isNotEmpty
              ? workspace.status.trim().toLowerCase()
              : (organization?.status ?? 'active').trim().toLowerCase(),
        ),
      );
    }
    final storage = _cloudStorage;
    if (storage != null) {
      for (final location in storage.locations) {
        final workspaceId = location.workspaceId.trim();
        if (workspaceId.isEmpty || !seenWorkspaceIds.add(workspaceId)) continue;
        final planLabel = defaultPlanLabelForCode(location.planCode);
        destinations.add(
          _CloudProjectDestination.workspace(
            workspaceId: workspaceId,
            organizationId: location.organizationId,
            label: location.label.trim().isEmpty
                ? 'Shared Cloud'
                : location.label.trim(),
            subtitle: location.canWrite
                ? (planLabel.isEmpty ? 'Shared cloud project space' : planLabel)
                : 'Read-only cloud storage',
            canWrite: location.canWrite,
            status: _cloudStorageLocationStatus(location),
          ),
        );
      }
    }
    return destinations;
  }

  String _cloudStorageLocationStatus(CloudProjectStorageLocation location) {
    for (final status in <String>[
      location.workspaceStatus,
      location.organizationStatus,
      location.status,
    ]) {
      final normalized = status.trim().toLowerCase();
      if (normalized.isNotEmpty) return normalized;
    }
    return 'active';
  }

  _CloudProjectDestination _destinationForCloudProject(
    CloudProjectAccessItem cloud,
    EntitlementService entitlement,
  ) {
    final workspaceId = cloud.workspaceId.trim();
    if (workspaceId.isEmpty) return const _CloudProjectDestination.personal();
    for (final destination in _availableCloudDestinations(entitlement)) {
      if (destination.workspaceId == workspaceId) return destination;
    }
    return _CloudProjectDestination.workspace(
      workspaceId: workspaceId,
      organizationId: cloud.organizationId,
      label: 'Shared Cloud',
      subtitle: 'Team project space',
      canWrite: cloud.canWrite,
      status: cloud.canWrite ? 'active' : 'locked',
    );
  }

  _CloudProjectDestination _selectedCloudDestination(
    EntitlementService entitlement,
  ) {
    final destinations = _availableCloudDestinations(entitlement);
    for (final destination in destinations) {
      if (destination.workspaceId == _selectedCloudWorkspaceId) {
        return destination;
      }
    }
    return destinations.first;
  }

  bool _cloudProjectIsInDestination(
    CloudProjectAccessItem project,
    _CloudProjectDestination destination,
  ) {
    return project.workspaceId.trim() == destination.workspaceId;
  }

  Future<_CloudProjectDestination?> _resolveCloudSyncDestination({
    required ProjectMeta meta,
    required EntitlementService entitlement,
    required bool promptForNewProject,
  }) async {
    final existing = _cloudProjectForLocal(meta);
    if (existing != null && !promptForNewProject) {
      return _destinationForCloudProject(existing, entitlement);
    }
    final destinations = _availableCloudDestinations(entitlement);
    final writableDestinations = destinations
        .where((destination) => destination.canWrite)
        .toList(growable: false);
    if (destinations.length <= 1) {
      return existing == null
          ? destinations.first
          : _destinationForCloudProject(existing, entitlement);
    }
    if (!promptForNewProject) {
      for (final destination in destinations) {
        if (destination.workspaceId == _selectedCloudWorkspaceId &&
            destination.canWrite) {
          return destination;
        }
      }
      return writableDestinations.isNotEmpty
          ? writableDestinations.first
          : destinations.first;
    }
    if (!mounted) return null;
    final selected = await showModalBottomSheet<_CloudProjectDestination>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: MixroomShellSurface(
              radius: 28,
              strong: true,
              color: const Color.fromRGBO(24, 24, 28, 0.96),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'Save project to' : 'Sync project to',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final destination in destinations)
                    ListTile(
                      enabled: destination.canWrite,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(
                        destination.icon,
                        color: destination.canWrite
                            ? const Color(0xFFA4C2FF)
                            : Colors.white.withValues(alpha: 0.48),
                      ),
                      title: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: destination.canWrite
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.58),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        _destinationSubtitle(
                          destination: destination,
                          existing: existing,
                          entitlement: entitlement,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.64),
                        ),
                      ),
                      onTap: destination.canWrite
                          ? () => Navigator.of(context).pop(destination)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await _setSelectedCloudWorkspace(selected.workspaceId);
    }
    return selected;
  }

  Future<void> _showCloudLocationSelector(
    List<_CloudProjectDestination> destinations, {
    required GlobalKey anchorKey,
  }) async {
    if (!mounted) return;
    final entitlement = context.read<EntitlementService>();
    final selectedDestination = _selectedCloudDestination(entitlement);
    final selected = await _showAnchoredShellMenu<_CloudProjectDestination>(
      anchorKey: anchorKey,
      width: 280,
      estimatedHeight: 58.0 + destinations.length * 58.0,
      child: Material(
        color: Colors.transparent,
        child: MixroomShellSurface(
          radius: 22,
          strong: true,
          color: const Color.fromRGBO(24, 24, 28, 0.96),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                child: Text(
                  L10n.translate(context, 'Cloud Location'),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final destination in destinations) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).pop(destination),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color:
                            destination.workspaceId ==
                                selectedDestination.workspaceId
                            ? const Color(0xFFA4C2FF).withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            destination.icon,
                            color: const Color(0xFFA4C2FF),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  destination.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFFF4F4F4),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  L10n.translate(context, destination.subtitle),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.62),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (destination.workspaceId ==
                              selectedDestination.workspaceId)
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (destination != destinations.last) const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await _setSelectedCloudWorkspace(selected.workspaceId);
    }
  }

  String _destinationSubtitle({
    required _CloudProjectDestination destination,
    required CloudProjectAccessItem? existing,
    required EntitlementService entitlement,
  }) {
    if (!destination.canWrite) {
      return L10n.translate(context, 'Read-only cloud storage');
    }
    if (existing != null) {
      final current = _destinationForCloudProject(existing, entitlement);
      if (current.workspaceId == destination.workspaceId) {
        return 'Current cloud location';
      }
      return 'Create a new cloud copy here';
    }
    return destination.subtitle;
  }

  String _cloudProjectLocationLabel(CloudProjectAccessItem cloud) {
    final destination = _destinationForCloudProject(
      cloud,
      context.read<EntitlementService>(),
    );
    return destination.label;
  }

  String _cloudProjectPersonLabel(
    CloudProjectUserSummary profile,
    String fallbackUserId,
  ) {
    if (profile.hasLabel) return profile.label;
    final safeUserId = fallbackUserId.trim();
    if (safeUserId.isEmpty) return L10n.translate(context, 'Unknown member');
    if (safeUserId.length <= 8) return safeUserId;
    return '${safeUserId.substring(0, 8)}…';
  }

  String? _cloudProjectAttributionLine(CloudProjectAccessItem cloud) {
    if (cloud.workspaceId.trim().isEmpty) return null;
    final owner = _cloudProjectPersonLabel(
      cloud.ownerProfile,
      cloud.ownerUserId,
    );
    final editorUserId = cloud.updatedByUserId.trim().isNotEmpty
        ? cloud.updatedByUserId
        : cloud.ownerUserId;
    final editor = _cloudProjectPersonLabel(
      cloud.updatedByProfile,
      editorUserId,
    );
    if (editorUserId.trim().isNotEmpty && editorUserId == cloud.ownerUserId) {
      return L10n.translate(
        context,
        'Created and edited by {user}',
      ).replaceAll('{user}', owner);
    }
    return L10n.translate(
      context,
      'Created by {owner} • Edited by {editor}',
    ).replaceAll('{owner}', owner).replaceAll('{editor}', editor);
  }

  bool _hasCloudReference(ProjectMeta meta) {
    return (meta.cloudProjectId ?? '').trim().isNotEmpty ||
        _cloudProjectForLocal(meta) != null;
  }

  String _workspaceIdForLocalCloudProject(
    ProjectMeta meta, {
    CloudProjectAccessItem? cloud,
  }) {
    return (cloud?.workspaceId ?? meta.cloudWorkspaceId ?? '').trim();
  }

  String _cloudLocationLabelForWorkspaceId(
    String workspaceId, {
    CloudProjectAccessItem? cloud,
  }) {
    final normalized = workspaceId.trim();
    if (normalized.isEmpty) {
      return const _CloudProjectDestination.personal().label;
    }
    final entitlement = context.read<EntitlementService>();
    for (final destination in _availableCloudDestinations(entitlement)) {
      if (destination.workspaceId == normalized) return destination.label;
    }
    if (cloud != null) {
      return _destinationForCloudProject(cloud, entitlement).label;
    }
    return 'Shared Cloud';
  }

  String? _localCloudLocationLabel(
    ProjectMeta meta,
    CloudProjectAccessItem? cloud,
  ) {
    if (!_hasCloudReference(meta)) return null;
    return _cloudLocationLabelForWorkspaceId(
      _workspaceIdForLocalCloudProject(meta, cloud: cloud),
      cloud: cloud,
    );
  }

  _LocalCloudStatusPresentation _localCloudStatus(
    ProjectMeta meta,
    CloudProjectAccessItem? cloud, {
    bool syncInProgress = false,
  }) {
    final location = _localCloudLocationLabel(meta, cloud);
    if (syncInProgress) {
      final baseLabel = L10n.translate(context, 'Syncing to cloud…');
      return _LocalCloudStatusPresentation(
        label: location == null || location.isEmpty
            ? baseLabel
            : '$baseLabel • $location',
        statusLabel: baseLabel,
        icon: Icons.sync_rounded,
        color: const Color(0xFFA4C2FF),
      );
    }
    final freshness = resolveProjectCloudFreshness(
      project: meta,
      cloudStatusAvailable: cloud != null,
      latestCloudRevision: cloud?.documentRevision,
    );
    late final String baseLabel;
    late final IconData icon;
    late final Color color;
    switch (freshness) {
      case ProjectCloudFreshness.diverged:
        baseLabel = L10n.translate(context, 'Not synced');
        icon = Icons.cloud_outlined;
        color = const Color(0xFFC7B8FF);
      case ProjectCloudFreshness.cloudAhead:
        baseLabel = L10n.translate(context, 'Cloud update available');
        icon = Icons.cloud_download_rounded;
        color = const Color(0xFFFFC56E);
      case ProjectCloudFreshness.localChanges:
        baseLabel = L10n.translate(context, 'Not synced');
        icon = Icons.cloud_outlined;
        color = const Color(0xFFC7B8FF);
      case ProjectCloudFreshness.linkedUnknown:
        baseLabel = L10n.translate(context, 'Sync status unknown');
        icon = Icons.cloud_outlined;
        color = const Color(0xFFC7B8FF);
      case ProjectCloudFreshness.synced:
        baseLabel = L10n.translate(context, 'Cloud synced');
        icon = Icons.cloud_done_rounded;
        color = const Color(0xFFA4C2FF);
    }
    final label = location == null || location.isEmpty
        ? baseLabel
        : '$baseLabel • $location';
    return _LocalCloudStatusPresentation(
      label: label,
      statusLabel: baseLabel,
      icon: icon,
      color: color,
    );
  }

  Widget _buildLocalCloudStatusIcon(_LocalCloudStatusPresentation status) =>
      Icon(status.icon, color: status.color, size: 18);

  bool _cloudScopedDisplayNameAllowed({
    required ProjectMeta original,
    required String requestedName,
  }) {
    final desired = requestedName.trim().toLowerCase();
    if (desired.isEmpty || !_hasCloudReference(original)) return false;
    final originalWorkspaceId = _workspaceIdForLocalCloudProject(
      original,
      cloud: _cloudProjectForLocal(original),
    );
    final originalPath = original.dir.path;
    for (final project in _projects) {
      if (project.dir.path == originalPath) continue;
      if (project.name.trim().toLowerCase() != desired) continue;
      if (!_hasCloudReference(project)) return false;
      final projectWorkspaceId = _workspaceIdForLocalCloudProject(
        project,
        cloud: _cloudProjectForLocal(project),
      );
      if (projectWorkspaceId == originalWorkspaceId) return false;
    }
    return true;
  }

  Future<void> _restoreCloudScopedDisplayNameIfAllowed({
    required ProjectMeta original,
    required Directory renamedDir,
    required String requestedName,
  }) async {
    final trimmed = requestedName.trim();
    if (trimmed.isEmpty) return;
    if (!_cloudScopedDisplayNameAllowed(
      original: original,
      requestedName: trimmed,
    )) {
      return;
    }
    final json = await ProjectManager.readProjectJson(renamedDir);
    json['name'] = trimmed;
    await ProjectManager.writeProjectJson(renamedDir, json);
  }

  String _downloadedCloudProjectDisplayName({
    required CloudProjectAccessItem cloud,
    required String resolvedName,
  }) {
    final desiredName = cloud.name.trim();
    if (desiredName.isEmpty) return resolvedName;
    final desiredLower = desiredName.toLowerCase();
    final cloudWorkspaceId = cloud.workspaceId.trim();
    for (final project in _projects) {
      if (project.name.trim().toLowerCase() != desiredLower) continue;
      if (!_hasCloudReference(project)) return resolvedName;
      final projectWorkspaceId = _workspaceIdForLocalCloudProject(
        project,
        cloud: _cloudProjectForLocal(project),
      );
      if (projectWorkspaceId == cloudWorkspaceId) return resolvedName;
    }
    return desiredName;
  }

  bool _localCloudSyncInFlight(
    ProjectMeta meta,
    CloudProjectAccessItem? cloud,
  ) {
    final projectId = meta.projectId.trim();
    final cloudProjectId = (meta.cloudProjectId ?? '').trim();
    final editorSyncs = ProjectManager.cloudProjectSyncInFlight.value;
    return (projectId.isNotEmpty &&
            (_cloudProjectsInFlight.contains(projectId) ||
                editorSyncs.contains(projectId) ||
                _settlingCloudProjectSyncs.contains(projectId))) ||
        (cloudProjectId.isNotEmpty &&
            (_cloudProjectsInFlight.contains(cloudProjectId) ||
                editorSyncs.contains(cloudProjectId) ||
                _settlingCloudProjectSyncs.contains(cloudProjectId))) ||
        (cloud != null &&
            (_cloudProjectsInFlight.contains(cloud.projectId) ||
                editorSyncs.contains(cloud.projectId) ||
                _settlingCloudProjectSyncs.contains(cloud.projectId)));
  }

  String? _syncQuotaErrorForBundle(
    ProjectMeta meta,
    int bundleSizeBytes, {
    required _CloudProjectDestination destination,
  }) {
    final storage = _cloudStorage;
    if (storage == null) return null;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    final existing = _cloudProjectForLocal(meta);
    final projectLimit = storageLocation?.projectLimit ?? storage.projectLimit;
    if (existing == null && projectLimit != null) {
      final activeCloudProjects = _cloudProjects.where(
        (project) =>
            project.isBundleStorage &&
            _cloudProjectIsInDestination(project, destination),
      );
      if (activeCloudProjects.length >= projectLimit) {
        return 'Cloud project limit reached for your current plan.';
      }
    }

    final limitBytes = storageLocation?.limitBytes ?? storage.limitBytes;
    if (limitBytes == null || limitBytes < 0) return null;
    final currentUsedBytes = _cloudStorageUsedBytesForDestination(destination);
    final replacingBytes =
        existing != null && _cloudProjectIsInDestination(existing, destination)
        ? existing.documentSizeBytes
        : 0;
    final projectedUsedBytes =
        currentUsedBytes - replacingBytes + bundleSizeBytes;
    if (projectedUsedBytes > limitBytes) {
      return 'Cloud storage limit reached for your current plan.';
    }
    return null;
  }

  void _showUpgradeRequired({
    required String title,
    required String message,
    IconData icon = Icons.lock_outline_rounded,
  }) {
    unawaited(
      showAppUpgradeDialog(
        context: context,
        title: title,
        message: message,
        icon: icon,
        onUpgrade: widget.onUpgradeRequested,
      ),
    );
  }

  List<CloudProjectAccessItem> _visibleCloudProjects() {
    final query = _searchController.text.trim().toLowerCase();
    final entitlement = context.read<EntitlementService>();
    final selectedDestination = _selectedCloudDestination(entitlement);
    final filtered = _cloudProjects.where((project) {
      if (!project.isBundleStorage) return false;
      if (!_cloudProjectIsInDestination(project, selectedDestination)) {
        return false;
      }
      if (query.isEmpty) return true;
      if (project.name.toLowerCase().contains(query)) return true;
      final frozen = localFrozenMixSibling(
        projects: _projects,
        localProject: _localProjectForCloud(project),
      );
      return frozen != null && frozen.name.toLowerCase().contains(query);
    }).toList();
    int compareLocation(CloudProjectAccessItem a, CloudProjectAccessItem b) {
      final aLabel = _destinationForCloudProject(a, entitlement).label;
      final bLabel = _destinationForCloudProject(b, entitlement).label;
      return aLabel.toLowerCase().compareTo(bLabel.toLowerCase());
    }

    switch (_sortMode) {
      case _ProjectSortMode.alphabetical:
        filtered.sort((a, b) {
          final location = compareLocation(a, b);
          if (location != 0) return location;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case _ProjectSortMode.recent:
        filtered.sort((a, b) {
          final location = compareLocation(a, b);
          if (location != 0) return location;
          final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
        break;
    }
    return filtered;
  }

  List<_ProjectListEntry> _visibleEntries() {
    return _visibleEntriesForTab(_libraryTab);
  }

  List<_ProjectListEntry> _visibleEntriesForTab(_ProjectLibraryTab tab) {
    switch (tab) {
      case _ProjectLibraryTab.yourProjects:
        return _visibleProjectGroups().map(_ProjectListEntry.family).toList();
      case _ProjectLibraryTab.cloudProjects:
        if (!_cloudProjectsFeatureEnabled) return const <_ProjectListEntry>[];
        return _visibleCloudProjects().map(_ProjectListEntry.cloud).toList();
      case _ProjectLibraryTab.demoProjects:
        return _visibleBundledDemoProjects()
            .map(_ProjectListEntry.bundledDemo)
            .toList();
    }
  }

  void _toggleSelection(ProjectMeta meta) {
    final key = _projectSelectionKey(meta);
    setState(() {
      if (_selectedProjectPaths.contains(key)) {
        _selectedProjectPaths.remove(key);
      } else {
        _selectedProjectPaths.add(key);
      }
    });
  }

  void _clearSelection() {
    if (!_selectionModePinned && _selectedEntryCount == 0) return;
    setState(() {
      _selectionModePinned = false;
      _selectedProjectPaths.clear();
      _selectedBundledDemoAssetPaths.clear();
    });
  }

  void _toggleSelectionMode() {
    if (_selectionMode) {
      _clearSelection();
      return;
    }
    setState(() => _selectionModePinned = true);
  }

  void _setLibraryTab(_ProjectLibraryTab tab, {bool animatePage = true}) {
    if (tab == _ProjectLibraryTab.cloudProjects &&
        !_cloudProjectsFeatureEnabled) {
      tab = _ProjectLibraryTab.yourProjects;
    }
    if (_libraryTab == tab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _libraryTab = tab;
      _selectionModePinned = false;
      _selectedProjectPaths.clear();
      _selectedBundledDemoAssetPaths.clear();
    });
    if (animatePage && _libraryPageController.hasClients) {
      unawaited(
        _libraryPageController.animateToPage(
          tab.index,
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (tab == _ProjectLibraryTab.cloudProjects) {
      unawaited(_refreshCloudProjectsForUi());
    }
  }

  void _handleLibraryPageChanged(int index) {
    final tabs = _ProjectLibraryTab.values;
    if (index < 0 || index >= tabs.length) return;
    _setLibraryTab(tabs[index], animatePage: false);
  }

  Future<void> _refreshCloudProjectsForUi() async {
    if (!mounted) return;
    if (!_cloudProjectsFeatureEnabled) {
      setState(() {
        _clearCloudProjectState();
      });
      return;
    }
    final hasCloudSnapshot = _cloudStorage != null || _cloudProjects.isNotEmpty;
    setState(() {
      _cloudError = null;
      if (!hasCloudSnapshot) {
        _cloudLoading = true;
      }
    });
    await _refreshCloudProjectsSilently(showLoading: !hasCloudSnapshot);
    if (!mounted) return;
    setState(() {});
  }

  void _selectAllVisible() {
    final visibleEntries = _visibleEntries();
    setState(() {
      _selectedProjectPaths.clear();
      _selectedBundledDemoAssetPaths.clear();
      for (final entry in visibleEntries) {
        if (entry.isBundledDemo) {
          final demo = entry.bundledDemo!;
          _selectedBundledDemoAssetPaths.add(demo.assetPath);
        } else if (entry.isCloudProject) {
          continue;
        } else {
          for (final project
              in entry.family?.members ?? const <ProjectMeta>[]) {
            _selectedProjectPaths.add(_projectSelectionKey(project));
          }
        }
      }
    });
  }

  void _toggleBundledDemoSelection(BundledDemoProjectAsset demo) {
    final key = demo.assetPath;
    setState(() {
      if (_selectedBundledDemoAssetPaths.contains(key)) {
        _selectedBundledDemoAssetPaths.remove(key);
      } else {
        _selectedBundledDemoAssetPaths.add(key);
      }
    });
  }

  Rect? _anchorRectFor(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final overlay = Navigator.of(
      this.context,
    ).overlay?.context.findRenderObject();
    if (overlay is! RenderBox) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    return origin & box.size;
  }

  Rect? _shareSheetOriginForCurrentContext() {
    final overlayContext = Navigator.of(context).overlay?.context;
    final overlayBox = overlayContext?.findRenderObject();
    if (overlayBox is RenderBox && overlayBox.hasSize) {
      final center = overlayBox.size.center(Offset.zero);
      return Rect.fromCenter(center: center, width: 1, height: 1);
    }

    final rootBox = context.findRenderObject();
    if (rootBox is RenderBox && rootBox.hasSize) {
      final center = rootBox.size.center(Offset.zero);
      return Rect.fromCenter(center: center, width: 1, height: 1);
    }

    return null;
  }

  Future<T?> _showAnchoredShellMenu<T>({
    required GlobalKey anchorKey,
    required Widget child,
    required double width,
    required double estimatedHeight,
  }) {
    final anchor = _anchorRectFor(anchorKey);
    if (anchor == null) {
      return Future<T?>.value(null);
    }
    final media = MediaQuery.of(context);
    final screen = media.size;
    final left = (anchor.right - width).clamp(12.0, screen.width - width - 12);
    double top = anchor.bottom + 10;
    final maxTop = screen.height - estimatedHeight - media.padding.bottom - 24;
    if (top > maxTop) {
      top = (anchor.top - estimatedHeight - 10).clamp(24.0, maxTop);
    }

    return showGeneralDialog<T>(
      context: context,
      barrierLabel: 'menu',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) {
        return Stack(
          children: [
            Positioned(left: left, top: top, width: width, child: child),
          ],
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            alignment: Alignment.topRight,
            child: child,
          ),
        );
      },
    );
  }

  Future<bool> _showDeleteProjectsDialog({
    required String message,
    Key? dialogKey,
    Key? cancelKey,
    Key? confirmKey,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return Dialog(
          key: dialogKey,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MixroomShellSurface(
              radius: 30,
              strong: true,
              color: const Color.fromRGBO(244, 244, 244, 0.14),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 119, 119, 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFF8D8D),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.translate(dialogContext, 'Delete project?'),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              L10n.translate(
                                dialogContext,
                                'This action cannot be undone.',
                              ),
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: cancelKey,
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFF4F4F4),
                            backgroundColor: const Color.fromRGBO(
                              244,
                              244,
                              244,
                              0.08,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                          ),
                          child: Text(L10n.translate(dialogContext, 'Cancel')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: confirmKey,
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(
                              196,
                              74,
                              74,
                              0.92,
                            ),
                            foregroundColor: const Color(0xFFFDF4F4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(L10n.translate(dialogContext, 'Delete')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result == true;
  }

  Future<_FamilyDeleteScope?> _showDeleteMixOrSongDialog({
    required String songName,
  }) async {
    return showDialog<_FamilyDeleteScope>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return Dialog(
          key: _deleteDialogKey,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MixroomShellSurface(
              radius: 30,
              strong: true,
              color: const Color.fromRGBO(244, 244, 244, 0.14),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 119, 119, 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFF8D8D),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.translate(dialogContext, 'Delete song?'),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              L10n.translate(
                                dialogContext,
                                'This action cannot be undone.',
                              ),
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '“$songName”. ${L10n.translate(dialogContext, 'Delete only this mix, or the original and Frozen mix?')}',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: _deleteCancelKey,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF4F4F4),
                        backgroundColor: const Color.fromRGBO(
                          244,
                          244,
                          244,
                          0.08,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                      child: Text(L10n.translate(dialogContext, 'Cancel')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: _deleteThisMixKey,
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_FamilyDeleteScope.mix),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color.fromRGBO(
                          244,
                          244,
                          244,
                          0.18,
                        ),
                        foregroundColor: const Color(0xFFF4F4F4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(L10n.translate(dialogContext, 'This mix')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: _deleteWholeSongKey,
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(_FamilyDeleteScope.song),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color.fromRGBO(
                          196,
                          74,
                          74,
                          0.92,
                        ),
                        foregroundColor: const Color(0xFFFDF4F4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(L10n.translate(dialogContext, 'Whole song')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showReplaceCloudVersionDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MixroomShellSurface(
              radius: 30,
              strong: true,
              color: const Color.fromRGBO(244, 244, 244, 0.14),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(107, 184, 255, 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          color: Color(0xFF8CC8FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L10n.translate(
                            dialogContext,
                            'Replace cloud version?',
                          ),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    L10n.translate(
                      dialogContext,
                      'The cloud copy changed on another device or account. Replace it with this device\'s version?',
                    ),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFF4F4F4),
                            backgroundColor: const Color.fromRGBO(
                              244,
                              244,
                              244,
                              0.08,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                          ),
                          child: Text(L10n.translate(dialogContext, 'Cancel')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF397DB5),
                            foregroundColor: const Color(0xFFF4F9FF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(L10n.translate(dialogContext, 'Replace')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result == true;
  }

  Future<_LocalCloudConflictChoice?> _showLocalCloudConflictDialog() {
    return showDialog<_LocalCloudConflictChoice>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        Widget option({
          required _LocalCloudConflictChoice choice,
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(dialogContext).pop(choice),
              borderRadius: BorderRadius.circular(18),
              splashColor: Colors.white.withValues(alpha: 0.12),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(244, 244, 244, 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(112, 139, 166, 0.28),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFFF4F4F4),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.translate(dialogContext, title),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: Color(0xFFF4F4F4),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            L10n.translate(dialogContext, subtitle),
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Colors.white.withValues(alpha: 0.66),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MixroomShellSurface(
              radius: 30,
              strong: true,
              color: const Color.fromRGBO(244, 244, 244, 0.14),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.translate(dialogContext, 'Project versions differ'),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    L10n.translate(
                      dialogContext,
                      'This project changed on this device and in the cloud.',
                    ),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  option(
                    choice: _LocalCloudConflictChoice.keepDevice,
                    icon: Icons.phone_iphone_rounded,
                    title: 'Keep this device',
                    subtitle: 'Open the copy on this device.',
                  ),
                  const SizedBox(height: 10),
                  option(
                    choice: _LocalCloudConflictChoice.takeCloud,
                    icon: Icons.cloud_download_rounded,
                    title: 'Take the cloud version',
                    subtitle: 'Replace this copy with the cloud version.',
                  ),
                  const SizedBox(height: 10),
                  option(
                    choice: _LocalCloudConflictChoice.keepBoth,
                    icon: Icons.copy_all_rounded,
                    title: 'Keep both',
                    subtitle:
                        'Save this copy as a second project, then open the cloud version.',
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(L10n.translate(dialogContext, 'Cancel')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isCloudRevisionConflict(Object error) {
    if (error is CloudProjectApiException) {
      final detail = '${error.message} ${error.body}'.toLowerCase();
      return detail.contains('revision conflict') ||
          (error.statusCode == 409 && detail.contains('revision'));
    }
    return error.toString().toLowerCase().contains('revision conflict');
  }

  Future<BundleAudioMode?> _chooseProjectBundleAudioMode() {
    return showDialog<BundleAudioMode>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        Widget option({
          required BundleAudioMode mode,
          required IconData icon,
          required String title,
          required String subtitle,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(dialogContext).pop(mode),
              borderRadius: BorderRadius.circular(18),
              splashColor: Colors.white.withValues(alpha: 0.12),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(244, 244, 244, 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(112, 139, 166, 0.28),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFFF4F4F4),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.translate(dialogContext, title),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              color: Color(0xFFF4F4F4),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            L10n.translate(dialogContext, subtitle),
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Colors.white.withValues(alpha: 0.66),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: MixroomShellSurface(
              radius: 30,
              strong: true,
              color: const Color.fromRGBO(244, 244, 244, 0.14),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.translate(dialogContext, 'Project bundle format'),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    L10n.translate(
                      dialogContext,
                      'Choose how audio should be packed into the .mixroom file.',
                    ),
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  option(
                    mode: BundleAudioMode.flacLossless,
                    icon: Icons.compress_rounded,
                    title: 'Lossless FLAC',
                    subtitle:
                        'Smaller file, keeps audio lossless, best for sharing.',
                  ),
                  const SizedBox(height: 10),
                  option(
                    mode: BundleAudioMode.preserveAsIs,
                    icon: Icons.folder_copy_outlined,
                    title: 'Original files',
                    subtitle:
                        'Keeps the current audio formats exactly as stored.',
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(L10n.translate(dialogContext, 'Cancel')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSelectedProjects() async {
    final selectedProjects = _projects
        .where((project) => _selectedProjectPaths.contains(project.dir.path))
        .toList();
    final selectedDemos = _bundledDemoProjects
        .where(
          (demo) => _selectedBundledDemoAssetPaths.contains(demo.assetPath),
        )
        .toList();
    final selectedCount = selectedProjects.length + selectedDemos.length;
    if (selectedCount == 0) return;
    final ok = await _showDeleteProjectsDialog(
      message:
          '$selectedCount ${L10n.translate(context, 'Projects')} ${L10n.translate(context, 'will be permanently deleted.')}',
    );
    if (!ok) return;
    for (final project in selectedProjects) {
      await ProjectManager.deleteProject(project.dir);
    }
    if (selectedDemos.isNotEmpty) {
      await ProjectManager.dismissBundledDemoAssets(
        selectedDemos.map((demo) => demo.assetPath),
      );
    }
    _clearSelection();
    await _refresh();
  }

  Future<void> _showProjectTools() async {
    final visibleEntries = _visibleEntries();
    final allVisibleSelected =
        visibleEntries.isNotEmpty &&
        visibleEntries.every((entry) {
          if (entry.isBundledDemo) {
            return _selectedBundledDemoAssetPaths.contains(
              entry.bundledDemo!.assetPath,
            );
          }
          if (entry.isCloudProject) return true;
          final members = entry.family?.members ?? const <ProjectMeta>[];
          if (members.isEmpty) return true;
          return members.every(
            (project) => _selectedProjectPaths.contains(project.dir.path),
          );
        });
    final selected = await _showAnchoredShellMenu<String>(
      anchorKey: _projectToolsButtonKey,
      width: 228,
      estimatedHeight: 204,
      child: Material(
        color: Colors.transparent,
        child: MixroomShellSurface(
          radius: 28,
          strong: true,
          color: const Color.fromRGBO(244, 244, 244, 0.16),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.translate(context, 'Projects'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _ProjectToolAction(
                icon: Icons.schedule_rounded,
                label: L10n.translate(context, 'Sort by recent'),
                onTap: () => Navigator.of(context).pop('sort_recent'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.sort_by_alpha_rounded,
                label: L10n.translate(context, 'Sort alphabetically'),
                onTap: () => Navigator.of(context).pop('sort_alpha'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: allVisibleSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                label: L10n.translate(
                  context,
                  allVisibleSelected ? 'Clear selection' : 'Select all',
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(allVisibleSelected ? 'clear' : 'select_all'),
              ),
            ],
          ),
        ),
      ),
    );
    switch (selected) {
      case 'sort_recent':
        setState(() => _sortMode = _ProjectSortMode.recent);
        return;
      case 'sort_alpha':
        setState(() => _sortMode = _ProjectSortMode.alphabetical);
        return;
      case 'clear':
        _clearSelection();
        return;
      case 'select_all':
        _selectAllVisible();
        return;
    }
  }

  Future<void> _showProjectItemMenu({
    required GlobalKey anchorKey,
    required ProjectMeta project,
  }) async {
    final selected = await _showAnchoredShellMenu<String>(
      anchorKey: anchorKey,
      width: 216,
      estimatedHeight: 332,
      child: Material(
        color: Colors.transparent,
        child: MixroomShellSurface(
          radius: 28,
          strong: true,
          color: const Color.fromRGBO(244, 244, 244, 0.16),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProjectToolAction(
                icon: Icons.drive_file_rename_outline_rounded,
                label: L10n.translate(context, 'Rename'),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.content_copy_rounded,
                label: L10n.translate(context, 'Duplicate'),
                onTap: () => Navigator.of(context).pop('duplicate'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.delete_outline_rounded,
                label: L10n.translate(
                  context,
                  _cloudProjectForLocal(project) == null
                      ? 'Delete'
                      : 'Delete from Device',
                ),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.history_rounded,
                label: L10n.translate(context, 'Version History'),
                onTap: () => Navigator.of(context).pop('version_history'),
              ),
              if (_cloudProjectsFeatureEnabled &&
                  !projectIsFrozenMix(project)) ...[
                const SizedBox(height: 4),
                _ProjectToolAction(
                  icon: Icons.cloud_upload_rounded,
                  label: L10n.translate(
                    context,
                    !_hasCloudReference(project) ? 'Sync to Cloud' : 'Sync Now',
                  ),
                  onTap: () => Navigator.of(context).pop('sync_cloud'),
                ),
              ],
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.download_rounded,
                label: L10n.translate(context, 'Save (.mixroom)'),
                onTap: () => Navigator.of(context).pop('save_mixroom'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.ios_share_rounded,
                label: L10n.translate(context, 'Share (.mixroom)'),
                onTap: () => Navigator.of(context).pop('share_mixroom'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.audio_file_outlined,
                label: L10n.translate(context, 'Export to Audio'),
                onTap: () => Navigator.of(context).pop('export_audio'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    await _handleCompactProjectMenuAction(selected, project);
  }

  Future<void> _showCloudProjectItemMenu({
    required GlobalKey anchorKey,
    required CloudProjectAccessItem project,
  }) async {
    final local = _localProjectForCloud(project);
    final selected = await _showAnchoredShellMenu<String>(
      anchorKey: anchorKey,
      width: 228,
      estimatedHeight: 196,
      child: Material(
        color: Colors.transparent,
        child: MixroomShellSurface(
          radius: 28,
          strong: true,
          color: const Color.fromRGBO(244, 244, 244, 0.16),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProjectToolAction(
                icon: Icons.info_outline_rounded,
                label: L10n.translate(context, 'View Details'),
                onTap: () => Navigator.of(context).pop('details'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: local == null
                    ? Icons.cloud_download_rounded
                    : Icons.folder_open_rounded,
                label: L10n.translate(
                  context,
                  local == null ? 'Download & Open' : 'Open',
                ),
                onTap: () => Navigator.of(context).pop('open'),
              ),
              if (project.canWrite) ...[
                const SizedBox(height: 4),
                _ProjectToolAction(
                  icon: Icons.delete_outline_rounded,
                  label: L10n.translate(context, 'Delete from Cloud'),
                  onTap: () => Navigator.of(context).pop('delete_cloud'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    switch (selected) {
      case 'details':
        await _showCloudProjectDetails(project);
        return;
      case 'open':
        await _openCloudProject(project);
        return;
      case 'delete_cloud':
        await _deleteCloudProject(project);
        return;
    }
  }

  Future<void> _showCloudProjectDetails(CloudProjectAccessItem project) async {
    final locationLabel = _cloudProjectLocationLabel(project);
    final owner = _cloudProjectPersonLabel(
      project.ownerProfile,
      project.ownerUserId,
    );
    final editorUserId = project.updatedByUserId.trim().isNotEmpty
        ? project.updatedByUserId
        : project.ownerUserId;
    final editor = _cloudProjectPersonLabel(
      project.updatedByProfile,
      editorUserId,
    );
    final createdAt = project.createdAt;
    final updatedAt = project.updatedAt;
    final createdValue = [
      owner,
      if (createdAt != null) _formatProjectVersionTimestamp(createdAt),
    ].join(' • ');
    final editedValue = [
      editor,
      if (updatedAt != null) _formatProjectVersionTimestamp(updatedAt),
    ].join(' • ');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottomInset),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 640,
                ),
                child: MixroomShellSurface(
                  radius: 28,
                  strong: true,
                  color: const Color.fromRGBO(244, 244, 244, 0.16),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.cloud_queue_rounded,
                            color: Color(0xFFA4C2FF),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              L10n.translate(context, 'Cloud Project Details'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MixroomShellRoundButton(
                            size: 34,
                            iconExtent: 18,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onTap: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _CloudProjectDetailRow(
                                icon: Icons.folder_open_rounded,
                                label: L10n.translate(context, 'Project Name'),
                                value: project.name,
                                maxValueLines: 8,
                              ),
                              _CloudProjectDetailRow(
                                icon: Icons.storage_rounded,
                                label: L10n.translate(context, 'Workspace'),
                                value: locationLabel,
                              ),
                              _CloudProjectDetailRow(
                                icon: project.canWrite
                                    ? Icons.edit_rounded
                                    : Icons.lock_rounded,
                                label: L10n.translate(context, 'Status'),
                                value: L10n.translate(
                                  context,
                                  project.canWrite ? 'Editable' : 'Read-only',
                                ),
                              ),
                              _CloudProjectDetailRow(
                                icon: Icons.person_outline_rounded,
                                label: L10n.translate(context, 'Created'),
                                value: createdValue,
                              ),
                              _CloudProjectDetailRow(
                                icon: Icons.edit_outlined,
                                label: L10n.translate(context, 'Last edited'),
                                value: editedValue,
                              ),
                              _CloudProjectDetailRow(
                                icon: Icons.data_object_rounded,
                                label: L10n.translate(context, 'Size'),
                                value: _formatBytes(project.documentSizeBytes),
                              ),
                              _CloudProjectDetailRow(
                                icon: Icons.history_rounded,
                                label: L10n.translate(
                                  context,
                                  'Number of Revisions',
                                ),
                                value: '${project.documentRevision}',
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
          ),
        );
      },
    );
  }

  Future<void> _renameLinkedFrozenMixIfFollowing({
    required ProjectMeta original,
    required String oldName,
    required String newName,
  }) async {
    final familyId = projectFamilyId(original);
    if (familyId == null) return;
    ProjectMeta? frozen;
    for (final project in _projects) {
      if (projectFamilyId(project) != familyId) continue;
      if (!projectIsFrozenMix(project)) continue;
      frozen = project;
      break;
    }
    if (frozen == null) return;
    if (!frozenMixNameFollowsOriginal(
      originalName: oldName,
      frozenName: frozen.name,
    )) {
      return;
    }
    await ProjectManager.renameProject(
      frozen.dir,
      ProjectManager.frozenMixDisplayName(newName),
    );
  }

  Future<void> _deleteProject(ProjectMeta meta) async {
    final group = _familyGroupContaining(meta);
    final deletingOriginalWithSibling =
        group.canExpand && !projectIsFrozenMix(meta);
    if (deletingOriginalWithSibling) {
      final scope = await _showDeleteMixOrSongDialog(
        songName: group.displayProject.name,
      );
      if (scope == null) return;
      if (scope == _FamilyDeleteScope.song) {
        for (final member in group.members) {
          await ProjectManager.deleteProject(member.dir);
        }
        await _refresh();
        return;
      }
    } else {
      final cloudBacked = _hasCloudReference(meta);
      final ok = await _showDeleteProjectsDialog(
        message: cloudBacked
            ? '“${meta.name}” ${L10n.translate(context, 'will be deleted from this device. The cloud copy will remain available.')}'
            : '“${meta.name}” ${L10n.translate(context, 'will be permanently deleted.')}',
        dialogKey: _deleteDialogKey,
        cancelKey: _deleteCancelKey,
        confirmKey: _deleteConfirmKey,
      );
      if (!ok) return;
    }
    await ProjectManager.deleteProject(meta.dir);
    await _refresh();
  }

  Future<void> _duplicateProject(ProjectMeta meta) async {
    try {
      await ProjectManager.duplicateProject(meta.dir);
      await _refresh();
      if (!mounted) return;
      showAppSnackBar(
        context,
        L10n.translate(context, 'Project duplicated'),
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Duplicate failed')}: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _shareProject(ProjectMeta meta) async {
    try {
      final bundlePath = await _exportProjectBundle(meta);
      if (bundlePath == null || !mounted) return;

      final params = ShareParams(
        files: [XFile(bundlePath)],
        sharePositionOrigin: _shareSheetOriginForCurrentContext(),
        // title: meta.name, // shows in some share UIs
        // subject: meta.name, // used by some email clients
      );

      await SharePlus.instance.share(params);
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Export failed')}: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _saveProjectBundle(ProjectMeta meta) async {
    try {
      final bundlePath = await _exportProjectBundle(meta);
      if (bundlePath == null || !mounted) return;

      final suggestedFileName = ExportSaveDialog.buildSuggestedFileName(
        baseName: meta.name,
        extension: 'mixroom',
      );
      final savedPath = await ExportSaveDialog.saveExportedFile(
        sourceFilePath: bundlePath,
        suggestedFileName: suggestedFileName,
        desktopDialogTitle: L10n.translate(context, 'Save export'),
      );
      if (!mounted || savedPath == null || savedPath.isEmpty) return;

      showAppSnackBar(
        context,
        L10n.translate(context, 'Project bundle saved'),
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Export failed')}: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<String?> _exportProjectBundle(ProjectMeta meta) async {
    final audioMode = await _chooseProjectBundleAudioMode();
    if (audioMode == null || !mounted) return null;

    showLoadingDialog(context, message: L10n.translate(context, 'Exporting…'));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return null;

    try {
      return await ProjectBundle.exportMixroomBundle(
        projectDir: meta.dir,
        audioMode: audioMode,
      );
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _syncProjectToCloud(ProjectMeta meta) async {
    if (projectIsFrozenMix(meta)) {
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          'Frozen mixes stay on this device. Sync the original project instead.',
        ),
        tone: AppPopupTone.warning,
      );
      return;
    }
    final auth = context.read<AuthService>();
    final entitlement = context.read<EntitlementService>();
    if (!entitlement.areCloudProjectsEnabled) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Cloud projects are not available.'),
        tone: AppPopupTone.warning,
      );
      return;
    }
    if (!auth.isSignedIn) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Sign in to use cloud projects.'),
        tone: AppPopupTone.warning,
      );
      return;
    }
    if (!entitlement.canUseCapability(SubscriptionCapability.cloudProjects)) {
      _showUpgradeRequired(
        title: 'Upgrade to use cloud projects',
        message:
            'Cloud projects are available on Starter and higher plans. Upgrade to sync this project across devices.',
        icon: Icons.cloud_upload_outlined,
      );
      return;
    }
    final projectId = meta.projectId.trim().isNotEmpty
        ? meta.projectId.trim()
        : await ProjectManager.ensureProjectId(meta.dir);
    if (!mounted) return;
    await entitlement.refreshAccountSurface(force: true);
    if (!mounted) return;
    await _refreshCloudProjectsSilently();
    if (!mounted) return;
    final destination = await _resolveCloudSyncDestination(
      meta: meta,
      entitlement: entitlement,
      promptForNewProject: true,
    );
    if (destination == null) return;
    if (!mounted) return;
    if (!destination.canWrite) {
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          'This cloud location is read-only. Renew or unlock it to sync changes.',
        ),
        tone: AppPopupTone.warning,
      );
      return;
    }
    if (!mounted) return;
    if (_cloudProjectsInFlight.contains(projectId)) return;
    setState(() => _cloudProjectsInFlight.add(projectId));
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Syncing to cloud…'),
    );
    var loadingOpen = true;
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: meta.dir,
        audioMode: BundleAudioMode.flacLossless,
        requireCurrentCompatibility: false,
      );
      final bundleFile = File(bundlePath);
      final quotaError = _syncQuotaErrorForBundle(
        meta,
        await bundleFile.length(),
        destination: destination,
      );
      if (quotaError != null) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          loadingOpen = false;
        }
        if (!mounted) return;
        _showUpgradeRequired(
          title: quotaError.contains('storage')
              ? 'Upgrade for more cloud storage'
              : 'Upgrade for more cloud projects',
          message:
              'Your current plan has reached its cloud limit. Upgrade to Starter or higher for more cloud capacity.',
          icon: Icons.cloud_off_outlined,
        );
        return;
      }
      final existingCloud = _cloudProjectForLocal(meta);
      if (existingCloud != null &&
          existingCloud.workspaceId.trim() == destination.workspaceId.trim() &&
          !existingCloud.canWrite) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          loadingOpen = false;
        }
        if (!mounted) return;
        showAppSnackBar(
          context,
          L10n.translate(
            context,
            'This cloud project is read-only. Renew or unlock it to sync changes.',
          ),
          tone: AppPopupTone.warning,
        );
        return;
      }
      final selectedWorkspaceId = destination.workspaceId.trim();
      final existingWorkspaceId =
          (existingCloud?.workspaceId ?? meta.cloudWorkspaceId ?? '').trim();
      final preservesExistingCloudLocation =
          existingCloud != null && existingWorkspaceId == selectedWorkspaceId;
      final fallbackPersonalCloudProjectId = (meta.cloudProjectId ?? '').trim();
      final hasStaleUnlistedPersonalLink =
          existingCloud == null &&
          selectedWorkspaceId.isEmpty &&
          fallbackPersonalCloudProjectId.isNotEmpty &&
          existingWorkspaceId.isEmpty;
      if (hasStaleUnlistedPersonalLink) {
        final json = await ProjectManager.readProjectJson(meta.dir);
        ProjectManager.stripCloudSyncMetadata(json);
        await ProjectManager.writeProjectJson(meta.dir, json);
        debugPrint(
          'Manual cloud sync detached stale cloud link '
          '$fallbackPersonalCloudProjectId before publishing.',
        );
      }
      final uploadCloudProjectId = preservesExistingCloudLocation
          ? existingCloud.projectId
          : null;
      final expectedRevision = uploadCloudProjectId == null
          ? null
          : meta.cloudDocumentRevision;
      CloudProjectUploadResult result;
      try {
        result = await _cloudProjectService.uploadBundle(
          auth: auth,
          bundleFile: bundleFile,
          projectId: projectId,
          name: meta.name,
          cloudProjectId: uploadCloudProjectId,
          workspaceId: destination.isPersonal ? null : destination.workspaceId,
          organizationId: destination.isPersonal
              ? null
              : destination.organizationId,
          expectedRevision: expectedRevision,
        );
      } catch (error) {
        if (uploadCloudProjectId == null || !_isCloudRevisionConflict(error)) {
          rethrow;
        }
        if (mounted && loadingOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          loadingOpen = false;
        }
        if (!mounted) return;
        final replaceCloudVersion = await _showReplaceCloudVersionDialog();
        if (!replaceCloudVersion || !mounted) return;

        showLoadingDialog(
          context,
          message: L10n.translate(context, 'Syncing to cloud…'),
        );
        loadingOpen = true;
        final latestSnapshot = await _cloudProjectService.listProjects(
          auth: auth,
        );
        CloudProjectAccessItem? latestCloud;
        for (final cloud in latestSnapshot.cloudProjects) {
          if (cloud.projectId == uploadCloudProjectId) {
            latestCloud = cloud;
            break;
          }
        }
        if (latestCloud == null) {
          throw StateError(
            'The cloud project is no longer available. Refresh and try again.',
          );
        }
        if (!latestCloud.canWrite) {
          throw StateError('This cloud project is now read-only.');
        }
        result = await _cloudProjectService.uploadBundle(
          auth: auth,
          bundleFile: bundleFile,
          projectId: projectId,
          name: meta.name,
          cloudProjectId: uploadCloudProjectId,
          workspaceId: destination.isPersonal ? null : destination.workspaceId,
          organizationId: destination.isPersonal
              ? null
              : destination.organizationId,
          expectedRevision: latestCloud.documentRevision,
        );
      }
      final json = await ProjectManager.readProjectJson(meta.dir);
      json['cloudProjectId'] = result.project.projectId;
      if (result.project.workspaceId.trim().isNotEmpty) {
        json['cloudWorkspaceId'] = result.project.workspaceId;
      } else {
        json.remove('cloudWorkspaceId');
      }
      if (result.project.organizationId.trim().isNotEmpty) {
        json['cloudOrganizationId'] = result.project.organizationId;
      } else {
        json.remove('cloudOrganizationId');
      }
      json['cloudDocumentRevision'] = result.project.documentRevision;
      json['cloudSyncedAt'] = DateTime.now().toUtc().toIso8601String();
      json['cloudChangeFingerprint'] =
          ProjectCompatibilityService.cloudChangeFingerprint(json);
      json.remove('cloudSourceFingerprint');
      await ProjectManager.writeProjectJson(meta.dir, json);
      await entitlement.refreshAccountSurface(force: true);
      await _refresh(includeCloud: true);
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Project synced to cloud')} • ${destination.label}',
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Cloud sync failed')}: ${_cleanCloudError(e)}',
        tone: AppPopupTone.error,
      );
    } finally {
      if (loadingOpen && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        setState(() => _cloudProjectsInFlight.remove(projectId));
      } else {
        _cloudProjectsInFlight.remove(projectId);
      }
    }
  }

  Future<void> _openCloudProject(CloudProjectAccessItem cloud) async {
    if (!_cloudProjectsFeatureEnabled) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Cloud projects are not available.'),
        tone: AppPopupTone.warning,
      );
      return;
    }
    final local = _localProjectForCloud(cloud);
    if (local != null) {
      await _applyLocalOpenAction(meta: local, cloud: cloud);
      return;
    }
    await _downloadAndOpenNewCloudCopy(cloud);
  }

  Future<void> _startProjectExport(
    ProjectMeta meta,
    AudioEditorInitialAction action,
  ) async {
    await _openProject(meta.dir, initialAction: action, checkCloud: false);
  }

  Future<void> _importProjectFromIncomingFile(File bundleFile) async {
    final canCreate = await ProjectManager.canCreateNew(
      maxProjects: _localProjectLimit(),
    );
    if (!mounted) return;

    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }

    if (_isIncomingAudioFile(bundleFile.path)) {
      await _importAudioFileAsNewProject(bundleFile);
      return;
    }

    await _importProjectFromFile(bundleFile.path);
  }

  bool _isIncomingAudioFile(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.wav':
      case '.wave':
      case '.mp3':
      case '.m4a':
      case '.aac':
      case '.caf':
      case '.aiff':
      case '.aif':
      case '.flac':
      case '.ogg':
        return true;
      default:
        return false;
    }
  }

  String _safeIncomingAudioFileName(String rawName) {
    final extension = p.extension(rawName).toLowerCase();
    final stem = p
        .basenameWithoutExtension(rawName)
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_');
    final safeStem = stem.isEmpty ? 'recording' : stem;
    return '$safeStem$extension';
  }

  Future<void> _importAudioFileAsNewProject(File audioFile) async {
    if (!await audioFile.exists()) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'File is unavailable.'),
        tone: AppPopupTone.error,
      );
      return;
    }

    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Importing recording…'),
    );
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final projectName = p.basenameWithoutExtension(audioFile.path).trim();
      final newDir = await ProjectManager.createNewProjectDir(
        name: projectName.isEmpty ? 'Imported Recording' : projectName,
      );
      final audioDir = ProjectManager.audioDir(newDir);
      await audioDir.create(recursive: true);
      final safeName = _safeIncomingAudioFileName(p.basename(audioFile.path));
      final dest = File(p.join(audioDir.path, safeName));
      await audioFile.copy(dest.path);
      final json = await ProjectManager.readProjectJson(newDir);
      json['version'] = 6;
      json['rows'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'rowId': -1,
          'name': 'Track 1',
          'iconId': 0,
          'kind': 'audio',
        },
      ];
      json['tracks'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'fileName': safeName,
          'label': p.basenameWithoutExtension(safeName),
          'clipType': 'audio',
          'trimStartMs': 0,
          'trimEndMs': 0,
          'offset': 0.0,
          'crossfade': 0.0,
          'gain': 2.0,
          'normalizeVolume': false,
          'normalizeGain': 1.0,
          'preNormalizeGain': 2.0,
          'pitchSemitones': 0.0,
          'isReversed': false,
          'sourceTempoBpm': 0.0,
          'stretchToProjectTempo': false,
          'tempoStretchPreservePitch': false,
          'tempoWarpMode': 'complex',
          'recordingLatencyMs': 0.0,
          'alignmentOffsetMs': 0.0,
          'rowIndex': 0,
          'rowId': -1,
          'automation': <Map<String, dynamic>>[
            <String, dynamic>{'x': 0.0, 'volume': 1.0},
            <String, dynamic>{'x': 1.0, 'volume': 1.0},
          ],
        },
      ];
      await ProjectManager.writeProjectJson(newDir, json);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: 'Pro',
            projectDir: newDir,
            onUpgradeRequested: widget.onUpgradeRequested,
          ),
        ),
      );
      if (!mounted) return;
      await _refresh();
    } catch (error) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Import failed')}: $error',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _importProjectFromFile(String path) async {
    try {
      if (!path.toLowerCase().endsWith('.mixroom')) {
        showAppSnackBar(
          context,
          L10n.translate(context, 'Please select a .mixroom project file'),
          tone: AppPopupTone.warning,
        );
        return;
      }
      showLoadingDialog(
        context,
        message: L10n.translate(context, 'Importing…'),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      // If your engine expects WAV only, use convertFlacToWav48k.
      // If you later add FLAC support end-to-end, switch to keepAsBundled.
      final newDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: File(path),
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );
      if (!mounted) return;

      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      // Open imported project immediately (optional)
      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: 'Pro',
            projectDir: newDir,
            onUpgradeRequested: widget.onUpgradeRequested,
          ),
        ),
      );
      if (!mounted) return;

      await _refresh();
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Import failed')}: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _importBundledDemoAndOpen(BundledDemoProjectAsset demo) async {
    final canCreate = await ProjectManager.canCreateNew(
      maxProjects: _localProjectLimit(),
    );
    if (!mounted) return;

    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }

    try {
      showLoadingDialog(
        context,
        message: L10n.translate(context, 'Importing…'),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      final newDir = await ProjectManager.importBundledDemoProjectAsset(
        assetPath: demo.assetPath,
      );
      if (!mounted) return;

      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: 'Pro',
            projectDir: newDir,
            onUpgradeRequested: widget.onUpgradeRequested,
          ),
        ),
      );
      if (!mounted) return;

      await _refresh();
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Import failed')}: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _deleteCloudProject(CloudProjectAccessItem cloud) async {
    if (!_cloudProjectsFeatureEnabled) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Cloud projects are not available.'),
        tone: AppPopupTone.warning,
      );
      return;
    }
    if (!cloud.canWrite) {
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          'This cloud project is read-only. Renew or unlock it to make changes.',
        ),
        tone: AppPopupTone.warning,
      );
      return;
    }
    final ok = await _showDeleteProjectsDialog(
      message:
          '“${cloud.name}” ${L10n.translate(context, 'will be deleted from cloud storage. Local copies on this device will remain.')}',
    );
    if (!ok || !mounted) return;

    final auth = context.read<AuthService>();
    final entitlement = context.read<EntitlementService>();
    if (_cloudProjectsInFlight.contains(cloud.projectId)) return;
    setState(() => _cloudProjectsInFlight.add(cloud.projectId));
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Deleting from cloud…'),
    );
    try {
      await _cloudProjectService.deleteProject(
        auth: auth,
        projectId: cloud.projectId,
      );
      final local = _localProjectForCloud(cloud);
      if (local != null) {
        final json = await ProjectManager.readProjectJson(local.dir);
        if ((json['cloudProjectId'] ?? json['cloud_project_id'] ?? '')
                .toString() ==
            cloud.projectId) {
          json.remove('cloudProjectId');
          json.remove('cloud_project_id');
          json.remove('cloudDocumentRevision');
          json.remove('cloudSyncedAt');
          await ProjectManager.writeProjectJson(local.dir, json);
        }
      }
      await entitlement.refreshAccountSurface(force: true);
      await _refresh(includeCloud: true);
      if (!mounted) return;
      showAppSnackBar(
        context,
        L10n.translate(context, 'Cloud project deleted'),
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Cloud delete failed')}: ${_cleanCloudError(e)}',
        tone: AppPopupTone.error,
      );
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        setState(() => _cloudProjectsInFlight.remove(cloud.projectId));
      } else {
        _cloudProjectsInFlight.remove(cloud.projectId);
      }
    }
  }

  String _formatLastOpened(DateTime dateTime) {
    return DateFormat('MMM d, h:mm a').format(dateTime.toLocal());
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatStoragePercentage(int usedBytes, int limitBytes) {
    if (limitBytes <= 0) return '0%';
    final percentage = usedBytes / limitBytes * 100;
    if (percentage < 10) return '${percentage.toStringAsFixed(1)}%';
    return '${percentage.round()}%';
  }

  String _formatLastUpdatedLabel(DateTime dateTime) {
    return L10n.translate(
      context,
      'Last updated: {date}',
    ).replaceAll('{date}', _formatLastOpened(dateTime));
  }

  CloudProjectStorageLocation? _cloudStorageLocationForDestination(
    _CloudProjectDestination destination,
  ) {
    final storage = _cloudStorage;
    if (storage == null || storage.locations.isEmpty) return null;
    for (final location in storage.locations) {
      if (location.workspaceId.trim() == destination.workspaceId) {
        return location;
      }
    }
    return null;
  }

  String _cloudStorageTitleLabel() {
    final entitlement = context.read<EntitlementService>();
    final destination = _selectedCloudDestination(entitlement);
    final storage = _cloudStorage;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    final label = destination.label;
    if (storage == null) return label;
    final limit = storageLocation?.limitBytes ?? storage.limitBytes;
    if (limit == null || limit <= 0) {
      return label;
    }
    final usedBytes = _cloudStorageUsedBytesForDestination(destination);
    final percentage = _formatStoragePercentage(usedBytes, limit);
    return '$label • $percentage';
  }

  String? _cloudStorageDetailLabel() {
    final entitlement = context.read<EntitlementService>();
    final destination = _selectedCloudDestination(entitlement);
    final storage = _cloudStorage;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    if (storage == null) return null;
    final limit = storageLocation?.limitBytes ?? storage.limitBytes;
    final usedBytes = _cloudStorageUsedBytesForDestination(destination);
    final used = _formatBytes(usedBytes);
    final prefix = destination.canWrite
        ? ''
        : '${L10n.translate(context, 'Read-only')} • ';
    if (limit == null || limit <= 0) return '$prefix$used used';
    if (usedBytes > limit) {
      return '$prefix${L10n.translate(context, 'Storage full')} • $used of ${_formatBytes(limit)} used';
    }
    return '$prefix$used of ${_formatBytes(limit)} used';
  }

  String? _cloudProjectCountDetailLabel() {
    final entitlement = context.read<EntitlementService>();
    final destination = _selectedCloudDestination(entitlement);
    if (!destination.isPersonal) return null;
    final storage = _cloudStorage;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    if (storage == null) return null;
    final projectLimit = storageLocation?.projectLimit ?? storage.projectLimit;
    final count = _cloudProjectCountForDestination(destination);
    if (projectLimit == null || projectLimit <= 0) return null;
    final planCode =
        (storageLocation?.planCode.trim().isNotEmpty == true
                ? storageLocation!.planCode
                : entitlement.currentPlanCode)
            .trim()
            .toLowerCase();
    final labelKey = planCode == 'free'
        ? 'Free Cloud Projects: {count} of {limit} used'
        : 'Cloud projects: {count} of {limit} used';
    return L10n.translate(
      context,
      labelKey,
    ).replaceAll('{count}', '$count').replaceAll('{limit}', '$projectLimit');
  }

  double? _cloudStorageUsageFraction() {
    final entitlement = context.read<EntitlementService>();
    final destination = _selectedCloudDestination(entitlement);
    final storage = _cloudStorage;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    final limit = storageLocation?.limitBytes ?? storage?.limitBytes;
    if (storage == null || limit == null || limit <= 0) return null;
    final usedBytes = _cloudStorageUsedBytesForDestination(destination);
    return (usedBytes / limit).clamp(0.0, 1.0);
  }

  Color _cloudStorageUsageColor() {
    final entitlement = context.read<EntitlementService>();
    final destination = _selectedCloudDestination(entitlement);
    final storage = _cloudStorage;
    final storageLocation = _cloudStorageLocationForDestination(destination);
    final limit = storageLocation?.limitBytes ?? storage?.limitBytes;
    if (storage == null || limit == null || limit <= 0) {
      return const Color(0xFFA4C2FF);
    }
    final ratio = _cloudStorageUsedBytesForDestination(destination) / limit;
    if (ratio >= 1) return const Color(0xFFFF7878);
    if (ratio >= 0.9) return const Color(0xFFFFC86B);
    return const Color(0xFFA4C2FF);
  }

  int _cloudStorageUsedBytesForDestination(
    _CloudProjectDestination destination,
  ) {
    final storageLocation = _cloudStorageLocationForDestination(destination);
    if (storageLocation != null) return storageLocation.usedBytes;
    return _cloudProjects
        .where(
          (project) =>
              project.isBundleStorage &&
              _cloudProjectIsInDestination(project, destination),
        )
        .fold<int>(0, (total, project) => total + project.documentSizeBytes);
  }

  int _cloudProjectCountForDestination(_CloudProjectDestination destination) {
    final storageLocation = _cloudStorageLocationForDestination(destination);
    if (storageLocation != null) return storageLocation.projectCount;
    return _cloudProjects
        .where(
          (project) =>
              project.isBundleStorage &&
              _cloudProjectIsInDestination(project, destination),
        )
        .length;
  }

  String _formatProjectVersionReason(ProjectVersionReason reason) {
    return L10n.translate(context, switch (reason) {
      ProjectVersionReason.autosave => 'Autosave',
      ProjectVersionReason.manualSave => 'Manual save',
      ProjectVersionReason.background => 'Background save',
      ProjectVersionReason.cloudUpdate => 'Cloud update',
    });
  }

  String _formatProjectVersionTimestamp(DateTime value) {
    return DateFormat('MMM d, h:mm a').format(value.toLocal());
  }

  String _formatCurrentProjectTimestamp(ProjectMeta project) {
    return DateFormat('MMM d, h:mm a').format(project.lastOpenedAt.toLocal());
  }

  Future<void> _showProjectVersionHistory(ProjectMeta project) async {
    final versions = await _projectVersionStore.listVersions(project.dir);
    if (!mounted) return;
    if (versions.isEmpty) {
      showAppSnackBar(context, L10n.translate(context, 'No versions yet.'));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottomInset),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 560,
                ),
                child: MixroomShellSurface(
                  radius: 28,
                  strong: true,
                  color: const Color.fromRGBO(244, 244, 244, 0.16),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            color: Color(0xFFA4C2FF),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              L10n.translate(sheetContext, 'Version History'),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MixroomShellRoundButton(
                            size: 34,
                            iconExtent: 18,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onTap: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: versions.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _ProjectVersionHistoryRow(
                                title: L10n.translate(sheetContext, 'Current'),
                                subtitle:
                                    '${L10n.translate(sheetContext, 'Current project')} • ${_formatCurrentProjectTimestamp(project)}',
                                actionLabel: L10n.translate(
                                  sheetContext,
                                  'Current',
                                ),
                                onAction: null,
                              );
                            }
                            final version = versions[index - 1];
                            return _ProjectVersionHistoryRow(
                              title: _formatProjectVersionTimestamp(
                                version.createdAt,
                              ),
                              subtitle:
                                  '${_formatProjectVersionReason(version.reason)} • ${_formatBytes(version.sizeBytes)}',
                              actionLabel: L10n.translate(
                                sheetContext,
                                'Restore Copy',
                              ),
                              onAction: () {
                                Navigator.of(sheetContext).pop();
                                unawaited(
                                  _restoreProjectVersion(project, version),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _restoreProjectVersion(
    ProjectMeta project,
    ProjectVersionEntry version,
  ) async {
    if (!await ProjectManager.canCreateNew(maxProjects: _localProjectLimit())) {
      if (!mounted) return;
      _showProjectLimitDialog();
      return;
    }
    if (!mounted) return;
    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Restoring version…'),
    );
    try {
      await _projectVersionStore.restoreVersionAsCopy(
        projectDir: project.dir,
        versionId: version.id,
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await _refresh(showBlockingLoader: false);
      if (!mounted) return;
      showAppSnackBar(
        context,
        L10n.translate(context, 'Restored project copy created.'),
      );
    } catch (error) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      showAppSnackBar(
        context,
        '${L10n.translate(context, 'Restore failed')}: $error',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _handleCompactProjectMenuAction(
    String action,
    ProjectMeta project,
  ) async {
    switch (action) {
      case 'rename':
        await _renameProject(project);
        return;
      case 'duplicate':
        await _duplicateProject(project);
        return;
      case 'delete':
        await _deleteProject(project);
        return;
      case 'save_mixroom':
        await _saveProjectBundle(project);
        return;
      case 'version_history':
        await _showProjectVersionHistory(project);
        return;
      case 'sync_cloud':
        await _syncProjectToCloud(project);
        return;
      case 'share_mixroom':
        await _shareProject(project);
        return;
      case 'export_audio':
        await _startProjectExport(project, AudioEditorInitialAction.exportMp3);
        return;
    }
  }

  Color? _projectTileOverlayColor(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return Colors.white.withValues(alpha: 0.14);
    }
    if (states.contains(WidgetState.hovered)) {
      return Colors.white.withValues(alpha: 0.08);
    }
    if (states.contains(WidgetState.focused)) {
      return Colors.white.withValues(alpha: 0.10);
    }
    return Colors.transparent;
  }

  String _familyMemberLabel(ProjectMeta member) {
    if (projectIsFrozenMix(member)) {
      return L10n.translate(context, 'Frozen mix');
    }
    return L10n.translate(context, 'Original');
  }

  Widget _buildOnDeviceFamilyTile({
    required ProjectFamilyGroup group,
    required bool compact,
  }) {
    final project = group.displayProject;
    final expandable = group.canExpand;
    final expanded = expandable && _isFamilyExpanded(group);
    final selected = _isFamilySelected(group);
    final cloud = _cloudProjectForLocal(project);
    final cloudLinked =
        cloud != null || (project.cloudProjectId ?? '').trim().isNotEmpty;
    final cloudInFlight = _localCloudSyncInFlight(project, cloud);
    final cloudStatus = cloudLinked
        ? _localCloudStatus(project, cloud, syncInProgress: cloudInFlight)
        : null;
    final localSubtitle = expandable
        ? L10n.translate(context, 'Original · Frozen mix')
        : '${L10n.translate(context, 'Last opened')} : ${_formatLastOpened(project.lastOpenedAt)}';
    final openedSubtitle =
        '${L10n.translate(context, 'Last opened')} : ${_formatLastOpened(group.sortOpenedAt)}';
    final keyToken = _projectActionKeyToken(
      '${project.name}_${project.projectId}',
    );
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final expandDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);

    void handleTileTap() {
      if (_selectionMode) {
        _toggleFamilySelection(group);
        return;
      }
      if (expandable) {
        _toggleFamilyExpansion(group);
        return;
      }
      _openProject(project.dir);
    }

    return Semantics(
      button: true,
      enabled: true,
      label:
          'Open project ${project.name}, $localSubtitle${cloudLinked ? ', ${cloudStatus!.label}' : ''}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onLongPress: () => _toggleFamilySelection(group),
            onTap: handleTileTap,
            splashFactory: InkRipple.splashFactory,
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              _projectTileOverlayColor,
            ),
            child: MixroomShellSurface(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
              color: selected
                  ? const Color.fromRGBO(193, 221, 249, 0.34)
                  : const Color.fromRGBO(244, 244, 244, 0.30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    project.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Color(0xFFF4F4F4),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      height: 22 / 15,
                                    ),
                                  ),
                                ),
                                if (cloudLinked) ...[
                                  const SizedBox(width: 8),
                                  _buildLocalCloudStatusIcon(cloudStatus!),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              localSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white.withValues(alpha: 0.80),
                                fontSize: 12,
                                height: 22 / 12,
                              ),
                            ),
                            if (expandable) ...[
                              const SizedBox(height: 2),
                              Text(
                                openedSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 11,
                                  height: 17 / 11,
                                ),
                              ),
                            ],
                            if (cloudLinked) ...[
                              const SizedBox(height: 2),
                              Text(
                                cloudStatus!.label,
                                softWrap: true,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 11,
                                  height: 17 / 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: selected
                              ? SvgPicture.asset(
                                  kMixroomShellCheckboxCheckedAsset,
                                  width: 22,
                                  height: 22,
                                )
                              : Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                        )
                      else if (cloudInFlight)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (expandable)
                              MixroomShellRoundButton(
                                size: 40,
                                iconExtent: 18,
                                icon: AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: expandDuration,
                                  child: const Icon(
                                    Icons.expand_more_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                onTap: () => _toggleFamilyExpansion(group),
                              ),
                            if (!expanded) ...[
                              if (expandable) const SizedBox(width: 6),
                              _buildProjectTrailingActions(
                                context: context,
                                project: project,
                                keyToken: keyToken,
                                compact: compact,
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                  AnimatedSize(
                    duration: expandDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Column(
                            children: [
                              for (final member in group.members)
                                _buildFamilyMemberRow(
                                  member: member,
                                  compact: compact,
                                ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyMemberRow({
    required ProjectMeta member,
    required bool compact,
  }) {
    final subtitle =
        '${L10n.translate(context, 'Last opened')} : ${_formatLastOpened(member.lastOpenedAt)}';
    final keyToken = _projectActionKeyToken(
      '${member.name}_${member.projectId}_member',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(member);
              return;
            }
            _openProject(member.dir);
          },
          splashFactory: InkRipple.splashFactory,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            _projectTileOverlayColor,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _familyMemberLabel(member),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFFF4F4F4),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 20 / 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 11,
                          height: 17 / 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_selectionMode)
                  _buildProjectTrailingActions(
                    context: context,
                    project: member,
                    keyToken: keyToken,
                    compact: compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectTrailingActions({
    required BuildContext context,
    required ProjectMeta project,
    required String keyToken,
    required bool compact,
  }) {
    if (compact) {
      final anchorKey = GlobalObjectKey('project_actions_$keyToken');
      return MixroomShellRoundButton(
        key: anchorKey,
        size: 40,
        iconExtent: 18,
        icon: const Icon(
          Icons.more_horiz_rounded,
          color: Colors.white,
          size: 22,
        ),
        onTap: () =>
            _showProjectItemMenu(anchorKey: anchorKey, project: project),
      );
    }

    final anchorKey = GlobalObjectKey('project_actions_$keyToken');
    return MixroomShellRoundButton(
      key: anchorKey,
      size: 40,
      iconExtent: 18,
      icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22),
      onTap: () => _showProjectItemMenu(anchorKey: anchorKey, project: project),
    );
  }

  void _showProjectLimitDialog() {
    final limit = _localProjectLimit();
    if (limit == SubscriptionLimits.freeLocalProjects) {
      unawaited(
        showAppUpgradeDialog(
          context: context,
          title: 'Upgrade for more projects',
          message:
              'Free includes 10 local projects. Export or delete one, or upgrade for more.',
          icon: Icons.folder_off_outlined,
          onUpgrade: widget.onUpgradeRequested,
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
  }

  int _localProjectLimit() {
    final entitlementService = context.read<EntitlementService>();
    return SubscriptionLimits.localProjectLimitForService(
      isEnforcementEnabled: entitlementService.isEnforcementEnabled,
      entitlement: entitlementService.entitlement,
    );
  }

  Widget _buildCloudStoragePanel({required bool canConfigureCloudSync}) {
    final entitlement = context.read<EntitlementService>();
    final destinations = _availableCloudDestinations(entitlement);
    final selectedDestination = _selectedCloudDestination(entitlement);
    final locationSelectorKey = GlobalObjectKey(
      'cloud_location_selector_${selectedDestination.workspaceId}',
    );
    final storageDetails = <String>[
      if (_cloudStorageDetailLabel() != null) _cloudStorageDetailLabel()!,
      if (_cloudProjectCountDetailLabel() != null)
        _cloudProjectCountDetailLabel()!,
    ].join(' • ');
    Widget buildLocationControl() {
      return Row(
        children: [
          const Icon(Icons.storage_rounded, color: Color(0xFFA4C2FF), size: 16),
          const SizedBox(width: 8),
          Text(
            L10n.translate(context, 'Cloud Location'),
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              key: locationSelectorKey,
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => unawaited(
                  _showCloudLocationSelector(
                    destinations,
                    anchorKey: locationSelectorKey,
                  ),
                ),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedDestination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withValues(alpha: 0.72),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget buildSyncControl() {
      Widget buildModeOption(CloudSyncMode mode) {
        final selected = _cloudSyncMode == mode;
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _setCloudSyncMode(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  L10n.translate(
                    context,
                    mode == CloudSyncMode.auto ? 'Auto' : 'Manual',
                  ),
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: selected
                        ? const Color(0xFFF4F4F4)
                        : Colors.white.withValues(alpha: 0.60),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Row(
        children: [
          const Icon(Icons.sync_rounded, color: Color(0xFFA4C2FF), size: 16),
          const SizedBox(width: 8),
          Text(
            L10n.translate(context, 'Cloud Sync'),
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Tooltip(
            key: _cloudSyncTooltipKey,
            triggerMode: TooltipTriggerMode.manual,
            showDuration: const Duration(seconds: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF11131A).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            richMessage: TextSpan(
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.42,
              ),
              children: [
                TextSpan(
                  text: L10n.translate(context, 'Auto'),
                  style: const TextStyle(
                    color: Color(0xFFA4C2FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ': '),
                TextSpan(
                  text: L10n.translate(
                    context,
                    'Syncs projects to cloud storage automatically.',
                  ),
                ),
                const TextSpan(text: '\n'),
                TextSpan(
                  text: L10n.translate(context, 'Manual'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ': '),
                TextSpan(
                  text: L10n.translate(
                    context,
                    'Uploads only when you choose "Sync to Cloud" in project settings.',
                  ),
                ),
              ],
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  _cloudSyncTooltipKey.currentState?.ensureTooltipVisible(),
              child: SizedBox(
                width: 20,
                height: 24,
                child: Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.58),
                  size: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                children: [
                  buildModeOption(CloudSyncMode.auto),
                  buildModeOption(CloudSyncMode.manual),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return MixroomShellSurface(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color.fromRGBO(244, 244, 244, 0.16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_queue_rounded,
                color: Color(0xFFA4C2FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _cloudStorageTitleLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        color: Color(0xFFF4F4F4),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (storageDetails.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        storageDetails,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (_cloudStorageUsageFraction() != null) ...[
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 5,
                          child: LinearProgressIndicator(
                            value: _cloudStorageUsageFraction()!,
                            minHeight: 5,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.18,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _cloudStorageUsageColor(),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if ((_cloudError ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _cloudError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: _cloudLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          onPressed: _refresh,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          tooltip: L10n.translate(context, 'Refresh'),
                        ),
                ),
              ),
            ],
          ),
          if (destinations.length > 1 || canConfigureCloudSync) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final useSingleRow =
                    destinations.length > 1 &&
                    canConfigureCloudSync &&
                    constraints.maxWidth >= 600;
                if (useSingleRow) {
                  return Row(
                    children: [
                      Expanded(child: buildLocationControl()),
                      const SizedBox(width: 16),
                      Expanded(child: buildSyncControl()),
                    ],
                  );
                }
                return Column(
                  children: [
                    if (destinations.length > 1) buildLocationControl(),
                    if (destinations.length > 1 && canConfigureCloudSync)
                      const SizedBox(height: 6),
                    if (canConfigureCloudSync) buildSyncControl(),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final entitlement = context.watch<EntitlementService>();
    final cloudProjectsEnabled = entitlement.areCloudProjectsEnabled;
    final visibleLibraryOptions = widget.hideDemoProjects
        ? (cloudProjectsEnabled ? const [0, 1] : const [0])
        : (cloudProjectsEnabled ? const [0, 1, 2] : const [0, 2]);
    final selectedLibraryTab =
        !cloudProjectsEnabled && _libraryTab == _ProjectLibraryTab.cloudProjects
        ? _ProjectLibraryTab.yourProjects
        : _libraryTab;
    if (!cloudProjectsEnabled &&
        _libraryTab == _ProjectLibraryTab.cloudProjects) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setLibraryTab(_ProjectLibraryTab.yourProjects);
      });
    }
    final canConfigureCloudSync =
        cloudProjectsEnabled &&
        auth.isSignedIn &&
        entitlement.canUseCapability(SubscriptionCapability.cloudProjects);
    final canCreate = _projects.length < _localProjectLimit();
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    final searchFocused = _searchFocusNode.hasFocus;
    final showSearchClear = searchFocused || hasSearchQuery;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final useSideRail = mixroomUsesSideRailNavigation(context);
    final dockOverlayBottom = useSideRail
        ? 0.0
        : mixroomShellDockBottomInset(context) + kMixroomMainDockHeight;
    final listBottomBaseline = dockOverlayBottom + (useSideRail ? 28 : 14);
    final floatingControlsBottom = dockOverlayBottom + (useSideRail ? 28 : 14);
    final pageMaxWidth = useSideRail ? 940.0 : 980.0;
    final pageHorizontalPadding = useSideRail
        ? _kProjectLibrarySideRailInset
        : 16.0;
    final pageTopPadding = useSideRail ? 14.0 : 14.0;
    final searchBarBottom = searchFocused && keyboardInset > 0
        ? keyboardInset + 14
        : floatingControlsBottom;
    final libraryPageCount = widget.hideDemoProjects ? 2 : 3;
    return Scaffold(
      key: _projectsScreenKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MixroomShellBackground()),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              maxWidth: pageMaxWidth,
              expandToHeight: true,
              padding: EdgeInsets.fromLTRB(
                pageHorizontalPadding,
                pageTopPadding,
                pageHorizontalPadding,
                listBottomBaseline + 64,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.demoOnly)
                    Row(
                      children: [
                        Semantics(
                          button: true,
                          label: _demoTileView
                              ? 'Show demo projects as a list'
                              : 'Show demo project thumbnails',
                          child: MixroomShellRoundButton(
                            key: const ValueKey('demo_view_toggle'),
                            size: 44,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                _demoTileView
                                    ? Icons.view_list_rounded
                                    : Icons.grid_view_rounded,
                                key: ValueKey<bool>(_demoTileView),
                                color: const Color(0xFFF4F4F4),
                                size: 23,
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _demoTileView = !_demoTileView;
                                if (_demoTileView) {
                                  _selectionModePinned = false;
                                  _selectedBundledDemoAssetPaths.clear();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                L10n.translate(context, 'Demo Projects'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color(0xFFF4F4F4),
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  height: 25 / 21,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                L10n.translate(
                                  context,
                                  'Prepared by Mixroom for you',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Colors.white.withValues(alpha: 0.58),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const SizedBox(width: 44, height: 44),
                      ],
                    )
                  else
                    Row(
                      children: [
                        MixroomShellRoundButton(
                          key: _projectToolsButtonKey,
                          size: 44,
                          iconExtent: 17,
                          assetPath: kMixroomShellFilterAsset,
                          onTap: _showProjectTools,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: MixroomShellSegmentedControl<int>(
                            value: selectedLibraryTab.index,
                            options: visibleLibraryOptions,
                            labelBuilder: (value) => L10n.translate(
                              context,
                              value == 0
                                  ? 'On Device'
                                  : value == 1
                                  ? 'Cloud'
                                  : 'Demo Projects',
                            ),
                            onChanged: (value) => _setLibraryTab(
                              value == 0
                                  ? _ProjectLibraryTab.yourProjects
                                  : value == 1
                                  ? _ProjectLibraryTab.cloudProjects
                                  : _ProjectLibraryTab.demoProjects,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        MixroomShellRoundButton(
                          size: 44,
                          active: _selectionMode,
                          icon: Icon(
                            _selectionMode
                                ? Icons.close_rounded
                                : Icons.checklist_rounded,
                            color: const Color(0xFFF4F4F4),
                            size: _selectionMode ? 22 : 21,
                          ),
                          onTap: _toggleSelectionMode,
                        ),
                      ],
                    ),
                  if (_selectionMode) ...[
                    const SizedBox(height: 12),
                    MixroomShellSurface(
                      radius: 24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: const Color.fromRGBO(244, 244, 244, 0.18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$_selectedEntryCount ${L10n.translate(context, 'Projects')}',
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _clearSelection,
                            child: Text(L10n.translate(context, 'Cancel')),
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: _deleteSelectedProjects,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF56708F),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(L10n.translate(context, 'Delete')),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: PageView.builder(
                      controller: _libraryPageController,
                      physics: widget.demoOnly || !cloudProjectsEnabled
                          ? const NeverScrollableScrollPhysics()
                          : cloudProjectsEnabled
                          ? const _ProjectLibraryPageScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: libraryPageCount,
                      onPageChanged: _handleLibraryPageChanged,
                      itemBuilder: (context, pageIndex) {
                        final tab = _ProjectLibraryTab.values[pageIndex];
                        final visibleEntries = _visibleEntriesForTab(tab);
                        final tabBody = _loading
                            ? const Center(child: CircularProgressIndicator())
                            : (_loadError ?? '').trim().isNotEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.folder_off_rounded,
                                        color: Colors.white54,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        L10n.translate(
                                          context,
                                          'Could not load projects.',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        L10n.translate(context, _loadError!),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      ElevatedButton(
                                        onPressed: _refresh,
                                        child: Text(
                                          L10n.translate(context, 'Retry'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : visibleEntries.isEmpty
                            ? Center(
                                child: Text(
                                  L10n.translate(
                                    context,
                                    hasSearchQuery
                                        ? 'No matching projects.'
                                        : tab == _ProjectLibraryTab.yourProjects
                                        ? 'No saved projects yet.'
                                        : tab ==
                                              _ProjectLibraryTab.cloudProjects
                                        ? 'No cloud projects yet.'
                                        : 'No demo projects available.',
                                  ),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final useCompactProjectMenus =
                                      constraints.maxWidth < 520;
                                  return _ProjectListBottomFade(
                                    controller: _libraryScrollControllers[tab]!,
                                    child: ListView.separated(
                                      key: ValueKey<String>(
                                        'projects_list_${tab.name}',
                                      ),
                                      controller:
                                          _libraryScrollControllers[tab],
                                      itemCount: visibleEntries.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 14),
                                      itemBuilder: (_, i) {
                                        final entry = visibleEntries[i];
                                        if (entry.isBundledDemo) {
                                          final demo = entry.bundledDemo!;
                                          final selected =
                                              _isBundledDemoSelected(demo);
                                          if (widget.demoOnly &&
                                              _demoTileView) {
                                            return _DemoProjectTile(
                                              demo: demo,
                                              onTap: () =>
                                                  _importBundledDemoAndOpen(
                                                    demo,
                                                  ),
                                            );
                                          }
                                          return Semantics(
                                            button: true,
                                            enabled: true,
                                            label:
                                                'Open demo project ${demo.name}',
                                            child: ExcludeSemantics(
                                              child: Material(
                                                color: Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                clipBehavior: Clip.antiAlias,
                                                child: InkWell(
                                                  onLongPress: () =>
                                                      _toggleBundledDemoSelection(
                                                        demo,
                                                      ),
                                                  onTap: () {
                                                    if (_selectionMode) {
                                                      _toggleBundledDemoSelection(
                                                        demo,
                                                      );
                                                      return;
                                                    }
                                                    _importBundledDemoAndOpen(
                                                      demo,
                                                    );
                                                  },
                                                  splashFactory:
                                                      InkRipple.splashFactory,
                                                  splashColor: Colors.white
                                                      .withValues(alpha: 0.12),
                                                  highlightColor: Colors.white
                                                      .withValues(alpha: 0.04),
                                                  overlayColor:
                                                      WidgetStateProperty.resolveWith<
                                                        Color?
                                                      >((states) {
                                                        if (states.contains(
                                                          WidgetState.pressed,
                                                        )) {
                                                          return Colors.white
                                                              .withValues(
                                                                alpha: 0.14,
                                                              );
                                                        }
                                                        if (states.contains(
                                                          WidgetState.hovered,
                                                        )) {
                                                          return Colors.white
                                                              .withValues(
                                                                alpha: 0.08,
                                                              );
                                                        }
                                                        if (states.contains(
                                                          WidgetState.focused,
                                                        )) {
                                                          return Colors.white
                                                              .withValues(
                                                                alpha: 0.10,
                                                              );
                                                        }
                                                        return Colors
                                                            .transparent;
                                                      }),
                                                  child: MixroomShellSurface(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          18,
                                                          16,
                                                          12,
                                                          16,
                                                        ),
                                                    color: selected
                                                        ? const Color.fromRGBO(
                                                            193,
                                                            221,
                                                            249,
                                                            0.34,
                                                          )
                                                        : const Color.fromRGBO(
                                                            244,
                                                            244,
                                                            244,
                                                            0.30,
                                                          ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                demo.name,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                  fontFamily:
                                                                      'Pretendard',
                                                                  color: Color(
                                                                    0xFFF4F4F4,
                                                                  ),
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  height:
                                                                      22 / 15,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Container(
                                                                height: 1,
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.22,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Text(
                                                                L10n.translate(
                                                                  context,
                                                                  'Tap to import demo project',
                                                                ),
                                                                style: TextStyle(
                                                                  fontFamily:
                                                                      'Pretendard',
                                                                  color: Colors
                                                                      .white
                                                                      .withValues(
                                                                        alpha:
                                                                            0.80,
                                                                      ),
                                                                  fontSize: 12,
                                                                  height:
                                                                      22 / 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        if (_selectionMode)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  top: 12,
                                                                ),
                                                            child: selected
                                                                ? SvgPicture.asset(
                                                                    kMixroomShellCheckboxCheckedAsset,
                                                                    width: 22,
                                                                    height: 22,
                                                                  )
                                                                : Container(
                                                                    width: 22,
                                                                    height: 22,
                                                                    decoration: BoxDecoration(
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      border: Border.all(
                                                                        color: Colors
                                                                            .white
                                                                            .withValues(
                                                                              alpha: 0.6,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                          )
                                                        else
                                                          MixroomShellRoundButton(
                                                            size: 40,
                                                            iconExtent: 18,
                                                            icon: const Icon(
                                                              Icons
                                                                  .file_download_outlined,
                                                              color:
                                                                  Colors.white,
                                                              size: 20,
                                                            ),
                                                            onTap: () =>
                                                                _importBundledDemoAndOpen(
                                                                  demo,
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

                                        if (entry.isCloudProject) {
                                          final cloud = entry.cloudProject!;
                                          final local = _localProjectForCloud(
                                            cloud,
                                          );
                                          final frozenMix =
                                              localFrozenMixSibling(
                                                projects: _projects,
                                                localProject: local,
                                              );
                                          final inFlight = local == null
                                              ? _cloudProjectsInFlight.contains(
                                                      cloud.projectId,
                                                    ) ||
                                                    ProjectManager
                                                        .cloudProjectSyncInFlight
                                                        .value
                                                        .contains(
                                                          cloud.projectId,
                                                        ) ||
                                                    _settlingCloudProjectSyncs
                                                        .contains(
                                                          cloud.projectId,
                                                        )
                                              : _localCloudSyncInFlight(
                                                  local,
                                                  cloud,
                                                );
                                          final localCloudStatus = local == null
                                              ? null
                                              : _localCloudStatus(
                                                  local,
                                                  cloud,
                                                  syncInProgress: inFlight,
                                                );
                                          final updated = cloud.updatedAt;
                                          final anchorKey = GlobalObjectKey(
                                            'cloud_project_actions_${cloud.projectId}',
                                          );
                                          final availabilityLabel =
                                              local != null
                                              ? L10n.translate(
                                                  context,
                                                  'On this device',
                                                )
                                              : L10n.translate(
                                                  context,
                                                  'Available in cloud',
                                                );
                                          final locationLabel =
                                              _cloudProjectLocationLabel(cloud);
                                          final updatedLabel = updated == null
                                              ? null
                                              : _formatLastUpdatedLabel(
                                                  updated,
                                                );
                                          final attributionLine =
                                              _cloudProjectAttributionLine(
                                                cloud,
                                              );
                                          final primaryDetailLine = [
                                            if (updatedLabel != null)
                                              updatedLabel,
                                            _formatBytes(
                                              cloud.documentSizeBytes,
                                            ),
                                          ].join(' • ');
                                          final secondaryDetailLine = [
                                            if (!cloud.canWrite)
                                              L10n.translate(
                                                context,
                                                'Read-only',
                                              ),
                                            if (localCloudStatus != null)
                                              localCloudStatus.statusLabel,
                                            attributionLine ??
                                                (localCloudStatus == null
                                                    ? '$availabilityLabel • $locationLabel'
                                                    : locationLabel),
                                          ].join(' • ');
                                          return Semantics(
                                            button: true,
                                            enabled: !inFlight,
                                            label:
                                                'Open cloud project ${cloud.name}, $secondaryDetailLine',
                                            child: ExcludeSemantics(
                                              child: Material(
                                                color: Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                clipBehavior: Clip.antiAlias,
                                                child: InkWell(
                                                  onTap: inFlight
                                                      ? null
                                                      : () => _openCloudProject(
                                                          cloud,
                                                        ),
                                                  splashFactory:
                                                      InkRipple.splashFactory,
                                                  splashColor: Colors.white
                                                      .withValues(alpha: 0.12),
                                                  highlightColor: Colors.white
                                                      .withValues(alpha: 0.04),
                                                  child: MixroomShellSurface(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          18,
                                                          16,
                                                          12,
                                                          16,
                                                        ),
                                                    color: const Color.fromRGBO(
                                                      244,
                                                      244,
                                                      244,
                                                      0.30,
                                                    ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      cloud
                                                                          .name,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                      style: const TextStyle(
                                                                        fontFamily:
                                                                            'Pretendard',
                                                                        color: Color(
                                                                          0xFFF4F4F4,
                                                                        ),
                                                                        fontSize:
                                                                            15,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        height:
                                                                            22 /
                                                                            15,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  if (!cloud
                                                                      .canWrite)
                                                                    Icon(
                                                                      Icons
                                                                          .lock_rounded,
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                            alpha:
                                                                                0.64,
                                                                          ),
                                                                      size: 18,
                                                                    )
                                                                  else if (localCloudStatus !=
                                                                      null)
                                                                    _buildLocalCloudStatusIcon(
                                                                      localCloudStatus,
                                                                    )
                                                                  else
                                                                    const Icon(
                                                                      Icons
                                                                          .cloud_download_rounded,
                                                                      color: Color(
                                                                        0xFFA4C2FF,
                                                                      ),
                                                                      size: 18,
                                                                    ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Container(
                                                                height: 1,
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                      alpha:
                                                                          0.22,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    primaryDetailLine,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: TextStyle(
                                                                      fontFamily:
                                                                          'Pretendard',
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                            alpha:
                                                                                0.80,
                                                                          ),
                                                                      fontSize:
                                                                          12,
                                                                      height:
                                                                          18 /
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 2,
                                                                  ),
                                                                  Text(
                                                                    secondaryDetailLine,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: TextStyle(
                                                                      fontFamily:
                                                                          'Pretendard',
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                            alpha:
                                                                                0.62,
                                                                          ),
                                                                      fontSize:
                                                                          11,
                                                                      height:
                                                                          17 /
                                                                          11,
                                                                    ),
                                                                  ),
                                                                  if (frozenMix !=
                                                                      null) ...[
                                                                    const SizedBox(
                                                                      height: 8,
                                                                    ),
                                                                    Material(
                                                                      color: Colors
                                                                          .transparent,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            14,
                                                                          ),
                                                                      clipBehavior:
                                                                          Clip.antiAlias,
                                                                      child: InkWell(
                                                                        onTap: () => _openProject(
                                                                          frozenMix
                                                                              .dir,
                                                                        ),
                                                                        splashFactory:
                                                                            InkRipple.splashFactory,
                                                                        splashColor: Colors
                                                                            .white
                                                                            .withValues(
                                                                              alpha: 0.12,
                                                                            ),
                                                                        child: Padding(
                                                                          padding: const EdgeInsets.symmetric(
                                                                            vertical:
                                                                                6,
                                                                          ),
                                                                          child: Row(
                                                                            children: [
                                                                              Expanded(
                                                                                child: Text(
                                                                                  L10n.translate(
                                                                                    context,
                                                                                    'Frozen mix',
                                                                                  ),
                                                                                  maxLines: 1,
                                                                                  overflow: TextOverflow.ellipsis,
                                                                                  style: TextStyle(
                                                                                    fontFamily: 'Pretendard',
                                                                                    color: Colors.white.withValues(
                                                                                      alpha: 0.86,
                                                                                    ),
                                                                                    fontSize: 12,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    height:
                                                                                        18 /
                                                                                        12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              Icon(
                                                                                Icons.chevron_right_rounded,
                                                                                size: 18,
                                                                                color: Colors.white.withValues(
                                                                                  alpha: 0.64,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        if (inFlight)
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  top: 10,
                                                                ),
                                                            child: SizedBox(
                                                              width: 22,
                                                              height: 22,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                            ),
                                                          )
                                                        else
                                                          MixroomShellRoundButton(
                                                            key: anchorKey,
                                                            size: 40,
                                                            iconExtent: 18,
                                                            icon: const Icon(
                                                              Icons
                                                                  .more_horiz_rounded,
                                                              color:
                                                                  Colors.white,
                                                              size: 22,
                                                            ),
                                                            onTap: () =>
                                                                _showCloudProjectItemMenu(
                                                                  anchorKey:
                                                                      anchorKey,
                                                                  project:
                                                                      cloud,
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

                                        final family = entry.family;
                                        if (family != null) {
                                          return _buildOnDeviceFamilyTile(
                                            group: family,
                                            compact: useCompactProjectMenus,
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  );
                                },
                              );
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _kProjectLibraryPageHorizontalGutter,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (tab == _ProjectLibraryTab.cloudProjects) ...[
                                const SizedBox(height: 6),
                                _buildCloudStoragePanel(
                                  canConfigureCloudSync: canConfigureCloudSync,
                                ),
                                const SizedBox(height: 10),
                              ] else
                                const SizedBox(height: 18),
                              Expanded(child: tabBody),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.demoOnly)
            Positioned(
              left: 27,
              right: 85,
              bottom: searchBarBottom,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration: const BoxDecoration(
                    color: Color.fromRGBO(244, 244, 244, 0.28),
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.25),
                        blurRadius: 15,
                        spreadRadius: 8,
                        offset: Offset.zero,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: showSearchClear
                            ? Padding(
                                key: const ValueKey('search-clear-visible'),
                                padding: const EdgeInsets.only(right: 8),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () {
                                      if (hasSearchQuery) {
                                        _searchController.clear();
                                        setState(() {});
                                      } else {
                                        _searchFocusNode.unfocus();
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(999),
                                    splashFactory: InkRipple.splashFactory,
                                    splashColor: Colors.white.withValues(
                                      alpha: 0.12,
                                    ),
                                    overlayColor:
                                        WidgetStateProperty.resolveWith<Color?>(
                                          (states) {
                                            if (states.contains(
                                              WidgetState.pressed,
                                            )) {
                                              return Colors.white.withValues(
                                                alpha: 0.14,
                                              );
                                            }
                                            if (states.contains(
                                              WidgetState.hovered,
                                            )) {
                                              return Colors.white.withValues(
                                                alpha: 0.08,
                                              );
                                            }
                                            if (states.contains(
                                              WidgetState.focused,
                                            )) {
                                              return Colors.white.withValues(
                                                alpha: 0.10,
                                              );
                                            }
                                            return Colors.transparent;
                                          },
                                        ),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: Colors.white.withValues(
                                          alpha: 0.86,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Padding(
                                key: const ValueKey('search-icon-visible'),
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.78),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (_) => setState(() {}),
                          scrollPadding: const EdgeInsets.only(bottom: 120),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: L10n.translate(context, 'Search'),
                            hintStyle: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!widget.demoOnly)
            Positioned(
              right: 27,
              bottom: floatingControlsBottom,
              child: MixroomShellRoundButton(
                iconExtent: 17,
                assetPath: kMixroomShellImportAsset,
                fillColor: const Color.fromRGBO(244, 244, 244, 0.28),
                onTap: () async {
                  if (!canCreate) {
                    _showProjectLimitDialog();
                    return;
                  }
                  final res = await _pickFilesSafely(
                    type: FileType.custom,
                    allowedExtensions: const <String>['mixroom'],
                    withData: false,
                  );
                  if (res == null || res.files.isEmpty) return;
                  final path = res.files.single.path;
                  if (path == null) return;
                  _importProjectFromFile(path);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DemoProjectTile extends StatelessWidget {
  const _DemoProjectTile({required this.demo, required this.onTap});

  final BundledDemoProjectAsset demo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open demo project ${demo.name}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashFactory: InkRipple.splashFactory,
          splashColor: Colors.white.withValues(alpha: 0.12),
          child: MixroomShellSurface(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            color: const Color.fromRGBO(244, 244, 244, 0.30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  demo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 22 / 16,
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<BundledDemoProjectPreview?>(
                  future: ProjectManager.readBundledDemoProjectPreview(
                    demo.assetPath,
                  ),
                  builder: (context, snapshot) {
                    final preview = snapshot.data;
                    if (preview == null) {
                      return const SizedBox(
                        height: 116,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return _DemoProjectTimelinePreview(preview: preview);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoProjectTimelinePreview extends StatelessWidget {
  const _DemoProjectTimelinePreview({required this.preview});

  final BundledDemoProjectPreview preview;

  @override
  Widget build(BuildContext context) {
    final populatedRowIds = preview.clips.map((clip) => clip.rowId).toSet();
    final rows = preview.rows
        .where((row) => populatedRowIds.contains(row.rowId))
        .take(4)
        .toList(growable: false);
    final visibleRows = rows.isEmpty
        ? preview.rows.take(4).toList(growable: false)
        : rows;
    final maxSeconds = preview.clips.fold<double>(
      1,
      (value, clip) => (clip.offsetSeconds + clip.durationSeconds) > value
          ? clip.offsetSeconds + clip.durationSeconds
          : value,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: (visibleRows.length * 29).clamp(87, 116).toDouble(),
        color: const Color(0xFF73797D).withValues(alpha: 0.88),
        child: Column(
          children: [
            for (var index = 0; index < visibleRows.length; index++)
              Expanded(
                child: Builder(
                  builder: (context) {
                    final row = visibleRows[index];
                    final clips = preview.clips
                        .where(
                          (clip) =>
                              clip.rowId == row.rowId ||
                              (clip.rowId == 0 && clip.rowIndex == index),
                        )
                        .toList(growable: false);
                    final hasProjectColor = row.color != 0;
                    final projectColor = hasProjectColor
                        ? Color(row.color).withValues(alpha: 1)
                        : const Color(0xFF6A7A89);
                    final headerColor = hasProjectColor
                        ? Color.lerp(
                            projectColor,
                            const Color(0xFF0B365D),
                            0.62,
                          )!
                        : row.kind == 'instrument'
                        ? const Color(0xFF146B6C)
                        : const Color(0xFF123F6A);
                    return Row(
                      children: [
                        Tooltip(
                          message: row.name,
                          child: Container(
                            width: 38,
                            color: headerColor,
                            alignment: Alignment.center,
                            child: Transform.translate(
                              offset: Offset(
                                row.iconId == 28
                                    ? 2.5
                                    : trackRowEmojiForId(row.iconId) == null
                                    ? 0
                                    : 1,
                                row.iconId == 28 ? 1.5 : 0,
                              ),
                              child: SizedBox.square(
                                dimension: 22,
                                child: Center(
                                  child: buildTrackRowIcon(
                                    row.iconId,
                                    color: const Color(0xFFF4F4F4),
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: CustomPaint(
                            painter: _DemoTimelineRowPainter(
                              clips: clips,
                              maxSeconds: maxSeconds,
                              color: projectColor,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DemoTimelineRowPainter extends CustomPainter {
  const _DemoTimelineRowPainter({
    required this.clips,
    required this.maxSeconds,
    required this.color,
  });

  final List<BundledDemoProjectPreviewClip> clips;
  final double maxSeconds;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.17)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      gridPaint,
    );

    for (final clip in clips) {
      final left = (clip.offsetSeconds / maxSeconds * size.width).clamp(
        0.0,
        size.width - 2,
      );
      final width = (clip.durationSeconds / maxSeconds * size.width).clamp(
        8.0,
        size.width - left,
      );
      final rect = Rect.fromLTWH(left + 1, 2.5, width - 2, size.height - 5);
      final radius = Radius.circular((size.height - 5) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = color.withValues(alpha: 0.62),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final waveform = Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..strokeWidth = 1;
      final centerY = rect.center.dy;
      final peaks = clip.waveformPeaks;
      final sampleCount = (rect.width / 3).floor().clamp(4, 96);
      for (var i = 0; i < sampleCount && peaks.isNotEmpty; i++) {
        final x = rect.left + rect.width * (i + 0.5) / sampleCount;
        final peakIndex = (i * peaks.length / sampleCount).floor().clamp(
          0,
          peaks.length - 1,
        );
        final height = 1.5 + peaks[peakIndex] * (rect.height * 0.70);
        canvas.drawLine(
          Offset(x, centerY - height / 2),
          Offset(x, centerY + height / 2),
          waveform,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DemoTimelineRowPainter oldDelegate) {
    return oldDelegate.clips != clips ||
        oldDelegate.maxSeconds != maxSeconds ||
        oldDelegate.color != color;
  }
}

class _ProjectToolAction extends StatelessWidget {
  const _ProjectToolAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectVersionHistoryRow extends StatelessWidget {
  const _ProjectVersionHistoryRow({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final enabled = onAction != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.14),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: enabled
                  ? const Color(0xFFA4C2FF)
                  : Colors.white.withValues(alpha: 0.44),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CloudProjectDetailRow extends StatelessWidget {
  const _CloudProjectDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.maxValueLines = 2,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxValueLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFA4C2FF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: maxValueLines,
                  overflow: maxValueLines > 6
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectListBottomFade extends StatefulWidget {
  const _ProjectListBottomFade({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_ProjectListBottomFade> createState() => _ProjectListBottomFadeState();
}

class _ProjectListBottomFadeState extends State<_ProjectListBottomFade> {
  bool _hasMoreBelow = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateExtent());
  }

  @override
  void didUpdateWidget(covariant _ProjectListBottomFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateExtent);
      widget.controller.addListener(_updateExtent);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateExtent());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateExtent);
    super.dispose();
  }

  void _updateExtent() {
    if (!mounted || !widget.controller.hasClients) return;
    final hasMoreBelow = widget.controller.position.extentAfter > 2;
    if (hasMoreBelow == _hasMoreBelow) return;
    setState(() => _hasMoreBelow = hasMoreBelow);
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        if (!_hasMoreBelow) {
          return const LinearGradient(
            colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
          ).createShader(bounds);
        }
        const fadeHeight = 28.0;
        final fadeStart =
            ((bounds.height - fadeHeight)
                .clamp(0.0, bounds.height)
                .toDouble()) /
            bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: <double>[0.0, fadeStart, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: widget.child,
    );
  }
}

Future<void> showLoadingDialog(
  BuildContext context, {
  String message = 'Loading…',
}) async {
  final colors = Theme.of(context).colorScheme;
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: MixroomShellSurface(
            radius: 28,
            strong: true,
            color: const Color.fromRGBO(244, 244, 244, 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    L10n.translate(context, message),
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
