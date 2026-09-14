import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_execution_expectations.dart';

void main() {
  test('row instrument verification uses the final planned row name', () {
    final runtime = <String, dynamic>{
      'kind': 'row_instrument',
      'row_id': 7,
      'row_name': 'Old name',
      'instrument_id': 'piano',
    };

    final reconciled = aiV3RowInstrumentExpectationForFinalState(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'row_name',
          'row_id': 7,
          'value': 'Happy Piano',
        },
      ],
      runtime,
    );

    expect(reconciled['row_name'], 'Happy Piano');
    expect(reconciled['instrument_id'], 'piano');
    expect(runtime['row_name'], 'Old name');
  });

  test('row instrument verification ignores renames for another row', () {
    final runtime = <String, dynamic>{
      'kind': 'row_instrument',
      'row_id': 7,
      'row_name': 'Keep me',
    };

    final reconciled = aiV3RowInstrumentExpectationForFinalState(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'row_name',
          'row_id': 8,
          'value': 'Other row',
        },
      ],
      runtime,
    );

    expect(reconciled['row_name'], 'Keep me');
  });

  test('effect observation falls back to matching native readback', () {
    final observed = aiV3EffectObservationWithNativeFallback(
      snapshotEffects: const <Map<String, dynamic>>[],
      nativeEffectNames: const <String>['EQ 3-Band', 'Reverb'],
      requiredNeedle: 'reverb',
    );

    expect(observed, const <Map<String, dynamic>>[
      <String, dynamic>{'display_name': 'Reverb'},
    ]);
  });

  test('effect observation remains strict when native readback is absent', () {
    expect(
      () => aiV3EffectObservationWithNativeFallback(
        snapshotEffects: const <Map<String, dynamic>>[],
        nativeEffectNames: const <String>['EQ 3-Band'],
        requiredNeedle: 'reverb',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'v3_effect_observation_missing',
        ),
      ),
    );
  });

  test('deleted-row matching uses a stable row id when available', () {
    expect(
      aiV3ExpectationMatchesDeletedStableRow(
        <String, dynamic>{'row_id': 42, 'row': 1},
        rowId: 42,
        rowIndex: 3,
      ),
      isTrue,
    );
  });

  test('deleted-row matching supports stable index-only expectations', () {
    expect(
      aiV3ExpectationMatchesDeletedStableRow(
        <String, dynamic>{'row': 3},
        rowId: 42,
        rowIndex: 3,
      ),
      isTrue,
    );
  });

  test('generated-row prediction cannot alias a deleted stable row', () {
    expect(
      aiV3ExpectationMatchesDeletedStableRow(
        <String, dynamic>{
          'row': 3,
          'destination_row_ref': <String, dynamic>{
            'command_id': 'create-jazz-row',
            'output': 'row',
          },
        },
        rowId: 42,
        rowIndex: 3,
      ),
      isFalse,
    );
  });
}
