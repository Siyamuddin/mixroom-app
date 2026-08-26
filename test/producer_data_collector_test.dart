import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exports producer sessions into the project folder when available',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_producer_project_',
      );
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

      final exported = await collector.exportActiveSession(
        projectDir: projectDir,
      );
      expect(exported, isNotNull);
      expect(await exported!.exists(), isTrue);
      expect(
        p.normalize(exported.path),
        startsWith(
          p.normalize(p.join(projectDir.path, 'exports', 'producer_sessions')),
        ),
      );
    },
  );

  test(
    'builds automatic v4 episodes and coalesces continuous gestures',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_producer_v4_',
      );
      addTearDown(() => projectDir.delete(recursive: true));
      var snapshot = _snapshot(gain: 1.0);
      final collector = ProducerDataCollector(
        snapshotProvider: () async => snapshot,
        episodeIdleTimeout: const Duration(milliseconds: 20),
      );
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: snapshot,
        projectId: 'client-project-name',
        projectDir: projectDir,
      );
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: const {'row': 0, 'old_gain': 1.0, 'new_gain': 1.2},
      );
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: const {'row': 0, 'old_gain': 1.2, 'new_gain': 1.4},
      );
      snapshot = _snapshot(gain: 1.4);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final file = await collector.closeSession();
      final document = jsonDecode(await file!.readAsString()) as Map;

      expect(document['schema_version'], ProducerDataCollector.schemaVersion);
      expect(document, isNot(contains('project_name')));
      final episodes = document['episodes'] as List;
      expect(episodes, hasLength(1));
      final episode = episodes.single as Map;
      expect((episode['actions_raw'] as List), hasLength(1));
      final payload =
          ((episode['actions_raw'] as List).single as Map)['payload'] as Map;
      expect(payload['old_gain'], 1.0);
      expect(payload['new_gain'], 1.4);
      expect(episode['diagnosis'], 'level_balance');
      expect(episode['masking_matrix_before'], isNotEmpty);
      expect(
        (episode['audio_feature_delta'] as Map)['integrated_lufs_est'],
        0.5,
      );
    },
  );

  test('marks a recent episode rejected when the producer undoes it', () async {
    final projectDir = await Directory.systemTemp.createTemp(
      'mixroom_producer_undo_',
    );
    addTearDown(() => projectDir.delete(recursive: true));
    final collector = ProducerDataCollector(
      snapshotProvider: () async => _snapshot(gain: 1.3),
    );
    await collector.setEnabled(true);
    await collector.beginSession(
      initialSnapshot: _snapshot(gain: 1.0),
      projectDir: projectDir,
    );
    await collector.recordManualEdit(
      kind: 'master_gain',
      payload: const {'old_gain': 1.0, 'new_gain': 1.3},
    );
    await collector.finalizeActiveEpisode();
    await collector.recordUndoRedo(isUndo: true, description: 'Master gain');
    final file = await collector.closeSession();
    final document = jsonDecode(await file!.readAsString()) as Map;
    final episode = (document['episodes'] as List).single as Map;
    expect(episode['status'], 'rejected');
    expect((episode['outcome_signals'] as Map)['rejected_by_undo'], isTrue);
  });

  test(
    'stores multiple producer-confirmed diagnoses for one episode',
    () async {
      final projectDir = await Directory.systemTemp.createTemp(
        'mixroom_producer_multilabel_',
      );
      addTearDown(() => projectDir.delete(recursive: true));
      final collector = ProducerDataCollector(
        snapshotProvider: () async => _snapshot(gain: 1.2),
      );
      await collector.setEnabled(true);
      await collector.beginSession(
        initialSnapshot: _snapshot(gain: 1.0),
        projectDir: projectDir,
      );
      await collector.recordManualEdit(
        kind: 'row_gain',
        payload: const {'row': 0, 'old_gain': 1.0, 'new_gain': 1.2},
      );
      await collector.finalizeActiveEpisode();
      final episodeId = collector
          .reviewCandidates()
          .single['episode_id']
          .toString();
      await collector.applyProducerLabel(
        episodeId: episodeId,
        diagnoses: const ['level_balance', 'masking'],
        strategies: const ['target_level_change', 'source_tone_change'],
      );
      final file = await collector.closeSession();
      final document = jsonDecode(await file!.readAsString()) as Map;
      final episode = (document['episodes'] as List).single as Map;

      expect(episode['diagnosis'], 'level_balance');
      expect(episode['diagnoses'], ['level_balance', 'masking']);
      expect((episode['provenance'] as Map)['label'], 'producer');
    },
  );

  test('privacy sanitizer strips names, paths, and credentials', () async {
    final projectDir = await Directory.systemTemp.createTemp(
      'mixroom_producer_privacy_',
    );
    addTearDown(() => projectDir.delete(recursive: true));
    final collector = ProducerDataCollector();
    await collector.setEnabled(true);
    await collector.beginSession(
      initialSnapshot: {
        ..._snapshot(gain: 1.0),
        'project_name': 'Secret Client',
        'path': '/Users/client/song.wav',
        'effect_id': '/Library/Audio/Plug-Ins/VST3/PrivatePlugin.vst3',
      },
      projectId: 'secret-project-id',
      projectDir: projectDir,
    );
    await collector.recordManualEdit(
      kind: 'row_fx_param',
      payload: const {
        'row': 0,
        'source_path': '/Users/client/vocal.wav',
        'authorization': 'Bearer private-token',
      },
    );
    final file = await collector.closeSession();
    final serialized = await file!.readAsString();
    expect(serialized, isNot(contains('Secret Client')));
    expect(serialized, isNot(contains('/Users/')));
    expect(serialized, isNot(contains('/Library/Audio/Plug-Ins')));
    expect(serialized, isNot(contains('private-token')));
    expect(serialized, isNot(contains('secret-project-id')));
  });

  test('migrates v3 prompt cycles without inventing missing targets', () {
    final migrated = migrateProducerSessionV3({
      'schema_version': 3,
      'session_id': 'legacy-one',
      'prompt_cycles': [
        {
          'status': 'complete',
          'prompt': 'Make the vocal clearer',
          'before_prompt_snapshot': {
            'project_name': 'Private Client',
            'path': '/Users/client/song.wav',
          },
          'ai_after_snapshot': {
            'master': {'gain': 1.1},
          },
          'resolved_ai_actions': [
            {'type': 'gain', 'row': 0, 'delta': 0.1},
          ],
        },
      ],
    });
    final episode = (migrated['episodes'] as List).single as Map;
    expect(migrated['schema_version'], ProducerDataCollector.schemaVersion);
    expect((episode['audio_target'] as Map)['status'], 'unavailable');
    expect((episode['provenance'] as Map)['label'], 'unknown');
    expect(jsonEncode(migrated), isNot(contains('Private Client')));
    expect(jsonEncode(migrated), isNot(contains('/Users/')));
  });
}

Map<String, dynamic> _snapshot({required double gain}) => {
  'project_state': {
    'rows': [
      {
        'row_id': 7,
        'row_name': 'Vocal Client Name',
        'hasAudio': true,
        'role_probs': {'vocals': 0.9, 'other': 0.1},
        'audio_stats': {
          'integrated_lufs_est': -18.0 + (gain - 1.0) * 2.5,
          'activity_ratio': 0.8,
          'low': 0.2,
          'lowmid': 0.5,
          'mid': 0.8,
          'high': 0.6,
        },
        'mix': {'gain_0to3': gain},
      },
      {
        'row_id': 8,
        'hasAudio': true,
        'role_probs': {'guitar': 0.8, 'other': 0.2},
        'audio_stats': {
          'integrated_lufs_est': -20.0,
          'activity_ratio': 0.7,
          'low': 0.1,
          'lowmid': 0.6,
          'mid': 0.7,
          'high': 0.4,
        },
      },
    ],
  },
};
