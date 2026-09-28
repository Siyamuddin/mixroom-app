import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef AiFileStatProvider = Future<FileStat> Function(File file);

class AiFileMetadata {
  const AiFileMetadata({
    required this.normalizedPath,
    required this.available,
    required this.sizeBytes,
    required this.modifiedMilliseconds,
  });

  final String normalizedPath;
  final bool available;
  final int sizeBytes;
  final int modifiedMilliseconds;

  String get analysisSignature => available
      ? '$normalizedPath|$modifiedMilliseconds|$sizeBytes'
      : '$normalizedPath|unavailable';
}

class AiFileMetadataResolution {
  AiFileMetadataResolution({
    required Map<String, AiFileMetadata> byNormalizedPath,
    required this.elapsedMilliseconds,
  }) : byNormalizedPath = UnmodifiableMapView(
         Map<String, AiFileMetadata>.from(byNormalizedPath),
       );

  final Map<String, AiFileMetadata> byNormalizedPath;
  final int elapsedMilliseconds;

  int get uniquePathCount => byNormalizedPath.length;
  int get unavailableCount =>
      byNormalizedPath.values.where((metadata) => !metadata.available).length;

  AiFileMetadata? metadataFor(File file) =>
      byNormalizedPath[normalizeAiFilePath(file.path)];
}

String normalizeAiFilePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  return p.normalize(File(trimmed).absolute.path);
}

Future<AiFileMetadataResolution> resolveAiFileMetadata(
  Iterable<File> files, {
  AiFileStatProvider? statProvider,
  int maxConcurrent = 8,
}) async {
  if (maxConcurrent <= 0) {
    throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
  }
  final stopwatch = Stopwatch()..start();
  final uniqueFiles = <String, File>{};
  for (final file in files) {
    final normalizedPath = normalizeAiFilePath(file.path);
    if (normalizedPath.isEmpty) continue;
    uniqueFiles.putIfAbsent(normalizedPath, () => file);
  }
  final entries = uniqueFiles.entries.toList(growable: false);
  final resolved = <String, AiFileMetadata>{};
  var nextIndex = 0;
  final effectiveStatProvider = statProvider ?? (file) => file.stat();

  Future<void> worker() async {
    while (true) {
      final index = nextIndex++;
      if (index >= entries.length) return;
      final entry = entries[index];
      FileStat? stat;
      try {
        stat = await effectiveStatProvider(entry.value);
      } catch (_) {
        stat = null;
      }
      final available =
          stat?.type == FileSystemEntityType.file && (stat?.size ?? 0) > 44;
      resolved[entry.key] = AiFileMetadata(
        normalizedPath: entry.key,
        available: available,
        sizeBytes: stat?.size ?? 0,
        modifiedMilliseconds: stat?.modified.millisecondsSinceEpoch ?? 0,
      );
    }
  }

  final workerCount = entries.length < maxConcurrent
      ? entries.length
      : maxConcurrent;
  await Future.wait(List<Future<void>>.generate(workerCount, (_) => worker()));
  stopwatch.stop();
  return AiFileMetadataResolution(
    byNormalizedPath: resolved,
    elapsedMilliseconds: stopwatch.elapsedMilliseconds,
  );
}
