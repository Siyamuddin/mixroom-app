import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/timeline_grid_policy.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/piano_roll_editor.dart';

void _setTestTargetPlatform(TargetPlatform? platform) {
  debugDefaultTargetPlatformOverride = platform;
  PlatformCapabilities.debugResetForCurrentPlatform();
}

Future<AudioTrack> _buildMidiTrack(
  List<MidiNote> notes, {
  String instrumentId = 'synth.test',
  String instrumentName = 'Test Synth',
  Duration duration = const Duration(seconds: 8),
}) {
  final file = File('/tmp/piano_roll_editor_test.mid');
  return AudioTrack.create(
    file: file,
    originalFile: file,
    audioDuration: duration,
    trimEnd: duration,
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
  TimelineGridMode gridMode = TimelineGridMode.adaptive,
  int fixedQuantizeDivisionsPerBar = 4,
  PianoRollGridResolutionChanged? onEffectiveGridResolutionChanged,
  int initialTab = 0,
  int tabRequestRevision = 0,
  double width = 900,
  double height = 620,
  List<Map<String, dynamic>> availableInstruments =
      const <Map<String, dynamic>>[],
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: PianoRollEditor(
            clip: clip,
            availableInstruments: availableInstruments,
            bpm: 120,
            beatsPerBar: 4,
            projectPlayheadMs: projectPlayheadMs,
            isPlaying: isPlaying,
            isRecording: isRecording,
            magnetEnabled: true,
            gridMode: gridMode,
            fixedQuantizeDivisionsPerBar: fixedQuantizeDivisionsPerBar,
            onEffectiveGridResolutionChanged:
                onEffectiveGridResolutionChanged,
            fullscreen: false,
            onFullscreenChanged: (_) {},
            onClose: () {},
            onCommit: onCommit,
            onScrubRequested: (_) {},
            onPreviewNote: onPreviewNote,
            onKeyboardNoteDown: onKeyboardNoteDown,
            onKeyboardNoteUp: onKeyboardNoteUp,
            resolvePlayablePitches: resolvePlayablePitches,
            initialTab: initialTab,
            tabRequestRevision: tabRequestRevision,
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

Future<void> _desktopCommandBoxSelectNotes(WidgetTester tester) async {
  final firstNote = find.byKey(const ValueKey<String>('piano_note_a'));
  final lastNote = find.byKey(const ValueKey<String>('piano_note_b'));
  final start = tester.getTopLeft(firstNote) + const Offset(-18, 6);
  final end = tester.getBottomRight(lastNote) + const Offset(18, 6);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kPrimaryMouseButton,
  );
  await gesture.down(start);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump(const Duration(milliseconds: 240));
}

Future<void> _tapEmptyPianoRollGrid(WidgetTester tester) async {
  await _clickEmptyPianoRollGrid(
    tester,
    kind: PointerDeviceKind.touch,
  );
}

Future<void> _clickEmptyPianoRollGrid(
  WidgetTester tester, {
  required PointerDeviceKind kind,
}) async {
  final noteA = tester.getRect(
    find.byKey(const ValueKey<String>('piano_note_a')),
  );
  final noteB = tester.getRect(
    find.byKey(const ValueKey<String>('piano_note_b')),
  );
  final lowerBottom =
      noteA.bottom > noteB.bottom ? noteA.bottom : noteB.bottom;
  final emptyTap = Offset(noteA.left, lowerBottom + 20);
  await tester.pump(const Duration(milliseconds: 250));
  if (kind == PointerDeviceKind.mouse) {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(emptyTap);
    await tester.pump();
    await gesture.up();
  } else {
    await tester.tapAt(emptyTap);
  }
  await tester.pump();
}

List<MidiNote> _twoSelectableNotes() {
  return <MidiNote>[
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
  ];
}

void _expectNotesSelected(WidgetTester tester, {required bool selected}) {
  final matcher = selected ? findsOneWidget : findsNothing;
  expect(
    find.byKey(const ValueKey<String>('piano_note_handle_a')),
    matcher,
  );
  expect(
    find.byKey(const ValueKey<String>('piano_note_handle_b')),
    matcher,
  );
  expect(find.byTooltip('Copy'), matcher);
}

MidiNote _noteById(List<MidiNote> notes, String id) {
  return notes.firstWhere((note) => note.id == id);
}

void main() {
  testWidgets('supports direct instrument-tab requests', (tester) async {
    final clip = await _buildMidiTrack(const <MidiNote>[]);
    var requestedTab = 2;
    var revision = 1;
    late StateSetter rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return _buildEditor(
            clip: clip,
            onCommit: ({
              required notes,
              required instrumentParams,
              required instrumentId,
              required instrumentName,
            }) async {},
            initialTab: requestedTab,
            tabRequestRevision: revision,
          );
        },
      ),
    );

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);

    rebuild(() {
      requestedTab = 0;
      revision += 1;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });

  testWidgets('built-in synth uses shared ADSR graph and commits all values',
      (tester) async {
    final semantics = tester.ensureSemantics();
    Map<String, double>? committedParams;
    var commitCount = 0;
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
    );
    clip.instrumentParams = <String, double>{
      'attackMs': 42.0,
      'releaseMs': 777.0,
      'drive': 0.24,
    };

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mixroom.basic_synth',
            'name': 'Basic Synth',
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {
          commitCount += 1;
          committedParams = Map<String, double>.from(instrumentParams);
        },
      ),
    );
    await tester.pumpAndSettle();

    final graph = find.byKey(const ValueKey<String>('synth_adsr_graph'));
    final attackRow = find.byKey(
      const ValueKey<String>('synth_attackMs_slider'),
    );
    final decayRow = find.byKey(
      const ValueKey<String>('synth_decayMs_slider'),
    );
    final sustainRow = find.byKey(
      const ValueKey<String>('synth_sustainLevel_slider'),
    );
    final releaseRow = find.byKey(
      const ValueKey<String>('synth_releaseMs_slider'),
    );
    expect(graph, findsOneWidget);
    expect(attackRow, findsOneWidget);
    expect(decayRow, findsOneWidget);
    expect(sustainRow, findsOneWidget);
    expect(releaseRow, findsOneWidget);
    expect(find.descendant(of: attackRow, matching: find.text('42 ms')),
        findsOneWidget);
    expect(find.descendant(of: decayRow, matching: find.text('120 ms')),
        findsOneWidget);
    expect(find.descendant(of: sustainRow, matching: find.text('86%')),
        findsOneWidget);
    expect(find.descendant(of: releaseRow, matching: find.text('777 ms')),
        findsOneWidget);

    final attackSlider = find.descendant(
      of: attackRow,
      matching: find.byType(Slider),
    );
    final decaySlider = find.descendant(
      of: decayRow,
      matching: find.byType(Slider),
    );
    expect(tester.getSemantics(attackSlider).label, 'Attack');
    expect(
      tester.widget<Slider>(attackSlider).semanticFormatterCallback!(42.0),
      '42 ms',
    );
    expect(tester.getSemantics(decaySlider).label, 'Decay');
    expect(
      tester.widget<Slider>(decaySlider).semanticFormatterCallback!(120.0),
      '120 ms',
    );

    final graphPaint = find.descendant(
      of: graph,
      matching: find.byType(CustomPaint),
    );
    final beforePainter = tester.widget<CustomPaint>(graphPaint).painter!;

    tester
        .widget<Slider>(
          find.descendant(of: attackRow, matching: find.byType(Slider)),
        )
        .onChanged!(300.0);
    tester
        .widget<Slider>(
          find.descendant(of: decayRow, matching: find.byType(Slider)),
        )
        .onChanged!(1200.0);
    tester
        .widget<Slider>(
          find.descendant(of: sustainRow, matching: find.byType(Slider)),
        )
        .onChanged!(0.55);
    tester
        .widget<Slider>(
          find.descendant(of: releaseRow, matching: find.byType(Slider)),
        )
        .onChanged!(1100.0);
    await tester.pump();

    final afterPainter = tester.widget<CustomPaint>(graphPaint).painter!;
    expect(afterPainter.shouldRepaint(beforePainter), isTrue);
    expect(commitCount, 0);
    expect(find.descendant(of: decayRow, matching: find.text('1.2 s')),
        findsOneWidget);
    expect(find.descendant(of: sustainRow, matching: find.text('55%')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));

    expect(commitCount, 1);
    expect(committedParams, isNotNull);
    expect(committedParams!['attackMs'], 300.0);
    expect(committedParams!['decayMs'], 1200.0);
    expect(committedParams!['sustainLevel'], 0.55);
    expect(committedParams!['releaseMs'], 1100.0);
    expect(committedParams!['drive'], 0.24);
    semantics.dispose();
  });

  testWidgets('oscillator presets share ADSR defaults without stale values',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
    );

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mixroom.basic_synth',
            'name': 'Basic Synth',
            'attackMs': 18.0,
            'releaseMs': 180.0,
          },
          <String, dynamic>{
            'id': 'mixroom.soft_pad',
            'name': 'Soft Pad',
            'pickerCategory': 'Synths',
            'attackMs': 210.0,
            'releaseMs': 950.0,
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    Slider slider(String parameter) => tester.widget<Slider>(
          find.descendant(
            of: find.byKey(
              ValueKey<String>('synth_${parameter}_slider'),
            ),
            matching: find.byType(Slider),
          ),
        );

    await tester.tap(find.text('Soft Pad'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('synth_adsr_graph')),
        findsOneWidget);
    expect(slider('attackMs').value, 210.0);
    expect(slider('decayMs').value, 120.0);
    expect(slider('sustainLevel').value, 0.86);
    expect(slider('releaseMs').value, 950.0);
    expect(slider('attackMs').max, 300.0);
    expect(slider('decayMs').max, 2000.0);
    expect(slider('sustainLevel').min, 0.0);
    expect(slider('releaseMs').min, 0.0);
    expect(slider('releaseMs').max, 1200.0);

    await tester.tap(find.text('Basic Synth').last);
    await tester.pumpAndSettle();

    expect(slider('attackMs').value, 18.0);
    expect(slider('decayMs').value, 120.0);
    expect(slider('sustainLevel').value, 0.86);
    expect(slider('releaseMs').value, 180.0);
  });

  testWidgets('zero-time stages collapse and release geometry scales',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
    );

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mixroom.basic_synth',
            'name': 'Basic Synth',
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    Slider slider(String parameter) => tester.widget<Slider>(
          find.descendant(
            of: find.byKey(
              ValueKey<String>('synth_${parameter}_slider'),
            ),
            matching: find.byType(Slider),
          ),
        );

    List<double> phaseWidths() {
      final graph = find.byKey(const ValueKey<String>('synth_adsr_graph'));
      final paint = find.descendant(
        of: graph,
        matching: find.byType(CustomPaint),
      );
      final dynamic painter = tester.widget<CustomPaint>(paint).painter!;
      return List<double>.from(painter.debugPhaseWidths() as List);
    }

    slider('attackMs').onChanged!(0.0);
    slider('decayMs').onChanged!(0.0);
    slider('sustainLevel').onChanged!(0.0);
    slider('releaseMs').onChanged!(0.0);
    await tester.pump();

    expect(slider('sustainLevel').min, 0.0);
    expect(slider('releaseMs').min, 0.0);
    expect(phaseWidths(), <double>[0.0, 0.0, 1.0, 0.0]);
    expect(find.text('0 ms'), findsNWidgets(3));
    expect(find.text('0%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final graph = find.byKey(const ValueKey<String>('synth_adsr_graph'));
    final paint = find.descendant(
      of: graph,
      matching: find.byType(CustomPaint),
    );
    final dynamic painter = tester.widget<CustomPaint>(paint).painter!;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    expect(
      () => painter.paint(canvas, const ui.Size(1026.8, 106.0)),
      returnsNormally,
    );
    recorder.endRecording().dispose();

    final releaseWidths = <double>[];
    for (final releaseMs in <double>[0.0, 20.0, 600.0, 1200.0]) {
      slider('releaseMs').onChanged!(releaseMs);
      await tester.pump();
      releaseWidths.add(phaseWidths()[3]);
      expect(tester.takeException(), isNull);
    }
    expect(releaseWidths[0], 0.0);
    expect(releaseWidths[1], lessThan(releaseWidths[2]));
    expect(releaseWidths[2], lessThan(releaseWidths[3]));
    expect(releaseWidths[1], lessThan(releaseWidths[3] * 0.2));
  });

  testWidgets('external plugins keep the existing attack release envelope',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'plugin.test',
      instrumentName: 'External Test',
    );

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'plugin.test',
            'name': 'External Test',
            'isExternalPlugin': true,
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attack'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('synth_adsr_graph')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('synth_decayMs_slider')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('synth_sustainLevel_slider')),
      findsNothing,
    );
    expect(
      tester.widgetList<Slider>(find.byType(Slider)).any(
            (slider) => slider.min == 20.0 && slider.max == 1200.0,
          ),
      isTrue,
    );
  });

  testWidgets('sampler keeps its controls with the shared ADSR editor',
      (tester) async {
    Map<String, double>? committedParams;
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'sfz.test_sampler',
      instrumentName: 'Test Sampler',
    );
    clip.instrumentParams = <String, double>{
      'attackMs': 12.0,
      'decayMs': 340.0,
      'sustainLevel': 0.65,
      'releaseMs': 1200.0,
      'outputGain': 0.8,
    };

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'sfz.test_sampler',
            'name': 'Test Sampler',
            'isSampled': true,
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {
          committedParams = Map<String, double>.from(instrumentParams);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sampler envelope'), findsOneWidget);
    expect(find.text('Gain'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sampler_adsr_graph')),
        findsOneWidget);

    Slider slider(String parameter) => tester.widget<Slider>(
          find.descendant(
            of: find.byKey(
              ValueKey<String>('sampler_${parameter}_slider'),
            ),
            matching: find.byType(Slider),
          ),
        );
    expect(slider('attackMs').max, 600.0);
    expect(slider('decayMs').value, 340.0);
    expect(slider('decayMs').max, 900.0);
    expect(slider('sustainLevel').min, 0.0);
    expect(slider('releaseMs').min, 0.0);
    expect(slider('releaseMs').max, 1800.0);

    slider('decayMs').onChanged!(500.0);
    slider('releaseMs').onChanged!(0.0);
    await tester.pump(const Duration(milliseconds: 200));

    expect(committedParams, isNotNull);
    expect(committedParams!['attackMs'], 12.0);
    expect(committedParams!['decayMs'], 500.0);
    expect(committedParams!['sustainLevel'], 0.65);
    expect(committedParams!['releaseMs'], 0.0);
    expect(committedParams!['outputGain'], 0.8);
  });

  testWidgets('catalog-marked sampled instruments use sampler ADSR ranges',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.sampled_drum_test',
      instrumentName: 'Sampled Drum Test',
    );

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mixroom.sampled_drum_test',
            'name': 'Sampled Drum Test',
            'category': 'drum',
            'isSampled': true,
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('sampler_adsr_graph')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('synth_adsr_graph')),
        findsNothing);
    final attack = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('sampler_attackMs_slider'),
        ),
        matching: find.byType(Slider),
      ),
    );
    final release = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('sampler_releaseMs_slider'),
        ),
        matching: find.byType(Slider),
      ),
    );
    expect(attack.max, 600.0);
    expect(
      tester.widget<Slider>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('sampler_sustainLevel_slider'),
          ),
          matching: find.byType(Slider),
        ),
      ).min,
      0.0,
    );
    expect(release.min, 0.0);
    expect(release.max, 1800.0);
  });

  testWidgets('granularizer keeps grain controls and shared amplitude ADSR',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'sfz.test_granularizer',
      instrumentName: 'Test Granularizer',
    );
    clip.instrumentParams = <String, double>{
      'granularMode': 1.0,
      'grainAttackMs': 21.0,
      'attackMs': 9.0,
      'decayMs': 180.0,
      'sustainLevel': 0.72,
      'releaseMs': 640.0,
    };

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'sfz.test_granularizer',
            'name': 'Test Granularizer',
            'isSampled': true,
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Granularizer'), findsWidgets);
    expect(find.text('Grain'), findsOneWidget);
    expect(find.text('Depth'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('granularizer_adsr_graph')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('granularizer_attackMs_slider')),
      findsOneWidget,
    );
    final release = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('granularizer_releaseMs_slider'),
        ),
        matching: find.byType(Slider),
      ),
    );
    expect(release.min, 0.0);
    expect(release.max, 1800.0);
    expect(
      tester.widget<Slider>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('granularizer_sustainLevel_slider'),
          ),
          matching: find.byType(Slider),
        ),
      ).min,
      0.0,
    );
    expect(find.byKey(const ValueKey<String>('sampler_adsr_graph')),
        findsNothing);
  });

  testWidgets('shared synth ADSR fits a narrow mobile-sized editor',
      (tester) async {
    final clip = await _buildMidiTrack(
      const <MidiNote>[],
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
    );

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        initialTab: 2,
        width: 390,
        availableInstruments: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mixroom.basic_synth',
            'name': 'Basic Synth',
          },
        ],
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey<String>('synth_adsr_graph')),
        findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

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

  testWidgets(
      'empty-grid tap after long-press marquee clears selection without adding a note',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.iOS);
    try {
      var commitCount = 0;
      List<MidiNote>? committedNotes;
      final clip = await _buildMidiTrack(_twoSelectableNotes());

      await tester.pumpWidget(
        _buildEditor(
          clip: clip,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {
            commitCount++;
            committedNotes = notes.map((note) => note.copy()).toList();
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      await _boxSelectNotes(tester);
      _expectNotesSelected(tester, selected: true);

      await _tapEmptyPianoRollGrid(tester);

      _expectNotesSelected(tester, selected: false);
      expect(find.byKey(const ValueKey<String>('piano_note_a')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('piano_note_b')), findsOneWidget);
      expect(commitCount, 0);
      expect(committedNotes, isNull);
    } finally {
      _setTestTargetPlatform(null);
    }
  });

  testWidgets(
      'empty-grid click after macOS Command marquee clears selection without adding a note',
      (tester) async {
    _setTestTargetPlatform(TargetPlatform.macOS);
    try {
      var commitCount = 0;
      final clip = await _buildMidiTrack(_twoSelectableNotes());

      await tester.pumpWidget(
        _buildEditor(
          clip: clip,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {
            commitCount++;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      await _desktopCommandBoxSelectNotes(tester);
      _expectNotesSelected(tester, selected: true);

      await _clickEmptyPianoRollGrid(
        tester,
        kind: PointerDeviceKind.mouse,
      );

      _expectNotesSelected(tester, selected: false);
      expect(find.byKey(const ValueKey<String>('piano_note_a')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('piano_note_b')), findsOneWidget);
      expect(commitCount, 0);
    } finally {
      HardwareKeyboard.instance.clearState();
      _setTestTargetPlatform(null);
    }
  });

  testWidgets('adaptive note snapping follows piano-roll zoom',
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

    await tester.tap(find.byTooltip('Zoom in').first);
    await tester.pump(const Duration(milliseconds: 120));

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final moveGesture = await tester.startGesture(tester.getCenter(noteFinder));
    await tester.pump(const Duration(milliseconds: 50));
    await moveGesture.moveBy(const Offset(37, 0));
    await tester.pump();
    await moveGesture.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(committedNotes, isNotNull);
    expect(_noteById(committedNotes!, 'a').startBeat, 2.5);
  });

  testWidgets('adaptive piano-roll grid reaches every bucket through 1/512',
      (tester) async {
    final reportedDivisions = <int>[];
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
        onEffectiveGridResolutionChanged: (clipId, divisionsPerBar) {
          expect(clipId, clip.clipId);
          reportedDivisions.add(divisionsPerBar);
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

    final zoomIn = find.byTooltip('Zoom in').first;
    for (var i = 0; i < 18; i++) {
      await tester.tap(zoomIn);
      await tester.pump();
    }

    expect(
      find.byKey(
        const ValueKey<String>('piano_roll_grid_divisions_512'),
      ),
      findsOneWidget,
    );
    expect(
      reportedDivisions,
      <int>[4, 8, 16, 32, 64, 128, 256, 512],
    );
    final maxZoomNoteWidth = tester.getSize(
      find.byKey(const ValueKey<String>('piano_note_a')),
    ).width;
    await tester.tap(zoomIn);
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('piano_note_a')))
          .width,
      maxZoomNoteWidth,
    );
    expect(reportedDivisions.last, 512);
  });

  testWidgets('fixed piano-roll grid remains fixed while zooming',
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
        gridMode: TimelineGridMode.fixed,
        fixedQuantizeDivisionsPerBar: 4,
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

    await tester.tap(find.byTooltip('Zoom in').first);
    await tester.pump(const Duration(milliseconds: 120));

    final noteFinder = find.byKey(const ValueKey<String>('piano_note_a'));
    final moveGesture = await tester.startGesture(tester.getCenter(noteFinder));
    await tester.pump(const Duration(milliseconds: 50));
    await moveGesture.moveBy(const Offset(37, 0));
    await tester.pump();
    await moveGesture.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(committedNotes, isNotNull);
    expect(_noteById(committedNotes!, 'a').startBeat, 3);
  });

  testWidgets('deep zoom keeps a long MIDI clip finite and paintable',
      (tester) async {
    final clip = await _buildMidiTrack(
      <MidiNote>[
        MidiNote(
          id: 'a',
          pitch: 84,
          startBeat: 2,
          lengthBeats: 1,
          velocity: 0.7,
        ),
      ],
      duration: const Duration(minutes: 10),
    );

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

    final zoomIn = find.byTooltip('Zoom in').first;
    for (var i = 0; i < 18; i++) {
      await tester.tap(zoomIn);
      await tester.pump();
    }

    expect(
      find.byKey(
        const ValueKey<String>('piano_roll_grid_divisions_512'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('touch pinch is damped and keeps its focal note stable',
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
    final focalPosition = tester.getCenter(noteFinder);
    final initialSize = tester.getSize(noteFinder);

    final first = await tester.startGesture(
      focalPosition - const Offset(40, 0),
      pointer: 13,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    final second = await tester.startGesture(
      focalPosition + const Offset(40, 0),
      pointer: 14,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    await tester.pump();

    final zoomedSize = tester.getSize(noteFinder);
    final zoomedCenter = tester.getCenter(noteFinder);
    final horizontalScale = zoomedSize.width / initialSize.width;

    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 120));

    expect(horizontalScale, closeTo(1.57, 0.04));
    expect((zoomedCenter.dx - focalPosition.dx).abs(), lessThan(1.0));
    expect((zoomedCenter.dy - focalPosition.dy).abs(), lessThan(1.0));
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

  testWidgets('macOS trackpad pinch zooms around its focal position',
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
      final focalPosition = tester.getCenter(noteFinder);
      final initialSize = tester.getSize(noteFinder);

      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 61, position: focalPosition),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 61,
          position: focalPosition,
          scale: 2.0,
        ),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 61, position: focalPosition),
      );
      await tester.pump();

      final zoomedSize = tester.getSize(noteFinder);
      final zoomedCenter = tester.getCenter(noteFinder);
      expect(zoomedSize.width, greaterThan(initialSize.width));
      expect(zoomedSize.height, greaterThan(initialSize.height));
      expect((zoomedCenter.dx - focalPosition.dx).abs(), lessThan(1.0));
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS command trackpad scroll zooms only in time',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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
      final focalPosition = tester.getCenter(noteFinder);
      final initialSize = tester.getSize(noteFinder);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 62, position: focalPosition),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 62,
          position: focalPosition,
          panDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 62, position: focalPosition),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      final zoomedSize = tester.getSize(noteFinder);
      expect(zoomedSize.width, greaterThan(initialSize.width));
      expect(zoomedSize.height, initialSize.height);
    } finally {
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

  testWidgets('playhead stays at transport position beyond a clip extension',
      (tester) async {
    final clip = await _buildMidiTrack(const <MidiNote>[]);
    clip.trimEnd = const Duration(seconds: 2);

    Widget editor() => _buildEditor(
          clip: clip,
          projectPlayheadMs: 5000,
          isRecording: true,
          onCommit: ({
            required List<MidiNote> notes,
            required Map<String, double> instrumentParams,
            required String instrumentId,
            required String instrumentName,
          }) async {},
        );

    double renderedPlayheadX() {
      final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final playhead = paints.firstWhere(
        (paint) =>
            paint.painter.runtimeType.toString() ==
            '_PianoRollPlayheadLinePainter',
      );
      return ((playhead.painter as dynamic).x as num).toDouble();
    }

    await tester.pumpWidget(editor());
    await tester.pump(const Duration(milliseconds: 120));
    final beforeExtensionX = renderedPlayheadX();

    clip.trimEnd = const Duration(seconds: 8);
    await tester.pumpWidget(editor());
    await tester.pump(const Duration(milliseconds: 120));
    final afterExtensionX = renderedPlayheadX();

    expect(beforeExtensionX, greaterThan(4.0 * 56.0));
    expect(afterExtensionX, closeTo(beforeExtensionX, 0.01));
  });

  testWidgets('playing playhead keeps advancing beyond the clip boundary',
      (tester) async {
    final clip = await _buildMidiTrack(const <MidiNote>[]);
    clip.trimEnd = const Duration(seconds: 2);

    await tester.pumpWidget(
      _buildEditor(
        clip: clip,
        projectPlayheadMs: 2500,
        isPlaying: true,
        isRecording: true,
        onCommit: ({
          required List<MidiNote> notes,
          required Map<String, double> instrumentParams,
          required String instrumentId,
          required String instrumentName,
        }) async {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    double renderedPlayheadX() {
      final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final playhead = paints.firstWhere(
        (paint) =>
            paint.painter.runtimeType.toString() ==
            '_PianoRollPlayheadLinePainter',
      );
      return ((playhead.painter as dynamic).x as num).toDouble();
    }

    final beyondBoundaryX = renderedPlayheadX();
    await tester.pump(const Duration(milliseconds: 250));
    final advancedX = renderedPlayheadX();

    expect(beyondBoundaryX, greaterThan(4.0 * 56.0));
    expect(advancedX, greaterThan(beyondBoundaryX + 20.0));
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
