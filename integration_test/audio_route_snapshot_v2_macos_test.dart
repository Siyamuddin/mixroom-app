import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repeated macOS snapshots do not open or reconfigure JUCE', (
    _,
  ) async {
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

  testWidgets('snapshots preserve an initialized JUCE route', (_) async {
    await JuceAudioEngine.initialise();
    try {
      final before = await JuceAudioEngine.getEngineDiagnostics();
      AudioRouteSnapshotV2? firstSnapshot;
      for (var index = 0; index < 20; index++) {
        final snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
        expect(
          snapshot.captureConsistency,
          AudioRouteCaptureConsistencyV2.stable,
        );
        expect(snapshot.juce.deviceOpen, isTrue);
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
      final conflictingV2 = await JuceAudioEngine.initialisePlaybackV2();
      expect(conflictingV2.success, isFalse);
      expect(conflictingV2.diagnosticCode, 'implementation_conflict');
      expect(conflictingV2.snapshot.juce.deviceOpen, isTrue);
    } finally {
      await JuceAudioEngine.shutdown();
    }
  });

  testWidgets(
    'V2 opens playback-only and can return to Legacy after shutdown',
    (_) async {
      final v2Started = await JuceAudioEngine.initialiseForImplementation(
        BluetoothImplementationV2.v2,
      );
      expect(v2Started, isTrue);
      try {
        await JuceAudioEngine.initialise();
        final ownershipSnapshot =
            await JuceAudioEngine.getAudioRouteSnapshotV2();
        expect(ownershipSnapshot.implementation, BluetoothImplementationV2.v2);
        expect(ownershipSnapshot.inputs, isEmpty);
        expect(ownershipSnapshot.juce.inputDeviceName, isEmpty);
        expect(ownershipSnapshot.juce.activeInputChannels, 0);
        expect(ownershipSnapshot.juce.inputOpen, isFalse);

        final monitored = await JuceAudioEngine.startAudioRouteMonitoringV2();
        expect(monitored.coordinatorManaged, isTrue);
        expect(monitored.generation, 0);
        final reapplied = await JuceAudioEngine.applyAudioRouteConfigurationV2(
          0,
        );
        expect(reapplied.succeeded, isTrue);
        expect(reapplied.snapshot.coordinatorManaged, isTrue);
        expect(reapplied.snapshot.inputs, isEmpty);
        expect(reapplied.snapshot.juce.inputDeviceName, isEmpty);
        expect(reapplied.snapshot.juce.activeInputChannels, 0);
        expect(
          (reapplied.snapshot.juce.activeOutputChannels ?? 0),
          greaterThan(0),
        );
        JuceAudioEngine.acceptVerifiedAudioRouteTransitionV2(reapplied);

        for (var index = 0; index < 20; index++) {
          final snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
          expect(snapshot.implementation, BluetoothImplementationV2.v2);
          expect(
            snapshot.captureConsistency,
            AudioRouteCaptureConsistencyV2.stable,
          );
          expect(snapshot.juce.deviceOpen, isTrue);
          expect(snapshot.juce.activeInputChannels, 0);
          expect((snapshot.juce.activeOutputChannels ?? 0), greaterThan(0));
          expect((snapshot.juce.sampleRateHz ?? 0), greaterThan(0));
          expect((snapshot.juce.bufferFrames ?? 0), greaterThan(0));
        }
        expect(await JuceAudioEngine.validatePlaybackV2(), isTrue);
        await JuceAudioEngine.stopAudioRouteMonitoringV2();
        final afterMonitoring = await JuceAudioEngine.getAudioRouteSnapshotV2();
        expect(afterMonitoring.coordinatorManaged, isFalse);
        expect(afterMonitoring.juce.deviceOpen, isTrue);
      } finally {
        await JuceAudioEngine.stopAudioRouteMonitoringV2();
        await JuceAudioEngine.shutdown();
      }

      final legacyStarted = await JuceAudioEngine.initialiseForImplementation(
        BluetoothImplementationV2.legacy,
      );
      expect(legacyStarted, isTrue);
      try {
        final snapshot = await JuceAudioEngine.getAudioRouteSnapshotV2();
        expect(snapshot.implementation, BluetoothImplementationV2.legacy);
        expect(snapshot.juce.deviceOpen, isTrue);
      } finally {
        await JuceAudioEngine.shutdown();
      }
    },
  );
}
