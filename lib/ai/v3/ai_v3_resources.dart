enum AiV3ResourceKind { audioRow, midiRow, audioClip, midiClip, group }

class AiV3ResourceConsumerSpec {
  const AiV3ResourceConsumerSpec({
    required this.commandType,
    required this.idField,
    required this.referenceField,
    required this.acceptedKinds,
    required this.actionType,
    required this.operation,
    this.consumesResource = false,
    this.preservesInputIdentity = false,
    this.referenceContainerField,
    this.kindPreservingOutputPorts = const <String>{},
  });

  final String commandType;
  final String idField;
  final String referenceField;
  final Set<AiV3ResourceKind> acceptedKinds;
  final String actionType;
  final String operation;
  final bool consumesResource;
  final bool preservesInputIdentity;
  final String? referenceContainerField;
  final Set<String> kindPreservingOutputPorts;
}

const Map<String, AiV3ResourceConsumerSpec> aiV3ResourceConsumerSpecs =
    <String, AiV3ResourceConsumerSpec>{
  'row.adjust_gain_db': AiV3ResourceConsumerSpec(
    commandType: 'row.adjust_gain_db',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_mix',
    operation: 'adjust_gain',
    preservesInputIdentity: true,
  ),
  'row.set_gain_db': AiV3ResourceConsumerSpec(
    commandType: 'row.set_gain_db',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_mix',
    operation: 'set_gain',
    preservesInputIdentity: true,
  ),
  'row.adjust_pan': AiV3ResourceConsumerSpec(
    commandType: 'row.adjust_pan',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_mix',
    operation: 'adjust_pan',
    preservesInputIdentity: true,
  ),
  'row.set_pan': AiV3ResourceConsumerSpec(
    commandType: 'row.set_pan',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_mix',
    operation: 'set_pan',
    preservesInputIdentity: true,
  ),
  'row.set_muted': AiV3ResourceConsumerSpec(
    commandType: 'row.set_muted',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_mute',
    operation: 'set_muted',
    preservesInputIdentity: true,
  ),
  'row.set_soloed': AiV3ResourceConsumerSpec(
    commandType: 'row.set_soloed',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_solo',
    operation: 'set_soloed',
    preservesInputIdentity: true,
  ),
  'row.rename': AiV3ResourceConsumerSpec(
    commandType: 'row.rename',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_rename',
    operation: 'rename',
    preservesInputIdentity: true,
  ),
  'row.delete': AiV3ResourceConsumerSpec(
    commandType: 'row.delete',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'row_delete',
    operation: 'delete',
    consumesResource: true,
  ),
  'effect.ensure_configured': AiV3ResourceConsumerSpec(
    commandType: 'effect.ensure_configured',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'v3_effect_configure',
    operation: 'ensure_configured',
    preservesInputIdentity: true,
  ),
  'automation.gain_fade': AiV3ResourceConsumerSpec(
    commandType: 'automation.gain_fade',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'automation_edit',
    operation: 'set_points',
    preservesInputIdentity: true,
  ),
  'automation.set_points': AiV3ResourceConsumerSpec(
    commandType: 'automation.set_points',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'v3_automation_points',
    operation: 'set_points',
    preservesInputIdentity: true,
  ),
  'automation.clear': AiV3ResourceConsumerSpec(
    commandType: 'automation.clear',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
    actionType: 'v3_automation_points',
    operation: 'clear',
    preservesInputIdentity: true,
  ),
  'group.set_collapsed': AiV3ResourceConsumerSpec(
    commandType: 'group.set_collapsed',
    idField: 'group_id',
    referenceField: 'group_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.group},
    actionType: 'v3_group_edit',
    operation: 'set_collapsed',
    preservesInputIdentity: true,
  ),
  'group.remove_row': AiV3ResourceConsumerSpec(
    commandType: 'group.remove_row',
    idField: 'group_id',
    referenceField: 'group_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.group},
    actionType: 'v3_group_edit',
    operation: 'remove_row',
  ),
  'sample.place': AiV3ResourceConsumerSpec(
    commandType: 'sample.place',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioRow},
    actionType: 'sample_insert',
    operation: 'insert_audio_clips',
    referenceContainerField: 'destination',
  ),
  'midi.create_clip': AiV3ResourceConsumerSpec(
    commandType: 'midi.create_clip',
    idField: 'row_id',
    referenceField: 'row_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.midiRow},
    actionType: 'midi_compose',
    operation: 'create_clip',
    referenceContainerField: 'destination',
  ),
  'clip.set_pitch_semitones': AiV3ResourceConsumerSpec(
    commandType: 'clip.set_pitch_semitones',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'pitch_shift',
    preservesInputIdentity: true,
  ),
  'clip.adjust_pitch_semitones': AiV3ResourceConsumerSpec(
    commandType: 'clip.adjust_pitch_semitones',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'pitch_shift',
    preservesInputIdentity: true,
  ),
  'clip.set_timeline_length_beats': AiV3ResourceConsumerSpec(
    commandType: 'clip.set_timeline_length_beats',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'stretch',
    preservesInputIdentity: true,
  ),
  'clip.scale_timeline_length': AiV3ResourceConsumerSpec(
    commandType: 'clip.scale_timeline_length',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'stretch',
    preservesInputIdentity: true,
  ),
  'clip.set_source_tempo_bpm': AiV3ResourceConsumerSpec(
    commandType: 'clip.set_source_tempo_bpm',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'set_source_tempo',
    preservesInputIdentity: true,
  ),
  'clip.set_tempo_follow_mode': AiV3ResourceConsumerSpec(
    commandType: 'clip.set_tempo_follow_mode',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'tempo_follow',
    preservesInputIdentity: true,
  ),
  'midi.transpose': AiV3ResourceConsumerSpec(
    commandType: 'midi.transpose',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
    actionType: 'midi_compose',
    operation: 'transpose_notes',
    preservesInputIdentity: true,
  ),
  'midi.replace_notes': AiV3ResourceConsumerSpec(
    commandType: 'midi.replace_notes',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
    actionType: 'midi_compose',
    operation: 'replace_notes',
    preservesInputIdentity: true,
  ),
  'midi.append_notes': AiV3ResourceConsumerSpec(
    commandType: 'midi.append_notes',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
    actionType: 'midi_compose',
    operation: 'replace_notes',
    preservesInputIdentity: true,
  ),
  'midi.chop_notes': AiV3ResourceConsumerSpec(
    commandType: 'midi.chop_notes',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
    actionType: 'midi_compose',
    operation: 'replace_notes',
    preservesInputIdentity: true,
  ),
  'clip.move_by_beats': AiV3ResourceConsumerSpec(
    commandType: 'clip.move_by_beats',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
    actionType: 'clip_edit',
    operation: 'move',
    preservesInputIdentity: true,
  ),
  'clip.delete': AiV3ResourceConsumerSpec(
    commandType: 'clip.delete',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
    actionType: 'clip_edit',
    operation: 'delete',
    consumesResource: true,
  ),
  'clip.split_at': AiV3ResourceConsumerSpec(
    commandType: 'clip.split_at',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
    actionType: 'clip_edit',
    operation: 'cut',
    consumesResource: true,
    kindPreservingOutputPorts: <String>{'left_clip', 'right_clip'},
  ),
  'clip.duplicate_to': AiV3ResourceConsumerSpec(
    commandType: 'clip.duplicate_to',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
    actionType: 'clip_edit',
    operation: 'duplicate',
    kindPreservingOutputPorts: <String>{'copy_clip'},
  ),
  'clip.trim_to_range': AiV3ResourceConsumerSpec(
    commandType: 'clip.trim_to_range',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'clip_edit',
    operation: 'trim',
    preservesInputIdentity: true,
  ),
  'sample.replace': AiV3ResourceConsumerSpec(
    commandType: 'sample.replace',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_sample_replace',
    operation: 'replace',
    preservesInputIdentity: true,
  ),
  'clip.separate_stems': AiV3ResourceConsumerSpec(
    commandType: 'clip.separate_stems',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_separate_stems',
    operation: 'separate_stems',
    preservesInputIdentity: true,
  ),
  'clip.trim_silence': AiV3ResourceConsumerSpec(
    commandType: 'clip.trim_silence',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_audio_analysis',
    operation: 'trim_silence',
    preservesInputIdentity: true,
  ),
  'clip.align_first_sound': AiV3ResourceConsumerSpec(
    commandType: 'clip.align_first_sound',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_audio_analysis',
    operation: 'align_first_sound',
    preservesInputIdentity: true,
  ),
  'clip.align_tempo_to_project': AiV3ResourceConsumerSpec(
    commandType: 'clip.align_tempo_to_project',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_audio_analysis',
    operation: 'align_tempo_to_project',
    preservesInputIdentity: true,
  ),
  'project.set_tempo_from_clip': AiV3ResourceConsumerSpec(
    commandType: 'project.set_tempo_from_clip',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_audio_analysis',
    operation: 'set_tempo_from_clip',
    preservesInputIdentity: true,
  ),
  'clip.convert_to_midi': AiV3ResourceConsumerSpec(
    commandType: 'clip.convert_to_midi',
    idField: 'clip_id',
    referenceField: 'clip_ref',
    acceptedKinds: <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    actionType: 'v3_clip_convert_to_midi',
    operation: 'convert_to_midi',
  ),
};

