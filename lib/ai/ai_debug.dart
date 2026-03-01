import 'dart:developer' as developer;

const bool kAiDebugLogs = bool.fromEnvironment(
  'MIXROOM_AI_DEBUG',
  defaultValue: false,
);

const bool kAiDebugVerbose = bool.fromEnvironment(
  'MIXROOM_AI_DEBUG_VERBOSE',
  defaultValue: false,
);

void aiDebugLog(String scope, String message) {
  if (!kAiDebugLogs) return;
  developer.log(message, name: 'AI.$scope');
}

String aiDebugShortMap(
  Map<String, dynamic> map, {
  int maxEntries = 8,
  int maxValueLen = 80,
}) {
  if (map.isEmpty) return '{}';
  final entries = map.entries.toList();
  final b = StringBuffer('{');
  for (int i = 0; i < entries.length && i < maxEntries; i++) {
    final e = entries[i];
    if (i > 0) b.write(', ');
    final v = e.value;
    String s;
    if (v is List) {
      s = 'list(${v.length})';
    } else if (v is Map) {
      s = 'map(${v.length})';
    } else {
      s = v.toString();
    }
    if (s.length > maxValueLen) {
      s = '${s.substring(0, maxValueLen)}...';
    }
    b.write('${e.key}: $s');
  }
  if (entries.length > maxEntries) b.write(', ...');
  b.write('}');
  return b.toString();
}
