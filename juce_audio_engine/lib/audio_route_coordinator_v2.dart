import 'dart:async';

import 'audio_route_v2.dart';

abstract interface class AudioRouteAdapterV2 {
  Stream<AudioRouteChangeEventV2> get events;

  Future<AudioRouteSnapshotV2> startMonitoring();

  Future<AudioRouteTransitionResultV2> applyPlaybackRoute(
    int generation, {
    String? outputDeviceName,
    String? inputDeviceName,
    String? inputDeviceUID,
    bool updateInputPreference = false,
    int? preferredSampleRateHz,
    int? preferredBufferFrames,
    bool updateHardwarePreferences = false,
  });

  Future<AudioRouteTransitionResultV2> applyIntent(
      AudioRouteIntentV2 intent, int generation,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard,
      int? recordingChannelStart,
      int? recordingChannelCount,
      int? monitoringTargetRow});

  Future<void> stopMonitoring();
}

class AudioRouteCoordinatorV2 {
  AudioRouteCoordinatorV2({
    required AudioRouteAdapterV2 adapter,
    this.settlingDelay = const Duration(milliseconds: 100),
    this.inputSelectionRecoveryDeadline = const Duration(seconds: 2),
    this.allowRecoveryGenerationSupersession = false,
    this.onStateChanged,
    this.onTransition,
    this.onIntentInvalidated,
  }) : _adapter = adapter;

  final AudioRouteAdapterV2 _adapter;
  final Duration settlingDelay;
  final Duration inputSelectionRecoveryDeadline;
  final bool allowRecoveryGenerationSupersession;
  final void Function(AudioRouteCoordinatorStateV2 state)? onStateChanged;
  final void Function(AudioRouteTransitionResultV2 result)? onTransition;
  final void Function(AudioRouteChangeEventV2 event)? onIntentInvalidated;

  AudioRouteCoordinatorStateV2 _state = AudioRouteCoordinatorStateV2.stable;
  AudioRouteCoordinatorStateV2 get state => _state;

  StreamSubscription<AudioRouteChangeEventV2>? _subscription;
  Timer? _settlingTimer;
  AudioRouteChangeEventV2? _pending;
  String? _lastFingerprint;
  int _latestGeneration = 0;
  int get generation => _latestGeneration;
  bool _applyInFlight = false;
  bool _intentTransitionInFlight = false;
  Completer<void>? _intentTransitionCompletion;
  Completer<void>? _interruptionEndedCompletion;
  Future<AudioRouteTransitionResultV2>? _invalidationRecovery;
  AudioRouteTransitionResultV2? _completedInvalidationRecovery;
  int? _completedInvalidationRecoveryGeneration;
  bool _interruptionActive = false;
  bool _interruptionEndHandled = false;
  bool _shutdownCancellation = false;
  int _invalidationEpisode = 0;
  bool _started = false;
  bool _disposed = false;
  AudioRouteIntentV2 _intent = AudioRouteIntentV2.playbackOnly;
  AudioRouteIntentV2? _transitioningIntent;
  _PlaybackRecoveryWaiter? _inputSelectionRecoveryWaiter;

  AudioRouteIntentV2 get intent => _intent;

  bool get _inputLifecycleOwned =>
      _intent != AudioRouteIntentV2.playbackOnly ||
      (_transitioningIntent != null &&
          _transitioningIntent != AudioRouteIntentV2.playbackOnly);

  void _schedulePendingDrain() {
    if (_disposed ||
        _shutdownCancellation ||
        _interruptionActive ||
        _pending == null) {
      return;
    }
    _settlingTimer?.cancel();
    _settlingTimer = Timer(settlingDelay, _drain);
  }

  void _beginInvalidationEpisode() {
    _invalidationEpisode += 1;
    _completedInvalidationRecovery = null;
    _completedInvalidationRecoveryGeneration = null;
  }

  /// Starts one editor-lifecycle invalidation episode when iOS backgrounds
  /// without first delivering a native audio interruption notification.
  void beginLocalInvalidationEpisode() {
    if (_disposed || !_started || _shutdownCancellation) return;
    _beginInvalidationEpisode();
    _pending = null;
    _settlingTimer?.cancel();
    _settlingTimer = null;
    _setState(AudioRouteCoordinatorStateV2.reconfiguring);
  }

