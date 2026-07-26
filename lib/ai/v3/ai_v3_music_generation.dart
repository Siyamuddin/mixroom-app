import 'dart:math' as math;

import 'ai_v3_contract.dart';

const String aiV3MusicSpecSchemaVersion = 'music_spec_v3_experiment_1';
const String aiV3GeneratedMusicSchemaVersion =
    'generated_music_bundle_v3_experiment_1';
const int aiV3MaxMusicRoles = 8;
const int aiV3MaxMusicHarmonyEvents = 16;

const String aiV3MusicPlannerInstructions = '''
You are Mixroom's sole musical planner for a provider-neutral generation
experiment. Preserve the complete original request and all explicit constraints.
Describe musical intent as one compact MusicSpecV3; do not serialize MIDI notes.
Use only stable project IDs and instrument IDs supplied in context. General
musical knowledge may determine harmony, roles, register, density, and groove,
but project resources and existing state must never be invented. Use retrieved
source material when the request depends on existing music. Never claim that
the proposed music was applied.
''';

class AiV3MusicGenerationException implements Exception {
  const AiV3MusicGenerationException(this.code);

  final String code;

  @override
  String toString() => 'AiV3MusicGenerationException($code)';
}

class MusicDestinationV3 {
  const MusicDestinationV3.existingRow(this.rowId)
      : newRowName = null,
        instrumentId = null;

  const MusicDestinationV3.newRow({
    required this.newRowName,
    required this.instrumentId,
  }) : rowId = null;

  final int? rowId;
  final String? newRowName;
  final String? instrumentId;

  bool get createsRow => rowId == null;

  factory MusicDestinationV3.fromJson(Map<String, dynamic> value) {
    if (value.keys.length == 1 && value['row_id'] is int) {
      return MusicDestinationV3.existingRow(value['row_id'] as int);
    }
    final newRow = value['new_row'];
    if (value.keys.length == 1 && newRow is Map) {
      final row = Map<String, dynamic>.from(newRow);
      if (row.keys.toSet().difference({'name', 'instrument_id'}).isNotEmpty ||
          row.length != 2) {
        throw const AiV3MusicGenerationException(
          'music_spec_destination_invalid',
        );
      }
      final name = row['name'];
      final instrumentId = row['instrument_id'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.trim().length > 80 ||
          instrumentId is! String ||
          instrumentId.trim().isEmpty) {
        throw const AiV3MusicGenerationException(
          'music_spec_destination_invalid',
        );
      }
      return MusicDestinationV3.newRow(
        newRowName: name.trim(),
        instrumentId: instrumentId.trim(),
      );
    }
    throw const AiV3MusicGenerationException(
      'music_spec_destination_invalid',
    );
  }

  Map<String, dynamic> toJson() => rowId != null
      ? <String, dynamic>{'row_id': rowId}
      : <String, dynamic>{
          'new_row': <String, dynamic>{
            'name': newRowName,
            'instrument_id': instrumentId,
          },
        };
}

class MusicRoleV3 {
  const MusicRoleV3({
    required this.roleId,
    required this.partId,
    required this.kind,
    required this.destination,
    required this.instrumentId,
    required this.registerLow,
    required this.registerHigh,
    required this.density,
    required this.velocity,
  });

  final String roleId;
  final String partId;
  final String kind;
  final MusicDestinationV3 destination;
  final String instrumentId;
  final int registerLow;
  final int registerHigh;
  final double density;
  final double velocity;

