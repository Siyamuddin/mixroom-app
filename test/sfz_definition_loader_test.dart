import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/sfz_definition_loader.dart';

void expectOnlyRange(Set<int> pitches, int low, int high) {
  expect(pitches, <int>{for (var pitch = low; pitch <= high; pitch++) pitch});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SfzDefinitionLoader', () {
    test(
      'parses inherited opcodes, includes, defines, key, and note names',
      () async {
        final directory = await Directory.systemTemp.createTemp('mixroom_sfz_');
        addTearDown(() => directory.delete(recursive: true));
        final included = File('${directory.path}/included.sfz');
        await included.writeAsString('''
<group> lovel=24 hivel=96 ampeg_release=0.75
<region> sample=single.wav key=C4
<region> sample=zone.wav lokey=\$LOW hikey=G4 pitch_keycenter=E4
''');
        final root = File('${directory.path}/root.sfz');
        await root.writeAsString('''
#define \$LOW D4
<control> default_path=samples/
<global> volume=-3 ampeg_attack=0.02
#include "included.sfz"
''');

        final definition = await SfzDefinitionLoader().load(root.path);

        expect(definition, isNotNull);
        expect(definition!.regions, hasLength(2));
        final single = definition.regions.first;
        expect((single.loKey, single.hiKey, single.keyCenter), (60, 60, 60));
        expect((single.loVel, single.hiVel), (24, 96));
        expect(single.attackSec, 0.02);
        expect(single.releaseSec, 0.75);
        expect(single.sampleAssetPath, endsWith('/samples/single.wav'));
        final zone = definition.regions.last;
        expect((zone.loKey, zone.hiKey, zone.keyCenter), (62, 67, 64));
        expect(
          definition.playableInputPitches(remapPitch: (pitch) => pitch),
          <int>{60, 62, 63, 64, 65, 66, 67},
        );
      },
    );

    test(
      'deduplicates concurrent loads and fails open through a null result',
      () async {
        final directory = await Directory.systemTemp.createTemp('mixroom_sfz_');
        addTearDown(() => directory.delete(recursive: true));
        final sfz = File('${directory.path}/valid.sfz');
        await sfz.writeAsString('<region> sample=a.wav lokey=40 hikey=44');
        final loader = SfzDefinitionLoader();

        final results = await Future.wait(<Future<SfzDefinition?>>[
          loader.load(sfz.path),
          loader.load(sfz.path),
          loader.load(sfz.path),
        ]);

        expect(
          results.every((result) => identical(result, results.first)),
          isTrue,
        );
        expect(await loader.load('${directory.path}/missing.sfz'), isNull);
      },
    );

    test('preserves an explicit zero amplitude release', () async {
      final directory = await Directory.systemTemp.createTemp('mixroom_sfz_');
      addTearDown(() => directory.delete(recursive: true));
      final sfz = File('${directory.path}/zero_release.sfz');
      await sfz.writeAsString('''
<global> ampeg_release=0
<region> sample=global.wav key=60
<region> sample=region.wav key=61 ampeg_release=0
''');

      final definition = await SfzDefinitionLoader().load(sfz.path);

      expect(definition, isNotNull);
      expect(definition!.defaultReleaseSec, 0.0);
      expect(definition.regions, hasLength(2));
      expect(definition.regions.every((region) => region.releaseSec == 0.0),
          isTrue);
    });

    test(
      'applies pitch remapping and sampler key limits to sparse regions',
      () async {
        final directory = await Directory.systemTemp.createTemp('mixroom_sfz_');
        addTearDown(() => directory.delete(recursive: true));
        final sfz = File('${directory.path}/sparse.sfz');
        await sfz.writeAsString('''
<region> sample=kick.wav key=36
<region> sample=snare.wav key=38
<region> sample=hat.wav key=42
''');
        final definition = await SfzDefinitionLoader().load(sfz.path);

        final playable = definition!.playableInputPitches(
          remapPitch: (pitch) => pitch == 37 || pitch == 39 ? 38 : pitch,
          sampleLowKey: 37,
          sampleHighKey: 42,
        );

        expect(playable, <int>{37, 38, 39, 42});
        expect(playable, isNot(contains(36)));
        expect(playable, isNot(contains(40)));
      },
    );

    test('detects the production guitar and piano mappings', () async {
      final loader = SfzDefinitionLoader();
      final acoustic = await loader.load(
        'assets/instruments/FreePats-Spanish-Classical-Guitar-2019-06-18/AcousticGuitar.sfz',
      );
      final electric = await loader.load(
        'assets/instruments/Karoryfer-Black-And-Green-Guitars-1.000/ElectricGuitar.sfz',
      );
      final piano = await loader.load(
        'assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz',
      );

      expectOnlyRange(
        acoustic!.playableInputPitches(remapPitch: (pitch) => pitch),
        40,
        84,
      );
      expectOnlyRange(
        electric!.playableInputPitches(remapPitch: (pitch) => pitch),
        40,
        86,
      );
      expectOnlyRange(
        piano!.playableInputPitches(remapPitch: (pitch) => pitch),
        21,
        108,
      );
    });
  });
}
