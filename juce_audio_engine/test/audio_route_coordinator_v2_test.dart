import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_coordinator_v2.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

AudioRouteSnapshotV2 _snapshot({
  int? generation,
  int? transitionId,
  bool coordinatorManaged = true,
}) {
  return AudioRouteSnapshotV2.fromMap(<String, dynamic>{
    'capturedAtUtc': '2026-08-08T12:00:00.000Z',
    'implementation': 'v2',
    'generation': generation,
    'transitionId': transitionId,
    'coordinatorManaged': coordinatorManaged,
    'captureConsistency': 'stable',
    'outputs': <Map<String, dynamic>>[
      <String, dynamic>{
        'direction': 'output',
        'nativePortType': '0x626c7565',
        'normalizedKind': 'bluetooth',
        'uid': 'output-$generation',
        'name': 'Test Output',
        'channelCount': 2,
      },
    ],
    'juce': <String, dynamic>{
      'deviceOpen': true,
      'sampleRateHz': 44100.0,
      'bufferFrames': 512,
      'activeInputChannels': 0,
      'activeOutputChannels': 2,
    },
  });
}

AudioRouteChangeEventV2 _event(int generation, String fingerprint) {
  return AudioRouteChangeEventV2(
    generation: generation,
    cause: 'defaultOutputChanged',
    fingerprint: fingerprint,
    transportWasPlaying: true,
    snapshot: _snapshot(generation: generation),
  );
}

AudioRouteTransitionResultV2 _result(
  int generation, {
  AudioRouteTransitionStatusV2 status = AudioRouteTransitionStatusV2.success,
  String code = 'ok',
}) {
  return AudioRouteTransitionResultV2(
    status: status,
    generation: generation,
    transitionId: generation + 100,
    diagnosticCode: code,
    elapsedMs: 12,
    transportWasPlaying: true,
    snapshot: _snapshot(
      generation: generation,
      transitionId: generation + 100,
    ),
  );
}

class _FakeAdapter implements AudioRouteAdapterV2 {
  final controller = StreamController<AudioRouteChangeEventV2>.broadcast();
  final appliedGenerations = <int>[];
  final results = <int, Future<AudioRouteTransitionResultV2>>{};
  var startCount = 0;
  var stopCount = 0;

  @override
  Stream<AudioRouteChangeEventV2> get events => controller.stream;

  @override
  Future<AudioRouteSnapshotV2> startMonitoring() async {
    startCount += 1;
    return _snapshot(generation: 0, transitionId: 0);
  }

  @override
  Future<AudioRouteTransitionResultV2> applyPlaybackRoute(
    int generation,
  ) async {
    appliedGenerations.add(generation);
    return results[generation] ?? _result(generation);
  }

  @override
  Future<void> stopMonitoring() async {
    stopCount += 1;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('starts observation before processing events and stops once', () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );

    final initial = await coordinator.start();
    expect(initial.generation, 0);
    expect(adapter.startCount, 1);

    await coordinator.dispose();
    await coordinator.dispose();
    expect(adapter.stopCount, 1);
  });

  test('ignores duplicate fingerprints and applies once', () async {
    final adapter = _FakeAdapter();
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onTransition: transitions.add,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'same'));
    adapter.controller.add(_event(2, 'same'));
    await _flush();
    await _flush();

    expect(adapter.appliedGenerations, <int>[1]);
    expect(transitions, hasLength(1));
    await coordinator.dispose();
  });

  test('coalesces rapid changes to the newest generation', () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: const Duration(milliseconds: 5),
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'one'));
    adapter.controller.add(_event(2, 'two'));
    adapter.controller.add(_event(3, 'three'));
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(adapter.appliedGenerations, <int>[3]);
    await coordinator.dispose();
  });

  test('never overlaps applies and discards stale completion', () async {
    final adapter = _FakeAdapter();
    final first = Completer<AudioRouteTransitionResultV2>();
    adapter.results[1] = first.future;
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onTransition: transitions.add,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'one'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    adapter.controller.add(_event(2, 'two'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(adapter.appliedGenerations, <int>[1]);

    first.complete(_result(1));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(adapter.appliedGenerations, <int>[1, 2]);
    expect(transitions.map((value) => value.generation), <int>[2]);
    await coordinator.dispose();
  });

  test('reports verified fallback as stable', () async {
    final adapter = _FakeAdapter();
    adapter.results[1] = Future.value(
      _result(
        1,
        status: AudioRouteTransitionStatusV2.fallback,
        code: 'fallback_succeeded',
      ),
    );
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onTransition: transitions.add,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'fallback'));
    await _flush();
    await _flush();

    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    expect(transitions.single.diagnosticCode, 'fallback_succeeded');
    await coordinator.dispose();
  });

  test('enters failed state without retry and disposal drops work', () async {
    final adapter = _FakeAdapter();
    adapter.results[1] = Future.value(
      _result(
        1,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'fallback_failed',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'failure'));
    await _flush();
    await _flush();
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    expect(adapter.appliedGenerations, <int>[1]);

    adapter.controller.add(_event(2, 'disposed'));
    await coordinator.dispose();
    await _flush();
    expect(adapter.appliedGenerations, <int>[1]);
  });
}
