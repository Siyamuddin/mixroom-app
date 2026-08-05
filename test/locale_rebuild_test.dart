import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/video_projects_placeholder.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('translated widgets rebuild immediately when locale changes', (
    tester,
  ) async {
    final localeProvider = LocaleProvider();
    final dependencyChanges = ValueNotifier<int>(0);

    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleProvider>.value(
        value: localeProvider,
        child: Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            return MaterialApp(
              locale: L10n.resolveSupportedLocale(provider.locale),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: _LocaleDependencyProbe(
                  dependencyChanges: dependencyChanges,
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Language'), findsOneWidget);
    expect(dependencyChanges.value, 1);

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();

    expect(find.text('언어'), findsOneWidget);
    expect(dependencyChanges.value, 2);

    dependencyChanges.dispose();
  });

  testWidgets('signed-in content surfaces respond to locale changes', (
    tester,
  ) async {
    final localeProvider = LocaleProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleProvider>.value(
        value: localeProvider,
        child: Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            return MaterialApp(
              locale: L10n.resolveSupportedLocale(provider.locale),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(body: VideoProjectsPlaceholderView()),
            );
          },
        ),
      ),
    );

    expect(find.text('Video Projects'), findsOneWidget);

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();

    expect(find.text('비디오 프로젝트'), findsOneWidget);
  });

  testWidgets('AI execution conflict message uses every supported locale', (
    tester,
  ) async {
    const messageKey =
        'Another AI change is still being applied. Please wait for it to finish.';
    final localeProvider = LocaleProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleProvider>.value(
        value: localeProvider,
        child: Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            return MaterialApp(
              locale: L10n.resolveSupportedLocale(provider.locale),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Builder(
                  builder: (context) =>
                      Text(L10n.translate(context, messageKey)),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text(messageKey), findsOneWidget);

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();
    expect(
      find.text('다른 AI 변경 사항을 적용하는 중입니다. 완료될 때까지 기다려 주세요.'),
      findsOneWidget,
    );

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(
      find.text('別のAI変更を適用中です。完了するまでお待ちください。'),
      findsOneWidget,
    );
  });

  testWidgets('instrument change notice uses every supported locale', (
    tester,
  ) async {
    const messageKey = 'Changed {row} instrument to {instrument}';
    final localeProvider = LocaleProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleProvider>.value(
        value: localeProvider,
        child: Consumer<LocaleProvider>(
          builder: (context, provider, _) {
            return MaterialApp(
              locale: L10n.resolveSupportedLocale(provider.locale),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Builder(
                  builder: (context) => Text(
                    L10n.translate(context, messageKey)
                        .replaceAll('{row}', 'Custom Keys')
                        .replaceAll('{instrument}', 'Dream Pad'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(
      find.text('Changed Custom Keys instrument to Dream Pad'),
      findsOneWidget,
    );

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();
    expect(
      find.text('Custom Keys: 악기를 Dream Pad로 변경했습니다'),
      findsOneWidget,
    );

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(
      find.text('Custom KeysのインストゥルメントをDream Padに変更しました'),
      findsOneWidget,
    );
  });
}

class _LocaleDependencyProbe extends StatefulWidget {
  const _LocaleDependencyProbe({required this.dependencyChanges});

  final ValueNotifier<int> dependencyChanges;

  @override
  State<_LocaleDependencyProbe> createState() => _LocaleDependencyProbeState();
}

class _LocaleDependencyProbeState extends State<_LocaleDependencyProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.dependencyChanges.value += 1;
  }

  @override
  Widget build(BuildContext context) {
    return Text(L10n.translate(context, 'Language'));
  }
}
