import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/bluetooth_implementation_session_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = BluetoothImplementationPreferencesV2();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('debug macOS defaults to Legacy', () async {
    final session = await preferences.loadSession(
      debugOverride: true,
      platformOverride: TargetPlatform.macOS,
    );

    expect(session.active, BluetoothImplementationV2.legacy);
    expect(session.nextSession, BluetoothImplementationV2.legacy);
    expect(session.selectionEnabled, isTrue);
  });

  test('debug macOS persists V2 for the next session', () async {
    final saved = await preferences.saveNextSession(
      BluetoothImplementationV2.v2,
      debugOverride: true,
      platformOverride: TargetPlatform.macOS,
    );
    final session = await preferences.loadSession(
      debugOverride: true,
      platformOverride: TargetPlatform.macOS,
    );

    expect(saved, isTrue);
    expect(session.active, BluetoothImplementationV2.v2);
    expect(session.nextSession, BluetoothImplementationV2.v2);
  });

  test('debug Android persists V2 for the next session', () async {
    final saved = await preferences.saveNextSession(
      BluetoothImplementationV2.v2,
      debugOverride: true,
      platformOverride: TargetPlatform.android,
    );
    final session = await preferences.loadSession(
      debugOverride: true,
      platformOverride: TargetPlatform.android,
    );

    expect(saved, isTrue);
    expect(session.active, BluetoothImplementationV2.v2);
    expect(session.nextSession, BluetoothImplementationV2.v2);
    expect(session.selectionEnabled, isTrue);
  });

  test('debug iOS persists V2 for the next session', () async {
    final saved = await preferences.saveNextSession(
      BluetoothImplementationV2.v2,
      debugOverride: true,
      platformOverride: TargetPlatform.iOS,
    );
    final session = await preferences.loadSession(
      debugOverride: true,
      platformOverride: TargetPlatform.iOS,
    );

    expect(saved, isTrue);
    expect(session.active, BluetoothImplementationV2.v2);
    expect(session.nextSession, BluetoothImplementationV2.v2);
    expect(session.selectionEnabled, isTrue);
  });

  test('changing the next session never changes the active implementation', () {
    const session = BluetoothImplementationSessionV2(
      active: BluetoothImplementationV2.legacy,
      nextSession: BluetoothImplementationV2.legacy,
      selectionEnabled: true,
    );

    final changed = session.withNextSession(BluetoothImplementationV2.v2);

    expect(changed.active, BluetoothImplementationV2.legacy);
    expect(changed.nextSession, BluetoothImplementationV2.v2);
  });

  test(
    'release and unsupported sessions force Legacy and ignore writes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        BluetoothImplementationPreferencesV2.preferenceKey: 'v2',
      });

      for (final configuration in <({bool debug, TargetPlatform platform})>[
        (debug: false, platform: TargetPlatform.macOS),
        (debug: false, platform: TargetPlatform.android),
        (debug: false, platform: TargetPlatform.iOS),
        (debug: true, platform: TargetPlatform.windows),
      ]) {
        final session = await preferences.loadSession(
          debugOverride: configuration.debug,
          platformOverride: configuration.platform,
        );
        final saved = await preferences.saveNextSession(
          BluetoothImplementationV2.v2,
          debugOverride: configuration.debug,
          platformOverride: configuration.platform,
        );

        expect(session.active, BluetoothImplementationV2.legacy);
        expect(session.nextSession, BluetoothImplementationV2.legacy);
        expect(session.selectionEnabled, isFalse);
        expect(saved, isFalse);
      }
    },
  );
}
