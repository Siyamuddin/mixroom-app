import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class SampleBrowserRootAccess {
  final String path;
  final String? persistentToken;

  const SampleBrowserRootAccess({required this.path, this.persistentToken});

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    if (persistentToken?.trim().isNotEmpty == true)
      'persistentToken': persistentToken,
  };

  static SampleBrowserRootAccess? fromJson(dynamic value) {
    if (value is! Map) return null;
    final path = SampleBrowserRootDefaults.normalizeRoot(
      value['path']?.toString(),
    );
    if (path.isEmpty) return null;
    final token = value['persistentToken']?.toString().trim();
    return SampleBrowserRootAccess(
      path: path,
      persistentToken: token == null || token.isEmpty ? null : token,
    );
  }
}

class SampleBrowserAccess {
  SampleBrowserAccess._();

  static const MethodChannel _channel = MethodChannel(
    'mixroom/sample_browser_access',
  );

  static Future<SampleBrowserRootAccess?> pickDirectory() async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel.invokeMethod<dynamic>('pickDirectory');
    return SampleBrowserRootAccess.fromJson(raw);
  }

  static Future<SampleBrowserRootAccess?> createPersistentAccess(
    String path,
  ) async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      return SampleBrowserRootAccess(
        path: SampleBrowserRootDefaults.normalizeRoot(path),
      );
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'createBookmark',
        <String, dynamic>{'path': path},
      );
      return SampleBrowserRootAccess.fromJson(raw) ??
          SampleBrowserRootAccess(
            path: SampleBrowserRootDefaults.normalizeRoot(path),
          );
    } on MissingPluginException {
      return SampleBrowserRootAccess(
        path: SampleBrowserRootDefaults.normalizeRoot(path),
      );
    } on PlatformException {
      return SampleBrowserRootAccess(
        path: SampleBrowserRootDefaults.normalizeRoot(path),
      );
    }
  }

  static Future<SampleBrowserRootAccess?> restore(
    SampleBrowserRootAccess access,
  ) async {
    final token = access.persistentToken?.trim();
    if (token == null || token.isEmpty) return access;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'restoreAccess',
        <String, dynamic>{'token': token, 'path': access.path},
      );
      return SampleBrowserRootAccess.fromJson(raw) ?? access;
    } on MissingPluginException {
      return access;
    } on PlatformException {
      return access;
    }
  }

  static Future<void> release(String token) async {
    if (token.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('releaseAccess', <String, dynamic>{
        'token': token,
      });
    } catch (_) {}
  }
}

class SampleBrowserRootDefaults {
  SampleBrowserRootDefaults._();

  static String normalizeRoot(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('file://')) {
      try {
        return p.normalize(Uri.parse(value).toFilePath());
      } catch (_) {
        return value;
      }
    }
    if (value.contains('://')) return value;
    return p.normalize(value);
  }

  static List<String> orderedRoots({
    required Iterable<String> bundledRoots,
    required String? projectAudioRoot,
    required String? userDropRoot,
    required Iterable<String> userRoots,
  }) {
    final roots = <String>[];
    final seen = <String>{};

    void addRoot(String? raw) {
      final normalized = normalizeRoot(raw);
      if (normalized.isEmpty || seen.contains(normalized)) return;
      roots.add(normalized);
      seen.add(normalized);
    }

    for (final root in bundledRoots) {
      addRoot(root);
    }
    addRoot(projectAudioRoot);
    addRoot(userDropRoot);
    for (final root in userRoots) {
      addRoot(root);
    }

    return roots;
  }

  static Set<String> fixedRoots({
    required String? projectAudioRoot,
    required String? userDropRoot,
  }) {
    return <String>{
      normalizeRoot(projectAudioRoot),
      normalizeRoot(userDropRoot),
    }..remove('');
  }

  static bool isAndroidSharedStoragePath(String? raw) {
    final normalized = normalizeRoot(raw);
    if (normalized.isEmpty) return false;
    return normalized == '/sdcard' ||
        normalized.startsWith('/sdcard/') ||
        normalized == '/storage/self/primary' ||
        normalized.startsWith('/storage/self/primary/') ||
        normalized == '/storage/emulated/0' ||
        normalized.startsWith('/storage/emulated/0/') ||
        RegExp(r'^/storage/[^/]+(?:/|$)').hasMatch(normalized);
  }

  static List<String> persistableUserRoots({
    required Iterable<String> roots,
    required Iterable<String> nonPersistedRoots,
  }) {
    final blocked = nonPersistedRoots
        .map(normalizeRoot)
        .where((root) => root.isNotEmpty)
        .toSet();
    final persisted = <String>[];
    final seen = <String>{};
    for (final root in roots) {
      final normalized = normalizeRoot(root);
      if (normalized.isEmpty ||
          blocked.contains(normalized) ||
          seen.contains(normalized)) {
        continue;
      }
      persisted.add(normalized);
      seen.add(normalized);
    }
    return persisted;
  }
}

class MobileSampleBrowserPrefs {
  MobileSampleBrowserPrefs._();

  static const String _rootsPrefix = 'mobile_sample_browser_roots_v1';

  static String _rootsKey(String? userId) {
    final trimmed = userId?.trim() ?? '';
    return trimmed.isEmpty
        ? '$_rootsPrefix:anonymous'
        : '$_rootsPrefix:$trimmed';
  }

  static String _accessKey(String? userId) => '${_rootsKey(userId)}:access';

  static Future<List<String>> loadSampleBrowserRoots(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_rootsKey(userId)) ?? const <String>[];
    return SampleBrowserRootDefaults.persistableUserRoots(
      roots: raw,
      nonPersistedRoots: const <String>[],
    );
  }

  static Future<void> saveSampleBrowserRoots(
    String? userId,
    Iterable<String> roots,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _rootsKey(userId),
      SampleBrowserRootDefaults.persistableUserRoots(
        roots: roots,
        nonPersistedRoots: const <String>[],
      ),
    );
  }

  static Future<List<SampleBrowserRootAccess>> loadSampleBrowserAccess(
    String? userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accessKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return (prefs.getStringList(_rootsKey(userId)) ?? const <String>[])
          .map(
            (path) => SampleBrowserRootAccess(
              path: SampleBrowserRootDefaults.normalizeRoot(path),
            ),
          )
          .where((access) => access.path.isNotEmpty)
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
      final path = SampleBrowserRootDefaults.normalizeRoot(entry.path);
      if (path.isEmpty) continue;
      normalized[path] = SampleBrowserRootAccess(
        path: path,
        persistentToken: entry.persistentToken,
      );
    }
    await prefs.setString(
      _accessKey(userId),
      jsonEncode(normalized.values.map((entry) => entry.toJson()).toList()),
    );
    await prefs.setStringList(_rootsKey(userId), normalized.keys.toList());
  }
}
