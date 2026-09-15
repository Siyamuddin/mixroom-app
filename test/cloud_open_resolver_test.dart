import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/helpers/cloud_open_resolver.dart';
import 'package:mixroom/helpers/cloud_project_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/models/entitlement_models.dart';

void main() {
  ProjectMeta project({
    String? cloudProjectId = 'cloud-1',
    int? revision = 4,
    String syncedFingerprint = 'same',
    String sourceFingerprint = 'same',
  }) {
    return ProjectMeta(
      dir: Directory('/tmp/cloud-open-resolver-test'),
      name: 'Cloud project',
      projectId: 'local-1',
      cloudProjectId: cloudProjectId,
      cloudDocumentRevision: revision,
      cloudSourceFingerprint: syncedFingerprint.isEmpty
          ? null
          : syncedFingerprint,
      sourceFingerprint: sourceFingerprint,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  CloudProjectAccessItem cloud({
    int revision = 4,
    String storageMode = 'blob_mixroom',
    String projectId = 'cloud-1',
  }) {
    const emptyUser = CloudProjectUserSummary(
      userId: '',
      username: '',
      displayName: '',
    );
    return CloudProjectAccessItem(
      projectId: projectId,
      workspaceId: '',
      organizationId: '',
      ownerUserId: '',
      updatedByUserId: '',
      name: 'Cloud project',
      status: 'active',
      visibility: '',
      storageMode: storageMode,
      storageProvider: 'r2',
      documentRevision: revision,
      documentSizeBytes: 0,
      localProjectId: 'local-1',
      canWrite: true,
      ownerProfile: emptyUser,
      updatedByProfile: emptyUser,
    );
  }

  test(
    'opens local when the project is unlinked or the cloud item is gone',
    () {
      expect(
        resolveLocalOpenAction(
          project: project(cloudProjectId: null),
          cloud: cloud(),
        ),
        LocalOpenAction.openLocal,
      );
      expect(
        resolveLocalOpenAction(
          project: project(cloudProjectId: ''),
          cloud: cloud(),
        ),
        LocalOpenAction.openLocal,
      );
      expect(
        resolveLocalOpenAction(project: project(), cloud: null),
        LocalOpenAction.openLocal,
      );
      expect(
        resolveLocalOpenAction(
          project: project(),
          cloud: cloud(storageMode: 'metadata_only'),
        ),
        LocalOpenAction.openLocal,
      );
    },
  );

  test('opens local when synced or only this device has edits', () {
    expect(
      resolveLocalOpenAction(project: project(), cloud: cloud()),
      LocalOpenAction.openLocal,
    );
    expect(
      resolveLocalOpenAction(
        project: project(sourceFingerprint: 'local-edit'),
        cloud: cloud(),
      ),
      LocalOpenAction.openLocal,
    );
  });

  test('updates in place when the cloud is ahead and the device is clean', () {
    expect(
      resolveLocalOpenAction(project: project(), cloud: cloud(revision: 5)),
      LocalOpenAction.updateInPlace,
    );
  });

  test('asks the user when both sides have different edits', () {
    expect(
      resolveLocalOpenAction(
        project: project(sourceFingerprint: 'local-edit'),
        cloud: cloud(revision: 5),
      ),
      LocalOpenAction.askUser,
    );
  });

  test(
    'asks the user when an older link has no fingerprint and the cloud moved',
    () {
      expect(
        resolveLocalOpenAction(
          project: project(syncedFingerprint: ''),
          cloud: cloud(revision: 5),
        ),
        LocalOpenAction.askUser,
      );
    },
  );

  test(
    'opens local when an older link has no fingerprint and revisions match',
    () {
      expect(
        resolveLocalOpenAction(
          project: project(syncedFingerprint: ''),
          cloud: cloud(revision: 4),
        ),
        LocalOpenAction.openLocal,
      );
    },
  );

  test('classifies offline and timeout failures as network-unavailable', () {
    expect(isNetworkUnavailableError(const SocketException('offline')), isTrue);
    expect(
      isNetworkUnavailableError(http.ClientException('connection failed')),
      isTrue,
    );
    expect(isNetworkUnavailableError(TimeoutException('timed out')), isTrue);
    expect(
      isNetworkUnavailableError(
        const CloudProjectApiException(
          path: '/v1/cloud-projects/me',
          statusCode: 503,
          body: 'unavailable',
          message: 'unavailable',
        ),
      ),
      isTrue,
    );
    expect(
      isNetworkUnavailableError(
        const CloudProjectApiException(
          path: '/v1/cloud-projects/me',
          statusCode: 0,
          body: '',
          message: 'failed',
        ),
      ),
      isTrue,
    );
    expect(
      isNetworkUnavailableError(
        const CloudProjectApiException(
          path: '/v1/cloud-projects/me',
          statusCode: 409,
          body: 'revision conflict',
          message: 'revision conflict',
        ),
      ),
      isFalse,
    );
    expect(isNetworkUnavailableError(StateError('boom')), isFalse);
  });
}
