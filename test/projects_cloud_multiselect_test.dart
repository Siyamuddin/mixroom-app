import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cloud_project_service.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory projectRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    projectRoot = await Directory.systemTemp.createTemp(
      'mixroom_cloud_multiselect_',
    );
    ProjectManager.setRootDirectoryForTesting(projectRoot);
    ProjectManager.cloudProjectSyncInFlight.value = const <String>{};
  });

  tearDown(() {
    ProjectManager.setRootDirectoryForTesting(null);
    ProjectManager.cloudProjectSyncInFlight.value = const <String>{};
    if (projectRoot.existsSync()) {
      projectRoot.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'cloud selection mirrors local interactions and excludes restricted cards',
    (tester) async {
      final service = _FakeCloudProjectService(<CloudProjectAccessItem>[
        _cloudProject('owner-a', ownerUserId: 'user-1'),
        _cloudProject('owner-b', ownerUserId: 'user-1'),
        _cloudProject('other-owner', ownerUserId: 'user-2'),
        _cloudProject('read-only', ownerUserId: 'user-1', canWrite: false),
      ]);
      addTearDown(service.close);
      await _pumpProjects(tester, service);

      await _openCloudTab(tester);
      expect(_cloudCard('owner-a'), findsOneWidget);

      await tester.ensureVisible(_cloudCard('other-owner'));
      await tester.tap(_cloudMenuButton('other-owner'));
      await _pumpFrames(tester);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Delete from Cloud'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await _pumpFrames(tester);

      await tester.ensureVisible(_cloudCard('owner-a'));
      await tester.tap(_cloudMenuButton('owner-a'));
      await _pumpFrames(tester);
      expect(find.text('Delete from Cloud'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await _pumpFrames(tester);

      await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
      await tester.pump();
      expect(find.text('0 Projects'), findsOneWidget);

      await tester.tap(_cloudCard('owner-a'));
      await tester.pump();
      expect(find.text('1 Projects'), findsOneWidget);
      expect(
        tester.getSemantics(_cloudCard('owner-a')).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await tester.tap(_cloudCard('other-owner'));
      await tester.pump();
      expect(find.text('1 Projects'), findsOneWidget);
      expect(
        find.text('Only the project owner can delete this cloud project.'),
        findsOneWidget,
      );

      await tester.tap(_cloudCard('read-only'));
      await tester.pump();
      expect(find.text('1 Projects'), findsOneWidget);
      expect(
        find.text(
          'This cloud project is read-only. Renew or unlock it to make changes.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('projects_selection_cancel')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('projects_selection_delete')),
        findsNothing,
      );

      await tester.longPress(_cloudCard('owner-b'));
      await tester.pump();
      expect(find.text('1 Projects'), findsOneWidget);
      await tester.tap(find.text('On Device').first);
      await _pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('projects_selection_delete')),
        findsNothing,
      );
      await _openCloudTab(tester);
      expect(
        tester.getSemantics(_cloudCard('owner-b')).flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );

      addTearDown(() => ProjectManager.endCloudProjectSync('owner-b'));
      await tester.longPress(_cloudCard('owner-b'));
      await tester.pump();
      ProjectManager.beginCloudProjectSync('owner-b');
      await _pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('projects_selection_delete')),
        findsNothing,
      );
      ProjectManager.endCloudProjectSync('owner-b');
      await _pumpFrames(tester);

      ScaffoldMessenger.of(
        tester.element(_cloudCard('other-owner')),
      ).clearSnackBars();
      await tester.pump();
      expect(service.downloadedProjectIds, isEmpty);
      await tester.ensureVisible(_cloudCard('other-owner'));
      await tester.pump();
      await tester.tap(
        find
            .descendant(
              of: _cloudCard('other-owner'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await _pumpFrames(tester, frames: 20);
      expect(service.downloadedProjectIds, <String>['other-owner']);
    },
  );

  testWidgets('cloud Select all selects only deletable visible projects', (
    tester,
  ) async {
    final service = _FakeCloudProjectService(<CloudProjectAccessItem>[
      _cloudProject('owner-a', ownerUserId: 'user-1'),
      _cloudProject('owner-b', ownerUserId: 'user-1'),
      _cloudProject('other-owner', ownerUserId: 'user-2'),
      _cloudProject('read-only', ownerUserId: 'user-1', canWrite: false),
    ]);
    addTearDown(service.close);
    await _pumpProjects(tester, service);
    await _openCloudTab(tester);

    await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
    await tester.pump();
    final toolsButton = find.byWidgetPredicate(
      (widget) =>
          widget is MixroomShellRoundButton &&
          widget.assetPath == kMixroomShellFilterAsset,
    );
    await tester.tap(toolsButton);
    await _pumpFrames(tester);
    await tester.tap(find.text('Select all'));
    await _pumpFrames(tester);

    expect(find.text('2 Projects'), findsOneWidget);
    expect(
      tester.getSemantics(_cloudCard('owner-a')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(_cloudCard('owner-b')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(_cloudCard('other-owner')).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(
      tester.getSemantics(_cloudCard('read-only')).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );

    await tester.tap(find.byKey(const ValueKey('projects_selection_cancel')));
    await tester.enterText(find.byType(TextField), 'owner-b');
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
    await tester.pump();
    await tester.tap(toolsButton);
    await _pumpFrames(tester);
    await tester.tap(find.text('Select all'));
    await _pumpFrames(tester);
    expect(find.text('1 Projects'), findsOneWidget);
    expect(
      tester.getSemantics(_cloudCard('owner-b')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('cloud bulk delete can be cancelled and succeeds sequentially', (
    tester,
  ) async {
    final service = _FakeCloudProjectService(<CloudProjectAccessItem>[
      _cloudProject('owner-a', ownerUserId: 'user-1'),
      _cloudProject('owner-b', ownerUserId: 'user-1'),
    ]);
    final entitlement = _FakeEntitlementService(service.snapshot);
    addTearDown(service.close);
    await _pumpProjects(tester, service, entitlement: entitlement);
    await _openCloudTab(tester);
    final listCallsBeforeDelete = service.listProjectsCalls;

    await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
    await tester.tap(_cloudCard('owner-a'));
    await tester.tap(_cloudCard('owner-b'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('projects_selection_delete')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('projects_delete_cancel')));
    await _pumpFrames(tester);
    expect(service.deletedProjectIds, isEmpty);
    expect(find.text('2 Projects'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('projects_selection_delete')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('projects_delete_confirm')));
    await _pumpFrames(tester, frames: 20);

    expect(service.deletedProjectIds, <String>['owner-a', 'owner-b']);
    expect(service.listProjectsCalls, listCallsBeforeDelete + 1);
    expect(entitlement.refreshCalls, 1);
    expect(_cloudCard('owner-a'), findsNothing);
    expect(_cloudCard('owner-b'), findsNothing);
    expect(
      find.byKey(const ValueKey('projects_selection_delete')),
      findsNothing,
    );
  });

  testWidgets('cloud delete revalidates the account after confirmation', (
    tester,
  ) async {
    final service = _FakeCloudProjectService(<CloudProjectAccessItem>[
      _cloudProject('owner-a', ownerUserId: 'user-1'),
    ]);
    final auth = _signedInAuth();
    addTearDown(service.close);
    await _pumpProjects(tester, service, auth: auth);
    await _openCloudTab(tester);

    await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
    await tester.tap(_cloudCard('owner-a'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('projects_selection_delete')));
    await _pumpFrames(tester);
    _primeSignedInAuth(auth, userId: 'user-2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('projects_delete_confirm')));
    await _pumpFrames(tester);

    expect(service.deletedProjectIds, isEmpty);
    expect(
      find.textContaining('Cloud project access changed.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'bulk cloud delete preserves local copy and retains failed selection',
    (tester) async {
      final localDir = (await tester.runAsync(
        () => ProjectManager.createNewProjectDir(name: 'Local Cloud Copy'),
      ))!;
      final localJson = await ProjectManager.readProjectJson(localDir);
      localJson
        ..['cloudProjectId'] = 'owner-a'
        ..['cloudWorkspaceId'] = 'workspace-1'
        ..['cloudOrganizationId'] = 'organization-1'
        ..['cloudDocumentRevision'] = 7
        ..['cloudSourceFingerprint'] = 'fingerprint'
        ..['cloudSyncedAt'] = '2026-09-15T00:00:00Z';
      await ProjectManager.writeProjectJson(localDir, localJson);

      final service = _FakeCloudProjectService(<CloudProjectAccessItem>[
        _cloudProject(
          'owner-a',
          ownerUserId: 'user-1',
          localProjectId: localJson['projectId'].toString(),
        ),
        _cloudProject('owner-b', ownerUserId: 'user-1'),
      ])..failedProjectIds.add('owner-b');
      addTearDown(service.close);
      await _pumpProjects(tester, service);
      await _openCloudTab(tester);

      await tester.tap(find.byKey(const ValueKey('projects_selection_toggle')));
      await tester.pump();
      await tester.tap(_cloudCard('owner-a'));
      await tester.tap(_cloudCard('owner-b'));
      await tester.pump();
      expect(find.text('2 Projects'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('projects_selection_delete')));
      await _pumpFrames(tester);
      expect(
        find.text(
          '2 cloud projects will be deleted from cloud storage. Local copies on this device will remain.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('projects_delete_confirm')));
      await _pumpFrames(tester, frames: 20);

      expect(service.deletedProjectIds, <String>['owner-a', 'owner-b']);
      expect(_cloudCard('owner-a'), findsNothing);
      expect(_cloudCard('owner-b'), findsOneWidget);
      expect(find.text('1 Projects'), findsOneWidget);
      expect(
        find.textContaining('1 cloud project could not be deleted.'),
        findsOneWidget,
      );

      expect(localDir.existsSync(), isTrue);
      final preservedJson = await ProjectManager.readProjectJson(localDir);
      for (final key in <String>[
        'cloudProjectId',
        'cloudWorkspaceId',
        'cloudOrganizationId',
        'cloudDocumentRevision',
        'cloudSourceFingerprint',
        'cloudSyncedAt',
      ]) {
        expect(preservedJson.containsKey(key), isFalse, reason: key);
      }
    },
  );
}

Finder _cloudCard(String projectId) =>
    find.byKey(ValueKey('cloud_project_card_$projectId'));

Finder _cloudMenuButton(String projectId) => find.descendant(
  of: _cloudCard(projectId),
  matching: find.byType(MixroomShellRoundButton),
);

Future<void> _openCloudTab(WidgetTester tester) async {
  await tester.tap(find.text('Cloud').first);
  await _pumpFrames(tester, frames: 30);
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpProjects(
  WidgetTester tester,
  _FakeCloudProjectService service, {
  AuthService? auth,
  _FakeEntitlementService? entitlement,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final locale = LocaleProvider();
  final resolvedAuth = auth ?? _signedInAuth();
  final resolvedEntitlement =
      entitlement ?? _FakeEntitlementService(service.snapshot);
  addTearDown(locale.dispose);
  addTearDown(resolvedAuth.dispose);
  addTearDown(resolvedEntitlement.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<AuthService>.value(value: resolvedAuth),
        ChangeNotifierProvider<EntitlementService>.value(
          value: resolvedEntitlement,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ProjectsScreen(
          hideDemoProjects: true,
          cloudProjectService: service,
        ),
      ),
    ),
  );
  await _pumpFrames(tester, frames: 30);
}

AuthService _signedInAuth() {
  final auth = AuthService(restoreSessionOnInit: false);
  _primeSignedInAuth(auth, userId: 'user-1');
  return auth;
}

void _primeSignedInAuth(AuthService auth, {required String userId}) {
  auth.debugPrimeSession(
    user: AuthUserProfile(
      userId: userId,
      email: '$userId@example.com',
      displayName: userId,
      provider: AuthProviderType.email,
      emailVerified: true,
      createdAt: DateTime.utc(2026, 9, 15),
    ),
    tokens: CognitoTokens(
      accessToken: 'access-token',
      idToken: 'id-token',
      refreshToken: 'rt_valid_refresh_secret',
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ),
  );
}

CloudProjectAccessItem _cloudProject(
  String projectId, {
  required String ownerUserId,
  bool canWrite = true,
  String localProjectId = '',
}) {
  return CloudProjectAccessItem(
    projectId: projectId,
    workspaceId: '',
    organizationId: '',
    ownerUserId: ownerUserId,
    updatedByUserId: ownerUserId,
    name: projectId,
    status: 'active',
    visibility: 'personal',
    storageMode: 'blob_mixroom',
    storageProvider: 's3',
    documentRevision: 7,
    documentSizeBytes: 2048,
    localProjectId: localProjectId,
    canWrite: canWrite,
    ownerProfile: CloudProjectUserSummary(
      userId: ownerUserId,
      username: '',
      displayName: ownerUserId,
    ),
    updatedByProfile: CloudProjectUserSummary(
      userId: ownerUserId,
      username: '',
      displayName: ownerUserId,
    ),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 15),
  );
}

class _FakeCloudProjectService extends CloudProjectService {
  _FakeCloudProjectService(List<CloudProjectAccessItem> projects)
    : _projects = List<CloudProjectAccessItem>.from(projects);

  final List<CloudProjectAccessItem> _projects;
  final Set<String> failedProjectIds = <String>{};
  final List<String> deletedProjectIds = <String>[];
  final List<String> downloadedProjectIds = <String>[];
  int listProjectsCalls = 0;

  CloudProjectAccessSnapshot get snapshot => CloudProjectAccessSnapshot(
    cloudProjects: List<CloudProjectAccessItem>.from(_projects),
    summary: CollaborationAccessSummary(
      organizationCount: 1,
      workspaceCount: 1,
      cloudProjectCount: _projects.length,
    ),
    configurable: true,
    storage: CloudProjectStorageSummary(
      usedBytes: _projects.fold<int>(
        0,
        (total, project) => total + project.documentSizeBytes,
      ),
      limitBytes: 1024 * 1024,
      projectCount: _projects.length,
      projectLimit: 10,
      locations: const <CloudProjectStorageLocation>[],
    ),
  );

  @override
  Future<CloudProjectAccessSnapshot> listProjects({
    required AuthService auth,
  }) async {
    listProjectsCalls += 1;
    return snapshot;
  }

  @override
  Future<void> deleteProject({
    required AuthService auth,
    required String projectId,
  }) async {
    deletedProjectIds.add(projectId);
    if (failedProjectIds.contains(projectId)) {
      throw const CloudProjectApiException(
        path: '/v1/cloud-projects/test',
        statusCode: 500,
        body: '{"error":"failed"}',
        message: 'failed',
      );
    }
    _projects.removeWhere((project) => project.projectId == projectId);
  }

  @override
  Future<CloudProjectDownloadResult> downloadBundle({
    required AuthService auth,
    required CloudProjectAccessItem project,
  }) async {
    downloadedProjectIds.add(project.projectId);
    throw StateError('Download stopped by test.');
  }
}

class _FakeEntitlementService extends EntitlementService {
  _FakeEntitlementService(this._snapshot);

  final CloudProjectAccessSnapshot _snapshot;
  int refreshCalls = 0;

  @override
  bool get areCloudProjectsEnabled => true;

  @override
  bool get isEnforcementEnabled => false;

  @override
  CloudProjectAccessSnapshot get cloudProjectsAccess => _snapshot;

  @override
  bool canUseCapability(String capability) => true;

  @override
  Future<void> refreshAccountSurface({bool force = false}) async {
    refreshCalls += 1;
  }
}
