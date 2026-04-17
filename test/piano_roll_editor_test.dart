import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/piano_roll_editor.dart';

Future<AudioTrack> _buildMidiTrack(List<MidiNote> notes) {
  final file = File('/tmp/piano_roll_editor_test.mid');
  return AudioTrack.create(
    file: file,
    originalFile: file,
    audioDuration: const Duration(seconds: 8),
    trimEnd: const Duration(seconds: 8),
    engineClipId: 101,
    label: 'Test MIDI',
    clipKind: ClipKind.midi,
    instrumentId: 'synth.test',
    instrumentName: 'Test Synth',
    midiNotes: notes,
  );
}

Widget _buildEditor({
  required AudioTrack clip,
  required MidiCommitCallback onCommit,
}) {
  return MaterialApp(
    home: Material(
      child: Center(
        child: SizedBox(
          width: 900,
          height: 620,
          child: PianoRollEditor(
            clip: clip,
            availableInstruments: const <Map<String, dynamic>>[],
            bpm: 120,
            beatsPerBar: 4,
            projectPlayheadMs: 0,
            isPlaying: false,
            magnetEnabled: true,
            quantizeDivisionsPerBar: 4,
            fullscreen: false,
            onFullscreenChanged: (_) {},
            onClose: () {},
            onCommit: onCommit,
          ),
        ),
      ),
    ),
  );
}

Future<void> _boxSelectNotes(WidgetTester tester) async {
  final firstNote = find.byKey(const ValueKey<String>('piano_note_a'));
  final lastNote = find.byKey(const ValueKey<String>('piano_note_b'));
  final firstTopLeft = tester.getTopLeft(firstNote);
  final lastBottomRight = tester.getBottomRight(lastNote);
  final gesture = await tester.startGesture(
    Offset(firstTopLeft.dx - 18, firstTopLeft.dy + 6),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 80));
  await gesture.moveTo(
    Offset(lastBottomRight.dx + 18, lastBottomRight.dy + 6),
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

MidiNote _noteById(List<MidiNote> notes, String id) {
  return notes.firstWhere((note) => note.id == id);
}

void main() {
  testWidgets('dragging a selected note moves the full multi-selection',
      (tester) async {
    List<MidiNote>? committedNotes;
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'a',
        pitch: 84,
        startBeat: 2,
        lengthBeats: 1,
        velocity: 0.7,
      ),
      MidiNote(
        id: 'b',
        pitch: 82,
        startBeat: 4,
        lengthBeats: 1,
        velocity: 0.8,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {
          committedNotes = notes.map((note) => note.copy()).toList();
        },
      ),
    );
    await tester.pumpAndSettle();

    await _boxSelectNotes(tester);

    expect(
      find.byKey(const ValueKey<String>('piano_note_handle_a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('piano_note_handle_b')),
      findsOneWidget,
    );

    final noteAFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final beforeMove = tester.getTopLeft(noteAFinder);
    final moveGesture =
        await tester.startGesture(tester.getCenter(noteAFinder));
    await tester.pump(const Duration(milliseconds: 50));
    await moveGesture.moveBy(const Offset(56, 0));
    await tester.pump();
    await moveGesture.up();
    await tester.pumpAndSettle();

    final afterMove = tester.getTopLeft(noteAFinder);
    expect(afterMove.dx, greaterThan(beforeMove.dx));
    expect(committedNotes, isNotNull);
    expect(_noteById(committedNotes!, 'a').startBeat, 3);
    expect(_noteById(committedNotes!, 'b').startBeat, 5);
  });

  testWidgets('dragging a selected resize handle resizes the full selection',
      (tester) async {
    List<MidiNote>? committedNotes;
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'a',
        pitch: 84,
        startBeat: 2,
        lengthBeats: 1,
        velocity: 0.7,
      ),
      MidiNote(
        id: 'b',
        pitch: 82,
        startBeat: 4,
        lengthBeats: 1,
        velocity: 0.8,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {
          committedNotes = notes.map((note) => note.copy()).toList();
        },
      ),
    );
    await tester.pumpAndSettle();

    await _boxSelectNotes(tester);

    final handleFinder =
        find.byKey(const ValueKey<String>('piano_note_handle_a'));
    final beforeResize =
        tester.getSize(find.byKey(const ValueKey<String>('piano_note_a')));
    final resizeGesture =
        await tester.startGesture(tester.getCenter(handleFinder));
    await tester.pump(const Duration(milliseconds: 50));
    await resizeGesture.moveBy(const Offset(56, 0));
    await tester.pump();
    await resizeGesture.up();
    await tester.pumpAndSettle();

    final afterResize =
        tester.getSize(find.byKey(const ValueKey<String>('piano_note_a')));
    expect(afterResize.width, greaterThan(beforeResize.width));
    expect(
      find.byKey(const ValueKey<String>('piano_note_handle_b')),
      findsOneWidget,
    );

    expect(committedNotes, isNotNull);
    expect(_noteById(committedNotes!, 'a').lengthBeats, 2);
    expect(_noteById(committedNotes!, 'b').lengthBeats, 2);
  });

  testWidgets(
      'reloads note layout when parent rebuilds with the same updated clip instance',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'a',
        pitch: 84,
        startBeat: 2,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ]);

    Future<void> pumpEditor() async {
      await tester.pumpWidget(
        _buildEditor(
          clip: clip,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpEditor();

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final beforeTopLeft = tester.getTopLeft(noteFinder);
    final beforeSize = tester.getSize(noteFinder);

    clip.midiNotes = <MidiNote>[
      MidiNote(
        id: 'a',
        pitch: 84,
        startBeat: 4,
        lengthBeats: 2,
        velocity: 0.7,
      ),
    ];

    await pumpEditor();

    final afterTopLeft = tester.getTopLeft(noteFinder);
    final afterSize = tester.getSize(noteFinder);

    expect(afterTopLeft.dx, greaterThan(beforeTopLeft.dx));
    expect(afterSize.width, greaterThan(beforeSize.width));
  });
}
