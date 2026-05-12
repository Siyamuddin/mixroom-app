import 'package:shared_preferences/shared_preferences.dart';

enum CloudSyncMode {
  auto,
  manual,
}

class CloudSyncPreferences {
  CloudSyncPreferences._();

  static const String _modeKey = 'mixroom.cloud_sync.mode.v1';
  static const String _defaultWorkspaceKey =
      'mixroom.cloud_sync.default_workspace_id.v1';

  static Future<CloudSyncMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey);
    return switch (raw) {
      'manual' => CloudSyncMode.manual,
      _ => CloudSyncMode.auto,
    };
  }

  static Future<void> saveMode(CloudSyncMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  static Future<String> loadDefaultWorkspaceId() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_defaultWorkspaceKey) ?? '').trim();
  }

  static Future<void> saveDefaultWorkspaceId(String workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = workspaceId.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_defaultWorkspaceKey);
    } else {
      await prefs.setString(_defaultWorkspaceKey, trimmed);
    }
  }
}
