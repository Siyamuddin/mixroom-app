import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Must match common/plugin_identity.py. Preserve already sanitized IDs and
/// stable vendor IDs; paths use the same SHA-256 identity in capture and runtime.
String canonicalProducerPluginId(String value) {
  if (RegExp(r'^plugin_[a-f0-9]{64}$').hasMatch(value)) return value;
  final containsPath = RegExp(
    r'^(?:file://|/|\\)|[A-Za-z]:[\\/]|/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/',
  ).hasMatch(value);
  if (containsPath || RegExp(r'Bearer\s+\S+', caseSensitive: false).hasMatch(value)) {
    return 'plugin_${sha256.convert(utf8.encode(value))}';
  }
  return value;
}
