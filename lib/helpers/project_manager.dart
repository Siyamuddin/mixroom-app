/*
class ProjectManager = logic for a creating/saving a project
class ProjectBundle = export; define format for sharing projects
class ProjectBundleImport = import; opening the zipped project

Export usage:
final path = await ProjectBundle.exportMixroomBundle(
  projectDir: _projectDir,
  audioMode: BundleAudioMode.flacLossless, // or preserveAsIs
);

Import usage:
final newDir = await ProjectBundleImport.importMixroomBundle(
  bundleFile: File(pickedPath),
  audioStrategy: ImportAudioStrategy.convertFlacToWav48k,
);

*/

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:mixroom/ffmpeg/ffmpeg.dart';
import 'package:mixroom/helpers/project_compatibility_service.dart';

class ProjectMeta {
  final Directory dir;
  final String name;
  final String projectId;
  final String? cloudProjectId;
  final String? cloudWorkspaceId;
  final String? cloudOrganizationId;
  final int? cloudDocumentRevision;
  final String? cloudSourceFingerprint;
  final String sourceFingerprint;
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final String? bundledDemoAssetPath;
  final String? familyId;
  final String? mixKind;
  final String? forkedFromProjectId;

  ProjectMeta({
    required this.dir,
    required this.name,
    required this.projectId,
    this.cloudProjectId,
    this.cloudWorkspaceId,
    this.cloudOrganizationId,
    this.cloudDocumentRevision,
    this.cloudSourceFingerprint,
    this.sourceFingerprint = '',
    required this.createdAt,
    required this.lastOpenedAt,
    this.bundledDemoAssetPath,
    this.familyId,
    this.mixKind,
    this.forkedFromProjectId,
  });
}

enum ProjectCloudFreshness {
  synced,
  localChanges,
  cloudAhead,
  diverged,
  linkedUnknown,
}

ProjectCloudFreshness resolveProjectCloudFreshness({
  required ProjectMeta project,
  required bool cloudStatusAvailable,
  int? latestCloudRevision,
}) {
  final syncedFingerprint = (project.cloudSourceFingerprint ?? '').trim();
  final hasLocalChanges =
      syncedFingerprint.isNotEmpty &&
      project.sourceFingerprint.isNotEmpty &&
      syncedFingerprint != project.sourceFingerprint;
  if (!cloudStatusAvailable) return ProjectCloudFreshness.linkedUnknown;
  final cloudAhead =
      latestCloudRevision != null &&
      (project.cloudDocumentRevision == null ||
          latestCloudRevision != project.cloudDocumentRevision);
  if (cloudAhead && hasLocalChanges) return ProjectCloudFreshness.diverged;
  if (cloudAhead) return ProjectCloudFreshness.cloudAhead;
  if (hasLocalChanges) return ProjectCloudFreshness.localChanges;
  return ProjectCloudFreshness.synced;
}

class BundledDemoProjectAsset {
  final String assetPath;
  final String name;

  const BundledDemoProjectAsset({required this.assetPath, required this.name});
}

class BundledDemoProjectPreviewRow {
  const BundledDemoProjectPreviewRow({
    required this.rowId,
    required this.name,
    required this.iconId,
    required this.kind,
    required this.color,
  });

  final int rowId;
  final String name;
  final int iconId;
  final String kind;
  final int color;
}

class BundledDemoProjectPreviewClip {
  const BundledDemoProjectPreviewClip({
    required this.label,
    required this.rowId,
    required this.rowIndex,
    required this.offsetSeconds,
    required this.durationSeconds,
    required this.waveformPeaks,
  });

  final String label;
  final int rowId;
  final int rowIndex;
  final double offsetSeconds;
  final double durationSeconds;
  final List<double> waveformPeaks;
}

class BundledDemoProjectPreview {
  const BundledDemoProjectPreview({
    required this.name,
    required this.tempoBpm,
    required this.rows,
    required this.clips,
  });

  final String name;
  final double tempoBpm;
  final List<BundledDemoProjectPreviewRow> rows;
  final List<BundledDemoProjectPreviewClip> clips;
}

class ProjectManager {
  static const int maxProjects = 10000;
  static const int maxFreeProjects = 10;
  static const String _bundledDemoAssetPrefix = 'assets/demo_projects/';
  static const String _bundledDemoDismissedStateFileName =
      '.bundled_demo_dismissed_v1.json';
  static final ValueNotifier<int> projectLibraryRevision = ValueNotifier<int>(
    0,
  );
  static final ValueNotifier<Set<String>> cloudProjectSyncInFlight =
      ValueNotifier<Set<String>>(const <String>{});
  static final Map<String, int> _cloudProjectSyncActivityCounts =
      <String, int>{};
  static final Map<String, Future<BundledDemoProjectPreview?>>
  _bundledDemoPreviewCache = <String, Future<BundledDemoProjectPreview?>>{};
  static Directory? _rootDirectoryOverrideForTesting;

  @visibleForTesting
  static void setRootDirectoryForTesting(Directory? directory) {
    _rootDirectoryOverrideForTesting = directory;
  }

  static String _nextProjectId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static void notifyProjectLibraryChanged() {
    projectLibraryRevision.value += 1;
  }

  static void beginCloudProjectSync(String projectId) {
    final normalized = projectId.trim();
    if (normalized.isEmpty) return;
    _cloudProjectSyncActivityCounts[normalized] =
        (_cloudProjectSyncActivityCounts[normalized] ?? 0) + 1;
    cloudProjectSyncInFlight.value = Set<String>.unmodifiable(
      _cloudProjectSyncActivityCounts.keys,
    );
  }

  static void endCloudProjectSync(String projectId) {
    final normalized = projectId.trim();
    if (normalized.isEmpty) return;
    final remaining = (_cloudProjectSyncActivityCounts[normalized] ?? 0) - 1;
    if (remaining > 0) {
      _cloudProjectSyncActivityCounts[normalized] = remaining;
    } else {
      _cloudProjectSyncActivityCounts.remove(normalized);
    }
    cloudProjectSyncInFlight.value = Set<String>.unmodifiable(
      _cloudProjectSyncActivityCounts.keys,
    );
  }

