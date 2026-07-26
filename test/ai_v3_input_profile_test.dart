import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_context.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:mixroom/ai/v3/ai_v3_input_profile.dart';
import 'package:mixroom/ai/v3/ai_v3_planner_request.dart';

AiV3CoreContext _context({int noteCount = 0, int assetCount = 0}) {
  final data = <String, dynamic>{
    'schema_version': 'core_context_v3_prototype_1',
    'profile': 'essential',
    'state_digest': 'digest',
    'original_request': 'Change the project.',
    'request_mode': 'new_request',
    'project': <String, dynamic>{'bpm': 120.0},
    'selection': const <String, dynamic>{},
    'rows': <Map<String, dynamic>>[
      <String, dynamic>{
        'row_id': 1,
        'display_index': 0,
        'name': 'Piano',
        'lane_kind': 'instrument',
        'gain_db': 0.0,
        'pan_signed': 0.0,
        'muted': false,
        'soloed': false,
        'clip_ids': const <String>['clip_1'],
        'effects': const <Object>[],
        'automation_targets': const <Object>[],
      },
    ],
    'groups': const <Object>[],
    'master': const <String, dynamic>{
      'gain_db': 0.0,
      'pan_signed': 0.0,
      'effects': <Object>[],
    },
    'clips': <Map<String, dynamic>>[
      <String, dynamic>{
        'clip_id': 'clip_1',
        'row_id': 1,
        'display_index': 0,
        'kind': 'midi',
        'name': 'Piano',
        'start_beat': 0.0,
        'length_beats': 4.0,
        'source_file': 'clip_1.midiclip',
        'instrument_id': 'piano',
        'pitch_semitones': 0.0,
        if (noteCount > 0)
          'midi_notes': List<Map<String, dynamic>>.generate(
            noteCount,
            (index) => <String, dynamic>{
              'pitch': 60 + (index % 12),
              'start_beat': index * 0.25,
              'length_beats': 0.25,
              'velocity': 80,
            },
          ),
      },
    ],
    'instruments': const <String>['piano'],
    'effects': const <Object>[],
    'library_assets': List<Map<String, dynamic>>.generate(
      assetCount,
      (index) => <String, dynamic>{
        'asset_id': 'asset_$index',
        'path': '/synthetic/asset_$index.wav',
        'role': 'sample',
      },
    ),
    'conversation': const <Object>[],
    'capabilities': aiV3CommandTypes.toList()..sort(),
  };
  return AiV3CoreContext(
    profile: AiV3ContextProfile.essential,
    stateDigest: 'digest',
    data: data,
  );
}

AiV3PlannerInputProfile _profile(AiV3CoreContext context) {
  final body = buildAiV3PlannerRequestBody(
    contextData: context.data,
    originalRequest: 'Change the project.',
    model: 'gpt-5.4-mini',
    reasoningEffort: 'low',
    promptTraceId: 'profile-test',
  );
  return AiV3PlannerInputProfile.measure(
    requestBody: body,
    contextData: context.data,
    providerInputTokens: 1234,
  );
}

void main() {
  test('profiles the exact serialized request and labels provider usage', () {
    final context = _context(noteCount: 8, assetCount: 3);
    final body = buildAiV3PlannerRequestBody(
      contextData: context.data,
      originalRequest: 'Change the project.',
      model: 'gpt-5.4-mini',
      reasoningEffort: 'low',
      promptTraceId: 'profile-test',
    );
    final profile = AiV3PlannerInputProfile.measure(
      requestBody: body,
      contextData: context.data,
      providerInputTokens: 1234,
    );

    expect(profile.fullPayload.utf8Bytes, utf8.encode(jsonEncode(body)).length);
    expect(profile.providerInputTokens, 1234);
    expect(profile.primarySections.keys, contains('context.rows'));
    expect(profile.contextDetails.keys, contains('clips.midi_notes'));
    expect(profile.toJson()['measurement_note'], contains('approximation'));
  });

  test('accounts for every current command schema branch exactly once', () {
    final profile = _profile(_context());

    expect(profile.commandSchemaBranches.keys.toSet(), aiV3CommandTypes);
    expect(profile.commandSchemaBranches, hasLength(aiV3CommandTypes.length));
    expect(profile.sharedPlanSchema.utf8Bytes, greaterThan(0));
  });

  test('profiling is deterministic for empty and envelope-sized data', () {
    final emptyFirst = _profile(_context());
    final emptySecond = _profile(_context());
    final maximum = _profile(_context(noteCount: 512, assetCount: 250));

    expect(emptyFirst.toJson(), emptySecond.toJson());
    expect(
      maximum.fullPayload.utf8Bytes,
      greaterThan(emptyFirst.fullPayload.utf8Bytes),
    );
  });

  test('profile output contains measurements but not scalar values or secrets',
      () {
    final context = _context();
    context.data['authorization'] = 'Bearer sk-secret-value';
    final encoded = jsonEncode(_profile(context).toJson());

    expect(encoded, isNot(contains('sk-secret-value')));
    expect(encoded, isNot(contains('Bearer')));
    expect(encoded, isNot(contains('/synthetic/asset')));
  });
}
