import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/piano_roll_editor.dart';

Future<AudioTrack> _buildMidiTrack(
  List<MidiNote> notes, {
  String instrumentId = 'synth.test',
  String instrumentName = 'Test Synth',
}) {
  final file = File('/tmp/piano_roll_editor_test.mid');
  return AudioTrack.create(
    file: file,
    originalFile: file,
    audioDuration: const Duration(seconds: 8),
    trimEnd: const Duration(seconds: 8),
    engineClipId: 101,
    label: 'Test MIDI',
    clipKind: ClipKind.midi,
    instrumentId: instrumentId,
    instrumentName: instrumentName,
    midiNotes: notes,
  );
}

Widget _buildEditor({
  required AudioTrack clip,
  required MidiCommitCallback onCommit,
  double projectPlayheadMs = 0,
  bool isPlaying = false,
  bool isRecording = false,
  Future<void> Function(int pitch, double velocity)? onPreviewNote,
  PianoKeyDownCallback? onKeyboardNoteDown,
  PianoKeyUpCallback? onKeyboardNoteUp,
  PlayableMidiPitchesResolver? resolvePlayablePitches,
  List<Map<String, dynamic>> availableInstruments =
      const <Map<String, dynamic>>[],
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 900,
          height: 620,
          child: PianoRollEditor(
            clip: clip,
            availableInstruments: availableInstruments,
            bpm: 120,
            beatsPerBar: 4,
            projectPlayheadMs: projectPlayheadMs,
            isPlaying: isPlaying,
            isRecording: isRecording,
            magnetEnabled: true,
            quantizeDivisionsPerBar: 4,
            fullscreen: false,
            onFullscreenChanged: (_) {},
            onClose: () {},
            onCommit: onCommit,
            onScrubRequested: (_) {},
            onPreviewNote: onPreviewNote,
            onKeyboardNoteDown: onKeyboardNoteDown,
            onKeyboardNoteUp: onKeyboardNoteUp,
            resolvePlayablePitches: resolvePlayablePitches,
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
  await tester.pump(const Duration(milliseconds: 120));
}

MidiNote _noteById(List<MidiNote> notes, String id) {
  return notes.firstWhere((note) => note.id == id);
}

void main() {
  testWidgets(
    'guitar instrument panel uses the shared guitar visual treatment',
    (tester) async {
      final clip = await _buildMidiTrack(
        const <MidiNote>[],
        instrumentId: 'sfz.guitar.steel_acoustic',
        instrumentName: 'Acoustic Guitar',
      );
      await tester.pumpWidget(
        _buildEditor(
          clip: clip,
          onCommit:
              ({
                required notes,
                required instrumentParams,
                required instrumentId,
                required instrumentName,
              }) async {},
          availableInstruments: const <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sfz.guitar.steel_acoustic',
              'name': 'Acoustic Guitar',
              'pickerCategory': 'Guitars',
              'isSampled': true,
            },
          ],
        ),
      );

      await tester.tap(find.text('Instrument').last);
      await tester.pumpAndSettle();

      expect(find.text('Guitars'), findsWidgets);
      final guitarIcon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.guitars).first,
      );
      expect(guitarIcon.color, const Color(0xFF67A6FF));
    },
  );

  testWidgets('piano roll exposes every MIDI pitch from 0 through 127',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[]);

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
    await tester.pump(const Duration(milliseconds: 120));

    for (var pitch = 0; pitch <= 127; pitch++) {
      expect(
        find.byKey(ValueKey<String>('piano_key_$pitch')),
        findsOneWidget,
        reason: 'MIDI pitch $pitch should have its own piano-roll row',
      );
    }
    expect(find.text('C-1'), findsOneWidget);
    expect(find.text('G9'), findsOneWidget);
  });

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
    await tester.pump(const Duration(milliseconds: 120));

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
    await tester.pump(const Duration(milliseconds: 120));

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
    await tester.pump(const Duration(milliseconds: 120));

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
    await tester.pump(const Duration(milliseconds: 120));

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

  testWidgets('newly added notes reuse the last resized note length',
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
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey<String>('piano_note_a')));
    await tester.pump(const Duration(milliseconds: 120));

    final handleFinder =
        find.byKey(const ValueKey<String>('piano_note_handle_a'));
    final resizeGesture =
        await tester.startGesture(tester.getCenter(handleFinder));
    await tester.pump(const Duration(milliseconds: 50));
    await resizeGesture.moveBy(const Offset(112, 0));
    await tester.pump();
    await resizeGesture.up();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 180)),
    );
    await tester.pump();

    expect(committedNotes, isNotNull);
    expect(_noteById(committedNotes!, 'a').lengthBeats, 3);

    final resizedRect =
        tester.getRect(find.byKey(const ValueKey<String>('piano_note_a')));
    await tester.tapAt(resizedRect.bottomRight + const Offset(80, 80));
    await tester.pump(const Duration(milliseconds: 220));

    expect(committedNotes, isNotNull);
    expect(committedNotes, hasLength(2));
    final added = committedNotes!.firstWhere((note) => note.id != 'a');
    expect(added.lengthBeats, 3);
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
      await tester.pump(const Duration(milliseconds: 120));
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

  testWidgets('two-finger pinch zoom scales the grid monotonically',
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
    await tester.pump(const Duration(milliseconds: 120));

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final editorTopLeft = tester.getTopLeft(find.byType(PianoRollEditor));
    final pinchCenter = editorTopLeft + const Offset(600, 360);
    final initialWidth = tester.getSize(noteFinder).width;

    final first = await tester.startGesture(
      pinchCenter + const Offset(-28, -18),
      pointer: 11,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      pinchCenter + const Offset(28, 18),
      pointer: 12,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.moveBy(const Offset(-24, -16));
    await second.moveBy(const Offset(24, 16));
    await tester.pump();
    final firstZoomWidth = tester.getSize(noteFinder).width;

    await first.moveBy(const Offset(-24, -16));
    await second.moveBy(const Offset(24, 16));
    await tester.pump();
    final secondZoomWidth = tester.getSize(noteFinder).width;

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(firstZoomWidth, greaterThan(initialWidth));
    expect(secondZoomWidth, greaterThanOrEqualTo(firstZoomWidth));
  });

  testWidgets('two-finger pinch zoom out shrinks the grid monotonically',
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
    await tester.pump(const Duration(milliseconds: 120));

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final editorTopLeft = tester.getTopLeft(find.byType(PianoRollEditor));
    final pinchCenter = editorTopLeft + const Offset(600, 360);
    final initialWidth = tester.getSize(noteFinder).width;

    final first = await tester.startGesture(
      pinchCenter + const Offset(-120, -80),
      pointer: 21,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      pinchCenter + const Offset(120, 80),
      pointer: 22,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.moveBy(const Offset(28, 18));
    await second.moveBy(const Offset(-28, -18));
    await tester.pump();
    final firstZoomWidth = tester.getSize(noteFinder).width;

    await first.moveBy(const Offset(28, 18));
    await second.moveBy(const Offset(-28, -18));
    await tester.pump();
    final secondZoomWidth = tester.getSize(noteFinder).width;

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(firstZoomWidth, lessThan(initialWidth));
    expect(secondZoomWidth, lessThanOrEqualTo(firstZoomWidth));
  });

  testWidgets('piano key retriggers when a previous pointer is stuck',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[]);
    final events = <String>[];
    final startBeats = <double?>[];

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isRecording: true,
        onKeyboardNoteDown: (requestedClip, pitch, velocity,
            {double? startBeat}) async {
          events.add('down:$pitch');
          startBeats.add(startBeat);
        },
        onKeyboardNoteUp: (requestedClip, pitch) async {
          events.add('up:$pitch');
        },
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final keyCenter = tester.getCenter(find.text('C4'));
    final first = await tester.startGesture(
      keyCenter,
      pointer: 31,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      keyCenter,
      pointer: 32,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(events.take(3), <String>['down:60', 'up:60', 'down:60']);
    expect(startBeats, isNotEmpty);
    expect(startBeats.first, isNotNull);
    expect(startBeats.first!.isFinite, isTrue);
  });

  testWidgets('desktop piano keys follow mouse drag across notes',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[]);
    final events = <String>[];
    var shortPreviewCount = 0;

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isRecording: true,
        onPreviewNote: (pitch, velocity) async {
          shortPreviewCount++;
        },
        onKeyboardNoteDown: (requestedClip, pitch, velocity,
            {double? startBeat}) async {
          events.add('down:$pitch');
        },
        onKeyboardNoteUp: (requestedClip, pitch) async {
          events.add('up:$pitch');
        },
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('C4')),
      pointer: 41,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('C3')));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(events, <String>['down:60', 'up:60', 'down:48', 'up:48']);
    expect(shortPreviewCount, 0);
  });

  testWidgets('desktop command scroll over piano keys scales only time',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final clip = await _buildMidiTrack(<MidiNote>[
        MidiNote(
          id: 'a',
          pitch: 84,
          startBeat: 2,
          lengthBeats: 1,
          velocity: 0.7,
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
          }) async {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
      final initialSize = tester.getSize(noteFinder);
      final modifierKey = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;

      await tester.sendKeyDownEvent(modifierKey);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.text('C6')),
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(modifierKey);

      final zoomedSize = tester.getSize(noteFinder);
      expect(zoomedSize.width, greaterThan(initialSize.width));
      expect(zoomedSize.height, initialSize.height);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop command scroll zoom anchors at mouse position',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    try {
      final clip = await _buildMidiTrack(<MidiNote>[
        MidiNote(
          id: 'a',
          pitch: 72,
          startBeat: 2,
          lengthBeats: 1,
          velocity: 0.7,
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
          }) async {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
      final beforeCenter = tester.getCenter(noteFinder);
      final modifierKey = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;

      await tester.sendKeyDownEvent(modifierKey);
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: beforeCenter,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump();
      }
      await tester.sendKeyUpEvent(modifierKey);

      final afterCenter = tester.getCenter(noteFinder);
      final afterSize = tester.getSize(noteFinder);
      expect(afterSize.width, greaterThan(56));
      expect((afterCenter.dx - beforeCenter.dx).abs(), lessThan(1.0));
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop command scroll over grid zooms before vertical scroll',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    try {
      final clip = await _buildMidiTrack(<MidiNote>[
        MidiNote(
          id: 'a',
          pitch: 72,
          startBeat: 2,
          lengthBeats: 1,
          velocity: 0.7,
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
          }) async {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
      final editorTopLeft = tester.getTopLeft(find.byType(PianoRollEditor));
      final scrollPosition = editorTopLeft + const Offset(720, 360);

      final initialTop = tester.getTopLeft(noteFinder).dy;
      await tester.dragFrom(scrollPosition, const Offset(0, -160));
      await tester.pump();
      final scrolledTop = tester.getTopLeft(noteFinder).dy;
      expect(scrolledTop, lessThan(initialTop));

      final sizeBeforeZoom = tester.getSize(noteFinder);
      final modifierKey = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;

      await tester.sendKeyDownEvent(modifierKey);
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: scrollPosition,
          scrollDelta: const Offset(0, 160),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(modifierKey);

      final zoomedTop = tester.getTopLeft(noteFinder).dy;
      final zoomedSize = tester.getSize(noteFinder);
      expect(zoomedTop, scrolledTop);
      expect(zoomedSize.width, lessThan(sizeBeforeZoom.width));
      expect(zoomedSize.height, sizeBeforeZoom.height);
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop secondary drag deletes notes it crosses',
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
    await tester.pump(const Duration(milliseconds: 120));

    final firstNote = find.byKey(const ValueKey<String>('piano_note_a'));
    final secondNote = find.byKey(const ValueKey<String>('piano_note_b'));
    final gesture = await tester.startGesture(
      tester.getCenter(firstNote),
      pointer: 51,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(secondNote));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey<String>('piano_note_a')), findsNothing);
    expect(find.byKey(const ValueKey<String>('piano_note_b')), findsNothing);
    expect(committedNotes, isNotNull);
    expect(committedNotes, isEmpty);
  });

  testWidgets('recording mode renders notes from the live clip model',
      (tester) async {
    final clip = await _buildMidiTrack(const <MidiNote>[]);

    Widget editor() => _buildEditor(
          clip: clip,
          isRecording: true,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        );

    await tester.pumpWidget(editor());
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey<String>('piano_note_live')), findsNothing);

    clip.midiNotes = <MidiNote>[
      MidiNote(
        id: 'live',
        pitch: 84,
        startBeat: 1,
        lengthBeats: 0.5,
        velocity: 0.8,
      ),
    ];
    await tester.pumpWidget(editor());
    await tester.pump(const Duration(milliseconds: 120));

    expect(
        find.byKey(const ValueKey<String>('piano_note_live')), findsOneWidget);
  });

  testWidgets('locked playback advances note positions from the visual clock',
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

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isPlaying: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byIcon(Icons.lock_open_rounded));
    await tester.pump();

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final beforeLeft = tester.getTopLeft(noteFinder).dx;
    await tester.pump(const Duration(milliseconds: 250));
    final midLeft = tester.getTopLeft(noteFinder).dx;
    await tester.pump(const Duration(milliseconds: 250));
    final afterLeft = tester.getTopLeft(noteFinder).dx;

    expect(midLeft, lessThan(beforeLeft - 8.0));
    expect(afterLeft, lessThan(beforeLeft - 12.0));
    expect(afterLeft, lessThanOrEqualTo(midLeft + 2.0));
  });

  testWidgets('locked playback ignores small stale playhead rebases',
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

    Widget editor({required double projectPlayheadMs}) {
      return _buildEditor(
        clip: clip,
        projectPlayheadMs: projectPlayheadMs,
        isPlaying: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      );
    }

    await tester.pumpWidget(editor(projectPlayheadMs: 200));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.lock_open_rounded));
    await tester.pump();

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    await tester.pump(const Duration(milliseconds: 170));
    final beforeRebaseLeft = tester.getTopLeft(noteFinder).dx;

    await tester.pumpWidget(editor(projectPlayheadMs: 350));
    await tester.pump(const Duration(milliseconds: 80));
    final afterRebaseLeft = tester.getTopLeft(noteFinder).dx;

    expect(afterRebaseLeft, lessThan(beforeRebaseLeft - 2.0));
  });

  testWidgets('playback highlights active pitches on the piano key rail',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'b_note',
        pitch: 83,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isPlaying: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey<String>('piano_key_active_overlay_83')),
      findsOneWidget,
    );
    expect(find.text('B5'), findsOneWidget);
  });

  testWidgets('black key playback highlight matches the black key cutout',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'black_note',
        pitch: 82,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isPlaying: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final keyRect =
        tester.getRect(find.byKey(const ValueKey<String>('piano_key_82')));
    final activeRect = tester.getRect(
      find.byKey(const ValueKey<String>('piano_key_active_overlay_82')),
    );

    expect(activeRect.left, keyRect.left);
    expect(activeRect.width, closeTo(46.0, 0.01));
    expect(activeRect.width, lessThan(keyRect.width));
  });

  testWidgets('black key row tail previews the black key pitch',
      (tester) async {
    final previewedPitches = <int>[];
    final releasedPitches = <int>[];
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'black_note',
        pitch: 82,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
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
        }) async {},
        onKeyboardNoteDown: (
          AudioTrack clip,
          int pitch,
          double velocity, {
          double? startBeat,
        }) async {
          previewedPitches.add(pitch);
        },
        onKeyboardNoteUp: (AudioTrack clip, int pitch) async {
          releasedPitches.add(pitch);
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final blackKeyRect =
        tester.getRect(find.byKey(const ValueKey<String>('piano_key_82')));
    final gesture = await tester.startGesture(
      Offset(
        blackKeyRect.left + 68.0,
        blackKeyRect.center.dy,
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(previewedPitches, <int>[82]);
    expect(releasedPitches, <int>[82]);
  });

  testWidgets('white key playback highlight does not spill into black key row',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'white_note',
        pitch: 83,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isPlaying: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.byKey(const ValueKey<String>('piano_key_active_overlay_83')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('piano_key_active_overlay_82')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('piano_key_tail_active_bottom_82')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('piano_key_tail_active_top_82')),
      findsNothing,
    );
  });

  testWidgets('range-aware keys dim, skip audition, and preserve MIDI notes',
      (tester) async {
    final pressed = <int>[];
    final released = <int>[];
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'preserved',
        pitch: 82,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ]);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        resolvePlayablePitches: (_, __) async => <int>{81, 83},
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
        onKeyboardNoteDown: (
          AudioTrack clip,
          int pitch,
          double velocity, {
          double? startBeat,
        }) async {
          pressed.add(pitch);
        },
        onKeyboardNoteUp: (clip, pitch) async => released.add(pitch),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey<String>('piano_key_disabled_82')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_83')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('piano_note_preserved')),
        findsOneWidget);

    final unavailable = await tester.startGesture(
      tester.getRect(find.byKey(const ValueKey<String>('piano_key_82'))).center,
    );
    await unavailable.up();
    await tester.pump();
    expect(pressed, isEmpty);
    expect(released, isEmpty);

    final glide = await tester.startGesture(
      tester.getRect(find.byKey(const ValueKey<String>('piano_key_83'))).center,
      kind: PointerDeviceKind.mouse,
    );
    await glide.moveTo(
      tester.getRect(find.byKey(const ValueKey<String>('piano_key_82'))).center,
    );
    await tester.pump();
    await glide.moveTo(
      tester.getRect(find.byKey(const ValueKey<String>('piano_key_81'))).center,
    );
    await tester.pump();
    await glide.up();
    await tester.pump();

    expect(pressed, <int>[83, 81]);
    expect(released, <int>[83, 81]);
  });

  testWidgets('stale range results cannot replace the current instrument',
      (tester) async {
    final first = Completer<Set<int>>();
    final second = Completer<Set<int>>();
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'preserved_note',
        pitch: 83,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ], instrumentId: 'instrument.first');

    Future<Set<int>> resolver(
      String instrumentId,
      Map<String, double> _,
    ) {
      return instrumentId == 'instrument.first' ? first.future : second.future;
    }

    Widget editor() => _buildEditor(
          clip: clip,
          resolvePlayablePitches: resolver,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        );

    await tester.pumpWidget(editor());
    await tester.pump();
    clip.instrumentId = 'instrument.second';
    clip.instrumentName = 'Second';
    await tester.pumpWidget(editor());
    await tester.pump();

    second.complete(<int>{82});
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_83')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('piano_note_preserved_note')),
        findsOneWidget);

    first.complete(<int>{83});
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_83')),
        findsOneWidget);
  });

  testWidgets('instrument range detection fails open while loading',
      (tester) async {
    final loadingRange = Completer<Set<int>>();
    final clip = await _buildMidiTrack(<MidiNote>[],
        instrumentId: 'instrument.restricted');

    Future<Set<int>> resolver(
      String instrumentId,
      Map<String, double> _,
    ) {
      if (instrumentId == 'instrument.restricted') {
        return Future<Set<int>>.value(<int>{83});
      }
      return loadingRange.future;
    }

    Widget editor() => _buildEditor(
          clip: clip,
          resolvePlayablePitches: resolver,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        );

    await tester.pumpWidget(editor());
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_82')),
        findsOneWidget);

    clip.instrumentId = 'instrument.loading';
    clip.instrumentName = 'Loading';
    await tester.pumpWidget(editor());
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_82')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_83')),
        findsNothing);

    loadingRange.complete(<int>{82});
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('piano_key_disabled_83')),
        findsOneWidget);
  });

  testWidgets('unrestricted and failed resolvers leave every key enabled',
      (tester) async {
    final clip = await _buildMidiTrack(<MidiNote>[
      MidiNote(
        id: 'visible_note',
        pitch: 83,
        startBeat: 0,
        lengthBeats: 1,
        velocity: 0.7,
      ),
    ], instrumentId: 'mixroom.basic_synth');
    final allPitches = <int>{for (var pitch = 0; pitch <= 127; pitch++) pitch};

    Future<void> pump(PlayableMidiPitchesResolver resolver) async {
      await tester.pumpWidget(
        _buildEditor(
          clip: clip,
          resolvePlayablePitches: resolver,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('piano_key_disabled_0')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('piano_key_disabled_127')),
          findsNothing);
    }

    await pump((_, __) async => allPitches);
    await pump((_, __) => Future<Set<int>>.error('broken'));
  });

  testWidgets('sequencer tab opens and commits step edits', (tester) async {
    List<MidiNote>? committedNotes;
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.drum_test',
      instrumentName: 'Test Drum Kit',
    );

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
    await tester.pump(const Duration(milliseconds: 120));

    final tabBarRect = tester.getRect(find.byType(TabBar));
    await tester.tapAt(
      Offset(tabBarRect.left + tabBarRect.width * 0.5, tabBarRect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sequencer_step_36_0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('sequencer_step_36_0')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(committedNotes, isNotNull);
    expect(committedNotes, hasLength(1));
    expect(committedNotes!.single.pitch, 36);
    expect(committedNotes!.single.startBeat, 0.0);

    expect(
        find.byKey(const ValueKey<String>('sequencer_fill_2')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('sequencer_fill_4')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('sequencer_fill_4')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sequencer_fill_4')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(committedNotes, isNotNull);
    expect(committedNotes, hasLength(16));
    expect(
      committedNotes!.map((note) => note.startBeat).take(4).toList(),
      <double>[0.0, 1.0, 2.0, 3.0],
    );
  });
}