  factory MusicRoleV3.fromJson(Map<String, dynamic> value) {
    _requireExactKeys(
      value,
      const {
        'role_id',
        'part_id',
        'kind',
        'destination',
        'instrument_id',
        'register_low',
        'register_high',
        'density',
        'velocity',
      },
      'music_spec_role_invalid',
    );
    final roleId = _boundedText(value['role_id'], 80);
    final partId = _boundedText(value['part_id'], 80);
    final kind = value['kind'];
    const kinds = {
      'kick',
      'snare',
      'clap',
      'closed_hat',
      'open_hat',
      'bass',
      'chords',
      'melody',
    };
    final instrumentId = _boundedText(value['instrument_id'], 160);
    final low = value['register_low'];
    final high = value['register_high'];
    final density = value['density'];
    final velocity = value['velocity'];
    if (kind is! String ||
        !kinds.contains(kind) ||
        low is! int ||
        high is! int ||
        low < 0 ||
        high > 127 ||
        low > high ||
        density is! num ||
        !density.isFinite ||
        density < 0 ||
        density > 1 ||
        velocity is! num ||
        !velocity.isFinite ||
        velocity <= 0 ||
        velocity > 1 ||
        value['destination'] is! Map) {
      throw const AiV3MusicGenerationException('music_spec_role_invalid');
    }
    return MusicRoleV3(
      roleId: roleId,
      partId: partId,
      kind: kind,
      destination: MusicDestinationV3.fromJson(
        Map<String, dynamic>.from(value['destination'] as Map),
      ),
      instrumentId: instrumentId,
      registerLow: low,
      registerHigh: high,
      density: density.toDouble(),
      velocity: velocity.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role_id': roleId,
        'part_id': partId,
        'kind': kind,
        'destination': destination.toJson(),
        'instrument_id': instrumentId,
        'register_low': registerLow,
        'register_high': registerHigh,
        'density': density,
        'velocity': velocity,
      };
}

class MusicHarmonyEventV3 {
  const MusicHarmonyEventV3({
    required this.startBar,
    required this.lengthBars,
    required this.rootPitchClass,
    required this.quality,
  });

  final int startBar;
  final int lengthBars;
  final int rootPitchClass;
  final String quality;

  factory MusicHarmonyEventV3.fromJson(Map<String, dynamic> value) {
    _requireExactKeys(
      value,
      const {'start_bar', 'length_bars', 'root_pitch_class', 'quality'},
      'music_spec_harmony_invalid',
    );
    final start = value['start_bar'];
    final length = value['length_bars'];
    final root = value['root_pitch_class'];
    final quality = value['quality'];
    if (start is! int ||
        start < 0 ||
        length is! int ||
        length < 1 ||
        root is! int ||
        root < 0 ||
        root > 11 ||
        quality is! String ||
        !const {'major', 'minor', 'diminished', 'sus2', 'sus4'}
            .contains(quality)) {
      throw const AiV3MusicGenerationException(
        'music_spec_harmony_invalid',
      );
    }
    return MusicHarmonyEventV3(
      startBar: start,
      lengthBars: length,
      rootPitchClass: root,
      quality: quality,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start_bar': startBar,
        'length_bars': lengthBars,
        'root_pitch_class': rootPitchClass,
        'quality': quality,
      };
}

class MusicSpecV3 {
  const MusicSpecV3({
    required this.specId,
    required this.projectDigest,
    required this.startBeat,
    required this.lengthBars,
    required this.beatsPerBar,
    required this.tempoBpm,
    required this.keyRootPitchClass,
    required this.scale,
    required this.styleTags,
    required this.moodTags,
    required this.pulse,
    required this.subdivision,
    required this.swing,
    required this.roles,
    required this.harmony,
    required this.sourceClipIds,
    required this.relationship,
    required this.seed,
  });

  final String specId;
  final String projectDigest;
  final double startBeat;
  final int lengthBars;
  final int beatsPerBar;
  final double tempoBpm;
  final int? keyRootPitchClass;
  final String? scale;
  final List<String> styleTags;
  final List<String> moodTags;
  final String pulse;
  final String subdivision;
  final double swing;
  final List<MusicRoleV3> roles;
  final List<MusicHarmonyEventV3> harmony;
  final List<String> sourceClipIds;
  final String relationship;
  final int seed;

