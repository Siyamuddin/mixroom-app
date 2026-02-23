import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProducerDataCollector {
  static const String _dirName = 'ai_mixing_sessions';

  bool _enabled = false;
  Map<String, dynamic>? _session;
  File? _sessionFile;
  int _eventCounter = 0;

  bool get isEnabled => _enabled;
  bool get hasActiveSession => _session != null;
  String? get activeSessionId => _session?['session_id']?.toString();

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled && _session != null) {
      await closeSession(reason: 'disabled');
    }
  }

  Future<void> recordAiStep({
    required String prompt,
    required Map<String, dynamic> preSnapshot,
    required Map<String, dynamic> postSnapshot,
    required List<Map<String, dynamic>> resolvedActions,
    Map<String, dynamic>? llmPayload,
  }) async {
    if (!_enabled) return;

    await _ensureSession();

    _appendEvent({
      'type': 'ai_step',
      'prompt': prompt,
      'llm_payload': llmPayload,
      'resolved_actions': resolvedActions,
      'pre_snapshot': preSnapshot,
      'post_snapshot': postSnapshot,
    });

    await _flush();
  }

  Future<void> recordManualEdit({
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    if (!_enabled) return;

    await _ensureSession();

    _appendEvent({
      'type': 'manual_edit',
      'kind': kind,
      'payload': payload,
    });

    await _flush();
  }

  Future<void> setQualityRating(double rating0To5) async {
    if (!_enabled || _session == null) return;
    _session!['quality_rating_0_to_5'] = rating0To5.clamp(0.0, 5.0);
    await _flush();
  }

  Future<File?> exportActiveSession() async {
    if (_session == null || _sessionFile == null) return null;
    await _flush();
    return _sessionFile;
  }

  Future<void> closeSession({String reason = 'completed'}) async {
    if (_session == null) return;

    _session!['ended_at'] = DateTime.now().toUtc().toIso8601String();
    _session!['close_reason'] = reason;

    await _flush();

    _session = null;
    _sessionFile = null;
    _eventCounter = 0;
  }

  Future<List<File>> listSessionFiles() async {
    final dir = await _rootDir();
    if (!await dir.exists()) return const [];

    final files = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File && e.path.endsWith('.json')) {
        files.add(e);
      }
    }

    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> _ensureSession() async {
    if (_session != null && _sessionFile != null) return;

    final now = DateTime.now().toUtc();
    final stamp = now.toIso8601String().replaceAll(':', '-');
    final sessionId = 'session_$stamp';

    final dir = await _rootDir();
    await dir.create(recursive: true);

    final file = File(p.join(dir.path, '$sessionId.json'));

    _session = {
      'schema_version': 1,
      'session_id': sessionId,
      'started_at': now.toIso8601String(),
      'events': <Map<String, dynamic>>[],
    };
    _sessionFile = file;
    _eventCounter = 0;

    await _flush();
  }

  void _appendEvent(Map<String, dynamic> event) {
    final events = (_session!['events'] as List).cast<Map<String, dynamic>>();
    events.add({
      'index': _eventCounter++,
      'at': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
  }

  Future<void> _flush() async {
    if (_session == null || _sessionFile == null) return;

    await _sessionFile!.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _sessionFile!.writeAsString(encoder.convert(_session), flush: true);
  }

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, _dirName));
  }
}
