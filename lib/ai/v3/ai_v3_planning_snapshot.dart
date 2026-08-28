import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

import '../../helpers/effect_parameter_exposure.dart';
import '../../helpers/midi_pitch_ranges.dart';
import '../../models/models.dart';
import '../../models/project_state.dart';
import 'ai_v3_audio_facts.dart';
import 'ai_v3_automation_targets.dart';

const String aiV3PlanningSnapshotSchemaVersion =
    'planning_snapshot_v3_shadow_1';

class AiV3PlanningSnapshotException implements Exception {
  const AiV3PlanningSnapshotException(this.code);

  final String code;

  @override
  String toString() => 'AiV3PlanningSnapshotException($code)';
}

/// An immutable, request-local copy of planning facts already available at the
/// V3 boundary. This object is not a planner input; later compact projections
/// and retrieval may read it without returning to mutable editor state.
class PlanningSnapshotV3 {
  PlanningSnapshotV3._({
    required this.snapshotId,
    required this.capturedAtUtc,
    required this.projectId,
    required this.stateDigest,
    required this.contentDigest,
    required Map<String, dynamic> data,
  }) : data = _freezeMap(data) {
    rowById = _indexBy<int>(this.data['rows'], 'row_id');
    clipById = _indexBy<String>(this.data['clips'], 'clip_id');
    groupById = _indexBy<String>(this.data['groups'], 'group_id');
    libraryAssetById = _indexBy<String>(
      (this.data['catalogs'] as Map)['library_assets'],
      'asset_id',
    );
    final effects = <String, Map<String, dynamic>>{};
    void indexEffects(Object? rawEffects) {
      for (final raw in (rawEffects as List? ?? const <Object>[])) {
        final effect = (raw as Map).cast<String, dynamic>();
        final id = effect['effect_instance_id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        if (effects.containsKey(id)) {
          throw const AiV3PlanningSnapshotException(
            'planning_snapshot_effect_instance_id_duplicate',
          );
        }
        effects[id] = effect;
      }
    }

    for (final row in rowById.values) {
      indexEffects(row['effects']);
    }
    for (final group in groupById.values) {
      indexEffects(group['effects']);
    }
    indexEffects((this.data['master'] as Map)['effects']);
    effectInstanceById = UnmodifiableMapView(effects);
  }

  final String snapshotId;
  final DateTime capturedAtUtc;
  final String? projectId;
  final String stateDigest;
  final String contentDigest;
  final Map<String, dynamic> data;

  late final Map<int, Map<String, dynamic>> rowById;
  late final Map<String, Map<String, dynamic>> clipById;
  late final Map<String, Map<String, dynamic>> groupById;
  late final Map<String, Map<String, dynamic>> effectInstanceById;
  late final Map<String, Map<String, dynamic>> libraryAssetById;

  String get canonicalJson => jsonEncode(data);

  Map<String, dynamic> get safeMetadata => <String, dynamic>{
    'status': 'captured',
    'schema_version': aiV3PlanningSnapshotSchemaVersion,
    'snapshot_id': snapshotId,
    'captured_at': capturedAtUtc.toIso8601String(),
    if ((projectId ?? '').isNotEmpty) 'project_id': projectId,
    'state_digest': stateDigest,
    'content_digest': contentDigest,
    'serialized_bytes': utf8.encode(canonicalJson).length,
    'counts': <String, int>{
      'rows': rowById.length,
      'clips': clipById.length,
      'groups': groupById.length,
      'effect_instances': effectInstanceById.length,
      'library_assets': libraryAssetById.length,
      'midi_notes': clipById.values.fold<int>(
        0,
        (count, clip) =>
            count + (clip['midi_notes'] as List? ?? const <Object>[]).length,
      ),
    },
  };
}

