import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/screens/audio_editor.dart';
import 'package:mixroom/voice/voice_comparison.dart';

class _GainAction extends EditorUndoAction {
  _GainAction(this.apply, this.before, this.after);
  final void Function(double) apply;
  final double before;
  final double after;
  @override
  String get description => 'Vocal gain';
  @override
  Future<void> undo() async => apply(before);
  @override
  Future<void> redo() async => apply(after);
}

void main() {
  test(
    'A/B uses the real editor undo stack and keeps unrelated edits',
    () async {
      final manager = EditorUndoManager();
      var gain = 0.0;
      await manager.execute(_GainAction((value) => gain = value, 0, -1));
      final latest = CompoundUndoAction('AI changes', [
        _GainAction((value) => gain = value, -1, -4),
      ]);
      await manager.execute(latest);
      final comparison = VoiceComparison<EditorUndoAction>(
        action: latest,
        beforeDigest: '-1.0',
        afterDigest: '-4.0',
      );
      final saveObservations = <bool>[];
      manager.addListener(() => saveObservations.add(comparison.before));
      Future<bool> switchTo(bool before) => comparison.switchTo(
        before,
        undoHead: () => manager.latestUndoAction,
        redoHead: () => manager.latestRedoAction,
        fingerprint: () => gain.toString(),
        undo: manager.undo,
        redo: manager.redo,
        refresh: () async {},
      );
      expect(await switchTo(true), isTrue);
      expect(gain, -1);
      expect(manager.undoDepth, 1);
      expect(comparison.before, isTrue);
      expect(await switchTo(false), isTrue);
      expect(gain, -4);
      expect(manager.undoDepth, 2);
      expect(comparison.before, isFalse);
      expect(saveObservations, [
        true,
        true,
      ], reason: 'Autosave is suppressed during both graph transitions.');
    },
  );

  test('intervening manual edit cannot be undone by stale A/B', () async {
    final manager = EditorUndoManager();
    var gain = 0.0;
    final ai = _GainAction((value) => gain = value, 0, -3);
    await manager.execute(ai);
    final comparison = VoiceComparison<EditorUndoAction>(
      action: ai,
      beforeDigest: '0.0',
      afterDigest: '-3.0',
    );
    await manager.execute(_GainAction((value) => gain = value, -3, -7));
    expect(
      await comparison.switchTo(
        true,
        undoHead: () => manager.latestUndoAction,
        redoHead: () => manager.latestRedoAction,
        fingerprint: () => gain.toString(),
        undo: manager.undo,
        redo: manager.redo,
        refresh: () async {},
      ),
      isFalse,
    );
    expect(gain, -7);
    expect(manager.undoDepth, 2);
  });

  test(
    'failed A readback restores committed B and releases save suppression',
    () async {
      final manager = EditorUndoManager();
      var gain = 0.0;
      final ai = _GainAction((value) => gain = value, 0, -3);
      await manager.execute(ai);
      final comparison = VoiceComparison<EditorUndoAction>(
        action: ai,
        beforeDigest: 'wrong-before',
        afterDigest: '-3.0',
      );
      expect(
        await comparison.switchTo(
          true,
          undoHead: () => manager.latestUndoAction,
          redoHead: () => manager.latestRedoAction,
          fingerprint: () => gain.toString(),
          undo: manager.undo,
          redo: manager.redo,
          refresh: () async {},
        ),
        isFalse,
      );
      expect(gain, -3);
      expect(manager.latestUndoAction, same(ai));
      expect(comparison.before, isFalse);
    },
  );
}
