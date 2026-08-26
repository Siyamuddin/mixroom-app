import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_service.dart';
import 'package:mixroom/ai/v3/ai_v3_adaptive_midi_planner.dart';
import 'package:mixroom/ai/v3/ai_v3_style_compiler.dart';
import 'package:mixroom/ai/v3/ai_v3_user_facing_text.dart';

AiV3CoreContext _context() => const AiV3CoreContext(
  profile: AiV3ContextProfile.essential,
  stateDigest: 'digest-1',
  data: <String, dynamic>{
    'schema_version': 'core_context_v3_prototype_1',
    'project': <String, dynamic>{'bpm': 120},
    'rows': <Object>[],
    'clips': <Object>[],
  },
);

Map<String, dynamic> _responseWithArguments(Object arguments) =>
    <String, dynamic>{
      'id': 'resp_v3_test',
      'service_tier': 'default',
      'output': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'function_call',
          'name': 'submit_plan_v3',
          'arguments': arguments,
        },
      ],
      'usage': <String, dynamic>{
        'input_tokens': 100,
        'output_tokens': 20,
        'output_tokens_details': <String, dynamic>{'reasoning_tokens': 5},
      },
    };

Map<String, dynamic> _respondPlan() => <String, dynamic>{
  'schema_version': aiV3PlanVersion,
  'outcome': 'respond',
  'goal_kind': 'named_edit',
  'user_message': 'The project is at 120 BPM.',
  'commands': const <Object>[],
  'question_options': const <Object>[],
};

