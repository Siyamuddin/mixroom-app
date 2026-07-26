import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test(
      'sample replacement applies, undoes, redoes, and persists exact payloads',
      () async {
    final before = <String, dynamic>{
      'clipId': 'clip-a',
      'fileName': 'old.wav',
      'gain': 1.25,
    };
    final after = <String, dynamic>{
      'clipId': 'clip-a',
      'fileName': 'new.wav',
      'gain': 1.25,
    };
    var current = <String, dynamic>{...before};
    final action = ReplaceAudioClipSourceAction(
      beforePayload: before,
      afterPayload: after,
      applyPayload: (payload) async {
        current = <String, dynamic>{...payload};
      },
    );

    await action.redo();
    expect(current, after);
    await action.undo();
    expect(current, before);
    await action.redo();
    expect(current, after);

    final persisted = action.toPersistedUndoCommand();
    expect(persisted['type'], 'clipSourceReplace');
    expect(persisted['beforeClip'], before);
    expect(persisted['afterClip'], after);
  });

  test('sample replacement propagates apply failures', () async {
    final action = ReplaceAudioClipSourceAction(
      beforePayload: const <String, dynamic>{
        'clipId': 'clip-a',
        'fileName': 'old.wav',
      },
      afterPayload: const <String, dynamic>{
        'clipId': 'clip-a',
        'fileName': 'new.wav',
      },
      applyPayload: (_) async => throw StateError('native load failed'),
    );

    await expectLater(action.redo(), throwsStateError);
  });
}
