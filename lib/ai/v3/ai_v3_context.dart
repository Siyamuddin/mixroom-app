import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import '../ai_gain_units.dart';
import '../../helpers/effect_parameter_exposure.dart';
import '../../helpers/midi_pitch_ranges.dart';
import '../../models/models.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_audio_facts.dart';
import 'ai_v3_midi_boundary.dart';

enum AiV3ContextProfile { essential, enriched, rich }

const int _aiV3MaxInstrumentCatalogFacts = 64;
const String aiV3ProjectCapacityPolicy = 'unbounded_rows_clips_v1';

AiV3ContextProfile parseAiV3ContextProfile(String value) {
  switch (value.trim().toLowerCase()) {
    case 'enriched':
      return AiV3ContextProfile.enriched;
    case 'rich':
      return AiV3ContextProfile.rich;
    case 'essential':
    default:
      return AiV3ContextProfile.essential;
  }
}

class AiV3ContextException implements Exception {
  const AiV3ContextException(this.code);
  final String code;

  @override
  String toString() => 'AiV3ContextException($code)';
}

class AiV3CoreContext {
  const AiV3CoreContext({
    required this.profile,
    required this.stateDigest,
    required this.data,
  });

  final AiV3ContextProfile profile;
  final String stateDigest;
  final Map<String, dynamic> data;

  String get profileName => profile.name;
  String get canonicalJson => jsonEncode(data);
  int get approximateTokens => (canonicalJson.length / 4).ceil();
}

class AiV3CoreContextBuilder {
  const AiV3CoreContextBuilder({this.maxLibraryAssets = 250});

  final int maxLibraryAssets;
  static const int maxCanonicalBytes = 4000000;

