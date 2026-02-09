import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

const double kActionCardHeight = 72;

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectMeta> _projects = [];
  bool _loading = true;
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

  Future<void> _openProject(Directory dir) async {
    // 1. Show loading spinner immediately
    showLoadingDialog(context, message: 'Opening project…');

    // 2. Let UI render the dialog
    // TODO: also an arbitrary delay to hide the blocking UI lag involved in opening the project
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. Push editor
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioEditorScreen(mode: "Pro", projectDir: dir),
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

    showLoadingDialog(context, message: 'Creating project…');

    // TODO: arbitrary delay to prevent bad UX from (probably) unavoidable blocking UI lag when going to DAW screen
    await Future.delayed(const Duration(milliseconds: 300));

    final dir = await ProjectManager.createNewProjectDir(name: "Untitled Project");

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioEditorScreen(mode: "Pro", projectDir: dir),
      ),
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await _refresh();
  }

  Future<void> _renameProject(ProjectMeta meta) async {
    final controller = TextEditingController(text: meta.name);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: const Text("Rename project", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Project name",
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text("Save")),
        ],
      ),
    );

    if (res == null) return;
    final newName = res.trim();
    if (newName.isEmpty) return;

    try {
      await ProjectManager.renameProject(meta.dir, newName);
      await _refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Project renamed")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Rename failed: $e")),
      );
    }
  }

  Future<void> _deleteProject(ProjectMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: const Text("Delete project?", style: TextStyle(color: Colors.white)),
        content: Text("“${meta.name}” will be permanently deleted.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Export failed: $e')),
      );
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a .mixroom project file')),
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioEditorScreen(mode: "Pro", projectDir: newDir),
        ),
      );

      await _refresh();
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Import failed: $e')),
      );
    }
  }

  Widget _compactActionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
  }) {
    return _GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1A32),
        title: const Text(
          "Project limit reached",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Delete a project to create or import a new one.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _projects.length < ProjectManager.maxProjects;

    return Scaffold(
      // appBar: AppBar(
      //   title: const Text("Projects"),
      // ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1A32),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,

        // IMPORTANT: remove default title handling
        title: null,
        centerTitle: true,

        flexibleSpace: SafeArea(
          bottom: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Image.asset('assets/mixroom_logo202_home.png', height: 28, fit: BoxFit.contain),
            ),
          ),
        ),
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
                            title: canCreate ? "New Project" : "Project limit reached",
                            subtitle: canCreate ? "Create a new project" : "Delete one to continue",
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

                              final res = await FilePicker.platform.pickFiles(
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
                            child: Text("No saved projects yet.", style: TextStyle(color: Colors.white70)),
                          )
                        : ListView.separated(
                            itemCount: _projects.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final p = _projects[i];
                              return _GlassCard(
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  leading: const Icon(Icons.folder_open_rounded, color: Colors.white),
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    "Last opened: ${DateFormat('yyyy-MM-dd HH:mm').format(p.lastOpenedAt.toLocal())}", //${p.lastOpenedAt.toLocal()}",
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                  onTap: () => _openProject(p.dir),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                                    onSelected: (v) async {
                                      if (v == "open") await _openProject(p.dir);
                                      if (v == "share") await _shareProject(p);
                                      if (v == "rename") await _renameProject(p);
                                      if (v == "delete") await _deleteProject(p);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: "open", child: Text("Open")),
                                      PopupMenuItem(value: "share", child: Text("Share (.mixroom)")),
                                      PopupMenuItem(value: "rename", child: Text("Rename")),
                                      PopupMenuItem(value: "delete", child: Text("Delete")),
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
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }
}

Future<void> showLoadingDialog(BuildContext context, {String message = 'Loading…'}) async {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (_) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1A32),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
