import 'dart:async';

import 'audio_route_v2.dart';

abstract interface class AudioRouteAdapterV2 {
  Stream<AudioRouteChangeEventV2> get events;

  Future<AudioRouteSnapshotV2> startMonitoring();

  Future<AudioRouteTransitionResultV2> applyPlaybackRoute(int generation);

  Future<AudioRouteTransitionResultV2> applyIntent(
      AudioRouteIntentV2 intent, int generation,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard});

  Future<void> stopMonitoring();
}

class AudioRouteCoordinatorV2 {
  AudioRouteCoordinatorV2({
    required AudioRouteAdapterV2 adapter,
    this.settlingDelay = const Duration(milliseconds: 100),
    this.onStateChanged,
    this.onTransition,
    this.onIntentInvalidated,
  }) : _adapter = adapter;

  final AudioRouteAdapterV2 _adapter;
  final Duration settlingDelay;
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

  AudioRouteIntentV2 get intent => _intent;

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

    final terminalEvent = event.cause == 'oldDeviceUnavailable' ||
        event.cause == 'noSuitableRoute';
    if (!terminalEvent &&
        event.fingerprint.isNotEmpty &&
        event.fingerprint == _lastFingerprint) {
      if (_pending != null) _pending = event;
      return;
    }
    _lastFingerprint = event.fingerprint;
    final effectiveIntent = _transitioningIntent ?? _intent;
    if (effectiveIntent != AudioRouteIntentV2.playbackOnly) {
      _pending = null;
      _settlingTimer?.cancel();
      _settlingTimer = null;
      _setState(AudioRouteCoordinatorStateV2.failed);
      onIntentInvalidated?.call(event);
      return;
    }
    _pending = event;
    _setState(AudioRouteCoordinatorStateV2.reconfiguring);
    _settlingTimer?.cancel();
    _settlingTimer = Timer(settlingDelay, _drain);
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
    }

    if (_pending != null) {
      _settlingTimer?.cancel();
      _settlingTimer = Timer(settlingDelay, _drain);
    }
  }

  Future<AudioRouteTransitionResultV2> transitionIntent(
      AudioRouteIntentV2 intent,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard}) async {
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

    if (_disposed) {
      finishTransition();
      return _localFailure(intent, 'coordinator_disposed');
    }
    final restoredPlaybackAfterPreparation =
        intent == AudioRouteIntentV2.preparingRecording &&
            result.snapshot.intent == AudioRouteIntentV2.playbackOnly &&
            result.snapshot.juce.deviceOpen == true &&
            result.snapshot.juce.activeInputChannels == 0 &&
            (result.snapshot.juce.activeOutputChannels ?? 0) > 0;
    final stale = result.generation != generation ||
        _latestGeneration != generation ||
        (result.diagnosticCode == 'stale_generation' &&
            !restoredPlaybackAfterPreparation);
    if (stale) {
      _setState(AudioRouteCoordinatorStateV2.failed);
      finishTransition();
      return result.diagnosticCode == 'stale_generation'
          ? result
          : _localFailure(intent, 'stale_generation');
    }
    if (result.succeeded) {
      _intent = intent;
      _setState(AudioRouteCoordinatorStateV2.stable);
    } else if (restoredPlaybackAfterPreparation) {
      _intent = AudioRouteIntentV2.playbackOnly;
      _setState(AudioRouteCoordinatorStateV2.stable);
    } else {
      _setState(AudioRouteCoordinatorStateV2.failed);
    }
    if (_pending != null) {
      _settlingTimer?.cancel();
      _settlingTimer = Timer(settlingDelay, _drain);
    }
    finishTransition();
    return result;
  }

  /// Serializes a playback-only recovery behind an intent transition that was
  /// invalidated by a native route event. This does not retry: it performs one
  /// transition using the latest observed generation.
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
    final result = await transitionIntent(AudioRouteIntentV2.playbackOnly);
    if (recoveryEpisode == _invalidationEpisode) return result;

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
    await _subscription?.cancel();
    _subscription = null;
    if (_started) await _adapter.stopMonitoring();
  }
}
