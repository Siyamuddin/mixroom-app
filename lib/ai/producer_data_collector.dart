import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'producer_control_changes.dart';

typedef ProducerSnapshotProvider = Future<Map<String, dynamic>> Function();

enum ProducerCaptureUploadState {
  idle,
  recording,
  pending,
  uploading,
  uploaded,
  retryNeeded,
}

/// Observation-only producer training capture.
///
/// Schema v4 keeps an append-only event journal as the source of truth and a
/// materialized episode view for training. Capture errors must never interrupt
/// editing, saving, playback, or AI execution.
class ProducerDataCollector {
  ProducerDataCollector({
    ProducerSnapshotProvider? snapshotProvider,
    String? Function()? ownerIdProvider,
    Duration episodeIdleTimeout = const Duration(seconds: 15),
    void Function(ProducerCaptureUploadState state)? onUploadStateChanged,
  }) : _snapshotProvider = snapshotProvider,
       _ownerIdProvider = ownerIdProvider,
       _episodeIdleTimeout = episodeIdleTimeout,
       _onUploadStateChanged = onUploadStateChanged;

  static const String directoryName = 'producer_sessions';
  static const String schemaVersion = 'producer_training_capture_v4';
  static const String consentVersion = 'producer_training_2026_08_v1';
  static const String segmentationVersion = 'natural_action_burst_v2';
  static const String featureExtractorVersion = 'state_audio_proxy_v1';
  static const int maximumAudioPairsPerSession = 20;
  static const int maximumReviewEpisodes = 3;

  final ProducerSnapshotProvider? _snapshotProvider;
  final String? Function()? _ownerIdProvider;

  static String ownerRef(String userId) =>
      sha256.convert(utf8.encode(userId)).toString();
  final Duration _episodeIdleTimeout;
  final void Function(ProducerCaptureUploadState state)? _onUploadStateChanged;

  bool _enabled = false;
  Map<String, dynamic>? _session;
  File? _sessionFile;
  File? _journalFile;
  Map<String, dynamic>? _checkpoint;
  Map<String, dynamic>? _activeEpisode;
  Timer? _episodeTimer;
  int _episodeCounter = 0;
  String? _projectId;
  Directory? _projectDir;
  String _sessionSalt = '';
  final List<Map<String, dynamic>> _inferenceTraces = [];
  int _traceGeneration = 0;
  String lastPrompt = '';
  final Map<String, String> _historyEpisodes = {};
  String get inferenceCaptureToken =>
      '${activeSessionId ?? ''}:$_traceGeneration';
  Future<void> _ioTail = Future<void>.value();
  Future<void> _operations = Future<void>.value();
  final Object _operationZone = Object();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    if (Zone.current[_operationZone] == true) return operation();
    final result = _operations.then(
      (_) => runZoned(operation, zoneValues: {_operationZone: true}),
    );
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void recordInferenceTrace(Map<String, dynamic> trace) {
    if (!_enabled) return;
    final safe = _sanitizeMap(trace);
    final identities = trace['row_identities'];
    if (identities is Map) {
      safe['row_identities'] = {
        for (final entry in identities.entries)
          entry.key.toString(): _stableTrackRef(entry.value),
      };
    }
    _inferenceTraces.add(safe);
  }

  void clearInferenceTraces() => _inferenceTraces.clear();

  Future<void> _write(Future<void> Function() operation) {
    final next = _ioTail.then((_) => operation());
    _ioTail = next.catchError((Object _) {});
    return next;
  }

  ProducerCaptureUploadState _uploadState = ProducerCaptureUploadState.idle;

  bool get isEnabled => _enabled;
  bool get hasActiveSession => _session != null;
  String? get activeSessionId => _session?['session_id']?.toString();
  bool get hasPendingPromptCycle => _activeEpisode != null;
  ProducerCaptureUploadState get uploadState => _uploadState;
  File? get activeSessionFile => _sessionFile;

  void configureProject({String? projectId, Directory? projectDir}) {
    _applyProjectContext(projectId: projectId, projectDir: projectDir);
  }

  Future<void> setEnabled(bool enabled) async {
    return _serialize(() async {
      _enabled = enabled;
      if (!enabled && _session != null) {
        await closeSession(reason: 'disabled');
      }
    });
  }

  Future<void> beginSession({
    required Map<String, dynamic> initialSnapshot,
    String? projectId,
    Directory? projectDir,
  }) async {
    return _serialize(() async {
      if (!_enabled) return;
      _applyProjectContext(projectId: projectId, projectDir: projectDir);
      await _ensureSession();
      _checkpoint = _sanitizeSnapshot(initialSnapshot);
      _session!['initial_state'] = _checkpoint;
      await _appendEvent('session_started', {'checkpoint': _checkpoint});
      await _flush();
    });
  }

