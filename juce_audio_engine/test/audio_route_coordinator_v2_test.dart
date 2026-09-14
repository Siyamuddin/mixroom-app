import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_coordinator_v2.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

AudioRouteSnapshotV2 _snapshot({
  int? generation,
  int? transitionId,
  bool coordinatorManaged = true,
  bool interruptionWasSuspended = false,
  AudioRouteIntentV2 intent = AudioRouteIntentV2.playbackOnly,
  bool deviceOpen = true,
  bool audioCallbackAttached = true,
  int activeInputChannels = 0,
  int activeOutputChannels = 2,
}) {
  return AudioRouteSnapshotV2.fromMap(<String, dynamic>{
    'capturedAtUtc': '2026-08-08T12:00:00.000Z',
    'implementation': 'v2',
    'generation': generation,
    'transitionId': transitionId,
    'coordinatorManaged': coordinatorManaged,
    'intent': intent.name,
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
      'deviceOpen': deviceOpen,
      'audioCallbackAttached': audioCallbackAttached,
      'sampleRateHz': 44100.0,
      'bufferFrames': 512,
      'activeInputChannels': activeInputChannels,
      'activeOutputChannels': activeOutputChannels,
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
  AudioRouteSnapshotV2? snapshot,
}) {
  return AudioRouteTransitionResultV2(
    status: status,
    generation: generation,
    transitionId: generation + 100,
    diagnosticCode: code,
    elapsedMs: 12,
    transportWasPlaying: true,
    snapshot: snapshot ??
        _snapshot(
          generation: generation,
          transitionId: generation + 100,
        ),
  );
}

class _FakeAdapter implements AudioRouteAdapterV2 {
  final controller = StreamController<AudioRouteChangeEventV2>.broadcast();
  final appliedGenerations = <int>[];
  final appliedOutputNames = <String?>[];
  final appliedInputNames = <String?>[];
  final appliedInputUIDs = <String?>[];
  final inputPreferenceUpdates = <bool>[];
  final preferredSampleRates = <int?>[];
  final preferredBufferFrames = <int?>[];
  final hardwarePreferenceUpdates = <bool>[];
  final queuedResults = <Future<AudioRouteTransitionResultV2>>[];
  final appliedIntents = <AudioRouteIntentV2>[];
  final appliedIntentGenerations = <int>[];
  final appliedOperations = <AudioRouteIntentOperationV2>[];
  final appliedRecordingChannelStarts = <int?>[];
  final appliedRecordingChannelCounts = <int?>[];
  final appliedMonitoringTargetRows = <int?>[];
  final results = <int, Future<AudioRouteTransitionResultV2>>{};
  final intentResults =
      <AudioRouteIntentV2, Future<AudioRouteTransitionResultV2>>{};
  final intentResultsByGeneration =
      <int, Future<AudioRouteTransitionResultV2>>{};
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
    int generation, {
    String? outputDeviceName,
    String? inputDeviceName,
    String? inputDeviceUID,
    bool updateInputPreference = false,
    int? preferredSampleRateHz,
    int? preferredBufferFrames,
    bool updateHardwarePreferences = false,
  }) async {
    appliedGenerations.add(generation);
    appliedOutputNames.add(outputDeviceName);
    appliedInputNames.add(inputDeviceName);
    appliedInputUIDs.add(inputDeviceUID);
    inputPreferenceUpdates.add(updateInputPreference);
    preferredSampleRates.add(preferredSampleRateHz);
    this.preferredBufferFrames.add(preferredBufferFrames);
    hardwarePreferenceUpdates.add(updateHardwarePreferences);
    if (queuedResults.isNotEmpty) return queuedResults.removeAt(0);
    return results[generation] ?? _result(generation);
  }

  @override
  Future<AudioRouteTransitionResultV2> applyIntent(
      AudioRouteIntentV2 intent, int generation,
      {AudioRouteIntentOperationV2 operation =
          AudioRouteIntentOperationV2.standard,
      int? recordingChannelStart,
      int? recordingChannelCount,
      int? monitoringTargetRow}) async {
    appliedIntents.add(intent);
    appliedIntentGenerations.add(generation);
    appliedOperations.add(operation);
    appliedRecordingChannelStarts.add(recordingChannelStart);
    appliedRecordingChannelCounts.add(recordingChannelCount);
    appliedMonitoringTargetRows.add(monitoringTargetRow);
    return intentResultsByGeneration[generation] ??
        intentResults[intent] ??
        _result(generation);
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

  test('serializes an explicit playback output through the route owner',
      () async {
    final adapter = _FakeAdapter();
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onTransition: transitions.add,
    );
    await coordinator.start();

    final result = await coordinator.selectPlaybackOutput('Mac Speakers');

    expect(result.succeeded, isTrue);
    expect(adapter.appliedGenerations, <int>[0]);
    expect(adapter.appliedOutputNames, <String?>['Mac Speakers']);
    expect(transitions, hasLength(1));
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('explicit output selection cannot overlap input lifecycle ownership',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);

    final result = await coordinator.selectPlaybackOutput('Mac Speakers');

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'route_unstable');
    expect(adapter.appliedOutputNames, isEmpty);
    await coordinator.dispose();
  });

  test('rapid explicit output selections never overlap', () async {
    final adapter = _FakeAdapter();
    final firstResult = Completer<AudioRouteTransitionResultV2>();
    adapter.results[0] = firstResult.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final first = coordinator.selectPlaybackOutput('Bluetooth Output');
    await Future<void>.delayed(Duration.zero);
    final second = await coordinator.selectPlaybackOutput('Mac Speakers');
    firstResult.complete(_result(0));
    final completedFirst = await first;

    expect(completedFirst.succeeded, isTrue);
    expect(second.succeeded, isFalse);
    expect(second.diagnosticCode, 'route_unstable');
    expect(adapter.appliedOutputNames, <String?>['Bluetooth Output']);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('failed output selection with verified playback remains stable',
      () async {
    final adapter = _FakeAdapter();
    adapter.results[0] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'output_selection_unavailable',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.selectPlaybackOutput('Missing Output');

    expect(result.succeeded, isFalse);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('serializes input preference without reconfiguring playback', () async {
    final adapter = _FakeAdapter();
    final states = <AudioRouteCoordinatorStateV2>[];
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onStateChanged: states.add,
      onTransition: transitions.add,
    );
    await coordinator.start();
    states.clear();

    final result = await coordinator.selectRecordingInput('Mac Microphone');

    expect(result.succeeded, isTrue);
    expect(adapter.appliedInputNames, <String?>['Mac Microphone']);
    expect(adapter.appliedInputUIDs, <String?>[null]);
    expect(adapter.inputPreferenceUpdates, <bool>[true]);
    expect(adapter.appliedOutputNames, <String?>[null]);
    expect(states, isEmpty);
    expect(transitions, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('system-default input clears preference through the same owner',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.selectRecordingInput(null);

    expect(result.succeeded, isTrue);
    expect(adapter.appliedInputNames, <String?>[null]);
    expect(adapter.appliedInputUIDs, <String?>[null]);
    expect(adapter.inputPreferenceUpdates, <bool>[true]);
    await coordinator.dispose();
  });

  test('retries input preference once after proven playback recovery',
      () async {
    final adapter = _FakeAdapter();
    adapter.results[0] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'actual_state_unavailable',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final selection = coordinator.selectRecordingInput(
      'Mac Microphone',
      inputDeviceUID: 'coreaudio-input-42',
      retryAfterPlaybackRecovery: true,
    );
    await _flush();
    adapter.controller.add(
      _event(1, 'recovered', requiresReconfiguration: true),
    );

    final result = await selection;
    expect(result.succeeded, isTrue);
    expect(adapter.appliedGenerations, <int>[0, 1, 1]);
    expect(
      adapter.appliedInputNames,
      <String?>['Mac Microphone', null, 'Mac Microphone'],
    );
    expect(
      adapter.appliedInputUIDs,
      <String?>['coreaudio-input-42', null, 'coreaudio-input-42'],
    );
    expect(adapter.inputPreferenceUpdates, <bool>[true, false, true]);
    await coordinator.dispose();
  });

  test('does not retry input preference when playback recovery fails',
      () async {
    final adapter = _FakeAdapter();
    adapter.results[0] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'actual_state_unavailable',
      ),
    );
    adapter.results[1] = Future.value(
      _result(
        1,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'actual_state_unavailable',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final selection = coordinator.selectRecordingInput(
      'Mac Microphone',
      retryAfterPlaybackRecovery: true,
    );
    await _flush();
    adapter.controller.add(
      _event(1, 'failed-recovery', requiresReconfiguration: true),
    );

    final result = await selection;
    expect(result.succeeded, isFalse);
    expect(adapter.appliedGenerations, <int>[0, 1]);
    expect(adapter.inputPreferenceUpdates, <bool>[true, false]);
    await coordinator.dispose();
  });

  test('does not retry input preference without a recovery event', () async {
    final adapter = _FakeAdapter();
    adapter.results[0] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'actual_state_unavailable',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      inputSelectionRecoveryDeadline: const Duration(milliseconds: 1),
    );
    await coordinator.start();

    final result = await coordinator.selectRecordingInput(
      'Mac Microphone',
      retryAfterPlaybackRecovery: true,
    );

    expect(result.succeeded, isFalse);
    expect(adapter.appliedGenerations, <int>[0]);
    expect(adapter.inputPreferenceUpdates, <bool>[true]);
    await coordinator.dispose();
  });

  test('rejects a retry made stale by another route generation', () async {
    final adapter = _FakeAdapter();
    final retryResult = Completer<AudioRouteTransitionResultV2>();
    adapter.queuedResults.addAll(<Future<AudioRouteTransitionResultV2>>[
      Future.value(
        _result(
          0,
          status: AudioRouteTransitionStatusV2.failure,
          code: 'actual_state_unavailable',
        ),
      ),
      Future.value(_result(1)),
      retryResult.future,
    ]);
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final selection = coordinator.selectRecordingInput(
      'Mac Microphone',
      retryAfterPlaybackRecovery: true,
    );
    await _flush();
    adapter.controller.add(
      _event(1, 'first-recovery', requiresReconfiguration: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    adapter.controller.add(
      _event(2, 'newer-route', requiresReconfiguration: true),
    );
    retryResult.complete(_result(1));

    final result = await selection;
    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'stale_generation');
    expect(adapter.appliedGenerations.take(3), <int>[0, 1, 1]);
    await coordinator.dispose();
  });

  test('does not retry a non-recovery input validation failure', () async {
    final adapter = _FakeAdapter();
    adapter.results[0] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'input_selection_unavailable',
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.selectRecordingInput(
      'Missing Microphone',
      retryAfterPlaybackRecovery: true,
    );

    expect(result.succeeded, isFalse);
    expect(adapter.appliedGenerations, <int>[0]);
    expect(adapter.inputPreferenceUpdates, <bool>[true]);
    await coordinator.dispose();
  });

  test('input preference cannot overlap recording lifecycle ownership',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);

    final result = await coordinator.selectRecordingInput('Mac Microphone');

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'route_unstable');
    expect(adapter.inputPreferenceUpdates, isEmpty);
    await coordinator.dispose();
  });

  test('hardware settings use the stable serialized playback owner', () async {
    final adapter = _FakeAdapter();
    final states = <AudioRouteCoordinatorStateV2>[];
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onStateChanged: states.add,
      onTransition: transitions.add,
    );
    await coordinator.start();
    states.clear();

    final result = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 96000,
      preferredBufferFrames: 128,
    );

    expect(result.succeeded, isTrue);
    expect(adapter.preferredSampleRates, <int?>[96000]);
    expect(adapter.preferredBufferFrames, <int?>[128]);
    expect(adapter.hardwarePreferenceUpdates, <bool>[true]);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    expect(states, isEmpty);
    expect(transitions, isEmpty);
    await coordinator.dispose();
  });

  test('automatic sample rate is serialized and forwarded without a default',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(adapter: adapter);
    await coordinator.start();
    final result = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 0,
      preferredBufferFrames: 512,
    );
    expect(result.succeeded, isTrue);
    expect(adapter.preferredSampleRates, <int?>[0]);
    expect(adapter.hardwarePreferenceUpdates, <bool>[true]);
    await coordinator.dispose();
  });

  test('negative rates are rejected without invoking native settings',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(adapter: adapter);
    await coordinator.start();
    final result = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: -1,
      preferredBufferFrames: 512,
    );
    expect(result.succeeded, isFalse);
    expect(adapter.hardwarePreferenceUpdates, isEmpty);
    await coordinator.dispose();
  });

  test(
      'failed automatic settings preserve native recovery result without a retry',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(adapter: adapter);
    await coordinator.start();
    final recovered = _result(0, status: AudioRouteTransitionStatusV2.failure);
    adapter.queuedResults.add(Future.value(recovered));
    final result = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 0,
      preferredBufferFrames: 512,
    );
    expect(result, same(recovered));
    expect(adapter.preferredSampleRates, [0]);
    await coordinator.dispose();
  });

  test('hardware settings cannot overlap an intent transition', () async {
    final adapter = _FakeAdapter();
    final preparing = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.preparingRecording] =
        preparing.future;
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final transition = coordinator.transitionIntent(
      AudioRouteIntentV2.preparingRecording,
    );
    await _flush();
    final settings = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 48000,
      preferredBufferFrames: 512,
    );

    expect(settings.succeeded, isFalse);
    expect(settings.diagnosticCode, 'route_unstable');
    expect(adapter.hardwarePreferenceUpdates, isEmpty);
    preparing.complete(_result(0));
    await transition;
    await coordinator.dispose();
  });

  test('hardware settings always drain a route event that makes them stale',
      () async {
    final adapter = _FakeAdapter();
    final settingsResult = Completer<AudioRouteTransitionResultV2>();
    adapter.results[0] = settingsResult.future;
    final transitions = <AudioRouteTransitionResultV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onTransition: transitions.add,
    );
    await coordinator.start();

    final settings = coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 96000,
      preferredBufferFrames: 128,
    );
    await _flush();
    adapter.controller.add(
      _event(1, 'new-output', requiresReconfiguration: true),
    );
    await _flush();
    await _flush();

    settingsResult.complete(_result(0));
    final staleSettings = await settings;
    await _flush();
    await _flush();

    expect(staleSettings.succeeded, isFalse);
    expect(staleSettings.diagnosticCode, 'stale_generation');
    expect(adapter.appliedGenerations, <int>[0, 1]);
    expect(adapter.hardwarePreferenceUpdates, <bool>[true, false]);
    expect(transitions.map((result) => result.generation), <int>[1]);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
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

  test('serializes monitoring ownership through recording and playback',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    expect(
      (await coordinator.transitionIntent(AudioRouteIntentV2.monitoring))
          .succeeded,
      isTrue,
    );
    expect(coordinator.intent, AudioRouteIntentV2.monitoring);
    expect(
      (await coordinator.transitionIntent(AudioRouteIntentV2.recording))
          .succeeded,
      isTrue,
    );
    expect(
      (await coordinator.transitionIntent(AudioRouteIntentV2.monitoring))
          .succeeded,
      isTrue,
    );
    expect(
      (await coordinator.transitionIntent(AudioRouteIntentV2.playbackOnly))
          .succeeded,
      isTrue,
    );

    expect(adapter.appliedIntents, <AudioRouteIntentV2>[
      AudioRouteIntentV2.monitoring,
      AudioRouteIntentV2.recording,
      AudioRouteIntentV2.monitoring,
      AudioRouteIntentV2.playbackOnly,
    ]);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('forwards the Android monitoring operation and target unchanged',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    await coordinator.transitionIntent(
      AudioRouteIntentV2.monitoring,
      operation: AudioRouteIntentOperationV2.systemSelectedMonitoring,
      recordingChannelStart: 2,
      recordingChannelCount: 2,
      monitoringTargetRow: 4,
    );

    expect(adapter.appliedOperations, <AudioRouteIntentOperationV2>[
      AudioRouteIntentOperationV2.systemSelectedMonitoring,
    ]);
    expect(adapter.appliedRecordingChannelStarts, <int?>[2]);
    expect(adapter.appliedRecordingChannelCounts, <int?>[2]);
    expect(adapter.appliedMonitoringTargetRows, <int?>[4]);
    await coordinator.dispose();
  });

  test('monitoring ownership blocks device and hardware changes', () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.monitoring);

    final output = await coordinator.selectPlaybackOutput('Mac Speakers');
    final input = await coordinator.selectRecordingInput('Mac Microphone');
    final hardware = await coordinator.configurePlaybackHardware(
      preferredSampleRateHz: 48000,
      preferredBufferFrames: 256,
    );

    for (final result in <AudioRouteTransitionResultV2>[
      output,
      input,
      hardware,
    ]) {
      expect(result.succeeded, isFalse);
      expect(result.diagnosticCode, 'route_unstable');
    }
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.intent, AudioRouteIntentV2.monitoring);
    await coordinator.dispose();
  });

  test(
      'repeated capture returns to monitoring without playback reconfiguration',
      () async {
    final adapter = _FakeAdapter();
    final coordinator =
        AudioRouteCoordinatorV2(adapter: adapter, settlingDelay: Duration.zero);
    await coordinator.start();
    Future<void> monitor() async {
      final result = await coordinator.transitionIntent(
        AudioRouteIntentV2.monitoring,
        operation: AudioRouteIntentOperationV2.systemSelectedMonitoring,
        recordingChannelStart: 2,
        recordingChannelCount: 2,
        monitoringTargetRow: 3,
      );
      expect(result.succeeded, isTrue);
      expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    }

    await monitor();
    for (var take = 0; take < 3; take++) {
      expect(
          (await coordinator.transitionIntent(AudioRouteIntentV2.recording))
              .succeeded,
          isTrue);
      await monitor();
      expect(coordinator.intent, AudioRouteIntentV2.monitoring);
    }
    expect(adapter.appliedGenerations, isEmpty);
    expect(
        adapter.appliedIntents
            .where((intent) => intent == AudioRouteIntentV2.playbackOnly),
        isEmpty);
    expect(
        adapter.appliedMonitoringTargetRows.whereType<int>(), everyElement(3));
    expect(adapter.appliedRecordingChannelStarts.whereType<int>(),
        everyElement(2));
    await coordinator.dispose();
  });

  test('route change invalidates monitoring exactly once', () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.monitoring);

    adapter.controller.add(_event(1, 'changed-during-monitoring'));
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('interruption invalidates monitoring exactly once', () async {
    final adapter = _FakeAdapter();
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.monitoring);

    adapter.controller.add(
      _event(1, 'interrupted', cause: 'audioInterruptionBegan'),
    );
    await _flush();
    adapter.controller.add(
      _event(2, 'interrupted-again', cause: 'audioInterruptionBegan'),
    );
    await _flush();

    expect(invalidated, hasLength(1));
    expect(adapter.appliedGenerations, isEmpty);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.reconfiguring);
    await coordinator.dispose();
  });

  test('stale monitoring cannot commit or overlap another transition',
      () async {
    final adapter = _FakeAdapter();
    final monitoring = Completer<AudioRouteTransitionResultV2>();
    adapter.intentResults[AudioRouteIntentV2.monitoring] = monitoring.future;
    final invalidated = <AudioRouteChangeEventV2>[];
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      onIntentInvalidated: invalidated.add,
    );
    await coordinator.start();

    final transition =
        coordinator.transitionIntent(AudioRouteIntentV2.monitoring);
    await _flush();
    final overlap = await coordinator.transitionIntent(
      AudioRouteIntentV2.playbackOnly,
    );
    expect(overlap.succeeded, isFalse);
    expect(overlap.diagnosticCode, 'route_unstable');

    adapter.controller.add(_event(1, 'changed-during-monitoring-start'));
    await _flush();
    monitoring.complete(_result(0));
    final result = await transition;

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'stale_generation');
    expect(invalidated, hasLength(1));
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('failed monitoring accepts callback-proven playback cleanup', () async {
    final adapter = _FakeAdapter();
    adapter.intentResults[AudioRouteIntentV2.monitoring] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'monitoring_unavailable',
        snapshot: _snapshot(
          generation: 0,
          intent: AudioRouteIntentV2.playbackOnly,
          audioCallbackAttached: true,
          activeInputChannels: 0,
          activeOutputChannels: 2,
        ),
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.monitoring,
    );

    expect(result.succeeded, isFalse);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('failed monitoring rejects unproven playback cleanup', () async {
    final adapter = _FakeAdapter();
    adapter.intentResults[AudioRouteIntentV2.monitoring] = Future.value(
      _result(
        0,
        status: AudioRouteTransitionStatusV2.failure,
        code: 'monitoring_unavailable',
        snapshot: _snapshot(
          generation: 0,
          intent: AudioRouteIntentV2.playbackOnly,
          audioCallbackAttached: false,
          activeInputChannels: 0,
          activeOutputChannels: 2,
        ),
      ),
    );
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();

    final result = await coordinator.transitionIntent(
      AudioRouteIntentV2.monitoring,
    );

    expect(result.succeeded, isFalse);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
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
      recordingChannelStart: 2,
      recordingChannelCount: 2,
    );

    expect(result.succeeded, isTrue);
    expect(
      adapter.appliedOperations,
      <AudioRouteIntentOperationV2>[
        AudioRouteIntentOperationV2.systemSelectedRecording,
      ],
    );
    expect(adapter.appliedRecordingChannelStarts, <int?>[2]);
    expect(adapter.appliedRecordingChannelCounts, <int?>[2]);
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

  test(
      'native stale recovery preflight is superseded once at newest generation',
      () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
      allowRecoveryGenerationSupersession: true,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(
      _event(1, 'speaker', cause: 'oldDeviceUnavailable'),
    );
    await _flush();
    adapter.intentResultsByGeneration[1] = Future.value(
      AudioRouteTransitionResultV2(
        status: AudioRouteTransitionStatusV2.failure,
        generation: 1,
        transitionId: 201,
        diagnosticCode: 'stale_generation',
        elapsedMs: 1,
        transportWasPlaying: false,
        snapshot: _snapshot(generation: 2, transitionId: 201),
      ),
    );
    adapter.intentResultsByGeneration[2] = Future.value(_result(2));

    final first = coordinator.recoverPlaybackAfterIntentInvalidation();
    final duplicate = coordinator.recoverPlaybackAfterIntentInvalidation();
    final firstResult = await first;
    final duplicateResult = await duplicate;

    expect(firstResult.succeeded, isTrue);
    expect(duplicateResult.succeeded, isTrue);
    expect(identical(firstResult, duplicateResult), isTrue);
    expect(
      adapter.appliedIntents,
      <AudioRouteIntentV2>[
        AudioRouteIntentV2.preparingRecording,
        AudioRouteIntentV2.recording,
        AudioRouteIntentV2.playbackOnly,
        AudioRouteIntentV2.playbackOnly,
      ],
    );
    expect(adapter.appliedIntentGenerations.sublist(2), <int>[1, 2]);
    expect(coordinator.intent, AudioRouteIntentV2.playbackOnly);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.stable);
    await coordinator.dispose();
  });

  test('shared coordinator does not supersede native stale without opt-in',
      () async {
    final adapter = _FakeAdapter();
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
    adapter.intentResultsByGeneration[1] = Future.value(
      AudioRouteTransitionResultV2(
        status: AudioRouteTransitionStatusV2.failure,
        generation: 1,
        transitionId: 203,
        diagnosticCode: 'stale_generation',
        elapsedMs: 1,
        transportWasPlaying: false,
        snapshot: _snapshot(generation: 2, transitionId: 203),
      ),
    );

    final result = await coordinator.recoverPlaybackAfterIntentInvalidation();

    expect(result.succeeded, isFalse);
    expect(adapter.appliedIntentGenerations.sublist(1), <int>[1]);
    await coordinator.dispose();
  });

  test('non-stale recovery failure is never superseded', () async {
    final adapter = _FakeAdapter();
    final coordinator = AudioRouteCoordinatorV2(
      adapter: adapter,
      settlingDelay: Duration.zero,
    );
    await coordinator.start();
    await coordinator.transitionIntent(AudioRouteIntentV2.preparingRecording);
    await coordinator.transitionIntent(AudioRouteIntentV2.recording);

    adapter.controller.add(
      _event(1, 'missing', cause: 'oldDeviceUnavailable'),
    );
    await _flush();
    adapter.intentResultsByGeneration[1] = Future.value(
      AudioRouteTransitionResultV2(
        status: AudioRouteTransitionStatusV2.failure,
        generation: 1,
        transitionId: 202,
        diagnosticCode: 'no_output',
        elapsedMs: 1,
        transportWasPlaying: false,
        snapshot: _snapshot(generation: 2, transitionId: 202),
      ),
    );

    final result = await coordinator.recoverPlaybackAfterIntentInvalidation();

    expect(result.succeeded, isFalse);
    expect(result.diagnosticCode, 'no_output');
    expect(adapter.appliedIntentGenerations.sublist(2), <int>[1]);
    expect(coordinator.state, AudioRouteCoordinatorStateV2.failed);
    await coordinator.dispose();
  });

  test('local stale recovery result is never superseded', () async {
    final adapter = _FakeAdapter();
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
    adapter.intentResultsByGeneration[1] = Future.value(
      AudioRouteTransitionResultV2(
        status: AudioRouteTransitionStatusV2.failure,
        generation: 1,
        transitionId: 0,
        diagnosticCode: 'stale_generation',
        elapsedMs: 0,
        transportWasPlaying: false,
        snapshot: _snapshot(generation: 2),
      ),
    );

    final result = await coordinator.recoverPlaybackAfterIntentInvalidation();

    expect(result.succeeded, isFalse);
    expect(adapter.appliedIntentGenerations.sublist(1), <int>[1]);
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
