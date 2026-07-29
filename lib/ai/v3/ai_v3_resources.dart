enum AiV3ResourceKind { audioRow, midiRow, audioClip, midiClip }

const Set<String> aiV3RuntimeResourceRefConsumerTypes = <String>{
  'clip.set_pitch_semitones',
  'clip.adjust_pitch_semitones',
  'midi.transpose',
};
const String aiV3ResourceRefSurfaceRevision =
    'stem_pitch_midi_transpose_resource_refs_v1';

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
    case 'clip.separate_stems':
      return const <String, AiV3ResourceKind>{
        'vocals_clip': AiV3ResourceKind.audioClip,
        'instrumental_clip': AiV3ResourceKind.audioClip,
        'vocals_row': AiV3ResourceKind.audioRow,
        'instrumental_row': AiV3ResourceKind.audioRow,
      };
  }
  return const <String, AiV3ResourceKind>{};
}
