import 'dart:async';

import 'audio_route_v2.dart';

abstract interface class AudioRouteAdapterV2 {
  Stream<AudioRouteChangeEventV2> get events;

  Future<AudioRouteSnapshotV2> startMonitoring();

  Future<AudioRouteTransitionResultV2> applyPlaybackRoute(int generation);

  Future<AudioRouteTransitionResultV2> applyIntent(
    AudioRouteIntentV2 intent,
    int generation,
  );

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
  bool _started = false;
  bool _disposed = false;
  AudioRouteIntentV2 _intent = AudioRouteIntentV2.playbackOnly;
  AudioRouteIntentV2? _transitioningIntent;

  AudioRouteIntentV2 get intent => _intent;

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
    final terminalEvent = event.cause == 'oldDeviceUnavailable' ||
        event.cause == 'audioInterrupted' ||
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
  ) async {
    if (_disposed || !_started) {
      return _localFailure(intent, 'coordinator_disposed');
    }
    if (_applyInFlight || _intentTransitionInFlight || _pending != null) {
      return _localFailure(intent, 'route_unstable');
    }

    _intentTransitionInFlight = true;
    _transitioningIntent = intent;
    final generation = _latestGeneration;
    _setState(intent == AudioRouteIntentV2.playbackOnly
        ? AudioRouteCoordinatorStateV2.reconfiguring
        : AudioRouteCoordinatorStateV2.preparingInput);
    AudioRouteTransitionResultV2 result;
    try {
      result = await _adapter.applyIntent(intent, generation);
    } catch (_) {
      result = _localFailure(intent, 'actual_state_unavailable');
    } finally {
      _intentTransitionInFlight = false;
      _transitioningIntent = null;
    }

    if (_disposed) return _localFailure(intent, 'coordinator_disposed');
    final stale = result.generation != generation ||
        result.diagnosticCode == 'stale_generation' ||
        _latestGeneration != generation;
    if (stale) {
      _setState(AudioRouteCoordinatorStateV2.failed);
      return result.diagnosticCode == 'stale_generation'
          ? result
          : _localFailure(intent, 'stale_generation');
    }
    if (result.succeeded) {
      _intent = intent;
      _setState(AudioRouteCoordinatorStateV2.stable);
    } else if (intent == AudioRouteIntentV2.preparingRecording &&
        result.snapshot.intent == AudioRouteIntentV2.playbackOnly &&
        result.snapshot.juce.deviceOpen == true &&
        result.snapshot.juce.activeInputChannels == 0 &&
        (result.snapshot.juce.activeOutputChannels ?? 0) > 0) {
      _intent = AudioRouteIntentV2.playbackOnly;
      _setState(AudioRouteCoordinatorStateV2.stable);
    } else {
      _setState(AudioRouteCoordinatorStateV2.failed);
    }
    if (_pending != null) {
      _settlingTimer?.cancel();
      _settlingTimer = Timer(settlingDelay, _drain);
    }
    return result;
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
    _settlingTimer?.cancel();
    _settlingTimer = null;
    _pending = null;
    await _subscription?.cancel();
    _subscription = null;
    if (_started) await _adapter.stopMonitoring();
  }
}