  AiV3CoreContext build({
    required AiV3ContextProfile profile,
    required String userRequest,
    required List<Map<String, String>> conversation,
    required Map<String, dynamic> validationState,
    required List<AudioTrack> audioTracks,
    required Map<String, dynamic> clientContext,
    required double bpm,
    required int beatsPerBar,
    required int beatUnit,
    String? projectId,
    Map<String, dynamic>? pendingPlan,
    String requestMode = 'new_request',
    String? modificationRequest,
  }) {
    final rawRows = validationState['rows'];
    final rawClips = validationState['clips'];
    if (rawRows is! List || rawClips is! List) {
      throw const AiV3ContextException('prototype_context_state_missing');
    }
    if (rawRows.any((value) => value is! Map) ||
        rawClips.any((value) => value is! Map)) {
      throw const AiV3ContextException('prototype_context_state_malformed');
    }
    if (!const <String>{
          'new_request',
          'modify_pending_plan',
        }.contains(requestMode) ||
        (requestMode == 'modify_pending_plan' &&
            (pendingPlan == null ||
                (modificationRequest ?? '').trim().isEmpty))) {
      throw const AiV3ContextException('prototype_context_request_invalid');
    }
    final libraryAssets = _libraryAssets(clientContext);
    if (libraryAssets.length > maxLibraryAssets) {
      throw const AiV3ContextException('prototype_context_library_limit');
    }
    if (libraryAssets.map((asset) => asset['asset_id']).toSet().length !=
        libraryAssets.length) {
      throw const AiV3ContextException('prototype_context_asset_id_duplicate');
    }

    final rowStateById = <int, Map<String, dynamic>>{};
    for (final raw in (clientContext['ai_v3_row_state'] as List? ?? const [])) {
      if (raw is! Map || raw['row_id'] is! int) {
        throw const AiV3ContextException('prototype_context_row_state_missing');
      }
      final id = raw['row_id'] as int;
      if (rowStateById.containsKey(id)) {
        throw const AiV3ContextException('prototype_context_row_id_duplicate');
      }
      rowStateById[id] = Map<String, dynamic>.from(raw);
    }
    final clipById = <String, AudioTrack>{};
    final clipIdsByRow = <int, List<String>>{};
    final tempoStretchEnabled =
        clientContext['ai_v3_tempo_stretch_enabled'] == true;
    final rawTimelineLengths = clientContext['ai_v3_clip_timeline_lengths_ms'];
    if (rawTimelineLengths is! Map) {
      throw const AiV3ContextException(
        'prototype_context_clip_timeline_state_missing',
      );
    }
    final timelineLengthMsByClipId = <String, double>{};
    for (final entry in rawTimelineLengths.entries) {
      final clipId = entry.key.toString().trim();
      final lengthMs = (entry.value as num?)?.toDouble();
      if (clipId.isEmpty ||
          lengthMs == null ||
          !lengthMs.isFinite ||
          lengthMs < 0 ||
          timelineLengthMsByClipId.containsKey(clipId)) {
        throw const AiV3ContextException(
          'prototype_context_clip_timeline_state_invalid',
        );
      }
      timelineLengthMsByClipId[clipId] = lengthMs;
    }
    for (final clip in audioTracks) {
      final clipId = clip.clipId.trim();
      if (clip.rowId < 0 || clipId.isEmpty) {
        throw const AiV3ContextException('prototype_context_clip_id_missing');
      }
      if (clipById.containsKey(clipId)) {
        throw const AiV3ContextException('prototype_context_clip_id_duplicate');
      }
      clipById[clipId] = clip;
      (clipIdsByRow[clip.rowId] ??= <String>[]).add(clipId);
    }
    if (timelineLengthMsByClipId.keys
            .toSet()
            .difference(clipById.keys.toSet())
            .isNotEmpty ||
        clipById.keys
            .toSet()
            .difference(timelineLengthMsByClipId.keys.toSet())
            .isNotEmpty) {
      throw const AiV3ContextException(
        'prototype_context_clip_timeline_state_missing',
      );
    }

    final rows = <Map<String, dynamic>>[];
    final rowIds = <int>{};
    final rowIndexes = <int>{};
    final effectInstanceIds = <String>{};
    for (final raw in rawRows.whereType<Map>()) {
      final source = Map<String, dynamic>.from(raw);
      final rowId = source['row_id'];
      final rowIndex = source['row_index'];
      if (rowId is! int || rowId < 0 || rowIndex is! int || rowIndex < 0) {
        throw const AiV3ContextException('prototype_context_row_id_missing');
      }
      if (!rowIds.add(rowId) || !rowIndexes.add(rowIndex)) {
        throw const AiV3ContextException('prototype_context_row_id_duplicate');
      }
      final runtime = rowStateById[rowId] ?? const <String, dynamic>{};
      final gainUi = (source['gain'] as num?)?.toDouble() ?? 2.0;
      final pan01 = (source['pan'] as num?)?.toDouble() ?? 0.5;
      final rowEffects = <Map<String, dynamic>>[];
      final rawEffects = source['effects'];
      if (rawEffects is! List || rawEffects.any((value) => value is! Map)) {
        throw const AiV3ContextException(
          'prototype_context_effect_instance_invalid',
        );
      }
      for (final rawEffect in rawEffects.whereType<Map>()) {
        final effect = Map<String, dynamic>.from(rawEffect);
        final instanceId =
            effect['effect_instance_id']?.toString().trim() ?? '';
        final effectId =
            (effect['effect_id'] ?? effect['name'])?.toString().trim() ?? '';
        final displayName = (effect['name'] ?? effectId).toString().trim();
        if (instanceId.isEmpty ||
            effectId.isEmpty ||
            !effectInstanceIds.add(instanceId)) {
          throw const AiV3ContextException(
            'prototype_context_effect_instance_invalid',
          );
        }
        rowEffects.add(<String, dynamic>{
          'effect_instance_id': instanceId,
          'effect_id': effectId,
          'display_name': displayName,
          'bypassed': effect['bypassed'] == true,
          'parameters': effect['parameters'] ?? const <Object>[],
        });
      }
      final audioAnalysis = source['audio_analysis'] is Map
          ? Map<Object?, Object?>.from(source['audio_analysis'] as Map)
          : const <Object?, Object?>{};
      final audioFacts = AiV3AudioFacts.fromAnalysis(
        mixProcessingSupported:
            source['has_audio'] == true ||
            (clipIdsByRow[rowId]?.isNotEmpty ?? false),
        hasAudio: source['has_audio'] == true,
        approxRms: (source['approx_rms'] as num?)?.toDouble() ?? 0.0,
        audioStatistics: audioAnalysis,
      );
      final row = <String, dynamic>{
        'row_id': rowId,
        'display_index': source['row_index'],
        'name': source['name'] ?? source['row_name'] ?? '',
        'lane_kind': source['lane_kind'] ?? 'audio',
        'instrument_id': source['instrument_id'],
        if ((source['role_override']?.toString().trim() ?? '').isNotEmpty)
          'role_override': source['role_override'].toString().trim(),
        if ((source['group_id']?.toString().trim() ?? '').isNotEmpty)
          'group_id': source['group_id'].toString().trim(),
        'mix_processing_supported': audioFacts.mixProcessingSupported,
        'has_usable_signal': audioFacts.hasUsableSignal,
        'analysis_available': audioFacts.analysisAvailable,
        'has_analyzable_audio': audioFacts.referenceSuitable,
        'gain_db': rowGainUiToDb(gainUi),
        'pan_signed': ((pan01.clamp(0.0, 1.0) * 2.0) - 1.0),
        'muted': runtime['muted'] ?? false,
        'soloed': runtime['soloed'] ?? false,
        'color': _canonicalRowColor(
          (source['row_color'] as num?)?.toInt() ?? 0,
        ),
        'clip_ids': (<String>[...?clipIdsByRow[rowId]]..sort()),
        'effects': rowEffects,
        'automation_targets': source['automation_targets'] ?? const <Object>[],
      };
      if (profile != AiV3ContextProfile.essential) {
        row.addAll(<String, dynamic>{
          'top_role': source['top_role'],
          'source_type': source['source_type'],
          'role_hints': source['role_hints'],
          'labels': source['labels'],
          'occupied': source['occupied'],
          'audio_analysis': source['audio_analysis'],
        });
      }
      if (profile == AiV3ContextProfile.rich) {
        row.addAll(<String, dynamic>{
          'files': source['files'],
          'is_reference': source['is_reference'],
        });
      }
      rows.add(_withoutNulls(row));
    }
    rows.sort(
      (a, b) => ((a['display_index'] as num?)?.toInt() ?? 0).compareTo(
        (b['display_index'] as num?)?.toInt() ?? 0,
      ),
    );
    if (rowStateById.keys.toSet().difference(rowIds).isNotEmpty ||
        rowIds.difference(rowStateById.keys.toSet()).isNotEmpty) {
      throw const AiV3ContextException('prototype_context_row_state_missing');
    }

    final clips = <Map<String, dynamic>>[];
    final sourceAvailability =
        (clientContext['ai_v3_clip_source_available'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value == true),
        ) ??
        const <String, bool>{};
    final validationClipIds = <String>{};
    final clipIndexes = <int>{};
    for (final raw in rawClips.whereType<Map>()) {
      final source = Map<String, dynamic>.from(raw);
      final clipId = source['clip_id']?.toString().trim() ?? '';
      final runtime = clipById[clipId];
      final clipIndex = source['clip_index'];
      if (clipId.isEmpty ||
          runtime == null ||
          runtime.rowId < 0 ||
          clipIndex is! int ||
          clipIndex < 0 ||
          source['row_id'] != runtime.rowId ||
          !rowIds.contains(runtime.rowId)) {
        throw const AiV3ContextException('prototype_context_clip_id_missing');
      }
      if (!validationClipIds.add(clipId) || !clipIndexes.add(clipIndex)) {
        throw const AiV3ContextException('prototype_context_clip_id_duplicate');
      }
      final startBeat = runtime.offset * bpm / 60.0;
      final trimDuration = runtime.trimEnd - runtime.trimStart;
      // MIDI beat lengths can end between milliseconds. Truncating them can
      // turn a valid end-of-clip note into an apparent boundary violation.
      final durationSeconds = runtime.isMidi
          ? trimDuration.inMicroseconds / Duration.microsecondsPerSecond
          : trimDuration.inMilliseconds / Duration.millisecondsPerSecond;
      final durationBeats = math.max(0.0, durationSeconds * bpm / 60.0);
      final timelineLengthBeats = math.max(
        0.0,
        (timelineLengthMsByClipId[clipId] ?? 0.0) * bpm / 60000.0,
      );
      final clip = <String, dynamic>{
        'clip_id': clipId,
        'row_id': runtime.rowId,
        'display_index': source['clip_index'],
        'kind': source['clip_kind'],
        'name': source['label'],
        'start_beat': startBeat,
        'length_beats': durationBeats,
        if (!runtime.isMidi) ...<String, dynamic>{
          'timeline_length_beats': timelineLengthBeats,
          'stretch_to_project_tempo': runtime.stretchToProjectTempo,
          'tempo_stretch_preserve_pitch': runtime.tempoStretchPreservePitch,
          'source_tempo_bpm': runtime.sourceTempoBpm,
          if (sourceAvailability.containsKey(clipId))
            'source_available': sourceAvailability[clipId],
          'trim_start_ms': source['trim_start_ms'],
          'trim_end_ms': source['trim_end_ms'],
          'alignment_offset_ms': source['alignment_offset_ms'],
        },
        'source_file': source['file'],
        'instrument_id': source['instrument_id'],
        'pitch_semitones': source['pitch_semitones'],
        if (runtime.midiNotes.isNotEmpty)
          'midi_notes': runtime.midiNotes
              .map(
                (note) => <String, dynamic>{
                  'pitch': note.pitch,
                  'start_beat': note.startBeat,
                  'length_beats': note.lengthBeats,
                  'velocity': note.velocity,
                },
              )
              .toList(growable: false),
      };
      if (profile != AiV3ContextProfile.essential) {
        clip['gain_ui'] = source['gain'];
        clip['duration_ms'] = source['duration_ms'];
      }
      clips.add(_withoutNulls(clip));
    }
    if (validationClipIds.length != clipById.length) {
      throw const AiV3ContextException(
        'prototype_context_clip_index_incomplete',
      );
    }
    clips.sort(
      (a, b) => ((a['display_index'] as num?)?.toInt() ?? 0).compareTo(
        (b['display_index'] as num?)?.toInt() ?? 0,
      ),
    );

    final history = conversation
        .where((entry) => entry['role'] != null && entry['content'] != null)
        .toList(growable: false);
    final recentHistory = history.length <= 8
        ? history
        : history.sublist(history.length - 8);
    final stateDigest = validationState['client_state_digest']
        ?.toString()
        .trim();
    final computedDigest = (stateDigest == null || stateDigest.isEmpty)
        ? crypto.sha256
              .convert(
                utf8.encode(
                  jsonEncode(<String, dynamic>{
                    'rows': rows,
                    'clips': clips,
                    'project': validationState['project'],
                  }),
                ),
              )
              .toString()
        : stateDigest;
    final playheadMs = clientContext['ai_v3_playhead_ms'];
    if (playheadMs is! num || !playheadMs.isFinite || playheadMs < 0) {
      throw const AiV3ContextException('prototype_context_playhead_missing');
    }
    final rawTransport = clientContext['ai_v3_transport'];
    if (rawTransport is! Map) {
      throw const AiV3ContextException('prototype_context_transport_missing');
    }
    final transport = Map<String, dynamic>.from(rawTransport);
    if (transport.keys.toSet().difference(const <String>{
          'playing',
          'recording',
          'metronome_enabled',
          'loop_enabled',
          'loop_start_ms',
          'loop_end_ms',
        }).isNotEmpty ||
        transport.length != 6 ||
        transport['playing'] is! bool ||
        transport['recording'] is! bool ||
        transport['metronome_enabled'] is! bool ||
        transport['loop_enabled'] is! bool ||
        transport['loop_start_ms'] is! int ||
        (transport['loop_start_ms'] as int) < 0 ||
        transport['loop_end_ms'] is! int ||
        (transport['loop_end_ms'] as int) < 0) {
      throw const AiV3ContextException('prototype_context_transport_invalid');
    }
    final usesDynamicCapacity = clientContext.containsKey('row_creation_limit');
    final configuredCreationLimit = clientContext['row_creation_limit'];
    final configuredMaxRows = clientContext['max_rows'];
    final configuredCurrentRows = clientContext['current_rows'];
    if ((usesDynamicCapacity &&
            configuredCreationLimit != null &&
            (configuredCreationLimit is! int || configuredCreationLimit < 0)) ||
        (!usesDynamicCapacity &&
            (configuredMaxRows is! int || configuredMaxRows < 0)) ||
        configuredCurrentRows is! int ||
        configuredCurrentRows != rows.length) {
      throw const AiV3ContextException(
        'prototype_context_row_capacity_missing',
      );
    }
    final creationLimit = usesDynamicCapacity
        ? configuredCreationLimit as int?
        : configuredMaxRows as int;
    final rowIdByIndex = <int, int>{
      for (final row in rows)
        if (row['display_index'] is int && row['row_id'] is int)
          row['display_index'] as int: row['row_id'] as int,
    };
    final groups = <Map<String, dynamic>>[];
    final groupIds = <String>{};
    final rawGroups = validationState['groups'];
    if (rawGroups is! List || rawGroups.any((value) => value is! Map)) {
      throw const AiV3ContextException('prototype_context_groups_missing');
    }
    for (final raw in rawGroups.whereType<Map>()) {
      final source = Map<String, dynamic>.from(raw);
      final groupId = source['group_id']?.toString().trim() ?? '';
      final memberIndices = source['member_row_indices'];
      if (groupId.isEmpty ||
          !groupIds.add(groupId) ||
          memberIndices is! List ||
          memberIndices.any((value) => value is! int) ||
          memberIndices.whereType<int>().any(
            (index) => !rowIdByIndex.containsKey(index),
          )) {
        throw const AiV3ContextException('prototype_context_group_invalid');
      }
      final gainUi = (source['gain'] as num?)?.toDouble() ?? 2.0;
      final pan01 = (source['pan'] as num?)?.toDouble() ?? 0.5;
      groups.add(<String, dynamic>{
        'group_id': groupId,
        'name': source['name'] ?? '',
        'member_row_ids': memberIndices
            .whereType<int>()
            .map((index) => rowIdByIndex[index]!)
            .toList(growable: false),
        'gain_db': rowGainUiToDb(gainUi),
        'pan_signed': (pan01.clamp(0.0, 1.0) * 2.0) - 1.0,
        'muted': source['muted'] == true,
        'soloed': source['soloed'] == true,
        'collapsed': source['collapsed'] == true,
        'effects': (source['effects'] as List? ?? const <Object>[])
            .whereType<Map>()
            .map(
              (effect) => <String, dynamic>{
                'effect_index': effect['effect_index'],
                'effect_id': effect['effect_id'] ?? effect['name'],
                'name': effect['name'] ?? effect['effect_id'],
                'bypassed': effect['bypassed'] == true,
              },
            )
            .toList(growable: false),
      });
    }
    groups.sort(
      (a, b) => a['group_id'].toString().compareTo(b['group_id'].toString()),
    );
    final rawMaster = validationState['master'];
    if (rawMaster is! Map) {
      throw const AiV3ContextException('prototype_context_master_missing');
    }
    final masterSource = Map<String, dynamic>.from(rawMaster);
    final masterGainUi = (masterSource['gain'] as num?)?.toDouble() ?? 2.0;
    final masterPan01 = (masterSource['pan'] as num?)?.toDouble() ?? 0.5;
    final master = <String, dynamic>{
      'gain_db': rowGainUiToDb(masterGainUi),
      'pan_signed': (masterPan01.clamp(0.0, 1.0) * 2.0) - 1.0,
      'effects': (masterSource['effects'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map(
            (effect) => <String, dynamic>{
              'effect_index': effect['effect_index'],
              'name': effect['name'],
              'bypassed': effect['bypassed'] == true,
            },
          )
          .toList(growable: false),
    };

    final data = <String, dynamic>{
      'schema_version': 'core_context_v3_prototype_1',
      'profile': profile.name,
      'state_digest': computedDigest,
      'original_request': userRequest,
      'request_mode': requestMode,
      if (requestMode == 'modify_pending_plan')
        'modification_request': modificationRequest!.trim(),
      'project': <String, dynamic>{
        'project_id': projectId,
        'bpm': bpm,
        if (usesDynamicCapacity)
          'project_capacity_policy': aiV3ProjectCapacityPolicy,
        'midi_boundary_policy': aiV3MidiBoundaryPolicy,
        'generated_midi_policy': aiV3GeneratedMidiPolicy,
        'plan_command_policy': aiV3PlanCommandPolicy,
        'beats_per_bar': beatsPerBar,
        'beat_unit': beatUnit,
        'key': (validationState['project'] as Map?)?['project_key'],
        'estimated_key': (validationState['project'] as Map?)?['estimated_key'],
        'playhead_ms': playheadMs,
        'playhead_beat': playheadMs.toDouble() * bpm / 60000.0,
        'row_capacity': <String, dynamic>{
          'current_rows': rows.length,
          if (usesDynamicCapacity) 'creation_limit': creationLimit,
          if (!usesDynamicCapacity) 'max_rows': creationLimit,
          'can_create': creationLimit == null || rows.length < creationLimit,
        },
        'tempo_stretch_enabled': tempoStretchEnabled,
      },
      'transport': transport,
      'selection': _selectionWithStableIds(
        validationState['selection'],
        rows,
        clips,
      ),
      'rows': rows,
      'groups': groups,
      'master': master,
      'clips': clips,
      'instruments': _sortedUniqueStrings(
        clientContext['allowed_instrument_ids'],
      ),
      'instrument_catalog': _instrumentCatalogFacts(
        clientContext,
        existingInstrumentIds: rows
            .where((row) => row['lane_kind'] == 'instrument')
            .map((row) => row['instrument_id']?.toString().trim() ?? '')
            .where((instrumentId) => instrumentId.isNotEmpty)
            .toSet(),
      ),
      'effects': _effectCatalog(clientContext, profile),
      'library_assets': libraryAssets
          .map((asset) {
            if (profile == AiV3ContextProfile.essential) {
              return <String, dynamic>{
                'asset_id': asset['asset_id'],
                'path': asset['path'],
                'role': asset['role'],
              };
            }
            if (profile == AiV3ContextProfile.enriched) {
              return <String, dynamic>{
                'asset_id': asset['asset_id'],
                'path': asset['path'],
                'role': asset['role'],
                'bpm': asset['bpm'],
              };
            }
            return asset;
          })
          .toList(growable: false),
      'conversation': recentHistory,
      'capabilities': aiV3CommandTypes.toList()..sort(),
      'runtime_capabilities': _sortedUniqueStrings(
        clientContext['ai_capabilities'],
      ),
      if (pendingPlan != null) 'pending_plan': pendingPlan,
    };
    final cleanedData = _withoutNulls(data);
    if (usesDynamicCapacity && creationLimit == null) {
      final project = cleanedData['project'] as Map<String, dynamic>;
      final rowCapacity = project['row_capacity'] as Map<String, dynamic>;
      // Null is meaningful here: it explicitly means that the current plan has
      // no product-defined row creation ceiling.
      rowCapacity['creation_limit'] = null;
    }
    final context = AiV3CoreContext(
      profile: profile,
      stateDigest: computedDigest,
      data: cleanedData,
    );
    if (utf8.encode(context.canonicalJson).length > maxCanonicalBytes) {
      throw const AiV3ContextException('v3_context_request_limit');
    }
    return context;
  }
}

String _canonicalRowColor(int argb) {
  if (argb == 0) return 'none';
  return switch (argb) {
    0xFFFF6F7D => 'red',
    0xFFFFA654 => 'orange',
    0xFFFFDD66 => 'yellow',
    0xFF69E080 => 'green',
    0xFF6BD7F0 => 'cyan',
    0xFF79A8FF => 'blue',
    0xFFC78DFF => 'purple',
    0xFFFF7FE3 => 'magenta',
    _ => 'custom',
  };
}

List<Map<String, dynamic>> _libraryAssets(Map<String, dynamic> context) {
  final raw = context['ai_v3_library_assets'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = raw
      .whereType<Map>()
      .map((value) => _withoutNulls(Map<String, dynamic>.from(value)))
      .where(
        (value) =>
            value['asset_id']?.toString().trim().isNotEmpty == true &&
            value['path']?.toString().trim().isNotEmpty == true,
      )
      .toList(growable: false);
  out.sort(
    (a, b) => a['asset_id'].toString().compareTo(b['asset_id'].toString()),
  );
  return out;
}

List<Map<String, dynamic>> _effectCatalog(
  Map<String, dynamic> context,
  AiV3ContextProfile profile,
) {
  final names = _sortedUniqueStrings(context['allowed_builtin_effects']);
  return names
      .map((name) {
        final parameters =
            kExposedEffectParameterNames[name] ?? const <String>[];
        return <String, dynamic>{
          'effect_id': name,
          'parameters': parameters
              .map(
                (parameter) => <String, dynamic>{
                  'parameter_id': parameter,
                  'range': <double>[0, 1],
                  if (profile == AiV3ContextProfile.rich)
                    'description': 'Normalized exposed $parameter control',
                },
              )
              .toList(growable: false),
        };
      })
      .toList(growable: false);
}

List<String> _sortedUniqueStrings(Object? raw) {
  final values =
      (raw as List? ?? const <Object>[])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return values;
}

List<Map<String, dynamic>> _instrumentCatalogFacts(
  Map<String, dynamic> context, {
  required Set<String> existingInstrumentIds,
}) {
  final allowedIds = _sortedUniqueStrings(
    context['allowed_instrument_ids'],
  ).toSet();
  final describableIds = allowedIds.union(existingInstrumentIds);
  final raw = context['ai_v3_instrument_catalog'];
  if (raw == null) return const <Map<String, dynamic>>[];
  if (raw is! List || raw.any((value) => value is! Map)) {
    throw const AiV3ContextException('prototype_instrument_catalog_invalid');
  }
  final byId = <String, Map<String, dynamic>>{};
  for (final value in raw.whereType<Map>()) {
    final instrumentId = value['instrument_id']?.toString().trim() ?? '';
    final name = value['name']?.toString().trim() ?? '';
    if (instrumentId.isEmpty ||
        name.isEmpty ||
        !describableIds.contains(instrumentId) ||
        byId.containsKey(instrumentId)) {
      throw const AiV3ContextException('prototype_instrument_catalog_invalid');
    }
    late final List<Map<String, int>> playablePitchRanges;
    try {
      playablePitchRanges = normalizeMidiPitchRanges(
        value['playable_pitch_ranges'],
      );
    } on FormatException {
      throw const AiV3ContextException('prototype_instrument_catalog_invalid');
    }
    byId[instrumentId] = <String, dynamic>{
      'instrument_id': instrumentId,
      'name': name,
      if (playablePitchRanges.isNotEmpty)
        'playable_pitch_ranges': playablePitchRanges,
    };
  }
  final result = byId.values.toList(growable: false)
    ..sort(
      (left, right) => left['instrument_id'].toString().compareTo(
        right['instrument_id'].toString(),
      ),
    );
  return result.take(_aiV3MaxInstrumentCatalogFacts).toList(growable: false);
}

Map<String, dynamic> _selectionWithStableIds(
  Object? rawSelection,
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> clips,
) {
  final selection = rawSelection is Map
      ? Map<String, dynamic>.from(rawSelection)
      : const <String, dynamic>{};
  final rowByIndex = <int, int>{
    for (final row in rows)
      if (row['display_index'] is int && row['row_id'] is int)
        row['display_index'] as int: row['row_id'] as int,
  };
  final clipByIndex = <int, String>{
    for (final clip in clips)
      if (clip['display_index'] is int && clip['clip_id'] is String)
        clip['display_index'] as int: clip['clip_id'] as String,
  };
  final rowIndex = selection['selected_row_index'];
  final clipIndices =
      (selection['selected_clip_indices'] as List? ?? const <Object>[])
          .whereType<int>();
  final primaryIndex = selection['primary_selected_clip_index'];
  return _withoutNulls(<String, dynamic>{
    'selected_row_id': rowIndex is int ? rowByIndex[rowIndex] : null,
    'selected_clip_ids': clipIndices
        .map((index) => clipByIndex[index])
        .whereType<String>()
        .toList(),
    'primary_selected_clip_id': primaryIndex is int
        ? clipByIndex[primaryIndex]
        : null,
  });
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) =>
    <String, dynamic>{
      for (final entry in value.entries)
        if (entry.value != null) entry.key: entry.value,
    };
