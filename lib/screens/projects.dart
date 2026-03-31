import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/core/analytics/analytics_events.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/widgets/app_responsive_body.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:provider/provider.dart';

class _NoSwipeMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _NoSwipeMaterialPageRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

const double kActionCardHeight = 72;

enum _ProjectSortMode {
  recent,
  alphabetical,
}

class _ProjectListEntry {
  const _ProjectListEntry.project(this.project)
      : bundledDemo = null,
        isBundledDemo = false;

  const _ProjectListEntry.bundledDemo(this.bundledDemo)
      : project = null,
        isBundledDemo = true;

  final ProjectMeta? project;
  final BundledDemoProjectAsset? bundledDemo;
  final bool isBundledDemo;
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  static const Key _projectsScreenKey = Key('projects_screen');
  static const Key _newProjectCardKey = Key('projects_new_project_card');
  static const Key _projectsListKey = Key('projects_list');
  static const Key _renameDialogKey = ValueKey('projects_rename_dialog');
  static const Key _renameFieldKey = ValueKey('projects_rename_field');
  static const Key _renameCancelKey = ValueKey('projects_rename_cancel');
  static const Key _renameSaveKey = ValueKey('projects_rename_save');
  static const Key _deleteDialogKey = ValueKey('projects_delete_dialog');
  static const Key _deleteCancelKey = ValueKey('projects_delete_cancel');
  static const Key _deleteConfirmKey = ValueKey('projects_delete_confirm');
  List<ProjectMeta> _projects = [];
  List<BundledDemoProjectAsset> _bundledDemoProjects = [];
  bool _loading = true;
  bool _filePickerInFlight = false;
  StreamSubscription<String>? _importSub;
  String? _loadError;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'projects_search');
  final GlobalKey _projectToolsButtonKey = GlobalKey();
  _ProjectSortMode _sortMode = _ProjectSortMode.recent;
  final Set<String> _selectedProjectPaths = <String>{};
  final Set<String> _selectedBundledDemoAssetPaths = <String>{};
  bool _selectionModePinned = false;

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

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    ProjectManager.projectLibraryRevision.addListener(
      _handleProjectLibraryChanged,
    );
    _refresh();

    // Cold start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = OpenMixroomService.consumeInitialPathOnce();
      if (initial != null) {
        await _importProjectFromIncomingFile(File(initial));
      }
    });

    // Warm start
    _importSub = OpenMixroomService.stream.listen((path) async {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _importProjectFromIncomingFile(File(path));
      });
    });
  }

  @override
  void dispose() {
    _importSub?.cancel();
    ProjectManager.projectLibraryRevision.removeListener(
      _handleProjectLibraryChanged,
    );
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleProjectLibraryChanged() {
    if (!mounted) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
    } catch (e) {
      _projects = <ProjectMeta>[];
      _bundledDemoProjects = <BundledDemoProjectAsset>[];
      _loadError = _friendlyLoadError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openProject(
    Directory dir, {
    AudioEditorInitialAction? initialAction,
  }) async {
    final resolvedMode = _resolvedEditorMode();
    final isProEntitled = _isProEntitled();

    // 1. Show loading spinner immediately
    showLoadingDialog(
      context,
      message: L10n.translate(
        context,
        initialAction == null ? 'Opening project…' : 'Preparing export…',
      ),
    );

    // 2. Let UI render the dialog
    // TODO: also an arbitrary delay to hide the blocking UI lag involved in opening the project
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // 3. Push editor
    await Navigator.push(
      context,
      _NoSwipeMaterialPageRoute(
        builder: (_) => AudioEditorScreen(
          mode: resolvedMode,
          projectDir: dir,
          isProEntitled: isProEntitled,
          initialAction: initialAction,
        ),
      ),
    );
    if (!mounted) return;

    // 4. Close spinner (safe even if already closed)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // 5. Refresh project list
    await _refresh();
  }

  Future<void> _newProject() async {
    if (!await ProjectManager.canCreateNew()) return;
    if (!mounted) return;
    final resolvedMode = _resolvedEditorMode();
    final isProEntitled = _isProEntitled();

    showLoadingDialog(
      context,
      message: L10n.translate(context, 'Creating project…'),
    );

    // TODO: arbitrary delay to prevent bad UX from (probably) unavoidable blocking UI lag when going to DAW screen
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

    await Navigator.push(
      context,
      _NoSwipeMaterialPageRoute(
        builder: (_) => AudioEditorScreen(
          mode: resolvedMode,
          projectDir: dir,
          isProEntitled: isProEntitled,
        ),
      ),
    );
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await _refresh();
  }

  Future<FilePickerResult?> _pickFilesSafely({
    required FileType type,
    bool withData = false,
  }) async {
    if (_filePickerInFlight) return null;
    _filePickerInFlight = true;
    try {
      // Avoid presenting a native picker during an active Flutter route transition.
      await SchedulerBinding.instance.endOfFrame;
      return await FilePicker.platform.pickFiles(
        type: type,
        withData: withData,
      );
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
      try {
        return await FilePicker.platform.pickFiles(
          type: type,
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
                                backgroundColor:
                                    const Color.fromRGBO(244, 244, 244, 0.08),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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
                              onPressed: () => closeWithResult(
                                ctx,
                                controller.text.trim(),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary.withValues(
                                  alpha: 0.94,
                                ),
                                foregroundColor: cs.onPrimary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
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
        await ProjectManager.renameProject(meta.dir, newName);
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

  List<ProjectMeta> _visibleProjects() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _projects.where((project) {
      if (query.isEmpty) return true;
      return project.name.toLowerCase().contains(query);
    }).toList();
    switch (_sortMode) {
      case _ProjectSortMode.alphabetical:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(
              b.name.toLowerCase(),
            ));
        break;
      case _ProjectSortMode.recent:
        filtered.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
        break;
    }
    return filtered;
  }

  List<BundledDemoProjectAsset> _visibleBundledDemoProjects() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _bundledDemoProjects.where((demo) {
      if (query.isEmpty) return true;
      return demo.name.toLowerCase().contains(query);
    }).toList();
    filtered
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  List<_ProjectListEntry> _visibleEntries() {
    final entries = <_ProjectListEntry>[
      ..._visibleProjects().map(_ProjectListEntry.project),
      ..._visibleBundledDemoProjects().map(_ProjectListEntry.bundledDemo),
    ];
    return entries;
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

  void _selectAllVisible() {
    final visibleEntries = _visibleEntries();
    setState(() {
      _selectedProjectPaths.clear();
      _selectedBundledDemoAssetPaths.clear();
      for (final entry in visibleEntries) {
        if (entry.isBundledDemo) {
          final demo = entry.bundledDemo!;
          _selectedBundledDemoAssetPaths.add(demo.assetPath);
        } else {
          final project = entry.project!;
          _selectedProjectPaths.add(_projectSelectionKey(project));
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
    final overlay =
        Navigator.of(this.context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    return origin & box.size;
  }

  Future<String?> _showAnchoredShellMenu({
    required GlobalKey anchorKey,
    required Widget child,
    required double width,
    required double estimatedHeight,
  }) {
    final anchor = _anchorRectFor(anchorKey);
    if (anchor == null) {
      return Future<String?>.value(null);
    }
    final media = MediaQuery.of(context);
    final screen = media.size;
    final left = (anchor.right - width).clamp(12.0, screen.width - width - 12);
    double top = anchor.bottom + 10;
    final maxTop = screen.height - estimatedHeight - media.padding.bottom - 24;
    if (top > maxTop) {
      top = (anchor.top - estimatedHeight - 10).clamp(24.0, maxTop);
    }

    return showGeneralDialog<String>(
      context: context,
      barrierLabel: 'menu',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: child,
            ),
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
                              L10n.translate(
                                dialogContext,
                                'Delete project?',
                              ),
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
                            backgroundColor:
                                const Color.fromRGBO(244, 244, 244, 0.08),
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
                            backgroundColor:
                                const Color.fromRGBO(196, 74, 74, 0.92),
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

  Future<void> _deleteSelectedProjects() async {
    final selectedProjects = _projects
        .where((project) => _selectedProjectPaths.contains(project.dir.path))
        .toList();
    final selectedDemos = _bundledDemoProjects
        .where(
            (demo) => _selectedBundledDemoAssetPaths.contains(demo.assetPath))
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
    final allVisibleSelected = visibleEntries.isNotEmpty &&
        visibleEntries.every((entry) {
          if (entry.isBundledDemo) {
            return _selectedBundledDemoAssetPaths
                .contains(entry.bundledDemo!.assetPath);
          }
          return _selectedProjectPaths.contains(entry.project!.dir.path);
        });
    final selected = await _showAnchoredShellMenu(
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
                onTap: () => Navigator.of(context)
                    .pop(allVisibleSelected ? 'clear' : 'select_all'),
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
    final selected = await _showAnchoredShellMenu(
      anchorKey: anchorKey,
      width: 216,
      estimatedHeight: 272,
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
                icon: Icons.delete_outline_rounded,
                label: L10n.translate(context, 'Delete'),
                onTap: () => Navigator.of(context).pop('delete'),
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
                label: L10n.translate(context, 'Export WAV'),
                onTap: () => Navigator.of(context).pop('export_wav'),
              ),
              const SizedBox(height: 4),
              _ProjectToolAction(
                icon: Icons.graphic_eq_rounded,
                label: L10n.translate(context, 'Export MP3'),
                onTap: () => Navigator.of(context).pop('export_mp3'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    await _handleCompactProjectMenuAction(selected, project);
  }

  Future<void> _deleteProject(ProjectMeta meta) async {
    final ok = await _showDeleteProjectsDialog(
      message:
          '“${meta.name}” ${L10n.translate(context, 'will be permanently deleted.')}',
      dialogKey: _deleteDialogKey,
      cancelKey: _deleteCancelKey,
      confirmKey: _deleteConfirmKey,
    );

    if (!ok) return;
    await ProjectManager.deleteProject(meta.dir);
    await _refresh();
  }

  Future<void> _shareProject(ProjectMeta meta) async {
    try {
      showLoadingDialog(
        context,
        message: L10n.translate(context, 'Exporting…'),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: meta.dir,
        audioMode: BundleAudioMode.flacLossless,
      );
      if (!mounted) return;

      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      final params = ShareParams(
        files: [XFile(bundlePath)],
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

  Future<void> _startProjectExport(
    ProjectMeta meta,
    AudioEditorInitialAction action,
  ) async {
    await _openProject(meta.dir, initialAction: action);
  }

  Future<void> _importProjectFromIncomingFile(File bundleFile) async {
    final canCreate = await ProjectManager.canCreateNew();
    if (!mounted) return;

    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }

    await _importProjectFromFile(bundleFile.path);
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
      final resolvedMode = _resolvedEditorMode();
      final isProEntitled = _isProEntitled();
      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: resolvedMode,
            projectDir: newDir,
            isProEntitled: isProEntitled,
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
    final canCreate = await ProjectManager.canCreateNew();
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

      final resolvedMode = _resolvedEditorMode();
      final isProEntitled = _isProEntitled();
      await Navigator.push(
        context,
        _NoSwipeMaterialPageRoute(
          builder: (_) => AudioEditorScreen(
            mode: resolvedMode,
            projectDir: newDir,
            isProEntitled: isProEntitled,
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

  String _resolvedEditorMode() {
    return _isProEntitled() ? "Pro" : "Basic";
  }

  bool _isProEntitled() {
    try {
      return context
          .read<EntitlementService>()
          .canUseCapability(SubscriptionCapability.proEditor);
    } catch (_) {
      return false;
    }
  }

  String _formatLastOpened(DateTime dateTime) {
    return DateFormat('MMM d, h:mm a').format(dateTime.toLocal());
  }

  Future<void> _handleCompactProjectMenuAction(
    String action,
    ProjectMeta project,
  ) async {
    switch (action) {
      case 'rename':
        await _renameProject(project);
        return;
      case 'delete':
        await _deleteProject(project);
        return;
      case 'share_mixroom':
        await _shareProject(project);
        return;
      case 'export_wav':
        await _startProjectExport(project, AudioEditorInitialAction.exportWav);
        return;
      case 'export_mp3':
        await _startProjectExport(project, AudioEditorInitialAction.exportMp3);
        return;
    }
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
        onTap: () => _showProjectItemMenu(
          anchorKey: anchorKey,
          project: project,
        ),
      );
    }

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
      onTap: () => _showProjectItemMenu(
        anchorKey: anchorKey,
        project: project,
      ),
    );
  }

  Widget _compactActionCard({
    Key? key,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
  }) {
    final isCompactLabel = subtitle == null;
    return _GlassCard(
      key: key,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompactLabel ? 10 : 14,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: isCompactLabel ? 20 : 24),
              SizedBox(width: isCompactLabel ? 8 : 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: isCompactLabel ? 14 : 15,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectLimitDialog() {
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

  @override
  Widget build(BuildContext context) {
    final canCreate = _projects.length < ProjectManager.maxProjects;
    final visibleEntries = _visibleEntries();
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    final searchFocused = _searchFocusNode.hasFocus;
    final showSearchClear = searchFocused || hasSearchQuery;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final dockOverlayBottom =
        mixroomShellDockBottomInset(context) + kMixroomMainDockHeight;
    final listBottomBaseline = dockOverlayBottom + 14;
    final floatingControlsBottom = dockOverlayBottom + 14;
    final searchBarBottom = searchFocused && keyboardInset > 0
        ? keyboardInset + 14
        : floatingControlsBottom;
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
              maxWidth: 980,
              expandToHeight: true,
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                listBottomBaseline + 64,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                          value: 0,
                          options: const [0, 1],
                          labelBuilder: (value) => L10n.translate(
                            context,
                            value == 0 ? 'Music project' : 'Video projects',
                          ),
                          onChanged: (value) {
                            if (value == 1) {
                              showAppSnackBar(
                                context,
                                L10n.translate(
                                  context,
                                  'Video projects are coming soon.',
                                ),
                              );
                            }
                          },
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
                          horizontal: 16, vertical: 12),
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
                  const SizedBox(height: 18),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : (_loadError ?? '').trim().isNotEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
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
                                        _projects.isEmpty &&
                                                _bundledDemoProjects.isEmpty
                                            ? 'No saved projects yet.'
                                            : 'No matching projects.',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  )
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                      final useCompactProjectMenus =
                                          constraints.maxWidth < 520;
                                      return ShaderMask(
                                        shaderCallback: (Rect bounds) {
                                          const fadeHeight = 32.0;
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
                                            stops: <double>[
                                              0.0,
                                              fadeStart,
                                              1.0,
                                            ],
                                          ).createShader(bounds);
                                        },
                                        blendMode: BlendMode.dstIn,
                                        child: ListView.separated(
                                          key: _projectsListKey,
                                          itemCount: visibleEntries.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 14),
                                          itemBuilder: (_, i) {
                                            final entry = visibleEntries[i];
                                            if (entry.isBundledDemo) {
                                              final demo = entry.bundledDemo!;
                                              final selected =
                                                  _isBundledDemoSelected(demo);
                                              return Material(
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
                                                      WidgetStateProperty
                                                          .resolveWith<Color?>(
                                                    (states) {
                                                      if (states.contains(
                                                        WidgetState.pressed,
                                                      )) {
                                                        return Colors.white
                                                            .withValues(
                                                                alpha: 0.14);
                                                      }
                                                      if (states.contains(
                                                        WidgetState.hovered,
                                                      )) {
                                                        return Colors.white
                                                            .withValues(
                                                                alpha: 0.08);
                                                      }
                                                      if (states.contains(
                                                        WidgetState.focused,
                                                      )) {
                                                        return Colors.white
                                                            .withValues(
                                                                alpha: 0.10);
                                                      }
                                                      return Colors.transparent;
                                                    },
                                                  ),
                                                  child: MixroomShellSurface(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
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
                                                                style:
                                                                    const TextStyle(
                                                                  fontFamily:
                                                                      'Pretendard',
                                                                  color: Color(
                                                                      0xFFF4F4F4),
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  height:
                                                                      22 / 15,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Container(
                                                                height: 1,
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.22),
                                                              ),
                                                              const SizedBox(
                                                                  height: 8),
                                                              Text(
                                                                L10n.translate(
                                                                  context,
                                                                  'Tap to import demo project',
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  fontFamily:
                                                                      'Pretendard',
                                                                  color: Colors
                                                                      .white
                                                                      .withValues(
                                                                          alpha:
                                                                              0.80),
                                                                  fontSize: 12,
                                                                  height:
                                                                      22 / 12,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        if (_selectionMode)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 12),
                                                            child: selected
                                                                ? SvgPicture
                                                                    .asset(
                                                                    kMixroomShellCheckboxCheckedAsset,
                                                                    width: 22,
                                                                    height: 22,
                                                                  )
                                                                : Container(
                                                                    width: 22,
                                                                    height: 22,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      shape: BoxShape
                                                                          .circle,
                                                                      border:
                                                                          Border
                                                                              .all(
                                                                        color: Colors
                                                                            .white
                                                                            .withValues(alpha: 0.6),
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
                                              );
                                            }

                                            final project = entry.project!;
                                            final keyToken =
                                                _projectActionKeyToken(
                                              project.name,
                                            );
                                            final selected =
                                                _isSelected(project);
                                            return Material(
                                              color: Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              clipBehavior: Clip.antiAlias,
                                              child: InkWell(
                                                onLongPress: () =>
                                                    _toggleSelection(project),
                                                onTap: () {
                                                  if (_selectionMode) {
                                                    _toggleSelection(project);
                                                    return;
                                                  }
                                                  _openProject(project.dir);
                                                },
                                                splashFactory:
                                                    InkRipple.splashFactory,
                                                splashColor: Colors.white
                                                    .withValues(alpha: 0.12),
                                                highlightColor: Colors.white
                                                    .withValues(alpha: 0.04),
                                                overlayColor:
                                                    WidgetStateProperty
                                                        .resolveWith<Color?>(
                                                  (states) {
                                                    if (states.contains(
                                                      WidgetState.pressed,
                                                    )) {
                                                      return Colors.white
                                                          .withValues(
                                                              alpha: 0.14);
                                                    }
                                                    if (states.contains(
                                                      WidgetState.hovered,
                                                    )) {
                                                      return Colors.white
                                                          .withValues(
                                                              alpha: 0.08);
                                                    }
                                                    if (states.contains(
                                                      WidgetState.focused,
                                                    )) {
                                                      return Colors.white
                                                          .withValues(
                                                              alpha: 0.10);
                                                    }
                                                    return Colors.transparent;
                                                  },
                                                ),
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
                                                              project.name,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                fontFamily:
                                                                    'Pretendard',
                                                                color: Color(
                                                                    0xFFF4F4F4),
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                height: 22 / 15,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Container(
                                                              height: 1,
                                                              color: Colors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.22),
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                              '${L10n.translate(context, 'Last opened')} : ${_formatLastOpened(project.lastOpenedAt)}',
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    'Pretendard',
                                                                color: Colors
                                                                    .white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.80),
                                                                fontSize: 12,
                                                                height: 22 / 12,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      if (_selectionMode)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  top: 12),
                                                          child: selected
                                                              ? SvgPicture
                                                                  .asset(
                                                                  kMixroomShellCheckboxCheckedAsset,
                                                                  width: 22,
                                                                  height: 22,
                                                                )
                                                              : Container(
                                                                  width: 22,
                                                                  height: 22,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    shape: BoxShape
                                                                        .circle,
                                                                    border:
                                                                        Border
                                                                            .all(
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(
                                                                              alpha: 0.6),
                                                                    ),
                                                                  ),
                                                                ),
                                                        )
                                                      else
                                                        _buildProjectTrailingActions(
                                                          context: context,
                                                          project: project,
                                                          keyToken: keyToken,
                                                          compact:
                                                              useCompactProjectMenus,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 27,
            right: 85,
            bottom: searchBarBottom,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
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
                        return FadeTransition(opacity: animation, child: child);
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
                                  splashColor:
                                      Colors.white.withValues(alpha: 0.12),
                                  overlayColor:
                                      WidgetStateProperty.resolveWith<Color?>(
                                    (states) {
                                      if (states
                                          .contains(WidgetState.pressed)) {
                                        return Colors.white
                                            .withValues(alpha: 0.14);
                                      }
                                      if (states
                                          .contains(WidgetState.hovered)) {
                                        return Colors.white
                                            .withValues(alpha: 0.08);
                                      }
                                      if (states
                                          .contains(WidgetState.focused)) {
                                        return Colors.white
                                            .withValues(alpha: 0.10);
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
                                      color:
                                          Colors.white.withValues(alpha: 0.86),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('search-clear-hidden'),
                              width: 0,
                              height: 20,
                            ),
                    ),
                    if (!showSearchClear) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                      const SizedBox(width: 8),
                    ],
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
                            letterSpacing: 0.08,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                  type: FileType.any,
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 10))
        ],
      ),
      child: child,
    );
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
                  style: const TextStyle(
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

Future<void> showLoadingDialog(BuildContext context,
    {String message = 'Loading…'}) async {
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
