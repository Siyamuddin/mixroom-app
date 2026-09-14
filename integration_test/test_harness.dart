import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:provider/provider.dart';

class IntegrationTestAuthService extends AuthService {
  IntegrationTestAuthService() : super(restoreSessionOnInit: false);

  static final AuthUserProfile _user = AuthUserProfile(
    userId: 'integration-user',
    email: 'integration@mixroom.test',
    displayName: 'Integration Tester',
    provider: AuthProviderType.email,
    emailVerified: true,
    createdAt: DateTime.utc(2025, 1, 1),
  );

  @override
  bool get isInitializing => false;

  @override
  bool get isBusy => false;

  @override
  bool get isSignedIn => true;

  @override
  AuthUserProfile? get currentUser => _user;

  @override
  AuthUserProfile? get signedInUser => _user;

  @override
  Future<String?> getIdTokenOrNull() async => null;

  @override
  Future<void> signOut() async {}
}

class IntegrationTestEntitlementService extends EntitlementService {
  IntegrationTestEntitlementService() : super();

  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;

  @override
  String? get lastError => null;

  @override
  bool get isEnforcementEnabled => false;

  @override
  bool canUseCapability(String capability) => true;

  @override
  void bindAuth(AuthService auth) {}

  @override
  Future<void> refresh({bool force = false}) async {}
}

class IntegrationTestAppUserService extends AppUserService {
  IntegrationTestAppUserService()
      : _current =
            AppUserSnapshot.fromAuthUser(IntegrationTestAuthService._user),
        super();

  final AppUserSnapshot _current;

  @override
  AppUserSnapshot? get current => _current;

  @override
  bool get isLoading => false;

  @override
  bool get isInitialized => true;

  @override
  String? get lastError => null;

  @override
  bool get supportsRemoteProfileEdits => false;

  @override
  void bindAuth(AuthService auth) {}

  @override
  Future<void> refresh({bool force = false}) async {}
}

Widget buildIntegrationTestApp({
  required Widget home,
  AuthService? authServiceOverride,
}) {
  final authService = authServiceOverride ?? IntegrationTestAuthService();
  final entitlementService = IntegrationTestEntitlementService();
  final appUserService = IntegrationTestAppUserService();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(),
      ),
      ChangeNotifierProvider<AuthService>.value(value: authService),
      ChangeNotifierProvider<AppUserService>.value(value: appUserService),
      ChangeNotifierProvider<EntitlementService>.value(
        value: entitlementService,
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Future<void> deleteAllProjects() async {
  await _ensureIsolatedProjectRoot();
  final projects = await ProjectManager.listProjects();
  for (final project in projects) {
    await ProjectManager.deleteProject(project.dir);
  }
}

Directory? _integrationTestProjectRoot;

Future<void> _ensureIsolatedProjectRoot() async {
  if (_integrationTestProjectRoot != null) return;
  final root = await Directory.systemTemp.createTemp(
    'mixroom_integration_projects_',
  );
  _integrationTestProjectRoot = root;
  ProjectManager.setRootDirectoryForTesting(root);
}
