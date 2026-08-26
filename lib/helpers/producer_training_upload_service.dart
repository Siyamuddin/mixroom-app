import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/helpers/auth_service.dart';

class ProducerTrainingUploadService {
  ProducerTrainingUploadService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  bool _draining = false;

  Future<void> deleteSession({
    required AuthService auth,
    required String sessionId,
  }) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) return;
    final path =
        '/v1/producer-training/sessions/${Uri.encodeComponent(normalized)}';
    final response = await auth.authorizedRequest(
      (token) => _httpClient
          .delete(
            _uri(path),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      expireSessionOnAuthFailure: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Producer training deletion failed (${response.statusCode}).',
      );
    }
  }

  Future<void> drainPending({
    required AuthService auth,
    required ProducerDataCollector collector,
  }) async {
    if (_draining || !auth.isSignedIn || !AppApiConfig.hasApiBaseUrl) return;
    _draining = true;
    try {
      for (final file in await collector.listPendingUploadFiles()) {
        await _uploadOne(auth: auth, collector: collector, file: file);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _uploadOne({
    required AuthService auth,
    required ProducerDataCollector collector,
    required File file,
  }) async {
    try {
      await collector.updateUploadStatus(file, 'uploading');
      final rawDocument = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
      final document = _sanitizeProducerTrainingBundle(rawDocument);
      final bytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(document),
      );
      await file.writeAsBytes(bytes, flush: true);
      final sessionId = (document['session_id'] ?? '').toString().trim();
      if (sessionId.isEmpty) throw StateError('Capture session ID is missing.');
      final checksum = sha256.convert(bytes).toString();
      final reserve = await _postAuthed(
        auth,
        '/v1/producer-training/sessions/uploads',
        <String, dynamic>{
          'session_id': sessionId,
          'schema_version': document['schema_version'],
          'consent_version': document['consent_version'],
          'feature_extractor_version': document['feature_extractor_version'],
          'segmentation_version': document['segmentation_version'],
          'size_bytes': bytes.length,
          'sha256': checksum,
          'media_manifest': document['media_manifest'] ?? const [],
        },
      );
      final uploadUrl = (reserve['upload_url'] ?? '').toString();
      if (uploadUrl.isEmpty) throw StateError('Upload URL was not returned.');
      final headers = <String, String>{
        for (final entry
            in ((reserve['upload_headers'] as Map?) ?? const {}).entries)
          entry.key.toString(): entry.value.toString(),
      };
      final putResponse = await _httpClient
          .put(Uri.parse(uploadUrl), headers: headers, body: bytes)
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds * 3));
      if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
        throw HttpException(
          'Signed upload failed (${putResponse.statusCode}).',
        );
      }
      await _postAuthed(
        auth,
        '/v1/producer-training/sessions/${Uri.encodeComponent(sessionId)}/complete',
        <String, dynamic>{
          'sha256': checksum,
          'size_bytes': bytes.length,
          'schema_version': document['schema_version'],
          'consent_version': document['consent_version'],
          'feature_extractor_version': document['feature_extractor_version'],
          'segmentation_version': document['segmentation_version'],
          'media_manifest': document['media_manifest'] ?? const [],
        },
      );
      await collector.updateUploadStatus(file, 'uploaded');
    } catch (error) {
      await collector.updateUploadStatus(
        file,
        'retry_needed',
        error: error.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _postAuthed(
    AuthService auth,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await auth.authorizedRequest(
      (token) => _httpClient
          .post(
            _uri(path),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds)),
      expireSessionOnAuthFailure: false,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Request $path failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  Uri _uri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
  }

  void close() => _httpClient.close();
}

Map<String, dynamic> _sanitizeProducerTrainingBundle(
  Map<String, dynamic> document,
) {
  const removedKeys = <String>{
    'project_name',
    'row_name',
    'clip_name',
    'file',
    'filename',
    'file_name',
    'path',
    'source_path',
    'source_file',
    'source_file_path',
    'authorization',
    'access_token',
    'refresh_token',
    'id_token',
    'api_key',
    'email',
    'username',
    'input_device_name',
  };

  Object? sanitize(Object? value, {String key = ''}) {
    final normalizedKey = key.toLowerCase();
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!removedKeys.contains(entry.key.toString().toLowerCase()) &&
              !entry.key.toString().toLowerCase().contains('file_name') &&
              !entry.key.toString().toLowerCase().contains('filepath'))
            entry.key.toString(): sanitize(
              entry.value,
              key: entry.key.toString(),
            ),
      };
    }
    if (value is Iterable) {
      return value.map((item) => sanitize(item, key: key)).toList();
    }
    if (value is! String) return value;
    if (normalizedKey.contains('path') || normalizedKey.contains('file')) {
      return '[redacted]';
    }
    return value
        .replaceAll(
          RegExp(
            r'(?:file://)?/(?:Users|Library|Applications|System|Volumes|private|var|tmp)/[^\s"\x27<>]+',
          ),
          '[local-path]',
        )
        .replaceAll(RegExp(r'[A-Za-z]:\\[^\s"\x27<>]+'), '[local-path]')
        .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false),
          'Bearer [redacted]',
        );
  }

  return (sanitize(document) as Map).cast<String, dynamic>();
}