void main() {
  test('sends one strict V3 tool and preserves the original request', () async {
    const request = '현재 BPM이 뭐야? Do not change anything.';
    late Map<String, dynamic> sent;
    final client = MockClient((http.Request httpRequest) async {
      sent = Map<String, dynamic>.from(jsonDecode(httpRequest.body) as Map);
      return http.Response(
        jsonEncode(_responseWithArguments(jsonEncode(_respondPlan()))),
        200,
      );
    });
    final service = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
      httpClient: client,
    );

    final result = await service.plan(
      context: _context(),
      originalRequest: request,
      promptTraceId: 'trace-1',
    );

    expect(result.plan.outcome, 'respond');
    expect(result.requestBody, sent);
    expect(sent['max_output_tokens'], 8192);
    expect(sent['parallel_tool_calls'], isFalse);
    expect((sent['tools'] as List), hasLength(1));
    expect((sent['tools'] as List).single['name'], 'submit_plan_v3');
    final oneShotTool = Map<String, dynamic>.from(
      (sent['tools'] as List).single as Map,
    );
    final adaptiveTool = Map<String, dynamic>.from(
      (buildAiV3AdaptiveFirstRequestBody(
                    compactCore: const <String, dynamic>{},
                    originalRequest: request,
                    model: 'gpt-5.4-mini',
                    reasoningEffort: 'low',
                  )['tools']
                  as List)
              .first
          as Map,
    );
    expect(oneShotTool, adaptiveTool);
    expect(
      sent['instructions'],
      allOf(
        contains('Never invent a group.'),
        contains('multiple named ungrouped rows'),
        contains('Use all_rows only'),
        contains('user_message must contain one focused question only'),
        contains('distinct, concise, meaningful'),
        contains('Never include Cancel, Something else, Other'),
      ),
    );
    expect(sent['instructions'], contains(aiV3CustomerLanguageInstructions));
    expect(sent['instructions'], contains('general music creator'));
    expect(sent['instructions'], contains('clear, easy-to-understand'));
    expect(sent['instructions'], contains('deeper technical detail'));
    expect(
      sent['instructions'],
      contains('request or conversation clearly shows'),
    );
    expect(sent['instructions'], contains('user-visible terms'));
    expect(
      sent['instructions'],
      contains('non-user-visible application context'),
    );
    expect(sent['instructions'], contains('never reveal or transform them'));
    expect(
      sent['instructions'],
      contains('one or two brief, past-tense sentences'),
    );
    expect(
      sent['instructions'],
      contains('Never copy the request into a successful plan summary'),
    );
    expect(sent['instructions'], contains('completed musical result'));
    expect(sent['instructions'], contains('under 500 characters'));
    expect(sent['instructions'], contains('Always finish naturally'));
    expect(jsonEncode(sent['input']), contains(request));
    expect(jsonEncode(sent), isNot(contains('intent_frame')));
    expect(jsonEncode(sent), isNot(contains('legacy_action')));
    expect(
      sent,
      buildAiV3PlannerRequestBody(
        contextData: _context().data,
        originalRequest: request,
        model: 'gpt-5.4-mini',
        reasoningEffort: 'low',
        promptTraceId: 'trace-1',
      ),
    );
  });

  test(
    'opt-in service accepts an ordered stem-to-pitch output reference',
    () async {
      final rawPlan = <String, dynamic>{
        'schema_version': aiV3PlanVersion,
        'outcome': 'plan',
        'goal_kind': 'named_edit',
        'user_message': 'Separated the stems and adjusted the generated clip.',
        'commands': <Map<String, dynamic>>[
          <String, dynamic>{
            'command_id': 'separate',
            'type': 'clip.separate_stems',
            'arguments': <String, dynamic>{'clip_id': 'source'},
          },
          <String, dynamic>{
            'command_id': 'pitch',
            'type': 'clip.adjust_pitch_semitones',
            'arguments': <String, dynamic>{
              'clip_ref': <String, dynamic>{
                'command_id': 'separate',
                'output': 'instrumental_clip',
              },
              'delta_semitones': -1,
            },
          },
        ],
        'question_options': const <Object>[],
      };
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'test-model',
        resourceRefsEnabled: true,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(_responseWithArguments(jsonEncode(rawPlan))),
            200,
          ),
        ),
      );

      final result = await service.plan(
        context: _context(),
        originalRequest: 'Perform the ordered edit.',
      );

      expect(result.plan.commands, hasLength(2));
      expect(result.plan.commands.last.arguments['clip_ref'], <String, dynamic>{
        'command_id': 'separate',
        'output': 'instrumental_clip',
      });
    },
  );

  test(
    'opt-in service accepts generated MIDI clip transpose reference',
    () async {
      final rawPlan = <String, dynamic>{
        'schema_version': aiV3PlanVersion,
        'outcome': 'plan',
        'goal_kind': 'named_edit',
        'user_message': 'Created and transposed the generated MIDI clip.',
        'commands': <Map<String, dynamic>>[
          <String, dynamic>{
            'command_id': 'create-midi',
            'type': 'midi.create_clip',
            'arguments': <String, dynamic>{
              'destination': <String, dynamic>{
                'new_row': <String, dynamic>{
                  'name': 'Synth',
                  'instrument_id': 'mixroom.basic_synth',
                },
              },
              'start_beat': 0,
              'length_beats': 4,
              'notes': <Map<String, dynamic>>[
                <String, dynamic>{
                  'pitch': 60,
                  'start_beat': 0,
                  'length_beats': 1,
                  'velocity': 0.8,
                },
              ],
            },
          },
          <String, dynamic>{
            'command_id': 'transpose',
            'type': 'midi.transpose',
            'arguments': <String, dynamic>{
              'clip_ref': <String, dynamic>{
                'command_id': 'create-midi',
                'output': 'midi_clip',
              },
              'semitones': 2,
            },
          },
        ],
        'question_options': const <Object>[],
      };
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'test-model',
        resourceRefsEnabled: true,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(_responseWithArguments(jsonEncode(rawPlan))),
            200,
          ),
        ),
      );

      final result = await service.plan(
        context: _context(),
        originalRequest:
            'Create a MIDI clip and transpose that generated clip.',
      );

      expect(result.plan.commands.map((command) => command.type), <String>[
        'midi.create_clip',
        'midi.transpose',
      ]);
      expect(result.plan.commands.last.arguments['clip_ref'], <String, dynamic>{
        'command_id': 'create-midi',
        'output': 'midi_clip',
      });
    },
  );

  test(
    'authenticated proxy preserves the V3 request and hides API keys',
    () async {
      late http.Request sentRequest;
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentRequest = request;
        sentBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode(<String, dynamic>{
            ..._responseWithArguments(jsonEncode(_respondPlan())),
            'model': 'gpt-5.6-luna',
          }),
          200,
        );
      });
      final service = AiV3PlannerService(
        model: 'gpt-5.6-luna',
        reasoningEffort: 'low',
        proxyApiBaseUrl: 'https://proxy.example/',
        proxyPath: 'v1/llm/v3/responses',
        authTokenProvider: () async => 'app-session-token',
        httpClient: client,
      );

      final result = await service.plan(
        context: _context(),
        originalRequest: 'Keep everything unchanged.',
        promptTraceId: 'trace-proxy',
      );

      expect(
        sentRequest.url.toString(),
        'https://proxy.example/v1/llm/v3/responses',
      );
      expect(sentRequest.headers['authorization'], 'Bearer app-session-token');
      expect(sentBody['ai_feature'], 'ai_chat_v3');
      expect(sentBody['prompt_trace_id'], 'trace-proxy');
      expect(sentBody['client_context'], <String, dynamic>{
        'ai_architecture': 'v3_one_shot_prototype',
      });
      expect(sentBody['store'], isTrue);
      expect(sentBody.containsKey('instructions'), isFalse);
      expect(
        jsonEncode(sentBody),
        isNot(contains('You are Mixroom')),
      );
      expect(
        jsonEncode(sentBody),
        isNot(contains('Set goal_kind from ORIGINAL_REQUEST_VERBATIM')),
      );
      expect(sentBody['metadata'], <String, dynamic>{
        'prompt_trace_id': 'trace-proxy',
        'architecture': 'v3_one_shot_prototype',
      });
      expect(jsonEncode(sentBody), isNot(contains('sk-')));
      expect(result.requestBody.containsKey('ai_feature'), isFalse);
      expect(result.meta['llm_route'], 'authenticated_proxy');
      expect(result.meta['model'], 'gpt-5.6-luna');
    },
  );

  test(
    'authenticated proxy refreshes rejected app auth exactly once',
    () async {
      var calls = 0;
      final authorizations = <String>[];
      final client = MockClient((request) async {
        calls += 1;
        authorizations.add(request.headers['authorization'] ?? '');
        if (calls == 1) {
          return http.Response('{"error":"expired"}', 401);
        }
        return http.Response(
          jsonEncode(_responseWithArguments(jsonEncode(_respondPlan()))),
          200,
        );
      });
      final service = AiV3PlannerService(
        model: 'gpt-5.6-luna',
        proxyApiBaseUrl: 'https://proxy.example',
        authTokenProvider: () async => 'expired-token',
        refreshAuthTokenProvider: () async => 'refreshed-token',
        httpClient: client,
      );

      await service.plan(
        context: _context(),
        originalRequest: 'What is the BPM?',
      );

      expect(calls, 2);
      expect(authorizations, <String>[
        'Bearer expired-token',
        'Bearer refreshed-token',
      ]);
    },
  );

  test(
    'authenticated proxy fails safely when app auth is unavailable',
    () async {
      final service = AiV3PlannerService(
        model: 'gpt-5.6-luna',
        proxyApiBaseUrl: 'https://proxy.example',
        authTokenProvider: () async => null,
        httpClient: MockClient((_) async {
          fail('HTTP must not run without app authentication.');
        }),
      );

      await expectLater(
        service.plan(context: _context(), originalRequest: 'What is the BPM?'),
        throwsA(
          isA<AiV3PlannerException>().having(
            (error) => error.code,
            'code',
            'v3_proxy_auth_token_missing',
          ),
        ),
      );
    },
  );

  test(
    'compact planner rejects commands outside its declared surface',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(
            _responseWithArguments(
              jsonEncode(<String, dynamic>{
                'schema_version': aiV3PlanVersion,
                'outcome': 'plan',
                'goal_kind': 'named_edit',
                'user_message': 'Transpose.',
                'commands': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'command_id': 'transpose',
                    'type': 'midi.transpose',
                    'arguments': <String, dynamic>{
                      'clip_id': 'clip-1',
                      'semitones': -2,
                    },
                  },
                ],
                'question_options': const <Object>[],
              }),
            ),
          ),
          200,
        ),
      );
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        commandTypes: aiV3CommonCommandTypes,
        architecture: 'v3_compact_common_shadow',
        httpClient: client,
      );

      await expectLater(
        service.plan(
          context: _context(),
          originalRequest: 'Transpose the clip.',
        ),
        throwsA(
          isA<AiV3PlannerException>().having(
            (error) => error.detail,
            'detail',
            'v3_planner_command_outside_surface',
          ),
        ),
      );
    },
  );

  test('rejects missing or malformed tool output without repair', () async {
    final missingToolClient = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{'output': const <Object>[]}),
        200,
      ),
    );
    final missingToolService = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: missingToolClient,
    );
    await expectLater(
      missingToolService.plan(
        context: _context(),
        originalRequest: 'What is the BPM?',
      ),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_tool_call_missing',
        ),
      ),
    );

    final malformedClient = MockClient(
      (_) async =>
          http.Response(jsonEncode(_responseWithArguments('{not-json')), 200),
    );
    final malformedService = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: malformedClient,
    );
    await expectLater(
      malformedService.plan(
        context: _context(),
        originalRequest: 'What is the BPM?',
      ),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_arguments_invalid_json',
        ),
      ),
    );
  });

  test('rejects multiple or unknown tool calls without choosing one', () async {
    Future<void> expectRejected(
      List<Map<String, dynamic>> output,
      String code,
    ) async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode(<String, dynamic>{'output': output}), 200),
      );
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      await expectLater(
        service.plan(context: _context(), originalRequest: 'What is the BPM?'),
        throwsA(
          isA<AiV3PlannerException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }

    final submit = <String, dynamic>{
      'type': 'function_call',
      'name': 'submit_plan_v3',
      'arguments': jsonEncode(_respondPlan()),
    };
    await expectRejected(<Map<String, dynamic>>[
      submit,
      Map<String, dynamic>.from(submit),
    ], 'v3_planner_tool_call_count_invalid');
    await expectRejected(<Map<String, dynamic>>[
      submit,
      <String, dynamic>{
        'type': 'function_call',
        'name': 'unknown_tool',
        'arguments': '{}',
      },
    ], 'v3_planner_tool_call_count_invalid');
    await expectRejected(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'function_call',
        'name': 'unknown_tool',
        'arguments': '{}',
      },
    ], 'v3_planner_tool_call_invalid');
  });

  test(
    'retains raw provider output when PlanV3 semantics are invalid',
    () async {
      final invalidPlan = _respondPlan()
        ..['commands'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'command_id': 'mute',
            'type': 'row.set_muted',
            'arguments': <String, dynamic>{'row_id': 1, 'muted': true},
          },
        ];
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(_responseWithArguments(jsonEncode(invalidPlan))),
          200,
        ),
      );
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'gpt-5.4-mini',
        httpClient: client,
      );

      await expectLater(
        service.plan(context: _context(), originalRequest: 'Mute row one.'),
        throwsA(
          isA<AiV3PlannerException>()
              .having(
                (error) => error.code,
                'code',
                'v3_planner_contract_invalid',
              )
              .having(
                (error) => error.detail,
                'detail',
                'v3_outcome_command_mismatch',
              )
              .having(
                (error) => error.diagnostic['tool_arguments'],
                'tool arguments',
                isNotNull,
              ),
        ),
      );
    },
  );

  test('reports timeout as a sanitized planner error', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 200);
    });
    final service = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      requestTimeout: const Duration(milliseconds: 1),
      httpClient: client,
    );

    await expectLater(
      service.plan(context: _context(), originalRequest: 'Rename the row.'),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_timeout',
        ),
      ),
    );
  });

  test('preserves sanitized OpenAI error detail for local diagnosis', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'invalid_function_parameters',
            'param': 'tools[0].parameters',
            'message': 'Unsupported keyword near sk-secret-value',
          },
        }),
        400,
      ),
    );
    final service = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'gpt-5.4-mini',
      httpClient: client,
    );

    await expectLater(
      service.plan(context: _context(), originalRequest: 'Rename the row.'),
      throwsA(
        isA<AiV3PlannerException>()
            .having((error) => error.detail, 'detail', contains('tools[0]'))
            .having((error) => error.detail, 'detail', contains('[redacted]'))
            .having(
              (error) => error.detail,
              'detail',
              isNot(contains('sk-secret-value')),
            ),
      ),
    );
  });

  test(
    'retries once when a production_goal collapses to align-tempo',
    () async {
      var calls = 0;
      late Map<String, dynamic> firstSent;
      late Map<String, dynamic> retrySent;
      final client = MockClient((http.Request httpRequest) async {
        calls += 1;
        final sent = Map<String, dynamic>.from(
          jsonDecode(httpRequest.body) as Map,
        );
        if (calls == 1) {
          firstSent = sent;
          return http.Response(
            jsonEncode(
              _responseWithArguments(
                jsonEncode(_alignOnlyPlan(goalKind: 'production_goal')),
              ),
            ),
            200,
          );
        }
        retrySent = sent;
        return http.Response(
          jsonEncode(_responseWithArguments(jsonEncode(_tempoAndPitchPlan()))),
          200,
        );
      });
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'test-model',
        httpClient: client,
      );

      final result = await service.plan(
        context: _context(),
        originalRequest: 'nightcore this',
      );

      expect(calls, 2);
      expect(
        result.plan.commands.map((command) => command.type).toList(),
        <String>['project.set_tempo', 'clip.adjust_pitch_semitones'],
      );
      expect(result.meta['align_tempo_collapse_retried'], isTrue);
      expect(
        firstSent['metadata'],
        isNot(contains('v3_align_tempo_retry')),
      );
      expect(
        (retrySent['metadata'] as Map)['v3_align_tempo_retry'],
        '1',
      );
      expect(
        firstSent['instructions'],
        isNot(contains(aiV3AlignTempoCollapseRetryReminder.trim())),
      );
      expect(
        retrySent['instructions'],
        contains(aiV3AlignTempoCollapseRetryReminder.trim()),
      );
      expect(retrySent['instructions'], isNot(contains('nightcore')));
    },
  );

  test(
    'does not retry a named_edit align-only plan',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls += 1;
        return http.Response(
          jsonEncode(_responseWithArguments(jsonEncode(_alignOnlyPlan()))),
          200,
        );
      });
      final service = AiV3PlannerService(
        apiKey: 'test-key',
        model: 'test-model',
        httpClient: client,
      );

      final result = await service.plan(
        context: _context(),
        originalRequest: 'make this a nightcore remix',
      );

      expect(calls, 1);
      expect(result.plan.commands.single.type, 'clip.align_tempo_to_project');
      expect(result.meta['align_tempo_collapse_retried'], isNull);
    },
  );

  test('does not retry a named pitch edit', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls += 1;
      return http.Response(
        jsonEncode(
          _responseWithArguments(
            jsonEncode(<String, dynamic>{
              'schema_version': aiV3PlanVersion,
              'outcome': 'plan',
              'goal_kind': 'named_edit',
              'user_message': 'Pitched the vocal.',
              'commands': <Map<String, dynamic>>[
                <String, dynamic>{
                  'command_id': 'pitch',
                  'type': 'clip.adjust_pitch_semitones',
                  'arguments': <String, dynamic>{
                    'clip_id': 'clip-1',
                    'delta_semitones': 3,
                  },
                },
              ],
              'question_options': const <Object>[],
            }),
          ),
        ),
        200,
      );
    });
    final service = AiV3PlannerService(
      apiKey: 'test-key',
      model: 'test-model',
      httpClient: client,
    );

    final result = await service.plan(
      context: _context(),
      originalRequest: 'pitch the vocal +3',
    );

    expect(calls, 1);
    expect(result.plan.commands.single.type, 'clip.adjust_pitch_semitones');
  });
}

