import 'dart:convert';
import 'dart:io';

import 'voice_protocol.dart';

/// Durable deduplication. An interrupted execution is never retried implicitly.
class VoiceCommandJournal {
  VoiceCommandJournal({this.file});
  final File? file;
  final Map<String, Map<String, dynamic>> _entries = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    if (file != null && await file!.exists()) {
      final decoded = jsonDecode(await file!.readAsString());
      if (decoded is! Map)
        throw const FormatException('Invalid command journal.');
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          final value = Map<String, dynamic>.from(entry.value as Map);
          if (value['status'] == 'running') {
            value['status'] = 'outcome_unknown';
            value['result'] = const VoiceResult(
              'outcome_unknown',
              'The app restarted during this request. Check the project before trying again.',
            ).toJson();
          }
          _entries[entry.key.toString()] = value;
        }
      }
    }
    _loaded = true;
    await _save();
  }

  VoiceResult? lookup(VoiceCommand command) {
    final value = _entries[command.id];
    if (value == null) return null;
    if (value['fingerprint'] != command.fingerprint) {
      return const VoiceResult(
        'rejected',
        'A command ID was reused with different content.',
      );
    }
    final raw = value['result'];
    if (raw is Map) return VoiceResult.fromJson(Map<String, dynamic>.from(raw));
    return const VoiceResult('running', 'This request is already running.');
  }

  Future<void> begin(VoiceCommand command) async {
    if (!_loaded) throw StateError('journal_not_loaded');
    if (_entries.containsKey(command.id))
      throw StateError('command_already_seen');
    _entries[command.id] = {
      'fingerprint': command.fingerprint,
      'status': 'running',
      'expiresAt': command.expiresAt.toIso8601String(),
    };
    await _save();
  }

  Future<void> complete(VoiceCommand command, VoiceResult result) async {
    final value = _entries[command.id];
    if (value == null || value['fingerprint'] != command.fingerprint) {
      throw StateError('command_journal_identity_mismatch');
    }
    value['status'] = result.status;
    value['result'] = result.toJson();
    await _save();
  }

  Future<void> _save() async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.pending');
    await temporary.writeAsString(jsonEncode(_entries), flush: true);
    await temporary.rename(target.path);
  }
}
