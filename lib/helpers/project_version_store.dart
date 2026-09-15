import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:path/path.dart' as p;

enum ProjectVersionReason { autosave, manualSave, background, cloudUpdate }

class ProjectVersionEntry {
  const ProjectVersionEntry({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.sizeBytes,
    required this.snapshotFileName,
    required this.projectName,
    required this.signature,
    this.legacyBundleFileName = '',
  });

  final String id;
  final DateTime createdAt;
  final ProjectVersionReason reason;
  final int sizeBytes;
  final String snapshotFileName;
  final String projectName;
  final String signature;
  final String legacyBundleFileName;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'reason': reason.name,
      'sizeBytes': sizeBytes,
      'snapshotFileName': snapshotFileName,
      'projectName': projectName,
      'signature': signature,
      if (legacyBundleFileName.isNotEmpty)
        'legacyBundleFileName': legacyBundleFileName,
    };
  }

  factory ProjectVersionEntry.fromJson(Map<String, dynamic> json) {
    final reasonName = (json['reason'] ?? '').toString().trim();
    final reason = ProjectVersionReason.values.firstWhere(
      (value) => value.name == reasonName,
      orElse: () => ProjectVersionReason.autosave,
    );
    final createdAtRaw = (json['createdAt'] ?? '').toString().trim();
    return ProjectVersionEntry(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(createdAtRaw)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      reason: reason,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      snapshotFileName: (json['snapshotFileName'] ?? '').toString(),
      projectName: (json['projectName'] ?? '').toString(),
      signature: (json['signature'] ?? '').toString(),
      legacyBundleFileName:
          (json['legacyBundleFileName'] ?? json['bundleFileName'] ?? '')
              .toString(),
    );
  }
}

class ProjectVersionStore {
  static const int defaultMaxEntries = 10;
  static const Duration defaultPeriodicInterval = Duration(minutes: 15);
  static const Duration defaultSaveInterval = Duration(minutes: 5);
  static const String _versionsDirName = '.mixroom_versions';
  static const String _manifestFileName = 'manifest.json';

  const ProjectVersionStore();

  Future<List<ProjectVersionEntry>> listVersions(Directory projectDir) async {
    final manifest = await _readManifest(projectDir);
    return _entriesFromManifest(manifest);
  }

  Future<ProjectVersionEntry?> maybeCreateSnapshot({
    required Directory projectDir,
    required ProjectVersionReason reason,
    Duration minInterval = defaultPeriodicInterval,
    int maxEntries = defaultMaxEntries,
  }) async {
    final projectJsonFile = File(p.join(projectDir.path, 'project.json'));
    if (!await projectJsonFile.exists()) return null;

    final manifest = await _readManifest(projectDir);
    final entries = _entriesFromManifest(manifest);
    final now = DateTime.now().toUtc();
    final signature = await _projectSignature(projectDir);
    if (entries.isNotEmpty) {
      final latest = entries.first;
      if (latest.signature == signature) {
        return null;
      }
      final elapsed = now.difference(latest.createdAt);
      if (minInterval > Duration.zero && elapsed < minInterval) {
        return null;
      }
    }

    final projectJson = await ProjectManager.readProjectJson(projectDir);
    final projectName = (projectJson['name'] ?? p.basename(projectDir.path))
        .toString()
        .trim();
    final id = _versionId(now);
    final snapshotFileName = '$id.json';
    final snapshotsDir = await _ensureSnapshotsDir(projectDir);
    final destination = File(p.join(snapshotsDir.path, snapshotFileName));
    if (await destination.exists()) {
      await destination.delete();
    }
    await destination.writeAsString(jsonEncode(projectJson), flush: true);
    final sizeBytes = await destination.length();
    final entry = ProjectVersionEntry(
      id: id,
      createdAt: now,
      reason: reason,
      sizeBytes: sizeBytes,
      snapshotFileName: snapshotFileName,
      projectName: projectName.isEmpty ? 'Untitled Project' : projectName,
      signature: signature,
    );
    entries.insert(0, entry);
    await _writeManifest(projectDir, entries);
    await _trim(projectDir, maxEntries: maxEntries);
    return entry;
  }

