import 'package:mixroom/models/models.dart';

List<MidiNote> copyMidiNotesForEditing(Iterable<MidiNote> notes) {
  return notes.map((note) => note.copy()).toList(growable: true);
}
