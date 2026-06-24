import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/desktop_editor_prefs.dart';

void main() {
  group('DesktopPluginPrefs', () {
    test('round-trips cached plugin catalog', () {
      const prefs = DesktopPluginPrefs(
        favoritePluginIds: <String>{'hosted:vst3:/plugin-a.vst3'},
        hiddenPluginIds: <String>{'hosted:vst3:/plugin-b.vst3'},
        scanPaths: <String>['/Library/Audio/Plug-Ins/VST3'],
        cachedPlugins: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'hosted:vst3:/plugin-a.vst3',
            'name': 'Plugin A',
            'format': 'VST3',
            'manufacturer': 'Acme',
            'category': 'effect',
            'isInstrument': false,
            'favorite': true,
            'hidden': false,
          },
          <String, dynamic>{
            'id': 'audiounit:instrument',
            'name': 'Instrument',
            'format': 'AudioUnit',
            'category': 'instrument',
            'isInstrument': true,
          },
        ],
        lastRescanAtMs: 1234,
      );

      final restored = DesktopPluginPrefs.fromJson(prefs.toJson());

      expect(restored.favoritePluginIds, prefs.favoritePluginIds);
      expect(restored.hiddenPluginIds, prefs.hiddenPluginIds);
      expect(restored.scanPaths, prefs.scanPaths);
      expect(restored.lastRescanAtMs, 1234);
      expect(restored.cachedPlugins, hasLength(2));
      expect(restored.cachedPlugins.first['name'], 'Plugin A');
      expect(restored.cachedPlugins.last['isInstrument'], isTrue);
    });

    test('drops malformed cached plugin entries', () {
      final restored = DesktopPluginPrefs.fromJson(
        <String, dynamic>{
          'favoritePluginIds': <String>[],
          'hiddenPluginIds': <String>[],
          'scanPaths': <String>[],
          'cachedPlugins': <Object?>[
            <String, dynamic>{'id': 'valid', 'name': 'Valid'},
            <String, dynamic>{'id': 'missing-name'},
            <String, dynamic>{'name': 'Missing ID'},
          ],
        },
      );

      expect(restored.cachedPlugins, hasLength(1));
      expect(restored.cachedPlugins.single['id'], 'valid');
    });
  });
}
