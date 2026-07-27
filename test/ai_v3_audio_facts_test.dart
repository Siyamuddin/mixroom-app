import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_audio_facts.dart';

void main() {
  test('audio facts distinguish clips, usable signal, and analysis', () {
    final silent = AiV3AudioFacts.fromAnalysis(
      mixProcessingSupported: true,
      hasAudio: true,
      approxRms: 0,
      audioStatistics: const <String, double>{'centroid_hz': 0},
    );
    expect(silent.mixProcessingSupported, isTrue);
    expect(silent.hasUsableSignal, isFalse);
    expect(silent.analysisAvailable, isTrue);
    expect(silent.referenceSuitable, isFalse);

    final unanalyzed = AiV3AudioFacts.fromAnalysis(
      mixProcessingSupported: true,
      hasAudio: true,
      approxRms: 0.1,
      audioStatistics: const <String, double>{},
    );
    expect(unanalyzed.hasUsableSignal, isTrue);
    expect(unanalyzed.analysisAvailable, isFalse);
    expect(unanalyzed.referenceSuitable, isFalse);

    final usable = AiV3AudioFacts.fromAnalysis(
      mixProcessingSupported: true,
      hasAudio: true,
      approxRms: 0.1,
      audioStatistics: const <String, double>{'centroid_hz': 1200},
    );
    expect(usable.hasUsableSignal, isTrue);
    expect(usable.analysisAvailable, isTrue);
    expect(usable.referenceSuitable, isTrue);

    final midiPlayback = AiV3AudioFacts.fromAnalysis(
      mixProcessingSupported: true,
      hasAudio: false,
      approxRms: 0,
      audioStatistics: const <String, double>{},
    );
    expect(midiPlayback.mixProcessingSupported, isTrue);
    expect(midiPlayback.hasUsableSignal, isFalse);
    expect(midiPlayback.analysisAvailable, isFalse);
    expect(midiPlayback.referenceSuitable, isFalse);
  });
}
