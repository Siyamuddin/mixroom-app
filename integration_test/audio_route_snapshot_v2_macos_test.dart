import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repeated macOS snapshots do not reconfigure JUCE', (_) async {
    final before = await JuceAudioEngine.getEngineDiagnostics();
    AudioRouteSnapshotV2? firstSnapshot;
    for (var index = 0; index < 20; index++) {
      final snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
      expect(
        snapshot.captureConsistency,
        isNot(AudioRouteCaptureConsistencyV2.unavailable),
      );
      firstSnapshot ??= snapshot;
    }
    final after = await JuceAudioEngine.getEngineDiagnostics();

    expect(after.inputDeviceName, before.inputDeviceName);
    expect(after.outputDeviceName, before.outputDeviceName);
    expect(after.inputChannelCount, before.inputChannelCount);
    expect(after.outputChannelCount, before.outputChannelCount);
    expect(after.sampleRate, before.sampleRate);
    expect(after.bufferSize, before.bufferSize);
    expect(firstSnapshot!.juce.inputOpen, before.inputChannelCount > 0);
    expect(firstSnapshot.juce.deviceOpen, isFalse);
  });
}