class AiV3PlanningSnapshotBuilder {
  AiV3PlanningSnapshotBuilder({
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final String Function() _idFactory;
  final DateTime Function() _clock;

  PlanningSnapshotV3 build({
    required ProjectState project,
    required List<AudioTrack> audioTracks,
    required Map<String, dynamic> validationState,
    required Map<String, dynamic> clientContext,
    required int beatsPerBar,
    required int beatUnit,
    String? projectId,
    Map<String, dynamic>? pendingPlan,
    String? pendingPlanId,
    String requestMode = 'new_request',
  }) {
    final snapshotId = _idFactory().trim();
    final stateDigest =
        validationState['client_state_digest']?.toString().trim() ?? '';
    if (snapshotId.isEmpty) {
      throw const AiV3PlanningSnapshotException('planning_snapshot_id_missing');
    }
    if (stateDigest.isEmpty) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_state_digest_missing',
      );
    }
    if (!const <String>{
      'new_request',
      'modify_pending_plan',
    }.contains(requestMode)) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_request_mode_invalid',
      );
    }
    if (!project.bpm.isFinite ||
        project.bpm <= 0 ||
        beatsPerBar <= 0 ||
        beatUnit <= 0) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_project_timing_invalid',
      );
    }

    final validationRows = _maps(validationState['rows']);
    final validationRowsById = _mutableIndexBy<int>(
      validationRows,
      'row_id',
      missingCode: 'planning_snapshot_row_id_missing',
      duplicateCode: 'planning_snapshot_row_id_duplicate',
    );
    final runtimeRows = _maps(clientContext['ai_v3_row_state']);
    final runtimeRowsById = _mutableIndexBy<int>(
      runtimeRows,
      'row_id',
      missingCode: 'planning_snapshot_row_id_missing',
      duplicateCode: 'planning_snapshot_row_id_duplicate',
    );
    final tempoStretchEnabled =
        clientContext['ai_v3_tempo_stretch_enabled'] == true;
    final rawTimelineLengths = clientContext['ai_v3_clip_timeline_lengths_ms'];
    if (rawTimelineLengths is! Map) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_clip_timeline_state_missing',
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
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_clip_timeline_state_invalid',
        );
      }
      timelineLengthMsByClipId[clipId] = lengthMs;
    }

    final clips = <Map<String, dynamic>>[];
    final clipIds = <String>{};
    final clipIdsByRow = <int, List<String>>{};
    for (var index = 0; index < audioTracks.length; index++) {
      final clip = audioTracks[index];
      final clipId = clip.clipId.trim();
      if (clipId.isEmpty || clip.rowId < 0 || clip.rowIndex < 0) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_clip_id_missing',
        );
      }
      if (!clipIds.add(clipId)) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_clip_id_duplicate',
        );
      }
      final timelineDurationMs = timelineLengthMsByClipId[clipId];
      if (timelineDurationMs == null) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_clip_timeline_state_missing',
        );
      }
      (clipIdsByRow[clip.rowId] ??= <String>[]).add(clipId);
      clips.add(<String, dynamic>{
        'clip_id': clipId,
        'display_index': index,
        'engine_clip_id': clip.engineClipId,
        'row_id': clip.rowId,
        'row_index': clip.rowIndex,
        'kind': clip.clipKind.wireName,
        'name': clip.label,
        'source_file_path': clip.file.path,
        'original_source_file_path': clip.originalFile.path,
        'audio_duration_ms': clip.audioDuration.inMilliseconds,
        'trim_start_ms': clip.trimStart.inMilliseconds,
        'trim_end_ms': clip.trimEnd.inMilliseconds,
        'start_seconds': clip.offset,
        'timeline_duration_ms': timelineDurationMs,
        'gain_ui': clip.gain,
        'normalize_volume': clip.normalizeVolume,
        'normalize_gain': clip.normalizeGain,
        'pitch_semitones': clip.pitchSemitones,
        'reversed': clip.isReversed,
        'source_tempo_bpm': clip.sourceTempoBpm,
        'stretch_to_project_tempo': clip.stretchToProjectTempo,
        'tempo_stretch_preserve_pitch': clip.tempoStretchPreservePitch,
        'tempo_warp_mode': clip.tempoWarpMode,
        'recording_latency_ms': clip.recordingLatencyMs,
        'alignment_offset_ms': clip.alignmentOffsetMs,
        'audio_enhancement_preset': clip.audioEnhancementPreset,
        'volume_automation': clip.volumeAutomation
            .map(
              (point) => <String, dynamic>{
                'time_ms': point.x,
                'value': point.volume,
              },
            )
            .toList(growable: false),
        if (clip.instrumentId.trim().isNotEmpty)
          'instrument_id': clip.instrumentId.trim(),
        if (clip.instrumentName.trim().isNotEmpty)
          'instrument_name': clip.instrumentName.trim(),
        if (clip.instrumentParams.isNotEmpty)
          'instrument_parameters': Map<String, double>.from(
            clip.instrumentParams,
          ),
        if (clip.midiNotes.isNotEmpty)
          'midi_notes': clip.midiNotes
              .map(
                (note) => <String, dynamic>{
                  'note_id': note.id,
                  'pitch': note.pitch,
                  'start_beat': note.startBeat,
                  'length_beats': note.lengthBeats,
                  'velocity': note.velocity,
                },
              )
              .toList(growable: false),
      });
    }
    if (timelineLengthMsByClipId.length != clips.length) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_clip_timeline_state_invalid',
      );
    }

    final rawAutomationByRow = clientContext['ai_v3_row_automation_points'];
    final automationByRow = <int, Map<String, List<Map<String, dynamic>>>>{};
    if (rawAutomationByRow != null) {
      if (rawAutomationByRow is! Map) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_automation_state_invalid',
        );
      }
      for (final rowEntry in rawAutomationByRow.entries) {
        final rowId = int.tryParse(rowEntry.key.toString());
        if (rowId == null || rowEntry.value is! Map) {
          throw const AiV3PlanningSnapshotException(
            'planning_snapshot_automation_state_invalid',
          );
        }
        final lanes = <String, List<Map<String, dynamic>>>{};
        for (final laneEntry in (rowEntry.value as Map).entries) {
          final targetId = laneEntry.key.toString().trim();
          final rawPoints = laneEntry.value;
          if (targetId.isEmpty || rawPoints is! List) {
            throw const AiV3PlanningSnapshotException(
              'planning_snapshot_automation_state_invalid',
            );
          }
          final points = <Map<String, dynamic>>[];
          double? previousTime;
          for (final rawPoint in rawPoints) {
            if (rawPoint is! Map) {
              throw const AiV3PlanningSnapshotException(
                'planning_snapshot_automation_state_invalid',
              );
            }
            final time = rawPoint['time_ms'];
            final value = rawPoint['value'];
            if (time is! num ||
                !time.isFinite ||
                time < 0 ||
                value is! num ||
                !value.isFinite ||
                value < 0 ||
                value > 1 ||
                (previousTime != null && time.toDouble() < previousTime)) {
              throw const AiV3PlanningSnapshotException(
                'planning_snapshot_automation_state_invalid',
              );
            }
            previousTime = time.toDouble();
            points.add(<String, dynamic>{
              'time_ms': time.toDouble(),
              'value': value.toDouble(),
            });
          }
          lanes[targetId] = points;
        }
        automationByRow[rowId] = lanes;
      }
    }

    final rows = <Map<String, dynamic>>[];
    final rowIds = <int>{};
    final rowIndexes = <int>{};
    final effectInstanceIds = <String>{};
    final orderedProjectRows = project.rows.toList(growable: false)
      ..sort((left, right) => left.rowIndex.compareTo(right.rowIndex));
    for (final row in orderedProjectRows) {
      if (row.rowId < 0 || row.rowIndex < 0) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_row_id_missing',
        );
      }
      if (!rowIds.add(row.rowId) || !rowIndexes.add(row.rowIndex)) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_row_id_duplicate',
        );
      }
      final validation = validationRowsById[row.rowId];
      final runtime = runtimeRowsById[row.rowId];
      if (validation == null ||
          runtime == null ||
          validation['row_index'] != row.rowIndex) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_row_index_incomplete',
        );
      }
      final effects = row.effects
          .map((effect) {
            final instanceId = effect.instanceId.trim();
            if (instanceId.isNotEmpty && !effectInstanceIds.add(instanceId)) {
              throw const AiV3PlanningSnapshotException(
                'planning_snapshot_effect_instance_id_duplicate',
              );
            }
            return <String, dynamic>{
              'effect_index': effect.effectIndex,
              if (instanceId.isNotEmpty) 'effect_instance_id': instanceId,
              'effect_id': effect.effectId,
              'name': effect.name,
              'bypassed': effect.isBypassed,
              'parameters': effect.parameters
                  .map((parameter) => parameter.toJson())
                  .toList(growable: false),
            };
          })
          .toList(growable: false);
      final audioFacts = AiV3AudioFacts.fromAnalysis(
        mixProcessingSupported:
            row.hasAudio || (clipIdsByRow[row.rowId]?.isNotEmpty ?? false),
        hasAudio: row.hasAudio,
        approxRms: row.approxRms,
        audioStatistics: row.audioStats,
      );
      rows.add(<String, dynamic>{
        'row_id': row.rowId,
        'display_index': row.rowIndex,
        'name': row.rowName,
        'lane_kind': row.laneKind,
        if (row.instrumentId.trim().isNotEmpty)
          'instrument_id': row.instrumentId.trim(),
        if (row.instrumentName.trim().isNotEmpty)
          'instrument_name': row.instrumentName.trim(),
        if (row.roleOverride.trim().isNotEmpty)
          'role_override': row.roleOverride.trim(),
        if (row.groupId.trim().isNotEmpty) 'group_id': row.groupId.trim(),
        'row_color': row.rowColor,
        'input_device_name': row.inputDeviceName,
        'input_channel_start': row.inputChannelStart,
        'input_channel_count': row.inputChannelCount,
        'clip_ids': List<String>.from(clipIdsByRow[row.rowId] ?? const []),
        'mixer': <String, dynamic>{
          'gain_ui': row.gain0to3,
          'pan_01': row.pan0To1,
          'muted': runtime['muted'] == true,
          'soloed': runtime['soloed'] == true,
        },
        'has_audio': row.hasAudio,
        'audio_facts': audioFacts.toJson(),
        'analysis': <String, dynamic>{
          'approx_rms': row.approxRms,
          'approx_crest': row.approxCrest,
          'role_probabilities': Map<String, double>.from(row.roleProbs),
          'role_consistency': row.roleConsistency,
          'clip_top_roles': List<String>.from(row.clipTopRoles),
          'audio_statistics': Map<String, double>.from(row.audioStats),
          'interpretation': row.interpretation.toJson(),
        },
        'effects': effects,
        'volume_automation': row.volumeAutomation
            .map(
              (point) => <String, dynamic>{
                'time_ms': point.x,
                'value': point.volume,
              },
            )
            .toList(growable: false),
        'automation_points': <String, dynamic>{
          'volume':
              (automationByRow[row.rowId]?['volume'] ??
              row.volumeAutomation
                  .map(
                    (point) => <String, dynamic>{
                      'time_ms': point.x,
                      'value': point.volume,
                    },
                  )
                  .toList(growable: false)),
          for (final entry
              in (automationByRow[row.rowId] ??
                      const <String, List<Map<String, dynamic>>>{})
                  .entries)
            if (entry.key != 'volume') entry.key: entry.value,
        },
        'automation_targets': aiV3EnsureRowMixAutomationTargets(
          _canonicalRowAutomationTargets(
            row.rowId,
            validation['automation_targets'],
          ),
        ),
      });
    }
    if (validationRowsById.keys.toSet().difference(rowIds).isNotEmpty ||
        runtimeRowsById.keys.toSet().difference(rowIds).isNotEmpty ||
        rowIds.difference(validationRowsById.keys.toSet()).isNotEmpty ||
        rowIds.difference(runtimeRowsById.keys.toSet()).isNotEmpty) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_row_index_incomplete',
      );
    }

    final validationClips = _maps(validationState['clips']);
    final validationClipIds = validationClips
        .map((clip) => clip['clip_id']?.toString().trim() ?? '')
        .toList(growable: false);
    if (validationClipIds.any((id) => id.isEmpty) ||
        validationClipIds.toSet().length != validationClipIds.length ||
        validationClipIds.toSet().difference(clipIds).isNotEmpty ||
        clipIds.difference(validationClipIds.toSet()).isNotEmpty) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_clip_index_incomplete',
      );
    }
    for (final clip in clips) {
      if (!rowIds.contains(clip['row_id'])) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_clip_row_unknown',
        );
      }
    }

    final groups = <Map<String, dynamic>>[];
    final groupIds = <String>{};
    for (final group in project.trackGroups) {
      final groupId = group.id.trim();
      if (groupId.isEmpty || !groupIds.add(groupId)) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_group_id_invalid',
        );
      }
      if (group.rowIds.any((rowId) => !rowIds.contains(rowId))) {
        throw const AiV3PlanningSnapshotException(
          'planning_snapshot_group_member_unknown',
        );
      }
      groups.add(<String, dynamic>{
        'group_id': groupId,
        'name': group.name,
        'color': group.color,
        'member_row_ids': List<int>.from(group.rowIds),
        'gain_ui': group.gain,
        'pan_01': group.pan,
        'muted': group.muted,
        'soloed': group.soloed,
        'collapsed': group.collapsed,
        'effects': group.effects
            .map(
              (effect) => <String, dynamic>{
                'effect_id': effect.effectId,
                'name': effect.displayName,
                'bypassed': effect.bypassed,
                'parameters': _copyJson(effect.params),
              },
            )
            .toList(growable: false),
      });
    }
    groups.sort(
      (left, right) =>
          left['group_id'].toString().compareTo(right['group_id'].toString()),
    );

    final selection = _selection(
      validationState['selection'],
      rows: rows,
      clips: clips,
    );
    final libraryAssets = _maps(clientContext['ai_v3_library_assets']);
    libraryAssets.sort(
      (left, right) =>
          left['asset_id'].toString().compareTo(right['asset_id'].toString()),
    );
    _mutableIndexBy<String>(
      libraryAssets,
      'asset_id',
      missingCode: 'planning_snapshot_asset_id_missing',
      duplicateCode: 'planning_snapshot_asset_id_duplicate',
    );
    final instruments = _stringList(clientContext['allowed_instrument_ids']);
    final instrumentCatalog = _instrumentCatalogFacts(
      clientContext['ai_v3_instrument_catalog'],
      instruments.toSet(),
    );
    final effectNames = _stringList(clientContext['allowed_builtin_effects']);
    final effectCatalog = effectNames
        .map(
          (name) => <String, dynamic>{
            'effect_id': name,
            'parameter_ids': List<String>.from(
              kExposedEffectParameterNames[name] ?? const <String>[],
            )..sort(),
          },
        )
        .toList(growable: false);

    final rawMaster = validationState['master'];
    if (rawMaster is! Map) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_master_missing',
      );
    }
    final playheadMs = clientContext['ai_v3_playhead_ms'];
    if (playheadMs is! num || !playheadMs.isFinite || playheadMs < 0) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_playhead_missing',
      );
    }
    final rawTransport = clientContext['ai_v3_transport'];
    if (rawTransport is! Map) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_transport_missing',
      );
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
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_transport_invalid',
      );
    }
    final maxRows = clientContext['max_rows'];
    final currentRows = clientContext['current_rows'];
    if (maxRows is! int ||
        maxRows < rows.length ||
        currentRows is! int ||
        currentRows != rows.length) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_row_capacity_invalid',
      );
    }

    final content = <String, dynamic>{
      'project': <String, dynamic>{
        'project_id': projectId,
        'bpm': project.bpm,
        'beats_per_bar': beatsPerBar,
        'beat_unit': beatUnit,
        'project_key': project.projectKey,
        'estimated_key': project.estimatedKey,
        'estimated_key_confidence': project.estimatedKeyConfidence,
        'playhead_ms': playheadMs.toDouble(),
        'tempo_stretch_enabled': tempoStretchEnabled,
        'row_capacity': <String, dynamic>{
          'current_rows': rows.length,
          'max_rows': maxRows,
          'can_create': rows.length < maxRows,
          'policy': clientContext['row_creation_policy']?.toString() ?? '',
        },
        'overlap_matrix': _copyJson(project.overlapMatrix),
        'overlap_ratio_matrix': _copyJson(project.overlapRatioMatrix),
      },
      'transport': _copyJson(transport),
      'request_state': <String, dynamic>{
        'mode': requestMode,
        if ((pendingPlanId ?? '').trim().isNotEmpty)
          'pending_plan_id': pendingPlanId!.trim(),
        if (pendingPlan != null) 'pending_plan': _copyJson(pendingPlan),
      },
      'selection': selection,
      'rows': rows,
      'groups': groups,
      'clips': clips,
      'master': <String, dynamic>{
        'gain_ui': project.masterGain0to3,
        'pan_01': project.masterPan0to1,
        'effects': project.masterEffects
            .map(
              (effect) => <String, dynamic>{
                'effect_index': effect.effectIndex,
                if (effect.instanceId.trim().isNotEmpty)
                  'effect_instance_id': effect.instanceId.trim(),
                'effect_id': effect.effectId,
                'name': effect.name,
                'bypassed': effect.isBypassed,
                'parameters': effect.parameters
                    .map((parameter) => parameter.toJson())
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
        'automation_targets': _copyJson(
          rawMaster['automation_targets'] ?? const <Object>[],
        ),
      },
      'automation_clips': _copyJson(
        validationState['automation_clips'] ?? const <Object>[],
      ),
      'catalogs': <String, dynamic>{
        'instrument_ids': instruments,
        'instrument_catalog': instrumentCatalog,
        'effects': effectCatalog,
        'library_assets': libraryAssets,
        'plugin_access': clientContext['plugin_access']?.toString() ?? '',
      },
      'services': <String, dynamic>{
        'capabilities': _stringList(clientContext['ai_capabilities']),
        'ai_v3_prototype_enabled':
            clientContext['ai_v3_prototype_enabled'] == true,
      },
    };
    final canonicalContent = _canonicalJson(content);
    final contentDigest = crypto.sha256
        .convert(utf8.encode(canonicalContent))
        .toString();
    final capturedAtUtc = _clock().toUtc();
    return PlanningSnapshotV3._(
      snapshotId: snapshotId,
      capturedAtUtc: capturedAtUtc,
      projectId: projectId,
      stateDigest: stateDigest,
      contentDigest: contentDigest,
      data: <String, dynamic>{
        'schema_version': aiV3PlanningSnapshotSchemaVersion,
        'snapshot_id': snapshotId,
        'captured_at': capturedAtUtc.toIso8601String(),
        if ((projectId ?? '').isNotEmpty) 'project_id': projectId,
        'state_digest': stateDigest,
        'content_digest': contentDigest,
        ...content,
      },
    );
  }
}

