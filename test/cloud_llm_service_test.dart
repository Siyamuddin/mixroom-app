import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/debug_system_prompt.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/models/mixing_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudLlmService', () {
    test('kDebugSystemPrompt stays in sync with the server prompt', () {
      final serverText = File(
        'backend/llm_proxy/src/common/llm_contract.py',
      ).readAsStringSync();
      const startMarker = 'SYSTEM_PROMPT_V3 = """';
      final start = serverText.indexOf(startMarker);
      expect(start, isNot(-1));

      final promptStart = start + startMarker.length;
      final promptEnd = serverText.indexOf('""".strip()', promptStart);
      expect(promptEnd, greaterThan(promptStart));

      final serverPrompt = serverText.substring(promptStart, promptEnd).trim();
      expect(kDebugSystemPrompt.trim(), serverPrompt);
    });

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
      expect(
        result.toolArgs?['assistant_message'],
        'Enhancé la calidad para que suene más sofisticado.',
      );
      final action = (result.toolArgs?['actions'] as List).first as Map;
      final goal = action['goal'] as Map;
      final intents = goal['intents'] as List;
      final target = goal['target'] as Map;
      expect((intents.first as Map)['kind'], 'limiter');
      expect(target['scope'], 'master');
      expect(target.containsKey('row_index'), isFalse);
      expect(target.containsKey('role'), isFalse);
    });

    test('repairs legacy mix goal types to mix_request', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'mix_model_request',
                'arguments': {
                  'mode': 'execute',
                  'assistant_message': 'Added some space to the bass.',
                  'actions': [
                    {
                      'goal': {
                        'type': 'reverb',
                        'intents': [
                          {
                            'kind': 'reverb',
                            'direction': 'up',
                            'confidence': 0.7,
                          }
                        ],
                        'target': {
                          'scope': 'row',
                          'row_index': 2,
                          'confidence': 0.8,
                        },
                        'intensity': 0.18,
                        'execution_profile': 'creative_bold',
                        'audibility': 'obvious',
                        'reference_target': {
                          'row_index': 5,
                          'confidence': 0.91,
                        },
                        'reference_mode': 'full_mix',
                        'reference_closeness': 'close',
                        'style_tags': ['washed', 'club'],
                        'destructive_ok': false,
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
        apiKey: 'sk-test',
        model: 'gpt-5.4-nano',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'add more wetness',
        projectSnapshot: 'Track 3: Bass',
      );

      expect(result.toolName, 'mix_model_request');
      final action = (result.toolArgs?['actions'] as List).first as Map;
      final goal = action['goal'] as Map;
      expect(goal['type'], 'mix_request');
      expect(goal['execution_profile'], 'creative_bold');
      expect(goal['audibility'], 'obvious');
      expect(goal['reference_target'], {
        'row_index': 5,
        'confidence': 0.91,
      });
      expect(goal['reference_mode'], 'full_mix');
      expect(goal['reference_closeness'], 'close');
      expect(goal['style_tags'], ['washed', 'club']);
      expect(goal['destructive_ok'], isFalse);
      expect(((goal['intents'] as List).first as Map)['kind'], 'reverb');
    });

    test('drops malformed bare clip_edit actions before they reach the app',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Moving the selected clip up one row.',
                  'actions': [
                    {
                      'type': 'clip_edit',
                      'data': {},
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'move this selected clip up a row',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        'Moving the selected clip up one row.\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.',
      );
    });

    test('does not rewrite bare dialog_remove_range based on prompt text',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      'Deleting all silences from the voice track.',
                  'actions': [
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'dialog_remove_range',
                        'target': {
                          'row_index': 0,
                        },
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'delete all silences in the voice track',
        projectSnapshot: 'Track 1: Voice',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        'Deleting all silences from the voice track.\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.',
      );
    });

    test('drops incomplete dialog_remove_range actions without a locator',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Deleting that phrase.',
                  'actions': [
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'dialog_remove_range',
                        'target': {
                          'row_index': 0,
                        },
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'delete that phrase on the voice track',
        projectSnapshot: 'Track 1: Voice',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        'Deleting that phrase.\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.',
      );
    });

    test('invalid daw action payload preserves assistant text with disclaimer',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      "I can help - what part of the topline isn't showing up?",
                  'actions': [
                    {
                      'type': 'tutorial',
                      'data': {
                        'message':
                            'Open the piano clip and reveal the melody notes.',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: "i don't see it",
        projectSnapshot: 'Track 1: Piano MIDI',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I can help - what part of the topline isn't showing up?\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.",
      );
    });

    test('preserves meaningful clip move actions for rhythm edits', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      "I'll tighten up the groove and give it a fresh rhythm.",
                  'actions': [
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'move',
                        'target': {
                          'scope': 'selected',
                          'prefer_selected': true,
                        },
                        'delta_beats': 0.5,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'switch up the rhythm',
        projectSnapshot: 'Track 1: Kick, Track 2: Snare, Track 3: Hats',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final action = ((result.toolArgs?['actions'] as List).single
          as Map<String, dynamic>);
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(action['type'], 'clip_edit');
      expect(data['operation'], 'move');
      expect((data['delta_beats'] as num).toDouble(), 0.5);
    });

    test(
        'drops no-op move and unsupported range cut while preserving whole-beat duplicate',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      "I'll rework the whole groove into a looser, more chilled rhythm.",
                  'actions': [
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'duplicate',
                        'target': {
                          'scope': 'all_audio',
                        },
                        'new_start_measure': 9,
                        'repeat_count': 1,
                        'delta_measures': 8,
                      },
                    },
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'move',
                        'target': {
                          'scope': 'all_audio',
                        },
                        'delta_measures': 0,
                        'delta_ms': 0,
                      },
                    },
                    {
                      'type': 'clip_edit',
                      'data': {
                        'operation': 'cut',
                        'target': {
                          'scope': 'all_audio',
                        },
                        'from_ms': 0,
                        'to_ms': 0,
                      },
                    },
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'whole beat',
        projectSnapshot: 'Track 1: Kick, Track 2: Snare, Track 3: Hats',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect(actions.length, 1);
      final action = actions.single;
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(action['type'], 'clip_edit');
      expect(data['operation'], 'duplicate');
      expect((data['target'] as Map)['scope'], 'all_audio');
      expect(data['new_start_measure'], 9);
    });

    test('preserves capable project_edit and sample_insert actions locally',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Setting tempo and dropping in a kick.',
                  'actions': [
                    {
                      'type': 'project_edit',
                      'data': {
                        'operation': 'set_bpm',
                        'bpm': '156',
                      },
                    },
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'insert_sample',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                            'start_measure': 1,
                          }
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'set bpm and add a kick',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect((actions[0]['type'] as String), 'project_edit');
      expect(((actions[0]['data'] as Map)['operation'] as String), 'set_tempo');
      expect(((actions[0]['data'] as Map)['tempo_bpm'] as num).toDouble(), 156);
      expect((actions[1]['type'] as String), 'sample_insert');
      expect(
        ((actions[1]['data'] as Map)['operation'] as String),
        'insert_audio_clips',
      );
    });

    test(
        'does not retry direct OpenAI solely because library snapshot is present',
        () async {
      final requestBodies = <Map<String, dynamic>>[];
      var callCount = 0;
      final client = MockClient((request) async {
        callCount += 1;
        requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        throw TimeoutException('slow');
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'brighten the lead vocal a bit',
        projectSnapshot: 'Track 1: Lead Vocal',
        selectionSnapshot: 'selected_row_index=0',
        librarySnapshot: 'built_in_instruments:\n- Keys: [mixroom.warm_keys]',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't complete that request just now. Please try again in a moment.",
      );
      expect(callCount, 1);
      expect(requestBodies, hasLength(1));
    });

    test(
        'retries direct OpenAI by dropping pending mix while retaining library snapshot',
        () async {
      final requestBodies = <Map<String, dynamic>>[];
      var callCount = 0;
      final client = MockClient((request) async {
        callCount += 1;
        requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (callCount == 1) {
          throw TimeoutException('slow');
        }
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'informational_response',
                'arguments': {
                  'message': 'Done.',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'brighten the lead vocal a bit',
        projectSnapshot: 'Track 1: Lead Vocal',
        selectionSnapshot: 'selected_row_index=0',
        librarySnapshot:
            'sample_packs:\n- Starter Kit v1/Processed Drums/Kick-01.flac',
        pendingMix: MixingResult(
          actions: [
            MixAction('set_row_gain', {'row': 0, 'delta': 1.5})
          ],
          summary: 'Raised lead vocal slightly.',
          isNoOp: false,
        ),
      );

      expect(result.toolName, 'informational_response');
      expect(callCount, 2);

      final firstInput = requestBodies.first['input'] as List;
      final secondInput = requestBodies.last['input'] as List;
      final firstHasLibrary = firstInput.any(
        (entry) =>
            (entry as Map)['content'].toString().contains('LIBRARY_SNAPSHOT:'),
      );
      final secondHasLibrary = secondInput.any(
        (entry) =>
            (entry as Map)['content'].toString().contains('LIBRARY_SNAPSHOT:'),
      );
      final firstHasPendingMix = firstInput.any(
        (entry) => (entry as Map)['content']
            .toString()
            .contains('PENDING_MIX_PROPOSAL:'),
      );
      final secondHasPendingMix = secondInput.any(
        (entry) => (entry as Map)['content']
            .toString()
            .contains('PENDING_MIX_PROPOSAL:'),
      );

      expect(firstHasLibrary, isTrue);
      expect(secondHasLibrary, isTrue);
      expect(firstHasPendingMix, isTrue);
      expect(secondHasPendingMix, isFalse);
    });

    test('normalizes sample replacement operations locally', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Swapping the snare sample.',
                  'actions': [
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'swap_sample',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Snare-02.flac',
                            'target': {
                              'row_index': 1,
                              'label_contains': 'snare',
                            },
                          }
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'change that snare for me',
        projectSnapshot: 'Track 2: snare clips',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect((actions.single['type'] as String), 'sample_insert');
      expect(
        (((actions.single['data'] as Map)['operation']) as String),
        'replace_audio_clips',
      );
    });

    test(
        'preserves model-selected sample replacements without prompt-word vetoes',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Making the rhythm cooler.',
                  'actions': [
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'replace_audio_clips',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Hi-Hat-01.flac',
                            'target': {
                              'row_index': 0,
                            },
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'cooler rhythm',
        projectSnapshot: 'Track 1: Kick, Track 2: Snare, Track 3: Hats',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect(actions.single['type'], 'sample_insert');
      expect(
        (((actions.single['data'] as Map)['operation']) as String),
        'replace_audio_clips',
      );
    });

    test(
        'drops vague groove follow-ups that try to use automation templates as fake rhythm changes',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      'I’ll loosen the groove and make it more laid-back.',
                  'actions': [
                    {
                      'type': 'automation_edit',
                      'data': {
                        'operation': 'apply_template',
                        'target': {
                          'scope': 'selected',
                          'prefer_selected': true,
                        },
                        'template': 'subtle_groove_swing',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'switch up rhythm more chill',
        projectSnapshot: 'Track 1: Kick, Track 2: Snare, Track 3: Hats',
      );

      expect(result.toolName, 'informational_response');
      expect(result.text, contains("I couldn't complete"));
    });

    test('accepts midi create_clip and normalizes one-based beat note payloads',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'Laying down a dark chord progression.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'create_clip',
                        'target': {
                          'row_index': 0,
                        },
                        'instrument_id': 'mixroom.warm_keys',
                        'length_measures': 4,
                        'notes': [
                          {
                            'pitch': 'D3',
                            'start_beat': 1,
                            'duration_beats': 4,
                            'velocity': 82,
                          },
                          {
                            'pitch': 'F3',
                            'start_beat': 1,
                            'duration_beats': 4,
                            'velocity': 82,
                          },
                          {
                            'pitch': 'Bb2',
                            'start_beat': 5,
                            'duration_beats': 4,
                            'velocity': 80,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'give me dark chord progression trap style',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      final action = actions.single;
      expect(action['type'], 'midi_compose');
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(data['operation'], 'create_clip');
      final notes = (data['notes'] as List).cast<Map>();
      expect(notes.first['pitch'], 50);
      expect(notes.first['start_beat'], 0.0);
      expect(notes.first['length_beats'], 4.0);
      expect(notes.first['velocity'], closeTo(82 / 127, 1e-6));
      expect(notes.last['start_beat'], 4.0);
    });

    test('normalizes midi notes that use measure plus beat positions',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      'I will lay down an original 8-bar jazz piano chord part.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'create_clip',
                        'target': {
                          'row_index': 0,
                        },
                        'instrument_id': 'sfz.vsco.upright_piano',
                        'length_measures': 8,
                        'notes': [
                          {
                            'measure': 1,
                            'beat': 1,
                            'duration_beats': 4,
                            'pitch': 50,
                            'velocity': 72,
                          },
                          {
                            'measure': 2,
                            'beat': 1,
                            'duration_beats': 4,
                            'pitch': 43,
                            'velocity': 72,
                          },
                          {
                            'measure': 3,
                            'beat': 3,
                            'duration_beats': 2,
                            'pitch': 45,
                            'velocity': 72,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'jazz chords',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final action = ((result.toolArgs?['actions'] as List).single
          as Map<String, dynamic>);
      final data = Map<String, dynamic>.from(action['data'] as Map);
      final notes = (data['notes'] as List).cast<Map>();
      expect(notes[0]['start_beat'], 0.0);
      expect(notes[1]['start_beat'], 4.0);
      expect(notes[2]['start_beat'], 10.0);
      expect(notes[0]['velocity'], closeTo(72 / 127, 1e-6));
    });

    test('accepts audio-to-midi midi_compose without synthetic note payloads',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      'I will convert that audio clip to MIDI.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'convert_audio_to_midi',
                        'target': {
                          'row_index': 1,
                          'prefer_selected': true,
                        },
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'convert this vocal to midi',
        projectSnapshot: 'Track 2: Lead Vocal',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      final action = actions.single;
      expect(action['type'], 'midi_compose');
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(data['operation'], 'convert_audio_to_midi');
      expect((data['target'] as Map)['row_index'], 1);
      expect(data.containsKey('notes'), isFalse);
      expect(data.containsKey('progression'), isFalse);
    });

    test('preserves existing midi notes for length-only span edits', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message':
                      'I will extend that piano clip to 8 bars.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'replace_notes',
                        'target': {
                          'row_index': 1,
                          'prefer_selected': true,
                        },
                        'length_measures': 8,
                        'instrument_id': 'sfz.vsco.upright_piano',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'make that 8 measures long rather than now',
        projectSnapshot: 'Track 2: Piano MIDI',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final action = ((result.toolArgs?['actions'] as List).single
          as Map<String, dynamic>);
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(data['operation'], 'replace_notes');
      expect(data['preserve_existing_notes'], isTrue);
      expect(data['length_measures'], 8);
    });

    test(
        'rejects style-only creative midi follow-ups that omit notes or progression',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          '''
          {
            "output": [
              {
                "type": "function_call",
                "name": "daw_assistant_actions",
                "arguments": {
                  "assistant_message": "I'll add a running topline on the same piano.",
                  "actions": [
                    {
                      "type": "midi_compose",
                      "data": {
                        "operation": "append_notes",
                        "target": {
                          "row_index": 0,
                          "clip_index": 0
                        },
                        "length_measures": 8,
                        "preserve_existing_notes": true,
                        "style": "running topline",
                        "register": "upper",
                        "density": "medium",
                        "direction": "mostly_stepwise"
                      }
                    }
                  ]
                }
              }
            ]
          }
          ''',
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'put running melody topline on same piano',
        projectSnapshot: 'Track 1: Piano MIDI',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        contains("I'll add a running topline on the same piano."),
      );
      expect(result.text, contains('nothing changed'));
    });

    test(
        'rejects tempo-only remnants when a generated beat action is structurally invalid',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          '''
          {
            "output": [
              {
                "type": "function_call",
                "name": "daw_assistant_actions",
                "arguments": {
                  "assistant_message": "I'll lay in a 150 BPM trap drop with drums and a synth sub.",
                  "actions": [
                    {
                      "type": "project_edit",
                      "data": {
                        "operation": "set_tempo",
                        "bpm": 150
                      }
                    },
                    {
                      "type": "sample_insert",
                      "data": {
                        "operation": "insert_audio_clips",
                        "items": [
                          {
                            "library_path": "Starter Kit v1/Processed Drums/Kick-01.flac",
                            "row_index": 0,
                            "start_measure": 1,
                            "length_measures": 8
                          },
                          {
                            "library_path": "mixroom.mellow_sub",
                            "row_index": 3,
                            "start_measure": 1,
                            "length_measures": 8
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
          ''',
          200,
        );
      });

      final service = CloudLlmService(
        apiKey: 'sk-test',
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'make edm trap drop drums 150 bpm with a synth sub',
        projectSnapshot: 'Project is empty',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        contains("I'll lay in a 150 BPM trap drop with drums and a synth sub."),
      );
      expect(result.text, contains('nothing changed'));
    });

    test('does not infer create_new_clip from prompt text alone', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will add a fresh piano chord clip.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'create_clip',
                        'target': {
                          'row_index': 1,
                          'prefer_selected': true,
                        },
                        'instrument_id': 'sfz.vsco.upright_piano',
                        'notes': [
                          {
                            'pitch': 'C4',
                            'start_beat': 1,
                            'duration_beats': 4,
                            'velocity': 80,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'jazz chords please new piano',
        projectSnapshot: 'Track 2: Piano MIDI',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final action = ((result.toolArgs?['actions'] as List).single
          as Map<String, dynamic>);
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(data['operation'], 'create_clip');
      expect(data.containsKey('create_new_clip'), isFalse);
      final target = Map<String, dynamic>.from(data['target'] as Map);
      expect(target['prefer_selected'], isTrue);
    });

    test('repairs high-tempo backbeat scaffolds without expanding extra items',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will build a trap drum beat.',
                  'actions': [
                    {
                      'type': 'project_edit',
                      'data': {
                        'operation': 'set_tempo',
                        'tempo_bpm': 150,
                      },
                    },
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'insert_audio_clips',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                            'repeat_count': 4,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-02.flac',
                            'row_index': 0,
                            'repeat_count': 4,
                            'start_beat': 3,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Snare-01.flac',
                            'row_index': 1,
                            'repeat_count': 4,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'add trap drum beat 150bpm',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect(actions.length, 2);
      final sampleAction = actions.last;
      expect(sampleAction['type'], 'sample_insert');
      final sampleData = Map<String, dynamic>.from(sampleAction['data'] as Map);
      final items = (sampleData['items'] as List).cast<Map>();
      expect(items.length, greaterThanOrEqualTo(3));
      final kickItems = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('kick'))
          .toList(growable: false);
      final snareItems = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('snare'))
          .toList(growable: false);
      expect(kickItems, isNotEmpty);
      expect(snareItems, isNotEmpty);
      expect(
        kickItems.map((item) => item['library_path']).toSet().length,
        2,
      );
      expect(
        items.any((item) => item.containsKey('length_measures')),
        isFalse,
      );
      expect(items.where((item) => item.containsKey('repeat_count')).length, 3);
      expect(snareItems.single['start_beat'], 3);
      expect(snareItems.single['step_beats'], 4);
    });

    test('does not expand generic beat roles into a scaffold on the client',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will build a drum and bass beat.',
                  'actions': [
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'insert_audio_clips',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Snare-01.flac',
                            'row_index': 1,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Hat-01.flac',
                            'row_index': 2,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Crash-01.flac',
                            'row_index': 3,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'drum n bass beat 175 tempo',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect(actions.length, 1);
      final sampleAction = actions.single;
      final sampleData = Map<String, dynamic>.from(sampleAction['data'] as Map);
      final items = (sampleData['items'] as List).cast<Map>();
      expect(items.length, 4);
      expect(items.any((item) => item.containsKey('start_beat')), isFalse);
      expect(
        items.any((item) =>
            (item['library_path'] as String).toLowerCase().contains('crash')),
        isTrue,
      );
    });

    test(
        'repairs lower-tempo colliding drum placements onto a 2-and-4 backbeat',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will build a hip hop drum beat.',
                  'actions': [
                    {
                      'type': 'project_edit',
                      'data': {
                        'operation': 'set_tempo',
                        'tempo_bpm': 96,
                      },
                    },
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'insert_audio_clips',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                            'start_beat': 1,
                            'step_beats': 2,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Clap-01.flac',
                            'row_index': 1,
                            'start_beat': 1,
                            'step_beats': 2,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Hat-01.flac',
                            'row_index': 2,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'make hip hop drum beat 96bpm',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      expect(actions.length, 2);
      final sampleAction = actions.last;
      final sampleData = Map<String, dynamic>.from(sampleAction['data'] as Map);
      final items = (sampleData['items'] as List).cast<Map>();

      final kickStarts = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('kick'))
          .map((item) => (item['start_beat'] as num).toDouble())
          .toList()
        ..sort();
      final clapStarts = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('clap'))
          .map((item) => (item['start_beat'] as num).toDouble())
          .toList()
        ..sort();

      expect(kickStarts, <double>[1.0]);
      expect(clapStarts, <double>[2.0]);
      expect(
        items
            .where((item) =>
                (item['library_path'] as String).toLowerCase().contains('clap'))
            .map((item) => (item['step_beats'] as num).toDouble())
            .toList(),
        <double>[2.0],
      );
    });

    test('preserves disjoint trap role spans without client rescaffolding',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will build a trap beat.',
                  'actions': [
                    {
                      'type': 'sample_insert',
                      'data': {
                        'operation': 'insert_audio_clips',
                        'items': [
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                            'start_beat': 1,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Kick-01.flac',
                            'row_index': 0,
                            'start_beat': 3,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Clap-01.flac',
                            'row_index': 1,
                            'start_beat': 1,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Clap-01.flac',
                            'row_index': 1,
                            'start_beat': 2,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Clap-01.flac',
                            'row_index': 1,
                            'start_beat': 3,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Clap-01.flac',
                            'row_index': 1,
                            'start_beat': 4,
                          },
                          {
                            'library_path':
                                'Starter Kit v1/Processed Drums/Hat-01.flac',
                            'row_index': 2,
                            'start_beat': 1,
                            'step_beats': 0.5,
                            'length_measures': 2,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'trap beat 145',
        projectSnapshot: 'Track 1: empty',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final actions = (result.toolArgs?['actions'] as List).cast<Map>();
      final sampleAction = actions.lastWhere(
        (action) => action['type'] == 'sample_insert',
      );
      final sampleData = Map<String, dynamic>.from(sampleAction['data'] as Map);
      final items = (sampleData['items'] as List).cast<Map>();

      final kickStarts = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('kick'))
          .map((item) => (item['start_beat'] as num).toDouble())
          .toList()
        ..sort();
      final clapStarts = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('clap'))
          .map((item) => (item['start_beat'] as num).toDouble())
          .toList()
        ..sort();
      final hatStarts = items
          .where((item) =>
              (item['library_path'] as String).toLowerCase().contains('hat'))
          .map((item) => (item['start_beat'] as num).toDouble())
          .toList()
        ..sort();

      expect(kickStarts, <double>[1.0, 3.0]);
      expect(clapStarts, <double>[1.0, 2.0, 3.0, 4.0]);
      expect(hatStarts, <double>[1.0]);
      expect(
        items.singleWhere((item) => (item['library_path'] as String)
            .toLowerCase()
            .contains('hat'))['length_measures'],
        2,
      );
    });

    test('does not inject midi span defaults from prompt text', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'daw_assistant_actions',
                'arguments': {
                  'assistant_message': 'I will add a fresh piano chord clip.',
                  'actions': [
                    {
                      'type': 'midi_compose',
                      'data': {
                        'operation': 'create_clip',
                        'target': {
                          'row_index': 1,
                          'prefer_selected': true,
                        },
                        'instrument_id': 'sfz.vsco.upright_piano',
                        'notes': [
                          {
                            'pitch': 'C4',
                            'start_beat': 1,
                            'duration_beats': 4,
                            'velocity': 80,
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'jazz chords please new piano',
        projectSnapshot: 'Track 2: Piano MIDI',
      );

      expect(result.toolName, 'daw_assistant_actions');
      final action = ((result.toolArgs?['actions'] as List).single
          as Map<String, dynamic>);
      final data = Map<String, dynamic>.from(action['data'] as Map);
      expect(data['operation'], 'create_clip');
      expect(data.containsKey('create_new_clip'), isFalse);
      expect(data.containsKey('length_measures'), isFalse);
    });

    test('sanitizes internal leak text in informational responses', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'function_call',
                'name': 'informational_response',
                'arguments': {
                  'message':
                      'There is nothing in project snapshot because isEmpty = true.',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      final result = await service.send(
        conversation: const [],
        userText: 'one button mix',
        projectSnapshot: '',
      );

      expect(result.toolName, 'informational_response');
      expect(
        result.text,
        "I couldn't complete that request just now. Please try again.",
      );
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
        "I understood the intent, but the action payload was incomplete or invalid, so nothing changed.",
      );
    });

    test('preserves specific tutorial assistant text (no placeholder rewrite)',
        () async {
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
      const expected =
          "Here's how to adjust the reverb on the drums track. First open the drums effects tab, then find reverb, then open its controls and adjust the mix knob.";
      expect(result.toolArgs?['assistant_message'], expected);
      expect(result.text, expected);
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
          result.toolArgs?['assistant_message']?.toString() ??
              result.text ??
              '';
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

    test('forwards conversation to proxy without hidden request-style hints',
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
                'arguments': {
                  'message': 'Done.',
                  'cancels_pending': false,
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
      await service.send(
        conversation: const [
          {'role': 'assistant', 'content': '추천해줄게.'},
        ],
        userText: '군대 가기전에 듣는 노래',
        projectSnapshot: 'Track 1: Lead Vocal',
      );

      final conversation =
          (requestBody['conversation'] as List).cast<Map<String, dynamic>>();
      expect(conversation, hasLength(1));
      expect(conversation.first['role'], 'assistant');
      expect(conversation.first['content'], '추천해줄게.');
      expect(requestBody['user_text'], '군대 가기전에 듣는 노래');
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

    test('does not describe upstream 429s as prompt limit exhaustion',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Rate limit reached for model.',
              'type': 'rate_limit_exceeded',
              'code': 'rate_limit_exceeded',
            },
          }),
          429,
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
        "I couldn't complete that request just now. Please try again in a moment.",
      );
      expect(result.text, isNot(contains('prompt limit')));
      expect(result.meta?['soft_error']?['code'], 'request_failed');
      expect(result.meta?['soft_error']?['usage_refunded'], isTrue);
    });

    test(
        'retries proxy requests once after auth rejection with a refreshed token',
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

    test('uses low reasoning for gpt-5.4-mini direct OpenAI requests',
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
                'arguments': {
                  'message': 'Done.',
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
        model: 'gpt-5.4-mini',
        httpClient: client,
      );
      await service.send(
        conversation: const [],
        userText: 'Write some jazz chords.',
        projectSnapshot: 'Track 1: Piano MIDI',
      );

      expect(requestBody['reasoning'], {'effort': 'low'});
      expect(requestBody.containsKey('temperature'), isFalse);
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
        'mixroom-daw-v20260422a:ai_chat',
      );
      expect(requestBody['prompt_cache_retention'], 'in_memory');
      expect(requestBody['max_output_tokens'], 4096);
      expect(result.meta?['cached_prompt_tokens'], 7424);
      expect(
        result.meta?['usage']?['input_tokens_details']?['cached_tokens'],
        7424,
      );
    });
  });
}
