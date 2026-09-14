import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_plugin_identity.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/models/project_state.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const descriptor =
      'plugin_descriptor_v1:["VST3","Example Vendor","Example","1234abcd","1.0"]';
  test(
    'qualified identity excludes path and separates vendors, UIDs and versions',
    () {
      final id = producerModelPluginId(descriptor);
      expect(id, matches(RegExp(r'^plugin_uid_v1_[a-f0-9]{64}$')));
      for (final changed in [
        descriptor.replaceAll('1234abcd', '1234abce'),
        descriptor.replaceAll('Example Vendor', 'Another Vendor'),
        descriptor.replaceAll('1.0', '2.0'),
        descriptor.replaceAll('VST3', 'AudioUnit'),
      ]) {
        expect(producerModelPluginId(changed), isNot(id));
      }
      expect(producerModelPluginId('/Library/Example.vst3'), '');
      expect(producerModelPluginId('plugin_descriptor_v1:[1,2,3,4,5]'), '');
      expect(producerModelPluginId(descriptor.replaceAll('1234abcd', '0')), '');
      final effect = EffectState(
        effectIndex: 0,
        effectId: '/first/Example.vst3',
        modelPluginId: id,
        name: 'Example',
        isBypassed: false,
        parameters: [],
      );
      expect(EffectState.fromMap(effect.toJson()).modelPluginId, id);
      expect(effect.effectId, '/first/Example.vst3');
    },
  );

  test('native bridge requests model identity only when opted in', () async {
    const channel = MethodChannel('juce_audio_engine');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.arguments?['modelIdentity'] == true
              ? [descriptor]
              : ['/first/Example.vst3'];
        });
    try {
      expect(await JuceAudioEngine.getTrackEffectIdsForRow(2), [
        '/first/Example.vst3',
      ]);
      final model = await JuceAudioEngine.getTrackEffectIdsForRow(
        2,
        forceIndividualRow: true,
        modelIdentity: true,
      );
      expect(
        producerModelPluginId(model.single),
        producerModelPluginId(descriptor),
      );
      await JuceAudioEngine.getMasterEffectIds(modelIdentity: true);
      expect(calls[1].arguments, {
        'row': 2,
        'forceIndividualRow': true,
        'modelIdentity': true,
      });
      expect(calls[2].arguments, {'modelIdentity': true});
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test('plugin identities match shared capture/backend golden fixtures', () {
    final fixtures =
        jsonDecode(
              File(
                'test/fixtures/producer_plugin_identity.json',
              ).readAsStringSync(),
            )
            as List;
    for (final row in fixtures) {
      expect(canonicalProducerPluginId(row['raw']), row['canonical']);
      expect(canonicalProducerPluginId(row['canonical']), row['canonical']);
    }
  });

  test('actual captured snapshot uses the canonical plugin identity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'producer-plugin-id',
    );
    final state = <String, dynamic>{
      'bpm': 120,
      'max_rows': 1,
      'rows': [
        {
          'row': 0,
          'row_id': 17,
          'hasAudio': true,
          'mix': {'gain_0to3': 1.0, 'pan_0to1': .5},
          'effects': [
            {
              'modelPluginId': producerModelPluginId(descriptor),
              'effectId': '/Library/Audio/Plug-Ins/VST3/Example.vst3',
              'name': 'Example',
              'instanceId': 'one',
              'parameters': [],
            },
          ],
        },
      ],
    };
    final collector = ProducerDataCollector(
      snapshotProvider: () async => {'project_state': state},
      ownerIdProvider: () => 'test-owner',
    );
    try {
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: {'project_state': state},
        projectId: 'plugin-test',
        projectDir: directory,
      );
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: {'row': 0, 'old_gain': 1.0, 'new_gain': 1.2},
      );
      final file = await collector.closeSession();
      final raw = await file!.readAsString();
      expect(
        raw,
        contains(
          canonicalProducerPluginId(
            '/Library/Audio/Plug-Ins/VST3/Example.vst3',
          ),
        ),
      );
      expect(raw, contains(producerModelPluginId(descriptor)));
      expect(raw, isNot(contains('/Library/Audio/Plug-Ins/')));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
