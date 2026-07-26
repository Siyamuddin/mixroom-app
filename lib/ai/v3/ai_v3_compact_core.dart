import 'dart:collection';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../ai_gain_units.dart';
import 'ai_v3_domain_registry.dart';
import 'ai_v3_planning_snapshot.dart';

const String aiV3CompactCoreSchemaVersion = 'compact_core_v3_shadow_1';

class AiV3CompactCoreException implements Exception {
  const AiV3CompactCoreException(this.code);

  final String code;

  @override
  String toString() => 'AiV3CompactCoreException($code)';
}

class CompactCoreV3 {
  CompactCoreV3._(Map<String, dynamic> data) : data = _freezeMap(data);

  final Map<String, dynamic> data;

  String get canonicalJson => jsonEncode(data);
  int get serializedBytes => utf8.encode(canonicalJson).length;
  int get approximateTokens => (canonicalJson.length / 4).ceil();

  Map<String, dynamic> get safeMetadata {
    final clips = data['clips'] as Map;
    final resources = data['resources'] as Map;
    return <String, dynamic>{
      'status': 'captured',
      'schema_version': aiV3CompactCoreSchemaVersion,
      'serialized_bytes': serializedBytes,
      'approximate_tokens': approximateTokens,
      'counts': <String, dynamic>{
        'rows': (data['rows'] as List).length,
        'groups': (data['groups'] as List).length,
        'clips_total': clips['total_count'],
        'clips_returned': clips['returned_count'],
        'conversation_turns': (data['conversation'] as List).length,
        'resource_categories': resources.length,
        'domains': (data['capability_domains'] as List).length,
      },
    };
  }
}

class AiV3CompactCoreBuilder {
  const AiV3CompactCoreBuilder({
    this.maxRows = 32,
    this.maxClipSummaries = 64,
    this.maxResourceIdentities = 32,
    this.maxConversationTurns = 8,
    this.domainDefinitions = aiV3DomainDefinitions,
  });

  final int maxRows;
  final int maxClipSummaries;
  final int maxResourceIdentities;
  final int maxConversationTurns;
  final List<AiV3DomainDefinition> domainDefinitions;