Map<String, dynamic> _alignOnlyPlan({
  String goalKind = 'named_edit',
}) => <String, dynamic>{
  'schema_version': aiV3PlanVersion,
  'outcome': 'plan',
  'goal_kind': goalKind,
  'user_message': 'Aligned the clip to the project tempo.',
  'commands': <Map<String, dynamic>>[
    <String, dynamic>{
      'command_id': 'align',
      'type': 'clip.align_tempo_to_project',
      'arguments': <String, dynamic>{
        'clip_id': 'clip-1',
        'mode': 'preserve_pitch',
      },
    },
  ],
  'question_options': const <Object>[],
};

Map<String, dynamic> _tempoAndPitchPlan() => <String, dynamic>{
  'schema_version': aiV3PlanVersion,
  'outcome': 'plan',
  'goal_kind': 'named_edit',
  'user_message': 'Sped up the project and pitched the audio.',
  'commands': <Map<String, dynamic>>[
    <String, dynamic>{
      'command_id': 'tempo',
      'type': 'project.set_tempo',
      'arguments': <String, dynamic>{
        'bpm': 150,
        'time_stretch_audio': true,
        'preserve_pitch': true,
      },
    },
    <String, dynamic>{
      'command_id': 'pitch',
      'type': 'clip.adjust_pitch_semitones',
      'arguments': <String, dynamic>{'clip_id': 'clip-1', 'delta_semitones': 3},
    },
  ],
  'question_options': const <Object>[],
};
