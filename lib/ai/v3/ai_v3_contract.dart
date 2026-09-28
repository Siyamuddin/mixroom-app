import 'dart:convert';

import 'ai_v3_resources.dart';

const String aiV3PlanVersion = 'plan_v3_prototype_2';
const String aiV3PlanCommandPolicy = 'commands_32_v1';
const String aiV3GeneratedMidiPolicy = 'notes_512_v1';
const String aiV3PlanOutputPolicy = 'serialized_plan_64000_bytes_v1';
const int aiV3MaxSerializedPlanBytes = 64000;
const int aiV3MaxRuntimeMidiStateBytes = 4000000;
const String aiV3PhoneMicCleanupPreset = 'phone_mic_cleanup_v1';
const List<String> aiV3PhoneMicCleanupEffectIds = <String>[
  'EQ Parametric',
  'De-Esser',
  'Dynamic Softener',
  'Compressor',
  'Limiter',
];

const Set<String> aiV3Outcomes = <String>{
  'plan',
  'respond',
  'clarify',
  'unsupported',
};

const Set<String> aiV3CommandTypes = <String>{
  'project.set_tempo',
  'transport.set_playing',
  'transport.restart',
  'transport.set_metronome_enabled',
  'transport.set_loop_enabled',
  'row.adjust_gain_db',
  'row.set_gain_db',
  'row.adjust_pan',
  'row.set_pan',
  'row.set_muted',
  'row.set_soloed',
  'row.rename',
  'row.set_instrument',
  'row.set_role_override',
  'row.apply_phone_mic_cleanup',
  'row.select',
  'row.set_color',
  'row.create',
  'row.delete',
  'group.create',
  'group.remove_row',
  'group.set_collapsed',
  'clip.move_by_beats',
  'clip.trim_to_range',
  'clip.split_at',
  'clip.duplicate_to',
  'clip.delete',
  'clip.glue',
  'clip.separate_stems',
  'clip.convert_to_midi',
  'clip.set_pitch_semitones',
  'clip.adjust_pitch_semitones',
  'clip.set_timeline_length_beats',
  'clip.scale_timeline_length',
  'clip.set_source_tempo_bpm',
  'clip.set_tempo_follow_mode',
  'clip.align_tempo_to_project',
  'project.set_tempo_from_clip',
  'clip.trim_silence',
  'clip.align_first_sound',
  'midi.transpose',
  'midi.create_clip',
  'midi.replace_notes',
  'midi.append_notes',
  'midi.chop_notes',
  'effect.ensure_configured',
  'effect.remove',
  'effect.set_bypassed',
  'automation.gain_fade',
  'automation.set_points',
  'automation.clear',
  'sample.place',
  'sample.replace',
  'mix.apply_goal',
};

enum AiV3ExecutionPolicy {
  autoApply('auto_apply'),
  confirm('confirm');

  const AiV3ExecutionPolicy(this.wireName);
  final String wireName;
}

const Map<String, AiV3ExecutionPolicy> aiV3ExecutionPolicyByCommandType =
    <String, AiV3ExecutionPolicy>{
      'project.set_tempo': AiV3ExecutionPolicy.autoApply,
      'transport.set_playing': AiV3ExecutionPolicy.autoApply,
      'transport.restart': AiV3ExecutionPolicy.autoApply,
      'transport.set_metronome_enabled': AiV3ExecutionPolicy.autoApply,
      'transport.set_loop_enabled': AiV3ExecutionPolicy.autoApply,
      'row.adjust_gain_db': AiV3ExecutionPolicy.autoApply,
      'row.set_gain_db': AiV3ExecutionPolicy.autoApply,
      'row.adjust_pan': AiV3ExecutionPolicy.autoApply,
      'row.set_pan': AiV3ExecutionPolicy.autoApply,
      'row.set_muted': AiV3ExecutionPolicy.autoApply,
      'row.set_soloed': AiV3ExecutionPolicy.autoApply,
      'row.rename': AiV3ExecutionPolicy.autoApply,
      'row.set_instrument': AiV3ExecutionPolicy.autoApply,
      'row.set_role_override': AiV3ExecutionPolicy.autoApply,
      'row.apply_phone_mic_cleanup': AiV3ExecutionPolicy.autoApply,
      'row.select': AiV3ExecutionPolicy.autoApply,
      'row.set_color': AiV3ExecutionPolicy.autoApply,
      'row.create': AiV3ExecutionPolicy.autoApply,
      'row.delete': AiV3ExecutionPolicy.autoApply,
      'group.create': AiV3ExecutionPolicy.autoApply,
      'group.remove_row': AiV3ExecutionPolicy.autoApply,
      'group.set_collapsed': AiV3ExecutionPolicy.autoApply,
      'clip.move_by_beats': AiV3ExecutionPolicy.autoApply,
      'clip.trim_to_range': AiV3ExecutionPolicy.autoApply,
      'clip.split_at': AiV3ExecutionPolicy.autoApply,
      'clip.duplicate_to': AiV3ExecutionPolicy.autoApply,
      'clip.delete': AiV3ExecutionPolicy.autoApply,
      'clip.glue': AiV3ExecutionPolicy.autoApply,
      'clip.separate_stems': AiV3ExecutionPolicy.autoApply,
      'clip.convert_to_midi': AiV3ExecutionPolicy.autoApply,
      'clip.set_pitch_semitones': AiV3ExecutionPolicy.autoApply,
      'clip.adjust_pitch_semitones': AiV3ExecutionPolicy.autoApply,
      'clip.set_timeline_length_beats': AiV3ExecutionPolicy.autoApply,
      'clip.scale_timeline_length': AiV3ExecutionPolicy.autoApply,
      'clip.set_source_tempo_bpm': AiV3ExecutionPolicy.autoApply,
      'clip.set_tempo_follow_mode': AiV3ExecutionPolicy.autoApply,
      'clip.align_tempo_to_project': AiV3ExecutionPolicy.autoApply,
      'project.set_tempo_from_clip': AiV3ExecutionPolicy.autoApply,
      'clip.trim_silence': AiV3ExecutionPolicy.autoApply,
      'clip.align_first_sound': AiV3ExecutionPolicy.autoApply,
      'midi.transpose': AiV3ExecutionPolicy.autoApply,
      'midi.create_clip': AiV3ExecutionPolicy.autoApply,
      'midi.replace_notes': AiV3ExecutionPolicy.autoApply,
      'midi.append_notes': AiV3ExecutionPolicy.autoApply,
      'midi.chop_notes': AiV3ExecutionPolicy.autoApply,
      'effect.ensure_configured': AiV3ExecutionPolicy.autoApply,
      'effect.remove': AiV3ExecutionPolicy.autoApply,
      'effect.set_bypassed': AiV3ExecutionPolicy.autoApply,
      'automation.gain_fade': AiV3ExecutionPolicy.autoApply,
      'automation.set_points': AiV3ExecutionPolicy.autoApply,
      'automation.clear': AiV3ExecutionPolicy.autoApply,
      'sample.place': AiV3ExecutionPolicy.autoApply,
      'sample.replace': AiV3ExecutionPolicy.autoApply,
      'mix.apply_goal': AiV3ExecutionPolicy.autoApply,
    };

AiV3ExecutionPolicy aiV3ExecutionPolicyForCommandTypes(
  Iterable<String> commandTypes, {
  Map<String, AiV3ExecutionPolicy> policies = aiV3ExecutionPolicyByCommandType,
}) {
  var result = AiV3ExecutionPolicy.autoApply;
  for (final type in commandTypes) {
    final policy = policies[type];
    if (policy == null) {
      throw const AiV3ContractException('v3_execution_policy_missing');
    }
    if (policy == AiV3ExecutionPolicy.confirm) {
      result = AiV3ExecutionPolicy.confirm;
    }
  }
  return result;
}

