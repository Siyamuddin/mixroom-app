import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/sample_browser_roots.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SampleBrowserRootDefaults', () {
    test('orders computed roots before persisted user roots', () {
      final roots = SampleBrowserRootDefaults.orderedRoots(
        bundledRoots: const <String>[
          '/packs/drums',
          '/packs/drums',
          '/packs/keys',
        ],
        projectAudioRoot: '/projects/song/audio',
        userDropRoot: '/documents/Mixroom Samples',
        userRoots: const <String>[
          '/documents/Mixroom Samples',
          '/samples/user',
          '/projects/song/audio',
        ],
      );

      expect(
        roots,
        const <String>[
          '/packs/drums',
          '/packs/keys',
          '/projects/song/audio',
          '/documents/Mixroom Samples',
          '/samples/user',
        ],
      );
    });

    test('marks project audio and app sample folder as fixed roots', () {
      final fixed = SampleBrowserRootDefaults.fixedRoots(
        projectAudioRoot: '/projects/song/audio',
        userDropRoot: '/documents/Mixroom Samples',
      );

      expect(
        fixed,
        containsAll(<String>[
          '/projects/song/audio',
          '/documents/Mixroom Samples',
        ]),
      );
    });

    test('persists only user-added roots', () {
      final persistable = SampleBrowserRootDefaults.persistableUserRoots(
        roots: const <String>[
          '/packs/drums',
          '/projects/song/audio',
          '/samples/user',
          '/samples/user',
          '/documents/Mixroom Samples',
          '/samples/second',
        ],
        nonPersistedRoots: const <String>[
          '/packs/drums',
          '/projects/song/audio',
          '/documents/Mixroom Samples',
        ],
      );

      expect(
        persistable,
        const <String>[
          '/samples/user',
          '/samples/second',
        ],
      );
    });

    test('detects Android shared storage roots', () {
      expect(
        SampleBrowserRootDefaults.isAndroidSharedStoragePath(
          '/storage/emulated/0/Music',
        ),
        isTrue,
      );
      expect(
        SampleBrowserRootDefaults.isAndroidSharedStoragePath(
          '/sdcard/Download',
        ),
        isTrue,
      );
      expect(
        SampleBrowserRootDefaults.isAndroidSharedStoragePath(
          '/storage/ABCD-1234',
        ),
        isTrue,
      );
      expect(
        SampleBrowserRootDefaults.isAndroidSharedStoragePath(
          '/data/user/0/com.mixroom.mixroomapp/app_flutter/project/audio',
        ),
        isFalse,
      );
    });
  });

  group('MobileSampleBrowserPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('round-trips roots per user', () async {
      await MobileSampleBrowserPrefs.saveSampleBrowserRoots(
        'user-a',
        const <String>[
          '/samples/user',
          '/samples/user',
          '  /samples/second  ',
        ],
      );
      await MobileSampleBrowserPrefs.saveSampleBrowserRoots(
        'user-b',
        const <String>['/samples/other'],
      );

      expect(
        await MobileSampleBrowserPrefs.loadSampleBrowserRoots('user-a'),
        const <String>[
          '/samples/user',
          '/samples/second',
        ],
      );
      expect(
        await MobileSampleBrowserPrefs.loadSampleBrowserRoots('user-b'),
        const <String>['/samples/other'],
      );
    });
  });
}
