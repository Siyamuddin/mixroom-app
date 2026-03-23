import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProducerDataCollector {
  static const String _dirName = 'producer_sessions';

  bool _enabled = false;
  Map<String, dynamic>? _session;
  File? _sessionFile;
  int _cycleCounter = 0;
  String? _projectId;
  String? _projectName;
  Directory? _projectDir;
  int? _pendingPromptCycleIndex;

  bool get isEnabled => _enabled;
  bool get hasActiveSession => _session != null;
  String? get activeSessionId => _session?['session_id']?.toString();
  bool get hasPendingPromptCycle => _pendingPromptCycleIndex != null;

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
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    if (!_enabled) return;

    _applyProjectContext(
      projectId: projectId,
      projectName: projectName,
      projectDir: projectDir,
    );
    await _ensureSession();

    if (_pendingPromptCycleIndex != null) {
      _finalizePendingPromptCycle(
        finalSnapshot: preSnapshot,
        disposition: 'next_ai_step',
      );
    }

    final cycles = _promptCycles();
    final cycleIndex = _cycleCounter++;
    final cycleId =
        '${activeSessionId ?? 'session'}_cycle_${cycleIndex.toString().padLeft(4, '0')}';
    cycles.add({
      'cycle_id': cycleId,
      'cycle_index': cycleIndex,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'awaiting_final',
      'prompt': prompt,
      'llm_payload': llmPayload,
      'resolved_ai_actions': resolvedActions,
      'before_prompt_snapshot': preSnapshot,
      'ai_after_snapshot': postSnapshot,
      'manual_edits_debug': <Map<String, dynamic>>[],
    });
    _pendingPromptCycleIndex = cycles.length - 1;

    await _flush();
  }

  Future<void> recordManualEdit({
    required String kind,
    required Map<String, dynamic> payload,
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    if (!_enabled) return;
    if (_pendingPromptCycleIndex == null && _session == null) return;

    _applyProjectContext(
      projectId: projectId,
      projectName: projectName,
      projectDir: projectDir,
    );
    await _ensureSession();

    final cycle = _pendingPromptCycle();
    if (cycle == null) return;
    final edits =
        (cycle['manual_edits_debug'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
    edits.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'kind': kind,
      'payload': payload,
    });
    cycle['manual_edits_debug'] = edits;

    await _flush();
  }

  Future<void> setQualityRating(double rating0To5) async {
    if (!_enabled || _session == null) return;
    final clamped = rating0To5.clamp(0.0, 5.0);
    final cycle = _pendingPromptCycle();
    if (cycle != null) {
      cycle['quality_rating_0_to_5'] = clamped;
    } else {
      _session!['quality_rating_0_to_5'] = clamped;
    }
    await _flush();
  }

  Future<void> recordPromptCycleStop({
    required Map<String, dynamic> finalSnapshot,
    String disposition = 'manual_mark',
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    if (!_enabled) return;
    if (_pendingPromptCycleIndex == null) return;

    _applyProjectContext(
      projectId: projectId,
      projectName: projectName,
      projectDir: projectDir,
    );
    await _ensureSession();

    _finalizePendingPromptCycle(
      finalSnapshot: finalSnapshot,
      disposition: disposition,
    );

    await _flush();
  }

  Future<File?> exportActiveSession({Directory? projectDir}) async {
    if (projectDir != null) {
      _applyProjectContext(projectDir: projectDir);
    }
    if (_session == null || _sessionFile == null) return null;
    await _flush();

    final exportDir = await _rootDir();
    final currentDirPath = p.normalize(_sessionFile!.parent.path);
    final exportDirPath = p.normalize(exportDir.path);
    if (currentDirPath != exportDirPath) {
      await exportDir.create(recursive: true);
      final migrated =
          File(p.join(exportDir.path, p.basename(_sessionFile!.path)));
      await migrated.writeAsBytes(await _sessionFile!.readAsBytes(),
          flush: true);
      _sessionFile = migrated;
      await _flush();
    }
    return _sessionFile;
  }

  Future<void> closeSession({String reason = 'completed'}) async {
    if (_session == null) return;
    if (_pendingPromptCycleIndex != null) {
      final cycle = _pendingPromptCycle();
      if (cycle != null) {
        cycle['status'] = 'incomplete';
        cycle['disposition'] = reason;
      }
    }

    _session!['ended_at'] = DateTime.now().toUtc().toIso8601String();
    _session!['close_reason'] = reason;

    await _flush();

    _session = null;
    _sessionFile = null;
    _cycleCounter = 0;
    _pendingPromptCycleIndex = null;
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
      'schema_version': 3,
      'session_id': sessionId,
      'started_at': now.toIso8601String(),
      if ((_projectId ?? '').trim().isNotEmpty) 'project_id': _projectId,
      if ((_projectName ?? '').trim().isNotEmpty) 'project_name': _projectName,
      'prompt_cycles': <Map<String, dynamic>>[],
    };
    _sessionFile = file;
    _cycleCounter = 0;

    await _flush();
  }

  void _applyProjectContext({
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) {
    final nextProjectId = projectId?.trim();
    if (nextProjectId != null && nextProjectId.isNotEmpty) {
      _projectId = nextProjectId;
    }

    final nextProjectName = projectName?.trim();
    if (nextProjectName != null && nextProjectName.isNotEmpty) {
      _projectName = nextProjectName;
    }

    if (projectDir != null) {
      _projectDir = projectDir;
    }

    if (_session != null) {
      if ((_projectId ?? '').trim().isNotEmpty) {
        _session!['project_id'] = _projectId;
      }
      if ((_projectName ?? '').trim().isNotEmpty) {
        _session!['project_name'] = _projectName;
      }
    }
  }

  List<Map<String, dynamic>> _promptCycles() {
    final existing = _session!['prompt_cycles'];
    if (existing is List) {
      return existing.cast<Map<String, dynamic>>();
    }
    final created = <Map<String, dynamic>>[];
    _session!['prompt_cycles'] = created;
    return created;
  }

  Map<String, dynamic>? _pendingPromptCycle() {
    final index = _pendingPromptCycleIndex;
    if (index == null) return null;
    final cycles = _promptCycles();
    if (index < 0 || index >= cycles.length) return null;
    return cycles[index];
  }

  void _finalizePendingPromptCycle({
    required Map<String, dynamic> finalSnapshot,
    required String disposition,
  }) {
    final cycle = _pendingPromptCycle();
    if (cycle == null) return;
    cycle['producer_final_snapshot'] = finalSnapshot;
    cycle['final_captured_at'] = DateTime.now().toUtc().toIso8601String();
    cycle['disposition'] = disposition;
    cycle['status'] = 'complete';
    _pendingPromptCycleIndex = null;
  }

  Future<void> _flush() async {
    if (_session == null || _sessionFile == null) return;

    await _sessionFile!.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _sessionFile!.writeAsString(encoder.convert(_session), flush: true);
  }

  Future<Directory> _rootDir() async {
    if (_projectDir != null) {
      return Directory(
        p.join(_projectDir!.path, 'exports', _dirName),
      );
    }
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, _dirName));
  }
}
