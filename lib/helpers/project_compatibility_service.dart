import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum ProjectCompatibilityScope { instrument, row, group, master }

class ProjectCompatibilityDependency {
  const ProjectCompatibilityDependency({
    required this.key,
    required this.scope,
    required this.pluginId,
    required this.displayName,
    this.row = -1,
    this.groupId = '',
    this.clipId = '',
  });

  final String key;
  final ProjectCompatibilityScope scope;
  final String pluginId;
  final String displayName;
  final int row;
  final String groupId;
  final String clipId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'scope': scope.name,
    'pluginId': pluginId,
    'displayName': displayName,
    if (row >= 0) 'row': row,
    if (groupId.isNotEmpty) 'groupId': groupId,
    if (clipId.isNotEmpty) 'clipId': clipId,
  };
}

class ProjectCompatibilityArtifact {
  const ProjectCompatibilityArtifact({
    required this.dependencyKey,
    required this.fileName,
    required this.fingerprint,
    this.trackJson,
    this.replacementRows = const <int>[],
  });

  final String dependencyKey;
  final String fileName;
  final String fingerprint;
  final Map<String, dynamic>? trackJson;
  final List<int> replacementRows;

  bool get isUsable => fileName.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'dependencyKey': dependencyKey,
    'fileName': fileName,
    'fingerprint': fingerprint,
    if (trackJson != null) 'track': trackJson,
    if (replacementRows.isNotEmpty) 'replacementRows': replacementRows,
  };

  factory ProjectCompatibilityArtifact.fromJson(Map<String, dynamic> json) {
    final track = json['track'];
    return ProjectCompatibilityArtifact(
      dependencyKey: (json['dependencyKey'] ?? '').toString().trim(),
      fileName: (json['fileName'] ?? '').toString().trim(),
      fingerprint: (json['fingerprint'] ?? '').toString().trim(),
      trackJson: track is Map ? Map<String, dynamic>.from(track) : null,
      replacementRows: ((json['replacementRows'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value >= 0)
          .toList(growable: false),
    );
  }
}

class ProjectCompatibilityManifest {
  const ProjectCompatibilityManifest({
    required this.sourceFingerprint,
    required this.dependencies,
    required this.artifacts,
    this.referenceMixFileName = '',
  });

  // v8 gives a rendered master reference its own neutral Master row instead
  // of attaching it to whichever source row happened to be first. It retains
  // the v7 render semantics for master and group processing.
  // Older sidecars are deliberately regenerated on a capable desktop.
  static const int version = 8;

  final String sourceFingerprint;
  final List<ProjectCompatibilityDependency> dependencies;
  final List<ProjectCompatibilityArtifact> artifacts;
  final String referenceMixFileName;

  bool get needsPluginAudio => dependencies.isNotEmpty;

  bool get isCurrent {
    if (!needsPluginAudio) return true;
    final artifactKeys = artifacts
        .where((artifact) => artifact.isUsable)
        .map((artifact) => artifact.dependencyKey)
        .toSet();
    return dependencies.every(
      (dependency) => artifactKeys.contains(dependency.key),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'sourceFingerprint': sourceFingerprint,
    'dependencies': dependencies
        .map((dependency) => dependency.toJson())
        .toList(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    if (referenceMixFileName.trim().isNotEmpty)
      'referenceMixFileName': referenceMixFileName.trim(),
    'current': isCurrent,
  };

  factory ProjectCompatibilityManifest.fromJson(Map<String, dynamic> json) {
    final dependencies = ((json['dependencies'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((raw) => _dependencyFromJson(Map<String, dynamic>.from(raw)))
        .whereType<ProjectCompatibilityDependency>()
        .toList(growable: false);
    final artifacts = ((json['artifacts'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (raw) => ProjectCompatibilityArtifact.fromJson(
            Map<String, dynamic>.from(raw),
          ),
        )
        .toList(growable: false);
    return ProjectCompatibilityManifest(
      sourceFingerprint: (json['sourceFingerprint'] ?? '').toString().trim(),
      dependencies: dependencies,
      artifacts: artifacts,
      referenceMixFileName: (json['referenceMixFileName'] ?? '').toString(),
    );
  }

  static ProjectCompatibilityDependency? _dependencyFromJson(
    Map<String, dynamic> json,
  ) {
    final scope = ProjectCompatibilityScope.values.where(
      (candidate) => candidate.name == (json['scope'] ?? '').toString(),
    );
    if (scope.isEmpty) return null;
    final key = (json['key'] ?? '').toString().trim();
    final pluginId = (json['pluginId'] ?? '').toString().trim();
    if (key.isEmpty || pluginId.isEmpty) return null;
    return ProjectCompatibilityDependency(
      key: key,
      scope: scope.first,
      pluginId: pluginId,
      displayName: (json['displayName'] ?? pluginId).toString().trim(),
      row: (json['row'] as num?)?.toInt() ?? -1,
      groupId: (json['groupId'] ?? '').toString().trim(),
      clipId: (json['clipId'] ?? '').toString().trim(),
    );
  }
}

class ProjectCompatibilityOpenResult {
  const ProjectCompatibilityOpenResult({
    required this.projectState,
    required this.usingCompatibleAudio,
  });

  final Map<String, dynamic> projectState;
  final bool usingCompatibleAudio;
}

/// Owns the portable, plugin-free representation of a project.
///
/// This class intentionally has no dependency on the DAW widget or the native
/// engine. The editor supplies rendered artifacts, while bundle/import/open
/// code can use the manifest independently.
class ProjectCompatibilityService {
  static const String directoryName = 'compatibility';
  static const String projectionFileName = 'project.json';
  static const String manifestFileName = 'manifest.json';
  static const String audioDirectoryName = 'audio';

  static Directory directoryFor(Directory projectDir) =>
      Directory(p.join(projectDir.path, directoryName));
  static File manifestFileFor(Directory projectDir) =>
      File(p.join(directoryFor(projectDir).path, manifestFileName));
  static File projectionFileFor(Directory projectDir) =>
      File(p.join(directoryFor(projectDir).path, projectionFileName));
  static Directory audioDirectoryFor(Directory projectDir) =>
      Directory(p.join(directoryFor(projectDir).path, audioDirectoryName));

  static File resolveAudioFile(Directory projectDir, String fileName) {
    final normalized = p.posix.normalize(fileName.replaceAll('\\', '/'));
    final compatibilityPrefix = '$directoryName/$audioDirectoryName/';
    if (normalized.startsWith(compatibilityPrefix) &&
        !normalized.contains('../')) {
      return File(
        p.joinAll(<String>[projectDir.path, ...p.posix.split(normalized)]),
      );
    }
    return File(p.join(projectDir.path, 'audio', p.basename(normalized)));
  }

  /// Converts an on-disk clip location back to the portable name stored in a
  /// project JSON file. Compatibility audio deliberately lives outside the
  /// canonical `audio/` directory, so reducing every path to its basename
  /// would make the next fallback open look in the wrong directory.
  static String persistedAudioFileName({
    required Directory projectDir,
    required File audioFile,
  }) {
    final compatibilityAudioPath = p.normalize(
      audioDirectoryFor(projectDir).path,
    );
    final filePath = p.normalize(audioFile.path);
    if (p.isWithin(compatibilityAudioPath, filePath)) {
      final relative = p.relative(filePath, from: compatibilityAudioPath);
      return p.posix.join(
        directoryName,
        audioDirectoryName,
        relative.replaceAll('\\', '/'),
      );
    }
    return p.basename(filePath);
  }

  /// Promotes audio from a portable compatibility view into the ordinary
  /// `audio/` folder of a newly edited project. The returned map is keyed by
  /// normalized source path so live clips can be repointed before the first
  /// normal autosave.
  static Future<Map<String, File>> promoteAudioForEditedCopy({
    required Directory sourceProjectDir,
    required Directory editedProjectDir,
    required Iterable<File> audioFiles,
  }) async {
    final sourceCompatibilityAudio = p.normalize(
      audioDirectoryFor(sourceProjectDir).path,
    );
    final destinationAudio = Directory(p.join(editedProjectDir.path, 'audio'));
    await destinationAudio.create(recursive: true);
    final usedNamesLower = <String>{
      for (final file in destinationAudio.listSync().whereType<File>())
        p.basename(file.path).toLowerCase(),
    };
    final promoted = <String, File>{};

    for (final audioFile in audioFiles) {
      final sourcePath = p.normalize(audioFile.path);
      if (!p.isWithin(sourceCompatibilityAudio, sourcePath) ||
          promoted.containsKey(sourcePath)) {
        continue;
      }
      if (!await audioFile.exists()) continue;

      final originalName = p.basename(sourcePath);
      final extension = p.extension(originalName);
      final stem = p.basenameWithoutExtension(originalName);
      var destinationName = originalName;
      var suffix = 1;
      while (!usedNamesLower.add(destinationName.toLowerCase())) {
        destinationName = '$stem #$suffix$extension';
        suffix++;
      }
      final destination = File(p.join(destinationAudio.path, destinationName));
      await audioFile.copy(destination.path);
      promoted[sourcePath] = destination;
    }
    return promoted;
  }

  static String sourceFingerprint(Map<String, dynamic> project) {
    final copy = _copyMap(project)
      ..remove('compatibility')
      ..remove('name')
      ..remove('nameConfirmed')
      ..remove('createdAt')
      ..remove('projectId')
      ..remove('project_id')
      ..remove('ui')
      ..remove('assistantChat')
      ..remove('undoHistory')
      ..remove('cloudProjectId')
      ..remove('cloudWorkspaceId')
      ..remove('cloudOrganizationId')
      ..remove('cloudDocumentRevision')
      ..remove('cloudSyncedAt')
      ..remove('cloudSourceFingerprint')
      ..remove('lastOpenedAt');
    copy['compatibilityRenderSettings'] = _compatibilityRenderSettings(project);
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(copy))))
        .toString();
  }

  /// Fingerprint only the signal path needed by one frozen boundary. This lets
  /// a native-only edit elsewhere update the projection without re-rendering
  /// unrelated third-party audio.
  static String artifactFingerprint(
    Map<String, dynamic> project,
    ProjectCompatibilityDependency dependency,
  ) {
    if (dependency.scope == ProjectCompatibilityScope.master) {
      return sourceFingerprint(project);
    }
    final rows = (project['rows'] as List?) ?? const <Object?>[];
    final rowEffects = (project['rowEffects'] as List?) ?? const <Object?>[];
    final rowStates = (project['rowStates'] as List?) ?? const <Object?>[];
    final tracks = (project['tracks'] as List?) ?? const <Object?>[];
    final relevantRows = <int>{};
    if (dependency.scope == ProjectCompatibilityScope.group) {
      for (final raw
          in ((project['trackGroups'] as List?) ?? const <Object?>[])
              .whereType<Map>()) {
        if ((raw['id'] ?? '').toString() != dependency.groupId) continue;
        final ids = (raw['rowIds'] as List?) ?? const <Object?>[];
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          if (row is Map && ids.contains(row['rowId'])) relevantRows.add(index);
        }
        break;
      }
    } else if (dependency.row >= 0) {
      relevantRows.add(dependency.row);
    }
    final signal = <String, Object?>{
      'renderSettings': _compatibilityRenderSettings(project),
      'tempoBpm': project['tempoBpm'] ?? project['bpm'],
      'timeSignature': project['timeSignature'],
      'rows': <Object?>[
        for (final index in relevantRows)
          if (index >= 0 && index < rows.length) rows[index],
      ],
      'rowEffects': <Object?>[
        for (final raw in rowEffects.whereType<Map>())
          if (relevantRows.contains((raw['row'] as num?)?.toInt())) raw,
      ],
      'rowStates': <Object?>[
        for (final raw in rowStates.whereType<Map>())
          if (relevantRows.contains((raw['row'] as num?)?.toInt())) raw,
      ],
      'tracks': <Object?>[
        for (final raw in tracks.whereType<Map>())
          if (relevantRows.contains((raw['rowIndex'] as num?)?.toInt())) raw,
      ],
    };
    if (dependency.scope == ProjectCompatibilityScope.group) {
      signal['group'] = <Object?>[
        for (final raw
            in ((project['trackGroups'] as List?) ?? const <Object?>[])
                .whereType<Map>())
          if ((raw['id'] ?? '').toString() == dependency.groupId) raw,
      ];
    }
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(signal))))
        .toString();
  }

  static ProjectCompatibilityManifest inspect(Map<String, dynamic> project) {
    final dependencies = <ProjectCompatibilityDependency>[];
    final rowEffects = (project['rowEffects'] as List?) ?? const <Object?>[];
    for (final rawRow in rowEffects.whereType<Map>()) {
      final row = Map<String, dynamic>.from(rawRow);
      final rowIndex = (row['row'] as num?)?.toInt() ?? -1;
      final effects = (row['effects'] as List?) ?? const <Object?>[];
      for (var index = 0; index < effects.length; index++) {
        final effect = effects[index];
        if (effect is! Map) continue;
        final map = Map<String, dynamic>.from(effect);
        final pluginId = _pluginId(map);
        if (!isThirdPartyPlugin(pluginId, origin: map['pluginOrigin'])) {
          continue;
        }
        dependencies.add(
          ProjectCompatibilityDependency(
            key: 'row:$rowIndex:$index:$pluginId',
            scope: ProjectCompatibilityScope.row,
            row: rowIndex,
            pluginId: pluginId,
            displayName: _pluginName(map, pluginId),
          ),
        );
      }
    }

    final groups = (project['trackGroups'] as List?) ?? const <Object?>[];
    for (final rawGroup in groups.whereType<Map>()) {
      final group = Map<String, dynamic>.from(rawGroup);
      final groupId = (group['id'] ?? '').toString().trim();
      final effects = (group['effects'] as List?) ?? const <Object?>[];
      for (var index = 0; index < effects.length; index++) {
        final effect = effects[index];
        if (effect is! Map) continue;
        final map = Map<String, dynamic>.from(effect);
        final pluginId = _pluginId(map);
        if (!isThirdPartyPlugin(pluginId, origin: map['pluginOrigin'])) {
          continue;
        }
        dependencies.add(
          ProjectCompatibilityDependency(
            key: 'group:$groupId:$index:$pluginId',
            scope: ProjectCompatibilityScope.group,
            groupId: groupId,
            pluginId: pluginId,
            displayName: _pluginName(map, pluginId),
          ),
        );
      }
    }

    final master = project['master'];
    final effectsContainer = master is Map ? master['effects'] : null;
    final masterEffects = effectsContainer is Map
        ? (effectsContainer['effects'] as List?) ?? const <Object?>[]
        : const <Object?>[];
    for (var index = 0; index < masterEffects.length; index++) {
      final effect = masterEffects[index];
      if (effect is! Map) continue;
      final map = Map<String, dynamic>.from(effect);
      final pluginId = _pluginId(map);
      if (!isThirdPartyPlugin(pluginId, origin: map['pluginOrigin'])) continue;
      dependencies.add(
        ProjectCompatibilityDependency(
          key: 'master:$index:$pluginId',
          scope: ProjectCompatibilityScope.master,
          pluginId: pluginId,
          displayName: _pluginName(map, pluginId),
        ),
      );
    }

    final tracks = (project['tracks'] as List?) ?? const <Object?>[];
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      if (track is! Map) continue;
      final map = Map<String, dynamic>.from(track);
      final pluginId = (map['instrumentId'] ?? '').toString().trim();
      if (!isThirdPartyPlugin(pluginId, origin: map['instrumentOrigin'])) {
        continue;
      }
      final clipId = (map['clipId'] ?? index).toString().trim();
      dependencies.add(
        ProjectCompatibilityDependency(
          key: 'instrument:$clipId:$pluginId',
          scope: ProjectCompatibilityScope.instrument,
          row: (map['rowIndex'] as num?)?.toInt() ?? -1,
          clipId: clipId,
          pluginId: pluginId,
          displayName: (map['instrumentName'] ?? pluginId).toString().trim(),
        ),
      );
    }

    return ProjectCompatibilityManifest(
      sourceFingerprint: sourceFingerprint(project),
      dependencies: dependencies,
      artifacts: const <ProjectCompatibilityArtifact>[],
    );
  }

  static bool isThirdPartyPlugin(String pluginId, {Object? origin}) {
    if (origin?.toString().trim().toLowerCase() == 'third_party') return true;
    if (origin?.toString().trim().toLowerCase() == 'mixroom') return false;
    final id = pluginId.trim().toLowerCase();
    return id.startsWith('audiounit') ||
        id.startsWith('au:') ||
        id.startsWith('vst3:') ||
        id.endsWith('.vst3') ||
        id.contains('/audio/plug-ins/') ||
        id.contains(r'\');
  }

  static Future<ProjectCompatibilityManifest?> readManifest(
    Directory projectDir,
  ) async {
    final file = manifestFileFor(projectDir);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if ((json['version'] as num?)?.toInt() !=
          ProjectCompatibilityManifest.version) {
        return null;
      }
      return ProjectCompatibilityManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isCurrent(Directory projectDir) async {
    final manifest = await readManifest(projectDir);
    final sourceFile = File(p.join(projectDir.path, 'project.json'));
    final projectionFile = projectionFileFor(projectDir);
    if (manifest == null ||
        !manifest.isCurrent ||
        !await sourceFile.exists() ||
        !await projectionFile.exists()) {
      return false;
    }
    final source = jsonDecode(await sourceFile.readAsString());
    if (source is! Map ||
        manifest.sourceFingerprint !=
            sourceFingerprint(Map<String, dynamic>.from(source))) {
      return false;
    }
    Map<String, dynamic>? projection;
    try {
      final decoded = jsonDecode(await projectionFile.readAsString());
      if (decoded is Map) projection = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return false;
    }
    if (projection == null ||
        !_projectionReferencesFrozenArtifacts(projection, manifest)) {
      return false;
    }
    for (final dependency in manifest.dependencies) {
      final artifact = manifest.artifacts
          .cast<ProjectCompatibilityArtifact?>()
          .firstWhere(
            (candidate) => candidate?.dependencyKey == dependency.key,
            orElse: () => null,
          );
      if (artifact == null ||
          !artifact.isUsable ||
          artifact.fingerprint !=
              artifactFingerprint(
                Map<String, dynamic>.from(source),
                dependency,
              )) {
        return false;
      }
      if (!await File(p.join(projectDir.path, artifact.fileName)).exists()) {
        return false;
      }
    }
    if (manifest.referenceMixFileName.isNotEmpty &&
        !await File(
          p.join(projectDir.path, manifest.referenceMixFileName),
        ).exists()) {
      return false;
    }
    return true;
  }

  static Future<void> writeCompatibleCopy({
    required Directory projectDir,
    required Map<String, dynamic> sourceProject,
    required List<ProjectCompatibilityArtifact> artifacts,
    String referenceMixFileName = '',
  }) async {
    final inspected = inspect(sourceProject);
    final manifest = ProjectCompatibilityManifest(
      sourceFingerprint: inspected.sourceFingerprint,
      dependencies: inspected.dependencies,
      artifacts: artifacts,
      referenceMixFileName: referenceMixFileName,
    );
    if (!manifest.isCurrent) {
      throw StateError(
        'Compatibility render did not cover every plugin dependency.',
      );
    }
    final dir = directoryFor(projectDir);
    await dir.create(recursive: true);
    final projection = buildCompatibleProjection(
      sourceProject: sourceProject,
      manifest: manifest,
    );
    await _writeJsonAtomically(projectionFileFor(projectDir), projection);
    await _writeJsonAtomically(manifestFileFor(projectDir), manifest.toJson());
  }

  /// Returns the unavailable plugin names that were rendered into each row of
  /// an audio compatibility projection. This is display metadata only: the
  /// projection itself stays free of plugin state.
  static Map<int, List<String>> frozenPluginNamesByRow({
    required ProjectCompatibilityManifest manifest,
    required Map<String, dynamic> projection,
  }) {
    final namesByRow = <int, List<String>>{};
    final dependenciesByKey = <String, ProjectCompatibilityDependency>{
      for (final dependency in manifest.dependencies)
        dependency.key: dependency,
    };

    void add(int row, ProjectCompatibilityDependency? dependency) {
      if (row < 0 || dependency == null) return;
      final name = dependency.displayName.trim().isEmpty
          ? dependency.pluginId
          : dependency.displayName.trim();
      if (name.isEmpty) return;
      final names = namesByRow.putIfAbsent(row, () => <String>[]);
      if (!names.contains(name)) names.add(name);
    }

    for (final artifact in manifest.artifacts) {
      final dependency = dependenciesByKey[artifact.dependencyKey];
      for (final row in artifact.replacementRows) {
        add(row, dependency);
      }
      final track = artifact.trackJson;
      final row =
          (track?['rowIndex'] as num?)?.toInt() ?? dependency?.row ?? -1;
      add(row, dependency);
    }

    // Instrument artifacts can be generated from a track snapshot without a
    // dependency row. Resolve their row from the final projection as well.
    final tracks = (projection['tracks'] as List?) ?? const <Object?>[];
    for (final rawTrack in tracks.whereType<Map>()) {
      final track = Map<String, dynamic>.from(rawTrack);
      final fileName = (track['fileName'] ?? '').toString().trim();
      if (fileName.isEmpty) continue;
      ProjectCompatibilityArtifact? artifact;
      for (final candidate in manifest.artifacts) {
        if (candidate.fileName == fileName) {
          artifact = candidate;
          break;
        }
      }
      if (artifact == null) continue;
      add(
        (track['rowIndex'] as num?)?.toInt() ?? -1,
        dependenciesByKey[artifact.dependencyKey],
      );
    }
    return Map<int, List<String>>.unmodifiable(
      namesByRow.map(
        (row, names) => MapEntry(row, List<String>.unmodifiable(names)),
      ),
    );
  }

  /// Persists edits made while opening the portable audio variant. This must
  /// never replace the canonical project because it retains the source plugin
  /// state for a future capable opener.
  static Future<void> writeCompatibleProjection({
    required Directory projectDir,
    required Map<String, dynamic> project,
  }) => _writeJsonAtomically(projectionFileFor(projectDir), project);

  static Future<void> rebaseForImportedProject({
    required Directory projectDir,
    required Map<String, dynamic> sourceProject,
  }) async {
    final manifest = await readManifest(projectDir);
    final projectionFile = projectionFileFor(projectDir);
    if (manifest == null || !await projectionFile.exists()) return;
    try {
      final decoded = jsonDecode(await projectionFile.readAsString());
      if (decoded is Map) {
        final projection = Map<String, dynamic>.from(decoded);
        projection['name'] = sourceProject['name'];
        projection['lastOpenedAt'] = sourceProject['lastOpenedAt'];
        final compatibility = projection['compatibility'];
        if (compatibility is Map) {
          final metadata = Map<String, dynamic>.from(compatibility);
          metadata['sourceFingerprint'] = sourceFingerprint(sourceProject);
          projection['compatibility'] = metadata;
        }
        await _writeJsonAtomically(projectionFile, projection);
      }
      final rebased = ProjectCompatibilityManifest(
        sourceFingerprint: sourceFingerprint(sourceProject),
        dependencies: manifest.dependencies,
        artifacts: manifest.artifacts
            .map(
              (artifact) => ProjectCompatibilityArtifact(
                dependencyKey: artifact.dependencyKey,
                fileName: artifact.fileName,
                fingerprint: artifactFingerprint(
                  sourceProject,
                  manifest.dependencies.firstWhere(
                    (dependency) => dependency.key == artifact.dependencyKey,
                  ),
                ),
                trackJson: artifact.trackJson,
                replacementRows: artifact.replacementRows,
              ),
            )
            .toList(growable: false),
        referenceMixFileName: manifest.referenceMixFileName,
      );
      await _writeJsonAtomically(manifestFileFor(projectDir), rebased.toJson());
    } catch (_) {
      // The source project still imports normally when an optional compatible
      // representation is corrupt or incomplete.
    }
  }

  static Map<String, dynamic> buildCompatibleProjection({
    required Map<String, dynamic> sourceProject,
    required ProjectCompatibilityManifest manifest,
  }) {
    final projection = _copyMap(sourceProject);
    final artifactsByKey = <String, ProjectCompatibilityArtifact>{
      for (final artifact in manifest.artifacts)
        artifact.dependencyKey: artifact,
    };
    final dependencies = <String, ProjectCompatibilityDependency>{
      for (final dependency in manifest.dependencies)
        dependency.key: dependency,
    };
    final replacementArtifacts =
        artifactsByKey.values
            .where(
              (artifact) =>
                  artifact.trackJson != null &&
                  artifact.replacementRows.isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.replacementRows.length.compareTo(a.replacementRows.length),
          );
    final selectedReplacements = <ProjectCompatibilityArtifact>[];
    final replacedRows = <int>{};
    for (final artifact in replacementArtifacts) {
      if (artifact.replacementRows.any(replacedRows.contains)) continue;
      selectedReplacements.add(artifact);
      replacedRows.addAll(artifact.replacementRows);
    }
    final rows = List<Object?>.from(
      (projection['rows'] as List?) ?? const <Object?>[],
    );
    projection['rows'] = rows;
    final usesReferenceMix =
        manifest.referenceMixFileName.trim().isNotEmpty &&
        manifest.dependencies.any(
          (dependency) => dependency.scope == ProjectCompatibilityScope.master,
        );
    if (usesReferenceMix) {
      // A master plug-in affects the entire mix. Its compatibility artifact is
      // therefore the authoritative playback source, not merely a reference
      // file alongside tracks that no longer have the master plug-in.
      selectedReplacements.clear();
      replacedRows
        ..clear()
        ..addAll(List<int>.generate(rows.length, (index) => index));
    }
    final rowIndexById = <int, int>{
      for (var index = 0; index < rows.length; index++)
        if (rows[index] is Map && (rows[index] as Map)['rowId'] is num)
          ((rows[index] as Map)['rowId'] as num).toInt(): index,
    };
    for (final rowIndex in replacedRows) {
      if (rowIndex < 0 || rowIndex >= rows.length) continue;
      final rawRow = rows[rowIndex];
      if (rawRow is! Map) continue;
      final row = Map<String, dynamic>.from(rawRow);
      row['kind'] = 'audio';
      row.remove('instrumentId');
      row.remove('instrumentName');
      row.remove('instrumentParams');
      row.remove('hostedInstrumentStateB64');
      row.remove('hostedInstrumentStateBase64');
      rows[rowIndex] = row;
    }

    final rowEffects = (projection['rowEffects'] as List?) ?? <Object?>[];
    for (final rawRow in rowEffects.whereType<Map>()) {
      final row = Map<String, dynamic>.from(rawRow);
      final rowIndex = (row['row'] as num?)?.toInt() ?? -1;
      final effects = (row['effects'] as List?) ?? <Object?>[];
      row['effects'] = replacedRows.contains(rowIndex)
          ? <Object?>[]
          : <Object?>[
              for (var index = 0; index < effects.length; index++)
                if (!_isDependency(dependencies, 'row:$rowIndex:$index:'))
                  effects[index],
            ];
      _replaceMapInList(rowEffects, rawRow, row);
    }

    // A frozen file already includes the row's automation, gain, pan, and
    // effects. Reset the destination row to neutral audio processing.
    final rowStates = (projection['rowStates'] as List?) ?? <Object?>[];
    for (final rawState in rowStates.whereType<Map>()) {
      final state = Map<String, dynamic>.from(rawState);
      final rowIndex = (state['row'] as num?)?.toInt() ?? -1;
      if (!replacedRows.contains(rowIndex)) continue;
      state['gain'] = 2.0;
      state['pan'] = 0.5;
      state['muted'] = false;
      state['soloed'] = false;
      state['volumeAutomation'] = <Object?>[
        <String, double>{'x': 0.0, 'volume': 1.0},
        <String, double>{'x': 1.0, 'volume': 1.0},
      ];
      state['automationLanes'] = <Object?>[];
      state['automationClips'] = <Object?>[];
      state['selectedAutomationTargetId'] = 'volume';
      _replaceMapInList(rowStates, rawState, state);
    }

    final groups = (projection['trackGroups'] as List?) ?? <Object?>[];
    for (final rawGroup in groups.whereType<Map>()) {
      final group = Map<String, dynamic>.from(rawGroup);
      final groupId = (group['id'] ?? '').toString().trim();
      final effects = (group['effects'] as List?) ?? <Object?>[];
      final groupRows = ((group['rowIds'] as List?) ?? const <Object?>[])
          .whereType<num>()
          .map((value) => rowIndexById[value.toInt()] ?? -1)
          .where((value) => value >= 0)
          .toSet();
      final groupWasFrozen =
          groupRows.isNotEmpty && groupRows.every(replacedRows.contains);
      group['effects'] = groupWasFrozen
          ? <Object?>[]
          : <Object?>[
              for (var index = 0; index < effects.length; index++)
                if (!_isDependency(dependencies, 'group:$groupId:$index:'))
                  effects[index],
            ];
      if (groupWasFrozen) {
        group['gain'] = 2.0;
        group['pan'] = 0.5;
        group['muted'] = false;
        group['soloed'] = false;
      }
      _replaceMapInList(groups, rawGroup, group);
    }

    final master = projection['master'];
    if (master is Map) {
      final masterMap = Map<String, dynamic>.from(master);
      final effectsContainer = masterMap['effects'];
      if (effectsContainer is Map) {
        final effectsMap = Map<String, dynamic>.from(effectsContainer);
        final effects = (effectsMap['effects'] as List?) ?? <Object?>[];
        effectsMap['effects'] = usesReferenceMix
            ? <Object?>[]
            : <Object?>[
                for (var index = 0; index < effects.length; index++)
                  if (!_isDependency(dependencies, 'master:$index:'))
                    effects[index],
              ];
        masterMap['effects'] = effectsMap;
      }
      if (usesReferenceMix) {
        // The reference mix already contains all master gain, pan, automation,
        // and effects, including native processors around the unavailable one.
        masterMap['gain'] = 2.0;
        masterMap['pan'] = 0.5;
        masterMap['muted'] = false;
      }
      projection['master'] = masterMap;
    }

    var referenceMixRowId = -1;
    if (usesReferenceMix) {
      final existingRowIds = rows
          .whereType<Map>()
          .map((row) => (row['rowId'] as num?)?.toInt() ?? -1)
          .where((rowId) => rowId >= 0);
      referenceMixRowId =
          existingRowIds.fold<int>(0, (a, b) => a > b ? a : b) + 1;

      rows.insert(0, <String, dynamic>{
        'rowId': referenceMixRowId,
        'name': 'Master',
        'iconId': 0,
        'kind': 'audio',
        'inputChannelStart': 0,
        'inputChannelCount': 1,
      });

      projection['rowStates'] = <Object?>[
        <String, dynamic>{
          'row': 0,
          'rowId': referenceMixRowId,
          'gain': 2.0,
          'pan': 0.5,
          'volumeAutomation': <Object?>[
            <String, double>{'x': 0.0, 'volume': 1.0},
            <String, double>{'x': 1.0, 'volume': 1.0},
          ],
          'automationLanes': <Object?>[],
          'automationClips': <Object?>[],
          'selectedAutomationTargetId': 'volume',
          'muted': false,
          'soloed': false,
          'inputChannelStart': 0,
          'inputChannelCount': 1,
        },
        for (final rawState in rowStates.whereType<Map>())
          if (((rawState['row'] as num?)?.toInt() ?? -1) >= 0 &&
              ((rawState['row'] as num?)?.toInt() ?? -1) < rows.length - 1)
            <String, dynamic>{
              ...Map<String, dynamic>.from(rawState),
              'row': ((rawState['row'] as num?)?.toInt() ?? -1) + 1,
            },
      ];
      projection['rowEffects'] = <Object?>[
        <String, dynamic>{
          'row': 0,
          'rowId': referenceMixRowId,
          'effects': <Object?>[],
        },
        for (final rawEffects in rowEffects.whereType<Map>())
          if (((rawEffects['row'] as num?)?.toInt() ?? -1) >= 0 &&
              ((rawEffects['row'] as num?)?.toInt() ?? -1) < rows.length - 1)
            <String, dynamic>{
              ...Map<String, dynamic>.from(rawEffects),
              'row': ((rawEffects['row'] as num?)?.toInt() ?? -1) + 1,
            },
      ];
    }

    final tracks = (projection['tracks'] as List?) ?? <Object?>[];
    final compatibleTracks = <Object?>[];
    for (var index = 0; index < tracks.length; index++) {
      final rawTrack = tracks[index];
      if (rawTrack is! Map) {
        compatibleTracks.add(rawTrack);
        continue;
      }
      final track = Map<String, dynamic>.from(rawTrack);
      final rowIndex = (track['rowIndex'] as num?)?.toInt() ?? -1;
      if (replacedRows.contains(rowIndex)) continue;
      final pluginId = (track['instrumentId'] ?? '').toString().trim();
      final clipId = (track['clipId'] ?? index).toString().trim();
      final key = 'instrument:$clipId:$pluginId';
      final artifact = artifactsByKey[key];
      if (artifact == null) {
        compatibleTracks.add(track);
        continue;
      }
      final rendered = artifact.trackJson == null
          ? Map<String, dynamic>.from(track)
          : _copyMap(artifact.trackJson!);
      rendered['fileName'] = artifact.fileName;
      rendered['clipType'] = 'audio';
      rendered['instrumentId'] = '';
      rendered['instrumentName'] = '';
      rendered['instrumentParams'] = <String, dynamic>{};
      rendered['midiNotes'] = <Object?>[];
      rendered.remove('hostedInstrumentStateB64');
      compatibleTracks.add(rendered);
    }
    final appendedFallbackKeys = <String>{};
    for (final artifact in selectedReplacements) {
      if (!appendedFallbackKeys.add(artifact.fileName)) continue;
      final track = _copyMap(artifact.trackJson!);
      track['fileName'] = artifact.fileName;
      track['clipType'] = 'audio';
      track['instrumentId'] = '';
      track['instrumentName'] = '';
      track['instrumentParams'] = <String, dynamic>{};
      track['midiNotes'] = <Object?>[];
      track.remove('hostedInstrumentStateB64');
      compatibleTracks.add(track);
    }
    if (usesReferenceMix) {
      compatibleTracks
        ..clear()
        ..add(<String, dynamic>{
          'fileName': manifest.referenceMixFileName.trim(),
          'label': 'Original mix',
          'clipType': 'audio',
          'clipId': 'compatibility-original-mix',
          'instrumentId': '',
          'instrumentName': '',
          'instrumentParams': <String, dynamic>{},
          'midiNotes': <Object?>[],
          'rowIndex': 0,
          'rowId': referenceMixRowId,
          'offset': 0.0,
          'gain': 2.0,
          'normalizeVolume': false,
          'normalizeGain': 1.0,
          'preNormalizeGain': 2.0,
          'trimStartMs': 0,
        });
    }
    projection['tracks'] = compatibleTracks;
    projection['compatibility'] = <String, dynamic>{
      'variant': 'audio',
      'sourceFingerprint': manifest.sourceFingerprint,
      if (manifest.referenceMixFileName.isNotEmpty)
        'referenceMixFileName': manifest.referenceMixFileName,
    };
    return projection;
  }

  static Future<ProjectCompatibilityOpenResult> resolveForOpen({
    required Directory projectDir,
    required Map<String, dynamic> sourceProject,
    required bool canHostExternalPlugins,
    required bool Function(String pluginId) hasPlugin,
  }) async {
    final manifest = await readManifest(projectDir);
    final sourceFingerprintValue = sourceFingerprint(sourceProject);
    final allPluginsAvailable =
        canHostExternalPlugins &&
        (manifest?.dependencies.every(
              (dependency) => hasPlugin(dependency.pluginId),
            ) ??
            true);
    if (allPluginsAvailable ||
        manifest == null ||
        manifest.sourceFingerprint != sourceFingerprintValue ||
        !await isCurrent(projectDir)) {
      return ProjectCompatibilityOpenResult(
        projectState: sourceProject,
        usingCompatibleAudio: false,
      );
    }
    try {
      final decoded = jsonDecode(
        await projectionFileFor(projectDir).readAsString(),
      );
      if (decoded is Map) {
        return ProjectCompatibilityOpenResult(
          projectState: Map<String, dynamic>.from(decoded),
          usingCompatibleAudio: true,
        );
      }
    } catch (_) {}
    return ProjectCompatibilityOpenResult(
      projectState: sourceProject,
      usingCompatibleAudio: false,
    );
  }

  static String _pluginId(Map<String, dynamic> json) =>
      (json['effectId'] ?? json['pluginId'] ?? json['id'] ?? '')
          .toString()
          .trim();

  static String _pluginName(Map<String, dynamic> json, String fallback) =>
      (json['displayName'] ?? json['name'] ?? fallback).toString().trim();

  static bool _isDependency(
    Map<String, ProjectCompatibilityDependency> dependencies,
    String prefix,
  ) => dependencies.keys.any((key) => key.startsWith(prefix));

  static void _replaceMapInList(
    List list,
    Map oldValue,
    Map<String, dynamic> newValue,
  ) {
    final index = list.indexOf(oldValue);
    if (index >= 0) list[index] = newValue;
  }

  static Map<String, dynamic> _copyMap(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

  /// These values live in the UI map for historical reasons, but they change
  /// the signal produced by an offline plugin render. Keep the rest of the UI
  /// metadata out of fingerprints so cosmetic changes do not create work.
  static Map<String, Object?> _compatibilityRenderSettings(
    Map<String, dynamic> project,
  ) {
    final ui = project['ui'];
    if (ui is! Map) return const <String, Object?>{};
    return <String, Object?>{
      'sampleRate': ui['sampleRate'],
      'crossfadeMode': ui['crossfadeMode'],
    };
  }

  static bool _projectionReferencesFrozenArtifacts(
    Map<String, dynamic> projection,
    ProjectCompatibilityManifest manifest,
  ) {
    final frozenFileNames = ((projection['tracks'] as List?) ?? const [])
        .whereType<Map>()
        .map((track) => (track['fileName'] ?? '').toString().trim())
        .toSet();
    final usesReferenceMix =
        manifest.referenceMixFileName.trim().isNotEmpty &&
        manifest.dependencies.any(
          (dependency) => dependency.scope == ProjectCompatibilityScope.master,
        );
    if (usesReferenceMix) {
      return frozenFileNames.contains(manifest.referenceMixFileName.trim());
    }
    return manifest.artifacts
        .where((artifact) => artifact.trackJson != null)
        .every((artifact) => frozenFileNames.contains(artifact.fileName));
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): _canonicalize(entry.value),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }

  static Future<void> _writeJsonAtomically(
    File file,
    Map<String, dynamic> json,
  ) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
