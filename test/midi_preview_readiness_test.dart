import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mixroom/helpers/midi_preview_readiness.dart';

void main() {
  test('only mobile platforms require playback-route preparation', () {
    expect(midiPreviewNeedsMobileRoute(TargetPlatform.android), isTrue);
    expect(midiPreviewNeedsMobileRoute(TargetPlatform.iOS), isTrue);
    expect(midiPreviewNeedsMobileRoute(TargetPlatform.macOS), isFalse);
    expect(midiPreviewNeedsMobileRoute(TargetPlatform.windows), isFalse);
    expect(midiPreviewNeedsMobileRoute(TargetPlatform.linux), isFalse);
  });

  test(
    'runs route, processor update, target, then preview can proceed',
    () async {
      final calls = <String>[];
      final ready = await ensureMidiPreviewReady(
        prepareRoute: () async {
          calls.add('route');
          return true;
        },
        updateProcessor: () async {
          calls.add('update');
          return true;
        },
        reloadProcessor: () async {
          calls.add('reload');
          return true;
        },
        assignLiveTarget: () async {
          calls.add('target');
          return true;
        },
        isStillValid: () => true,
      );

      if (ready) calls.add('preview');
      expect(ready, isTrue);
      expect(calls, <String>['route', 'update', 'target', 'preview']);
    },
  );

  test('route failure stops before processor, target, or preview', () async {
    final calls = <String>[];
    final ready = await ensureMidiPreviewReady(
      prepareRoute: () async {
        calls.add('route');
        return false;
      },
      updateProcessor: () async {
        calls.add('update');
        return true;
      },
      reloadProcessor: () async {
        calls.add('reload');
        return true;
      },
      assignLiveTarget: () async {
        calls.add('target');
        return true;
      },
      isStillValid: () => true,
    );

    if (ready) calls.add('preview');
    expect(ready, isFalse);
    expect(calls, <String>['route']);
  });

  test('target failure reloads once and retries target once', () async {
    final calls = <String>[];
    var targetAttempts = 0;
    final ready = await ensureMidiPreviewReady(
      prepareRoute: () async {
        calls.add('route');
        return true;
      },
      updateProcessor: () async {
        calls.add('update');
        return true;
      },
      reloadProcessor: () async {
        calls.add('reload');
        return true;
      },
      assignLiveTarget: () async {
        calls.add('target');
        return ++targetAttempts == 2;
      },
      isStillValid: () => true,
    );

    if (ready) calls.add('preview');
    expect(ready, isTrue);
    expect(calls, <String>[
      'route',
      'update',
      'target',
      'reload',
      'target',
      'preview',
    ]);
  });

  test('two failed target assignments stop without another reload', () async {
    final calls = <String>[];
    final ready = await ensureMidiPreviewReady(
      prepareRoute: () async {
        calls.add('route');
        return true;
      },
      updateProcessor: () async {
        calls.add('update');
        return true;
      },
      reloadProcessor: () async {
        calls.add('reload');
        return true;
      },
      assignLiveTarget: () async {
        calls.add('target');
        return false;
      },
      isStillValid: () => true,
    );

    if (ready) calls.add('preview');
    expect(ready, isFalse);
    expect(calls, <String>['route', 'update', 'target', 'reload', 'target']);
  });

  test('processor update failure uses its only reload before target', () async {
    final calls = <String>[];
    final ready = await ensureMidiPreviewReady(
      prepareRoute: () async {
        calls.add('route');
        return true;
      },
      updateProcessor: () async {
        calls.add('update');
        return false;
      },
      reloadProcessor: () async {
        calls.add('reload');
        return true;
      },
      assignLiveTarget: () async {
        calls.add('target');
        return false;
      },
      isStillValid: () => true,
    );

    expect(ready, isFalse);
    expect(calls, <String>['route', 'update', 'reload', 'target']);
  });
}
