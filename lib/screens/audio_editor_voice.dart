part of 'audio_editor.dart';

class _NativeVoiceComparison extends VoiceComparison<EditorUndoAction> {
  _NativeVoiceComparison({
    required super.action,
    required super.beforeDigest,
    required super.afterDigest,
  });
  final String id = const Uuid().v4();
}

class _NativeVoiceState {
  final String projectSessionId = const Uuid().v4();
  VoiceSessionController? controller;
  VoiceRelayPlanner? planner;
  Map<String, dynamic>? plannerResponse;
  Map<String, dynamic>? handoff;
  VoiceResult? executionResult;
  EditorUndoAction? pendingAction;
  _NativeVoiceComparison? comparison;
  String digest = '';
  int revision = 0;
  bool comparisonSwitching = false;
  bool disposed = false;
  bool captureCancelled = false;
  Completer<void>? captureFinished;
  String? captureId;
  String recordingPhase = 'idle';
  double remainingSeconds = 0;
  List<Map<String, dynamic>> notes = [];
  String status = 'Connect a browser to begin a voice session';
}

extension _AudioEditorVoice on _AudioEditorScreenState2 {
  AiV3Planner _createVoicePlanner() {
    return _voice.planner = VoiceRelayPlanner(
      request: (body) {
        final controller = _voice.controller;
        if (controller == null) throw StateError('voice_not_connected');
        return controller.plan(body);
      },
      onResponse: (response) => _voice.plannerResponse = response,
    );
  }

  VoiceProjectNotes get _voiceNotes =>
      VoiceProjectNotes(File(p.join(_projectDir.path, 'voice_notes.json')));

  Map<String, dynamic> _voiceSnapshot() {
    final digest = _freshAiV3StateFingerprint();
    if (digest != _voice.digest) {
      _voice.digest = digest;
      _voice.revision++;
    }
    final comparison = _voice.comparison;
    final clock = _isPlaying
        ? _estimateTransportClockFromSample()
        : _globalAudioClock;
    return {
      'projectSessionId': _voice.projectSessionId,
      'projectRevision': _voice.revision,
      'state': {
        'projectName': _projectName,
        'projectReady':
            _loadedOnce && _editorSessionReady && !_isProjectLoading,
        'tracks': [
          for (var index = 0; index < _rows.length; index++)
            {
              'id': _rows[index].rowId,
              'name': _rows[index].name,
              'type': _rows[index].kind.wireName,
              'muted': index < _rowMuted.length && _rowMuted[index],
              'solo': index < _rowSoloed.length && _rowSoloed[index],
              'armed': index == _selectedRow,
              'volumeDb': index < _rowGain.length
                  ? rowGainUiToDb(_rowGain[index])
                  : 0,
              'pan': index < _rowPan.length ? _rowPan[index] * 2 - 1 : 0,
            },
        ],
        'transport': {
          'playing': _isPlaying,
          'recording': _recordButtonVisuallyActive,
          'positionSeconds': clock.inMilliseconds / 1000,
          'tempo': _tempo,
          'timeSignature':
              '$_timeSignatureNumerator/$_timeSignatureDenominator',
          'loopEnabled': _loopEnabled,
          'loopStartSeconds': _loopStartMs / 1000,
          'loopEndSeconds': _loopEndMs / 1000,
        },
        'selectedTrackIds': [
          if (_isValidRowIndex(_selectedRow)) _rowIdAt(_selectedRow),
        ],
        'busy':
            _isThinking ||
            (_v3ExecutionInProgress && _voice.comparison?.before != true) ||
            _voice.controller?.busy == true,
        'inputReady': !_microphoneAccessBlocked && !_v2AudioSessionInvalidated,
        'captureId': _voice.captureId,
        'recordingPhase': _voice.recordingPhase,
        'captureRemainingSeconds': _voice.remainingSeconds,
        'comparison': {
          'id': comparison?.id,
          'available': comparison != null,
          'side': comparison?.before == true ? 'before' : 'after',
        },
        'notes': _voice.notes.take(100).toList(),
        if (_voice.executionResult != null)
          'lastResult': {
            'status': _voice.executionResult!.status,
            'message': _voice.executionResult!.message,
          },
      },
    };
  }

