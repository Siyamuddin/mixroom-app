import 'package:mixroom/config/hackathon_config.dart';

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CloudProjectUploadResult {
  const CloudProjectUploadResult({
    required this.project,
    required this.storage,
  });

  final CloudProjectAccessItem project;
  final CloudProjectStorageSummary storage;
}

class CloudProjectDownloadResult {
  const CloudProjectDownloadResult({
    required this.project,
    required this.file,
  });

  final CloudProjectAccessItem project;
  final File file;
}

class CloudProjectApiException implements Exception {
  const CloudProjectApiException({
    required this.path,
    required this.statusCode,
    required this.body,
    required this.message,
  });

  final String path;
  final int statusCode;
  final String body;
  final String message;

  @override
  String toString() => 'Request $path failed ($statusCode): $body';
}

class CloudProjectService {
  CloudProjectService({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  void close() {
    _httpClient.close();
  }

  Future<CloudProjectAccessSnapshot> listProjects({
    required AuthService auth,
  }) async {
    final json = await _getAuthed(auth, '/v1/cloud-projects/me');
    return CloudProjectAccessSnapshot.fromJson(json);
  }

  Future<CloudProjectUploadResult> uploadBundle({
    required AuthService auth,
    required File bundleFile,
    required String projectId,
    required String name,
    String? cloudProjectId,
    String? workspaceId,
    String? organizationId,
    int? expectedRevision,
  }) async {
    final sizeBytes = await bundleFile.length();
    try {
      return await _uploadBundleWithSize(
        auth: auth,
        bundleFile: bundleFile,
        projectId: projectId,
        name: name,
        sizeBytes: sizeBytes,
        cloudProjectId: cloudProjectId,
        workspaceId: workspaceId,
        organizationId: organizationId,
        expectedRevision: expectedRevision,
      );
    } on CloudProjectApiException catch (error) {
      if (!_isForeignCloudProjectError(error) ||
          (cloudProjectId ?? '').trim().isEmpty) {
        rethrow;
      }
      return _uploadBundleWithSize(
        auth: auth,
        bundleFile: bundleFile,
        projectId: projectId,
        name: name,
        sizeBytes: sizeBytes,
        workspaceId: workspaceId,
        organizationId: organizationId,
      );
    }
  }

  Future<CloudProjectUploadResult> _uploadBundleWithSize({
    required AuthService auth,
    required File bundleFile,
    required String projectId,
    required String name,
    required int sizeBytes,
    String? cloudProjectId,
    String? workspaceId,
    String? organizationId,
    int? expectedRevision,
  }) async {
    final initPayload = await _postAuthed(
      auth,
      '/v1/cloud-projects/me',
      body: <String, dynamic>{
        if ((cloudProjectId ?? '').trim().isNotEmpty)
          'project_id': cloudProjectId!.trim(),
        if ((workspaceId ?? '').trim().isNotEmpty)
          'workspace_id': workspaceId!.trim(),
        if ((organizationId ?? '').trim().isNotEmpty)
          'organization_id': organizationId!.trim(),
        'local_project_id': projectId,
        'name': name,
        'size_bytes': sizeBytes,
        if (expectedRevision != null) 'expected_revision': expectedRevision,
      },
    );
    final initProject = _mapPayload(initPayload['cloud_project']);
    final resolvedCloudProjectId =
        (initProject['project_id'] ?? '').toString().trim();
    final uploadUrl = (initProject['upload_url'] ?? '').toString();
    if (uploadUrl.isEmpty) {
      throw StateError('Cloud upload URL was not returned.');
    }
    final uploadHeaders = _stringMap(initProject['upload_headers'] as Object?);
    await _putFileToSignedUrl(
      uploadUrl: uploadUrl,
      headers: uploadHeaders,
      file: bundleFile,
      sizeBytes: sizeBytes,
    );

    final completePayload = await _postAuthed(
      auth,
      '/v1/cloud-projects/${Uri.encodeComponent(resolvedCloudProjectId.isEmpty ? projectId : resolvedCloudProjectId)}/complete',
    );
    return CloudProjectUploadResult(
      project:
          CloudProjectAccessItem.fromJson(completePayload['cloud_project']),
      storage: CloudProjectStorageSummary.fromJson(initPayload['storage']),
    );
  }

  bool _isForeignCloudProjectError(CloudProjectApiException error) {
    return error.statusCode == 403 &&
        error.message.toLowerCase().contains('belongs to another account');
  }

  Future<CloudProjectDownloadResult> downloadBundle({
    required AuthService auth,
    required CloudProjectAccessItem project,
  }) async {
    final payload = await _getAuthed(
      auth,
      '/v1/cloud-projects/${Uri.encodeComponent(project.projectId)}/download',
    );
    final detail = _mapPayload(payload['cloud_project']);
    final downloadUrl = (detail['download_url'] ?? '').toString();
    if (downloadUrl.isEmpty) {
      throw StateError('Cloud download URL was not returned.');
    }
    final tempDir = await getTemporaryDirectory();
    final safeName =
        _safeFileStem(project.name.isEmpty ? project.projectId : project.name);
    final file = File(
      p.join(
        tempDir.path,
        'mixroom_cloud_${project.projectId}_$safeName.mixroom',
      ),
    );
    await _downloadSignedUrl(downloadUrl: downloadUrl, file: file);
    return CloudProjectDownloadResult(
      project: CloudProjectAccessItem.fromJson(detail),
      file: file,
    );
  }

  Future<void> deleteProject({
    required AuthService auth,
    required String projectId,
  }) async {
    await _deleteAuthed(
      auth,
      '/v1/cloud-projects/${Uri.encodeComponent(projectId)}',
    );
  }

  Future<Map<String, dynamic>> _getAuthed(
    AuthService auth,
    String path,
  ) async {
    final response = await auth.authorizedRequest(
      (token) => _httpClient.get(
        _buildUri(path),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      expireSessionOnAuthFailure: false,
    );
    return _decode(path: path, response: response);
  }

  Future<Map<String, dynamic>> _postAuthed(
    AuthService auth,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await auth.authorizedRequest(
      (token) => _httpClient
          .post(
            _buildUri(path),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body ?? const <String, dynamic>{}),
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      expireSessionOnAuthFailure: false,
    );
    return _decode(path: path, response: response);
  }

  Future<Map<String, dynamic>> _deleteAuthed(
    AuthService auth,
    String path,
  ) async {
    final response = await auth.authorizedRequest(
      (token) => _httpClient.delete(
        _buildUri(path),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      expireSessionOnAuthFailure: false,
    );
    return _decode(path: path, response: response);
  }

  Future<void> _putFileToSignedUrl({
    required String uploadUrl,
    required Map<String, String> headers,
    required File file,
    required int sizeBytes,
  }) async {
    final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
    request.contentLength = sizeBytes;
    request.headers.addAll(headers);
    final responseFuture = _httpClient.send(request);
    await file.openRead().pipe(request.sink);
    final response = await responseFuture.timeout(const Duration(minutes: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw StateError('Cloud upload failed (${response.statusCode}): $body');
    }
  }

  Future<void> _downloadSignedUrl({
    required String downloadUrl,
    required File file,
  }) async {
    final request = http.Request('GET', Uri.parse(downloadUrl));
    final response =
        await _httpClient.send(request).timeout(const Duration(minutes: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw StateError('Cloud download failed (${response.statusCode}): $body');
    }
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  Map<String, dynamic> _decode({
    required String path,
    required http.Response response,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {
        // Keep the raw response body for malformed error payloads.
      }
      throw CloudProjectApiException(
        path: path,
        statusCode: response.statusCode,
        body: response.body,
        message: message,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('Request $path returned invalid response payload.');
  }

  Uri _buildUri(String path) {
    if (HackathonConfig.enabled) {
      throw StateError(
        'Cloud project synchronization is disabled in this build.',
      );
    }
    final base = AppApiConfig.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, dynamic> _mapPayload(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  String _safeFileStem(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return cleaned.isEmpty ? 'MixroomProject' : cleaned;
  }
}
