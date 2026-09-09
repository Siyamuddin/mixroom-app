import 'audio_route_v2.dart';

/// Supported app capture range reported by the Android native recording policy.
/// Device presence is deliberately nullable: unknown must allow native probing.
class AndroidRecordingInputV2 {
  const AndroidRecordingInputV2(
      {required this.channelStart,
      required this.channelCount,
      this.inputAvailable});
  final int channelStart;
  final int channelCount;
  final bool? inputAvailable;
  bool accepts(int start, int count) =>
      start == channelStart && count == channelCount;
  String get label => 'Input ${channelStart + 1} (Mono)';
  static AndroidRecordingInputV2? fromMap(Map<dynamic, dynamic> map) {
    final start = map['channelStart'];
    final count = map['channelCount'];
    if (start is! int || start < 0 || count is! int || count != 1) return null;
    return AndroidRecordingInputV2(
        channelStart: start,
        channelCount: count,
        inputAvailable: map['inputAvailable'] is bool
            ? map['inputAvailable'] as bool
            : null);
  }
}

class AndroidRecordingInputRefreshV2 {
  const AndroidRecordingInputRefreshV2({
    required this.configuration,
    required this.snapshot,
  });

  final AndroidRecordingInputV2? configuration;
  final AudioRouteSnapshotV2? snapshot;
}

/// Reads capability and route identity independently so a transient snapshot
/// failure cannot hide an otherwise valid recording policy.
Future<AndroidRecordingInputRefreshV2> readAndroidRecordingInputRefreshV2({
  required Future<AndroidRecordingInputV2?> Function() readConfiguration,
  required Future<AudioRouteSnapshotV2> Function() readSnapshot,
}) async {
  AndroidRecordingInputV2? configuration;
  AudioRouteSnapshotV2? snapshot;
  try {
    configuration = await readConfiguration();
  } catch (_) {}
  try {
    snapshot = await readSnapshot();
  } catch (_) {}
  return AndroidRecordingInputRefreshV2(
    configuration: configuration,
    snapshot: snapshot,
  );
}

/// Device inventory cannot identify the system-selected microphone. Only a
/// current, running capture snapshot may supply its user-visible name.
String verifiedAndroidInputNameV2(AndroidRecordingInputV2? configuration,
    AudioRouteSnapshotV2 snapshot, int? currentGeneration) {
  final capturing = snapshot.intent == AudioRouteIntentV2.preparingRecording ||
      snapshot.intent == AudioRouteIntentV2.recording ||
      snapshot.intent == AudioRouteIntentV2.monitoring;
  if (configuration == null ||
      currentGeneration == null ||
      snapshot.generation != currentGeneration ||
      !capturing ||
      snapshot.captureConsistency != AudioRouteCaptureConsistencyV2.stable ||
      snapshot.juce.deviceOpen != true ||
      snapshot.juce.audioCallbackAttached != true ||
      snapshot.juce.activeInputChannels != configuration.channelCount ||
      snapshot.inputs.length != 1 ||
      snapshot.inputs.single.channelCount != configuration.channelCount) {
    return '';
  }
  return snapshot.inputs.single.name.trim();
}
