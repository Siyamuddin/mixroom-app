import 'package:flutter/material.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/screens/projects.dart';

/// Local-only entry point: creating a project does not require an account.
class HackathonHomeScreen extends StatefulWidget {
  const HackathonHomeScreen({super.key});

  @override
  State<HackathonHomeScreen> createState() => _HackathonHomeScreenState();
}

class _HackathonHomeScreenState extends State<HackathonHomeScreen> {
  bool _creating = false;

  Future<void> _createProject() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final directory = await ProjectManager.createNewProjectDir(
        name: 'Untitled Project',
      );
      await ProjectManager.ensureProjectId(directory);
      ProjectManager.notifyProjectLibraryChanged();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AudioEditorScreen(projectDir: directory, mode: 'Pro'),
        ),
      );
      ProjectManager.notifyProjectLibraryChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create the project. Check available disk space and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MixRoom'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton.icon(
            onPressed: _creating ? null : _createProject,
            icon: const Icon(Icons.add),
            label: Text(_creating ? 'Creating project…' : 'New Project'),
          ),
        ),
      ],
    ),
    body: const ProjectsScreen(),
  );
}
