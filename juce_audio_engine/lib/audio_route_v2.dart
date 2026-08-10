enum AudioRouteDirectionV2 { input, output }

enum AudioRouteKindV2 {
  builtIn,
  wired,
  external,
  bluetooth,
  bluetoothMedia,
  bluetoothDuplex,
  bluetoothLe,
  unknown,
}

enum BluetoothImplementationV2 { legacy, v2 }

enum AudioRouteCaptureConsistencyV2 {
  stable,
  routeChangedDuringCapture,
  unavailable,
}

enum AudioRouteIntentV2 {
  playbackOnly,
  preparingRecording,
  recording,
  monitoring,
}

enum AudioHardwareRatePolicyV2 { native, prefer48000 }

enum AudioBufferPolicyV2 { routeNative, conservativeBluetooth }

enum AudioRouteCoordinatorStateV2 {
  stable,
  preparingInput,
  reconfiguring,
  failed,
}

enum AudioRouteTransitionStatusV2 { success, fallback, failure }

String _wireName(Object value) => value.toString().split('.').last;

T _enumFromWire<T extends Enum>(
  List<T> values,
  Object? raw,
  T fallback,
) {
  final value = raw?.toString() ?? '';
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  return fallback;
}

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;

bool? _nullableBool(Object? value) => value is bool ? value : null;

class AudioRouteEndpointV2 {
  const AudioRouteEndpointV2({
    required this.direction,
    required this.nativePortType,
    required this.normalizedKind,
    required this.uid,
    required this.name,
    required this.channelCount,
  });

  final AudioRouteDirectionV2 direction;
  final String nativePortType;
  final AudioRouteKindV2 normalizedKind;
  final String uid;
  final String name;
  final int? channelCount;

  factory AudioRouteEndpointV2.fromMap(Map<String, dynamic> map) {
    return AudioRouteEndpointV2(
      direction: _enumFromWire(
        AudioRouteDirectionV2.values,
        map['direction'],
        AudioRouteDirectionV2.output,
      ),
      nativePortType: map['nativePortType']?.toString() ?? '',
      normalizedKind: _enumFromWire(
        AudioRouteKindV2.values,
        map['normalizedKind'],
        AudioRouteKindV2.unknown,
      ),
      uid: map['uid']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      channelCount: _nullableInt(map['channelCount']),
    );
  }

  Map<String, dynamic> toRawMap() => <String, dynamic>{
        'direction': _wireName(direction),
        'nativePortType': nativePortType,
        'normalizedKind': _wireName(normalizedKind),
        'uid': uid,
        'name': name,
        'channelCount': channelCount,
      };
}

class AudioSessionFactsV2 {
  const AudioSessionFactsV2({
    this.category,
    this.mode,
    this.sampleRateHz,
    this.ioBufferDurationSeconds,
    this.inputChannelCount,
    this.outputChannelCount,
    this.active,
    this.streamRunning,
    this.communicationDeviceSelected,
    this.communicationDeviceType,
    this.bluetoothScoActive,
  });

  final String? category;
  final String? mode;
  final double? sampleRateHz;
  final double? ioBufferDurationSeconds;
  final int? inputChannelCount;
  final int? outputChannelCount;
  final bool? active;
  final bool? streamRunning;
  final bool? communicationDeviceSelected;
  final String? communicationDeviceType;
  final bool? bluetoothScoActive;

