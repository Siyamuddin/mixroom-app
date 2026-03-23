import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/daw_onboarding_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('seen state is scoped per user', () async {
    expect(await DawOnboardingPrefs.hasSeen('user-a'), isFalse);
    expect(await DawOnboardingPrefs.hasSeen('user-b'), isFalse);

    await DawOnboardingPrefs.markSeen('user-a');

    expect(await DawOnboardingPrefs.hasSeen('user-a'), isTrue);
    expect(await DawOnboardingPrefs.hasSeen('user-b'), isFalse);
  });

  test('pending quick tour is consumed once', () async {
    expect(await DawOnboardingPrefs.consumePendingQuickTour('user-a'), isFalse);

    await DawOnboardingPrefs.setPendingQuickTour('user-a', pending: true);

    expect(await DawOnboardingPrefs.consumePendingQuickTour('user-a'), isTrue);
    expect(await DawOnboardingPrefs.consumePendingQuickTour('user-a'), isFalse);
  });

  test('guest scope works when user id is null', () async {
    await DawOnboardingPrefs.setPendingQuickTour(null, pending: true);

    expect(await DawOnboardingPrefs.consumePendingQuickTour(null), isTrue);
    expect(await DawOnboardingPrefs.hasSeen(null), isFalse);

    await DawOnboardingPrefs.markSeen(null);

    expect(await DawOnboardingPrefs.hasSeen(null), isTrue);
  });
}
