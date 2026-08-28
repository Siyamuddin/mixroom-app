import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_service.dart';

AiV3CoreContext _context({List<Map<String, String>> conversation = const []}) =>
    AiV3CoreContext(
      profile: AiV3ContextProfile.essential,
      stateDigest: 'digest-1',
      data: <String, dynamic>{
        'schema_version': 'core_context_v3_prototype_1',
        'original_request': 'duplicate must be removed',
        'conversation': conversation,
        'project': <String, dynamic>{'project_id': 'project-1', 'bpm': 120},
        'rows': const <Object>[],
        'clips': const <Object>[],
      },
    );

Map<String, dynamic> _respondPlan() => <String, dynamic>{
  'schema_version': aiV3PlanVersion,
  'outcome': 'respond',
  'goal_kind': 'question',
  'user_message': 'The project is at 120 BPM.',
  'skipped': const <Object>[],
  'commands': const <Object>[],
  'question_options': const <Object>[],
};

Map<String, dynamic> _serverResponse(
  Map<String, dynamic> plan, {
  Map<String, dynamic> extra = const <String, dynamic>{},
  Map<String, dynamic> traceExtra = const <String, dynamic>{},
}) => <String, dynamic>{
  'schema_version': aiV3ServerResponseVersion,
  'plan': plan,
  'trace': <String, dynamic>{
    'contract_version': 'mixroom_v3_server_contract_2',
    'contract_fingerprint': 'abcdef0123456789',
    'request_id': 'request-1',
    ...traceExtra,
  },
  ...extra,
};

AiV3PlannerService _service(
  http.Client client, {
  Future<String?> Function()? authTokenProvider,
  Future<String?> Function()? refreshAuthTokenProvider,
  Set<String> commandTypes = aiV3CommandTypes,
  bool resourceRefsEnabled = false,
  Duration timeout = const Duration(seconds: 2),
}) => AiV3PlannerService(
  proxyApiBaseUrl: 'https://proxy.example/',
  proxyPath: 'v1/llm/v3/responses',
  authTokenProvider: authTokenProvider ?? () async => 'session-token',
  refreshAuthTokenProvider: refreshAuthTokenProvider,
  commandTypes: commandTypes,
  resourceRefsEnabled: resourceRefsEnabled,
  requestTimeout: timeout,
  httpClient: client,
);

