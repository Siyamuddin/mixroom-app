import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_music_generation.dart';

void main() {
  Map<String, dynamic> role({
    required String id,
    required String kind,
    String part = 'drums',
    String instrument = 'sfz.vsco.mixroom_acoustic_drum_kit',
    int low = 0,
    int high = 127,
    double density = 0.8,
  }) =>
      <String, dynamic>{
        'role_id': id,
        'part_id': part,
        'kind': kind,
        'destination': <String, dynamic>{
          'new_row': <String, dynamic>{
            'name': part == 'drums' ? 'House Drums' : 'Generated $part',
            'instrument_id': instrument,
          },
        },
        'instrument_id': instrument,
        'register_low': low,
        'register_high': high,
        'density': density,
        'velocity': 0.8,
      };

  Map<String, dynamic> spec({
    List<Map<String, dynamic>>? roles,
    List<Map<String, dynamic>>? harmony,
    int seed = 7,
  }) =>
      <String, dynamic>{
        'schema_version': aiV3MusicSpecSchemaVersion,
        'spec_id': 'spec_1',
        'project_digest': 'digest_1',
        'start_beat': 0,
        'length_bars': 4,
        'beats_per_bar': 4,
        'tempo_bpm': 120,
        'key_root_pitch_class': 0,
        'scale': 'minor',
        'style_tags': <String>['house'],
        'mood_tags': <String>['driving'],
        'groove': <String, dynamic>{
          'pulse': 'four_on_floor',
          'subdivision': 'eighth',
          'swing': 0,
        },
        'roles': roles ??
            <Map<String, dynamic>>[
              role(id: 'kick', kind: 'kick'),
              role(id: 'clap', kind: 'clap'),
              role(id: 'hat', kind: 'closed_hat'),
            ],
        'harmony': harmony ?? <Map<String, dynamic>>[],
        'source_clip_ids': <String>[],
        'relationship': 'none',
        'seed': seed,
      };

  test('tool schema is compact intent and contains no raw note arrays', () {
    final tool = aiV3SubmitMusicSpecTool();
    final encoded = jsonEncode(tool);

    expect(tool['name'], 'submit_music_spec_v3');
    expect(encoded, isNot(contains('"notes"')));
    expect(encoded, isNot(contains('midi.create_clip')));
    expect(encoded, contains('"roles"'));
    expect(encoded, contains('"harmony"'));
  });

  test('strict parser rejects unknown fields and invalid destinations', () {
    final unknown = spec()..['unexpected'] = true;
    expect(
      () => MusicSpecV3.fromJson(unknown),
      throwsA(
        isA<AiV3MusicGenerationException>().having(
          (error) => error.code,
          'code',
          'music_spec_fields_invalid',
        ),
      ),
    );

    final invalid = spec();
    (invalid['roles'] as List).first['destination'] = <String, dynamic>{
      'row_id': 1,
      'new_row': <String, dynamic>{
        'name': 'Drums',
        'instrument_id': 'drums',
      },
    };
    expect(
      () => MusicSpecV3.fromJson(invalid),
      throwsA(isA<AiV3MusicGenerationException>()),
    );
  });

  test('house brief expands to exact requested four-bar grid', () {
    final parsed = MusicSpecV3.fromJson(spec());
    final bundle = const DeterministicMusicProviderV3().realize(parsed);

    expect(bundle.parts, hasLength(1));
    expect(bundle.noteCount, 56);
    final notes = bundle.parts.single.notes;
    final kicks = notes.where((note) => note['pitch'] == 36).toList();
    final claps = notes.where((note) => note['pitch'] == 39).toList();
    final hats = notes.where((note) => note['pitch'] == 42).toList();
    expect(
      kicks.map((note) => note['start_beat']),
      List<double>.generate(16, (index) => index.toDouble()),
    );
    expect(
      claps.map((note) => note['start_beat']),
      <double>[1, 3, 5, 7, 9, 11, 13, 15],
    );
    expect(
      hats.map((note) => note['start_beat']),
      List<double>.generate(32, (index) => index * 0.5),
    );
  });

  test('same spec and seed realize byte-for-byte deterministically', () {
    final parsed = MusicSpecV3.fromJson(spec(seed: 91));
    const provider = DeterministicMusicProviderV3();

    expect(
      jsonEncode(provider.realize(parsed).toJson()),
      jsonEncode(provider.realize(parsed).toJson()),
    );
  });

  test('harmony drives bass roots while staying inside register', () {
    final bassRole = role(
      id: 'bass',
      kind: 'bass',
      part: 'bass',
      instrument: 'mixroom.bass_mono',
      low: 36,
      high: 52,
      density: 0.4,
    );
    final parsed = MusicSpecV3.fromJson(spec(
      roles: <Map<String, dynamic>>[bassRole],
      harmony: <Map<String, dynamic>>[
        <String, dynamic>{
          'start_bar': 0,
          'length_bars': 1,
          'root_pitch_class': 0,
          'quality': 'minor',
        },
        <String, dynamic>{
          'start_bar': 1,
          'length_bars': 1,
          'root_pitch_class': 8,
          'quality': 'major',
        },
        <String, dynamic>{
          'start_bar': 2,
          'length_bars': 1,
          'root_pitch_class': 3,
          'quality': 'major',
        },
        <String, dynamic>{
          'start_bar': 3,
          'length_bars': 1,
          'root_pitch_class': 10,
          'quality': 'major',
        },
      ],
    ));

    final notes =
        const DeterministicMusicProviderV3().realize(parsed).parts.single.notes;
    expect(notes, isNotEmpty);
    expect(
      notes.every((note) {
        final pitch = note['pitch'] as int;
        return pitch >= 36 && pitch <= 52;
      }),
      isTrue,
    );
    expect(
      notes.where((note) => (note['start_beat'] as num) == 0).single['pitch'],
      36,
    );
    expect(
      notes.where((note) => (note['start_beat'] as num) == 4).single['pitch'] %
          12,
      8,
    );
  });

  test('generated bundle converts to existing strict MIDI plan', () {
    final parsed = MusicSpecV3.fromJson(spec());
    final bundle = const DeterministicMusicProviderV3().realize(parsed);
    final plan = bundle.toPlan(userMessage: 'Preview the generated pattern.');

    expect(plan.commands, hasLength(1));
    expect(plan.commands.single.type, 'midi.create_clip');
    expect(plan.commands.single.arguments['notes'], hasLength(56));
    expect(
      plan.commands.single.arguments['destination'],
      <String, dynamic>{
        'new_row': <String, dynamic>{
          'name': 'House Drums',
          'instrument_id': 'sfz.vsco.mixroom_acoustic_drum_kit',
        },
      },
    );
  });
}
