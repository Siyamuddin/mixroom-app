import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/mac_input_channel_policy.dart';
import 'package:mixroom/widgets/mac_input_channel_selector.dart';

Widget ui({
  int capacity = 2,
  MacInputChannelOption selection = const MacInputChannelOption(0, 1),
  bool enabled = true,
  String? status,
  ValueChanged<MacInputChannelOption>? onChanged,
}) => MaterialApp(
  home: Scaffold(
    body: MacInputChannelSelector(
      capacity: capacity,
      names: const [],
      selection: selection,
      enabled: enabled,
      status: status,
      decoration: const InputDecoration(labelText: 'Input Channel'),
      onChanged: onChanged ?? (_) {},
    ),
  ),
);
void main() {
  testWidgets('mono remains visible without a useless dropdown', (
    tester,
  ) async {
    await tester.pumpWidget(ui(capacity: 1));
    expect(find.text('Input 1 (Mono)'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<MacInputChannelOption>),
      findsNothing,
    );
  });
  testWidgets(
    'saved unavailable stereo requires explicit replacement even on mono',
    (tester) async {
      MacInputChannelOption? chosen;
      await tester.pumpWidget(
        ui(
          capacity: 1,
          selection: const MacInputChannelOption(4, 2),
          onChanged: (o) => chosen = o,
        ),
      );
      expect(find.text('Inputs 5–6 — Unavailable'), findsWidgets);
      expect(chosen, isNull);
      await tester.tap(find.byType(DropdownButton<MacInputChannelOption>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Input 1').last);
      await tester.pumpAndSettle();
      expect(chosen, const MacInputChannelOption(0, 1));
    },
  );
  testWidgets(
    'track changes display the new saved selection and capture disables edits',
    (tester) async {
      await tester.pumpWidget(
        ui(capacity: 4, selection: const MacInputChannelOption(0, 2)),
      );
      await tester.pumpWidget(
        ui(
          capacity: 4,
          selection: const MacInputChannelOption(2, 2),
          enabled: false,
        ),
      );
      final field = tester
          .widget<DropdownButtonFormField<MacInputChannelOption>>(
            find.byType(DropdownButtonFormField<MacInputChannelOption>),
          );
      expect(field.initialValue, const MacInputChannelOption(2, 2));
      expect(field.onChanged, isNull);
    },
  );
  testWidgets('loading missing and failed metadata offer no invented inputs', (
    tester,
  ) async {
    for (final status in [
      'Loading input channels…',
      'No input device available',
      'Input channel information unavailable',
    ]) {
      await tester.pumpWidget(ui(status: status));
      expect(find.text(status), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<MacInputChannelOption>),
        findsNothing,
      );
    }
  });
}
