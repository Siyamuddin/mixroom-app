import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoProjectMeta {
  final Directory dir;
  final String name;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  VideoProjectMeta({
    required this.dir,
    required this.name,
    required this.createdAt,
    required this.lastOpenedAt,
  });
}

class VideoProjectManager {
  static const int maxProjects = 10000;

  static Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'mixroom_video_projects'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static File _projectJsonFile(Directory dir) =>
      File(p.join(dir.path, 'project.json'));
  static File _stateJsonFile(Directory dir) =>
      File(p.join(dir.path, 'sequencer_state.json'));

  static String _sanitizeFolderName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    final safe = cleaned.isEmpty ? 'Untitled Video Project' : cleaned;
    return safe.length > 70 ? safe.substring(0, 70).trim() : safe;
  }

  static Future<Directory> _nextAvailableProjectDirName(
      String preferredName) async {
    final root = await _rootDir();
    final base = _sanitizeFolderName(preferredName);

    Directory candidate = Directory(p.join(root.path, base));
    if (!await candidate.exists()) return candidate;

    int i = 1;
    while (true) {
      candidate = Directory(p.join(root.path, '$base #$i'));
      if (!await candidate.exists()) return candidate;
      i++;
    }
  }

  static Future<List<VideoProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final metas = <VideoProjectMeta>[];

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final dir = entity;
      final file = _projectJsonFile(dir);
      if (!await file.exists()) continue;

      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        metas.add(
          VideoProjectMeta(
            dir: dir,
            name: (json['name'] ?? 'Untitled Video Project') as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
                (json['createdAt'] ?? 0) as int),
            lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
                (json['lastOpenedAt'] ?? 0) as int),
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

  static Future<Directory> createNewProjectDir(
      {String name = 'Untitled Video Project'}) async {
    final dir = await _nextAvailableProjectDirName(name);
    await dir.create(recursive: true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final folderName = p.basename(dir.path);
    final json = <String, dynamic>{
      'version': 1,
      'projectType': 'video',
      'name': folderName,
      'createdAt': now,
      'lastOpenedAt': now,
      'projectId': now.toString(),
    };
    await _projectJsonFile(dir).writeAsString(jsonEncode(json));

    final initialState = <String, dynamic>{
      'version': 1,
      'createdAt': now,
      'updatedAt': now,
      'sequencer': <String, dynamic>{},
      'chatDraft': '',
      'chatMessages': <Map<String, dynamic>>[],
    };
    await _stateJsonFile(dir).writeAsString(jsonEncode(initialState));
    return dir;
  }

  static Future<void> touchProject(Directory dir) async {
    final file = _projectJsonFile(dir);
    if (!await file.exists()) return;

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['lastOpenedAt'] = DateTime.now().millisecondsSinceEpoch;
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  static Future<void> deleteProject(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<Directory> renameProject(Directory dir, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const FormatException("Project name can't be empty.");
    }

    final projectJson = _projectJsonFile(dir);
    if (!await projectJson.exists()) {
      throw FileSystemException('project.json missing', projectJson.path);
    }

    final parent = dir.parent;
    final base = _sanitizeFolderName(trimmed);
    final selfPathNorm = p.normalize(dir.path);

    final siblingFolderNamesLower = <String>{};
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final siblingNorm = p.normalize(entity.path);
      if (siblingNorm == selfPathNorm) continue;
      siblingFolderNamesLower.add(p.basename(entity.path).toLowerCase());
    }

    String resolved = base;
    int i = 1;
    while (true) {
      final desiredPath = p.join(parent.path, resolved);
      final desiredNorm = p.normalize(desiredPath);
      final desiredDir = Directory(desiredPath);
      final desiredExists = await desiredDir.exists();
      final takenByOtherDir = desiredExists && desiredNorm != selfPathNorm;
      final takenBySiblingFolder =
          siblingFolderNamesLower.contains(resolved.toLowerCase());
      if (!takenByOtherDir && !takenBySiblingFolder) break;
      resolved = '$base #$i';
      i++;
    }

    Directory finalDir = dir;
    final desired = Directory(p.join(parent.path, resolved));
    if (p.normalize(dir.path) != p.normalize(desired.path)) {
      finalDir = await dir.rename(desired.path);
    }

    final jsonFileNew = _projectJsonFile(finalDir);
    final json = jsonDecode(await jsonFileNew.readAsString()) as Map<String, dynamic>;
    json['name'] = p.basename(finalDir.path);
    await jsonFileNew.writeAsString(jsonEncode(json));
    return finalDir;
  }

  static Future<Map<String, dynamic>> readState(Directory dir) async {
    final file = _stateJsonFile(dir);
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> writeState(
      Directory dir, Map<String, dynamic> state) async {
    final file = _stateJsonFile(dir);
    final merged = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      ...state,
    };
    await file.writeAsString(jsonEncode(merged));
  }
}

