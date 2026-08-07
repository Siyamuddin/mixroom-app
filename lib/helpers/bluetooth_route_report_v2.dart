import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';

class BluetoothRouteReportSerializerV2 {
  BluetoothRouteReportSerializerV2({List<int>? sessionSalt})
    : _sessionSalt = List<int>.unmodifiable(
        sessionSalt ?? _createSessionSalt(),
      );

  final List<int> _sessionSalt;

  static List<int> _createSessionSalt() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  String encode(AudioRouteSnapshotV2 snapshot) => jsonEncode(toMap(snapshot));

  Map<String, dynamic> toMap(AudioRouteSnapshotV2 snapshot) {
    return <String, dynamic>{
      'schemaVersion': snapshot.schemaVersion,
      'capturedAtUtc': snapshot.capturedAtUtc.toUtc().toIso8601String(),
      'captureDurationMs': snapshot.captureDurationMs,
      'implementation': snapshot.implementation.name,
      'generation': snapshot.generation,
      'transitionId': snapshot.transitionId,
      'coordinatorManaged': snapshot.coordinatorManaged,
      'captureConsistency': snapshot.captureConsistency.name,
      'inputs': _sanitizeEndpoints(snapshot.inputs),
      'outputs': _sanitizeEndpoints(snapshot.outputs),
      'session': snapshot.session.toMap(),
      'juce': snapshot.juce.toMap(includeDeviceNames: false),
      'unavailableReasons': snapshot.unavailableReasons,
    };
  }

  List<Map<String, dynamic>> _sanitizeEndpoints(
    List<AudioRouteEndpointV2> endpoints,
  ) {
    return <Map<String, dynamic>>[
      for (var index = 0; index < endpoints.length; index++)
        _sanitizeEndpoint(endpoints[index], index),
    ];
  }

  Map<String, dynamic> _sanitizeEndpoint(
    AudioRouteEndpointV2 endpoint,
    int index,
  ) {
    final identity = endpoint.uid.isNotEmpty
        ? endpoint.uid
        : '${endpoint.nativePortType}|${endpoint.name}|$index';
    final digest = sha256.convert(<int>[
      ..._sessionSalt,
      ...utf8.encode('${endpoint.direction.name}|$identity'),
    ]);
    return <String, dynamic>{
      'direction': endpoint.direction.name,
      'endpointToken':
          '${endpoint.direction.name}-${digest.toString().substring(0, 8)}',
      'nativePortType': endpoint.nativePortType,
      'normalizedKind': endpoint.normalizedKind.name,
      'channelCount': endpoint.channelCount,
    };
  }
}
