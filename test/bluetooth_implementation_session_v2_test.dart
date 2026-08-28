import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/bluetooth_implementation_session_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const resolver = BluetoothImplementationSessionResolverV2();

  test('supported sessions always use V2', () async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      final session = await resolver.loadSession(platformOverride: platform);

      expect(session.active, BluetoothImplementationV2.v2);
      expect(session.allowsLegacyInputLifecycle, isFalse);
    }
  });

  test('unsupported sessions remain Legacy', () async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final session = await resolver.loadSession(platformOverride: platform);

      expect(session.active, BluetoothImplementationV2.legacy);
      expect(session.allowsLegacyInputLifecycle, isTrue);
    }
  });

  test('runtime selection has no persisted debug preference', () {
    final source = File(
      'lib/helpers/bluetooth_implementation_session_v2.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('SharedPreferences')));
    expect(source, isNot(contains('saveNextSession')));
    expect(source, isNot(contains('selectionEnabled')));
    expect(source, isNot(contains('nextSession')));
    expect(source, isNot(contains('internal.bluetooth_implementation_v2')));
  });
}