const Set<String> aiV3CommonCommandTypes = <String>{
  'project.set_tempo',
  'transport.set_playing',
  'transport.restart',
  'transport.set_metronome_enabled',
  'transport.set_loop_enabled',
  'row.adjust_gain_db',
  'row.set_gain_db',
  'row.adjust_pan',
  'row.set_pan',
  'row.set_muted',
  'row.set_soloed',
  'row.rename',
  'clip.move_by_beats',
  'clip.trim_to_range',
  'clip.split_at',
  'clip.duplicate_to',
  'clip.delete',
};

const Set<String> aiV3MixIntentKinds = <String>{
  'gain',
  'pan',
  'eq',
  'reverb',
  'delay',
  'distortion',
  'deesser',
  'compressor',
  'limiter',
  'clipper',
  'balance',
};

const Set<String> aiV3MixDirections = <String>{
  'up',
  'down',
  'left',
  'right',
  'center',
  'widen',
  'narrow',
  'remove',
};

const Set<String> aiV3MixDescriptors = <String>{
  'mud_cut',
  'box_cut',
  'boom_cut',
  'harsh_cut',
  'presence_boost',
  'air_boost',
  'warmth_boost',
  'thin_fix',
  'dull_fix',
  'low_cut',
  'high_cut',
};

class AiV3ContractException implements Exception {
  const AiV3ContractException(this.code);
  final String code;

  @override
  String toString() => 'AiV3ContractException($code)';
}

class AiV3Command {
  const AiV3Command({
    required this.commandId,
    required this.type,
    required this.arguments,
  });

  final String commandId;
  final String type;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'command_id': commandId,
    'type': type,
    'arguments': arguments,
  };
}

class AiV3Plan {
  const AiV3Plan({
    required this.outcome,
    required this.userMessage,
    required this.commands,
    this.questionOptions = const <String>[],
  });

  final String outcome;
  final String userMessage;
  final List<AiV3Command> commands;
  final List<String> questionOptions;

  bool get isMutating => outcome == 'plan' && commands.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': aiV3PlanVersion,
    'outcome': outcome,
    'user_message': userMessage,
    'commands': commands.map((value) => value.toJson()).toList(),
    'question_options': questionOptions,
  };

  factory AiV3Plan.fromJson(
    Map<String, dynamic> raw, {
    bool allowResourceRefs = false,
    Set<String>? resourceRefCommandTypes,
  }) {
    int serializedBytes;
    try {
      serializedBytes = utf8.encode(jsonEncode(raw)).length;
    } on Object {
      throw const AiV3ContractException('v3_plan_serialization_invalid');
    }
    if (serializedBytes > aiV3MaxSerializedPlanBytes) {
      throw const AiV3ContractException('v3_provider_plan_too_large');
    }
    final enabledResourceRefCommandTypes = allowResourceRefs
        ? resourceRefCommandTypes ?? aiV3CommandTypes
        : const <String>{};
    if (enabledResourceRefCommandTypes
        .difference(aiV3CommandTypes)
        .isNotEmpty) {
      throw const AiV3ContractException('v3_resource_ref_surface_invalid');
    }
    _requireExactKeys(raw, const <String>{
      'schema_version',
      'outcome',
      'user_message',
      'commands',
      'question_options',
    }, 'v3_plan_fields_invalid');
    if (raw['schema_version'] != aiV3PlanVersion) {
      throw const AiV3ContractException('v3_plan_version_invalid');
    }
    final outcome = raw['outcome'] is String
        ? (raw['outcome'] as String).trim()
        : '';
    if (!aiV3Outcomes.contains(outcome)) {
      throw const AiV3ContractException('v3_outcome_invalid');
    }
    final userMessage = raw['user_message'] is String
        ? (raw['user_message'] as String).trim()
        : '';
    if (userMessage.isEmpty) {
      throw const AiV3ContractException('v3_user_message_invalid');
    }
    final rawCommands = raw['commands'];
    if (rawCommands is! List) {
      throw const AiV3ContractException('v3_commands_invalid');
    }
    final commandIds = <String>{};
    final commands = <AiV3Command>[];
    for (final value in rawCommands) {
      if (value is! Map) {
        throw const AiV3ContractException('v3_command_not_object');
      }
      final command = Map<String, dynamic>.from(value);
      _requireExactKeys(command, const <String>{
        'command_id',
        'type',
        'arguments',
      }, 'v3_command_fields_invalid');
      final id = command['command_id'] is String
          ? (command['command_id'] as String).trim()
          : '';
      final type = command['type'] is String
          ? (command['type'] as String).trim()
          : '';
      final arguments = command['arguments'];
      if (id.isEmpty || id.length > 80 || !commandIds.add(id)) {
        throw const AiV3ContractException('v3_command_id_invalid');
      }
      if (!aiV3CommandTypes.contains(type) || arguments is! Map) {
        throw const AiV3ContractException('v3_command_type_invalid');
      }
      final args = Map<String, dynamic>.from(arguments);
      _validateCommand(
        type,
        args,
        allowResourceRefs: enabledResourceRefCommandTypes.contains(type),
      );
      commands.add(AiV3Command(commandId: id, type: type, arguments: args));
    }
    if (allowResourceRefs) {
      _canonicalizeIdentityResourceReferences(commands);
      _validateResourceReferences(commands);
    }
    if ((outcome == 'plan') != commands.isNotEmpty) {
      throw const AiV3ContractException('v3_outcome_command_mismatch');
    }

    final rawOptions = raw['question_options'];
    if (rawOptions is! List || rawOptions.any((value) => value is! String)) {
      throw const AiV3ContractException('v3_question_options_invalid');
    }
    final options = rawOptions
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (outcome == 'clarify' && options.length > 4) {
      throw const AiV3ContractException('v3_clarify_options_invalid');
    }
    if (outcome != 'clarify' && options.isNotEmpty) {
      throw const AiV3ContractException('v3_unexpected_question_options');
    }
    return AiV3Plan(
      outcome: outcome,
      userMessage: userMessage,
      commands: List<AiV3Command>.unmodifiable(commands),
      questionOptions: options,
    );
  }
}