List<Map<String, dynamic>> aiV3CanonicalMidiNotes(
  Iterable<Map<String, dynamic>> notes,
) {
  final sorted = notes
      .map((note) => Map<String, dynamic>.from(note))
      .toList(growable: true);
  sorted.sort((a, b) {
    var result = (a['start_beat'] as num)
        .toDouble()
        .compareTo((b['start_beat'] as num).toDouble());
    if (result != 0) return result;
    result = (a['pitch'] as int).compareTo(b['pitch'] as int);
    if (result != 0) return result;
    result = (a['length_beats'] as num)
        .toDouble()
        .compareTo((b['length_beats'] as num).toDouble());
    if (result != 0) return result;
    return (a['velocity'] as num)
        .toDouble()
        .compareTo((b['velocity'] as num).toDouble());
  });
  return List<Map<String, dynamic>>.unmodifiable(sorted);
}

final Set<String> aiV3RuntimeResourceRefConsumerTypes =
    Set<String>.unmodifiable(<String>{
      ...aiV3ResourceConsumerSpecs.keys,
      'clip.glue',
      'group.create',
      'group.remove_row',
    });

const String aiV3ResourceRefSurfaceRevision =
    'generated_row_grouping_v1';

const Map<String, Map<String, Set<AiV3ResourceKind>>>
aiV3PossibleProducerOutputKinds =
    <String, Map<String, Set<AiV3ResourceKind>>>{
  'row.create': <String, Set<AiV3ResourceKind>>{
    'row': <AiV3ResourceKind>{
      AiV3ResourceKind.audioRow,
      AiV3ResourceKind.midiRow,
    },
  },
  'midi.create_clip': <String, Set<AiV3ResourceKind>>{
    'midi_clip': <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
  },
  'sample.place': <String, Set<AiV3ResourceKind>>{
    'audio_clip': <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
  },
  'clip.separate_stems': <String, Set<AiV3ResourceKind>>{
    'vocals_clip': <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    'instrumental_clip': <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
    'vocals_row': <AiV3ResourceKind>{AiV3ResourceKind.audioRow},
    'instrumental_row': <AiV3ResourceKind>{AiV3ResourceKind.audioRow},
  },
  'clip.split_at': <String, Set<AiV3ResourceKind>>{
    'left_clip': <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
    'right_clip': <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
  },
  'clip.duplicate_to': <String, Set<AiV3ResourceKind>>{
    'copy_clip': <AiV3ResourceKind>{
      AiV3ResourceKind.audioClip,
      AiV3ResourceKind.midiClip,
    },
  },
  'clip.convert_to_midi': <String, Set<AiV3ResourceKind>>{
    'midi_clip': <AiV3ResourceKind>{AiV3ResourceKind.midiClip},
    'midi_row': <AiV3ResourceKind>{AiV3ResourceKind.midiRow},
  },
  'clip.glue': <String, Set<AiV3ResourceKind>>{
    'glued_clip': <AiV3ResourceKind>{AiV3ResourceKind.audioClip},
  },
  'group.create': <String, Set<AiV3ResourceKind>>{
    'group': <AiV3ResourceKind>{AiV3ResourceKind.group},
  },
};

