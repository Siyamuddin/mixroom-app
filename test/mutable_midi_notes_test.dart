import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/mutable_midi_notes.dart';
import 'package:mixroom/models/models.dart';

void main() {
  test('copied empty MIDI state remains growable for the next take', () {
    final notes = copyMidiNotesForEditing(const <MidiNote>[]);

    notes.add(
      MidiNote(
        id: 'recorded-note',
        pitch: 60,
        velocity: 0.8,
        startBeat: 0,
        lengthBeats: 1,
      ),
    );

    expect(notes, hasLength(1));
  });

  test('copy does not alias notes from undo state', () {
    final source = MidiNote(
      id: 'source-note',
      pitch: 60,
      velocity: 0.8,
      startBeat: 0,
      lengthBeats: 1,
    );

    final notes = copyMidiNotesForEditing(<MidiNote>[source]);

    expect(notes.single, isNot(same(source)));
  });
}
