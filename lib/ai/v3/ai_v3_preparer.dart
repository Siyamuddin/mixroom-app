import 'dart:io';
import 'dart:math' as math;

import '../../helpers/timeline_tempo_mapping.dart';
import '../../models/mixing_result.dart';
import 'package:uuid/uuid.dart';
import 'ai_v3_context.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_resources.dart';

class AiV3PreparationException implements Exception {
  const AiV3PreparationException(this.code);
  final String code;

  @override
  String toString() => 'AiV3PreparationException($code)';
}

class AiV3PreparedBundle {
  const AiV3PreparedBundle({
    required this.plan,
    required this.stateDigest,
    required this.actions,
    required this.receipts,
    required this.preview,
    this.executionPolicy = AiV3ExecutionPolicy.autoApply,
  });

  final AiV3Plan plan;
  final String stateDigest;
  final List<AssistantAction> actions;
  final List<Map<String, dynamic>> receipts;
  final String preview;
  final AiV3ExecutionPolicy executionPolicy;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': 'prepared_bundle_v3_prototype_1',
        'state_digest': stateDigest,
        'plan': plan.toJson(),
        'actions': actions.map((action) => action.toJson()).toList(),
        'receipts': receipts,
        'preview': preview,
        'execution_policy': executionPolicy.wireName,
      };
}

class AiV3ClipBoundaryAnalysis {
  const AiV3ClipBoundaryAnalysis({
    required this.audibleStartMs,
    required this.audibleEndMs,
    required this.firstSoundOffsetMs,
  });

  final double audibleStartMs;
  final double audibleEndMs;
  final double firstSoundOffsetMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'audible_start_ms': audibleStartMs,
    'audible_end_ms': audibleEndMs,
    'first_sound_offset_ms': firstSoundOffsetMs,
  };
}

class _AiV3SymbolicResource {
  _AiV3SymbolicResource({
    required this.kind,
    required this.startMs,
    this.durationMs,
    this.durationFollowsTempo,
    this.rowId,
    this.rowIndex,
    this.parentRowResourceKey,
    this.pitchSemitones,
    this.sourceTempoBpm,
    this.tempoFollowMode,
    this.tempoPreservePitch,
    this.midiNotes,
    this.midiNotesRuntimeAuthoritative = false,
    this.boundsRuntimeAuthoritative = false,
    this.rowName,
    this.instrumentId,
    this.gainDb,
    this.panSigned,
    this.muted,
    this.soloed,
    this.groupId,
    this.groupMemberKeys,
    this.groupCollapsed,
  });

  final AiV3ResourceKind kind;
  double startMs;
  double? durationMs;
  bool? durationFollowsTempo;
  final int? rowId;
  int? rowIndex;
  String? parentRowResourceKey;
  bool available = true;
  double? pitchSemitones;
  double? sourceTempoBpm;
  String? tempoFollowMode;
  bool? tempoPreservePitch;
  List<Map<String, dynamic>>? midiNotes;
  bool midiNotesRuntimeAuthoritative;
  bool boundsRuntimeAuthoritative;
  String? rowName;
  String? instrumentId;
  double? gainDb;
  double? panSigned;
  bool? muted;
  bool? soloed;
  String? groupId;
  List<Object>? groupMemberKeys;
  bool? groupCollapsed;
}

class AiV3CommandPreparer {
  const AiV3CommandPreparer();