void _validateCommand(
  String type,
  Map<String, dynamic> args, {
  bool allowResourceRefs = false,
}) {
  void requireKeys(List<String> keys) {
    final expected = keys.toSet();
    if (args.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(args.keys.toSet()).isNotEmpty) {
      throw AiV3ContractException('v3_$type.required_field_missing');
    }
  }

  num number(String key, {num? min, num? max}) {
    final value = args[key];
    if (value is! num ||
        !value.isFinite ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      throw AiV3ContractException('v3_$type.$key.invalid');
    }
    return value;
  }

  int rowId(String key) {
    final value = args[key];
    if (value is! int || value < 0) {
      throw AiV3ContractException('v3_$type.$key.invalid');
    }
    return value;
  }

  String text(String key, {int max = 160}) {
    final value = args[key]?.toString().trim() ?? '';
    if (value.isEmpty || value.length > max) {
      throw AiV3ContractException('v3_$type.$key.invalid');
    }
    return value;
  }

  switch (type) {
    case 'project.set_tempo':
      requireKeys(<String>['bpm', 'time_stretch_audio', 'preserve_pitch']);
      number('bpm', min: 20, max: 999);
      if (args['time_stretch_audio'] is! bool ||
          args['preserve_pitch'] is! bool) {
        throw const AiV3ContractException('v3_project_tempo_flags_invalid');
      }
      return;
    case 'transport.set_playing':
      requireKeys(<String>['playing']);
      if (args['playing'] is! bool) {
        throw const AiV3ContractException('v3_transport_playing_invalid');
      }
      return;
    case 'transport.restart':
      requireKeys(const <String>[]);
      return;
    case 'transport.set_metronome_enabled':
    case 'transport.set_loop_enabled':
      requireKeys(<String>['enabled']);
      if (args['enabled'] is! bool) {
        throw AiV3ContractException('v3_$type.enabled.invalid');
      }
      return;
    case 'row.adjust_gain_db':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['delta_db'],
        allowResourceRefs: allowResourceRefs,
      );
      number('delta_db', min: -60, max: 24);
      return;
    case 'row.set_gain_db':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['gain_db'],
        allowResourceRefs: allowResourceRefs,
      );
      number('gain_db', min: -60, max: 6);
      return;
    case 'row.adjust_pan':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['delta_signed'],
        allowResourceRefs: allowResourceRefs,
      );
      number('delta_signed', min: -2, max: 2);
      return;
    case 'row.set_pan':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['pan_signed'],
        allowResourceRefs: allowResourceRefs,
      );
      number('pan_signed', min: -1, max: 1);
      return;
    case 'row.set_muted':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['muted'],
        allowResourceRefs: allowResourceRefs,
      );
      if (args['muted'] is! bool) {
        throw const AiV3ContractException('v3_row_muted_invalid');
      }
      return;
    case 'row.select':
      requireKeys(<String>['row_id']);
      rowId('row_id');
      return;
    case 'row.set_color':
      requireKeys(<String>['row_id', 'color']);
      rowId('row_id');
      if (!const <String>{
        'none',
        'red',
        'orange',
        'yellow',
        'green',
        'cyan',
        'blue',
        'purple',
        'magenta',
      }.contains(args['color'])) {
        throw const AiV3ContractException('v3_row_color_invalid');
      }
      return;
    case 'row.set_soloed':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['soloed'],
        allowResourceRefs: allowResourceRefs,
      );
      if (args['soloed'] is! bool) {
        throw const AiV3ContractException('v3_row_soloed_invalid');
      }
      return;
    case 'row.rename':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['new_name'],
        allowResourceRefs: allowResourceRefs,
      );
      text('new_name', max: 80);
      return;
    case 'row.set_instrument':
      requireKeys(<String>['row_id', 'instrument_id']);
      rowId('row_id');
      text('instrument_id');
      return;
    case 'row.set_role_override':
      requireKeys(<String>['row_id', 'role']);
      rowId('row_id');
      final role = args['role'];
      if (role != null &&
          !const <String>{
            'vocals',
            'drums',
            'bass',
            'guitar',
            'synth',
            'other',
          }.contains(role)) {
        throw const AiV3ContractException('v3_row_role_override_invalid');
      }
      return;
    case 'row.apply_phone_mic_cleanup':
      requireKeys(<String>['row_id']);
      rowId('row_id');
      return;
    case 'row.create':
      requireKeys(<String>['name', 'lane', 'position']);
      text('name', max: 80);
      final lane = args['lane'];
      if (lane is! Map) {
        throw const AiV3ContractException('v3_row.create.lane.invalid');
      }
      final laneMap = Map<String, dynamic>.from(lane);
      final laneKind = laneMap['kind'];
      if (laneKind == 'audio') {
        _requireExactKeys(laneMap, const <String>{
          'kind',
        }, 'v3_row.create.lane.invalid');
      } else if (laneKind == 'midi') {
        _requireExactKeys(laneMap, const <String>{
          'kind',
          'instrument_id',
        }, 'v3_row.create.lane.invalid');
        final instrumentId = laneMap['instrument_id'];
        if (instrumentId is! String || instrumentId.trim().isEmpty) {
          throw const AiV3ContractException(
            'v3_row.create.instrument_id.invalid',
          );
        }
      } else {
        throw const AiV3ContractException('v3_row.create.lane.invalid');
      }
      final position = args['position'];
      if (position is! Map) {
        throw const AiV3ContractException('v3_row.create.position.invalid');
      }
      final positionMap = Map<String, dynamic>.from(position);
      final positionKind = positionMap['kind'];
      if (positionKind == 'end') {
        _requireExactKeys(positionMap, const <String>{
          'kind',
        }, 'v3_row.create.position.invalid');
      } else if (positionKind == 'before' || positionKind == 'after') {
        _requireExactKeys(positionMap, const <String>{
          'kind',
          'row_id',
        }, 'v3_row.create.position.invalid');
        final anchorId = positionMap['row_id'];
        if (anchorId is! int || anchorId < 0) {
          throw const AiV3ContractException(
            'v3_row.create.position.row_id.invalid',
          );
        }
      } else {
        throw const AiV3ContractException('v3_row.create.position.invalid');
      }
      return;
    case 'row.delete':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>[],
        allowResourceRefs: allowResourceRefs,
      );
      return;
    case 'group.create':
      final usesTypedMembers = allowResourceRefs && args['members'] is List;
      requireKeys(<String>[usesTypedMembers ? 'members' : 'row_ids', 'name']);
      final rawMembers = args[usesTypedMembers ? 'members' : 'row_ids'];
      if (rawMembers is! List || rawMembers.length < 2) {
        throw const AiV3ContractException('v3_group.create.members.invalid');
      }
      if (usesTypedMembers) {
        final identities = <String>{};
        for (final rawMember in rawMembers) {
          if (rawMember is! Map) {
            throw const AiV3ContractException(
              'v3_group.create.members.invalid',
            );
          }
          final member = Map<String, dynamic>.from(rawMember);
          final hasRowId = member['row_id'] is int && member['row_id'] >= 0;
          final hasRowRef = member['row_ref'] is Map;
          if (hasRowId == hasRowRef) {
            throw const AiV3ContractException(
              'v3_group.create.members.invalid',
            );
          }
          _requireExactKeys(member, <String>{
            hasRowId ? 'row_id' : 'row_ref',
          }, 'v3_group.create.members.invalid');
          final identity = hasRowId
              ? 'id:${member['row_id']}'
              : 'ref:${jsonEncode(_parseResourceRef(member['row_ref']).toJson())}';
          if (!identities.add(identity)) {
            throw const AiV3ContractException(
              'v3_group.create.members.invalid',
            );
          }
        }
      } else if (rawMembers.any((value) => value is! int || value < 0) ||
          rawMembers.cast<int>().toSet().length != rawMembers.length) {
        throw const AiV3ContractException('v3_group.create.row_ids.invalid');
      }
      final name = args['name'];
      if (name != null &&
          (name is! String || name.trim().isEmpty || name.trim().length > 80)) {
        throw const AiV3ContractException('v3_group.create.name.invalid');
      }
      return;
    case 'group.remove_row':
      _validateGroupAndRowTargets(
        type,
        args,
        allowResourceRefs: allowResourceRefs,
      );
      return;
    case 'group.set_collapsed':
      _validateGroupIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['collapsed'],
        allowResourceRefs: allowResourceRefs,
      );
      if (args['collapsed'] is! bool) {
        throw const AiV3ContractException(
          'v3_group.set_collapsed.collapsed.invalid',
        );
      }
      return;
    case 'clip.move_by_beats':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['delta_beats'],
        allowResourceRefs: allowResourceRefs,
      );
      number('delta_beats', min: -1024, max: 1024);
      return;
    case 'clip.trim_to_range':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['start_beat', 'end_beat'],
        allowResourceRefs: allowResourceRefs,
      );
      number('start_beat', min: 0);
      number('end_beat', min: 0);
      return;
    case 'clip.split_at':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['at_beat'],
        allowResourceRefs: allowResourceRefs,
      );
      number('at_beat', min: 0);
      return;
    case 'clip.duplicate_to':
      if (!allowResourceRefs) {
        requireKeys(<String>['clip_id', 'destination_row_id', 'start_beat']);
        text('clip_id');
        rowId('destination_row_id');
      } else {
        _validateIdOrResourceRef(
          type,
          args,
          valueKeys: const <String>['destination_row_id', 'start_beat'],
          allowResourceRefs: true,
        );
        if (args['clip_id'] != null || args['destination_row_id'] != null) {
          rowId('destination_row_id');
        }
      }
      number('start_beat', min: 0);
      return;
    case 'clip.delete':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>[],
        allowResourceRefs: allowResourceRefs,
      );
      return;
    case 'clip.glue':
      final usesTypedSources = allowResourceRefs && args['sources'] is List;
      requireKeys(<String>[usesTypedSources ? 'sources' : 'clip_ids', 'label']);
      if (usesTypedSources) {
        final rawSources = args['sources'] as List;
        final sourceKeys = <String>{};
        if (rawSources.length < 2) {
          throw const AiV3ContractException('v3_clip.glue.sources.invalid');
        }
        for (final rawSource in rawSources) {
          if (rawSource is! Map) {
            throw const AiV3ContractException('v3_clip.glue.sources.invalid');
          }
          final source = Map<String, dynamic>.from(rawSource);
          final clipId = source['clip_id'];
          final hasClipId = clipId is String && clipId.trim().isNotEmpty;
          final hasClipRef = source['clip_ref'] is Map;
          if (hasClipId == hasClipRef) {
            throw const AiV3ContractException('v3_clip.glue.sources.invalid');
          }
          _requireExactKeys(source, <String>{
            hasClipId ? 'clip_id' : 'clip_ref',
          }, 'v3_clip.glue.sources.invalid');
          final sourceKey = hasClipId
              ? 'id:${clipId.trim()}'
              : 'ref:${jsonEncode(_parseResourceRef(source['clip_ref']).toJson())}';
          if (!sourceKeys.add(sourceKey)) {
            throw const AiV3ContractException('v3_clip.glue.sources.invalid');
          }
        }
      } else {
        final rawClipIds = args['clip_ids'];
        if (rawClipIds is! List ||
            rawClipIds.length < 2 ||
            rawClipIds.any(
              (value) => value is! String || value.trim().isEmpty,
            ) ||
            rawClipIds
                    .cast<String>()
                    .map((value) => value.trim())
                    .toSet()
                    .length !=
                rawClipIds.length) {
          throw const AiV3ContractException('v3_clip.glue.clip_ids.invalid');
        }
      }
      final label = args['label'];
      if (label != null &&
          (label is! String ||
              label.trim().isEmpty ||
              label.trim().length > 80)) {
        throw const AiV3ContractException('v3_clip.glue.label.invalid');
      }
      return;
    case 'clip.separate_stems':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>[],
        allowResourceRefs: allowResourceRefs,
      );
      return;
    case 'clip.convert_to_midi':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['instrument_id'],
        allowResourceRefs: allowResourceRefs,
      );
      text('instrument_id');
      return;
    case 'clip.set_pitch_semitones':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['pitch_semitones'],
        allowResourceRefs: allowResourceRefs,
      );
      number('pitch_semitones', min: -12, max: 12);
      return;
    case 'clip.adjust_pitch_semitones':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['delta_semitones'],
        allowResourceRefs: allowResourceRefs,
      );
      number('delta_semitones', min: -24, max: 24);
      return;
    case 'clip.set_timeline_length_beats':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['length_beats', 'preserve_pitch'],
        allowResourceRefs: allowResourceRefs,
      );
      if (number('length_beats') <= 0 || args['preserve_pitch'] is! bool) {
        throw const AiV3ContractException('v3_clip_stretch_invalid');
      }
      return;
    case 'clip.scale_timeline_length':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['factor', 'preserve_pitch'],
        allowResourceRefs: allowResourceRefs,
      );
      if (number('factor') <= 0 || args['preserve_pitch'] is! bool) {
        throw const AiV3ContractException('v3_clip_stretch_invalid');
      }
      return;
    case 'clip.set_source_tempo_bpm':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['source_tempo_bpm'],
        allowResourceRefs: allowResourceRefs,
      );
      number('source_tempo_bpm', min: 20, max: 999);
      return;
    case 'clip.set_tempo_follow_mode':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['mode'],
        allowResourceRefs: allowResourceRefs,
      );
      if (!const <String>{
        'off',
        'repitch',
        'preserve_pitch',
      }.contains(text('mode'))) {
        throw const AiV3ContractException('v3_clip_tempo_follow_invalid');
      }
      return;
    case 'clip.align_tempo_to_project':
    case 'project.set_tempo_from_clip':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['mode'],
        allowResourceRefs: allowResourceRefs,
      );
      if (!const <String>{'repitch', 'preserve_pitch'}.contains(text('mode'))) {
        throw const AiV3ContractException(
          'v3_clip_tempo_analysis_mode_invalid',
        );
      }
      return;
    case 'clip.trim_silence':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['edges', 'padding_ms'],
        allowResourceRefs: allowResourceRefs,
      );
      if (!const <String>{'start', 'end', 'both'}.contains(text('edges'))) {
        throw const AiV3ContractException('v3_clip_trim_silence_edges_invalid');
      }
      number('padding_ms', min: 0, max: 500);
      return;
    case 'clip.align_first_sound':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['destination'],
        allowResourceRefs: allowResourceRefs,
      );
      final destination = args['destination'];
      if (destination is! Map) {
        throw const AiV3ContractException(
          'v3_clip_first_sound_destination_invalid',
        );
      }
      final destinationMap = Map<String, dynamic>.from(destination);
      final kind = destinationMap['kind'];
      if (kind == 'project_beat') {
        if (destinationMap.keys.toSet().difference(const <String>{
              'kind',
              'beat',
            }).isNotEmpty ||
            destinationMap.length != 2) {
          throw const AiV3ContractException(
            'v3_clip_first_sound_destination_invalid',
          );
        }
        final beat = destinationMap['beat'];
        if (beat is! num || !beat.toDouble().isFinite || beat < 0) {
          throw const AiV3ContractException(
            'v3_clip_first_sound_destination_invalid',
          );
        }
      } else if (const <String>{
        'nearest_beat',
        'nearest_bar',
        'playhead',
        'project_start',
      }.contains(kind)) {
        if (destinationMap.length != 1) {
          throw const AiV3ContractException(
            'v3_clip_first_sound_destination_invalid',
          );
        }
      } else {
        throw const AiV3ContractException(
          'v3_clip_first_sound_destination_invalid',
        );
      }
      return;
    case 'midi.transpose':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['semitones'],
        allowResourceRefs: allowResourceRefs,
      );
      final semitones = args['semitones'];
      if (semitones is! int || semitones < -48 || semitones > 48) {
        throw const AiV3ContractException('v3_midi_transpose_invalid');
      }
      return;
    case 'midi.create_clip':
      requireKeys(<String>[
        'destination',
        'start_beat',
        'length_beats',
        'notes',
      ]);
      _validateDestination(
        type,
        args['destination'],
        midi: true,
        allowResourceRefs: allowResourceRefs,
      );
      number('start_beat', min: 0);
      number('length_beats', min: 0.001);
      _validateMidiNotes(args['notes']);
      return;
    case 'midi.replace_notes':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['notes'],
        allowResourceRefs: allowResourceRefs,
      );
      _validateMidiNotes(args['notes']);
      return;
    case 'midi.append_notes':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['notes'],
        allowResourceRefs: allowResourceRefs,
      );
      _validateMidiNotes(args['notes']);
      return;
    case 'midi.chop_notes':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>[
          'subdivision',
          'range',
          'velocity_decay_per_slice',
        ],
        allowResourceRefs: allowResourceRefs,
      );
      final subdivision = args['subdivision'];
      if (subdivision is! int || subdivision < 1 || subdivision > 128) {
        throw const AiV3ContractException('v3_midi_chop_subdivision_invalid');
      }
      number('velocity_decay_per_slice', min: 0, max: 1);
      final range = args['range'];
      if (range != null) {
        if (range is! Map) {
          throw const AiV3ContractException('v3_midi_chop_range_invalid');
        }
        final value = Map<String, dynamic>.from(range);
        _requireExactKeys(value, const <String>{
          'start_beat',
          'end_beat',
        }, 'v3_midi_chop_range_invalid');
        final start = value['start_beat'];
        final end = value['end_beat'];
        if (start is! num ||
            !start.isFinite ||
            start < 0 ||
            end is! num ||
            !end.isFinite ||
            end <= start) {
          throw const AiV3ContractException('v3_midi_chop_range_invalid');
        }
      }
      return;
    case 'effect.ensure_configured':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['effect_id', 'parameters'],
        allowResourceRefs: allowResourceRefs,
      );
      text('effect_id');
      final parameters = args['parameters'];
      if (parameters is! List ||
          parameters.any((raw) {
            if (raw is! Map) return true;
            if (raw.keys.toSet().difference(const <String>{
                  'parameter_id',
                  'value',
                }).isNotEmpty ||
                const <String>{
                  'parameter_id',
                  'value',
                }.difference(raw.keys.toSet()).isNotEmpty) {
              return true;
            }
            final id = raw['parameter_id']?.toString().trim() ?? '';
            final value = raw['value'];
            return id.isEmpty ||
                value is! num ||
                !value.isFinite ||
                value < 0 ||
                value > 1;
          })) {
        throw const AiV3ContractException('v3_effect_parameters_invalid');
      }
      return;
    case 'effect.remove':
      requireKeys(<String>['effect_instance_id']);
      text('effect_instance_id');
      return;
    case 'effect.set_bypassed':
      requireKeys(<String>['effect_instance_id', 'bypassed']);
      text('effect_instance_id');
      if (args['bypassed'] is! bool) {
        throw const AiV3ContractException('v3_effect_bypassed_invalid');
      }
      return;
    case 'automation.gain_fade':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>[
          'start_beat',
          'end_beat',
          'from_gain_db',
          'to_level',
        ],
        allowResourceRefs: allowResourceRefs,
      );
      final start = number('start_beat', min: 0).toDouble();
      final end = number('end_beat', min: 0).toDouble();
      if (end <= start) {
        throw const AiV3ContractException('v3_fade_range_invalid');
      }
      number('from_gain_db', min: -120, max: 24);
      final toLevel = args['to_level'];
      if (toLevel != 'current' && toLevel is! num) {
        throw const AiV3ContractException('v3_fade_to_level_invalid');
      }
      if (toLevel is num &&
          (!toLevel.isFinite || toLevel < -120 || toLevel > 24)) {
        throw const AiV3ContractException('v3_fade_to_level_invalid');
      }
      return;
    case 'automation.set_points':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['automation_target_id', 'points'],
        allowResourceRefs: allowResourceRefs,
      );
      text('automation_target_id');
      final points = args['points'];
      if (points is! List || points.isEmpty) {
        throw const AiV3ContractException('v3_automation_points_invalid');
      }
      double? previousBeat;
      for (final raw in points) {
        if (raw is! Map) {
          throw const AiV3ContractException('v3_automation_point_invalid');
        }
        final point = Map<String, dynamic>.from(raw);
        _requireExactKeys(point, const <String>{
          'beat',
          'value_normalized',
        }, 'v3_automation_point_fields_invalid');
        final beat = point['beat'];
        final value = point['value_normalized'];
        if (beat is! num ||
            !beat.isFinite ||
            beat < 0 ||
            value is! num ||
            !value.isFinite ||
            value < 0 ||
            value > 1 ||
            (previousBeat != null && beat.toDouble() <= previousBeat)) {
          throw const AiV3ContractException('v3_automation_point_invalid');
        }
        previousBeat = beat.toDouble();
      }
      return;
    case 'automation.clear':
      _validateRowIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['automation_target_id'],
        allowResourceRefs: allowResourceRefs,
      );
      text('automation_target_id');
      return;
    case 'sample.place':
      requireKeys(<String>['destination', 'placements']);
      _validateDestination(
        type,
        args['destination'],
        allowResourceRefs: allowResourceRefs,
      );
      final placements = args['placements'];
      if (placements is! List || placements.isEmpty) {
        throw const AiV3ContractException('v3_sample_placements_invalid');
      }
      for (final value in placements) {
        if (value is! Map) {
          throw const AiV3ContractException('v3_sample_placement_not_object');
        }
        final placement = Map<String, dynamic>.from(value);
        _requireExactKeys(placement, const <String>{
          'asset_id',
          'start_beat',
        }, 'v3_sample_placement_fields_invalid');
        final assetId = placement['asset_id']?.toString().trim() ?? '';
        final start = placement['start_beat'];
        if (assetId.isEmpty || start is! num || !start.isFinite || start < 0) {
          throw const AiV3ContractException('v3_sample_placement_invalid');
        }
      }
      return;
    case 'sample.replace':
      _validateIdOrResourceRef(
        type,
        args,
        valueKeys: const <String>['asset_id'],
        allowResourceRefs: allowResourceRefs,
      );
      text('asset_id');
      return;
    case 'mix.apply_goal':
      requireKeys(<String>[
        'target',
        'intents',
        'intensity',
        'execution_profile',
        'audibility',
        'style_tags',
        'reset_fx',
        'reference',
      ]);
      _validateMixTarget(
        type,
        args['target'],
        allowResourceRefs: allowResourceRefs,
      );
      final intents = args['intents'];
      if (intents is! List || intents.isEmpty || intents.length > 4) {
        throw const AiV3ContractException('v3_mix_intents_invalid');
      }
      for (final raw in intents) {
        if (raw is! Map) {
          throw const AiV3ContractException('v3_mix_intent_invalid');
        }
        final intent = Map<String, dynamic>.from(raw);
        _requireExactKeys(intent, const <String>{
          'kind',
          'direction',
          'descriptor',
        }, 'v3_mix_intent_fields_invalid');
        if (!aiV3MixIntentKinds.contains(intent['kind']) ||
            (intent['direction'] != null &&
                !aiV3MixDirections.contains(intent['direction'])) ||
            (intent['descriptor'] != null &&
                !aiV3MixDescriptors.contains(intent['descriptor']))) {
          throw const AiV3ContractException('v3_mix_intent_invalid');
        }
      }
      number('intensity', min: 0, max: 1);
      if (!const <String>{
        'producer_safe',
        'creative_bold',
        'experimental_extreme',
      }.contains(args['execution_profile'])) {
        throw const AiV3ContractException('v3_mix_profile_invalid');
      }
      if (!const <String>{
        'subtle',
        'noticeable',
        'obvious',
        'extreme',
      }.contains(args['audibility'])) {
        throw const AiV3ContractException('v3_mix_audibility_invalid');
      }
      final styleTags = args['style_tags'];
      if (styleTags is! List ||
          styleTags.length > 8 ||
          styleTags.any(
            (value) =>
                value is! String ||
                value.trim().isEmpty ||
                value.trim().length > 40,
          )) {
        throw const AiV3ContractException('v3_mix_style_tags_invalid');
      }
      if (args['reset_fx'] is! bool) {
        throw const AiV3ContractException('v3_mix_reset_fx_invalid');
      }
      _validateMixReference(type, args['reference']);
      return;
  }
}

