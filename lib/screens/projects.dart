import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/subscription_service.dart';
import 'package:mixroom/models/subscription_models.dart';
import 'package:mixroom/screens/audio_editor.dart';
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

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectMeta> _projects = [];
  bool _loading = true;
  bool _filePickerInFlight = false;
  StreamSubscription<String>? _importSub;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _projects = await ProjectManager.listProjects();
    setState(() => _loading = false);
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
      message: initialAction == null ? 'Opening project…' : 'Preparing export…',
    );

    // 2. Let UI render the dialog
    // TODO: also an arbitrary delay to hide the blocking UI lag involved in opening the project
    await Future.delayed(const Duration(milliseconds: 300));

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

    // 4. Close spinner (safe even if already closed)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // 5. Refresh project list
    await _refresh();
  }

  Future<void> _newProject() async {
    if (!await ProjectManager.canCreateNew()) return;
    final resolvedMode = _resolvedEditorMode();
    final isProEntitled = _isProEntitled();

    showLoadingDialog(context, message: 'Creating project…');

    // TODO: arbitrary delay to prevent bad UX from (probably) unavoidable blocking UI lag when going to DAW screen
    await Future.delayed(const Duration(milliseconds: 300));

    final dir =
        await ProjectManager.createNewProjectDir(name: "Untitled Project");

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
    final focusNode = FocusNode();
    bool focusScheduled = false;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        if (!focusScheduled) {
          focusScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!focusNode.canRequestFocus) return;
            focusNode.requestFocus();
          });
        }
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return MediaQuery.removeViewInsets(
          context: ctx,
          removeBottom: true,
          child: Dialog(
            alignment: Alignment.topCenter,
            insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.drive_file_rename_outline, color: cs.primary),
                      const SizedBox(width: 8),
                      const Text(
                        "Rename Project",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) =>
                          Navigator.pop(ctx, controller.text.trim()),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Project name",
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        suffixIconColor: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Save"),
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
    controller.dispose();
    focusNode.dispose();

    if (res == null) return;
    final newName = res.trim();
    if (newName.isEmpty) return;

    try {
      await ProjectManager.renameProject(meta.dir, newName);
      await _refresh();

      if (!mounted) return;
      showAppSnackBar(
        context,
        "Project renamed",
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        "Rename failed: $e",
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _deleteProject(ProjectMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: const Text("Delete project?",
            style: TextStyle(color: Colors.white)),
        content: Text("“${meta.name}” will be permanently deleted.",
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (ok != true) return;
    await ProjectManager.deleteProject(meta.dir);
    await _refresh();
  }

  Future<void> _shareProject(ProjectMeta meta) async {
    try {
      showLoadingDialog(context, message: 'Exporting…');
      await Future.delayed(const Duration(milliseconds: 200));

      final bundlePath = await ProjectBundle.exportMixroomBundle(
        projectDir: meta.dir,
        audioMode: BundleAudioMode.flacLossless,
      );

      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      final params = ShareParams(
        files: [XFile(bundlePath)],
        // title: meta.name, // shows in some share UIs
        // subject: meta.name, // used by some email clients
      );

      await SharePlus.instance.share(params);
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      showAppSnackBar(
        context,
        'Export failed: $e',
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
          'Please select a .mixroom project file',
          tone: AppPopupTone.warning,
        );
        return;
      }
      showLoadingDialog(context, message: 'Importing…');
      await Future.delayed(const Duration(milliseconds: 200));

      // If your engine expects WAV only, use convertFlacToWav48k.
      // If you later add FLAC support end-to-end, switch to keepAsBundled.
      final newDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: File(path),
        audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
      );

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

      await _refresh();
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      showAppSnackBar(
        context,
        'Import failed: $e',
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
          .read<SubscriptionService>()
          .canUseCapability(SubscriptionCapability.proEditor);
    } catch (_) {
      return true;
    }
  }

  String _formatLastOpened(DateTime dateTime) {
    return DateFormat('MMM d, h:mm a').format(dateTime.toLocal());
  }

  Widget _compactActionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
  }) {
    final isCompactLabel = subtitle == null;
    return _GlassCard(
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
      title: "Project limit reached",
      message: "Delete a project to create or import a new one.",
      buttonLabel: "OK",
      icon: Icons.folder_off_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _projects.length < ProjectManager.maxProjects;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      // appBar: AppBar(
      //   title: const Text("Projects"),
      // ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1A32),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 62,
        title: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Image.asset('assets/short_white.png',
              height: 28, fit: BoxFit.contain),
        ),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: kActionCardHeight,
                          child: _compactActionCard(
                            icon: Icons.add_circle_outline,
                            title: canCreate
                                ? "New Project"
                                : "Project limit reached",
                            subtitle: canCreate
                                ? "Create a new project"
                                : "Delete one to continue",
                            onTap: () {
                              if (!canCreate) {
                                _showProjectLimitDialog();
                                return;
                              }
                              _newProject();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: kActionCardHeight,
                          child: _compactActionCard(
                            icon: Icons.file_download_outlined,
                            title: "Import",
                            subtitle: null,
                            onTap: () async {
                              if (!canCreate) {
                                _showProjectLimitDialog();
                                return;
                              }

                              final res = await _pickFilesSafely(
                                type: FileType.any,
                                // allowedExtensions: ['mixroom', 'zip'], // allow zip just in case
                                withData: false,
                              );
                              if (res == null || res.files.isEmpty) return;

                              final path = res.files.single.path;
                              if (path == null) return;
                              _importProjectFromFile(path);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _projects.isEmpty
                        ? const Center(
                            child: Text("No saved projects yet.",
                                style: TextStyle(color: Colors.white70)),
                          )
                        : ListView.separated(
                            itemCount: _projects.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = _projects[i];
                              return _GlassCard(
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsetsDirectional.only(
                                    start: 10,
                                    end: 8,
                                  ),
                                  horizontalTitleGap: 10,
                                  minLeadingWidth: 30,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18)),
                                  leading: const Icon(Icons.folder_open_rounded,
                                      color: Colors.white),
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    "Last opened: ${_formatLastOpened(p.lastOpenedAt)}",
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 11),
                                  ),
                                  onTap: () => _openProject(p.dir),
                                  trailing: SizedBox(
                                    width: 108,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PopupMenuButton<String>(
                                          tooltip: "Edit",
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          constraints: const BoxConstraints(
                                            minWidth: 40,
                                          ),
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 23, color: Colors.white70),
                                          iconSize: 23,
                                          onSelected: (v) async {
                                            if (v == "rename") {
                                              await _renameProject(p);
                                            }
                                            if (v == "delete") {
                                              await _deleteProject(p);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: "rename",
                                                child: Text("Rename")),
                                            PopupMenuItem(
                                                value: "delete",
                                                child: Text("Delete")),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        PopupMenuButton<String>(
                                          tooltip: "Share / Export",
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          constraints: const BoxConstraints(
                                            minWidth: 40,
                                          ),
                                          icon: const Icon(Icons.ios_share_rounded,
                                              size: 23, color: Colors.white70),
                                          iconSize: 23,
                                          onSelected: (v) async {
                                            if (v == "share_mixroom") {
                                              await _shareProject(p);
                                            }
                                            if (v == "export_wav") {
                                              await _startProjectExport(
                                                  p,
                                                  AudioEditorInitialAction
                                                      .exportWav);
                                            }
                                            if (v == "export_mp3") {
                                              await _startProjectExport(
                                                  p,
                                                  AudioEditorInitialAction
                                                      .exportMp3);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: "share_mixroom",
                                              child: Text("Share (.mixroom)"),
                                            ),
                                            PopupMenuItem(
                                              value: "export_wav",
                                              child: Text("Export WAV"),
                                            ),
                                            PopupMenuItem(
                                              value: "export_mp3",
                                              child: Text("Export MP3"),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10))
        ],
      ),
      child: child,
    );
  }
}

Future<void> showLoadingDialog(BuildContext context,
    {String message = 'Loading…'}) async {
  final colors = Theme.of(context).colorScheme;
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF13233D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
                selectionColor: Colors.transparent,
              ),
            ],
          ),
        ),
      );
    },
  );
}
