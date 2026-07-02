import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
}