  AiV3PreparedBundle prepare({
    required AiV3Plan plan,
    required AiV3CoreContext context,
    Map<String, double> detectedTempoByClipId = const <String, double>{},
    Map<String, AiV3ClipBoundaryAnalysis> boundaryAnalysisByClipId =
        const <String, AiV3ClipBoundaryAnalysis>{},
  }) {
    if (!plan.isMutating) {
      throw const AiV3PreparationException('v3_non_mutating_plan');
    }
    final preparedPlan = _canonicalizeEmbeddedDestinationRows(plan);
    final referencedProducerCommandIds = <String>{};
    for (final command in preparedPlan.commands) {
      final references = <Object?>[
        command.arguments['clip_ref'],
        command.arguments['row_ref'],
        if (command.arguments['destination'] is Map)
          (command.arguments['destination'] as Map)['row_ref'],
        if (command.arguments['sources'] is List)
          ...(command.arguments['sources'] as List).whereType<Map>().map(
            (source) => source['clip_ref'],
          ),
        if (command.type == 'group.create' &&
            command.arguments['members'] is List)
          ...(command.arguments['members'] as List).whereType<Map>().map(
            (member) => member['row_ref'],
          ),
      ];
      for (final rawRef in references.whereType<Map>()) {
        final commandId = rawRef['command_id']?.toString().trim() ?? '';
        if (commandId.isNotEmpty) {
          referencedProducerCommandIds.add(commandId);
        }
      }
    }
    final rows = (context.data['rows'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final clips = (context.data['clips'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final assets = (context.data['library_assets'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final groups = (context.data['groups'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final instruments =
        (context.data['instruments'] as List? ?? const <Object>[])
            .map((value) => value.toString())
            .toSet();
    final effects = (context.data['effects'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final runtimeCapabilities =
        (context.data['runtime_capabilities'] as List? ?? const <Object>[])
            .map((value) => value.toString())
            .toSet();
    final rowById = <int, Map<String, dynamic>>{
      for (final row in rows)
        if (row['row_id'] is int) row['row_id'] as int: row,
    };
    final simulatedRoleOverrideByRowId = <int, String>{
      for (final entry in rowById.entries)
        entry.key: entry.value['role_override']?.toString().trim() ?? '',
    };
    final clipById = <String, Map<String, dynamic>>{
      for (final clip in clips)
        if (clip['clip_id'] is String) clip['clip_id'] as String: clip,
    };
    final simulatedMidiNotesByClipId = <String, List<Map<String, dynamic>>>{
      for (final entry in clipById.entries)
        if (entry.value['kind'] == 'midi')
          entry.key: _normalizedMidiNotes(
            entry.value['midi_notes'] as List? ?? const <Object>[],
          ),
    };
    final simulatedMidiLengthByClipId = <String, double>{
      for (final entry in clipById.entries)
        if (entry.value['kind'] == 'midi' && entry.value['length_beats'] is num)
          entry.key: (entry.value['length_beats'] as num).toDouble(),
    };
    final assetById = <String, Map<String, dynamic>>{
      for (final asset in assets)
        if (asset['asset_id'] is String) asset['asset_id'] as String: asset,
    };
    final groupById = <String, Map<String, dynamic>>{
      for (final group in groups)
        if (group['group_id'] is String) group['group_id'] as String: group,
    };
    final simulatedGroupsById = <String, Map<String, dynamic>>{
      for (final entry in groupById.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final simulatedGroupIdByRow = <Object, String>{};
    for (final entry in simulatedGroupsById.entries) {
      final members = (entry.value['member_row_ids'] as List? ?? const [])
          .whereType<int>()
          .toList(growable: false);
      for (final rowId in members) {
        if (simulatedGroupIdByRow.containsKey(rowId)) {
          throw const AiV3PreparationException('v3_group_membership_invalid');
        }
        simulatedGroupIdByRow[rowId] = entry.key;
      }
    }
    final effectById = <String, Map<String, dynamic>>{
      for (final effect in effects)
        if (effect['effect_id'] is String)
          effect['effect_id'] as String: effect,
    };
    final effectChainByRowId = <int, List<Map<String, dynamic>>>{};
    final effectRowByInstanceId = <String, int>{};
    final seenEffectInstanceIds = <String>{};
    for (final row in rows) {
      final rowId = row['row_id'];
      if (rowId is! int) continue;
      final chain = (row['effects'] as List? ?? const <Object>[])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: true);
      for (final effect in chain) {
        final instanceId =
            effect['effect_instance_id']?.toString().trim() ?? '';
        if (instanceId.isEmpty || !seenEffectInstanceIds.add(instanceId)) {
          throw const AiV3PreparationException(
            'v3_effect_instance_index_invalid',
          );
        }
        effectRowByInstanceId[instanceId] = rowId;
      }
      effectChainByRowId[rowId] = chain;
    }
    final cleanupRowIds = preparedPlan.commands
        .where((command) => command.type == 'row.apply_phone_mic_cleanup')
        .map((command) => command.arguments['row_id'])
        .whereType<int>()
        .toSet();
    if (cleanupRowIds.isNotEmpty) {
      for (final command in preparedPlan.commands) {
        int? effectMutationRowId;
        if (command.type == 'effect.ensure_configured') {
          effectMutationRowId = command.arguments['row_id'] as int?;
        } else if (command.type == 'effect.remove' ||
            command.type == 'effect.set_bypassed') {
          final instanceId =
              command.arguments['effect_instance_id']?.toString() ?? '';
          effectMutationRowId = effectRowByInstanceId[instanceId];
        }
        if (effectMutationRowId != null &&
            cleanupRowIds.contains(effectMutationRowId)) {
          throw const AiV3PreparationException(
            'v3_phone_cleanup_effect_conflict',
          );
        }
        if (command.type != 'mix.apply_goal') continue;
        final rawTarget = command.arguments['target'];
        if (rawTarget is! Map) continue;
        final target = Map<String, dynamic>.from(rawTarget);
        final targetRowIds = <int>{};
        switch (target['scope']) {
          case 'row':
            final rowId = target['row_id'];
            if (rowId is int) targetRowIds.add(rowId);
            break;
          case 'group':
            final group = simulatedGroupsById[target['group_id']];
            targetRowIds.addAll(
              (group?['member_row_ids'] as List? ?? const <Object>[])
                  .whereType<int>(),
            );
            break;
          case 'all_rows':
            targetRowIds.addAll(rowById.keys);
            break;
        }
        if (targetRowIds.any(cleanupRowIds.contains)) {
          throw const AiV3PreparationException(
            'v3_phone_cleanup_effect_conflict',
          );
        }
      }
    }
    final project = context.data['project'] as Map;
    final rawTransport = context.data['transport'];
    if (rawTransport is! Map) {
      throw const AiV3PreparationException('v3_transport_state_missing');
    }
    final transport = Map<String, dynamic>.from(rawTransport);
    final recording = transport['recording'] == true;
    var simulatedLoopEnabled = transport['loop_enabled'] == true;
    var simulatedLoopStartMs =
        (transport['loop_start_ms'] as num?)?.round() ?? 0;
    var simulatedLoopEndMs = (transport['loop_end_ms'] as num?)?.round() ?? 0;
    final selection = context.data['selection'] is Map
        ? Map<String, dynamic>.from(context.data['selection'] as Map)
        : const <String, dynamic>{};
    final bpm = (project['bpm'] as num).toDouble();
    var symbolicBpm = bpm;
    var projectAudioForcedTempoFollow = false;
    final rowCapacity = project['row_capacity'];
    if (rowCapacity is! Map ||
        rowCapacity['current_rows'] is! int ||
        rowCapacity['max_rows'] is! int ||
        rowCapacity['current_rows'] != rows.length) {
      throw const AiV3PreparationException('v3_row_capacity_missing');
    }
    final maximumRows = rowCapacity['max_rows'] as int;
    var simulatedRowCount = rows.length;
    var simulatedClipCount = clips.length;
    final deletedRowIds = <int>{};
    final unavailableClipIds = <String>{};
    final previouslyMutatedClipIds = <String>{};
    var hasPriorTopologyMutation = false;
    var hasPreparedStemSeparation = false;
    var hasPreparedAudioToMidi = false;
    final symbolicResources = <String, _AiV3SymbolicResource>{};
    final symbolicRowOrder = <Object>[
      ...rows.map((row) => row['row_id']).whereType<int>(),
    ];
    final simulatedRowOrder = rows
        .toList(growable: false)
        .map((row) => row['row_id'])
        .whereType<int>()
        .toList(growable: true);
    final actions = <AssistantAction>[];
    final receipts = <Map<String, dynamic>>[];
    final previewLines = <String>[];

    Map<String, dynamic> rowTarget(int rowId) {
      final row = rowById[rowId];
      if (row == null || deletedRowIds.contains(rowId)) {
        throw const AiV3PreparationException('v3_row_id_unknown');
      }
      return <String, dynamic>{
        'scope': 'row',
        'row_id': rowId,
        'row_index': row['display_index'],
      };
    }

    Map<String, dynamic> automationTarget(
      int rowId,
      String automationTargetId,
    ) {
      final target = rowTarget(rowId);
      final row = rowById[rowId]!;
      final ownerPrefix = 'row:$rowId:';
      final canonicalTargetId = automationTargetId.startsWith(ownerPrefix)
          ? automationTargetId.substring(ownerPrefix.length)
          : automationTargetId;
      final matches = (row['automation_targets'] as List? ?? const <Object>[])
          .whereType<Map>()
          .where((candidate) {
        final id =
            (candidate['target_id'] ?? candidate['id'])?.toString().trim() ??
                '';
        return id == canonicalTargetId;
      }).toList(growable: false);
      if (matches.length != 1) {
        throw const AiV3PreparationException(
          'v3_automation_target_unknown',
        );
      }
      final metadata = matches.single;
      if (metadata['isOrphan'] == true ||
          metadata['is_orphan'] == true ||
          metadata['uiVisible'] == false ||
          metadata['ui_visible'] == false) {
        throw const AiV3PreparationException(
          'v3_automation_target_unknown',
        );
      }
      return <String, dynamic>{
        ...target,
        'automation_target_id': canonicalTargetId,
      };
    }

    Map<String, dynamic> generatedRowAutomationTarget(
      ({
        Map<String, dynamic> target,
        AiV3ResourceRef? ref,
        _AiV3SymbolicResource? symbolic,
        String label,
      })
      resolved,
      String automationTargetId,
    ) {
      if (resolved.ref == null) {
        return automationTarget(
          resolved.target['row_id'] as int,
          automationTargetId,
        );
      }
      if (!const <String>{
        'volume',
        'mix:gain',
        'mix:pan',
      }.contains(automationTargetId)) {
        throw const AiV3PreparationException('v3_automation_target_unknown');
      }
      return <String, dynamic>{
        ...resolved.target,
        'automation_target_id': automationTargetId,
      };
    }

    Map<String, dynamic> clipTarget(
      String clipId, {
      bool requireMidi = false,
      bool requireAudio = false,
    }) {
      final clip = clipById[clipId];
      if (clip == null || unavailableClipIds.contains(clipId)) {
        throw const AiV3PreparationException('v3_clip_id_unknown');
      }
      final rowId = clip['row_id'];
      if (rowId is! int || deletedRowIds.contains(rowId)) {
        throw const AiV3PreparationException('v3_clip_id_unknown');
      }
      if (requireMidi && clip['kind'] != 'midi') {
        throw const AiV3PreparationException('v3_midi_clip_required');
      }
      if (requireAudio && clip['kind'] != 'audio') {
        throw const AiV3PreparationException('v3_audio_clip_required');
      }
      return <String, dynamic>{
        'scope': 'clip',
        'clip_id': clipId,
        'clip_index': clip['display_index'],
        'row_id': clip['row_id'],
        'row_index': rowById[clip['row_id']]?['display_index'],
      };
    }

    ({AiV3ResourceRef ref, _AiV3SymbolicResource resource}) symbolicRowTarget(
      Object? raw, {
      required Set<AiV3ResourceKind> acceptedKinds,
    }) {
      late final AiV3ResourceRef ref;
      try {
        ref = AiV3ResourceRef.fromJson(raw);
      } on FormatException {
        throw const AiV3PreparationException('v3_resource_ref_unavailable');
      }
      final resource = symbolicResources['${ref.commandId}.${ref.output}'];
      if (resource == null ||
          !resource.available ||
          !acceptedKinds.contains(resource.kind) ||
          resource.rowIndex == null) {
        throw const AiV3PreparationException('v3_resource_ref_unavailable');
      }
      return (ref: ref, resource: resource);
    }

    Map<String, dynamic> generatedRowActionTarget(
      AiV3ResourceRef ref,
      _AiV3SymbolicResource resource,
    ) => <String, dynamic>{
      'scope': 'row',
      'row_index': resource.rowIndex,
      'resource_ref': ref.toJson(),
    };

    ({Map<String, dynamic> target, List<AssistantAction> setup}) destination(
      Object? raw, {
      required bool midi,
    }) {
      final value = Map<String, dynamic>.from(raw as Map);
      if (value['row_id'] is int) {
        final target = rowTarget(value['row_id'] as int);
        final row = rowById[value['row_id'] as int]!;
        if (midi && row['lane_kind'] != 'instrument') {
          throw const AiV3PreparationException('v3_instrument_row_required');
        }
        if (!midi && row['lane_kind'] == 'instrument') {
          throw const AiV3PreparationException('v3_audio_row_required');
        }
        return (target: target, setup: const <AssistantAction>[]);
      }
      if (value['row_ref'] is Map) {
        final resolved = symbolicRowTarget(
          value['row_ref'],
          acceptedKinds: <AiV3ResourceKind>{
            midi ? AiV3ResourceKind.midiRow : AiV3ResourceKind.audioRow,
          },
        );
        return (
          target: <String, dynamic>{
            ...generatedRowActionTarget(resolved.ref, resolved.resource),
            if ((resolved.resource.instrumentId ?? '').isNotEmpty)
              'instrument_id': resolved.resource.instrumentId,
          },
          setup: const <AssistantAction>[],
        );
      }
      final newRow = Map<String, dynamic>.from(value['new_row'] as Map);
      if (simulatedRowCount >= maximumRows) {
        throw const AiV3PreparationException('v3_row_capacity_exceeded');
      }
      // Embedded destinations always append their row. Its executable index is
      // therefore the current simulated row count, not an index derived from
      // the original snapshot. A preceding deletion changes that count.
      final rowIndex = simulatedRowCount;
      simulatedRowCount += 1;
      hasPriorTopologyMutation = true;
      final instrumentId = newRow['instrument_id']?.toString().trim() ?? '';
      if (midi && !instruments.contains(instrumentId)) {
        throw const AiV3PreparationException('v3_instrument_id_unknown');
      }
      return (
        target: <String, dynamic>{
          'scope': 'row',
          'row_index': rowIndex,
          if (instrumentId.isNotEmpty) 'instrument_id': instrumentId,
        },
        setup: <AssistantAction>[
          AssistantAction(
            type: 'row_create',
            data: <String, dynamic>{
              'operation': 'create',
              'position': 'end',
              'name': newRow['name'],
              'lane_kind': midi ? 'instrument' : 'audio',
              if (instrumentId.isNotEmpty) 'instrument_id': instrumentId,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          ),
        ],
      );
    }

    for (final command in preparedPlan.commands) {
      final args = command.arguments;
      final commandActions = <AssistantAction>[];
      String label;
      String verifiedLabel;
      var receiptStatus = 'prepared';
      ({
        Map<String, dynamic> target,
        AiV3ResourceRef? ref,
        _AiV3SymbolicResource? symbolic,
        String label,
      })
      resolveRowCommandTarget() {
        final rawRef = args['row_ref'];
        if (rawRef is Map) {
          final spec = aiV3ResourceConsumerSpecs[command.type];
          if (spec == null) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final resolved = symbolicRowTarget(
            rawRef,
            acceptedKinds: spec.acceptedKinds,
          );
          return (
            target: generatedRowActionTarget(resolved.ref, resolved.resource),
            ref: resolved.ref,
            symbolic: resolved.resource,
            label: '${resolved.ref.commandId}.${resolved.ref.output}',
          );
        }
        final rowId = args['row_id'] as int;
        return (
          target: rowTarget(rowId),
          ref: null,
          symbolic: null,
          label: _rowLabel(rowById, rowId),
        );
      }

      final topologyConsumerSpec = aiV3ResourceConsumerSpecs[command.type];
      final topologyReferenceContainer =
          topologyConsumerSpec?.referenceContainerField == null
          ? args
          : args[topologyConsumerSpec!.referenceContainerField];
      final hasTypedTopologyTarget =
          topologyConsumerSpec != null &&
              topologyReferenceContainer is Map &&
              topologyReferenceContainer[topologyConsumerSpec.referenceField]
                  is Map ||
          (command.type == 'group.create' &&
              args['members'] is List &&
              (args['members'] as List).any(
                (member) => member is Map && member['row_ref'] is Map,
              )) ||
          (command.type == 'group.remove_row' &&
              (args['group_ref'] is Map || args['row_ref'] is Map));
      if ((hasPreparedStemSeparation || hasPreparedAudioToMidi) &&
          !hasTypedTopologyTarget &&
          const <String>{
            'row.create',
            'row.delete',
            'group.create',
            'group.remove_row',
            'clip.glue',
            'clip.separate_stems',
            'clip.convert_to_midi',
            'mix.apply_goal',
          }.contains(command.type)) {
        throw const AiV3PreparationException('v3_row_id_unknown');
      }
      switch (command.type) {
        case 'project.set_tempo':
          final nextBpm = (args['bpm'] as num).toDouble();
          final stretchAudio = args['time_stretch_audio'] == true;
          commandActions.add(
            AssistantAction(
              type: 'project_edit',
              data: <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': args['bpm'],
                'time_stretch_audio': args['time_stretch_audio'],
                'preserve_pitch': args['preserve_pitch'],
                'target': const <String, dynamic>{'scope': 'project'},
              },
            ),
          );
          for (final resource in symbolicResources.values) {
            resource.startMs = remapTimelineMillisecondsForTempoChange(
              resource.startMs,
              previousBpm: symbolicBpm,
              nextBpm: nextBpm,
            );
            final durationFollowsTempo =
                resource.kind == AiV3ResourceKind.midiClip ||
                (resource.kind == AiV3ResourceKind.audioClip &&
                    (stretchAudio || resource.durationFollowsTempo == true));
            if (durationFollowsTempo && resource.durationMs != null) {
              resource.durationMs = remapTimelineMillisecondsForTempoChange(
                resource.durationMs!,
                previousBpm: symbolicBpm,
                nextBpm: nextBpm,
              );
            }
            if (stretchAudio && resource.kind == AiV3ResourceKind.audioClip) {
              resource.durationFollowsTempo = true;
            }
          }
          if (stretchAudio) projectAudioForcedTempoFollow = true;
          symbolicBpm = nextBpm;
          label = 'Set project tempo to ${args['bpm']} BPM';
          verifiedLabel = label;
          break;
        case 'transport.set_playing':
          if (recording) {
            throw const AiV3PreparationException(
              'v3_transport_recording_active',
            );
          }
          final playing = args['playing'] as bool;
          commandActions.add(AssistantAction(
            type: 'v3_transport',
            data: <String, dynamic>{
              'operation': 'set_playing',
              'playing': playing,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          ));
          label = playing ? 'Start playback' : 'Pause playback';
          verifiedLabel = playing ? 'Started playback' : 'Paused playback';
          break;
        case 'transport.restart':
          if (recording) {
            throw const AiV3PreparationException(
              'v3_transport_recording_active',
            );
          }
          commandActions.add(AssistantAction(
            type: 'v3_transport',
            data: const <String, dynamic>{
              'operation': 'restart',
              'target': <String, dynamic>{'scope': 'project'},
            },
          ));
          label =
              simulatedLoopEnabled && simulatedLoopEndMs > simulatedLoopStartMs
              ? 'Pause playback at the loop start'
              : 'Pause playback at the project start';
          verifiedLabel =
              simulatedLoopEnabled && simulatedLoopEndMs > simulatedLoopStartMs
              ? 'Paused playback at the loop start'
              : 'Paused playback at the project start';
          break;
        case 'transport.set_metronome_enabled':
          final enabled = args['enabled'] as bool;
          commandActions.add(AssistantAction(
            type: 'v3_transport',
            data: <String, dynamic>{
              'operation': 'set_metronome_enabled',
              'enabled': enabled,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          ));
          label = '${enabled ? 'Enable' : 'Disable'} the metronome';
          verifiedLabel = '${enabled ? 'Enabled' : 'Disabled'} the metronome';
          break;
        case 'transport.set_loop_enabled':
          final enabled = args['enabled'] as bool;
          simulatedLoopEnabled = enabled;
          if (enabled && simulatedLoopEndMs <= simulatedLoopStartMs) {
            // The editor creates the existing four-bar default at execution
            // time. Keep the simulated range merely valid for later ordered
            // restart semantics; the runtime expectation owns exact bounds.
            simulatedLoopStartMs = 0;
            simulatedLoopEndMs = 1;
          }
          commandActions.add(AssistantAction(
            type: 'v3_transport',
            data: <String, dynamic>{
              'operation': 'set_loop_enabled',
              'enabled': enabled,
              'target': const <String, dynamic>{'scope': 'project'},
            },
          ));
          label = '${enabled ? 'Enable' : 'Disable'} loop playback';
          verifiedLabel = '${enabled ? 'Enabled' : 'Disabled'} loop playback';
          break;
        case 'row.adjust_gain_db':
          final resolved = resolveRowCommandTarget();
          final target = resolved.target;
          final deltaDb = (args['delta_db'] as num).toDouble();
          if (resolved.symbolic != null) {
            resolved.symbolic!.gainDb =
                ((resolved.symbolic!.gainDb ?? 0.0) + deltaDb).clamp(
                  -60.0,
                  6.0,
                );
          }
          commandActions.add(
            AssistantAction(
              type: 'row_mix',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'adjust_gain',
                'delta_db': args['delta_db'],
                if (resolved.symbolic != null)
                  'expected_gain_db': resolved.symbolic!.gainDb,
                'target': target,
              },
            ),
          );
          label = 'Adjust ${resolved.label} by ${args['delta_db']} dB';
          verifiedLabel =
              'Adjusted ${resolved.label} by ${args['delta_db']} dB';
          break;
        case 'row.set_gain_db':
          final resolved = resolveRowCommandTarget();
          final target = resolved.target;
          if (resolved.symbolic != null) {
            resolved.symbolic!.gainDb = (args['gain_db'] as num).toDouble();
          }
          commandActions.add(
            AssistantAction(
              type: 'row_mix',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'set_gain',
                'gain_db': args['gain_db'],
                if (resolved.symbolic != null)
                  'expected_gain_db': resolved.symbolic!.gainDb,
                'target': target,
              },
            ),
          );
          label = 'Set ${resolved.label} gain to ${args['gain_db']} dB';
          verifiedLabel = label;
          break;
        case 'row.adjust_pan':
          final resolved = resolveRowCommandTarget();
          final target = resolved.target;
          final delta = (args['delta_signed'] as num).toDouble();
          if (resolved.symbolic != null) {
            resolved.symbolic!.panSigned =
                ((resolved.symbolic!.panSigned ?? 0.0) + delta).clamp(
                  -1.0,
                  1.0,
                );
          }
          commandActions.add(
            AssistantAction(
              type: 'row_mix',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'adjust_pan',
                'delta': args['delta_signed'],
                if (resolved.symbolic != null)
                  'expected_pan_signed': resolved.symbolic!.panSigned,
                'target': target,
              },
            ),
          );
          label = 'Adjust ${resolved.label} pan by ${args['delta_signed']}';
          verifiedLabel =
              'Adjusted ${resolved.label} pan by ${args['delta_signed']}';
          break;
        case 'row.set_pan':
          final resolved = resolveRowCommandTarget();
          final target = resolved.target;
          if (resolved.symbolic != null) {
            resolved.symbolic!.panSigned = (args['pan_signed'] as num)
                .toDouble();
          }
          commandActions.add(
            AssistantAction(
              type: 'row_mix',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'set_pan',
                'pan_signed': args['pan_signed'],
                if (resolved.symbolic != null)
                  'expected_pan_signed': resolved.symbolic!.panSigned,
                'target': target,
              },
            ),
          );
          label = 'Set ${resolved.label} pan to ${args['pan_signed']}';
          verifiedLabel = label;
          break;
        case 'row.set_muted':
          final muted = args['muted'] as bool;
          final resolved = resolveRowCommandTarget();
          final target = resolved.target;
          final currentMuted =
              resolved.symbolic?.muted ?? rowById[args['row_id']]?['muted'];
          if (currentMuted == muted) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(
              AssistantAction(
                type: 'row_mute',
                data: <String, dynamic>{
                  if (resolved.ref != null)
                    'resource_consumer_type': command.type,
                  'operation': 'set_muted',
                  'muted': muted,
                  if (resolved.symbolic != null) 'expected_muted': muted,
                  'target': target,
                },
              ),
            );
            if (resolved.symbolic != null) {
              resolved.symbolic!.muted = muted;
            }
          }
          label = '${muted ? 'Mute' : 'Unmute'} ${resolved.label}';
          verifiedLabel = '${muted ? 'Muted' : 'Unmuted'} ${resolved.label}';
          break;
        case 'row.set_soloed':
          final soloed = args['soloed'] as bool;
          final resolved = resolveRowCommandTarget();
          final currentSoloed =
              resolved.symbolic?.soloed ?? rowById[args['row_id']]?['soloed'];
          if (currentSoloed == soloed) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(
              AssistantAction(
                type: 'row_solo',
                data: <String, dynamic>{
                  if (resolved.ref != null)
                    'resource_consumer_type': command.type,
                  'operation': 'set_soloed',
                  'soloed': soloed,
                  if (resolved.symbolic != null) 'expected_soloed': soloed,
                  'target': resolved.target,
                },
              ),
            );
            if (resolved.symbolic != null) {
              resolved.symbolic!.soloed = soloed;
            }
          }
          label = '${soloed ? 'Solo' : 'Unsolo'} ${resolved.label}';
          verifiedLabel = '${soloed ? 'Soloed' : 'Unsoloed'} ${resolved.label}';
          break;
        case 'row.rename':
          final resolved = resolveRowCommandTarget();
          final newName = args['new_name'] as String;
          if (resolved.symbolic != null) {
            resolved.symbolic!.rowName = newName;
          }
          commandActions.add(
            AssistantAction(
              type: 'row_rename',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'rename',
                'new_name': newName,
                if (resolved.symbolic != null) 'expected_name': newName,
                'target': resolved.target,
              },
            ),
          );
          label = 'Rename ${resolved.label} to $newName';
          verifiedLabel = 'Renamed ${resolved.label} to $newName';
          break;
        case 'row.set_role_override':
          final rowId = args['row_id'] as int;
          final target = rowTarget(rowId);
          final role = args['role']?.toString() ?? '';
          if (simulatedRoleOverrideByRowId[rowId] == role) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'v3_row_role_override',
              data: <String, dynamic>{
                'role': role.isEmpty ? null : role,
                'target': target,
              },
            ));
            simulatedRoleOverrideByRowId[rowId] = role;
          }
          label = role.isEmpty
              ? 'Clear role override on ${_rowLabel(rowById, rowId)}'
              : 'Set ${_rowLabel(rowById, rowId)} role to $role';
          verifiedLabel = role.isEmpty
              ? 'Cleared role override on ${_rowLabel(rowById, rowId)}'
              : label;
          break;
        case 'row.apply_phone_mic_cleanup':
          final rowId = args['row_id'] as int;
          final target = rowTarget(rowId);
          if (!runtimeCapabilities.contains('daw.audio_enhance') ||
              aiV3PhoneMicCleanupEffectIds
                  .any((effectId) => !effectById.containsKey(effectId))) {
            throw const AiV3PreparationException(
              'v3_phone_cleanup_unavailable',
            );
          }
          final audioClipIds = clipById.entries
              .where((entry) =>
                  entry.value['row_id'] == rowId &&
                  entry.value['kind'] == 'audio' &&
                  !unavailableClipIds.contains(entry.key))
              .map((entry) => entry.key)
              .toList(growable: false)
            ..sort();
          if (audioClipIds.isEmpty) {
            throw const AiV3PreparationException(
              'v3_phone_cleanup_audio_missing',
            );
          }
          commandActions.add(AssistantAction(
            type: 'v3_phone_mic_cleanup',
            data: <String, dynamic>{
              'operation': 'apply',
              'effect_ids': aiV3PhoneMicCleanupEffectIds,
              'audio_clip_ids': audioClipIds,
              'preset': aiV3PhoneMicCleanupPreset,
              'target': target,
            },
          ));
          label =
              'Clean all ${audioClipIds.length} audio clip${audioClipIds.length == 1 ? '' : 's'} on ${_rowLabel(rowById, rowId)}';
          verifiedLabel =
              'Cleaned all ${audioClipIds.length} audio clip${audioClipIds.length == 1 ? '' : 's'} on ${_rowLabel(rowById, rowId)}';
          break;
        case 'row.select':
          final rowId = args['row_id'] as int;
          final target = rowTarget(rowId);
          if (selection['selected_row_id'] == rowId) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'row_select',
              data: <String, dynamic>{
                'operation': 'select',
                'target': target,
              },
            ));
          }
          label = 'Select ${_rowLabel(rowById, rowId)}';
          verifiedLabel = 'Selected ${_rowLabel(rowById, rowId)}';
          break;
        case 'row.set_color':
          final rowId = args['row_id'] as int;
          final color = args['color'] as String;
          final target = rowTarget(rowId);
          if (rowById[rowId]?['color'] == color) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'row_color_edit',
              data: <String, dynamic>{
                'operation': color == 'none' ? 'clear' : 'set',
                'color': color,
                'target': target,
              },
            ));
          }
          label = color == 'none'
              ? 'Clear color on ${_rowLabel(rowById, rowId)}'
              : 'Set ${_rowLabel(rowById, rowId)} color to $color';
          verifiedLabel = color == 'none'
              ? 'Cleared color on ${_rowLabel(rowById, rowId)}'
              : label;
          break;
        case 'row.create':
          if (simulatedRowCount >= maximumRows) {
            throw const AiV3PreparationException('v3_row_capacity_exceeded');
          }
          final name = args['name'].toString().trim();
          final lane = Map<String, dynamic>.from(args['lane'] as Map);
          final laneKind = lane['kind'] as String;
          final instrumentId = lane['instrument_id']?.toString().trim() ?? '';
          if (laneKind == 'midi' && !instruments.contains(instrumentId)) {
            throw const AiV3PreparationException('v3_instrument_id_unknown');
          }
          final position = Map<String, dynamic>.from(args['position'] as Map);
          final positionKind = position['kind'] as String;
          Map<String, dynamic> target;
          String editorPosition;
          late final int predictedRowIndex;
          if (positionKind == 'end') {
            target = const <String, dynamic>{'scope': 'project'};
            editorPosition = 'end';
            predictedRowIndex = symbolicRowOrder.length;
          } else {
            final anchorId = position['row_id'] as int;
            if (deletedRowIds.contains(anchorId)) {
              throw const AiV3PreparationException('v3_row_id_unknown');
            }
            target = rowTarget(anchorId);
            editorPosition = positionKind == 'before' ? 'above' : 'below';
            final anchorIndex = symbolicRowOrder.indexOf(anchorId);
            if (anchorIndex < 0) {
              throw const AiV3PreparationException('v3_row_id_unknown');
            }
            predictedRowIndex = positionKind == 'before'
                ? anchorIndex
                : anchorIndex + 1;
          }
          final symbolicRowKey = '${command.commandId}.row';
          commandActions.add(
            AssistantAction(
              type: 'row_create',
              data: <String, dynamic>{
                if (referencedProducerCommandIds.contains(command.commandId))
                  'command_id': command.commandId,
                'operation': 'create',
                'position': editorPosition,
                'predicted_row_index': predictedRowIndex,
                'name': name,
                'lane_kind': laneKind == 'midi' ? 'instrument' : 'audio',
                if (instrumentId.isNotEmpty) 'instrument_id': instrumentId,
                'target': target,
              },
            ),
          );
          symbolicRowOrder.insert(predictedRowIndex, symbolicRowKey);
          simulatedRowCount += 1;
          hasPriorTopologyMutation = true;
          label = laneKind == 'midi'
              ? 'Create MIDI row $name'
              : 'Create audio row $name';
          verifiedLabel = laneKind == 'midi'
              ? 'Created MIDI row $name'
              : 'Created audio row $name';
          break;
        case 'row.delete':
          final resolved = resolveRowCommandTarget();
          final rowId = args['row_id'] as int?;
          if (rowId != null && deletedRowIds.contains(rowId)) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final target = resolved.target;
          if (simulatedRowCount <= 1) {
            throw const AiV3PreparationException(
              'v3_row_delete_last_remaining',
            );
          }
          commandActions.add(
            AssistantAction(
              type: 'row_delete',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'delete',
                'target': target,
              },
            ),
          );
          if (resolved.ref != null) {
            final rowKey = '${resolved.ref!.commandId}.${resolved.ref!.output}';
            resolved.symbolic!.available = false;
            symbolicRowOrder.remove(rowKey);
            for (final resource in symbolicResources.values) {
              if (resource.parentRowResourceKey == rowKey) {
                resource.available = false;
              }
            }
            final deletedGroupId = simulatedGroupIdByRow.remove(rowKey);
            if (deletedGroupId != null) {
              final deletedGroup = simulatedGroupsById[deletedGroupId];
              final remaining =
                  (deletedGroup?['member_row_ids'] as List? ?? const <Object>[])
                      .where((candidate) => candidate != rowKey)
                      .toList(growable: false);
              if (remaining.length < 2) {
                simulatedGroupsById.remove(deletedGroupId);
                for (final memberKey in remaining) {
                  simulatedGroupIdByRow.remove(memberKey);
                }
                for (final resource in symbolicResources.values) {
                  if (resource.kind == AiV3ResourceKind.group &&
                      resource.groupId == deletedGroupId) {
                    resource.available = false;
                  }
                }
              } else {
                simulatedGroupsById[deletedGroupId] = <String, dynamic>{
                  ...deletedGroup!,
                  'member_row_ids': remaining,
                };
                for (final resource in symbolicResources.values) {
                  if (resource.kind == AiV3ResourceKind.group &&
                      resource.groupId == deletedGroupId) {
                    resource.groupMemberKeys = List<Object>.from(remaining);
                  }
                }
              }
            }
          } else {
            deletedRowIds.add(rowId!);
            for (final resource in symbolicResources.values) {
              if (resource.rowId == rowId) resource.available = false;
            }
            simulatedRowOrder.remove(rowId);
            symbolicRowOrder.remove(rowId);
            final deletedGroupId = simulatedGroupIdByRow.remove(rowId);
            if (deletedGroupId != null) {
              final deletedGroup = simulatedGroupsById[deletedGroupId];
              final remaining =
                  (deletedGroup?['member_row_ids'] as List? ?? const <Object>[])
                      .whereType<int>()
                      .where((candidate) => candidate != rowId)
                      .toList(growable: false);
              if (remaining.length < 2) {
                simulatedGroupsById.remove(deletedGroupId);
                for (final memberId in remaining) {
                  simulatedGroupIdByRow.remove(memberId);
                }
              } else {
                simulatedGroupsById[deletedGroupId] = <String, dynamic>{
                  ...deletedGroup!,
                  'member_row_ids': remaining,
                };
              }
            }
          }
          simulatedRowCount -= 1;
          hasPriorTopologyMutation = true;
          label = 'Delete ${resolved.label}';
          verifiedLabel = 'Deleted ${resolved.label}';
          break;
        case 'group.create':
          final usesTypedMembers = args['members'] is List;
          final rawMembers = usesTypedMembers
              ? args['members'] as List
              : (args['row_ids'] as List)
                    .map((rowId) => <String, dynamic>{'row_id': rowId})
                    .toList(growable: false);
          final resolvedMembers =
              <({Object key, Map<String, dynamic> target})>[];
          for (final rawMember in rawMembers) {
            final member = Map<String, dynamic>.from(rawMember as Map);
            if (member['row_ref'] is Map) {
              final resolved = symbolicRowTarget(
                member['row_ref'],
                acceptedKinds: const <AiV3ResourceKind>{
                  AiV3ResourceKind.audioRow,
                  AiV3ResourceKind.midiRow,
                },
              );
              resolvedMembers.add((
                key: '${resolved.ref.commandId}.${resolved.ref.output}',
                target: generatedRowActionTarget(
                  resolved.ref,
                  resolved.resource,
                ),
              ));
            } else {
              final rowId = member['row_id'] as int;
              resolvedMembers.add((key: rowId, target: rowTarget(rowId)));
            }
          }
          final orderedMembers = resolvedMembers.toList(growable: false)
            ..sort(
              (left, right) => symbolicRowOrder
                  .indexOf(left.key)
                  .compareTo(symbolicRowOrder.indexOf(right.key)),
            );
          if (orderedMembers.any(
            (member) => !symbolicRowOrder.contains(member.key),
          )) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final orderedKeys = orderedMembers
              .map((member) => member.key)
              .toList();
          final requestedSet = orderedKeys.toSet();
          final matchingGroup = simulatedGroupsById.values.where((group) {
            final members = (group['member_row_ids'] as List? ?? const [])
                .toSet();
            return members.length == requestedSet.length &&
                members.containsAll(requestedSet);
          }).firstOrNull;
          final requestedName = args['name']?.toString().trim() ?? '';
          if (matchingGroup != null) {
            final existingName = matchingGroup['name']?.toString().trim() ?? '';
            if (requestedName.isEmpty || requestedName == existingName) {
              receiptStatus = 'already_satisfied';
              label = 'Keep existing group $existingName';
              verifiedLabel = 'Kept existing group $existingName';
              break;
            }
            throw const AiV3PreparationException(
              'v3_group_members_already_grouped',
            );
          }
          var groupId = 'v3_group_${const Uuid().v4()}';
          while (simulatedGroupsById.containsKey(groupId)) {
            groupId = 'v3_group_${const Uuid().v4()}';
          }
          final name = requestedName.isEmpty
              ? 'Group ${simulatedGroupsById.length + 1}'
              : requestedName;
          final affectedGroupIds = <String>{
            for (final key in orderedKeys)
              if (simulatedGroupIdByRow[key] != null)
                simulatedGroupIdByRow[key]!,
          };
          final dissolvedGroupIds = <String>[];
          for (final affectedId in affectedGroupIds) {
            final existing = simulatedGroupsById[affectedId]!;
            final oldMembers = (existing['member_row_ids'] as List? ?? const [])
                .toList(growable: false);
            final remaining = oldMembers
                .where((rowId) => !requestedSet.contains(rowId))
                .toList(growable: false);
            if (remaining.length < 2) {
              simulatedGroupsById.remove(affectedId);
              dissolvedGroupIds.add(affectedId);
              for (final key in oldMembers) {
                simulatedGroupIdByRow.remove(key);
              }
            } else {
              simulatedGroupsById[affectedId] = <String, dynamic>{
                ...existing,
                'member_row_ids': remaining,
              };
              for (final key in oldMembers) {
                if (!remaining.contains(key)) {
                  simulatedGroupIdByRow.remove(key);
                }
              }
            }
          }
          for (final key in orderedKeys) {
            simulatedGroupIdByRow[key] = groupId;
          }
          simulatedGroupsById[groupId] = <String, dynamic>{
            'group_id': groupId,
            'name': name,
            'member_row_ids': orderedKeys,
            'collapsed': false,
          };
          final insertionIndex = orderedKeys
              .map(symbolicRowOrder.indexOf)
              .reduce((left, right) => math.min(left, right).toInt());
          symbolicRowOrder.removeWhere(requestedSet.contains);
          symbolicRowOrder.insertAll(insertionIndex, orderedKeys);
          if (orderedKeys.every((key) => key is int)) {
            simulatedRowOrder
              ..clear()
              ..addAll(symbolicRowOrder.whereType<int>());
          }
          commandActions.add(
            AssistantAction(
              type: 'v3_group_edit',
              data: <String, dynamic>{
                'operation': 'create',
                if (usesTypedMembers) 'command_id': command.commandId,
                'group_id': groupId,
                'name': name,
                if (usesTypedMembers)
                  'member_targets': orderedMembers
                      .map((member) => member.target)
                      .toList(growable: false),
                if (!usesTypedMembers)
                  'row_ids': orderedKeys.whereType<int>().toList(),
                if (!usesTypedMembers)
                  'expected_row_order': List<int>.from(simulatedRowOrder),
                'affected_group_ids': affectedGroupIds.toList()..sort(),
                'dissolved_group_ids': dissolvedGroupIds..sort(),
              },
            ),
          );
          symbolicResources['${command.commandId}.group'] =
              _AiV3SymbolicResource(
                kind: AiV3ResourceKind.group,
                startMs: 0.0,
                groupId: groupId,
                groupMemberKeys: List<Object>.from(orderedKeys),
                groupCollapsed: false,
              );
          hasPriorTopologyMutation = true;
          label = dissolvedGroupIds.isEmpty
              ? 'Create group $name from ${orderedKeys.length} rows'
              : 'Create group $name and dissolve ${dissolvedGroupIds.length} superseded group(s)';
          verifiedLabel = dissolvedGroupIds.isEmpty
              ? 'Created group $name from ${orderedKeys.length} rows'
              : 'Created group $name and dissolved ${dissolvedGroupIds.length} superseded group(s)';
          break;
        case 'group.remove_row':
          final groupRef = args['group_ref'] is Map
              ? AiV3ResourceRef.fromJson(args['group_ref'])
              : null;
          final groupSymbolic = groupRef == null
              ? null
              : symbolicResources['${groupRef.commandId}.${groupRef.output}'];
          final groupId = groupRef == null
              ? args['group_id'].toString().trim()
              : groupSymbolic?.groupId ?? '';
          if (groupRef != null &&
              (groupSymbolic == null ||
                  !groupSymbolic.available ||
                  groupSymbolic.kind != AiV3ResourceKind.group)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final rowRef = args['row_ref'] is Map
              ? AiV3ResourceRef.fromJson(args['row_ref'])
              : null;
          final rowSymbolic = rowRef == null
              ? null
              : symbolicRowTarget(
                  args['row_ref'],
                  acceptedKinds: const <AiV3ResourceKind>{
                    AiV3ResourceKind.audioRow,
                    AiV3ResourceKind.midiRow,
                  },
                );
          final memberKey = rowRef == null
              ? args['row_id'] as int
              : '${rowRef.commandId}.${rowRef.output}';
          final group = simulatedGroupsById[groupId];
          if (group == null) {
            throw const AiV3PreparationException('v3_group_id_unknown');
          }
          final oldMembers =
              (group['member_row_ids'] as List? ?? const <Object>[]).toList(
                growable: false,
              );
          if (!oldMembers.contains(memberKey) ||
              simulatedGroupIdByRow[memberKey] != groupId) {
            throw const AiV3PreparationException(
              'v3_group_membership_mismatch',
            );
          }
          final remaining = oldMembers
              .where((candidate) => candidate != memberKey)
              .toList(growable: false);
          final dissolves = remaining.length < 2;
          if (dissolves) {
            simulatedGroupsById.remove(groupId);
            for (final key in oldMembers) {
              simulatedGroupIdByRow.remove(key);
            }
            if (groupSymbolic != null) groupSymbolic.available = false;
          } else {
            simulatedGroupsById[groupId] = <String, dynamic>{
              ...group,
              'member_row_ids': remaining,
            };
            simulatedGroupIdByRow.remove(memberKey);
            if (groupSymbolic != null) {
              groupSymbolic.groupMemberKeys = List<Object>.from(remaining);
            }
          }
          commandActions.add(
            AssistantAction(
              type: 'v3_group_edit',
              data: <String, dynamic>{
                'operation': 'remove_row',
                if (groupRef == null) 'group_id': groupId,
                if (groupRef != null)
                  'target': <String, dynamic>{
                    'scope': 'group',
                    'resource_ref': groupRef.toJson(),
                  },
                if (groupRef != null) 'resource_consumer_type': command.type,
                'row_target': rowRef == null
                    ? rowTarget(args['row_id'] as int)
                    : generatedRowActionTarget(rowRef, rowSymbolic!.resource),
                'dissolves_group': dissolves,
              },
            ),
          );
          hasPriorTopologyMutation = true;
          label = dissolves
              ? 'Remove $memberKey and dissolve ${group['name']}'
              : 'Remove $memberKey from ${group['name']}';
          verifiedLabel = dissolves
              ? 'Removed $memberKey and dissolved ${group['name']}'
              : 'Removed $memberKey from ${group['name']}';
          break;
        case 'group.set_collapsed':
          final groupRef = args['group_ref'] is Map
              ? AiV3ResourceRef.fromJson(args['group_ref'])
              : null;
          final groupSymbolic = groupRef == null
              ? null
              : symbolicResources['${groupRef.commandId}.${groupRef.output}'];
          final groupId = groupRef == null
              ? args['group_id'].toString().trim()
              : groupSymbolic?.groupId ?? '';
          if (groupRef != null &&
              (groupSymbolic == null ||
                  !groupSymbolic.available ||
                  groupSymbolic.kind != AiV3ResourceKind.group)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final collapsed = args['collapsed'] as bool;
          final group = simulatedGroupsById[groupId];
          if (group == null) {
            throw const AiV3PreparationException('v3_group_id_unknown');
          }
          if (group['collapsed'] == collapsed) {
            receiptStatus = 'already_satisfied';
          } else {
            simulatedGroupsById[groupId] = <String, dynamic>{
              ...group,
              'collapsed': collapsed,
            };
            commandActions.add(
              AssistantAction(
                type: 'v3_group_edit',
                data: <String, dynamic>{
                  'operation': 'set_collapsed',
                  if (groupRef == null) 'group_id': groupId,
                  if (groupRef != null) 'resource_consumer_type': command.type,
                  if (groupRef != null)
                    'target': <String, dynamic>{
                      'scope': 'group',
                      'resource_ref': groupRef.toJson(),
                    },
                  'collapsed': collapsed,
                },
              ),
            );
            if (groupSymbolic != null) {
              groupSymbolic.groupCollapsed = collapsed;
            }
          }
          label = '${collapsed ? 'Collapse' : 'Expand'} ${group['name']}';
          verifiedLabel =
              '${collapsed ? 'Collapsed' : 'Expanded'} ${group['name']}';
          break;
        case 'clip.move_by_beats':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final deltaMs =
              (args['delta_beats'] as num).toDouble() *
              60000.0 /
              (clipRef == null ? bpm : symbolicBpm);
          if (symbolic != null) symbolic.startMs += deltaMs;
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'move',
                'delta_ms': deltaMs,
                if (symbolic != null) 'predicted_start_ms': symbolic.startMs,
                'target': clipRef == null
                    ? clipTarget(clipId!)
                    : <String, dynamic>{
                        'scope': 'clip',
                        'resource_ref': clipRef.toJson(),
                      },
              },
            ),
          );
          label = clipRef == null
              ? 'Move ${_clipLabel(clipById, clipId!)} by ${args['delta_beats']} beats'
              : 'Move ${clipRef.commandId}.${clipRef.output} by ${args['delta_beats']} beats';
          verifiedLabel = clipRef == null
              ? 'Moved ${_clipLabel(clipById, clipId!)} by ${args['delta_beats']} beats'
              : 'Moved ${clipRef.commandId}.${clipRef.output} by ${args['delta_beats']} beats';
          break;
        case 'clip.trim_to_range':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final target = clipRef == null
              ? clipTarget(clipId!, requireAudio: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final currentStartBeat = (clip?['start_beat'] as num?)?.toDouble();
          final currentStartMs =
              symbolic?.startMs ??
              (currentStartBeat == null
                  ? null
                  : currentStartBeat * 60000.0 / symbolicBpm);
          final currentLengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble() ??
              (clip?['length_beats'] as num?)?.toDouble();
          final currentDurationMs =
              symbolic?.durationMs ??
              (currentLengthBeats == null
                  ? null
                  : currentLengthBeats * 60000.0 / symbolicBpm);
          if (currentStartMs == null ||
              !currentStartMs.isFinite ||
              (clipRef == null && currentDurationMs == null) ||
              (currentDurationMs != null &&
                  (!currentDurationMs.isFinite || currentDurationMs <= 0))) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          final startBeat = (args['start_beat'] as num).toDouble();
          final endBeat = (args['end_beat'] as num).toDouble();
          final requestedStartMs = startBeat * 60000.0 / symbolicBpm;
          final requestedEndMs = endBeat * 60000.0 / symbolicBpm;
          final currentEndMs = currentDurationMs == null
              ? null
              : currentStartMs + currentDurationMs;
          if (requestedStartMs < currentStartMs - 0.001 ||
              (currentEndMs != null && requestedEndMs > currentEndMs + 0.001) ||
              requestedEndMs - requestedStartMs < 50.0) {
            throw const AiV3PreparationException('v3_clip_trim_bounds_invalid');
          }
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: clipRef == null
                  ? <String, dynamic>{
                      'operation': 'trim',
                      'delta_trim_start_ms': requestedStartMs - currentStartMs,
                      'delta_trim_end_ms': requestedEndMs - currentEndMs!,
                      'new_start_ms': requestedStartMs,
                      'target': target,
                    }
                  : <String, dynamic>{
                      'command_id': command.commandId,
                      'resource_consumer_type': command.type,
                      'operation': 'trim',
                      'requested_start_ms': requestedStartMs,
                      'requested_end_ms': requestedEndMs,
                      'predicted_input_start_ms': currentStartMs,
                      if (currentEndMs != null)
                        'predicted_input_end_ms': currentEndMs,
                      if (currentEndMs != null)
                        'delta_trim_start_ms':
                            requestedStartMs - currentStartMs,
                      if (currentEndMs != null)
                        'delta_trim_end_ms': requestedEndMs - currentEndMs,
                      'new_start_ms': requestedStartMs,
                      'target': target,
                    },
            ),
          );
          if (symbolic != null) {
            symbolic
              ..startMs = requestedStartMs
              ..durationMs = requestedEndMs - requestedStartMs;
          }
          label = clipRef == null
              ? 'Trim ${_clipLabel(clipById, clipId!)} to beats $startBeat–$endBeat'
              : 'Trim ${clipRef.commandId}.${clipRef.output} to beats $startBeat–$endBeat';
          verifiedLabel = clipRef == null
              ? 'Trimmed ${_clipLabel(clipById, clipId!)} to beats $startBeat–$endBeat'
              : 'Trimmed ${clipRef.commandId}.${clipRef.output} to beats $startBeat–$endBeat';
          break;
        case 'clip.split_at':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final kind =
              symbolic?.kind ??
              switch (clip?['kind']) {
                'audio' => AiV3ResourceKind.audioClip,
                'midi' => AiV3ResourceKind.midiClip,
                _ => null,
              };
          final currentStartBeat = (clip?['start_beat'] as num?)?.toDouble();
          final currentStartMs =
              symbolic?.startMs ??
              (currentStartBeat == null
                  ? null
                  : currentStartBeat * 60000.0 / symbolicBpm);
          final currentLengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble() ??
              (clip?['length_beats'] as num?)?.toDouble();
          final currentDurationFollowsTempo =
              symbolic?.durationFollowsTempo ??
              (kind == AiV3ResourceKind.midiClip ||
                  clip?['stretch_to_project_tempo'] == true ||
                  (kind == AiV3ResourceKind.audioClip &&
                      projectAudioForcedTempoFollow));
          final currentDurationMs =
              symbolic?.durationMs ??
              (currentLengthBeats == null
                  ? null
                  : currentLengthBeats *
                        60000.0 /
                        (currentDurationFollowsTempo ? symbolicBpm : bpm));
          if (kind == null ||
              currentStartMs == null ||
              !currentStartMs.isFinite ||
              (currentDurationMs != null &&
                  (!currentDurationMs.isFinite || currentDurationMs <= 0))) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          final atBeat = (args['at_beat'] as num).toDouble();
          final cutMs = atBeat * 60000.0 / symbolicBpm;
          final deferredRuntimeBounds =
              symbolic?.boundsRuntimeAuthoritative == true;
          final leftDurationMs = deferredRuntimeBounds
              ? null
              : cutMs - currentStartMs;
          final rightDurationMs =
              deferredRuntimeBounds || currentDurationMs == null
              ? null
              : currentDurationMs - leftDurationMs!;
          if ((leftDurationMs != null && leftDurationMs < 50.0) ||
              (rightDurationMs != null && rightDurationMs < 50.0)) {
            throw const AiV3PreparationException('v3_clip_split_point_invalid');
          }
          if (simulatedClipCount + 1 > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'cut',
                'cut_ms': cutMs,
                'predicted_input_start_ms': currentStartMs,
                if (currentDurationMs != null)
                  'predicted_input_end_ms': currentStartMs + currentDurationMs,
                'target': clipRef == null
                    ? clipTarget(clipId!)
                    : <String, dynamic>{
                        'scope': 'clip',
                        'resource_ref': clipRef.toJson(),
                      },
              },
            ),
          );
          if (symbolic != null) symbolic.available = false;
          final inheritedPitch =
              symbolic?.pitchSemitones ??
              (clip?['pitch_semitones'] as num?)?.toDouble();
          final inheritedNotes =
              symbolic?.midiNotes ??
              (kind == AiV3ResourceKind.midiClip
                  ? _normalizedMidiNotes(
                      clip?['midi_notes'] as List? ?? const <Object>[],
                    )
                  : null);
          symbolicResources['${command.commandId}.left_clip'] =
              _AiV3SymbolicResource(
                kind: kind,
                startMs: currentStartMs,
                durationMs: leftDurationMs,
                durationFollowsTempo: currentDurationFollowsTempo,
                rowId: symbolic?.rowId ?? clip?['row_id'] as int?,
                rowIndex:
                    symbolic?.rowIndex ??
                    rowById[clip?['row_id']]?['display_index'] as int?,
                parentRowResourceKey: symbolic?.parentRowResourceKey,
                pitchSemitones: inheritedPitch,
                sourceTempoBpm:
                    symbolic?.sourceTempoBpm ??
                    (clip?['source_tempo_bpm'] as num?)?.toDouble(),
                tempoFollowMode:
                    symbolic?.tempoFollowMode ??
                    (clip?['stretch_to_project_tempo'] == true
                        ? (clip?['tempo_stretch_preserve_pitch'] == true
                              ? 'preserve_pitch'
                              : 'repitch')
                        : 'off'),
                tempoPreservePitch:
                    symbolic?.tempoPreservePitch ??
                    (clip?['tempo_stretch_preserve_pitch'] == true),
                midiNotes: inheritedNotes
                    ?.map((note) => Map<String, dynamic>.from(note))
                    .toList(growable: false),
                midiNotesRuntimeAuthoritative:
                    symbolic?.midiNotesRuntimeAuthoritative == true,
                boundsRuntimeAuthoritative:
                    deferredRuntimeBounds || currentDurationMs == null,
              );
          symbolicResources['${command.commandId}.right_clip'] =
              _AiV3SymbolicResource(
                kind: kind,
                startMs: cutMs,
                durationMs: rightDurationMs,
                durationFollowsTempo: currentDurationFollowsTempo,
                rowId: symbolic?.rowId ?? clip?['row_id'] as int?,
                rowIndex:
                    symbolic?.rowIndex ??
                    rowById[clip?['row_id']]?['display_index'] as int?,
                parentRowResourceKey: symbolic?.parentRowResourceKey,
                pitchSemitones: inheritedPitch,
                sourceTempoBpm:
                    symbolic?.sourceTempoBpm ??
                    (clip?['source_tempo_bpm'] as num?)?.toDouble(),
                tempoFollowMode:
                    symbolic?.tempoFollowMode ??
                    (clip?['stretch_to_project_tempo'] == true
                        ? (clip?['tempo_stretch_preserve_pitch'] == true
                              ? 'preserve_pitch'
                              : 'repitch')
                        : 'off'),
                tempoPreservePitch:
                    symbolic?.tempoPreservePitch ??
                    (clip?['tempo_stretch_preserve_pitch'] == true),
                midiNotes: inheritedNotes
                    ?.map((note) => Map<String, dynamic>.from(note))
                    .toList(growable: false),
                midiNotesRuntimeAuthoritative:
                    symbolic?.midiNotesRuntimeAuthoritative == true,
                boundsRuntimeAuthoritative:
                    deferredRuntimeBounds || currentDurationMs == null,
              );
          simulatedClipCount += 1;
          label = clipRef == null
              ? 'Split ${_clipLabel(clipById, clipId!)} at beat $atBeat'
              : 'Split ${clipRef.commandId}.${clipRef.output} at beat $atBeat';
          verifiedLabel = label;
          break;
        case 'clip.duplicate_to':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          if (clipRef == null && hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final kind =
              symbolic?.kind ??
              switch (clip?['kind']) {
                'audio' => AiV3ResourceKind.audioClip,
                'midi' => AiV3ResourceKind.midiClip,
                _ => null,
              };
          if (kind == null) {
            throw const AiV3PreparationException('v3_clip_id_unknown');
          }
          final target = clipRef == null
              ? clipTarget(clipId!)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final destinationRowId = args['destination_row_id'] as int?;
          final destinationRow = destinationRowId == null
              ? null
              : rowById[destinationRowId];
          if (destinationRowId != null) {
            rowTarget(destinationRowId);
            if (destinationRow == null) {
              throw const AiV3PreparationException('v3_row_id_unknown');
            }
            final destinationIsMidi =
                destinationRow['lane_kind'] == 'instrument';
            if ((kind == AiV3ResourceKind.midiClip) != destinationIsMidi) {
              throw const AiV3PreparationException(
                'v3_clip_destination_lane_mismatch',
              );
            }
          }
          if (simulatedClipCount + 1 > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          final startBeat = (args['start_beat'] as num).toDouble();
          final startMs = startBeat * 60000.0 / symbolicBpm;
          final sourceStartBeat = (clip?['start_beat'] as num?)?.toDouble();
          final sourceStartMs =
              symbolic?.startMs ??
              (sourceStartBeat == null
                  ? null
                  : sourceStartBeat * 60000.0 / symbolicBpm);
          final sourceLengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble() ??
              (clip?['length_beats'] as num?)?.toDouble();
          final durationMs =
              symbolic?.durationMs ??
              (sourceLengthBeats == null
                  ? null
                  : sourceLengthBeats *
                        60000.0 /
                        ((kind == AiV3ResourceKind.midiClip ||
                                clip?['stretch_to_project_tempo'] == true ||
                                (kind == AiV3ResourceKind.audioClip &&
                                    projectAudioForcedTempoFollow))
                            ? symbolicBpm
                            : bpm));
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                if (referencedProducerCommandIds.contains(command.commandId) ||
                    clipRef != null)
                  'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'duplicate',
                'paste_start_ms': startMs,
                if (destinationRow != null)
                  'row_index': destinationRow['display_index'],
                if (destinationRow != null)
                  'new_row_index': destinationRow['display_index'],
                if (clipRef != null && destinationRowId != null)
                  'row_id': destinationRowId,
                if (sourceStartMs != null)
                  'predicted_input_start_ms': sourceStartMs,
                if (durationMs != null)
                  'predicted_input_end_ms': sourceStartMs! + durationMs,
                'target': target,
              },
            ),
          );
          symbolicResources['${command.commandId}.copy_clip'] =
              _AiV3SymbolicResource(
                kind: kind,
                startMs: startMs,
                durationMs: durationMs,
                durationFollowsTempo:
                    symbolic?.durationFollowsTempo ??
                    (kind == AiV3ResourceKind.midiClip ||
                        clip?['stretch_to_project_tempo'] == true ||
                        (kind == AiV3ResourceKind.audioClip &&
                            projectAudioForcedTempoFollow)),
                rowId:
                    destinationRowId ??
                    symbolic?.rowId ??
                    clip?['row_id'] as int?,
                rowIndex:
                    destinationRow?['display_index'] as int? ??
                    symbolic?.rowIndex ??
                    rowById[clip?['row_id']]?['display_index'] as int?,
                parentRowResourceKey: destinationRowId == null
                    ? symbolic?.parentRowResourceKey
                    : null,
                pitchSemitones:
                    symbolic?.pitchSemitones ??
                    (clip?['pitch_semitones'] as num?)?.toDouble(),
                sourceTempoBpm:
                    symbolic?.sourceTempoBpm ??
                    (clip?['source_tempo_bpm'] as num?)?.toDouble(),
                tempoFollowMode:
                    symbolic?.tempoFollowMode ??
                    (clip?['stretch_to_project_tempo'] == true
                        ? (clip?['tempo_stretch_preserve_pitch'] == true
                              ? 'preserve_pitch'
                              : 'repitch')
                        : 'off'),
                tempoPreservePitch:
                    symbolic?.tempoPreservePitch ??
                    (clip?['tempo_stretch_preserve_pitch'] == true),
                midiNotes: symbolic?.midiNotes == null
                    ? (kind == AiV3ResourceKind.midiClip
                          ? _normalizedMidiNotes(
                              clip?['midi_notes'] as List? ?? const <Object>[],
                            )
                          : null)
                    : symbolic!.midiNotes!
                          .map((note) => Map<String, dynamic>.from(note))
                          .toList(growable: false),
                midiNotesRuntimeAuthoritative:
                    symbolic?.midiNotesRuntimeAuthoritative == true,
                boundsRuntimeAuthoritative:
                    symbolic?.boundsRuntimeAuthoritative == true ||
                    durationMs == null,
              );
          simulatedClipCount += 1;
          label = clipRef == null
              ? 'Duplicate ${_clipLabel(clipById, clipId!)} to ${_rowLabel(rowById, destinationRowId!)} at beat $startBeat'
              : 'Duplicate ${clipRef.commandId}.${clipRef.output} at beat $startBeat';
          verifiedLabel = clipRef == null
              ? 'Duplicated ${_clipLabel(clipById, clipId!)} to ${_rowLabel(rowById, destinationRowId!)} at beat $startBeat'
              : 'Duplicated ${clipRef.commandId}.${clipRef.output} at beat $startBeat';
          break;
        case 'clip.delete':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'delete',
                'target': clipRef == null
                    ? clipTarget(clipId!)
                    : <String, dynamic>{
                        'scope': 'clip',
                        'resource_ref': clipRef.toJson(),
                      },
              },
            ),
          );
          if (symbolic != null) {
            symbolic.available = false;
          } else {
            unavailableClipIds.add(clipId!);
          }
          simulatedClipCount -= 1;
          label = clipRef == null
              ? 'Delete ${_clipLabel(clipById, clipId!)}'
              : 'Delete ${clipRef.commandId}.${clipRef.output}';
          verifiedLabel = clipRef == null
              ? 'Deleted ${_clipLabel(clipById, clipId!)}'
              : 'Deleted ${clipRef.commandId}.${clipRef.output}';
          break;
        case 'clip.glue':
          final usesTypedSources = args['sources'] is List;
          if (!usesTypedSources && hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_clip_id_unknown');
          }
          final rawSources = usesTypedSources
              ? args['sources'] as List
              : (args['clip_ids'] as List)
                    .map((clipId) => <String, dynamic>{'clip_id': clipId})
                    .toList(growable: false);
          final preparedSources = <Map<String, dynamic>>[];
          final stableIds = <String>[];
          final referencedResources =
              <({AiV3ResourceRef ref, _AiV3SymbolicResource resource})>[];
          final rowKeys = <String>{};
          final startsMs = <double>[];
          final endsMs = <double>[];
          var hasDeferredBounds = false;
          for (final rawSource in rawSources) {
            final source = Map<String, dynamic>.from(rawSource as Map);
            if (source['clip_ref'] is Map) {
              final ref = AiV3ResourceRef.fromJson(source['clip_ref']);
              final symbolic =
                  symbolicResources['${ref.commandId}.${ref.output}'];
              if (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip ||
                  symbolic.rowIndex == null) {
                throw const AiV3PreparationException(
                  'v3_resource_ref_unavailable',
                );
              }
              referencedResources.add((ref: ref, resource: symbolic));
              preparedSources.add(<String, dynamic>{
                'resource_ref': ref.toJson(),
              });
              rowKeys.add(
                symbolic.parentRowResourceKey ??
                    (symbolic.rowId != null
                        ? 'stable:${symbolic.rowId}'
                        : 'index:${symbolic.rowIndex}'),
              );
              startsMs.add(symbolic.startMs);
              if (symbolic.durationMs == null ||
                  symbolic.boundsRuntimeAuthoritative) {
                hasDeferredBounds = true;
              } else {
                endsMs.add(symbolic.startMs + symbolic.durationMs!);
              }
              continue;
            }
            final clipId = source['clip_id'].toString().trim();
            if (previouslyMutatedClipIds.contains(clipId)) {
              throw const AiV3PreparationException(
                'v3_clip_glue_source_already_mutated',
              );
            }
            clipTarget(clipId, requireAudio: true);
            final clip = clipById[clipId]!;
            final startBeat = (clip['start_beat'] as num?)?.toDouble();
            final lengthBeats =
                (clip['timeline_length_beats'] as num?)?.toDouble() ??
                (clip['length_beats'] as num?)?.toDouble();
            if (startBeat == null ||
                lengthBeats == null ||
                !startBeat.isFinite ||
                !lengthBeats.isFinite) {
              throw const AiV3PreparationException('v3_clip_bounds_missing');
            }
            final followsTempo =
                clip['stretch_to_project_tempo'] == true ||
                projectAudioForcedTempoFollow;
            final startMs = startBeat * 60000.0 / symbolicBpm;
            final durationMs =
                lengthBeats * 60000.0 / (followsTempo ? symbolicBpm : bpm);
            stableIds.add(clipId);
            preparedSources.add(<String, dynamic>{'clip_id': clipId});
            rowKeys.add('stable:${clip['row_id']}');
            startsMs.add(startMs);
            endsMs.add(startMs + durationMs);
          }
          if (rowKeys.length != 1) {
            throw const AiV3PreparationException('v3_clip_glue_row_mismatch');
          }
          final predictedStartMs = startsMs.reduce(math.min);
          final predictedEndMs = hasDeferredBounds
              ? null
              : endsMs.reduce(math.max);
          if (predictedEndMs != null &&
              predictedEndMs - predictedStartMs <= 50.0) {
            throw const AiV3PreparationException('v3_clip_glue_bounds_invalid');
          }
          final firstReferenced = referencedResources.firstOrNull?.resource;
          final stableRowId = stableIds.isEmpty
              ? null
              : clipById[stableIds.first]?['row_id'] as int?;
          final rowId = firstReferenced?.rowId ?? stableRowId;
          final rowIndex =
              firstReferenced?.rowIndex ??
              (rowId == null ? null : rowById[rowId]?['display_index'] as int?);
          final labelValue = args['label']?.toString().trim() ?? '';
          final legacyOrderedIds = stableIds.toList(growable: false)
            ..sort((left, right) {
              final leftStart =
                  (clipById[left]?['start_beat'] as num?)?.toDouble() ?? 0.0;
              final rightStart =
                  (clipById[right]?['start_beat'] as num?)?.toDouble() ?? 0.0;
              final comparison = leftStart.compareTo(rightStart);
              return comparison != 0 ? comparison : left.compareTo(right);
            });
          commandActions.add(
            AssistantAction(
              type: 'v3_clip_glue',
              data: usesTypedSources
                  ? <String, dynamic>{
                      'command_id': command.commandId,
                      'sources': preparedSources,
                      'label': labelValue.isEmpty ? 'Glued Clip' : labelValue,
                      'predicted_start_ms': predictedStartMs,
                      if (predictedEndMs != null)
                        'predicted_duration_ms':
                            predictedEndMs - predictedStartMs,
                      'target': <String, dynamic>{
                        'scope': 'row',
                        if (rowId != null) 'row_id': rowId,
                        if (rowIndex != null) 'row_index': rowIndex,
                      },
                    }
                  : <String, dynamic>{
                      'source_clip_ids': legacyOrderedIds,
                      'label': labelValue.isEmpty ? 'Glued Clip' : labelValue,
                      'start_ms': predictedStartMs,
                      'duration_ms': predictedEndMs! - predictedStartMs,
                      'target': <String, dynamic>{
                        ...rowTarget(rowId!),
                        'source_clip_ids': legacyOrderedIds,
                      },
                    },
            ),
          );
          for (final source in referencedResources) {
            source.resource.available = false;
          }
          unavailableClipIds.addAll(stableIds);
          previouslyMutatedClipIds.addAll(stableIds);
          if (usesTypedSources) {
            symbolicResources['${command.commandId}.glued_clip'] =
                _AiV3SymbolicResource(
                  kind: AiV3ResourceKind.audioClip,
                  startMs: predictedStartMs,
                  durationMs: predictedEndMs == null
                      ? null
                      : predictedEndMs - predictedStartMs,
                  durationFollowsTempo: false,
                  rowId: rowId,
                  rowIndex: rowIndex,
                  parentRowResourceKey: firstReferenced?.parentRowResourceKey,
                  pitchSemitones: 0.0,
                  sourceTempoBpm: 0.0,
                  tempoFollowMode: 'off',
                  tempoPreservePitch: false,
                  boundsRuntimeAuthoritative: true,
                );
          }
          simulatedClipCount -= rawSources.length - 1;
          hasPriorTopologyMutation = true;
          label =
              'Glue ${rawSources.length} audio clips as ${labelValue.isEmpty ? 'Glued Clip' : labelValue}';
          verifiedLabel =
              'Glued ${rawSources.length} audio clips as ${labelValue.isEmpty ? 'Glued Clip' : labelValue}';
          break;
        case 'clip.separate_stems':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          if (clipRef == null && hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_clip_id_unknown');
          }
          if (!runtimeCapabilities.contains('daw.stem_separate')) {
            throw const AiV3PreparationException(
              'v3_stem_separation_unavailable',
            );
          }
          if (simulatedRowCount + 2 > maximumRows) {
            throw const AiV3PreparationException(
              'v3_row_capacity_exceeded',
            );
          }
          if (simulatedClipCount + 2 > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final target = clipRef == null
              ? clipTarget(clipId!, requireAudio: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final rowId = symbolic?.rowId ?? clip?['row_id'];
          final startBeat = (clip?['start_beat'] as num?)?.toDouble();
          final lengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble();
          final sourcePath = clip?['source_file']?.toString().trim() ?? '';
          final startMs =
              symbolic?.startMs ??
              (startBeat == null ? null : startBeat * 60000.0 / symbolicBpm);
          final durationMs =
              symbolic?.durationMs ??
              (lengthBeats == null
                  ? null
                  : lengthBeats * 60000.0 / symbolicBpm);
          if (clipRef == null &&
              (rowId is! int ||
                  startMs == null ||
                  !startMs.isFinite ||
                  durationMs == null ||
                  !durationMs.isFinite ||
                  durationMs <= 0)) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          if (clipRef == null && sourcePath.isEmpty) {
            throw const AiV3PreparationException('v3_stem_source_unreadable');
          }
          final sourceAvailable = clip?['source_available'];
          final sourceFile = File(sourcePath);
          final absoluteSourceUnavailable = sourceFile.isAbsolute &&
              (!sourceFile.existsSync() || sourceFile.lengthSync() <= 44);
          if (clipRef == null &&
              (sourceAvailable == false || absoluteSourceUnavailable)) {
            throw const AiV3PreparationException('v3_stem_source_unreadable');
          }
          final sourceName = clip?['name']?.toString().trim() ?? '';
          final baseName = sourceName.isEmpty ? 'Separated' : sourceName;
          final vocalsLabel = _boundedStemLabel(baseName, 'Vocals');
          final instrumentalLabel = _boundedStemLabel(baseName, 'Instrumental');
          commandActions.add(
            AssistantAction(
              type: 'v3_clip_separate_stems',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'separate_stems',
                if (clipId != null) 'source_clip_id': clipId,
                if (rowId is int) 'source_row_id': rowId,
                if (target['row_index'] is int)
                  'source_row_index': target['row_index'],
                if (startMs != null) 'start_ms': startMs,
                if (durationMs != null) 'duration_ms': durationMs,
                'vocals_label': vocalsLabel,
                'instrumental_label': instrumentalLabel,
                'target': target,
              },
            ),
          );
          simulatedRowCount += 2;
          simulatedClipCount += 2;
          hasPriorTopologyMutation = true;
          hasPreparedStemSeparation = true;
          final sourceLabel = clipRef == null
              ? _clipLabel(clipById, clipId!)
              : '${clipRef.commandId}.${clipRef.output}';
          label =
              'Separate $sourceLabel into $vocalsLabel and $instrumentalLabel on two new rows; preserve the source clip';
          verifiedLabel = 'Separated vocals and instrumental';
          break;
        case 'clip.convert_to_midi':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          if (clipRef == null && hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_clip_id_unknown');
          }
          if (!runtimeCapabilities.contains('daw.midi_compose.audio_to_midi')) {
            throw const AiV3PreparationException(
              'v3_audio_to_midi_unavailable',
            );
          }
          if (simulatedRowCount + 1 > maximumRows) {
            throw const AiV3PreparationException(
              'v3_row_capacity_exceeded',
            );
          }
          if (simulatedClipCount + 1 > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          final instrumentId = args['instrument_id'].toString().trim();
          if (!instruments.contains(instrumentId)) {
            throw const AiV3PreparationException(
              'v3_instrument_id_unknown',
            );
          }
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final target = clipRef == null
              ? clipTarget(clipId!, requireAudio: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final rowId = symbolic?.rowId ?? clip?['row_id'];
          final startBeat = (clip?['start_beat'] as num?)?.toDouble();
          final lengthBeats = (clip?['timeline_length_beats'] as num?)
              ?.toDouble();
          final startMs =
              symbolic?.startMs ??
              (startBeat == null ? null : startBeat * 60000.0 / symbolicBpm);
          final durationMs =
              symbolic?.durationMs ??
              (lengthBeats == null
                  ? null
                  : lengthBeats *
                        60000.0 /
                        ((clip?['stretch_to_project_tempo'] == true ||
                                projectAudioForcedTempoFollow)
                            ? symbolicBpm
                            : bpm));
          final deferredRuntimeBounds =
              clipRef != null &&
              symbolic!.boundsRuntimeAuthoritative &&
              durationMs == null;
          final sourcePath = clip?['source_file']?.toString().trim() ?? '';
          if (startMs == null ||
              !startMs.isFinite ||
              (!deferredRuntimeBounds &&
                  (durationMs == null ||
                      !durationMs.isFinite ||
                      durationMs <= 0))) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          if (clipRef == null && sourcePath.isEmpty) {
            throw const AiV3PreparationException(
              'v3_audio_to_midi_source_unreadable',
            );
          }
          final sourceAvailable = clip?['source_available'];
          final sourceFile = File(sourcePath);
          final absoluteSourceUnavailable = sourceFile.isAbsolute &&
              (!sourceFile.existsSync() || sourceFile.lengthSync() <= 44);
          if (clipRef == null &&
              (sourceAvailable == false || absoluteSourceUnavailable)) {
            throw const AiV3PreparationException(
              'v3_audio_to_midi_source_unreadable',
            );
          }
          final sourceName = clip?['name']?.toString().trim() ?? 'Audio';
          final outputLabel = _boundedMidiConversionLabel(sourceName);
          commandActions.add(
            AssistantAction(
              type: 'v3_clip_convert_to_midi',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'convert_to_midi',
                if (clipId != null) 'source_clip_id': clipId,
                if (rowId is int) 'source_row_id': rowId,
                if (target['row_index'] is int)
                  'source_row_index': target['row_index'],
                'start_ms': startMs,
                if (durationMs != null) 'duration_ms': durationMs,
                'instrument_id': instrumentId,
                'output_label': outputLabel,
                'target': target,
              },
            ),
          );
          simulatedRowCount += 1;
          hasPriorTopologyMutation = true;
          hasPreparedAudioToMidi = true;
          simulatedClipCount += 1;
          label =
              'Convert ${clipId == null ? '${clipRef!.commandId}.${clipRef.output}' : _clipLabel(clipById, clipId)} to MIDI with $instrumentId on a new row below the source; preserve the source clip';
          verifiedLabel =
              'Converted ${clipId == null ? '${clipRef!.commandId}.${clipRef.output}' : _clipLabel(clipById, clipId)} to MIDI with $instrumentId on a new row below the source; preserved the source clip';
          break;
        case 'clip.set_pitch_semitones':
        case 'clip.adjust_pitch_semitones':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final target = clipRef == null
              ? clipTarget(clipId!, requireAudio: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final currentPitch = clipRef == null
              ? (clip?['pitch_semitones'] as num?)?.toDouble()
              : symbolic!.pitchSemitones;
          if (currentPitch == null || !currentPitch.isFinite) {
            throw const AiV3PreparationException('v3_clip_pitch_missing');
          }
          final finalPitch = command.type == 'clip.set_pitch_semitones'
              ? (args['pitch_semitones'] as num).toDouble()
              : currentPitch + (args['delta_semitones'] as num).toDouble();
          if (!finalPitch.isFinite || finalPitch < -12 || finalPitch > 12) {
            throw const AiV3PreparationException(
              'v3_clip_pitch_out_of_range',
            );
          }
          if (symbolic != null) symbolic.pitchSemitones = finalPitch;
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'pitch_shift',
                'mode': 'set',
                'new_pitch_semitones': finalPitch,
                'target': target,
              },
            ),
          );
          final targetLabel = clipRef == null
              ? _clipLabel(clipById, clipId!)
              : '${clipRef.commandId}.${clipRef.output}';
          label = 'Set $targetLabel pitch to $finalPitch semitones';
          verifiedLabel = label;
          break;
        case 'clip.set_timeline_length_beats':
        case 'clip.scale_timeline_length':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          if (clipRef != null) {
            final preservePitch = args['preserve_pitch'] as bool;
            final absoluteLengthBeats =
                command.type == 'clip.set_timeline_length_beats'
                ? (args['length_beats'] as num).toDouble()
                : null;
            final factor = command.type == 'clip.scale_timeline_length'
                ? (args['factor'] as num).toDouble()
                : null;
            final predictedDurationMs = absoluteLengthBeats != null
                ? absoluteLengthBeats * 60000.0 / symbolicBpm
                : symbolic!.durationMs == null
                ? null
                : symbolic.durationMs! * factor!;
            if (predictedDurationMs != null &&
                (!predictedDurationMs.isFinite ||
                    predictedDurationMs < 50.0 ||
                    predictedDurationMs > 36000000.0)) {
              throw const AiV3PreparationException(
                'v3_clip_stretch_out_of_range',
              );
            }
            commandActions.add(
              AssistantAction(
                type: 'clip_edit',
                data: <String, dynamic>{
                  'command_id': command.commandId,
                  'resource_consumer_type': command.type,
                  'operation': 'stretch',
                  'runtime_authoritative_audio_timing': true,
                  if (absoluteLengthBeats != null)
                    'requested_length_beats': absoluteLengthBeats,
                  if (factor != null) 'requested_length_factor': factor,
                  'preserve_pitch': preservePitch,
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic!
              ..durationMs = predictedDurationMs
              ..durationFollowsTempo = true
              ..tempoFollowMode = preservePitch ? 'preserve_pitch' : 'repitch'
              ..tempoPreservePitch = preservePitch
              ..boundsRuntimeAuthoritative = true;
            label = absoluteLengthBeats != null
                ? 'Set ${clipRef.commandId}.${clipRef.output} timeline length to $absoluteLengthBeats beats${preservePitch ? ' while preserving pitch' : ' with repitching'}'
                : 'Scale ${clipRef.commandId}.${clipRef.output} timeline length by $factor${preservePitch ? ' while preserving pitch' : ' with repitching'}';
            verifiedLabel = absoluteLengthBeats != null
                ? label
                : 'Scaled ${clipRef.commandId}.${clipRef.output} timeline length by $factor${preservePitch ? ' while preserving pitch' : ' with repitching'}';
            break;
          }
          final stableClipId = clipId!;
          final clip = clipById[stableClipId];
          final target = clipTarget(stableClipId, requireAudio: true);
          final rawLengthBeats = (clip?['length_beats'] as num?)?.toDouble();
          final currentTimelineLengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble();
          if (rawLengthBeats == null ||
              currentTimelineLengthBeats == null ||
              !rawLengthBeats.isFinite ||
              !currentTimelineLengthBeats.isFinite ||
              rawLengthBeats <= 0 ||
              currentTimelineLengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_stretch_source_invalid',
            );
          }
          final finalLengthBeats = command.type ==
                  'clip.set_timeline_length_beats'
              ? (args['length_beats'] as num).toDouble()
              : currentTimelineLengthBeats * (args['factor'] as num).toDouble();
          final finalDurationSeconds = finalLengthBeats * 60.0 / bpm;
          final rawDurationSeconds = rawLengthBeats * 60.0 / bpm;
          final requiredSourceTempo =
              finalDurationSeconds * bpm / rawDurationSeconds;
          final requiredPlaybackRatio =
              rawDurationSeconds / finalDurationSeconds;
          if (!finalLengthBeats.isFinite ||
              !finalDurationSeconds.isFinite ||
              finalDurationSeconds < 0.05 ||
              finalDurationSeconds > 36000.0 ||
              requiredSourceTempo < 20.0 ||
              requiredSourceTempo > 999.0 ||
              requiredPlaybackRatio < 0.05 ||
              requiredPlaybackRatio > 20.0) {
            throw const AiV3PreparationException(
              'v3_clip_stretch_out_of_range',
            );
          }
          final preservePitch = args['preserve_pitch'] as bool;
          final projectStretchEnabled =
              project['tempo_stretch_enabled'] == true;
          final stretchAlreadyActive = projectStretchEnabled &&
              clip?['stretch_to_project_tempo'] == true;
          final currentPreservePitch =
              clip?['tempo_stretch_preserve_pitch'] == true;
          const lengthEpsilon = 0.000001;
          if (stretchAlreadyActive &&
              currentPreservePitch == preservePitch &&
              (currentTimelineLengthBeats - finalLengthBeats).abs() <=
                  lengthEpsilon) {
            receiptStatus = 'already_satisfied';
          } else {
            if (!projectStretchEnabled) {
              for (final other in clips) {
                if (other['clip_id'] == stableClipId ||
                    other['kind'] != 'audio' ||
                    other['stretch_to_project_tempo'] != true) {
                  continue;
                }
                final otherRaw =
                    (other['length_beats'] as num?)?.toDouble() ?? 0.0;
                final otherSourceTempo =
                    (other['source_tempo_bpm'] as num?)?.toDouble() ?? 0.0;
                if (otherRaw > 0 &&
                    otherSourceTempo > 0 &&
                    (otherRaw * otherSourceTempo / bpm - otherRaw).abs() >
                        lengthEpsilon) {
                  throw const AiV3PreparationException(
                    'v3_clip_stretch_global_conflict',
                  );
                }
              }
            }
            commandActions.add(AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'stretch',
                'timeline_duration_ms': finalDurationSeconds * 1000.0,
                'preserve_pitch': preservePitch,
                'target': target,
              },
            ));
          }
          label =
              'Set ${_clipLabel(clipById, stableClipId)} timeline length to $finalLengthBeats beats${preservePitch ? ' while preserving pitch' : ' with repitching'}';
          verifiedLabel = label;
          break;
        case 'clip.set_source_tempo_bpm':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final sourceTempo = (args['source_tempo_bpm'] as num).toDouble();
          if (clipRef != null) {
            commandActions.add(
              AssistantAction(
                type: 'clip_edit',
                data: <String, dynamic>{
                  'command_id': command.commandId,
                  'resource_consumer_type': command.type,
                  'operation': 'set_source_tempo',
                  'runtime_authoritative_audio_timing': true,
                  'source_tempo_bpm': sourceTempo,
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic!
              ..sourceTempoBpm = sourceTempo
              ..boundsRuntimeAuthoritative = true;
            if (symbolic.durationFollowsTempo == true) {
              symbolic.durationMs = null;
            }
            label =
                'Set ${clipRef.commandId}.${clipRef.output} source tempo to $sourceTempo BPM';
            verifiedLabel = label;
            break;
          }
          final stableClipId = clipId!;
          final clip = clipById[stableClipId];
          final target = clipTarget(stableClipId, requireAudio: true);
          final currentSourceTempo = (clip?['source_tempo_bpm'] as num?)
              ?.toDouble();
          final rawLengthBeats = (clip?['length_beats'] as num?)?.toDouble();
          if (currentSourceTempo == null ||
              !currentSourceTempo.isFinite ||
              rawLengthBeats == null ||
              !rawLengthBeats.isFinite ||
              rawLengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_source_tempo_missing',
            );
          }
          if ((currentSourceTempo - sourceTempo).abs() <= 0.000001) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'set_source_tempo',
                'source_tempo_bpm': sourceTempo,
                'target': target,
              },
            ));
          }
          label =
              'Set ${_clipLabel(clipById, stableClipId)} source tempo to $sourceTempo BPM';
          verifiedLabel = label;
          break;
        case 'clip.set_tempo_follow_mode':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final mode = args['mode'] as String;
          if (clipRef != null) {
            commandActions.add(
              AssistantAction(
                type: 'clip_edit',
                data: <String, dynamic>{
                  'command_id': command.commandId,
                  'resource_consumer_type': command.type,
                  'operation': 'tempo_follow',
                  'runtime_authoritative_audio_timing': true,
                  'mode': mode,
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic!
              ..durationMs = null
              ..durationFollowsTempo = mode != 'off'
              ..tempoFollowMode = mode
              ..tempoPreservePitch = mode == 'preserve_pitch'
              ..boundsRuntimeAuthoritative = true;
            label =
                'Set ${clipRef.commandId}.${clipRef.output} tempo-follow mode to $mode';
            verifiedLabel = label;
            break;
          }
          final stableClipId = clipId!;
          final clip = clipById[stableClipId];
          final target = clipTarget(stableClipId, requireAudio: true);
          final projectStretchEnabled =
              project['tempo_stretch_enabled'] == true;
          final configured = clip?['stretch_to_project_tempo'] == true;
          final currentPreserve = clip?['tempo_stretch_preserve_pitch'] == true;
          final rawLengthBeats = (clip?['length_beats'] as num?)?.toDouble();
          final timelineLengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble();
          if (rawLengthBeats == null ||
              timelineLengthBeats == null ||
              !rawLengthBeats.isFinite ||
              !timelineLengthBeats.isFinite ||
              rawLengthBeats <= 0 ||
              timelineLengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_stretch_source_invalid',
            );
          }
          final alreadySatisfied = mode == 'off'
              ? !configured
              : projectStretchEnabled &&
                  configured &&
                  currentPreserve == (mode == 'preserve_pitch');
          if (alreadySatisfied) {
            receiptStatus = 'already_satisfied';
          } else {
            if (mode != 'off' && !projectStretchEnabled) {
              const lengthEpsilon = 0.000001;
              for (final other in clips) {
                if (other['clip_id'] == stableClipId ||
                    other['kind'] != 'audio' ||
                    other['stretch_to_project_tempo'] != true) {
                  continue;
                }
                final otherRaw =
                    (other['length_beats'] as num?)?.toDouble() ?? 0.0;
                final otherSourceTempo =
                    (other['source_tempo_bpm'] as num?)?.toDouble() ?? 0.0;
                if (otherRaw > 0 &&
                    otherSourceTempo > 0 &&
                    (otherRaw * otherSourceTempo / bpm - otherRaw).abs() >
                        lengthEpsilon) {
                  throw const AiV3PreparationException(
                    'v3_clip_stretch_global_conflict',
                  );
                }
              }
            }
            commandActions.add(AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'tempo_follow',
                'mode': mode,
                'target': target,
              },
            ));
          }
          label =
              'Set ${_clipLabel(clipById, stableClipId)} tempo-follow mode to $mode';
          verifiedLabel = label;
          break;
        case 'clip.align_tempo_to_project':
        case 'project.set_tempo_from_clip':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          if (clipRef != null) {
            final symbolic =
                symbolicResources['${clipRef.commandId}.${clipRef.output}'];
            if (symbolic == null ||
                !symbolic.available ||
                symbolic.kind != AiV3ResourceKind.audioClip) {
              throw const AiV3PreparationException(
                'v3_resource_ref_unavailable',
              );
            }
            final mode = args['mode'] as String;
            commandActions.add(
              AssistantAction(
                type: 'v3_clip_audio_analysis',
                data: <String, dynamic>{
                  'resource_consumer_type': command.type,
                  'operation': command.type == 'project.set_tempo_from_clip'
                      ? 'set_tempo_from_clip'
                      : 'align_tempo_to_project',
                  'mode': mode,
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic
              ..durationMs = null
              ..durationFollowsTempo = true
              ..sourceTempoBpm = null
              ..tempoFollowMode = mode
              ..tempoPreservePitch = mode == 'preserve_pitch'
              ..boundsRuntimeAuthoritative = true;
            label = command.type == 'project.set_tempo_from_clip'
                ? 'Set the project tempo from ${clipRef.commandId}.${clipRef.output} and follow in $mode mode'
                : 'Align ${clipRef.commandId}.${clipRef.output} to the project tempo in $mode mode';
            verifiedLabel = command.type == 'project.set_tempo_from_clip'
                ? 'Set the project tempo from ${clipRef.commandId}.${clipRef.output} with $mode tempo following'
                : 'Aligned ${clipRef.commandId}.${clipRef.output} to the project tempo in $mode mode';
            break;
          }
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final detectedTempo = detectedTempoByClipId[clipId];
          final rawLengthBeats = (clip?['length_beats'] as num?)?.toDouble();
          if (detectedTempo == null ||
              !detectedTempo.isFinite ||
              detectedTempo < 40.0 ||
              detectedTempo > 240.0 ||
              rawLengthBeats == null ||
              !rawLengthBeats.isFinite ||
              rawLengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_tempo_detection_unavailable',
            );
          }
          final mode = args['mode'] as String;
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'set_source_tempo',
              'source_tempo_bpm': detectedTempo,
              'target': target,
            },
          ));
          if (command.type == 'project.set_tempo_from_clip') {
            final projectTempo = detectedTempo.round();
            if (projectTempo < 40 || projectTempo > 240) {
              throw const AiV3PreparationException(
                'v3_clip_tempo_detection_unavailable',
              );
            }
            commandActions.add(
              AssistantAction(
                type: 'project_edit',
                data: <String, dynamic>{
                  'operation': 'set_tempo',
                  'tempo_bpm': projectTempo,
                  'time_stretch_audio': false,
                  'preserve_pitch': mode == 'preserve_pitch',
                  'target': const <String, dynamic>{'scope': 'project'},
                },
              ),
            );
          }
          commandActions.add(
            AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'tempo_follow',
                'mode': mode,
                'target': target,
              },
            ),
          );
          label = command.type == 'project.set_tempo_from_clip'
              ? 'Detect ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM, set the project to ${detectedTempo.round()} BPM, and follow in $mode mode'
              : 'Detect ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM and align it to the project in $mode mode';
          verifiedLabel = command.type == 'project.set_tempo_from_clip'
              ? 'Detected ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM, set the project to ${detectedTempo.round()} BPM, and enabled $mode tempo following'
              : 'Detected ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM and aligned it to the project in $mode mode';
          break;
        case 'clip.trim_silence':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          if (clipRef != null) {
            final symbolic =
                symbolicResources['${clipRef.commandId}.${clipRef.output}'];
            if (symbolic == null ||
                !symbolic.available ||
                symbolic.kind != AiV3ResourceKind.audioClip) {
              throw const AiV3PreparationException(
                'v3_resource_ref_unavailable',
              );
            }
            commandActions.add(
              AssistantAction(
                type: 'v3_clip_audio_analysis',
                data: <String, dynamic>{
                  'resource_consumer_type': command.type,
                  'operation': 'trim_silence',
                  'edges': args['edges'],
                  'padding_ms': args['padding_ms'],
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic
              ..durationMs = null
              ..boundsRuntimeAuthoritative = true;
            label =
                'Trim ${args['edges']} silence from ${clipRef.commandId}.${clipRef.output} with ${_formatNumber((args['padding_ms'] as num).toDouble())} ms padding';
            verifiedLabel =
                'Trimmed ${args['edges']} silence from ${clipRef.commandId}.${clipRef.output} with ${_formatNumber((args['padding_ms'] as num).toDouble())} ms padding';
            break;
          }
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final analysis = boundaryAnalysisByClipId[clipId];
          final currentStartBeat = (clip?['start_beat'] as num?)?.toDouble();
          final currentTrimStart = (clip?['trim_start_ms'] as num?)?.toDouble();
          final currentTrimEnd = (clip?['trim_end_ms'] as num?)?.toDouble();
          if (analysis == null ||
              currentStartBeat == null ||
              currentTrimStart == null ||
              currentTrimEnd == null ||
              !currentStartBeat.isFinite ||
              !currentTrimStart.isFinite ||
              !currentTrimEnd.isFinite ||
              currentTrimEnd - currentTrimStart < 50.0) {
            throw const AiV3PreparationException(
              'v3_clip_boundary_analysis_unavailable',
            );
          }
          final edges = args['edges'] as String;
          final paddingMs = (args['padding_ms'] as num).toDouble();
          var nextTrimStart = currentTrimStart;
          var nextTrimEnd = currentTrimEnd;
          if (edges == 'start' || edges == 'both') {
            nextTrimStart = math.max(
              currentTrimStart,
              analysis.audibleStartMs - paddingMs,
            );
          }
          if (edges == 'end' || edges == 'both') {
            nextTrimEnd = math.min(
              currentTrimEnd,
              analysis.audibleEndMs + paddingMs,
            );
          }
          if (!nextTrimStart.isFinite ||
              !nextTrimEnd.isFinite ||
              nextTrimEnd - nextTrimStart < 50.0) {
            throw const AiV3PreparationException(
              'v3_clip_boundary_analysis_unavailable',
            );
          }
          final startDeltaMs = nextTrimStart - currentTrimStart;
          final endDeltaMs = nextTrimEnd - currentTrimEnd;
          if (startDeltaMs.abs() < 0.5 && endDeltaMs.abs() < 0.5) {
            receiptStatus = 'already_satisfied';
          } else {
            final millisecondsPerBeat = 60000.0 / bpm;
            commandActions.add(AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'trim',
                'delta_trim_start_ms': startDeltaMs,
                'delta_trim_end_ms': endDeltaMs,
                'new_start_ms':
                    currentStartBeat * millisecondsPerBeat + startDeltaMs,
                'expected_trim_start_ms': nextTrimStart,
                'expected_trim_end_ms': nextTrimEnd,
                'target': target,
              },
            ));
          }
          label =
              'Trim $edges silence from ${_clipLabel(clipById, clipId)} with ${_formatNumber(paddingMs)} ms padding';
          verifiedLabel =
              'Trimmed $edges silence from ${_clipLabel(clipById, clipId)} with ${_formatNumber(paddingMs)} ms padding';
          break;
        case 'clip.align_first_sound':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          if (clipRef != null) {
            final symbolic =
                symbolicResources['${clipRef.commandId}.${clipRef.output}'];
            if (symbolic == null ||
                !symbolic.available ||
                symbolic.kind != AiV3ResourceKind.audioClip) {
              throw const AiV3PreparationException(
                'v3_resource_ref_unavailable',
              );
            }
            commandActions.add(
              AssistantAction(
                type: 'v3_clip_audio_analysis',
                data: <String, dynamic>{
                  'resource_consumer_type': command.type,
                  'operation': 'align_first_sound',
                  'destination': Map<String, dynamic>.from(
                    args['destination'] as Map,
                  ),
                  'target': <String, dynamic>{
                    'scope': 'clip',
                    'resource_ref': clipRef.toJson(),
                  },
                },
              ),
            );
            symbolic
              ..durationMs = null
              ..boundsRuntimeAuthoritative = true;
            label =
                'Align the first sound of ${clipRef.commandId}.${clipRef.output}';
            verifiedLabel =
                'Aligned the first sound of ${clipRef.commandId}.${clipRef.output}';
            break;
          }
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final analysis = boundaryAnalysisByClipId[clipId];
          final currentStartBeat = (clip?['start_beat'] as num?)?.toDouble();
          final currentAlignmentOffset =
              (clip?['alignment_offset_ms'] as num?)?.toDouble() ?? 0.0;
          if (analysis == null ||
              currentStartBeat == null ||
              !currentStartBeat.isFinite ||
              !analysis.firstSoundOffsetMs.isFinite ||
              analysis.firstSoundOffsetMs < 0) {
            throw const AiV3PreparationException(
              'v3_clip_boundary_analysis_unavailable',
            );
          }
          final destination =
              Map<String, dynamic>.from(args['destination'] as Map);
          final millisecondsPerBeat = 60000.0 / bpm;
          final currentFirstSoundBeat = currentStartBeat +
              analysis.firstSoundOffsetMs / millisecondsPerBeat;
          final beatsPerBar =
              (project['beats_per_bar'] as num?)?.toDouble() ?? 4.0;
          final destinationBeat = switch (destination['kind']) {
            'project_beat' => (destination['beat'] as num).toDouble(),
            'nearest_beat' => currentFirstSoundBeat.roundToDouble(),
            'nearest_bar' =>
              (currentFirstSoundBeat / beatsPerBar).roundToDouble() *
                  beatsPerBar,
            'playhead' => (project['playhead_beat'] as num?)?.toDouble() ?? 0.0,
            'project_start' => 0.0,
            _ => throw const AiV3PreparationException(
                'v3_clip_first_sound_destination_invalid',
              ),
          };
          final nextStartMs = destinationBeat * millisecondsPerBeat -
              analysis.firstSoundOffsetMs;
          if (!nextStartMs.isFinite || nextStartMs < -0.5) {
            throw const AiV3PreparationException(
              'v3_clip_first_sound_negative_start',
            );
          }
          final currentStartMs = currentStartBeat * millisecondsPerBeat;
          final deltaMs = math.max(0.0, nextStartMs) - currentStartMs;
          if (deltaMs.abs() < 0.5) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'clip_edit',
              data: <String, dynamic>{
                'operation': 'move',
                'delta_ms': deltaMs,
                'new_alignment_offset_ms': currentAlignmentOffset + deltaMs,
                'target': target,
              },
            ));
          }
          label =
              'Align the first sound of ${_clipLabel(clipById, clipId)} to ${destination['kind'] == 'project_beat' ? 'beat ${_formatNumber(destinationBeat)}' : destination['kind']}';
          verifiedLabel =
              'Aligned the first sound of ${_clipLabel(clipById, clipId)} to ${destination['kind'] == 'project_beat' ? 'beat ${_formatNumber(destinationBeat)}' : destination['kind']}';
          break;
        case 'midi.transpose':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.midiClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final target = clipRef == null
              ? clipTarget(clipId!, requireMidi: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final currentNotes = clipRef == null
              ? simulatedMidiNotesByClipId[clipId] ??
                    const <Map<String, dynamic>>[]
              : symbolic!.midiNotes ?? const <Map<String, dynamic>>[];
          final runtimeAuthoritativeNotes =
              symbolic?.midiNotesRuntimeAuthoritative == true;
          final semitones = args['semitones'] as int;
          final nextNotes = runtimeAuthoritativeNotes
              ? null
              : _sortedMidiNotes(
                  currentNotes
                      .map(
                        (note) => <String, dynamic>{
                          ...note,
                          'pitch': ((note['pitch'] as int) + semitones)
                              .clamp(0, 127)
                              .toInt(),
                        },
                      )
                      .toList(growable: false),
                );
          if (clipRef == null) {
            simulatedMidiNotesByClipId[clipId!] = nextNotes!;
          } else if (nextNotes != null) {
            symbolic!.midiNotes = nextNotes;
          }
          commandActions.add(
            AssistantAction(
              type: 'midi_compose',
              data: <String, dynamic>{
                'command_id': command.commandId,
                if (clipRef != null) 'resource_consumer_type': command.type,
                'operation': 'transpose_notes',
                'semitones': semitones,
                if (clipRef != null && nextNotes != null)
                  'expected_notes': nextNotes,
                if (runtimeAuthoritativeNotes)
                  'runtime_authoritative_midi': true,
                'target': target,
              },
            ),
          );
          label = clipRef == null
              ? 'Transpose ${_clipLabel(clipById, clipId!)} by $semitones semitones'
              : 'Transpose generated MIDI clip by $semitones semitones';
          verifiedLabel = clipRef == null
              ? 'Transposed ${_clipLabel(clipById, clipId!)} by $semitones semitones'
              : 'Transposed generated MIDI clip by $semitones semitones';
          break;
        case 'midi.create_clip':
          final arrangementLimit =
              ((project['beats_per_bar'] as num?)?.toDouble() ?? 4.0) * 8.0;
          final clipStart = (args['start_beat'] as num).toDouble();
          final clipLength = (args['length_beats'] as num).toDouble();
          final notes = (args['notes'] as List).whereType<Map>();
          if (clipLength > arrangementLimit ||
              notes.any(
                (note) =>
                    (note['start_beat'] as num).toDouble() +
                        (note['length_beats'] as num).toDouble() >
                    clipLength,
              )) {
            throw const AiV3PreparationException('v3_midi_arrangement_limit');
          }
          if (simulatedClipCount + 1 > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          final resolved = destination(args['destination'], midi: true);
          final usesRowRef = (args['destination'] as Map)['row_ref'] is Map;
          commandActions.addAll(resolved.setup);
          final instrumentId =
              (resolved.target['instrument_id'] ??
                      rowById[(args['destination']
                          as Map)['row_id']]?['instrument_id'])
                  ?.toString();
          commandActions.add(
            AssistantAction(
              type: 'midi_compose',
              data: <String, dynamic>{
                if (referencedProducerCommandIds.contains(command.commandId))
                  'command_id': command.commandId,
                if (usesRowRef) 'resource_consumer_type': command.type,
                'operation': 'create_clip',
                'target': resolved.target,
                'notes': args['notes'],
                'start_ms': clipStart * 60000.0 / symbolicBpm,
                'length_beats': args['length_beats'],
                'exact_notes': true,
                'create_new_clip': true,
                if ((instrumentId ?? '').isNotEmpty)
                  'instrument_id': instrumentId,
              },
            ),
          );
          simulatedClipCount += 1;
          label =
              'Create MIDI clip with ${(args['notes'] as List).length} notes';
          verifiedLabel =
              'Created MIDI clip with ${(args['notes'] as List).length} notes';
          break;
        case 'midi.replace_notes':
        case 'midi.append_notes':
        case 'midi.chop_notes':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final spec = aiV3ResourceConsumerSpecs[command.type]!;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  !spec.acceptedKinds.contains(symbolic.kind))) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final target = clipRef == null
              ? clipTarget(clipId!, requireMidi: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final clip = clipId == null ? null : clipById[clipId];
          final runtimeAuthoritativeNotes =
              symbolic?.midiNotesRuntimeAuthoritative == true;
          final runtimeAuthoritativeBounds =
              symbolic?.boundsRuntimeAuthoritative == true;
          final clipLength = symbolic?.durationMs == null
              ? simulatedMidiLengthByClipId[clipId] ??
                    (clip?['length_beats'] as num?)?.toDouble()
              : symbolic!.durationMs! * symbolicBpm / 60000.0;
          if ((clipLength == null && !runtimeAuthoritativeBounds) ||
              (clipLength != null &&
                  (!clipLength.isFinite || clipLength <= 0))) {
            throw const AiV3PreparationException('v3_midi_clip_length_invalid');
          }
          final currentNotes = clipRef == null
              ? simulatedMidiNotesByClipId[clipId] ??
                    const <Map<String, dynamic>>[]
              : symbolic!.midiNotes ?? const <Map<String, dynamic>>[];
          late final List<Map<String, dynamic>> nextNotes;
          var deferredRuntimeTransform = false;
          if (command.type == 'midi.replace_notes') {
            nextNotes = _normalizedMidiNotes(args['notes'] as List);
            deferredRuntimeTransform =
                runtimeAuthoritativeBounds && clipLength == null;
            if (symbolic != null) {
              symbolic
                ..midiNotesRuntimeAuthoritative = false
                ..midiNotes = nextNotes;
            }
          } else if (runtimeAuthoritativeNotes ||
              (runtimeAuthoritativeBounds && clipLength == null)) {
            deferredRuntimeTransform = true;
            nextNotes = const <Map<String, dynamic>>[];
            if (command.type == 'midi.chop_notes') {
              final rawRange = args['range'];
              final range = rawRange is Map
                  ? Map<String, dynamic>.from(rawRange)
                  : null;
              final rangeStart =
                  (range?['start_beat'] as num?)?.toDouble() ?? 0.0;
              final rangeEnd = (range?['end_beat'] as num?)?.toDouble();
              if (rangeStart < 0 ||
                  (rangeEnd != null && rangeEnd <= rangeStart)) {
                throw const AiV3PreparationException(
                  'v3_midi_chop_range_invalid',
                );
              }
            }
          } else if (command.type == 'midi.append_notes') {
            final relativeNotes = _normalizedMidiNotes(args['notes'] as List);
            final existingNoteEnd = currentNotes.fold<double>(
              0.0,
              (latest, note) => math.max(
                latest,
                (note['start_beat'] as double) +
                    (note['length_beats'] as double),
              ),
            );
            final appendAnchor = math.max(clipLength!, existingNoteEnd);
            final appended = relativeNotes
                .map((note) => <String, dynamic>{
                      ...note,
                      'start_beat':
                          (note['start_beat'] as double) + appendAnchor,
                    })
                .toList(growable: false);
            nextNotes = _sortedMidiNotes(<Map<String, dynamic>>[
              ...currentNotes,
              ...appended,
            ]);
            final appendedSpan = relativeNotes
                .map((note) =>
                    (note['start_beat'] as double) +
                    (note['length_beats'] as double))
                .reduce(math.max);
            final appendedLength = appendAnchor + appendedSpan;
            if (clipRef == null) {
              simulatedMidiLengthByClipId[clipId!] = appendedLength;
            } else {
              symbolic!.durationMs = appendedLength * 60000.0 / symbolicBpm;
            }
          } else {
            if (currentNotes.isEmpty) {
              throw const AiV3PreparationException(
                'v3_midi_notes_missing',
              );
            }
            final rawRange = args['range'];
            final range =
                rawRange is Map ? Map<String, dynamic>.from(rawRange) : null;
            final rangeStart =
                (range?['start_beat'] as num?)?.toDouble() ?? 0.0;
            final rangeEnd =
                (range?['end_beat'] as num?)?.toDouble() ?? clipLength!;
            if (rangeStart < 0 ||
                rangeEnd <= rangeStart ||
                rangeEnd > clipLength! + 0.000001) {
              throw const AiV3PreparationException(
                'v3_midi_chop_range_invalid',
              );
            }
            nextNotes = _chopMidiNotes(
              currentNotes,
              stepBeats: 4.0 / (args['subdivision'] as int),
              rangeStart: rangeStart,
              rangeEnd: rangeEnd,
              velocityDecayPerSlice:
                  (args['velocity_decay_per_slice'] as num).toDouble(),
            );
          }
          final double? finalClipLength = deferredRuntimeTransform
              ? null
              : clipRef == null
              ? simulatedMidiLengthByClipId[clipId] ?? clipLength
              : symbolic!.durationMs! * symbolicBpm / 60000.0;
          if (!deferredRuntimeTransform &&
              nextNotes.any(
                (note) =>
                    (note['start_beat'] as double) +
                        (note['length_beats'] as double) >
                    finalClipLength! + 0.000001,
              )) {
            throw const AiV3PreparationException('v3_midi_note_out_of_bounds');
          }
          if (!deferredRuntimeTransform && nextNotes.length > 512) {
            throw const AiV3PreparationException('v3_midi_result_limit');
          }
          if (deferredRuntimeTransform) {
            // Exact converted notes are bound at runtime and transformed there.
          } else if (clipRef == null) {
            simulatedMidiNotesByClipId[clipId!] = nextNotes;
          } else {
            symbolic!.midiNotes = nextNotes;
          }
          final alreadySatisfied =
              !deferredRuntimeTransform &&
              command.type != 'midi.append_notes' &&
              _midiNotesEqual(currentNotes, nextNotes);
          if (alreadySatisfied) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(
              AssistantAction(
                type: 'midi_compose',
                data: <String, dynamic>{
                  if (clipRef != null) 'command_id': command.commandId,
                  if (clipRef != null) 'resource_consumer_type': command.type,
                  'operation': 'replace_notes',
                  'target': target,
                  if (!deferredRuntimeTransform) 'notes': nextNotes,
                  if (clipRef != null && !deferredRuntimeTransform)
                    'expected_notes': nextNotes,
                  if (deferredRuntimeTransform) ...<String, dynamic>{
                    'runtime_authoritative_midi': true,
                    'deferred_midi_command': command.type,
                    if (args['notes'] != null) 'requested_notes': args['notes'],
                    if (args['subdivision'] != null)
                      'subdivision': args['subdivision'],
                    if (args['range'] != null) 'range': args['range'],
                    if (args['velocity_decay_per_slice'] != null)
                      'velocity_decay_per_slice':
                          args['velocity_decay_per_slice'],
                  },
                  'exact_notes': true,
                  'preserve_existing_notes': false,
                  'preserve_clip_state': true,
                  if (command.type == 'midi.append_notes' &&
                      !deferredRuntimeTransform)
                    'final_length_beats': finalClipLength!,
                },
              ),
            );
          }
          label = switch (command.type) {
            'midi.replace_notes' =>
              clipRef == null
                  ? 'Replace notes in ${_clipLabel(clipById, clipId!)}'
                  : 'Replace notes in ${clipRef.commandId}.${clipRef.output}',
            'midi.append_notes' =>
              clipRef == null
                  ? 'Append notes to ${_clipLabel(clipById, clipId!)}'
                  : 'Append notes to ${clipRef.commandId}.${clipRef.output}',
            _ =>
              clipRef == null
                  ? 'Chop notes in ${_clipLabel(clipById, clipId!)}'
                  : 'Chop notes in ${clipRef.commandId}.${clipRef.output}',
          };
          verifiedLabel = switch (command.type) {
            'midi.replace_notes' =>
              clipRef == null
                  ? 'Replaced notes in ${_clipLabel(clipById, clipId!)}'
                  : 'Replaced notes in ${clipRef.commandId}.${clipRef.output}',
            'midi.append_notes' =>
              clipRef == null
                  ? 'Appended notes to ${_clipLabel(clipById, clipId!)}'
                  : 'Appended notes to ${clipRef.commandId}.${clipRef.output}',
            _ =>
              clipRef == null
                  ? 'Chopped notes in ${_clipLabel(clipById, clipId!)}'
                  : 'Chopped notes in ${clipRef.commandId}.${clipRef.output}',
          };
          break;
        case 'effect.ensure_configured':
          final resolved = resolveRowCommandTarget();
          final effectId = args['effect_id'] as String;
          final effect = effectById[effectId];
          if (effect == null) {
            throw const AiV3PreparationException('v3_effect_id_unknown');
          }
          final allowedParameters =
              (effect['parameters'] as List? ?? const <Object>[])
                  .whereType<Map>()
                  .map((value) => value['parameter_id']?.toString())
                  .whereType<String>()
                  .toSet();
          final parameterEntries = (args['parameters'] as List)
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false);
          final parameters = <String, dynamic>{};
          for (final entry in parameterEntries) {
            final canonicalParameterId = _canonicalEffectParameterId(
              entry['parameter_id'].toString(),
              allowedParameters,
            );
            if (canonicalParameterId == null ||
                parameters.containsKey(canonicalParameterId)) {
              throw const AiV3PreparationException(
                'v3_effect_parameter_unknown',
              );
            }
            parameters[canonicalParameterId] = entry['value'];
          }
          commandActions.add(
            AssistantAction(
              type: 'v3_effect_configure',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'ensure_configured',
                'effect_id': effectId,
                'parameters': parameters,
                'target': resolved.target,
              },
            ),
          );
          label = 'Add/configure $effectId on ${resolved.label}';
          verifiedLabel = 'Added/configured $effectId on ${resolved.label}';
          break;
        case 'effect.remove':
        case 'effect.set_bypassed':
          final instanceId = args['effect_instance_id'] as String;
          final rowId = effectRowByInstanceId[instanceId];
          final chain = rowId == null ? null : effectChainByRowId[rowId];
          final effectIndex = chain?.indexWhere(
                (effect) => effect['effect_instance_id'] == instanceId,
              ) ??
              -1;
          if (rowId == null || chain == null || effectIndex < 0) {
            throw const AiV3PreparationException(
              'v3_effect_instance_unknown',
            );
          }
          final effect = chain[effectIndex];
          final effectId = effect['effect_id']?.toString().trim() ?? '';
          if (effectId.isEmpty) {
            throw const AiV3PreparationException(
              'v3_effect_instance_index_invalid',
            );
          }
          if (command.type == 'effect.remove') {
            commandActions.add(AssistantAction(
              type: 'v3_effect_instance_edit',
              data: <String, dynamic>{
                'operation': 'remove',
                'effect_instance_id': instanceId,
                'effect_id': effectId,
                'effect_index': effectIndex,
                'target': rowTarget(rowId),
              },
            ));
            chain.removeAt(effectIndex);
            label =
                'Remove ${effect['display_name'] ?? effectId} from ${_rowLabel(rowById, rowId)}';
            verifiedLabel =
                'Removed ${effect['display_name'] ?? effectId} from ${_rowLabel(rowById, rowId)}';
          } else {
            final bypassed = args['bypassed'] as bool;
            if (effect['bypassed'] == bypassed) {
              receiptStatus = 'already_satisfied';
            } else {
              commandActions.add(AssistantAction(
                type: 'v3_effect_instance_edit',
                data: <String, dynamic>{
                  'operation': 'set_bypassed',
                  'effect_instance_id': instanceId,
                  'effect_id': effectId,
                  'effect_index': effectIndex,
                  'bypassed': bypassed,
                  'target': rowTarget(rowId),
                },
              ));
              effect['bypassed'] = bypassed;
            }
            label =
                '${bypassed ? 'Bypass' : 'Enable'} ${effect['display_name'] ?? effectId} on ${_rowLabel(rowById, rowId)}';
            verifiedLabel =
                '${bypassed ? 'Bypassed' : 'Enabled'} ${effect['display_name'] ?? effectId} on ${_rowLabel(rowById, rowId)}';
          }
          break;
        case 'automation.gain_fade':
          final resolved = resolveRowCommandTarget();
          final startMs =
              (args['start_beat'] as num).toDouble() * 60000.0 / symbolicBpm;
          final endMs =
              (args['end_beat'] as num).toDouble() * 60000.0 / symbolicBpm;
          final toLevel = args['to_level'];
          // Volume automation is a normalized multiplier in the editor. A
          // value of 1 preserves the row's current fader level, while 0 is
          // silence. Converting here is factual command preparation; the
          // executor must never reinterpret a dB value as a normalized one.
          double normalizedGain(Object value) {
            if (value == 'current') return 1.0;
            final db = (value as num).toDouble();
            if (db <= -120.0) return 0.0;
            return math.pow(10.0, db / 20.0).toDouble().clamp(0.0, 1.0);
          }

          commandActions.add(
            AssistantAction(
              type: 'automation_edit',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'set_points',
                'target': <String, dynamic>{
                  ...resolved.target,
                  'automation_target_id': 'volume',
                },
                'value_mode': 'normalized',
                'points': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'time_ms': startMs,
                    'value': normalizedGain(args['from_gain_db']!),
                  },
                  <String, dynamic>{
                    'time_ms': endMs,
                    'value': normalizedGain(toLevel!),
                  },
                ],
              },
            ),
          );
          label = 'Add gain fade on ${resolved.label}';
          verifiedLabel = 'Added gain fade on ${resolved.label}';
          break;
        case 'automation.set_points':
          final resolved = resolveRowCommandTarget();
          final targetId = args['automation_target_id'].toString();
          final target = generatedRowAutomationTarget(resolved, targetId);
          final points = (args['points'] as List)
              .whereType<Map>()
              .map(
                (raw) => <String, dynamic>{
                  'time_ms':
                      (raw['beat'] as num).toDouble() * 60000.0 / symbolicBpm,
                  'value': (raw['value_normalized'] as num).toDouble(),
                },
              )
              .toList(growable: false);
          commandActions.add(
            AssistantAction(
              type: 'v3_automation_points',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'set_points',
                'target': target,
                'points': points,
              },
            ),
          );
          label = 'Set ${points.length} automation points on ${resolved.label}';
          verifiedLabel = label;
          break;
        case 'automation.clear':
          final resolved = resolveRowCommandTarget();
          final targetId = args['automation_target_id'].toString();
          commandActions.add(
            AssistantAction(
              type: 'v3_automation_points',
              data: <String, dynamic>{
                if (resolved.ref != null)
                  'resource_consumer_type': command.type,
                'operation': 'clear',
                'target': generatedRowAutomationTarget(resolved, targetId),
                'points': const <Map<String, dynamic>>[],
              },
            ),
          );
          label = 'Clear automation on ${resolved.label}';
          verifiedLabel = 'Cleared automation on ${resolved.label}';
          break;
        case 'sample.place':
          final resolved = destination(args['destination'], midi: false);
          final usesRowRef = (args['destination'] as Map)['row_ref'] is Map;
          commandActions.addAll(resolved.setup);
          final items = <Map<String, dynamic>>[];
          for (final raw in (args['placements'] as List).whereType<Map>()) {
            final placement = Map<String, dynamic>.from(raw);
            final asset = assetById[placement['asset_id']];
            if (asset == null) {
              throw const AiV3PreparationException('v3_asset_id_unknown');
            }
            items.add(<String, dynamic>{
              'library_path': asset['path'],
              'row_index': resolved.target['row_index'],
              'start_ms':
                  (placement['start_beat'] as num).toDouble() *
                  60000.0 /
                  symbolicBpm,
              'target': resolved.target,
            });
          }
          if (simulatedClipCount + items.length > 128) {
            throw const AiV3PreparationException('v3_clip_capacity_exceeded');
          }
          commandActions.add(
            AssistantAction(
              type: 'sample_insert',
              data: <String, dynamic>{
                if (referencedProducerCommandIds.contains(command.commandId))
                  'command_id': command.commandId,
                if (usesRowRef) 'resource_consumer_type': command.type,
                'operation': 'insert_audio_clips',
                'items': items,
                'target': resolved.target,
              },
            ),
          );
          simulatedClipCount += items.length;
          label =
              'Place ${items.length} library sample${items.length == 1 ? '' : 's'}';
          verifiedLabel =
              'Placed ${items.length} library sample${items.length == 1 ? '' : 's'}';
          break;
        case 'sample.replace':
          final rawRef = args['clip_ref'];
          final AiV3ResourceRef? clipRef = rawRef is Map
              ? AiV3ResourceRef.fromJson(rawRef)
              : null;
          final String? clipId = args['clip_id'] is String
              ? args['clip_id'] as String
              : null;
          final symbolic = clipRef == null
              ? null
              : symbolicResources['${clipRef.commandId}.${clipRef.output}'];
          if (clipRef != null &&
              (symbolic == null ||
                  !symbolic.available ||
                  symbolic.kind != AiV3ResourceKind.audioClip)) {
            throw const AiV3PreparationException('v3_resource_ref_unavailable');
          }
          final target = clipRef == null
              ? clipTarget(clipId!, requireAudio: true)
              : <String, dynamic>{
                  'scope': 'clip',
                  'resource_ref': clipRef.toJson(),
                };
          final assetId = args['asset_id'] as String;
          final asset = assetById[assetId];
          if (asset == null) {
            throw const AiV3PreparationException('v3_asset_id_unknown');
          }
          final sourcePath = asset['path']?.toString().trim() ?? '';
          if (sourcePath.isEmpty) {
            throw const AiV3PreparationException('v3_asset_id_unknown');
          }
          final clip = clipId == null ? null : clipById[clipId];
          final currentSource = clip?['source_file']?.toString().trim() ?? '';
          if (clipRef == null &&
              currentSource.isNotEmpty &&
              currentSource == sourcePath) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(
              AssistantAction(
                type: 'v3_sample_replace',
                data: <String, dynamic>{
                  if (clipRef != null) 'resource_consumer_type': command.type,
                  'operation': 'replace',
                  'asset_id': assetId,
                  'library_path': sourcePath,
                  'target': target,
                },
              ),
            );
            if (symbolic != null) {
              symbolic
                ..durationMs = null
                ..durationFollowsTempo = false
                ..sourceTempoBpm = 0.0
                ..tempoFollowMode = 'off'
                ..tempoPreservePitch = false
                ..boundsRuntimeAuthoritative = true;
            }
          }
          final assetName = asset['filename']?.toString().trim();
          label =
              'Replace ${clipRef == null ? _clipLabel(clipById, clipId!) : '${clipRef.commandId}.${clipRef.output}'} with ${assetName == null || assetName.isEmpty ? assetId : assetName}';
          verifiedLabel =
              'Replaced ${clipRef == null ? _clipLabel(clipById, clipId!) : '${clipRef.commandId}.${clipRef.output}'} with ${assetName == null || assetName.isEmpty ? assetId : assetName}';
          break;
        case 'mix.apply_goal':
          if (hasPriorTopologyMutation) {
            throw const AiV3PreparationException(
              'v3_mix_action_target_invalid',
            );
          }
          final rawTarget = Map<String, dynamic>.from(args['target'] as Map);
          final scope = rawTarget['scope'] as String;
          final preparedTarget = <String, dynamic>{'scope': scope};
          switch (scope) {
            case 'row':
              final rowId = rawTarget['row_id'] as int;
              rowTarget(rowId);
              final row = rowById[rowId];
              if (row == null) {
                throw const AiV3PreparationException('v3_row_id_unknown');
              }
              preparedTarget.addAll(<String, dynamic>{
                'row_id': rowId,
                'row_index': row['display_index'],
              });
              break;
            case 'group':
              final groupId = rawTarget['group_id'] as String;
              final group = simulatedGroupsById[groupId];
              if (group == null ||
                  (group['member_row_ids'] as List? ?? const <Object>[])
                      .isEmpty) {
                throw const AiV3PreparationException('v3_group_id_unknown');
              }
              preparedTarget['group_id'] = groupId;
              break;
            case 'all_rows':
              if (!rows.any((row) =>
                  row['row_id'] is int &&
                  !deletedRowIds.contains(row['row_id']) &&
                  row['mix_processing_supported'] == true)) {
                throw const AiV3PreparationException('v3_mix_audio_missing');
              }
              break;
            case 'master':
              break;
          }
          Map<String, dynamic>? preparedReference;
          final rawReference = args['reference'];
          if (rawReference is Map) {
            if (scope == 'master') {
              throw const AiV3PreparationException(
                'v3_mix_master_reference_unsupported',
              );
            }
            final reference = Map<String, dynamic>.from(rawReference);
            final referenceRowId = reference['row_id'] as int;
            final referenceRow = rowById[referenceRowId];
            if (referenceRow == null ||
                deletedRowIds.contains(referenceRowId)) {
              throw const AiV3PreparationException(
                'v3_mix_reference_id_unknown',
              );
            }
            if (referenceRow['has_analyzable_audio'] != true) {
              throw const AiV3PreparationException(
                'v3_mix_reference_audio_missing',
              );
            }
            if (scope == 'row' && preparedTarget['row_id'] == referenceRowId) {
              throw const AiV3PreparationException(
                'v3_mix_reference_equals_target',
              );
            }
            preparedReference = <String, dynamic>{
              ...reference,
              'row_index': referenceRow['display_index'],
            };
          }
          commandActions.add(AssistantAction(
            type: 'v3_mix_goal',
            data: <String, dynamic>{
              'command_id': command.commandId,
              'target': preparedTarget,
              'intents': args['intents'],
              'intensity': args['intensity'],
              'execution_profile': args['execution_profile'],
              'audibility': args['audibility'],
              'style_tags': args['style_tags'],
              'reset_fx': args['reset_fx'],
              'reference': preparedReference,
            },
          ));
          final targetLabel = switch (scope) {
            'row' => _rowLabel(rowById, rawTarget['row_id'] as int),
            'group' =>
              simulatedGroupsById[rawTarget['group_id']]?['name']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true
                  ? simulatedGroupsById[rawTarget['group_id']]!['name']
                        .toString()
                        .trim()
                  : 'group ${rawTarget['group_id']}',
            'master' => 'Master Bus',
            _ => 'all project rows',
          };
          final referenceLabel = preparedReference == null
              ? ''
              : ' using ${_rowLabel(rowById, preparedReference['row_id'] as int)} as reference';
          label = 'Mix $targetLabel$referenceLabel';
          verifiedLabel = 'Mixed $targetLabel$referenceLabel';
          break;
        default:
          throw const AiV3PreparationException('v3_command_not_supported');
      }
      actions.addAll(commandActions);
      previewLines.add('- $label');
      receipts.add(<String, dynamic>{
        'command_id': command.commandId,
        'type': command.type,
        'status': receiptStatus,
        'expanded_action_count': commandActions.length,
        'preview_label': label,
        'verified_label': _aiV3VerifiedReceiptLabel(
          verifiedLabel: verifiedLabel,
          symbolicResources: symbolicResources,
        ),
      });
      for (final output in aiV3ProducedResources(
        commandType: command.type,
        arguments: command.arguments,
      ).entries) {
        if (symbolicResources.containsKey(
          '${command.commandId}.${output.key}',
        )) {
          continue;
        }
        final isRowOutput =
            output.value == AiV3ResourceKind.audioRow ||
            output.value == AiV3ResourceKind.midiRow;
        String? outputInstrumentId;
        if (output.value == AiV3ResourceKind.midiRow) {
          outputInstrumentId = command.type == 'clip.convert_to_midi'
              ? command.arguments['instrument_id']?.toString()
              : (command.arguments['lane'] as Map?)?['instrument_id']
                    ?.toString();
        }
        final producerTarget = commandActions
            .map((action) => action.data['target'])
            .whereType<Map>()
            .map((target) => Map<String, dynamic>.from(target))
            .where(
              (target) => target['row_id'] is int || target['row_index'] is int,
            )
            .lastOrNull;
        final producerInputRef = command.arguments['clip_ref'] is Map
            ? AiV3ResourceRef.fromJson(command.arguments['clip_ref'])
            : null;
        final producerInputSymbolic = producerInputRef == null
            ? null
            : symbolicResources['${producerInputRef.commandId}.${producerInputRef.output}'];
        final sourceRowId = command.arguments['clip_id'] is String
            ? (clipById[command.arguments['clip_id']]?['row_id']) as int?
            : producerInputSymbolic?.rowId;
        final sourceRowIndex = sourceRowId == null
            ? producerInputSymbolic?.rowIndex
            : rowById[sourceRowId]?['display_index'];
        final outputRowIndex = command.type == 'clip.separate_stems'
            ? (sourceRowIndex is int
                  ? sourceRowIndex +
                        (output.key == 'instrumental_clip' ||
                                output.key == 'instrumental_row'
                            ? 2
                            : 1)
                  : null)
            : command.type == 'clip.convert_to_midi'
            ? (sourceRowIndex == null ? null : sourceRowIndex + 1)
            : command.type == 'row.create'
            ? commandActions
                  .map((action) => action.data['predicted_row_index'])
                  .whereType<int>()
                  .firstOrNull
            : producerTarget?['row_index'] as int?;
        final outputRowId = command.type == 'clip.convert_to_midi'
            ? null
            : producerTarget?['row_id'] as int?;
        final destination = command.arguments['destination'];
        final rawParentRowRef = destination is Map
            ? destination['row_ref']
            : null;
        final parentRowResourceKey = rawParentRowRef is Map
            ? '${rawParentRowRef['command_id']}.${rawParentRowRef['output']}'
            : command.type == 'clip.separate_stems'
            ? '${command.commandId}.${output.key == 'vocals_clip' ? 'vocals_row' : 'instrumental_row'}'
            : command.type == 'clip.convert_to_midi' &&
                  output.key == 'midi_clip'
            ? '${command.commandId}.midi_row'
            : null;
        final stableProducerInput = command.arguments['clip_id'] is String
            ? clipById[command.arguments['clip_id']]
            : null;
        final stableProducerLengthBeats =
            (stableProducerInput?['timeline_length_beats'] as num?)
                ?.toDouble() ??
            (stableProducerInput?['length_beats'] as num?)?.toDouble();
        final startMs = switch (command.type) {
          'clip.separate_stems' =>
            producerInputSymbolic?.startMs ??
                (((command.arguments['clip_id'] is String
                                    ? clipById[command.arguments['clip_id']]
                                    : null)?['start_beat']
                                as num?)
                            ?.toDouble() ??
                        0.0) *
                    60000.0 /
                    symbolicBpm,
          'midi.create_clip' =>
            (command.arguments['start_beat'] as num).toDouble() *
                60000.0 /
                symbolicBpm,
          'sample.place' =>
            (((command.arguments['placements'] as List).single
                            as Map)['start_beat']
                        as num)
                    .toDouble() *
                60000.0 /
                symbolicBpm,
          'clip.convert_to_midi' =>
            producerInputSymbolic?.startMs ??
                (((command.arguments['clip_id'] is String
                                    ? clipById[command.arguments['clip_id']]
                                    : null)?['start_beat']
                                as num?)
                            ?.toDouble() ??
                        0.0) *
                    60000.0 /
                    symbolicBpm,
          _ => 0.0,
        };
        final durationMs = switch (command.type) {
          'clip.separate_stems' =>
            producerInputSymbolic != null
                ? producerInputSymbolic.durationMs
                : (((command.arguments['clip_id'] is String
                                      ? clipById[command.arguments['clip_id']]
                                      : null)?['timeline_length_beats']
                                  as num?)
                              ?.toDouble() ??
                          0.0) *
                      60000.0 /
                      ((command.arguments['clip_id'] is String &&
                              (clipById[command
                                          .arguments['clip_id']]?['stretch_to_project_tempo'] ==
                                      true ||
                                  projectAudioForcedTempoFollow))
                          ? symbolicBpm
                          : bpm),
          'midi.create_clip' =>
            (command.arguments['length_beats'] as num).toDouble() *
                60000.0 /
                symbolicBpm,
          'clip.convert_to_midi' =>
            producerInputSymbolic?.durationMs ??
                (stableProducerLengthBeats == null
                    ? null
                    : stableProducerLengthBeats *
                          60000.0 /
                          ((stableProducerInput?['stretch_to_project_tempo'] ==
                                      true ||
                                  projectAudioForcedTempoFollow)
                              ? symbolicBpm
                              : bpm)),
          _ => null,
        };
        symbolicResources['${command.commandId}.${output.key}'] =
            _AiV3SymbolicResource(
              kind: output.value,
              startMs: startMs,
              durationMs: durationMs,
              durationFollowsTempo: switch (command.type) {
                'midi.create_clip' => true,
                'clip.convert_to_midi' => true,
                'clip.separate_stems' => false,
                _ => null,
              },
              rowId: outputRowId,
              rowIndex: outputRowIndex,
              parentRowResourceKey:
                  output.value == AiV3ResourceKind.audioClip ||
                      output.value == AiV3ResourceKind.midiClip
                  ? parentRowResourceKey
                  : null,
              pitchSemitones: output.value == AiV3ResourceKind.audioClip
                  ? 0.0
                  : null,
              sourceTempoBpm: output.value == AiV3ResourceKind.audioClip
                  ? 0.0
                  : null,
              tempoFollowMode: output.value == AiV3ResourceKind.audioClip
                  ? 'off'
                  : null,
              tempoPreservePitch: output.value == AiV3ResourceKind.audioClip
                  ? false
                  : null,
              midiNotes:
                  output.value == AiV3ResourceKind.midiClip &&
                      command.type != 'clip.convert_to_midi'
                  ? _normalizedMidiNotes(
                      command.arguments['notes'] as List? ?? const <Object>[],
                    )
                  : null,
              midiNotesRuntimeAuthoritative:
                  command.type == 'clip.convert_to_midi' &&
                  output.value == AiV3ResourceKind.midiClip,
              boundsRuntimeAuthoritative:
                  (command.type == 'clip.convert_to_midi' &&
                      output.value == AiV3ResourceKind.midiClip) ||
                  ((output.value == AiV3ResourceKind.audioClip ||
                          output.value == AiV3ResourceKind.midiClip) &&
                      durationMs == null),
              rowName: isRowOutput
                  ? (command.type == 'row.create'
                        ? command.arguments['name'] as String
                        : command.type == 'clip.convert_to_midi'
                        ? commandActions
                              .map((action) => action.data['output_label'])
                              .whereType<String>()
                              .firstOrNull
                        : null)
                  : null,
              instrumentId: outputInstrumentId,
              gainDb: isRowOutput ? 0.0 : null,
              panSigned: isRowOutput ? 0.0 : null,
              muted: isRowOutput ? false : null,
              soloed: isRowOutput ? false : null,
            );
        if (isRowOutput) {
          final resourceKey = '${command.commandId}.${output.key}';
          if (!symbolicRowOrder.contains(resourceKey) &&
              outputRowIndex != null &&
              outputRowIndex >= 0 &&
              outputRowIndex <= symbolicRowOrder.length) {
            symbolicRowOrder.insert(outputRowIndex, resourceKey);
          }
        }
      }
      final directlyTargetedClipId = args['clip_id'];
      if (directlyTargetedClipId is String &&
          command.type != 'clip.delete' &&
          command.type != 'clip.glue' &&
          command.type != 'clip.separate_stems' &&
          command.type != 'clip.convert_to_midi') {
        previouslyMutatedClipIds.add(directlyTargetedClipId);
      }
    }
    return AiV3PreparedBundle(
      plan: preparedPlan,
      stateDigest: context.stateDigest,
      actions: List<AssistantAction>.unmodifiable(actions),
      receipts: List<Map<String, dynamic>>.unmodifiable(receipts),
      executionPolicy: aiV3ExecutionPolicyForCommandTypes(
        preparedPlan.commands.map((command) => command.type),
      ),
      preview: <String>[
        preparedPlan.userMessage,
        'Planned changes:',
        ...previewLines,
      ].join('\n'),
    );
  }
}

