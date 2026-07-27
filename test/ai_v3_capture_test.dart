import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_capture.dart';

void main() {
  test('captures active and detached runs without leaking secrets', () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_capture_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(
      enabled: true,
      directoryPath: directory.path,
    );

    await capture.capture(
      captureId: 'case-1',
      request: const <String, dynamic>{
        'original_request': 'Rename the row.',
        'authorization': 'Bearer should-not-appear',
        'file': '/Users/example/Music/private-vocal.wav',
        'source_file_path': '/private/tmp/session/reference.wav',
      },
      active: AiV3CaptureRun(
        architecture: 'v3',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        run: () async => const <String, dynamic>{},
      ),
      activeResult: const <String, dynamic>{'outcome': 'plan'},
      comparisons: <AiV3CaptureRun>[
        AiV3CaptureRun(
          architecture: 'v1',
          model: 'gpt-5.6-luna',
          reasoningEffort: 'low',
          run: () async => const <String, dynamic>{'outcome': 'comparison'},
        ),
      ],
    );

    final files = directory.listSync().whereType<File>().toList();
    expect(files, hasLength(2));
    final documents = files
        .map((file) => jsonDecode(file.readAsStringSync()) as Map)
        .toList(growable: false);
    expect(
      documents.map((document) => document['architecture']).toSet(),
      <String>{'v3', 'v1'},
    );
    final serialized = files.map((file) => file.readAsStringSync()).join();
    expect(serialized, isNot(contains('should-not-appear')));
    expect(serialized, isNot(contains('/Users/')));
    expect(serialized, isNot(contains('/private/')));
    expect(serialized, contains('private-vocal.wav'));
    expect(serialized, contains('reference.wav'));
  });

  test('disabled capture performs no writes', () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_disabled_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(
      enabled: false,
      directoryPath: directory.path,
    );

    await capture.captureExecution(
      planId: 'plan',
      handoff: const <String, dynamic>{},
      executionResult: const <String, dynamic>{},
    );

    expect(directory.listSync(), isEmpty);
  });

  test('detached compact failure cannot replace the active result', () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_shadow_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(enabled: true, directoryPath: directory.path);

    await capture.capture(
      captureId: 'shadow-failure',
      request: const <String, dynamic>{'original_request': 'Mute the row.'},
      active: AiV3CaptureRun(
        architecture: 'v3',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        run: () async => const <String, dynamic>{},
      ),
      activeResult: const <String, dynamic>{'outcome': 'plan'},
      comparisons: <AiV3CaptureRun>[
        AiV3CaptureRun(
          architecture: 'v3_compact_common_shadow',
          model: 'gpt-5.4-mini',
          reasoningEffort: 'low',
          run: () async => throw StateError('shadow failed'),
        ),
      ],
    );

    final documents = directory
        .listSync()
        .whereType<File>()
        .map((file) => jsonDecode(file.readAsStringSync()) as Map)
        .toList(growable: false);
    final active = documents.singleWhere(
      (document) => document['architecture'] == 'v3',
    );
    final shadow = documents.singleWhere(
      (document) => document['architecture'] == 'v3_compact_common_shadow',
    );
    expect((active['result'] as Map)['status'], 'completed');
    expect(((active['result'] as Map)['output'] as Map)['outcome'], 'plan');
    expect((shadow['result'] as Map)['status'], 'failed');
  });

  test('detached failure retains explicitly supplied safe diagnostics',
      () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_diag_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(enabled: true, directoryPath: directory.path);

    await capture.capture(
      captureId: 'diagnostic-failure',
      request: const <String, dynamic>{'original_request': 'Transpose Keys.'},
      active: AiV3CaptureRun(
        architecture: 'v3',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        run: () async => const <String, dynamic>{},
      ),
      activeResult: const <String, dynamic>{'outcome': 'clarify'},
      comparisons: <AiV3CaptureRun>[
        AiV3CaptureRun(
          architecture: 'v3_adaptive_shadow',
          model: 'gpt-5.4-mini',
          reasoningEffort: 'low',
          errorDiagnostic: (_) => const <String, dynamic>{
            'retrieval_request': <String, dynamic>{
              'schema_version': 'context_request_v3_1',
            },
          },
          run: () async => throw StateError('retrieval failed'),
        ),
      ],
    );

    final document = directory
        .listSync()
        .whereType<File>()
        .map((file) => jsonDecode(file.readAsStringSync()) as Map)
        .singleWhere(
          (value) => value['architecture'] == 'v3_adaptive_shadow',
        );
    final result = document['result'] as Map;
    expect(result['status'], 'failed');
    expect(
      ((result['diagnostic'] as Map)['retrieval_request']
          as Map)['schema_version'],
      'context_request_v3_1',
    );
  });

  test('captures planner failure and still runs detached comparison', () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_failure_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(
      enabled: true,
      directoryPath: directory.path,
    );

    await capture.captureFailure(
      captureId: 'case-failure',
      request: const <String, dynamic>{'original_request': 'Mute the row.'},
      active: AiV3CaptureRun(
        architecture: 'v3',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        run: () async => const <String, dynamic>{},
      ),
      error: Exception('schema rejected'),
      diagnostic: const <String, dynamic>{
        'tool_arguments': <String, dynamic>{'outcome': 'respond'},
      },
      comparisons: <AiV3CaptureRun>[
        AiV3CaptureRun(
          architecture: 'v1',
          model: 'gpt-5.4-mini',
          reasoningEffort: 'low',
          run: () async => const <String, dynamic>{'outcome': 'plan'},
        ),
      ],
    );

    final documents = directory
        .listSync()
        .whereType<File>()
        .map((file) => jsonDecode(file.readAsStringSync()) as Map)
        .toList(growable: false);
    expect(documents, hasLength(2));
    final active = documents.singleWhere(
      (document) => document['architecture'] == 'v3',
    );
    final comparison = documents.singleWhere(
      (document) => document['architecture'] == 'v1',
    );
    expect((active['result'] as Map)['status'], 'failed');
    expect(
      ((active['result'] as Map)['diagnostic'] as Map)['tool_arguments'],
      isNotNull,
    );
    expect((comparison['result'] as Map)['status'], 'completed');
  });

  test('sanitizes local paths from captured errors and diagnostics', () async {
    final directory = await Directory.systemTemp.createTemp('ai_v3_paths_');
    addTearDown(() => directory.delete(recursive: true));
    final capture = AiV3Capture(enabled: true, directoryPath: directory.path);

    await capture.captureFailure(
      captureId: 'path-failure',
      request: const <String, dynamic>{'original_request': 'Inspect the clip.'},
      active: AiV3CaptureRun(
        architecture: 'v3',
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        run: () async => const <String, dynamic>{},
      ),
      error: Exception(
        'failed at file:///Users/example/project/test.dart:42:7',
      ),
      diagnostic: const <String, dynamic>{
        'path': '/Users/example/Music/take.wav',
        'stack_trace':
            '#0 handler (file:///Users/example/project/handler.dart:9:3)',
      },
      comparisons: const <AiV3CaptureRun>[],
    );

    final serialized =
        directory.listSync().whereType<File>().single.readAsStringSync();
    expect(serialized, isNot(contains('/Users/')));
    expect(serialized, contains('take.wav'));
    expect(serialized, contains('handler.dart'));
    expect(serialized, contains('[local-path]'));
  });
}
