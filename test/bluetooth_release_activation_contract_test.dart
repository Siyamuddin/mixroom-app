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

  test('supported non-debug sessions select V2 before reading preferences', () {
    final loadStart = sessionPolicy.indexOf(
      'Future<BluetoothImplementationSessionV2> loadSession',
    );
    final loadEnd = sessionPolicy.indexOf(
      '\n  Future<bool> saveNextSession',
      loadStart,
    );
    final load = sessionPolicy.substring(loadStart, loadEnd);
    final releaseBranch = load.indexOf('if (!debug)');
    final v2Selection = load.indexOf(
      'active: BluetoothImplementationV2.v2',
      releaseBranch,
    );
    final preferenceRead = load.indexOf('SharedPreferences.getInstance()');

    expect(releaseBranch, greaterThanOrEqualTo(0));
    expect(v2Selection, greaterThan(releaseBranch));
    expect(v2Selection, lessThan(preferenceRead));
    expect(
      load.substring(releaseBranch, preferenceRead),
      contains('selectionEnabled: false'),
    );
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
      contains(
        "_showSmallNotice('Bluetooth 2.0 playback is not available yet.')",
      ),
    );
    expect(startup, isNot(contains('JuceAudioEngine.initialise();')));
    expect(startup, isNot(contains('BluetoothImplementationV2.legacy')));
  });
}