String _boundedStemLabel(String base, String suffix) {
  final normalized = '$base $suffix'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 80) return normalized;
  final available = math.max(1, 80 - suffix.length - 1);
  return '${base.substring(0, math.min(base.length, available))} $suffix';
}

String _boundedMidiConversionLabel(String sourceName) {
  final base = sourceName.trim().isEmpty ? 'Audio' : sourceName.trim();
  final normalized = '$base MIDI'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 80) return normalized;
  return normalized.substring(0, 80).trimRight();
}

typedef _AiV3RowDestinationDescriptor = ({
  String laneKind,
  String name,
  String instrumentId,
  String position,
});

AiV3Plan _canonicalizeEmbeddedDestinationRows(AiV3Plan plan) {
  final embeddedCounts = <_AiV3RowDestinationDescriptor, int>{};
  final standaloneCounts = <_AiV3RowDestinationDescriptor, int>{};
  final standaloneDescriptorByCommandId =
      <String, _AiV3RowDestinationDescriptor>{};
  final referencedCommandIds = <String>{};
  for (final command in plan.commands) {
    final directRef = command.arguments['row_ref'];
    final destination = command.arguments['destination'];
    final destinationRef = destination is Map ? destination['row_ref'] : null;
    final groupMemberRefs =
        command.type == 'group.create' && command.arguments['members'] is List
        ? (command.arguments['members'] as List).whereType<Map>().map(
            (member) => member['row_ref'],
          )
        : const Iterable<Object?>.empty();
    for (final rawRef in <Object?>[
      directRef,
      destinationRef,
      ...groupMemberRefs,
    ].whereType<Map>()) {
      final commandId = rawRef['command_id']?.toString().trim() ?? '';
      if (commandId.isNotEmpty) referencedCommandIds.add(commandId);
    }
  }

  _AiV3RowDestinationDescriptor descriptor({
    required String laneKind,
    required String name,
    required String instrumentId,
    required String position,
  }) =>
      (
        laneKind: laneKind,
        name: name.trim(),
        instrumentId: instrumentId.trim(),
        position: position,
      );

  for (final command in plan.commands) {
    final arguments = command.arguments;
    if (command.type == 'row.create') {
      final lane = Map<String, dynamic>.from(arguments['lane'] as Map);
      final position = Map<String, dynamic>.from(arguments['position'] as Map);
      final value = descriptor(
        laneKind: lane['kind'] as String,
        name: arguments['name'] as String,
        instrumentId: lane['instrument_id']?.toString() ?? '',
        position: position['kind'] as String,
      );
      standaloneDescriptorByCommandId[command.commandId] = value;
      standaloneCounts[value] = (standaloneCounts[value] ?? 0) + 1;
      continue;
    }
    if (command.type != 'midi.create_clip' && command.type != 'sample.place') {
      continue;
    }
    final destination =
        Map<String, dynamic>.from(arguments['destination'] as Map);
    final rawNewRow = destination['new_row'];
    if (rawNewRow is! Map) continue;
    final newRow = Map<String, dynamic>.from(rawNewRow);
    final value = descriptor(
      laneKind: command.type == 'midi.create_clip' ? 'midi' : 'audio',
      name: newRow['name'] as String,
      instrumentId: newRow['instrument_id']?.toString() ?? '',
      position: 'end',
    );
    embeddedCounts[value] = (embeddedCounts[value] ?? 0) + 1;
  }

  for (final entry in embeddedCounts.entries) {
    final standaloneCount = standaloneCounts[entry.key] ?? 0;
    if (entry.value > 1 || standaloneCount > 1) {
      throw const AiV3PreparationException(
        'v3_embedded_destination_row_conflict',
      );
    }
  }

  final redundantStandaloneIds = standaloneDescriptorByCommandId.entries
      .where(
        (entry) =>
            embeddedCounts[entry.value] == 1 &&
            !referencedCommandIds.contains(entry.key),
      )
      .map((entry) => entry.key)
      .toSet();
  if (redundantStandaloneIds.isEmpty) return plan;

  return AiV3Plan(
    outcome: plan.outcome,
    userMessage: plan.userMessage,
    commands: List<AiV3Command>.unmodifiable(
      plan.commands.where(
        (command) => !redundantStandaloneIds.contains(command.commandId),
      ),
    ),
    questionOptions: plan.questionOptions,
  );
}