  static Future<Directory> _rootDir() async {
    final override = _rootDirectoryOverrideForTesting;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, "mixroom_projects"));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static File _projectJsonFile(Directory dir) =>
      File(p.join(dir.path, "project.json"));
  static Directory _audioDir(Directory dir) =>
      Directory(p.join(dir.path, "audio"));

  static String _sanitizeFolderName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_') // safe cross-platform
        .replaceAll(RegExp(r'\s+'), ' ');
    final safe = cleaned.isEmpty ? "Untitled Project" : cleaned;
    return safe.length > 60 ? safe.substring(0, 60).trim() : safe;
  }

  static Future<Directory> _nextAvailableProjectDirName(
    String preferredName,
  ) async {
    final root = await _rootDir();
    final base = _sanitizeFolderName(preferredName);

    Directory candidate = Directory(p.join(root.path, base));
    if (!await candidate.exists()) return candidate;

    int i = 1;
    while (true) {
      candidate = Directory(p.join(root.path, "$base #$i"));
      if (!await candidate.exists()) return candidate;
      i++;
    }
  }

  static Future<List<ProjectMeta>> listProjects() async {
    final root = await _rootDir();
    final metas = <ProjectMeta>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final d = entity;
      final f = _projectJsonFile(d);
      if (!await f.exists()) continue;
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final bundledDemoAssetPath = (json['bundledDemoAssetPath'] as String?)
            ?.trim();
        final cloudProjectId =
            (json["cloudProjectId"] ?? json["cloud_project_id"])
                ?.toString()
                .trim();
        final cloudWorkspaceId =
            (json["cloudWorkspaceId"] ?? json["cloud_workspace_id"])
                ?.toString()
                .trim();
        final cloudOrganizationId =
            (json["cloudOrganizationId"] ?? json["cloud_organization_id"])
                ?.toString()
                .trim();
        final cloudSourceFingerprint = (json['cloudSourceFingerprint'] ?? '')
            .toString()
            .trim();
        final familyId = (json['familyId'] ?? '').toString().trim();
        final mixKind = (json['mixKind'] ?? '').toString().trim();
        final forkedFromProjectId = (json['forkedFromProjectId'] ?? '')
            .toString()
            .trim();
        metas.add(
          ProjectMeta(
            dir: d,
            name: (json["name"] ?? "Untitled") as String,
            projectId: (json["projectId"] ?? json["project_id"] ?? '')
                .toString(),
            cloudProjectId: cloudProjectId == null || cloudProjectId.isEmpty
                ? null
                : cloudProjectId,
            cloudWorkspaceId:
                cloudWorkspaceId == null || cloudWorkspaceId.isEmpty
                ? null
                : cloudWorkspaceId,
            cloudOrganizationId:
                cloudOrganizationId == null || cloudOrganizationId.isEmpty
                ? null
                : cloudOrganizationId,
            cloudDocumentRevision: (json["cloudDocumentRevision"] as num?)
                ?.toInt(),
            cloudSourceFingerprint: cloudSourceFingerprint.isEmpty
                ? null
                : cloudSourceFingerprint,
            sourceFingerprint: ProjectCompatibilityService.sourceFingerprint(
              json,
            ),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (json["createdAt"] ?? 0) as int,
            ),
            lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
              (json["lastOpenedAt"] ?? 0) as int,
            ),
            bundledDemoAssetPath: bundledDemoAssetPath?.isEmpty == true
                ? null
                : bundledDemoAssetPath,
            familyId: familyId.isEmpty ? null : familyId,
            mixKind: mixKind.isEmpty ? null : mixKind,
            forkedFromProjectId: forkedFromProjectId.isEmpty
                ? null
                : forkedFromProjectId,
          ),
        );
      } catch (_) {}
    }

    metas.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return metas;
  }

  static Future<bool> canCreateNew({
    int maxProjects = ProjectManager.maxProjects,
  }) async {
    final list = await listProjects();
    return list.length < maxProjects;
  }

  static Future<Directory> createNewProjectDir({
    String name = "Untitled Project",
  }) async {
    final dir = await _nextAvailableProjectDirName(name);
    await dir.create(recursive: true);

    final audio = _audioDir(dir);
    if (!await audio.exists()) await audio.create(recursive: true);

    final now = DateTime.now().millisecondsSinceEpoch;

    // IMPORTANT: the real project name must match the final folder name
    final folderName = p.basename(dir.path);

    final json = <String, dynamic>{
      "version": 1,
      "name": folderName,
      "createdAt": now,
      "lastOpenedAt": now,
      "tempoBpm": 120,
      "tracks": [],
      "rowEffects": [],
      "master": {
        "gain": 1.0,
        "pan": 0.5,
        "effects": {"effects": []},
      },
      "masterEffects": {"effects": []},
      "projectId": _nextProjectId(),
    };

    await _projectJsonFile(dir).writeAsString(jsonEncode(json));
    return dir;
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

    final jsonFileOld = _projectJsonFile(dir);
    if (!await jsonFileOld.exists()) {
      throw FileSystemException("project.json missing", jsonFileOld.path);
    }

    // Find a collision-safe folder name inside the same parent using folder
    // names only. This keeps rename fast even with many projects.
    final parent = dir.parent;
    final base = _sanitizeFolderName(trimmed);
    final selfPathNorm = p.normalize(dir.path);
    final siblingFolderNamesLower = <String>{};
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final sibling = entity;
      final siblingNorm = p.normalize(sibling.path);
      if (siblingNorm == selfPathNorm) continue;
      siblingFolderNamesLower.add(p.basename(sibling.path).toLowerCase());
    }

    String resolved = base;
    int i = 1;
    while (true) {
      final desiredPath = p.join(parent.path, resolved);
      final desiredNorm = p.normalize(desiredPath);
      final desiredDir = Directory(desiredPath);
      final desiredExists = await desiredDir.exists();
      final takenByOtherDir = desiredExists && desiredNorm != selfPathNorm;
      final takenBySiblingFolder = siblingFolderNamesLower.contains(
        resolved.toLowerCase(),
      );
      if (!takenByOtherDir && !takenBySiblingFolder) break;
      resolved = "$base #$i";
      i++;
    }
    final desired = Directory(p.join(parent.path, resolved));

    // 1) Rename folder FIRST (so folder+json will match)
    Directory finalDir = dir;
    if (p.normalize(dir.path) != p.normalize(desired.path)) {
      finalDir = await dir.rename(
        desired.path,
      ); // IMPORTANT: capture returned Directory
    }

    // 2) Update JSON name INSIDE the NEW folder.
    // If you want json name to match folder name exactly (including #1), use folderName:
    final folderName = p.basename(finalDir.path);

    final jsonFileNew = _projectJsonFile(finalDir);
    final json =
        jsonDecode(await jsonFileNew.readAsString()) as Map<String, dynamic>;
    json["name"] = folderName; // guarantees match
    await jsonFileNew.writeAsString(jsonEncode(json));

    return finalDir;
  }

  static Future<Directory> duplicateProject(Directory dir) async {
    final sourceJson = await readProjectJson(dir);
    final sourceName = (sourceJson["name"] ?? p.basename(dir.path))
        .toString()
        .trim();
    final duplicateDir = await createNewProjectDir(
      name: sourceName.isEmpty ? "Untitled Project Copy" : "$sourceName Copy",
    );
    await _copyProjectContentsForDuplicate(
      source: dir,
      destination: duplicateDir,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final duplicateJson = Map<String, dynamic>.from(sourceJson);
    stripCloudSyncMetadata(duplicateJson);
    stripFamilyMetadata(duplicateJson);
    duplicateJson["name"] = p.basename(duplicateDir.path);
    assignFreshProjectId(duplicateJson);
    duplicateJson["createdAt"] = now;
    duplicateJson["lastOpenedAt"] = now;
    await writeProjectJson(duplicateDir, duplicateJson);
    return duplicateDir;
  }

  static Future<void> _copyProjectContentsForDuplicate({
    required Directory source,
    required Directory destination,
  }) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name == "project.json" || name == ".mixroom_versions") continue;
      final targetPath = p.join(destination.path, name);
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectoryContents(
          source: entity,
          destination: Directory(targetPath),
        );
      }
    }
  }

  static Future<void> _copyDirectoryContents({
    required Directory source,
    required Directory destination,
  }) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectoryContents(
          source: entity,
          destination: Directory(targetPath),
        );
      }
    }
  }

  static Future<Map<String, dynamic>> readProjectJson(Directory dir) async {
    final f = _projectJsonFile(dir);
    if (!await f.exists()) {
      throw Exception("project.json missing in ${dir.path}");
    }
    return (jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  static String assignFreshProjectId(Map<String, dynamic> json) {
    final next = _nextProjectId();
    json['projectId'] = next;
    json.remove('project_id');
    return next;
  }

  static String ensureProjectIdInJson(Map<String, dynamic> json) {
    final existing = (json['projectId'] ?? json['project_id'] ?? '')
        .toString()
        .trim();
    if (existing.isNotEmpty) return existing;
    return assignFreshProjectId(json);
  }

  static Map<int, int> persistedRowOrderIndexById(
    List<Map<String, dynamic>> rows,
  ) {
    final byId = <int, int>{};
    for (var i = 0; i < rows.length; i++) {
      final rowId = (rows[i]['rowId'] as num?)?.toInt() ?? -1;
      if (rowId >= 0) {
        byId[rowId] = i;
      }
    }
    return byId;
  }

  static int resolveSavedTrackRowIndex({
    required Map<String, dynamic> track,
    required Map<int, int> persistedRowIndexById,
  }) {
    final fallbackRowIndex = (track['rowIndex'] as num?)?.toInt() ?? 0;
    final storedRowId = (track['rowId'] as num?)?.toInt() ?? -1;
    if (persistedRowIndexById.isEmpty || storedRowId < 0) {
      return fallbackRowIndex;
    }
    return persistedRowIndexById[storedRowId] ?? fallbackRowIndex;
  }

  static String uniqueAudioFileName({
    required String preferredName,
    required Set<String> usedNamesLower,
  }) {
    final ext = p.extension(preferredName);
    final stem = ext.isEmpty
        ? preferredName
        : preferredName.substring(0, preferredName.length - ext.length);
    var candidate = preferredName;
    var suffix = 1;
    while (usedNamesLower.contains(candidate.toLowerCase())) {
      candidate = '$stem #$suffix$ext';
      suffix++;
    }
    usedNamesLower.add(candidate.toLowerCase());
    return candidate;
  }

  static Future<String> ensureProjectId(Directory dir) async {
    final json = await readProjectJson(dir);
    final before = (json['projectId'] ?? json['project_id'] ?? '')
        .toString()
        .trim();
    final projectId = ensureProjectIdInJson(json);
    if (before != projectId) {
      await writeProjectJson(dir, json);
    }
    return projectId;
  }

  static int extractTrackCount(Map<String, dynamic> json) {
    final tracks = json['tracks'];
    if (tracks is List) return tracks.length;
    return 0;
  }

  static Future<void> writeProjectJson(
    Directory dir,
    Map<String, dynamic> json,
  ) async {
    final f = _projectJsonFile(dir);
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    try {
      await temp.rename(f.path);
    } on FileSystemException {
      if (await f.exists()) {
        await f.delete();
      }
      await temp.rename(f.path);
    }
  }

  static void stripCloudSyncMetadata(Map<String, dynamic> json) {
    json.remove('cloudProjectId');
    json.remove('cloud_project_id');
    json.remove('cloudWorkspaceId');
    json.remove('cloud_workspace_id');
    json.remove('cloudOrganizationId');
    json.remove('cloud_organization_id');
    json.remove('cloudDocumentRevision');
    json.remove('cloudSourceFingerprint');
    json.remove('cloud_document_revision');
    json.remove('cloudSyncedAt');
    json.remove('cloud_synced_at');
  }

  static const String mixKindOriginal = 'original';
  static const String mixKindFrozen = 'frozen';

  static void stripFamilyMetadata(Map<String, dynamic> json) {
    json.remove('familyId');
    json.remove('mixKind');
    json.remove('forkedFromProjectId');
  }

  static String frozenMixDisplayName(String originalName) {
    final trimmed = originalName.trim();
    if (trimmed.isEmpty) return 'Frozen mix';
    if (trimmed.toLowerCase().endsWith('frozen mix')) return trimmed;
    return '$trimmed Frozen mix';
  }

  static void applyFrozenMixFamily({
    required Map<String, dynamic> originalJson,
    required Map<String, dynamic> forkJson,
  }) {
    final originalProjectId = ensureProjectIdInJson(originalJson);
    originalJson['familyId'] = originalProjectId;
    if ((originalJson['mixKind'] ?? '').toString().trim().isEmpty) {
      originalJson['mixKind'] = mixKindOriginal;
    }
    forkJson['familyId'] = originalProjectId;
    forkJson['mixKind'] = mixKindFrozen;
    forkJson['forkedFromProjectId'] = originalProjectId;
  }

  static Directory audioDir(Directory dir) => _audioDir(dir);

  static bool isBundledDemoAssetPath(String assetPath) {
    return assetPath.startsWith(_bundledDemoAssetPrefix) &&
        assetPath.toLowerCase().endsWith('.mixroom');
  }

  static Future<List<BundledDemoProjectAsset>>
  listBundledDemoProjectAssets() async {
    final paths = await _discoverBundledDemoAssetPaths();
    return paths
        .map(
          (path) => BundledDemoProjectAsset(
            assetPath: path,
            name: p.basenameWithoutExtension(path),
          ),
        )
        .toList(growable: false);
  }

  static Future<BundledDemoProjectPreview?> readBundledDemoProjectPreview(
    String assetPath,
  ) {
    if (!isBundledDemoAssetPath(assetPath)) {
      return Future<BundledDemoProjectPreview?>.value(null);
    }
    return _bundledDemoPreviewCache.putIfAbsent(
      assetPath,
      () => _readBundledDemoProjectPreviewUncached(assetPath),
    );
  }

  static Future<BundledDemoProjectPreview?>
  _readBundledDemoProjectPreviewUncached(String assetPath) async {
    try {
      dynamic decoded;
      try {
        decoded = jsonDecode(
          await rootBundle.loadString('$assetPath.preview.json'),
        );
      } catch (_) {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final archive = ZipDecoder().decodeBytes(bytes, verify: false);
        final projectFile = archive.findFile('project.json');
        if (projectFile == null || !projectFile.isFile) return null;
        decoded = jsonDecode(utf8.decode(projectFile.content));
      }
      if (decoded is! Map) return null;
      final project = Map<String, dynamic>.from(decoded);
      final rowsJson = project['rows'];
      final tracksJson = project['tracks'];
      final rows = rowsJson is List
          ? rowsJson
                .whereType<Map>()
                .map((value) {
                  final row = Map<String, dynamic>.from(value);
                  return BundledDemoProjectPreviewRow(
                    rowId: (row['rowId'] as num?)?.toInt() ?? 0,
                    name: (row['name'] as String?)?.trim() ?? '',
                    iconId: (row['iconId'] as num?)?.toInt() ?? 0,
                    kind: (row['kind'] as String?)?.trim() ?? 'audio',
                    color: (row['color'] as num?)?.toInt() ?? 0,
                  );
                })
                .toList(growable: false)
          : const <BundledDemoProjectPreviewRow>[];
      final clips = tracksJson is List
          ? tracksJson
                .whereType<Map>()
                .map((value) {
                  final track = Map<String, dynamic>.from(value);
                  final trimStart =
                      (track['trimStartMs'] as num?)?.toDouble() ?? 0.0;
                  final trimEnd =
                      (track['trimEndMs'] as num?)?.toDouble() ?? trimStart;
                  return BundledDemoProjectPreviewClip(
                    label: (track['label'] as String?)?.trim() ?? '',
                    rowId: (track['rowId'] as num?)?.toInt() ?? 0,
                    rowIndex: (track['rowIndex'] as num?)?.toInt() ?? 0,
                    offsetSeconds:
                        (track['offset'] as num?)?.toDouble().clamp(0.0, 1e9) ??
                        0.0,
                    durationSeconds: ((trimEnd - trimStart) / 1000).clamp(
                      0.15,
                      1e9,
                    ),
                    waveformPeaks:
                        (track['waveformPeaks'] as List?)
                            ?.whereType<num>()
                            .map((value) => value.toDouble().clamp(0.0, 1.0))
                            .toList(growable: false) ??
                        const <double>[],
                  );
                })
                .toList(growable: false)
          : const <BundledDemoProjectPreviewClip>[];
      return BundledDemoProjectPreview(
        name: (project['name'] as String?)?.trim() ?? '',
        tempoBpm: (project['tempoBpm'] as num?)?.toDouble() ?? 120.0,
        rows: rows,
        clips: clips,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Set<String>> listDismissedBundledDemoAssetPaths() async {
    final stateFile = await _bundledDemoDismissedStateFile();
    return _readDismissedBundledDemoAssetPaths(stateFile);
  }

  static Future<void> dismissBundledDemoAsset(String assetPath) async {
    await dismissBundledDemoAssets(<String>[assetPath]);
  }

  static Future<void> dismissBundledDemoAssets(
    Iterable<String> assetPaths,
  ) async {
    final normalized = assetPaths
        .map((path) => path.trim())
        .where((path) => isBundledDemoAssetPath(path))
        .toSet();
    if (normalized.isEmpty) return;

    final stateFile = await _bundledDemoDismissedStateFile();
    final dismissed = await _readDismissedBundledDemoAssetPaths(stateFile);
    dismissed.addAll(normalized);

    await stateFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'dismissedAssets': dismissed.toList()..sort(),
        'updatedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<Directory> importBundledDemoProjectAsset({
    required String assetPath,
    ImportAudioStrategy audioStrategy = ImportAudioStrategy.convertFlacToWav48k,
  }) async {
    if (!isBundledDemoAssetPath(assetPath)) {
      throw FormatException('Unsupported bundled demo asset path: $assetPath');
    }

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    final tempDir = await getTemporaryDirectory();
    final outName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(assetPath)}';
    final bundleFile = File(p.join(tempDir.path, outName));
    await bundleFile.writeAsBytes(bytes, flush: true);

    try {
      final importedDir = await ProjectBundleImport.importMixroomBundle(
        bundleFile: bundleFile,
        audioStrategy: audioStrategy,
      );
      final json = await readProjectJson(importedDir);
      json['bundledDemoAssetPath'] = assetPath;
      await writeProjectJson(importedDir, json);
      return importedDir;
    } finally {
      if (await bundleFile.exists()) {
        await bundleFile.delete();
      }
    }
  }

  static Future<List<String>> _discoverBundledDemoAssetPaths() async {
    final discovered = <String>{};

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      discovered.addAll(
        manifest.listAssets().where(
          (path) =>
              path.startsWith(_bundledDemoAssetPrefix) &&
              path.toLowerCase().endsWith('.mixroom'),
        ),
      );
    } catch (_) {
      // Continue with legacy fallback below.
    }

    if (discovered.isEmpty) {
      try {
        final manifestRaw = await rootBundle.loadString('AssetManifest.json');
        final decoded = jsonDecode(manifestRaw);
        if (decoded is Map) {
          discovered.addAll(
            decoded.keys.whereType<String>().where(
              (path) =>
                  path.startsWith(_bundledDemoAssetPrefix) &&
                  path.toLowerCase().endsWith('.mixroom'),
            ),
          );
        }
      } catch (_) {
        // Ignore and return empty when no manifest format is available.
      }
    }

    final sorted = discovered.toList()..sort();
    return sorted;
  }

  static Future<File> _bundledDemoDismissedStateFile() async {
    final root = await _rootDir();
    return File(p.join(root.path, _bundledDemoDismissedStateFileName));
  }

  static Future<Set<String>> _readDismissedBundledDemoAssetPaths(
    File stateFile,
  ) async {
    if (!await stateFile.exists()) return <String>{};
    try {
      final decoded = jsonDecode(await stateFile.readAsString());
      if (decoded is! Map<String, dynamic>) return <String>{};
      final raw = decoded['dismissedAssets'];
      if (raw is! List) return <String>{};
      return raw.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }
}

enum BundleAudioMode {
  preserveAsIs, // copy whatever files are in project/audio/ in their respective formats
  flacLossless, // convert everything to .flac (lossless)
}

class ProjectBundle {
  static Future<String> exportMixroomBundle({
    required Directory projectDir,
    required BundleAudioMode audioMode,
    bool requireCurrentCompatibility = true,
  }) async {
    final projectJson = File(p.join(projectDir.path, "project.json"));
    if (!projectJson.existsSync()) {
      throw Exception("Missing project.json in ${projectDir.path}");
    }

    final jsonMap =
        jsonDecode(projectJson.readAsStringSync()) as Map<String, dynamic>;
    final projectName = (jsonMap["name"] as String?) ?? "Mixroom Project";
    final compatibility = ProjectCompatibilityService.inspect(jsonMap);
    final hasCurrentCompatibility =
        compatibility.needsPluginAudio &&
        await ProjectCompatibilityService.isCurrent(projectDir);
    if (requireCurrentCompatibility &&
        compatibility.needsPluginAudio &&
        !hasCurrentCompatibility) {
      throw StateError(
        'This project needs an up-to-date compatible version. Open it on the desktop that has its plugins, then choose Prepare under Project Settings before sharing it with devices that do not have those plugins.',
      );
    }
    ProjectManager.stripCloudSyncMetadata(jsonMap);

    final tmpDir = await getTemporaryDirectory();
    final base = _sanitizeFileName(projectName);
    String bundlePath = p.join(tmpDir.path, "$base.mixroom");

    // staging folders
    final staging = Directory(
      p.join(
        tmpDir.path,
        "mixroom_bundle_staging_${DateTime.now().millisecondsSinceEpoch}",
      ),
    );
    await staging.create(recursive: true);

    // copy/convert audio
    final srcAudioDir = Directory(p.join(projectDir.path, "audio"));
    final dstAudioDir = Directory(p.join(staging.path, "audio"));
    await dstAudioDir.create(recursive: true);
    final fileNameRemap = <String, String>{};

    if (await srcAudioDir.exists()) {
      final audioFiles = srcAudioDir.listSync().whereType<File>().toList();

      for (final f in audioFiles) {
        final ext = p.extension(f.path).toLowerCase();

        if (audioMode == BundleAudioMode.preserveAsIs) {
          final outName = p.basename(f.path);
          await f.copy(p.join(dstAudioDir.path, outName));
          fileNameRemap[p.basename(f.path)] = outName;
        } else {
          final outName = "${p.basenameWithoutExtension(f.path)}.flac";
          final outPath = p.join(dstAudioDir.path, outName);

          if (ext == ".flac") {
            await f.copy(outPath);
          } else {
            await _convertToFlacLossless(inPath: f.path, outPath: outPath);
          }
          fileNameRemap[p.basename(f.path)] = outName;
        }
      }
    }

    final tracks = (jsonMap["tracks"] as List?) ?? const [];
    for (final t in tracks) {
      final track = (t as Map).cast<String, dynamic>();
      final original = track["fileName"] as String?;
      if (original == null) continue;
      final remapped = fileNameRemap[original];
      if (remapped != null) {
        track["fileName"] = remapped;
      }
    }

    await File(
      p.join(staging.path, "project.json"),
    ).writeAsString(jsonEncode(jsonMap));

    final sourceCompatibilityDir = ProjectCompatibilityService.directoryFor(
      projectDir,
    );
    final stagedCompatibilityDir = Directory(
      p.join(staging.path, ProjectCompatibilityService.directoryName),
    );
    // Cloud autosave may publish the canonical editable source before the
    // producer explicitly prepares portable audio. Never package a stale
    // projection beside a newer source revision.
    if (hasCurrentCompatibility && await sourceCompatibilityDir.exists()) {
      await _copyDirectory(sourceCompatibilityDir, stagedCompatibilityDir);
    }

    // meta.json
    final meta = {
      "bundleVersion": 2,
      "audioMode": audioMode.name,
      "exportedAt": DateTime.now().toIso8601String(),
      "hasCompatibilityAudio": await stagedCompatibilityDir.exists(),
    };
    await File(
      p.join(staging.path, "meta.json"),
    ).writeAsString(jsonEncode(meta));

    // --------------------------------------------
    // BUILD THE ZIP USING archive (no ZipFileEncoder)
    // --------------------------------------------

    final archive = Archive();

    // Add project.json
    final stagedProjJson = File(p.join(staging.path, "project.json"));
    final projBytes = stagedProjJson.readAsBytesSync();
    archive.addFile(ArchiveFile("project.json", projBytes.length, projBytes));

    // Add meta.json
    final stagedMetaJson = File(p.join(staging.path, "meta.json"));
    final metaBytes = stagedMetaJson.readAsBytesSync();
    archive.addFile(ArchiveFile("meta.json", metaBytes.length, metaBytes));

    // Add audio files
    final audioDirInStaging = Directory(p.join(staging.path, "audio"));
    if (audioDirInStaging.existsSync()) {
      for (final file in audioDirInStaging.listSync().whereType<File>()) {
        final bytes = file.readAsBytesSync();
        archive.addFile(
          ArchiveFile("audio/${p.basename(file.path)}", bytes.length, bytes),
        );
      }
    }

    if (stagedCompatibilityDir.existsSync()) {
      for (final entity in stagedCompatibilityDir.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: staging.path)
            .replaceAll('\\', '/');
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(relative, bytes.length, bytes));
      }
    }

    // Encode ZIP in memory
    final zipData = ZipEncoder().encode(archive);
    if (zipData.isEmpty) {
      throw Exception("ZipEncoder produced empty archive");
    }

    // Write to disk
    final outFile = File(bundlePath);
    await outFile.writeAsBytes(zipData, flush: true);

    // Sanity check: a successfully written bundle should never be empty.
    final len = await outFile.length();
    if (len <= 0) {
      throw Exception("Export resulted in empty file");
    }

    // Cleanup staging
    try {
      await staging.delete(recursive: true);
    } catch (_) {}

    return bundlePath;
  }

  /// Reads only the canonical source document from a downloaded bundle.
  /// This is used to distinguish a real concurrent edit from a harmless cloud
  /// revision that changed only local/session metadata.
  static Future<Map<String, dynamic>?> readCanonicalProjectJsonFromBundle(
    File bundleFile,
  ) async {
    if (!await bundleFile.exists()) return null;
    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final item in archive) {
        if (item.isDirectory || item.name != 'project.json') continue;
        final decoded = jsonDecode(utf8.decode(item.content));
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      }
    } catch (_) {
      return null;
    } finally {
      input.closeSync();
    }
    return null;
  }

  static Future<void> _convertToFlacLossless({
    required String inPath,
    required String outPath,
  }) async {
    // FLAC is lossless. This preserves audio quality; it just compresses storage.
    // You can add -ar 48000 if you WANT to standardize, but it’s not required.
    final cmd = '-y -i "$inPath" -c:a flac "$outPath"';
    await FFmpegKit.execute(cmd);
  }

  static String _sanitizeFileName(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? "MixroomProject" : cleaned;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      }
    }
  }
}

