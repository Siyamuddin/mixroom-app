import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/automation_target_labels.dart';

void main() {
  group('buildAutomationEffectDisplayLabels', () {
    test('adds numbered suffixes when effect names repeat', () {
      final labels = buildAutomationEffectDisplayLabels(
        effectNames: const <String>[
          'Compressor',
          'EQ',
          'Compressor',
          'Compressor',
        ],
      );

      expect(
        labels.map((label) => label.displayName).toList(growable: false),
        const <String>[
          'Compressor #1',
          'EQ',
          'Compressor #2',
          'Compressor #3',
        ],
      );
    });

    test('falls back to effect ids when display names are empty', () {
      final labels = buildAutomationEffectDisplayLabels(
        effectNames: const <String>['', ''],
        fallbackIds: const <String>['mixroom.comp', 'mixroom.comp'],
      );

      expect(
        labels.map((label) => label.displayName).toList(growable: false),
        const <String>[
          'mixroom.comp #1',
          'mixroom.comp #2',
        ],
      );
    });

    test('does not suffix unique names', () {
      final labels = buildAutomationEffectDisplayLabels(
        effectNames: const <String>['Reverb', 'Delay', 'EQ'],
      );

      expect(
        labels.map((label) => label.displayName).toList(growable: false),
        const <String>['Reverb', 'Delay', 'EQ'],
      );
    });
  });
}