  factory MusicSpecV3.fromJson(Map<String, dynamic> value) {
    _requireExactKeys(
      value,
      const {
        'schema_version',
        'spec_id',
        'project_digest',
        'start_beat',
        'length_bars',
        'beats_per_bar',
        'tempo_bpm',
        'key_root_pitch_class',
        'scale',
        'style_tags',
        'mood_tags',
        'groove',
        'roles',
        'harmony',
        'source_clip_ids',
        'relationship',
        'seed',
      },
      'music_spec_fields_invalid',
    );
    if (value['schema_version'] != aiV3MusicSpecSchemaVersion) {
      throw const AiV3MusicGenerationException(
        'music_spec_version_invalid',
      );
    }
    final startBeat = value['start_beat'];
    final lengthBars = value['length_bars'];
    final beatsPerBar = value['beats_per_bar'];
    final tempo = value['tempo_bpm'];
    final key = value['key_root_pitch_class'];
    final scale = value['scale'];
    final groove = value['groove'];
    final roles = value['roles'];
    final harmony = value['harmony'];
    final sourceIds = value['source_clip_ids'];
    final relationship = value['relationship'];
    final seed = value['seed'];
    if (startBeat is! num ||
        !startBeat.isFinite ||
        startBeat < 0 ||
        lengthBars is! int ||
        lengthBars < 1 ||
        lengthBars > 8 ||
        beatsPerBar is! int ||
        beatsPerBar < 2 ||
        beatsPerBar > 12 ||
        tempo is! num ||
        !tempo.isFinite ||
        tempo < 20 ||
        tempo > 300 ||
        (key != null && (key is! int || key < 0 || key > 11)) ||
        (scale != null &&
            (scale is! String ||
                !const {
                  'major',
                  'minor',
                  'dorian',
                  'phrygian',
                  'mixolydian',
                  'minor_pentatonic',
                }.contains(scale))) ||
        groove is! Map ||
        roles is! List ||
        roles.isEmpty ||
        roles.length > aiV3MaxMusicRoles ||
        harmony is! List ||
        harmony.length > aiV3MaxMusicHarmonyEvents ||
        sourceIds is! List ||
        sourceIds.length > 16 ||
        relationship is! String ||
        !const {'none', 'complement', 'continue', 'vary'}
            .contains(relationship) ||
        seed is! int) {
      throw const AiV3MusicGenerationException('music_spec_invalid');
    }
    final grooveMap = Map<String, dynamic>.from(groove);
    _requireExactKeys(
      grooveMap,
      const {'pulse', 'subdivision', 'swing'},
      'music_spec_groove_invalid',
    );
    final pulse = grooveMap['pulse'];
    final subdivision = grooveMap['subdivision'];
    final swing = grooveMap['swing'];
    if (pulse is! String ||
        !const {'four_on_floor', 'half_time', 'straight', 'syncopated'}
            .contains(pulse) ||
        subdivision is! String ||
        !const {'quarter', 'eighth', 'sixteenth'}.contains(subdivision) ||
        swing is! num ||
        !swing.isFinite ||
        swing < 0 ||
        swing > 0.5) {
      throw const AiV3MusicGenerationException(
        'music_spec_groove_invalid',
      );
    }
    final parsedRoles = roles.map((item) {
      if (item is! Map) {
        throw const AiV3MusicGenerationException(
          'music_spec_role_invalid',
        );
      }
      return MusicRoleV3.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
    if (parsedRoles.map((role) => role.roleId).toSet().length !=
        parsedRoles.length) {
      throw const AiV3MusicGenerationException(
        'music_spec_role_id_duplicate',
      );
    }
    final parsedHarmony = harmony.map((item) {
      if (item is! Map) {
        throw const AiV3MusicGenerationException(
          'music_spec_harmony_invalid',
        );
      }
      return MusicHarmonyEventV3.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList(growable: false)
      ..sort((a, b) => a.startBar.compareTo(b.startBar));
    for (final event in parsedHarmony) {
      if (event.startBar + event.lengthBars > lengthBars) {
        throw const AiV3MusicGenerationException(
          'music_spec_harmony_bounds',
        );
      }
    }
    return MusicSpecV3(
      specId: _boundedText(value['spec_id'], 80),
      projectDigest: _boundedText(value['project_digest'], 160),
      startBeat: startBeat.toDouble(),
      lengthBars: lengthBars,
      beatsPerBar: beatsPerBar,
      tempoBpm: tempo.toDouble(),
      keyRootPitchClass: key as int?,
      scale: scale as String?,
      styleTags: _textList(value['style_tags'], maxItems: 8),
      moodTags: _textList(value['mood_tags'], maxItems: 8),
      pulse: pulse,
      subdivision: subdivision,
      swing: swing.toDouble(),
      roles: List<MusicRoleV3>.unmodifiable(parsedRoles),
      harmony: List<MusicHarmonyEventV3>.unmodifiable(parsedHarmony),
      sourceClipIds: _textList(sourceIds, maxItems: 16),
      relationship: relationship,
      seed: seed,
    );
  }

  double get lengthBeats => lengthBars * beatsPerBar.toDouble();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': aiV3MusicSpecSchemaVersion,
        'spec_id': specId,
        'project_digest': projectDigest,
        'start_beat': startBeat,
        'length_bars': lengthBars,
        'beats_per_bar': beatsPerBar,
        'tempo_bpm': tempoBpm,
        'key_root_pitch_class': keyRootPitchClass,
        'scale': scale,
        'style_tags': styleTags,
        'mood_tags': moodTags,
        'groove': <String, dynamic>{
          'pulse': pulse,
          'subdivision': subdivision,
          'swing': swing,
        },
        'roles': roles.map((role) => role.toJson()).toList(growable: false),
        'harmony':
            harmony.map((event) => event.toJson()).toList(growable: false),
        'source_clip_ids': sourceClipIds,
        'relationship': relationship,
        'seed': seed,
      };
}

class GeneratedMusicPartV3 {
  const GeneratedMusicPartV3({
    required this.partId,
    required this.destination,
    required this.instrumentId,
    required this.notes,
  });

  final String partId;
  final MusicDestinationV3 destination;
  final String instrumentId;
  final List<Map<String, dynamic>> notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'part_id': partId,
        'destination': destination.toJson(),
        'instrument_id': instrumentId,
        'notes': notes,
      };
}

class GeneratedMusicBundleV3 {
  const GeneratedMusicBundleV3({
    required this.specId,
    required this.projectDigest,
    required this.providerId,
    required this.providerVersion,
    required this.seed,
    required this.startBeat,
    required this.lengthBeats,
    required this.parts,
    required this.warnings,
  });

  final String specId;
  final String projectDigest;
  final String providerId;
  final String providerVersion;
  final int seed;
  final double startBeat;
  final double lengthBeats;
  final List<GeneratedMusicPartV3> parts;
  final List<String> warnings;

  int get noteCount =>
      parts.fold(0, (count, part) => count + part.notes.length);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': aiV3GeneratedMusicSchemaVersion,
        'spec_id': specId,
        'project_digest': projectDigest,
        'provider_id': providerId,
        'provider_version': providerVersion,
        'seed': seed,
        'start_beat': startBeat,
        'length_beats': lengthBeats,
        'parts': parts.map((part) => part.toJson()).toList(growable: false),
        'warnings': warnings,
      };

  AiV3Plan toPlan({required String userMessage}) {
    final commands = <Map<String, dynamic>>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      commands.add(<String, dynamic>{
        'command_id': 'music_${index + 1}',
        'type': 'midi.create_clip',
        'arguments': <String, dynamic>{
          'destination': part.destination.toJson(),
          'start_beat': startBeat,
          'length_beats': lengthBeats,
          'notes': part.notes,
        },
      });
    }
    return AiV3Plan.fromJson(<String, dynamic>{
      'schema_version': aiV3PlanVersion,
      'outcome': 'plan',
      'user_message': userMessage,
      'commands': commands,
      'question_options': <String>[],
    });
  }
}

abstract interface class MusicRealizationProviderV3 {
  String get providerId;
  String get providerVersion;

