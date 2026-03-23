import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudLlmService', () {
    test('preserves wrapped master tool args without prompt-based rewrites',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'value': jsonEncode({
                    'mode': 'execute',
                    'assistant_message':
                        'Enhancé la calidad para que suene más sofisticado.',
                    'actions': [
                      {
                        'goal': {
                          'type': 'mix_request',
                          'intents': [
                            {
                              'kind': 'limiter',
                              'direction': 'up',
                              'descriptor': 'null',
                              'confidence': 0.9,
                            }
                          ],
                          'target': {
                            'scope': 'master',
                            'row_index': -1,
                            'role': null,
                            'confidence': 0.8,
                          },
                          'intensity': 0.4,
                        }
                      }
                    ],
                  }),
                },
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Put a clipper on the master bus.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.toolName, 'mix_model_request');
      expect(result.toolArgs?['assistant_message'],
          'Applied the requested mix changes.');
      final action = (result.toolArgs?['actions'] as List).first as Map;
      final goal = action['goal'] as Map;
      final intents = goal['intents'] as List;
      final target = goal['target'] as Map;
      expect((intents.first as Map)['kind'], 'limiter');
      expect(target['scope'], 'master');
      expect(target.containsKey('row_index'), isFalse);
      expect(target.containsKey('role'), isFalse);
    });

    test('returns clean fallback text for malformed function arguments',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': '{"mode":"execute","assistant_message":"Applied',
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Make the mix more modern.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't complete that request just now. Please try again.",
      );
    });

    test('compresses tutorial assistant text to a short one-liner', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      "Here's how to adjust the reverb on the drums track. First open the drums effects tab, then find reverb, then open its controls and adjust the mix knob.",
                  'actions': [
                    {
                      'type': 'tutorial',
                      'data': {
                        'topic': 'adjust drum reverb',
                        'steps': [
                          {
                            'text': 'Open the drums effects tab.',
                            'target_id': 'row:0:effects_tab',
                          },
                          {
                            'text': 'Open the reverb effect.',
                            'target_id': 'row:0:fx_contains:reverb',
                          },
                        ],
                      },
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
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'show how to adjust reverb on drum track',
        projectSnapshot: 'Track 1: Drums',
      );

      expect(result.toolName, 'daw_assistant_actions');
      expect(result.toolArgs?['assistant_message'], 'Showing you in the UI.');
      expect(result.text, 'Showing you in the UI.');
    });

    test('aggregates multiple mix_model_request function calls', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'mode': 'execute',
                  'assistant_message': 'Applied a combined mix pass.',
                  'actions': [
                    {
                      'goal': {
                        'type': 'mix_request',
                        'intents': [
                          {
                            'kind': 'gain',
                            'direction': 'up',
                            'confidence': 0.9,
                          }
                        ],
                        'target': {
                          'scope': 'row',
                          'row_index': 0,
                          'confidence': 0.95,
                        },
                        'intensity': 0.2,
                      }
                    }
                  ],
                },
              },
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'mode': 'execute',
                  'actions': [
                    {
                      'goal': {
                        'type': 'mix_request',
                        'intents': [
                          {
                            'kind': 'reverb',
                            'direction': 'up',
                            'confidence': 0.8,
                          }
                        ],
                        'target': {
                          'scope': 'row',
                          'row_index': 1,
                          'confidence': 0.9,
                        },
                        'intensity': 0.4,
                      }
                    }
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Turn vocals up and add reverb to drums.',
        projectSnapshot: 'Track 1: Lead Vocal\nTrack 2: Drums',
      );

      expect(result.toolName, 'mix_model_request');
      expect(result.text, 'Applied a combined mix pass.');
      final calls = result.toolArgs?['calls'] as List?;
      expect(calls, isNotNull);
      expect(calls, hasLength(2));
    });

    test('aggregates multiple daw_assistant_actions function calls', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Showing you in the UI.',
                  'actions': [
                    {
                      'type': 'tutorial',
                      'data': {
                        'topic': 'open reverb',
                        'steps': [
                          {
                            'text': 'Open the drums effects tab.',
                            'target_id': 'row:0:effects_tab',
                          }
                        ],
                      },
                    }
                  ],
                },
              },
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'actions': [
                    {
                      'type': 'tutorial',
                      'data': {
                        'topic': 'open mix knob',
                        'steps': [
                          {
                            'text': 'Open the reverb mix control.',
                            'target_id': 'row:0:fx_contains:reverb:param:mix',
                          }
                        ],
                      },
                    }
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'show me where the drum reverb mix is',
        projectSnapshot: 'Track 1: Drums',
      );

      expect(result.toolName, 'daw_assistant_actions');
      expect(result.text, 'Showing you in the UI.');
      final calls = result.toolArgs?['calls'] as List?;
      expect(calls, isNotNull);
      expect(calls, hasLength(2));
    });

    test('falls back when English prompt gets Korean tool text', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'value': jsonEncode({
                    'mode': 'execute',
                    'assistant_message': '드럼 트랙에 리버브를 추가했습니다.',
                    'actions': [
                      {
                        'goal': {
                          'type': 'mix_request',
                          'intents': [
                            {
                              'kind': 'reverb',
                              'direction': 'up',
                              'confidence': 0.9,
                            }
                          ],
                          'target': {
                            'scope': 'row',
                            'row_index': 0,
                            'confidence': 0.9,
                          },
                          'intensity': 0.5,
                        }
                      }
                    ],
                  }),
                },
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Add reverb to drums.',
        projectSnapshot: 'Track 1: Drums',
      );

      final surfacedAssistantText =
          result.toolArgs?['assistant_message']?.toString() ?? result.text ?? '';
      expect(surfacedAssistantText, isNot('드럼 트랙에 리버브를 추가했습니다.'));
      expect(surfacedAssistantText.contains('드럼 트랙'), isFalse);
    });

    test('returns clean fallback text for json-like assistant text output',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'soft_error': {
              'code': 'invalid_structured_output',
              'usage_refunded': true,
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
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Make the mix more modern.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't complete that request just now. Please try again.",
      );
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
    });

    test('handles refunded soft-failure responses from proxy cleanly',
        () async {
      Uri? requestUri;
      String? authorization;
      Map<String, dynamic>? requestBody;
      final client = MockClient((request) async {
        requestUri = request.url;
        authorization = request.headers['Authorization'] ?? '';
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'soft_error': {
              'code': 'invalid_structured_output',
              'usage_refunded': true,
            },
            'prompt_rate_limit': {
              'daily': {
                'used': 4,
                'limit': 50,
                'remaining': 46,
                'resets_at': '2026-03-18T00:00:00Z',
              },
              'weekly': {
                'used': 10,
                'limit': 350,
                'remaining': 340,
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
        authTokenProvider: () async => 'session-token',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Make this sound more polished.',
        projectSnapshot: 'Track 1: Lead Vocal',
        aiFeature: 'ai_chat',
      );

      expect(result.text, isNot('Your session expired. Please sign in again.'));
      expect(
        result.text,
        isNot('There has been an error, please try again in a moment.'),
      );
      expect(requestUri?.toString(),
          'https://proxy.mixroom.test/v1/llm/responses');
      expect(authorization, 'Bearer session-token');
      expect(requestBody?['user_text'], 'Make this sound more polished.');
      expect(requestBody?['ai_feature'], 'ai_chat');
      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't complete that request just now. Please try again.",
      );
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
      expect(
        result.meta?['prompt_rate_limit']?['daily']?['remaining'],
        46,
      );
    });

    test('parses successful proxy tool responses without triggering fallback',
        () async {
      String? authorization;
      final client = MockClient((request) async {
        authorization = request.headers['Authorization'] ?? '';
        return http.Response(
          jsonEncode({
            'prompt_rate_limit': {
              'daily': {
                'used': 5,
                'limit': 50,
                'remaining': 45,
                'resets_at': '2026-03-18T00:00:00Z',
              },
              'weekly': {
                'used': 11,
                'limit': 350,
                'remaining': 339,
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
                  'assistant_message': 'Raised the vocal level slightly.',
                  'actions': [
                    {
                      'goal': {
                        'type': 'mix_request',
                        'intents': [
                          {
                            'kind': 'gain',
                            'direction': 'up',
                            'confidence': 0.9,
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
        authTokenProvider: () async => 'session-token',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Turn the vocals up a bit.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.text, isNot('Your session expired. Please sign in again.'));
      expect(
        result.text,
        isNot('There has been an error, please try again in a moment.'),
      );
      expect(authorization, 'Bearer session-token');
      expect(result.toolName, 'mix_model_request');
      expect(result.text, 'Raised the vocal level slightly.');
      expect(result.toolArgs?['assistant_message'],
          'Raised the vocal level slightly.');
      expect(result.meta?['soft_error'], isNull);
      expect(
        result.meta?['prompt_rate_limit']?['daily']?['remaining'],
        45,
      );
    });

    test('returns a calm message when proxy auth token is temporarily missing',
        () async {
      var requestCount = 0;
      final client = MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 500);
      });

      final service = CloudLlmService(
        proxyApiBaseUrl: 'https://proxy.mixroom.test',
        authTokenProvider: () async => null,
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Add reverb to drums.',
        projectSnapshot: 'Track 1: Drums',
      );

      expect(requestCount, 0);
      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't reach the AI service just now. Please try again in a moment.",
      );
      expect(result.text, isNot('Your session expired. Please sign in again.'));
      expect(result.meta?['soft_error']?['code'], 'auth_unavailable');
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
    });

    test('maps proxy 401 responses to a calm recoverable message', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': 'Unauthorized',
          }),
          401,
        );
      });

      final service = CloudLlmService(
        proxyApiBaseUrl: 'https://proxy.mixroom.test',
        authTokenProvider: () async => 'session-token',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Add reverb to drums.',
        projectSnapshot: 'Track 1: Drums',
      );

      expect(
        result.text,
        "I couldn't reach the AI service just now. Please try again in a moment.",
      );
      expect(result.text, isNot('Your session expired. Please sign in again.'));
      expect(result.meta?['soft_error']?['code'], 'auth_rejected');
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
    });

    test('retries proxy requests once after auth rejection with a refreshed token',
        () async {
      final seenTokens = <String>[];
      final client = MockClient((request) async {
        final token = request.headers['Authorization'] ?? '';
        seenTokens.add(token);
        if (token == 'Bearer stale-token') {
          return http.Response(
            jsonEncode({
              'error': 'Unauthorized',
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'prompt_rate_limit': {
              'daily': {
                'used': 4,
                'limit': 50,
                'remaining': 46,
                'resets_at': '2026-03-18T00:00:00Z',
              },
              'weekly': {
                'used': 9,
                'limit': 350,
                'remaining': 341,
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
                  'assistant_message': 'Raised the vocal level slightly.',
                  'actions': [
                    {
                      'goal': {
                        'type': 'mix_request',
                        'intents': [
                          {
                            'kind': 'gain',
                            'direction': 'up',
                            'confidence': 0.9,
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
        authTokenProvider: () async => 'stale-token',
        refreshAuthTokenProvider: () async => 'fresh-token',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Turn the vocals up a bit.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(seenTokens, <String>['Bearer stale-token', 'Bearer fresh-token']);
      expect(result.toolName, 'mix_model_request');
      expect(result.text, 'Raised the vocal level slightly.');
      expect(result.meta?['soft_error'], isNull);
    });

    test('omits temperature for gpt-5 models in direct OpenAI requests',
        () async {
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'informational_response',
                'arguments': jsonEncode({
                  'message': 'Done.',
                  'cancels_pending': false,
                }),
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-5-mini',
        httpClient: client,
      );
      await service.send(
        conversation: const [],
        userText: 'Explain what a de-esser does.',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(requestBody['model'], 'gpt-5-mini');
      expect(requestBody.containsKey('temperature'), isFalse);
      expect(requestBody['reasoning'], {'effort': 'minimal'});
    });

    test(
        'direct OpenAI requests include prompt cache settings and expose cache telemetry',
        () async {
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'usage': {
              'input_tokens': 8099,
              'output_tokens': 161,
              'total_tokens': 8260,
              'input_tokens_details': {
                'cached_tokens': 7424,
              },
            },
            'output': [
              {
                'type': 'function_call',
                'name': 'informational_response',
                'arguments': {
                  'message':
                      'Added a subtle delay effect to the lead vocal track.',
                  'cancels_pending': false,
                },
              }
            ],
          }),
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-4.1-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'Add a subtle delay to the vocal.',
        projectSnapshot: 'Track 1: Lead Vocal',
        aiFeature: 'assistant_chat',
      );

      expect(
        requestBody['prompt_cache_key'],
        'mixroom-daw-v20260316:ai_chat',
      );
      expect(requestBody['prompt_cache_retention'], 'in_memory');
      expect(result.meta?['cached_prompt_tokens'], 7424);
      expect(
        result.meta?['usage']?['input_tokens_details']?['cached_tokens'],
        7424,
      );
    });
  });
}
