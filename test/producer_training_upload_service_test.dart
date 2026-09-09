import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/helpers/producer_training_upload_service.dart';

class _Auth extends AuthService {
  String userId = 'producer-a';
  @override
  AuthUserProfile get signedInUser => AuthUserProfile(
    userId: userId,
    email: '',
    displayName: '',
    provider: AuthProviderType.email,
    emailVerified: true,
    createdAt: DateTime.utc(2026),
  );
  @override
  bool get isSignedIn => true;
  @override
  Future<http.Response> authorizedRequest(
    Future<http.Response> Function(String) send, {
    bool expireSessionOnAuthFailure = false,
  }) => send('test-token');
}

class _Collector extends ProducerDataCollector {
  _Collector(this.file);
  final File file;
  @override
  Future<List<File>> listSessionFiles() async => [file];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'network failure after reservation retries identical bytes and checksum',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_retry_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/capture.json');
      await file.writeAsString(
        jsonEncode({
          'session_id': 'retry-session',
          'local_owner_ref': ProducerDataCollector.ownerRef('producer-a'),
          'schema_version': ProducerDataCollector.schemaVersion,
          'consent_version': ProducerDataCollector.consentVersion,
          'feature_extractor_version':
              ProducerDataCollector.featureExtractorVersion,
          'segmentation_version': ProducerDataCollector.segmentationVersion,
          'media_manifest': [],
          'episodes': [],
          'upload': {'status': 'pending', 'attempts': 0},
        }),
      );
      final collector = _Collector(file);
      final reserved = <Map>[];
      final uploads = <String>[];
      final service = ProducerTrainingUploadService(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/uploads')) {
            reserved.add(jsonDecode(request.body) as Map);
            return http.Response(
              jsonEncode({
                'upload_url': 'https://storage.example/bundle',
                'upload_headers': {},
              }),
              201,
            );
          }
          if (request.method == 'PUT') {
            uploads.add(request.body);
            return http.Response('', uploads.length == 1 ? 503 : 200);
          }
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.close);
      await service.drainPending(auth: _Auth(), collector: collector);
      expect(
        (jsonDecode(await file.readAsString())['upload'])['status'],
        'retry_needed',
      );
      await service.drainPending(auth: _Auth(), collector: collector);
      expect(uploads, hasLength(2));
      expect(uploads[0], uploads[1]);
      expect(reserved[0]['sha256'], reserved[1]['sha256']);
      expect(reserved[0]['size_bytes'], reserved[1]['size_bytes']);
      expect(jsonDecode(uploads[0]), isNot(contains('upload')));
      expect(
        (jsonDecode(await file.readAsString())['upload'])['status'],
        'uploaded',
      );
    },
  );

  test(
    'failed status persistence leaves the previous capture intact',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_atomic_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/session.json');
      final original = jsonEncode({
        'upload': {'status': 'pending'},
        'episodes': [],
      });
      await file.writeAsString(original);
      // Simulate failure while preparing a replacement, before atomic rename.
      await Directory('${file.path}.tmp').create();
      await _Collector(file).updateUploadStatus(file, 'uploading');
      expect(await file.readAsString(), original);
    },
  );

  test(
    'pending sessions never upload under a different or unknown owner',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_owner_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/session.json');
      var requests = 0;
      final service = ProducerTrainingUploadService(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      addTearDown(service.close);
      for (final owner in [
        null,
        ProducerDataCollector.ownerRef('another-producer'),
      ]) {
        await file.writeAsString(
          jsonEncode({
            'local_owner_ref': owner,
            'upload': {'status': 'pending'},
            'episodes': [],
          }),
        );
        await service.drainPending(auth: _Auth(), collector: _Collector(file));
      }
      expect(requests, 0);
    },
  );

  test(
    'account switch after reservation prevents upload to a different owner',
    () async {
      final dir = await Directory.systemTemp.createTemp('producer_switch_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/session.json');
      await file.writeAsString(
        jsonEncode({
          'session_id': 'test',
          'local_owner_ref': ProducerDataCollector.ownerRef('producer-a'),
          'upload': {'status': 'pending'},
          'episodes': [],
        }),
      );
      final auth = _Auth();
      final methods = <String>[];
      final service = ProducerTrainingUploadService(
        httpClient: MockClient((request) async {
          methods.add(request.method);
          auth.userId = 'producer-b';
          return http.Response(
            jsonEncode({'upload_url': 'https://storage.example/bundle'}),
            201,
          );
        }),
      );
      addTearDown(service.close);
      await service.drainPending(auth: auth, collector: _Collector(file));
      expect(methods, ['POST']);
      expect(
        jsonDecode(await file.readAsString())['upload']['status'],
        'retry_needed',
      );
    },
  );

  test('interrupted uploading and recording files recover for retry', () async {
    final dir = await Directory.systemTemp.createTemp('producer_recover_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/capture.json');
    for (final status in ['uploading', 'recording']) {
      await file.writeAsString(
        jsonEncode({
          'upload': {'status': status},
          'episodes': [
            {'status': 'active'},
          ],
        }),
      );
      final collector = _Collector(file);
      expect(await collector.listPendingUploadFiles(), [file]);
      if (status == 'recording') {
        final recovered = jsonDecode(await file.readAsString());
        expect(
          recovered['episodes'][0]['capture_warning'],
          'interrupted_before_final_snapshot',
        );
      }
    }
  });

  test(
    'sanitizer preserves feature semantics while removing local identifiers',
    () {
      final wire = sanitizeProducerTrainingBundle({
        'goal': {'execution_profile': 'creative_bold'},
        'feature_extractor_version': 'state_audio_proxy_v1',
        'source_path': '/Users/private/file.wav',
        'upload': {'attempts': 4},
      });
      expect(wire['goal']['execution_profile'], 'creative_bold');
      expect(wire['feature_extractor_version'], 'state_audio_proxy_v1');
      expect(wire.containsKey('source_path'), isFalse);
      expect(wire.containsKey('upload'), isFalse);
    },
  );
}
