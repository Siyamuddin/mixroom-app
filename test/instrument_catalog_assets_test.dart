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
      p.join(repoRoot.path, 'juce_audio_engine', 'ios', 'Classes',
          'JuceEngine.h'),
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
}
