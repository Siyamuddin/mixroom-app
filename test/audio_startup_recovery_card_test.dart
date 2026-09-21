import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/audio_startup_recovery_card.dart';

const _messageKey =
    'Audio is unavailable, so this project has not loaded. Your saved project remains unchanged.';
const _backgroundButtonKey = Key('background_editor_action');

Widget _recoveryApp({
  Locale locale = const Locale('en'),
  VoidCallback? onRetry,
  VoidCallback? onBack,
  VoidCallback? onBackgroundPressed,
  bool retryInProgress = false,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          if (onBackgroundPressed != null)
            Center(
              child: FilledButton(
                key: _backgroundButtonKey,
                onPressed: onBackgroundPressed,
                child: const Text('Underlying editor action'),
              ),
            ),
          Positioned.fill(
            child: Builder(
              builder: (context) => AudioStartupRecoveryCard(
                title: L10n.translate(context, "Audio couldn't start."),
                message: L10n.translate(context, _messageKey),
                retryLabel: L10n.translate(context, 'Retry'),
                backLabel: L10n.translate(context, 'Back'),
                retryInProgress: retryInProgress,
                onRetry: onRetry,
                onBack: onBack,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('blocks interaction and exposes working recovery actions', (
    tester,
  ) async {
    var retryCount = 0;
    var backCount = 0;
    var backgroundCount = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _recoveryApp(
        onRetry: () => retryCount += 1,
        onBack: () => backCount += 1,
        onBackgroundPressed: () => backgroundCount += 1,
      ),
    );

    expect(find.byKey(AudioStartupRecoveryCard.overlayKey), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(find.text("Audio couldn't start."), findsOneWidget);
    expect(find.text(_messageKey), findsOneWidget);
    expect(
      find.bySemanticsLabel("Audio couldn't start. $_messageKey"),
      findsOneWidget,
    );

    final retrySize = tester.getSize(
      find.byKey(AudioStartupRecoveryCard.retryButtonKey),
    );
    final backSize = tester.getSize(
      find.byKey(AudioStartupRecoveryCard.backButtonKey),
    );
    expect(retrySize.width, greaterThanOrEqualTo(44));
    expect(retrySize.height, greaterThanOrEqualTo(44));
    expect(backSize.width, greaterThanOrEqualTo(44));
    expect(backSize.height, greaterThanOrEqualTo(44));

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.byKey(_backgroundButtonKey), warnIfMissed: false);
    expect(retryCount, 1);
    expect(backCount, 1);
    expect(backgroundCount, 0);
    semantics.dispose();
  });

  testWidgets('localized recovery copy fits narrow layouts', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const expectedMessages = <(Locale, String)>[
      (
        Locale('en'),
        'Audio is unavailable, so this project has not loaded. Your saved project remains unchanged.',
      ),
      (Locale('ko'), '오디오를 사용할 수 없어 프로젝트를 불러오지 못했습니다. 저장된 프로젝트는 변경되지 않았습니다.'),
      (Locale('ja'), 'オーディオを利用できないため、プロジェクトは読み込まれていません。保存済みのプロジェクトは変更されていません。'),
    ];

    for (final entry in expectedMessages) {
      await tester.pumpWidget(_recoveryApp(locale: entry.$1));
      await tester.pump();
      expect(find.text(entry.$2), findsOneWidget);
      expect(tester.takeException(), isNull, reason: entry.$1.languageCode);
    }
  });

  testWidgets('retry progress prevents duplicate recovery actions', (
    tester,
  ) async {
    var retryCount = 0;
    var backCount = 0;
    await tester.pumpWidget(
      _recoveryApp(
        retryInProgress: true,
        onRetry: () => retryCount += 1,
        onBack: () => backCount += 1,
      ),
    );

    await tester.tap(
      find.byKey(AudioStartupRecoveryCard.retryButtonKey),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(AudioStartupRecoveryCard.backButtonKey),
      warnIfMissed: false,
    );
    expect(retryCount, 0);
    expect(backCount, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
