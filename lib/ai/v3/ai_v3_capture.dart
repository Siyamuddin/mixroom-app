import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef AiV3CaptureRunner = Future<Map<String, dynamic>> Function();
typedef AiV3CaptureErrorDiagnostic = Map<String, dynamic> Function(
  Object error,
);

class AiV3CaptureRun {
  const AiV3CaptureRun({
    required this.architecture,
    required this.model,
    required this.reasoningEffort,
    required this.run,
    this.errorDiagnostic,
  });

  final String architecture;
  final String model;
  final String reasoningEffort;
  final AiV3CaptureRunner run;
  final AiV3CaptureErrorDiagnostic? errorDiagnostic;
}

class AiV3Capture {
  const AiV3Capture({
    required this.enabled,
    required this.directoryPath,
  });

  final bool enabled;
  final String directoryPath;
  bool get isEnabled => enabled;

  Future<void> captureExecution({
    required String planId,
    required Map<String, dynamic> handoff,
    required Map<String, dynamic> executionResult,
  }) async {
    if (!enabled) return;
    final capturedAt = DateTime.now().toUtc();
    await _write(
      captureId: planId,
      capturedAt: capturedAt,
      run: AiV3CaptureRun(
        architecture: 'v3_execution',
        model: 'flutter',
        reasoningEffort: 'none',
        run: () async => const <String, dynamic>{},
      ),
      request: handoff,
      result: executionResult,
    );
  }

  Future<void> capture({
    required String captureId,
    required Map<String, dynamic> request,
    required AiV3CaptureRun active,
    required Map<String, dynamic> activeResult,
    required List<AiV3CaptureRun> comparisons,
  }) async {
    if (!enabled) return;
    final capturedAt = DateTime.now().toUtc();
    await _write(
      captureId: captureId,
      capturedAt: capturedAt,
      run: active,
      request: request,
      result: <String, dynamic>{
        'status': 'completed',
        'user_visible': true,
        'output': activeResult,
      },
    );
    await Future.wait(comparisons.map((run) async {
      final stopwatch = Stopwatch()..start();
      Map<String, dynamic> result;
      try {
        result = <String, dynamic>{
          'status': 'completed',
          'user_visible': false,
          'output': await run.run(),
        };
      } catch (error) {
        final diagnostic =
            run.errorDiagnostic?.call(error) ?? const <String, dynamic>{};
        result = <String, dynamic>{
          'status': 'failed',
          'user_visible': false,
          'error_type': error.runtimeType.toString(),
          'error': _sanitizeError(error.toString()),
          if (diagnostic.isNotEmpty) 'diagnostic': diagnostic,
        };
      } finally {
        stopwatch.stop();
      }
      result['elapsed_ms'] = stopwatch.elapsedMilliseconds;
      await _write(
        captureId: captureId,
        capturedAt: capturedAt,
        run: run,
        request: request,
        result: result,
      );
    }));
  }

  Future<void> captureFailure({
    required String captureId,
    required Map<String, dynamic> request,
    required AiV3CaptureRun active,
    required Object error,
    Map<String, dynamic> diagnostic = const <String, dynamic>{},
    required List<AiV3CaptureRun> comparisons,
  }) async {
    if (!enabled) return;
    final capturedAt = DateTime.now().toUtc();
    await _write(
      captureId: captureId,
      capturedAt: capturedAt,
      run: active,
      request: request,
      result: <String, dynamic>{
        'status': 'failed',
        'user_visible': true,
        'error_type': error.runtimeType.toString(),
        'error': _sanitizeError(error.toString()),
        if (diagnostic.isNotEmpty) 'diagnostic': diagnostic,
      },
    );
    await Future.wait(comparisons.map((run) async {
      final stopwatch = Stopwatch()..start();
      Map<String, dynamic> result;
      try {
        result = <String, dynamic>{
          'status': 'completed',
          'user_visible': false,
          'output': await run.run(),
        };
      } catch (comparisonError) {
        final diagnostic = run.errorDiagnostic?.call(comparisonError) ??
            const <String, dynamic>{};
        result = <String, dynamic>{
          'status': 'failed',
          'user_visible': false,
          'error_type': comparisonError.runtimeType.toString(),
          'error': _sanitizeError(comparisonError.toString()),
          if (diagnostic.isNotEmpty) 'diagnostic': diagnostic,
        };
      } finally {
        stopwatch.stop();
      }
      result['elapsed_ms'] = stopwatch.elapsedMilliseconds;
      await _write(
        captureId: captureId,
        capturedAt: capturedAt,
        run: run,
        request: request,
        result: result,
      );
    }));
  }

  Future<void> _write({
    required String captureId,
    required DateTime capturedAt,
    required AiV3CaptureRun run,
    required Map<String, dynamic> request,
    required Map<String, dynamic> result,
  }) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) await directory.create(recursive: true);
      final timestamp = capturedAt
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final pathToken = <String>[
        run.architecture,
        run.model,
        run.reasoningEffort,
      ].map(_safeToken).where((value) => value.isNotEmpty).join('_');
      final safeId = _safeToken(captureId);
      final file = File(p.join(
        directory.path,
        '${timestamp}_${safeId.isEmpty ? 'capture' : safeId}_$pathToken.json',
      ));
      await file.writeAsString(
        const JsonEncoder.withIndent(' ').convert(_sanitize(<String, dynamic>{
          'schema_version': 'ai_v3_workflow_capture_v1',
          'captured_at': capturedAt.toIso8601String(),
          'capture_id': captureId,
          'architecture': run.architecture,
          'model': run.model,
          'reasoning_effort': run.reasoningEffort,
          'request': request,
          'result': result,
        })),
        flush: true,
      );
    } catch (_) {
      // Capture is observation-only and must never affect the active result.
    }
  }
}

String _safeToken(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

Object? _sanitize(Object? value, {String key = ''}) {
  const redacted = <String>{
    'api_key',
    'authorization',
    'access_token',
    'refresh_token',
    'token',
    'secret',
  };
  const pathFields = <String>{
    'file',
    'path',
    'source_file',
    'source_file_path',
    'original_source_file_path',
    'directory_path',
  };
  const diagnosticTextFields = <String>{
    'error',
    'error_message',
    'stack',
    'stack_trace',
    'stacktrace',
  };
  final normalizedKey = key.toLowerCase();
  if (redacted.contains(normalizedKey)) return '[redacted]';
  if (diagnosticTextFields.contains(normalizedKey) && value is String) {
    return _sanitizeError(value);
  }
  if (pathFields.contains(normalizedKey) && value is String) {
    final withoutScheme = value.startsWith('file://')
        ? Uri.tryParse(value)?.toFilePath() ?? value
        : value;
    final filename = p.basename(withoutScheme.trim());
    return filename.isEmpty ? '[local-path]' : filename;
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _sanitize(
          entry.value,
          key: entry.key.toString(),
        ),
    };
  }
  if (value is Iterable) return value.map(_sanitize).toList(growable: false);
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  return value.toString();
}

String _sanitizeError(String value) => value
        .replaceAll(
            RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer [redacted]')
        .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+\b'), '[redacted]')
        .replaceAllMapped(
      RegExp(r'(?:file://)?/(?:Users|private|var|tmp)/[^\s"\x27<>\\)]+'),
      (match) {
        final raw = match.group(0) ?? '';
        final withoutScheme = raw.startsWith('file://')
            ? Uri.tryParse(raw)?.toFilePath() ?? raw
            : raw;
        final filename = p.basename(withoutScheme);
        return filename.isEmpty ? '[local-path]' : '[local-path]/$filename';
      },
    );