void _validateMidiNotes(Object? raw) {
  if (raw is! List || raw.isEmpty) {
    throw const AiV3ContractException('v3_midi_notes_invalid');
  }
  for (final value in raw) {
    if (value is! Map) {
      throw const AiV3ContractException('v3_midi_note_not_object');
    }
    final note = Map<String, dynamic>.from(value);
    _requireExactKeys(note, const <String>{
      'pitch',
      'start_beat',
      'length_beats',
      'velocity',
    }, 'v3_midi_note_fields_invalid');
    final pitch = note['pitch'];
    final start = note['start_beat'];
    final length = note['length_beats'];
    final velocity = note['velocity'];
    if (pitch is! int ||
        pitch < 0 ||
        pitch > 127 ||
        start is! num ||
        !start.isFinite ||
        start < 0 ||
        length is! num ||
        !length.isFinite ||
        length <= 0 ||
        velocity is! num ||
        !velocity.isFinite ||
        velocity < 0 ||
        velocity > 1) {
      throw const AiV3ContractException('v3_midi_note_invalid');
    }
  }
}

void _validateMixTarget(
  String type,
  Object? raw, {
  required bool allowResourceRefs,
}) {
  if (raw is! Map) {
    throw AiV3ContractException('v3_$type.target_invalid');
  }
  final target = Map<String, dynamic>.from(raw);
  final scope = target['scope'];
  switch (scope) {
    case 'row':
      if (allowResourceRefs && target['row_ref'] != null) {
        _requireExactKeys(target, const <String>{
          'scope',
          'row_ref',
        }, 'v3_$type.target_invalid');
        _parseResourceRef(target['row_ref']);
        return;
      }
      _requireExactKeys(target, const <String>{
        'scope',
        'row_id',
      }, 'v3_$type.target_invalid');
      if (target['row_id'] is! int || (target['row_id'] as int) < 0) {
        throw AiV3ContractException('v3_$type.target_invalid');
      }
      return;
    case 'group':
      if (allowResourceRefs && target['group_ref'] != null) {
        _requireExactKeys(target, const <String>{
          'scope',
          'group_ref',
        }, 'v3_$type.target_invalid');
        _parseResourceRef(target['group_ref']);
        return;
      }
      _requireExactKeys(target, const <String>{
        'scope',
        'group_id',
      }, 'v3_$type.target_invalid');
      if (target['group_id'] is! String ||
          (target['group_id'] as String).trim().isEmpty) {
        throw AiV3ContractException('v3_$type.target_invalid');
      }
      return;
    case 'all_rows':
    case 'master':
      _requireExactKeys(target, const <String>{
        'scope',
      }, 'v3_$type.target_invalid');
      return;
    default:
      throw AiV3ContractException('v3_$type.target_invalid');
  }
}