  GeneratedMusicBundleV3 realize(MusicSpecV3 spec);
}

/// First comparison candidate: a compact musical brief expanded by a small,
/// deterministic provider. It deliberately owns note realization; GPT does not.
class DeterministicMusicProviderV3 implements MusicRealizationProviderV3 {
  const DeterministicMusicProviderV3();

  @override
  String get providerId => 'mixroom.deterministic_brief';

  @override
  String get providerVersion => '1';

  @override
  GeneratedMusicBundleV3 realize(MusicSpecV3 spec) {
    final grouped = <String, List<MusicRoleV3>>{};
    for (final role in spec.roles) {
      grouped.putIfAbsent(role.partId, () => <MusicRoleV3>[]).add(role);
    }
    final parts = <GeneratedMusicPartV3>[];
    for (final entry in grouped.entries) {
      final roles = entry.value;
      final first = roles.first;
      if (roles.any((role) =>
          role.destination.toJson().toString() !=
              first.destination.toJson().toString() ||
          role.instrumentId != first.instrumentId)) {
        throw const AiV3MusicGenerationException(
          'music_provider_part_binding_conflict',
        );
      }
      final notes = <Map<String, dynamic>>[];
      for (final role in roles) {
        notes.addAll(_realizeRole(spec, role));
      }
      notes.sort((a, b) {
        final start =
            (a['start_beat'] as num).compareTo(b['start_beat'] as num);
        return start != 0
            ? start
            : (a['pitch'] as int).compareTo(b['pitch'] as int);
      });
      if (notes.isEmpty || notes.length > aiV3MaxGeneratedMidiNotes) {
        throw const AiV3MusicGenerationException(
          'music_provider_note_budget_exceeded',
        );
      }
      parts.add(GeneratedMusicPartV3(
        partId: entry.key,
        destination: first.destination,
        instrumentId: first.instrumentId,
        notes: List<Map<String, dynamic>>.unmodifiable(notes),
      ));
    }
    if (parts.length > aiV3MaxCommands) {
      throw const AiV3MusicGenerationException(
        'music_provider_part_budget_exceeded',
      );
    }
    return GeneratedMusicBundleV3(
      specId: spec.specId,
      projectDigest: spec.projectDigest,
      providerId: providerId,
      providerVersion: providerVersion,
      seed: spec.seed,
      startBeat: spec.startBeat,
      lengthBeats: spec.lengthBeats,
      parts: List<GeneratedMusicPartV3>.unmodifiable(parts),
      warnings: const <String>[],
    );
  }

