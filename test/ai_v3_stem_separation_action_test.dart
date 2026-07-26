import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';

void main() {
  test('stem separation action reuses stable clip payloads on redo', () async {
    final transitions = <bool>[];
    final vocals = <String, dynamic>{'clipId': 'vocals-1'};
    final instrumental = <String, dynamic>{'clipId': 'instrumental-1'};
    final action = StemSeparationAction(
      sourceRowId: 10,
      vocalsPayload: vocals,
      instrumentalPayload: instrumental,
      beforeSelectedClipIds: const <String>['source-1'],
      beforePrimaryClipId: 'source-1',
      beforeSelectedRowId: 10,
      applySnapshot: ({
        required int sourceRowId,
        required Map<String, dynamic> vocalsPayload,
        required Map<String, dynamic> instrumentalPayload,
        required List<String> beforeSelectedClipIds,
        required String beforePrimaryClipId,
        required int? beforeSelectedRowId,
        required bool separated,
      }) async {
        expect(sourceRowId, 10);
        expect(vocalsPayload['clipId'], 'vocals-1');
        expect(instrumentalPayload['clipId'], 'instrumental-1');
        transitions.add(separated);
      },
    );

    await action.redo();
    await action.undo();
    await action.redo();

    expect(transitions, <bool>[true, false, true]);
    expect(action.toPersistedUndoCommand()['type'], 'clipStemSeparation');
  });
}
