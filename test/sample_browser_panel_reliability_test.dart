import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mixroom_sample_browser_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Widget buildPanel({
    required SampleBrowserDirectoryReader directoryReader,
    double width = 420,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 680,
          child: SampleBrowserPanel(
            rootFolders: <String>[root.path],
            auditioningPath: null,
            onAuditionTap: (_) async {},
            onInsertSample: (_) async {},
            onAddFolder: () async {},
            onRemoveFolder: (_) {},
            resolveDuration: (_) async => null,
            onClose: () {},
            expanded: false,
            onExpandedChanged: (_) {},
            previewPositionStream: const Stream<Duration>.empty(),
            previewDurationStream: const Stream<Duration?>.empty(),
            previewPlaying: false,
            onPreviewSeek: (_) async {},
            directoryReader: directoryReader,
          ),
        ),
      ),
    );
  }

  Future<void> pumpDirectoryRetries(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump();
  }

  testWidgets('reserves balanced desktop gutters around tree controls',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    PlatformCapabilities.debugResetForCurrentPlatform();
    try {
      final sample = File('${root.path}/kick.wav');
      await tester.pumpWidget(
        buildPanel(
          directoryReader: (_) async => <FileSystemEntity>[sample],
        ),
      );
      await tester.pump();
      await tester.pump();

      final treeListFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.vertical,
      );
      final treeList = tester.widget<ListView>(treeListFinder);
      final padding = treeList.padding! as EdgeInsets;
      expect(padding.left, 12);
      expect(padding.right, 12);

      final listBounds = tester.getRect(treeListFinder);
      final insertButtonBounds = tester.getRect(
        find.byIcon(Icons.add_circle_outline),
      );
      final durationBounds = tester.getRect(find.text('--:--'));
      expect(
        insertButtonBounds.left - durationBounds.right,
        greaterThanOrEqualTo(6),
      );
      expect(
        listBounds.right - insertButtonBounds.right,
        greaterThanOrEqualTo(16),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      PlatformCapabilities.debugResetForCurrentPlatform();
    }
  });

  testWidgets('keeps file duration visible at minimum desktop panel width',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    PlatformCapabilities.debugResetForCurrentPlatform();
    try {
      final sample = File('${root.path}/kick.wav');
      await tester.pumpWidget(
        buildPanel(
          width: 344,
          directoryReader: (_) async => <FileSystemEntity>[sample],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('--:--'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      PlatformCapabilities.debugResetForCurrentPlatform();
    }
  });

  testWidgets('retries a transient empty Android-style directory result',
      (tester) async {
    final sample = File('${root.path}/Snare.WAV');
    var reads = 0;

    await tester.pumpWidget(
      buildPanel(
        directoryReader: (_) async {
          reads += 1;
          return reads == 1
              ? const <FileSystemEntity>[]
              : <FileSystemEntity>[sample];
        },
      ),
    );
    await pumpDirectoryRetries(tester);

    expect(reads, greaterThanOrEqualTo(2));
    expect(find.text('Snare.WAV'), findsOneWidget);
    expect(find.text('No files found.'), findsNothing);
  });

  testWidgets('does not drop a refresh requested during an active read',
      (tester) async {
    final staleSample = File('${root.path}/stale.wav');
    final currentSample = File('${root.path}/current.wav');
    final firstRead = Completer<List<FileSystemEntity>>();
    var reads = 0;

    await tester.pumpWidget(
      buildPanel(
        directoryReader: (_) {
          reads += 1;
          if (reads == 1) return firstRead.future;
          return Future<List<FileSystemEntity>>.value(
            <FileSystemEntity>[currentSample],
          );
        },
      ),
    );
    await tester.pump();
    expect(reads, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    firstRead.complete(<FileSystemEntity>[staleSample]);
    await tester.pump();
    await tester.pump();

    expect(reads, 2);
    expect(find.text('current.wav'), findsOneWidget);
    expect(find.text('stale.wav'), findsNothing);
  });

  testWidgets('re-expanding an empty folder performs a fresh read',
      (tester) async {
    final kit = Directory('${root.path}/Kit');
    await tester.runAsync(kit.create);
    final sample = File('${kit.path}/kick.wav');
    var kitReads = 0;

    await tester.pumpWidget(
      buildPanel(
        directoryReader: (path) async {
          if (path == root.path) return <FileSystemEntity>[kit];
          kitReads += 1;
          return kitReads <= 3
              ? const <FileSystemEntity>[]
              : <FileSystemEntity>[sample];
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Kit'));
    await pumpDirectoryRetries(tester);
    expect(kitReads, 3);
    expect(find.text('kick.wav'), findsNothing);

    await tester.tap(find.text('Kit'));
    await tester.pump();
    await tester.tap(find.text('Kit'));
    await tester.pump();
    await tester.pump();

    expect(kitReads, 4);
    expect(find.text('kick.wav'), findsOneWidget);
  });

  testWidgets('refreshes expanded folders after returning to the app',
      (tester) async {
    final staleSample = File('${root.path}/before.wav');
    final currentSample = File('${root.path}/after.wav');
    var reads = 0;

    await tester.pumpWidget(
      buildPanel(
        directoryReader: (_) async {
          reads += 1;
          return <FileSystemEntity>[
            reads == 1 ? staleSample : currentSample,
          ];
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('before.wav'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(reads, 2);
    expect(find.text('after.wav'), findsOneWidget);
    expect(find.text('before.wav'), findsNothing);
  });
}
