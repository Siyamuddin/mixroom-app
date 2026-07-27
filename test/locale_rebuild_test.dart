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
