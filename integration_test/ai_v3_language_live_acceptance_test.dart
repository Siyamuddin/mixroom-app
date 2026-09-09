import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/screens/audio_editor.dart';

import 'ai_v3_eval_fixture.dart';
import 'test_harness.dart';

const bool _liveGate = bool.fromEnvironment('AI_V3_LANGUAGE_LIVE_ACCEPTANCE');
const int _scenarioLimit = int.fromEnvironment(
  'AI_V3_LANGUAGE_SCENARIO_LIMIT',
  defaultValue: 12,
);
const int _scenarioStart = int.fromEnvironment(
  'AI_V3_LANGUAGE_SCENARIO_START',
  defaultValue: 0,
);
const int _rounds = int.fromEnvironment(
  'AI_V3_LANGUAGE_ROUNDS',
  defaultValue: 1,
);

class _Scenario {
  const _Scenario({
    required this.id,
    required this.expectedLanguage,
    required this.history,
    required this.prompt,
  });

  final String id;
  final String expectedLanguage;
  final List<(String, String)> history;
  final String prompt;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    id: 'ko_history_to_en_capabilities',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', '이 프로젝트의 드럼을 더 강하게 만들어 줘.'),
      ('assistant', '드럼을 더 강하고 선명하게 만들었습니다.'),
    ],
    prompt:
        'Do not change anything. What kinds of changes can you help me make '
        'to this music project?',
  ),
  _Scenario(
    id: 'es_history_to_en_scope',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', 'Haz que la mezcla suene más cálida.'),
      ('assistant', 'He ajustado la mezcla para que suene más cálida.'),
    ],
    prompt:
        'Without changing the project, briefly explain whether you can edit '
        'both audio and MIDI tracks.',
  ),
  _Scenario(
    id: 'fr_history_to_en_limit',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', 'Ajoute une réverbération légère au piano.'),
      ('assistant', 'Une réverbération légère a été ajoutée au piano.'),
    ],
    prompt:
        'I have not attached a reference image. Can you inspect one anyway? '
        'Do not change the project.',
  ),
  _Scenario(
    id: 'ru_history_to_en_summary',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', 'Сделай бас более плотным.'),
      ('assistant', 'Бас стал плотнее и выразительнее.'),
    ],
    prompt:
        'Do not make edits. Give me a short summary of what is currently in '
        'this project.',
  ),
  _Scenario(
    id: 'ja_history_to_en_guidance',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', 'ピアノを少し明るくしてください。'),
      ('assistant', 'ピアノを少し明るい音に調整しました。'),
    ],
    prompt:
        'What would be a sensible next production step for this project? '
        'Please do not apply it yet.',
  ),
  _Scenario(
    id: 'ar_history_to_en_question',
    expectedLanguage: 'English',
    history: <(String, String)>[
      ('user', 'اجعل الإيقاع أكثر حيوية.'),
      ('assistant', 'تم جعل الإيقاع أكثر حيوية.'),
    ],
    prompt:
        'Before doing anything, ask me one useful question about the sound I '
        'want.',
  ),
  _Scenario(
    id: 'en_history_to_ko_capabilities',
    expectedLanguage: 'Korean',
    history: <(String, String)>[
      ('user', 'Make the piano warmer.'),
      ('assistant', 'I made the piano warmer.'),
    ],
    prompt: '지금은 수정하지 말고, 이 프로젝트에서 어떤 작업을 도와줄 수 있는지 간단히 설명해 줘.',
  ),
  _Scenario(
    id: 'es_history_to_ko_summary',
    expectedLanguage: 'Korean',
    history: <(String, String)>[
      ('user', 'Haz que la batería tenga más energía.'),
      ('assistant', 'La batería ahora tiene más energía.'),
    ],
    prompt: '아무것도 바꾸지 말고 현재 프로젝트에 무엇이 있는지 짧게 요약해 줘.',
  ),
  _Scenario(
    id: 'en_history_to_es_capabilities',
    expectedLanguage: 'Spanish',
    history: <(String, String)>[
      ('user', 'Make the mix wider.'),
      ('assistant', 'I made the mix wider.'),
    ],
    prompt:
        'Sin cambiar nada, explica brevemente qué puedes hacer con las pistas '
        'de este proyecto.',
  ),
  _Scenario(
    id: 'en_history_to_ja_summary',
    expectedLanguage: 'Japanese',
    history: <(String, String)>[
      ('user', 'Make the drums punchier.'),
      ('assistant', 'I made the drums punchier.'),
    ],
    prompt: '何も変更せずに、現在のプロジェクトの内容を短く説明してください。',
  ),
  _Scenario(
    id: 'en_history_to_fr_guidance',
    expectedLanguage: 'French',
    history: <(String, String)>[
      ('user', 'Make the vocal clearer.'),
      ('assistant', 'I made the vocal clearer.'),
    ],
    prompt:
        'Sans rien modifier, suggère brièvement la prochaine étape de '
        'production pour ce projet.',
  ),
  _Scenario(
    id: 'en_history_to_ru_question',
    expectedLanguage: 'Russian',
    history: <(String, String)>[
      ('user', 'Make the bass fuller.'),
      ('assistant', 'I made the bass fuller.'),
    ],
    prompt:
        'Ничего не меняй. Задай мне один полезный вопрос о желаемом звучании.',
  ),
];

