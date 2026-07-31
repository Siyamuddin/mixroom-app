import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/ai_v3_clarification_options.dart';

void main() {
  test(
    'clarification session retains failures and ignores stale completion',
    () {
      final session = AiV3ClarificationSession()..activate('first');

      expect(session.activeId, 'first');
      expect(session.resolve(null), isFalse);
      expect(session.activeId, 'first');

      session.activate('follow-up');
      expect(session.resolve('first'), isFalse);
      expect(session.activeId, 'follow-up');
      expect(session.resolve('follow-up'), isTrue);
      expect(session.activeId, isNull);
    },
  );

  test('clarification session clears restored or cleared chat state', () {
    final session = AiV3ClarificationSession()..activate('active');

    session.clear();

    expect(session.activeId, isNull);
    expect(session.resolve('active'), isFalse);
  });

  testWidgets('suggested option submits its exact text only once', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final submitted = <String>[];
    await _pumpOptions(
      tester,
      options: const <String>['Lead Vocal', 'Backing Vocal'],
      onSubmit: (response) {
        submitted.add(response);
        return pending.future;
      },
    );

    final option = find.byKey(
      const ValueKey<String>('ai_v3_clarification_option_0'),
    );
    await tester.tap(option);
    await tester.pump();
    await tester.tap(option);
    await tester.pump();

    expect(submitted, <String>['Lead Vocal']);
    pending.complete(true);
    await tester.pump();
  });

  testWidgets('failed submission leaves options available for retry', (
    tester,
  ) async {
    final submitted = <String>[];
    await _pumpOptions(
      tester,
      options: const <String>['Lead Vocal'],
      onSubmit: (response) async {
        submitted.add(response);
        return false;
      },
    );

    final option = find.byKey(
      const ValueKey<String>('ai_v3_clarification_option_0'),
    );
    await tester.tap(option);
    await tester.pump();
    await tester.tap(option);
    await tester.pump();

    expect(submitted, <String>['Lead Vocal', 'Lead Vocal']);
    expect(option, findsOneWidget);
  });

  testWidgets(
    'custom response focuses, rejects empty, and submits trimmed text',
    (tester) async {
      final submitted = <String>[];
      await _pumpOptions(
        tester,
        options: const <String>['Use the selected clip'],
        onSubmit: (response) async {
          submitted.add(response);
          return true;
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('ai_v3_clarification_custom')),
      );
      await tester.pump();

      final field = find.byKey(
        const ValueKey<String>('ai_v3_clarification_custom_field'),
      );
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('ai_v3_clarification_custom_send')),
      );
      await tester.pump();
      expect(submitted, isEmpty);

      await tester.enterText(field, '  Keep both versions  ');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(submitted, <String>['Keep both versions']);
    },
  );

  testWidgets('cancel dismisses controls without submitting', (tester) async {
    final submitted = <String>[];
    var canceled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              if (canceled) return const Text('dismissed');
              return AiV3ClarificationOptions(
                options: const <String>['Continue'],
                busy: false,
                onSubmit: (response) async {
                  submitted.add(response);
                  return true;
                },
                onCancel: () => setState(() => canceled = true),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('ai_v3_clarification_cancel')),
    );
    await tester.pump();

    expect(find.text('dismissed'), findsOneWidget);
    expect(submitted, isEmpty);
  });

  testWidgets('busy state disables every clarification action', (tester) async {
    final submitted = <String>[];
    var canceled = false;
    await _pumpOptions(
      tester,
      options: const <String>['Continue'],
      busy: true,
      onSubmit: (response) async {
        submitted.add(response);
        return true;
      },
      onCancel: () => canceled = true,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('ai_v3_clarification_option_0')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ai_v3_clarification_custom')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ai_v3_clarification_cancel')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(submitted, isEmpty);
    expect(canceled, isFalse);
    expect(
      find.byKey(const ValueKey<String>('ai_v3_clarification_custom_field')),
      findsNothing,
    );
  });

  testWidgets('long options wrap within compact layouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpOptions(
      tester,
      options: const <String>[
        'Separate the stems and pitch-shift only the instrumental while preserving the original vocal stem',
      ],
      onSubmit: (_) async => true,
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('Separate the stems'));
    expect(text.maxLines, isNull);
  });

  for (final localeCase
      in const <
        ({
          Locale locale,
          String somethingElse,
          String describe,
          String cancel,
          String send,
        })
      >[
        (
          locale: Locale('en'),
          somethingElse: 'Something else…',
          describe: 'Describe what you want',
          cancel: 'Cancel',
          send: 'Send response',
        ),
        (
          locale: Locale('ko'),
          somethingElse: '다른 요청…',
          describe: '원하는 내용을 입력하세요',
          cancel: '취소',
          send: '응답 보내기',
        ),
        (
          locale: Locale('ja'),
          somethingElse: 'その他の内容…',
          describe: '希望する内容を入力してください',
          cancel: 'キャンセル',
          send: '回答を送信',
        ),
      ]) {
    testWidgets(
      'clarification controls are localized for ${localeCase.locale.languageCode}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpOptions(
            tester,
            locale: localeCase.locale,
            options: const <String>['Option'],
            onSubmit: (_) async => true,
          );

          expect(find.text(localeCase.somethingElse), findsOneWidget);
          expect(find.text(localeCase.cancel), findsOneWidget);
          expect(
            find.bySemanticsLabel(localeCase.somethingElse),
            findsAtLeast(1),
          );
          expect(find.bySemanticsLabel(localeCase.cancel), findsAtLeast(1));
          await tester.tap(
            find.byKey(const ValueKey<String>('ai_v3_clarification_custom')),
          );
          await tester.pump();
          final field = tester.widget<TextField>(
            find.byKey(
              const ValueKey<String>('ai_v3_clarification_custom_field'),
            ),
          );
          expect(field.decoration?.hintText, localeCase.describe);
          expect(find.byTooltip(localeCase.send), findsOneWidget);
          expect(find.bySemanticsLabel(localeCase.send), findsAtLeast(1));
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

Future<void> _pumpOptions(
  WidgetTester tester, {
  required List<String> options,
  required AiV3ClarificationSubmit onSubmit,
  Locale locale = const Locale('en'),
  bool busy = false,
  VoidCallback? onCancel,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: AiV3ClarificationOptions(
              options: options,
              busy: busy,
              onSubmit: onSubmit,
              onCancel: onCancel ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}
