import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/subscription_limits.dart';

void main() {
  test('both bundled guitars are available on the free plan', () {
    const guitarIds = <String>[
      'sfz.guitar.steel_acoustic',
      'sfz.guitar.clean_electric',
    ];

    for (final id in guitarIds) {
      expect(SubscriptionLimits.freeBuiltInInstrumentIds, contains(id));
      expect(
        SubscriptionLimits.canUseInstrument(null, id),
        isTrue,
        reason: '$id must be usable without a paid entitlement.',
      );
    }
  });
}
