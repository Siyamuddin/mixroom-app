import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:path/path.dart' as p;

Map<String, String> _parseSfzOpcodes(String lineRaw) {
  final line = lineRaw.split('//').first.trim();
  if (line.isEmpty) return const <String, String>{};

  final pattern = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)=');
  final matches = pattern.allMatches(line).toList(growable: false);
  if (matches.isEmpty) return const <String, String>{};

  final out = <String, String>{};
  for (var i = 0; i < matches.length; i++) {
    final valueStart = matches[i].end;
    final valueEnd =
        i + 1 < matches.length ? matches[i + 1].start : line.length;
    if (valueStart >= valueEnd) continue;
    final key = (matches[i].group(1) ?? '').trim().toLowerCase();
    final value = line.substring(valueStart, valueEnd).trim();
    if (key.isEmpty || value.isEmpty) continue;
    out[key] = value;
  }
  return out;
}

({String? blockTag, Map<String, String> opcodes}) _parseSfzLine(
    String rawLine) {
  final line = rawLine.split('//').first.trim();
  if (line.isEmpty) {
    return (blockTag: null, opcodes: const <String, String>{});
  }

  String? blockTag;
  var remainder = line;
  final tagMatch = RegExp(r'^<\s*([A-Za-z0-9_]+)\s*>').firstMatch(line);
  if (tagMatch != null) {
    blockTag = (tagMatch.group(1) ?? '').trim().toLowerCase();
    remainder = line.substring(tagMatch.end).trim();
  }

  return (
    blockTag: blockTag,
    opcodes: remainder.isEmpty
        ? const <String, String>{}
        : _parseSfzOpcodes(remainder),
  );
}

String _normalizeAssetPath(String rawPath) {
  var path = rawPath.trim().replaceAll('\\', '/');
  while (path.contains('//')) {
    path = path.replaceAll('//', '/');
  }
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  return path;
}

String _resolveSfzSampleAssetPath({
  required String sfzAssetPath,
  required String defaultPathRaw,
  required String samplePathRaw,
}) {
  final sfzDir = p.posix.dirname(sfzAssetPath);
  final defaultPath = _normalizeAssetPath(defaultPathRaw);
  final samplePath = _normalizeAssetPath(samplePathRaw);
  return _normalizeAssetPath(p.posix.join(sfzDir, defaultPath, samplePath));
}

Set<String> _extractStaticSfzPaths(String source) {
  final out = <String>{};
  final regex = RegExp(r'''assets/instruments/[^"'\s]+\.sfz''');
  for (final match in regex.allMatches(source)) {
    final value = match.group(0)?.trim();
    if (value != null && value.isNotEmpty) {
      out.add(_normalizeAssetPath(value));
    }
  }
  return out;
}

Future<List<Map<String, String>>> _parseSfzRegions(File sfzFile) async {
  final control = <String, String>{};
  final global = <String, String>{};
  final master = <String, String>{};
  final group = <String, String>{};
  Map<String, String>? region;
  var currentBlock = '';
  final regions = <Map<String, String>>[];

  for (final rawLine
      in const LineSplitter().convert(await sfzFile.readAsString())) {
    final parsed = _parseSfzLine(rawLine);
    final tag = parsed.blockTag;
    if (tag != null && tag.isNotEmpty) {
      currentBlock = tag;
      if (tag == 'group') {
        group.clear();
      } else if (tag == 'master') {
        master.clear();
      } else if (tag == 'region') {
        region = <String, String>{}
          ..addAll(control)
          ..addAll(global)
          ..addAll(master)
          ..addAll(group);
        regions.add(region);
      }
    }

    final opcodes = parsed.opcodes;
    if (opcodes.isEmpty) continue;

    switch (currentBlock) {
      case 'control':
        control.addAll(opcodes);
        break;
      case 'global':
        global.addAll(opcodes);
        break;
      case 'master':
        master.addAll(opcodes);
        break;
      case 'group':
        group.addAll(opcodes);
        break;
      case 'region':
        region ??= <String, String>{}
          ..addAll(control)
          ..addAll(global)
          ..addAll(master)
          ..addAll(group);
        region.addAll(opcodes);
        break;
    }
  }

  return regions;
}

