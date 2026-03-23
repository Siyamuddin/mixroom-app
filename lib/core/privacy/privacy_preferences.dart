import 'package:shared_preferences/shared_preferences.dart';

class PrivacyPreferences {
  const PrivacyPreferences._();

  static const String analyticsAndCrashDiagnosticsKey =
      'mixroom.privacy.analytics_diagnostics.v1';
  static const String productEmailsKey = 'mixroom.privacy.product_emails.v1';

  static Future<bool> isAnalyticsAndCrashDiagnosticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(analyticsAndCrashDiagnosticsKey) ?? true;
  }

  static Future<void> setAnalyticsAndCrashDiagnosticsEnabled(
      bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(analyticsAndCrashDiagnosticsKey, enabled);
  }

  static Future<void> setProductEmailsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(productEmailsKey, enabled);
  }
}