class _LocalBridgeAuthService extends IntegrationTestAuthService {
  @override
  Future<String?> getIdTokenOrNull() async => 'local-live-eval-token';

  @override
  Future<String?> refreshIdTokenOrNull() async => 'local-live-eval-token';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'captures last-prompt language evidence with conflicting history',
    (tester) async {
      if (!_liveGate) return;
      expect(_scenarioStart, inInclusiveRange(0, _scenarios.length - 1));
      expect(
        _scenarioLimit,
        inInclusiveRange(1, _scenarios.length - _scenarioStart),
      );
      expect(_rounds, inInclusiveRange(1, 3));
      _ignoreKnownEditorSemanticsAssertion();

      final auth = _LocalBridgeAuthService();
      addTearDown(auth.dispose);
      final results = <Map<String, dynamic>>[];
      final selected = _scenarios
          .skip(_scenarioStart)
          .take(_scenarioLimit)
          .toList(growable: false);

      for (var round = 1; round <= _rounds; round++) {
        for (final scenario in selected) {
          final result = await _runScenario(
            tester: tester,
            auth: auth,
            scenario: scenario,
            round: round,
          );
          results.add(result);
          expect(result['completed'], isTrue, reason: '${scenario.id} failed');
        }
      }

      final evidence = <String, dynamic>{
        'contract': 'pro4_language_live_acceptance_v1',
        'request_count': results.length,
        'results': results,
      };
      final evidenceFile = File(
        '${Directory.systemTemp.path}/pro4_language_live_acceptance_'
        '${_scenarioStart}_$_scenarioLimit.json',
      );
      await evidenceFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(evidence),
        flush: true,
      );
      // Language is deliberately reviewed from the model text rather than by
      // adding a brittle writing-system detector to app or test behavior.
      // ignore: avoid_print
      print('PRO4_LANGUAGE_LIVE_EVIDENCE ${evidenceFile.path}');
      // ignore: avoid_print
      print('PRO4_LANGUAGE_LIVE_RESULTS ${jsonEncode(evidence)}');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<Map<String, dynamic>> _runScenario({
  required WidgetTester tester,
  required AuthService auth,
  required _Scenario scenario,
  required int round,
}) async {
  await deleteAllProjects();
  final fixture = await createDevelopmentEvalFixture(
    'mixed_small_selected_row',
  );
  await _seedHistory(fixture.directory, scenario.history);
  final controller = AudioEditorEvaluationController();
  await tester.pumpWidget(
    buildIntegrationTestApp(
      authServiceOverride: auth,
      home: AudioEditorScreen(
        mode: 'edit',
        projectDir: fixture.directory,
        isProEntitled: true,
        evaluationController: controller,
      ),
    ),
  );
  await _pumpUntil(tester, () => controller.isAttached);
  await _pumpFor(tester, const Duration(seconds: 2));
  final before = controller.stateDigest;
  final timer = Stopwatch()..start();
  await controller.submit(scenario.prompt);
  await _pumpFor(tester, const Duration(seconds: 2));
  timer.stop();

  final messages = await _readMessages(fixture.directory);
  final seededAssistantCount = scenario.history
      .where((message) => message.$1 == 'assistant')
      .length;
  final assistantMessages = messages
      .where((message) => message['authorId'] == 'assistant')
      .toList(growable: false);
  final newAssistantMessages = assistantMessages
      .skip(seededAssistantCount)
      .toList(growable: false);
  final response = newAssistantMessages.isEmpty
      ? ''
      : newAssistantMessages.last['text']?.toString().trim() ?? '';
  final after = controller.stateDigest;
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpFor(tester, const Duration(milliseconds: 300));

  return <String, dynamic>{
    'scenario': scenario.id,
    'round': round,
    'expected_language': scenario.expectedLanguage,
    'prompt': scenario.prompt,
    'response': response,
    'elapsed_ms': timer.elapsedMilliseconds,
    'state_unchanged': before == after,
    'completed': response.isNotEmpty,
  };
}

Future<void> _seedHistory(
  Directory directory,
  List<(String, String)> history,
) async {
  final project = await ProjectManager.readProjectJson(directory);
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  project['assistantChat'] = <String, dynamic>{
    'stateSessionId': 'synthetic-language-history',
    'messages': <Map<String, dynamic>>[
      for (var index = 0; index < history.length; index++)
        <String, dynamic>{
          'id': 'synthetic-history-$index',
          'authorId': history[index].$1,
          'text': history[index].$2,
          'createdAtMs': now - (history.length - index) * 1000,
        },
    ],
  };
  await ProjectManager.writeProjectJson(directory, project);
}

Future<List<Map<String, dynamic>>> _readMessages(Directory directory) async {
  final project = await ProjectManager.readProjectJson(directory);
  final chat = project['assistantChat'];
  final rawMessages = chat is Map ? chat['messages'] : null;
  if (rawMessages is! List) return const <Map<String, dynamic>>[];
  return rawMessages
      .whereType<Map>()
      .map((message) => Map<String, dynamic>.from(message))
      .toList(growable: false);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > timeout) {
      throw TimeoutException('Timed out waiting for the editor test hook.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _ignoreKnownEditorSemanticsAssertion() {
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains(
          'A SemanticsNode with action "increase" needs to be annotated',
        ) ||
        (message.contains("'package:flutter/src/rendering/object.dart'") &&
            message.contains("'node.built'"))) {
      return;
    }
    previousHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousHandler);
}
