import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectMeta> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
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

    await ProjectManager.renameProject(meta.dir, newName);
    await _refresh();
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
                  _GlassCard(
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      leading: const Icon(Icons.add_circle_outline, color: Colors.white),
                      title: Text(
                        canCreate ? "New Project" : "Project limit reached (5/5)",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        canCreate ? "Create a new project" : "Delete one to create a new project",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onTap: canCreate ? _newProject : null,
                    ),
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
                                      if (v == "rename") await _renameProject(p);
                                      if (v == "delete") await _deleteProject(p);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: "open", child: Text("Open")),
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