  Future<AudioRouteSnapshotV2> start() async {
    if (_disposed) throw StateError('AudioRouteCoordinatorV2 is disposed');
    if (_started) throw StateError('AudioRouteCoordinatorV2 already started');
    _started = true;
    _subscription = _adapter.events.listen(_receive);
    try {
      return await _adapter.startMonitoring();
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      _started = false;
      rethrow;
    }
  }

  void _receive(AudioRouteChangeEventV2 event) {
    if (_disposed || event.generation <= _latestGeneration) return;
    _latestGeneration = event.generation;
    final interruptionBegan = event.cause == 'audioInterruptionBegan' ||
        event.cause == 'audioInterrupted';
    final interruptionEnded = event.cause == 'audioInterruptionEnded';

    if (interruptionBegan) {
      _lastFingerprint = event.fingerprint;
      _pending = null;
      _settlingTimer?.cancel();
      _settlingTimer = null;
      if (!_interruptionActive) {
        _beginInvalidationEpisode();
        _interruptionActive = true;
        _interruptionEndHandled = false;
        _interruptionEndedCompletion = Completer<void>();
        _setState(AudioRouteCoordinatorStateV2.reconfiguring);
        onIntentInvalidated?.call(event);
      }
      return;
    }

    if (interruptionEnded) {
      _lastFingerprint = event.fingerprint;
      _pending = null;
      _settlingTimer?.cancel();
      _settlingTimer = null;
      final suspendedSession =
          event.snapshot.interruption?.wasSuspended == true;
      if (suspendedSession && !_interruptionActive) {
        _beginInvalidationEpisode();
        _interruptionEndHandled = false;
      }
      if (_interruptionEndHandled) return;
      _interruptionEndHandled = true;
      if (_interruptionActive) {
        _interruptionActive = false;
        final completion = _interruptionEndedCompletion;
        if (completion != null && !completion.isCompleted) {
          completion.complete();
        }
      } else if (_invalidationRecovery == null) {
        // iOS can deliver a suspended-session interruption only after the app
        // is running again. It is already recoverable, but still needs the
        // same cleanup and one playback-only transition.
        _setState(AudioRouteCoordinatorStateV2.reconfiguring);
        onIntentInvalidated?.call(event);
      }
      return;
    }

    if (_interruptionActive) {
      // Retain the newest generation and route identity for the eventual
      // recovery, but never apply a route while the session is interrupted.
      _lastFingerprint = event.fingerprint;
      return;
    }

    // A route event owns recording safety until playback-only has actually
    // committed. Event causes are diagnostics, not lifecycle policy: a new or
    // platform-specific cause must not bypass capture invalidation merely
    // because its endpoint fingerprint stayed the same.
    if (_inputLifecycleOwned) {
      _lastFingerprint = event.fingerprint;
      _pending = null;
      _settlingTimer?.cancel();
      _settlingTimer = null;
      _setState(AudioRouteCoordinatorStateV2.failed);
      onIntentInvalidated?.call(event);
      return;
    }
    if (!event.requiresReconfiguration &&
        event.fingerprint.isNotEmpty &&
        event.fingerprint == _lastFingerprint) {
      if (_pending != null) _pending = event;
      return;
    }
    _lastFingerprint = event.fingerprint;
    _pending = event;
    final waiter = _inputSelectionRecoveryWaiter;
    if (waiter != null && event.generation > waiter.afterGeneration) {
      waiter.targetGeneration = event.generation;
    }
    _setState(AudioRouteCoordinatorStateV2.reconfiguring);
    _schedulePendingDrain();
  }

  Future<void> _drain() async {
    _settlingTimer = null;
    if (_disposed || _applyInFlight || _intentTransitionInFlight) return;
    final event = _pending;
    if (event == null) return;
    _pending = null;
    _applyInFlight = true;

    AudioRouteTransitionResultV2 result;
    try {
      result = await _adapter.applyPlaybackRoute(event.generation);
    } catch (_) {
      result = AudioRouteTransitionResultV2(
        status: AudioRouteTransitionStatusV2.failure,
        generation: event.generation,
        transitionId: 0,
        diagnosticCode: 'actual_state_unavailable',
        elapsedMs: 0,
        transportWasPlaying: event.transportWasPlaying,
        snapshot: event.snapshot,
      );
    } finally {
      _applyInFlight = false;
    }

    if (_disposed) return;
    final stale = result.generation != event.generation ||
        result.diagnosticCode == 'stale_generation' ||
        (_latestGeneration > result.generation && _pending != null);
    if (!stale) {
      _setState(result.succeeded
          ? AudioRouteCoordinatorStateV2.stable
          : AudioRouteCoordinatorStateV2.failed);
      onTransition?.call(result);
      final waiter = _inputSelectionRecoveryWaiter;
      if (waiter != null &&
          waiter.targetGeneration != null &&
          result.generation >= waiter.targetGeneration! &&
          _pending == null &&
          !waiter.completion.isCompleted) {
        waiter.completion.complete(result);
      }
    }

    _schedulePendingDrain();
  }

