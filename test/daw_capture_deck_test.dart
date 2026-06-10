import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/widgets/daw_capture_deck.dart';

void main() {
  Future<void> pumpDeck(
    WidgetTester tester, {
    bool desktop = true,
    bool recording = false,
    bool busy = false,
    bool canBounceSelection = true,
    bool canFreezeRow = true,
    bool canCleanUpRecording = true,
    List<double> recordingPeaks = const <double>[0.12, 0.48, 0.31, 0.76],
    VoidCallback? onClose,
    Future<void> Function()? onStartRecording,
    Future<void> Function()? onStopRecording,
    Future<void> Function()? onCaptureMix,
    Future<void> Function()? onBounceSelection,
    Future<void> Function()? onFreezeRow,
    Future<void> Function()? onCleanUpRecording,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: desktop ? 760 : 360,
              height: desktop ? 420 : 560,
              child: DawCaptureDeck(
                desktop: desktop,
                fullscreen: false,
                busy: busy,
                recording: recording,
                playing: false,
                recordingPeaks: recordingPeaks,
                selectedRowName: 'Vocals',
                selectedClipLabel: 'Lead take',
                selectedClipCount: 1,
                canBounceSelection: canBounceSelection,
                canFreezeRow: canFreezeRow,
                canCleanUpRecording: canCleanUpRecording,
                onFullscreenChanged: (_) {},
                onClose: onClose ?? () {},
                onStartRecording: onStartRecording ?? () async {},
                onStopRecording: onStopRecording ?? () async {},
                onCaptureMix: onCaptureMix ?? () async {},
                onBounceSelection: onBounceSelection ?? () async {},
                onFreezeRow: onFreezeRow ?? () async {},
                onOpenExport: () async {},
                onCleanUpRecording: onCleanUpRecording ?? () async {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('desktop capture deck exposes recording and bounce controls',
      (tester) async {
    var recordStarted = false;
    var mixCaptured = false;
    var bounced = false;
    var cleaned = false;

    await pumpDeck(
      tester,
      onStartRecording: () async => recordStarted = true,
      onCaptureMix: () async => mixCaptured = true,
      onBounceSelection: () async => bounced = true,
      onCleanUpRecording: () async => cleaned = true,
    );

    expect(find.byKey(const ValueKey('daw_capture_deck')), findsOneWidget);
    expect(find.text('Capture Deck'), findsOneWidget);
    expect(find.text('Lead take'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('capture_deck_record_button')));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('capture_deck_capture_mix_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture_deck_bounce_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture_deck_cleanup_button')));
    await tester.pump();

    expect(recordStarted, isTrue);
    expect(mixCaptured, isTrue);
    expect(bounced, isTrue);
    expect(cleaned, isTrue);
  });

  testWidgets(
      'mobile capture deck uses compact actions and disables invalid work',
      (tester) async {
    var bounced = false;
    var frozen = false;

    await pumpDeck(
      tester,
      desktop: false,
      canBounceSelection: false,
      canFreezeRow: false,
      canCleanUpRecording: false,
      onBounceSelection: () async => bounced = true,
      onFreezeRow: () async => frozen = true,
    );

    expect(find.text('Bounce'), findsOneWidget);
    expect(find.text('Freeze Track'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture_deck_bounce_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('capture_deck_freeze_button')));
    await tester.pump();

    expect(bounced, isFalse);
    expect(frozen, isFalse);
  });

  testWidgets('empty live waveform does not draw synthetic audio',
      (tester) async {
    await pumpDeck(
      tester,
      recordingPeaks: const <double>[],
    );

    expect(find.text('No live input yet'), findsOneWidget);
  });
}
