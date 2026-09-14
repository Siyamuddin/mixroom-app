import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_plugin_identity.dart';
import 'package:mixroom/ai/producer_data_collector.dart';

void main() {
  test('plugin identities match shared capture/backend golden fixtures', () {
    final fixtures = jsonDecode(File('test/fixtures/producer_plugin_identity.json').readAsStringSync()) as List;
    for (final row in fixtures) {
      expect(canonicalProducerPluginId(row['raw']), row['canonical']);
      expect(canonicalProducerPluginId(row['canonical']), row['canonical']);
    }
  });

  test('actual captured snapshot uses the canonical plugin identity', () async {
    final directory = await Directory.systemTemp.createTemp('producer-plugin-id');
    final state = <String, dynamic>{
      'bpm': 120, 'max_rows': 1, 'rows': [
        {'row': 0, 'row_id': 17, 'hasAudio': true, 'mix': {'gain_0to3': 1.0, 'pan_0to1': .5},
          'effects': [{'effectId': '/Library/Audio/Plug-Ins/VST3/Example.vst3', 'name': 'Example', 'instanceId': 'one', 'parameters': []}]}
      ],
    };
    final collector = ProducerDataCollector(snapshotProvider: () async => {'project_state': state}, ownerIdProvider: () => 'test-owner');
    try {
      await collector.setEnabled(true);
      await collector.beginSession(initialSnapshot: {'project_state': state}, projectId: 'plugin-test', projectDir: directory);
      await collector.recordManualEdit(kind: 'row_gain', payload: {'row': 0, 'old_gain': 1.0, 'new_gain': 1.2});
      final file = await collector.closeSession();
      final raw = await file!.readAsString();
      expect(raw, contains(canonicalProducerPluginId('/Library/Audio/Plug-Ins/VST3/Example.vst3')));
      expect(raw, isNot(contains('/Library/Audio/Plug-Ins/')));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
