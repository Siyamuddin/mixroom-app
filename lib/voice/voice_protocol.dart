import 'dart:convert';

import 'package:crypto/crypto.dart';

class VoiceCommand {
  const VoiceCommand({
    required this.id,
    required this.sessionId,
    required this.projectSessionId,
    required this.kind,
    required this.arguments,
    required this.expiresAt,
    this.expectedRevision,
  });

  final String id;
  final String sessionId;
  final String projectSessionId;
  final String kind;
  final Map<String, dynamic> arguments;
  final DateTime expiresAt;
  final int? expectedRevision;

  factory VoiceCommand.fromJson(Map<String, dynamic> value) {
    final id = value['commandId'];
    final session = value['sessionId'];
    final project = value['projectSessionId'];
    final kind = value['kind'];
    final args = value['args'];
    final expiry = DateTime.tryParse(value['expiresAt']?.toString() ?? '');
    if (value['version'] != 1 ||
        id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        session is! String ||
        session.isEmpty ||
        project is! String ||
        project.isEmpty ||
        kind is! String ||
        kind.isEmpty ||
        args is! Map ||
        expiry == null ||
        (value['expectedProjectRevision'] != null &&
            value['expectedProjectRevision'] is! int)) {
      throw const FormatException('Invalid voice command envelope.');
    }
    return VoiceCommand(
      id: id,
      sessionId: session,
      projectSessionId: project,
      kind: kind,
      arguments: Map<String, dynamic>.from(args),
      expiresAt: expiry.toUtc(),
      expectedRevision: value['expectedProjectRevision'] as int?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'commandId': id,
    'sessionId': sessionId,
    'projectSessionId': projectSessionId,
    'kind': kind,
    'args': arguments,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (expectedRevision != null) 'expectedProjectRevision': expectedRevision,
  };

  String get fingerprint {
    Object? stable(Object? value) {
      if (value is Map) {
        final keys = value.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: stable(value[key])};
      }
      if (value is List) return value.map(stable).toList();
      return value;
    }

    return sha256.convert(utf8.encode(jsonEncode(stable(toJson())))).toString();
  }
}

class VoiceResult {
  const VoiceResult(this.status, this.message, {this.data = const {}});
  final String status;
  final String message;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'status': status,
    'message': message,
    'data': data,
  };

  factory VoiceResult.fromJson(Map<String, dynamic> value) => VoiceResult(
    value['status'] as String,
    value['message'] as String,
    data: Map<String, dynamic>.from(value['data'] as Map? ?? const {}),
  );
}

Duration voiceCaptureDuration(
  Map<String, dynamic> args, {
  required double bpm,
  required int beatsPerBar,
  int beatUnit = 4,
}) {
  final rawSeconds = args['duration_seconds'];
  final rawBars = args['bars'];
  if (rawSeconds != null && rawBars != null) {
    throw const FormatException('Choose a duration or bar count, not both.');
  }
  double seconds = 10;
  if (rawSeconds != null) {
    if (rawSeconds is! num) throw const FormatException('Invalid duration.');
    seconds = rawSeconds.toDouble();
  } else if (rawBars != null) {
    if (rawBars is! num ||
        !bpm.isFinite ||
        bpm <= 0 ||
        beatsPerBar < 1 ||
        beatUnit < 1) {
      throw const FormatException('Invalid bar count or tempo.');
    }
    seconds = rawBars.toDouble() * beatsPerBar * (4 / beatUnit) * 60 / bpm;
  }
  if (!seconds.isFinite || seconds < 1 || seconds > 60) {
    throw const FormatException('Recording must be between 1 and 60 seconds.');
  }
  return Duration(milliseconds: (seconds * 1000).round());
}
