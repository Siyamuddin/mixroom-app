import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/pitch_blob_editor.dart';

Future<AudioTrack> _makeMidiClip() {
  return AudioTrack.create(
    file: File('/tmp/pitch_lab_render.wav'),
    originalFile: File('/tmp/pitch_lab_render.wav'),
    audioDuration: const Duration(milliseconds: 2400),
    trimEnd: const Duration(milliseconds: 2400),
    label: 'Lead Take',
    clipKind: ClipKind.midi,
    instrumentId: 'mixroom.basic_synth',
    instrumentName: 'Basic Synth',
    instrumentParams: const <String, double>{'cutoffHz': 3200.0},
    midiNotes: <MidiNote>[
      MidiNote(
        id: 'note_1',
        pitch: 61,
        startBeat: 0.13,
        lengthBeats: 0.37,
        velocity: 0.8,
      ),
    ],
  );
}

Future<AudioTrack> _makeVisibleMidiClip() {
  return AudioTrack.create(
    file: File('/tmp/pitch_lab_visible.wav'),
    originalFile: File('/tmp/pitch_lab_visible.wav'),
    audioDuration: const Duration(milliseconds: 2400),
    trimEnd: const Duration(milliseconds: 2400),
    label: 'Visible Lead',
    clipKind: ClipKind.midi,
    instrumentId: 'mixroom.basic_synth',
    instrumentName: 'Basic Synth',
    instrumentParams: const <String, double>{'cutoffHz': 3200.0},
    midiNotes: <MidiNote>[
      MidiNote(
        id: 'visible_note_1',
        pitch: 84,
        startBeat: 0.25,
        lengthBeats: 0.5,
        velocity: 0.72,
      ),
    ],
  );
}

Future<AudioTrack> _makeLowMidiClip() {
  return AudioTrack.create(
    file: File('/tmp/pitch_lab_low.wav'),
    originalFile: File('/tmp/pitch_lab_low.wav'),
    audioDuration: const Duration(milliseconds: 2400),
    trimEnd: const Duration(milliseconds: 2400),
    label: 'Low Lead',
    clipKind: ClipKind.midi,
    instrumentId: 'mixroom.basic_synth',
    instrumentName: 'Basic Synth',
    instrumentParams: const <String, double>{'cutoffHz': 3200.0},
    midiNotes: <MidiNote>[
      MidiNote(
        id: 'low_note_1',
        pitch: 24,
        startBeat: 0.25,
        lengthBeats: 0.5,
        velocity: 0.72,
      ),
    ],
  );
}

