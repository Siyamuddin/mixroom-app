import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/video_project_manager.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/screens/video_editor_sequencer.dart';
import 'package:path/path.dart' as p;

class _NoSwipeMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _NoSwipeMaterialPageRoute({required super.builder});

  @override
  bool get popGestureEnabled => false;
}

class VideoProjectsScreen extends StatefulWidget {
  const VideoProjectsScreen({super.key});

  @override
  State<VideoProjectsScreen> createState() => _VideoProjectsScreenState();
}

const double kVideoActionCardHeight = 72;

class _VideoProjectsScreenState extends State<VideoProjectsScreen> {
  List<VideoProjectMeta> _projects = [];
  bool _loading = true;
  bool _filePickerInFlight = false;
  String? _loadError;

  String _friendlyLoadError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('path_provider') ||
        raw.contains('getapplicationdocumentspath') ||
        raw.contains('shared_preferences') ||
        raw.contains('channel-error')) {
      return L10n.translate(
        context,
        'Video projects are temporarily unavailable on this device. Please try again in a moment.',
      );
    }
    return L10n.translate(
      context,
      'We couldn\'t load your video projects right now. Please try again.',
    );
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _projects = await VideoProjectManager.listProjects();
    } catch (e) {
      _projects = <VideoProjectMeta>[];
      _loadError = _friendlyLoadError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openProject(
    Directory dir, {
    String? initialImportPath,
  }) async {
    if (!_ensureCanAccessVideoProjects()) return;

    showVideoLoadingDialog(
      context,
      message: L10n.translate(context, 'Opening video project...'),
    );
    await Future.delayed(const Duration(milliseconds: 220));
    await VideoProjectManager.touchProject(dir);

    if (!mounted) return;
    await Navigator.push(
      context,
      _NoSwipeMaterialPageRoute(
        builder: (_) => VideoSequencerEditorScreen(
          projectDir: dir,
          initialImportPath: initialImportPath,
        ),
      ),
    );

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await _refresh();
  }

  Future<void> _newProject() async {
    if (!_ensureCanAccessVideoProjects()) return;
    if (!await VideoProjectManager.canCreateNew()) return;
    if (!mounted) return;
    showVideoLoadingDialog(
      context,
      message: L10n.translate(context, 'Creating video project...'),
    );
    await Future.delayed(const Duration(milliseconds: 220));
    final dir = await VideoProjectManager.createNewProjectDir();

    if (!mounted) return;
    await Navigator.push(
      context,
      _NoSwipeMaterialPageRoute(
        builder: (_) => VideoSequencerEditorScreen(projectDir: dir),
      ),
    );
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await _refresh();
  }

  String _formatTimestamp(DateTime date) {
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<FilePickerResult?> _pickFilesSafely({
    required FileType type,
  }) async {
    if (_filePickerInFlight) return null;
    _filePickerInFlight = true;
    try {
      // Avoid presenting a native picker during an active Flutter route transition.
      await SchedulerBinding.instance.endOfFrame;
      return await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: type == FileType.custom
            ? const <String>['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi']
            : null,
      );
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
      try {
        return await FilePicker.platform.pickFiles(
          type: type,
          allowedExtensions: type == FileType.custom
              ? const <String>['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi']
              : null,
        );
      } on PlatformException catch (retryError) {
        if (retryError.code == 'multiple_request') return null;
        rethrow;
      }
    } finally {
      _filePickerInFlight = false;
    }
  }

  Future<void> _importVideoIntoNewProject() async {
    if (!_ensureCanAccessVideoProjects()) return;
    final canCreate = await VideoProjectManager.canCreateNew();
    if (!canCreate) {
      _showProjectLimitDialog();
      return;
    }

    final picked = await _pickFilesSafely(type: FileType.custom);
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;

    final guessedName = p.basenameWithoutExtension(path).trim();
    final projectName = guessedName.isEmpty
        ? L10n.translate(context, 'Untitled Video Project')
        : '$guessedName ${L10n.translate(context, 'Project')}';
    final dir =
        await VideoProjectManager.createNewProjectDir(name: projectName);
    await _openProject(dir, initialImportPath: path);
  }

  Future<void> _renameProject(VideoProjectMeta meta) async {
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
        final cs = Theme.of(ctx).colorScheme;
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
                      Text(
                        L10n.translate(context, 'Rename Video Project'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
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
                        hintText: L10n.translate(context, 'Project name'),
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(L10n.translate(context, 'Cancel')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(L10n.translate(context, 'Save')),
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

    if (res == null || res.trim().isEmpty) return;
    try {
      await VideoProjectManager.renameProject(meta.dir, res.trim());
      await _refresh();
      if (!mounted) return;
      showAppSnackBar(
        context,
        L10n.translate(context, 'Video project renamed'),
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
  }

  Future<void> _deleteProject(VideoProjectMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: Text(
          L10n.translate(context, 'Delete video project?'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          '“${meta.name}” ${L10n.translate(context, 'will be permanently deleted.')}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.translate(context, 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await VideoProjectManager.deleteProject(meta.dir);
    await _refresh();
  }

  void _showProjectLimitDialog() {
    showAppMessageDialog(
      context: context,
      title: L10n.translate(context, 'Project limit reached'),
      message: L10n.translate(
          context, 'Delete a project to create or import a new one.'),
      buttonLabel: L10n.translate(context, 'OK'),
      icon: Icons.folder_off_outlined,
    );
  }

  bool _ensureCanAccessVideoProjects() => true;

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

  @override
  Widget build(BuildContext context) {
    final canCreate = _projects.length < VideoProjectManager.maxProjects;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1A32),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 62,
        title: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.translate(context, 'Video Projects'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
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
                          height: kVideoActionCardHeight,
                          child: _compactActionCard(
                            icon: Icons.add_circle_outline,
                            title: canCreate
                                ? L10n.translate(context, 'New Project')
                                : L10n.translate(
                                    context, 'Project limit reached'),
                            subtitle: canCreate
                                ? L10n.translate(
                                    context,
                                    'Create a new video project',
                                  )
                                : L10n.translate(
                                    context, 'Delete one to continue'),
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
                          height: kVideoActionCardHeight,
                          child: _compactActionCard(
                            icon: Icons.file_upload_outlined,
                            title: L10n.translate(context, 'Import'),
                            subtitle: null,
                            onTap: _importVideoIntoNewProject,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: (_loadError ?? '').trim().isNotEmpty
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.video_collection_outlined,
                                    color: Colors.white54,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    L10n.translate(
                                      context,
                                      'Could not load video projects.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _loadError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton(
                                    onPressed: _refresh,
                                    child:
                                        Text(L10n.translate(context, 'Retry')),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _projects.isEmpty
                            ? Center(
                                child: Text(
                                  L10n.translate(
                                    context,
                                    'No saved video projects yet.',
                                  ),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _projects.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final p = _projects[i];
                                  return _GlassCard(
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      leading: const Icon(
                                        Icons.video_collection_outlined,
                                        color: Colors.white,
                                      ),
                                      title: Text(
                                        p.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${L10n.translate(context, 'Last opened')}: ${_formatTimestamp(p.lastOpenedAt)}',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12),
                                      ),
                                      onTap: () {
                                        _openProject(p.dir);
                                      },
                                      trailing: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert,
                                            color: Colors.white70),
                                        onSelected: (v) async {
                                          if (v == 'open') {
                                            await _openProject(p.dir);
                                          }
                                          if (v == 'rename') {
                                            await _renameProject(p);
                                          }
                                          if (v == 'delete') {
                                            await _deleteProject(p);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'open',
                                            child: Text(
                                              L10n.translate(context, 'Open'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'rename',
                                            child: Text(
                                              L10n.translate(context, 'Rename'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              L10n.translate(context, 'Delete'),
                                            ),
                                          ),
                                        ],
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
  const _GlassCard({required this.child});

  final Widget child;

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
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

Future<void> showVideoLoadingDialog(BuildContext context,
    {String message = 'Loading...'}) async {
  final colors = Theme.of(context).colorScheme;
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF13233D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4), blurRadius: 20),
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
              ),
            ],
          ),
        ),
      );
    },
  );
}
