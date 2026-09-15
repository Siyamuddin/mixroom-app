import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Must match common/plugin_identity.py. Preserve already sanitized IDs and
/// stable vendor IDs; paths use the same SHA-256 identity in capture and runtime.
String canonicalProducerPluginId(String value) {
  if (RegExp(r'^plugin_[a-f0-9]{64}$').hasMatch(value)) return value;
  final containsPath = RegExp(
    r'^(?:file://|/|\\)|[A-Za-z]:[\\/]|/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/',
  ).hasMatch(value);
  if (containsPath ||
      RegExp(r'Bearer\s+\S+', caseSensitive: false).hasMatch(value)) {
    return 'plugin_${sha256.convert(utf8.encode(value))}';
  }
  return value;
}

/// Convert only the native host's qualified descriptor, never a filename.
String producerModelPluginId(String descriptor) {
  const prefix = 'plugin_descriptor_v1:';
  if (!descriptor.startsWith(prefix)) return '';
  try {
    final fields = jsonDecode(descriptor.substring(prefix.length));
    if (fields is! List ||
        fields.length != 5 ||
        fields.any((v) => v is! String) ||
        fields.take(4).any((v) => (v as String).isEmpty) ||
        !RegExp(r'^[a-fA-F0-9]{1,8}$').hasMatch(fields[3]) ||
        int.parse(fields[3], radix: 16) == 0) {
      return '';
    }
    fields[3] = int.parse(fields[3], radix: 16).toRadixString(16);
    return 'plugin_uid_v1_${sha256.convert(utf8.encode(jsonEncode(fields)))}';
  } on FormatException {
    return '';
  }
}
