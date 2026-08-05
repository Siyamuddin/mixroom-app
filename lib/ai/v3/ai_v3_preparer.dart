import 'dart:io';
import 'dart:math' as math;

import '../../models/mixing_result.dart';
import 'package:uuid/uuid.dart';
import 'ai_v3_context.dart';
import 'ai_v3_contract.dart';

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
    final simulatedGroupIdByRow = <int, String>{};
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
    final rowCapacity = project['row_capacity'];
    if (rowCapacity is! Map ||
        rowCapacity['current_rows'] is! int ||
        rowCapacity['max_rows'] is! int ||
        rowCapacity['current_rows'] != rows.length) {
      throw const AiV3PreparationException('v3_row_capacity_missing');
    }
    final maximumRows = rowCapacity['max_rows'] as int;
    var simulatedRowCount = rows.length;
    final deletedRowIds = <int>{};
    final unavailableClipIds = <String>{};
    final previouslyMutatedClipIds = <String>{};
    var hasPriorTopologyMutation = false;
    var hasPreparedStemSeparation = false;
    var hasPreparedAudioToMidi = false;
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
      var receiptStatus = 'prepared';
      if ((hasPreparedStemSeparation || hasPreparedAudioToMidi) &&
          const <String>{
            'row.create',
            'row.delete',
            'group.create',
            'group.remove_row',
            'clip.duplicate_to',
            'clip.glue',
            'clip.separate_stems',
            'clip.convert_to_midi',
            'mix.apply_goal',
          }.contains(command.type)) {
        throw const AiV3PreparationException('v3_row_id_unknown');
      }
      switch (command.type) {
        case 'project.set_tempo':
          commandActions.add(AssistantAction(
            type: 'project_edit',
            data: <String, dynamic>{
              'operation': 'set_tempo',
              'tempo_bpm': args['bpm'],
              'time_stretch_audio': args['time_stretch_audio'],
              'preserve_pitch': args['preserve_pitch'],
              'target': const <String, dynamic>{'scope': 'project'},
            },
          ));
          label = 'Set project tempo to ${args['bpm']} BPM';
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
          break;
        case 'row.adjust_gain_db':
          final target = rowTarget(args['row_id'] as int);
          commandActions.add(AssistantAction(
            type: 'row_mix',
            data: <String, dynamic>{
              'operation': 'adjust_gain',
              'delta_db': args['delta_db'],
              'target': target,
            },
          ));
          label =
              'Adjust ${_rowLabel(rowById, args['row_id'] as int)} by ${args['delta_db']} dB';
          break;
        case 'row.set_gain_db':
          final target = rowTarget(args['row_id'] as int);
          commandActions.add(AssistantAction(
            type: 'row_mix',
            data: <String, dynamic>{
              'operation': 'set_gain',
              'gain_db': args['gain_db'],
              'target': target,
            },
          ));
          label =
              'Set ${_rowLabel(rowById, args['row_id'] as int)} gain to ${args['gain_db']} dB';
          break;
        case 'row.adjust_pan':
          final target = rowTarget(args['row_id'] as int);
          commandActions.add(AssistantAction(
            type: 'row_mix',
            data: <String, dynamic>{
              'operation': 'adjust_pan',
              'delta': args['delta_signed'],
              'target': target,
            },
          ));
          label =
              'Adjust ${_rowLabel(rowById, args['row_id'] as int)} pan by ${args['delta_signed']}';
          break;
        case 'row.set_pan':
          final target = rowTarget(args['row_id'] as int);
          commandActions.add(AssistantAction(
            type: 'row_mix',
            data: <String, dynamic>{
              'operation': 'set_pan',
              'pan_signed': args['pan_signed'],
              'target': target,
            },
          ));
          label =
              'Set ${_rowLabel(rowById, args['row_id'] as int)} pan to ${args['pan_signed']}';
          break;
        case 'row.set_muted':
          final muted = args['muted'] as bool;
          final rowId = args['row_id'] as int;
          final target = rowTarget(rowId);
          if (rowById[rowId]?['muted'] == muted) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'row_mute',
              data: <String, dynamic>{
                'operation': muted ? 'mute' : 'unmute',
                'target': target,
              },
            ));
          }
          label = '${muted ? 'Mute' : 'Unmute'} ${_rowLabel(rowById, rowId)}';
          break;
        case 'row.set_soloed':
          final soloed = args['soloed'] as bool;
          commandActions.add(AssistantAction(
            type: 'row_solo',
            data: <String, dynamic>{
              'operation': soloed ? 'solo' : 'unsolo',
              'target': rowTarget(args['row_id'] as int),
            },
          ));
          label =
              '${soloed ? 'Solo' : 'Unsolo'} ${_rowLabel(rowById, args['row_id'] as int)}';
          break;
        case 'row.rename':
          commandActions.add(AssistantAction(
            type: 'row_rename',
            data: <String, dynamic>{
              'operation': 'rename',
              'new_name': args['new_name'],
              'target': rowTarget(args['row_id'] as int),
            },
          ));
          label =
              'Rename ${_rowLabel(rowById, args['row_id'] as int)} to ${args['new_name']}';
          break;
        case 'row.set_instrument':
          final rowId = args['row_id'] as int;
          final instrumentId = args['instrument_id'].toString().trim();
          final target = rowTarget(rowId);
          final row = rowById[rowId]!;
          if (row['lane_kind'] != 'instrument') {
            throw const AiV3PreparationException('v3_instrument_row_required');
          }
          if (!instruments.contains(instrumentId)) {
            throw const AiV3PreparationException('v3_instrument_id_unknown');
          }
          if (row['instrument_id']?.toString().trim() == instrumentId) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(
              AssistantAction(
                type: 'v3_row_set_instrument',
                data: <String, dynamic>{
                  'operation': 'set',
                  'instrument_id': instrumentId,
                  'target': target,
                },
              ),
            );
          }
          row['instrument_id'] = instrumentId;
          label =
              'Set ${_rowLabel(rowById, rowId)} instrument to $instrumentId';
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
          if (positionKind == 'end') {
            target = const <String, dynamic>{'scope': 'project'};
            editorPosition = 'end';
          } else {
            final anchorId = position['row_id'] as int;
            if (deletedRowIds.contains(anchorId)) {
              throw const AiV3PreparationException('v3_row_id_unknown');
            }
            target = rowTarget(anchorId);
            editorPosition = positionKind == 'before' ? 'above' : 'below';
          }
          commandActions.add(AssistantAction(
            type: 'row_create',
            data: <String, dynamic>{
              'operation': 'create',
              'position': editorPosition,
              'name': name,
              'lane_kind': laneKind == 'midi' ? 'instrument' : 'audio',
              if (instrumentId.isNotEmpty) 'instrument_id': instrumentId,
              'target': target,
            },
          ));
          simulatedRowCount += 1;
          hasPriorTopologyMutation = true;
          label = laneKind == 'midi'
              ? 'Create MIDI row $name'
              : 'Create audio row $name';
          break;
        case 'row.delete':
          final rowId = args['row_id'] as int;
          if (deletedRowIds.contains(rowId)) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final target = rowTarget(rowId);
          if (simulatedRowCount <= 1) {
            throw const AiV3PreparationException(
              'v3_row_delete_last_remaining',
            );
          }
          commandActions.add(AssistantAction(
            type: 'row_delete',
            data: <String, dynamic>{
              'operation': 'delete',
              'target': target,
            },
          ));
          deletedRowIds.add(rowId);
          simulatedRowOrder.remove(rowId);
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
          simulatedRowCount -= 1;
          hasPriorTopologyMutation = true;
          label = 'Delete ${_rowLabel(rowById, rowId)}';
          break;
        case 'group.create':
          final requestedIds = (args['row_ids'] as List).cast<int>();
          for (final rowId in requestedIds) {
            if (!rowById.containsKey(rowId) || deletedRowIds.contains(rowId)) {
              throw const AiV3PreparationException('v3_row_id_unknown');
            }
          }
          final orderedIds = requestedIds.toList(growable: false)
            ..sort((left, right) => simulatedRowOrder
                .indexOf(left)
                .compareTo(simulatedRowOrder.indexOf(right)));
          final requestedSet = orderedIds.toSet();
          final matchingGroup = simulatedGroupsById.values.where((group) {
            final members = (group['member_row_ids'] as List? ?? const [])
                .whereType<int>()
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
            for (final rowId in orderedIds)
              if (simulatedGroupIdByRow[rowId] != null)
                simulatedGroupIdByRow[rowId]!,
          };
          final dissolvedGroupIds = <String>[];
          for (final affectedId in affectedGroupIds) {
            final existing = simulatedGroupsById[affectedId]!;
            final oldMembers = (existing['member_row_ids'] as List? ?? const [])
                .whereType<int>()
                .toList(growable: false);
            final remaining = oldMembers
                .where((rowId) => !requestedSet.contains(rowId))
                .toList(growable: false);
            if (remaining.length < 2) {
              simulatedGroupsById.remove(affectedId);
              dissolvedGroupIds.add(affectedId);
              for (final rowId in oldMembers) {
                simulatedGroupIdByRow.remove(rowId);
              }
            } else {
              simulatedGroupsById[affectedId] = <String, dynamic>{
                ...existing,
                'member_row_ids': remaining,
              };
              for (final rowId in oldMembers) {
                if (!remaining.contains(rowId)) {
                  simulatedGroupIdByRow.remove(rowId);
                }
              }
            }
          }
          for (final rowId in orderedIds) {
            simulatedGroupIdByRow[rowId] = groupId;
          }
          simulatedGroupsById[groupId] = <String, dynamic>{
            'group_id': groupId,
            'name': name,
            'member_row_ids': orderedIds,
            'collapsed': false,
          };
          final insertionIndex = orderedIds
              .map(simulatedRowOrder.indexOf)
              .reduce((left, right) => math.min(left, right).toInt());
          simulatedRowOrder.removeWhere(requestedSet.contains);
          simulatedRowOrder.insertAll(insertionIndex, orderedIds);
          commandActions.add(AssistantAction(
            type: 'v3_group_edit',
            data: <String, dynamic>{
              'operation': 'create',
              'group_id': groupId,
              'name': name,
              'row_ids': orderedIds,
              'expected_row_order': List<int>.from(simulatedRowOrder),
              'affected_group_ids': affectedGroupIds.toList()..sort(),
              'dissolved_group_ids': dissolvedGroupIds..sort(),
            },
          ));
          hasPriorTopologyMutation = true;
          label = dissolvedGroupIds.isEmpty
              ? 'Create group $name from ${orderedIds.length} rows'
              : 'Create group $name and dissolve ${dissolvedGroupIds.length} superseded group(s)';
          break;
        case 'group.remove_row':
          final groupId = args['group_id'].toString().trim();
          final rowId = args['row_id'] as int;
          final group = simulatedGroupsById[groupId];
          if (group == null) {
            throw const AiV3PreparationException('v3_group_id_unknown');
          }
          final oldMembers =
              (group['member_row_ids'] as List? ?? const <Object>[])
                  .whereType<int>()
                  .toList(growable: false);
          if (!oldMembers.contains(rowId) ||
              simulatedGroupIdByRow[rowId] != groupId) {
            throw const AiV3PreparationException(
              'v3_group_membership_mismatch',
            );
          }
          final remaining = oldMembers
              .where((candidate) => candidate != rowId)
              .toList(growable: false);
          final dissolves = remaining.length < 2;
          if (dissolves) {
            simulatedGroupsById.remove(groupId);
            for (final memberId in oldMembers) {
              simulatedGroupIdByRow.remove(memberId);
            }
          } else {
            simulatedGroupsById[groupId] = <String, dynamic>{
              ...group,
              'member_row_ids': remaining,
            };
            simulatedGroupIdByRow.remove(rowId);
          }
          commandActions.add(AssistantAction(
            type: 'v3_group_edit',
            data: <String, dynamic>{
              'operation': 'remove_row',
              'group_id': groupId,
              'row_id': rowId,
              'dissolves_group': dissolves,
              'expected_member_row_ids':
                  dissolves ? const <int>[] : List<int>.from(remaining),
            },
          ));
          hasPriorTopologyMutation = true;
          label = dissolves
              ? 'Remove ${_rowLabel(rowById, rowId)} and dissolve ${group['name']}'
              : 'Remove ${_rowLabel(rowById, rowId)} from ${group['name']}';
          break;
        case 'group.set_collapsed':
          final groupId = args['group_id'].toString().trim();
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
            commandActions.add(AssistantAction(
              type: 'v3_group_edit',
              data: <String, dynamic>{
                'operation': 'set_collapsed',
                'group_id': groupId,
                'collapsed': collapsed,
              },
            ));
          }
          label = '${collapsed ? 'Collapse' : 'Expand'} ${group['name']}';
          break;
        case 'clip.move_by_beats':
          final clipId = args['clip_id'] as String;
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'move',
              'delta_ms':
                  (args['delta_beats'] as num).toDouble() * 60000.0 / bpm,
              'target': clipTarget(clipId),
            },
          ));
          label =
              'Move ${_clipLabel(clipById, clipId)} by ${args['delta_beats']} beats';
          break;
        case 'clip.trim_to_range':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final currentStart = (clip?['start_beat'] as num?)?.toDouble();
          final currentLength = (clip?['length_beats'] as num?)?.toDouble();
          if (currentStart == null ||
              currentLength == null ||
              !currentStart.isFinite ||
              !currentLength.isFinite ||
              currentLength <= 0) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          final currentEnd = currentStart + currentLength;
          final startBeat = (args['start_beat'] as num).toDouble();
          final endBeat = (args['end_beat'] as num).toDouble();
          final minimumLengthBeats = 50.0 * bpm / 60000.0;
          const epsilon = 0.000001;
          if (startBeat < currentStart - epsilon ||
              endBeat > currentEnd + epsilon ||
              endBeat - startBeat < minimumLengthBeats) {
            throw const AiV3PreparationException('v3_clip_trim_bounds_invalid');
          }
          final millisecondsPerBeat = 60000.0 / bpm;
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'trim',
              'delta_trim_start_ms':
                  (startBeat - currentStart) * millisecondsPerBeat,
              'delta_trim_end_ms': (endBeat - currentEnd) * millisecondsPerBeat,
              'new_start_ms': startBeat * millisecondsPerBeat,
              'target': target,
            },
          ));
          label =
              'Trim ${_clipLabel(clipById, clipId)} to beats $startBeat–$endBeat';
          break;
        case 'clip.split_at':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId);
          final currentStart = (clip?['start_beat'] as num?)?.toDouble();
          final currentLength = (clip?['length_beats'] as num?)?.toDouble();
          if (currentStart == null ||
              currentLength == null ||
              !currentStart.isFinite ||
              !currentLength.isFinite ||
              currentLength <= 0) {
            throw const AiV3PreparationException('v3_clip_bounds_missing');
          }
          final atBeat = (args['at_beat'] as num).toDouble();
          final minimumLengthBeats = 50.0 * bpm / 60000.0;
          if (atBeat - currentStart < minimumLengthBeats ||
              currentStart + currentLength - atBeat < minimumLengthBeats) {
            throw const AiV3PreparationException('v3_clip_split_point_invalid');
          }
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'cut',
              'cut_ms': atBeat * 60000.0 / bpm,
              'target': target,
            },
          ));
          label = 'Split ${_clipLabel(clipById, clipId)} at beat $atBeat';
          break;
        case 'clip.duplicate_to':
          if (hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId);
          final destinationRowId = args['destination_row_id'] as int;
          rowTarget(destinationRowId);
          final destinationRow = rowById[destinationRowId];
          if (destinationRow == null) {
            throw const AiV3PreparationException('v3_row_id_unknown');
          }
          final isMidi = clip?['kind'] == 'midi';
          final destinationIsMidi = destinationRow['lane_kind'] == 'instrument';
          if (isMidi != destinationIsMidi) {
            throw const AiV3PreparationException(
              'v3_clip_destination_lane_mismatch',
            );
          }
          final startBeat = (args['start_beat'] as num).toDouble();
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'duplicate',
              'paste_start_ms': startBeat * 60000.0 / bpm,
              'row_index': destinationRow['display_index'],
              'new_row_index': destinationRow['display_index'],
              'target': target,
            },
          ));
          label =
              'Duplicate ${_clipLabel(clipById, clipId)} to ${_rowLabel(rowById, destinationRowId)} at beat $startBeat';
          break;
        case 'clip.delete':
          final clipId = args['clip_id'] as String;
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'delete',
              'target': clipTarget(clipId),
            },
          ));
          unavailableClipIds.add(clipId);
          label = 'Delete ${_clipLabel(clipById, clipId)}';
          break;
        case 'clip.glue':
          if (hasPriorTopologyMutation) {
            throw const AiV3PreparationException('v3_clip_id_unknown');
          }
          final requestedIds = (args['clip_ids'] as List)
              .cast<String>()
              .map((value) => value.trim())
              .toList(growable: false);
          if (requestedIds.any(previouslyMutatedClipIds.contains)) {
            throw const AiV3PreparationException(
              'v3_clip_glue_source_already_mutated',
            );
          }
          final resolved = requestedIds.map((clipId) {
            clipTarget(clipId, requireAudio: true);
            return clipById[clipId]!;
          }).toList(growable: false)
            ..sort((left, right) {
              final startComparison =
                  ((left['start_beat'] as num?)?.toDouble() ?? 0).compareTo(
                (right['start_beat'] as num?)?.toDouble() ?? 0,
              );
              if (startComparison != 0) return startComparison;
              return left['clip_id']
                  .toString()
                  .compareTo(right['clip_id'].toString());
            });
          final rowIds =
              resolved.map((clip) => clip['row_id']).whereType<int>().toSet();
          if (rowIds.length != 1) {
            throw const AiV3PreparationException(
              'v3_clip_glue_row_mismatch',
            );
          }
          final starts = resolved
              .map((clip) => (clip['start_beat'] as num?)?.toDouble())
              .toList(growable: false);
          final ends = resolved.map((clip) {
            final start = (clip['start_beat'] as num?)?.toDouble();
            final length =
                (clip['timeline_length_beats'] as num?)?.toDouble() ??
                    (clip['length_beats'] as num?)?.toDouble();
            return start == null || length == null ? null : start + length;
          }).toList(growable: false);
          if (starts.any((value) => value == null || !value.isFinite) ||
              ends.any((value) => value == null || !value.isFinite)) {
            throw const AiV3PreparationException(
              'v3_clip_bounds_missing',
            );
          }
          final startBeat =
              starts.cast<double>().reduce((a, b) => math.min(a, b));
          final endBeat = ends.cast<double>().reduce((a, b) => math.max(a, b));
          if ((endBeat - startBeat) * 60000.0 / bpm <= 50.0) {
            throw const AiV3PreparationException(
              'v3_clip_glue_bounds_invalid',
            );
          }
          final rowId = rowIds.single;
          final labelValue = args['label']?.toString().trim() ?? '';
          final orderedIds = resolved
              .map((clip) => clip['clip_id'].toString())
              .toList(growable: false);
          commandActions.add(AssistantAction(
            type: 'v3_clip_glue',
            data: <String, dynamic>{
              'source_clip_ids': orderedIds,
              'label': labelValue.isEmpty ? 'Glued Clip' : labelValue,
              'start_ms': startBeat * 60000.0 / bpm,
              'duration_ms': (endBeat - startBeat) * 60000.0 / bpm,
              'target': <String, dynamic>{
                ...rowTarget(rowId),
                'source_clip_ids': orderedIds,
              },
            },
          ));
          unavailableClipIds.addAll(orderedIds);
          previouslyMutatedClipIds.addAll(orderedIds);
          label =
              'Glue ${orderedIds.length} clips on ${_rowLabel(rowById, rowId)} as ${labelValue.isEmpty ? 'Glued Clip' : labelValue} from beat $startBeat to $endBeat';
          break;
        case 'clip.separate_stems':
          if (hasPriorTopologyMutation) {
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
          if (clips.length + 2 > 128) {
            throw const AiV3PreparationException(
              'v3_clip_capacity_exceeded',
            );
          }
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final rowId = clip?['row_id'];
          final startBeat = (clip?['start_beat'] as num?)?.toDouble();
          final lengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble();
          final sourcePath = clip?['source_file']?.toString().trim() ?? '';
          if (rowId is! int ||
              startBeat == null ||
              !startBeat.isFinite ||
              lengthBeats == null ||
              !lengthBeats.isFinite ||
              lengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_bounds_missing',
            );
          }
          if (sourcePath.isEmpty) {
            throw const AiV3PreparationException(
              'v3_stem_source_unreadable',
            );
          }
          final sourceAvailable = clip?['source_available'];
          final sourceFile = File(sourcePath);
          final absoluteSourceUnavailable = sourceFile.isAbsolute &&
              (!sourceFile.existsSync() || sourceFile.lengthSync() <= 44);
          if (sourceAvailable == false || absoluteSourceUnavailable) {
            throw const AiV3PreparationException(
              'v3_stem_source_unreadable',
            );
          }
          final sourceName = clip?['name']?.toString().trim() ?? '';
          final baseName = sourceName.isEmpty ? 'Separated' : sourceName;
          final vocalsLabel = _boundedStemLabel(baseName, 'Vocals');
          final instrumentalLabel = _boundedStemLabel(baseName, 'Instrumental');
          commandActions.add(AssistantAction(
            type: 'v3_clip_separate_stems',
            data: <String, dynamic>{
              'source_clip_id': clipId,
              'source_row_id': rowId,
              'source_row_index': target['row_index'],
              'start_ms': startBeat * 60000.0 / bpm,
              'duration_ms': lengthBeats * 60000.0 / bpm,
              'vocals_label': vocalsLabel,
              'instrumental_label': instrumentalLabel,
              'target': target,
            },
          ));
          simulatedRowCount += 2;
          hasPriorTopologyMutation = true;
          hasPreparedStemSeparation = true;
          label =
              'Separate ${_clipLabel(clipById, clipId)} into $vocalsLabel and $instrumentalLabel on two new rows; preserve the source clip';
          break;
        case 'clip.convert_to_midi':
          if (hasPriorTopologyMutation) {
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
          if (clips.length + 1 > 128) {
            throw const AiV3PreparationException(
              'v3_clip_capacity_exceeded',
            );
          }
          final clipId = args['clip_id'] as String;
          final instrumentId = args['instrument_id'].toString().trim();
          if (!instruments.contains(instrumentId)) {
            throw const AiV3PreparationException(
              'v3_instrument_id_unknown',
            );
          }
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final rowId = clip?['row_id'];
          final startBeat = (clip?['start_beat'] as num?)?.toDouble();
          final lengthBeats =
              (clip?['timeline_length_beats'] as num?)?.toDouble();
          final sourcePath = clip?['source_file']?.toString().trim() ?? '';
          if (rowId is! int ||
              startBeat == null ||
              !startBeat.isFinite ||
              lengthBeats == null ||
              !lengthBeats.isFinite ||
              lengthBeats <= 0) {
            throw const AiV3PreparationException(
              'v3_clip_bounds_missing',
            );
          }
          if (sourcePath.isEmpty) {
            throw const AiV3PreparationException(
              'v3_audio_to_midi_source_unreadable',
            );
          }
          final sourceAvailable = clip?['source_available'];
          final sourceFile = File(sourcePath);
          final absoluteSourceUnavailable = sourceFile.isAbsolute &&
              (!sourceFile.existsSync() || sourceFile.lengthSync() <= 44);
          if (sourceAvailable == false || absoluteSourceUnavailable) {
            throw const AiV3PreparationException(
              'v3_audio_to_midi_source_unreadable',
            );
          }
          final sourceName = clip?['name']?.toString().trim() ?? '';
          final outputLabel = _boundedMidiConversionLabel(sourceName);
          commandActions.add(AssistantAction(
            type: 'v3_clip_convert_to_midi',
            data: <String, dynamic>{
              'source_clip_id': clipId,
              'source_row_id': rowId,
              'source_row_index': target['row_index'],
              'start_ms': startBeat * 60000.0 / bpm,
              'duration_ms': lengthBeats * 60000.0 / bpm,
              'instrument_id': instrumentId,
              'output_label': outputLabel,
              'target': target,
            },
          ));
          simulatedRowCount += 1;
          hasPriorTopologyMutation = true;
          hasPreparedAudioToMidi = true;
          label =
              'Convert ${_clipLabel(clipById, clipId)} to MIDI with $instrumentId on a new row below the source; preserve the source clip';
          break;
        case 'clip.set_pitch_semitones':
        case 'clip.adjust_pitch_semitones':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final currentPitch = (clip?['pitch_semitones'] as num?)?.toDouble();
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
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'pitch_shift',
              'mode': 'set',
              'new_pitch_semitones': finalPitch,
              'target': target,
            },
          ));
          label =
              'Set ${_clipLabel(clipById, clipId)} pitch to $finalPitch semitones';
          break;
        case 'clip.set_timeline_length_beats':
        case 'clip.scale_timeline_length':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
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
                if (other['clip_id'] == clipId ||
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
              'Set ${_clipLabel(clipById, clipId)} timeline length to $finalLengthBeats beats${preservePitch ? ' while preserving pitch' : ' with repitching'}';
          break;
        case 'clip.set_source_tempo_bpm':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final sourceTempo = (args['source_tempo_bpm'] as num).toDouble();
          final currentSourceTempo =
              (clip?['source_tempo_bpm'] as num?)?.toDouble();
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
              'Set ${_clipLabel(clipById, clipId)} source tempo to $sourceTempo BPM';
          break;
        case 'clip.set_tempo_follow_mode':
          final clipId = args['clip_id'] as String;
          final clip = clipById[clipId];
          final target = clipTarget(clipId, requireAudio: true);
          final mode = args['mode'] as String;
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
                if (other['clip_id'] == clipId ||
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
              'Set ${_clipLabel(clipById, clipId)} tempo-follow mode to $mode';
          break;
        case 'clip.align_tempo_to_project':
        case 'project.set_tempo_from_clip':
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
            commandActions.add(AssistantAction(
              type: 'project_edit',
              data: <String, dynamic>{
                'operation': 'set_tempo',
                'tempo_bpm': projectTempo,
                'time_stretch_audio': false,
                'preserve_pitch': mode == 'preserve_pitch',
                'target': const <String, dynamic>{'scope': 'project'},
              },
            ));
          }
          commandActions.add(AssistantAction(
            type: 'clip_edit',
            data: <String, dynamic>{
              'operation': 'tempo_follow',
              'mode': mode,
              'target': target,
            },
          ));
          label = command.type == 'project.set_tempo_from_clip'
              ? 'Detect ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM, set the project to ${detectedTempo.round()} BPM, and follow in $mode mode'
              : 'Detect ${_clipLabel(clipById, clipId)} at ${_formatNumber(detectedTempo)} BPM and align it to the project in $mode mode';
          break;
        case 'clip.trim_silence':
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
          break;
        case 'clip.align_first_sound':
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
          break;
        case 'midi.transpose':
          final clipId = args['clip_id'] as String;
          clipTarget(clipId, requireMidi: true);
          final currentNotes = simulatedMidiNotesByClipId[clipId] ??
              const <Map<String, dynamic>>[];
          final semitones = args['semitones'] as int;
          simulatedMidiNotesByClipId[clipId] = _sortedMidiNotes(
            currentNotes
                .map((note) => <String, dynamic>{
                      ...note,
                      'pitch': ((note['pitch'] as int) + semitones)
                          .clamp(0, 127)
                          .toInt(),
                    })
                .toList(growable: false),
          );
          commandActions.add(AssistantAction(
            type: 'midi_compose',
            data: <String, dynamic>{
              'operation': 'transpose_notes',
              'semitones': semitones,
              'target': clipTarget(clipId, requireMidi: true),
            },
          ));
          label =
              'Transpose ${_clipLabel(clipById, clipId)} by $semitones semitones';
          break;
        case 'midi.create_clip':
          final arrangementLimit =
              ((project['beats_per_bar'] as num?)?.toDouble() ?? 4.0) * 8.0;
          final clipStart = (args['start_beat'] as num).toDouble();
          final clipLength = (args['length_beats'] as num).toDouble();
          final notes = (args['notes'] as List).whereType<Map>();
          if (clipLength > arrangementLimit ||
              notes.any((note) =>
                  (note['start_beat'] as num).toDouble() +
                      (note['length_beats'] as num).toDouble() >
                  clipLength)) {
            throw const AiV3PreparationException(
              'v3_midi_arrangement_limit',
            );
          }
          final resolved = destination(args['destination'], midi: true);
          commandActions.addAll(resolved.setup);
          final instrumentId = (resolved.target['instrument_id'] ??
                  rowById[(args['destination'] as Map)['row_id']]
                      ?['instrument_id'])
              ?.toString();
          commandActions.add(AssistantAction(
            type: 'midi_compose',
            data: <String, dynamic>{
              'operation': 'create_clip',
              'target': resolved.target,
              'notes': args['notes'],
              'start_ms': clipStart * 60000.0 / bpm,
              'length_beats': args['length_beats'],
              'exact_notes': true,
              'create_new_clip': true,
              if ((instrumentId ?? '').isNotEmpty)
                'instrument_id': instrumentId,
            },
          ));
          label =
              'Create MIDI clip with ${(args['notes'] as List).length} notes';
          break;
        case 'midi.replace_notes':
        case 'midi.append_notes':
        case 'midi.chop_notes':
          final clipId = args['clip_id'] as String;
          final target = clipTarget(clipId, requireMidi: true);
          final clip = clipById[clipId]!;
          final clipLength = simulatedMidiLengthByClipId[clipId] ??
              (clip['length_beats'] as num?)?.toDouble();
          if (clipLength == null || !clipLength.isFinite || clipLength <= 0) {
            throw const AiV3PreparationException(
              'v3_midi_clip_length_invalid',
            );
          }
          final currentNotes = simulatedMidiNotesByClipId[clipId] ??
              const <Map<String, dynamic>>[];
          late final List<Map<String, dynamic>> nextNotes;
          if (command.type == 'midi.replace_notes') {
            nextNotes = _normalizedMidiNotes(args['notes'] as List);
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
            final appendAnchor = math.max(clipLength, existingNoteEnd);
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
            simulatedMidiLengthByClipId[clipId] = appendAnchor + appendedSpan;
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
                (range?['end_beat'] as num?)?.toDouble() ?? clipLength;
            if (rangeStart < 0 ||
                rangeEnd <= rangeStart ||
                rangeEnd > clipLength + 0.000001) {
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
          final finalClipLength =
              simulatedMidiLengthByClipId[clipId] ?? clipLength;
          if (nextNotes.any((note) =>
              (note['start_beat'] as double) +
                  (note['length_beats'] as double) >
              finalClipLength + 0.000001)) {
            throw const AiV3PreparationException(
              'v3_midi_note_out_of_bounds',
            );
          }
          if (nextNotes.length > 512) {
            throw const AiV3PreparationException(
              'v3_midi_result_limit',
            );
          }
          simulatedMidiNotesByClipId[clipId] = nextNotes;
          final alreadySatisfied = command.type != 'midi.append_notes' &&
              _midiNotesEqual(currentNotes, nextNotes);
          if (alreadySatisfied) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'midi_compose',
              data: <String, dynamic>{
                'operation': 'replace_notes',
                'target': target,
                'notes': nextNotes,
                'exact_notes': true,
                'preserve_existing_notes': false,
                'preserve_clip_state': true,
                if (command.type == 'midi.append_notes')
                  'final_length_beats': finalClipLength,
              },
            ));
          }
          label = switch (command.type) {
            'midi.replace_notes' =>
              'Replace notes in ${_clipLabel(clipById, clipId)}',
            'midi.append_notes' =>
              'Append notes to ${_clipLabel(clipById, clipId)}',
            _ => 'Chop notes in ${_clipLabel(clipById, clipId)}',
          };
          break;
        case 'effect.ensure_configured':
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
          commandActions.add(AssistantAction(
            type: 'v3_effect_configure',
            data: <String, dynamic>{
              'operation': 'ensure_configured',
              'effect_id': effectId,
              'parameters': parameters,
              'target': rowTarget(args['row_id'] as int),
            },
          ));
          label =
              'Add/configure $effectId on ${_rowLabel(rowById, args['row_id'] as int)}';
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
          }
          break;
        case 'automation.gain_fade':
          final startMs =
              (args['start_beat'] as num).toDouble() * 60000.0 / bpm;
          final endMs = (args['end_beat'] as num).toDouble() * 60000.0 / bpm;
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

          commandActions.add(AssistantAction(
            type: 'automation_edit',
            data: <String, dynamic>{
              'operation': 'set_points',
              'target': <String, dynamic>{
                ...rowTarget(args['row_id'] as int),
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
          ));
          label =
              'Add gain fade on ${_rowLabel(rowById, args['row_id'] as int)}';
          break;
        case 'automation.set_points':
          final rowId = args['row_id'] as int;
          final targetId = args['automation_target_id'].toString();
          final target = automationTarget(rowId, targetId);
          final points = (args['points'] as List)
              .whereType<Map>()
              .map((raw) => <String, dynamic>{
                    'time_ms': (raw['beat'] as num).toDouble() * 60000.0 / bpm,
                    'value': (raw['value_normalized'] as num).toDouble(),
                  })
              .toList(growable: false);
          commandActions.add(AssistantAction(
            type: 'v3_automation_points',
            data: <String, dynamic>{
              'operation': 'set_points',
              'target': target,
              'points': points,
            },
          ));
          label =
              'Set ${points.length} automation points on ${_rowLabel(rowById, rowId)}';
          break;
        case 'automation.clear':
          final rowId = args['row_id'] as int;
          final targetId = args['automation_target_id'].toString();
          commandActions.add(AssistantAction(
            type: 'v3_automation_points',
            data: <String, dynamic>{
              'operation': 'clear',
              'target': automationTarget(rowId, targetId),
              'points': const <Map<String, dynamic>>[],
            },
          ));
          label = 'Clear automation on ${_rowLabel(rowById, rowId)}';
          break;
        case 'sample.place':
          final resolved = destination(args['destination'], midi: false);
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
                  (placement['start_beat'] as num).toDouble() * 60000.0 / bpm,
              'target': resolved.target,
            });
          }
          commandActions.add(AssistantAction(
            type: 'sample_insert',
            data: <String, dynamic>{
              'operation': 'insert_audio_clips',
              'items': items,
              'target': resolved.target,
            },
          ));
          label =
              'Place ${items.length} library sample${items.length == 1 ? '' : 's'}';
          break;
        case 'sample.replace':
          final clipId = args['clip_id'] as String;
          final target = clipTarget(clipId, requireAudio: true);
          final assetId = args['asset_id'] as String;
          final asset = assetById[assetId];
          if (asset == null) {
            throw const AiV3PreparationException('v3_asset_id_unknown');
          }
          final sourcePath = asset['path']?.toString().trim() ?? '';
          if (sourcePath.isEmpty) {
            throw const AiV3PreparationException('v3_asset_id_unknown');
          }
          final clip = clipById[clipId]!;
          final currentSource = clip['source_file']?.toString().trim() ?? '';
          if (currentSource.isNotEmpty && currentSource == sourcePath) {
            receiptStatus = 'already_satisfied';
          } else {
            commandActions.add(AssistantAction(
              type: 'v3_sample_replace',
              data: <String, dynamic>{
                'operation': 'replace',
                'asset_id': assetId,
                'library_path': sourcePath,
                'target': target,
              },
            ));
          }
          final assetName = asset['filename']?.toString().trim();
          label =
              'Replace ${_clipLabel(clipById, clipId)} with ${assetName == null || assetName.isEmpty ? assetId : assetName}';
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
            'group' => simulatedGroupsById[rawTarget['group_id']]?['name']
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
      });
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
      .where((entry) => embeddedCounts[entry.value] == 1)
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

List<Map<String, dynamic>> _sortedMidiNotes(
  List<Map<String, dynamic>> notes,
) {
  final sorted = notes
      .map((note) => Map<String, dynamic>.from(note))
      .toList(growable: true);
  sorted.sort((a, b) {
    var result =
        (a['start_beat'] as double).compareTo(b['start_beat'] as double);
    if (result != 0) return result;
    result = (a['pitch'] as int).compareTo(b['pitch'] as int);
    if (result != 0) return result;
    result =
        (a['length_beats'] as double).compareTo(b['length_beats'] as double);
    if (result != 0) return result;
    return (a['velocity'] as double).compareTo(b['velocity'] as double);
  });
  return List<Map<String, dynamic>>.unmodifiable(sorted);
}

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

String _formatNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