void _validateMixReference(String type, Object? raw) {
  if (raw == null) return;
  if (raw is! Map) {
    throw AiV3ContractException('v3_$type.reference_invalid');
  }
  final reference = Map<String, dynamic>.from(raw);
  _requireExactKeys(reference, const <String>{
    'row_id',
    'mode',
    'closeness',
  }, 'v3_$type.reference_invalid');
  if (reference['row_id'] is! int ||
      (reference['row_id'] as int) < 0 ||
      !const <String>{
        'tone',
        'loudness',
        'width',
        'glue',
        'full_mix',
      }.contains(reference['mode']) ||
      !const <String>{
        'loose',
        'balanced',
        'close',
      }.contains(reference['closeness'])) {
    throw AiV3ContractException('v3_$type.reference_invalid');
  }
}

AiV3ResourceRef _parseResourceRef(Object? raw) {
  try {
    return AiV3ResourceRef.fromJson(raw);
  } on FormatException {
    throw const AiV3ContractException('v3_resource_ref_invalid');
  }
}

void _validateIdOrResourceRef(
  String type,
  Map<String, dynamic> args, {
  required List<String> valueKeys,
  required bool allowResourceRefs,
}) {
  final clipId = args['clip_id'];
  final hasClipId = clipId is String && clipId.trim().isNotEmpty;
  final hasClipRef = args['clip_ref'] is Map;
  if (!allowResourceRefs) {
    _requireExactKeys(args, <String>{
      'clip_id',
      ...valueKeys,
    }, 'v3_$type.required_field_missing');
    if (!hasClipId) {
      throw AiV3ContractException('v3_$type.clip_id.invalid');
    }
    return;
  }
  if (hasClipId == hasClipRef) {
    throw AiV3ContractException('v3_$type.target_invalid');
  }
  _requireExactKeys(args, <String>{
    hasClipId ? 'clip_id' : 'clip_ref',
    ...valueKeys,
  }, 'v3_$type.target_invalid');
  if (hasClipRef) _parseResourceRef(args['clip_ref']);
}