String? _canonicalEffectParameterId(
  String submittedId,
  Set<String> authoritativeIds,
) {
  if (authoritativeIds.contains(submittedId)) return submittedId;
  final folded = submittedId.toLowerCase();
  final matches = authoritativeIds
      .where((candidate) => candidate.toLowerCase() == folded)
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

List<Map<String, dynamic>> _normalizedMidiNotes(List<dynamic> rawNotes) {
  final notes = <Map<String, dynamic>>[];
  for (final raw in rawNotes) {
    if (raw is! Map) {
      throw const AiV3PreparationException('v3_midi_note_state_invalid');
    }
    final note = Map<String, dynamic>.from(raw);
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
      throw const AiV3PreparationException('v3_midi_note_state_invalid');
    }
    notes.add(<String, dynamic>{
      'pitch': pitch,
      'start_beat': start.toDouble(),
      'length_beats': length.toDouble(),
      'velocity': velocity.toDouble(),
    });
  }
  return _sortedMidiNotes(notes);
}

List<Map<String, dynamic>> _sortedMidiNotes(List<Map<String, dynamic>> notes) =>
    aiV3CanonicalMidiNotes(notes);

bool _midiNotesEqual(
  List<Map<String, dynamic>> left,
  List<Map<String, dynamic>> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a['pitch'] != b['pitch'] ||
        a['start_beat'] != b['start_beat'] ||
        a['length_beats'] != b['length_beats'] ||
        a['velocity'] != b['velocity']) {
      return false;
    }
  }
  return true;
}

