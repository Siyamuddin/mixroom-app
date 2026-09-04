import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class SfzRegion {
  const SfzRegion({
    required this.sampleAssetPath,
    required this.loKey,
    required this.hiKey,
    required this.keyCenter,
    required this.loVel,
    required this.hiVel,
    required this.gainLinear,
    required this.attackSec,
    required this.releaseSec,
    required this.pitchKeytrack,
    required this.pitchOffsetSemitones,
    required this.sampleStartFrame,
    required this.sampleEndFrameExclusive,
    required this.oneShot,
    required this.seqLength,
    required this.seqPosition,
    required this.loRand,
    required this.hiRand,
  });

  final String sampleAssetPath;
  final int loKey;
  final int hiKey;
  final int keyCenter;
  final int loVel;
  final int hiVel;
  final double gainLinear;
  final double attackSec;
  final double releaseSec;
  final double pitchKeytrack;
  final double pitchOffsetSemitones;
  final int sampleStartFrame;
  final int sampleEndFrameExclusive;
  final bool oneShot;
  final int seqLength;
  final int seqPosition;
  final double loRand;
  final double hiRand;
}

class SfzDefinition {
  const SfzDefinition({
    required this.sfzAssetPath,
    required this.regions,
    required this.defaultAttackSec,
    required this.defaultReleaseSec,
  });

  final String sfzAssetPath;
  final List<SfzRegion> regions;
  final double defaultAttackSec;
  final double defaultReleaseSec;

  Set<int> playableInputPitches({
    required int Function(int pitch) remapPitch,
    int sampleLowKey = 0,
    int sampleHighKey = 127,
  }) {
    final low = sampleLowKey.clamp(0, 127);
    final high = sampleHighKey.clamp(low, 127);
    final playable = <int>{};
    for (var inputPitch = 0; inputPitch <= 127; inputPitch++) {
      final mappedPitch = remapPitch(inputPitch).clamp(0, 127);
      if (mappedPitch < low || mappedPitch > high) continue;
      if (regions.any(
        (region) => mappedPitch >= region.loKey && mappedPitch <= region.hiKey,
      )) {
        playable.add(inputPitch);
      }
    }
    return Set<int>.unmodifiable(playable);
  }
}

class _SfzParsedLine {
  const _SfzParsedLine({
    this.blockTag,
    this.opcodes = const <String, String>{},
  });

  final String? blockTag;
  final Map<String, String> opcodes;
}

class SfzDefinitionLoader {
  SfzDefinitionLoader({AssetBundle? assetBundle})
      : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  final Map<String, Future<SfzDefinition?>> _cache =
      <String, Future<SfzDefinition?>>{};

  Future<SfzDefinition?> load(String sfzAssetPath) {
    final normalizedPath = p.normalize(sfzAssetPath.trim());
    if (normalizedPath.isEmpty || normalizedPath == '.') {
      return Future<SfzDefinition?>.value();
    }
    return _cache.putIfAbsent(normalizedPath, () => _load(normalizedPath));
  }

  void clear() => _cache.clear();