void main() {
  test('builds only the context request contract with sorted capabilities', () {
    final conversation = List<Map<String, String>>.generate(
      14,
      (index) => <String, String>{
        'role': index.isEven ? 'user' : 'assistant',
        'content': 'turn-$index',
      },
    );
    final body = buildAiV3ContextRequestBody(
      contextData: _context(conversation: conversation).data,
      originalRequest: ' Keep everything unchanged. ',
      promptTraceId: 'trace-1',
      commandTypes: const <String>{'transport.stop', 'transport.play'},
      resourceRefsEnabled: true,
    );

    expect(body.keys.toSet(), <String>{
      'request_contract',
      'original_request',
      'conversation',
      'core_context',
      'plan_schema_version',
      'supported_command_types',
      'resource_refs_enabled',
      'project_id',
      'prompt_trace_id',
    });
    expect(body['request_contract'], aiV3ContextRequestContract);
    expect(body['original_request'], 'Keep everything unchanged.');
    expect(body['plan_schema_version'], aiV3PlanVersion);
    expect(body['supported_command_types'], <String>[
      'transport.play',
      'transport.stop',
    ]);
    expect(body['resource_refs_enabled'], isTrue);
    expect(body['project_id'], 'project-1');
    expect(body['prompt_trace_id'], 'trace-1');
    expect(body['conversation'], hasLength(12));
    expect((body['conversation'] as List).first['content'], 'turn-2');
    final core = body['core_context'] as Map;
    expect(core.containsKey('original_request'), isFalse);
    expect(core.containsKey('conversation'), isFalse);
    for (final forbidden in <String>{
      'model',
      'reasoning',
      'instructions',
      'tools',
      'tool_choice',
      'parallel_tool_calls',
      'max_output_tokens',
      'store',
      'input',
      'messages',
      'ai_feature',
      'client_context',
    }) {
      expect(body.containsKey(forbidden), isFalse, reason: forbidden);
    }
  });

  test(
    'authenticated proxy sends context only and parses sanitized envelope',
    () async {
      late http.Request sentRequest;
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentRequest = request;
        sentBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode(
            _serverResponse(
              _respondPlan(),
              extra: <String, dynamic>{
                'prompt_rate_limit': <String, dynamic>{'can_submit': true},
              },
              traceExtra: <String, dynamic>{'prompt_trace_id': 'trace-1'},
            ),
          ),
          200,
        );
      });

      final result = await _service(client).plan(
        context: _context(),
        originalRequest: 'What is the BPM?',
        promptTraceId: 'trace-1',
      );

      expect(
        sentRequest.url.toString(),
        'https://proxy.example/v1/llm/v3/responses',
      );
      expect(sentRequest.headers['authorization'], 'Bearer session-token');
      expect(sentBody['request_contract'], aiV3ContextRequestContract);
      expect(sentBody.containsKey('instructions'), isFalse);
      expect(sentBody.containsKey('tools'), isFalse);
      expect(sentBody.containsKey('model'), isFalse);
      expect(result.plan.outcome, 'respond');
      expect(result.meta.containsKey('model'), isFalse);
      expect(result.meta.containsKey('reasoning_effort'), isFalse);
      expect(result.meta.containsKey('provider_response_id'), isFalse);
      expect(result.meta['prompt_rate_limit'], <String, dynamic>{
        'can_submit': true,
      });
    },
  );

  test(
    'refreshes rejected authentication exactly once with the same body',
    () async {
      var calls = 0;
      final authorizations = <String>[];
      final bodies = <String>[];
      final client = MockClient((request) async {
        calls += 1;
        authorizations.add(request.headers['authorization'] ?? '');
        bodies.add(request.body);
        if (calls == 1)
          return http.Response('{"error":{"code":"expired"}}', 401);
        return http.Response(jsonEncode(_serverResponse(_respondPlan())), 200);
      });

      await _service(
        client,
        authTokenProvider: () async => 'expired-token',
        refreshAuthTokenProvider: () async => 'refreshed-token',
      ).plan(context: _context(), originalRequest: 'What is the BPM?');

      expect(calls, 2);
      expect(authorizations, <String>[
        'Bearer expired-token',
        'Bearer refreshed-token',
      ]);
      expect(bodies[0], bodies[1]);
    },
  );

  test('does not call HTTP without app authentication', () async {
    final service = _service(
      MockClient((_) async {
        fail('HTTP must not run without authentication.');
      }),
      authTokenProvider: () async => null,
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
  });

  test('does not repeat an align-only production plan on the client', () async {
    var calls = 0;
    final plan = <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'goal_kind': 'production_goal',
      'user_message': 'The clip was aligned.',
      'skipped': const <Object>[],
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'align-1',
          'type': 'clip.align_tempo_to_project',
          'arguments': <String, dynamic>{
            'clip_id': 'clip-1',
            'mode': 'preserve_pitch',
          },
        },
      ],
      'question_options': const <Object>[],
    };
    final client = MockClient((_) async {
      calls += 1;
      return http.Response(jsonEncode(_serverResponse(plan)), 200);
    });

    final result = await _service(
      client,
      commandTypes: const <String>{'clip.align_tempo_to_project'},
    ).plan(context: _context(), originalRequest: 'Make this a remix.');

    expect(result.plan.goalKind, AiV3GoalKind.productionGoal);
    expect(calls, 1);
  });

  test('rejects commands outside the declared client surface', () async {
    final plan = <String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'goal_kind': 'named_edit',
      'user_message': 'Playback started.',
      'skipped': const <Object>[],
      'commands': <Map<String, dynamic>>[
        <String, dynamic>{
          'command_id': 'play-1',
          'type': 'transport.play',
          'arguments': const <String, dynamic>{},
        },
      ],
      'question_options': const <Object>[],
    };
    final client = MockClient(
      (_) async => http.Response(jsonEncode(_serverResponse(plan)), 200),
    );
    await expectLater(
      _service(
        client,
        commandTypes: const <String>{'transport.stop'},
      ).plan(context: _context(), originalRequest: 'Play.'),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_contract_invalid',
        ),
      ),
    );
  });

  test('rejects provider-shaped and unknown response fields', () async {
    for (final payload in <Map<String, dynamic>>[
      <String, dynamic>{'output': const <Object>[]},
      _serverResponse(
        _respondPlan(),
        extra: <String, dynamic>{'model': 'secret'},
      ),
      _serverResponse(
        _respondPlan(),
        traceExtra: <String, dynamic>{'provider_response_id': 'secret'},
      ),
      <String, dynamic>{
        ..._serverResponse(_respondPlan()),
        'schema_version': 'v3_plan_response_server_v99',
      },
    ]) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(payload), 200),
      );
      await expectLater(
        _service(
          client,
        ).plan(context: _context(), originalRequest: 'Question.'),
        throwsA(
          isA<AiV3PlannerException>().having(
            (error) => error.code,
            'code',
            'v3_server_response_contract_invalid',
          ),
        ),
      );
    }
  });

  test('does not retain arbitrary server error messages', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{
            'code': 'v3_server_contract_disabled',
            'message': 'secret prompt and sk-sensitive',
          },
        }),
        503,
      ),
    );
    try {
      await _service(
        client,
      ).plan(context: _context(), originalRequest: 'Question.');
      fail('Expected a planner exception.');
    } on AiV3PlannerException catch (error) {
      expect(error.code, 'v3_planner_http_error');
      expect(error.detail, 'http_503:v3_server_contract_disabled');
      expect(error.toString(), isNot(contains('secret prompt')));
      expect(error.diagnostic, isEmpty);
    }
  });

  test('maps invalid JSON and timeout to safe failures', () async {
    await expectLater(
      _service(
        MockClient((_) async => http.Response('not-json', 200)),
      ).plan(context: _context(), originalRequest: 'Question.'),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_response_invalid_json',
        ),
      ),
    );

    final timeoutClient = MockClient((_) async {
      await Completer<void>().future;
      return http.Response('{}', 200);
    });
    await expectLater(
      _service(
        timeoutClient,
        timeout: const Duration(milliseconds: 1),
      ).plan(context: _context(), originalRequest: 'Question.'),
      throwsA(
        isA<AiV3PlannerException>().having(
          (error) => error.code,
          'code',
          'v3_planner_timeout',
        ),
      ),
    );
  });
}
