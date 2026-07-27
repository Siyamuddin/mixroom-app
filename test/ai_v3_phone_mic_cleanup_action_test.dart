import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('phone cleanup metadata applies, undoes, redoes, and persists',
      () async {
    var current = <String, String>{
      'clip-a': '',
      'clip-b': 'older_cleanup',
    };
    final action = PhoneMicCleanupMetadataAction(
      beforePresets: current,
      preset: 'phone_mic_cleanup_v1',
      applyPresets: (presets) async {
        current = Map<String, String>.from(presets);
      },
    );

    await action.redo();
    expect(current, <String, String>{
      'clip-a': 'phone_mic_cleanup_v1',
      'clip-b': 'phone_mic_cleanup_v1',
    });

    await action.undo();
    expect(current, <String, String>{
      'clip-a': '',
      'clip-b': 'older_cleanup',
    });

    await action.redo();
    expect(current.values, everyElement('phone_mic_cleanup_v1'));
    expect(action.toPersistedUndoCommand(), <String, dynamic>{
      'type': 'phoneMicCleanupMetadata',
      'beforePresets': <String, String>{
        'clip-a': '',
        'clip-b': 'older_cleanup',
      },
      'preset': 'phone_mic_cleanup_v1',
    });
  });

  test('phone cleanup metadata propagates stable-clip failures', () async {
    final action = PhoneMicCleanupMetadataAction(
      beforePresets: const <String, String>{'missing': ''},
      preset: 'phone_mic_cleanup_v1',
      applyPresets: (_) async => throw StateError('missing stable clip'),
    );

    await expectLater(action.redo(), throwsStateError);
  });
}
