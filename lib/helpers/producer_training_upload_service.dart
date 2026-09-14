import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/helpers/auth_service.dart';

class ProducerTrainingUploadService {
  ProducerTrainingUploadService({
    http.Client? httpClient,
    this.onProgress,
    this.retryDelay = const Duration(seconds: 30),
    this.verificationPollDelay = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  Future<void>? _drain;
  final void Function(String stage, double? progress)? onProgress;
  final Duration retryDelay;
  final Duration verificationPollDelay;
  Timer? _retryTimer;
  bool _closed = false;
  Completer<void>? _abortUpload;
  bool _retryablePending = false;
  bool get hasScheduledRetry => _retryTimer != null;

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
    bool retryFailed = false,
  }) {
    if (_closed) return Future<void>.value();
    if (_drain != null) return _drain!;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!auth.isSignedIn || !AppApiConfig.hasApiBaseUrl)
      return Future<void>.value();
    _retryablePending = false;
    return _drain = _drainPending(auth, collector, retryFailed).whenComplete(
      () {
        _drain = null;
        if (!_closed && _retryablePending) {
          _retryTimer = Timer(retryDelay, () {
            _retryTimer = null;
            unawaited(
              drainPending(
                auth: auth,
                collector: collector,
              ).catchError((Object _) {}),
            );
          });
        }
      },
    );
  }

  Future<void> _drainPending(
    AuthService auth,
    ProducerDataCollector collector,
    bool retryFailed,
  ) async {
    for (final file in await collector.listPendingUploadFiles(
      includeFailed: retryFailed,
    )) {
      if (_closed) break;
      final path = file.path;
      String ownerRef;
      try {
        ownerRef = await compute(readProducerUploadOwner, path);
      } catch (_) {
        await collector.failUnreadableUpload(file);
        onProgress?.call('failed', null);
        continue;
      }
      if (ownerRef.isEmpty || ownerRef != _currentOwnerRef(auth)) continue;
      await _uploadOne(
        auth: auth,
        collector: collector,
        file: file,
        ownerRef: ownerRef,
      );
    }
  }

  Future<void> _uploadOne({
    required AuthService auth,
    required ProducerDataCollector collector,
    required File file,
    required String ownerRef,
  }) async {
    try {
      _requireOwner(auth, ownerRef);
      onProgress?.call('preparing', null);
      await collector.updateUploadStatus(file, 'uploading');
      final path = file.path;
      final prepared = await compute(prepareProducerUpload, path);
      final payload = File(prepared['path'] as String);
      final size = prepared['size_bytes'] as int;
      final contract = (prepared['contract'] as Map).cast<String, dynamic>();
      final sessionId = contract['session_id'] as String;
      final fields = <String, dynamic>{
        ...contract,
        'size_bytes': size,
        'sha256': prepared['sha256'],
      };
      final reserve =
          await _postAuthed(auth, '/v1/producer-training/sessions/uploads', {
            ...fields,
            if (size > producerSingleUploadLimit)
              'part_checksums': prepared['part_checksums'],
          }, ownerRef: ownerRef);
      if (reserve['already_completed'] != true) {
        if (reserve['multipart'] == true) {
          final parts = (reserve['parts'] as List).cast<Map>();
          final partSize = reserve['part_size'] as int;
          if (partSize != producerUploadPartSize)
            throw const FormatException('Unsupported upload part size');
          var sent =
              size -
              parts.fold<int>(
                0,
                (sum, part) => sum + (part['size_bytes'] as int),
              );
          onProgress?.call('uploading', sent / size);
          for (final part in parts) {
            _requireOwner(auth, ownerRef);
            final number = part['part_number'] as int;
            final length = part['size_bytes'] as int;
            if (number < 1 ||
                length <= 0 ||
                length > partSize ||
                (number - 1) * partSize + length > size) {
              throw const FormatException('Invalid upload part');
            }
            await _putFile(
              payload,
              part['upload_url'] as String,
              (part['upload_headers'] as Map).cast<String, String>(),
              offset: (number - 1) * partSize,
              length: length,
              onBytes: (bytes) =>
                  onProgress?.call('uploading', (sent + bytes) / size),
            );
            sent += length;
            onProgress?.call('uploading', sent / size);
          }
        } else {
          _requireOwner(auth, ownerRef);
          onProgress?.call('uploading', 0);
          await _putFile(
            payload,
            reserve['upload_url'] as String,
            ((reserve['upload_headers'] as Map?) ?? {}).cast<String, String>(),
            offset: 0,
            length: size,
            onBytes: (bytes) => onProgress?.call('uploading', bytes / size),
          );
          onProgress?.call('uploading', 1);
        }
        _requireOwner(auth, ownerRef);
        onProgress?.call('verifying', null);
        final completed = await _postAuthed(
          auth,
          '/v1/producer-training/sessions/${Uri.encodeComponent(sessionId)}/complete',
          fields,
          ownerRef: ownerRef,
        );
        if (completed['status'] == 'verifying') {
          final deadline = DateTime.now().add(const Duration(minutes: 20));
          while (true) {
            if (_closed || DateTime.now().isAfter(deadline))
              throw const HttpException('Verification is still pending');
            await Future<void>.delayed(verificationPollDelay);
            _requireOwner(auth, ownerRef);
            final response = await auth.authorizedRequest(
              (token) => _httpClient
                  .get(
                    _uri(
                      '/v1/producer-training/sessions/${Uri.encodeComponent(sessionId)}',
                    ),
                    headers: {'Authorization': 'Bearer $token'},
                  )
                  .timeout(const Duration(seconds: 30)),
              expireSessionOnAuthFailure: false,
            );
            _checkResponse(response.statusCode);
            final status = jsonDecode(response.body)['status'];
            if (status == 'verified') break;
            if (status == 'failed')
              throw const ProducerUploadRejected('Capture validation failed');
            if (status != 'verifying')
              throw const HttpException('Verification needs retry');
          }
        } else if (completed['accepted'] != true) {
          throw const HttpException('Upload has not been confirmed');
        }
      }
      _requireOwner(auth, ownerRef);
      await collector.updateUploadStatus(file, 'uploaded');
      onProgress?.call('uploaded', 1);
    } catch (error) {
      final permanent =
          error is ProducerUploadRejected || error is FormatException;
      _retryablePending |= !permanent;
      try {
        await collector.updateUploadStatus(
          file,
          permanent ? 'failed' : 'retry_needed',
          error: error.toString(),
        );
      } catch (_) {
        // A disk failure must not escape into editing or discard the existing file.
        _retryablePending = true;
      }
      onProgress?.call(permanent ? 'failed' : 'retry_needed', null);
    }
  }

  Future<void> _putFile(
    File file,
    String url,
    Map<String, String> headers, {
    required int offset,
    required int length,
    void Function(int)? onBytes,
  }) async {
    final abort = _abortUpload = Completer<void>();
    var bytes = 0;
    final clock = Stopwatch()..start();
    var lastUpdate = 0;
    final request =
        http.AbortableStreamedRequest(
            'PUT',
            Uri.parse(url),
            abortTrigger: abort.future,
          )
          ..headers.addAll(headers)
          ..contentLength = length;
    final response = _httpClient.send(request);
    final write = request.sink
        .addStream(
          file.openRead(offset, offset + length).map((chunk) {
            bytes += chunk.length;
            if (clock.elapsedMilliseconds - lastUpdate >= 250) {
              lastUpdate = clock.elapsedMilliseconds;
              onBytes?.call(bytes);
            }
            return chunk;
          }),
        )
        .then((_) => request.sink.close());
    try {
      await Future.wait<void>([
        write,
        response.then((result) async {
          await result.stream.drain<void>();
          _checkResponse(result.statusCode);
        }),
      ], eagerError: true).timeout(
        Duration(seconds: AppApiConfig.requestTimeoutSeconds * 3),
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
      _abortUpload = null;
    }
  }

  void _checkResponse(int status) {
    if (status >= 200 && status < 300) return;
    if (const {400, 409, 413, 422}.contains(status)) {
      throw ProducerUploadRejected(
        'Upload rejected ($status); the local capture is preserved.',
      );
    }
    throw HttpException('Capture upload failed ($status)');
  }

  Future<Map<String, dynamic>> _postAuthed(
    AuthService auth,
    String path,
    Map<String, dynamic> body, {
    required String ownerRef,
  }) async {
    final response = await auth.authorizedRequest((token) {
      _requireOwner(auth, ownerRef);
      return _httpClient
          .post(
            _uri(path),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
    }, expireSessionOnAuthFailure: false);
    _checkResponse(response.statusCode);
    final decoded = jsonDecode(response.body);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  String? _currentOwnerRef(AuthService auth) {
    final id = auth.signedInUser?.userId;
    return id == null || id.isEmpty ? null : ProducerDataCollector.ownerRef(id);
  }

  void _requireOwner(AuthService auth, String expected) {
    if (_currentOwnerRef(auth) != expected)
      throw StateError('Capture upload account changed.');
  }

  Uri _uri(String path) {
    final base = AppApiConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
  }

  void close() {
    _closed = true;
    if (_abortUpload != null && !_abortUpload!.isCompleted)
      _abortUpload!.complete();
    _retryTimer?.cancel();
    _retryTimer = null;
    _httpClient.close();
  }
}

Map<String, dynamic> sanitizeProducerTrainingBundle(
  Map<String, dynamic> document,
) {
  const removedKeys = <String>{
    'local_owner_ref',
    'upload',
    'event_journal_file',
    'statebase64',
    'state_base64',
    'client_name',
    'account_id',
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
    if (normalizedKey.contains('path') ||
        normalizedKey == 'file' ||
        normalizedKey.endsWith('_file')) {
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

const producerSingleUploadLimit = 25000000;
const producerUploadPartSize = 8 * 1024 * 1024;
const producerMaximumUploadSize = 5000000000;

class ProducerUploadRejected implements Exception {
  const ProducerUploadRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) {
    value = digest;
  }

  @override
  void close() {}
}

/// Worker only: sanitize, write and hash without large JSON/byte work on the UI.
Future<Map<String, dynamic>> prepareProducerUpload(String path) async {
  final payload = File('$path.payload');
  Map<String, dynamic> document;
  if (await payload.exists()) {
    document = (jsonDecode(await payload.readAsString()) as Map)
        .cast<String, dynamic>();
  } else {
    document = sanitizeProducerTrainingBundle(
      (jsonDecode(await File(path).readAsString()) as Map)
          .cast<String, dynamic>(),
    );
    await writeProducerDocument(payload.path, document);
  }
  final size = await payload.length();
  if (size > producerMaximumUploadSize) {
    throw const ProducerUploadRejected(
      'Capture exceeds the 5 GB upload limit; the local file is preserved.',
    );
  }
  final sessionId = document['session_id']?.toString() ?? '';
  if (sessionId.isEmpty)
    throw const FormatException('Capture session ID is missing');
  final digestSink = _DigestSink();
  final digest = sha256.startChunkedConversion(digestSink);
  final parts = <String>[];
  final input = await payload.open();
  try {
    while (true) {
      final chunk = await input.read(producerUploadPartSize);
      if (chunk.isEmpty) break;
      digest.add(chunk);
      parts.add(sha256.convert(chunk).toString());
    }
  } finally {
    await input.close();
  }
  digest.close();
  return {
    'path': payload.path,
    'size_bytes': size,
    'sha256': digestSink.value.toString(),
    'part_checksums': parts,
    'contract': {
      for (final key in [
        'session_id',
        'schema_version',
        'consent_version',
        'feature_extractor_version',
        'segmentation_version',
      ])
        key: document[key],
      'media_manifest': document['media_manifest'] ?? [],
    },
  };
}

Future<String> readProducerUploadOwner(String path) async {
  final document = jsonDecode(await File(path).readAsString()) as Map;
  return document['local_owner_ref']?.toString() ?? '';
}