  List<Map<String, dynamic>> _realizeRole(
    MusicSpecV3 spec,
    MusicRoleV3 role,
  ) {
    return switch (role.kind) {
      'kick' => _drumGrid(spec, role, 36, _kickOffsets(spec)),
      'snare' => _drumGrid(spec, role, 38, _backbeatOffsets(spec)),
      'clap' => _drumGrid(spec, role, 39, _backbeatOffsets(spec)),
      'closed_hat' => _drumGrid(spec, role, 42, _hatOffsets(spec, role)),
      'open_hat' => _drumGrid(
          spec,
          role,
          46,
          List<double>.generate(
            spec.lengthBars,
            (bar) => bar * spec.beatsPerBar + 1.5,
          ),
        ),
      'bass' => _tonalGrid(spec, role, bass: true),
      'chords' => _chordGrid(spec, role),
      'melody' => _tonalGrid(spec, role, bass: false),
      _ => throw const AiV3MusicGenerationException(
          'music_provider_role_unsupported',
        ),
    };
  }

  List<double> _kickOffsets(MusicSpecV3 spec) {
    final step = spec.pulse == 'four_on_floor' ? 1.0 : 2.0;
    return _grid(spec.lengthBeats, step);
  }

  List<double> _backbeatOffsets(MusicSpecV3 spec) => <double>[
        for (var bar = 0; bar < spec.lengthBars; bar++)
          for (final offset in const <double>[1, 3])
            if (offset < spec.beatsPerBar) bar * spec.beatsPerBar + offset,
      ];

