import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/android_recording_input_v2.dart';
import 'package:mixroom/widgets/android_input_channel_selector.dart';

class _ReplacementHarness extends StatefulWidget {
  const _ReplacementHarness({
    required this.configuration,
    required this.onSave,
  });

  final AndroidRecordingInputV2 configuration;
  final VoidCallback onSave;

  @override
  State<_ReplacementHarness> createState() => _ReplacementHarnessState();
}

class _ReplacementHarnessState extends State<_ReplacementHarness> {
  int start = 0;
  int count = 2;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AndroidInputChannelSelector(
          configuration: widget.configuration,
          start: start,
          count: count,
          enabled: true,
          decoration: const InputDecoration(labelText: 'Input Channel'),
          onUseSupportedInput: () {
            setState(() {
              start = widget.configuration.channelStart;
              count = widget.configuration.channelCount;
            });
            widget.onSave();
          },
        ),
      ),
    );
  }
}

void main() {
  final mono = AndroidRecordingInputV2.fromMap({
    'channelStart': 0,
    'channelCount': 1,
  })!;
  test(
    'native capability accepts only its exact capture range; unknown presence stays unknown',
    () {
      expect(mono.inputAvailable, isNull);
      expect(mono.accepts(0, 1), isTrue);
      for (final range in [(0, 2), (1, 1), (-1, 1), (0, 0), (255, 1)]) {
        expect(mono.accepts(range.$1, range.$2), isFalse);
      }
      expect(AndroidRecordingInputV2.fromMap({}), isNull);
      expect(
        AndroidRecordingInputV2.fromMap({'channelStart': 0, 'channelCount': 2}),
        isNull,
      );
      expect(
        AndroidRecordingInputV2.fromMap({
          'channelStart': 0,
          'channelCount': 1,
          'inputAvailable': false,
        })!.inputAvailable,
        isFalse,
      );
    },
  );
  Widget view({
    AndroidRecordingInputV2? config,
    int start = 0,
    int count = 1,
    bool enabled = true,
    VoidCallback? replace,
  }) => MaterialApp(
    home: Scaffold(
      body: AndroidInputChannelSelector(
        configuration: config,
        start: start,
        count: count,
        enabled: enabled,
        decoration: const InputDecoration(labelText: 'Input Channel'),
        onUseSupportedInput: replace ?? () {},
      ),
    ),
  );
  testWidgets(
    'mono is visible and read only even with unknown device identity',
    (tester) async {
      await tester.pumpWidget(view(config: mono));
      expect(find.text('Input 1 (Mono)'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    },
  );
  testWidgets(
    'saved route remains visible until explicit replacement; track changes retain own selection',
    (tester) async {
      var replacements = 0;
      await tester.pumpWidget(
        view(config: mono, count: 2, replace: () => replacements++),
      );
      expect(find.text('Inputs 1–2 — Unavailable'), findsOneWidget);
      expect(replacements, 0);
      await tester.tap(find.text('Use Input 1 (Mono)'));
      expect(replacements, 1);
      await tester.pumpWidget(
        view(
          config: mono,
          start: 7,
          enabled: false,
          replace: () => replacements++,
        ),
      );
      expect(find.text('Input 8 — Unavailable'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(replacements, 1);
      await tester.pumpWidget(view(config: mono));
      expect(find.text('Input 1 (Mono)'), findsOneWidget);
    },
  );
  testWidgets('replacement immediately repaints and requests persistence', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      _ReplacementHarness(configuration: mono, onSave: () => saves++),
    );

    expect(find.text('Inputs 1–2 — Unavailable'), findsOneWidget);
    await tester.tap(find.text('Use Input 1 (Mono)'));
    await tester.pump();

    expect(find.text('Input 1 (Mono)'), findsOneWidget);
    expect(find.text('Inputs 1–2 — Unavailable'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(saves, 1);
  });
  testWidgets(
    'missing capability and confirmed absence have distinct explanations',
    (tester) async {
      await tester.pumpWidget(view());
      expect(find.text('Input information unavailable'), findsOneWidget);
      expect(find.text('No input device available'), findsNothing);
      await tester.pumpWidget(
        view(
          config: AndroidRecordingInputV2.fromMap({
            'channelStart': 0,
            'channelCount': 1,
            'inputAvailable': false,
          }),
        ),
      );
      expect(find.text('No input device available'), findsOneWidget);
    },
  );
}
