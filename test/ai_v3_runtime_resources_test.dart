import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_resources.dart';
import 'package:mixroom/ai/v3/ai_v3_runtime_resources.dart';

void main() {
  test('binds and resolves only the exact typed producer output', () {
    final runtime = AiV3WorkflowRuntime();
    const instrumental = AiV3ResourceRef(
      commandId: 'separate',
      output: 'instrumental_clip',
    );
    runtime.bind(
      ref: instrumental,
      kind: AiV3ResourceKind.audioClip,
      stableId: 'runtime-instrumental',
    );

    expect(
      runtime
          .resolve(instrumental, expectedKind: AiV3ResourceKind.audioClip)
          .stableId,
      'runtime-instrumental',
    );
    expect(
      () => runtime.resolve(
        instrumental,
        expectedKind: AiV3ResourceKind.audioRow,
      ),
      throwsStateError,
    );
    expect(
      () => runtime.resolve(
        const AiV3ResourceRef(commandId: 'separate', output: 'vocals_clip'),
        expectedKind: AiV3ResourceKind.audioClip,
      ),
      throwsStateError,
    );
  });

  test('rejects duplicate and malformed runtime bindings', () {
    final runtime = AiV3WorkflowRuntime();
    const ref = AiV3ResourceRef(commandId: 'create', output: 'row');
    runtime.bind(ref: ref, kind: AiV3ResourceKind.audioRow, stableId: 42);
    expect(
      () =>
          runtime.bind(ref: ref, kind: AiV3ResourceKind.audioRow, stableId: 43),
      throwsStateError,
    );
    expect(
      () => AiV3WorkflowRuntime().bind(
        ref: ref,
        kind: AiV3ResourceKind.audioRow,
        stableId: 'not-a-row-id',
      ),
      throwsStateError,
    );
  });

  test('binds a generated MIDI clip with stable string identity', () {
    final runtime = AiV3WorkflowRuntime();
    const ref = AiV3ResourceRef(commandId: 'create-midi', output: 'midi_clip');
    runtime.bind(
      ref: ref,
      kind: AiV3ResourceKind.midiClip,
      stableId: 'runtime-midi-clip',
    );

    expect(
      runtime.resolve(ref, expectedKind: AiV3ResourceKind.midiClip).stableId,
      'runtime-midi-clip',
    );
    expect(
      () => runtime.resolve(ref, expectedKind: AiV3ResourceKind.audioClip),
      throwsStateError,
    );
  });

  test('binds and retires a generated group by stable string identity', () {
    final runtime = AiV3WorkflowRuntime();
    const ref = AiV3ResourceRef(commandId: 'create-group', output: 'group');
    runtime.bind(
      ref: ref,
      kind: AiV3ResourceKind.group,
      stableId: 'runtime-group',
    );

    expect(
      runtime.resolve(ref, expectedKind: AiV3ResourceKind.group).stableId,
      'runtime-group',
    );
    expect(
      () => runtime.resolve(ref, expectedKind: AiV3ResourceKind.audioRow),
      throwsStateError,
    );

    runtime.retire(ref);
    expect(
      () => runtime.resolve(ref, expectedKind: AiV3ResourceKind.group),
      throwsStateError,
    );
  });

  test('retires bindings whose stable resources were deleted', () {
    final runtime = AiV3WorkflowRuntime();
    const deleted = AiV3ResourceRef(commandId: 'place', output: 'audio_clip');
    const preserved = AiV3ResourceRef(commandId: 'other', output: 'audio_clip');
    runtime
      ..bind(
        ref: deleted,
        kind: AiV3ResourceKind.audioClip,
        stableId: 'deleted-clip',
      )
      ..bind(
        ref: preserved,
        kind: AiV3ResourceKind.audioClip,
        stableId: 'preserved-clip',
      )
      ..retireStableIds(<Object>{'deleted-clip'});

    expect(
      () => runtime.resolve(deleted, expectedKind: AiV3ResourceKind.audioClip),
      throwsStateError,
    );
    expect(
      runtime.resolve(preserved, expectedKind: AiV3ResourceKind.audioClip).stableId,
      'preserved-clip',
    );
  });

  test('row retirement preserves a copy bound to another row', () {
    final runtime = AiV3WorkflowRuntime();
    const row = AiV3ResourceRef(commandId: 'create-row', output: 'row');
    const source = AiV3ResourceRef(commandId: 'place', output: 'audio_clip');
    const copy = AiV3ResourceRef(commandId: 'copy-away', output: 'copy_clip');
    runtime
      ..bind(ref: row, kind: AiV3ResourceKind.audioRow, stableId: 42)
      ..bind(
        ref: source,
        kind: AiV3ResourceKind.audioClip,
        stableId: 'source-clip',
        parentRowRef: row,
      )
      ..bind(
        ref: copy,
        kind: AiV3ResourceKind.audioClip,
        stableId: 'copy-clip',
        parentRowKey: 'stable_row:100',
      )
      ..retireRowAndChildren(row);

    expect(
      () => runtime.resolve(source, expectedKind: AiV3ResourceKind.audioClip),
      throwsStateError,
    );
    expect(
      runtime.resolve(copy, expectedKind: AiV3ResourceKind.audioClip).stableId,
      'copy-clip',
    );
  });

  test('deletes tracked generated artifacts after workflow failure', () async {
    final directory = await Directory.systemTemp.createTemp('mixroom_v3_refs_');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final generated = File('${directory.path}/instrumental.wav');
    await generated.writeAsBytes(<int>[1, 2, 3]);
    final runtime = AiV3WorkflowRuntime()
      ..trackGeneratedArtifact(generated.path);

    expect(await runtime.deleteGeneratedArtifacts(), isTrue);
    expect(await generated.exists(), isFalse);
  });
}
