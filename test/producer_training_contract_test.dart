import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/models/project_state.dart';
import 'package:mixroom/helpers/producer_training_upload_service.dart';

Map<String, dynamic> project(double gain) => {
  'bpm': 120,
  'max_rows': 1,
  'master_gain_0to3': 1.0,
  'master_pan_0to1': 0.5,
  'rows': [
    {
      'row': 0,
      'row_id': 17,
      'hasAudio': true,
      'mix': {'gain_0to3': gain, 'pan_0to1': 0.5},
      'effects': [],
      'role_probs': {'vocals': 1.0},
      'features': {'approx_rms': 0.2, 'approx_crest': 3.0},
      'audio_stats': {'integrated_lufs_est': -18.0},
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Dart capture and wire bundle convert and validate in Python',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_contract_');
      addTearDown(() => dir.delete(recursive: true));
      var state = project(1);
      final collector = ProducerDataCollector(
        snapshotProvider: () async => {'project_state': state},
        ownerIdProvider: () => 'contract-producer',
        episodeIdleTimeout: const Duration(milliseconds: 20),
      );
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: {'project_state': state},
        projectId: 'contract-song-uuid',
        projectDir: dir,
      );
      await collector.recordAiRequest(prompt: 'Raise the vocal slightly');
      const action = {
        'type': 'set_row_gain',
        'data': {'row': 0, 'mode': 'set', 'value': 2.0},
      };
      collector.recordInferenceTrace({
        'mix_feature_contract_version': 'mix_refine_v1',
        'row_identities': {'0': 17},
        'project_state': state,
        'goal': {
          'intensity': 0.4,
          'execution_profile': 'producer_safe',
          'intents': [
            {'kind': 'gain'},
          ],
        },
        'strict': true,
        'actions': [action],
        'resolved_actions': [action],
        'fallback_used': false,
      });
      state = project(2);
      await collector.recordAiStep(
        prompt: 'Raise the vocal slightly',
        preSnapshot: {'project_state': project(1)},
        postSnapshot: {'project_state': state},
        resolvedActions: [action],
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(collector.hasPendingPromptCycle, isFalse);
      state = project(1.5);
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: {'row': 0, 'old_gain': 2.0, 'new_gain': 1.5},
      );
      await collector.finalizeActiveEpisode();
      expect(collector.reviewCandidates(), hasLength(1));
      final episode = collector.reviewCandidates().single;
      await collector.applyProducerLabel(
        episodeId: episode['episode_id'],
        diagnoses: ['level_balance'],
        strategies: ['target_level_change'],
        outcome: 'accepted',
        notes: 'Forward but natural',
      );
      final closed = await collector.closeSession();
      final document =
          jsonDecode(await closed!.readAsString()) as Map<String, dynamic>;
      final capturedEpisode = (document['episodes'] as List).first as Map;
      expect(
        capturedEpisode['inference_traces'][0]['row_identities']['0'],
        capturedEpisode['state_after']['project_state']['rows'][0]['row_id'],
      );
      expect(
        document['local_owner_ref'],
        ProducerDataCollector.ownerRef('contract-producer'),
      );
      expect(
        sanitizeProducerTrainingBundle(document).containsKey('local_owner_ref'),
        isFalse,
      );
      final wire = File('${dir.path}/wire.json');
      await wire.writeAsString(
        jsonEncode(sanitizeProducerTrainingBundle(document)),
      );
      final output = '${dir.path}/dataset';
      final conversion = await Process.run('python3', [
        'backend/training/producer_capture_converter.py',
        wire.path,
        '--output',
        output,
      ]);
      expect(
        conversion.exitCode,
        0,
        reason: '${conversion.stdout}\n${conversion.stderr}',
      );
      final manifest = jsonDecode(
        await File('$output/manifest.json').readAsString(),
      );
      expect(manifest['objective_example_counts']['mix_apply'], 1);
      expect(manifest['objective_example_counts']['mix_magnitude'], 1);
      final rows = (await File(
        '$output/examples-00000.jsonl',
      ).readAsLines()).map((s) => jsonDecode(s)).toList();
      expect(rows.first['labels']['magnitude_scale'], 0.5);
      expect(rows.first['feature_vector'], hasLength(77));
      expect(rows.first['goal']['execution_profile'], 'producer_safe');
      expect(rows.first['producer_notes'], 'Forward but natural');
      final validation = await Process.run('python3', [
        'backend/training/train_mix_refine_models.py',
        output,
        '--output',
        '${dir.path}/models',
        '--validate-only',
      ]);
      expect(
        validation.exitCode,
        0,
        reason: '${validation.stdout}\n${validation.stderr}',
      );
      final export = Platform.environment['PRODUCER_FIXTURE_DIR'];
      if (export != null) {
        await Directory(export).create(recursive: true);
        await wire.copy('$export/contract-capture.json');
      }
    },
  );

  for (final master in [false, true]) {
    test(
      'plugin capture survives Dart serialization and offline conversion master=$master',
      () async {
        final dir = await Directory.systemTemp.createTemp('producer_plugin_');
        addTearDown(() => dir.delete(recursive: true));
        Map<String, dynamic> snapshot(double threshold) {
          final state = project(1);
          final parameter = EffectParameterState.fromMap({
            'id': 'threshold',
            'name': 'Threshold',
            'type': 'float',
            'value': threshold,
            'min': -60.0,
            'max': 0.0,
            'unit': 'dB',
            'interval': 0.1,
            'valueNormalized': 0.5,
            'displayValue': '$threshold dB',
          });
          final effect = EffectState(
            effectIndex: 0,
            instanceId: 'instance-17',
            effectId: '/Library/Audio/Plug-Ins/VST3/Compressor.vst3',
            name: 'Compressor',
            isBypassed: false,
            parameters: [parameter],
          );
          if (master) {
            state['master_effects'] = [effect.toJson()];
          } else {
            state['rows'][0]['effects'] = [effect.toJson()];
          }
          return state;
        }

        var state = snapshot(-12);
        final collector = ProducerDataCollector(
          snapshotProvider: () async => {'project_state': state},
        );
        await collector.setEnabled(true);
        await collector.beginSession(
          initialSnapshot: {'project_state': state},
          projectId: 'plugin-song',
          projectDir: dir,
        );
        await collector.recordAiRequest(prompt: 'Control the vocal dynamics');
        final action = {
          'type': master
              ? 'adjust_master_effect_param_by_name'
              : 'adjust_effect_param_by_name',
          'data': {
            if (!master) 'row': 0,
            'effect_name_contains': 'Compressor',
            'param_name': 'Threshold',
            'mode': 'set',
            'value': -24.0,
          },
        };
        collector.recordInferenceTrace({
          'mix_feature_contract_version': 'mix_refine_v1',
          'row_identities': {'0': 17},
          'project_state': state,
          'goal': {'intensity': 0.4},
          'strict': true,
          'actions': [action],
          'resolved_actions': [action],
          'fallback_used': false,
        });
        state = snapshot(-24);
        await collector.recordAiStep(
          prompt: 'Control the vocal dynamics',
          preSnapshot: {'project_state': snapshot(-12)},
          postSnapshot: {'project_state': state},
          resolvedActions: [action],
        );
        if (master) await collector.finalizeActiveEpisode();
        state = snapshot(-18);
        if (!master) {
          await collector.recordManualEdit(
            kind: master ? 'master_fx_param' : 'row_fx_param',
            payload: {
              if (!master) 'row': 0,
              'index': 0,
              'param_id': 'threshold',
              'old_value': -24,
              'new_value': -18,
            },
          );
        }
        await collector.finalizeActiveEpisode();
        await collector.applyProducerLabel(
          episodeId: collector.reviewCandidates().single['episode_id'],
          diagnoses: ['dynamics'],
          strategies: ['compression'],
          outcome: 'accepted',
          notes: 'Less pumping',
        );
        final file = await collector.closeSession();
        final wire = File('${dir.path}/wire.json');
        await wire.writeAsString(
          jsonEncode(
            sanitizeProducerTrainingBundle(
              jsonDecode(await file!.readAsString()),
            ),
          ),
        );
        expect(await wire.readAsString(), isNot(contains('/Library/')));
        final converted = await Process.run('python3', [
          'backend/training/producer_capture_converter.py',
          wire.path,
          '--output',
          '${dir.path}/dataset',
        ]);
        expect(
          converted.exitCode,
          0,
          reason: '${converted.stdout} ${converted.stderr}',
        );
        final row = jsonDecode(
          (await File(
            '${dir.path}/dataset/examples-00000.jsonl',
          ).readAsLines()).first,
        );
        expect(
          row['eligibility']['mix_magnitude'],
          true,
          reason: '${row['exclusion_reasons']}',
        );
        expect(row['labels']['magnitude_scale'], closeTo(0.5, 0.00001));
        expect(row['final_plugin_target']['unit'], 'dB');
        expect(row['plugin_feature_vector'], hasLength(64));
        final export = Platform.environment['PRODUCER_FIXTURE_DIR'];
        if (export != null) {
          await Directory(export).create(recursive: true);
          await wire.copy('$export/plugin-capture-$master.json');
        }
      },
    );
  }

  test(
    'native plugin changes without gestures are reconciled before review',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_native_');
      addTearDown(() => dir.delete(recursive: true));
      var state = project(1);
      state['rows'][0]['effects'] = [
        {
          'name': 'Reverb',
          'instanceId': 'fx1',
          'parameters': [
            {'id': 'mix', 'type': 'float', 'value': 0.1},
          ],
        },
      ];
      final collector = ProducerDataCollector(
        snapshotProvider: () async => {'project_state': state},
      );
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: {'project_state': state},
        projectId: 'native-song',
        projectDir: dir,
      );
      // No Flutter gesture callback occurs when using a hosted plugin window.
      state = jsonDecode(jsonEncode(state));
      state['rows'][0]['effects'][0]['parameters'][0]['value'] = 0.4;
      await collector.finalizeActiveEpisode(disposition: 'mode_disabled');
      final episode = collector.reviewCandidates().single;
      expect(episode['actions_raw'][0]['kind'], 'observed_state_change');
      expect(
        episode['state_before']['project_state']['rows'][0]['effects'][0]['parameters'][0]['value'],
        0.1,
      );
      expect(
        episode['state_after']['project_state']['rows'][0]['effects'][0]['parameters'][0]['value'],
        0.4,
      );
      await collector.closeSession();
    },
  );

  test('partial application warning survives labeling and closing', () async {
    final dir = await Directory.systemTemp.createTemp('producer_partial_');
    addTearDown(() => dir.delete(recursive: true));
    final collector = ProducerDataCollector(
      snapshotProvider: () async => {'project_state': project(1.5)},
    );
    await collector.setEnabled(true);
    await collector.beginSession(
      initialSnapshot: {'project_state': project(1)},
      projectDir: dir,
    );
    await collector.recordAiStep(
      prompt: 'mix',
      preSnapshot: {'project_state': project(1)},
      postSnapshot: {'project_state': project(1.5)},
      resolvedActions: [],
      captureWarning: 'partial_ai_application',
    );
    await collector.finalizeActiveEpisode();
    await collector.applyProducerLabel(
      episodeId: collector.reviewCandidates().single['episode_id'],
      diagnoses: ['level_balance'],
      strategies: ['target_level_change'],
      outcome: 'accepted',
    );
    final file = await collector.closeSession();
    expect(
      jsonDecode(await file!.readAsString())['episodes'][0]['capture_warning'],
      'partial_ai_application',
    );
  });

  test('history operations affect only the mapped episode', () async {
    final dir = await Directory.systemTemp.createTemp('producer_history_');
    addTearDown(() => dir.delete(recursive: true));
    final collector = ProducerDataCollector(
      snapshotProvider: () async => {'project_state': project(1)},
    );
    await collector.setEnabled(true);
    await collector.beginSession(
      initialSnapshot: {'project_state': project(1)},
      projectDir: dir,
    );
    for (final id in ['first', 'second']) {
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: {
          'row': 0,
          'old_gain': 1.0,
          'new_gain': 1.2,
          'undo_transaction_id': id,
        },
      );
      await collector.finalizeActiveEpisode(disposition: 'test_boundary');
    }
    await collector.recordUndoRedo(isUndo: true, undoTransactionId: 'first');
    await collector.recordUndoRedo(isUndo: false, undoTransactionId: 'first');
    final file = await collector.closeSession();
    final episodes = jsonDecode(await file!.readAsString())['episodes'];
    expect(episodes[0]['outcome_signals']['undo_redo_observed'], true);
    expect(episodes[0]['outcome_signals']['rejected_by_undo'], false);
    expect(episodes[1]['outcome_signals']['undo_redo_observed'], isNull);
  });

  test(
    'concurrent gestures and session close keep a valid ordered journal',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_order_');
      addTearDown(() => dir.delete(recursive: true));
      final collector = ProducerDataCollector(
        snapshotProvider: () async => {'project_state': project(1.9)},
      );
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: {'project_state': project(1)},
        projectId: 'song',
        projectDir: dir,
      );
      final edits = [
        for (var i = 0; i < 10; i++)
          collector.recordManualEdit(
            kind: 'row_gain',
            payload: {
              'row': 0,
              'old_gain': 1 + i / 10,
              'new_gain': 1.1 + i / 10,
            },
          ),
      ];
      final closing = collector.closeSession();
      await Future.wait(edits);
      final file = await closing;
      final data = jsonDecode(await file!.readAsString());
      expect(
        (data['event_journal'] as List).where(
          (e) => e['type'] == 'mix_mutation',
        ),
        hasLength(10),
      );
      expect(data['episodes'][0]['actions_raw'], hasLength(1));
    },
  );
}
