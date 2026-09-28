import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_library_index.dart';

void main() {
  test('deduplicates overlapping roots by physical file identity', () {
    final builder = AiV3LibraryIndexBuilder()
      ..addRoot(AiV3LibrarySource.bundled)
      ..addRoot(AiV3LibrarySource.addedFolder);

    expect(
      builder.add(
        logicalPath: 'Starter Kit/Kick.wav',
        physicalPath: '/samples/Starter Kit/Kick.wav',
        physicalIdentity: '/samples/Starter Kit/Kick.wav',
        source: AiV3LibrarySource.bundled,
      ),
      isTrue,
    );
    expect(
      builder.add(
        logicalPath: 'samples/Starter Kit/Kick.wav',
        physicalPath: '/samples/Starter Kit/Kick.wav',
        physicalIdentity: '/samples/Starter Kit/Kick.wav',
        source: AiV3LibrarySource.addedFolder,
      ),
      isFalse,
    );
    expect(
      builder.add(
        logicalPath: 'Starter Kit/Kick.wav',
        physicalPath: '/other/Starter Kit/Kick.wav',
        physicalIdentity: '/other/Starter Kit/Kick.wav',
        source: AiV3LibrarySource.addedFolder,
      ),
      isFalse,
    );

    final index = builder.build();
    expect(index.samplePaths, <String, String>{
      'Starter Kit/Kick.wav': '/samples/Starter Kit/Kick.wav',
    });
    expect(index.scannedAudioFileCount, 3);
    expect(index.uniquePhysicalFileCount, 2);
    expect(index.duplicatePhysicalFileCount, 1);
    expect(index.logicalPathCollisionCount, 1);
    expect(index.diagnosticFields, containsPair('library_root_count', 2));
    expect(
      index.diagnosticFields,
      containsPair('library_indexed_asset_count', 1),
    );
    expect(
      index.diagnosticFields,
      containsPair('library_bundled_sample_count', 1),
    );
    expect(
      index.diagnosticFields,
      containsPair('library_added_folder_scanned_count', 2),
    );
  });
}