  Future<void> _pairVoiceSession() async {
    if (_voice.controller?.busy == true || _voice.captureId != null) {
      _voice.status =
          'Wait for the current request to finish before reconnecting.';
      _voiceRefresh();
      return;
    }
    final details = await showVoicePairDialog(
      context,
      initialBaseUrl: HackathonConfig.relayBaseUrl,
    );
    if (details == null || !mounted) return;
    if (_voice.controller?.busy == true || _voice.captureId != null) return;
    try {
      final old = _voice.controller;
      if (old != null) {
        await old.disconnect();
        old.dispose();
      }
      _voice.notes = await _voiceNotes.list();
      final controller = VoiceSessionController(
        transport: HttpVoiceRelayTransport(details.baseUrl),
        journal: VoiceCommandJournal(
          file: File(p.join(_projectDir.path, '.voice_commands.json')),
        ),
        stateProvider: _voiceSnapshot,
        commandHandler: _runVoiceCommandWithTiming,
        onDisconnect: _voiceDisconnected,
        onEmergencyStop: (captureId) {
          if (_voice.captureId == captureId) _voice.captureCancelled = true;
        },
      );
      _voice.controller = controller;
      controller.addListener(_voiceRefresh);
      await controller.pair(details.code);
      _voice.status = 'Connected · speak in your browser';
    } catch (_) {
      _voice.status =
          'Could not connect. Check the relay URL and pairing code.';
    }
    _voiceRefresh();
  }

  void _voiceRefresh() {
    if (mounted && !_voice.disposed) _safeAudioEditorStateSetter(() {});
  }

  Future<void> _voiceDisconnected() async {
    // A bounded take already in progress finishes locally even without Wi-Fi.
    if (_voice.recordingPhase == 'awaiting_ready' ||
        _voice.recordingPhase == 'countdown') {
      _voice.captureCancelled = true;
      if (_voice.captureId != null)
        _voice.controller?.cancelCapture(_voice.captureId!);
    }
    await _voiceSwitchComparison(false);
    _voice.status = 'Voice session disconnected';
    _voiceRefresh();
  }