Map<String, dynamic> _selection(
  Object? raw, {
  required List<Map<String, dynamic>> rows,
  required List<Map<String, dynamic>> clips,
}) {
  final selection = raw is Map
      ? Map<String, dynamic>.from(raw)
      : const <String, dynamic>{};
  final rowByIndex = <int, int>{
    for (final row in rows) row['display_index'] as int: row['row_id'] as int,
  };
  final clipByIndex = <int, String>{
    for (final clip in clips)
      clip['display_index'] as int: clip['clip_id'] as String,
  };
  final selectedRowIndex = selection['selected_row_index'];
  final validSelectedRow =
      selectedRowIndex is int && rowByIndex.containsKey(selectedRowIndex)
      ? selectedRowIndex
      : null;
  final rawSelectedClips =
      selection['selected_clip_indices'] as List? ?? const <Object>[];
  final validSelectedClips = rawSelectedClips
      .whereType<int>()
      .where(clipByIndex.containsKey)
      .toList(growable: false);
  final primaryIndex = selection['primary_selected_clip_index'];
  final validPrimaryIndex =
      primaryIndex is int && clipByIndex.containsKey(primaryIndex)
      ? primaryIndex
      : null;
  return <String, dynamic>{
    if (validSelectedRow != null) ...<String, dynamic>{
      'selected_row_id': rowByIndex[validSelectedRow],
      'selected_row_display_index': validSelectedRow,
    },
    'selected_clip_ids': [
      for (final index in validSelectedClips) clipByIndex[index]!,
    ],
    if (validPrimaryIndex != null) ...<String, dynamic>{
      'primary_selected_clip_id': clipByIndex[validPrimaryIndex],
      'primary_selected_clip_display_index': validPrimaryIndex,
    },
  };
}

