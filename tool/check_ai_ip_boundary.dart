import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const String _manifestPath = 'tool/ai_ip_boundary_manifest.json';
const int _chunkSize = 1024 * 1024;

Future<void> main(List<String> arguments) async {
  final artifactPaths = <String>[];
  var scanStatic = arguments.isEmpty;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--static':
        scanStatic = true;
      case '--artifact':
        if (index + 1 >= arguments.length) {
          stderr.writeln('--artifact requires a file or directory path.');
          exitCode = 64;
          return;
        }
        artifactPaths.add(arguments[++index]);
      default:
        stderr.writeln('Unknown argument: ${arguments[index]}');
        exitCode = 64;
        return;
    }
  }

  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Missing reviewed marker manifest: $_manifestPath');
    exitCode = 66;
    return;
  }
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  final staticMarkers = _markers(manifest['static_v3_markers']);
  final artifactMarkers = <_Marker>[
    ..._markers(manifest['v3_artifact_markers'], category: 'v3'),
    ..._markers(manifest['cross_ai_artifact_markers'], category: 'other-ai'),
  ];
  final findings = <_Finding>[];

  if (scanStatic) {
    final root = Directory('lib');
    if (!root.existsSync()) {
      stderr.writeln('Run this command from the repository root.');
      exitCode = 66;
      return;
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        await _scanFile(entity, staticMarkers, findings);
      }
    }
  }

  for (final path in artifactPaths) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      findings.add(_Finding(path, 'gate', 'artifact does not exist'));
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      await for (final entity in Directory(
        path,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          await _scanArtifactFile(entity, artifactMarkers, findings);
        }
      }
    } else {
      await _scanArtifactFile(File(path), artifactMarkers, findings);
    }
  }

  if (findings.isNotEmpty) {
    stderr.writeln(
      'AI IP boundary scan failed (${findings.length} finding(s)):',
    );
    for (final finding in findings) {
      stderr.writeln(
        '- [${finding.category}] ${finding.marker} in ${finding.location}',
      );
    }
    exitCode = 1;
    return;
  }
  final scopes = <String>[
    if (scanStatic) 'shipped Flutter source',
    if (artifactPaths.isNotEmpty) '${artifactPaths.length} artifact target(s)',
  ];
  stdout.writeln('AI IP boundary scan passed: ${scopes.join(' and ')}.');
}

List<_Marker> _markers(Object? raw, {String category = 'v3-static'}) {
  if (raw is! List) return const <_Marker>[];
  return raw
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .map((value) => _Marker(value, category))
      .toList(growable: false);
}

Future<void> _scanArtifactFile(
  File file,
  List<_Marker> markers,
  List<_Finding> findings,
) async {
  final lower = file.path.toLowerCase();
  if (lower.endsWith('.apk') ||
      lower.endsWith('.aab') ||
      lower.endsWith('.zip') ||
      lower.endsWith('.ipa')) {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      for (final entry in archive.files.where((entry) => entry.isFile)) {
        final bytes = entry.readBytes();
        if (bytes != null) {
          _scanBytes(bytes, '${file.path}!/${entry.name}', markers, findings);
        }
      }
      return;
    } on Object catch (error) {
      findings.add(
        _Finding(file.path, 'gate', 'archive could not be inspected: $error'),
      );
      return;
    }
  }
  await _scanFile(file, markers, findings);
}

Future<void> _scanFile(
  File file,
  List<_Marker> markers,
  List<_Finding> findings,
) async {
  final maxPattern = markers.fold<int>(
    0,
    (current, marker) =>
        marker.utf8Bytes.length > current ? marker.utf8Bytes.length : current,
  );
  final handle = await file.open();
  var carry = Uint8List(0);
  try {
    while (true) {
      final chunk = await handle.read(_chunkSize);
      if (chunk.isEmpty) break;
      final combined = Uint8List(carry.length + chunk.length)
        ..setRange(0, carry.length, carry)
        ..setRange(carry.length, carry.length + chunk.length, chunk);
      _scanBytes(combined, file.path, markers, findings);
      final carryLength = maxPattern <= 1
          ? 0
          : (combined.length < maxPattern - 1
                ? combined.length
                : maxPattern - 1);
      carry = Uint8List.sublistView(combined, combined.length - carryLength);
    }
  } finally {
    await handle.close();
  }
}

void _scanBytes(
  Uint8List bytes,
  String location,
  List<_Marker> markers,
  List<_Finding> findings,
) {
  for (final marker in markers) {
    if (_contains(bytes, marker.utf8Bytes) ||
        _contains(bytes, marker.utf16LeBytes)) {
      final duplicate = findings.any(
        (finding) =>
            finding.location == location && finding.marker == marker.value,
      );
      if (!duplicate) {
        findings.add(_Finding(location, marker.category, marker.value));
      }
    }
  }
}

bool _contains(Uint8List bytes, Uint8List pattern) {
  if (pattern.isEmpty || bytes.length < pattern.length) return false;
  var offset = 0;
  while (offset <= bytes.length - pattern.length) {
    final candidate = bytes.indexOf(pattern.first, offset);
    if (candidate < 0 || candidate > bytes.length - pattern.length) {
      return false;
    }
    var matches = true;
    for (var index = 1; index < pattern.length; index += 1) {
      if (bytes[candidate + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
    offset = candidate + 1;
  }
  return false;
}

class _Marker {
  _Marker(this.value, this.category)
    : utf8Bytes = Uint8List.fromList(utf8.encode(value)),
      utf16LeBytes = Uint8List.fromList(<int>[
        for (final unit in value.codeUnits) ...<int>[unit & 0xff, unit >> 8],
      ]);

  final String value;
  final String category;
  final Uint8List utf8Bytes;
  final Uint8List utf16LeBytes;
}

class _Finding {
  const _Finding(this.location, this.category, this.marker);

  final String location;
  final String category;
  final String marker;
}
