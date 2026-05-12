import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/cloud_project_service.dart';
import 'package:mixroom/helpers/cognito_auth_client.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'uploadBundle creates a new cloud copy when local link belongs to '
      'another account', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('mixroom_cloud_test_');
    final bundleFile = File('${tempDir.path}/project.mixroom');
    await bundleFile.writeAsString('bundle');

    final auth = AuthService(restoreSessionOnInit: false);
    auth.debugPrimeSession(
      user: AuthUserProfile(
        userId: 'current-user',
        email: 'current@example.com',
        displayName: 'Current User',
        provider: AuthProviderType.email,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 7),
      ),
      tokens: CognitoTokens(
        accessToken: 'access-token',
        idToken: 'id-token',
        refreshToken: 'rt_valid_refresh_secret',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );

    final initBodies = <Map<String, dynamic>>[];
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' &&
          request.url.path.endsWith('/v1/cloud-projects/me')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        initBodies.add(body);
        if (initBodies.length == 1) {
          expect(body['project_id'], 'old-cloud-project');
          expect(body['expected_revision'], 7);
          return http.Response(
            jsonEncode(<String, String>{
              'error': 'Cloud project belongs to another account.',
            }),
            403,
          );
        }
        expect(body.containsKey('project_id'), isFalse);
        expect(body.containsKey('expected_revision'), isFalse);
        return _jsonResponse(<String, dynamic>{
          'cloud_project': <String, dynamic>{
            'project_id': 'new-cloud-project',
            'upload_url': 'https://uploads.example.com/new-cloud-project',
            'upload_headers': <String, String>{},
          },
          'storage': <String, dynamic>{
            'used_bytes': 0,
            'limit_bytes': 2147483648,
            'project_count': 2,
            'project_limit': 10,
          },
        });
      }
      if (request.method == 'PUT' &&
          request.url.host == 'uploads.example.com') {
        return http.Response('', 200);
      }
      if (request.method == 'POST' &&
          request.url.path
              .endsWith('/v1/cloud-projects/new-cloud-project/complete')) {
        return _jsonResponse(<String, dynamic>{
          'cloud_project': <String, dynamic>{
            'project_id': 'new-cloud-project',
            'name': 'Local Project',
            'user_id': 'current-user',
            'document_revision': 1,
            'document_size_bytes': 6,
            'local_project_id': 'local-project',
          },
        });
      }
      return http.Response('unexpected request', 500);
    });

    final service = CloudProjectService(httpClient: client);
    try {
      final result = await service.uploadBundle(
        auth: auth,
        bundleFile: bundleFile,
        projectId: 'local-project',
        name: 'Local Project',
        cloudProjectId: 'old-cloud-project',
        expectedRevision: 7,
      );

      expect(result.project.projectId, 'new-cloud-project');
      expect(result.storage.projectCount, 2);
      expect(result.storage.projectLimit, 10);
      expect(initBodies, hasLength(2));
      expect(requests, <String>[
        'POST /prod/v1/cloud-projects/me',
        'POST /prod/v1/cloud-projects/me',
        'PUT /new-cloud-project',
        'POST /prod/v1/cloud-projects/new-cloud-project/complete',
      ]);
    } finally {
      service.close();
      await tempDir.delete(recursive: true);
    }
  });

  test('uploadBundle sends workspace destination when provided', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('mixroom_cloud_test_');
    final bundleFile = File('${tempDir.path}/project.mixroom');
    await bundleFile.writeAsString('bundle');

    final auth = AuthService(restoreSessionOnInit: false);
    auth.debugPrimeSession(
      user: AuthUserProfile(
        userId: 'current-user',
        email: 'current@example.com',
        displayName: 'Current User',
        provider: AuthProviderType.email,
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 7),
      ),
      tokens: CognitoTokens(
        accessToken: 'access-token',
        idToken: 'id-token',
        refreshToken: 'rt_valid_refresh_secret',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );

    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/v1/cloud-projects/me')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['workspace_id'], 'ws-1');
        expect(body['organization_id'], 'org-1');
        return _jsonResponse(<String, dynamic>{
          'cloud_project': <String, dynamic>{
            'project_id': 'workspace-cloud-project',
            'workspace_id': 'ws-1',
            'organization_id': 'org-1',
            'upload_url': 'https://uploads.example.com/workspace-cloud-project',
            'upload_headers': <String, String>{},
          },
          'storage': <String, dynamic>{
            'used_bytes': 0,
            'project_count': 1,
          },
        });
      }
      if (request.method == 'PUT' &&
          request.url.host == 'uploads.example.com') {
        return http.Response('', 200);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith(
            '/v1/cloud-projects/workspace-cloud-project/complete',
          )) {
        return _jsonResponse(<String, dynamic>{
          'cloud_project': <String, dynamic>{
            'project_id': 'workspace-cloud-project',
            'workspace_id': 'ws-1',
            'organization_id': 'org-1',
            'name': 'Studio Project',
            'user_id': 'current-user',
            'storage_mode': 'blob_mixroom',
            'document_revision': 1,
            'document_size_bytes': 6,
            'local_project_id': 'local-project',
          },
        });
      }
      return http.Response('unexpected request', 500);
    });

    final service = CloudProjectService(httpClient: client);
    try {
      final result = await service.uploadBundle(
        auth: auth,
        bundleFile: bundleFile,
        projectId: 'local-project',
        name: 'Studio Project',
        workspaceId: 'ws-1',
        organizationId: 'org-1',
      );

      expect(result.project.projectId, 'workspace-cloud-project');
      expect(result.project.workspaceId, 'ws-1');
      expect(result.project.organizationId, 'org-1');
    } finally {
      service.close();
      await tempDir.delete(recursive: true);
    }
  });
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{'Content-Type': 'application/json'},
  );
}
