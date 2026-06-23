import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/auth_gate.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Android back returns create account to sign in', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var systemPopCount = 0;
      await _setSystemNavigatorPopHandler(tester, () {
        systemPopCount += 1;
      });

      await _pumpAndroidAuthGate(tester);

      await tester.tap(_pillButton('Create account'));
      await tester.pumpAndSettle();

      expect(_createAccountStage(), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_createAccountStage(), findsNothing);
      expect(find.text('Sign In'), findsOneWidget);
      expect(systemPopCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android root back exits only after a second press',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var systemPopCount = 0;
      await _setSystemNavigatorPopHandler(tester, () {
        systemPopCount += 1;
      });

      await _pumpAndroidAuthGate(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Press back again to exit Mixroom'), findsOneWidget);
      expect(systemPopCount, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(systemPopCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Finder _pillButton(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is MixroomPillButton && widget.label == label,
    description: 'MixroomPillButton labeled "$label"',
  );
}

Finder _createAccountStage() {
  return find.byWidgetPredicate(
    (widget) =>
        widget.key == const ValueKey('create-account-stage') ||
        widget.key == const ValueKey('tablet-create-account-stage'),
    description: 'create account stage',
  );
}

Future<void> _setSystemNavigatorPopHandler(
  WidgetTester tester,
  VoidCallback onPop,
) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') {
        onPop();
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}

Future<void> _pumpAndroidAuthGate(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  final localeProvider = LocaleProvider();
  final authService = AuthService(restoreSessionOnInit: false);
  final appUserService = AppUserService();
  addTearDown(localeProvider.dispose);
  addTearDown(authService.dispose);
  addTearDown(appUserService.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<AppUserService>.value(value: appUserService),
      ],
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
            home: const AuthGate(),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
