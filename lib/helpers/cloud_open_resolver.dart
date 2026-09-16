import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mixroom/helpers/cloud_project_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/models/entitlement_models.dart';

const Duration kCloudOpenCheckTimeout = Duration(seconds: 6);

enum LocalOpenAction { openLocal, updateInPlace, askUser }

LocalOpenAction resolveLocalOpenAction({
  required ProjectMeta project,
  required CloudProjectAccessItem? cloud,
}) {
  final linkedCloudProjectId = (project.cloudProjectId ?? '').trim();
  if (linkedCloudProjectId.isEmpty) return LocalOpenAction.openLocal;
  if (cloud == null || !cloud.isBundleStorage) {
    return LocalOpenAction.openLocal;
  }

  final syncedFingerprint = (project.cloudSourceFingerprint ?? '').trim();
  final freshness = resolveProjectCloudFreshness(
    project: project,
    cloudStatusAvailable: true,
    latestCloudRevision: cloud.documentRevision,
  );

  // Older links have no fingerprint, so we cannot prove the device has no
  // local edits. Never overwrite those silently when the revision moved.
  if (freshness == ProjectCloudFreshness.cloudAhead &&
      syncedFingerprint.isEmpty) {
    return LocalOpenAction.askUser;
  }

  switch (freshness) {
    case ProjectCloudFreshness.cloudAhead:
      return LocalOpenAction.updateInPlace;
    case ProjectCloudFreshness.diverged:
      return LocalOpenAction.askUser;
    case ProjectCloudFreshness.synced:
    case ProjectCloudFreshness.localChanges:
    case ProjectCloudFreshness.linkedUnknown:
      return LocalOpenAction.openLocal;
  }
}

bool isNetworkUnavailableError(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException) {
    return true;
  }
  if (error is CloudProjectApiException) {
    return error.statusCode == 0 || error.statusCode >= 500;
  }
  return false;
}