  Future<bool> _voicePrepareToLeave() async {
    if (_isThinking) _stopActiveChatFlow();
    final mutationWait = Stopwatch()..start();
    while (_v3ExecutionInProgress && _voice.comparison?.before != true) {
      if (mutationWait.elapsed > const Duration(seconds: 15)) {
        _voice.status = 'Wait for the current edit to finish before closing.';
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _voice.captureCancelled = true;
    if (!await _voiceSwitchComparison(false)) return false;
    final finished = _voice.captureFinished;
    if (finished != null) {
      try {
        await finished.future.timeout(const Duration(seconds: 15));
      } catch (_) {
        _voice.status =
            'Wait for the recording to finish saving before closing.';
        _voiceRefresh();
        return false;
      }
    }
    await _voice.controller?.disconnect();
    return true;
  }

  void _disposeVoiceSession() {
    _voice.disposed = true;
    _voice.captureCancelled = true;
    // A/B never autosaves A. The on-disk project remains the verified B state.
    _voice.controller?.dispose();
    _voice.controller = null;
  }

  Future<VoiceResult> _runVoiceCommandWithTiming(VoiceCommand command) async {
    if (_voice.planner != null) _voice.planner!.lastPlanningMs = 0;
    final total = Stopwatch()..start();
    final result = await _runVoiceCommand(command);
    total.stop();
    final planningMs = _voice.planner?.lastPlanningMs ?? 0;
    final timed = VoiceResult(
      result.status,
      result.message,
      data: {
        ...result.data,
        'planningMs': planningMs,
        'executionMs':
            result.data['executionMs'] ??
            math.max(0, total.elapsedMilliseconds - planningMs),
      },
    );
    _voice.executionResult = timed;
    _voice.status = timed.message;
    _voiceRefresh();
    return timed;
  }

  Future<VoiceResult> _runVoiceCommand(VoiceCommand command) async {
    if (!_loadedOnce || !_editorSessionReady || _isProjectLoading) {
      return const VoiceResult(
        'rejected',
        'Wait for the project to finish opening.',
      );
    }
    if (_voice.captureId != null) {
      return const VoiceResult(
        'rejected',
        'Wait for the current recording to finish. Use Stop recording to end it now.',
      );
    }
    if (_isThinking ||
        (_v3ExecutionInProgress && _voice.comparison?.before != true)) {
      return const VoiceResult(
        'rejected',
        'MixRoom is finishing another change.',
      );
    }
    _voice.executionResult = null;
    _voice.pendingAction = null;
    _voice.plannerResponse = null;
    _voice.handoff = null;
    if (command.kind == 'session_action') {
      return _runVoiceSessionAction(command.arguments);
    }
    if (command.kind != 'utterance' || command.arguments['text'] is! String) {
      return const VoiceResult('rejected', 'Unsupported voice command.');
    }
    // Preserve the auditioned side while interpreting "keep this" or "after".
    // DAW mutations remain blocked in _presentAiV3Handoff until A/B is resolved.
    final beforePlanning = _freshAiV3StateFingerprint();
    await _submitChatPrompt(command.arguments['text'] as String);
    if (_voice.disposed || _voice.controller?.connected != true) {
      return const VoiceResult(
        'rejected',
        'The voice session closed before this request finished.',
      );
    }
    final response = _voice.plannerResponse;
    if (response?['kind'] == 'session_action') {
      if (_freshAiV3StateFingerprint() != beforePlanning) {
        return const VoiceResult(
          'rejected',
          'The project changed while this request was being planned. Please ask again.',
        );
      }
      return _runVoiceSessionAction(
        Map<String, dynamic>.from(response!['action'] as Map),
      );
    }
    final executed = _voice.executionResult;
    if (executed != null) return executed;
    final handoff = _voice.handoff;
    final decision = handoff?['decision'];
    if (const {
      'respond',
      'clarify',
      'unsupported',
      'ask_confirmation',
      'canceled',
    }.contains(decision)) {
      final message =
          (handoff?['message'] ??
                  (handoff?['plan'] as Map?)?['user_message'] ??
                  (handoff?['prepared_bundle'] as Map?)?['preview'] ??
                  response?['message'] ??
                  '')
              .toString();
      return VoiceResult(
        decision == 'ask_confirmation' ? 'clarify' : decision.toString(),
        message.isEmpty ? 'Please clarify what you want to change.' : message,
      );
    }
    return const VoiceResult(
      'failed',
      'MixRoom could not verify that request. Nothing is reported as complete.',
    );
  }

  Future<VoiceResult> _runVoiceSessionAction(
    Map<String, dynamic> action,
  ) async {
    final type = action['type'];
    final rawArgs = action['arguments'];
    if (type is! String || rawArgs is! Map) {
      return const VoiceResult('rejected', 'Invalid session action.');
    }
    final args = Map<String, dynamic>.from(rawArgs);
    switch (type) {
      case 'recording.start':
        return _voiceRecord(args);
      case 'recording.stop':
        _voice.captureCancelled = true;
        if (_recordButtonVisuallyActive) {
          await _stopRecordingJuce(keepPlaying: false);
        }
        return VoiceResult(
          _recordButtonVisuallyActive ? 'failed' : 'verified',
          _recordButtonVisuallyActive
              ? 'Recording has not stopped yet.'
              : 'Recording stopped.',
        );
      case 'comparison.before':
      case 'comparison.after':
        if (_voice.comparison == null) {
          return const VoiceResult(
            'rejected',
            'There is no recent mix change to compare.',
          );
        }
        final ok = await _voiceSwitchComparison(type.endsWith('before'));
        return VoiceResult(
          ok ? 'verified' : 'rejected',
          ok
              ? 'Switched to the ${type.endsWith('before') ? 'original' : 'revised'} mix.'
              : 'The last mix change is no longer available for comparison.',
        );
      case 'comparison.keep_before':
      case 'comparison.keep_after':
        if (_voice.comparison == null) {
          return const VoiceResult(
            'rejected',
            'There is no recent mix change to keep.',
          );
        }
        final before = type.endsWith('before');
        final ok = await _voiceSwitchComparison(before);
        if (!ok)
          return const VoiceResult(
            'rejected',
            'That comparison is no longer available.',
          );
        _voice.comparison = null;
        _setV3ExecutionInProgress(false);
        _scheduleProjectAutosave();
        await _persistUndoHistory();
        return VoiceResult(
          'verified',
          before ? 'Kept the original mix.' : 'Kept the revised mix.',
        );
      case 'history.undo':
      case 'history.redo':
        if (!await _voiceSwitchComparison(false)) {
          return const VoiceResult(
            'rejected',
            'The revised mix could not be restored. Resolve the comparison first.',
          );
        }
        _voice.comparison = null;
        final historyAction = type == 'history.undo'
            ? _undoManager.latestUndoAction
            : _undoManager.latestRedoAction;
        if (type == 'history.undo') {
          if (!_undoManager.canUndo)
            return const VoiceResult('respond', 'There is nothing to undo.');
          await _performEditorUndo();
        } else {
          if (!_undoManager.canRedo)
            return const VoiceResult('respond', 'There is nothing to redo.');
          await _performEditorRedo();
        }
        final movedAction = type == 'history.undo'
            ? _undoManager.latestRedoAction
            : _undoManager.latestUndoAction;
        if (!identical(historyAction, movedAction)) {
          return const VoiceResult(
            'failed',
            'The history change could not be verified.',
          );
        }
        return VoiceResult(
          'verified',
          type == 'history.undo'
              ? 'Undid the last edit.'
              : 'Redid the last edit.',
        );
      case 'notes.add':
        final note = await _voiceNotes.add(
          args['text']?.toString() ?? '',
          playheadMs: _globalAudioClock.inMilliseconds,
          projectId: _projectId,
          trackId: _isValidRowIndex(_selectedRow)
              ? _rowIdAt(_selectedRow)
              : null,
        );
        _voice.notes = await _voiceNotes.list();
        return VoiceResult(
          'verified',
          'Saved your session note.',
          data: {'note': note},
        );
      case 'notes.list':
        _voice.notes = await _voiceNotes.list();
        final open = _voice.notes
            .where((note) => note['completed'] != true)
            .toList();
        return VoiceResult(
          'respond',
          open.isEmpty
              ? 'No open session notes.'
              : open.map((note) => note['text']).join('. '),
          data: {'notes': open},
        );
      case 'notes.complete':
        final ok = await _voiceNotes.complete(
          args['note_id']?.toString() ?? '',
        );
        _voice.notes = await _voiceNotes.list();
        return VoiceResult(
          ok ? 'verified' : 'rejected',
          ok ? 'Marked the note complete.' : 'That note was not found.',
        );
      default:
        return const VoiceResult(
          'unsupported',
          'That session action is not available.',
        );
    }
  }

  void _voiceVerified(
    Map<String, dynamic> bundle,
    String beforeDigest,
    String message,
    List<Map<String, dynamic>> observed,
    int executionMs,
  ) {
    _voice.executionResult = VoiceResult(
      'verified',
      message.isEmpty ? 'The edit was applied and verified.' : message,
      data: {
        'verification': 'passed',
        'receipts': bundle['receipts'] ?? [],
        'executionMs': executionMs,
      },
    );
    final plan = bundle['plan'];
    final commands = plan is Map ? plan['commands'] : null;
    const comparable = {
      'row.adjust_gain_db',
      'row.set_gain_db',
      'row.adjust_pan',
      'row.set_pan',
      'row.set_muted',
      'row.set_soloed',
      'effect.ensure_configured',
      'effect.remove',
      'effect.set_bypassed',
      'mix.apply_goal',
    };
    final action = _voice.pendingAction;
    if (commands is List &&
        commands.isNotEmpty &&
        commands.every(
          (command) => command is Map && comparable.contains(command['type']),
        ) &&
        action != null &&
        identical(_undoManager.latestUndoAction, action)) {
      _voice.comparison = _NativeVoiceComparison(
        action: action,
        beforeDigest: beforeDigest,
        afterDigest: _freshAiV3StateFingerprint(),
      );
    } else {
      _voice.comparison = null;
    }
    _voice.pendingAction = null;
  }

  void _voiceHistoryChanged() {
    if (_voice.comparisonSwitching) return;
    final comparison = _voice.comparison;
    if (comparison != null &&
        !identical(_undoManager.latestUndoAction, comparison.action)) {
      _voice.comparison = null;
    }
  }

  Future<bool> _voiceSwitchComparison(bool before) async {
    final comparison = _voice.comparison;
    if (comparison == null) return !before;
    if (_recordButtonVisuallyActive || _voice.comparisonSwitching) return false;
    final expected = comparison.before
        ? comparison.beforeDigest
        : comparison.afterDigest;
    final head = comparison.before
        ? _undoManager.latestRedoAction
        : _undoManager.latestUndoAction;
    if (!identical(head, comparison.action) ||
        _freshAiV3StateFingerprint() != expected) {
      if (!comparison.before) _voice.comparison = null;
      return false;
    }
    if (comparison.before == before) return true;
    _voice.comparisonSwitching = true;
    final wasPlaying = _isPlaying;
    try {
      if (!comparison.before) await _projectAutosaveCoordinator.flush();
      if (_isPlaying) await _pauseAudio(_safeAudioEditorStateSetter);
      _setV3ExecutionInProgress(true);
      final switched = await comparison.switchTo(
        before,
        undoHead: () => _undoManager.latestUndoAction,
        redoHead: () => _undoManager.latestRedoAction,
        fingerprint: _freshAiV3StateFingerprint,
        undo: _undoManager.undo,
        redo: _undoManager.redo,
        refresh: () => _refreshEffectCachesForUndoAction(comparison.action),
      );
      if (!switched) {
        if (!comparison.before) _setV3ExecutionInProgress(false);
        throw StateError('comparison_readback_failed');
      }
      await _restartAudio(_safeAudioEditorStateSetter);
      if (wasPlaying && !_isPlaying) await _togglePlayPause();
      if (!before) {
        _setV3ExecutionInProgress(false);
        _scheduleProjectAutosave();
      }
      return true;
    } catch (_) {
      _voice.status = 'Comparison could not be verified. Restore the revised mix before editing.';
      return false;
    } finally {
      _voice.comparisonSwitching = false;
      _voiceRefresh();
    }
  }

  Future<VoiceResult> _voiceRecord(Map<String, dynamic> args) async {
    if (_recordButtonVisuallyActive || _voice.captureId != null) {
      return const VoiceResult('rejected', 'Recording is already running.');
    }
    final controller = _voice.controller;
    if (controller == null || !controller.connected) {
      return const VoiceResult(
        'rejected',
        'Connect the browser before recording.',
      );
    }
    final duration = voiceCaptureDuration(
      args,
      bpm: _tempo,
      beatsPerBar: _timeSignatureNumerator,
      beatUnit: _timeSignatureDenominator,
    );
    final requestedRow = args['row_id'];
    final row = requestedRow is int
        ? _rowIndexForId(requestedRow)
        : _selectedRow;
    if (!_isValidRowIndex(row) || _rows[row].kind != TimelineRowKind.audio) {
      return const VoiceResult(
        'clarify',
        'Select an audio track to record into.',
      );
    }
    final recordingRowId = _rowIdAt(row);
    if (!await _voiceSwitchComparison(false)) {
      return const VoiceResult(
        'rejected',
        'Restore the revised mix before recording.',
      );
    }
    final hum = args['hum'] == true;
    final instrument = args['instrument_id']?.toString() ?? 'mixroom.warm_keys';
    if (hum && _findInstrumentSpecById(instrument) == null) {
      return const VoiceResult(
        'clarify',
        'Choose an available instrument for the melody.',
      );
    }
    final beforeClips = _audioTracks.map((track) => track.clipId).toSet();
    final captureId = const Uuid().v4();
    final previousLoopEnabled = _loopEnabled;
    var recordingStarted = false;
    _voice.captureId = captureId;
    _voice.captureFinished = Completer<void>();
    _voice.captureCancelled = false;
    _voice.recordingPhase = 'awaiting_ready';
    _voice.remainingSeconds = duration.inMilliseconds / 1000;
    _voiceRefresh();
    try {
      await controller.publishState();
      if (!await controller.waitForCaptureReady(captureId)) {
        return const VoiceResult(
          'rejected',
          'The browser did not confirm that its microphone and speech were paused. Recording did not start.',
        );
      }
      _voice.recordingPhase = 'countdown';
      _voice.status = 'Recording starts in 2 seconds';
      await controller.publishState();
      final countIn = Stopwatch()..start();
      while (countIn.elapsed < const Duration(seconds: 2) &&
          !_voice.captureCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_voice.captureCancelled ||
          _voice.disposed ||
          !controller.connected ||
          !mounted) {
        return const VoiceResult(
          'rejected',
          'Recording canceled before it started.',
        );
      }
      final currentRow = _rowIndexForId(recordingRowId);
      if (!_isValidRowIndex(currentRow) ||
          _rows[currentRow].kind != TimelineRowKind.audio) {
        return const VoiceResult(
          'rejected',
          'The selected recording track changed.',
        );
      }
      _safeAudioEditorStateSetter(() => _selectedRow = currentRow);
      // A pre-existing short loop must not truncate this bounded take.
      _loopEnabled = false;
      await _syncNativeLoopRegion();
      await _startRecordingJuce();
      recordingStarted = _isRecording;
      if (!_isRecording)
        return const VoiceResult(
          'failed',
          'The recording input could not start.',
        );
      _voice.recordingPhase = 'capturing';
      final watch = Stopwatch()..start();
      _voiceRefresh();
      while (_isRecording &&
          watch.elapsed < duration &&
          !_voice.captureCancelled &&
          !_voice.disposed) {
        _voice.remainingSeconds = math.max(
          0,
          (duration - watch.elapsed).inMilliseconds / 1000,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _voice.recordingPhase = 'saving';
      if (_isRecording) await _stopRecordingJuce(keepPlaying: false);
      final saveWait = Stopwatch()..start();
      while (_recordTransitionInFlight &&
          saveWait.elapsed < const Duration(seconds: 15)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_voice.disposed)
        return const VoiceResult(
          'failed',
          'The session closed during recording.',
        );
      final clips = _audioTracks
          .where(
            (track) => !beforeClips.contains(track.clipId) && !track.isMidi,
          )
          .toList();
      if (clips.length != 1)
        return const VoiceResult(
          'failed',
          'The recording could not be verified as a saved clip.',
        );
      final clip = clips.single;
      if (!await clip.file.exists() || await clip.file.length() <= 44) {
        return const VoiceResult(
          'failed',
          'The recorded audio file is empty or unavailable.',
        );
      }
      if (!hum)
        return VoiceResult(
          'verified',
          'Recorded and saved your take.',
          data: {'clipId': clip.clipId},
        );
      _voice.recordingPhase = 'transcribing';
      _voice.status = 'Turning your humming into editable notes';
      _voice.planner!.nextLocalPlan = AiV3Plan(
        outcome: 'plan',
        userMessage: '',
        commands: [
          AiV3Command(
            commandId: 'hum_to_midi',
            type: 'clip.convert_to_midi',
            arguments: {'clip_id': clip.clipId, 'instrument_id': instrument},
          ),
        ],
      );
      _voice.executionResult = null;
      await _submitChatPrompt(
        'Turn the recorded humming into editable MIDI; preserve the original recording.',
      );
      final conversion = _voice.executionResult;
      if (conversion?.status != 'verified') {
        return VoiceResult(
          'failed',
          'Your original humming was saved, but stable MIDI notes could not be verified.',
          data: {'clipId': clip.clipId},
        );
      }
      return VoiceResult(
        'verified',
        'Created editable MIDI from your humming and kept the original recording.',
        data: {'sourceClipId': clip.clipId},
      );
    } finally {
      if (recordingStarted && _isRecording && !_voice.disposed) {
        try {
          await _stopRecordingJuce(keepPlaying: false);
        } catch (_) {}
      }
      try {
        _loopEnabled = previousLoopEnabled;
        if (!_voice.disposed) await _syncNativeLoopRegion();
      } finally {
        _voice.recordingPhase = 'idle';
        _voice.captureId = null;
        _voice.remainingSeconds = 0;
        _voice.planner?.nextLocalPlan = null;
        _voice.captureFinished?.complete();
        _voice.captureFinished = null;
        _voiceRefresh();
      }
    }
  }

  Widget _buildVoiceSessionOverlay() {
    final controller = _voice.controller;
    final connected = controller?.connected == true;
    return Positioned(
      right: 18,
      top: 76,
      child: Material(
        elevation: 8,
        color: const Color(0xFF202B39),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected ? Icons.mic : Icons.mic_none,
                    color: connected ? const Color(0xFF82E7C6) : Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Voice session',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: connected
                        ? () => unawaited(controller!.disconnect())
                        : controller?.busy == true || _voice.captureId != null
                        ? null
                        : _pairVoiceSession,
                    child: Text(connected ? 'Disconnect' : 'Connect'),
                  ),
                ],
              ),
              SizedBox(
                width: 290,
                child: Text(
                  controller?.error ?? _voice.status,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (_voice.recordingPhase != 'idle') ...[
                const SizedBox(height: 8),
                Text(
                  '${_voice.recordingPhase} · ${_voice.remainingSeconds.ceil()}s',
                  style: const TextStyle(color: Colors.white),
                ),
                TextButton(
                  onPressed: () {
                    _voice.captureCancelled = true;
                    if (_voice.captureId != null)
                      controller?.cancelCapture(_voice.captureId!);
                  },
                  child: const Text('Stop recording'),
                ),
              ],
              if (_voice.comparison != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => unawaited(_voiceSwitchComparison(true)),
                      child: const Text('Before'),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_voiceSwitchComparison(false)),
                      child: const Text('After'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