List<Map<String, dynamic>> _maps(Object? raw) {
  if (raw == null) return <Map<String, dynamic>>[];
  if (raw is! List || raw.any((value) => value is! Map)) {
    throw const AiV3PlanningSnapshotException(
      'planning_snapshot_source_malformed',
    );
  }
  return raw
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: true);
}

List<String> _stringList(Object? raw) {
  if (raw == null) return <String>[];
  if (raw is! List) {
    throw const AiV3PlanningSnapshotException(
      'planning_snapshot_source_malformed',
    );
  }
  final values =
      raw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return values;
}

List<Map<String, dynamic>> _instrumentCatalogFacts(
  Object? raw,
  Set<String> allowedIds,
) {
  if (raw == null) return <Map<String, dynamic>>[];
  final values = _maps(raw);
  final byId = <String, Map<String, dynamic>>{};
  for (final value in values) {
    final instrumentId = value['instrument_id']?.toString().trim() ?? '';
    final name = value['name']?.toString().trim() ?? '';
    if (instrumentId.isEmpty ||
        name.isEmpty ||
        !allowedIds.contains(instrumentId) ||
        byId.containsKey(instrumentId)) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_instrument_catalog_invalid',
      );
    }
    late final List<Map<String, int>> playablePitchRanges;
    try {
      playablePitchRanges = normalizeMidiPitchRanges(
        value['playable_pitch_ranges'],
      );
    } on FormatException {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_instrument_catalog_invalid',
      );
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
  return result;
}

