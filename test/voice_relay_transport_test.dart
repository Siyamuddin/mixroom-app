import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/voice/voice_relay_transport.dart';

void main() {
  test('plain HTTP is limited to exact loopback relay addresses', () {
    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      final url = 'http://$host:8765/api/voice';
      expect(validateVoiceRelayUrl('$url/'), url);
    }
    expect(
      validateVoiceRelayUrl('https://voice.example/api/voice'),
      'https://voice.example/api/voice',
    );
    for (final url in [
      'http://192.168.1.2:8765/api/voice',
      'http://10.0.0.2:8765/api/voice',
      'http://0.0.0.0:8765/api/voice',
      'http://127.0.0.2:8765/api/voice',
      'http://localhost.example:8765/api/voice',
      'http://[::ffff:127.0.0.1]:8765/api/voice',
      'https://user:password@voice.example/api/voice',
      'http://127.0.0.1:8765/api/voice?token=secret',
      'http://127.0.0.1:8765/api/voice#fragment',
      'file:///tmp/voice',
      '//localhost:8765/api/voice',
      '',
    ]) {
      expect(() => validateVoiceRelayUrl(url), throwsFormatException);
    }
  });

  test(
    'local endpoint preserves prefix and pairs without bearer credentials',
    () async {
      final requests = <http.Request>[];
      final transport = HttpVoiceRelayTransport(
        'http://127.0.0.1:8765/api/voice/',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(transport.close);
      await transport.request(
        'POST',
        '/pairing/claim',
        body: {'pairingCode': '123456', 'deviceName': 'MixRoom macOS'},
      );
      await transport.request(
        'PUT',
        '/sessions/session-id/state',
        token: 'test-device-token',
        body: {
          'projectSessionId': 'project',
          'projectRevision': 1,
          'state': {},
        },
      );
      expect(
        requests.first.url.toString(),
        'http://127.0.0.1:8765/api/voice/pairing/claim',
      );
      expect(requests.first.headers['authorization'], isNull);
      expect(jsonDecode(requests.first.body)['pairingCode'], '123456');
      expect(requests.last.url.path, '/api/voice/sessions/session-id/state');
      expect(
        requests.last.headers['authorization'],
        'Bearer test-device-token',
      );
      expect(requests.every((request) => !request.followRedirects), isTrue);
    },
  );

  test('redirects fail without forwarding the paired device token', () async {
    var sends = 0;
    final transport = HttpVoiceRelayTransport(
      'http://localhost:8765/api/voice',
      client: MockClient((request) async {
        sends++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          307,
          headers: {'location': 'http://192.168.1.2/steal'},
        );
      }),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.request(
        'GET',
        '/sessions/session-id/poll',
        token: 'test-token',
      ),
      throwsA(
        isA<VoiceRelayException>().having(
          (error) => error.statusCode,
          'statusCode',
          307,
        ),
      ),
    );
    expect(sends, 1);
  });
}
