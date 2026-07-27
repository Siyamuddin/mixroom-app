class AiV3DomainDefinition {
  const AiV3DomainDefinition({
    required this.id,
    required this.purpose,
    this.retrievalEnabled = false,
    this.capabilities = const <String>[],
    this.requestedFields = const <String>[],
    this.commandTypes = const <String>[],
  });

  final String id;
  final String purpose;
  final bool retrievalEnabled;
  final List<String> capabilities;
  final List<String> requestedFields;
  final List<String> commandTypes;
}

const List<AiV3DomainDefinition> aiV3DomainDefinitions = <AiV3DomainDefinition>[
  AiV3DomainDefinition(
    id: 'project_structure',
    purpose: 'Project, transport, row, group, and selection details.',
  ),
  AiV3DomainDefinition(
    id: 'clip_advanced',
    purpose: 'Audio-only detailed and analysis-driven clip editing facts.',
    retrievalEnabled: true,
    capabilities: <String>[
      'set_audio_clip_pitch',
      'adjust_audio_clip_pitch',
      'set_audio_clip_timeline_length',
      'scale_audio_clip_timeline_length',
      'set_audio_clip_source_tempo',
      'set_audio_clip_tempo_follow_mode',
      'align_audio_clip_tempo_to_project',
      'set_project_tempo_from_audio_clip',
      'trim_audio_clip_silence',
      'align_audio_clip_first_sound',
      'glue_audio_clips',
      'separate_vocal_instrumental_stems',
      'convert_audio_clip_to_midi',
    ],
    requestedFields: <String>[
      'clip_details',
      'transform_capabilities',
    ],
    commandTypes: <String>[
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
      'clip.glue',
      'clip.separate_stems',
      'clip.convert_to_midi',
    ],
  ),
  AiV3DomainDefinition(
    id: 'midi',
    purpose: 'MIDI notes, instruments, transcription, and editing facts.',
    retrievalEnabled: true,
    capabilities: <String>[
      'transpose_notes',
      'create_midi_clip',
      'replace_notes',
      'append_notes',
      'chop_notes',
    ],
    requestedFields: <String>[
      'clip_notes',
      'clip_instruments',
      'edit_capabilities',
    ],
    commandTypes: <String>[
      'midi.transpose',
      'midi.create_clip',
      'midi.replace_notes',
      'midi.append_notes',
      'midi.chop_notes',
    ],
  ),
  AiV3DomainDefinition(
    id: 'samples',
    purpose: 'Sample search, metadata, placement, and replacement facts.',
    retrievalEnabled: true,
    capabilities: <String>[
      'place_samples',
      'replace_audio_clip_source',
    ],
    requestedFields: <String>[
      'search_results',
      'asset_metadata',
      'placement_capabilities',
    ],
    commandTypes: <String>[
      'sample.place',
      'sample.replace',
    ],
  ),
  AiV3DomainDefinition(
    id: 'effects',
    purpose: 'Effect instances, catalogs, parameters, and presets.',
    retrievalEnabled: true,
    capabilities: <String>[
      'ensure_configured_effect',
      'remove_effect',
      'set_effect_bypass',
    ],
    requestedFields: <String>[
      'instances',
      'catalog',
      'parameter_definitions',
      'target_capabilities',
    ],
    commandTypes: <String>[
      'effect.ensure_configured',
      'effect.remove',
      'effect.set_bypassed',
    ],
  ),
  AiV3DomainDefinition(
    id: 'automation',
    purpose: 'Automation targets, points, clips, templates, and state.',
    retrievalEnabled: true,
    capabilities: <String>[
      'create_gain_fade',
      'set_automation_points',
      'clear_automation',
    ],
    requestedFields: <String>[
      'gain_points',
      'automation_targets',
      'automation_points',
      'target_capabilities',
    ],
    commandTypes: <String>[
      'automation.gain_fade',
      'automation.set_points',
      'automation.clear',
    ],
  ),
  AiV3DomainDefinition(
    id: 'mix',
    purpose:
        'Subjective row, group, all-row, master, and reference mixing through the Mixroom mixing engine.',
    retrievalEnabled: true,
    capabilities: <String>[
      'apply_mix_goal',
      'subjective_sonic_mixing',
      'group_mixing',
      'all_rows_mixing',
      'master_mixing',
      'reference_mixing',
    ],
    requestedFields: <String>[
      'row_analysis',
      'group_state',
      'master_state',
      'reference_analysis',
      'engine_capabilities',
    ],
    commandTypes: <String>['mix.apply_goal'],
  ),
  AiV3DomainDefinition(
    id: 'music_generation',
    purpose: 'Musical brief, roles, styles, and realization capabilities.',
  ),
  AiV3DomainDefinition(
    id: 'files_plugins',
    purpose: 'File browser, instrument, plugin, and preset facts.',
  ),
  AiV3DomainDefinition(
    id: 'external_audio',
    purpose: 'Stem, transcription, cleanup, rendering, and job capabilities.',
    capabilities: <String>['apply_phone_mic_cleanup'],
    commandTypes: <String>['row.apply_phone_mic_cleanup'],
  ),
  AiV3DomainDefinition(
    id: 'tutorial_ui',
    purpose: 'Platform and visible-interface facts for non-mutating help.',
  ),
];

AiV3DomainDefinition aiV3DomainDefinition(String id) =>
    aiV3DomainDefinitions.singleWhere((definition) => definition.id == id);

Iterable<AiV3DomainDefinition> get aiV3RetrievalEnabledDomains =>
    aiV3DomainDefinitions.where((definition) => definition.retrievalEnabled);