Map<K, Map<String, dynamic>> _mutableIndexBy<K>(
  Object? raw,
  String key, {
  required String missingCode,
  required String duplicateCode,
}) {
  final values = raw is List<Map<String, dynamic>> ? raw : _maps(raw);
  final result = <K, Map<String, dynamic>>{};
  for (final value in values) {
    final id = value[key];
    if (id is! K || (id is String && id.trim().isEmpty)) {
      throw AiV3PlanningSnapshotException(missingCode);
    }
    if (result.containsKey(id)) {
      throw AiV3PlanningSnapshotException(duplicateCode);
    }
    result[id] = value;
  }
  return result;
}

Map<K, Map<String, dynamic>> _indexBy<K>(Object? raw, String key) {
  final values = (raw as List? ?? const <Object>[]).whereType<Map>();
  final result = <K, Map<String, dynamic>>{};
  for (final value in values) {
    final item = value.cast<String, dynamic>();
    final id = item[key];
    if (id is K) result[id] = item;
  }
  return UnmodifiableMapView(result);
}

Object? _copyJson(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw const AiV3PlanningSnapshotException(
        'planning_snapshot_number_non_finite',
      );
    }
    return value;
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _copyJson(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_copyJson).toList(growable: false);
  }
  throw const AiV3PlanningSnapshotException(
    'planning_snapshot_value_unsupported',
  );
}

List<Map<String, dynamic>> _canonicalRowAutomationTargets(
  int rowId,
  Object? raw,
) {
  final prefix = 'row:$rowId:';
  return (raw as List? ?? const <Object>[])
      .whereType<Map>()
      .map((value) {
        final target = Map<String, dynamic>.from(_copyJson(value) as Map);
        for (final key in const <String>['target_id', 'id']) {
          final id = target[key]?.toString().trim();
          if (id != null && id.startsWith(prefix)) {
            target[key] = id.substring(prefix.length);
          }
        }
        return target;
      })
      .toList(growable: false);
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    _freeze(_canonicalize(value)) as Map<String, dynamic>;

Object? _freeze(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, dynamic>(<String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _freeze(entry.value),
    });
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_freeze));
  }
  return value;
}
