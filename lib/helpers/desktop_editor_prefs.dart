import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mixroom/helpers/desktop_slider_wheel_sensitivity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mixroom/helpers/sample_browser_roots.dart';

class DesktopEditorWindowLayout {
  const DesktopEditorWindowLayout({
    required this.leftFraction,
    required this.topFraction,
    required this.widthFraction,
    required this.heightFraction,
  });

  final double leftFraction;
  final double topFraction;
  final double widthFraction;
  final double heightFraction;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'leftFraction': leftFraction,
    'topFraction': topFraction,
    'widthFraction': widthFraction,
    'heightFraction': heightFraction,
  };

  static DesktopEditorWindowLayout? fromJson(Map<String, dynamic> json) {
    final left = (json['leftFraction'] as num?)?.toDouble();
    final top = (json['topFraction'] as num?)?.toDouble();
    final width = (json['widthFraction'] as num?)?.toDouble();
    final height = (json['heightFraction'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return DesktopEditorWindowLayout(
      leftFraction: left,
      topFraction: top,
      widthFraction: width,
      heightFraction: height,
    );
  }
}

class DesktopShortcutBinding {
  const DesktopShortcutBinding({
    required this.keyId,
    this.meta = false,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final int keyId;
  final bool meta;
  final bool control;
  final bool shift;
  final bool alt;

  LogicalKeyboardKey? get logicalKey =>
      LogicalKeyboardKey.findKeyByKeyId(keyId);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'keyId': keyId,
    'meta': meta,
    'control': control,
    'shift': shift,
    'alt': alt,
  };

  static DesktopShortcutBinding? fromJson(Map<String, dynamic> json) {
    final keyId = (json['keyId'] as num?)?.toInt();
    if (keyId == null) return null;
    return DesktopShortcutBinding(
      keyId: keyId,
      meta: json['meta'] == true,
      control: json['control'] == true,
      shift: json['shift'] == true,
      alt: json['alt'] == true,
    );
  }
}

class DesktopPluginPrefs {
  const DesktopPluginPrefs({
    required this.favoritePluginIds,
    required this.hiddenPluginIds,
    required this.scanPaths,
    this.cachedPlugins = const <Map<String, dynamic>>[],
    this.hostedWindowsDetached = false,
    this.lastRescanAtMs,
  });

  final Set<String> favoritePluginIds;
  final Set<String> hiddenPluginIds;
  final List<String> scanPaths;
  final List<Map<String, dynamic>> cachedPlugins;
  final bool hostedWindowsDetached;
  final int? lastRescanAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'favoritePluginIds': favoritePluginIds.toList()..sort(),
    'hiddenPluginIds': hiddenPluginIds.toList()..sort(),
    'scanPaths': scanPaths,
    'cachedPlugins': cachedPlugins
        .map(_sanitizePluginJson)
        .where(_hasPluginIdentity)
        .toList(),
    'hostedWindowsDetached': hostedWindowsDetached,
    if (lastRescanAtMs != null) 'lastRescanAtMs': lastRescanAtMs,
  };

  static DesktopPluginPrefs fromJson(Map<String, dynamic> json) {
    Set<String> readStringSet(String key) {
      final raw = json[key];
      if (raw is! List) return <String>{};
      return raw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }

    List<Map<String, dynamic>> readPluginList(String key) {
      final raw = json[key];
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map(
            (plugin) => _sanitizePluginJson(Map<String, dynamic>.from(plugin)),
          )
          .where(_hasPluginIdentity)
          .toList(growable: false);
    }

    return DesktopPluginPrefs(
      favoritePluginIds: readStringSet('favoritePluginIds'),
      hiddenPluginIds: readStringSet('hiddenPluginIds'),
      scanPaths: ((json['scanPaths'] as List?) ?? const <Object?>[])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      cachedPlugins: readPluginList('cachedPlugins'),
      hostedWindowsDetached: json['hostedWindowsDetached'] == true,
      lastRescanAtMs: (json['lastRescanAtMs'] as num?)?.toInt(),
    );
  }

  static Map<String, dynamic> _sanitizePluginJson(Map<String, dynamic> plugin) {
    final out = <String, dynamic>{};
    final id = plugin['id']?.toString().trim() ?? '';
    final name = plugin['name']?.toString().trim() ?? '';
    if (id.isNotEmpty) out['id'] = id;
    if (name.isNotEmpty) out['name'] = name;

    for (final key in <String>['format', 'manufacturer', 'category']) {
      final value = plugin[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) out[key] = value;
    }
    for (final key in <String>[
      'isInstrument',
      'quarantined',
      'favorite',
      'hidden',
    ]) {
      if (plugin[key] is bool) out[key] = plugin[key] == true;
    }
    return out;
  }

  static bool _hasPluginIdentity(Map<String, dynamic> plugin) {
    final id = (plugin['id'] as String?)?.trim() ?? '';
    final name = (plugin['name'] as String?)?.trim() ?? '';
    return id.isNotEmpty && name.isNotEmpty;
  }
}

class DesktopEditorPrefs {
  DesktopEditorPrefs._();

  static const String _windowKeyPrefix = 'mixroom.desktop.windows.v1';
  static const String _shortcutKeyPrefix = 'mixroom.desktop.shortcuts.v1';
  static const String _sliderWheelSensitivityKeyPrefix =
      'mixroom.desktop.slider_wheel_sensitivity.v1';
  static const String _sampleRootsKeyPrefix = 'mixroom.desktop.sample_roots.v1';
  static const String _pluginPrefsKeyPrefix = 'mixroom.desktop.plugins.v1';

  static String _scope(String? userId) {
    final trimmed = (userId ?? '').trim();
    return trimmed.isEmpty ? 'guest' : trimmed;
  }

  static String _windowKey(String? userId) =>
      '$_windowKeyPrefix.${_scope(userId)}';
  static String _shortcutKey(String? userId) =>
      '$_shortcutKeyPrefix.${_scope(userId)}';
  static String _sliderWheelSensitivityKey(String? userId) =>
      '$_sliderWheelSensitivityKeyPrefix.${_scope(userId)}';
  static String _sampleRootsKey(String? userId) =>
      '$_sampleRootsKeyPrefix.${_scope(userId)}';
  static String _sampleAccessKey(String? userId) =>
      '${_sampleRootsKey(userId)}.access';
  static String _pluginPrefsKey(String? userId) =>
      '$_pluginPrefsKeyPrefix.${_scope(userId)}';

  static Future<Map<String, DesktopEditorWindowLayout>> loadWindowLayouts(
    String? userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_windowKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return <String, DesktopEditorWindowLayout>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, DesktopEditorWindowLayout>{};
      }
      final out = <String, DesktopEditorWindowLayout>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final layout = DesktopEditorWindowLayout.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (layout != null) {
          out[entry.key as String] = layout;
        }
      }
      return out;
    } catch (_) {
      return <String, DesktopEditorWindowLayout>{};
    }
  }

  static Future<void> saveWindowLayouts(
    String? userId,
    Map<String, DesktopEditorWindowLayout> layouts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    for (final entry in layouts.entries) {
      encoded[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_windowKey(userId), jsonEncode(encoded));
  }

  static Future<Map<String, DesktopShortcutBinding>> loadShortcuts(
    String? userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shortcutKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return <String, DesktopShortcutBinding>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, DesktopShortcutBinding>{};
      }
      final out = <String, DesktopShortcutBinding>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final binding = DesktopShortcutBinding.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (binding != null) {
          out[entry.key as String] = binding;
        }
      }
      return out;
    } catch (_) {
      return <String, DesktopShortcutBinding>{};
    }
  }

  static Future<void> saveShortcuts(
    String? userId,
    Map<String, DesktopShortcutBinding> shortcuts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    for (final entry in shortcuts.entries) {
      encoded[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_shortcutKey(userId), jsonEncode(encoded));
  }

  static Future<void> clearShortcuts(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shortcutKey(userId));
  }

  static Future<DesktopSliderWheelSensitivity> loadSliderWheelSensitivity(
    String? userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sliderWheelSensitivityKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return DesktopSliderWheelSensitivity.defaults;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return DesktopSliderWheelSensitivity.defaults;
      }
      return DesktopSliderWheelSensitivity.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return DesktopSliderWheelSensitivity.defaults;
    }
  }

  static Future<void> saveSliderWheelSensitivity(
    String? userId,
    DesktopSliderWheelSensitivity sensitivity,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sliderWheelSensitivityKey(userId),
      jsonEncode(sensitivity.toJson()),
    );
  }

  static Future<void> clearSliderWheelSensitivity(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sliderWheelSensitivityKey(userId));
  }

  static Future<List<String>> loadSampleBrowserRoots(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(_sampleRootsKey(userId)) ?? const <String>[];
    return raw
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> saveSampleBrowserRoots(
    String? userId,
    Iterable<String> roots,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = roots
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    await prefs.setStringList(_sampleRootsKey(userId), normalized);
  }

  static Future<List<SampleBrowserRootAccess>> loadSampleBrowserAccess(
    String? userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sampleAccessKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return (prefs.getStringList(_sampleRootsKey(userId)) ?? const <String>[])
          .map((path) => SampleBrowserRootAccess(path: path))
          .toList(growable: false);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SampleBrowserRootAccess>[];
      return decoded
          .map(SampleBrowserRootAccess.fromJson)
          .whereType<SampleBrowserRootAccess>()
          .toList(growable: false);
    } catch (_) {
      return const <SampleBrowserRootAccess>[];
    }
  }

  static Future<void> saveSampleBrowserAccess(
    String? userId,
    Iterable<SampleBrowserRootAccess> access,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = <String, SampleBrowserRootAccess>{};
    for (final entry in access) {
      final path = entry.path.trim();
      if (path.isEmpty) continue;
      normalized[path] = entry;
    }
    await prefs.setString(
      _sampleAccessKey(userId),
      jsonEncode(normalized.values.map((entry) => entry.toJson()).toList()),
    );
    await prefs.setStringList(
      _sampleRootsKey(userId),
      normalized.keys.toList(growable: false),
    );
  }

  static Future<DesktopPluginPrefs> loadPluginPrefs(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pluginPrefsKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return const DesktopPluginPrefs(
        favoritePluginIds: <String>{},
        hiddenPluginIds: <String>{},
        scanPaths: <String>[],
        hostedWindowsDetached: false,
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const DesktopPluginPrefs(
          favoritePluginIds: <String>{},
          hiddenPluginIds: <String>{},
          scanPaths: <String>[],
          hostedWindowsDetached: false,
        );
      }
      return DesktopPluginPrefs.fromJson(decoded);
    } catch (_) {
      return const DesktopPluginPrefs(
        favoritePluginIds: <String>{},
        hiddenPluginIds: <String>{},
        scanPaths: <String>[],
        hostedWindowsDetached: false,
      );
    }
  }

  static Future<void> savePluginPrefs(
    String? userId,
    DesktopPluginPrefs prefsValue,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pluginPrefsKey(userId),
      jsonEncode(prefsValue.toJson()),
    );
  }
}
