import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/widgets/system_default_mono_input_channel_selector.dart';

void main() {
  Widget view({
    bool known = true,
    bool? available = true,
    bool loading = false,
    int start = 0,
    int count = 1,
    bool enabled = true,
    VoidCallback? replace,
  }) => MaterialApp(
    home: Scaffold(
      body: SystemDefaultMonoInputChannelSelector(
        configurationKnown: known,
        loading: loading,
        inputAvailable: available,
        supportedStart: 0,
        supportedCount: 1,
        start: start,
        count: count,
        enabled: enabled,
        decoration: const InputDecoration(labelText: 'Input Channel'),
        onUseSupportedInput: replace ?? () {},
      ),
    ),
  );

  testWidgets('valid mono route is a read-only value', (tester) async {
    await tester.pumpWidget(view());
    expect(find.text('Input 1 (Mono)'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
  });

  testWidgets('unavailable saved route changes only through explicit action', (
    tester,
  ) async {
    var replacements = 0;
    await tester.pumpWidget(view(count: 2, replace: () => replacements += 1));
    expect(find.text('Inputs 1–2 — Unavailable'), findsOneWidget);
    expect(
      find.text('Choose the supported input before recording or monitoring.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use Input 1 (Mono)'));
    expect(replacements, 1);

    await tester.pumpWidget(
      view(start: 7, enabled: false, replace: () => replacements += 1),
    );
    expect(find.text('Input 8 — Unavailable'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });

  testWidgets('unknown policy and confirmed no input are distinct', (
    tester,
  ) async {
    await tester.pumpWidget(view(known: false, available: null));
    expect(find.text('Input information unavailable'), findsOneWidget);
    expect(find.text('No input device available'), findsNothing);

    await tester.pumpWidget(view(available: false));
    expect(find.text('Input 1 (Mono)'), findsOneWidget);
    expect(find.text('No input device available'), findsOneWidget);
  });

  testWidgets('loading is distinct from unavailable information', (
    tester,
  ) async {
    await tester.pumpWidget(view(known: false, available: null, loading: true));

    expect(find.text('Loading input information…'), findsOneWidget);
    expect(find.text('Input information unavailable'), findsNothing);
  });
}