  Future<AudioRouteTransitionResultV2> transitionIntent(
      AudioRouteIntentV2 intent,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard,
      int? recordingChannelStart,
      int? recordingChannelCount,
      int? monitoringTargetRow}) async {
    if (_disposed || !_started || _shutdownCancellation) {
      return _localFailure(intent, 'coordinator_disposed');
    }
    if (_interruptionActive) {
      return _localFailure(intent, 'route_unstable');
    }
    if (_applyInFlight || _intentTransitionInFlight || _pending != null) {
      return _localFailure(intent, 'route_unstable');
    }

    _intentTransitionInFlight = true;
    final completion = Completer<void>();
    _intentTransitionCompletion = completion;
    _transitioningIntent = intent;
    final generation = _latestGeneration;
    _setState(intent == AudioRouteIntentV2.playbackOnly
        ? AudioRouteCoordinatorStateV2.reconfiguring
        : AudioRouteCoordinatorStateV2.preparingInput);
    AudioRouteTransitionResultV2 result;
    try {
      result = await _adapter.applyIntent(
        intent,
        generation,
        operation: operation,
        recordingChannelStart: recordingChannelStart,
        recordingChannelCount: recordingChannelCount,
        monitoringTargetRow: monitoringTargetRow,
      );
    } catch (_) {
      result = _localFailure(intent, 'actual_state_unavailable');
    } finally {
      _intentTransitionInFlight = false;
      _transitioningIntent = null;
    }

    void finishTransition() {
      if (!completion.isCompleted) completion.complete();
      if (identical(_intentTransitionCompletion, completion)) {
        _intentTransitionCompletion = null;
      }
    }

    try {
      if (_disposed) {
        return _localFailure(intent, 'coordinator_disposed');
      }
      final restoredPlaybackAfterRecordingPreparation =
          intent == AudioRouteIntentV2.preparingRecording &&
              result.snapshot.intent == AudioRouteIntentV2.playbackOnly &&
              result.snapshot.juce.deviceOpen == true &&
              result.snapshot.juce.activeInputChannels == 0 &&
              (result.snapshot.juce.activeOutputChannels ?? 0) > 0;
      final restoredPlaybackAfterMonitoring =
          intent == AudioRouteIntentV2.monitoring &&
              result.snapshot.intent == AudioRouteIntentV2.playbackOnly &&
              result.snapshot.juce.deviceOpen == true &&
              result.snapshot.juce.audioCallbackAttached == true &&
              result.snapshot.juce.activeInputChannels == 0 &&
              (result.snapshot.juce.activeOutputChannels ?? 0) > 0;
      final restoredPlaybackAfterInputPreparation =
          restoredPlaybackAfterRecordingPreparation ||
              restoredPlaybackAfterMonitoring;
      final stale = result.generation != generation ||
          _latestGeneration != generation ||
          (result.diagnosticCode == 'stale_generation' &&
              !restoredPlaybackAfterInputPreparation);
      if (stale) {
        _setState(AudioRouteCoordinatorStateV2.failed);
        return result.diagnosticCode == 'stale_generation'
            ? result
            : _localFailure(intent, 'stale_generation');
      }
      if (result.succeeded) {
        _intent = intent;
        _setState(AudioRouteCoordinatorStateV2.stable);
      } else if (restoredPlaybackAfterInputPreparation) {
        _intent = AudioRouteIntentV2.playbackOnly;
        _setState(AudioRouteCoordinatorStateV2.stable);
      } else {
        _setState(AudioRouteCoordinatorStateV2.failed);
      }
      return result;
    } finally {
      finishTransition();
      _schedulePendingDrain();
    }
  }

  /// Performs one explicit output-only transition through the same serialized
  /// owner used by system route changes. The optional output is meaningful on
  /// macOS only; mobile platforms remain system-selected.
  Future<AudioRouteTransitionResultV2> selectPlaybackOutput(
    String outputDeviceName,
  ) async {
    final selection = outputDeviceName.trim();
    if (_disposed || !_started || _shutdownCancellation) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'coordinator_disposed',
      );
    }
    if (selection.isEmpty ||
        _interruptionActive ||
        _intent != AudioRouteIntentV2.playbackOnly ||
        _applyInFlight ||
        _intentTransitionInFlight ||
        _pending != null) {
      return _localFailure(AudioRouteIntentV2.playbackOnly, 'route_unstable');
    }

    _applyInFlight = true;
    final generation = _latestGeneration;
    _setState(AudioRouteCoordinatorStateV2.reconfiguring);
    AudioRouteTransitionResultV2 result;
    try {
      result = await _adapter.applyPlaybackRoute(
        generation,
        outputDeviceName: selection,
      );
    } catch (_) {
      result = _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'actual_state_unavailable',
      );
    } finally {
      _applyInFlight = false;
      // A route event can arrive while an explicit apply is settling. Its
      // first timer may fire while this call still owns the adapter, so
      // re-arm the pending drain before inspecting the result.
      _schedulePendingDrain();
    }

    if (_disposed) return result;
    final stale = result.generation != generation ||
        result.diagnosticCode == 'stale_generation' ||
        (_latestGeneration > result.generation && _pending != null);
    if (!stale) {
      final restoredPlayback =
          result.snapshot.intent == AudioRouteIntentV2.playbackOnly &&
              result.snapshot.juce.deviceOpen == true &&
              result.snapshot.juce.activeInputChannels == 0 &&
              (result.snapshot.juce.activeOutputChannels ?? 0) > 0;
      _setState(result.succeeded || restoredPlayback
          ? AudioRouteCoordinatorStateV2.stable
          : AudioRouteCoordinatorStateV2.failed);
      onTransition?.call(result);
    }
    return result;
  }

  /// Validates and stores a macOS recording-input preference without
  /// mutating the active output-only route. A null/empty selection means
  /// follow the system default input.
  Future<AudioRouteTransitionResultV2> selectRecordingInput(
    String? inputDeviceName, {
    String? inputDeviceUID,
    bool retryAfterPlaybackRecovery = false,
  }) async {
    if (_disposed || !_started || _shutdownCancellation) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'coordinator_disposed',
      );
    }
    if (_interruptionActive ||
        _intent != AudioRouteIntentV2.playbackOnly ||
        _applyInFlight ||
        _intentTransitionInFlight ||
        _inputSelectionRecoveryWaiter != null ||
        _pending != null) {
      return _localFailure(AudioRouteIntentV2.playbackOnly, 'route_unstable');
    }

    final generation = _latestGeneration;
    final selection = inputDeviceName?.trim();
    final selectionUID = inputDeviceUID?.trim();
    final recoveryWaiter =
        retryAfterPlaybackRecovery ? _PlaybackRecoveryWaiter(generation) : null;
    _inputSelectionRecoveryWaiter = recoveryWaiter;
    var result = await _applyRecordingInputPreference(
      generation,
      selection,
      selectionUID,
    );

    try {
      if (_disposed) return result;
      final stale = result.generation != generation ||
          result.diagnosticCode == 'stale_generation' ||
          (_latestGeneration != generation &&
              result.diagnosticCode != 'actual_state_unavailable');
      if (stale) {
        return result.diagnosticCode == 'stale_generation'
            ? result
            : _localFailure(
                AudioRouteIntentV2.playbackOnly,
                'stale_generation',
              );
      }
      if (!retryAfterPlaybackRecovery ||
          result.diagnosticCode != 'actual_state_unavailable' ||
          recoveryWaiter == null) {
        return result;
      }

      final recovery = await recoveryWaiter.completion.future.timeout(
        inputSelectionRecoveryDeadline,
        onTimeout: () => null,
      );
      if (recovery == null ||
          !recovery.succeeded ||
          _disposed ||
          _shutdownCancellation ||
          _interruptionActive ||
          _intent != AudioRouteIntentV2.playbackOnly ||
          _state != AudioRouteCoordinatorStateV2.stable ||
          _applyInFlight ||
          _intentTransitionInFlight ||
          _pending != null ||
          _latestGeneration != recovery.generation) {
        return result;
      }

      result = await _applyRecordingInputPreference(
        recovery.generation,
        selection,
        selectionUID,
      );
      if (result.generation != recovery.generation ||
          result.diagnosticCode == 'stale_generation' ||
          _latestGeneration != recovery.generation) {
        return result.diagnosticCode == 'stale_generation'
            ? result
            : _localFailure(
                AudioRouteIntentV2.playbackOnly,
                'stale_generation',
              );
      }
      return result;
    } finally {
      if (identical(_inputSelectionRecoveryWaiter, recoveryWaiter)) {
        _inputSelectionRecoveryWaiter = null;
      }
    }
  }

  Future<AudioRouteTransitionResultV2> _applyRecordingInputPreference(
    int generation,
    String? inputDeviceName,
    String? inputDeviceUID,
  ) async {
    _applyInFlight = true;
    try {
      return await _adapter.applyPlaybackRoute(
        generation,
        inputDeviceName: inputDeviceName,
        inputDeviceUID: inputDeviceUID,
        updateInputPreference: true,
      );
    } catch (_) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'actual_state_unavailable',
      );
    } finally {
      _applyInFlight = false;
      _schedulePendingDrain();
    }
  }

  /// On macOS and iOS, zero follows the current output's sample rate.
  /// Positive values request an explicit rate at the native boundary.
  /// Applies the existing project hardware preferences through the same
  /// serialized playback owner. This command intentionally leaves the
  /// coordinator in [AudioRouteCoordinatorStateV2.stable]: an explicit
  /// settings edit is not an external route change and must preserve the
  /// product's existing playing/paused state and notices.
  Future<AudioRouteTransitionResultV2> configurePlaybackHardware({
    required int preferredSampleRateHz,
    required int preferredBufferFrames,
  }) async {
    if (_disposed || !_started || _shutdownCancellation) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'coordinator_disposed',
      );
    }
    if (preferredSampleRateHz < 0 ||
        preferredBufferFrames <= 0 ||
        _state != AudioRouteCoordinatorStateV2.stable ||
        _interruptionActive ||
        _intent != AudioRouteIntentV2.playbackOnly ||
        _applyInFlight ||
        _intentTransitionInFlight ||
        _pending != null) {
      return _localFailure(AudioRouteIntentV2.playbackOnly, 'route_unstable');
    }

    _applyInFlight = true;
    final generation = _latestGeneration;
    AudioRouteTransitionResultV2 result;
    try {
      result = await _adapter.applyPlaybackRoute(
        generation,
        preferredSampleRateHz: preferredSampleRateHz,
        preferredBufferFrames: preferredBufferFrames,
        updateHardwarePreferences: true,
      );
    } catch (_) {
      result = _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'actual_state_unavailable',
      );
    } finally {
      _applyInFlight = false;
      _schedulePendingDrain();
    }

    if (_disposed) return result;
    final stale = result.generation != generation ||
        result.diagnosticCode == 'stale_generation' ||
        _latestGeneration != generation;
    if (stale) {
      return result.diagnosticCode == 'stale_generation'
          ? result
          : _localFailure(
              AudioRouteIntentV2.playbackOnly,
              'stale_generation',
            );
    }
    return result;
  }

  /// Serializes a playback-only recovery behind an intent transition that was
  /// invalidated by a native route event. A native stale-generation result may
  /// be superseded once when its immutable snapshot proves that the native
  /// route generation advanced during the owned recovery. Native recovery is
  /// responsible for quiescing any incomplete route before returning stale.
  Future<AudioRouteTransitionResultV2>
      recoverPlaybackAfterIntentInvalidation() async {
    final existing = _invalidationRecovery;
    if (existing != null) return existing;
    if (_completedInvalidationRecoveryGeneration == _latestGeneration &&
        _completedInvalidationRecovery != null) {
      return _completedInvalidationRecovery!;
    }

    final recovery = _runPlaybackRecoveryAfterIntentInvalidation();
    _invalidationRecovery = recovery;
    final result = await recovery;
    if (identical(_invalidationRecovery, recovery)) {
      _invalidationRecovery = null;
      _completedInvalidationRecovery = result;
      _completedInvalidationRecoveryGeneration = _latestGeneration;
    }
    return result;
  }

  Future<AudioRouteTransitionResultV2>
      _runPlaybackRecoveryAfterIntentInvalidation() async {
    var recoveryEpisode = _invalidationEpisode;
    final interruptionEnded = _interruptionEndedCompletion;
    if (_interruptionActive && interruptionEnded != null) {
      await interruptionEnded.future;
    }
    final activeTransition = _intentTransitionCompletion;
    if (activeTransition != null) await activeTransition.future;
    if (_disposed || !_started || _shutdownCancellation) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        'coordinator_disposed',
      );
    }
    final attemptedGeneration = _latestGeneration;
    var result = await transitionIntent(AudioRouteIntentV2.playbackOnly);
    if (recoveryEpisode == _invalidationEpisode) {
      final snapshotGeneration = result.snapshot.generation ?? 0;
      final authoritativeGeneration = snapshotGeneration > _latestGeneration
          ? snapshotGeneration
          : _latestGeneration;
      final canSupersedeNativeStalePreflight =
          allowRecoveryGenerationSupersession &&
              result.diagnosticCode == 'stale_generation' &&
              result.transitionId > 0 &&
              authoritativeGeneration > attemptedGeneration &&
              !_disposed &&
              _started &&
              !_shutdownCancellation &&
              !_interruptionActive &&
              _pending == null;
      if (!canSupersedeNativeStalePreflight) return result;

      // Promote only the authoritative generation exposed by native/event
      // facts, then replace that stale request once within the same
      // invalidation episode. All other stale transitions remain rejected.
      _latestGeneration = authoritativeGeneration;
      result = await transitionIntent(AudioRouteIntentV2.playbackOnly);
      return result;
    }

    // An interruption can begin while an older route restoration is already
    // in flight. That stale transition belongs to the older episode. Wait for
    // the new interruption to end, then perform its single playback recovery.
    recoveryEpisode = _invalidationEpisode;
    final supersedingInterruptionEnd = _interruptionEndedCompletion;
    if (_interruptionActive && supersedingInterruptionEnd != null) {
      await supersedingInterruptionEnd.future;
    }
    if (_disposed ||
        !_started ||
        _shutdownCancellation ||
        recoveryEpisode != _invalidationEpisode) {
      return _localFailure(
        AudioRouteIntentV2.playbackOnly,
        _shutdownCancellation ? 'coordinator_disposed' : 'stale_generation',
      );
    }
    return transitionIntent(AudioRouteIntentV2.playbackOnly);
  }

  /// Releases an interruption waiter during editor shutdown without allowing
  /// a late playback reopen to start.
  void cancelPendingRecoveryForShutdown() {
    _shutdownCancellation = true;
    _interruptionActive = false;
    final completion = _interruptionEndedCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  AudioRouteTransitionResultV2 _localFailure(
    AudioRouteIntentV2 intent,
    String code,
  ) {
    return AudioRouteTransitionResultV2(
      status: AudioRouteTransitionStatusV2.failure,
      generation: _latestGeneration,
      transitionId: 0,
      diagnosticCode: code,
      elapsedMs: 0,
      transportWasPlaying: false,
      snapshot: AudioRouteSnapshotV2.fromMap(<String, dynamic>{
        'implementation': 'v2',
        'intent': intent.name,
        'captureConsistency': 'unavailable',
        'unavailableReasons': <String, String>{'coordinator': code},
      }),
    );
  }

  void _setState(AudioRouteCoordinatorStateV2 value) {
    if (_state == value) return;
    _state = value;
    onStateChanged?.call(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPendingRecoveryForShutdown();
    _settlingTimer?.cancel();
    _settlingTimer = null;
    _pending = null;
    final waiter = _inputSelectionRecoveryWaiter;
    if (waiter != null && !waiter.completion.isCompleted) {
      waiter.completion.complete(null);
    }
    _inputSelectionRecoveryWaiter = null;
    await _subscription?.cancel();
    _subscription = null;
    if (_started) await _adapter.stopMonitoring();
  }
}

class _PlaybackRecoveryWaiter {
  _PlaybackRecoveryWaiter(this.afterGeneration);

  final int afterGeneration;
  final Completer<AudioRouteTransitionResultV2?> completion =
      Completer<AudioRouteTransitionResultV2?>();
  int? targetGeneration;
}
