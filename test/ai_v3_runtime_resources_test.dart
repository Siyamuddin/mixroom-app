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