  Future<Directory> restoreVersionAsCopy({
    required Directory projectDir,
    required String versionId,
  }) async {
    final entries = await listVersions(projectDir);
    final entry = entries.firstWhere(
      (candidate) => candidate.id == versionId,
      orElse: () => throw StateError('Version not found.'),
    );
    if (entry.snapshotFileName.isEmpty &&
        entry.legacyBundleFileName.isNotEmpty) {
      return _restoreLegacyBundleVersionAsCopy(
        projectDir: projectDir,
        entry: entry,
      );
    }
    final snapshot = File(
      p.join(_snapshotsDir(projectDir).path, entry.snapshotFileName),
    );
    if (!await snapshot.exists()) {
      throw StateError('Version snapshot is missing.');
    }
    final decoded = jsonDecode(await snapshot.readAsString());
    if (decoded is! Map) {
      throw StateError('Version snapshot is invalid.');
    }
    final json = decoded.cast<String, dynamic>();
    final timestamp = DateFormat(
      'yyyy-MM-dd HH.mm',
    ).format(entry.createdAt.toLocal());
    final baseName = entry.projectName.trim().isEmpty
        ? p.basename(projectDir.path)
        : entry.projectName.trim();
    final restoredDir = await ProjectManager.createNewProjectDir(
      name: '$baseName Restored $timestamp',
    );
    await _copyAudioFiles(projectDir: projectDir, restoredDir: restoredDir);
    json['name'] = p.basename(restoredDir.path);
    json.remove('projectId');
    json.remove('project_id');
    ProjectManager.stripCloudSyncMetadata(json);
    ProjectManager.ensureProjectIdInJson(json);
    await ProjectManager.writeProjectJson(restoredDir, json);
    ProjectManager.notifyProjectLibraryChanged();
    return restoredDir;
  }

  Future<void> deleteVersion({
    required Directory projectDir,
    required String versionId,
  }) async {
    final entries = await listVersions(projectDir);
    final keep = <ProjectVersionEntry>[];
    for (final entry in entries) {
      if (entry.id == versionId) {
        final files = <File>[
          if (entry.snapshotFileName.isNotEmpty)
            File(
              p.join(_snapshotsDir(projectDir).path, entry.snapshotFileName),
            ),
          if (entry.legacyBundleFileName.isNotEmpty)
            File(
              p.join(_bundlesDir(projectDir).path, entry.legacyBundleFileName),
            ),
        ];
        for (final file in files) {
          if (await file.exists()) {
            await file.delete();
          }
        }
      } else {
        keep.add(entry);
      }
    }
    await _writeManifest(projectDir, keep);
  }

  Directory _versionsDir(Directory projectDir) {
    return Directory(p.join(projectDir.path, _versionsDirName));
  }

  Directory _bundlesDir(Directory projectDir) {
    return Directory(p.join(projectDir.path, _versionsDirName, 'bundles'));
  }

  Directory _snapshotsDir(Directory projectDir) {
    return Directory(p.join(projectDir.path, _versionsDirName, 'snapshots'));
  }

