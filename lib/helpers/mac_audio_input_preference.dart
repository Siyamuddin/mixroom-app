import 'package:shared_preferences/shared_preferences.dart';

class MacAudioInputPreference {
  const MacAudioInputPreference._();

  static const String _uidKey = 'mixroom.audio.mac_input_uid.v1';

  static Future<String?> loadUID() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_uidKey)?.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  static Future<bool> saveUID(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = uid?.trim() ?? '';
    return normalized.isEmpty
        ? prefs.remove(_uidKey)
        : prefs.setString(_uidKey, normalized);
  }
}
