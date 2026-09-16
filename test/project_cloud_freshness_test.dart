import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';

void main() {
  ProjectMeta project({
    int? revision = 4,
    String syncedFingerprint = 'same',
    String sourceFingerprint = 'same',
  }) {
    return ProjectMeta(
      dir: Directory('/tmp/cloud-freshness-test'),
      name: 'Cloud project',
      projectId: 'local-1',
      cloudProjectId: 'cloud-1',
      cloudDocumentRevision: revision,
      cloudSourceFingerprint: syncedFingerprint,
      sourceFingerprint: sourceFingerprint,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  test('distinguishes synced, local, cloud, and diverged project states', () {
    expect(
      resolveProjectCloudFreshness(
        project: project(),
        cloudStatusAvailable: true,
        latestCloudRevision: 4,
      ),
      ProjectCloudFreshness.synced,
    );
    expect(
      resolveProjectCloudFreshness(
        project: project(sourceFingerprint: 'local-edit'),
        cloudStatusAvailable: true,
        latestCloudRevision: 4,
      ),
      ProjectCloudFreshness.localChanges,
    );
    expect(
      resolveProjectCloudFreshness(
        project: project(),
        cloudStatusAvailable: true,
        latestCloudRevision: 5,
      ),
      ProjectCloudFreshness.cloudAhead,
    );
    expect(
      resolveProjectCloudFreshness(
        project: project(sourceFingerprint: 'local-edit'),
        cloudStatusAvailable: true,
        latestCloudRevision: 5,
      ),
      ProjectCloudFreshness.diverged,
    );
  });

  test('does not claim synced when the latest cloud state is unavailable', () {
    expect(
      resolveProjectCloudFreshness(
        project: project(),
        cloudStatusAvailable: false,
      ),
      ProjectCloudFreshness.linkedUnknown,
    );
  });

  test('empty fingerprint is never treated as synced', () {
    expect(
      resolveProjectCloudFreshness(
        project: project(syncedFingerprint: ''),
        cloudStatusAvailable: true,
        latestCloudRevision: 4,
      ),
      ProjectCloudFreshness.linkedUnknown,
    );
    expect(
      resolveProjectCloudFreshness(
        project: project(syncedFingerprint: ''),
        cloudStatusAvailable: true,
        latestCloudRevision: 5,
      ),
      ProjectCloudFreshness.cloudAhead,
    );
  });
}