  CompactCoreV3 build({
    required PlanningSnapshotV3 snapshot,
    required List<Map<String, String>> conversation,
  }) {
    if (snapshot.rowById.length > maxRows) {
      throw const AiV3CompactCoreException('compact_core_row_limit');
    }
    final project = _map(snapshot.data['project']);
    final sourceSelection = _map(snapshot.data['selection']);
    final selection = <String, dynamic>{
      if (sourceSelection['selected_row_id'] != null)
        'selected_row_id': sourceSelection['selected_row_id'],
      'selected_clip_ids': List<String>.from(
        sourceSelection['selected_clip_ids'] as List? ?? const <String>[],
      ),
      if (sourceSelection['primary_selected_clip_id'] != null)
        'primary_selected_clip_id': sourceSelection['primary_selected_clip_id'],
    };
    final requestState = _map(snapshot.data['request_state']);
    final transport = _map(snapshot.data['transport']);
    final bpm = (project['bpm'] as num?)?.toDouble();
    if (bpm == null || !bpm.isFinite || bpm <= 0) {
      throw const AiV3CompactCoreException('compact_core_tempo_invalid');
    }

    final clipsByRow = <int, List<Map<String, dynamic>>>{};
    for (final clip in snapshot.clipById.values) {
      final rowId = clip['row_id'];
      if (rowId is int) {
        (clipsByRow[rowId] ??= <Map<String, dynamic>>[]).add(clip);
      }
    }
    final rows = snapshot.rowById.values.toList(growable: false)
      ..sort((left, right) => (left['display_index'] as int)
          .compareTo(right['display_index'] as int));
    final compactRows = rows.map((row) {
      final rowId = row['row_id'] as int;
      final rowClips = clipsByRow[rowId] ?? const <Map<String, dynamic>>[];
      final mixer = _map(row['mixer']);
      final audioFacts = _map(row['audio_facts']);
      return <String, dynamic>{
        'row_id': rowId,
        'display_index': row['display_index'],
        'name': row['name'],
        'lane_kind': row['lane_kind'],
        if ((row['group_id']?.toString().trim() ?? '').isNotEmpty)
          'group_id': row['group_id'],
        if ((row['instrument_id']?.toString().trim() ?? '').isNotEmpty)
          'instrument_id': row['instrument_id'],
        if ((row['role_override']?.toString().trim() ?? '').isNotEmpty)
          'role_override': row['role_override'],
        'gain_db': rowGainUiToDb(
          (mixer['gain_ui'] as num?)?.toDouble() ?? 2.0,
        ),
        'pan_signed':
            (((mixer['pan_01'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0) *
                    2.0) -
                1.0,
        'muted': mixer['muted'] == true,
        'soloed': mixer['soloed'] == true,
        'clip_count': rowClips.length,
        'has_audio_content': rowClips.any((clip) => clip['kind'] == 'audio'),
        'has_midi_content': rowClips.any((clip) => clip['kind'] == 'midi'),
        'loaded_effect_count':
            (row['effects'] as List? ?? const <Object>[]).length,
        'has_usable_signal': audioFacts['has_usable_signal'] == true,
        'analysis_available': audioFacts['analysis_available'] == true,
        'reference_suitable': audioFacts['reference_suitable'] == true,
      };
    }).toList(growable: false);
    final compactGroups = snapshot.groupById.values.map((group) {
      return <String, dynamic>{
        'group_id': group['group_id'],
        'name': group['name'],
        'member_row_ids': List<int>.from(
          group['member_row_ids'] as List? ?? const <int>[],
        ),
        'collapsed': group['collapsed'] == true,
      };
    }).toList(growable: false)
      ..sort((left, right) =>
          left['group_id'].toString().compareTo(right['group_id'].toString()));

    final orderedClips = _orderedClips(snapshot, selection);
    final returnedClips = orderedClips
        .take(maxClipSummaries)
        .map((clip) => _clipSummary(clip, bpm))
        .toList(growable: false);

    final resources = _resources(snapshot);
    final domains = _domains(
      snapshot: snapshot,
      resources: resources,
    );
    final recentConversation = conversation
        .where((turn) =>
            const <String>{'user', 'assistant'}.contains(turn['role']) &&
            (turn['content'] ?? '').trim().isNotEmpty)
        .map((turn) => <String, String>{
              'role': turn['role']!,
              'content': turn['content']!.trim(),
            })
        .toList(growable: false);
    final boundedConversation =
        recentConversation.length <= maxConversationTurns
            ? recentConversation
            : recentConversation.sublist(
                recentConversation.length - maxConversationTurns,
              );
    final playheadMs = (project['playhead_ms'] as num).toDouble();
    return CompactCoreV3._(<String, dynamic>{
      'schema_version': aiV3CompactCoreSchemaVersion,
      'snapshot_id': snapshot.snapshotId,
      'state_digest': snapshot.stateDigest,
      if ((snapshot.projectId ?? '').isNotEmpty)
        'project_id': snapshot.projectId,
      'project': <String, dynamic>{
        'bpm': bpm,
        'beats_per_bar': project['beats_per_bar'],
        'beat_unit': project['beat_unit'],
        'key': project['project_key'],
        'estimated_key': project['estimated_key'],
        'playhead_ms': playheadMs,
        'playhead_beat': playheadMs * bpm / 60000.0,
        'row_count': snapshot.rowById.length,
        'clip_count': snapshot.clipById.length,
        'row_capacity': project['row_capacity'],
      },
      'transport': <String, dynamic>{
        'playing': transport['playing'],
        'recording': transport['recording'],
        'metronome_enabled': transport['metronome_enabled'],
        'loop_enabled': transport['loop_enabled'],
        'loop_start_ms': transport['loop_start_ms'],
        'loop_end_ms': transport['loop_end_ms'],
      },
      'selection': selection,
      'request_state': <String, dynamic>{
        'mode': requestState['mode'],
        if ((requestState['pending_plan_id']?.toString().trim() ?? '')
            .isNotEmpty)
          'pending_plan_id': requestState['pending_plan_id'],
      },
      'rows': compactRows,
      'groups': compactGroups,
      'clips': <String, dynamic>{
        'total_count': orderedClips.length,
        'returned_count': returnedClips.length,
        'has_more': returnedClips.length < orderedClips.length,
        'items': returnedClips,
      },
      'resources': resources,
      'capability_domains': domains,
      'conversation': boundedConversation,
    });
  }

  List<Map<String, dynamic>> _orderedClips(
    PlanningSnapshotV3 snapshot,
    Map<String, dynamic> selection,
  ) {
    final ordered = <Map<String, dynamic>>[];
    final seen = <String>{};
    void add(String? id) {
      if (id == null || !seen.add(id)) return;
      final clip = snapshot.clipById[id];
      if (clip != null) ordered.add(clip);
    }

    add(selection['primary_selected_clip_id']?.toString());
    for (final id
        in (selection['selected_clip_ids'] as List? ?? const <Object>[])) {
      add(id.toString());
    }
    final rowDisplayById = <int, int>{
      for (final row in snapshot.rowById.values)
        row['row_id'] as int: row['display_index'] as int,
    };
    final remaining = snapshot.clipById.values
        .where((clip) => !seen.contains(clip['clip_id']))
        .toList(growable: false)
      ..sort((left, right) {
        final byStart = ((left['start_seconds'] as num?)?.toDouble() ?? 0)
            .compareTo((right['start_seconds'] as num?)?.toDouble() ?? 0);
        if (byStart != 0) return byStart;
        final byRow = (rowDisplayById[left['row_id']] ?? 0)
            .compareTo(rowDisplayById[right['row_id']] ?? 0);
        if (byRow != 0) return byRow;
        return left['clip_id']
            .toString()
            .compareTo(right['clip_id'].toString());
      });
    ordered.addAll(remaining);
    return ordered;
  }

  Map<String, dynamic> _clipSummary(Map<String, dynamic> clip, double bpm) {
    final startSeconds = (clip['start_seconds'] as num?)?.toDouble() ?? 0;
    final trimStart = (clip['trim_start_ms'] as num?)?.toDouble() ?? 0;
    final trimEnd = (clip['trim_end_ms'] as num?)?.toDouble() ?? trimStart;
    final kind = clip['kind']?.toString() ?? 'audio';
    return <String, dynamic>{
      'clip_id': clip['clip_id'],
      'row_id': clip['row_id'],
      'kind': kind,
      'name': clip['name'],
      'start_beat': startSeconds * bpm / 60.0,
      'length_beats':
          (trimEnd - trimStart).clamp(0.0, double.infinity) * bpm / 60000.0,
      if (kind == 'midi' &&
          (clip['instrument_id']?.toString().trim() ?? '').isNotEmpty)
        'instrument_id': clip['instrument_id'],
      if (kind != 'midi' &&
          (clip['source_file_path']?.toString().trim() ?? '').isNotEmpty)
        'source_name': p.basename(clip['source_file_path'].toString()),
    };
  }

  Map<String, dynamic> _resources(PlanningSnapshotV3 snapshot) {
    final catalogs = _map(snapshot.data['catalogs']);
    final instrumentCatalog = _strings(catalogs['instrument_ids']);
    final loadedInstruments = snapshot.rowById.values
        .map((row) => row['instrument_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final effectCatalog = (catalogs['effects'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((effect) => effect['effect_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final loadedEffects = <String>{};
    void collectEffects(Object? rawEffects) {
      for (final effect
          in (rawEffects as List? ?? const <Object>[]).whereType<Map>()) {
        final id = effect['effect_id']?.toString().trim() ?? '';
        if (id.isNotEmpty) loadedEffects.add(id);
      }
    }

    for (final row in snapshot.rowById.values) {
      collectEffects(row['effects']);
    }
    for (final group in snapshot.groupById.values) {
      collectEffects(group['effects']);
    }
    collectEffects(_map(snapshot.data['master'])['effects']);
    final knownEffects = <String>{...effectCatalog, ...loadedEffects};

    final loadedAssetIds = <String>{};
    for (final clip in snapshot.clipById.values) {
      final source = clip['source_file_path']?.toString() ?? '';
      if (source.isEmpty) continue;
      for (final asset in snapshot.libraryAssetById.values) {
        final assetPath = asset['path']?.toString() ?? '';
        if (assetPath.isNotEmpty &&
            (source == assetPath || source.endsWith('/$assetPath'))) {
          loadedAssetIds.add(asset['asset_id'].toString());
        }
      }
    }
    final analysisRowIds = snapshot.rowById.values
        .where((row) {
          final analysis = _map(row['analysis']);
          return row['has_audio'] == true &&
              _map(analysis['audio_statistics']).isNotEmpty;
        })
        .map((row) => row['row_id'].toString())
        .toList()
      ..sort();
    final automationIds = <String>{};
    var automationTargetCount = 0;
    void collectAutomation(Object? rawTargets) {
      for (final target
          in (rawTargets as List? ?? const <Object>[]).whereType<Map>()) {
        final id =
            (target['target_id'] ?? target['id'])?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          automationTargetCount += 1;
          automationIds.add(id);
        }
      }
    }

    for (final row in snapshot.rowById.values) {
      collectAutomation(row['automation_targets']);
    }

    const externalCapabilityIds = <String>{
      'daw.stem_separate',
      'daw.audio_enhance',
      'daw.midi_compose.audio_to_midi',
    };
    final serviceCapabilities = _strings(
      _map(snapshot.data['services'])['capabilities'],
    );
    final externalServices = serviceCapabilities
        .where(externalCapabilityIds.contains)
        .toList(growable: false);
    final pluginAccess = catalogs['plugin_access']?.toString().trim() ?? '';

    return <String, dynamic>{
      'instruments': _resourceEnvelope(
        available: instrumentCatalog.isNotEmpty,
        totalCount: instrumentCatalog.length,
        identities: loadedInstruments,
      ),
      'effects': _resourceEnvelope(
        available: knownEffects.isNotEmpty,
        totalCount: knownEffects.length,
        identities: loadedEffects.toList()..sort(),
      ),
      'hosted_plugins': _resourceEnvelope(
        available: pluginAccess.isNotEmpty,
        totalCount: null,
        identities: const <String>[],
        unknownRemainder: pluginAccess.isNotEmpty,
      ),
      'library_assets': _resourceEnvelope(
        available: snapshot.libraryAssetById.isNotEmpty,
        totalCount: snapshot.libraryAssetById.length,
        identities: loadedAssetIds.toList()..sort(),
      ),
      'analysis_results': _resourceEnvelope(
        available: analysisRowIds.isNotEmpty,
        totalCount: analysisRowIds.length,
        identities: analysisRowIds,
      ),
      'automation_targets': _resourceEnvelope(
        available: automationIds.isNotEmpty,
        totalCount: automationTargetCount,
        identities: automationIds.toList()..sort(),
      ),
      'external_audio_services': _resourceEnvelope(
        available: externalServices.isNotEmpty,
        totalCount: externalServices.length,
        identities: externalServices,
      ),
    };
  }

  Map<String, dynamic> _resourceEnvelope({
    required bool available,
    required int? totalCount,
    required List<String> identities,
    bool unknownRemainder = false,
  }) {
    final unique = identities.toSet().toList()..sort();
    final returned = unique.take(maxResourceIdentities).toList(growable: false);
    return <String, dynamic>{
      'available': available,
      'total_count': totalCount,
      'returned_count': returned.length,
      'has_more': unknownRemainder ||
          (totalCount != null && totalCount > returned.length) ||
          unique.length > returned.length,
      'identities': returned,
    };
  }

  List<Map<String, dynamic>> _domains({
    required PlanningSnapshotV3 snapshot,
    required Map<String, dynamic> resources,
  }) {
    bool available(String resource) =>
        _map(resources[resource])['available'] == true;
    int total(String resource) =>
        (_map(resources[resource])['total_count'] as num?)?.toInt() ?? 0;
    final audioClips = snapshot.clipById.values
        .where((clip) => clip['kind'] == 'audio')
        .length;
    final midiClips = snapshot.clipById.length - audioClips;
    final automationClips =
        (snapshot.data['automation_clips'] as List? ?? const <Object>[]).length;
    Map<String, dynamic> domain(
      String id,
      String purpose,
      bool isAvailable,
      Map<String, int> counts,
    ) =>
        <String, dynamic>{
          'domain': id,
          'purpose': purpose,
          'available': isAvailable,
          'counts': counts,
        };

    final facts = <String, ({bool available, Map<String, int> counts})>{
      'project_structure': (
        available: true,
        counts: <String, int>{
          'rows': snapshot.rowById.length,
          'groups': snapshot.groupById.length,
        },
      ),
      'clip_advanced': (
        available: snapshot.clipById.isNotEmpty,
        counts: <String, int>{'clips': snapshot.clipById.length},
      ),
      'midi': (
        available: midiClips > 0 || available('instruments'),
        counts: <String, int>{'midi_clips': midiClips},
      ),
      'samples': (
        available: available('library_assets'),
        counts: <String, int>{'assets': total('library_assets')},
      ),
      'effects': (
        available: available('effects'),
        counts: <String, int>{'effects': total('effects')},
      ),
      'automation': (
        available: available('automation_targets') || automationClips > 0,
        counts: <String, int>{
          'targets': total('automation_targets'),
          'clips': automationClips,
        },
      ),
      'mix': (
        available: snapshot.rowById.isNotEmpty,
        counts: <String, int>{
          'rows': snapshot.rowById.length,
          'analyzed_rows': total('analysis_results'),
        },
      ),
      'music_generation': (
        available: available('instruments') || available('library_assets'),
        counts: <String, int>{
          'instruments': total('instruments'),
          'assets': total('library_assets'),
        },
      ),
      'files_plugins': (
        available: available('hosted_plugins') ||
            available('instruments') ||
            available('library_assets'),
        counts: <String, int>{
          'instruments': total('instruments'),
          'assets': total('library_assets'),
        },
      ),
      'external_audio': (
        available: available('external_audio_services'),
        counts: <String, int>{
          'services': total('external_audio_services'),
        },
      ),
      'tutorial_ui': (
        available: true,
        counts: const <String, int>{},
      ),
    };
    return domainDefinitions.map((definition) {
      final fact = facts[definition.id];
      if (fact == null) {
        throw const AiV3CompactCoreException(
          'compact_core_domain_unknown',
        );
      }
      return domain(
        definition.id,
        definition.purpose,
        fact.available,
        fact.counts,
      )..['retrieval_enabled'] = definition.retrievalEnabled;
    }).toList(growable: false);
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<String> _strings(Object? value) => (value as List? ?? const <Object>[])
    .map((item) => item.toString().trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList()
  ..sort();

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    _freeze(_canonicalize(value)) as Map<String, dynamic>;

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()));
    return <String, dynamic>{
      for (final entry in entries)
        entry.key.toString(): _canonicalize(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

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
