import 'package:shared_preferences/shared_preferences.dart';

class DawOnboardingPrefs {
  DawOnboardingPrefs._();

  static const String _seenKeyPrefix = 'mixroom.daw_onboarding.seen.v1';
  static const String _pendingKeyPrefix = 'mixroom.daw_onboarding.pending.v1';

  static String _scope(String? userId) {
    final trimmed = (userId ?? '').trim();
    return trimmed.isEmpty ? 'guest' : trimmed;
  }

  static String _seenKey(String? userId) => '$_seenKeyPrefix.${_scope(userId)}';
  static String _pendingKey(String? userId) =>
      '$_pendingKeyPrefix.${_scope(userId)}';

  static Future<bool> hasSeen(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey(userId)) ?? false;
  }

  static Future<void> markSeen(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey(userId), true);
  }

  static Future<void> setPendingQuickTour(
    String? userId, {
    required bool pending,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingKey(userId), pending);
  }

  static Future<bool> consumePendingQuickTour(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _pendingKey(userId);
    final pending = prefs.getBool(key) ?? false;
    if (pending) {
      await prefs.remove(key);
    }
    return pending;
  }
}
