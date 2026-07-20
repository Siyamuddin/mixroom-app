import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

num _numValue(Map<String, dynamic> stats, String key) {
  final value = stats[key];
  if (value is num) return value;
  return 0;
}

bool _boolValue(Map<String, dynamic> stats, String key) {
  final value = stats[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native timeline renderer stress stays under callback budget',
      (tester) async {
    const clipCount =
        int.fromEnvironment('MIXROOM_ENGINE_STRESS_CLIPS', defaultValue: 64);
    const blockCount =
        int.fromEnvironment('MIXROOM_ENGINE_STRESS_BLOCKS', defaultValue: 512);
    const blockSize = int.fromEnvironment('MIXROOM_ENGINE_STRESS_BLOCK_SIZE',
        defaultValue: 512);
    const sampleRateText = String.fromEnvironment(
      'MIXROOM_ENGINE_STRESS_SAMPLE_RATE',
      defaultValue: '48000.0',
    );
    final sampleRate = double.tryParse(sampleRateText) ?? 48000.0;

    final stats = await JuceAudioEngine.runEngineStressTest(
      clipCount: clipCount,
      blockCount: blockCount,
      blockSize: blockSize,
      sampleRate: sampleRate,
    );

    // Keep this line stable so local/CI logs can scrape the timing payload.
    // ignore: avoid_print
    print('MIXROOM_ENGINE_STRESS ${jsonEncode(stats)}');

    expect(_numValue(stats, 'stressClipCount').toInt(), clipCount);
    expect(_numValue(stats, 'stressBlockCount').toInt(), blockCount);
    expect(_numValue(stats, 'stressBlockSize').toInt(), blockSize);
    expect(_numValue(stats, 'stressChecksum').abs(), greaterThan(0));
    expect(_numValue(stats, 'stressOverBudgetBlocks').toInt(), 0);
    expect(_boolValue(stats, 'stressRealtimeSafe'), isTrue);
  });
}
