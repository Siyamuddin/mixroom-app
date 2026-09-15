import 'audio_route_v2.dart';

/// Recording range supported by the current iOS V2 system-selected route.
/// Input presence is nullable because passive discovery can be inconclusive.
class IOSRecordingInputV2 {
  const IOSRecordingInputV2({
    required this.channelStart,
    required this.channelCount,
    this.inputAvailable,
    this.resolvedDeviceName = '',
    this.deviceNameVerified = false,
  });

  final int channelStart;
  final int channelCount;
  final bool? inputAvailable;
  final String resolvedDeviceName;
  final bool deviceNameVerified;

  bool accepts(int start, int count) =>
      start == channelStart && count == channelCount;

  String get label => 'Input ${channelStart + 1} (Mono)';

  static IOSRecordingInputV2? fromMap(Map<dynamic, dynamic> map) {
    final start = map['channelStart'];
    final count = map['channelCount'];
    if (start is! int || start < 0 || count is! int || count != 1) {
      return null;
    }
    return IOSRecordingInputV2(
      channelStart: start,
      channelCount: count,
      inputAvailable:
          map['inputAvailable'] is bool ? map['inputAvailable'] as bool : null,
      resolvedDeviceName: map['resolvedDeviceName']?.toString().trim() ?? '',
      deviceNameVerified: map['deviceNameVerified'] == true,
    );
  }
}

class IOSRecordingInputRefreshV2 {
  const IOSRecordingInputRefreshV2({
    required this.configuration,
    required this.snapshot,
  });

  final IOSRecordingInputV2? configuration;
  final AudioRouteSnapshotV2? snapshot;
}

Future<IOSRecordingInputRefreshV2> readIOSRecordingInputRefreshV2({
  required Future<IOSRecordingInputV2?> Function() readConfiguration,
  required Future<AudioRouteSnapshotV2> Function() readSnapshot,
}) async {
  IOSRecordingInputV2? configuration;
  AudioRouteSnapshotV2? snapshot;
  try {
    configuration = await readConfiguration();
  } catch (_) {}
  try {
    snapshot = await readSnapshot();
  } catch (_) {}
  return IOSRecordingInputRefreshV2(
    configuration: configuration,
    snapshot: snapshot,
  );
}

/// Only an active, current capture route can upgrade a passive device name to
/// verified. Passive resolution remains useful for the System Default label.
String resolvedIOSInputNameV2(
  IOSRecordingInputV2? configuration,
  AudioRouteSnapshotV2? snapshot,
  int? currentGeneration,
) {
  if (configuration == null) return '';
  if (snapshot == null ||
      currentGeneration == null ||
      snapshot.generation != currentGeneration ||
      snapshot.captureConsistency != AudioRouteCaptureConsistencyV2.stable ||
      snapshot.juce.deviceOpen != true ||
      snapshot.juce.audioCallbackAttached != true ||
      snapshot.juce.activeInputChannels != configuration.channelCount ||
      snapshot.inputs.length != 1 ||
      snapshot.inputs.single.channelCount != configuration.channelCount) {
    return configuration.deviceNameVerified
        ? ''
        : configuration.resolvedDeviceName;
  }
  return snapshot.inputs.single.name.trim();
}