void main() {
  testWidgets('PitchBlobEditor renders blobs and commits quantized notes',
      (tester) async {
    final clip = await _makeMidiClip();
    List<MidiNote>? committed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {
                committed = notes;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Lead Take'), findsOneWidget);
    expect(find.text('1 note'), findsOneWidget);

    await tester.tap(find.text('Quantize'));
    await tester.pumpAndSettle();

    expect(committed, isNotNull);
    expect(committed!.single.startBeat, 0.25);
    expect(committed!.single.lengthBeats, 0.25);
  });

  testWidgets('PitchBlobEditor exposes down transpose and audio actions',
      (tester) async {
    final clip = await _makeMidiClip();
    List<MidiNote>? committed;
    List<MidiNote>? previewedAudio;
    List<MidiNote>? renderedAudio;
    var pausedPreview = false;
    var stoppedPreview = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1180,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {
                committed = notes;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Pitch Only'), findsOneWidget);
    expect(find.text('Time Only'), findsOneWidget);
    expect(find.text('C Major'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pump();

    expect(
      find.text(
        'Drag notes to change pitch or timing. Drag empty space to move around. Pinch to zoom. Save when the melody feels right.',
      ),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(find.text('-1'), findsOneWidget);

    await tester.tap(find.text('-1'));
    await tester.pumpAndSettle();

    expect(committed, isNotNull);
    expect(committed!.single.pitch, 60);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
              draftNotes: clip.midiNotes,
              audioCorrectionMode: true,
              primaryActionLabel: 'Render Audio',
              onPreviewAudio: (notes) async {
                previewedAudio = notes;
              },
              onApplyAudio: (notes) async {
                renderedAudio = notes;
              },
              onStopPreviewAudio: () async {
                stoppedPreview = true;
              },
              allowCreateNotes: false,
              allowHarmony: false,
              allowSplit: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Render Audio'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(previewedAudio, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
              draftNotes: clip.midiNotes,
              audioCorrectionMode: true,
              primaryActionLabel: 'Render Audio',
              onPreviewAudio: (notes) async {
                previewedAudio = notes;
              },
              onApplyAudio: (notes) async {
                renderedAudio = notes;
              },
              onStopPreviewAudio: () async {
                stoppedPreview = true;
              },
              onPausePreviewAudio: () async {
                pausedPreview = true;
              },
              audioPreviewPlaying: true,
              audioPreviewReady: true,
              allowCreateNotes: false,
              allowHarmony: false,
              allowSplit: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(pausedPreview, isTrue);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(stoppedPreview, isTrue);

    await tester.tap(find.text('Render Audio'));
    await tester.pumpAndSettle();

    expect(renderedAudio, isNotNull);
    expect(previewedAudio!.single.pitch, 61);
    expect(renderedAudio!.single.pitch, 61);
  });

  testWidgets('PitchBlobEditor shows note preview action after note tap',
      (tester) async {
    final clip = await _makeVisibleMidiClip();
    int? previewedPitch;
    double? previewedVelocity;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
              onPreviewNote: (pitch, velocity) async {
                previewedPitch = pitch;
                previewedVelocity = velocity;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

    await tester.tapAt(const Offset(110, 270));
    await tester.pumpAndSettle();

    expect(previewedPitch, isNull);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('pitch-lab-note-preview-action')),
    );
    await tester.pumpAndSettle();

    expect(previewedPitch, 84);
    expect(previewedVelocity, 0.72);
  });

  testWidgets('PitchBlobEditor shows note preview action in audio mode',
      (tester) async {
    final clip = await _makeVisibleMidiClip();
    MidiNote? previewedNote;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 520,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
              draftNotes: clip.midiNotes,
              audioCorrectionMode: true,
              primaryActionLabel: 'Render Audio',
              onPreviewAudio: (_) async {},
              onApplyAudio: (_) async {},
              onPreviewSingleNote: (note) async {
                previewedNote = note;
              },
              allowCreateNotes: false,
              allowHarmony: false,
              allowSplit: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

    await tester.tapAt(const Offset(110, 270));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('pitch-lab-note-preview-action')),
    );
    await tester.pumpAndSettle();

    expect(previewedNote?.id, 'visible_note_1');
  });

  testWidgets('PitchBlobEditor opens vertically centered near notes',
      (tester) async {
    final clip = await _makeLowMidiClip();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 220,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollables = tester.widgetList<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final vertical = scrollables.firstWhere(
      (scrollable) => scrollable.scrollDirection == Axis.vertical,
    );

    expect(vertical.controller!.offset, greaterThan(0));
  });

  testWidgets('PitchBlobEditor supports desktop wheel viewport movement',
      (tester) async {
    final clip = await _makeLowMidiClip();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 820,
            height: 220,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollables = tester.widgetList<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final vertical = scrollables.firstWhere(
      (scrollable) => scrollable.scrollDirection == Axis.vertical,
    );
    final horizontal = scrollables.firstWhere(
      (scrollable) => scrollable.scrollDirection == Axis.horizontal,
    );
    final initialVertical = vertical.controller!.offset;

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(300, 150),
        scrollDelta: Offset(0, -80),
      ),
    );
    await tester.pump();
    expect(vertical.controller!.offset, lessThan(initialVertical));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(300, 150),
        scrollDelta: Offset(0, 80),
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(horizontal.controller!.offset, greaterThan(0));
  });

  testWidgets('PitchBlobEditor preview transport fits narrow bottom bar',
      (tester) async {
    final clip = await _makeMidiClip();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 420,
            child: PitchBlobEditor(
              clip: clip,
              bpm: 120,
              projectPlayheadMs: 0,
              isPlaying: false,
              fullscreen: false,
              onFullscreenChanged: (_) {},
              onClose: () {},
              onCommit: ({
                required List<MidiNote> notes,
                required Map<String, double> instrumentParams,
                required String instrumentId,
                required String instrumentName,
              }) async {},
              draftNotes: clip.midiNotes,
              audioCorrectionMode: true,
              primaryActionLabel: 'Render Audio',
              onPreviewAudio: (_) async {},
              onApplyAudio: (_) async {},
              onPausePreviewAudio: () async {},
              onStopPreviewAudio: () async {},
              audioPreviewPlaying: true,
              audioPreviewReady: true,
              allowCreateNotes: false,
              allowHarmony: false,
              allowSplit: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