  List<double> _hatOffsets(MusicSpecV3 spec, MusicRoleV3 role) {
    final requestedStep = switch (spec.subdivision) {
      'sixteenth' => 0.25,
      'eighth' => 0.5,
      _ => 1.0,
    };
    final densityStep = role.density >= 0.7
        ? requestedStep
        : role.density >= 0.35
            ? math.max(requestedStep, 0.5)
            : math.max(requestedStep, 1.0);
    return _grid(spec.lengthBeats, densityStep);
  }

  List<Map<String, dynamic>> _drumGrid(
    MusicSpecV3 spec,
    MusicRoleV3 role,
    int pitch,
    List<double> offsets,
  ) =>
      offsets
          .map((start) => _note(
                pitch: pitch,
                start: _swung(start, spec),
                length: math.min(0.25, spec.lengthBeats - start),
                velocity: role.velocity,
              ))
          .toList(growable: false);

  List<Map<String, dynamic>> _tonalGrid(
    MusicSpecV3 spec,
    MusicRoleV3 role, {
    required bool bass,
  }) {
    final step = bass
        ? (role.density >= 0.65 ? 1.0 : 2.0)
        : (role.density >= 0.65 ? 0.5 : 1.0);
    final offsets = _grid(spec.lengthBeats, step);
    final random = math.Random(spec.seed ^ _stableTextHash(role.roleId));
    final notes = <Map<String, dynamic>>[];
    for (var index = 0; index < offsets.length; index++) {
      final start = offsets[index];
      final harmony = _harmonyAt(spec, start);
      final root = harmony?.rootPitchClass ?? spec.keyRootPitchClass ?? 0;
      final chord = _chordIntervals(harmony?.quality ?? 'minor');
      final interval = bass
          ? chord[index % math.min(2, chord.length)]
          : chord[random.nextInt(chord.length)];
      final pitch = _pitchInRegister(
        root + interval,
        role.registerLow,
        role.registerHigh,
        preferLow: bass,
      );
      notes.add(_note(
        pitch: pitch,
        start: _swung(start, spec),
        length: math.min(step * 0.8, spec.lengthBeats - start),
        velocity: role.velocity,
      ));
    }
    return notes;
  }

  List<Map<String, dynamic>> _chordGrid(
    MusicSpecV3 spec,
    MusicRoleV3 role,
  ) {
    final harmony = spec.harmony.isEmpty
        ? <MusicHarmonyEventV3>[
            MusicHarmonyEventV3(
              startBar: 0,
              lengthBars: spec.lengthBars,
              rootPitchClass: spec.keyRootPitchClass ?? 0,
              quality: spec.scale == 'major' ? 'major' : 'minor',
            ),
          ]
        : spec.harmony;
    final notes = <Map<String, dynamic>>[];
    for (final event in harmony) {
      final start = event.startBar * spec.beatsPerBar.toDouble();
      final length = event.lengthBars * spec.beatsPerBar.toDouble();
      for (final interval in _chordIntervals(event.quality)) {
        notes.add(_note(
          pitch: _pitchInRegister(
            event.rootPitchClass + interval,
            role.registerLow,
            role.registerHigh,
          ),
          start: start,
          length: length,
          velocity: role.velocity,
        ));
      }
    }
    return notes;
  }

  MusicHarmonyEventV3? _harmonyAt(MusicSpecV3 spec, double beat) {
    final bar = (beat / spec.beatsPerBar).floor();
    for (final event in spec.harmony) {
      if (bar >= event.startBar && bar < event.startBar + event.lengthBars) {
        return event;
      }
    }
    return null;
  }

  static List<int> _chordIntervals(String quality) => switch (quality) {
        'major' => const <int>[0, 4, 7],
        'diminished' => const <int>[0, 3, 6],
        'sus2' => const <int>[0, 2, 7],
        'sus4' => const <int>[0, 5, 7],
        _ => const <int>[0, 3, 7],
      };

