import 'package:juce_audio_engine/audio_route_v2.dart';

/// A stable inventory alone does not prove that the processing graph has
/// followed the hardware. Only publish a clock shared by an open output and
/// its prepared graph. Native rates need not belong to the editable presets.
int? verifiedDawOutputSampleRate(AudioRouteSnapshotV2 snapshot) {
  if (snapshot.captureConsistency != AudioRouteCaptureConsistencyV2.stable ||
      snapshot.outputs.length != 1 ||
      snapshot.juce.deviceOpen != true ||
      snapshot.juce.audioCallbackAttached != true ||
      (snapshot.juce.activeOutputChannels ?? 0) <= 0 ||
      (snapshot.juce.realtimeCallbackCount ?? 0) <= 0) {
    return null;
  }
  final native = snapshot.session.sampleRateHz;
  final device = snapshot.juce.sampleRateHz;
  final graph = snapshot.juce.projectGraphSampleRateHz;
  if (native == null ||
      !native.isFinite ||
      native <= 1000 ||
      device == null ||
      !device.isFinite ||
      graph == null ||
      !graph.isFinite ||
      (device - native).abs() >= 1 ||
      (graph - native).abs() >= 1) {
    return null;
  }
  return native.round();
}

/// Finite menu choices within the driver's reported ranges. Discrete rates are
/// retained verbatim; continuous ranges contribute integer boundaries plus
/// supported common rates. Unknown or system-managed capabilities are read-only.
List<int> selectableDawOutputSampleRates(
  AudioRouteSnapshotV2 snapshot, {
  required Iterable<int> commonRates,
}) {
  final current = verifiedDawOutputSampleRate(snapshot);
  if (current == null || snapshot.intent != AudioRouteIntentV2.playbackOnly) {
    return const [];
  }
  final output = snapshot.outputs.single;
  if (output.sampleRateChangeable != true) return const [];
  final ranges = output.sampleRateRanges
      .where((range) => range.isValid)
      .toList();
  final candidates = <int>{current, ...commonRates};
  for (final range in ranges) {
    candidates.add(range.minimumHz.ceil());
    candidates.add(range.maximumHz.floor());
  }
  final supported =
      candidates
          .where((rate) => ranges.any((range) => range.contains(rate)))
          .toList()
        ..sort();
  // A dropdown that cannot change the current value adds no control.
  return supported.any((rate) => rate != current) ? supported : const [];
}

String formatDawSampleRate(int rate) => rate < 1000
    ? '$rate Hz'
    : '${rate % 1000 == 0 ? rate ~/ 1000 : rate / 1000} kHz';