  Future<Directory> _ensureVersionsDir(Directory projectDir) async {
    final dir = _versionsDir(projectDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _ensureSnapshotsDir(Directory projectDir) async {
    final dir = _snapshotsDir(projectDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _manifestFile(Directory projectDir) {
    return File(p.join(_versionsDir(projectDir).path, _manifestFileName));
  }

  Future<Map<String, dynamic>> _readManifest(Directory projectDir) async {
    final file = _manifestFile(projectDir);
    if (!await file.exists()) {
      return <String, dynamic>{'version': 1, 'entries': <dynamic>[]};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{'version': 1, 'entries': <dynamic>[]};
  }

  List<ProjectVersionEntry> _entriesFromManifest(
    Map<String, dynamic> manifest,
  ) {
    final rawEntries = manifest['entries'];
    if (rawEntries is! List) return <ProjectVersionEntry>[];
    final entries = <ProjectVersionEntry>[];
    for (final raw in rawEntries) {
      if (raw is Map<String, dynamic>) {
        entries.add(ProjectVersionEntry.fromJson(raw));
      } else if (raw is Map) {
        entries.add(ProjectVersionEntry.fromJson(raw.cast<String, dynamic>()));
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> _writeManifest(
    Directory projectDir,
    List<ProjectVersionEntry> entries,
  ) async {
    final dir = await _ensureVersionsDir(projectDir);
    final file = File(p.join(dir.path, _manifestFileName));
    final temp = File('${file.path}.tmp');
    final payload = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
    await temp.writeAsString(jsonEncode(payload), flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }

  Future<void> _trim(Directory projectDir, {required int maxEntries}) async {
    final entries = await listVersions(projectDir);
    if (entries.length <= maxEntries) return;
    final keep = entries.take(maxEntries).toList();
    final remove = entries.skip(maxEntries);
    for (final entry in remove) {
      final files = <File>[
        if (entry.snapshotFileName.isNotEmpty)
          File(p.join(_snapshotsDir(projectDir).path, entry.snapshotFileName)),
        if (entry.legacyBundleFileName.isNotEmpty)
          File(
            p.join(_bundlesDir(projectDir).path, entry.legacyBundleFileName),
          ),
      ];
      for (final file in files) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    await _writeManifest(projectDir, keep);
  }

  Future<Directory> _restoreLegacyBundleVersionAsCopy({
    required Directory projectDir,
    required ProjectVersionEntry entry,
  }) async {
    final bundle = File(
      p.join(_bundlesDir(projectDir).path, entry.legacyBundleFileName),
    );
    if (!await bundle.exists()) {
      throw StateError('Version bundle is missing.');
    }
    final restoredDir = await ProjectBundleImport.importMixroomBundle(
      bundleFile: bundle,
      audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
    );
    final timestamp = DateFormat(
      'yyyy-MM-dd HH.mm',
    ).format(entry.createdAt.toLocal());
    final baseName = entry.projectName.trim().isEmpty
        ? p.basename(projectDir.path)
        : entry.projectName.trim();
    final renamed = await ProjectManager.renameProject(
      restoredDir,
      '$baseName Restored $timestamp',
    );
    final json = await ProjectManager.readProjectJson(renamed);
    json.remove('projectId');
    json.remove('project_id');
    ProjectManager.stripCloudSyncMetadata(json);
    ProjectManager.ensureProjectIdInJson(json);
    await ProjectManager.writeProjectJson(renamed, json);
    ProjectManager.notifyProjectLibraryChanged();
    return renamed;
  }

  Future<void> _copyAudioFiles({
    required Directory projectDir,
    required Directory restoredDir,
  }) async {
    final sourceDir = ProjectManager.audioDir(projectDir);
    if (!await sourceDir.exists()) return;
    final destinationDir = ProjectManager.audioDir(restoredDir);
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }
    await for (final entity in sourceDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final destination = File(
        p.join(destinationDir.path, p.basename(entity.path)),
      );
      await entity.copy(destination.path);
    }
  }

  Future<String> _projectSignature(Directory projectDir) async {
    final bytes = BytesBuilder(copy: false);
    final projectJson = File(p.join(projectDir.path, 'project.json'));
    bytes.add(await projectJson.readAsBytes());
    final audioDir = ProjectManager.audioDir(projectDir);
    if (await audioDir.exists()) {
      final files = await audioDir
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final file in files) {
        final stat = await file.stat();
        bytes.add(
          utf8.encode(
            '${p.basename(file.path)}:${stat.size}:${stat.modified.toUtc().millisecondsSinceEpoch}\n',
          ),
        );
      }
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  String _versionId(DateTime timestamp) {
    return DateFormat("yyyyMMdd'T'HHmmssSSS'Z'").format(timestamp.toUtc());
  }
}