enum ImportAudioStrategy {
  keepAsBundled, // if bundle has flac, keep flac; if wav keep wav
  convertFlacToWav48k, // if bundle has flac, convert to wav 48k (useful if your engine expects wav)
}

class ProjectBundleImport {
  static const int _maxBundleCompressedBytes = 512 * 1024 * 1024;
  static const int _maxBundleUncompressedBytes = 1024 * 1024 * 1024;
  static const int _maxArchiveEntries = 512;
  static const Set<String> _allowedRootFiles = <String>{
    'project.json',
    'meta.json',
  };

  static const String incomingUpdateDirectoryName = '.incoming_update';

  static Future<Directory> importMixroomBundle({
    required File bundleFile,
    required ImportAudioStrategy audioStrategy,
  }) async {
    if (!bundleFile.existsSync()) throw Exception("Bundle file missing");

    final tmpDir = await getTemporaryDirectory();
    final unpackDir = Directory(
      p.join(
        tmpDir.path,
        "mixroom_unpacked_${DateTime.now().millisecondsSinceEpoch}",
      ),
    );
    await unpackDir.create(recursive: true);

    Directory? destProjectDir;
    var importCompleted = false;

    try {
      await _extractValidatedArchive(
        bundleFile: bundleFile,
        unpackDir: unpackDir,
      );
      final jsonMap = await _readIncomingProjectJson(unpackDir);
      final incomingName = (jsonMap["name"] as String?) ?? "Imported Project";

      destProjectDir = await ProjectManager.createNewProjectDir(
        name: incomingName,
      );

      final resolvedName = p.basename(destProjectDir.path);
      jsonMap["name"] = resolvedName;
      jsonMap["lastOpenedAt"] = DateTime.now().millisecondsSinceEpoch;
      ProjectManager.stripCloudSyncMetadata(jsonMap);

      await _materializeImportedAudio(
        unpackDir: unpackDir,
        destProjectDir: destProjectDir,
        jsonMap: jsonMap,
        audioStrategy: audioStrategy,
      );

      await File(
        p.join(destProjectDir.path, "project.json"),
      ).writeAsString(jsonEncode(jsonMap));

      await _copyIncomingCompatibilityIfPresent(
        unpackDir: unpackDir,
        destProjectDir: destProjectDir,
        sourceProject: jsonMap,
      );

      importCompleted = true;
      return destProjectDir;
    } finally {
      try {
        await unpackDir.delete(recursive: true);
      } catch (_) {}
      if (!importCompleted && destProjectDir != null) {
        try {
          await destProjectDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> updateProjectFromMixroomBundle({
    required Directory projectDir,
    required File bundleFile,
    required ImportAudioStrategy audioStrategy,
  }) async {
    if (!bundleFile.existsSync()) throw Exception("Bundle file missing");
    if (!await projectDir.exists()) {
      throw Exception("Project folder missing");
    }
    final existingJsonFile = File(p.join(projectDir.path, "project.json"));
    if (!await existingJsonFile.exists()) {
      throw Exception("project.json missing in ${projectDir.path}");
    }

    final localJson = await ProjectManager.readProjectJson(projectDir);
    final stagingDir = Directory(
      p.join(projectDir.path, incomingUpdateDirectoryName),
    );
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);

    try {
      await _extractValidatedArchive(
        bundleFile: bundleFile,
        unpackDir: stagingDir,
      );
      final jsonMap = await _readIncomingProjectJson(stagingDir);

      await _materializeImportedAudio(
        unpackDir: stagingDir,
        destProjectDir: projectDir,
        jsonMap: jsonMap,
        audioStrategy: audioStrategy,
      );
      await _replaceCompatibilityDirectory(
        projectDir: projectDir,
        stagingDir: stagingDir,
      );

      final localProjectId = (localJson['projectId'] ?? localJson['project_id'])
          ?.toString()
          .trim();
      if (localProjectId != null && localProjectId.isNotEmpty) {
        jsonMap['projectId'] = localProjectId;
        jsonMap.remove('project_id');
      } else {
        ProjectManager.ensureProjectIdInJson(jsonMap);
      }
      jsonMap['name'] = p.basename(projectDir.path);
      if (localJson.containsKey('createdAt')) {
        jsonMap['createdAt'] = localJson['createdAt'];
      }
      jsonMap['lastOpenedAt'] = DateTime.now().millisecondsSinceEpoch;
      ProjectManager.stripCloudSyncMetadata(jsonMap);

      await ProjectManager.writeProjectJson(projectDir, jsonMap);

      final destCompatibility = ProjectCompatibilityService.directoryFor(
        projectDir,
      );
      if (await destCompatibility.exists()) {
        await ProjectCompatibilityService.rebaseForImportedProject(
          projectDir: projectDir,
          sourceProject: jsonMap,
        );
      }
    } finally {
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<void> _extractValidatedArchive({
    required File bundleFile,
    required Directory unpackDir,
  }) async {
    final archive = _decodeValidatedArchive(bundleFile);
    for (final item in archive) {
      final outPath = _resolveExtractPath(unpackDir, item.name);
      if (item.isDirectory) {
        await Directory(outPath).create(recursive: true);
        continue;
      }

      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      final output = OutputFileStream(outFile.path);
      try {
        item.writeContent(output);
      } finally {
        await output.close();
        item.clear();
      }
    }
  }

  static Future<Map<String, dynamic>> _readIncomingProjectJson(
    Directory unpackDir,
  ) async {
    final incomingJsonFile = File(p.join(unpackDir.path, "project.json"));
    if (!incomingJsonFile.existsSync()) {
      throw Exception("Bundle missing project.json");
    }
    final decoded = jsonDecode(incomingJsonFile.readAsStringSync());
    if (decoded is! Map) {
      throw Exception("Bundle project.json is invalid");
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<void> _materializeImportedAudio({
    required Directory unpackDir,
    required Directory destProjectDir,
    required Map<String, dynamic> jsonMap,
    required ImportAudioStrategy audioStrategy,
  }) async {
    final srcAudioDir = Directory(p.join(unpackDir.path, "audio"));
    final dstAudioDir = Directory(p.join(destProjectDir.path, "audio"));
    await dstAudioDir.create(recursive: true);
    final fileNameRemap = <String, String>{};

    if (await srcAudioDir.exists()) {
      final files = srcAudioDir.listSync(followLinks: false).whereType<File>();
      for (final f in files) {
        final ext = p.extension(f.path).toLowerCase();
        final base = p.basenameWithoutExtension(f.path);

        if (audioStrategy == ImportAudioStrategy.convertFlacToWav48k &&
            ext == ".flac") {
          final outName = "$base.wav";
          final outWav = File(p.join(dstAudioDir.path, outName));
          final cmd =
              '-y -i "${f.path}" -c:a pcm_s16le -ar 48000 "${outWav.path}"';
          await FFmpegKit.execute(cmd);
          fileNameRemap[p.basename(f.path)] = outName;
        } else {
          final outName = p.basename(f.path);
          await f.copy(p.join(dstAudioDir.path, outName));
          fileNameRemap[p.basename(f.path)] = outName;
        }
      }
    }

    if (fileNameRemap.isEmpty) return;
    final tracks = (jsonMap["tracks"] as List?) ?? const [];
    for (final t in tracks) {
      final track = (t as Map).cast<String, dynamic>();
      final original = track["fileName"] as String?;
      if (original == null) continue;
      final remapped = fileNameRemap[original];
      if (remapped != null) {
        track["fileName"] = remapped;
      }
    }
  }

  static Future<void> _copyIncomingCompatibilityIfPresent({
    required Directory unpackDir,
    required Directory destProjectDir,
    required Map<String, dynamic> sourceProject,
  }) async {
    final sourceCompatibilityDir = Directory(
      p.join(unpackDir.path, ProjectCompatibilityService.directoryName),
    );
    if (!await sourceCompatibilityDir.exists()) return;
    final destinationCompatibilityDir =
        ProjectCompatibilityService.directoryFor(destProjectDir);
    await ProjectBundle._copyDirectory(
      sourceCompatibilityDir,
      destinationCompatibilityDir,
    );
    await ProjectCompatibilityService.rebaseForImportedProject(
      projectDir: destProjectDir,
      sourceProject: sourceProject,
    );
  }

  static Future<void> _replaceCompatibilityDirectory({
    required Directory projectDir,
    required Directory stagingDir,
  }) async {
    final incoming = Directory(
      p.join(stagingDir.path, ProjectCompatibilityService.directoryName),
    );
    final dest = ProjectCompatibilityService.directoryFor(projectDir);
    final outgoing = Directory('${dest.path}.outgoing_update');
    if (await outgoing.exists()) {
      await outgoing.delete(recursive: true);
    }

    if (await incoming.exists()) {
      if (await dest.exists()) {
        await dest.rename(outgoing.path);
      }
      try {
        await incoming.rename(dest.path);
      } catch (_) {
        if (await outgoing.exists() && !await dest.exists()) {
          await outgoing.rename(dest.path);
        }
        rethrow;
      }
      if (await outgoing.exists()) {
        await outgoing.delete(recursive: true);
      }
      return;
    }

    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }
  }

  static Archive _decodeValidatedArchive(File bundleFile) {
    final bundleLength = bundleFile.lengthSync();
    if (bundleLength <= 0) {
      throw Exception("Bundle is empty");
    }
    if (bundleLength > _maxBundleCompressedBytes) {
      throw Exception("Bundle is too large to import safely");
    }

    final input = InputFileStream(bundleFile.path);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } finally {
      input.closeSync();
    }

    if (archive.isEmpty) {
      throw Exception("Bundle archive is empty");
    }

    var totalUncompressedBytes = 0;
    var entryCount = 0;
    var hasProjectJson = false;
    final seenPaths = <String>{};

    for (final item in archive) {
      entryCount += 1;
      if (entryCount > _maxArchiveEntries) {
        throw Exception("Bundle contains too many files");
      }

      final normalizedName = _normalizeArchiveEntryName(item.name);
      if (!seenPaths.add(normalizedName)) {
        throw Exception("Bundle contains duplicate files");
      }
      if (item.isSymbolicLink) {
        throw Exception("Bundle contains unsupported symbolic links");
      }
      if (!_isAllowedArchivePath(
        normalizedName,
        isDirectory: item.isDirectory,
      )) {
        throw Exception("Bundle contains unsupported files");
      }

      item.name = normalizedName;
      if (item.isFile) {
        if (item.size < 0) {
          throw Exception("Bundle contains an invalid file entry");
        }
        totalUncompressedBytes += item.size;
        if (totalUncompressedBytes > _maxBundleUncompressedBytes) {
          throw Exception("Bundle expands beyond the safe import limit");
        }
        if (normalizedName == "project.json") {
          hasProjectJson = true;
        }
      }
    }

    if (!hasProjectJson) {
      throw Exception("Bundle missing project.json");
    }
    return archive;
  }

  static String _normalizeArchiveEntryName(String rawName) {
    final normalized = p.posix.normalize(rawName.replaceAll('\\', '/').trim());
    final withoutLeadingSlash = normalized.startsWith('/')
        ? normalized.substring(1)
        : normalized;
    if (withoutLeadingSlash.isEmpty ||
        withoutLeadingSlash == '.' ||
        withoutLeadingSlash == '..' ||
        p.posix.isAbsolute(withoutLeadingSlash) ||
        withoutLeadingSlash.startsWith('../') ||
        withoutLeadingSlash.contains('/../')) {
      throw Exception("Bundle contains an invalid path");
    }
    return withoutLeadingSlash;
  }

  static bool _isAllowedArchivePath(
    String normalizedPath, {
    required bool isDirectory,
  }) {
    if (_allowedRootFiles.contains(normalizedPath)) {
      return !isDirectory;
    }
    if (normalizedPath == 'audio') {
      return isDirectory;
    }
    if (normalizedPath.startsWith('audio/')) {
      final relative = normalizedPath.substring('audio/'.length);
      if (relative.isEmpty) return isDirectory;
      return !isDirectory &&
          !relative.contains('/') &&
          !relative.contains('\\') &&
          p.basename(relative) == relative;
    }
    final root = ProjectCompatibilityService.directoryName;
    if (normalizedPath == root ||
        normalizedPath ==
            '$root/${ProjectCompatibilityService.audioDirectoryName}') {
      return isDirectory;
    }
    if (normalizedPath ==
            '$root/${ProjectCompatibilityService.projectionFileName}' ||
        normalizedPath ==
            '$root/${ProjectCompatibilityService.manifestFileName}') {
      return !isDirectory;
    }
    final prefix = '$root/${ProjectCompatibilityService.audioDirectoryName}/';
    if (!normalizedPath.startsWith(prefix)) return false;
    final relative = normalizedPath.substring(prefix.length);
    return !isDirectory &&
        relative.isNotEmpty &&
        !relative.contains('/') &&
        !relative.contains('\\') &&
        p.basename(relative) == relative;
  }

  static String _resolveExtractPath(Directory unpackDir, String archivePath) {
    final resolved = p.normalize(
      p.joinAll(<String>[unpackDir.path, ...p.posix.split(archivePath)]),
    );
    final root = p.normalize(unpackDir.path);
    if (resolved != root && !p.isWithin(root, resolved)) {
      throw Exception("Bundle attempted to write outside the import directory");
    }
    return resolved;
  }
}
