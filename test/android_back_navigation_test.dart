import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
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

  testWidgets('visible create account back returns to sign in', (tester) async {
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

      await tester.tap(find.byType(MixroomAuthBackCircleButton));
      await tester.pumpAndSettle();

      expect(_createAccountStage(), findsNothing);
      expect(find.text('Sign In'), findsOneWidget);
      expect(systemPopCount, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android back does nothing when visible auth back is disabled',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var systemPopCount = 0;
      await _setSystemNavigatorPopHandler(tester, () {
        systemPopCount += 1;
      });

      final authService = _MutableBusyAuthService();
      await _pumpAndroidAuthGate(tester, authService: authService);

      await tester.tap(_pillButton('Create account'));
      await tester.pumpAndSettle();

      authService.setBusy(true);
      await tester.pump();
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(_createAccountStage(), findsOneWidget);
      expect(find.text('Press back again to exit Mixroom'), findsNothing);
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

  testWidgets('Android back on required profile uses the screen back action',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var systemPopCount = 0;
      await _setSystemNavigatorPopHandler(tester, () {
        systemPopCount += 1;
      });

      final authService = _signedInAuthService();
      final appUserService = _IncompleteAppUserService();
      await _pumpAndroidAuthGate(
        tester,
        authService: authService,
        appUserService: appUserService,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('required_profile')),
      );

      expect(find.byKey(const ValueKey('required_profile')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const ValueKey('required_profile')), findsNothing);
      expect(_createAccountStage(), findsOneWidget);
      expect(find.text('Press back again to exit Mixroom'), findsNothing);
      expect(systemPopCount, 0);
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

Future<void> _pumpAndroidAuthGate(
  WidgetTester tester, {
  AuthService? authService,
  AppUserService? appUserService,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  final localeProvider = LocaleProvider();
  final auth = authService ?? AuthService(restoreSessionOnInit: false);
  final appUser = appUserService ?? AppUserService();
  appUser.bindAuth(auth);
  addTearDown(localeProvider.dispose);
  addTearDown(auth.dispose);
  addTearDown(appUser.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppUserService>.value(value: appUser),
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

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AuthService _signedInAuthService() {
  final auth = AuthService(
    cognitoClient: _NoopCognitoAuthClient(),
    restoreSessionOnInit: false,
  );
  final user = AuthUserProfile(
    userId: 'user-1',
    email: 'user@example.com',
    displayName: 'User One',
    provider: AuthProviderType.email,
    emailVerified: true,
    createdAt: DateTime.utc(2026, 3, 20),
  );
  final tokens = CognitoTokens(
    accessToken: 'access-token',
    idToken: 'id-token',
    refreshToken: 'rt_test-session_secret',
    expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );
  auth.debugPrimeSession(user: user, tokens: tokens);
  return auth;
}

class _NoopCognitoAuthClient extends CognitoAuthClient {
  @override
  Future<void> signOut({required String accessToken}) async {}
}

class _MutableBusyAuthService extends AuthService {
  _MutableBusyAuthService() : super(restoreSessionOnInit: false);

  bool _busy = false;

  @override
  bool get isBusy => _busy;

  void setBusy(bool busy) {
    _busy = busy;
    notifyListeners();
  }
}

class _IncompleteAppUserService extends AppUserService {
  final AppUserSnapshot _profile = AppUserSnapshot.fromAuthUser(
    AuthUserProfile(
      userId: 'user-1',
      email: 'user@example.com',
      displayName: 'User One',
      provider: AuthProviderType.email,
      emailVerified: true,
      createdAt: DateTime.utc(2026, 3, 20),
    ),
  );

  @override
  AppUserSnapshot? get current => _profile;

  @override
  bool get isLoading => false;

  @override
  bool get isInitialized => true;

  @override
  String? get lastError => null;

  @override
  bool get supportsRemoteProfileEdits => true;

  @override
  bool get hasPendingSignupProfileSync => false;

  @override
  bool get isResolvingPostSignIn => false;

  @override
  void bindAuth(AuthService auth) {}
}