void _validateRowIdOrResourceRef(
  String type,
  Map<String, dynamic> args, {
  required List<String> valueKeys,
  required bool allowResourceRefs,
}) {
  final rowId = args['row_id'];
  final hasRowId = rowId is int && rowId >= 0;
  final hasRowRef = args['row_ref'] is Map;
  if (!allowResourceRefs) {
    _requireExactKeys(args, <String>{
      'row_id',
      ...valueKeys,
    }, 'v3_$type.required_field_missing');
    if (!hasRowId) {
      throw AiV3ContractException('v3_$type.row_id.invalid');
    }
    return;
  }
  if (hasRowId == hasRowRef) {
    throw AiV3ContractException('v3_$type.target_invalid');
  }
  _requireExactKeys(args, <String>{
    hasRowId ? 'row_id' : 'row_ref',
    ...valueKeys,
  }, 'v3_$type.target_invalid');
  if (hasRowRef) _parseResourceRef(args['row_ref']);
}

void _validateGroupIdOrResourceRef(
  String type,
  Map<String, dynamic> args, {
  required List<String> valueKeys,
  required bool allowResourceRefs,
}) {
  final groupId = args['group_id'];
  final hasGroupId = groupId is String && groupId.trim().isNotEmpty;
  final hasGroupRef = args['group_ref'] is Map;
  if (!allowResourceRefs) {
    _requireExactKeys(args, <String>{
      'group_id',
      ...valueKeys,
    }, 'v3_$type.required_field_missing');
    if (!hasGroupId) {
      throw AiV3ContractException('v3_$type.group_id.invalid');
    }
    return;
  }
  if (hasGroupId == hasGroupRef) {
    throw AiV3ContractException('v3_$type.target_invalid');
  }
  _requireExactKeys(args, <String>{
    hasGroupId ? 'group_id' : 'group_ref',
    ...valueKeys,
  }, 'v3_$type.target_invalid');
  if (hasGroupRef) _parseResourceRef(args['group_ref']);
}

void _validateGroupAndRowTargets(
  String type,
  Map<String, dynamic> args, {
  required bool allowResourceRefs,
}) {
  final hasGroupId =
      args['group_id'] is String &&
      (args['group_id'] as String).trim().isNotEmpty;
  final hasGroupRef = args['group_ref'] is Map;
  final hasRowId = args['row_id'] is int && (args['row_id'] as int) >= 0;
  final hasRowRef = args['row_ref'] is Map;
  if (!allowResourceRefs) {
    _requireExactKeys(args, const <String>{
      'group_id',
      'row_id',
    }, 'v3_$type.required_field_missing');
    if (!hasGroupId || !hasRowId) {
      throw AiV3ContractException('v3_$type.target_invalid');
    }
    return;
  }
  if (hasGroupId == hasGroupRef || hasRowId == hasRowRef) {
    throw AiV3ContractException('v3_$type.target_invalid');
  }
  _requireExactKeys(args, <String>{
    hasGroupId ? 'group_id' : 'group_ref',
    hasRowId ? 'row_id' : 'row_ref',
  }, 'v3_$type.target_invalid');
  if (hasGroupRef) _parseResourceRef(args['group_ref']);
  if (hasRowRef) _parseResourceRef(args['row_ref']);
}

