import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/subscription_service.dart';
import 'package:mixroom/helpers/video_project_manager.dart';
import 'package:mixroom/models/subscription_models.dart';
import 'package:mixroom/screens/video_editor_sequencer.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _projects = await VideoProjectManager.listProjects();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openProject(
    Directory dir, {
    String? initialImportPath,
  }) async {
    if (!_ensureCanAccessVideoProjects()) return;

    showVideoLoadingDialog(context, message: 'Opening video project...');
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
    showVideoLoadingDialog(context, message: 'Creating video project...');
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
      return await FilePicker.platform.pickFiles(type: type);
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
      try {
        return await FilePicker.platform.pickFiles(type: type);
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

    final picked = await _pickFilesSafely(type: FileType.video);
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;

    final guessedName = p.basenameWithoutExtension(path).trim();
    final projectName =
        guessedName.isEmpty ? 'Untitled Video Project' : '$guessedName Project';
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
                      const Text(
                        'Rename Video Project',
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
                      decoration: const InputDecoration(
                        hintText: 'Project name',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
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
                        child: const Text('Save'),
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
        'Video project renamed',
        tone: AppPopupTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Rename failed: $e',
        tone: AppPopupTone.error,
      );
    }
  }

  Future<void> _deleteProject(VideoProjectMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: const Text('Delete video project?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '“${meta.name}” will be permanently deleted.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
      title: 'Project limit reached',
      message: 'Delete a project to create or import a new one.',
      buttonLabel: 'OK',
      icon: Icons.folder_off_outlined,
    );
  }

  bool _ensureCanAccessVideoProjects() {
    if (_canAccessVideoProjects()) return true;
    _showVideoAccessLockedDialog();
    return false;
  }

  bool _canAccessVideoProjects() {
    try {
      return context
          .read<SubscriptionService>()
          .canUseCapability(SubscriptionCapability.videoProjects);
    } catch (_) {
      return true;
    }
  }

  void _showVideoAccessLockedDialog() {
    showAppMessageDialog(
      context: context,
      title: 'Subscription required',
      message: 'Your current plan does not include video projects.',
      buttonLabel: 'OK',
      icon: Icons.lock_outline_rounded,
    );
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

  @override
  Widget build(BuildContext context) {
    context.watch<SubscriptionService>();
    final hasVideoAccess = _canAccessVideoProjects();
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
            children: const [
              Text(
                'Video Projects',
                style: TextStyle(
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
                                ? 'New Project'
                                : 'Project limit reached',
                            subtitle: canCreate
                                ? 'Create a new video project'
                                : 'Delete one to continue',
                            onTap: () {
                              if (!hasVideoAccess) {
                                _showVideoAccessLockedDialog();
                                return;
                              }
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
                            title: 'Import',
                            subtitle: null,
                            onTap: _importVideoIntoNewProject,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _projects.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved video projects yet.',
                              style: TextStyle(color: Colors.white70),
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
                                    'Last opened: ${_formatTimestamp(p.lastOpenedAt)}',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12),
                                  ),
                                  onTap: () {
                                    if (!hasVideoAccess) {
                                      _showVideoAccessLockedDialog();
                                      return;
                                    }
                                    _openProject(p.dir);
                                  },
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert,
                                        color: Colors.white70),
                                    onSelected: (v) async {
                                      if (!hasVideoAccess) {
                                        _showVideoAccessLockedDialog();
                                        return;
                                      }
                                      if (v == 'open')
                                        await _openProject(p.dir);
                                      if (v == 'rename')
                                        await _renameProject(p);
                                      if (v == 'delete')
                                        await _deleteProject(p);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'open', child: Text('Open')),
                                      PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename')),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete')),
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
