import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('LLM Proxy Contract', () {
    testWidgets('refunded soft failures surface fallback text and metadata',
        (tester) async {
      late Uri requestUri;
      final client = MockClient((request) async {
        requestUri = request.url;
        return http.Response(
          jsonEncode({
            'soft_error': {
              'code': 'invalid_structured_output',
              'usage_refunded': true,
            },
            'prompt_rate_limit': {
              'daily': {
                'used': 7,
                'limit': 50,
                'remaining': 43,
                'resets_at': '2026-03-18T00:00:00Z',
              },
              'weekly': {
                'used': 15,
                'limit': 350,
                'remaining': 335,
                'resets_at': '2026-03-23T00:00:00Z',
              },
              'can_submit': true,
              'blocked_by': '',
            },
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '{"assistant_message":"Applied"}',
                  }
                ],
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        proxyApiBaseUrl: 'https://proxy.mixroom.test',
        authTokenProvider: () async => 'integration-token',
        httpClient: client,
      );

      final result = await service.send(
        conversation: const [],
        userText: 'Make this feel more polished.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(
          requestUri.toString(), 'https://proxy.mixroom.test/v1/llm/responses');
      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        'I hit an internal formatting issue while preparing that response. Please try again.',
      );
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
      expect(result.meta?['prompt_rate_limit']?['daily']?['remaining'], 43);
    });

    testWidgets('successful proxy tool responses remain executable',
        (tester) async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'prompt_rate_limit': {
              'daily': {
                'used': 8,
                'limit': 50,
                'remaining': 42,
                'resets_at': '2026-03-18T00:00:00Z',
              },
              'weekly': {
                'used': 16,
                'limit': 350,
                'remaining': 334,
                'resets_at': '2026-03-23T00:00:00Z',
              },
              'can_submit': true,
              'blocked_by': '',
            },
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'mode': 'execute',
                  'assistant_message': 'Added a subtle vocal delay.',
                  'actions': [
                    {
                      'goal': {
                        'type': 'mix_request',
                        'intents': [
                          {
                            'kind': 'delay',
                            'direction': 'up',
                            'confidence': 0.8,
                          }
                        ],
                        'target': {
                          'scope': 'row',
                          'row_index': 0,
                          'confidence': 0.95,
                        },
                        'intensity': 0.3,
                        'reset_fx': false,
                      }
                    }
                  ],
                },
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        proxyApiBaseUrl: 'https://proxy.mixroom.test',
        authTokenProvider: () async => 'integration-token',
        httpClient: client,
      );

      final result = await service.send(
        conversation: const [],
        userText: 'Add a subtle delay to the vocal.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.toolName, 'mix_model_request');
      expect(result.text, 'Added a subtle vocal delay.');
      expect(
          result.toolArgs?['assistant_message'], 'Added a subtle vocal delay.');
      expect(result.meta?['soft_error'], isNull);
      expect(result.meta?['prompt_rate_limit']?['daily']?['remaining'], 42);
    });
  });
}
