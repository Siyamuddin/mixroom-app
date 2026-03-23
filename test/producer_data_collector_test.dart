import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports producer sessions into the project folder when available',
      () async {
    final projectDir =
        await Directory.systemTemp.createTemp('mixroom_producer_project_');
    addTearDown(() async {
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
    });

    final collector = ProducerDataCollector();
    await collector.setEnabled(true);

    await collector.recordManualEdit(
      kind: 'test_edit',
      payload: const {'value': 1},
      projectId: 'project_123',
      projectName: 'Producer Test Project',
      projectDir: projectDir,
    );

    final exported =
        await collector.exportActiveSession(projectDir: projectDir);
    expect(exported, isNotNull);
    expect(await exported!.exists(), isTrue);
    expect(
      p.normalize(exported.path),
      startsWith(
        p.normalize(p.join(projectDir.path, 'exports', 'producer_sessions')),
      ),
    );
  });
}