  static int _pitchInRegister(
    int pitchClass,
    int low,
    int high, {
    bool preferLow = false,
  }) {
    var pitch = pitchClass % 12;
    while (pitch < low) {
      pitch += 12;
    }
    if (!preferLow) {
      final middle = ((low + high) / 2).round();
      while (pitch + 12 <= high && pitch < middle) {
        pitch += 12;
      }
    }
    while (pitch > high) {
      pitch -= 12;
    }
    if (pitch < low || pitch > high) {
      throw const AiV3MusicGenerationException(
        'music_provider_register_invalid',
      );
    }
    return pitch;
  }

  static List<double> _grid(double length, double step) => <double>[
        for (var value = 0.0; value < length - 0.000001; value += step) value,
      ];

  static double _swung(double start, MusicSpecV3 spec) {
    if (spec.swing == 0) return start;
    final eighthIndex = (start / 0.5).round();
    if ((eighthIndex * 0.5 - start).abs() > 0.000001 || eighthIndex.isEven) {
      return start;
    }
    return math.min(start + spec.swing * 0.5, spec.lengthBeats - 0.001);
  }

  static Map<String, dynamic> _note({
    required int pitch,
    required double start,
    required double length,
    required double velocity,
  }) =>
      <String, dynamic>{
        'pitch': pitch,
        'start_beat': start,
        'length_beats': length,
        'velocity': velocity,
      };

  static int _stableTextHash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}

Map<String, dynamic> aiV3SubmitMusicSpecTool() => <String, dynamic>{
      'type': 'function',
      'name': 'submit_music_spec_v3',
      'strict': true,
      'description':
          'Return one compact provider-neutral music-generation specification.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'schema_version': <String, dynamic>{
            'type': 'string',
            'enum': <String>[aiV3MusicSpecSchemaVersion],
          },
          'spec_id': _stringSchema(maxLength: 80),
          'project_digest': _stringSchema(maxLength: 160),
          'start_beat': <String, dynamic>{'type': 'number', 'minimum': 0},
          'length_bars': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
          },
          'beats_per_bar': <String, dynamic>{
            'type': 'integer',
            'minimum': 2,
            'maximum': 12,
          },
          'tempo_bpm': <String, dynamic>{
            'type': 'number',
            'minimum': 20,
            'maximum': 300,
          },
          'key_root_pitch_class': <String, dynamic>{
            'anyOf': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'integer',
                'minimum': 0,
                'maximum': 11,
              },
              <String, dynamic>{'type': 'null'},
            ],
          },
          'scale': <String, dynamic>{
            'anyOf': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  'major',
                  'minor',
                  'dorian',
                  'phrygian',
                  'mixolydian',
                  'minor_pentatonic',
                ],
              },
              <String, dynamic>{'type': 'null'},
            ],
          },
          'style_tags': _tagsSchema(),
          'mood_tags': _tagsSchema(),
          'groove': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'pulse': <String, dynamic>{
                'type': 'string',
                'enum': <String>[
                  'four_on_floor',
                  'half_time',
                  'straight',
                  'syncopated',
                ],
              },
              'subdivision': <String, dynamic>{
                'type': 'string',
                'enum': <String>['quarter', 'eighth', 'sixteenth'],
              },
              'swing': <String, dynamic>{
                'type': 'number',
                'minimum': 0,
                'maximum': 0.5,
              },
            },
            'required': <String>['pulse', 'subdivision', 'swing'],
            'additionalProperties': false,
          },
          'roles': <String, dynamic>{
            'type': 'array',
            'minItems': 1,
            'maxItems': aiV3MaxMusicRoles,
            'items': _musicRoleSchema(),
          },
          'harmony': <String, dynamic>{
            'type': 'array',
            'maxItems': aiV3MaxMusicHarmonyEvents,
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'start_bar': <String, dynamic>{
                  'type': 'integer',
                  'minimum': 0,
                },
                'length_bars': <String, dynamic>{
                  'type': 'integer',
                  'minimum': 1,
                },
                'root_pitch_class': <String, dynamic>{
                  'type': 'integer',
                  'minimum': 0,
                  'maximum': 11,
                },
                'quality': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>[
                    'major',
                    'minor',
                    'diminished',
                    'sus2',
                    'sus4',
                  ],
                },
              },
              'required': <String>[
                'start_bar',
                'length_bars',
                'root_pitch_class',
                'quality',
              ],
              'additionalProperties': false,
            },
          },
          'source_clip_ids': <String, dynamic>{
            'type': 'array',
            'maxItems': 16,
            'items': _stringSchema(maxLength: 160),
          },
          'relationship': <String, dynamic>{
            'type': 'string',
            'enum': <String>['none', 'complement', 'continue', 'vary'],
          },
          'seed': <String, dynamic>{'type': 'integer'},
        },
        'required': <String>[
          'schema_version',
          'spec_id',
          'project_digest',
          'start_beat',
          'length_bars',
          'beats_per_bar',
          'tempo_bpm',
          'key_root_pitch_class',
          'scale',
          'style_tags',
          'mood_tags',
          'groove',
          'roles',
          'harmony',
          'source_clip_ids',
          'relationship',
          'seed',
        ],
        'additionalProperties': false,
      },
    };

