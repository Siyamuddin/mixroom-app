import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProjectMeta {
  final Directory dir;
  final String name;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  ProjectMeta({
    required this.dir,
    required this.name,
    required this.createdAt,
    required this.lastOpenedAt,
  });
}

class ProjectManager {
  static const int maxProjects = 5;

  static Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, "mixroom_projects"));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static File _projectJsonFile(Directory dir) => File(p.join(dir.path, "project.json"));
  static Directory _audioDir(Directory dir) => Directory(p.join(dir.path, "audio"));

  static Future<List<ProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final dirs = root.listSync().whereType<Directory>().toList();

    final metas = <ProjectMeta>[];
    for (final d in dirs) {
      final f = _projectJsonFile(d);
      if (!f.existsSync()) continue;
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        metas.add(
          ProjectMeta(
            dir: d,
            name: (json["name"] ?? "Untitled") as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch((json["createdAt"] ?? 0) as int),
            lastOpenedAt: DateTime.fromMillisecondsSinceEpoch((json["lastOpenedAt"] ?? 0) as int),
          ),
        );
      } catch (_) {}
    }

    metas.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return metas;
  }

  static Future<bool> canCreateNew() async {
    final list = await listProjects();
    return list.length < maxProjects;
  }

  static Future<Directory> createNewProjectDir({String name = "Untitled Project"}) async {
    final root = await _rootDir();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = Directory(p.join(root.path, "proj_$id"));
    await dir.create(recursive: true);

    final audio = _audioDir(dir);
    if (!await audio.exists()) await audio.create(recursive: true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final json = <String, dynamic>{
      "version": 1,
      "name": name,
      "createdAt": now,
      "lastOpenedAt": now,
      "tracks": [],
      "rowEffects": [],
      "masterEffects": {"effects": []},
    };

    await _projectJsonFile(dir).writeAsString(jsonEncode(json));
    return dir;
  }

  static Future<void> deleteProject(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> renameProject(Directory dir, String newName) async {
    final f = _projectJsonFile(dir);
    if (!await f.exists()) return;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    json["name"] = newName;
    await f.writeAsString(jsonEncode(json));
  }

  static Future<Map<String, dynamic>> readProjectJson(Directory dir) async {
    final f = _projectJsonFile(dir);
    if (!await f.exists()) {
      throw Exception("project.json missing in ${dir.path}");
    }
    return (jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  static Future<void> writeProjectJson(Directory dir, Map<String, dynamic> json) async {
    final f = _projectJsonFile(dir);
    await f.writeAsString(jsonEncode(json));
  }

  static Directory audioDir(Directory dir) => _audioDir(dir);
}
