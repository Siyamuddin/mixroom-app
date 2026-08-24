import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editor;
  late String routeTypes;
  late String sessionResolver;
  late String androidPlugin;
  late String applePlugin;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    routeTypes = File(
      'juce_audio_engine/lib/audio_route_v2.dart',
    ).readAsStringSync();
    sessionResolver = File(
      'lib/helpers/bluetooth_implementation_session_v2.dart',
    ).readAsStringSync();
    androidPlugin = File(
      'juce_audio_engine/android/src/main/kotlin/com/mixroom/juce_audio_engine/JuceAudioEnginePlugin.kt',
    ).readAsStringSync();
    applePlugin = File(
      'juce_audio_engine/ios/Classes/JuceAudioEnginePlugin.m',
    ).readAsStringSync();
  });

  test('temporary Bluetooth controls and probe operations are absent', () {
    final runtime = <String>[
      editor,
      routeTypes,
      androidPlugin,
      applePlugin,
    ].join('\n');
    for (final forbidden in <String>[
      'Copy Bluetooth Report',
      'Run System Recording Route Check',
      'Run Bluetooth Input + Output Check',
      'Internal audio implementation',
      'systemSelectedProbe',
      'systemSelectedMediaProbe',
      'SYSTEM_SELECTED_PROBE',
      'SYSTEM_SELECTED_MEDIA_PROBE',
      '_buildMobileBluetoothV2DebugControls',
    ]) {
      expect(runtime, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      File('lib/helpers/bluetooth_route_report_v2.dart').existsSync(),
      isFalse,
    );
  });

  test('implementation selection has no debug preference lifecycle', () {
    for (final forbidden in <String>[
      'SharedPreferences',
      'saveNextSession',
      'selectionEnabled',
      'nextSession',
      'internal.bluetooth_implementation_v2',
    ]) {
      expect(sessionResolver, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(sessionResolver, contains('active: BluetoothImplementationV2.v2'));
    expect(
      sessionResolver,
      contains('active: BluetoothImplementationV2.legacy'),
    );
  });

  test('product controls and internal diagnostics remain available', () {
    expect(editor, contains('_buildDesktopDiagnosticsLauncher'));
    expect(editor, contains("'Desktop Diagnostics'"));
    expect(editor, contains("child: const Text('Refresh')"));
    expect(editor, contains("child: const Text('Reset RT')"));
    expect(editor, contains('Widget _buildInputSelector()'));
    expect(editor, contains('Widget _buildOutputSelector()'));
    expect(editor, contains('_selectMacV2InputDevice'));
    expect(editor, contains('_selectMacOutputDevice'));
    expect(editor, contains('_buildDawAudioEngineSettingsControls'));
    expect(
      routeTypes,
      contains('final AudioRouteDuplexProbeFactsV2? duplexProbe'),
    );
    expect(androidPlugin, contains('"duplexProbe" to duplexProbeFactsV2'));
    expect(applePlugin, contains('@"duplexProbe":'));
  });

  test('reachable notices use product language', () {
    expect(editor, isNot(contains('Bluetooth 2.0')));
    expect(editor, isNot(contains('Bluetooth 2.0 checkpoint')));
    expect(
      editor,
      contains('Audio output could not be restored. Reopen the audio editor.'),
    );
    expect(
      editor,
      contains(
        'Recording stopped because the audio device changed. Press Play to continue.',
      ),
    );
  });
}
