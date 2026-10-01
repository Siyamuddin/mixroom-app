import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/config/hackathon_config.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/crash_reporting/crash_reporting_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cloud_sync_preferences.dart';
import 'package:mixroom/helpers/desktop_auto_update_service.dart';
import 'package:mixroom/models/app_feature_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hackathon stays local even when a remote feature snapshot enables services',
      () async {
    // Run with --dart-define=MIXROOM_HACKATHON=true. No platform storage or
    // production service channel is installed: touching either fails this test.
    final auth = AuthService();
    expect(auth.isInitializing, isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(await auth.getIdTokenOrNull(), isNull);
    expect(AppApiConfig.hasApiBaseUrl, isFalse);
    expect(await CloudSyncPreferences.loadMode(), CloudSyncMode.manual);
    expect(DesktopAutoUpdateService.instance.isSupported, isFalse);
    expect(DesktopAutoUpdateService.instance.isConfigured, isFalse);
    await DesktopAutoUpdateService.instance.initialize();

    final flags = AppFeatureFlags.fromJson({
      'flags': {
        AppFeatureFlagKeys.cloudProjectsEnabled: true,
        AppFeatureFlagKeys.accountPlanBillingEnabled: true,
        AppFeatureFlagKeys.iapPurchasesEnabled: true,
        AppFeatureFlagKeys.subscriptionEnforcementEnabled: true,
      },
    });
    expect(flags.cloudProjectsEnabled, isFalse);
    expect(flags.accountPlanBillingEnabled, isFalse);
    expect(flags.iapPurchasesEnabled, isFalse);
    expect(flags.subscriptionEnforcementEnabled, isFalse);

    await AnalyticsService.instance.initialize();
    await AnalyticsService.instance.setCollectionEnabled(true);
    expect(AnalyticsService.instance.isCollectionEnabled, isFalse);
    await CrashReportingService.instance.initialize();
    await CrashReportingService.instance.setCollectionEnabled(true);
    await CrashReportingService.instance.captureException(StateError('local'));
    auth.dispose();
  }, skip: !HackathonConfig.enabled);
}