  Future<void> recordAiStep({
    required String prompt,
    required Map<String, dynamic> preSnapshot,
    required Map<String, dynamic> postSnapshot,
    required List<Map<String, dynamic>> resolvedActions,
    Map<String, dynamic>? llmPayload,
    String? undoTransactionId,
    String? captureWarning,
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    return _serialize(() async {
      if (!_enabled) return;
      _applyProjectContext(projectId: projectId, projectDir: projectDir);
      await _ensureSession();
      await finalizeActiveEpisode(
        finalSnapshot: preSnapshot,
        disposition: 'new_ai_prompt',
      );

      final before = _sanitizeSnapshot(preSnapshot);
      final after = _sanitizeSnapshot(postSnapshot);
      final actions = resolvedActions.map(_sanitizeMap).toList();
      _activeEpisode = _newEpisode(
        stateBefore: before,
        requestOrContext: {
          'source': 'ai_prompt',
          'prompt': prompt.trim(),
          if (llmPayload != null) 'ai_metadata': _sanitizeMap(llmPayload),
        },
      );
      if (captureWarning != null)
        _activeEpisode!['capture_warning'] = _safeToken(captureWarning);
      _activeEpisode!['inference_traces'] = List<Map<String, dynamic>>.from(
        _inferenceTraces,
      );
      _inferenceTraces.clear();
      if (undoTransactionId != null) {
        _historyEpisodes[undoTransactionId] = _activeEpisode!['episode_id']
            .toString();
      }
      _activeEpisode!['actions_raw'] = actions;
      _activeEpisode!['actions_relational'] = actions
          .map(_relationalAction)
          .toList();
      _activeEpisode!['state_after'] = after;
      _inferLabels(_activeEpisode!);
      _attachDiagnostics(_activeEpisode!, before: before, after: after);
      _checkpoint = after;
      await _appendEvent('ai_step', {
        'episode_id': _activeEpisode!['episode_id'],
        'prompt': prompt.trim(),
        'actions': actions,
      });
      _armEpisodeTimer();
      await _flush();
    });
  }

  Future<void> recordAiRequest({
    required String prompt,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) async {
    return _serialize(() async {
      if (!_enabled) return;
      await _ensureSession();
      _inferenceTraces.clear();
      lastPrompt = prompt.trim();
      _traceGeneration++;
      await _appendEvent('ai_request', <String, dynamic>{
        'prompt': prompt.trim(),
        if (context.isNotEmpty) 'context': _sanitizeMap(context),
      });
    });
  }

  Future<void> recordManualEdit({
    required String kind,
    required Map<String, dynamic> payload,
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    return _serialize(() async {
      if (!_enabled) return;
      _applyProjectContext(projectId: projectId, projectDir: projectDir);
      await _ensureSession();
      if (_activeEpisode == null) {
        final latest = _latestEpisode();
        if (latest != null &&
            latest['disposition'] == 'idle_timeout' &&
            (latest['request_or_context'] as Map?)?['source'] == 'ai_prompt') {
          _activeEpisode = latest;
          latest['status'] = 'active';
          latest.remove('ended_at');
        }
      }
      _activeEpisode ??= _newEpisode(
        stateBefore: _checkpoint ?? const {},
        requestOrContext: const {'source': 'manual_work'},
      );

      final historyId = payload['undo_transaction_id']?.toString();
      if (historyId != null)
        _historyEpisodes[historyId] = _activeEpisode!['episode_id'].toString();
      final action = <String, dynamic>{
        'at': DateTime.now().toUtc().toIso8601String(),
        'kind': _safeToken(kind),
        'payload': _sanitizeMap(payload),
      };
      final actions = (_activeEpisode!['actions_raw'] as List)
          .cast<Map<String, dynamic>>();
      final key = _coalesceKey(action);
      final existing = actions.lastIndexWhere(
        (candidate) => _coalesceKey(candidate) == key,
      );
      if (existing >= 0 && _isContinuousMutation(kind)) {
        final first = actions[existing];
        action['payload'] = _coalescePayload(
          (first['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
          (action['payload'] as Map).cast<String, dynamic>(),
        );
        actions[existing] = action;
      } else {
        actions.add(action);
      }
      _activeEpisode!['actions_relational'] = actions
          .map(_relationalAction)
          .toList();
      _inferLabels(_activeEpisode!);
      await _appendEvent('mix_mutation', {
        'episode_id': _activeEpisode!['episode_id'],
        'action': action,
      });
      _armEpisodeTimer();
      await _flush();
    });
  }

  Future<void> recordUndoRedo({
    required bool isUndo,
    String description = '',
    String? undoTransactionId,
  }) async {
    return _serialize(() async {
      if (!_enabled) return;
      await _ensureSession();
      final mappedId = _historyEpisodes[undoTransactionId];
      final matching = _episodes().where((e) => e['episode_id'] == mappedId);
      final episode = undoTransactionId == null
          ? (_activeEpisode ?? _latestEpisode())
          : (matching.isEmpty ? null : matching.first);
      if (episode != null) {
        final outcome = (episode['outcome_signals'] as Map)
            .cast<String, dynamic>();
        outcome['undo_redo_observed'] = true;
        outcome['last_history_operation'] = isUndo ? 'undo' : 'redo';
        // A history operation may affect only part of an episode. Never infer
        // rejection or acceptance without an action-level transaction mapping.
        outcome['rejected_by_undo'] = false;
        outcome['restored_by_redo'] = !isUndo;
        if (episode['status'] == 'rejected') episode['status'] = 'complete';
        episode['producer_outcome'] = 'not_evaluated';
      }
      try {
        final snapshot = await _snapshotProvider?.call();
        if (snapshot != null) {
          _checkpoint = _sanitizeSnapshot(snapshot);
          if (episode != null) episode['state_after'] = _checkpoint;
        }
      } catch (_) {
        if (episode != null)
          episode['capture_warning'] = 'history_snapshot_unavailable';
      }
      await _appendEvent(isUndo ? 'undo' : 'redo', {
        if (description.trim().isNotEmpty) 'description': description.trim(),
        if (episode != null) 'episode_id': episode['episode_id'],
      });
      await _flush();
    });
  }

  Future<void> recordPlaybackContext(Map<String, dynamic> context) async {
    return _serialize(() async {
      if (!_enabled) return;
      await _ensureSession();
      final safe = _sanitizeMap(context);
      _session!['latest_playback_context'] = safe;
      if (safe['event'] == 'play') {
        final latest = _latestEpisode();
        if (latest != null && latest['status'] == 'complete') {
          final outcome = (latest['outcome_signals'] as Map)
              .cast<String, dynamic>();
          outcome['survived_next_playback'] = true;
          outcome['playback_at'] = DateTime.now().toUtc().toIso8601String();
        }
      }
      await _appendEvent('playback_context', safe);
      await _flush();
    });
  }

  Future<void> finalizeActiveEpisode({
    Map<String, dynamic>? finalSnapshot,
    String disposition = 'idle_timeout',
  }) async {
    return _serialize(() async {
      _episodeTimer?.cancel();
      _episodeTimer = null;
      if (_session == null) return;
      Map<String, dynamic> after;
      var unavailable = false;
      try {
        final source = finalSnapshot ?? await _snapshotProvider?.call();
        after = source == null
            ? (_checkpoint ?? const {})
            : _sanitizeSnapshot(source);
        unavailable = source == null;
      } catch (_) {
        after = _checkpoint ?? const {};
        unavailable = true;
      }
      var episode = _activeEpisode;
      // Native plugin windows can change parameters without a Flutter gesture.
      // Reconcile controls at boundaries so those sessions/corrections survive.
      // This is an observed state transition, not a fabricated gesture history.
      if (episode == null &&
          !unavailable &&
          _checkpoint != null &&
          producerControlChanges(_checkpoint!, after).isNotEmpty) {
        final latest = _latestEpisode();
        if (latest != null &&
            latest['disposition'] == 'idle_timeout' &&
            (latest['request_or_context'] as Map?)?['source'] == 'ai_prompt') {
          episode = latest;
          episode.remove('producer_outcome');
          episode['provenance'] = {'label': 'unknown', 'confidence': 0.0};
        } else {
          episode = _newEpisode(
            stateBefore: _checkpoint!,
            requestOrContext: const {'source': 'observed_plugin_or_mix_change'},
          );
        }
        (episode['actions_raw'] as List).add({
          'kind': 'observed_state_change',
          'payload': {'source': 'snapshot_reconciliation'},
        });
        await _appendEvent('observed_state_change', {
          'episode_id': episode['episode_id'],
          'state_before': _checkpoint,
          'state_after': after,
        });
      }
      if (episode == null) return;
      if (unavailable)
        episode['capture_warning'] = 'final_snapshot_unavailable';
      episode['state_after'] = after;
      episode['control_changes'] = producerControlChanges(
        (episode['state_before'] as Map).cast<String, dynamic>(),
        after,
      );
      episode['ended_at'] = DateTime.now().toUtc().toIso8601String();
      episode['disposition'] = disposition;
      episode['status'] = episode['status'] == 'rejected'
          ? 'rejected'
          : 'complete';
      final raw = ((episode['actions_raw'] as List?) ?? const [])
          .whereType<Map>();
      episode['actions_relational'] = raw
          .map((value) => _relationalAction(value.cast<String, dynamic>()))
          .toList();
      _inferLabels(episode);
      _attachDiagnostics(
        episode,
        before: (episode['state_before'] as Map).cast<String, dynamic>(),
        after: after,
      );
      _checkpoint = after;
      _activeEpisode = null;
      await _appendEvent('episode_closed', {
        'episode_id': episode['episode_id'],
        'disposition': disposition,
        'status': episode['status'],
      });
      await _flush();
    });
  }

  Future<void> recordPromptCycleStop({
    required Map<String, dynamic> finalSnapshot,
    String disposition = 'manual_mark',
    String? projectId,
    String? projectName,
    Directory? projectDir,
  }) async {
    return _serialize(() async {
      _applyProjectContext(projectId: projectId, projectDir: projectDir);
      await finalizeActiveEpisode(
        finalSnapshot: finalSnapshot,
        disposition: disposition,
      );
    });
  }

  Future<void> setQualityRating(double rating0To5) async {
    return _serialize(() async {
      if (!_enabled || _session == null) return;
      final target = _activeEpisode ?? _latestEpisode();
      if (target != null) {
        target['quality_rating_0_to_5'] = rating0To5.clamp(0.0, 5.0);
      }
      await _flush();
    });
  }

  List<Map<String, dynamic>> reviewCandidates({
    int limit = maximumReviewEpisodes,
  }) {
    final episodes = List<Map<String, dynamic>>.from(_episodes())
      ..removeWhere((episode) => episode['status'] == 'rejected')
      ..sort((a, b) {
        final ac =
            ((a['provenance'] as Map?)?['confidence'] as num?)?.toDouble() ?? 0;
        final bc =
            ((b['provenance'] as Map?)?['confidence'] as num?)?.toDouble() ?? 0;
        return ac.compareTo(bc);
      });
    final diagnoses = <String>{};
    final selected = <Map<String, dynamic>>[];
    for (final episode in episodes) {
      final diagnosis = episode['diagnosis']?.toString() ?? 'other';
      if (diagnoses.add(diagnosis) || selected.length + 1 >= limit) {
        selected.add(episode);
      }
      if (selected.length >= limit) break;
    }
    return selected;
  }

  Future<void> applyProducerLabel({
    required String episodeId,
    required List<String> diagnoses,
    required List<String> strategies,
    String outcome = 'not_evaluated',
    String notes = '',
  }) async {
    return _serialize(() async {
      Map<String, dynamic>? episode;
      for (final candidate in _episodes()) {
        if (candidate['episode_id'] == episodeId) episode = candidate;
      }
      if (episode == null) return;
      final selectedDiagnoses = diagnoses.map(_safeToken).toSet().toList();
      episode['diagnoses'] = List<String>.from(selectedDiagnoses)..sort();
      episode['diagnosis'] = selectedDiagnoses.isEmpty
          ? 'other'
          : selectedDiagnoses.first;
      episode['strategies'] = strategies.map(_safeToken).toSet().toList()
        ..sort();
      const outcomes = {
        'accepted',
        'rejected',
        'partial',
        'experimenting',
        'not_evaluated',
      };
      if (!outcomes.contains(outcome))
        throw ArgumentError.value(outcome, 'outcome');
      episode['producer_outcome'] = outcome;
      episode['producer_notes'] = _sanitizeText(
        notes.trim().substring(0, notes.trim().length.clamp(0, 2000)),
      );
      episode['provenance'] = {'label': 'producer', 'confidence': 1.0};
      await _appendEvent('producer_label', {
        'episode_id': episodeId,
        'diagnosis': episode['diagnosis'],
        'diagnoses': episode['diagnoses'],
        'strategies': episode['strategies'],
        'outcome': episode['producer_outcome'],
        'notes': episode['producer_notes'],
      });
      await _flush();
    });
  }

  Future<File?> exportActiveSession({Directory? projectDir}) async {
    return _serialize(() async {
      if (projectDir != null) _applyProjectContext(projectDir: projectDir);
      if (_session == null || _sessionFile == null) return null;
      await _flush();
      return _sessionFile;
    });
  }

  Future<File?> closeSession({String reason = 'completed'}) async {
    return _serialize(() async {
      if (_session == null) return null;
      _enabled = false;
      _traceGeneration++;
      await finalizeActiveEpisode(disposition: reason);
      _session!['ended_at'] = DateTime.now().toUtc().toIso8601String();
      _session!['close_reason'] = reason;
      _session!['upload'] = {
        'status': 'pending',
        'attempts': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _appendEvent('session_closed', {'reason': reason});
      await _embedEventJournal();
      await _flush();
      final closed = _sessionFile;
      _setUploadState(ProducerCaptureUploadState.pending);
      _session = null;
      _sessionFile = null;
      _journalFile = null;
      _checkpoint = null;
      _activeEpisode = null;
      _episodeCounter = 0;
      _historyEpisodes.clear();
      return closed;
    });
  }

  Future<List<File>> listSessionFiles() async {
    return _serialize(() async {
      final roots = <Directory>[await _applicationRootDir()];
      if (_projectDir != null) roots.insert(0, await _rootDir());
      final files = <String, File>{};
      for (final dir in roots) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.json')) {
            files[p.normalize(entity.path)] = entity;
          }
        }
      }
      final result = files.values.toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return result;
    });
  }

  Future<List<File>> listPendingUploadFiles() async {
    return _serialize(() async {
      final pending = <File>[];
      for (final file in await listSessionFiles()) {
        try {
          final document = jsonDecode(await file.readAsString()) as Map;
          var status = ((document['upload'] as Map?)?['status'] ?? '')
              .toString();
          if (status == 'recording' && file.path != _sessionFile?.path) {
            document['close_reason'] = 'interrupted_recovery';
            document['ended_at'] = DateTime.now().toUtc().toIso8601String();
            for (final episode
                in (document['episodes'] as List? ?? const [])
                    .whereType<Map>()) {
              if (episode['status'] == 'active') {
                episode['status'] = 'interrupted';
                episode['capture_warning'] =
                    'interrupted_before_final_snapshot';
              }
            }
            document['upload'] = {'status': 'pending', 'attempts': 0};
            await _writeDocument(file, document);
            status = 'pending';
          }
          if (status == 'pending' ||
              status == 'retry_needed' ||
              status == 'uploading')
            pending.add(file);
        } catch (_) {}
      }
      return pending;
    });
  }

  Future<void> updateUploadStatus(
    File file,
    String status, {
    String? error,
  }) async {
    return _serialize(() async {
      try {
        final document = (jsonDecode(await file.readAsString()) as Map)
            .cast<String, dynamic>();
        final previous = ((document['upload'] as Map?) ?? const {})
            .cast<String, dynamic>();
        document['upload'] = {
          ...previous,
          'status': status,
          'attempts':
              ((previous['attempts'] as num?)?.toInt() ?? 0) +
              (status == 'uploading' ? 1 : 0),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          if (error != null && error.isNotEmpty)
            'last_error': _sanitizeText(error),
        };
        await _writeDocument(file, document);
        _setUploadState(switch (status) {
          'uploading' => ProducerCaptureUploadState.uploading,
          'uploaded' => ProducerCaptureUploadState.uploaded,
          'retry_needed' => ProducerCaptureUploadState.retryNeeded,
          _ => ProducerCaptureUploadState.pending,
        });
      } catch (_) {}
    });
  }

  Future<void> _ensureSession() async {
    if (_session != null && _sessionFile != null) return;
    final now = DateTime.now().toUtc();
    final sessionId =
        'session_${now.toIso8601String().replaceAll(':', '-')}_${now.microsecondsSinceEpoch}';
    _sessionSalt = sha256
        .convert(utf8.encode('$sessionId:${now.microsecondsSinceEpoch}'))
        .toString();
    final dir = await _rootDir();
    await dir.create(recursive: true);
    _sessionFile = File(p.join(dir.path, '$sessionId.json'));
    _journalFile = File(p.join(dir.path, '$sessionId.events.ndjson'));
    _session = {
      'schema_version': schemaVersion,
      if ((_ownerIdProvider?.call() ?? '').isNotEmpty)
        'local_owner_ref': ownerRef(_ownerIdProvider!.call()!),
      'session_id': sessionId,
      'started_at': now.toIso8601String(),
      'consent_version': consentVersion,
      'segmentation_version': segmentationVersion,
      'feature_extractor_version': featureExtractorVersion,
      'audio_retention_days': 90,
      'media_policy': {
        'full_stems_uploaded': false,
        'short_render_seconds': 12,
        'maximum_pairs': maximumAudioPairsPerSession,
      },
      if ((_projectId ?? '').isNotEmpty)
        'project_ref': _projectGroup(_projectId!),
      'event_journal_file': p.basename(_journalFile!.path),
      'episodes': <Map<String, dynamic>>[],
      'media_manifest': <Map<String, dynamic>>[],
      'upload': {'status': 'recording', 'attempts': 0},
    };
    _setUploadState(ProducerCaptureUploadState.recording);
    await _flush();
  }

  Map<String, dynamic> _newEpisode({
    required Map<String, dynamic> stateBefore,
    required Map<String, dynamic> requestOrContext,
  }) {
    final index = _episodeCounter++;
    final episode = <String, dynamic>{
      'episode_id':
          '${activeSessionId}_episode_${index.toString().padLeft(4, '0')}',
      'episode_index': index,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'active',
      'state_before': stateBefore,
      'request_or_context': {
        ...requestOrContext,
        if (_session?['latest_playback_context'] != null)
          'playback': _session!['latest_playback_context'],
      },
      'diagnosis': 'other',
      'diagnoses': <String>['other'],
      'strategies': <String>[],
      'actions_raw': <Map<String, dynamic>>[],
      'actions_relational': <Map<String, dynamic>>[],
      'state_after': <String, dynamic>{},
      'audio_features_before': <String, dynamic>{},
      'audio_features_after': <String, dynamic>{},
      'audio_feature_delta': <String, dynamic>{},
      'audio_target': {
        'status': 'not_rendered',
        'reason': 'shadow_feature_phase',
      },
      'outcome_signals': <String, dynamic>{
        'rejected_by_undo': false,
        'restored_by_redo': false,
        'survived_next_playback': false,
      },
      'provenance': {'label': 'unknown', 'confidence': 0.0},
    };
    _episodes().add(episode);
    return episode;
  }

  void _attachDiagnostics(
    Map<String, dynamic> episode, {
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    final beforeFeatures = _aggregateAudioFeatures(before);
    final afterFeatures = _aggregateAudioFeatures(after);
    episode['audio_features_before'] = beforeFeatures;
    episode['audio_features_after'] = afterFeatures;
    episode['audio_feature_delta'] = _numericDelta(
      beforeFeatures,
      afterFeatures,
    );
    episode['masking_matrix_before'] = _maskingMatrix(before);
    episode['masking_matrix_after'] = _maskingMatrix(after);
  }

  void _inferLabels(Map<String, dynamic> episode) {
    if ((episode['provenance'] as Map?)?['label'] == 'producer') return;
    final kinds = ((episode['actions_raw'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (action) =>
              (action['kind'] ?? action['type'] ?? '').toString().toLowerCase(),
        )
        .join(' ');
    var diagnosis = 'other';
    final strategies = <String>{};
    if (kinds.contains('gain') || kinds.contains('volume')) {
      diagnosis = 'level_balance';
      strategies.add('target_level_change');
    }
    if (kinds.contains('eq') ||
        kinds.contains('filter') ||
        kinds.contains('tone')) {
      diagnosis = kinds.contains('mask') ? 'masking' : 'tone';
      strategies.add(
        kinds.contains('mask')
            ? 'competing_track_spectral_carve'
            : 'source_tone_change',
      );
    }
    if (kinds.contains('compress') ||
        kinds.contains('limit') ||
        kinds.contains('dynamics')) {
      diagnosis = 'dynamics';
      strategies.add('dynamics_control');
    }
    if (kinds.contains('reverb') ||
        kinds.contains('delay') ||
        kinds.contains('space')) {
      diagnosis = 'space_depth';
      strategies.add('ambience_change');
    }
    if (kinds.contains('pan') ||
        kinds.contains('stereo') ||
        kinds.contains('width')) {
      diagnosis = 'stereo_image';
      strategies.add('spatial_separation');
    }
    if (kinds.contains('master') || kinds.contains('group_bus')) {
      strategies.add('bus_processing');
    }
    episode['diagnosis'] = diagnosis;
    episode['diagnoses'] = <String>[diagnosis];
    episode['strategies'] = strategies.isEmpty
        ? <String>['other']
        : (strategies.toList()..sort());
    episode['provenance'] = {
      'label': strategies.isEmpty ? 'unknown' : 'inferred',
      'confidence': strategies.isEmpty
          ? 0.0
          : (strategies.length == 1 ? 0.55 : 0.4),
    };
  }

  Map<String, dynamic> _relationalAction(Map<String, dynamic> action) {
    final payload = ((action['payload'] as Map?) ?? action)
        .cast<String, dynamic>();
    final oldValue = _firstNumeric(payload, const [
      'old_gain',
      'old_pan',
      'old_value',
    ]);
    final newValue = _firstNumeric(payload, const [
      'new_gain',
      'new_pan',
      'new_value',
      'value',
    ]);
    final kind = _safeToken(
      (action['kind'] ?? action['type'] ?? 'unknown').toString(),
    );
    return {
      'kind': kind,
      'scope': payload.containsKey('group_id')
          ? 'group'
          : payload.containsKey('row')
          ? 'track_role'
          : kind.contains('master')
          ? 'master'
          : 'project',
      if (payload['row'] != null)
        'target_track': _stableTrackRef(payload['row']),
      if (payload['role'] != null)
        'target_role': _safeToken(payload['role'].toString()),
      if (payload['param_id'] != null)
        'parameter': _safeToken(payload['param_id'].toString()),
      if (oldValue != null) 'before': oldValue,
      if (newValue != null) 'after': newValue,
      if (oldValue != null && newValue != null) 'delta': newValue - oldValue,
    };
  }

  Map<String, dynamic> _sanitizeSnapshot(Map<String, dynamic> snapshot) =>
      _sanitizeMap(snapshot, snapshotMode: true);

  Map<String, dynamic> _sanitizeMap(Map value, {bool snapshotMode = false}) {
    final out = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key.toLowerCase();
      if (_redactedKeys.contains(normalized) ||
          normalized.contains('file_name') ||
          normalized.contains('filepath')) {
        continue;
      }
      var next = _sanitizeValue(
        entry.value,
        key: key,
        snapshotMode: snapshotMode,
      );
      if (snapshotMode &&
          (normalized == 'row_id' ||
              normalized == 'rowindex' ||
              normalized == 'row_index')) {
        next = _stableTrackRef(next);
      }
      out[key] = next;
      if (snapshotMode && normalized == 'row') {
        out['track_ref'] = _stableTrackRef(next);
      }
    }
    return out;
  }

  Object? _sanitizeValue(
    Object? value, {
    required String key,
    required bool snapshotMode,
  }) {
    if (value is Map) return _sanitizeMap(value, snapshotMode: snapshotMode);
    if (value is Iterable) {
      return value
          .map(
            (item) =>
                _sanitizeValue(item, key: key, snapshotMode: snapshotMode),
          )
          .toList();
    }
    if (value is String &&
        key.toLowerCase() == 'effectid' &&
        _sanitizeText(value) != value) {
      return 'plugin_${sha256.convert(utf8.encode(value))}';
    }
    if (value is String) return _sanitizeText(value, key: key);
    return value;
  }

  Map<String, dynamic> _aggregateAudioFeatures(Map<String, dynamic> snapshot) {
    final rows = _rows(snapshot);
    final stats = <String, List<double>>{};
    for (final row in rows) {
      final audio = ((row['audio_stats'] as Map?) ?? const {})
          .cast<String, dynamic>();
      for (final entry in audio.entries) {
        if (entry.value is num) {
          stats
              .putIfAbsent(entry.key, () => [])
              .add((entry.value as num).toDouble());
        }
      }
    }
    return {
      'source': 'state_proxy',
      'analyzed_track_count': rows.length,
      for (final entry in stats.entries)
        if (entry.value.isNotEmpty)
          entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
    };
  }

  List<Map<String, dynamic>> _maskingMatrix(Map<String, dynamic> snapshot) {
    final rows = _rows(snapshot);
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      for (var j = i + 1; j < rows.length; j++) {
        final a = rows[i];
        final b = rows[j];
        final as = ((a['audio_stats'] as Map?) ?? const {})
            .cast<String, dynamic>();
        final bs = ((b['audio_stats'] as Map?) ?? const {})
            .cast<String, dynamic>();
        final overlap =
            const ['low', 'lowmid', 'mid', 'high']
                .map((band) {
                  final av = ((as[band] as num?)?.toDouble() ?? 0).abs();
                  final bv = ((bs[band] as num?)?.toDouble() ?? 0).abs();
                  final maximum = av > bv ? av : bv;
                  return maximum <= 0 ? 0.0 : (av < bv ? av : bv) / maximum;
                })
                .reduce((a, b) => a + b) /
            4;
        final activity = _activityOverlap(as, bs);
        result.add({
          'track_a': a['track_ref'] ?? _stableTrackRef(a['row'] ?? i),
          'track_b': b['track_ref'] ?? _stableTrackRef(b['row'] ?? j),
          'role_a': _topRole(a),
          'role_b': _topRole(b),
          'band_overlap': overlap,
          'simultaneous_activity_proxy': activity,
          'masking_score': (overlap * activity).clamp(0.0, 1.0),
        });
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> snapshot) {
    final project = ((snapshot['project_state'] as Map?) ?? const {})
        .cast<String, dynamic>();
    return ((project['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .where((row) => row['hasAudio'] == true)
        .toList();
  }

  Map<String, dynamic> _numericDelta(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final out = <String, dynamic>{'source': 'state_proxy'};
    for (final key in {...before.keys, ...after.keys}) {
      if (before[key] is num && after[key] is num) {
        out[key] =
            (after[key] as num).toDouble() - (before[key] as num).toDouble();
      }
    }
    return out;
  }

  void _armEpisodeTimer() {
    _episodeTimer?.cancel();
    _episodeTimer = Zone.root.run(
      () => Timer(_episodeIdleTimeout, () {
        unawaited(finalizeActiveEpisode().catchError((Object _) {}));
      }),
    );
  }

  void _applyProjectContext({String? projectId, Directory? projectDir}) {
    if ((projectId ?? '').trim().isNotEmpty) _projectId = projectId!.trim();
    if (projectDir != null) _projectDir = projectDir;
    if (_session != null && (_projectId ?? '').isNotEmpty) {
      _session!['project_ref'] = _projectGroup(_projectId!);
    }
  }

  Future<void> _appendEvent(String type, Map<String, dynamic> payload) async {
    if (_journalFile == null) return;
    final event = {
      'schema_version': schemaVersion,
      'at': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      'payload': payload,
    };
    final file = _journalFile!;
    final line = '${jsonEncode(event)}\n';
    await _write(() async {
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  Future<void> _embedEventJournal() async {
    final journal = _journalFile;
    if (journal == null || !await journal.exists() || _session == null) return;
    final events = <Map<String, dynamic>>[];
    await for (final line
        in journal
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) events.add(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    _session!['event_journal'] = events;
  }

  Future<void> _flush() async {
    if (_session == null || _sessionFile == null) return;
    await _writeDocument(_sessionFile!, _session!);
  }

  Future<void> _writeDocument(File file, Map document) async {
    final content = const JsonEncoder.withIndent('  ').convert(document);
    await _write(() async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(file.path);
    });
  }

  List<Map<String, dynamic>> _episodes() =>
      ((_session?['episodes'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Map<String, dynamic>? _latestEpisode() =>
      _episodes().isEmpty ? null : _episodes().last;

  Future<Directory> _rootDir() async {
    if (_projectDir != null) {
      return Directory(p.join(_projectDir!.path, 'exports', directoryName));
    }
    return _applicationRootDir();
  }

  Future<Directory> _applicationRootDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, directoryName));
  }

  // Project IDs are UUIDs. Versioned hash is stable across capture sessions.
  String _projectGroup(String id) =>
      sha256.convert(utf8.encode('mixroom-source-group-v1:$id')).toString();

  String _stableHash(Object value) => sha256
      .convert(utf8.encode('$_sessionSalt:${value.toString()}'))
      .toString()
      .substring(0, 20);

  String _stableTrackRef(Object? value) =>
      'track_${_stableHash(value ?? 'unknown')}';

  void _setUploadState(ProducerCaptureUploadState state) {
    _uploadState = state;
    _onUploadStateChanged?.call(state);
  }

  static const Set<String> _redactedKeys = {
    'statebase64',
    'state_base64',
    'client_name',
    'account_id',
    'project_name',
    'row_name',
    'clip_name',
    'file',
    'filename',
    'file_name',
    'path',
    'source_path',
    'source_file',
    'source_file_path',
    'authorization',
    'access_token',
    'refresh_token',
    'id_token',
    'api_key',
    'email',
    'username',
    'input_device_name',
  };
}

String _sanitizeText(String value, {String key = ''}) {
  final normalized = key.toLowerCase();
  if (normalized.contains('path') ||
      normalized == 'file' ||
      normalized.endsWith('_file')) {
    return '[redacted]';
  }
  return value
      .replaceAll(
        RegExp(
          r'(?:file://)?/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/[^\s"\x27<>]+',
        ),
        '[local-path]',
      )
      .replaceAll(RegExp(r'[A-Za-z]:\\[^\s"\x27<>]+'), '[local-path]')
      .replaceAll(
        RegExp(r'Bearer\s+\S+', caseSensitive: false),
        'Bearer [redacted]',
      );
}

String _safeToken(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

bool _isContinuousMutation(String kind) {
  final token = kind.toLowerCase();
  return token.contains('gain') ||
      token.contains('pan') ||
      token.contains('param') ||
      token.contains('automation');
}

String _coalesceKey(Map<String, dynamic> action) {
  final payload = ((action['payload'] as Map?) ?? const {})
      .cast<String, dynamic>();
  return <Object?>[
    action['kind'],
    payload['row'],
    payload['index'],
    payload['param_id'],
    payload['clip'],
  ].join(':');
}

Map<String, dynamic> _coalescePayload(
  Map<String, dynamic> first,
  Map<String, dynamic> last,
) {
  final merged = <String, dynamic>{...first, ...last};
  for (final key in const ['old_gain', 'old_pan', 'old_value']) {
    if (first.containsKey(key)) merged[key] = first[key];
  }
  return merged;
}

double? _firstNumeric(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (map[key] is num) return (map[key] as num).toDouble();
  }
  return null;
}

double _activityOverlap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final av = ((a['activity_ratio'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
  final bv = ((b['activity_ratio'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
  return av < bv ? av : bv;
}

String _topRole(Map<String, dynamic> row) {
  final roles = ((row['role_probs'] as Map?) ?? const {})
      .cast<String, dynamic>();
  var best = 'other';
  var score = -1.0;
  for (final entry in roles.entries) {
    final value = (entry.value as num?)?.toDouble() ?? 0;
    if (value > score) {
      best = _safeToken(entry.key);
      score = value;
    }
  }
  return best;
}

/// Converts legacy prompt-cycle captures into partial v4 episodes.
/// Unrecoverable labels, audio targets, and output features remain explicitly
/// unavailable so downstream training cannot mistake synthesized data for truth.
Map<String, dynamic> migrateProducerSessionV3(Map<String, dynamic> legacy) {
  final sessionId = (legacy['session_id'] ?? 'legacy_session').toString();
  final sanitizer = ProducerDataCollector()
    .._sessionSalt = sha256.convert(utf8.encode(sessionId)).toString();
  final cycles = ((legacy['prompt_cycles'] as List?) ?? const [])
      .whereType<Map>()
      .toList();
  final episodes = <Map<String, dynamic>>[];
  for (var index = 0; index < cycles.length; index++) {
    final cycle = cycles[index].cast<String, dynamic>();
    final before = sanitizer._sanitizeMap(
      ((cycle['before_prompt_snapshot'] as Map?) ?? const {}),
      snapshotMode: true,
    );
    final after = sanitizer._sanitizeMap(
      ((cycle['producer_final_snapshot'] as Map?) ??
          (cycle['ai_after_snapshot'] as Map?) ??
          const {}),
      snapshotMode: true,
    );
    final aiActions = ((cycle['resolved_ai_actions'] as List?) ?? const [])
        .whereType<Map>()
        .map(sanitizer._sanitizeMap);
    final manual = ((cycle['manual_edits_debug'] as List?) ?? const [])
        .whereType<Map>()
        .map(sanitizer._sanitizeMap);
    episodes.add(<String, dynamic>{
      'episode_id': '${sessionId}_migrated_${index.toString().padLeft(4, '0')}',
      'episode_index': index,
      'started_at': cycle['captured_at'],
      'ended_at': cycle['final_captured_at'],
      'status': cycle['status'] == 'complete' ? 'complete' : 'incomplete',
      'disposition': 'migrated_v3',
      'state_before': before,
      'request_or_context': <String, dynamic>{
        'source': 'ai_prompt',
        'prompt': (cycle['prompt'] ?? '').toString(),
      },
      'diagnosis': 'other',
      'diagnoses': <String>['other'],
      'strategies': <String>[],
      'actions_raw': <Map<String, dynamic>>[...aiActions, ...manual],
      'actions_relational': <Map<String, dynamic>>[],
      'state_after': after,
      'audio_features_before': <String, dynamic>{},
      'audio_features_after': <String, dynamic>{},
      'audio_feature_delta': <String, dynamic>{},
      'audio_target': <String, dynamic>{
        'status': 'unavailable',
        'reason': 'legacy_capture_has_no_render',
      },
      'outcome_signals': <String, dynamic>{
        'legacy_disposition': cycle['disposition'],
      },
      'provenance': <String, dynamic>{'label': 'unknown', 'confidence': 0.0},
      'migration_missing_fields': <String>[
        'confirmed_diagnosis',
        'confirmed_strategies',
        'relational_actions',
        'audio_features',
        'paired_audio',
      ],
    });
  }
  return <String, dynamic>{
    'schema_version': ProducerDataCollector.schemaVersion,
    'session_id': sessionId,
    'started_at': legacy['started_at'],
    'ended_at': legacy['ended_at'],
    'close_reason': legacy['close_reason'],
    'migration': <String, dynamic>{
      'source_schema_version': legacy['schema_version'],
      'migrated_at': DateTime.now().toUtc().toIso8601String(),
    },
    'episodes': episodes,
    'media_manifest': <Map<String, dynamic>>[],
    'upload': <String, dynamic>{'status': 'pending', 'attempts': 0},
  };
}
