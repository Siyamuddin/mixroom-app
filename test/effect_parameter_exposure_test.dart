import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/effect_parameter_exposure.dart';

void main() {
  group('effect parameter exposure', () {
    test('keeps only canonical reverb controls in canonical order', () {
      final params = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Damping', 'value': 0.2},
        <String, dynamic>{'name': 'Mix', 'value': 31.0},
        <String, dynamic>{'name': 'Room Size', 'value': 53.0},
        <String, dynamic>{'name': 'LPF', 'value': 0.7},
        <String, dynamic>{'name': 'Predelay', 'value': 12.0},
      ];

      final exposed = exposedEffectParameters('Reverb', params);

      expect(
        exposed.map((param) => param['name']),
        <String>['Room Size', 'Mix', 'Predelay'],
      );
    });

    test('serializes only exposed values for canonical effects', () {
      final values =
          exposedEffectParameterValues('Reverb', <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Room Size', 'value': 53.0},
        <String, dynamic>{'name': 'Mix', 'value': 31.0},
        <String, dynamic>{'name': 'Predelay', 'value': 12.0},
        <String, dynamic>{'name': 'Damping', 'value': 0.2},
      ]);

      expect(values, <String, dynamic>{
        'Room Size': 53.0,
        'Mix': 31.0,
        'Predelay': 12.0,
      });
    });

    test('filters old saved value maps for canonical effects', () {
      final values = exposedEffectParameterValueMap('Reverb', <String, dynamic>{
        'Room Size': 53.0,
        'Mix': 31.0,
        'Predelay': 12.0,
        'Damping': 0.2,
      });

      expect(values.keys, <String>['Room Size', 'Mix', 'Predelay']);
    });

    test('passes unknown plugin parameters through untouched', () {
      final params = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Custom A', 'value': 0.1},
        <String, dynamic>{'name': 'Custom B', 'value': 0.2},
      ];

      expect(exposedEffectParameters('Third Party', params), same(params));
      expect(
        exposedEffectParameterValueMap(
          'Third Party',
          <String, dynamic>{'Custom A': 0.1, 'Custom B': 0.2},
        ),
        <String, dynamic>{'Custom A': 0.1, 'Custom B': 0.2},
      );
    });
  });
}
