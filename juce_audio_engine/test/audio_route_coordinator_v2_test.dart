import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_coordinator_v2.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

AudioRouteSnapshotV2 _snapshot({
  int? generation,
  int? transitionId,
  bool coordinatorManaged = true,
  bool interruptionWasSuspended = false,
}) {
  return AudioRouteSnapshotV2.fromMap(<String, dynamic>{
    'capturedAtUtc': '2026-08-08T12:00:00.000Z',
    'implementation': 'v2',
    'generation': generation,
    'transitionId': transitionId,
    'coordinatorManaged': coordinatorManaged,
    'interruption': <String, dynamic>{
      'phase': interruptionWasSuspended ? 'ended' : 'idle',
      'wasSuspended': interruptionWasSuspended,
      'shouldResumeHint': false,
      'recoveryOutcome': interruptionWasSuspended ? 'pending' : null,
    },
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

AudioRouteChangeEventV2 _event(
  int generation,
  String fingerprint, {
  String cause = 'defaultOutputChanged',
  bool interruptionWasSuspended = false,
  bool requiresReconfiguration = false,
}) {
  return AudioRouteChangeEventV2(
    generation: generation,
    cause: cause,
    fingerprint: fingerprint,
    transportWasPlaying: true,
    requiresReconfiguration: requiresReconfiguration,
    snapshot: _snapshot(
      generation: generation,
      interruptionWasSuspended: interruptionWasSuspended,
    ),
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
  final appliedIntents = <AudioRouteIntentV2>[];
  final appliedOperations = <AudioRouteIntentOperationV2>[];
  final results = <int, Future<AudioRouteTransitionResultV2>>{};
  final intentResults =
      <AudioRouteIntentV2, Future<AudioRouteTransitionResultV2>>{};
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
  Future<AudioRouteTransitionResultV2> applyIntent(
      AudioRouteIntentV2 intent, int generation,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard}) async {
    appliedIntents.add(intent);
    appliedOperations.add(operation);
    return intentResults[intent] ?? _result(generation);
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

    expect(adapter.appliedGenerations, <int>[2]);
    expect(transitions, hasLength(1));
    await coordinator.dispose();
  });

  test('same-fingerprint playback events are coalesced regardless of cause',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'same'));
    await _flush();
    await _flush();
    adapter.controller.add(_event(
      2,
      'same',
      cause: 'oldDeviceUnavailable',
    ));
    await _flush();
    await _flush();

    expect(adapter.appliedGenerations, <int>[1]);
    await coordinator.dispose();
  });

  test('explicit native reconfiguration bypasses playback fingerprint dedupe',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'same'));
    await _flush();
    await _flush();
    adapter.controller.add(
      _event(
        2,
        'same',
        cause: 'nativeStreamDisconnected',
        requiresReconfiguration: true,
      ),
    );
    await _flush();
    await _flush();

    expect(adapter.appliedGenerations, <int>[1, 2]);
    await coordinator.dispose();
  });

  test('same-fingerprint inventory change invalidates built-in recording',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();

    adapter.controller.add(_event(1, 'speaker'));
    await _flush();
    await _flush();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(
      _event(2, 'speaker', cause: 'deviceInventoryChanged'),
    );
    await _flush();

    expect(invalidated, hasLength(1));
    expect(invalidated.single.cause, 'deviceInventoryChanged');
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('recording ownership persists until playback-only commits', () async {
    final adapter = _FakeAdapter();
    final stopping = Completer<AudioRouteTransitionResultV2>();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);
    adapter.intentResults[AudioRouteIntentV2.playbackOnly] = stopping.future;

    final stop = coordinator.transitionIntent(AudioRouteIntentV2.playbackOnly);
    await _flush();
    adapter.controller.add(
      _event(1, 'speaker', cause: 'deviceRemoved'),
    );
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedGenerations, isEmpty);
    stopping.complete(_result(0));
    expect((await stop).diagnosticCode, 'stale_generation');

    adapter.intentResults[AudioRouteIntentV2.playbackOnly] =
        Future.value(_result(1));
    final recovery = await coordinator.recoverPlaybackAfterIntentInvalidation();
    expect(recovery.succeeded, isTrue);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    await coordinator.dispose();
  });

  test('stale playback intent completion rearms a consumed pending drain',
      () async {
    final adapter = _FakeAdapter();
    final transition = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.playbackOnly] = transition.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final playbackIntent =
        coordinator.transitionIntent(AudioRouteIntentV2.playbackOnly);
    await _flush();
    adapter.controller.add(_event(1, 'headset'));
    await _flush();
    expect(adapter.appliedGenerations, isEmpty);

    transition.complete(_result(0));
    expect((await playbackIntent).diagnosticCode, 'stale_generation');
    await _flush();
    await _flush();

    expect(adapter.appliedGenerations, <int>[1]);
    await coordinator.dispose();
  });

  test('same-fingerprint native stream loss invalidates active recording',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(_event(
      1,
      'same',
      cause: 'nativeStreamDisconnected',
    ));
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('interruption recovery waits for ended and performs one intent',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(
      _event(1, 'same', cause: 'audioInterruptionBegan'),
    );
    await _flush();
    final recovery = coordinator.recoverPlaybackAfterIntentInvalidation();
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.preparingRecording,
      AudioRouteIntentV2.recording,
    ]);

    adapter.controller.add(
      _event(2, 'same', cause: 'audioInterruptionEnded'),
    );
    final result = await recovery;
    expect(
      result.succeeded,
      isTrue,
      reason: '${result.diagnosticCode}: ${adapter.appliedIntents}',
    );
    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.preparingRecording,
      AudioRouteIntentV2.recording,
      AudioRouteIntentV2.playbackOnly,
    ]);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('interruption blocks intent transitions until recovery', () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    adapter.controller.add(
      _event(1, 'speaker', cause: 'audioInterruptionBegan'),
    );
    await _flush();

    final blocked = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );
    expect(blocked.succeeded, isFalse);
    expect(blocked.diagnosticCode, 'route_unstable');
    expect(adapter.appliedIntents, isEmpty);

    final recovery = coordinator.recoverPlaybackAfterIntentInvalidation();
    adapter.controller.add(
      _event(2, 'speaker', cause: 'audioInterruptionEnded'),
    );
    expect((await recovery).succeeded, isTrue);
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[AudioRouteIntentV2.playbackOnly],
    );
    await coordinator.dispose();
  });

  test('suspended end-only interruption recovers and duplicates are ignored',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();

    adapter.controller.add(
      _event(1, 'speaker', cause: 'audioInterruptionEnded'),
    );
    await _flush();
    adapter.controller.add(
      _event(2, 'speaker', cause: 'audioInterruptionEnded'),
    );
    await _flush();

    expect(invalidated, hasLength(1));
    final first = coordinator.recoverPlaybackAfterIntentInvalidation();
    final second = coordinator.recoverPlaybackAfterIntentInvalidation();
    expect((await first).succeeded, isTrue);
    expect((await second).succeeded, isTrue);
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[AudioRouteIntentV2.playbackOnly],
    );
    await coordinator.dispose();
  });

  test('separate suspended episodes recover at the same output identity',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();

    for (var generation = 1; generation <= 2; generation += 1) {
      adapter.controller.add(
        _event(
          generation,
          'speaker',
          cause: 'audioInterruptionEnded',
          interruptionWasSuspended: true,
        ),
      );
      await _flush();
      expect(
        (await coordinator.recoverPlaybackAfterIntentInvalidation()).succeeded,
        isTrue,
      );
    }

    expect(invalidated, hasLength(2));
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[
        AudioRouteIntentV2.playbackOnly,
        AudioRouteIntentV2.playbackOnly,
      ],
    );
    await coordinator.dispose();
  });

  test('separate local foreground episodes never reuse a prior reopen',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    for (var episode = 0; episode < 2; episode += 1) {
      coordinator.beginLocalInvalidationEpisode();
      expect(
        (await coordinator.recoverPlaybackAfterIntentInvalidation()).succeeded,
        isTrue,
      );
    }

    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[
        AudioRouteIntentV2.playbackOnly,
        AudioRouteIntentV2.playbackOnly,
      ],
    );
    await coordinator.dispose();
  });

  test('shutdown releases a missing interruption end without reopening',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    adapter.controller.add(
      _event(1, 'speaker', cause: 'audioInterruptionBegan'),
    );
    await _flush();

    final recovery = coordinator.recoverPlaybackAfterIntentInvalidation();
    coordinator.cancelPendingRecoveryForShutdown();
    final result = await recovery;

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'coordinator_disposed');
    expect(adapter.appliedIntents, isEmpty);
    await coordinator.dispose();
  });

  test('interruption supersedes an in-flight route restoration once', () async {
    final adapter = _FakeAdapter();
    final firstRestoration = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.playbackOnly] =
        firstRestoration.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);

    adapter.controller.add(
      _event(1, 'speaker', cause: 'oldDeviceUnavailable'),
    );
    await _flush();
    final recovery = coordinator.recoverPlaybackAfterIntentInvalidation();
    await _flush();

    adapter.controller.add(
      _event(2, 'speaker', cause: 'audioInterruptionBegan'),
    );
    adapter.controller.add(
      _event(3, 'speaker', cause: 'audioInterruptionEnded'),
    );
    await _flush();
    adapter.intentResults[AudioRouteIntentV2.playbackOnly] =
        Future.value(_result(3));
    firstRestoration.complete(_result(1));

    final result = await recovery;
    expect(
      result.succeeded,
      isTrue,
      reason: '${result.diagnosticCode}: ${adapter.appliedIntents}',
    );
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[
        AudioRouteIntentV2.preparingRecording,
        AudioRouteIntentV2.playbackOnly,
        AudioRouteIntentV2.playbackOnly,
      ],
    );
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
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

  test('serializes recording intents through the existing coordinator',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final preparing = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );
    final recording = await coordinator.transitionIntent(
      AudioRouteIntentV2.recording,
    );
    final playback = await coordinator.transitionIntent(
      AudioRouteIntentV2.playbackOnly,
    );

    expect(preparing.succeeded, isTrue);
    expect(recording.succeeded, isTrue);
    expect(playback.succeeded, isTrue);
    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.preparingRecording,
      AudioRouteIntentV2.recording,
      AudioRouteIntentV2.playbackOnly,
    ]);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('forwards the private system-selected probe on the existing intent',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
      operation: AudioRouteIntentOperationV2.systemSelectedProbe,
    );

    expect(result.succeeded, isTrue);
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[AudioRouteIntentV2.preparingRecording],
    );
    expect(adapter.appliedOperations, <AudioRouteIntentOperationV2>[
      AudioRouteIntentOperationV2.systemSelectedProbe,
    ]);
    await coordinator.dispose();
  });

  test('forwards system-selected recording without adding coordinator state',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
      operation: AudioRouteIntentOperationV2.systemSelectedRecording,
    );

    expect(result.succeeded, isTrue);
    expect(
      adapter.appliedOperations,
      <AudioRouteIntentOperationV2>[
        AudioRouteIntentOperationV2.systemSelectedRecording,
      ],
    );
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    expect(coordinator.intent, AudioRouteIntentV2.preparingRecording);
    await coordinator.dispose();
  });

  test('blocks route readiness until recording verification completes',
      () async {
    final adapter = _FakeAdapter();
    final recording = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.recording] = recording.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);

    final transition = coordinator.transitionIntent(
      AudioRouteIntentV2.recording,
    );
    await _flush();
    expect(coordinator.state, AudioRouteCoordinatorStateV2.preparingInput);

    recording.complete(_result(0));
    expect((await transition).succeeded, isTrue);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('route change invalidates recording without applying playback route',
      () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(_event(1, 'changed-during-recording'));
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('route change also invalidates an in-flight input preparation',
      () async {
    final adapter = _FakeAdapter();
    final preparing = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.preparingRecording] =
        preparing.future;
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();

    final transition = coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );
    await _flush();
    adapter.controller.add(_event(1, 'changed-during-preparation'));
    await _flush();
    preparing.complete(_result(0));
    final result = await transition;

    expect(invalidated, hasLength(1));
    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'stale_generation');
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('serializes one playback recovery after invalidated preparation',
      () async {
    final adapter = _FakeAdapter();
    final preparing = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.preparingRecording] =
        preparing.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final preparation = coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );
    await _flush();
    adapter.controller.add(
      _event(
        1,
        'speaker-after-disconnect',
        cause: 'oldDeviceUnavailable',
      ),
    );
    await _flush();

    final recovery = coordinator.recoverPlaybackAfterIntentInvalidation();
    await _flush();
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[AudioRouteIntentV2.preparingRecording],
    );

    preparing.complete(_result(0));
    expect((await preparation).diagnosticCode, 'stale_generation');
    final recoveryResult = await recovery;

    expect(recoveryResult.succeeded, isTrue);
    expect(recoveryResult.generation, 1);
    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.preparingRecording,
      AudioRouteIntentV2.playbackOnly,
    ]);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('recording invalidation performs only the requested recovery attempt',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(
      _event(1, 'speaker', cause: 'oldDeviceUnavailable'),
    );
    await _flush();
    final result = await coordinator.recoverPlaybackAfterIntentInvalidation();

    expect(result.succeeded, isTrue);
    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.preparingRecording,
      AudioRouteIntentV2.recording,
      AudioRouteIntentV2.playbackOnly,
    ]);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('recording route-change causes share one serialized recovery contract',
      () async {
    for (final cause in <String>[
      'oldDeviceUnavailable',
      'routeConfigurationChanged',
      'noSuitableRoute',
      'unrelatedRoute',
    ]) {
      final adapter = _FakeAdapter();
      final coordinator = AudioRouteCoordinatorV2(
        adapter: adapter,
        settlingDelay: Duration.zero,
      );
      await coordinator.start();
      await coordinator.transitionIntent(
        AudioRouteIntentV2.preparingRecording,
      );

      adapter.controller.add(_event(1, 'replacement-$cause', cause: cause));
      await _flush();
      final result = await coordinator.recoverPlaybackAfterIntentInvalidation();

      expect(result.succeeded, isTrue, reason: cause);
      expect(
        adapter.appliedIntents,
        <AudioRouteIntentV2>[
          AudioRouteIntentV2.preparingRecording,
          AudioRouteIntentV2.playbackOnly,
        ],
        reason: cause,
      );
      expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
      await coordinator.dispose();
    }
  });

  test('failed input preparation with verified cleanup keeps playback usable',
      () async {
    final adapter = _FakeAdapter();
    adapter.intentResults[AudioRouteIntentV2.preparingRecording] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'no_input',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );

    expect(result.succeeded, isFalse);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('cancelled input preparation accepts verified playback cleanup',
      () async {
    final adapter = _FakeAdapter();
    adapter.intentResults[AudioRouteIntentV2.preparingRecording] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'stale_generation',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );

    expect(result.succeeded, isFalse);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });
}