List<Map<String, dynamic>> _chopMidiNotes(
  List<Map<String, dynamic>> notes, {
  required double stepBeats,
  required double rangeStart,
  required double rangeEnd,
  required double velocityDecayPerSlice,
}) {
  const tiny = 0.000001;
  final result = <Map<String, dynamic>>[];

  void addSegment(
    Map<String, dynamic> source,
    double start,
    double length, {
    int? sliceIndex,
  }) {
    if (length <= tiny) return;
    final sourceVelocity = source['velocity'] as double;
    final velocity = sliceIndex == null
        ? sourceVelocity
        : (sourceVelocity - sliceIndex * velocityDecayPerSlice)
            .clamp(0.05, 1.0)
            .toDouble();
    result.add(<String, dynamic>{
      'pitch': source['pitch'],
      'start_beat': start,
      'length_beats': length,
      'velocity': velocity,
    });
  }

  for (final note in notes) {
    final start = note['start_beat'] as double;
    final end = start + (note['length_beats'] as double);
    if (end <= rangeStart || start >= rangeEnd) {
      addSegment(note, start, end - start);
      continue;
    }

    final chopStart = math.max(start, rangeStart);
    final chopEnd = math.min(end, rangeEnd);
    addSegment(note, start, chopStart - start);
    var cursor = chopStart;
    var sliceIndex = 0;
    while (cursor < chopEnd - tiny) {
      final boundary = math.min(chopEnd, cursor + stepBeats);
      addSegment(
        note,
        cursor,
        boundary - cursor,
        sliceIndex: sliceIndex,
      );
      cursor = boundary;
      sliceIndex += 1;
    }
    addSegment(note, chopEnd, end - chopEnd);
  }
  return _sortedMidiNotes(result);
}

