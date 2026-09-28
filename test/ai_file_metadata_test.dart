import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/ai_file_metadata.dart';

void main() {
  test('availability preserves the existing 44-byte boundary', () async {
    final root = await Directory.systemTemp.createTemp('ai_file_metadata_');
    addTearDown(() => root.delete(recursive: true));
    final empty = File('${root.path}/empty.wav')..writeAsBytesSync(const []);
    final boundary = File('${root.path}/boundary.wav')
      ..writeAsBytesSync(List<int>.filled(44, 0));
    final available = File('${root.path}/available.wav')
      ..writeAsBytesSync(List<int>.filled(45, 0));

    final result = await resolveAiFileMetadata(<File>[
      empty,
      boundary,
      available,
    ]);

    expect(result.metadataFor(empty)?.available, isFalse);
    expect(result.metadataFor(boundary)?.available, isFalse);
    expect(result.metadataFor(available)?.available, isTrue);
  });

  test('missing, directory, and stat failures are unavailable', () async {
    final root = await Directory.systemTemp.createTemp('ai_file_metadata_');
    addTearDown(() => root.delete(recursive: true));
    final missing = File('${root.path}/missing.wav');
    final directory = File(root.path);
    final failed = File('${root.path}/failed.wav');

    final result = await resolveAiFileMetadata(
      <File>[missing, directory, failed],
      statProvider: (file) async {
        if (file.path == failed.path) throw const FileSystemException('test');
        return file.stat();
      },
    );

    expect(result.unavailableCount, 3);
    expect(result.metadataFor(missing)?.available, isFalse);
    expect(result.metadataFor(directory)?.available, isFalse);
    expect(result.metadataFor(failed)?.available, isFalse);
  });

  test('deduplicates normalized paths', () async {
    var calls = 0;
    final file = File('/tmp/pro118/clip.wav');
    final duplicate = File('/tmp/pro118/folder/../clip.wav');

    final result = await resolveAiFileMetadata(
      <File>[file, duplicate, file],
      statProvider: (_) async {
        calls++;
        return FileStat.stat('/dev/null');
      },
    );

    expect(result.uniquePathCount, 1);
    expect(calls, 1);
  });

  test('processes every path with at most eight concurrent stats', () async {
    var active = 0;
    var maximumActive = 0;
    var calls = 0;
    final files = List<File>.generate(
      25,
      (index) => File('/tmp/pro118/concurrency_$index.wav'),
    );

    final result = await resolveAiFileMetadata(
      files,
      statProvider: (_) async {
        calls++;
        active++;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return FileStat.stat('/dev/null');
      },
    );

    expect(result.uniquePathCount, 25);
    expect(calls, 25);
    expect(maximumActive, 8);
  });

  test('size or modification changes the analysis signature', () async {
    final root = await Directory.systemTemp.createTemp('ai_file_metadata_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/signature.wav')
      ..writeAsBytesSync(List<int>.filled(45, 0));

    final first = await resolveAiFileMetadata(<File>[file]);
    file.writeAsBytesSync(List<int>.filled(46, 0));
    file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
    final second = await resolveAiFileMetadata(<File>[file]);

    expect(
      first.metadataFor(file)?.analysisSignature,
      isNot(second.metadataFor(file)?.analysisSignature),
    );
  });
}
