import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editor;
  late String sessionPolicy;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    sessionPolicy = File(
      'lib/helpers/bluetooth_implementation_session_v2.dart',
    ).readAsStringSync();
  });

  test('supported sessions select V2 without a stored debug preference', () {
    expect(sessionPolicy, contains('active: BluetoothImplementationV2.v2'));
    expect(sessionPolicy, contains('active: BluetoothImplementationV2.legacy'));
    expect(sessionPolicy, isNot(contains('SharedPreferences')));
    expect(sessionPolicy, isNot(contains('debugOverride')));
    expect(sessionPolicy, isNot(contains('saveNextSession')));
    expect(sessionPolicy, isNot(contains('selectionEnabled')));
  });

  test('editor startup has one selected implementation and no fallback', () {
    final startupStart = editor.indexOf(
      'WidgetsBinding.instance.addPostFrameCallback((_) async {',
    );
    final startupEnd = editor.indexOf(
      '_juceEngineEventSubscription ??=',
      startupStart,
    );
    final startup = editor.substring(startupStart, startupEnd);
    final sessionLoad = startup.indexOf('.loadSession()');
    final initialization = startup.indexOf(
      'JuceAudioEngine.initialiseForImplementation(',
    );
    final failure = startup.indexOf('if (!engineInitialised)');

    expect(sessionLoad, greaterThanOrEqualTo(0));
    expect(initialization, greaterThan(sessionLoad));
    expect(failure, greaterThan(initialization));
    expect(
      startup,
      contains("_showSmallNotice('Audio output is not available yet.')"),
    );
    expect(startup, isNot(contains('JuceAudioEngine.initialise();')));
    expect(startup, isNot(contains('BluetoothImplementationV2.legacy')));
  });
}
