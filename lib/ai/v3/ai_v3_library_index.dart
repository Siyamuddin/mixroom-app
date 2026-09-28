enum AiV3LibrarySource {
  bundled('bundled'),
  projectAudio('project_audio'),
  userSamples('user_samples'),
  addedFolder('added_folder');

  const AiV3LibrarySource(this.diagnosticName);

  final String diagnosticName;
}

class AiV3LibraryIndex {
  const AiV3LibraryIndex({
    required this.samplePaths,
    required this.rootCounts,
    required this.scannedCounts,
    required this.includedCounts,
    required this.scannedAudioFileCount,
    required this.uniquePhysicalFileCount,
    required this.duplicatePhysicalFileCount,
    required this.logicalPathCollisionCount,
  });

  final Map<String, String> samplePaths;
  final Map<AiV3LibrarySource, int> rootCounts;
  final Map<AiV3LibrarySource, int> scannedCounts;
  final Map<AiV3LibrarySource, int> includedCounts;
  final int scannedAudioFileCount;
  final int uniquePhysicalFileCount;
  final int duplicatePhysicalFileCount;
  final int logicalPathCollisionCount;

  Map<String, Object?> get diagnosticFields {
    int rootCount(AiV3LibrarySource source) => rootCounts[source] ?? 0;
    int scannedCount(AiV3LibrarySource source) => scannedCounts[source] ?? 0;
    int includedCount(AiV3LibrarySource source) => includedCounts[source] ?? 0;

    return <String, Object?>{
      'library_root_count': rootCounts.values.fold<int>(0, (a, b) => a + b),
      'library_bundled_root_count': rootCount(AiV3LibrarySource.bundled),
      'library_project_audio_root_count': rootCount(
        AiV3LibrarySource.projectAudio,
      ),
      'library_user_samples_root_count': rootCount(
        AiV3LibrarySource.userSamples,
      ),
      'library_added_folder_root_count': rootCount(
        AiV3LibrarySource.addedFolder,
      ),
      'library_scanned_audio_file_count': scannedAudioFileCount,
      'library_unique_physical_file_count': uniquePhysicalFileCount,
      'library_indexed_asset_count': samplePaths.length,
      'library_duplicate_physical_file_count': duplicatePhysicalFileCount,
      'library_logical_path_collision_count': logicalPathCollisionCount,
      for (final source in AiV3LibrarySource.values) ...<String, Object?>{
        'library_${source.diagnosticName}_scanned_count': scannedCount(source),
        'library_${source.diagnosticName}_sample_count': includedCount(source),
      },
    };
  }
}

class AiV3LibraryIndexBuilder {
  final Map<String, String> _samplePaths = <String, String>{};
  final Set<String> _physicalIdentities = <String>{};
  final Map<AiV3LibrarySource, int> _rootCounts = <AiV3LibrarySource, int>{};
  final Map<AiV3LibrarySource, int> _scannedCounts = <AiV3LibrarySource, int>{};
  final Map<AiV3LibrarySource, int> _includedCounts =
      <AiV3LibrarySource, int>{};
  var _scannedAudioFileCount = 0;
  var _duplicatePhysicalFileCount = 0;
  var _logicalPathCollisionCount = 0;

  void addRoot(AiV3LibrarySource source) {
    _rootCounts[source] = (_rootCounts[source] ?? 0) + 1;
  }

  /// Adds one catalog entry and returns whether it was retained.
  ///
  /// The caller supplies a normalized physical identity. This keeps filesystem
  /// and security-scope handling outside this privacy-safe, testable index.
  bool add({
    required String logicalPath,
    required String physicalPath,
    required String physicalIdentity,
    required AiV3LibrarySource source,
  }) {
    _scannedAudioFileCount++;
    _scannedCounts[source] = (_scannedCounts[source] ?? 0) + 1;

    if (!_physicalIdentities.add(physicalIdentity)) {
      _duplicatePhysicalFileCount++;
      return false;
    }
    if (_samplePaths.containsKey(logicalPath)) {
      _logicalPathCollisionCount++;
      return false;
    }

    _samplePaths[logicalPath] = physicalPath;
    _includedCounts[source] = (_includedCounts[source] ?? 0) + 1;
    return true;
  }

  AiV3LibraryIndex build() => AiV3LibraryIndex(
    samplePaths: Map<String, String>.unmodifiable(_samplePaths),
    rootCounts: Map<AiV3LibrarySource, int>.unmodifiable(_rootCounts),
    scannedCounts: Map<AiV3LibrarySource, int>.unmodifiable(_scannedCounts),
    includedCounts: Map<AiV3LibrarySource, int>.unmodifiable(_includedCounts),
    scannedAudioFileCount: _scannedAudioFileCount,
    uniquePhysicalFileCount: _physicalIdentities.length,
    duplicatePhysicalFileCount: _duplicatePhysicalFileCount,
    logicalPathCollisionCount: _logicalPathCollisionCount,
  );
}
