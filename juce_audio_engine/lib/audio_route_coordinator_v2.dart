import 'dart:async';

import 'audio_route_v2.dart';

abstract interface class AudioRouteAdapterV2 {
  Stream<AudioRouteChangeEventV2> get events;

  Future<AudioRouteSnapshotV2> startMonitoring();

  Future<AudioRouteTransitionResultV2> applyPlaybackRoute(int generation);

  Future<void> stopMonitoring();
}

class AudioRouteCoordinatorV2 {
  AudioRouteCoordinatorV2({
    required AudioRouteAdapterV2 adapter,
    this.settlingDelay = const Duration(milliseconds: 100),
    this.onStateChanged,
    this.onTransition,
  }) : _adapter = adapter;

  final AudioRouteAdapterV2 _adapter;
  final Duration settlingDelay;
  final void Function(AudioRouteCoordinatorStateV2 state)? onStateChanged;
  final void Function(AudioRouteTransitionResultV2 result)? onTransition;

  AudioRouteCoordinatorStateV2 _state = AudioRouteCoordinatorStateV2.stable;
  AudioRouteCoordinatorStateV2 get state => _state;

  StreamSubscription<AudioRouteChangeEventV2>? _subscription;
  Timer? _settlingTimer;
  AudioRouteChangeEventV2? _pending;
  String? _lastFingerprint;
  int _latestGeneration = 0;
  bool _applyInFlight = false;
  bool _started = false;
  bool _disposed = false;

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
    if (event.fingerprint.isNotEmpty && event.fingerprint == _lastFingerprint) {
      return;
    }
    _latestGeneration = event.generation;
    _lastFingerprint = event.fingerprint;
    _pending = event;
    _setState(AudioRouteCoordinatorStateV2.reconfiguring);
    _settlingTimer?.cancel();
    _settlingTimer = Timer(settlingDelay, _drain);
  }

  Future<void> _drain() async {
    _settlingTimer = null;
    if (_disposed || _applyInFlight) return;
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
        _latestGeneration > result.generation;
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