List<String> aiV3OutputPortsCompatibleWith(
  Set<AiV3ResourceKind> acceptedKinds,
) {
  final ports = <String>{};
  for (final outputs in aiV3PossibleProducerOutputKinds.values) {
    for (final output in outputs.entries) {
      if (output.value.intersection(acceptedKinds).isNotEmpty) {
        ports.add(output.key);
      }
    }
  }
  return ports.toList(growable: false)..sort();
}

String aiV3ProducerOutputPortCatalog(
  Set<AiV3ResourceKind> acceptedKinds,
) {
  final producers = <String>[];
  for (final producer in aiV3PossibleProducerOutputKinds.entries) {
    final outputs = producer.value.entries
        .where(
          (output) =>
              output.value.intersection(acceptedKinds).isNotEmpty,
        )
        .map((output) => output.key)
        .toList(growable: false)
      ..sort();
    if (outputs.isEmpty) continue;
    producers.add('${producer.key} -> ${outputs.join(', ')}');
  }
  producers.sort();
  return producers.join('; ');
}

class AiV3ResourceRef {
  const AiV3ResourceRef({required this.commandId, required this.output});

  final String commandId;
  final String output;

  factory AiV3ResourceRef.fromJson(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const FormatException('v3_resource_ref_invalid');
    }
    final value = Map<String, dynamic>.from(raw);
    final keys = value.keys.toSet();
    if (keys.length != 2 ||
        !keys.contains('command_id') ||
        !keys.contains('output')) {
      throw const FormatException('v3_resource_ref_invalid');
    }
    final commandId = value['command_id'];
    final output = value['output'];
    if (commandId is! String ||
        commandId.trim().isEmpty ||
        commandId.trim().length > 80 ||
        output is! String ||
        output.trim().isEmpty ||
        output.trim().length > 80) {
      throw const FormatException('v3_resource_ref_invalid');
    }
    return AiV3ResourceRef(commandId: commandId.trim(), output: output.trim());
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'command_id': commandId,
    'output': output,
  };
}