String _rowLabel(Map<int, Map<String, dynamic>> rows, int id) =>
    rows[id]?['name']?.toString().trim().isNotEmpty == true
        ? rows[id]!['name'].toString().trim()
        : 'row $id';

String _clipLabel(Map<String, Map<String, dynamic>> clips, String id) =>
    clips[id]?['name']?.toString().trim().isNotEmpty == true
    ? clips[id]!['name'].toString().trim()
    : 'clip $id';

String _aiV3VerifiedReceiptLabel({
  required String verifiedLabel,
  required Map<String, _AiV3SymbolicResource> symbolicResources,
}) {
  var label = verifiedLabel;
  final resources = symbolicResources.entries.toList(growable: false)
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  for (final entry in resources) {
    if (!label.contains(entry.key)) continue;
    label = label.replaceAll(
      entry.key,
      _aiV3SymbolicResourceDisplayLabel(entry.key, entry.value),
    );
  }
  return label;
}

String _aiV3SymbolicResourceDisplayLabel(
  String resourceKey,
  _AiV3SymbolicResource resource,
) {
  final separator = resourceKey.lastIndexOf('.');
  final output = separator < 0
      ? resourceKey
      : resourceKey.substring(separator + 1);
  return switch (output) {
    'vocals_clip' => 'vocal stem',
    'instrumental_clip' => 'instrumental stem',
    'vocals_row' => 'vocal row',
    'instrumental_row' => 'instrumental row',
    'audio_clip' => 'generated audio clip',
    'midi_clip' => 'generated MIDI clip',
    'midi_row' =>
      resource.rowName?.trim().isNotEmpty == true
          ? resource.rowName!.trim()
          : 'generated MIDI row',
    'left_clip' => 'left split clip',
    'right_clip' => 'right split clip',
    'copy_clip' => 'copied clip',
    'glued_clip' => 'glued clip',
    'group' => 'generated group',
    'row' =>
      resource.rowName?.trim().isNotEmpty == true
          ? resource.rowName!.trim()
          : resource.kind == AiV3ResourceKind.midiRow
          ? 'generated MIDI row'
          : 'generated audio row',
    _ => switch (resource.kind) {
      AiV3ResourceKind.audioRow => 'generated audio row',
      AiV3ResourceKind.midiRow => 'generated MIDI row',
      AiV3ResourceKind.audioClip => 'generated audio clip',
      AiV3ResourceKind.midiClip => 'generated MIDI clip',
      AiV3ResourceKind.group => 'generated group',
    },
  };
}

String _formatNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
