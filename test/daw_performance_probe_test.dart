import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/daw_performance_probe.dart';

void main() {
  testWidgets('emits structured operation phases only when enabled', (
    tester,
  ) async {
    final messages = <String>[];
    var enabled = true;
    final probe = DawPerformanceProbe(
      isEnabled: () => enabled,
      context: () => const DawPerformanceContext(
        projectId: 'pro17-stress-17-40-400',
        projectName: 'PRO-17 stress',
        rowCount: 40,
        clipCount: 400,
      ),
      logger: messages.add,
      instrumentationBuildEnabled: true,
    );

    final span = probe.beginOperation('delete_clip');
    span.checkpoint('native_graph_done');
    span.finish(fields: const <String, Object?>{'deleted': 1});
    tester.binding.scheduleFrame();
    await tester.pump();

    final payloads = messages
        .map((message) => message.substring('[PRO17_PERF] '.length))
        .map((message) => jsonDecode(message) as Map<String, dynamic>)
        .toList();
    expect(payloads.first['event'], 'operation_start');
    expect(payloads[1]['event'], 'operation_phase');
    expect(payloads[1]['phase'], 'native_graph_done');
    expect(payloads[2]['event'], 'operation_end');
    expect(payloads[2]['deleted'], 1);
    expect(payloads.last['event'], 'operation_visible_frame');

    enabled = false;
    probe.beginOperation('add_row').finish();
    expect(messages, hasLength(payloads.length));
  });

  test('mirrors ordered JSONL metrics into the project log', () async {
    final sandbox = await Directory.systemTemp.createTemp('pro17_probe_');
    addTearDown(() => sandbox.delete(recursive: true));
    final logFile = File('${sandbox.path}/pro17_performance.jsonl');
    final probe = DawPerformanceProbe(
      isEnabled: () => true,
      context: () => const DawPerformanceContext(
        projectId: 'pro17-stress-17-99-400',
        projectName: 'PRO-17 long clips',
        rowCount: 99,
        clipCount: 400,
      ),
      logger: (_) {},
      logFile: logFile,
      instrumentationBuildEnabled: true,
    );

    probe.emit('project_ready');
    probe.emit('manual_test_marker', const <String, Object?>{'step': 1});
    await probe.flushLogs();

    final lines = await logFile.readAsLines();
    final payloads = lines
        .map((line) => line.substring('[PRO17_PERF] '.length))
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(payloads.map((payload) => payload['event']), <Object?>[
      'project_ready',
      'manual_test_marker',
    ]);
    expect(
      payloads.map((payload) => payload['session_id']).toSet(),
      hasLength(1),
    );
    expect(payloads.last['monotonic_ms'], isA<num>());
  });
}
