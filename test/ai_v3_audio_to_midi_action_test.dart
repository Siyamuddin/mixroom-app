import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('audio-to-MIDI action reuses captured notes and stable clip ID on redo',
      () async {
    final transitions = <bool>[];
    final result = <String, dynamic>{
      'clipId': 'audio-midi-1',
      'instrumentId': 'piano',
      'midiNotes': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'note-1',
          'pitch': 60,
          'startBeat': 0.0,
          'lengthBeats': 1.0,
          'velocity': 0.8,
        },
      ],
    };
    final action = AudioToMidiConversionAction(
      sourceRowId: 10,
      resultPayload: result,
      beforeSelectedClipIds: const <String>['source-1'],
      beforePrimaryClipId: 'source-1',
      beforeSelectedRowId: 10,
      applySnapshot: ({
        required int sourceRowId,
        required Map<String, dynamic> resultPayload,
        required List<String> beforeSelectedClipIds,
        required String beforePrimaryClipId,
        required int? beforeSelectedRowId,
        required bool converted,
      }) async {
        expect(sourceRowId, 10);
        expect(resultPayload['clipId'], 'audio-midi-1');
        expect((resultPayload['midiNotes'] as List), hasLength(1));
        transitions.add(converted);
      },
    );

    await action.redo();
    await action.undo();
    await action.redo();

    expect(transitions, <bool>[true, false, true]);
    expect(action.toPersistedUndoCommand()['type'], 'clipAudioToMidi');
  });
}