  Future<SfzDefinition?> _load(String sfzAssetPath) async {
    try {
      final sfzLines = await _loadExpandedLines(sfzAssetPath);
      if (sfzLines.isEmpty) return null;
      final control = <String, String>{};
      final global = <String, String>{};
      final master = <String, String>{};
      final group = <String, String>{};
      Map<String, String>? region;
      String currentBlock = '';

      final regions = <Map<String, String>>[];
      for (final rawLine in sfzLines) {
        final parsed = _parseLine(rawLine);
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
          default:
            break;
        }
      }

      final defaultPathRaw = control['default_path'] ?? '';
      final globalAttackSec = _readNumeric(global, 'ampeg_attack', 0.005);
      final globalReleaseSec = _readNumeric(global, 'ampeg_release', 0.35);
      final globalVol = _readNumeric(global, 'volume', 0.0);
      final parsedRegions = <SfzRegion>[];

      for (final values in regions) {
        final sampleRaw = values['sample'] ?? '';
        if (sampleRaw.isEmpty) continue;
        final keyValue = values.containsKey('key')
            ? _readNumeric(values, 'key', 60.0)
            : null;
        final loKey = _readNumeric(
          values,
          'lokey',
          keyValue ?? 0,
        ).round().clamp(0, 127);
        final hiKey = _readNumeric(
          values,
          'hikey',
          keyValue ?? 127,
        ).round().clamp(loKey, 127);
        final keyCenter = _readNumeric(
          values,
          'pitch_keycenter',
          keyValue ?? ((loKey + hiKey) / 2.0).roundToDouble(),
        ).round().clamp(0, 127);
        final loVel = _readNumeric(values, 'lovel', 0).round().clamp(0, 127);
        final hiVel = _readNumeric(
          values,
          'hivel',
          127,
        ).round().clamp(loVel, 127);
        final regionVolDb = _readNumeric(values, 'volume', globalVol);
        final gainLinear =
            math.pow(10.0, regionVolDb.clamp(-24.0, 12.0) / 20.0).toDouble();
        final attackSec = _readNumeric(
          values,
          'ampeg_attack',
          globalAttackSec,
        ).clamp(0.0, 4.0).toDouble();
        final releaseSec = _readNumeric(
          values,
          'ampeg_release',
          globalReleaseSec,
        ).clamp(0.0, 12.0).toDouble();
        final pitchKeytrack = _readNumeric(
          values,
          'pitch_keytrack',
          100.0,
        ).clamp(-1200.0, 1200.0).toDouble();
        final pitchOffsetSemitones = (_readNumeric(values, 'transpose', 0.0) +
                (_readNumeric(values, 'tune', 0.0) / 100.0))
            .clamp(-48.0, 48.0)
            .toDouble();
        final sampleStartFrame = math.max(
          0,
          _readNumeric(values, 'offset', 0.0).round(),
        );
        final sampleEndFrameExclusive = math.max(
          0,
          _readNumeric(values, 'end', -1.0).round() + 1,
        );
        final loopMode = (values['loop_mode'] ?? '').trim().toLowerCase();
        final seqLength = math.max(
          1,
          _readNumeric(values, 'seq_length', 1.0).round(),
        );
        final seqPosition = _readNumeric(
          values,
          'seq_position',
          1.0,
        ).round().clamp(1, seqLength);
        final loRand = _readNumeric(
          values,
          'lorand',
          0.0,
        ).clamp(0.0, 1.0).toDouble();
        final hiRand = _readNumeric(
          values,
          'hirand',
          1.0,
        ).clamp(loRand, 1.0).toDouble();

        parsedRegions.add(
          SfzRegion(
            sampleAssetPath: _resolveSampleAssetPath(
              sfzAssetPath: sfzAssetPath,
              defaultPathRaw: values['default_path'] ?? defaultPathRaw,
              samplePathRaw: sampleRaw,
            ),
            loKey: loKey,
            hiKey: hiKey,
            keyCenter: keyCenter,
            loVel: loVel,
            hiVel: hiVel,
            gainLinear: gainLinear,
            attackSec: attackSec,
            releaseSec: releaseSec,
            pitchKeytrack: pitchKeytrack,
            pitchOffsetSemitones: pitchOffsetSemitones,
            sampleStartFrame: sampleStartFrame,
            sampleEndFrameExclusive: sampleEndFrameExclusive,
            oneShot: loopMode == 'one_shot',
            seqLength: seqLength,
            seqPosition: seqPosition,
            loRand: loRand,
            hiRand: hiRand,
          ),
        );
      }

      if (parsedRegions.isEmpty) return null;
      return SfzDefinition(
        sfzAssetPath: sfzAssetPath,
        regions: List<SfzRegion>.unmodifiable(parsedRegions),
        defaultAttackSec: globalAttackSec.clamp(0.0, 4.0),
        defaultReleaseSec: globalReleaseSec.clamp(0.0, 12.0),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _parseOpcodes(String line) {
    final out = <String, String>{};
    final trimmed = line.split('//').first.trim();
    if (trimmed.isEmpty) return out;
    final matches = RegExp(
      r'([A-Za-z_][A-Za-z0-9_]*)=',
    ).allMatches(trimmed).toList();
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final key = (match.group(1) ?? '').trim().toLowerCase();
      final valueEnd =
          i + 1 < matches.length ? matches[i + 1].start : trimmed.length;
      final value = trimmed.substring(match.end, valueEnd).trim();
      if (key.isNotEmpty && value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  _SfzParsedLine _parseLine(String rawLine) {
    final line = rawLine.split('//').first.trim();
    if (line.isEmpty) return const _SfzParsedLine();
    String? blockTag;
    var remainder = line;
    final tagMatch = RegExp(r'^<\s*([A-Za-z0-9_]+)\s*>').firstMatch(line);
    if (tagMatch != null) {
      blockTag = (tagMatch.group(1) ?? '').trim().toLowerCase();
      remainder = line.substring(tagMatch.end).trim();
    }
    return _SfzParsedLine(
      blockTag: blockTag,
      opcodes: remainder.isEmpty
          ? const <String, String>{}
          : _parseOpcodes(remainder),
    );
  }

  Future<List<String>> _loadExpandedLines(
    String sfzAssetPath, {
    Set<String>? includeStack,
    Map<String, String>? defines,
  }) async {
    final normalizedPath = p.normalize(sfzAssetPath);
    final stack = includeStack ?? <String>{};
    if (!stack.add(normalizedPath)) return const <String>[];
    try {
      final file = File(normalizedPath);
      final isFile = file.existsSync();
      final text = isFile
          ? await file.readAsString()
          : await _assetBundle.loadString(p.posix.normalize(normalizedPath));
      final dir =
          isFile ? p.dirname(normalizedPath) : p.posix.dirname(normalizedPath);
      final macroMap = defines ?? <String, String>{};
      final out = <String>[];
      for (final rawLine in const LineSplitter().convert(text)) {
        final line = rawLine.split('//').first.trim();
        if (line.isEmpty) continue;
        final includeMatch = RegExp(
          r'''^#include\s+["']([^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(line);
        if (includeMatch != null) {
          final includeRaw = _stripQuotes(includeMatch.group(1) ?? '');
          if (includeRaw.isNotEmpty) {
            final includePath = isFile
                ? p.normalize(p.join(dir, includeRaw.replaceAll('\\', '/')))
                : p.posix.normalize(
                    p.posix.join(dir, includeRaw.replaceAll('\\', '/')),
                  );
            out.addAll(
              await _loadExpandedLines(
                includePath,
                includeStack: stack,
                defines: macroMap,
              ),
            );
          }
          continue;
        }
        final defineMatch = RegExp(
          r'^#define\s+\$?([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$',
        ).firstMatch(line);
        if (defineMatch != null) {
          final key = (defineMatch.group(1) ?? '').trim();
          final value = (defineMatch.group(2) ?? '').trim();
          if (key.isNotEmpty && value.isNotEmpty) macroMap[key] = value;
          continue;
        }
        var expandedLine = rawLine;
        for (final entry in macroMap.entries) {
          expandedLine = expandedLine.replaceAll('\$${entry.key}', entry.value);
        }
        out.add(expandedLine);
      }
      return out;
    } catch (_) {
      return const <String>[];
    } finally {
      stack.remove(normalizedPath);
    }
  }

  String _resolveSampleAssetPath({
    required String sfzAssetPath,
    required String defaultPathRaw,
    required String samplePathRaw,
  }) {
    final sfzDir = p.posix.dirname(sfzAssetPath);
    final defaultPath = _stripQuotes(defaultPathRaw).replaceAll('\\', '/');
    final samplePath = _stripQuotes(samplePathRaw).replaceAll('\\', '/');
    if (samplePath.startsWith('assets/')) {
      return p.posix.normalize(samplePath);
    }
    return p.posix.normalize(p.posix.join(sfzDir, defaultPath, samplePath));
  }

  String _stripQuotes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  double? _parseNumberOrNote(String raw) {
    final token = _stripQuotes(raw);
    final numeric = double.tryParse(token);
    if (numeric != null) return numeric;
    final match = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)$').firstMatch(token);
    if (match == null) return null;
    const semitones = <String, int>{
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    var semitone = semitones[(match.group(1) ?? '').toUpperCase()];
    final octave = int.tryParse(match.group(3) ?? '');
    if (semitone == null || octave == null) return null;
    if (match.group(2) == '#') semitone += 1;
    if (match.group(2) == 'b') semitone -= 1;
    return (((octave + 1) * 12) + semitone).toDouble();
  }

  double _readNumeric(Map<String, String> values, String key, double fallback) {
    final raw = values[key];
    return raw == null ? fallback : _parseNumberOrNote(raw) ?? fallback;
  }
}
