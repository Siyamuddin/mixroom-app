import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/app_feature_flags.dart';

void main() {
  test('remote subscription enforcement false overrides fallback default', () {
    const fallback = AppFeatureFlags(
      flags: <String, bool>{
        AppFeatureFlagKeys.subscriptionEnforcementEnabled: true,
      },
      updatedAt: null,
      source: 'test',
    );

    final flags = AppFeatureFlags.fromJson(
      <String, dynamic>{
        'flags': <String, dynamic>{
          AppFeatureFlagKeys.subscriptionEnforcementEnabled: false,
        },
      },
      fallback: fallback,
    );

    expect(flags.subscriptionEnforcementEnabled, isFalse);
  });
}
