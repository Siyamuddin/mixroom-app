import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/ai/ai_gain_units.dart';
import 'package:mixroom/ai/basic_pitch_transcriber.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:path/path.dart' as p;

import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('V3 transport success is rollback-capable but not user Undo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _transportAction('set_metronome_enabled', enabled: true),
        _transportAction('set_loop_enabled', enabled: true),
        _transportAction('restart'),
      ],
    ));

    final applied = controller.snapshot();
    final transport = (applied['transport'] as Map).cast<String, dynamic>();
    expect(transport['playing'], isFalse);
    expect(transport['playhead_ms'], transport['loop_start_ms']);
    expect(transport['metronome_enabled'], isTrue);
    expect(transport['loop_enabled'], isTrue);
    expect(transport['loop_end_ms'] as int,
        greaterThan(transport['loop_start_ms'] as int));
    expect(applied['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 restores transport after a later bundle action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final initialTransport =
        (before['transport'] as Map).cast<String, dynamic>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _transportAction('set_metronome_enabled', enabled: true),
        _transportAction('set_loop_enabled', enabled: true),
        _renameAction(1, rows[1]['row_id'] as int, ''),
      ],
    ));

    final after = controller.snapshot();
    expect(after['transport'], initialTransport);
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mixed V3 Undo leaves successful transport state alone',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _transportAction('set_metronome_enabled', enabled: true),
        _muteAction(0, rows[0]['row_id'] as int),
      ],
    ));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect(_row(undone, 0)['muted'], isFalse);
    expect((undone['transport'] as Map)['metronome_enabled'], isTrue);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(_row(redone, 0)['muted'], isTrue);
    expect((redone['transport'] as Map)['metronome_enabled'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 compound mute and rename is one atomic undo entry',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _muteAction(0, rows[0]['row_id'] as int),
        _renameAction(1, rows[1]['row_id'] as int, 'Soft Pad'),
      ],
    ));

    final applied = controller.snapshot();
    expect(_row(applied, 0)['muted'], isTrue);
    expect(_row(applied, 1)['name'], 'Soft Pad');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _muteAction(0, rows[0]['row_id'] as int),
      ],
    ));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1,
        reason: 'An idempotent mute must not add an undo entry.');

    await controller.undo();
    final undone = controller.snapshot();
    expect(_row(undone, 0)['muted'], isFalse);
    expect(_row(undone, 1)['name'], 'Synth');
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(_row(redone, 0)['muted'], isTrue);
    expect(_row(redone, 1)['name'], 'Soft Pad');
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row role override uses one ordered reversible transaction',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows.first['row_id'] as int;
    final initialRole = rows.first['role_override'] as String;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _roleOverrideAction(0, rowId, 'drums'),
        _roleOverrideAction(0, rowId, 'bass'),
      ],
    ));

    var applied = controller.snapshot();
    expect(_row(applied, 0)['role_override'], 'bass');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(_row(controller.snapshot(), 0)['role_override'], initialRole);

    await controller.redo();
    expect(_row(controller.snapshot(), 0)['role_override'], 'bass');

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _roleOverrideAction(0, rowId, null),
      ],
    ));
    applied = controller.snapshot();
    expect(_row(applied, 0)['role_override'], isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row role override rolls back after a later failure',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows.first['row_id'] as int;
    final initialRole = rows.first['role_override'] as String;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _roleOverrideAction(0, rowId, 'synth'),
        _renameAction(0, rowId, ''),
      ],
    ));

    final after = controller.snapshot();
    expect(_row(after, 0)['role_override'], initialRole);
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row role override survives autosave and project reload',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final rows =
        (controller.snapshot()['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows.first['row_id'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _roleOverrideAction(0, rowId, 'guitar'),
      ],
    ));
    await _pumpFor(tester, const Duration(seconds: 2));

    final projectJson = jsonDecode(
      await File('${fixture.directory.path}/project.json').readAsString(),
    ) as Map<String, dynamic>;
    final persistedRows =
        (projectJson['rows'] as List).cast<Map<String, dynamic>>();
    final persisted = persistedRows.singleWhere((row) => row['rowId'] == rowId);
    expect(persisted['roleOverride'], 'guitar');

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['rows'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(
      _row(reopenedController.snapshot(), 0)['role_override'],
      'guitar',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 rolls mute back when the following action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _muteAction(0, rows[0]['row_id'] as int),
        _renameAction(1, rows[1]['row_id'] as int, ''),
      ],
    ));

    final after = controller.snapshot();
    expect(_row(after, 0)['muted'], isFalse);
    expect(_row(after, 1)['name'], 'Synth');
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row metadata is one reversible atomic transaction',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final firstRowId = rows[0]['row_id'] as int;
    final secondRowId = rows[1]['row_id'] as int;
    final initialSelectedRowId = before['selected_row_id'];
    final initialColor = rows[1]['color'] as int;
    final initialUndoDepth = before['undo_depth'] as int;

    final metadataActions = <Map<String, dynamic>>[
      _selectAction(1, secondRowId),
      _colorAction(1, secondRowId, 'blue'),
      _muteAction(0, firstRowId),
    ];
    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: metadataActions,
    ));

    final applied = controller.snapshot();
    expect(applied['selected_row_id'], secondRowId);
    expect(_row(applied, 1)['color'], 0xFF79A8FF);
    expect(_row(applied, 0)['muted'], isTrue);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect(undone['selected_row_id'], initialSelectedRowId);
    expect(_row(undone, 1)['color'], initialColor);
    expect(_row(undone, 0)['muted'], isFalse);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(redone['selected_row_id'], secondRowId);
    expect(_row(redone, 1)['color'], 0xFF79A8FF);
    expect(_row(redone, 0)['muted'], isTrue);
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        ...metadataActions,
        _renameAction(1, secondRowId, ''),
      ],
    ));
    final rolledBack = controller.snapshot();
    expect(rolledBack['selected_row_id'], initialSelectedRowId);
    expect(_row(rolledBack, 1)['color'], initialColor);
    expect(_row(rolledBack, 0)['muted'], isFalse);
    expect(rolledBack['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row creation preserves stable compound targets and undo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final anchorId = rows.first['row_id'] as int;
    final shiftedId = rows.last['row_id'] as int;
    final previousSelection = before['selected_row_id'];
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _createRowAction(
          name: 'Vocal Double',
          position: 'above',
          anchorRowIndex: 0,
          anchorRowId: anchorId,
        ),
        _renameAction(1, shiftedId, 'Shifted Synth'),
      ],
    ));

    var applied = controller.snapshot();
    final appliedRows = (applied['rows'] as List).cast<Map>();
    expect(appliedRows, hasLength(rows.length + 1));
    expect(appliedRows.first['name'], 'Vocal Double');
    expect(
      appliedRows.singleWhere((row) => row['row_id'] == shiftedId)['name'],
      'Shifted Synth',
    );
    expect(applied['selected_row_id'], appliedRows.first['row_id']);
    expect(applied['undo_depth'], initialUndoDepth + 1);
    final createdRowId = appliedRows.first['row_id'];

    await controller.undo();
    final undone = controller.snapshot();
    expect((undone['rows'] as List), hasLength(rows.length));
    expect(_row(undone, 1)['name'], rows.last['name']);
    expect(undone['selected_row_id'], previousSelection);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect((applied['rows'] as List), hasLength(rows.length + 1));
    expect(_row(applied, 0)['name'], 'Vocal Double');
    expect(_row(applied, 2)['name'], 'Shifted Synth');
    expect(_row(applied, 0)['row_id'], createdRowId);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 identical row creations bind distinct runtime ids',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final originalIds = rows.map((row) => row['row_id'] as int).toSet();
    final anchorId = rows.first['row_id'] as int;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _createRowAction(
          name: 'Double',
          position: 'end',
          anchorRowIndex: 0,
          anchorRowId: anchorId,
        ),
        _createRowAction(
          name: 'Double',
          position: 'end',
          anchorRowIndex: 0,
          anchorRowId: anchorId,
        ),
      ],
    ));

    var applied = controller.snapshot();
    final created = (applied['rows'] as List)
        .cast<Map<String, dynamic>>()
        .where((row) => !originalIds.contains(row['row_id']))
        .toList(growable: false);
    expect(created, hasLength(2));
    expect(created.map((row) => row['name']), everyElement('Double'));
    expect(created.map((row) => row['row_id']).toSet(), hasLength(2));
    final createdIds = created.map((row) => row['row_id'] as int).toSet();
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect((controller.snapshot()['rows'] as List), hasLength(rows.length));

    await controller.redo();
    applied = controller.snapshot();
    final redoneCreated = (applied['rows'] as List)
        .cast<Map<String, dynamic>>()
        .where((row) => !originalIds.contains(row['row_id']))
        .toList(growable: false);
    expect(redoneCreated, hasLength(2));
    expect(redoneCreated.map((row) => row['row_id']).toSet(), createdIds);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 created row identity survives persisted undo and redo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final originalIds = rows.map((row) => row['row_id'] as int).toSet();

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _createRowAction(
          name: 'Persisted Creation',
          position: 'end',
          anchorRowIndex: 0,
          anchorRowId: rows.first['row_id'] as int,
        ),
      ],
    ));
    await _pumpFor(tester, const Duration(seconds: 2));

    final applied = controller.snapshot();
    final createdId = (applied['rows'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => !originalIds.contains(row['row_id']))['row_id'];

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['rows'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    expect(
      (reopenedController.snapshot()['rows'] as List)
          .cast<Map<String, dynamic>>()
          .any((row) => row['row_id'] == createdId),
      isTrue,
    );
    await reopenedController.undo();
    expect(
      (reopenedController.snapshot()['rows'] as List)
          .cast<Map<String, dynamic>>()
          .any((row) => row['row_id'] == createdId),
      isFalse,
    );
    await reopenedController.redo();
    expect(
      (reopenedController.snapshot()['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['row_id'] == createdId)['name'],
      'Persisted Creation',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row deletion rollback restores exact row and clip identities',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    expect(rows.length, greaterThanOrEqualTo(2));
    final initialRowIds =
        rows.map((row) => row['row_id'] as int).toList(growable: false);
    final initialClipOwners = <String, int>{
      for (final clip in clips)
        clip['clip_id'] as String: clip['row_id'] as int,
    };
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _deleteRowAction(1, initialRowIds[1]),
        _renameAction(0, initialRowIds[0], ''),
      ],
    ));

    final after = controller.snapshot();
    expect(
      (after['rows'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['row_id'])
          .toList(growable: false),
      initialRowIds,
    );
    expect(
      <String, int>{
        for (final clip
            in (after['clips'] as List).cast<Map<String, dynamic>>())
          clip['clip_id'] as String: clip['row_id'] as int,
      },
      initialClipOwners,
    );
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 populated row deletion restores contents and selection',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final deletedRowId = rows.first['row_id'] as int;
    final survivingRowId = rows.last['row_id'] as int;
    final deletedClipCount =
        clips.where((clip) => clip['row_id'] == deletedRowId).length;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _deleteRowAction(0, deletedRowId),
      ],
    ));

    var applied = controller.snapshot();
    expect((applied['rows'] as List), hasLength(rows.length - 1));
    expect(
      (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['row_id'])
          .toList(growable: false),
      <Object?>[survivingRowId],
    );
    expect(applied['selected_row_id'], survivingRowId);
    expect(
      (applied['clips'] as List).length,
      clips.length - deletedClipCount,
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect((undone['rows'] as List), hasLength(rows.length));
    expect((undone['clips'] as List), hasLength(clips.length));
    expect(_row(undone, 0)['name'], rows.first['name']);
    expect(undone['selected_row_id'], isNot(survivingRowId));
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect((applied['rows'] as List), hasLength(rows.length - 1));
    expect(
      (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['row_id'])
          .toList(growable: false),
      <Object?>[survivingRowId],
    );
    expect(
        (applied['clips'] as List), hasLength(clips.length - deletedClipCount));
    expect(applied['selected_row_id'], survivingRowId);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 verifies edited row followed by deletion as final absence',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final deletedRow = rows.first;
    final deletedRowId = deletedRow['row_id'] as int;
    final deletedClip = clips.firstWhere(
      (clip) => clip['row_id'] == deletedRowId,
    );
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          _rowMixAction(0, deletedRowId, 'set_gain', gainDb: -8),
          _renameAction(0, deletedRowId, 'Delete After Editing'),
          <String, dynamic>{
            'type': 'automation_edit',
            'data': <String, dynamic>{
              'operation': 'set_points',
              'value_mode': 'normalized',
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': deletedRowId,
                'automation_target_id': 'volume',
              },
              'points': const <Map<String, dynamic>>[
                <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
                <String, dynamic>{'time_ms': 1000.0, 'value': 0.75},
              ],
            },
          },
          <String, dynamic>{
            'type': 'v3_effect_configure',
            'data': <String, dynamic>{
              'operation': 'ensure_configured',
              'effect_id': 'EQ 3-Band',
              'parameters': const <String, dynamic>{'Low Gain': 0.75},
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': deletedRowId,
              },
            },
          },
          _clipAction(
            'move',
            deletedClip,
            deletedRow,
            extra: const <String, dynamic>{'delta_ms': 250.0},
          ),
          _deleteRowAction(0, deletedRowId),
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    var applied = controller.snapshot();
    expect(
      (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .any((row) => row['row_id'] == deletedRowId),
      isFalse,
    );
    expect(
      (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .any((clip) => clip['row_id'] == deletedRowId),
      isFalse,
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect((undone['rows'] as List), hasLength(rows.length));
    expect((undone['clips'] as List), hasLength(clips.length));
    expect(_row(undone, 0)['name'], deletedRow['name']);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect(
      (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .any((row) => row['row_id'] == deletedRowId),
      isFalse,
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 grouped row deletion restores the dissolved group',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowIds = rows.map((row) => row['row_id'] as int).toList();
    final initialUndoDepth = before['undo_depth'] as int;
    const groupId = 'v3-delete-group';

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupCreateAction(groupId, 'Delete Test', rowIds, rowIds),
      ],
    ));
    expect(_group(controller.snapshot(), groupId)['name'], 'Delete Test');

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _deleteRowAction(0, rowIds.first),
      ],
    ));
    var current = controller.snapshot();
    expect(current['groups'], isEmpty);
    expect(current['undo_depth'], initialUndoDepth + 2);

    await controller.undo();
    current = controller.snapshot();
    expect((current['rows'] as List), hasLength(rows.length));
    final restoredRowIds = (current['rows'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['row_id'] as int)
        .toList(growable: false);
    expect(_group(current, groupId)['name'], 'Delete Test');
    expect(_group(current, groupId)['member_row_ids'], restoredRowIds);
    expect(restoredRowIds.last, rowIds.last,
        reason: 'The surviving row must keep its stable runtime ID.');
    expect(current['undo_depth'], initialUndoDepth + 1);

    await controller.redo();
    current = controller.snapshot();
    expect((current['rows'] as List), hasLength(rows.length - 1));
    expect(current['groups'], isEmpty);
    expect(current['undo_depth'], initialUndoDepth + 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 grouping applies, dissolves, and rolls back atomically',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowIds = rows.map((row) => row['row_id'] as int).toList();
    final initialSelection = before['selected_row_id'];
    final initialUndoDepth = before['undo_depth'] as int;
    const groupId = 'v3-test-group';

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupCreateAction(groupId, 'Music', rowIds, rowIds),
      ],
    ));

    var applied = controller.snapshot();
    expect(applied['groups'], hasLength(1));
    expect(_group(applied, groupId)['name'], 'Music');
    expect(_group(applied, groupId)['member_row_ids'], rowIds);
    expect(_group(applied, groupId)['collapsed'], isFalse);
    expect(
      (applied['rows'] as List).map((row) => row['group_id']).toList(),
      everyElement(groupId),
    );
    expect(applied['selected_row_id'], initialSelection);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    var restored = controller.snapshot();
    expect(restored['groups'], isEmpty);
    expect(
      (restored['rows'] as List).map((row) => row['group_id']).toList(),
      everyElement(isEmpty),
    );
    expect(restored['selected_row_id'], initialSelection);
    expect(restored['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect(_group(applied, groupId)['member_row_ids'], rowIds);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupCollapsedAction(groupId, true),
        _renameAction(1, rowIds[1], ''),
      ],
    ));
    applied = controller.snapshot();
    expect(_group(applied, groupId)['collapsed'], isFalse,
        reason: 'A later failure must roll back the group state.');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupRemoveRowAction(groupId, rowIds.first, dissolvesGroup: true),
      ],
    ));
    applied = controller.snapshot();
    expect(applied['groups'], isEmpty);
    expect(
      (applied['rows'] as List).map((row) => row['group_id']).toList(),
      everyElement(isEmpty),
    );
    expect(applied['undo_depth'], initialUndoDepth + 2);

    await controller.undo();
    restored = controller.snapshot();
    expect(_group(restored, groupId)['member_row_ids'], rowIds);
    expect(restored['selected_row_id'], initialSelection);
    expect(restored['undo_depth'], initialUndoDepth + 1);

    await controller.redo();
    applied = controller.snapshot();
    expect(applied['groups'], isEmpty);
    expect(applied['undo_depth'], initialUndoDepth + 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 row effects remain row-scoped when their row becomes a group lead',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final rowIds = rows.map((row) => row['row_id'] as int).toList();
      final initialUndoDepth = before['undo_depth'] as int;

      Map<String, dynamic> effectAction() => <String, dynamic>{
        'type': 'v3_effect_configure',
        'data': <String, dynamic>{
          'operation': 'ensure_configured',
          'effect_id': 'EQ 3-Band',
          'parameters': const <String, dynamic>{},
          'target': <String, dynamic>{
            'scope': 'row',
            'row_index': 0,
            'row_id': rowIds.first,
          },
        },
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            effectAction(),
            _groupCreateAction(
              'v3-row-effect-group',
              'Processed',
              rowIds,
              rowIds,
            ),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      var applied = controller.snapshot();
      expect(_group(applied, 'v3-row-effect-group')['member_row_ids'], rowIds);
      expect(
        (await controller.effectChain(
          0,
        )).map((effect) => effect['effect_id']).toList(),
        contains('EQ 3-Band'),
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(controller.snapshot()['groups'], isEmpty);
      expect(await controller.effectChain(0), isEmpty);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      applied = controller.snapshot();
      expect(_group(applied, 'v3-row-effect-group')['member_row_ids'], rowIds);
      expect(
        (await controller.effectChain(
          0,
        )).map((effect) => effect['effect_id']).toList(),
        contains('EQ 3-Band'),
      );

      await controller.undo();
      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            _groupCreateAction('v3-group-first', 'Group First', rowIds, rowIds),
            effectAction(),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(_group(controller.snapshot(), 'v3-group-first'), isNotEmpty);
      expect(
        (await controller.effectChain(
          0,
        )).map((effect) => effect['effect_id']).toList(),
        contains('EQ 3-Band'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 group metadata survives autosave and project reload', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final rows =
        (controller.snapshot()['rows'] as List).cast<Map<String, dynamic>>();
    final rowIds = rows.map((row) => row['row_id'] as int).toList();
    const groupId = 'v3-persisted-group';

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupCreateAction(groupId, 'Persisted Name', rowIds, rowIds),
        _groupCollapsedAction(groupId, true),
      ],
    ));
    await _pumpFor(tester, const Duration(seconds: 2));

    final projectJson = jsonDecode(
      await File('${fixture.directory.path}/project.json').readAsString(),
    ) as Map<String, dynamic>;
    final persistedGroups =
        (projectJson['trackGroups'] as List).cast<Map<String, dynamic>>();
    final persisted = persistedGroups.singleWhere(
      (group) => group['id'] == groupId,
    );
    expect(persisted['name'], 'Persisted Name');
    expect(persisted['rowIds'], rowIds);
    expect(persisted['collapsed'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['rows'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    final reopened = reopenedController.snapshot();
    final reopenedRowIds = (reopened['rows'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['row_id'] as int)
        .toList(growable: false);
    expect(_group(reopened, groupId)['name'], 'Persisted Name');
    expect(_group(reopened, groupId)['member_row_ids'], reopenedRowIds);
    expect(_group(reopened, groupId)['collapsed'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row controls apply, undo, redo, and roll back atomically',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows[0]['row_id'] as int;
    final initialGain = rows[0]['gain_ui'] as double;
    final initialPan = rows[0]['pan_01'] as double;
    final initialUndoDepth = before['undo_depth'] as int;
    final expectedGain = rowGainDbToUi(-6);
    final initialPanSigned = (initialPan * 2.0) - 1.0;
    final expectedPanSigned = (initialPanSigned + 0.25).clamp(-1.0, 1.0);
    final expectedPan = (expectedPanSigned + 1.0) * 0.5;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _rowMixAction(0, rowId, 'set_gain', gainDb: -6),
        _rowMixAction(0, rowId, 'adjust_pan', deltaSigned: 0.25),
        _soloAction(0, rowId, true),
      ],
    ));

    final applied = controller.snapshot();
    expect(_row(applied, 0)['gain_ui'], closeTo(expectedGain, 0.00001));
    expect(_row(applied, 0)['pan_01'], closeTo(expectedPan, 0.00001));
    expect(_row(applied, 0)['soloed'], isTrue);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _rowMixAction(0, rowId, 'set_gain', gainDb: -6),
        _rowMixAction(0, rowId, 'set_pan', panSigned: expectedPanSigned),
        _soloAction(0, rowId, true),
      ],
    ));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1,
        reason: 'Already-satisfied row controls must not add history.');

    await controller.undo();
    final undone = controller.snapshot();
    expect(_row(undone, 0)['gain_ui'], closeTo(initialGain, 0.00001));
    expect(_row(undone, 0)['pan_01'], closeTo(initialPan, 0.00001));
    expect(_row(undone, 0)['soloed'], isFalse);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(_row(redone, 0)['gain_ui'], closeTo(expectedGain, 0.00001));
    expect(_row(redone, 0)['pan_01'], closeTo(expectedPan, 0.00001));
    expect(_row(redone, 0)['soloed'], isTrue);
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _rowMixAction(0, rowId, 'set_gain', gainDb: -6),
        _rowMixAction(0, rowId, 'adjust_gain', deltaSigned: 0.1),
        _rowMixAction(0, rowId, 'adjust_pan', deltaSigned: 0.25),
        _soloAction(0, rowId, true),
        _renameAction(1, rows[1]['row_id'] as int, ''),
      ],
    ));
    final rolledBack = controller.snapshot();
    expect(_row(rolledBack, 0)['gain_ui'], closeTo(initialGain, 0.00001));
    expect(_row(rolledBack, 0)['pan_01'], closeTo(initialPan, 0.00001));
    expect(_row(rolledBack, 0)['soloed'], isFalse);
    expect(rolledBack['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 direct row controls do not edit a containing group bus',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowIds = rows.map((row) => row['row_id'] as int).toList();
    const groupId = 'v3-direct-row-group';

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _groupCreateAction(groupId, 'Grouped Rows', rowIds, rowIds),
      ],
    ));

    final grouped = controller.snapshot();
    final groupBefore = Map<String, dynamic>.from(_group(grouped, groupId));
    final rowBefore = _row(grouped, 0);
    final initialGain = (rowBefore['gain_ui'] as num).toDouble();
    final initialPan = (rowBefore['pan_01'] as num).toDouble();

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _rowMixAction(
          0,
          rowIds.first,
          'adjust_gain',
          deltaSigned: 0.2,
        ),
        _rowMixAction(
          0,
          rowIds.first,
          'adjust_pan',
          deltaSigned: -0.2,
        ),
      ],
    ));

    var applied = controller.snapshot();
    expect(
      (_row(applied, 0)['gain_ui'] as num).toDouble(),
      closeTo((initialGain + 0.2).clamp(0.0, 3.0), 0.00001),
    );
    expect(
      (_row(applied, 0)['pan_01'] as num).toDouble(),
      closeTo((initialPan - 0.1).clamp(0.0, 1.0), 0.00001),
    );
    expect(_group(applied, groupId), groupBefore);

    await controller.undo();
    final undone = controller.snapshot();
    expect(
      (_row(undone, 0)['gain_ui'] as num).toDouble(),
      closeTo(initialGain, 0.00001),
    );
    expect(
      (_row(undone, 0)['pan_01'] as num).toDouble(),
      closeTo(initialPan, 0.00001),
    );
    expect(_group(undone, groupId), groupBefore);

    await controller.redo();
    applied = controller.snapshot();
    expect(
      (_row(applied, 0)['pan_01'] as num).toDouble(),
      closeTo((initialPan - 0.1).clamp(0.0, 1.0), 0.00001),
    );
    expect(_group(applied, groupId), groupBefore);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 verifies repeated direct row edits as ordered final state',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows[0]['row_id'] as int;
    final secondRowId = rows[1]['row_id'] as int;
    final initialGain = rows[0]['gain_ui'] as double;
    final initialPan = rows[0]['pan_01'] as double;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _rowMixAction(0, rowId, 'set_gain', gainDb: -6),
        _rowMixAction(0, rowId, 'adjust_gain', deltaSigned: 0.1),
        _rowMixAction(0, rowId, 'adjust_gain', deltaSigned: 0.2),
        _rowMixAction(0, rowId, 'adjust_pan', deltaSigned: 0.2),
        _rowMixAction(0, rowId, 'adjust_pan', deltaSigned: -0.1),
        _renameAction(0, rowId, 'First Name'),
        _renameAction(0, rowId, 'Final Name'),
        _soloAction(0, rowId, true),
        _soloAction(0, rowId, false),
        _muteAction(0, rowId),
        _muteAction(0, rowId, false),
        _colorAction(0, rowId, 'blue'),
        _colorAction(0, rowId, 'none'),
        _selectAction(1, secondRowId),
        _selectAction(0, rowId),
      ],
    ));

    final applied = controller.snapshot();
    expect(_row(applied, 0)['gain_ui'],
        closeTo((rowGainDbToUi(-6) + 0.3).clamp(0.0, 3.0), 0.00001));
    expect(_row(applied, 0)['pan_01'],
        closeTo((initialPan + 0.05).clamp(0.0, 1.0), 0.00001));
    expect(_row(applied, 0)['name'], 'Final Name');
    expect(_row(applied, 0)['soloed'], isFalse);
    expect(_row(applied, 0)['muted'], isFalse);
    expect(_row(applied, 0)['color'], 0);
    expect(applied['selected_row_id'], rowId);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect(_row(undone, 0)['gain_ui'], closeTo(initialGain, 0.00001));
    expect(_row(undone, 0)['pan_01'], closeTo(initialPan, 0.00001));
    expect(_row(undone, 0)['name'], rows[0]['name']);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(_row(redone, 0)['name'], 'Final Name');
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 compact mix accumulates repeated row and master edits',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final initialGain = _row(before, 0)['gain_ui'] as double;
    final initialPan = _row(before, 0)['pan_01'] as double;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'ordered-mix',
              'actions': <Map<String, dynamic>>[
                for (final delta in const <double>[0.1, 0.2])
                  <String, dynamic>{
                    'type': 'set_row_gain',
                    'data': <String, dynamic>{
                      'row': 0,
                      'mode': 'delta',
                      'delta': delta,
                    },
                  },
                for (final delta in const <double>[0.2, -0.1])
                  <String, dynamic>{
                    'type': 'set_row_pan',
                    'data': <String, dynamic>{'row': 0, 'delta': delta},
                  },
                for (final delta in const <double>[0.1, 0.15])
                  <String, dynamic>{
                    'type': 'set_master_gain',
                    'data': <String, dynamic>{'mode': 'delta', 'delta': delta},
                  },
                for (final delta in const <double>[0.2, -0.1])
                  <String, dynamic>{
                    'type': 'set_master_pan',
                    'data': <String, dynamic>{'delta': delta},
                  },
              ],
            },
          },
        ],
      ),
    );

    final applied = controller.snapshot();
    expect(_row(applied, 0)['gain_ui'],
        closeTo((initialGain + 0.3).clamp(0.0, 3.0), 0.00001));
    expect(_row(applied, 0)['pan_01'],
        closeTo((initialPan + 0.05).clamp(0.0, 1.0), 0.00001));
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(_row(controller.snapshot(), 0)['gain_ui'],
        closeTo(initialGain, 0.00001));
    await controller.redo();
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 audio pitch applies, reads back, undoes, and redoes',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialPitch = (clip['pitch_semitones'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;
    final targetPitch = initialPitch - 2.0;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': initialPitch - 1.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': targetPitch,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    expect(
      ((applied['clips'] as List).first as Map)['pitch_semitones'],
      closeTo(targetPitch, 0.0005),
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect(
      ((undone['clips'] as List).first as Map)['pitch_semitones'],
      closeTo(initialPitch, 0.0005),
    );
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect(
      ((applied['clips'] as List).first as Map)['pitch_semitones'],
      closeTo(targetPitch, 0.0005),
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': targetPitch,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
        ],
      ),
    );
    expect(
      controller.snapshot()['undo_depth'],
      initialUndoDepth + 1,
      reason: 'An already-satisfied pitch must not add history.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 sample replacement preserves stable identity and compounds with pitch',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_replace_lengths',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final target = clips.first;
      final replacementSource = clips[2]['file'] as String;
      final clipId = target['clip_id'] as String;
      final initialPitch = (target['pitch_semitones'] as num).toDouble();
      final targetPitch = initialPitch + 2.0;
      final initialUndoDepth = before['undo_depth'] as int;
      final initialStart = target['start_ms'];
      final initialLength = (target['length_ms'] as num).toDouble();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': targetPitch,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_index': 0,
                  'clip_id': clipId,
                  'row_index': target['row_index'],
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_sample_replace',
              'data': <String, dynamic>{
                'operation': 'replace',
                'asset_id': 'fixture-replacement',
                'library_path': replacementSource,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_index': 0,
                  'clip_id': clipId,
                  'row_index': target['row_index'],
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      var appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final replaced = appliedClips.singleWhere(
        (clip) => clip['clip_id'] == clipId,
      );
      expect(appliedClips, hasLength(clips.length));
      expect(replaced['file'], isNot(target['file']));
      expect(replaced['start_ms'], initialStart);
      expect(replaced['length_ms'], closeTo(initialLength, 1));
      expect(replaced['pitch_semitones'], closeTo(targetPitch, 0.0005));
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      final undone = controller.snapshot();
      final restored = (undone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] == clipId);
      expect(restored['file'], target['file']);
      expect(restored['pitch_semitones'], closeTo(initialPitch, 0.0005));
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      applied = controller.snapshot();
      appliedClips = (applied['clips'] as List).cast<Map<String, dynamic>>();
      final redone = appliedClips.singleWhere(
        (clip) => clip['clip_id'] == clipId,
      );
      expect(redone['file'], isNot(target['file']));
      expect(redone['pitch_semitones'], closeTo(targetPitch, 0.0005));
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await _pumpFor(tester, const Duration(seconds: 2));
      final projectJson =
          jsonDecode(
                await File(
                  '${fixture.directory.path}/project.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final persistedTracks = (projectJson['tracks'] as List)
          .cast<Map<String, dynamic>>();
      final persisted = persistedTracks.singleWhere(
        (clip) => clip['clipId'] == clipId,
      );
      expect(
        persisted['fileName'],
        isNot(p.basename(target['file'] as String)),
      );

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(buildIntegrationTestApp(
      home: AudioEditorScreen(
        mode: 'edit',
        projectDir: fixture.directory,
        isProEntitled: true,
        evaluationController: reopenedController,
      ),
    ));
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['clips'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final reopened = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == clipId);
    expect(reopened['file'], isNot(target['file']));
    expect(reopened['pitch_semitones'], closeTo(targetPitch, 0.0005));

    await reopenedController.undo();
    final reopenedUndone = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == clipId);
    expect(reopenedUndone['file'], target['file']);
    expect(reopenedUndone['pitch_semitones'], closeTo(initialPitch, 0.0005));

    await reopenedController.redo();
    final reopenedRedone = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == clipId);
    expect(reopenedRedone['file'], isNot(target['file']));
    expect(reopenedRedone['pitch_semitones'], closeTo(targetPitch, 0.0005));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 sample replacement shortens only for a shorter source',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture =
        await _openAudioFixture(tester, fixtureId: 'audio_replace_lengths');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final target = clips.first;
    final shortSource = clips[1];
    final clipId = target['clip_id'] as String;
    final initialLength = (target['length_ms'] as num).toDouble();
    final shortLength = (shortSource['length_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_sample_replace',
            'data': <String, dynamic>{
              'operation': 'replace',
              'asset_id': 'fixture-short-replacement',
              'library_path': shortSource['file'],
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clipId,
                'row_index': target['row_index'],
              },
            },
          },
        ],
      ),
    );

    final applied = controller.snapshot();
    final replaced = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == clipId);
    expect(shortLength, lessThan(initialLength));
    expect(replaced['length_ms'], closeTo(shortLength, 1));
    expect(replaced['start_ms'], target['start_ms']);
    expect((applied['clips'] as List), hasLength(clips.length));
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final restored = (controller.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == clipId);
    expect(restored['file'], target['file']);
    expect(restored['length_ms'], closeTo(initialLength, 1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 rolls audio pitch back when a later action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialPitch = (clip['pitch_semitones'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': initialPitch - 2,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
          _renameAction(1, rows[1]['row_id'] as int, ''),
        ],
      ),
    );

    final after = controller.snapshot();
    expect(
      ((after['clips'] as List).first as Map)['pitch_semitones'],
      closeTo(initialPitch, 0.0005),
    );
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 exact trim and onset move share one atomic undo entry',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip = Map<String, dynamic>.from((before['clips'] as List).first);
    final initialStart = (clip['start_ms'] as num).toDouble();
    final initialTrimStart = (clip['trim_start_ms'] as num).toDouble();
    final initialTrimEnd = (clip['trim_end_ms'] as num).toDouble();
    final initialAlignment = (clip['alignment_offset_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;
    final target = <String, dynamic>{
      'scope': 'clip',
      'clip_id': clip['clip_id'],
      'clip_index': 0,
      'row_index': clip['row_index'],
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'trim',
              'delta_trim_start_ms': 100.0,
              'delta_trim_end_ms': -100.0,
              'new_start_ms': initialStart + 100.0,
              'expected_trim_start_ms': initialTrimStart + 100.0,
              'expected_trim_end_ms': initialTrimEnd - 100.0,
              'target': target,
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'move',
              'delta_ms': 500.0,
              'new_alignment_offset_ms': initialAlignment + 500.0,
              'target': target,
            },
          },
        ],
      ),
    );

    var applied = Map<String, dynamic>.from(
      (controller.snapshot()['clips'] as List).first,
    );
    expect(applied['start_ms'], closeTo(initialStart + 600.0, 1.0));
    expect(applied['trim_start_ms'], closeTo(initialTrimStart + 100.0, 1.0));
    expect(applied['trim_end_ms'], closeTo(initialTrimEnd - 100.0, 1.0));
    expect(
      applied['alignment_offset_ms'],
      closeTo(initialAlignment + 500.0, 0.5),
    );
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = Map<String, dynamic>.from(
      (controller.snapshot()['clips'] as List).first,
    );
    expect(undone['start_ms'], closeTo(initialStart, 1.0));
    expect(undone['trim_start_ms'], closeTo(initialTrimStart, 1.0));
    expect(undone['trim_end_ms'], closeTo(initialTrimEnd, 1.0));
    expect(undone['alignment_offset_ms'], closeTo(initialAlignment, 0.5));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = Map<String, dynamic>.from(
      (controller.snapshot()['clips'] as List).first,
    );
    expect(applied['start_ms'], closeTo(initialStart + 600.0, 1.0));
    expect(applied['trim_start_ms'], closeTo(initialTrimStart + 100.0, 1.0));
    expect(applied['trim_end_ms'], closeTo(initialTrimEnd - 100.0, 1.0));
    expect(
      applied['alignment_offset_ms'],
      closeTo(initialAlignment + 500.0, 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 audio stretch applies, reads back, undoes, and redoes',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialLengthMs = (clip['length_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;
    final targetLengthMs = initialLengthMs * 1.5;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'stretch',
              'timeline_duration_ms': targetLengthMs,
              'preserve_pitch': true,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
          _renameAction(1, rows[1]['row_id'] as int, 'Stretched Companion'),
        ],
      ),
    );

    var applied = controller.snapshot();
    var appliedClip = ((applied['clips'] as List).first as Map);
    expect(appliedClip['length_ms'], closeTo(targetLengthMs, 2.0));
    expect(appliedClip['stretch_to_project_tempo'], isTrue);
    expect(appliedClip['tempo_stretch_preserve_pitch'], isTrue);
    expect(appliedClip['tempo_warp_mode'], 'complex');
    expect(_row(applied, 1)['name'], 'Stretched Companion');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    final undoneClip = ((undone['clips'] as List).first as Map);
    expect(undoneClip['length_ms'], closeTo(initialLengthMs, 2.0));
    expect(undoneClip['stretch_to_project_tempo'],
        clip['stretch_to_project_tempo']);
    expect(_row(undone, 1)['name'], 'Synth');
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    appliedClip = ((applied['clips'] as List).first as Map);
    expect(appliedClip['length_ms'], closeTo(targetLengthMs, 2.0));
    expect(_row(applied, 1)['name'], 'Stretched Companion');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 coalesces stretch and tempo-follow in planner order',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialLengthMs = (clip['length_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;
    final targetLengthMs = initialLengthMs * 1.25;

    Map<String, dynamic> clipAction(
      String operation,
      Map<String, dynamic> values,
    ) =>
        <String, dynamic>{
          'type': 'clip_edit',
          'data': <String, dynamic>{
            'operation': operation,
            ...values,
            'target': <String, dynamic>{
              'scope': 'clip',
              'clip_index': 0,
              'clip_id': clip['clip_id'],
              'row_index': clip['row_index'],
            },
          },
        };

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        clipAction('stretch', <String, dynamic>{
          'timeline_duration_ms': targetLengthMs,
          'preserve_pitch': false,
        }),
        clipAction('tempo_follow', <String, dynamic>{
          'mode': 'preserve_pitch',
        }),
      ],
    ));

    var appliedClip = ((controller.snapshot()['clips'] as List).first as Map);
    expect(appliedClip['length_ms'], closeTo(targetLengthMs, 2.0));
    expect(appliedClip['tempo_stretch_preserve_pitch'], isTrue);
    expect(appliedClip['tempo_warp_mode'], 'complex');
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        clipAction('tempo_follow', <String, dynamic>{
          'mode': 'preserve_pitch',
        }),
        clipAction('stretch', <String, dynamic>{
          'timeline_duration_ms': targetLengthMs,
          'preserve_pitch': false,
        }),
      ],
    ));

    appliedClip = ((controller.snapshot()['clips'] as List).first as Map);
    expect(appliedClip['length_ms'], closeTo(targetLengthMs, 2.0));
    expect(appliedClip['tempo_stretch_preserve_pitch'], isFalse);
    expect(appliedClip['tempo_warp_mode'], 'repitch');
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undoneClip = ((controller.snapshot()['clips'] as List).first as Map);
    expect(undoneClip['length_ms'], closeTo(initialLengthMs, 2.0));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 rolls audio stretch back when a later action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialLengthMs = (clip['length_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'operation': 'stretch',
              'timeline_duration_ms': initialLengthMs * 1.5,
              'preserve_pitch': false,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_index': 0,
                'clip_id': clip['clip_id'],
                'row_index': clip['row_index'],
              },
            },
          },
          _renameAction(1, rows[1]['row_id'] as int, ''),
        ],
      ),
    );

    final after = controller.snapshot();
    final afterClip = ((after['clips'] as List).first as Map);
    expect(afterClip['length_ms'], closeTo(initialLengthMs, 2.0));
    expect(afterClip['stretch_to_project_tempo'],
        clip['stretch_to_project_tempo']);
    expect(afterClip['tempo_stretch_preserve_pitch'],
        clip['tempo_stretch_preserve_pitch']);
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 detected source, project tempo, and follow share one undo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clip = ((before['clips'] as List).first as Map<String, dynamic>);
    final initialSourceTempo = (clip['source_tempo_bpm'] as num).toDouble();
    final initialProjectTempo = (before['tempo_bpm'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;

    Map<String, dynamic> clipAction(
      String operation,
      Map<String, dynamic> values,
    ) =>
        <String, dynamic>{
          'type': 'clip_edit',
          'data': <String, dynamic>{
            'operation': operation,
            ...values,
            'target': <String, dynamic>{
              'scope': 'clip',
              'clip_index': 0,
              'clip_id': clip['clip_id'],
              'row_index': clip['row_index'],
            },
          },
        };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          clipAction('set_source_tempo', <String, dynamic>{
            'source_tempo_bpm': 100.0,
          }),
          clipAction('set_source_tempo', <String, dynamic>{
            'source_tempo_bpm': 90.0,
          }),
          <String, dynamic>{
            'type': 'project_edit',
            'data': <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': 100.0,
              'time_stretch_audio': false,
              'preserve_pitch': true,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
          <String, dynamic>{
            'type': 'project_edit',
            'data': <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': 90.0,
              'time_stretch_audio': false,
              'preserve_pitch': true,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
          clipAction('tempo_follow', <String, dynamic>{
            'mode': 'preserve_pitch',
          }),
          _renameAction(1, rows[1]['row_id'] as int, 'Tempo Companion'),
        ],
      ),
    );

    var applied = controller.snapshot();
    var appliedClip = ((applied['clips'] as List).first as Map);
    expect(appliedClip['source_tempo_bpm'], closeTo(90.0, 0.0005));
    expect(applied['tempo_bpm'], closeTo(90.0, 0.0005));
    expect(appliedClip['stretch_to_project_tempo'], isTrue);
    expect(appliedClip['tempo_stretch_preserve_pitch'], isTrue);
    expect(appliedClip['tempo_warp_mode'], 'complex');
    expect(_row(applied, 1)['name'], 'Tempo Companion');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    final undoneClip = ((undone['clips'] as List).first as Map);
    expect(
      undoneClip['source_tempo_bpm'],
      closeTo(initialSourceTempo, 0.0005),
    );
    expect(undone['tempo_bpm'], closeTo(initialProjectTempo, 0.0005));
    expect(
      undoneClip['stretch_to_project_tempo'],
      clip['stretch_to_project_tempo'],
    );
    expect(_row(undone, 1)['name'], 'Synth');
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    appliedClip = ((applied['clips'] as List).first as Map);
    expect(appliedClip['source_tempo_bpm'], closeTo(90.0, 0.0005));
    expect(applied['tempo_bpm'], closeTo(90.0, 0.0005));
    expect(appliedClip['stretch_to_project_tempo'], isTrue);
    expect(_row(applied, 1)['name'], 'Tempo Companion');
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 core audio clip edits stay atomic across index shifts',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _clipAction(
          'trim',
          clips[0],
          rows[0],
          extra: <String, dynamic>{
            'delta_trim_start_ms': 250.0,
            'delta_trim_end_ms': -200.0,
            'new_start_ms': 250.0,
          },
        ),
        _clipAction(
          'cut',
          clips[1],
          rows[1],
          extra: const <String, dynamic>{'cut_ms': 600.0},
        ),
        _clipAction(
          'duplicate',
          clips[0],
          rows[0],
          extra: const <String, dynamic>{
            'paste_start_ms': 2000.0,
            'row_index': 0,
            'new_row_index': 0,
          },
        ),
        _clipAction('delete', clips[1], rows[1]),
      ],
    ));

    final applied = controller.snapshot();
    final appliedClips =
        (applied['clips'] as List).cast<Map<String, dynamic>>();
    final trimmed = _clip(applied, clips[0]['clip_id'] as String);
    expect(trimmed['start_ms'], closeTo(250.0, 1.0));
    expect(trimmed['length_ms'], closeTo(750.0, 1.0));
    expect(appliedClips, hasLength(3));
    expect(
      appliedClips.any((clip) => clip['clip_id'] == clips[1]['clip_id']),
      isFalse,
    );
    expect(
      appliedClips.where(
        (clip) => clip['file'] == clips[1]['file'] && clip['start_ms'] == 600.0,
      ),
      hasLength(1),
    );
    expect(
        appliedClips.where((clip) =>
            clip['file'] == clips[0]['file'] && clip['start_ms'] == 2000.0),
        hasLength(1));
    final duplicatedAudio = appliedClips.singleWhere((clip) =>
        clip['file'] == clips[0]['file'] && clip['start_ms'] == 2000.0);
    final duplicatedAudioId = duplicatedAudio['clip_id'] as String;
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect((undone['clips'] as List), hasLength(2));
    expect(_clip(undone, clips[0]['clip_id'] as String)['start_ms'], 0.0);
    expect(_clip(undone, clips[0]['clip_id'] as String)['length_ms'], 1200.0);
    expect(_clip(undone, clips[1]['clip_id'] as String), isNotEmpty);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect((redone['clips'] as List), hasLength(3));
    expect(
      _clip(redone, clips[0]['clip_id'] as String)['start_ms'],
      closeTo(250.0, 1.0),
    );
    expect(
      (redone['clips'] as List).cast<Map>().any(
        (clip) => clip['clip_id'] == clips[1]['clip_id'],
      ),
      isFalse,
    );
    final redoneAudioDuplicate = _clip(redone, duplicatedAudioId);
    expect(redoneAudioDuplicate['file'], duplicatedAudio['file']);
    expect(redoneAudioDuplicate['start_ms'], duplicatedAudio['start_ms']);
    expect(redoneAudioDuplicate['length_ms'], duplicatedAudio['length_ms']);
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 core MIDI clip split duplicate and delete is reversible',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row =
        ((before['rows'] as List).single as Map).cast<String, dynamic>();
    final source =
        ((before['clips'] as List).single as Map).cast<String, dynamic>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _clipAction(
          'cut',
          source,
          row,
          extra: const <String, dynamic>{'cut_ms': 600.0},
        ),
        _clipAction(
          'duplicate',
          source,
          row,
          extra: const <String, dynamic>{
            'paste_start_ms': 1800.0,
            'row_index': 0,
            'new_row_index': 0,
          },
        ),
        _clipAction('delete', source, row),
      ],
    ));

    final applied = controller.snapshot();
    expect((applied['clips'] as List), hasLength(2));
    expect(
        (applied['clips'] as List)
            .cast<Map>()
            .every((clip) => clip['kind'] == 'midi'),
        isTrue);
    expect(
        (applied['clips'] as List)
            .cast<Map>()
            .any((clip) => clip['clip_id'] == source['clip_id']),
        isFalse);
    final generatedMidiClips = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .where((clip) => clip['clip_id'] != source['clip_id'])
        .toList(growable: false);
    expect(generatedMidiClips, hasLength(2));
    final generatedMidiIds =
        generatedMidiClips.map((clip) => clip['clip_id'] as String).toSet();
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect((undone['clips'] as List), hasLength(1));
    expect(_clip(undone, source['clip_id'] as String), isNotEmpty);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect((redone['clips'] as List), hasLength(2));
    expect(
      (redone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .map((clip) => clip['clip_id'] as String)
          .toSet(),
      generatedMidiIds,
    );
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 rolls a trim back when a later clip bundle action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _clipAction(
          'trim',
          clips[0],
          rows[0],
          extra: <String, dynamic>{
            'delta_trim_start_ms': 250.0,
            'delta_trim_end_ms': 0.0,
            'new_start_ms': 250.0,
          },
        ),
        _renameAction(1, rows[1]['row_id'] as int, ''),
      ],
    ));

    final after = controller.snapshot();
    final restored = _clip(after, clips[0]['clip_id'] as String);
    expect(restored['start_ms'], 0.0);
    expect(restored['length_ms'], 1200.0);
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 mix actions share one transaction with direct commands',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final initialGain = rows[0]['gain_ui'] as double;
    final referenceBefore = Map<String, dynamic>.from(rows[1]);
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'mix',
              'protected_reference_row_index': 1,
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'set_row_gain',
                  'data': <String, dynamic>{
                    'row': 0,
                    'mode': 'delta',
                    'delta': 0.2,
                  },
                },
              ],
            },
          },
          _muteAction(0, rows[0]['row_id'] as int),
        ],
      ),
    );

    final applied = controller.snapshot();
    expect(_row(applied, 0)['gain_ui'], closeTo(initialGain + 0.2, 0.00001));
    expect(_row(applied, 0)['muted'], isTrue);
    expect(_row(applied, 1), referenceBefore);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = controller.snapshot();
    expect(_row(undone, 0)['gain_ui'], closeTo(initialGain, 0.00001));
    expect(_row(undone, 0)['muted'], isFalse);
    expect(_row(undone, 1), referenceBefore);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(_row(redone, 0)['gain_ui'], closeTo(initialGain + 0.2, 0.00001));
    expect(_row(redone, 0)['muted'], isTrue);
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'mix-fail',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'set_row_gain',
                  'data': <String, dynamic>{
                    'row': 0,
                    'mode': 'delta',
                    'delta': 0.2,
                  },
                },
              ],
            },
          },
          _renameAction(1, rows[1]['row_id'] as int, ''),
        ],
      ),
    );
    final rolledBack = controller.snapshot();
    expect(_row(rolledBack, 0)['gain_ui'], closeTo(initialGain, 0.00001));
    expect(rolledBack['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 row mix effects persist through one-step undo and redo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'mix-effects',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'ensure_effect',
                  'data': <String, dynamic>{
                    'row': 0,
                    'effect_name_contains': 'EQ 3-Band',
                  },
                },
              ],
            },
          },
        ],
      ),
    );

    Map<String, dynamic> snapshot = controller.snapshot();
    expect(_effectNames(_row(snapshot, 0)['effects']),
        contains(contains('EQ 3-Band')));
    expect(snapshot['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    await _pumpFor(tester, const Duration(seconds: 2));
    snapshot = controller.snapshot();
    expect(_effectNames(_row(snapshot, 0)['effects']), isEmpty,
        reason: 'Row effects must be removed by the compound undo.');
    expect(snapshot['undo_depth'], initialUndoDepth);

    await controller.redo();
    await _pumpUntil(tester, () {
      snapshot = controller.snapshot();
      return _effectNames(_row(snapshot, 0)['effects'])
          .any((name) => name.contains('EQ 3-Band'));
    });
    expect(snapshot['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 mix removal is already satisfied when effect is absent',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'remove-absent-effects',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'delete_effect',
                  'data': <String, dynamic>{
                    'row': 0,
                    'effect_name_contains': 'Clipper',
                  },
                },
                <String, dynamic>{
                  'type': 'delete_master_effect',
                  'data': <String, dynamic>{'effect_name_contains': 'Limiter'},
                },
              ],
            },
          },
        ],
      ),
    );

    final after = controller.snapshot();
    expect(_effectNames(_row(after, 0)['effects']), isEmpty);
    expect(_effectNames(after['master_effects']), isEmpty);
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 resolves and verifies exact row mix effect parameters by ID',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final initialUndoDepth = before['undo_depth'] as int;

      Map<String, dynamic> mixAction() => <String, dynamic>{
        'type': 'v3_mix_actions',
        'data': <String, dynamic>{
          'command_id': 'warm-row',
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'ensure_effect',
              'data': <String, dynamic>{
                'row': 0,
                'effect_name_contains': 'EQ 3-Band',
              },
            },
            <String, dynamic>{
              'type': 'adjust_effect_param_by_name',
              'data': <String, dynamic>{
                'row': 0,
                'effect_name_contains': 'EQ 3-Band',
                'param_name_contains_any': <String>['Low Gain', 'Low'],
                'mode': 'delta',
                'delta': 2.0,
                'skip_if_missing_effect': false,
              },
            },
            <String, dynamic>{
              'type': 'adjust_effect_param_by_name',
              'data': <String, dynamic>{
                'row': 0,
                'effect_name_contains': 'EQ 3-Band',
                'param_name_contains_any': <String>['Low Gain', 'Low'],
                'mode': 'delta',
                'delta': 2.5,
                'skip_if_missing_effect': false,
              },
            },
            <String, dynamic>{
              'type': 'adjust_effect_param_by_name',
              'data': <String, dynamic>{
                'row': 0,
                'effect_name_contains': 'EQ 3-Band',
                'param_name_contains_any': <String>['Mid Gain', 'Mid'],
                'mode': 'delta',
                'delta': 0.625,
                'skip_if_missing_effect': false,
              },
            },
          ],
        },
      };

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[mixAction()],
    ));

      var applied = controller.snapshot();
      var eq = (_row(applied, 0)['effects'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((effect) => effect['display_name'] == 'EQ 3-Band');
      expect((eq['params'] as Map)['Low Gain'], closeTo(4.5, 0.06));
      expect((eq['params'] as Map)['Mid Gain'], closeTo(0.625, 0.13));
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      var undone = controller.snapshot();
      expect(_effectNames(_row(undone, 0)['effects']), isEmpty);
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      applied = controller.snapshot();
      eq = (_row(applied, 0)['effects'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((effect) => effect['display_name'] == 'EQ 3-Band');
      expect((eq['params'] as Map)['Low Gain'], closeTo(4.5, 0.06));
      expect((eq['params'] as Map)['Mid Gain'], closeTo(0.625, 0.13));

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            mixAction(),
            _renameAction(1, rows[1]['row_id'] as int, ''),
          ],
        ),
      );
      undone = controller.snapshot();
      expect(_effectNames(_row(undone, 0)['effects']), isEmpty);
      expect(undone['undo_depth'], initialUndoDepth);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 applies punch compression and master safety as one reversible mix',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

      Map<String, dynamic> rowParam(String name, double value) =>
          <String, dynamic>{
            'type': 'adjust_effect_param_by_name',
            'data': <String, dynamic>{
              'row': 0,
              'effect_name_contains': 'Compressor',
              'param_name_contains_any': <String>[name],
              'mode': 'set',
              'value': value,
              'skip_if_missing_effect': false,
            },
          };
      Map<String, dynamic> masterParam(String name, double value) =>
          <String, dynamic>{
            'type': 'adjust_master_effect_param_by_name',
            'data': <String, dynamic>{
              'effect_name_contains': 'Limiter',
              'param_name_contains_any': <String>[name],
              'mode': 'set',
              'value': value,
              'skip_if_missing_effect': false,
            },
          };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_mix_actions',
              'data': <String, dynamic>{
                'command_id': 'punch-and-protect',
                'actions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'ensure_effect',
                    'data': const <String, dynamic>{
                      'row': 0,
                      'effect_name_contains': 'Compressor',
                    },
                  },
                  rowParam('Threshold', -17.5),
                  rowParam('Ratio', 4.0),
                  rowParam('Attack', 12.0),
                  rowParam('Release', 90.0),
                  rowParam('Makeup', 1.2),
                  rowParam('Mix', 62.0),
                  <String, dynamic>{
                    'type': 'ensure_master_effect',
                    'data': const <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                    },
                  },
                  masterParam('Threshold', -3.0),
                  masterParam('Release', 90.0),
                  masterParam('Ceiling', -1.0),
                ],
              },
            },
          ],
        ),
      );

      var snapshot = controller.snapshot();
      final compressor = (_row(snapshot, 0)['effects'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((effect) => effect['display_name'] == 'Compressor');
      final limiter = (snapshot['master_effects'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((effect) => effect['display_name'] == 'Limiter');
      expect(
        ((compressor['params'] as Map)['Threshold'] as num).toDouble(),
        closeTo(-17.5, 0.051),
      );
      expect(
        ((compressor['params'] as Map)['Mix'] as num).toDouble(),
        closeTo(62.0, 0.501),
      );
      expect(
        ((limiter['params'] as Map)['Ceiling'] as num).toDouble(),
        closeTo(-1.0, 0.051),
      );
      expect(snapshot['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      snapshot = controller.snapshot();
      expect(_effectNames(_row(snapshot, 0)['effects']), isEmpty);
      expect(_effectNames(snapshot['master_effects']), isEmpty);
      expect(snapshot['undo_depth'], initialUndoDepth);

      await controller.redo();
      snapshot = controller.snapshot();
      expect(
        _effectNames(_row(snapshot, 0)['effects']),
        contains(contains('Compressor')),
      );
      expect(
        _effectNames(snapshot['master_effects']),
        contains(contains('Limiter')),
      );
      expect(snapshot['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 master mix effects persist through undo and redo', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'master-mix-effect',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'ensure_master_effect',
                  'data': <String, dynamic>{
                    'effect_name_contains': 'Compressor',
                  },
                },
              ],
            },
          },
        ],
      ),
    );

    var snapshot = controller.snapshot();
    expect(
      _effectNames(snapshot['master_effects']),
      contains(contains('Compressor')),
    );
    expect(snapshot['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    snapshot = controller.snapshot();
    expect(_effectNames(snapshot['master_effects']), isEmpty);
    expect(snapshot['undo_depth'], initialUndoDepth);

    await controller.redo();
    snapshot = controller.snapshot();
    expect(
      _effectNames(snapshot['master_effects']),
      contains(contains('Compressor')),
    );
    expect(snapshot['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 master mix parameter readback survives later chain insertion',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_mix_actions',
              'data': <String, dynamic>{
                'command_id': 'master-identity-readback',
                'actions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'ensure_master_effect',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Compressor',
                    },
                  },
                  <String, dynamic>{
                    'type': 'adjust_master_effect_param_by_name',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Compressor',
                      'param_name_contains_any': <String>['Threshold'],
                      'mode': 'set',
                      'value': -10.0,
                      'skip_if_missing_effect': false,
                    },
                  },
                  <String, dynamic>{
                    'type': 'ensure_master_effect',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'EQ Parametric',
                    },
                  },
                  <String, dynamic>{
                    'type': 'ensure_master_effect',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                    },
                  },
                  <String, dynamic>{
                    'type': 'adjust_master_effect_param_by_name',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                      'param_name_contains_any': <String>['Ceiling'],
                      'mode': 'set',
                      'value': -0.2,
                      'skip_if_missing_effect': false,
                    },
                  },
                ],
              },
            },
          ],
        ),
      );

      var snapshot = controller.snapshot();
      expect(
        _effectNames(snapshot['master_effects']),
        containsAll(<Matcher>[
          contains('Compressor'),
          contains('EQ Parametric'),
          contains('Limiter'),
        ]),
      );
      final appliedMasterEffects = (snapshot['master_effects'] as List)
          .cast<Map<String, dynamic>>();
      final appliedCompressor = appliedMasterEffects.singleWhere(
        (effect) => effect['display_name'] == 'Compressor',
      );
      final appliedLimiter = appliedMasterEffects.singleWhere(
        (effect) => effect['display_name'] == 'Limiter',
      );
      final appliedThreshold =
          ((appliedCompressor['params'] as Map)['Threshold'] as num).toDouble();
      final appliedCeiling =
          ((appliedLimiter['params'] as Map)['Ceiling'] as num).toDouble();
      expect(snapshot['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      snapshot = controller.snapshot();
      expect(_effectNames(snapshot['master_effects']), isEmpty);

      await controller.redo();
      snapshot = controller.snapshot();
      expect(
        _effectNames(snapshot['master_effects']),
        containsAll(<Matcher>[
          contains('Compressor'),
          contains('EQ Parametric'),
          contains('Limiter'),
        ]),
      );
      final redoneMasterEffects = (snapshot['master_effects'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        ((redoneMasterEffects.singleWhere(
                      (effect) => effect['display_name'] == 'Compressor',
                    )['params']
                    as Map)['Threshold']
                as num)
            .toDouble(),
        closeTo(appliedThreshold, 0.00001),
      );
      expect(
        ((redoneMasterEffects.singleWhere(
                      (effect) => effect['display_name'] == 'Limiter',
                    )['params']
                    as Map)['Ceiling']
                as num)
            .toDouble(),
        closeTo(appliedCeiling, 0.00001),
      );
      expect(snapshot['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 materialized master polish applies every parameter strictly',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'materialized-master-polish',
                'operation': 'apply_goal',
                'target': <String, dynamic>{'scope': 'master'},
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'compressor',
                    'direction': 'up',
                    'descriptor': null,
                  },
                  <String, dynamic>{
                    'kind': 'eq',
                    'direction': null,
                    'descriptor': 'dull_fix',
                  },
                  <String, dynamic>{
                    'kind': 'limiter',
                    'direction': 'up',
                    'descriptor': null,
                  },
                ],
                'intensity': 0.45,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>['polished', 'clean', 'cohesive'],
                'reset_fx': false,
                'reference': null,
              },
            },
          ],
        ),
      );

      final applied = controller.snapshot();
      expect(
        _effectNames(applied['master_effects']),
        containsAll(<Matcher>[
          contains('Compressor'),
          contains('EQ Parametric'),
          contains('Limiter'),
        ]),
      );
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['master_effects'], before['master_effects']);
      await controller.redo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['master_effects'], applied['master_effects']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 master effect removal restores exact parameters on Undo', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'configure-master-limiter',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'ensure_master_effect',
                  'data': <String, dynamic>{'effect_name_contains': 'Limiter'},
                },
                <String, dynamic>{
                  'type': 'adjust_master_effect_param_by_name',
                  'data': <String, dynamic>{
                    'effect_name_contains': 'Limiter',
                    'param_name_contains_any': <String>['Release'],
                    'mode': 'set',
                    'value': 144.0,
                    'skip_if_missing_effect': false,
                  },
                },
                <String, dynamic>{
                  'type': 'adjust_master_effect_param_by_name',
                  'data': <String, dynamic>{
                    'effect_name_contains': 'Limiter',
                    'param_name_contains_any': <String>['Ceiling'],
                    'mode': 'set',
                    'value': -0.2,
                    'skip_if_missing_effect': false,
                  },
                },
              ],
            },
          },
        ],
      ),
    );
    final configured = controller.snapshot();
    final configuredLimiter = (configured['master_effects'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((effect) => effect['display_name'] == 'Limiter');
    final configuredParams = configuredLimiter['params'] as Map;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_mix_actions',
            'data': <String, dynamic>{
              'command_id': 'remove-master-limiter',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'delete_master_effect',
                  'data': <String, dynamic>{'effect_name_contains': 'Limiter'},
                },
              ],
            },
          },
        ],
      ),
    );
    expect(
      _effectNames(controller.snapshot()['master_effects']),
      isNot(contains(contains('Limiter'))),
    );

    await controller.undo();
    final restored = controller.snapshot();
    final restoredLimiter = (restored['master_effects'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((effect) => effect['display_name'] == 'Limiter');
    final restoredParams = restoredLimiter['params'] as Map;
    expect(
      (restoredParams['Release'] as num).toDouble(),
      closeTo((configuredParams['Release'] as num).toDouble(), 0.00001),
    );
    expect(
      (restoredParams['Ceiling'] as num).toDouble(),
      closeTo((configuredParams['Ceiling'] as num).toDouble(), 0.00001),
    );

    await controller.redo();
    expect(
      _effectNames(controller.snapshot()['master_effects']),
      isNot(contains(contains('Limiter'))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 final verification drops superseded master parameter expectations',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_mix_actions',
              'data': <String, dynamic>{
                'command_id': 'configure-then-remove-master-limiter',
                'actions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'ensure_master_effect',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                    },
                  },
                  <String, dynamic>{
                    'type': 'adjust_master_effect_param_by_name',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                      'param_name_contains_any': <String>['Release'],
                      'mode': 'set',
                      'value': 80.0,
                      'skip_if_missing_effect': false,
                    },
                  },
                  <String, dynamic>{
                    'type': 'delete_master_effect',
                    'data': <String, dynamic>{
                      'effect_name_contains': 'Limiter',
                    },
                  },
                ],
              },
            },
          ],
        ),
      );
      expect(
        _effectNames(controller.snapshot()['master_effects']),
        isNot(contains(contains('Limiter'))),
      );

    await controller.undo();
    expect(controller.snapshot()['master_effects'], before['master_effects']);

    await controller.redo();
    expect(
      _effectNames(controller.snapshot()['master_effects']),
      isNot(contains(contains('Limiter'))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 verifies exact sample placement automation and effect parameters',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final initialClipCount = clips.length;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 2400.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'automation_edit',
              'data': <String, dynamic>{
                'operation': 'set_points',
                'value_mode': 'normalized',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': rows[0]['row_id'],
                  'automation_target_id': 'volume',
                },
                'points': const <Map<String, dynamic>>[
                  <String, dynamic>{'time_ms': 0.0, 'value': 0.0},
                  <String, dynamic>{'time_ms': 2000.0, 'value': 1.0},
                ],
              },
            },
            <String, dynamic>{
              'type': 'v3_effect_configure',
              'data': <String, dynamic>{
                'operation': 'ensure_configured',
                'effect_id': 'EQ 3-Band',
                'parameters': const <String, dynamic>{'Low Gain': 0.75},
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': rows[0]['row_id'],
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      var applied = controller.snapshot();
      final addedSamples = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) =>
                clip['row_index'] == 1 &&
                !clips.any(
                  (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
                ) &&
                ((clip['start_ms'] as num).toDouble() - 2400.0).abs() <= 1.0,
          )
          .toList(growable: false);
      expect(addedSamples, hasLength(1));
      expect(_row(applied, 0)['automation'], <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'value': 0.0},
        <String, dynamic>{'x': 2000.0, 'value': 1.0},
      ]);
      final eq = (_row(applied, 0)['effects'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((effect) => effect['display_name'] == 'EQ 3-Band');
      expect((eq['params'] as Map)['Low Gain'], closeTo(12.0, 0.13));
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      final undone = controller.snapshot();
      expect((undone['clips'] as List), hasLength(initialClipCount));
      expect(_effectNames(_row(undone, 0)['effects']), isEmpty);
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      applied = controller.snapshot();
      expect((applied['clips'] as List), hasLength(initialClipCount + 1));
      expect(_row(applied, 0)['automation'], <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'value': 0.0},
        <String, dynamic>{'x': 2000.0, 'value': 1.0},
      ]);
      expect(
        _effectNames(_row(applied, 0)['effects']),
        contains(contains('EQ 3-Band')),
      );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 effect-instance edits target, undo, and redo exact plugins',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final rows =
        (controller.snapshot()['rows'] as List).cast<Map<String, dynamic>>();
    final rowId = rows[0]['row_id'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_effect_configure',
            'data': <String, dynamic>{
              'operation': 'ensure_configured',
              'effect_id': 'EQ 3-Band',
              'parameters': const <String, dynamic>{},
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': rowId,
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_effect_configure',
            'data': <String, dynamic>{
              'operation': 'ensure_configured',
              'effect_id': 'Compressor',
              'parameters': const <String, dynamic>{},
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': rowId,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    final before = await controller.effectChain(0);
    expect(before, hasLength(2));
    final eq = before.singleWhere(
      (effect) => effect['display_name'] == 'EQ 3-Band',
    );
    final compressor = before.singleWhere(
      (effect) => effect['display_name'] == 'Compressor',
    );
    final initialUndoDepth = controller.snapshot()['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_effect_instance_edit',
            'data': <String, dynamic>{
              'operation': 'set_bypassed',
              'effect_instance_id': eq['effect_instance_id'],
              'effect_id': eq['effect_id'],
              'effect_index': 0,
              'bypassed': true,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': rowId,
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_effect_instance_edit',
            'data': <String, dynamic>{
              'operation': 'remove',
              'effect_instance_id': compressor['effect_instance_id'],
              'effect_id': compressor['effect_id'],
              'effect_index': 1,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': rowId,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    var applied = await controller.effectChain(0);
    expect(applied, hasLength(1));
    expect(applied.single['effect_id'], eq['effect_id']);
    expect(applied.single['bypassed'], isTrue);
    var persistedEffects = (_row(controller.snapshot(), 0)['effects'] as List)
        .cast<Map<String, dynamic>>();
    expect(persistedEffects, hasLength(1));
    expect(persistedEffects.single['effect_id'], eq['effect_id']);
    expect(persistedEffects.single['bypassed'], isTrue);
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    await _pumpFor(tester, const Duration(seconds: 2));
    final undone = await controller.effectChain(0);
    expect(undone, hasLength(2));
    expect(undone.first['bypassed'], isFalse);
    persistedEffects = (_row(controller.snapshot(), 0)['effects'] as List)
        .cast<Map<String, dynamic>>();
    expect(persistedEffects, hasLength(2));
    expect(persistedEffects.first['bypassed'], isFalse);

    await controller.redo();
    await _pumpFor(tester, const Duration(seconds: 2));
    applied = await controller.effectChain(0);
    expect(applied, hasLength(1));
    expect(applied.single['bypassed'], isTrue);
    persistedEffects = (_row(controller.snapshot(), 0)['effects'] as List)
        .cast<Map<String, dynamic>>();
    expect(persistedEffects, hasLength(1));
    expect(persistedEffects.single['bypassed'], isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 MIDI transpose expectations follow ordered clamp semantics',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip =
        ((before['clips'] as List).single as Map).cast<String, dynamic>();
    final initialPitches = (clip['midi_notes'] as List)
        .cast<Map<String, dynamic>>()
        .map((note) => note['pitch'] as int)
        .toList(growable: false);
    final initialUndoDepth = before['undo_depth'] as int;

    Map<String, dynamic> transpose(int semitones) => <String, dynamic>{
          'type': 'midi_compose',
          'data': <String, dynamic>{
            'operation': 'transpose_notes',
            'semitones': semitones,
            'target': <String, dynamic>{
              'scope': 'clip',
              'clip_index': 0,
              'clip_id': clip['clip_id'],
            },
          },
        };

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        transpose(100),
        transpose(-100),
      ],
    ));

    final applied = controller.snapshot();
    final finalPitches =
        ((_clip(applied, clip['clip_id'] as String)['midi_notes'] as List)
                .cast<Map<String, dynamic>>())
            .map((note) => note['pitch'] as int)
            .toList(growable: false);
    expect(finalPitches, everyElement(27));
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undonePitches =
        ((_clip(controller.snapshot(), clip['clip_id'] as String)['midi_notes']
                    as List)
                .cast<Map<String, dynamic>>())
            .map((note) => note['pitch'] as int)
            .toList(growable: false);
    expect(undonePitches, initialPitches);

    await controller.redo();
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 exact MIDI replacements verify final state and undo once',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip =
        ((before['clips'] as List).single as Map).cast<String, dynamic>();
    final initialNotes =
        (clip['midi_notes'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;
    final firstNotes = const <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];
    final finalNotes = const <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 64,
        'start_beat': 0.0,
        'length_beats': 0.5,
        'velocity': 0.7,
      },
      <String, dynamic>{
        'pitch': 67,
        'start_beat': 1.0,
        'length_beats': 1.0,
        'velocity': 0.6,
      },
    ];

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _midiReplaceAction(clip, firstNotes),
        _midiReplaceAction(clip, finalNotes),
      ],
    ));

    var applied = _clip(controller.snapshot(), clip['clip_id'] as String);
    expect(applied['midi_notes'], finalNotes);
    expect(applied['start_ms'], clip['start_ms']);
    expect(applied['length_ms'], clip['length_ms']);
    expect(applied['instrument_id'], clip['instrument_id']);
    expect(applied['stretch_to_tempo'], clip['stretch_to_tempo']);
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(
      _clip(controller.snapshot(), clip['clip_id'] as String)['midi_notes'],
      initialNotes,
    );
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = _clip(controller.snapshot(), clip['clip_id'] as String);
    expect(applied['midi_notes'], finalNotes);
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 MIDI append extends length and restores it with Undo Redo',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture =
        await _openAudioFixture(tester, fixtureId: 'midi_append_live');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip = _clip(before, 'append_midi');
    final initialNotes =
        (clip['midi_notes'] as List).cast<Map<String, dynamic>>();
    final initialLengthMs = (clip['length_ms'] as num).toDouble();
    final initialTempoState = <String, dynamic>{
      'source_tempo_bpm': clip['source_tempo_bpm'],
      'stretch_to_tempo': clip['stretch_to_tempo'],
      'tempo_stretch_preserve_pitch': clip['tempo_stretch_preserve_pitch'],
      'tempo_warp_mode': clip['tempo_warp_mode'],
    };
    final tempo = (before['tempo_bpm'] as num).toDouble();
    final initialLengthBeats = initialLengthMs * tempo / 60000.0;
    final finalLengthBeats = initialLengthBeats + 4.0;
    final finalNotes = <Map<String, dynamic>>[
      ...initialNotes,
      <String, dynamic>{
        'pitch': 60,
        'start_beat': initialLengthBeats + 1.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 63,
        'start_beat': initialLengthBeats + 2.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 67,
        'start_beat': initialLengthBeats + 3.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _midiReplaceAction(
          clip,
          finalNotes,
          finalLengthBeats: finalLengthBeats,
        ),
      ],
    ));

    var applied = _clip(controller.snapshot(), clip['clip_id'] as String);
    expect(applied['midi_notes'], finalNotes);
    expect(
      (applied['length_ms'] as num).toDouble(),
      closeTo(finalLengthBeats * 60000.0 / tempo, 2.0),
    );
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    final undone = _clip(controller.snapshot(), clip['clip_id'] as String);
    expect(undone['midi_notes'], initialNotes);
    expect((undone['length_ms'] as num).toDouble(), initialLengthMs);
    for (final entry in initialTempoState.entries) {
      expect(undone[entry.key], entry.value);
    }
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = _clip(controller.snapshot(), clip['clip_id'] as String);
    expect(applied['midi_notes'], finalNotes);
    expect(
      (applied['length_ms'] as num).toDouble(),
      closeTo(finalLengthBeats * 60000.0 / tempo, 2.0),
    );
    for (final entry in initialTempoState.entries) {
      expect(applied[entry.key], entry.value);
    }
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 MIDI edit rolls back completely when a later action fails',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clip =
        ((before['clips'] as List).single as Map).cast<String, dynamic>();
    final row =
        ((before['rows'] as List).single as Map).cast<String, dynamic>();
    final initialNotes =
        (clip['midi_notes'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        _midiReplaceAction(
          clip,
          const <Map<String, dynamic>>[
            <String, dynamic>{
              'pitch': 72,
              'start_beat': 0.0,
              'length_beats': 0.25,
              'velocity': 0.9,
            },
          ],
        ),
        _renameAction(0, row['row_id'] as int, ''),
      ],
    ));

    final rolledBack = controller.snapshot();
    expect(
      _clip(rolledBack, clip['clip_id'] as String)['midi_notes'],
      initialNotes,
    );
    expect(rolledBack['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 repeated automation verifies only the final point set',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).first as Map<String, dynamic>);
    final initialUndoDepth = before['undo_depth'] as int;

    Map<String, dynamic> automation(List<Map<String, dynamic>> points) =>
        <String, dynamic>{
          'type': 'automation_edit',
          'data': <String, dynamic>{
            'operation': 'set_points',
            'value_mode': 'normalized',
            'target': <String, dynamic>{
              'scope': 'row',
              'row_index': 0,
              'row_id': row['row_id'],
              'automation_target_id': 'volume',
            },
            'points': points,
          },
        };

    const finalPoints = <Map<String, dynamic>>[
      <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
      <String, dynamic>{'time_ms': 1500.0, 'value': 0.75},
    ];
    await controller.executeV3Handoff(_handoff(
      digest: controller.stateDigest,
      actions: <Map<String, dynamic>>[
        automation(const <Map<String, dynamic>>[
          <String, dynamic>{'time_ms': 0.0, 'value': 0.0},
          <String, dynamic>{'time_ms': 1000.0, 'value': 1.0},
        ]),
        automation(finalPoints),
      ],
    ));

    expect(
        _row(controller.snapshot(), 0)['automation'],
        const <Map<String, dynamic>>[
          <String, dynamic>{'x': 0.0, 'value': 0.25},
          <String, dynamic>{'x': 1500.0, 'value': 0.75},
        ]);
    expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);
    await controller.redo();
    expect(_row(controller.snapshot(), 0)['automation'], isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 exact automation set clear Undo Redo and late rollback are atomic',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).first as Map<String, dynamic>);
      final rowId = row['row_id'] as int;
      final initialAutomation = (row['automation'] as List)
          .whereType<Map>()
          .map((point) => Map<String, dynamic>.from(point))
          .toList(growable: false);
      final initialUndoDepth = before['undo_depth'] as int;

      Map<String, dynamic> exactAutomation({
        required String operation,
        List<Map<String, dynamic>> points = const <Map<String, dynamic>>[],
      }) => <String, dynamic>{
        'type': 'v3_automation_points',
        'data': <String, dynamic>{
          'operation': operation,
          'target': <String, dynamic>{
            'scope': 'row',
            'row_id': rowId,
            'row_index': 0,
            'automation_target_id': 'volume',
          },
          'points': points,
        },
      };

      const finalInputPoints = <Map<String, dynamic>>[
        <String, dynamic>{'time_ms': 0.0, 'value': 0.2},
        <String, dynamic>{'time_ms': 1000.0, 'value': 0.6},
        <String, dynamic>{'time_ms': 2000.0, 'value': 0.9},
      ];
      const finalPoints = <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'value': 0.2},
        <String, dynamic>{'x': 1000.0, 'value': 0.6},
        <String, dynamic>{'x': 2000.0, 'value': 0.9},
      ];
      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            exactAutomation(operation: 'set_points', points: finalInputPoints),
          ],
        ),
      );
      expect(_row(controller.snapshot(), 0)['automation'], finalPoints);
      expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      expect(_row(controller.snapshot(), 0)['automation'], initialAutomation);
      await controller.redo();
      expect(_row(controller.snapshot(), 0)['automation'], finalPoints);

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[exactAutomation(operation: 'clear')],
        ),
      );
      final cleared = _row(controller.snapshot(), 0)['automation'] as List;
      expect(cleared, hasLength(2));
      expect(cleared.every((point) => (point as Map)['value'] == 1.0), isTrue);

      final beforeFailure = controller.snapshot();
      final beforeFailureUndoDepth = beforeFailure['undo_depth'];
      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            exactAutomation(operation: 'set_points', points: finalInputPoints),
            _renameAction(0, rowId, ''),
          ],
        ),
      );
      expect(
        _row(controller.snapshot(), 0)['automation'],
        _row(beforeFailure, 0)['automation'],
      );
      expect(controller.snapshot()['undo_depth'], beforeFailureUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 exact automation and Undo history survive project reload',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).first as Map<String, dynamic>);
    final rowId = row['row_id'] as int;
    final initialAutomation = (row['automation'] as List)
        .whereType<Map>()
        .map((point) => Map<String, dynamic>.from(point))
        .toList(growable: false);
    const inputPoints = <Map<String, dynamic>>[
      <String, dynamic>{'time_ms': 0.0, 'value': 0.15},
      <String, dynamic>{'time_ms': 1000.0, 'value': 0.55},
      <String, dynamic>{'time_ms': 2500.0, 'value': 0.85},
    ];
    const expectedPoints = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'value': 0.15},
      <String, dynamic>{'x': 1000.0, 'value': 0.55},
      <String, dynamic>{'x': 2500.0, 'value': 0.85},
    ];

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_automation_points',
            'data': <String, dynamic>{
              'operation': 'set_points',
              'target': <String, dynamic>{
                'scope': 'row',
                'row_id': rowId,
                'row_index': 0,
                'automation_target_id': 'volume',
              },
              'points': inputPoints,
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['rows'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    expect(
        _row(reopenedController.snapshot(), 0)['automation'], expectedPoints);
    await reopenedController.undo();
    expect(
      _row(reopenedController.snapshot(), 0)['automation'],
      initialAutomation,
    );
    await reopenedController.redo();
    expect(
        _row(reopenedController.snapshot(), 0)['automation'], expectedPoints);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 verifies exact created MIDI content and timing',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row =
        ((before['rows'] as List).single as Map).cast<String, dynamic>();
    final source =
        ((before['clips'] as List).single as Map).cast<String, dynamic>();
    final instrumentId = source['instrument_id'] as String;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'operation': 'create_clip',
              'start_ms': 2000.0,
              'length_beats': 4.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': instrumentId,
              'notes': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 60,
                  'start_beat': 0.0,
                  'length_beats': 1.0,
                  'velocity': 0.8,
                },
                <String, dynamic>{
                  'pitch': 64,
                  'start_beat': 1.0,
                  'length_beats': 1.0,
                  'velocity': 0.7,
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': instrumentId,
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    final created = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
    expect(created['row_index'], 0);
    expect(created['start_ms'], closeTo(2000.0, 1.0));
    expect(created['length_ms'], closeTo(2000.0, 1.0));
    expect(created['instrument_id'], instrumentId);
    expect(created['midi_notes'], const <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 64,
        'start_beat': 1.0,
        'length_beats': 1.0,
        'velocity': 0.7,
      },
    ]);
    final createdClipId = created['clip_id'];
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect((controller.snapshot()['clips'] as List), hasLength(1));
    expect(controller.snapshot()['undo_depth'], initialUndoDepth);

    await controller.redo();
    applied = controller.snapshot();
    expect((applied['clips'] as List), hasLength(2));
    expect(
      (applied['clips'] as List).cast<Map<String, dynamic>>().singleWhere(
          (clip) => clip['clip_id'] != source['clip_id'])['clip_id'],
      createdClipId,
    );
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated MIDI clip reference transposes exact notes and composes tempo',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).single as Map)
          .cast<String, dynamic>();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final instrumentId = source['instrument_id'] as String;
      final initialUndoDepth = before['undo_depth'] as int;
      const initialNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 0,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 1.0,
          'length_beats': 1.0,
          'velocity': 0.7,
        },
        <String, dynamic>{
          'pitch': 127,
          'start_beat': 2.0,
          'length_beats': 1.0,
          'velocity': 0.6,
        },
      ];
      const finalNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 2,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 1.0,
          'length_beats': 1.0,
          'velocity': 0.7,
        },
        <String, dynamic>{
          'pitch': 127,
          'start_beat': 2.0,
          'length_beats': 1.0,
          'velocity': 0.6,
        },
      ];

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'create-midi',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 4.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': instrumentId,
                'notes': initialNotes,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': row['row_id'],
                  'instrument_id': instrumentId,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 2,
                'expected_notes': finalNotes,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'create-midi',
                    'output': 'midi_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': 100.0,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
          ],
        ),
      );

      final applied = controller.snapshot();
      final created = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
      expect(created['midi_notes'], finalNotes);
      expect(created['row_id'], row['row_id']);
      expect(created['instrument_id'], instrumentId);
      expect(created['start_ms'], closeTo(0.0, 1.0));
      expect(created['length_ms'], closeTo(2400.0, 2.0));
      expect(applied['tempo_bpm'], closeTo(100.0, 0.0005));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final createdClipId = created['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
      expect(controller.snapshot()['undo_depth'], initialUndoDepth);

      await controller.redo();
      final redone = controller.snapshot();
      final redoneCreated = (redone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] == createdClipId);
      expect(redoneCreated, created);
      expect(redone['tempo_bpm'], applied['tempo_bpm']);
      expect(redone['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated MIDI clip composes replace append and chop atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).single as Map)
          .cast<String, dynamic>();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final initialUndoDepth = before['undo_depth'] as int;
      const replacedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 65,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];
      const appendedNotes = <Map<String, dynamic>>[
        ...replacedNotes,
        <String, dynamic>{
          'pitch': 67,
          'start_beat': 4.0,
          'length_beats': 1.0,
          'velocity': 0.7,
        },
      ];
      const finalNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 65,
          'start_beat': 0.0,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 65,
          'start_beat': 0.5,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 67,
          'start_beat': 4.0,
          'length_beats': 0.5,
          'velocity': 0.7,
        },
        <String, dynamic>{
          'pitch': 67,
          'start_beat': 4.5,
          'length_beats': 0.5,
          'velocity': 0.7,
        },
      ];

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'create-editable-midi',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 4.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': source['instrument_id'],
                'notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 60,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.8,
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': row['row_id'],
                  'instrument_id': source['instrument_id'],
                },
              },
            },
            for (final edit
                in <
                  ({
                    String consumer,
                    List<Map<String, dynamic>> notes,
                    double? finalLength,
                  })
                >[
                  (
                    consumer: 'midi.replace_notes',
                    notes: replacedNotes,
                    finalLength: null,
                  ),
                  (
                    consumer: 'midi.append_notes',
                    notes: appendedNotes,
                    finalLength: 5.0,
                  ),
                  (
                    consumer: 'midi.chop_notes',
                    notes: finalNotes,
                    finalLength: null,
                  ),
                ])
              <String, dynamic>{
                'type': 'midi_compose',
                'data': <String, dynamic>{
                  'resource_consumer_type': edit.consumer,
                  'operation': 'replace_notes',
                  'notes': edit.notes,
                  'expected_notes': edit.notes,
                  'exact_notes': true,
                  'preserve_existing_notes': false,
                  'preserve_clip_state': true,
                  if (edit.finalLength != null)
                    'final_length_beats': edit.finalLength,
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': <String, dynamic>{
                      'command_id': 'create-editable-midi',
                      'output': 'midi_clip',
                    },
                  },
                },
              },
          ],
        ),
      );

      var applied = controller.snapshot();
      final created = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
      expect(created['midi_notes'], finalNotes);
      expect(created['length_ms'], closeTo(2500.0, 1.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final createdId = created['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['undo_depth'], initialUndoDepth);

      await controller.redo();
      applied = controller.snapshot();
      final redone = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] == createdId);
      expect(redone, created);
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated MIDI verification ignores note storage order', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).single as Map)
        .cast<String, dynamic>();
    final source = ((before['clips'] as List).single as Map)
        .cast<String, dynamic>();
    const unsortedNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 67,
        'start_beat': 2.0,
        'length_beats': 1.0,
        'velocity': 0.7,
      },
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 64,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];
    const expectedNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 58,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 62,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 65,
        'start_beat': 2.0,
        'length_beats': 1.0,
        'velocity': 0.7,
      },
    ];

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'unordered-midi',
              'operation': 'create_clip',
              'start_ms': 0.0,
              'length_beats': 4.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': source['instrument_id'],
              'notes': unsortedNotes,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': source['instrument_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'resource_consumer_type': 'midi.transpose',
              'operation': 'transpose_notes',
              'semitones': -2,
              'expected_notes': expectedNotes,
              'target': const <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'unordered-midi',
                  'output': 'midi_clip',
                },
              },
            },
          },
        ],
      ),
    );

    final applied = controller.snapshot();
    final created = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
    expect(
      aiV3CanonicalMidiNotes(
        (created['midi_notes'] as List).cast<Map>().map(
          (note) => Map<String, dynamic>.from(note),
        ),
      ),
      expectedNotes,
    );
    await controller.undo();
    expect(controller.snapshot()['clips'], before['clips']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated MIDI duplicate note-edit stages undo and redo atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final initialRows = (before['rows'] as List).length;
      const rowRef = <String, dynamic>{
        'command_id': 'compound-midi-row',
        'output': 'row',
      };
      const clipRef = <String, dynamic>{
        'command_id': 'compound-midi',
        'output': 'midi_clip',
      };
      const copyRef = <String, dynamic>{
        'command_id': 'compound-copy',
        'output': 'copy_clip',
      };
      const originalNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];
      const replacedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 72,
          'start_beat': 0.0,
          'length_beats': 2.0,
          'velocity': 0.8,
        },
      ];
      const appendedNotes = <Map<String, dynamic>>[
        ...replacedNotes,
        <String, dynamic>{
          'pitch': 74,
          'start_beat': 8.0,
          'length_beats': 1.0,
          'velocity': 0.7,
        },
      ];
      const choppedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 72,
          'start_beat': 0.0,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 72,
          'start_beat': 0.5,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 72,
          'start_beat': 1.0,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 72,
          'start_beat': 1.5,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 74,
          'start_beat': 8.0,
          'length_beats': 0.5,
          'velocity': 0.7,
        },
        <String, dynamic>{
          'pitch': 74,
          'start_beat': 8.5,
          'length_beats': 0.5,
          'velocity': 0.7,
        },
      ];

      Map<String, dynamic> noteEdit(
        String consumer,
        List<Map<String, dynamic>> notes, {
        double? finalLengthBeats,
      }) => <String, dynamic>{
        'type': 'midi_compose',
        'data': <String, dynamic>{
          'resource_consumer_type': consumer,
          'operation': 'replace_notes',
          'notes': notes,
          'expected_notes': notes,
          'exact_notes': true,
          'preserve_existing_notes': false,
          'preserve_clip_state': true,
          if (finalLengthBeats != null) 'final_length_beats': finalLengthBeats,
          'target': const <String, dynamic>{
            'scope': 'clip',
            'resource_ref': copyRef,
          },
        },
      };

      final allActions = <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'row_create',
          'data': <String, dynamic>{
            'command_id': 'compound-midi-row',
            'operation': 'create',
            'position': 'end',
            'predicted_row_index': initialRows,
            'name': 'Variation',
            'lane_kind': 'instrument',
            'instrument_id': source['instrument_id'],
            'target': const <String, dynamic>{'scope': 'project'},
          },
        },
        <String, dynamic>{
          'type': 'midi_compose',
          'data': <String, dynamic>{
            'command_id': 'compound-midi',
            'resource_consumer_type': 'midi.create_clip',
            'operation': 'create_clip',
            'start_ms': 0.0,
            'length_beats': 8.0,
            'exact_notes': true,
            'create_new_clip': true,
            'instrument_id': source['instrument_id'],
            'notes': originalNotes,
            'target': <String, dynamic>{
              'scope': 'row',
              'row_index': initialRows,
              'resource_ref': rowRef,
            },
          },
        },
        <String, dynamic>{
          'type': 'clip_edit',
          'data': <String, dynamic>{
            'command_id': 'compound-copy',
            'resource_consumer_type': 'clip.duplicate_to',
            'operation': 'duplicate',
            'paste_start_ms': 8000.0,
            'predicted_input_start_ms': 0.0,
            'predicted_input_end_ms': 4000.0,
            'target': const <String, dynamic>{
              'scope': 'clip',
              'resource_ref': clipRef,
            },
          },
        },
        noteEdit('midi.replace_notes', replacedNotes),
        noteEdit('midi.append_notes', appendedNotes, finalLengthBeats: 9.0),
        noteEdit('midi.chop_notes', choppedNotes),
      ];

      for (final actionCount in <int>[2, 3, 4, 5, 6]) {
        await controller.executeV3Handoff(
          _handoff(
            digest: controller.stateDigest,
            actions: allActions.take(actionCount).toList(growable: false),
          ),
        );
        final applied = controller.snapshot();
        expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);
        final generatedIds = (applied['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => clip['clip_id'] != source['clip_id'])
            .map((clip) => clip['clip_id'])
            .toSet();

        await controller.undo().timeout(const Duration(seconds: 8));
        expect(controller.snapshot()['rows'], before['rows']);
        expect(controller.snapshot()['clips'], before['clips']);

        await controller.redo().timeout(const Duration(seconds: 8));
        final redone = controller.snapshot();
        expect(redone, applied);
        expect(
          (redone['clips'] as List)
              .cast<Map<String, dynamic>>()
              .map((clip) => clip['clip_id'])
              .toSet(),
          containsAll(generatedIds),
        );

        await controller.undo().timeout(const Duration(seconds: 8));
        expect(controller.snapshot()['rows'], before['rows']);
        expect(controller.snapshot()['clips'], before['clips']);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated MIDI can be duplicated after append chop and transpose',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).single as Map)
          .cast<String, dynamic>();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      const clipRef = <String, dynamic>{
        'command_id': 'edited-midi',
        'output': 'midi_clip',
      };
      const initialNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];
      const appendedNotes = <Map<String, dynamic>>[
        ...initialNotes,
        <String, dynamic>{
          'pitch': 64,
          'start_beat': 12.0,
          'length_beats': 1.0,
          'velocity': 0.75,
        },
      ];
      const choppedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.5,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 64,
          'start_beat': 12.0,
          'length_beats': 0.5,
          'velocity': 0.75,
        },
        <String, dynamic>{
          'pitch': 64,
          'start_beat': 12.5,
          'length_beats': 0.5,
          'velocity': 0.75,
        },
      ];
      const transposedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 0.0,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 0.5,
          'length_beats': 0.5,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 66,
          'start_beat': 12.0,
          'length_beats': 0.5,
          'velocity': 0.75,
        },
        <String, dynamic>{
          'pitch': 66,
          'start_beat': 12.5,
          'length_beats': 0.5,
          'velocity': 0.75,
        },
      ];

      Map<String, dynamic> replaceNotes(
        String consumer,
        List<Map<String, dynamic>> notes, {
        double? finalLengthBeats,
      }) => <String, dynamic>{
        'type': 'midi_compose',
        'data': <String, dynamic>{
          'resource_consumer_type': consumer,
          'operation': 'replace_notes',
          'notes': notes,
          'expected_notes': notes,
          'exact_notes': true,
          'preserve_existing_notes': false,
          'preserve_clip_state': true,
          if (finalLengthBeats != null) 'final_length_beats': finalLengthBeats,
          'target': const <String, dynamic>{
            'scope': 'clip',
            'resource_ref': clipRef,
          },
        },
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'edited-midi',
                'resource_consumer_type': 'midi.create_clip',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 12.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': source['instrument_id'],
                'notes': initialNotes,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': row['row_id'],
                  'instrument_id': source['instrument_id'],
                },
              },
            },
            replaceNotes(
              'midi.append_notes',
              appendedNotes,
              finalLengthBeats: 16.0,
            ),
            replaceNotes('midi.chop_notes', choppedNotes),
            <String, dynamic>{
              'type': 'midi_compose',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 2,
                'expected_notes': transposedNotes,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'command_id': 'edited-midi-copy',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 10000.0,
                'predicted_input_start_ms': 0.0,
                'predicted_input_end_ms': 8000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': 2000.0,
                'predicted_start_ms': 2000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef,
                },
              },
            },
          ],
        ),
      );

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['clip_id'] != source['clip_id'])
          .toList(growable: false);
      expect(generated, hasLength(2));
      expect(generated.map((clip) => clip['start_ms']).toSet(), <Object?>{
        2000.0,
        10000.0,
      });
      for (final clip in generated) {
        expect(clip['length_ms'], closeTo(8000.0, 2.0));
        expect(clip['midi_notes'], transposedNotes);
      }

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      expect(controller.snapshot(), applied);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated MIDI note-edit verification failure rolls back', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).single as Map)
        .cast<String, dynamic>();
    final source = ((before['clips'] as List).single as Map)
        .cast<String, dynamic>();

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'create-midi-before-failure',
              'operation': 'create_clip',
              'start_ms': 0.0,
              'length_beats': 4.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': source['instrument_id'],
              'notes': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 60,
                  'start_beat': 0.0,
                  'length_beats': 1.0,
                  'velocity': 0.8,
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': source['instrument_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'resource_consumer_type': 'midi.replace_notes',
              'operation': 'replace_notes',
              'notes': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 65,
                  'start_beat': 0.0,
                  'length_beats': 1.0,
                  'velocity': 0.8,
                },
              ],
              'exact_notes': true,
              'preserve_existing_notes': false,
              'preserve_clip_state': true,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'create-midi-before-failure',
                  'output': 'midi_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'project_edit',
            'data': <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': 90.0,
              'time_stretch_audio': false,
              'preserve_pitch': true,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
        ],
      ),
    );

    final rolledBack = controller.snapshot();
    expect(rolledBack['rows'], before['rows']);
    expect(rolledBack['clips'], before['clips']);
    expect(rolledBack['tempo_bpm'], before['tempo_bpm']);
    expect(rolledBack['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 generated MIDI clip can be transposed and moved', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).single as Map)
        .cast<String, dynamic>();
    final source = ((before['clips'] as List).single as Map)
        .cast<String, dynamic>();
    const initialNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];
    const finalNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 63,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'create-moved-midi',
              'operation': 'create_clip',
              'start_ms': 0.0,
              'length_beats': 4.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': source['instrument_id'],
              'notes': initialNotes,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': source['instrument_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'resource_consumer_type': 'midi.transpose',
              'operation': 'transpose_notes',
              'semitones': 3,
              'expected_notes': finalNotes,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'create-moved-midi',
                  'output': 'midi_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.move_by_beats',
              'operation': 'move',
              'delta_ms': 1000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'create-moved-midi',
                  'output': 'midi_clip',
                },
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    final created = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
    expect(created['midi_notes'], finalNotes);
    expect(created['start_ms'], closeTo(1000.0, 1.0));
    final createdId = created['clip_id'];

    await controller.undo();
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    final redone = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == createdId);
    expect(redone['midi_notes'], finalNotes);
    expect(redone['start_ms'], closeTo(1000.0, 1.0));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 missing resource consumer type fails closed and rolls creation back',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).single as Map)
          .cast<String, dynamic>();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'create-midi-rollback',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 4.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': source['instrument_id'],
                'notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 60,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.8,
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': row['row_id'],
                  'instrument_id': source['instrument_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'operation': 'transpose_notes',
                'semitones': 2,
                'expected_notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 62,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.8,
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'create-midi-rollback',
                    'output': 'midi_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      final rolledBack = controller.snapshot();
      expect(rolledBack['rows'], before['rows']);
      expect(rolledBack['clips'], before['clips']);
      expect(rolledBack['undo_depth'], before['undo_depth']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 transposes a generated MIDI clip on an embedded destination row',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'empty_one_row',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialUndoDepth = before['undo_depth'] as int;
      const instrumentId = 'sfz.vsco.upright_piano';
      const notes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 63,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 67,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
      ];
      const finalNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 59,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 66,
          'start_beat': 0.0,
          'length_beats': 4.0,
          'velocity': 0.8,
        },
      ];

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'operation': 'create',
                'position': 'end',
                'name': 'Chords',
                'lane_kind': 'instrument',
                'instrument_id': instrumentId,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'embedded-midi',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 16.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': instrumentId,
                'notes': notes,
                'target': const <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'instrument_id': instrumentId,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': -1,
                'expected_notes': finalNotes,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'embedded-midi',
                    'output': 'midi_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      expect((applied['rows'] as List), hasLength(2));
      expect((applied['clips'] as List), hasLength(1));
      final createdRow = ((applied['rows'] as List).last as Map)
          .cast<String, dynamic>();
      final createdClip = ((applied['clips'] as List).single as Map)
          .cast<String, dynamic>();
      expect(createdRow['name'], 'Chords');
      expect(createdClip['row_index'], 1);
      expect(createdClip['instrument_id'], instrumentId);
      expect(createdClip['midi_notes'], finalNotes);
      final createdRowId = createdRow['row_id'];
      final createdClipId = createdClip['clip_id'];
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      expect((controller.snapshot()['rows'] as List), hasLength(1));
      expect((controller.snapshot()['clips'] as List), isEmpty);

      await controller.redo();
      applied = controller.snapshot();
      expect((applied['rows'] as List), hasLength(2));
      expect((applied['clips'] as List), hasLength(1));
      expect(((applied['rows'] as List).last as Map)['row_id'], createdRowId);
      expect(
        ((applied['clips'] as List).single as Map)['clip_id'],
        createdClipId,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 tempo then three MIDI creations verify and undo as one transaction',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final instrumentId = source['instrument_id'] as String;
      final initialTempo = (before['tempo_bpm'] as num).toDouble();
      final initialRows = (before['rows'] as List).length;
      final initialClips = (before['clips'] as List).length;
      final initialUndoDepth = before['undo_depth'] as int;

      Map<String, dynamic> createRow(String name) => <String, dynamic>{
        'type': 'row_create',
        'data': <String, dynamic>{
          'operation': 'create',
          'position': 'end',
          'name': name,
          'lane_kind': 'instrument',
          'instrument_id': instrumentId,
          'target': const <String, dynamic>{'scope': 'project'},
        },
      };

      Map<String, dynamic> createClip(int row, int pitch) => <String, dynamic>{
        'type': 'midi_compose',
        'data': <String, dynamic>{
          'operation': 'create_clip',
          'start_ms': 0.0,
          'length_beats': 16.0,
          'exact_notes': true,
          'create_new_clip': true,
          'instrument_id': instrumentId,
          'notes': <Map<String, dynamic>>[
            <String, dynamic>{
              'pitch': pitch,
              'start_beat': 0.0,
              'length_beats': 16.0,
              'velocity': 0.8,
            },
          ],
          'target': <String, dynamic>{
            'scope': 'row',
            'row_index': row,
            'instrument_id': instrumentId,
          },
        },
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': 100.0,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            createRow('Gate Drums'),
            createClip(initialRows, 36),
            createRow('Gate Bass'),
            createClip(initialRows + 1, 48),
            createRow('Gate Piano'),
            createClip(initialRows + 2, 60),
          ],
        ),
      );

      var applied = controller.snapshot();
      expect(applied['tempo_bpm'], closeTo(100.0, 0.0005));
      expect((applied['rows'] as List), hasLength(initialRows + 3));
      expect((applied['clips'] as List), hasLength(initialClips + 3));
      final created = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['clip_id'] != source['clip_id'])
          .toList(growable: false);
      expect(created, hasLength(3));
      expect(created.map((clip) => clip['row_index']), <int>[
        initialRows,
        initialRows + 1,
        initialRows + 2,
      ]);
      expect(
        created.map((clip) => (clip['length_ms'] as num).toDouble()),
        everyElement(closeTo(9600.0, 2.0)),
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      final undone = controller.snapshot();
      expect(undone['tempo_bpm'], closeTo(initialTempo, 0.0005));
      expect((undone['rows'] as List), hasLength(initialRows));
      expect((undone['clips'] as List), hasLength(initialClips));
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      applied = controller.snapshot();
      expect(applied['tempo_bpm'], closeTo(100.0, 0.0005));
      expect((applied['rows'] as List), hasLength(initialRows + 3));
      expect((applied['clips'] as List), hasLength(initialClips + 3));
      expect(
        (applied['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => clip['clip_id'] != source['clip_id'])
            .map((clip) => (clip['length_ms'] as num).toDouble()),
        everyElement(closeTo(9600.0, 2.0)),
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated sample can be pitched and moved atomically', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final sourcePath = clips.first['file'] as String;
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'place-sample',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': 1,
                  'start_ms': 500.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 1,
                'row_id': rows[1]['row_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.set_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': 2.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'place-sample',
                  'output': 'audio_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.move_by_beats',
              'operation': 'move',
              'delta_ms': 1000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'place-sample',
                  'output': 'audio_clip',
                },
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    final created = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (clip) => !clips.any(
            (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
          ),
        );
    expect(created['pitch_semitones'], 2.0);
    expect(created['start_ms'], closeTo(1500.0, 1.0));
    expect(applied['undo_depth'], initialUndoDepth + 1);
    final createdId = created['clip_id'];

    await controller.undo();
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    final redone = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] == createdId);
    expect(redone['pitch_semitones'], 2.0);
    expect(redone['start_ms'], closeTo(1500.0, 1.0));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated audio row can be configured and receive a sample atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      final initialClips = (before['clips'] as List)
          .cast<Map<String, dynamic>>();
      final sourcePath = initialClips.first['file'] as String;
      final initialUndoDepth = before['undo_depth'] as int;
      const rowRef = <String, dynamic>{
        'command_id': 'create-audio-row',
        'output': 'row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'create-audio-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Audio',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'row_rename',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.rename',
                'operation': 'rename',
                'new_name': 'Percussion',
                'expected_name': 'Percussion',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'row_mix',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.adjust_gain_db',
                'operation': 'adjust_gain',
                'delta_db': -3.0,
                'expected_gain_db': -3.0,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'row_mix',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.set_pan',
                'operation': 'set_pan',
                'pan_signed': 0.25,
                'expected_pan_signed': 0.25,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-on-audio-row',
                'resource_consumer_type': 'sample.place',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': initialRows,
                    'start_ms': 2000.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': initialRows,
                      'resource_ref': rowRef,
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final createdRow = (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (row) => !(before['rows'] as List).cast<Map<String, dynamic>>().any(
              (old) => old['row_id'] == row['row_id'],
            ),
          );
      final createdClip = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (clip) =>
                !initialClips.any((old) => old['clip_id'] == clip['clip_id']),
          );
      expect(createdRow['name'], 'Percussion');
      expect(createdRow['gain_ui'], closeTo(rowGainDbToUi(-3.0), 0.0005));
      expect(createdRow['pan_01'], closeTo(0.625, 0.0005));
      expect(createdClip['row_id'], createdRow['row_id']);
      expect(createdClip['start_ms'], closeTo(2000.0, 1.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final createdRowId = createdRow['row_id'];
      final createdClipId = createdClip['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(
        (applied['rows'] as List).cast<Map<String, dynamic>>().singleWhere(
          (row) => row['row_id'] == createdRowId,
        ),
        createdRow,
      );
      expect(_clip(applied, createdClipId), createdClip);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated MIDI row can receive, transpose, and mute its clip atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final initialUndoDepth = before['undo_depth'] as int;
      const rowRef = <String, dynamic>{
        'command_id': 'create-midi-row',
        'output': 'row',
      };
      const initialNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];
      const transposedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'create-midi-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Chords',
                'lane_kind': 'instrument',
                'instrument_id': source['instrument_id'],
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'create-midi-clip-on-row',
                'resource_consumer_type': 'midi.create_clip',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 4.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': source['instrument_id'],
                'notes': initialNotes,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 2,
                'expected_notes': transposedNotes,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'create-midi-clip-on-row',
                    'output': 'midi_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'row_mute',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.set_muted',
                'operation': 'set_muted',
                'muted': true,
                'expected_muted': true,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': rowRef,
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final createdRow = (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['name'] == 'Chords');
      final createdClip = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['row_id'] == createdRow['row_id']);
      expect(createdRow['muted'], isTrue);
      expect(createdClip['midi_notes'], transposedNotes);
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final createdRowId = createdRow['row_id'];
      final createdClipId = createdClip['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(
        (applied['rows'] as List).cast<Map<String, dynamic>>().singleWhere(
          (row) => row['row_id'] == createdRowId,
        ),
        createdRow,
      );
      expect(_clip(applied, createdClipId), createdClip);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated rows can form and mutate one typed group atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      final stableRowId = ((before['rows'] as List).first as Map)['row_id'];
      final initialUndoDepth = before['undo_depth'] as int;
      const firstRowRef = <String, dynamic>{
        'command_id': 'group-row-one',
        'output': 'row',
      };
      const secondRowRef = <String, dynamic>{
        'command_id': 'group-row-two',
        'output': 'row',
      };
      const groupRef = <String, dynamic>{
        'command_id': 'generated-group',
        'output': 'group',
      };
      const groupId = 'v3_generated_group_test';

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'group-row-one',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Generated One',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'group-row-two',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows + 1,
                'name': 'Generated Two',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'v3_group_edit',
              'data': <String, dynamic>{
                'command_id': 'generated-group',
                'operation': 'create',
                'group_id': groupId,
                'name': 'Generated Trio',
                'member_targets': <Map<String, dynamic>>[
                  <String, dynamic>{'scope': 'row', 'row_id': stableRowId},
                  <String, dynamic>{
                    'scope': 'row',
                    'resource_ref': firstRowRef,
                  },
                  <String, dynamic>{
                    'scope': 'row',
                    'resource_ref': secondRowRef,
                  },
                ],
                'affected_group_ids': <String>[],
                'dissolved_group_ids': <String>[],
              },
            },
            <String, dynamic>{
              'type': 'v3_group_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'group.remove_row',
                'operation': 'remove_row',
                'target': <String, dynamic>{
                  'scope': 'group',
                  'resource_ref': groupRef,
                },
                'row_target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': firstRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_group_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'group.set_collapsed',
                'operation': 'set_collapsed',
                'collapsed': true,
                'target': <String, dynamic>{
                  'scope': 'group',
                  'resource_ref': groupRef,
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final group = _group(applied, groupId);
      expect(group['name'], 'Generated Trio');
      expect(group['collapsed'], isTrue);
      expect((group['member_row_ids'] as List), hasLength(2));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final appliedRows = applied['rows'];

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['groups'], before['groups']);
      await controller.redo();
      applied = controller.snapshot();
      expect(applied['rows'], appliedRows);
      expect(_group(applied, groupId), group);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated row deletion retires its generated child', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final initialRows = (before['rows'] as List).length;
    final sourcePath = ((before['clips'] as List).first as Map)['file']
        .toString();
    final initialUndoDepth = before['undo_depth'] as int;
    const rowRef = <String, dynamic>{
      'command_id': 'temporary-row',
      'output': 'row',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'row_create',
            'data': <String, dynamic>{
              'command_id': 'temporary-row',
              'operation': 'create',
              'position': 'end',
              'predicted_row_index': initialRows,
              'name': 'Temporary',
              'lane_kind': 'audio',
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'temporary-sample',
              'resource_consumer_type': 'sample.place',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': initialRows,
                  'start_ms': 0.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': initialRows,
                    'resource_ref': rowRef,
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': initialRows,
                'resource_ref': rowRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'row_delete',
            'data': <String, dynamic>{
              'resource_consumer_type': 'row.delete',
              'operation': 'delete',
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': initialRows,
                'resource_ref': rowRef,
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    expect(applied['rows'], before['rows']);
    expect(applied['clips'], before['clips']);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await controller.undo();
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    expect(applied['rows'], before['rows']);
    expect(applied['clips'], before['clips']);
    expect(applied['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated row deletion preserves a later producer reusing its index',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      final sourcePath = ((before['clips'] as List).first as Map)['file']
          .toString();
      const scratchRowRef = <String, dynamic>{
        'command_id': 'scratch-row',
        'output': 'row',
      };
      const replacementRowRef = <String, dynamic>{
        'command_id': 'replacement-row',
        'output': 'row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'scratch-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Scratch',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'row_delete',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.delete',
                'operation': 'delete',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': scratchRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'replacement-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Replacement',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'replacement-sample',
                'resource_consumer_type': 'sample.place',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': initialRows,
                    'start_ms': 1000.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': initialRows,
                      'resource_ref': replacementRowRef,
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': initialRows,
                  'resource_ref': replacementRowRef,
                },
              },
            },
          ],
        ),
      );

      final applied = controller.snapshot();
      final rows = (applied['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (applied['clips'] as List).cast<Map<String, dynamic>>();
      expect(rows.where((row) => row['name'] == 'Scratch'), isEmpty);
      final replacement = rows.singleWhere(
        (row) => row['name'] == 'Replacement',
      );
      final placed = clips.singleWhere(
        (clip) => clip['row_id'] == replacement['row_id'],
      );
      expect(placed['start_ms'], closeTo(1000.0, 2.0));

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 copy survives deletion of its generated source row', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final initialRows = rows.length;
    final sourcePath = clips.first['file'].toString();
    final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
    final initialUndoDepth = before['undo_depth'] as int;
    const rowRef = <String, dynamic>{
      'command_id': 'temporary-source-row',
      'output': 'row',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'row_create',
            'data': <String, dynamic>{
              'command_id': 'temporary-source-row',
              'operation': 'create',
              'position': 'end',
              'predicted_row_index': initialRows,
              'name': 'Temporary Source',
              'lane_kind': 'audio',
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'temporary-source-clip',
              'resource_consumer_type': 'sample.place',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': initialRows,
                  'start_ms': 0.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': initialRows,
                    'resource_ref': rowRef,
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': initialRows,
                'resource_ref': rowRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'copy-away',
              'resource_consumer_type': 'clip.duplicate_to',
              'operation': 'duplicate',
              'paste_start_ms': 2000.0,
              'row_id': rows.first['row_id'],
              'row_index': 0,
              'new_row_index': 0,
              'predicted_input_start_ms': 0.0,
              'predicted_input_end_ms': sourceLengthMs,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'temporary-source-clip',
                  'output': 'audio_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'row_delete',
            'data': <String, dynamic>{
              'resource_consumer_type': 'row.delete',
              'operation': 'delete',
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': initialRows,
                'resource_ref': rowRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.adjust_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': 2.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'copy-away',
                  'output': 'copy_clip',
                },
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    expect(applied['rows'], before['rows']);
    final generated = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (clip) => !clips.any(
            (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
          ),
        )
        .single;
    expect(generated['row_id'], rows.first['row_id']);
    expect(generated['start_ms'], closeTo(2000.0, 2.0));
    expect(generated['pitch_semitones'], 2.0);
    expect(applied['undo_depth'], initialUndoDepth + 1);
    final generatedId = generated['clip_id'] as String;

    await controller.undo();
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    expect(_clip(applied, generatedId), generated);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated audio duplicate can be pitched and trimmed independently',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
      final sourceTrimStart = (clips.first['trim_start_ms'] as num).toDouble();
      final sourceTrimEnd = (clips.first['trim_end_ms'] as num).toDouble();
      final initialUndoDepth = before['undo_depth'] as int;
      const copyStartMs = 2000.0;
      final requestedStartMs = copyStartMs + 100.0;
      final requestedEndMs = copyStartMs + sourceLengthMs - 100.0;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-duplicate-audio',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duplicate-audio',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': copyStartMs,
                'predicted_input_start_ms': 0.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'place-duplicate-audio',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': -2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duplicate-audio',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.trim_to_range',
                'operation': 'trim',
                'requested_start_ms': requestedStartMs,
                'requested_end_ms': requestedEndMs,
                'predicted_input_start_ms': copyStartMs,
                'predicted_input_end_ms': copyStartMs + sourceLengthMs,
                'new_start_ms': requestedStartMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duplicate-audio',
                    'output': 'copy_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) => !clips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      final original = generated.singleWhere((clip) => clip['start_ms'] == 0.0);
      final copy = generated.singleWhere(
        (clip) =>
            ((clip['start_ms'] as num).toDouble() - requestedStartMs).abs() <
            1.0,
      );
      expect(original['pitch_semitones'], 0.0);
      expect(original['length_ms'], closeTo(sourceLengthMs, 2.0));
      expect(original['trim_start_ms'], closeTo(sourceTrimStart, 1.0));
      expect(original['trim_end_ms'], closeTo(sourceTrimEnd, 1.0));
      expect(copy['pitch_semitones'], -2.0);
      expect(copy['length_ms'], closeTo(sourceLengthMs - 200.0, 3.0));
      expect(copy['trim_start_ms'], closeTo(sourceTrimStart + 100.0, 1.0));
      expect(copy['trim_end_ms'], closeTo(sourceTrimEnd - 100.0, 1.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final originalId = original['clip_id'];
      final copyId = copy['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(_clip(applied, originalId), original);
      expect(_clip(applied, copyId), copy);
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 referenced trim uses timeline units while audio follows tempo',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
      final initialTempo = (before['tempo_bpm'] as num).toDouble();
      final firstTempo = initialTempo - 20.0;
      final finalTempo = initialTempo - 40.0;
      final firstTimelineLength = sourceLengthMs * initialTempo / firstTempo;
      const trimEachSideMs = 100.0;
      final requestedEndMs = firstTimelineLength - trimEachSideMs;
      final sourceTrimEachSideMs = trimEachSideMs * firstTempo / initialTempo;
      final finalRawLengthMs = sourceLengthMs - sourceTrimEachSideMs * 2.0;
      final expectedFinalStartMs = trimEachSideMs * firstTempo / finalTempo;
      final expectedFinalLengthMs =
          finalRawLengthMs * initialTempo / finalTempo;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-tempo-trim',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': firstTempo,
                'time_stretch_audio': true,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.trim_to_range',
                'operation': 'trim',
                'requested_start_ms': trimEachSideMs,
                'requested_end_ms': requestedEndMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'place-tempo-trim',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': finalTempo,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (clip) => !clips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          );
      expect(applied['tempo_bpm'], closeTo(finalTempo, 0.001));
      expect(generated['start_ms'], closeTo(expectedFinalStartMs, 2.0));
      expect(generated['length_ms'], closeTo(expectedFinalLengthMs, 3.0));
      expect(generated['trim_start_ms'], closeTo(sourceTrimEachSideMs, 1.0));
      expect(
        generated['trim_end_ms'],
        closeTo(sourceLengthMs - sourceTrimEachSideMs, 1.0),
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final generatedId = generated['clip_id'] as String;

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(_clip(applied, generatedId)['start_ms'], generated['start_ms']);
      expect(_clip(applied, generatedId)['length_ms'], generated['length_ms']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 referenced trim keeps fixed audio duration across tempo changes',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
      final initialTempo = (before['tempo_bpm'] as num).toDouble();
      final firstTempo = initialTempo - 20.0;
      final finalTempo = initialTempo - 40.0;
      const trimEachSideMs = 100.0;
      final expectedFinalStartMs = trimEachSideMs * firstTempo / finalTempo;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-fixed-tempo-trim',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': firstTempo,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.trim_to_range',
                'operation': 'trim',
                'requested_start_ms': trimEachSideMs,
                'requested_end_ms': sourceLengthMs - trimEachSideMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'place-fixed-tempo-trim',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': finalTempo,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (clip) => !clips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          );
      expect(applied['tempo_bpm'], closeTo(finalTempo, 0.001));
      expect(generated['start_ms'], closeTo(expectedFinalStartMs, 2.0));
      expect(generated['length_ms'], closeTo(sourceLengthMs - 200.0, 3.0));
      expect(generated['trim_start_ms'], closeTo(100.0, 1.0));
      expect(generated['trim_end_ms'], closeTo(sourceLengthMs - 100.0, 1.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final generatedId = generated['clip_id'] as String;

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(_clip(applied, generatedId)['start_ms'], generated['start_ms']);
      expect(_clip(applied, generatedId)['length_ms'], generated['length_ms']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 existing MIDI duplicate can split and edit both generated sides',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final sourceNotes = (source['midi_notes'] as List)
          .whereType<Map>()
          .map((note) => Map<String, dynamic>.from(note))
          .toList(growable: false);
      final transposedNotes = sourceNotes
          .map(
            (note) => <String, dynamic>{
              ...note,
              'pitch': (note['pitch'] as int) - 3,
            },
          )
          .toList(growable: false);
      final sourceLengthMs = (source['length_ms'] as num).toDouble();
      const duplicateStartMs = 2000.0;
      final splitMs = duplicateStartMs + sourceLengthMs / 2.0;
      const moveMs = 2000.0;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duplicate-existing-midi',
                'operation': 'duplicate',
                'paste_start_ms': duplicateStartMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'split-existing-copy',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': splitMs,
                'predicted_input_start_ms': duplicateStartMs,
                'predicted_input_end_ms': duplicateStartMs + sourceLengthMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duplicate-existing-midi',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': -3,
                'expected_notes': transposedNotes,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-existing-copy',
                    'output': 'left_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': moveMs,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-existing-copy',
                    'output': 'right_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['clip_id'] != source['clip_id'])
          .toList(growable: false);
      expect(generated, hasLength(2));
      final left = generated.singleWhere(
        (clip) =>
            ((clip['start_ms'] as num).toDouble() - duplicateStartMs).abs() <
            1.0,
      );
      final right = generated.singleWhere(
        (clip) =>
            ((clip['start_ms'] as num).toDouble() - (splitMs + moveMs)).abs() <
            1.0,
      );
      expect(left['midi_notes'], transposedNotes);
      expect(right['midi_notes'], sourceNotes);
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final leftId = left['clip_id'];
      final rightId = right['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(_clip(applied, leftId), left);
      expect(_clip(applied, rightId), right);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated MIDI duplicate can transpose, split, and delete one side',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
      final controller = fixture.controller;
      final before = controller.snapshot();
      final row = ((before['rows'] as List).single as Map)
          .cast<String, dynamic>();
      final source = ((before['clips'] as List).single as Map)
          .cast<String, dynamic>();
      final initialUndoDepth = before['undo_depth'] as int;
      const initialNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];
      const transposedNotes = <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 62,
          'start_beat': 0.0,
          'length_beats': 1.0,
          'velocity': 0.8,
        },
      ];

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'create-duplicate-midi',
                'operation': 'create_clip',
                'start_ms': 0.0,
                'length_beats': 4.0,
                'exact_notes': true,
                'create_new_clip': true,
                'instrument_id': source['instrument_id'],
                'notes': initialNotes,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 0,
                  'row_id': row['row_id'],
                  'instrument_id': source['instrument_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duplicate-midi',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 2000.0,
                'predicted_input_start_ms': 0.0,
                'predicted_input_end_ms': 2000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'create-duplicate-midi',
                    'output': 'midi_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 2,
                'expected_notes': transposedNotes,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duplicate-midi',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'split-duplicate-midi',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': 3000.0,
                'predicted_input_start_ms': 2000.0,
                'predicted_input_end_ms': 4000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duplicate-midi',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.delete',
                'operation': 'delete',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-duplicate-midi',
                    'output': 'right_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['clip_id'] != source['clip_id'])
          .toList(growable: false);
      expect(generated, hasLength(2));
      final original = generated.singleWhere((clip) => clip['start_ms'] == 0.0);
      final left = generated.singleWhere((clip) => clip['start_ms'] == 2000.0);
      expect(original['midi_notes'], initialNotes);
      expect(original['length_ms'], closeTo(2000.0, 2.0));
      expect(left['midi_notes'], transposedNotes);
      expect(left['length_ms'], closeTo(1000.0, 3.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final originalId = original['clip_id'];
      final leftId = left['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      expect(_clip(applied, originalId), original);
      expect(_clip(applied, leftId), left);
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 referenced trim failure rolls duplication back', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final sourcePath = clips.first['file'] as String;
    final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'place-trim-rollback',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': 1,
                  'start_ms': 10000.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 1,
                'row_id': rows[1]['row_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'duplicate-trim-rollback',
              'resource_consumer_type': 'clip.duplicate_to',
              'operation': 'duplicate',
              'paste_start_ms': 12000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'place-trim-rollback',
                  'output': 'audio_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.trim_to_range',
              'operation': 'trim',
              'requested_start_ms': 12100.0,
              'requested_end_ms': 12100.0 + sourceLengthMs,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'duplicate-trim-rollback',
                  'output': 'copy_clip',
                },
              },
            },
          },
        ],
      ),
    );

    final rolledBack = controller.snapshot();
    expect(rolledBack['rows'], before['rows']);
    expect(rolledBack['clips'], before['clips']);
    expect(rolledBack['overall_duration_ms'], before['overall_duration_ms']);
    expect(rolledBack['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated audio clip can split, edit each side, and delete one side',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
      final cutMs = sourceLengthMs / 2.0;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-split-audio',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'split-audio',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': cutMs,
                'predicted_input_start_ms': 0.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'place-split-audio',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': 2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-audio',
                    'output': 'left_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': 500.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-audio',
                    'output': 'right_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.delete',
                'operation': 'delete',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'split-audio',
                    'output': 'right_clip',
                  },
                },
              },
            },
          ],
        ),
      );

      var applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final created = appliedClips
          .where(
            (clip) => !clips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(created, hasLength(1));
      expect(created.single['pitch_semitones'], 2.0);
      expect(created.single['start_ms'], closeTo(0.0, 1.0));
      expect(created.single['length_ms'], closeTo(cutMs, 3.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final leftId = created.single['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      applied = controller.snapshot();
      final redone = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] == leftId);
      expect(redone['pitch_semitones'], 2.0);
      expect(redone['length_ms'], closeTo(cutMs, 3.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated MIDI split outputs remain independently editable', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).single as Map)
        .cast<String, dynamic>();
    final source = ((before['clips'] as List).single as Map)
        .cast<String, dynamic>();
    const initialNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 64,
        'start_beat': 2.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];
    const transposedNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 62,
        'start_beat': 0.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
      <String, dynamic>{
        'pitch': 66,
        'start_beat': 2.0,
        'length_beats': 1.0,
        'velocity': 0.8,
      },
    ];

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'create-split-midi',
              'operation': 'create_clip',
              'start_ms': 0.0,
              'length_beats': 4.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': source['instrument_id'],
              'notes': initialNotes,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': source['instrument_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'split-midi',
              'resource_consumer_type': 'clip.split_at',
              'operation': 'cut',
              'cut_ms': 1000.0,
              'predicted_input_start_ms': 0.0,
              'predicted_input_end_ms': 2000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'create-split-midi',
                  'output': 'midi_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'resource_consumer_type': 'midi.transpose',
              'operation': 'transpose_notes',
              'semitones': 2,
              'expected_notes': transposedNotes,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'split-midi',
                  'output': 'right_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'project_edit',
            'data': <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': 100.0,
              'time_stretch_audio': false,
              'preserve_pitch': true,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.move_by_beats',
              'operation': 'move',
              'delta_ms': 600.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'split-midi',
                  'output': 'left_clip',
                },
              },
            },
          },
        ],
      ),
    );

    var applied = controller.snapshot();
    final generated = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .where((clip) => clip['clip_id'] != source['clip_id'])
        .toList(growable: false);
    expect(generated, hasLength(2));
    final left = generated.singleWhere((clip) => clip['start_ms'] == 600.0);
    final right = generated.singleWhere((clip) => clip['start_ms'] == 1200.0);
    expect(left['midi_notes'], initialNotes);
    expect(right['midi_notes'], transposedNotes);
    expect(left['length_ms'], closeTo(1200.0, 3.0));
    expect(right['length_ms'], closeTo(1200.0, 3.0));
    expect(applied['tempo_bpm'], closeTo(100.0, 0.0005));
    final generatedIds = generated.map((clip) => clip['clip_id']).toSet();

    await controller.undo();
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    expect(
      (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['clip_id'] != source['clip_id'])
          .map((clip) => clip['clip_id'])
          .toSet(),
      generatedIds,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated audio timing composes through tempo and duplication',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'] as String;
      final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();
      final initialTempo = (before['tempo_bpm'] as num).toDouble();
      final initialUndoDepth = before['undo_depth'] as int;
      const ref = <String, dynamic>{
        'command_id': 'place-timed-audio',
        'output': 'audio_clip',
      };

      Map<String, dynamic> timingAction(
        String consumer,
        String operation,
        Map<String, dynamic> values,
      ) => <String, dynamic>{
        'type': 'clip_edit',
        'data': <String, dynamic>{
          'resource_consumer_type': consumer,
          'operation': operation,
          'runtime_authoritative_audio_timing': true,
          ...values,
          'target': const <String, dynamic>{
            'scope': 'clip',
            'resource_ref': ref,
          },
        },
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-timed-audio',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            timingAction(
              'clip.set_source_tempo_bpm',
              'set_source_tempo',
              <String, dynamic>{'source_tempo_bpm': 90.0},
            ),
            timingAction(
              'clip.set_tempo_follow_mode',
              'tempo_follow',
              <String, dynamic>{'mode': 'preserve_pitch'},
            ),
            timingAction(
              'clip.set_timeline_length_beats',
              'stretch',
              <String, dynamic>{
                'requested_length_beats': 4.0,
                'preserve_pitch': true,
              },
            ),
            timingAction(
              'clip.scale_timeline_length',
              'stretch',
              <String, dynamic>{
                'requested_length_factor': 0.5,
                'preserve_pitch': false,
              },
            ),
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': 100.0,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'copy-timed-audio',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 3000.0,
                'predicted_input_start_ms': 0.0,
                'predicted_input_end_ms': 1200.0,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': ref,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      var applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) => !clips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      final original = generated.singleWhere((clip) => clip['start_ms'] == 0.0);
      final copy = generated.singleWhere((clip) => clip['start_ms'] == 3000.0);
      final expectedSourceTempo = 1000.0 * initialTempo / sourceLengthMs;
      for (final clip in <Map<String, dynamic>>[original, copy]) {
        expect(clip['length_ms'], closeTo(1200.0, 3.0));
        expect(clip['source_tempo_bpm'], closeTo(expectedSourceTempo, 0.001));
        expect(clip['stretch_to_project_tempo'], isTrue);
        expect(clip['tempo_stretch_preserve_pitch'], isFalse);
        expect(clip['tempo_warp_mode'], 'repitch');
      }
      expect(applied['tempo_bpm'], closeTo(100.0, 0.0005));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final generatedIds = generated.map((clip) => clip['clip_id']).toSet();

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
      await controller.redo();
      applied = controller.snapshot();
      expect(
        (applied['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => generatedIds.contains(clip['clip_id']))
            .map((clip) => clip['clip_id'])
            .toSet(),
        generatedIds,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 invalid generated timing materialization rolls back', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final sourcePath = clips.first['file'] as String;
    const ref = <String, dynamic>{
      'command_id': 'place-invalid-timing',
      'output': 'audio_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'place-invalid-timing',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': 1,
                  'start_ms': 0.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 1,
                'row_id': rows[1]['row_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'project_edit',
            'data': const <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': 20.0,
              'time_stretch_audio': false,
              'preserve_pitch': true,
              'target': <String, dynamic>{'scope': 'project'},
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.set_source_tempo_bpm',
              'operation': 'set_source_tempo',
              'runtime_authoritative_audio_timing': true,
              'source_tempo_bpm': 999.0,
              'target': <String, dynamic>{'scope': 'clip', 'resource_ref': ref},
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.set_tempo_follow_mode',
              'operation': 'tempo_follow',
              'runtime_authoritative_audio_timing': true,
              'mode': 'preserve_pitch',
              'target': <String, dynamic>{'scope': 'clip', 'resource_ref': ref},
            },
          },
        ],
      ),
    );

    final after = controller.snapshot();
    expect(after['rows'], before['rows']);
    expect(after['clips'], before['clips']);
    expect(after['tempo_bpm'], before['tempo_bpm']);
    expect(after['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 generated stem timing propagates through split outputs', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      stemSeparatorOverride:
          ({
            required String inputPath,
            required String vocalsOutputPath,
            required String instrumentalOutputPath,
          }) async {
            await File(inputPath).copy(vocalsOutputPath);
            await File(inputPath).copy(instrumentalOutputPath);
          },
      sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );
    final beforeClipIds = clips.map((clip) => clip['clip_id']).toSet();
    final splitMs = (source['start_ms'] as num).toDouble() + 1000.0;
    const instrumentalRef = <String, dynamic>{
      'command_id': 'timed-stems',
      'output': 'instrumental_clip',
    };

    Map<String, dynamic> timingAction(
      String consumer,
      String operation,
      Map<String, dynamic> values,
    ) => <String, dynamic>{
      'type': 'clip_edit',
      'data': <String, dynamic>{
        'resource_consumer_type': consumer,
        'operation': operation,
        'runtime_authoritative_audio_timing': true,
        ...values,
        'target': const <String, dynamic>{
          'scope': 'clip',
          'resource_ref': instrumentalRef,
        },
      },
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_separate_stems',
            'data': <String, dynamic>{
              'command_id': 'timed-stems',
              'source_clip_id': source['clip_id'],
              'source_row_id': source['row_id'],
              'source_row_index': sourceRowIndex,
              'start_ms': source['start_ms'],
              'duration_ms': source['length_ms'],
              'vocals_label': 'Timed Vocals',
              'instrumental_label': 'Timed Instrumental',
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
                'clip_index': clips.indexOf(source),
                'row_id': source['row_id'],
                'row_index': sourceRowIndex,
              },
            },
          },
          timingAction(
            'clip.set_source_tempo_bpm',
            'set_source_tempo',
            <String, dynamic>{'source_tempo_bpm': 120.0},
          ),
          timingAction(
            'clip.set_tempo_follow_mode',
            'tempo_follow',
            <String, dynamic>{'mode': 'preserve_pitch'},
          ),
          timingAction(
            'clip.set_timeline_length_beats',
            'stretch',
            <String, dynamic>{
              'requested_length_beats': 4.0,
              'preserve_pitch': true,
            },
          ),
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'split-timed-stem',
              'resource_consumer_type': 'clip.split_at',
              'operation': 'cut',
              'cut_ms': splitMs,
              'target': const <String, dynamic>{
                'scope': 'clip',
                'resource_ref': instrumentalRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.trim_to_range',
              'operation': 'trim',
              'requested_start_ms': splitMs + 100.0,
              'requested_end_ms': splitMs + 900.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'split-timed-stem',
                  'output': 'right_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.set_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': 2.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'split-timed-stem',
                  'output': 'right_clip',
                },
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    var applied = controller.snapshot();
    final generated = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .where((clip) => !beforeClipIds.contains(clip['clip_id']))
        .toList(growable: false);
    expect(generated, hasLength(3));
    final instrumental = generated
        .where((clip) => clip['label'] == 'Timed Instrumental')
        .toList(growable: false);
    expect(instrumental, hasLength(2));
    final instrumentalLengths =
        instrumental
            .map((clip) => (clip['length_ms'] as num).toDouble())
            .toList(growable: false)
          ..sort();
    expect(instrumentalLengths[0], closeTo(800.0, 3.0));
    expect(instrumentalLengths[1], closeTo(1000.0, 3.0));
    expect(
      instrumental.map((clip) => clip['pitch_semitones']).toSet(),
      <double>{0.0, 2.0},
    );
    for (final clip in instrumental) {
      expect(clip['stretch_to_project_tempo'], isTrue);
      expect(clip['tempo_stretch_preserve_pitch'], isTrue);
      expect(clip['source_tempo_bpm'], closeTo(200.0, 0.001));
    }
    final generatedIds = generated.map((clip) => clip['clip_id']).toSet();

    await controller.undo();
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    applied = controller.snapshot();
    expect(
      (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => generatedIds.contains(clip['clip_id']))
          .map((clip) => clip['clip_id'])
          .toSet(),
      generatedIds,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 split validation failure rolls the producer back', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final sourcePath = clips.first['file'] as String;
    final sourceLengthMs = (clips.first['length_ms'] as num).toDouble();

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'command_id': 'place-before-failed-split',
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': sourcePath,
                  'file_path': sourcePath,
                  'row_index': 1,
                  'start_ms': 0.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              ],
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 1,
                'row_id': rows[1]['row_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'failed-split',
              'resource_consumer_type': 'clip.split_at',
              'operation': 'cut',
              'cut_ms': 20.0,
              'predicted_input_start_ms': 0.0,
              'predicted_input_end_ms': sourceLengthMs,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'place-before-failed-split',
                  'output': 'audio_clip',
                },
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'resource_consumer_type': 'clip.set_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': 5.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'failed-split',
                  'output': 'left_clip',
                },
              },
            },
          },
        ],
      ),
    );

    final after = controller.snapshot();
    expect(after['rows'], before['rows']);
    expect(after['clips'], before['clips']);
    expect(after['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 rolls back when sample source readback differs', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester);
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final initialUndoDepth = before['undo_depth'] as int;

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'sample_insert',
            'data': <String, dynamic>{
              'operation': 'insert_audio_clips',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'library_path': '/unavailable/different-source.wav',
                  'file_path': clips.first['file'],
                  'row_index': 1,
                  'start_ms': 2400.0,
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              ],
            },
          },
        ],
      ),
    );

    final after = controller.snapshot();
    expect((after['clips'] as List), hasLength(clips.length));
    expect(after['undo_depth'], initialUndoDepth);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 clip glue renders and restores exact sources on Undo and rollback',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_glue_live',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final initialUndoDepth = before['undo_depth'] as int;
      const sourceIds = <String>['drums_intro_a', 'drums_intro_b'];
      final unrelatedBefore = clips
          .where((clip) => !sourceIds.contains(clip['clip_id']))
          .toList(growable: false);

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            _glueAction(
              clipIds: sourceIds,
              rowIndex: 0,
              rowId: rows[0]['row_id'] as int,
              startMs: 0,
              durationMs: 2400,
              label: 'Drums Intro Glued',
            ),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      final applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        appliedClips.any((clip) => sourceIds.contains(clip['clip_id'])),
        isFalse,
      );
      final result = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Drums Intro Glued',
      );
      expect(result['row_id'], rows[0]['row_id']);
      expect(result['start_ms'], closeTo(0, 2));
      expect(result['length_ms'], closeTo(2400, 100));
      expect(result['pitch_semitones'], 0.0);
      expect(result['stretch_to_project_tempo'], isFalse);
      expect(await File(result['file'].toString()).length(), greaterThan(44));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      expect(
        appliedClips
            .where((clip) => clip['clip_id'] != result['clip_id'])
            .toList(growable: false),
        unrelatedBefore,
      );
      expect(_row(applied, 1)['automation'], _row(before, 1)['automation']);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      final undone = controller.snapshot();
      expect(undone['clips'], before['clips']);
      expect(undone['rows'], before['rows']);
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      final redone = controller.snapshot();
      final redoneResult = (redone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Drums Intro Glued');
      expect(redoneResult['clip_id'], result['clip_id']);
      expect(redone['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            _glueAction(
              clipIds: sourceIds,
              rowIndex: 0,
              rowId: rows[0]['row_id'] as int,
              startMs: 0,
              durationMs: 2400,
              label: 'Rollback Glue',
            ),
            _renameAction(1, rows[1]['row_id'] as int, ''),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      final rolledBack = controller.snapshot();
      expect(rolledBack['clips'], before['clips']);
      expect(rolledBack['rows'], before['rows']);
      expect(rolledBack['undo_depth'], initialUndoDepth);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 typed glue binds generated copy and supports trim then pitch',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_glue_live',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final source = (before['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['clip_id'] == 'drums_intro_a');
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duplicate-for-glue',
                'operation': 'duplicate',
                'paste_start_ms': 1200.0,
                'predicted_input_start_ms': 0.0,
                'predicted_input_end_ms': 1200.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_clip_glue',
              'data': <String, dynamic>{
                'command_id': 'glue-generated-copy',
                'sources': <Map<String, dynamic>>[
                  <String, dynamic>{'clip_id': source['clip_id']},
                  <String, dynamic>{
                    'resource_ref': <String, dynamic>{
                      'command_id': 'duplicate-for-glue',
                      'output': 'copy_clip',
                    },
                  },
                ],
                'label': 'Typed Glue Result',
                'predicted_start_ms': 0.0,
                'predicted_duration_ms': 2400.0,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_id': source['row_id'],
                  'row_index': source['row_index'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.trim_to_range',
                'operation': 'trim',
                'requested_start_ms': 100.0,
                'requested_end_ms': 2300.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'glue-generated-copy',
                    'output': 'glued_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.adjust_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'delta_semitones': 2.0,
                'new_pitch_semitones': 2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'glue-generated-copy',
                    'output': 'glued_clip',
                  },
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      var applied = controller.snapshot();
      final result = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Typed Glue Result');
      expect(result['start_ms'], closeTo(100.0, 2.0));
      expect(result['length_ms'], closeTo(2200.0, 3.0));
      expect(result['pitch_semitones'], closeTo(2.0, 0.001));
      expect(
        (applied['clips'] as List).cast<Map<String, dynamic>>().any(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        isFalse,
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final resultId = result['clip_id'];

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      applied = controller.snapshot();
      expect(_clip(applied, resultId)['pitch_semitones'], closeTo(2.0, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 glued audio timing composes through move and conversion', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_glue_live',
      basicPitchOverride: ({required mono16k}) async {
        return const <BasicPitchNoteEvent>[
          BasicPitchNoteEvent(
            startSeconds: 0.0,
            endSeconds: 0.4,
            pitchMidi: 60,
            amplitude: 0.8,
          ),
          BasicPitchNoteEvent(
            startSeconds: 0.5,
            endSeconds: 0.9,
            pitchMidi: 67,
            amplitude: 0.75,
          ),
        ];
      },
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final beforeClipIds = (before['clips'] as List)
        .cast<Map<String, dynamic>>()
        .map((clip) => clip['clip_id'])
        .toSet();
    const gluedRef = <String, dynamic>{
      'command_id': 'timed-glue',
      'output': 'glued_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_glue',
            'data': <String, dynamic>{
              'command_id': 'timed-glue',
              'sources': const <Map<String, dynamic>>[
                <String, dynamic>{'clip_id': 'drums_intro_a'},
                <String, dynamic>{'clip_id': 'drums_intro_b'},
              ],
              'label': 'Timed Glue',
              'predicted_start_ms': 0.0,
              'predicted_duration_ms': 2400.0,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_id': rows[0]['row_id'],
                'row_index': 0,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.scale_timeline_length',
              'operation': 'stretch',
              'runtime_authoritative_audio_timing': true,
              'requested_length_factor': 0.5,
              'preserve_pitch': false,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': gluedRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.move_by_beats',
              'operation': 'move',
              'delta_ms': 1000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': gluedRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_clip_convert_to_midi',
            'data': const <String, dynamic>{
              'command_id': 'convert-timed-glue',
              'resource_consumer_type': 'clip.convert_to_midi',
              'operation': 'convert_to_midi',
              'instrument_id': 'sfz.vsco.upright_piano',
              'output_label': 'Timed Glue MIDI',
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': gluedRef,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));

    var applied = controller.snapshot();
    final generated = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .where((clip) => !beforeClipIds.contains(clip['clip_id']))
        .toList(growable: false);
    expect(generated, hasLength(2));
    final audio = generated.singleWhere((clip) => clip['kind'] == 'audio');
    final midi = generated.singleWhere((clip) => clip['kind'] == 'midi');
    expect(audio['start_ms'], closeTo(1000.0, 2.0));
    expect(audio['length_ms'], closeTo(1200.0, 100.0));
    expect(audio['stretch_to_project_tempo'], isTrue);
    expect(audio['tempo_stretch_preserve_pitch'], isFalse);
    expect(audio['tempo_warp_mode'], 'repitch');
    expect(midi['start_ms'], closeTo(1000.0, 2.0));
    expect((midi['midi_notes'] as List), hasLength(2));
    final generatedIds = generated.map((clip) => clip['clip_id']).toSet();

    await controller.undo();
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    await _pumpFor(tester, const Duration(seconds: 1));
    applied = controller.snapshot();
    expect(
      (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => generatedIds.contains(clip['clip_id']))
          .map((clip) => clip['clip_id'])
          .toSet(),
      generatedIds,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 clip glue persists one-step Undo and Redo after reopen', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_glue_live',
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    const sourceIds = <String>['drums_gap_a', 'drums_gap_b'];

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          _glueAction(
            clipIds: sourceIds,
            rowIndex: 0,
            rowId: rows[0]['row_id'] as int,
            startMs: 3000,
            durationMs: 3000,
            label: 'Persisted Gap Glue',
          ),
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));
    final applied = controller.snapshot();
    final appliedResult = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['label'] == 'Persisted Gap Glue');
    final resultId = appliedResult['clip_id'];

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['clips'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    var reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(reopenedClips.any((clip) => clip['clip_id'] == resultId), isTrue);
    expect(
      reopenedClips.any((clip) => sourceIds.contains(clip['clip_id'])),
      isFalse,
    );

    await reopenedController.undo();
    await _pumpFor(tester, const Duration(seconds: 2));
    reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(reopenedClips.any((clip) => clip['clip_id'] == resultId), isFalse);
    expect(
      reopenedClips.where((clip) => sourceIds.contains(clip['clip_id'])),
      hasLength(2),
    );

    await reopenedController.redo();
    await _pumpFor(tester, const Duration(seconds: 2));
    reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(reopenedClips.any((clip) => clip['clip_id'] == resultId), isTrue);
    expect(
      reopenedClips.any((clip) => sourceIds.contains(clip['clip_id'])),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 stem separation preserves source and restores two outputs atomically',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (path) async => path.contains('stem_vocals_')
            ? const Duration(milliseconds: 1180)
            : const Duration(milliseconds: 1170),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Drums Intro Vocals',
                'instrumental_label': 'Drums Intro Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final vocals = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Drums Intro Vocals',
      );
      final instrumental = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Drums Intro Instrumental',
      );
      expect(
        appliedClips.singleWhere(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        source,
      );
      expect((applied['rows'] as List), hasLength(rows.length + 2));
      expect(appliedClips, hasLength(clips.length + 2));
      expect(vocals['start_ms'], closeTo(source['start_ms'] as num, 2));
      expect(instrumental['start_ms'], closeTo(source['start_ms'] as num, 2));
      expect(vocals['pitch_semitones'], 0.0);
      expect(instrumental['pitch_semitones'], 0.0);
      expect(await File(vocals['file'].toString()).length(), greaterThan(44));
      expect(
        await File(instrumental['file'].toString()).length(),
        greaterThan(44),
      );
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 2));
      final undone = controller.snapshot();
      expect(undone['rows'], before['rows']);
      expect(undone['clips'], before['clips']);
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 2));
      final redone = controller.snapshot();
      final redoneClips = (redone['clips'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        redoneClips.singleWhere(
          (clip) => clip['label'] == 'Drums Intro Vocals',
        )['clip_id'],
        vocals['clip_id'],
      );
      expect(
        redoneClips.singleWhere(
          (clip) => clip['label'] == 'Drums Intro Instrumental',
        )['clip_id'],
        instrumental['clip_id'],
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 stem separation rolls back atomically after a later failure',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Rollback Vocals',
                'instrumental_label': 'Rollback Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            _renameAction(1, rows[1]['row_id'] as int, ''),
          ],
        ),
      );

      final rolledBack = controller.snapshot();
      expect(rolledBack['rows'], before['rows']);
      expect(rolledBack['clips'], before['clips']);
      expect(rolledBack['undo_depth'], before['undo_depth']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 referenced stem pitch binds exactly, verifies, undoes, and redoes',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (path) async => path.contains('stem_vocals_')
            ? const Duration(milliseconds: 1180)
            : const Duration(milliseconds: 1170),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'command_id': 'stems',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Referenced Vocals',
                'instrumental_label': 'Referenced Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'pitch',
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': -1.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'stems',
                    'output': 'instrumental_clip',
                  },
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final vocals = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Referenced Vocals',
      );
      final instrumental = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Referenced Instrumental',
      );
      expect(
        appliedClips.singleWhere(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        source,
      );
      expect(vocals['pitch_semitones'], 0.0);
      expect(instrumental['pitch_semitones'], -1.0);
      expect(vocals['length_ms'], closeTo(1180.0, 1.0));
      expect(instrumental['length_ms'], closeTo(1170.0, 1.0));
      expect(_row(applied, sourceRowIndex)['muted'], isFalse);
      expect(applied['undo_depth'], initialUndoDepth + 1);
      expect(await File(vocals['file'].toString()).exists(), isTrue);
      expect(await File(instrumental['file'].toString()).exists(), isTrue);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final redone = controller.snapshot();
      final redoneInstrumental = (redone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Referenced Instrumental');
      expect(redoneInstrumental['clip_id'], instrumental['clip_id']);
      expect(redoneInstrumental['pitch_semitones'], -1.0);
      expect(redone['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 bound stem duration replaces symbolic bounds for duplicate and split',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (path) async => path.contains('stem_vocals_')
            ? const Duration(milliseconds: 1180)
            : const Duration(milliseconds: 1170),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final symbolicSourceLength = (source['length_ms'] as num).toDouble();
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'command_id': 'duration-stems',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Duration Vocals',
                'instrumental_label': 'Duration Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duration-copy',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 2000.0,
                'predicted_input_start_ms': 0.0,
                'predicted_input_end_ms': symbolicSourceLength,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duration-stems',
                    'output': 'instrumental_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duration-split',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': 2500.0,
                'predicted_input_start_ms': 2000.0,
                'predicted_input_end_ms': 2000.0 + symbolicSourceLength,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duration-copy',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': 2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duration-split',
                    'output': 'left_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': 500.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'duration-split',
                    'output': 'right_clip',
                  },
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      var applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final vocals = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Duration Vocals',
      );
      final instrumental = appliedClips.singleWhere(
        (clip) =>
            clip['label'] == 'Duration Instrumental' &&
            clip['start_ms'] == source['start_ms'] &&
            ((clip['length_ms'] as num).toDouble() - 1170.0).abs() < 1.0,
      );
      final splitLeft = appliedClips.singleWhere(
        (clip) =>
            clip['clip_id'] != instrumental['clip_id'] &&
            clip['start_ms'] == 2000.0,
      );
      final splitRight = appliedClips.singleWhere(
        (clip) =>
            clip['clip_id'] != instrumental['clip_id'] &&
            ((clip['start_ms'] as num).toDouble() - 3000.0).abs() < 2.0,
      );
      expect(vocals['length_ms'], closeTo(1180.0, 1.0));
      expect(instrumental['length_ms'], closeTo(1170.0, 1.0));
      expect(splitLeft['length_ms'], closeTo(500.0, 3.0));
      expect(splitLeft['pitch_semitones'], 2.0);
      expect(splitRight['length_ms'], closeTo(670.0, 3.0));
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final splitLeftId = splitLeft['clip_id'] as String;
      final splitRightId = splitRight['clip_id'] as String;

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      applied = controller.snapshot();
      expect(_clip(applied, splitLeftId)['pitch_semitones'], 2.0);
      expect(_clip(applied, splitRightId)['start_ms'], closeTo(3000.0, 2.0));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 can mute the source, pitch one generated stem, and delete its sibling row',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'command_id': 'lifecycle-stems',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Lifecycle Vocals',
                'instrumental_label': 'Lifecycle Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.adjust_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': -1.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'lifecycle-stems',
                    'output': 'instrumental_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'row_mute',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.set_muted',
                'operation': 'set_muted',
                'muted': true,
                'expected_muted': true,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': sourceRowIndex,
                  'row_id': source['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'row_delete',
              'data': <String, dynamic>{
                'resource_consumer_type': 'row.delete',
                'operation': 'delete',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'lifecycle-stems',
                    'output': 'vocals_row',
                  },
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      var applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        appliedClips.where((clip) => clip['label'] == 'Lifecycle Vocals'),
        isEmpty,
      );
      expect((applied['rows'] as List), hasLength(rows.length + 1));
      final instrumental = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Lifecycle Instrumental',
      );
      expect(instrumental['pitch_semitones'], -1.0);
      expect(_row(applied, sourceRowIndex)['muted'], isTrue);
      expect(
        appliedClips.singleWhere(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        source,
      );
      final instrumentalId = instrumental['clip_id'];

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      applied = controller.snapshot();
      expect(
        (applied['clips'] as List).cast<Map<String, dynamic>>().where(
          (clip) => clip['label'] == 'Lifecycle Vocals',
        ),
        isEmpty,
      );
      expect((applied['rows'] as List), hasLength(rows.length + 1));
      expect(
        (applied['clips'] as List).cast<Map<String, dynamic>>().singleWhere(
          (clip) => clip['clip_id'] == instrumentalId,
        )['pitch_semitones'],
        -1.0,
      );
      final redoneSourceRowIndex = (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .indexWhere((row) => row['row_id'] == source['row_id']);
      expect(_row(applied, redoneSourceRowIndex)['muted'], isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _registerCompositionalStemTempoTest(
    name: 'V3 stem pitch composes when tempo follows stem creation',
    order: _StemTempoOrder.tempoLast,
  );
  _registerCompositionalStemTempoTest(
    name: 'V3 stem pitch composes when tempo precedes stem creation',
    order: _StemTempoOrder.tempoFirst,
  );
  _registerCompositionalStemTempoTest(
    name: 'V3 stem pitch composes across multiple later tempo changes',
    order: _StemTempoOrder.multipleTempos,
  );

  testWidgets('V3 tempo before and after a generated MIDI clip composes once', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(tester, fixtureId: 'midi_small');
    final controller = fixture.controller;
    final before = controller.snapshot();
    final row = ((before['rows'] as List).single as Map)
        .cast<String, dynamic>();
    final source = ((before['clips'] as List).single as Map)
        .cast<String, dynamic>();
    final instrumentId = source['instrument_id'] as String;
    const initialNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 60,
        'start_beat': 0.0,
        'length_beats': 8.0,
        'velocity': 0.8,
      },
    ];
    const finalNotes = <Map<String, dynamic>>[
      <String, dynamic>{
        'pitch': 62,
        'start_beat': 0.0,
        'length_beats': 8.0,
        'velocity': 0.8,
      },
    ];

    Map<String, dynamic> tempo(double bpm) => <String, dynamic>{
      'type': 'project_edit',
      'data': <String, dynamic>{
        'operation': 'set_tempo',
        'tempo_bpm': bpm,
        'time_stretch_audio': false,
        'preserve_pitch': true,
        'target': const <String, dynamic>{'scope': 'project'},
      },
    };
    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          tempo(100),
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'tempo-ordered-midi',
              'operation': 'create_clip',
              'start_ms': 4800.0,
              'length_beats': 8.0,
              'exact_notes': true,
              'create_new_clip': true,
              'instrument_id': instrumentId,
              'notes': initialNotes,
              'target': <String, dynamic>{
                'scope': 'row',
                'row_index': 0,
                'row_id': row['row_id'],
                'instrument_id': instrumentId,
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'resource_consumer_type': 'midi.transpose',
              'operation': 'transpose_notes',
              'semitones': 2,
              'expected_notes': finalNotes,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'tempo-ordered-midi',
                  'output': 'midi_clip',
                },
              },
            },
          },
          tempo(80),
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));

    final applied = controller.snapshot();
    final created = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['clip_id'] != source['clip_id']);
    expect(applied['tempo_bpm'], closeTo(80.0, 0.0005));
    expect(created['start_ms'], closeTo(6000.0, 2.0));
    expect(created['length_ms'], closeTo(6000.0, 2.0));
    expect(created['midi_notes'], finalNotes);
    final createdId = created['clip_id'];

    await controller.undo();
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
    await controller.redo();
    final redone = controller.snapshot();
    expect(
      (redone['clips'] as List).cast<Map<String, dynamic>>().singleWhere(
        (clip) => clip['clip_id'] == createdId,
      ),
      created,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated loop branches retain authoritative duration through tempo',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final beforeClips = (before['clips'] as List)
          .cast<Map<String, dynamic>>();
      final sourcePath = beforeClips.first['file'] as String;
      final loopPath = p.join(fixture.directory.path, 'drum_loop_120bpm.wav');
      await File(sourcePath).copy(loopPath);

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'tempo-loop',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': loopPath,
                    'file_path': loopPath,
                    'row_index': 1,
                    'start_ms': 0.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': 1,
                      'row_id': rows[1]['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': 1,
                  'row_id': rows[1]['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'tempo-loop-copy',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 4000.0,
                'predicted_input_start_ms': 0.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'tempo-loop',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': -2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'tempo-loop-copy',
                    'output': 'copy_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': 1000.0,
                'predicted_start_ms': 1000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'tempo-loop',
                    'output': 'audio_clip',
                  },
                },
              },
            },
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': 128.0,
                'time_stretch_audio': false,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) => !beforeClips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      final original = generated.singleWhere(
        (clip) => ((clip['start_ms'] as num).toDouble() - 937.5).abs() < 2.0,
      );
      final copy = generated.singleWhere(
        (clip) => ((clip['start_ms'] as num).toDouble() - 3750.0).abs() < 2.0,
      );
      expect(original['length_ms'], closeTo(1125.0, 2.0));
      expect(copy['length_ms'], closeTo(1125.0, 2.0));
      expect(original['pitch_semitones'], 0.0);
      expect(copy['pitch_semitones'], -2.0);
      final generatedIds = generated.map((clip) => clip['clip_id']).toList();

      await controller.undo();
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
      await controller.redo();
      final redoneIds = (controller.snapshot()['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) => !beforeClips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          )
          .map((clip) => clip['clip_id'])
          .toList();
      expect(redoneIds, generatedIds);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final stretchAudio in <bool>[false, true]) {
    testWidgets(
      'V3 generated one-shot duration ${stretchAudio ? 'follows' : 'ignores'} tempo',
      (tester) async {
        _ignoreKnownEditorSemanticsAssertion();
        final fixture = await _openAudioFixture(
          tester,
          fixtureId: 'audio_reference_valid',
          sampleDurationOverride: (_) async =>
              const Duration(milliseconds: 1200),
        );
        final controller = fixture.controller;
        final before = controller.snapshot();
        final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
        final beforeClips = (before['clips'] as List)
            .cast<Map<String, dynamic>>();
        final sourcePath = beforeClips.first['file'] as String;
        final oneShotPath = p.join(fixture.directory.path, 'clap_one_shot.wav');
        await File(sourcePath).copy(oneShotPath);
        await controller.executeV3Handoff(
          _handoff(
            digest: controller.stateDigest,
            actions: <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'sample_insert',
                'data': <String, dynamic>{
                  'command_id': 'tempo-one-shot',
                  'operation': 'insert_audio_clips',
                  'items': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'library_path': oneShotPath,
                      'file_path': oneShotPath,
                      'row_index': 1,
                      'start_ms': 1000.0,
                      'target': <String, dynamic>{
                        'scope': 'row',
                        'row_index': 1,
                        'row_id': rows[1]['row_id'],
                      },
                    },
                  ],
                  'target': <String, dynamic>{
                    'scope': 'row',
                    'row_index': 1,
                    'row_id': rows[1]['row_id'],
                  },
                },
              },
              <String, dynamic>{
                'type': 'project_edit',
                'data': <String, dynamic>{
                  'operation': 'set_tempo',
                  'tempo_bpm': 128.0,
                  'time_stretch_audio': stretchAudio,
                  'preserve_pitch': true,
                  'target': const <String, dynamic>{'scope': 'project'},
                },
              },
            ],
          ),
        );
        await _pumpFor(tester, const Duration(seconds: 1));

        final applied = controller.snapshot();
        final generated = (applied['clips'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere(
              (clip) => !beforeClips.any(
                (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
              ),
            );
        expect(generated['start_ms'], closeTo(937.5, 2.0));
        expect(
          generated['length_ms'],
          closeTo(stretchAudio ? 1125.0 : 1200.0, 2.0),
        );
        expect(generated['stretch_to_project_tempo'], stretchAudio);
        final generatedId = generated['clip_id'];

        await controller.undo();
        expect(controller.snapshot()['rows'], before['rows']);
        expect(controller.snapshot()['clips'], before['clips']);
        expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
        await controller.redo();
        expect(
          (controller.snapshot()['clips'] as List)
              .cast<Map<String, dynamic>>()
              .singleWhere((clip) => clip['clip_id'] == generatedId),
          generated,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'V3 tempo before stable audio duplicate uses remapped clip bounds',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(tester);
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final beforeClips = (before['clips'] as List)
          .cast<Map<String, dynamic>>();
      final source = beforeClips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final initialTempo = (before['tempo_bpm'] as num).toDouble();
      final nextTempo = initialTempo + 8.0;
      final expectedLengthMs =
          (source['length_ms'] as num).toDouble() * initialTempo / nextTempo;
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'project_edit',
              'data': <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': nextTempo,
                'time_stretch_audio': true,
                'preserve_pitch': true,
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'operation': 'duplicate',
                'paste_start_ms': 15000.0,
                'row_index': sourceRowIndex,
                'new_row_index': sourceRowIndex,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      final applied = controller.snapshot();
      final duplicate = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (clip) => !beforeClips.any(
              (beforeClip) => beforeClip['clip_id'] == clip['clip_id'],
            ),
          );
      expect(applied['tempo_bpm'], closeTo(nextTempo, 0.001));
      expect(duplicate['start_ms'], closeTo(15000.0, 2.0));
      expect(duplicate['length_ms'], closeTo(expectedLengthMs, 3.0));
      expect(duplicate['stretch_to_project_tempo'], isTrue);
      expect(duplicate['tempo_stretch_preserve_pitch'], isTrue);
      expect(applied['undo_depth'], initialUndoDepth + 1);
      final duplicateId = duplicate['clip_id'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['tempo_bpm'], before['tempo_bpm']);
      await controller.redo();
      final redone = controller.snapshot();
      expect(
        (redone['clips'] as List).cast<Map<String, dynamic>>().singleWhere(
          (clip) => clip['clip_id'] == duplicateId,
        ),
        duplicate,
      );
      expect(redone['tempo_bpm'], closeTo(nextTempo, 0.001));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 audio-to-MIDI preserves source and reuses captured notes on Redo',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      var transcriptionCount = 0;
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async {
          transcriptionCount += 1;
          return const <BasicPitchNoteEvent>[
            BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 0.4,
              pitchMidi: 60,
              amplitude: 0.8,
            ),
            BasicPitchNoteEvent(
              startSeconds: 0.5,
              endSeconds: 0.9,
              pitchMidi: 64,
              amplitude: 0.6,
            ),
          ];
        },
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Drums Intro MIDI',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedRows = (applied['rows'] as List)
          .cast<Map<String, dynamic>>();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final result = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Drums Intro MIDI',
      );
      expect(
        appliedClips.singleWhere(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        source,
      );
      expect(appliedRows, hasLength(rows.length + 1));
      expect(appliedClips, hasLength(clips.length + 1));
      expect(result['kind'], 'midi');
      expect(result['instrument_id'], 'sfz.vsco.upright_piano');
      expect(result['start_ms'], closeTo(source['start_ms'] as num, 2));
      expect(result['length_ms'], closeTo(source['length_ms'] as num, 2));
      expect(result['midi_notes'], const <Map<String, dynamic>>[
        <String, dynamic>{
          'pitch': 60,
          'start_beat': 0.0,
          'length_beats': 0.8,
          'velocity': 0.8,
        },
        <String, dynamic>{
          'pitch': 64,
          'start_beat': 1.0,
          'length_beats': 0.8,
          'velocity': 0.6,
        },
      ]);
      expect(transcriptionCount, 1);
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final undone = controller.snapshot();
      expect(undone['rows'], before['rows']);
      expect(undone['clips'], before['clips']);
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final redone = controller.snapshot();
      final redoneResult = (redone['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Drums Intro MIDI');
      expect(redone['rows'], applied['rows']);
      expect(redone['clips'], applied['clips']);
      expect(redone['selected_row_id'], applied['selected_row_id']);
      expect(redone['selected_clip_ids'], applied['selected_clip_ids']);
      expect(redoneResult['clip_id'], result['clip_id']);
      expect(redoneResult['midi_notes'], result['midi_notes']);
      expect(transcriptionCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 audio-to-MIDI binds typed clip and row outputs for dependent edits',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async {
          return const <BasicPitchNoteEvent>[
            BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 0.505,
              pitchMidi: 60,
              amplitude: 0.8,
            ),
            BasicPitchNoteEvent(
              startSeconds: 0.5,
              endSeconds: 1.0,
              pitchMidi: 64,
              amplitude: 0.7,
            ),
          ];
        },
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      const midiClipRef = <String, dynamic>{
        'command_id': 'convert',
        'output': 'midi_clip',
      };
      const midiRowRef = <String, dynamic>{
        'command_id': 'convert',
        'output': 'midi_row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'command_id': 'convert',
                'operation': 'convert_to_midi',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Typed MIDI',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'transpose',
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 2,
                'runtime_authoritative_midi': true,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': midiClipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'move',
                'resource_consumer_type': 'clip.move_by_beats',
                'operation': 'move',
                'delta_ms': 1000.0,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': midiClipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'row_rename',
              'data': <String, dynamic>{
                'command_id': 'rename',
                'resource_consumer_type': 'row.rename',
                'operation': 'rename',
                'new_name': 'Transcribed melody',
                'expected_name': 'Transcribed melody',
                'target': const <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': midiRowRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final result = appliedClips.singleWhere(
        (clip) => clip['label'] == 'Typed MIDI',
      );
      expect(
        result['start_ms'],
        closeTo((source['start_ms'] as num) + 1000, 2),
      );
      expect(
        (result['midi_notes'] as List).cast<Map<String, dynamic>>().map(
          (note) => note['pitch'],
        ),
        <int>[62, 66],
      );
      expect(
        (applied['rows'] as List).cast<Map<String, dynamic>>().singleWhere(
          (row) => row['row_id'] == result['row_id'],
        )['name'],
        'Transcribed melody',
      );
      expect(
        appliedClips.singleWhere(
          (clip) => clip['clip_id'] == source['clip_id'],
        ),
        source,
      );

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final redone = controller.snapshot();
      expect(redone['rows'], applied['rows']);
      expect(redone['clips'], applied['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 generated audio converts to runtime-authoritative MIDI note edits',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async {
          return const <BasicPitchNoteEvent>[
            BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 1.0,
              pitchMidi: 60,
              amplitude: 0.8,
            ),
          ];
        },
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'].toString();
      final initialRows = rows.length;
      const audioRowRef = <String, dynamic>{
        'command_id': 'audio-row',
        'output': 'row',
      };
      const placedClipRef = <String, dynamic>{
        'command_id': 'place',
        'output': 'audio_clip',
      };
      const midiClipRef = <String, dynamic>{
        'command_id': 'convert',
        'output': 'midi_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'audio-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Melody source',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place',
                'resource_consumer_type': 'sample.place',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': initialRows,
                    'start_ms': 0.0,
                    'target': const <String, dynamic>{
                      'scope': 'row',
                      'resource_ref': audioRowRef,
                    },
                  },
                ],
                'target': const <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': audioRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'command_id': 'convert',
                'resource_consumer_type': 'clip.convert_to_midi',
                'operation': 'convert_to_midi',
                'start_ms': 0.0,
                'duration_ms': clips.first['length_ms'],
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Generated MIDI',
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': placedClipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'append',
                'resource_consumer_type': 'midi.append_notes',
                'operation': 'replace_notes',
                'runtime_authoritative_midi': true,
                'deferred_midi_command': 'midi.append_notes',
                'requested_notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 72,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.7,
                  },
                ],
                'exact_notes': true,
                'preserve_existing_notes': false,
                'preserve_clip_state': true,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': midiClipRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'chop',
                'resource_consumer_type': 'midi.chop_notes',
                'operation': 'replace_notes',
                'runtime_authoritative_midi': true,
                'deferred_midi_command': 'midi.chop_notes',
                'subdivision': 8,
                'range': null,
                'velocity_decay_per_slice': 0.0,
                'exact_notes': true,
                'preserve_existing_notes': false,
                'preserve_clip_state': true,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': midiClipRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Generated MIDI');
      final notes = (generated['midi_notes'] as List)
          .cast<Map<String, dynamic>>();
      expect(notes.any((note) => note['pitch'] == 60), isTrue);
      expect(notes.any((note) => note['pitch'] == 72), isTrue);
      expect(notes.where((note) => note['pitch'] == 60).length, greaterThan(1));
      expect(
        (applied['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => clip['kind'] == 'audio')
            .length,
        clips.where((clip) => clip['kind'] == 'audio').length + 1,
      );

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 runtime MIDI split keeps content extent independent of visible bounds',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async {
          return const <BasicPitchNoteEvent>[
            BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 0.25,
              pitchMidi: 60,
              amplitude: 0.8,
            ),
            BasicPitchNoteEvent(
              startSeconds: 0.75,
              endSeconds: 1.0,
              pitchMidi: 67,
              amplitude: 0.7,
            ),
          ];
        },
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final beforeClipIds = clips.map((clip) => clip['clip_id']).toSet();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      final sourceStart = (source['start_ms'] as num).toDouble();
      final sourceLength = (source['length_ms'] as num).toDouble();
      final splitMs = sourceStart + sourceLength / 2.0;
      const convertedRef = <String, dynamic>{
        'command_id': 'convert-split',
        'output': 'midi_clip',
      };
      const rightRef = <String, dynamic>{
        'command_id': 'split-runtime-midi',
        'output': 'right_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'command_id': 'convert-split',
                'operation': 'convert_to_midi',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': sourceStart,
                'duration_ms': sourceLength,
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Runtime Split MIDI',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'split-runtime-midi',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': splitMs,
                'predicted_input_start_ms': sourceStart,
                'predicted_input_end_ms': sourceStart + sourceLength,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': convertedRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'transpose-runtime-right',
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 12,
                'runtime_authoritative_midi': true,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': rightRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) =>
                clip['kind'] == 'midi' &&
                !beforeClipIds.contains(clip['clip_id']),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      final left = generated.singleWhere(
        (clip) =>
            ((clip['start_ms'] as num).toDouble() - sourceStart).abs() < 1,
      );
      final right = generated.singleWhere(
        (clip) => ((clip['start_ms'] as num).toDouble() - splitMs).abs() < 1,
      );
      expect(
        (left['midi_notes'] as List).cast<Map<String, dynamic>>().map(
          (note) => note['pitch'],
        ),
        <int>[60, 67],
      );
      expect(
        (right['midi_notes'] as List).cast<Map<String, dynamic>>().map(
          (note) => note['pitch'],
        ),
        <int>[72, 79],
      );
      expect(
        (left['length_ms'] as num).toDouble(),
        closeTo(sourceLength / 2, 2),
      );
      expect(
        (right['length_ms'] as num).toDouble(),
        closeTo(sourceLength / 2, 2),
      );

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated stem converts, splits, and edits one MIDI output', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      stemSeparatorOverride:
          ({
            required String inputPath,
            required String vocalsOutputPath,
            required String instrumentalOutputPath,
          }) async {
            await File(inputPath).copy(vocalsOutputPath);
            await File(inputPath).copy(instrumentalOutputPath);
          },
      sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      basicPitchOverride: ({required mono16k}) async {
        return const <BasicPitchNoteEvent>[
          BasicPitchNoteEvent(
            startSeconds: 0.0,
            endSeconds: 0.25,
            pitchMidi: 60,
            amplitude: 0.8,
          ),
          BasicPitchNoteEvent(
            startSeconds: 0.8,
            endSeconds: 1.0,
            pitchMidi: 67,
            amplitude: 0.7,
          ),
        ];
      },
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final beforeClipIds = clips.map((clip) => clip['clip_id']).toSet();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );
    final sourceStart = (source['start_ms'] as num).toDouble();
    const stemRef = <String, dynamic>{
      'command_id': 'runtime-stems',
      'output': 'instrumental_clip',
    };
    const midiRef = <String, dynamic>{
      'command_id': 'convert-stem',
      'output': 'midi_clip',
    };
    const rightRef = <String, dynamic>{
      'command_id': 'split-stem-midi',
      'output': 'right_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_separate_stems',
            'data': <String, dynamic>{
              'command_id': 'runtime-stems',
              'source_clip_id': source['clip_id'],
              'source_row_id': source['row_id'],
              'source_row_index': sourceRowIndex,
              'start_ms': sourceStart,
              'duration_ms': source['length_ms'],
              'vocals_label': 'Runtime Vocals',
              'instrumental_label': 'Runtime Instrumental',
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
                'clip_index': clips.indexOf(source),
                'row_id': source['row_id'],
                'row_index': sourceRowIndex,
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_clip_convert_to_midi',
            'data': const <String, dynamic>{
              'command_id': 'convert-stem',
              'resource_consumer_type': 'clip.convert_to_midi',
              'operation': 'convert_to_midi',
              'instrument_id': 'sfz.vsco.upright_piano',
              'output_label': 'Stem MIDI',
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': stemRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'split-stem-midi',
              'resource_consumer_type': 'clip.split_at',
              'operation': 'cut',
              'cut_ms': sourceStart + 600.0,
              'target': const <String, dynamic>{
                'scope': 'clip',
                'resource_ref': midiRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'transpose-stem-right',
              'resource_consumer_type': 'midi.transpose',
              'operation': 'transpose_notes',
              'semitones': 12,
              'runtime_authoritative_midi': true,
              'target': const <String, dynamic>{
                'scope': 'clip',
                'resource_ref': rightRef,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));

    final applied = controller.snapshot();
    final appliedClips = (applied['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      appliedClips.singleWhere(
        (clip) => clip['clip_id'] == source['clip_id'],
      ),
      source,
    );
    expect(
      appliedClips.where((clip) => clip['label'] == 'Runtime Vocals'),
      hasLength(1),
    );
    expect(
      appliedClips.where((clip) => clip['label'] == 'Runtime Instrumental'),
      hasLength(1),
    );
    final generatedMidi = appliedClips
        .where(
          (clip) =>
              clip['kind'] == 'midi' &&
              !beforeClipIds.contains(clip['clip_id']),
        )
        .toList(growable: false);
    expect(generatedMidi, hasLength(2));
    final left = generatedMidi.singleWhere(
      (clip) => ((clip['start_ms'] as num).toDouble() - sourceStart).abs() < 1,
    );
    final right = generatedMidi.singleWhere(
      (clip) =>
          ((clip['start_ms'] as num).toDouble() - (sourceStart + 600)).abs() <
          1,
    );
    expect(
      (left['midi_notes'] as List).cast<Map<String, dynamic>>().map(
        (note) => note['pitch'],
      ),
      <int>[60, 67],
    );
    expect(
      (right['midi_notes'] as List).cast<Map<String, dynamic>>().map(
        (note) => note['pitch'],
      ),
      <int>[72, 79],
    );

    await controller.undo();
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(controller.snapshot()['rows'], applied['rows']);
    expect(controller.snapshot()['clips'], applied['clips']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 runtime MIDI append supplies authoritative bounds to duplicate and chop',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async {
          return const <BasicPitchNoteEvent>[
            BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 0.5,
              pitchMidi: 60,
              amplitude: 0.8,
            ),
          ];
        },
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final beforeClipIds = clips.map((clip) => clip['clip_id']).toSet();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      const convertedRef = <String, dynamic>{
        'command_id': 'convert-append',
        'output': 'midi_clip',
      };
      const copyRef = <String, dynamic>{
        'command_id': 'duplicate-appended',
        'output': 'copy_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'command_id': 'convert-append',
                'operation': 'convert_to_midi',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Runtime Append MIDI',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'append-runtime',
                'resource_consumer_type': 'midi.append_notes',
                'operation': 'replace_notes',
                'runtime_authoritative_midi': true,
                'deferred_midi_command': 'midi.append_notes',
                'requested_notes': const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'pitch': 72,
                    'start_beat': 0.0,
                    'length_beats': 1.0,
                    'velocity': 0.7,
                  },
                ],
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': convertedRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'duplicate-appended',
                'resource_consumer_type': 'clip.duplicate_to',
                'operation': 'duplicate',
                'paste_start_ms': 4000.0,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': convertedRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'chop-runtime-copy',
                'resource_consumer_type': 'midi.chop_notes',
                'operation': 'replace_notes',
                'runtime_authoritative_midi': true,
                'deferred_midi_command': 'midi.chop_notes',
                'subdivision': 8,
                'range': null,
                'velocity_decay_per_slice': 0.0,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': copyRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) =>
                clip['kind'] == 'midi' &&
                !beforeClipIds.contains(clip['clip_id']),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      final original = generated.singleWhere(
        (clip) => (clip['start_ms'] as num).toDouble() < 4000,
      );
      final copy = generated.singleWhere(
        (clip) => ((clip['start_ms'] as num).toDouble() - 4000).abs() < 1,
      );
      final originalNotes = (original['midi_notes'] as List)
          .cast<Map<String, dynamic>>();
      final copyNotes = (copy['midi_notes'] as List)
          .cast<Map<String, dynamic>>();
      expect(originalNotes.map((note) => note['pitch']).toSet(), <int>{60, 72});
      expect(copyNotes.map((note) => note['pitch']).toSet(), <int>{60, 72});
      expect(copyNotes.length, greaterThan(originalNotes.length));
      expect(copy['length_ms'], original['length_ms']);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 runtime-authoritative MIDI accepts the converter 1024-note ceiling',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        basicPitchOverride: ({required mono16k}) async =>
            List<BasicPitchNoteEvent>.generate(
              aiV3MaxRuntimeAuthoritativeMidiNotes,
              (index) => BasicPitchNoteEvent(
                startSeconds: 0.0,
                endSeconds: 0.25,
                pitchMidi: 24 + index % 84,
                amplitude: 0.6,
              ),
            ),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      const midiClipRef = <String, dynamic>{
        'command_id': 'convert-limit',
        'output': 'midi_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_convert_to_midi',
              'data': <String, dynamic>{
                'command_id': 'convert-limit',
                'operation': 'convert_to_midi',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'instrument_id': 'sfz.vsco.upright_piano',
                'output_label': 'Runtime Limit MIDI',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'midi_compose',
              'data': <String, dynamic>{
                'command_id': 'transpose-limit',
                'resource_consumer_type': 'midi.transpose',
                'operation': 'transpose_notes',
                'semitones': 1,
                'runtime_authoritative_midi': true,
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': midiClipRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final result = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((clip) => clip['label'] == 'Runtime Limit MIDI');
      expect(
        (result['midi_notes'] as List).length,
        aiV3MaxRuntimeAuthoritativeMidiNotes,
      );
      expect(
        (result['midi_notes'] as List).cast<Map<String, dynamic>>().every(
          (note) => (note['pitch'] as int) >= 25,
        ),
        isTrue,
      );

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 runtime-authoritative MIDI rolls back a 1025-note result', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      basicPitchOverride: ({required mono16k}) async =>
          List<BasicPitchNoteEvent>.generate(
            aiV3MaxRuntimeAuthoritativeMidiNotes,
            (index) => BasicPitchNoteEvent(
              startSeconds: 0.0,
              endSeconds: 0.25,
              pitchMidi: 24 + index % 84,
              amplitude: 0.6,
            ),
          ),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );
    const midiClipRef = <String, dynamic>{
      'command_id': 'convert-overflow',
      'output': 'midi_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_convert_to_midi',
            'data': <String, dynamic>{
              'command_id': 'convert-overflow',
              'operation': 'convert_to_midi',
              'source_clip_id': source['clip_id'],
              'source_row_id': source['row_id'],
              'source_row_index': sourceRowIndex,
              'start_ms': source['start_ms'],
              'duration_ms': source['length_ms'],
              'instrument_id': 'sfz.vsco.upright_piano',
              'output_label': 'Should Roll Back',
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
                'clip_index': clips.indexOf(source),
                'row_id': source['row_id'],
                'row_index': sourceRowIndex,
              },
            },
          },
          <String, dynamic>{
            'type': 'midi_compose',
            'data': <String, dynamic>{
              'command_id': 'append-overflow',
              'resource_consumer_type': 'midi.append_notes',
              'operation': 'replace_notes',
              'runtime_authoritative_midi': true,
              'deferred_midi_command': 'midi.append_notes',
              'requested_notes': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 72,
                  'start_beat': 0.0,
                  'length_beats': 0.5,
                  'velocity': 0.7,
                },
              ],
              'target': const <String, dynamic>{
                'scope': 'clip',
                'resource_ref': midiClipRef,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final after = controller.snapshot();
    expect(after['rows'], before['rows']);
    expect(after['clips'], before['clips']);
    expect(after['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 audio-to-MIDI empty transcription leaves project unchanged',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      basicPitchOverride: ({required mono16k}) async =>
          const <BasicPitchNoteEvent>[],
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_convert_to_midi',
            'data': <String, dynamic>{
              'source_clip_id': source['clip_id'],
              'source_row_id': source['row_id'],
              'source_row_index': sourceRowIndex,
              'start_ms': source['start_ms'],
              'duration_ms': source['length_ms'],
              'instrument_id': 'sfz.vsco.upright_piano',
              'output_label': 'Should Not Exist',
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
                'clip_index': clips.indexOf(source),
                'row_id': source['row_id'],
                'row_index': sourceRowIndex,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));

    final after = controller.snapshot();
    expect(after['rows'], before['rows']);
    expect(after['clips'], before['clips']);
    expect(after['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 audio-to-MIDI Undo and Redo persist after reopen',
      (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    var transcriptionCount = 0;
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      basicPitchOverride: ({required mono16k}) async {
        transcriptionCount += 1;
        return const <BasicPitchNoteEvent>[
          BasicPitchNoteEvent(
            startSeconds: 0.1,
            endSeconds: 0.6,
            pitchMidi: 67,
            amplitude: 0.75,
          ),
        ];
      },
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'v3_clip_convert_to_midi',
            'data': <String, dynamic>{
              'source_clip_id': source['clip_id'],
              'source_row_id': source['row_id'],
              'source_row_index': sourceRowIndex,
              'start_ms': source['start_ms'],
              'duration_ms': source['length_ms'],
              'instrument_id': 'sfz.vsco.upright_piano',
              'output_label': 'Persisted MIDI',
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
                'clip_index': clips.indexOf(source),
                'row_id': source['row_id'],
                'row_index': sourceRowIndex,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));
    final applied = controller.snapshot();
    final appliedPlannerVisible = _plannerVisibleEvaluationState(applied);
    final result = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((clip) => clip['label'] == 'Persisted MIDI');
    expect(transcriptionCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFor(tester, const Duration(milliseconds: 250));
    final reopenedController = AudioEditorEvaluationController();
    await tester.pumpWidget(
      buildIntegrationTestApp(
        home: AudioEditorScreen(
          mode: 'edit',
          projectDir: fixture.directory,
          isProEntitled: true,
          evaluationController: reopenedController,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          reopenedController.isAttached &&
          reopenedController.snapshot()['clips'] is List,
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    var reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      reopenedClips.any((clip) => clip['clip_id'] == result['clip_id']),
      isTrue,
    );
    expect(
      reopenedClips.singleWhere(
        (clip) => clip['clip_id'] == result['clip_id'],
      )['row_id'],
      result['row_id'],
    );

    await reopenedController.undo();
    await _pumpFor(tester, const Duration(seconds: 1));
    reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      reopenedClips.any((clip) => clip['clip_id'] == result['clip_id']),
      isFalse,
    );
    expect(
      reopenedClips.any((clip) => clip['clip_id'] == source['clip_id']),
      isTrue,
    );

    await reopenedController.redo();
    await _pumpFor(tester, const Duration(seconds: 1));
    reopenedClips = (reopenedController.snapshot()['clips'] as List)
        .cast<Map<String, dynamic>>();
    final redone = reopenedClips.singleWhere(
      (clip) => clip['clip_id'] == result['clip_id'],
    );
    expect(redone['row_id'], result['row_id']);
    expect(redone['midi_notes'], result['midi_notes']);
    expect(
      _plannerVisibleEvaluationState(reopenedController.snapshot()),
      appliedPlannerVisible,
    );
    expect(transcriptionCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 phone cleanup preserves the row and supports exact Undo and Redo',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_phone_cleanup',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final rowIndex = rows.indexWhere((row) => row['name'] == 'Voice');
      final rowId = rows[rowIndex]['row_id'] as int;
      final clipIds =
          (before['clips'] as List)
              .cast<Map<String, dynamic>>()
              .where(
                (clip) => clip['row_id'] == rowId && clip['kind'] == 'audio',
              )
              .map((clip) => clip['clip_id'].toString())
              .toList(growable: false)
            ..sort();
      final beforeChain = await controller.effectChain(rowIndex);
      final initialUndoDepth = before['undo_depth'] as int;

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            _phoneMicCleanupAction(rowIndex, rowId, clipIds),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedChain = await controller.effectChain(rowIndex);
      final requiredChain = appliedChain
          .where(
            (effect) =>
                aiV3PhoneMicCleanupEffectIds.contains(effect['effect_id']),
          )
          .map((effect) => effect['effect_id'].toString())
          .toList(growable: false);
      expect(requiredChain, aiV3PhoneMicCleanupEffectIds);
      expect(
        appliedChain
            .where(
              (effect) =>
                  aiV3PhoneMicCleanupEffectIds.contains(effect['effect_id']),
            )
            .every((effect) => effect['bypassed'] == false),
        isTrue,
      );
      for (final clipId in clipIds) {
        expect(
          _clip(applied, clipId)['audio_enhancement_preset'],
          aiV3PhoneMicCleanupPreset,
        );
      }
      expect(applied['undo_depth'], initialUndoDepth + 1);

      await controller.undo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final undone = controller.snapshot();
      expect(await controller.effectChain(rowIndex), beforeChain);
      for (final clipId in clipIds) {
        expect(
          _clip(undone, clipId)['audio_enhancement_preset'],
          _clip(before, clipId)['audio_enhancement_preset'],
        );
      }
      expect(undone['undo_depth'], initialUndoDepth);

      await controller.redo();
      await _pumpFor(tester, const Duration(seconds: 1));
      final redone = controller.snapshot();
      for (final clipId in clipIds) {
        expect(
          _clip(redone, clipId)['audio_enhancement_preset'],
          aiV3PhoneMicCleanupPreset,
        );
      }
      expect(redone['undo_depth'], initialUndoDepth + 1);

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            _phoneMicCleanupAction(rowIndex, rowId, clipIds),
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(controller.snapshot()['undo_depth'], initialUndoDepth + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 phone cleanup rolls back after a later action fails', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_phone_cleanup',
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final rowIndex = rows.indexWhere((row) => row['name'] == 'Voice');
    final rowId = rows[rowIndex]['row_id'] as int;
    final clipIds =
        (before['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => clip['row_id'] == rowId && clip['kind'] == 'audio')
            .map((clip) => clip['clip_id'].toString())
            .toList(growable: false)
          ..sort();
    final beforeChain = await controller.effectChain(rowIndex);

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          _phoneMicCleanupAction(rowIndex, rowId, clipIds),
          _renameAction(rowIndex, rowId, ''),
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final after = controller.snapshot();
    expect(await controller.effectChain(rowIndex), beforeChain);
    for (final clipId in clipIds) {
      expect(
        _clip(after, clipId)['audio_enhancement_preset'],
        _clip(before, clipId)['audio_enhancement_preset'],
      );
    }
    expect(after['undo_depth'], before['undo_depth']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 generated audio replacement composes through pitch and split',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_replace_lengths',
        sampleDurationOverride: (_) async => const Duration(milliseconds: 800),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final target = clips.singleWhere(
        (clip) => clip['clip_id'] == 'replace_target',
      );
      final replacement = clips.singleWhere(
        (clip) => clip['clip_id'] == 'replace_short',
      );
      const copyRef = <String, dynamic>{
        'command_id': 'replace-copy',
        'output': 'copy_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'clip_edit',
              'data': <String, dynamic>{
                'command_id': 'replace-copy',
                'operation': 'duplicate',
                'paste_start_ms': 5000.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': target['clip_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_sample_replace',
              'data': <String, dynamic>{
                'resource_consumer_type': 'sample.replace',
                'operation': 'replace',
                'library_path': replacement['file'],
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': copyRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'clip.adjust_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'adjust',
                'new_pitch_semitones': 2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': copyRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'command_id': 'split-replacement',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': 5400.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': copyRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedClips = (applied['clips'] as List)
          .cast<Map<String, dynamic>>();
      final generated = appliedClips
          .where(
            (clip) => !clips.any(
              (original) => original['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      expect(generated.map((clip) => clip['pitch_semitones']).toSet(), {2.0});
      expect(
        generated.map((clip) => clip['length_ms']).toList(),
        everyElement(closeTo(400.0, 3.0)),
      );
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);
      final generatedIds = generated.map((clip) => clip['clip_id']).toSet();

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo();
      expect(
        (controller.snapshot()['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => generatedIds.contains(clip['clip_id']))
            .map((clip) => clip['clip_id'])
            .toSet(),
        generatedIds,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 placed sample replacement uses final generated resource state',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_replace_lengths',
        sampleDurationOverride: (_) async => const Duration(milliseconds: 800),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.first;
      final replacement = clips.singleWhere(
        (clip) => clip['clip_id'] == 'replace_short',
      );
      const placedRef = <String, dynamic>{
        'command_id': 'placed-for-replacement',
        'output': 'audio_clip',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'placed-for-replacement',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': source['file'],
                    'file_path': source['file'],
                    'row_index': source['row_index'],
                    'start_ms': 10000.0,
                    'target': <String, dynamic>{
                      'scope': 'row',
                      'row_index': source['row_index'],
                      'row_id': source['row_id'],
                    },
                  },
                ],
                'target': <String, dynamic>{
                  'scope': 'row',
                  'row_index': source['row_index'],
                  'row_id': source['row_id'],
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_sample_replace',
              'data': <String, dynamic>{
                'resource_consumer_type': 'sample.replace',
                'operation': 'replace',
                'library_path': replacement['file'],
                'target': const <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': placedRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'clip.set_pitch_semitones',
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': 2.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': placedRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'clip_edit',
              'data': const <String, dynamic>{
                'command_id': 'split-replaced-sample',
                'resource_consumer_type': 'clip.split_at',
                'operation': 'cut',
                'cut_ms': 10400.0,
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': placedRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (clip) => !clips.any(
              (original) => original['clip_id'] == clip['clip_id'],
            ),
          )
          .toList(growable: false);
      expect(generated, hasLength(2));
      expect(generated.map((clip) => clip['pitch_semitones']).toSet(), {2.0});
      expect(
        generated.map((clip) => clip['length_ms']),
        everyElement(closeTo(400.0, 3.0)),
      );
      expect(applied['overall_duration_ms'], greaterThan(10000));
      final generatedIds = generated.map((clip) => clip['clip_id']).toSet();
      final finalDuration = applied['overall_duration_ms'];

      await controller.undo();
      expect(controller.snapshot()['clips'], before['clips']);
      expect(
        controller.snapshot()['overall_duration_ms'],
        before['overall_duration_ms'],
      );
      await controller.redo();
      final redone = controller.snapshot();
      expect(redone['overall_duration_ms'], finalDuration);
      expect(
        (redone['clips'] as List)
            .cast<Map<String, dynamic>>()
            .where((clip) => generatedIds.contains(clip['clip_id']))
            .map((clip) => clip['clip_id'])
            .toSet(),
        generatedIds,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('V3 generated audio silence analysis remains chainable', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_boundary_signal',
      sampleDurationOverride: (path) async =>
          path.contains('voice_with_silence')
          ? const Duration(milliseconds: 4000)
          : const Duration(milliseconds: 1200),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.singleWhere(
      (clip) => clip['clip_id'] == 'voice_with_silence',
    );
    const copyRef = <String, dynamic>{
      'command_id': 'boundary-copy',
      'output': 'copy_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'boundary-copy',
              'operation': 'duplicate',
              'paste_start_ms': 5000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_clip_audio_analysis',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.trim_silence',
              'operation': 'trim_silence',
              'edges': 'both',
              'padding_ms': 0.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': copyRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.set_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': -1.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': copyRef,
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final applied = controller.snapshot();
    final generated = (applied['clips'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (clip) =>
              !clips.any((original) => original['clip_id'] == clip['clip_id']),
        );
    expect(generated['start_ms'] as num, greaterThan(5000));
    expect(generated['length_ms'] as num, lessThan(4000));
    expect(generated['pitch_semitones'], -1.0);
    expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);
    final generatedId = generated['clip_id'];

    await controller.undo();
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    expect(
      (controller.snapshot()['clips'] as List).cast<Map<String, dynamic>>().any(
        (clip) => clip['clip_id'] == generatedId,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('V3 generated audio can produce referenceable stems', (
    tester,
  ) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      stemSeparatorOverride:
          ({
            required String inputPath,
            required String vocalsOutputPath,
            required String instrumentalOutputPath,
          }) async {
            await File(inputPath).copy(vocalsOutputPath);
            await File(inputPath).copy(instrumentalOutputPath);
          },
      sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.first;
    const copyRef = <String, dynamic>{
      'command_id': 'stem-source-copy',
      'output': 'copy_clip',
    };

    await controller.executeV3Handoff(
      _handoff(
        digest: controller.stateDigest,
        actions: <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'clip_edit',
            'data': <String, dynamic>{
              'command_id': 'stem-source-copy',
              'operation': 'duplicate',
              'paste_start_ms': 2000.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'clip_id': source['clip_id'],
              },
            },
          },
          <String, dynamic>{
            'type': 'v3_clip_separate_stems',
            'data': const <String, dynamic>{
              'command_id': 'nested-stems',
              'resource_consumer_type': 'clip.separate_stems',
              'operation': 'separate_stems',
              'vocals_label': 'Nested Vocals',
              'instrumental_label': 'Nested Instrumental',
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': copyRef,
              },
            },
          },
          <String, dynamic>{
            'type': 'clip_edit',
            'data': const <String, dynamic>{
              'resource_consumer_type': 'clip.set_pitch_semitones',
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': 1.0,
              'target': <String, dynamic>{
                'scope': 'clip',
                'resource_ref': <String, dynamic>{
                  'command_id': 'nested-stems',
                  'output': 'instrumental_clip',
                },
              },
            },
          },
        ],
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final applied = controller.snapshot();
    final appliedClips = (applied['clips'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      appliedClips.singleWhere(
        (clip) => clip['label'] == 'Nested Vocals',
      )['pitch_semitones'],
      0.0,
    );
    expect(
      appliedClips.singleWhere(
        (clip) => clip['label'] == 'Nested Instrumental',
      )['pitch_semitones'],
      1.0,
    );
    expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

    await controller.undo();
    expect(controller.snapshot()['rows'], before['rows']);
    expect(controller.snapshot()['clips'], before['clips']);
    await controller.redo();
    expect(
      (controller.snapshot()['clips'] as List)
          .cast<Map<String, dynamic>>()
          .where((clip) => clip['label'] == 'Nested Instrumental'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'V3 compound Undo batches effect removal before generated stem teardown',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'command_id': 'effect-stems',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Effect Vocals',
                'instrumental_label': 'Effect Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_effect_configure',
              'data': const <String, dynamic>{
                'command_id': 'instrumental-effect',
                'resource_consumer_type': 'effect.ensure_configured',
                'operation': 'ensure_configured',
                'effect_id': 'EQ 3-Band',
                'parameters': <String, dynamic>{},
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'effect-stems',
                    'output': 'instrumental_row',
                  },
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      final applied = controller.snapshot();
      expect(
        (applied['rows'] as List).cast<Map<String, dynamic>>(),
        hasLength(rows.length + 2),
      );

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);

      await controller.redo().timeout(const Duration(seconds: 20));
      final redone = controller.snapshot();
      expect(redone['rows'], applied['rows']);
      expect(redone['clips'], applied['clips']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 materializes a deferred mix goal on a generated stem row',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        stemSeparatorOverride:
            ({
              required String inputPath,
              required String vocalsOutputPath,
              required String instrumentalOutputPath,
            }) async {
              await File(inputPath).copy(vocalsOutputPath);
              await File(inputPath).copy(instrumentalOutputPath);
            },
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
      final sourceRowIndex = rows.indexWhere(
        (row) => row['row_id'] == source['row_id'],
      );
      const instrumentalRowRef = <String, dynamic>{
        'command_id': 'mix-stems',
        'output': 'instrumental_row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'v3_clip_separate_stems',
              'data': <String, dynamic>{
                'command_id': 'mix-stems',
                'source_clip_id': source['clip_id'],
                'source_row_id': source['row_id'],
                'source_row_index': sourceRowIndex,
                'start_ms': source['start_ms'],
                'duration_ms': source['length_ms'],
                'vocals_label': 'Deferred Mix Vocals',
                'instrumental_label': 'Deferred Mix Instrumental',
                'target': <String, dynamic>{
                  'scope': 'clip',
                  'clip_id': source['clip_id'],
                  'clip_index': clips.indexOf(source),
                  'row_id': source['row_id'],
                  'row_index': sourceRowIndex,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'warm-instrumental',
                'resource_consumer_type': 'mix.apply_goal',
                'operation': 'apply_goal',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': instrumentalRowRef,
                },
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'eq',
                    'direction': null,
                    'descriptor': 'warmth_boost',
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>['warm'],
                'reset_fx': false,
                'reference': null,
              },
            },
            <String, dynamic>{
              'type': 'v3_automation_points',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'automation.set_points',
                'operation': 'set_points',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'automation_target_id': 'volume',
                  'resource_ref': instrumentalRowRef,
                },
                'points': <Map<String, dynamic>>[
                  <String, dynamic>{'time_ms': 0.0, 'value': 0.25},
                  <String, dynamic>{'time_ms': 1000.0, 'value': 0.75},
                ],
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedRows = (applied['rows'] as List)
          .cast<Map<String, dynamic>>();
      final instrumental = appliedRows.singleWhere(
        (row) => row['name'].toString().contains('Instrumental'),
      );
      final vocal = appliedRows.singleWhere(
        (row) => row['name'].toString().contains('Vocals'),
      );
      expect(instrumental['automation'], const <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'value': 0.25},
        <String, dynamic>{'x': 1000.0, 'value': 0.75},
      ]);
      expect(instrumental['effects'], isNotEmpty);
      expect(vocal['effects'], isEmpty);
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 rolls back a generated row when deferred mixing has no signal',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': const <String, dynamic>{
                'command_id': 'empty-row',
                'operation': 'create',
                'position': 'end',
                'name': 'Empty Mix Row',
                'lane_kind': 'audio',
                'target': <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'mix-empty-row',
                'resource_consumer_type': 'mix.apply_goal',
                'operation': 'apply_goal',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': <String, dynamic>{
                    'command_id': 'empty-row',
                    'output': 'row',
                  },
                },
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'eq',
                    'direction': null,
                    'descriptor': 'warmth_boost',
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>['warm'],
                'reset_fx': false,
                'reference': null,
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      final after = controller.snapshot();
      expect(after['rows'], before['rows']);
      expect(after['clips'], before['clips']);
      expect(after['undo_depth'], before['undo_depth']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 composes relative row gain and pan from a deferred mix result',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      final sourcePath = ((before['clips'] as List).first as Map)['file']
          .toString();
      const generatedRowRef = <String, dynamic>{
        'command_id': 'runtime-mix-row',
        'output': 'row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'runtime-mix-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Runtime Mix Row',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'runtime-mix-sample',
                'resource_consumer_type': 'sample.place',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': initialRows,
                    'start_ms': 0.0,
                    'target': const <String, dynamic>{
                      'scope': 'row',
                      'resource_ref': generatedRowRef,
                    },
                  },
                ],
                'target': const <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'runtime-row-mix',
                'resource_consumer_type': 'mix.apply_goal',
                'operation': 'apply_goal',
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'gain',
                    'direction': 'up',
                    'descriptor': null,
                  },
                  <String, dynamic>{
                    'kind': 'pan',
                    'direction': 'right',
                    'descriptor': null,
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>[],
                'reset_fx': false,
                'reference': null,
              },
            },
            <String, dynamic>{
              'type': 'row_mix',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'row.adjust_gain_db',
                'operation': 'adjust_gain',
                'delta_db': 1.0,
                'expected_gain_db': 1.0,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'row_mix',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'row.adjust_pan',
                'operation': 'adjust_pan',
                'delta': 0.1,
                'expected_pan_signed': 0.1,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['name'] == 'Runtime Mix Row');
      expect(generated['gain_ui'], greaterThan(rowGainDbToUi(1.0)));
      expect(generated['pan_01'], closeTo(0.55, 0.00001));
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      await controller.redo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 resolves generated group and all-row mix goals from live state',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
        sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
      final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
      final sourcePath = clips.first['file'].toString();
      final stableRowId = rows.first['row_id'] as int;
      final initialRows = rows.length;
      const generatedRowRef = <String, dynamic>{
        'command_id': 'generated-drums',
        'output': 'row',
      };
      const groupRef = <String, dynamic>{
        'command_id': 'rhythm-group',
        'output': 'group',
      };
      const groupId = 'v3_deferred_mix_group_test';

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'generated-drums',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Generated Drums',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'sample_insert',
              'data': <String, dynamic>{
                'command_id': 'place-drums',
                'resource_consumer_type': 'sample.place',
                'operation': 'insert_audio_clips',
                'items': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'library_path': sourcePath,
                    'file_path': sourcePath,
                    'row_index': initialRows,
                    'start_ms': 0.0,
                    'target': const <String, dynamic>{
                      'scope': 'row',
                      'resource_ref': generatedRowRef,
                    },
                  },
                ],
                'target': const <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
              },
            },
            <String, dynamic>{
              'type': 'v3_group_edit',
              'data': <String, dynamic>{
                'command_id': 'rhythm-group',
                'operation': 'create',
                'group_id': groupId,
                'name': 'Rhythm',
                'member_targets': <Map<String, dynamic>>[
                  <String, dynamic>{'scope': 'row', 'row_id': stableRowId},
                  const <String, dynamic>{
                    'scope': 'row',
                    'resource_ref': generatedRowRef,
                  },
                ],
                'affected_group_ids': const <String>[],
                'dissolved_group_ids': const <String>[],
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'mix-group',
                'operation': 'apply_goal',
                'target': <String, dynamic>{
                  'scope': 'group',
                  'group_resource_ref': groupRef,
                },
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'eq',
                    'direction': null,
                    'descriptor': 'warmth_boost',
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>['warm'],
                'reset_fx': false,
                'reference': null,
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'mix-all',
                'operation': 'apply_goal',
                'target': <String, dynamic>{'scope': 'all_rows'},
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'reverb',
                    'direction': 'up',
                    'descriptor': null,
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>[],
                'reset_fx': false,
                'reference': null,
              },
            },
            <String, dynamic>{
              'type': 'v3_group_edit',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'group.set_collapsed',
                'operation': 'set_collapsed',
                'collapsed': true,
                'target': <String, dynamic>{
                  'scope': 'group',
                  'resource_ref': groupRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final appliedRows =
          (applied['rows'] as List).cast<Map<String, dynamic>>();
      final generated = appliedRows.singleWhere(
        (row) => row['name'] == 'Generated Drums',
      );
      final stable = appliedRows.singleWhere(
        (row) => row['row_id'] == stableRowId,
      );
      expect(
        await controller.effectChain(appliedRows.indexOf(generated)),
        isNotEmpty,
      );
      expect(
        await controller.effectChain(appliedRows.indexOf(stable)),
        isNotEmpty,
      );
      expect(_group(applied, groupId)['collapsed'], isTrue);
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['clips'], before['clips']);
      expect(controller.snapshot()['groups'], before['groups']);
      await controller.redo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(controller.snapshot()['clips'], applied['clips']);
      expect(controller.snapshot()['groups'], applied['groups']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 materializes master mixing after generation and continues the chain',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'audio_reference_valid',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();
      final initialRows = (before['rows'] as List).length;
      const generatedRowRef = <String, dynamic>{
        'command_id': 'master-generated-row',
        'output': 'row',
      };

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'master-generated-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': initialRows,
                'name': 'Generated After Master',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'polish-master',
                'operation': 'apply_goal',
                'target': <String, dynamic>{'scope': 'master'},
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'reverb',
                    'direction': 'up',
                    'descriptor': null,
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>[],
                'reset_fx': false,
                'reference': null,
              },
            },
            <String, dynamic>{
              'type': 'row_mute',
              'data': const <String, dynamic>{
                'resource_consumer_type': 'row.set_muted',
                'operation': 'set_muted',
                'muted': true,
                'expected_muted': true,
                'target': <String, dynamic>{
                  'scope': 'row',
                  'resource_ref': generatedRowRef,
                },
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 2));

      final applied = controller.snapshot();
      final generated = (applied['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['name'] == 'Generated After Master');
      expect(generated['muted'], isTrue);
      expect(
        _effectNames(applied['master_effects']),
        contains(contains('Reverb')),
      );
      expect(applied['undo_depth'], (before['undo_depth'] as int) + 1);

      await controller.undo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], before['rows']);
      expect(controller.snapshot()['master_effects'], before['master_effects']);
      await controller.redo().timeout(const Duration(seconds: 20));
      expect(controller.snapshot()['rows'], applied['rows']);
      expect(
        controller.snapshot()['master_effects'],
        applied['master_effects'],
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'V3 rolls back preceding changes when deferred master mixing has no signal',
    (tester) async {
      _ignoreKnownEditorSemanticsAssertion();
      final fixture = await _openAudioFixture(
        tester,
        fixtureId: 'empty_one_row',
      );
      final controller = fixture.controller;
      final before = controller.snapshot();

      await controller.executeV3Handoff(
        _handoff(
          digest: controller.stateDigest,
          actions: <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'row_create',
              'data': <String, dynamic>{
                'command_id': 'empty-master-row',
                'operation': 'create',
                'position': 'end',
                'predicted_row_index': (before['rows'] as List).length,
                'name': 'Still Empty',
                'lane_kind': 'audio',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            },
            <String, dynamic>{
              'type': 'v3_deferred_mix_goal',
              'data': const <String, dynamic>{
                'command_id': 'empty-master-mix',
                'operation': 'apply_goal',
                'target': <String, dynamic>{'scope': 'master'},
                'intents': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'kind': 'reverb',
                    'direction': 'up',
                    'descriptor': null,
                  },
                ],
                'intensity': 0.5,
                'execution_profile': 'producer_safe',
                'audibility': 'noticeable',
                'style_tags': <String>[],
                'reset_fx': false,
                'reference': null,
              },
            },
          ],
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));

      final after = controller.snapshot();
      expect(after['rows'], before['rows']);
      expect(after['clips'], before['clips']);
      expect(after['master_effects'], before['master_effects']);
      expect(after['undo_depth'], before['undo_depth']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

enum _StemTempoOrder { tempoLast, tempoFirst, multipleTempos }

void _registerCompositionalStemTempoTest({
  required String name,
  required _StemTempoOrder order,
}) {
  testWidgets(name, (tester) async {
    _ignoreKnownEditorSemanticsAssertion();
    final fixture = await _openAudioFixture(
      tester,
      fixtureId: 'audio_reference_valid',
      stemSeparatorOverride:
          ({
            required String inputPath,
            required String vocalsOutputPath,
            required String instrumentalOutputPath,
          }) async {
            await File(inputPath).copy(vocalsOutputPath);
            await File(inputPath).copy(instrumentalOutputPath);
          },
      sampleDurationOverride: (_) async => const Duration(milliseconds: 1200),
    );
    final controller = fixture.controller;
    final before = controller.snapshot();
    final rows = (before['rows'] as List).cast<Map<String, dynamic>>();
    final clips = (before['clips'] as List).cast<Map<String, dynamic>>();
    final source = clips.firstWhere((clip) => clip['kind'] == 'audio');
    final sourceRowIndex = rows.indexWhere(
      (row) => row['row_id'] == source['row_id'],
    );
    final initialUndoDepth = before['undo_depth'] as int;
    final suffix = switch (order) {
      _StemTempoOrder.tempoLast => 'tempo_last',
      _StemTempoOrder.tempoFirst => 'tempo_first',
      _StemTempoOrder.multipleTempos => 'multiple_tempos',
    };
    final finalTempo = order == _StemTempoOrder.multipleTempos ? 90.0 : 110.0;

    final separateAction = <String, dynamic>{
      'type': 'v3_clip_separate_stems',
      'data': <String, dynamic>{
        'command_id': 'stems_$suffix',
        'source_clip_id': source['clip_id'],
        'source_row_id': source['row_id'],
        'source_row_index': sourceRowIndex,
        'start_ms': source['start_ms'],
        'duration_ms': source['length_ms'],
        'vocals_label': 'Composed Vocals $suffix',
        'instrumental_label': 'Composed Instrumental $suffix',
        'target': <String, dynamic>{
          'scope': 'clip',
          'clip_id': source['clip_id'],
          'clip_index': clips.indexOf(source),
          'row_id': source['row_id'],
          'row_index': sourceRowIndex,
        },
      },
    };
    final pitchAction = <String, dynamic>{
      'type': 'clip_edit',
      'data': <String, dynamic>{
        'command_id': 'pitch_$suffix',
        'resource_consumer_type': 'clip.set_pitch_semitones',
        'operation': 'pitch_shift',
        'mode': 'set',
        'new_pitch_semitones': -1.0,
        'target': <String, dynamic>{
          'scope': 'clip',
          'resource_ref': <String, dynamic>{
            'command_id': 'stems_$suffix',
            'output': 'instrumental_clip',
          },
        },
      },
    };
    Map<String, dynamic> tempoAction(double bpm) => <String, dynamic>{
      'type': 'project_edit',
      'data': <String, dynamic>{
        'command_id': 'tempo_${bpm.round()}_$suffix',
        'operation': 'set_tempo',
        'tempo_bpm': bpm,
        'time_stretch_audio': false,
        'preserve_pitch': true,
        'target': const <String, dynamic>{'scope': 'project'},
      },
    };
    final actions = switch (order) {
      _StemTempoOrder.tempoLast => <Map<String, dynamic>>[
        separateAction,
        pitchAction,
        tempoAction(110.0),
      ],
      _StemTempoOrder.tempoFirst => <Map<String, dynamic>>[
        tempoAction(110.0),
        separateAction,
        pitchAction,
      ],
      _StemTempoOrder.multipleTempos => <Map<String, dynamic>>[
        separateAction,
        pitchAction,
        tempoAction(110.0),
        tempoAction(90.0),
      ],
    };

    await controller.executeV3Handoff(
      _handoff(digest: controller.stateDigest, actions: actions),
    );
    await _pumpFor(tester, const Duration(seconds: 2));

    final applied = controller.snapshot();
    final appliedClips = (applied['clips'] as List)
        .cast<Map<String, dynamic>>();
    final vocals = appliedClips.singleWhere(
      (clip) => clip['label'] == 'Composed Vocals $suffix',
    );
    final instrumental = appliedClips.singleWhere(
      (clip) => clip['label'] == 'Composed Instrumental $suffix',
    );
    expect(applied['tempo_bpm'], closeTo(finalTempo, 0.0005));
    expect(appliedClips, hasLength(clips.length + 2));
    expect((applied['rows'] as List), hasLength(rows.length + 2));
    expect(
      appliedClips.singleWhere(
        (clip) => clip['clip_id'] == source['clip_id'],
      )['pitch_semitones'],
      0.0,
    );
    expect(vocals['pitch_semitones'], 0.0);
    expect(instrumental['pitch_semitones'], -1.0);
    expect(_row(applied, sourceRowIndex)['muted'], isFalse);
    expect(applied['undo_depth'], initialUndoDepth + 1);
    expect(await File(vocals['file'].toString()).exists(), isTrue);
    expect(await File(instrumental['file'].toString()).exists(), isTrue);

    await controller.undo();
    final undone = controller.snapshot();
    expect(undone['rows'], before['rows']);
    expect(undone['clips'], before['clips']);
    expect(undone['tempo_bpm'], before['tempo_bpm']);
    expect(undone['undo_depth'], initialUndoDepth);

    await controller.redo();
    final redone = controller.snapshot();
    expect(redone['rows'], applied['rows']);
    expect(redone['clips'], applied['clips']);
    expect(redone['tempo_bpm'], applied['tempo_bpm']);
    expect(redone['undo_depth'], initialUndoDepth + 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _ignoreKnownEditorSemanticsAssertion() {
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains(
          'A SemanticsNode with action "increase" needs to be annotated',
        ) ||
        (message.contains("'package:flutter/src/rendering/object.dart'") &&
            message.contains("'node.built'"))) {
      return;
    }
    previousHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousHandler);
}

Future<({AudioEditorEvaluationController controller, Directory directory})>
    _openAudioFixture(
  WidgetTester tester, {
  String fixtureId = 'audio_small',
  AudioEditorStemSeparatorOverride? stemSeparatorOverride,
  AudioEditorSampleDurationOverride? sampleDurationOverride,
  AudioEditorBasicPitchOverride? basicPitchOverride,
}) async {
  await deleteAllProjects();
  final fixture = await createDevelopmentEvalFixture(fixtureId);
  final controller = AudioEditorEvaluationController();
  await tester.pumpWidget(
    buildIntegrationTestApp(
      home: AudioEditorScreen(
        mode: 'edit',
        projectDir: fixture.directory,
        isProEntitled: true,
        evaluationController: controller,
        stemSeparatorOverride: stemSeparatorOverride,
        sampleDurationOverride: sampleDurationOverride,
        basicPitchOverride: basicPitchOverride,
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => controller.isAttached && controller.snapshot()['rows'] is List,
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  return (controller: controller, directory: fixture.directory);
}

Map<String, dynamic> _handoff({
  required String digest,
  required List<Map<String, dynamic>> actions,
}) => <String, dynamic>{
  'schema_version': 'ai_v3_handoff_prototype_1',
  'decision': 'execute_now',
  'plan_id': 'atomic-transaction-test',
  'execution_policy': 'auto_apply',
  'prepared_bundle': <String, dynamic>{
    'state_digest': digest,
    'execution_policy': 'auto_apply',
    'plan': const <String, dynamic>{
      'user_message': 'Applying verified test changes.',
    },
    'actions': actions,
    'receipts': <Map<String, dynamic>>[
      for (var index = 0; index < actions.length; index++)
        <String, dynamic>{
          'command_id': _commandIdForAction(actions[index], index),
          'type': actions[index]['type'],
          'status': 'prepared',
          'preview_label': 'Apply ${actions[index]['type']}',
        },
    ],
  },
};

String _commandIdForAction(Map<String, dynamic> action, int index) {
  final data = action['data'];
  final commandId = data is Map
      ? data['command_id']?.toString().trim() ?? ''
      : '';
  return commandId.isEmpty ? 'test-$index' : commandId;
}

Map<String, dynamic> _muteAction(int rowIndex, int rowId,
        [bool muted = true]) =>
    <String, dynamic>{
      'type': 'row_mute',
      'data': <String, dynamic>{
        'operation': muted ? 'mute' : 'unmute',
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _transportAction(
  String operation, {
  bool? playing,
  bool? enabled,
}) =>
    <String, dynamic>{
      'type': 'v3_transport',
      'data': <String, dynamic>{
        'operation': operation,
        if (playing != null) 'playing': playing,
        if (enabled != null) 'enabled': enabled,
        'target': const <String, dynamic>{'scope': 'project'},
      },
    };

Map<String, dynamic> _phoneMicCleanupAction(
  int rowIndex,
  int rowId,
  List<String> clipIds,
) =>
    <String, dynamic>{
      'type': 'v3_phone_mic_cleanup',
      'data': <String, dynamic>{
        'operation': 'apply',
        'effect_ids': aiV3PhoneMicCleanupEffectIds,
        'audio_clip_ids': clipIds,
        'preset': aiV3PhoneMicCleanupPreset,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _renameAction(int rowIndex, int rowId, String name) =>
    <String, dynamic>{
      'type': 'row_rename',
      'data': <String, dynamic>{
        'operation': 'rename',
        'new_name': name,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _roleOverrideAction(
  int rowIndex,
  int rowId,
  String? role,
) =>
    <String, dynamic>{
      'type': 'v3_row_role_override',
      'data': <String, dynamic>{
        'role': role,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _selectAction(int rowIndex, int rowId) =>
    <String, dynamic>{
      'type': 'row_select',
      'data': <String, dynamic>{
        'operation': 'select',
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _createRowAction({
  required String name,
  required String position,
  required int anchorRowIndex,
  required int anchorRowId,
}) =>
    <String, dynamic>{
      'type': 'row_create',
      'data': <String, dynamic>{
        'operation': 'create',
        'name': name,
        'lane_kind': 'audio',
        'position': position,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': anchorRowIndex,
          'row_id': anchorRowId,
        },
      },
    };

Map<String, dynamic> _deleteRowAction(int rowIndex, int rowId) =>
    <String, dynamic>{
      'type': 'row_delete',
      'data': <String, dynamic>{
        'operation': 'delete',
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _groupCreateAction(
  String groupId,
  String name,
  List<int> rowIds,
  List<int> expectedRowOrder,
) =>
    <String, dynamic>{
      'type': 'v3_group_edit',
      'data': <String, dynamic>{
        'operation': 'create',
        'group_id': groupId,
        'name': name,
        'row_ids': rowIds,
        'expected_row_order': expectedRowOrder,
        'affected_group_ids': const <String>[],
        'dissolved_group_ids': const <String>[],
      },
    };

Map<String, dynamic> _groupRemoveRowAction(
  String groupId,
  int rowId, {
  required bool dissolvesGroup,
}) =>
    <String, dynamic>{
      'type': 'v3_group_edit',
      'data': <String, dynamic>{
        'operation': 'remove_row',
        'group_id': groupId,
        'row_id': rowId,
        'dissolves_group': dissolvesGroup,
        'expected_member_row_ids': const <int>[],
      },
    };

Map<String, dynamic> _groupCollapsedAction(String groupId, bool collapsed) =>
    <String, dynamic>{
      'type': 'v3_group_edit',
      'data': <String, dynamic>{
        'operation': 'set_collapsed',
        'group_id': groupId,
        'collapsed': collapsed,
      },
    };

Map<String, dynamic> _colorAction(
  int rowIndex,
  int rowId,
  String color,
) =>
    <String, dynamic>{
      'type': 'row_color_edit',
      'data': <String, dynamic>{
        'operation': color == 'none' ? 'clear' : 'set',
        'color': color,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _rowMixAction(
  int rowIndex,
  int rowId,
  String operation, {
  double? gainDb,
  double? deltaSigned,
  double? panSigned,
}) =>
    <String, dynamic>{
      'type': 'row_mix',
      'data': <String, dynamic>{
        'operation': operation,
        if (gainDb != null) 'gain_db': gainDb,
        if (deltaSigned != null) 'delta': deltaSigned,
        if (panSigned != null) 'pan_signed': panSigned,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _soloAction(int rowIndex, int rowId, bool soloed) =>
    <String, dynamic>{
      'type': 'row_solo',
      'data': <String, dynamic>{
        'operation': 'set_soloed',
        'soloed': soloed,
        'target': <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

List<String> _effectNames(Object? raw) => (raw as List? ?? const <Object>[])
    .whereType<Map>()
    .map((effect) =>
        (effect['display_name'] ?? effect['effect_id'] ?? '').toString())
    .toList(growable: false);

Map<String, dynamic> _clipAction(
  String operation,
  Map<String, dynamic> clip,
  Map<String, dynamic> row, {
  Map<String, dynamic> extra = const <String, dynamic>{},
}) =>
    <String, dynamic>{
      'type': 'clip_edit',
      'data': <String, dynamic>{
        'operation': operation,
        ...extra,
        'target': <String, dynamic>{
          'scope': 'clip',
          'clip_id': clip['clip_id'],
          'clip_index': (clip['display_index'] ?? clip['clip_index']) ?? 0,
          'row_id': row['row_id'],
          'row_index': clip['row_index'],
        },
      },
    };

Map<String, dynamic> _glueAction({
  required List<String> clipIds,
  required int rowIndex,
  required int rowId,
  required double startMs,
  required double durationMs,
  required String label,
}) =>
    <String, dynamic>{
      'type': 'v3_clip_glue',
      'data': <String, dynamic>{
        'source_clip_ids': clipIds,
        'label': label,
        'start_ms': startMs,
        'duration_ms': durationMs,
        'target': <String, dynamic>{
          'scope': 'clips',
          'source_clip_ids': clipIds,
          'row_index': rowIndex,
          'row_id': rowId,
        },
      },
    };

Map<String, dynamic> _midiReplaceAction(
  Map<String, dynamic> clip,
  List<Map<String, dynamic>> notes, {
  double? finalLengthBeats,
}) =>
    <String, dynamic>{
      'type': 'midi_compose',
      'data': <String, dynamic>{
        'operation': 'replace_notes',
        'notes': notes,
        'exact_notes': true,
        'preserve_existing_notes': false,
        'preserve_clip_state': true,
        if (finalLengthBeats != null) 'final_length_beats': finalLengthBeats,
        'target': <String, dynamic>{
          'scope': 'clip',
          'clip_id': clip['clip_id'],
          'clip_index': clip['clip_index'],
          'row_id': clip['row_id'],
          'row_index': clip['row_index'],
        },
      },
    };

Map<String, dynamic> _row(Map<String, dynamic> snapshot, int index) =>
    ((snapshot['rows'] as List)[index] as Map).cast<String, dynamic>();

Map<String, dynamic> _group(Map<String, dynamic> snapshot, String groupId) =>
    (snapshot['groups'] as List)
        .whereType<Map>()
        .map((value) => value.cast<String, dynamic>())
        .singleWhere((group) => group['group_id'] == groupId);

Map<String, dynamic> _clip(Map<String, dynamic> snapshot, String clipId) =>
    (snapshot['clips'] as List)
        .whereType<Map>()
        .map((value) => value.cast<String, dynamic>())
        .singleWhere((clip) => clip['clip_id'] == clipId);

Map<String, dynamic> _plannerVisibleEvaluationState(
  Map<String, dynamic> snapshot,
) {
  final result = Map<String, dynamic>.from(snapshot)
    ..remove('undo_depth')
    ..remove('redo_depth')
    ..remove('transport');
  result['clips'] = (snapshot['clips'] as List).whereType<Map>().map((raw) {
    final clip = Map<String, dynamic>.from(raw);
    if (clip['kind'] == 'midi') {
      // MIDI render slots are native playback details, not planner-visible
      // source identities. The stable clip ID, notes, and instrument are.
      clip.remove('file');
    }
    return clip;
  }).toList(growable: false);
  return result;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timed out waiting for the audio editor.');
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 100));
    elapsed += const Duration(milliseconds: 100);
  }
}
