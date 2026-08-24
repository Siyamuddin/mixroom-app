import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/one_button_mix_profiles.dart';
import 'package:mixroom/models/mixing_result.dart';

void main() {
  test('offers baseline plus two all-tier proof-of-concept profiles', () {
    expect(OneButtonMixProfiles.all.map((profile) => profile.id), <String>[
      OneButtonMixProfiles.producerId,
      OneButtonMixProfiles.warmSpaciousId,
      OneButtonMixProfiles.punchyEnergeticId,
    ]);
  });

  test(
    'profile prompts contain distinct and bounded planning instructions',
    () {
      final warm = OneButtonMixProfiles.buildPrompt(
        OneButtonMixProfiles.warmSpaciousId,
      );
      final punchy = OneButtonMixProfiles.buildPrompt(
        OneButtonMixProfiles.punchyEnergeticId,
      );

      expect(warm, contains('warmer, wider, and more spacious'));
      expect(punchy, contains('tighter, more forward, and energetic'));
      expect(warm, contains('bounded'));
      expect(punchy, contains('bounded'));
      expect(warm, isNot(punchy));
    },
  );

  test('warm and punchy profiles bias the same actions differently', () {
    final source = <MixAction>[
      MixAction('adjust_effect_param_by_name', <String, dynamic>{
        'effect_name_contains': 'Reverb',
        'param_name_contains_any': <String>['Mix'],
        'mode': 'delta',
        'delta_norm': 0.10,
      }),
      MixAction('adjust_effect_param_by_name', <String, dynamic>{
        'effect_name_contains': 'Compressor',
        'param_name_contains_any': <String>['Ratio'],
        'mode': 'delta',
        'delta': 1.0,
      }),
    ];

    final warm = OneButtonMixProfiles.tuneActions(
      source,
      profileId: OneButtonMixProfiles.warmSpaciousId,
    );
    final punchy = OneButtonMixProfiles.tuneActions(
      source,
      profileId: OneButtonMixProfiles.punchyEnergeticId,
    );

    expect(warm[0].data['delta_norm'], closeTo(0.122, 0.0001));
    expect(punchy[0].data['delta_norm'], closeTo(0.075, 0.0001));
    expect(warm[1].data['delta'], closeTo(0.90, 0.0001));
    expect(punchy[1].data['delta'], closeTo(1.18, 0.0001));
  });

  test('baseline profile leaves actions unchanged', () {
    final action = MixAction('set_row_gain', <String, dynamic>{'delta': 0.2});
    final tuned = OneButtonMixProfiles.tuneActions(<MixAction>[
      action,
    ], profileId: OneButtonMixProfiles.producerId);
    expect(identical(tuned.first, action), isTrue);
  });
}
