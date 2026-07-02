import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    final pack = (decoded['pack'] as String?)?.trim() ?? '';
    final presets = (decoded['presets'] as List?) ?? const <dynamic>[];
    expect(presets, isNotEmpty, reason: 'Bundled instrument index is empty.');

    for (final rawEntry in presets) {
      final entry = (rawEntry as Map).cast<String, dynamic>();
      final presetFile = (entry['preset'] as String?)?.trim() ?? '';
      expect(presetFile, isNotEmpty,
          reason: 'Indexed preset is missing its SFZ filename.');

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

  test('native sampled resolver does not hardcode bundled SFZ asset paths',
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
      expect(
        _extractStaticSfzPaths(text),
        isEmpty,
        reason: 'Native sampled resolver should use sfz_asset paths, not '
            'hardcoded bundled SFZ asset constants: $path',
      );
    }
  });
}
