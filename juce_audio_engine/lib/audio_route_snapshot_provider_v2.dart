import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_route_v2.dart';

class MethodChannelAudioRouteSnapshotProviderV2
    implements AudioRouteSnapshotProviderV2 {
  const MethodChannelAudioRouteSnapshotProviderV2({
    MethodChannel channel = const MethodChannel('juce_audio_engine'),
    TargetPlatform? platformOverride,
  })  : _channel = channel,
        _platformOverride = platformOverride;

  final MethodChannel _channel;
  final TargetPlatform? _platformOverride;

  bool get _isSupported =>
      !kIsWeb &&
      (_platformOverride ?? defaultTargetPlatform) == TargetPlatform.macOS;

  @override
  Future<AudioRouteSnapshotV2> readSnapshot() async {
    if (!_isSupported) {
      return _unavailable('platform', 'macOSOnlyCheckpoint');
    }

    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAudioRouteSnapshotV2',
      );
      if (raw == null) {
        return _unavailable('nativeSnapshot', 'emptyNativeResponse');
      }
      return AudioRouteSnapshotV2.fromMap(Map<String, dynamic>.from(raw));
    } on MissingPluginException {
      return _unavailable('nativeSnapshot', 'nativeMethodUnavailable');
    } on PlatformException catch (error) {
      return _unavailable(
        'nativeSnapshot',
        error.code.isEmpty ? 'platformError' : error.code,
      );
    }
  }

  AudioRouteSnapshotV2 _unavailable(String field, String reason) {
    return AudioRouteSnapshotV2(
      capturedAtUtc: DateTime.now().toUtc(),
      captureDurationMs: 0,
      implementation: BluetoothImplementationV2.legacy,
      generation: null,
      transitionId: null,
      coordinatorManaged: false,
      captureConsistency: AudioRouteCaptureConsistencyV2.unavailable,
      inputs: const <AudioRouteEndpointV2>[],
      outputs: const <AudioRouteEndpointV2>[],
      session: const AudioSessionFactsV2(),
      juce: const JuceRouteFactsV2(),
      unavailableReasons: <String, String>{field: reason},
    );
  }
}
