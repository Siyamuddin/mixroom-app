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
    expect(find.text('Custom Keys: 악기를 Dream Pad로 변경했습니다'), findsOneWidget);

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(find.text('Custom KeysのインストゥルメントをDream Padに変更しました'), findsOneWidget);
  });

  testWidgets('project cloud actions and destination picker are localized', (
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
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: <Widget>[
                      Text(L10n.translate(context, 'Delete from Device')),
                      Text(L10n.translate(context, 'Download & Open')),
                      Text(L10n.translate(context, 'Sync to Cloud')),
                      Text(L10n.translate(context, 'Sync Now')),
                      Text(L10n.translate(context, 'Save project to')),
                      Text(L10n.translate(context, 'Sync project to')),
                      Text(L10n.translate(context, 'Personal Cloud')),
                      Text(
                        L10n.translate(
                          context,
                          'Only you can access this project',
                        ),
                      ),
                      Text(L10n.translate(context, 'Shared Cloud')),
                      Text(
                        L10n.translate(context, 'Shared cloud project space'),
                      ),
                      Text(L10n.translate(context, 'Current cloud location')),
                      Text(
                        L10n.translate(context, 'Create a new cloud copy here'),
                      ),
                      Text(L10n.translate(context, 'Team project space')),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Delete from Device'), findsOneWidget);
    expect(find.text('Download & Open'), findsOneWidget);
    expect(find.text('Sync to Cloud'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
    expect(find.text('Save project to'), findsOneWidget);
    expect(find.text('Sync project to'), findsOneWidget);
    expect(find.text('Personal Cloud'), findsOneWidget);
    expect(find.text('Only you can access this project'), findsOneWidget);
    expect(find.text('Shared Cloud'), findsOneWidget);
    expect(find.text('Shared cloud project space'), findsOneWidget);
    expect(find.text('Current cloud location'), findsOneWidget);
    expect(find.text('Create a new cloud copy here'), findsOneWidget);
    expect(find.text('Team project space'), findsOneWidget);

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에서 삭제'), findsOneWidget);
    expect(find.text('다운로드하여 열기'), findsOneWidget);
    expect(find.text('클라우드에 동기화'), findsOneWidget);
    expect(find.text('지금 동기화'), findsOneWidget);
    expect(find.text('프로젝트 저장 위치'), findsOneWidget);
    expect(find.text('프로젝트 동기화 위치'), findsOneWidget);
    expect(find.text('개인 클라우드'), findsOneWidget);
    expect(find.text('나만 이 프로젝트에 접근할 수 있습니다'), findsOneWidget);
    expect(find.text('공유 클라우드'), findsOneWidget);
    expect(find.text('공유 클라우드 프로젝트 공간'), findsOneWidget);
    expect(find.text('현재 클라우드 위치'), findsOneWidget);
    expect(find.text('여기에 새 클라우드 복사본 만들기'), findsOneWidget);
    expect(find.text('팀 프로젝트 공간'), findsOneWidget);

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(find.text('このデバイスから削除'), findsOneWidget);
    expect(find.text('ダウンロードして開く'), findsOneWidget);
    expect(find.text('クラウドに同期'), findsOneWidget);
    expect(find.text('今すぐ同期'), findsOneWidget);
    expect(find.text('プロジェクトの保存先'), findsOneWidget);
    expect(find.text('プロジェクトの同期先'), findsOneWidget);
    expect(find.text('パーソナルクラウド'), findsOneWidget);
    expect(find.text('このプロジェクトには自分だけがアクセスできます'), findsOneWidget);
    expect(find.text('共有クラウド'), findsOneWidget);
    expect(find.text('共有クラウドのプロジェクトスペース'), findsOneWidget);
    expect(find.text('現在のクラウド保存先'), findsOneWidget);
    expect(find.text('ここに新しいクラウドコピーを作成'), findsOneWidget);
    expect(find.text('チームプロジェクトスペース'), findsOneWidget);
  });

  testWidgets('cloud multi-select copy is localized', (tester) async {
    const keys = <String>[
      'Only the project owner can delete this cloud project.',
      'Please wait for this cloud project to finish syncing.',
      'Cloud project access changed. Review your selection and try again.',
      '{count} cloud projects will be deleted from cloud storage. Local copies on this device will remain.',
      '1 cloud project will be deleted from cloud storage. Local copies on this device will remain.',
      '{count} cloud projects deleted.',
      '1 cloud project deleted.',
      '{count} cloud projects could not be deleted.',
      '1 cloud project could not be deleted.',
      '{count} local copies could not be unlinked from cloud.',
      '1 local copy could not be unlinked from cloud.',
      'Select cloud project {name}',
      'Deselect cloud project {name}',
      'Cloud project {name} cannot be selected for deletion',
      'Open cloud project {name}',
    ];
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
                body: SingleChildScrollView(
                  child: Builder(
                    builder: (context) => Column(
                      children: keys
                          .map((key) => Text(L10n.translate(context, key)))
                          .toList(growable: false),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    for (final key in keys) {
      expect(find.text(key), findsOneWidget);
    }

    await localeProvider.setLocale(const Locale('ko'));
    await tester.pumpAndSettle();
    for (final key in keys) {
      expect(find.text(key), findsNothing, reason: 'Korean: $key');
    }

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    for (final key in keys) {
      expect(find.text(key), findsNothing, reason: 'Japanese: $key');
    }
  });

  testWidgets('new-row sample drop label uses every supported locale', (
    tester,
  ) async {
    const messageKey = 'Drop to create a new row';
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
                    L10n.translate(context, messageKey),
                  ),
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
    expect(find.text('놓아서 새 트랙 만들기'), findsOneWidget);

    await localeProvider.setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(find.text('ドロップして新しいトラックを作成'), findsOneWidget);
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
