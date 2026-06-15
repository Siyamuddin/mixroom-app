import 'dart:io';

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
  bool isRecording = false,
  Future<void> Function(int pitch, double velocity)? onPreviewNote,
  PianoKeyDownCallback? onKeyboardNoteDown,
  PianoKeyUpCallback? onKeyboardNoteUp,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
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

    final gridTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('piano_roll_grid_canvas')),
    );
    await tester.tapAt(gridTopLeft + const Offset(420, 110));
    await tester.pump(const Duration(milliseconds: 120));

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
    final gridTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('piano_roll_grid_canvas')));
    final pinchCenter = gridTopLeft + const Offset(260, 160);
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
    final gridTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('piano_roll_grid_canvas')));
    final pinchCenter = gridTopLeft + const Offset(260, 160);
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

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        isRecording: true,
        onKeyboardNoteDown: (requestedClip, pitch, velocity) async {
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

    final keyCenter = tester.getCenter(find.text('C6'));
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

    expect(events.take(3), <String>['down:84', 'up:84', 'down:84']);
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
        onKeyboardNoteDown: (requestedClip, pitch, velocity) async {
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
      tester.getCenter(find.text('C6')),
      pointer: 41,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('C5')));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(events, <String>['down:84', 'up:84', 'down:72', 'up:72']);
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