void _validateDestination(
  String type,
  Object? raw, {
  bool midi = false,
  bool allowResourceRefs = false,
}) {
  if (raw is! Map) {
    throw AiV3ContractException('v3_$type.destination_invalid');
  }
  final destination = Map<String, dynamic>.from(raw);
  final hasRow =
      destination['row_id'] is int && (destination['row_id'] as int) >= 0;
  final hasRowRef = allowResourceRefs && destination['row_ref'] is Map;
  final newRow = destination['new_row'];
  final hasNewRow = newRow is Map;
  if (<bool>[hasRow, hasRowRef, hasNewRow].where((value) => value).length !=
      1) {
    throw AiV3ContractException('v3_$type.destination_invalid');
  }
  _requireExactKeys(
    destination,
    hasRow
        ? const <String>{'row_id'}
        : hasRowRef
        ? const <String>{'row_ref'}
        : const <String>{'new_row'},
    'v3_$type.destination_invalid',
  );
  if (hasRowRef) _parseResourceRef(destination['row_ref']);
  if (hasNewRow) {
    final row = Map<String, dynamic>.from(newRow);
    _requireExactKeys(
      row,
      midi ? const <String>{'name', 'instrument_id'} : const <String>{'name'},
      'v3_$type.destination_invalid',
    );
    final name = row['name']?.toString().trim() ?? '';
    if (name.isEmpty || name.length > 80) {
      throw AiV3ContractException('v3_$type.new_row_name_invalid');
    }
    if (midi && (row['instrument_id']?.toString().trim().isEmpty ?? true)) {
      throw AiV3ContractException('v3_$type.instrument_required');
    }
  }
}