int _sfzInt(Map<String, String> region, String key, int fallback) {
  return int.tryParse((region[key] ?? '').trim()) ?? fallback;
}

List<File> _filesUnder(Directory directory) {
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList(growable: false)
    ..sort((a, b) => a.path.compareTo(b.path));
}

int _directorySize(Directory directory) => _filesUnder(directory).fold<int>(
      0,
      (total, file) => total + file.lengthSync(),
    );

Digest _aggregateFileDigest(Iterable<File> files) {
  final bytes = <int>[];
  for (final file in files) {
    bytes.addAll(file.readAsBytesSync());
  }
  return sha256.convert(bytes);
}

Future<void> _expectChromaticGuitarMapping({
  required File sfzFile,
  required int expectedRegionCount,
  required int lowPitch,
  required int highPitch,
}) async {
  expect(sfzFile.existsSync(), isTrue, reason: 'Missing ${sfzFile.path}.');
  final regions = (await _parseSfzRegions(sfzFile))
      .where((region) => (region['sample'] ?? '').trim().isNotEmpty)
      .toList(growable: false);
  expect(regions.length, expectedRegionCount);

  const velocities = <int>[0, 1, 64, 127];
  for (var pitch = lowPitch; pitch <= highPitch; pitch++) {
    for (final velocity in velocities) {
      final matches = regions.where((region) {
        final key = int.tryParse((region['key'] ?? '').trim());
        final loKey = key ?? _sfzInt(region, 'lokey', 0);
        final hiKey = key ?? _sfzInt(region, 'hikey', 127);
        final loVel = _sfzInt(region, 'lovel', 0);
        final hiVel = _sfzInt(region, 'hivel', 127);
        return pitch >= loKey &&
            pitch <= hiKey &&
            velocity >= loVel &&
            velocity <= hiVel;
      }).toList(growable: false);
      expect(matches, isNotEmpty,
          reason: 'Expected a region for MIDI $pitch at velocity $velocity '
              'in ${sfzFile.path}.');
      final sequenceLengths = matches
          .map((region) => _sfzInt(region, 'seq_length', 1))
          .toSet();
      expect(sequenceLengths.length, 1,
          reason: 'MIDI $pitch at velocity $velocity mixes sequence lengths '
              'in ${sfzFile.path}.');
      final sequenceLength = sequenceLengths.single;
      expect(matches.length, sequenceLength,
          reason: 'Expected one region per sequence position for MIDI $pitch '
              'at velocity $velocity in ${sfzFile.path}.');
      expect(
        matches
            .map((region) => _sfzInt(region, 'seq_position', 1))
            .toSet(),
        <int>{for (var position = 1; position <= sequenceLength; position++) position},
        reason: 'Missing or duplicate sequence position for MIDI $pitch at '
            'velocity $velocity in ${sfzFile.path}.',
      );
    }
  }

  for (final pitch in <int>[lowPitch - 1, highPitch + 1]) {
    final matches = regions.where((region) {
      final key = int.tryParse((region['key'] ?? '').trim());
      final loKey = key ?? _sfzInt(region, 'lokey', 0);
      final hiKey = key ?? _sfzInt(region, 'hikey', 127);
      return pitch >= loKey && pitch <= hiKey;
    });
    expect(matches, isEmpty,
        reason: 'MIDI $pitch must remain unmapped in ${sfzFile.path}.');
  }
}

