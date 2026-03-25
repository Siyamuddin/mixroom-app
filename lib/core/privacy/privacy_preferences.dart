import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyPreferences {
  const PrivacyPreferences._();

  static const String analyticsAndCrashDiagnosticsKey =
      'mixroom.privacy.analytics_diagnostics.v1';
  static const String productEmailsKey = 'mixroom.privacy.product_emails.v1';

  static Future<bool> isAnalyticsAndCrashDiagnosticsEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(analyticsAndCrashDiagnosticsKey) ?? true;
    } catch (error) {
      debugPrint(
          'PrivacyPreferences: failed to read diagnostics preference: $error');
      return true;
    }
  }

  static Future<void> setAnalyticsAndCrashDiagnosticsEnabled(
      bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(analyticsAndCrashDiagnosticsKey, enabled);
    } catch (error) {
      debugPrint(
          'PrivacyPreferences: failed to persist diagnostics preference: $error');
    }
  }

  static Future<void> setProductEmailsEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(productEmailsKey, enabled);
    } catch (error) {
      debugPrint(
          'PrivacyPreferences: failed to persist product emails preference: $error');
    }
  }
}