Map<String, dynamic> _musicRoleSchema() {
  final destination = <String, dynamic>{
    'anyOf': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'row_id': <String, dynamic>{'type': 'integer', 'minimum': 0},
        },
        'required': <String>['row_id'],
        'additionalProperties': false,
      },
      <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'new_row': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'name': _stringSchema(maxLength: 80),
              'instrument_id': _stringSchema(maxLength: 160),
            },
            'required': <String>['name', 'instrument_id'],
            'additionalProperties': false,
          },
        },
        'required': <String>['new_row'],
        'additionalProperties': false,
      },
    ],
  };
  return <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'role_id': _stringSchema(maxLength: 80),
      'part_id': _stringSchema(maxLength: 80),
      'kind': <String, dynamic>{
        'type': 'string',
        'enum': <String>[
          'kick',
          'snare',
          'clap',
          'closed_hat',
          'open_hat',
          'bass',
          'chords',
          'melody',
        ],
      },
      'destination': destination,
      'instrument_id': _stringSchema(maxLength: 160),
      'register_low': <String, dynamic>{
        'type': 'integer',
        'minimum': 0,
        'maximum': 127,
      },
      'register_high': <String, dynamic>{
        'type': 'integer',
        'minimum': 0,
        'maximum': 127,
      },
      'density': <String, dynamic>{
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
      },
      'velocity': <String, dynamic>{
        'type': 'number',
        'exclusiveMinimum': 0,
        'maximum': 1,
      },
    },
    'required': <String>[
      'role_id',
      'part_id',
      'kind',
      'destination',
      'instrument_id',
      'register_low',
      'register_high',
      'density',
      'velocity',
    ],
    'additionalProperties': false,
  };
}

Map<String, dynamic> _stringSchema({required int maxLength}) =>
    <String, dynamic>{
      'type': 'string',
      'minLength': 1,
      'maxLength': maxLength,
    };

Map<String, dynamic> _tagsSchema() => <String, dynamic>{
      'type': 'array',
      'maxItems': 8,
      'items': _stringSchema(maxLength: 40),
    };

void _requireExactKeys(
  Map<String, dynamic> value,
  Set<String> expected,
  String code,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw AiV3MusicGenerationException(code);
  }
}

String _boundedText(Object? value, int maxLength) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw const AiV3MusicGenerationException('music_spec_text_invalid');
  }
  return value.trim();
}

List<String> _textList(Object? value, {required int maxItems}) {
  if (value is! List || value.length > maxItems) {
    throw const AiV3MusicGenerationException('music_spec_text_list_invalid');
  }
  final result =
      value.map((item) => _boundedText(item, 80)).toList(growable: false);
  if (result.toSet().length != result.length) {
    throw const AiV3MusicGenerationException(
      'music_spec_text_list_duplicate',
    );
  }
  return List<String>.unmodifiable(result);
}