void main() {
  test('bundled instrument catalog resolves every indexed SFZ preset',
      () async {
    final repoRoot = Directory.current;
    final indexFile =
        File(p.join(repoRoot.path, 'assets', 'instruments', 'index.json'));
    expect(indexFile.existsSync(), isTrue,
        reason: 'Missing bundled instrument index.');

    final decoded =
        jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final defaultPack = (decoded['pack'] as String?)?.trim() ?? '';
    final presets = (decoded['presets'] as List?) ?? const <dynamic>[];
    expect(presets, isNotEmpty, reason: 'Bundled instrument index is empty.');

    for (final rawEntry in presets) {
      final entry = (rawEntry as Map).cast<String, dynamic>();
      final presetFile = (entry['preset'] as String?)?.trim() ?? '';
      expect(presetFile, isNotEmpty,
          reason: 'Indexed preset is missing its SFZ filename.');
      final entryPack = (entry['pack'] as String?)?.trim() ?? '';
      final pack = entryPack.isEmpty ? defaultPack : entryPack;
      expect(pack, isNotEmpty,
          reason: 'Indexed preset is missing a resolvable pack.');

      final sfzAssetPath =
          p.posix.join('assets', 'instruments', pack, presetFile);
      final sfzFile = File(p.join(repoRoot.path, sfzAssetPath));
      expect(
        sfzFile.existsSync(),
        isTrue,
        reason: 'Indexed SFZ preset is missing: $sfzAssetPath',
      );

      final control = <String, String>{};
      final global = <String, String>{};
      final master = <String, String>{};
      final group = <String, String>{};
      Map<String, String>? region;
      var currentBlock = '';
      final regions = <Map<String, String>>[];

      for (final rawLine
          in const LineSplitter().convert(await sfzFile.readAsString())) {
        final parsed = _parseSfzLine(rawLine);
        final tag = parsed.blockTag;
        if (tag != null && tag.isNotEmpty) {
          currentBlock = tag;
          if (tag == 'group') {
            group.clear();
          } else if (tag == 'master') {
            master.clear();
          } else if (tag == 'region') {
            region = <String, String>{}
              ..addAll(control)
              ..addAll(global)
              ..addAll(master)
              ..addAll(group);
            regions.add(region);
          }
        }

        final opcodes = parsed.opcodes;
        if (opcodes.isEmpty) continue;

        switch (currentBlock) {
          case 'control':
            control.addAll(opcodes);
            break;
          case 'global':
            global.addAll(opcodes);
            break;
          case 'master':
            master.addAll(opcodes);
            break;
          case 'group':
            group.addAll(opcodes);
            break;
          case 'region':
            region ??= <String, String>{}
              ..addAll(control)
              ..addAll(global)
              ..addAll(master)
              ..addAll(group);
            region.addAll(opcodes);
            break;
        }
      }

      final defaultPathRaw = control['default_path'] ?? '';
      final sampleRegions = regions
          .where((region) => (region['sample'] ?? '').trim().isNotEmpty)
          .toList();
      expect(
        sampleRegions,
        isNotEmpty,
        reason: 'SFZ preset parsed with zero sample regions: $sfzAssetPath',
      );

      for (final region in sampleRegions) {
        final sampleAssetPath = _resolveSfzSampleAssetPath(
          sfzAssetPath: sfzAssetPath,
          defaultPathRaw: region['default_path'] ?? defaultPathRaw,
          samplePathRaw: region['sample'] ?? '',
        );
        final sampleFile = File(p.join(repoRoot.path, sampleAssetPath));
        expect(
          sampleFile.existsSync(),
          isTrue,
          reason: 'Missing sample for $sfzAssetPath: $sampleAssetPath',
        );
      }
    }
  });

  test('bundled guitars retain approved mappings, hashes, and size budgets',
      () async {
    final repoRoot = Directory.current;
    final index = jsonDecode(await File(p.join(
      repoRoot.path,
      'assets',
      'instruments',
      'index.json',
    )).readAsString()) as Map<String, dynamic>;
    final entries = (index['presets'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final expectedCatalogValues = <String, Map<String, Object>>{
      'sfz.guitar.steel_acoustic': <String, Object>{
        'pack': 'FreePats-Spanish-Classical-Guitar-2019-06-18',
        'name': 'Acoustic Guitar',
        'source_project': 'FreePats Spanish Classical Guitar',
        'outputGain': 1.0,
        'attackMs': 2.0,
        'releaseMs': 350.0,
      },
      'sfz.guitar.clean_electric': <String, Object>{
        'pack': 'Karoryfer-Black-And-Green-Guitars-1.000',
        'name': 'Electric Guitar',
        'source_project': 'Karoryfer Black And Green Guitars',
        'outputGain': 2.0,
        'attackMs': 2.0,
        'releaseMs': 250.0,
      },
    };
    for (final expected in expectedCatalogValues.entries) {
      final entry = entries.singleWhere((entry) => entry['id'] == expected.key);
      expect(entry['category'], 'Guitars');
      expect(entry['source_license'], 'CC0 1.0 Universal');
      for (final value in expected.value.entries) {
        expect(entry[value.key], value.value,
            reason: '${expected.key} ${value.key}.');
      }
      final fallback = kBundledSfzFallbackCatalog.singleWhere(
        (candidate) => candidate['id'] == expected.key,
      );
      expect(fallback['name'], entry['name']);
      expect(fallback['pickerCategory'], entry['category']);
      expect(fallback['sourceProject'], entry['source_project']);
      expect(fallback['sourceLicense'], entry['source_license']);
      expect(fallback['outputGain'], entry['outputGain']);
      expect(fallback['attackMs'], entry['attackMs']);
      expect(fallback['releaseMs'], entry['releaseMs']);
      expect(
        fallback['sfzAssetPath'],
        p.posix.join(
          'assets',
          'instruments',
          entry['pack'] as String,
          entry['preset'] as String,
        ),
      );
    }

    final acousticPack = Directory(p.join(repoRoot.path, 'assets',
        'instruments', 'FreePats-Spanish-Classical-Guitar-2019-06-18'));
    final electricPack = Directory(p.join(repoRoot.path, 'assets',
        'instruments', 'Karoryfer-Black-And-Green-Guitars-1.000'));

    await _expectChromaticGuitarMapping(
      sfzFile: File(p.join(acousticPack.path, 'AcousticGuitar.sfz')),
      expectedRegionCount: 39,
      lowPitch: 40,
      highPitch: 84,
    );
    await _expectChromaticGuitarMapping(
      sfzFile: File(p.join(electricPack.path, 'ElectricGuitar.sfz')),
      expectedRegionCount: 78,
      lowPitch: 40,
      highPitch: 86,
    );

    final acousticAudio = _filesUnder(
      Directory(p.join(acousticPack.path, 'samples')),
    ).where((file) => p.extension(file.path).toLowerCase() == '.mp3').toList();
    final electricAudio = _filesUnder(
      Directory(p.join(electricPack.path, 'samples')),
    ).where((file) => p.extension(file.path).toLowerCase() == '.mp3').toList();
    expect(acousticAudio.length, 39);
    expect(electricAudio.length, 78);
    expect(
      _aggregateFileDigest(acousticAudio).toString(),
      '53462f729b184cee20ad1fd5ad62741668e99c38c4c1ca2027c29307bd8ec53a',
      reason: 'Acoustic MP3s must remain byte-identical to the approved bank.',
    );
    expect(
      _aggregateFileDigest(electricAudio).toString(),
      '8300f812c229c1c1237117286829b1ea9d256d35fcca5bcb1516f8c77ae82cf4',
      reason: 'Electric MP3s must remain byte-identical to the approved bank.',
    );

    const targetBytes = 4 * 1024 * 1024;
    const maximumBytes = 5 * 1024 * 1024;
    const combinedMaximumBytes = 10 * 1024 * 1024;
    final acousticBytes = _directorySize(acousticPack);
    final electricBytes = _directorySize(electricPack);
    expect(acousticBytes, lessThanOrEqualTo(targetBytes));
    expect(electricBytes, lessThanOrEqualTo(targetBytes));
    expect(acousticBytes, lessThanOrEqualTo(maximumBytes));
    expect(electricBytes, lessThanOrEqualTo(maximumBytes));
    expect(acousticBytes + electricBytes,
        lessThanOrEqualTo(combinedMaximumBytes));

    final expectedPresetByPack = <String, String>{
      acousticPack.path: 'AcousticGuitar.sfz',
      electricPack.path: 'ElectricGuitar.sfz',
    };
    for (final pack in <Directory>[acousticPack, electricPack]) {
      expect(File(p.join(pack.path, 'LICENSE')).existsSync(), isTrue);
      expect(File(p.join(pack.path, 'NOTICE.md')).existsSync(), isTrue);
      expect(
        pack
            .listSync(followLinks: false)
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toSet(),
        <String>{'LICENSE', 'NOTICE.md', expectedPresetByPack[pack.path]!},
        reason: 'Guitar pack contains non-production top-level files.',
      );
      expect(
        pack
            .listSync(followLinks: false)
            .whereType<Directory>()
            .map((directory) => p.basename(directory.path))
            .toSet(),
        <String>{'samples'},
      );
    }
  });

  test('android guitar asset packs are byte-identical to canonical assets',
      () async {
    final repoRoot = Directory.current;
    const packs = <String>[
      'FreePats-Spanish-Classical-Guitar-2019-06-18',
      'Karoryfer-Black-And-Green-Guitars-1.000',
    ];
    for (final pack in packs) {
      final source = Directory(
          p.join(repoRoot.path, 'assets', 'instruments', pack));
      final android = Directory(p.join(
        repoRoot.path,
        'android',
        'assetpacks',
        'instruments',
        'src',
        'main',
        'assets',
        'assets',
        'instruments',
        pack,
      ));
      expect(android.existsSync(), isTrue,
          reason: 'Missing Android guitar pack: $pack.');

      final sourceFiles = _filesUnder(source);
      final androidFiles = _filesUnder(android);
      expect(
        androidFiles.map((file) => p.relative(file.path, from: android.path)),
        sourceFiles.map((file) => p.relative(file.path, from: source.path)),
        reason: 'Android guitar pack file list differs for $pack.',
      );
      for (var index = 0; index < sourceFiles.length; index++) {
        expect(androidFiles[index].readAsBytesSync(),
            sourceFiles[index].readAsBytesSync(),
            reason: 'Android guitar asset differs: '
                '${p.relative(sourceFiles[index].path, from: source.path)}.');
      }
    }

    final sourceIndex =
        File(p.join(repoRoot.path, 'assets', 'instruments', 'index.json'));
    final androidIndex = File(p.join(
      repoRoot.path,
      'android',
      'assetpacks',
      'instruments',
      'src',
      'main',
      'assets',
      'assets',
      'instruments',
      'index.json',
    ));
    expect(androidIndex.readAsBytesSync(), sourceIndex.readAsBytesSync());
  });

  test(
    'guitars are registered for Flutter, licenses, and Android install-time delivery',
    () async {
      final repoRoot = Directory.current;
      final pubspec = await File(
        p.join(repoRoot.path, 'pubspec.yaml'),
      ).readAsString();
      final mainSource = await File(
        p.join(repoRoot.path, 'lib', 'main.dart'),
      ).readAsString();
      final androidApp = await File(
        p.join(repoRoot.path, 'android', 'app', 'build.gradle.kts'),
      ).readAsString();
      final androidPack = await File(
        p.join(
          repoRoot.path,
          'android',
          'assetpacks',
          'instruments',
          'build.gradle.kts',
        ),
      ).readAsString();

      for (final pack in <String>[
        'FreePats-Spanish-Classical-Guitar-2019-06-18',
        'Karoryfer-Black-And-Green-Guitars-1.000',
      ]) {
        expect(pubspec, contains('assets/instruments/$pack/'));
        expect(pubspec, contains('assets/instruments/$pack/samples/'));
        expect(mainSource, contains('assets/instruments/$pack/LICENSE'));
        expect(mainSource, contains('assets/instruments/$pack/NOTICE.md'));
      }
      expect(androidApp, contains(':assetpacks:instruments'));
      expect(
        androidApp,
        contains('delete(File(outDir, "assets/instruments"))'),
      );
      expect(
        androidApp,
        contains('delete(File(outDir, "flutter_assets/assets/instruments"))'),
      );
      expect(androidPack, contains('deliveryType.set("install-time")'));
      expect(androidPack, contains('from("../../../assets/instruments")'));
    },
  );

  test('statically referenced SFZ assets exist on disk', () async {
    final repoRoot = Directory.current;
    final sourceFiles = <String>[
      p.join(repoRoot.path, 'lib', 'screens', 'audio_editor.dart'),
      p.join(repoRoot.path, 'juce_audio_engine', 'android', 'src', 'main',
          'cpp', 'JuceEngine.h'),
      p.join(repoRoot.path, 'juce_audio_engine', 'android', 'src', 'main',
          'cpp', 'TimelineMidiClipProcessor.h'),
      p.join(
          repoRoot.path, 'juce_audio_engine', 'ios', 'Classes', 'JuceEngine.h'),
    ];

    final referenced = <String>{};
    for (final path in sourceFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'Missing source file: $path');
      final text = await file.readAsString();
      referenced.addAll(_extractStaticSfzPaths(text));
    }

    expect(referenced, isNotEmpty,
        reason: 'No static SFZ references were found.');

    for (final sfzPath in referenced) {
      final sfzFile = File(p.join(repoRoot.path, sfzPath));
      expect(
        sfzFile.existsSync(),
        isTrue,
        reason: 'Missing static SFZ reference: $sfzPath',
      );
    }
  });

  test('upright piano covers the chromatic 88-key piano range', () async {
    final repoRoot = Directory.current;
    final sfzFile = File(p.join(repoRoot.path, 'assets', 'instruments',
        'VSCO-2-CE-1.1.0', 'UprightPiano.sfz'));
    expect(sfzFile.existsSync(), isTrue,
        reason: 'Missing upright piano SFZ preset.');

    final regions = (await _parseSfzRegions(sfzFile))
        .where((region) => (region['sample'] ?? '').trim().isNotEmpty)
        .toList(growable: false);
    expect(regions, isNotEmpty,
        reason: 'Upright piano parsed with zero sample regions.');

    for (final region in regions) {
      final loKey = _sfzInt(region, 'lokey', 0);
      final hiKey = _sfzInt(region, 'hikey', 127);
      final keyCenter = _sfzInt(region, 'pitch_keycenter', -1);
      expect(loKey, greaterThanOrEqualTo(21),
          reason: 'Upright piano must not map below A0.');
      expect(hiKey, lessThanOrEqualTo(108),
          reason: 'Upright piano must not map above C8.');
      expect(keyCenter, inInclusiveRange(21, 108),
          reason: 'Upright piano sample key center must stay in piano range.');
      expect(loKey, lessThanOrEqualTo(hiKey),
          reason: 'Upright piano region has an inverted key range.');
    }

    const velocities = <int>[1, 64, 110];
    for (var pitch = 21; pitch <= 108; pitch++) {
      final exactPitchRegions = regions.where((region) {
        final loKey = _sfzInt(region, 'lokey', 0);
        final hiKey = _sfzInt(region, 'hikey', 127);
        final keyCenter = _sfzInt(region, 'pitch_keycenter', -1);
        return loKey == pitch && hiKey == pitch && keyCenter == pitch;
      }).toList(growable: false);
      expect(exactPitchRegions.length, 2,
          reason:
              'Upright piano must have two explicit sample regions for pitch $pitch.');

      for (final velocity in velocities) {
        final matches = regions.where((region) {
          final loKey = _sfzInt(region, 'lokey', 0);
          final hiKey = _sfzInt(region, 'hikey', 127);
          final loVel = _sfzInt(region, 'lovel', 0);
          final hiVel = _sfzInt(region, 'hivel', 127);
          return pitch >= loKey &&
              pitch <= hiKey &&
              velocity >= loVel &&
              velocity <= hiVel;
        });
        expect(matches, isNotEmpty,
            reason:
                'Upright piano missing pitch $pitch at velocity $velocity.');
      }
    }
  });

  test('android asset pack upright piano matches chromatic source preset',
      () async {
    final repoRoot = Directory.current;
    final sourceSfz = File(p.join(repoRoot.path, 'assets', 'instruments',
        'VSCO-2-CE-1.1.0', 'UprightPiano.sfz'));
    final androidSfz = File(p.join(
      repoRoot.path,
      'android',
      'assetpacks',
      'instruments',
      'src',
      'main',
      'assets',
      'assets',
      'instruments',
      'VSCO-2-CE-1.1.0',
      'UprightPiano.sfz',
    ));
    expect(sourceSfz.existsSync(), isTrue,
        reason: 'Missing source upright piano SFZ.');
    expect(androidSfz.existsSync(), isTrue,
        reason: 'Missing Android asset-pack upright piano SFZ.');
    expect(
      await androidSfz.readAsString(),
      await sourceSfz.readAsString(),
      reason:
          'Android upright piano SFZ must stay in sync with the chromatic source preset.',
    );

    final regions = (await _parseSfzRegions(androidSfz))
        .where((region) => (region['sample'] ?? '').trim().isNotEmpty)
        .toList(growable: false);
    expect(regions.length, 176,
        reason:
            'Android upright piano must include two velocity layers for 88 keys.');

    const androidSfzAssetPath =
        'android/assetpacks/instruments/src/main/assets/assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz';
    for (final region in regions) {
      final sampleAssetPath = _resolveSfzSampleAssetPath(
        sfzAssetPath: androidSfzAssetPath,
        defaultPathRaw: '',
        samplePathRaw: region['sample'] ?? '',
      );
      final sampleFile = File(p.join(repoRoot.path, sampleAssetPath));
      expect(
        sampleFile.existsSync(),
        isTrue,
        reason:
            'Android asset pack missing upright piano sample: $sampleAssetPath',
      );
    }
  });

  test('native sampled resolver does not hardcode guitar SFZ asset paths',
      () async {
    final repoRoot = Directory.current;
    final nativeFiles = <String>[
      p.join(repoRoot.path, 'juce_audio_engine', 'android', 'src', 'main',
          'cpp', 'JuceEngine.h'),
      p.join(repoRoot.path, 'juce_audio_engine', 'android', 'src', 'main',
          'cpp', 'TimelineMidiClipProcessor.h'),
      p.join(
          repoRoot.path, 'juce_audio_engine', 'ios', 'Classes', 'JuceEngine.h'),
    ];

    for (final path in nativeFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'Missing source file: $path');
      final text = await file.readAsString();
      final guitarPaths = _extractStaticSfzPaths(text).where(
        (sfzPath) =>
            sfzPath.contains('FreePats-Spanish-Classical-Guitar') ||
            sfzPath.contains('Karoryfer-Black-And-Green-Guitars'),
      );
      expect(guitarPaths, isEmpty,
          reason: 'Native sampled resolver should load guitars through '
              'generic sfz_asset paths, not hardcoded constants: $path');
    }
  });
}
