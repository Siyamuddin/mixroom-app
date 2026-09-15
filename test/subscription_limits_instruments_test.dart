import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/models/entitlement_models.dart';

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

  test('only Free has a product-defined row creation limit', () {
    final paid = EntitlementSnapshot.fromJson(<String, dynamic>{
      'plan_code': 'producer',
      'status': 'active',
    }, fallbackUserId: 'paid-user');

    expect(SubscriptionLimits.rowCreationLimitFor(null), 5);
    expect(SubscriptionLimits.rowCreationLimitFor(paid), isNull);
  });

  test('Free admits rows one through five and rejects row six', () {
    for (var currentRows = 0; currentRows < 5; currentRows++) {
      expect(
        SubscriptionLimits.canCreateRows(
          currentRows: currentRows,
          count: 1,
          creationLimit: 5,
        ),
        isTrue,
      );
    }
    expect(
      SubscriptionLimits.canCreateRows(
        currentRows: 5,
        count: 1,
        creationLimit: 5,
      ),
      isFalse,
    );
    expect(
      SubscriptionLimits.canCreateRows(
        currentRows: 20,
        count: 0,
        creationLimit: 5,
      ),
      isTrue,
      reason: 'Oversized Free projects must remain editable.',
    );
  });

  test('paid capacity admits row 101 without a product limit', () {
    expect(
      SubscriptionLimits.canCreateRows(
        currentRows: 100,
        count: 1,
        creationLimit: null,
      ),
      isTrue,
    );
  });

  test('enforcement off uses the paid local project limit', () {
    expect(
      SubscriptionLimits.localProjectLimitForService(
        isEnforcementEnabled: false,
        entitlement: null,
      ),
      SubscriptionLimits.paidLocalProjects,
    );
    expect(
      SubscriptionLimits.localProjectLimitForService(
        isEnforcementEnabled: true,
        entitlement: null,
      ),
      SubscriptionLimits.freeLocalProjects,
    );
  });
}
