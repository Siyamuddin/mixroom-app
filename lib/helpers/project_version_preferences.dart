import 'package:shared_preferences/shared_preferences.dart';

class ProjectVersionPreferences {
  static const String enabledKey = 'mixroom.project_version_history.enabled.v1';

  const ProjectVersionPreferences._();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, enabled);
  }
}
