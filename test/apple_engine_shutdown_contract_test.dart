import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS termination shuts down audio before an immortal engine singleton',
    () {
      final appDelegate = File(
        'macos/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final swiftPlugin = File(
        'juce_audio_engine/macos/Classes/JuceAudioEnginePlugin.swift',
      ).readAsStringSync();
      final plugin = File(
        'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
      ).readAsStringSync();
      final engine = File(
        'juce_audio_engine/ios/Classes/JuceEngine.cpp',
      ).readAsStringSync();

      expect(appDelegate, contains('applicationWillTerminate'));
      expect(
        appDelegate,
        contains(
          'JuceAudioEnginePluginSwift.shutdownForApplicationTermination',
        ),
      );
      expect(swiftPlugin, contains('shutdownForApplicationTermination'));
      expect(plugin, contains('shutdownForApplicationTermination'));
      expect(
        engine,
        contains('static JuceEngine *instance = new JuceEngine();'),
      );
      expect(engine, isNot(contains('static JuceEngine instance;')));
    },
  );
}