void _canonicalizeIdentityResourceReferences(List<AiV3Command> commands) {
  final earlierCommands = <String, AiV3Command>{};
  AiV3ResourceRef canonicalize(Object? rawRef) {
    var canonical = _parseResourceRef(rawRef);
    final visited = <String>{};
    while (visited.add(canonical.commandId)) {
      final aliasCommand = earlierCommands[canonical.commandId];
      final aliasSpec = aliasCommand == null
          ? null
          : aiV3ResourceConsumerSpecs[aliasCommand.type];
      if (aliasCommand == null ||
          aliasSpec == null ||
          !aliasSpec.preservesInputIdentity) {
        break;
      }
      final aliasContainer = aliasSpec.referenceContainerField == null
          ? aliasCommand.arguments
          : aliasCommand.arguments[aliasSpec.referenceContainerField];
      final aliasRawRef = aliasContainer is Map
          ? aliasContainer[aliasSpec.referenceField]
          : null;
      if (aliasRawRef == null) break;
      final aliasInput = _parseResourceRef(aliasRawRef);
      if (canonical.output != aliasInput.output) break;
      canonical = aliasInput;
    }
    return canonical;
  }

  for (final command in commands) {
    final consumerSpec = aiV3ResourceConsumerSpecs[command.type];
    Map<String, dynamic>? referenceContainer;
    if (consumerSpec?.referenceContainerField == null) {
      referenceContainer = command.arguments;
    } else {
      final rawContainer =
          command.arguments[consumerSpec!.referenceContainerField];
      if (rawContainer is Map) {
        referenceContainer = Map<String, dynamic>.from(rawContainer);
        command.arguments[consumerSpec.referenceContainerField!] =
            referenceContainer;
      }
    }
    if (consumerSpec != null && referenceContainer != null) {
      final rawRef = referenceContainer[consumerSpec.referenceField];
      if (rawRef != null) {
        referenceContainer[consumerSpec.referenceField] = canonicalize(rawRef)
            .toJson();
      }
    }
    if (command.type == 'clip.glue' && command.arguments['sources'] is List) {
      final sources = (command.arguments['sources'] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList(growable: false);
      for (final source in sources) {
        if (source['clip_ref'] != null) {
          source['clip_ref'] = canonicalize(source['clip_ref']).toJson();
        }
      }
      command.arguments['sources'] = sources;
    }
    if (command.type == 'group.create' &&
        command.arguments['members'] is List) {
      final members = (command.arguments['members'] as List)
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList(growable: false);
      for (final member in members) {
        if (member['row_ref'] != null) {
          member['row_ref'] = canonicalize(member['row_ref']).toJson();
        }
      }
      command.arguments['members'] = members;
    }
    if (command.type == 'group.remove_row') {
      if (command.arguments['group_ref'] != null) {
        command.arguments['group_ref'] = canonicalize(
          command.arguments['group_ref'],
        ).toJson();
      }
      if (command.arguments['row_ref'] != null) {
        command.arguments['row_ref'] = canonicalize(
          command.arguments['row_ref'],
        ).toJson();
      }
    }
    if (command.type == 'mix.apply_goal') {
      final target = command.arguments['target'];
      if (target is Map && target['group_ref'] != null) {
        final mutableTarget = Map<String, dynamic>.from(target);
        mutableTarget['group_ref'] = canonicalize(mutableTarget['group_ref'])
            .toJson();
        command.arguments['target'] = mutableTarget;
      }
    }
    earlierCommands[command.commandId] = command;
  }
}

void _validateResourceReferences(List<AiV3Command> commands) {
  final available = <String, Set<AiV3ResourceKind>>{};
  final parentRowByResource = <String, String>{};
  final groupMembersByResource = <String, Set<String>>{};

  ({AiV3ResourceRef ref, Set<AiV3ResourceKind> kinds}) validateRef(
    Object? raw,
    Set<AiV3ResourceKind> acceptedKinds,
  ) {
    final ref = _parseResourceRef(raw);
    final key = '${ref.commandId}.${ref.output}';
    final possibleKinds = available[key];
    if (possibleKinds == null) {
      throw const AiV3ContractException('v3_resource_ref_unavailable');
    }
    final compatibleKinds = possibleKinds.intersection(acceptedKinds);
    if (compatibleKinds.isEmpty) {
      throw const AiV3ContractException('v3_resource_ref_type_mismatch');
    }
    return (ref: ref, kinds: compatibleKinds);
  }

  for (var commandIndex = 0; commandIndex < commands.length; commandIndex++) {
    final command = commands[commandIndex];
    final args = command.arguments;
    if (command.type == 'project.set_tempo_from_clip' &&
        args['clip_ref'] is Map &&
        commandIndex != commands.length - 1) {
      throw const AiV3ContractException(
        'v3_runtime_tempo_command_must_be_final',
      );
    }
    final consumedRefs = <AiV3ResourceRef>[];
    final consumedKindsByRef = <String, Set<AiV3ResourceKind>>{};
    if (command.type == 'clip.glue' && args['sources'] is List) {
      for (final rawSource in args['sources'] as List) {
        final source = Map<String, dynamic>.from(rawSource as Map);
        if (source['clip_ref'] == null) continue;
        final validated = validateRef(
          source['clip_ref'],
          const <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
        );
        consumedRefs.add(validated.ref);
        consumedKindsByRef['${validated.ref.commandId}.${validated.ref.output}'] =
            validated.kinds;
      }
    }
    Set<String>? createdGroupMembers;
    if (command.type == 'group.create' && args['members'] is List) {
      createdGroupMembers = <String>{};
      for (final rawMember in args['members'] as List) {
        final member = Map<String, dynamic>.from(rawMember as Map);
        if (member['row_ref'] != null) {
          final validated = validateRef(
            member['row_ref'],
            const <AiV3ResourceKind>{
              AiV3ResourceKind.audioRow,
              AiV3ResourceKind.midiRow,
            },
          );
          createdGroupMembers.add(
            '${validated.ref.commandId}.${validated.ref.output}',
          );
        } else {
          createdGroupMembers.add('stable_row:${member['row_id']}');
        }
      }
      if (createdGroupMembers.length != (args['members'] as List).length) {
        throw const AiV3ContractException('v3_group.create.members.invalid');
      }
    }
    AiV3ResourceRef? removedGroupRef;
    String? removedGroupMemberKey;
    if (command.type == 'group.remove_row') {
      if (args['group_ref'] != null) {
        removedGroupRef = validateRef(
          args['group_ref'],
          const <AiV3ResourceKind>{AiV3ResourceKind.group},
        ).ref;
      }
      if (args['row_ref'] != null) {
        final rowRef = validateRef(args['row_ref'], const <AiV3ResourceKind>{
          AiV3ResourceKind.audioRow,
          AiV3ResourceKind.midiRow,
        }).ref;
        removedGroupMemberKey = '${rowRef.commandId}.${rowRef.output}';
      } else if (args['row_id'] is int) {
        removedGroupMemberKey = 'stable_row:${args['row_id']}';
      }
    }
    if (command.type == 'mix.apply_goal') {
      final target = args['target'];
      if (target is Map && target['group_ref'] != null) {
        validateRef(target['group_ref'], const <AiV3ResourceKind>{
          AiV3ResourceKind.group,
        });
      }
    }
    AiV3ResourceRef? consumedRef;
    Set<AiV3ResourceKind>? consumedKinds;
    final consumerSpec = aiV3ResourceConsumerSpecs[command.type];
    final referenceContainer = consumerSpec?.referenceContainerField == null
        ? args
        : args[consumerSpec!.referenceContainerField];
    final rawConsumerRef = referenceContainer is Map
        ? referenceContainer[consumerSpec?.referenceField]
        : null;
    if (consumerSpec != null && rawConsumerRef != null) {
      final validated = validateRef(rawConsumerRef, consumerSpec.acceptedKinds);
      consumedRef = validated.ref;
      consumedKinds = validated.kinds;
      consumedRefs.add(validated.ref);
      consumedKindsByRef['${validated.ref.commandId}.${validated.ref.output}'] =
          validated.kinds;
    }
    final consumesAllGlueSources = command.type == 'clip.glue';
    final glueParentRows = consumesAllGlueSources
        ? consumedRefs
              .map(
                (ref) => parentRowByResource['${ref.commandId}.${ref.output}'],
              )
              .whereType<String>()
              .toSet()
        : const <String>{};
    if (consumesAllGlueSources &&
        consumedRefs
                .map((ref) => '${ref.commandId}.${ref.output}')
                .toSet()
                .length !=
            consumedRefs.length) {
      throw const AiV3ContractException('v3_clip.glue.sources.invalid');
    }
    if (consumerSpec?.consumesResource == true || consumesAllGlueSources) {
      for (final ref in consumedRefs) {
        final consumedKey = '${ref.commandId}.${ref.output}';
        final kinds = consumedKindsByRef[consumedKey];
        final consumesRow =
            kinds?.any(
              (kind) =>
                  kind == AiV3ResourceKind.audioRow ||
                  kind == AiV3ResourceKind.midiRow,
            ) ==
            true;
        available.remove(consumedKey);
        parentRowByResource.remove(consumedKey);
        if (consumesRow) {
          final children = parentRowByResource.entries
              .where((entry) => entry.value == consumedKey)
              .map((entry) => entry.key)
              .toList(growable: false);
          for (final child in children) {
            available.remove(child);
            parentRowByResource.remove(child);
          }
        }
      }
    }
    if (command.type == 'row.delete' && consumedRef == null) {
      final rowId = args['row_id'];
      if (rowId is int) {
        final stableRowKey = 'stable_row:$rowId';
        final children = parentRowByResource.entries
            .where((entry) => entry.value == stableRowKey)
            .map((entry) => entry.key)
            .toList(growable: false);
        for (final child in children) {
          available.remove(child);
          parentRowByResource.remove(child);
        }
      }
    }
    String? deletedRowKey;
    if (command.type == 'row.delete') {
      deletedRowKey = consumedRef == null
          ? 'stable_row:${args['row_id']}'
          : '${consumedRef.commandId}.${consumedRef.output}';
    }
    if (removedGroupRef != null) {
      final groupKey = '${removedGroupRef.commandId}.${removedGroupRef.output}';
      final members = groupMembersByResource[groupKey];
      if (members == null ||
          removedGroupMemberKey == null ||
          !members.remove(removedGroupMemberKey)) {
        throw const AiV3ContractException('v3_group_membership_mismatch');
      }
      if (members.length < 2) {
        available.remove(groupKey);
        groupMembersByResource.remove(groupKey);
      }
    }
    if (deletedRowKey != null) {
      for (final entry in groupMembersByResource.entries.toList()) {
        if (!entry.value.remove(deletedRowKey)) continue;
        if (entry.value.length < 2) {
          available.remove(entry.key);
          groupMembersByResource.remove(entry.key);
        }
      }
    }
    final outputs = aiV3ProducedResources(
      commandType: command.type,
      arguments: command.arguments,
    );
    for (final output in outputs.entries) {
      final outputKey = '${command.commandId}.${output.key}';
      available[outputKey] = <AiV3ResourceKind>{output.value};
      if (command.type == 'group.create' &&
          output.key == 'group' &&
          createdGroupMembers != null) {
        groupMembersByResource[outputKey] = Set<String>.from(
          createdGroupMembers,
        );
      }
      if (command.type == 'clip.separate_stems') {
        if (output.key == 'vocals_clip') {
          parentRowByResource[outputKey] = '${command.commandId}.vocals_row';
        } else if (output.key == 'instrumental_clip') {
          parentRowByResource[outputKey] =
              '${command.commandId}.instrumental_row';
        }
      } else if (command.type == 'clip.convert_to_midi' &&
          output.key == 'midi_clip') {
        parentRowByResource[outputKey] = '${command.commandId}.midi_row';
      } else if (command.type == 'clip.glue' && output.key == 'glued_clip') {
        if (glueParentRows.length == 1) {
          parentRowByResource[outputKey] = glueParentRows.single;
        }
      } else if (consumerSpec?.referenceContainerField == 'destination' &&
          (output.value == AiV3ResourceKind.audioClip ||
              output.value == AiV3ResourceKind.midiClip)) {
        final destination = args['destination'];
        final stableRowId = destination is Map ? destination['row_id'] : null;
        if (consumedRef != null) {
          parentRowByResource[outputKey] =
              '${consumedRef.commandId}.${consumedRef.output}';
        } else if (stableRowId is int) {
          parentRowByResource[outputKey] = 'stable_row:$stableRowId';
        }
      }
    }
    if (consumerSpec != null &&
        consumerSpec.kindPreservingOutputPorts.isNotEmpty) {
      final outputKinds = consumedKinds ?? consumerSpec.acceptedKinds;
      final consumedKey = consumedRef == null
          ? null
          : '${consumedRef.commandId}.${consumedRef.output}';
      String? parentRow = consumedKey == null
          ? null
          : parentRowByResource[consumedKey];
      if (command.type == 'clip.duplicate_to') {
        final destinationRowId = args['destination_row_id'];
        if (destinationRowId is int) {
          parentRow = 'stable_row:$destinationRowId';
        }
      }
      for (final output in consumerSpec.kindPreservingOutputPorts) {
        final outputKey = '${command.commandId}.$output';
        available[outputKey] = Set<AiV3ResourceKind>.from(outputKinds);
        if (parentRow != null) parentRowByResource[outputKey] = parentRow;
      }
    }
  }
}

void _requireExactKeys(
  Map<dynamic, dynamic> value,
  Set<String> expected,
  String errorCode,
) {
  final actual = value.keys.map((key) => key.toString()).toSet();
  if (actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw AiV3ContractException(errorCode);
  }
}
