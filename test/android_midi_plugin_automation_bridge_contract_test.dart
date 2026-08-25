import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android acknowledges unsupported hosted MIDI automation sync', () {
    final source = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/'
      'juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();

    const methods = <String>[
      'setMidiClipPluginParameter',
      'setMidiClipPluginAutomationPoints',
      'clearMidiClipPluginAutomation',
    ];
    for (final method in methods) {
      expect(source, contains('"$method"'));
    }

    final contractStart = source.indexOf('"setMidiClipPluginParameter",');
    final nextHandler = source.indexOf(
      '"setRowGainAutomationPoints"',
      contractStart,
    );
    expect(contractStart, greaterThanOrEqualTo(0));
    expect(nextHandler, greaterThan(contractStart));
    final contract = source.substring(contractStart, nextHandler);
    expect(contract, contains('result.success(null)'));
    expect(contract, isNot(contains('JuceBridge.')));
  });
}