  factory AudioSessionFactsV2.fromMap(Map<String, dynamic> map) {
    return AudioSessionFactsV2(
      category: map['category']?.toString(),
      mode: map['mode']?.toString(),
      sampleRateHz: _nullableDouble(map['sampleRateHz']),
      ioBufferDurationSeconds: _nullableDouble(map['ioBufferDurationSeconds']),
      inputChannelCount: _nullableInt(map['inputChannelCount']),
      outputChannelCount: _nullableInt(map['outputChannelCount']),
      active: _nullableBool(map['active']),
      streamRunning: _nullableBool(map['streamRunning']),
      communicationDeviceSelected:
          _nullableBool(map['communicationDeviceSelected']),
      communicationDeviceType: map['communicationDeviceType']?.toString(),
      bluetoothScoActive: _nullableBool(map['bluetoothScoActive']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'category': category,
        'mode': mode,
        'sampleRateHz': sampleRateHz,
        'ioBufferDurationSeconds': ioBufferDurationSeconds,
        'inputChannelCount': inputChannelCount,
        'outputChannelCount': outputChannelCount,
        'active': active,
        'streamRunning': streamRunning,
        'communicationDeviceSelected': communicationDeviceSelected,
        'communicationDeviceType': communicationDeviceType,
        'bluetoothScoActive': bluetoothScoActive,
      };
}

class JuceRouteFactsV2 {
  const JuceRouteFactsV2({
    this.deviceOpen,
    this.audioCallbackAttached,
    this.sampleRateHz,
    this.bufferFrames,
    this.activeInputChannels,
    this.activeOutputChannels,
    this.inputDeviceName,
    this.outputDeviceName,
    this.realtimeCallbackCount,
    this.realtimeCallbackLastMs,
    this.realtimeCallbackMaxMs,
    this.realtimeCallbackAverageMs,
    this.realtimeCallbackBudgetMs,
    this.realtimeCallbackOverBudgetCount,
    this.xRunCount,
    this.requestedSampleRateHz,
    this.requestedBufferFrames,
    this.oboeSampleRateHz,
    this.oboeBufferFrames,
    this.routedDeviceId,
    this.audioBackend,
    this.performanceMode,
    this.sharingMode,
    this.bufferCapacityFrames,
    this.framesPerBurst,
    this.framesPerCallback,
    this.streamState,
  });

  final bool? deviceOpen;
  final bool? audioCallbackAttached;
  final double? sampleRateHz;
  final int? bufferFrames;
  final int? activeInputChannels;
  final int? activeOutputChannels;
  final String? inputDeviceName;
  final String? outputDeviceName;
  final int? realtimeCallbackCount;
  final double? realtimeCallbackLastMs;
  final double? realtimeCallbackMaxMs;
  final double? realtimeCallbackAverageMs;
  final double? realtimeCallbackBudgetMs;
  final int? realtimeCallbackOverBudgetCount;
  final int? xRunCount;
  final double? requestedSampleRateHz;
  final int? requestedBufferFrames;
  final double? oboeSampleRateHz;
  final int? oboeBufferFrames;
  final String? routedDeviceId;
  final String? audioBackend;
  final String? performanceMode;
  final String? sharingMode;
  final int? bufferCapacityFrames;
  final int? framesPerBurst;
  final int? framesPerCallback;
  final String? streamState;

  bool? get inputOpen =>
      activeInputChannels == null ? null : activeInputChannels! > 0;

  factory JuceRouteFactsV2.fromMap(Map<String, dynamic> map) {
    return JuceRouteFactsV2(
      deviceOpen: _nullableBool(map['deviceOpen']),
      audioCallbackAttached: _nullableBool(map['audioCallbackAttached']),
      sampleRateHz: _nullableDouble(map['sampleRateHz']),
      bufferFrames: _nullableInt(map['bufferFrames']),
      activeInputChannels: _nullableInt(map['activeInputChannels']),
      activeOutputChannels: _nullableInt(map['activeOutputChannels']),
      inputDeviceName: map['inputDeviceName']?.toString(),
      outputDeviceName: map['outputDeviceName']?.toString(),
      realtimeCallbackCount: _nullableInt(map['realtimeCallbackCount']),
      realtimeCallbackLastMs: _nullableDouble(map['realtimeCallbackLastMs']),
      realtimeCallbackMaxMs: _nullableDouble(map['realtimeCallbackMaxMs']),
      realtimeCallbackAverageMs:
          _nullableDouble(map['realtimeCallbackAverageMs']),
      realtimeCallbackBudgetMs:
          _nullableDouble(map['realtimeCallbackBudgetMs']),
      realtimeCallbackOverBudgetCount:
          _nullableInt(map['realtimeCallbackOverBudgetCount']),
      xRunCount: _nullableInt(map['xRunCount']),
      requestedSampleRateHz: _nullableDouble(map['requestedSampleRateHz']),
      requestedBufferFrames: _nullableInt(map['requestedBufferFrames']),
      oboeSampleRateHz: _nullableDouble(map['oboeSampleRateHz']),
      oboeBufferFrames: _nullableInt(map['oboeBufferFrames']),
      routedDeviceId: map['routedDeviceId']?.toString(),
      audioBackend: map['audioBackend']?.toString(),
      performanceMode: map['performanceMode']?.toString(),
      sharingMode: map['sharingMode']?.toString(),
      bufferCapacityFrames: _nullableInt(map['bufferCapacityFrames']),
      framesPerBurst: _nullableInt(map['framesPerBurst']),
      framesPerCallback: _nullableInt(map['framesPerCallback']),
      streamState: map['streamState']?.toString(),
    );
  }

  Map<String, dynamic> toMap({bool includeDeviceNames = true}) {
    return <String, dynamic>{
      'deviceOpen': deviceOpen,
      'audioCallbackAttached': audioCallbackAttached,
      'sampleRateHz': sampleRateHz,
      'bufferFrames': bufferFrames,
      'activeInputChannels': activeInputChannels,
      'activeOutputChannels': activeOutputChannels,
      if (includeDeviceNames) 'inputDeviceName': inputDeviceName,
      if (includeDeviceNames) 'outputDeviceName': outputDeviceName,
      'inputOpen': inputOpen,
      'realtimeCallbackCount': realtimeCallbackCount,
      'realtimeCallbackLastMs': realtimeCallbackLastMs,
      'realtimeCallbackMaxMs': realtimeCallbackMaxMs,
      'realtimeCallbackAverageMs': realtimeCallbackAverageMs,
      'realtimeCallbackBudgetMs': realtimeCallbackBudgetMs,
      'realtimeCallbackOverBudgetCount': realtimeCallbackOverBudgetCount,
      'xRunCount': xRunCount,
      'requestedSampleRateHz': requestedSampleRateHz,
      'requestedBufferFrames': requestedBufferFrames,
      'oboeSampleRateHz': oboeSampleRateHz,
      'oboeBufferFrames': oboeBufferFrames,
      'routedDeviceId': routedDeviceId,
      'audioBackend': audioBackend,
      'performanceMode': performanceMode,
      'sharingMode': sharingMode,
      'bufferCapacityFrames': bufferCapacityFrames,
      'framesPerBurst': framesPerBurst,
      'framesPerCallback': framesPerCallback,
      'streamState': streamState,
    };
  }
}

class AudioRouteSnapshotV2 {
  const AudioRouteSnapshotV2({
    this.schemaVersion = 1,
    required this.capturedAtUtc,
    required this.captureDurationMs,
    required this.implementation,
    required this.generation,
    required this.transitionId,
    required this.coordinatorManaged,
    required this.captureConsistency,
    required this.inputs,
    required this.outputs,
    required this.session,
    required this.juce,
    required this.unavailableReasons,
  });

  final int schemaVersion;
  final DateTime capturedAtUtc;
  final int captureDurationMs;
  final BluetoothImplementationV2 implementation;
  final int? generation;
  final int? transitionId;
  final bool coordinatorManaged;
  final AudioRouteCaptureConsistencyV2 captureConsistency;
  final List<AudioRouteEndpointV2> inputs;
  final List<AudioRouteEndpointV2> outputs;
  final AudioSessionFactsV2 session;
  final JuceRouteFactsV2 juce;
  final Map<String, String> unavailableReasons;

  bool get hasBluetoothOutput => outputs.any(
        (endpoint) => <AudioRouteKindV2>{
          AudioRouteKindV2.bluetooth,
          AudioRouteKindV2.bluetoothMedia,
          AudioRouteKindV2.bluetoothDuplex,
          AudioRouteKindV2.bluetoothLe,
        }.contains(endpoint.normalizedKind),
      );

  factory AudioRouteSnapshotV2.fromMap(Map<String, dynamic> map) {
    List<AudioRouteEndpointV2> endpoints(Object? raw) {
      if (raw is! List) return const <AudioRouteEndpointV2>[];
      return raw
          .whereType<Map>()
          .map(
            (value) => AudioRouteEndpointV2.fromMap(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(growable: false);
    }

    Map<String, dynamic> nestedMap(String key) {
      final raw = map[key];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    }

    final unavailable = <String, String>{};
    final rawUnavailable = map['unavailableReasons'];
    if (rawUnavailable is Map) {
      for (final entry in rawUnavailable.entries) {
        unavailable[entry.key.toString()] = entry.value.toString();
      }
    }

    return AudioRouteSnapshotV2(
      schemaVersion: _nullableInt(map['schemaVersion']) ?? 1,
      capturedAtUtc: DateTime.tryParse(
            map['capturedAtUtc']?.toString() ?? '',
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      captureDurationMs: _nullableInt(map['captureDurationMs']) ?? 0,
      implementation: _enumFromWire(
        BluetoothImplementationV2.values,
        map['implementation'],
        BluetoothImplementationV2.legacy,
      ),
      generation: _nullableInt(map['generation']),
      transitionId: _nullableInt(map['transitionId']),
      coordinatorManaged: map['coordinatorManaged'] == true,
      captureConsistency: _enumFromWire(
        AudioRouteCaptureConsistencyV2.values,
        map['captureConsistency'],
        AudioRouteCaptureConsistencyV2.unavailable,
      ),
      inputs: endpoints(map['inputs']),
      outputs: endpoints(map['outputs']),
      session: AudioSessionFactsV2.fromMap(nestedMap('session')),
      juce: JuceRouteFactsV2.fromMap(nestedMap('juce')),
      unavailableReasons: Map<String, String>.unmodifiable(unavailable),
    );
  }

  Map<String, dynamic> toRawMap() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'capturedAtUtc': capturedAtUtc.toUtc().toIso8601String(),
        'captureDurationMs': captureDurationMs,
        'implementation': _wireName(implementation),
        'generation': generation,
        'transitionId': transitionId,
        'coordinatorManaged': coordinatorManaged,
        'captureConsistency': _wireName(captureConsistency),
        'inputs': inputs.map((value) => value.toRawMap()).toList(),
        'outputs': outputs.map((value) => value.toRawMap()).toList(),
        'session': session.toMap(),
        'juce': juce.toMap(),
        'unavailableReasons': unavailableReasons,
      };
}

class AudioPlaybackStartupResultV2 {
  const AudioPlaybackStartupResultV2({
    required this.success,
    required this.diagnosticCode,
    required this.snapshot,
  });

  final bool success;
  final String diagnosticCode;
  final AudioRouteSnapshotV2 snapshot;

  factory AudioPlaybackStartupResultV2.fromMap(Map<String, dynamic> map) {
    final rawSnapshot = map['snapshot'];
    return AudioPlaybackStartupResultV2(
      success: map['success'] == true,
      diagnosticCode:
          map['diagnosticCode']?.toString() ?? 'actual_state_unavailable',
      snapshot: AudioRouteSnapshotV2.fromMap(
        rawSnapshot is Map
            ? Map<String, dynamic>.from(rawSnapshot)
            : <String, dynamic>{
                'captureConsistency': 'unavailable',
                'unavailableReasons': <String, String>{
                  'startup.snapshot': 'missingFromNativeResult',
                },
              },
      ),
    );
  }
}

class AudioRouteChangeEventV2 {
  const AudioRouteChangeEventV2({
    required this.generation,
    required this.cause,
    required this.fingerprint,
    required this.transportWasPlaying,
    required this.snapshot,
  });

  final int generation;
  final String cause;
  final String fingerprint;
  final bool transportWasPlaying;
  final AudioRouteSnapshotV2 snapshot;

  factory AudioRouteChangeEventV2.fromMap(Map<String, dynamic> map) {
    final rawSnapshot = map['snapshot'];
    return AudioRouteChangeEventV2(
      generation: _nullableInt(map['generation']) ?? 0,
      cause: map['cause']?.toString() ?? 'unknown',
      fingerprint: map['fingerprint']?.toString() ?? '',
      transportWasPlaying: map['transportWasPlaying'] == true,
      snapshot: AudioRouteSnapshotV2.fromMap(
        rawSnapshot is Map
            ? Map<String, dynamic>.from(rawSnapshot)
            : <String, dynamic>{
                'captureConsistency': 'unavailable',
                'unavailableReasons': <String, String>{
                  'routeEvent.snapshot': 'missingFromNativeEvent',
                },
              },
      ),
    );
  }
}

class AudioRouteTransitionResultV2 {
  const AudioRouteTransitionResultV2({
    required this.status,
    required this.generation,
    required this.transitionId,
    required this.diagnosticCode,
    required this.elapsedMs,
    required this.transportWasPlaying,
    required this.snapshot,
  });

  final AudioRouteTransitionStatusV2 status;
  final int generation;
  final int transitionId;
  final String diagnosticCode;
  final int elapsedMs;
  final bool transportWasPlaying;
  final AudioRouteSnapshotV2 snapshot;

  bool get succeeded => status != AudioRouteTransitionStatusV2.failure;

  factory AudioRouteTransitionResultV2.fromMap(Map<String, dynamic> map) {
    final rawSnapshot = map['snapshot'];
    return AudioRouteTransitionResultV2(
      status: _enumFromWire(
        AudioRouteTransitionStatusV2.values,
        map['status'],
        AudioRouteTransitionStatusV2.failure,
      ),
      generation: _nullableInt(map['generation']) ?? 0,
      transitionId: _nullableInt(map['transitionId']) ?? 0,
      diagnosticCode:
          map['diagnosticCode']?.toString() ?? 'actual_state_unavailable',
      elapsedMs: _nullableInt(map['elapsedMs']) ?? 0,
      transportWasPlaying: map['transportWasPlaying'] == true,
      snapshot: AudioRouteSnapshotV2.fromMap(
        rawSnapshot is Map
            ? Map<String, dynamic>.from(rawSnapshot)
            : <String, dynamic>{
                'captureConsistency': 'unavailable',
                'unavailableReasons': <String, String>{
                  'transition.snapshot': 'missingFromNativeResult',
                },
              },
      ),
    );
  }
}

class DesiredAudioRouteConfigurationV2 {
  const DesiredAudioRouteConfigurationV2({
    required this.intent,
    required this.supported,
    required this.rejectionCode,
    required this.desiredInputChannels,
    required this.requireNonBluetoothInput,
    required this.hardwareRatePolicy,
    required this.bufferPolicy,
    required this.monitoringAllowed,
  });

  final AudioRouteIntentV2 intent;
  final bool supported;
  final String? rejectionCode;
  final int desiredInputChannels;
  final bool requireNonBluetoothInput;
  final AudioHardwareRatePolicyV2 hardwareRatePolicy;
  final AudioBufferPolicyV2 bufferPolicy;
  final bool monitoringAllowed;
}

class AudioRoutePolicyV2 {
  const AudioRoutePolicyV2();

  DesiredAudioRouteConfigurationV2 resolve({
    required AudioRouteSnapshotV2 snapshot,
    required AudioRouteIntentV2 intent,
  }) {
    final bluetoothOutput = snapshot.hasBluetoothOutput;
    final wantsInput = intent != AudioRouteIntentV2.playbackOnly;
    final unsupportedBluetoothMonitoring =
        bluetoothOutput && intent == AudioRouteIntentV2.monitoring;

    return DesiredAudioRouteConfigurationV2(
      intent: intent,
      supported: !unsupportedBluetoothMonitoring,
      rejectionCode: unsupportedBluetoothMonitoring
          ? 'bluetooth_monitoring_unsupported'
          : null,
      desiredInputChannels: wantsInput ? 1 : 0,
      requireNonBluetoothInput: wantsInput,
      hardwareRatePolicy: bluetoothOutput
          ? AudioHardwareRatePolicyV2.prefer48000
          : AudioHardwareRatePolicyV2.native,
      bufferPolicy: bluetoothOutput
          ? AudioBufferPolicyV2.conservativeBluetooth
          : AudioBufferPolicyV2.routeNative,
      monitoringAllowed:
          !bluetoothOutput && intent == AudioRouteIntentV2.monitoring,
    );
  }
}

abstract interface class AudioRouteSnapshotProviderV2 {
  Future<AudioRouteSnapshotV2> readSnapshot();
}