Map<String, AiV3ResourceKind> aiV3ProducedResources({
  required String commandType,
  required Map<String, dynamic> arguments,
}) {
  switch (commandType) {
    case 'row.create':
      final lane = arguments['lane'];
      final laneKind = lane is Map ? lane['kind'] : null;
      if (laneKind == 'audio') {
        return const <String, AiV3ResourceKind>{
          'row': AiV3ResourceKind.audioRow,
        };
      }
      if (laneKind == 'midi') {
        return const <String, AiV3ResourceKind>{
          'row': AiV3ResourceKind.midiRow,
        };
      }
      return const <String, AiV3ResourceKind>{};
    case 'midi.create_clip':
      return const <String, AiV3ResourceKind>{
        'midi_clip': AiV3ResourceKind.midiClip,
      };
    case 'sample.place':
      final placements = arguments['placements'];
      if (placements is List && placements.length == 1) {
        return const <String, AiV3ResourceKind>{
          'audio_clip': AiV3ResourceKind.audioClip,
        };
      }
      return const <String, AiV3ResourceKind>{};
    case 'clip.separate_stems':
      return const <String, AiV3ResourceKind>{
        'vocals_clip': AiV3ResourceKind.audioClip,
        'instrumental_clip': AiV3ResourceKind.audioClip,
        'vocals_row': AiV3ResourceKind.audioRow,
        'instrumental_row': AiV3ResourceKind.audioRow,
      };
    case 'clip.convert_to_midi':
      return const <String, AiV3ResourceKind>{
        'midi_clip': AiV3ResourceKind.midiClip,
        'midi_row': AiV3ResourceKind.midiRow,
      };
    case 'clip.glue':
      if (arguments['sources'] is! List) {
        return const <String, AiV3ResourceKind>{};
      }
      return const <String, AiV3ResourceKind>{
        'glued_clip': AiV3ResourceKind.audioClip,
      };
    case 'group.create':
      return const <String, AiV3ResourceKind>{
        'group': AiV3ResourceKind.group,
      };
  }
  return const <String, AiV3ResourceKind>{};
}
