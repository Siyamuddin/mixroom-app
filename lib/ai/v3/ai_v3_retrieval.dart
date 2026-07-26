import '../ai_gain_units.dart';
import 'ai_v3_contract.dart';
import 'ai_v3_domain_registry.dart';
import 'ai_v3_planning_snapshot.dart';

const String aiV3ContextRequestVersion = 'context_request_v3_1';
const String aiV3ContextResultVersion = 'context_result_v3_1';
const int aiV3MaxRetrievalQueries = 4;
const int aiV3MaxRetrievalTargetIds = 64;
const int aiV3MaxRetrievedMidiNotes = 512;
const int aiV3MaxRetrievedInstrumentIds = 64;
const int aiV3MaxEffectTargetIds = 32;
const int aiV3MaxRetrievedEffectRecords = 64;
const int aiV3MaxRetrievedEffectParameterDefinitions = 128;
const int aiV3MaxSampleTargetIds = 64;
const int aiV3MaxSampleQueryTerms = 8;
const int aiV3MaxSampleQueryTermLength = 80;
const int aiV3MaxRetrievedSampleRecordsPerQuery = 32;
const int aiV3MaxRetrievedSampleRecords = 64;
const int aiV3MaxAutomationTargetIds = 32;
const int aiV3MaxRetrievedAutomationPoints = 512;
const int aiV3MaxMixTargetIds = 32;
const int aiV3MaxRetrievedMixRecords = 32;
const int aiV3MaxRetrievedAdvancedClipRecords = 64;

final Set<String> aiV3ClipAdvancedRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('clip_advanced').requestedFields,
);

final Set<String> aiV3ClipAdvancedCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('clip_advanced').commandTypes,
);

final Set<String> aiV3MidiRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('midi').requestedFields,
);

final Set<String> aiV3MidiCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('midi').commandTypes,
);

final Set<String> aiV3EffectRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('effects').requestedFields,
);

final Set<String> aiV3EffectCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('effects').commandTypes,
);

final Set<String> aiV3SampleRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('samples').requestedFields,
);

final Set<String> aiV3SampleCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('samples').commandTypes,
);

final Set<String> aiV3AutomationRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('automation').requestedFields,
);

final Set<String> aiV3AutomationCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('automation').commandTypes,
);

final Set<String> aiV3MixRequestedFields = Set<String>.unmodifiable(
  aiV3DomainDefinition('mix').requestedFields,
);

final Set<String> aiV3MixCommandTypes = Set<String>.unmodifiable(
  aiV3DomainDefinition('mix').commandTypes,
);

final Set<String> aiV3CommonAndMidiCommandTypes = Set<String>.unmodifiable(
  <String>{...aiV3CommonCommandTypes, ...aiV3MidiCommandTypes},
);

Set<String> aiV3CommandTypesForDomains(Iterable<String> domains) {
  final result = <String>{...aiV3CommonCommandTypes};
  for (final domain in domains) {
    final definition = aiV3DomainDefinition(domain);
    if (!definition.retrievalEnabled) {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    result.addAll(definition.commandTypes);
  }
  return Set<String>.unmodifiable(result);
}

class AiV3RetrievalException implements Exception {
  const AiV3RetrievalException(this.code);

  final String code;

  @override
  String toString() => 'AiV3RetrievalException($code)';
}

class AiV3BeatRange {
  const AiV3BeatRange({required this.startBeat, required this.endBeat});

  final double startBeat;
  final double endBeat;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'start_beat': startBeat,
        'end_beat': endBeat,
      };
}

abstract interface class AiV3ContextQuery {
  String get requestId;
  String get domain;
  List<Object> get targetIds;
  Set<String> get requestedFields;
  int get limit;
  Map<String, dynamic> toJson();
}

class AiV3MidiContextQuery implements AiV3ContextQuery {
  AiV3MidiContextQuery._({
    required this.requestId,
    required List<Object> targetIds,
    required this.timeRange,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<Object>.unmodifiable(targetIds),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'midi';
  @override
  final List<Object> targetIds;
  final AiV3BeatRange? timeRange;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3MidiContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'midi') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    final rawTargets = raw['target_ids'];
    if (rawTargets is! List || rawTargets.length > aiV3MaxRetrievalTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <Object>[];
    final targetKeys = <String>{};
    for (final value in rawTargets) {
      final Object normalized;
      final String key;
      if (value is int && value >= 0) {
        normalized = value;
        key = 'row:$value';
      } else if (value is String && value.trim().isNotEmpty) {
        normalized = value.trim();
        key = 'clip:${value.trim()}';
      } else {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      if (!targetKeys.add(key)) {
        throw const AiV3RetrievalException(
          'v3_retrieval_target_duplicate',
        );
      }
      targets.add(normalized);
    }
    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3MidiRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    if (targets.isEmpty && !fields.contains('edit_capabilities')) {
      throw const AiV3RetrievalException(
        'v3_retrieval_clip_target_required',
      );
    }
    final queryTerms = raw['query_terms'];
    if (queryTerms is! List || queryTerms.isNotEmpty) {
      throw const AiV3RetrievalException(
        'v3_retrieval_query_terms_invalid',
      );
    }
    AiV3BeatRange? range;
    final rawRange = raw['time_range'];
    if (rawRange != null) {
      if (rawRange is! Map) {
        throw const AiV3RetrievalException('v3_retrieval_range_invalid');
      }
      final map = Map<String, dynamic>.from(rawRange);
      _requireExactKeys(
        map,
        const <String>{'start_beat', 'end_beat'},
        'v3_retrieval_range_fields_invalid',
      );
      final start = map['start_beat'];
      final end = map['end_beat'];
      if (start is! num ||
          end is! num ||
          !start.isFinite ||
          !end.isFinite ||
          start < 0 ||
          end <= start) {
        throw const AiV3RetrievalException('v3_retrieval_range_invalid');
      }
      range = AiV3BeatRange(
        startBeat: start.toDouble(),
        endBeat: end.toDouble(),
      );
    }
    final limit = raw['limit'];
    if (limit is! int || limit < 1 || limit > aiV3MaxRetrievedMidiNotes) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3MidiContextQuery._(
      requestId: requestId,
      targetIds: targets,
      timeRange: range,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': 'midi',
        'target_ids': targetIds,
        'time_range': timeRange?.toJson(),
        'query_terms': const <Object>[],
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3ClipAdvancedContextQuery implements AiV3ContextQuery {
  AiV3ClipAdvancedContextQuery._({
    required this.requestId,
    required List<Object> targetIds,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<Object>.unmodifiable(targetIds),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'clip_advanced';
  @override
  final List<Object> targetIds;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3ClipAdvancedContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'clip_advanced') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    final rawTargets = raw['target_ids'];
    if (rawTargets is! List || rawTargets.length > aiV3MaxRetrievalTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <Object>[];
    final targetKeys = <String>{};
    for (final value in rawTargets) {
      final Object target;
      final String key;
      if (value is int && value >= 0) {
        target = value;
        key = 'row:$value';
      } else if (value is String && value.trim().isNotEmpty) {
        target = value.trim();
        key = 'clip:${value.trim()}';
      } else {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      if (!targetKeys.add(key)) {
        throw const AiV3RetrievalException('v3_retrieval_target_duplicate');
      }
      targets.add(target);
    }
    if (raw['time_range'] != null) {
      throw const AiV3RetrievalException('v3_retrieval_range_invalid');
    }
    final queryTerms = raw['query_terms'];
    if (queryTerms is! List || queryTerms.isNotEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_query_terms_invalid');
    }
    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3ClipAdvancedRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    if (targets.isEmpty && fields.contains('clip_details')) {
      throw const AiV3RetrievalException(
        'v3_retrieval_clip_target_required',
      );
    }
    final limit = raw['limit'];
    if (limit is! int ||
        limit < 1 ||
        limit > aiV3MaxRetrievedAdvancedClipRecords) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3ClipAdvancedContextQuery._(
      requestId: requestId,
      targetIds: targets,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'target_ids': targetIds,
        'time_range': null,
        'query_terms': const <Object>[],
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3EffectsContextQuery implements AiV3ContextQuery {
  AiV3EffectsContextQuery._({
    required this.requestId,
    required List<int> targetIds,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<int>.unmodifiable(targetIds),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'effects';
  @override
  final List<int> targetIds;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3EffectsContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'effects') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    final rawTargets = raw['target_ids'];
    if (rawTargets is! List || rawTargets.length > aiV3MaxEffectTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <int>[];
    final seenTargets = <int>{};
    for (final value in rawTargets) {
      if (value is! int || value < 0 || !seenTargets.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      targets.add(value);
    }
    if (raw['time_range'] != null) {
      throw const AiV3RetrievalException('v3_retrieval_range_invalid');
    }
    final queryTerms = raw['query_terms'];
    if (queryTerms is! List || queryTerms.isNotEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_query_terms_invalid');
    }
    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3EffectRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    if (targets.isEmpty && fields.contains('instances')) {
      throw const AiV3RetrievalException(
        'v3_retrieval_effect_row_target_required',
      );
    }
    final limit = raw['limit'];
    if (limit is! int || limit < 1 || limit > aiV3MaxRetrievedEffectRecords) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3EffectsContextQuery._(
      requestId: requestId,
      targetIds: targets,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'target_ids': targetIds,
        'time_range': null,
        'query_terms': const <Object>[],
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3SamplesContextQuery implements AiV3ContextQuery {
  AiV3SamplesContextQuery._({
    required this.requestId,
    required List<String> targetIds,
    required List<String> queryTerms,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<String>.unmodifiable(targetIds),
        queryTerms = List<String>.unmodifiable(queryTerms),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'samples';
  @override
  final List<String> targetIds;
  final List<String> queryTerms;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3SamplesContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'samples') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    if (raw['time_range'] != null) {
      throw const AiV3RetrievalException('v3_retrieval_range_invalid');
    }

    final rawTargets = raw['target_ids'];
    if (rawTargets is! List || rawTargets.length > aiV3MaxSampleTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <String>[];
    final targetKeys = <String>{};
    for (final value in rawTargets) {
      final target = value is String ? value.trim() : '';
      if (target.isEmpty || !targetKeys.add(target)) {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      targets.add(target);
    }

    final rawTerms = raw['query_terms'];
    if (rawTerms is! List || rawTerms.length > aiV3MaxSampleQueryTerms) {
      throw const AiV3RetrievalException('v3_retrieval_query_terms_invalid');
    }
    final terms = <String>[];
    final termKeys = <String>{};
    for (final value in rawTerms) {
      final term = value is String ? value.trim() : '';
      final key = term.toLowerCase();
      if (term.isEmpty ||
          term.length > aiV3MaxSampleQueryTermLength ||
          !termKeys.add(key)) {
        throw const AiV3RetrievalException(
          'v3_retrieval_query_term_invalid',
        );
      }
      terms.add(term);
    }

    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3SampleRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    if (fields.contains('search_results') && terms.isEmpty) {
      throw const AiV3RetrievalException(
        'v3_retrieval_sample_search_terms_required',
      );
    }
    if (fields.contains('asset_metadata') && targets.isEmpty && terms.isEmpty) {
      throw const AiV3RetrievalException(
        'v3_retrieval_sample_asset_selector_required',
      );
    }
    final limit = raw['limit'];
    if (limit is! int ||
        limit < 1 ||
        limit > aiV3MaxRetrievedSampleRecordsPerQuery) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3SamplesContextQuery._(
      requestId: requestId,
      targetIds: targets,
      queryTerms: terms,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'target_ids': targetIds,
        'time_range': null,
        'query_terms': queryTerms,
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3AutomationContextQuery implements AiV3ContextQuery {
  AiV3AutomationContextQuery._({
    required this.requestId,
    required List<int> targetIds,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<int>.unmodifiable(targetIds),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'automation';
  @override
  final List<int> targetIds;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3AutomationContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'automation') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    final rawTargets = raw['target_ids'];
    if (rawTargets is! List ||
        rawTargets.isEmpty ||
        rawTargets.length > aiV3MaxAutomationTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <int>[];
    final seenTargets = <int>{};
    for (final value in rawTargets) {
      if (value is! int || value < 0 || !seenTargets.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      targets.add(value);
    }
    if (raw['time_range'] != null) {
      throw const AiV3RetrievalException('v3_retrieval_range_invalid');
    }
    final queryTerms = raw['query_terms'];
    if (queryTerms is! List || queryTerms.isNotEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_query_terms_invalid');
    }
    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3AutomationRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    final limit = raw['limit'];
    if (limit is! int ||
        limit < 1 ||
        limit > aiV3MaxRetrievedAutomationPoints) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3AutomationContextQuery._(
      requestId: requestId,
      targetIds: targets,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'target_ids': targetIds,
        'time_range': null,
        'query_terms': const <Object>[],
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3MixContextQuery implements AiV3ContextQuery {
  AiV3MixContextQuery._({
    required this.requestId,
    required List<Object> targetIds,
    required Set<String> requestedFields,
    required this.limit,
  })  : targetIds = List<Object>.unmodifiable(targetIds),
        requestedFields = Set<String>.unmodifiable(requestedFields);

  @override
  final String requestId;
  @override
  String get domain => 'mix';
  @override
  final List<Object> targetIds;
  @override
  final Set<String> requestedFields;
  @override
  final int limit;

  factory AiV3MixContextQuery.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      },
      'v3_retrieval_query_fields_invalid',
    );
    final requestId =
        raw['request_id'] is String ? (raw['request_id'] as String).trim() : '';
    if (requestId.isEmpty || requestId.length > 80) {
      throw const AiV3RetrievalException('v3_retrieval_request_id_invalid');
    }
    if (raw['domain'] != 'mix') {
      throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
    }
    final rawTargets = raw['target_ids'];
    if (rawTargets is! List || rawTargets.length > aiV3MaxMixTargetIds) {
      throw const AiV3RetrievalException('v3_retrieval_targets_invalid');
    }
    final targets = <Object>[];
    final targetKeys = <String>{};
    for (final value in rawTargets) {
      final Object target;
      final String key;
      if (value is int && value >= 0) {
        target = value;
        key = 'row:$value';
      } else if (value is String && value.trim().isNotEmpty) {
        target = value.trim();
        key = 'group:${value.trim()}';
      } else {
        throw const AiV3RetrievalException('v3_retrieval_target_invalid');
      }
      if (!targetKeys.add(key)) {
        throw const AiV3RetrievalException('v3_retrieval_target_duplicate');
      }
      targets.add(target);
    }
    if (raw['time_range'] != null) {
      throw const AiV3RetrievalException('v3_retrieval_range_invalid');
    }
    final queryTerms = raw['query_terms'];
    if (queryTerms is! List || queryTerms.isNotEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_query_terms_invalid');
    }
    final rawFields = raw['requested_fields'];
    if (rawFields is! List || rawFields.isEmpty) {
      throw const AiV3RetrievalException('v3_retrieval_fields_invalid');
    }
    final fields = <String>{};
    for (final value in rawFields) {
      if (value is! String ||
          !aiV3MixRequestedFields.contains(value) ||
          !fields.add(value)) {
        throw const AiV3RetrievalException('v3_retrieval_field_invalid');
      }
    }
    final hasRowField = fields.contains('row_analysis') ||
        fields.contains('reference_analysis');
    final hasGroupField = fields.contains('group_state');
    final rowTargetCount = targets.whereType<int>().length;
    final groupTargetCount = targets.whereType<String>().length;
    if ((hasGroupField && groupTargetCount == 0) ||
        (rowTargetCount > 0 && !hasRowField) ||
        (groupTargetCount > 0 && !hasGroupField)) {
      throw const AiV3RetrievalException(
        'v3_retrieval_mix_target_fields_invalid',
      );
    }
    final limit = raw['limit'];
    if (limit is! int || limit < 1 || limit > aiV3MaxRetrievedMixRecords) {
      throw const AiV3RetrievalException('v3_retrieval_limit_invalid');
    }
    return AiV3MixContextQuery._(
      requestId: requestId,
      targetIds: targets,
      requestedFields: fields,
      limit: limit,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'target_ids': targetIds,
        'time_range': null,
        'query_terms': const <Object>[],
        'requested_fields': requestedFields.toList()..sort(),
        'limit': limit,
      };
}

class AiV3ContextRequest {
  AiV3ContextRequest._(List<AiV3ContextQuery> requests)
      : requests = List<AiV3ContextQuery>.unmodifiable(requests);

  final List<AiV3ContextQuery> requests;

  factory AiV3ContextRequest.fromJson(Map<String, dynamic> raw) {
    _requireExactKeys(
      raw,
      const <String>{'schema_version', 'requests'},
      'v3_retrieval_envelope_fields_invalid',
    );
    if (raw['schema_version'] != aiV3ContextRequestVersion) {
      throw const AiV3RetrievalException('v3_retrieval_version_invalid');
    }
    final values = raw['requests'];
    if (values is! List ||
        values.isEmpty ||
        values.length > aiV3MaxRetrievalQueries) {
      throw const AiV3RetrievalException('v3_retrieval_requests_invalid');
    }
    final ids = <String>{};
    final requests = <AiV3ContextQuery>[];
    for (final value in values) {
      if (value is! Map) {
        throw const AiV3RetrievalException('v3_retrieval_query_invalid');
      }
      final map = Map<String, dynamic>.from(value);
      final query = switch (map['domain']) {
        'clip_advanced' => AiV3ClipAdvancedContextQuery.fromJson(map),
        'midi' => AiV3MidiContextQuery.fromJson(map),
        'effects' => AiV3EffectsContextQuery.fromJson(map),
        'samples' => AiV3SamplesContextQuery.fromJson(map),
        'automation' => AiV3AutomationContextQuery.fromJson(map),
        'mix' => AiV3MixContextQuery.fromJson(map),
        _ => throw const AiV3RetrievalException(
            'v3_retrieval_domain_invalid',
          ),
      };
      if (!ids.add(query.requestId)) {
        throw const AiV3RetrievalException(
          'v3_retrieval_request_id_duplicate',
        );
      }
      requests.add(query);
    }
    return AiV3ContextRequest._(requests);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': aiV3ContextRequestVersion,
        'requests': requests.map((query) => query.toJson()).toList(),
      };
}

abstract interface class AiV3DomainRetrievalResult {
  String get requestId;
  String get domain;
  Map<String, dynamic> toJson();
}

class AiV3ClipAdvancedRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3ClipAdvancedRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.matchedRowIds,
    required this.audioClips,
    required this.transformCapabilities,
    required this.totalRecords,
    required this.returnedRecords,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'clip_advanced';
  final List<String> requestedFields;
  final List<int> matchedRowIds;
  final List<Map<String, dynamic>> audioClips;
  final Map<String, dynamic>? transformCapabilities;
  final int totalRecords;
  final int returnedRecords;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'requested_fields': requestedFields,
        'matched_row_ids': matchedRowIds,
        'audio_clips': audioClips,
        'transform_capabilities': transformCapabilities,
        'counts': <String, dynamic>{
          'records_total': totalRecords,
          'records_returned': returnedRecords,
          'has_more': hasMore,
        },
      };
}

class AiV3MidiRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3MidiRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.matchedRowIds,
    required this.midiClips,
    required this.instrumentIds,
    required this.editCapabilities,
    required this.totalNotes,
    required this.returnedNotes,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'midi';
  final List<String> requestedFields;
  final List<int> matchedRowIds;
  final List<Map<String, dynamic>> midiClips;
  final List<String> instrumentIds;
  final Map<String, dynamic>? editCapabilities;
  final int totalNotes;
  final int returnedNotes;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': 'midi',
        'requested_fields': requestedFields,
        'matched_row_ids': matchedRowIds,
        'midi_clips': midiClips,
        'instrument_ids': instrumentIds,
        'edit_capabilities': editCapabilities,
        'counts': <String, dynamic>{
          'clips': midiClips.length,
          'notes_total': totalNotes,
          'notes_returned': returnedNotes,
          'has_more': hasMore,
        },
      };
}

class AiV3EffectsRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3EffectsRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.matchedRowIds,
    required this.instances,
    required this.catalog,
    required this.parameterDefinitions,
    required this.targetCapabilities,
    required this.totalRecords,
    required this.returnedRecords,
    required this.totalParameterDefinitions,
    required this.returnedParameterDefinitions,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'effects';
  final List<String> requestedFields;
  final List<int> matchedRowIds;
  final List<Map<String, dynamic>> instances;
  final List<Map<String, dynamic>> catalog;
  final List<Map<String, dynamic>> parameterDefinitions;
  final Map<String, dynamic>? targetCapabilities;
  final int totalRecords;
  final int returnedRecords;
  final int totalParameterDefinitions;
  final int returnedParameterDefinitions;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'requested_fields': requestedFields,
        'matched_row_ids': matchedRowIds,
        'instances': instances,
        'catalog': catalog,
        'parameter_definitions': parameterDefinitions,
        'target_capabilities': targetCapabilities,
        'counts': <String, dynamic>{
          'records_total': totalRecords,
          'records_returned': returnedRecords,
          'parameter_definitions_total': totalParameterDefinitions,
          'parameter_definitions_returned': returnedParameterDefinitions,
          'has_more': hasMore,
        },
      };
}

class AiV3SamplesRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3SamplesRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.assets,
    required this.placementCapabilities,
    required this.totalRecords,
    required this.returnedRecords,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'samples';
  final List<String> requestedFields;
  final List<Map<String, dynamic>> assets;
  final Map<String, dynamic>? placementCapabilities;
  final int totalRecords;
  final int returnedRecords;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'requested_fields': requestedFields,
        'assets': assets,
        'placement_capabilities': placementCapabilities,
        'counts': <String, dynamic>{
          'records_total': totalRecords,
          'records_returned': returnedRecords,
          'has_more': hasMore,
        },
      };
}

class AiV3AutomationRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3AutomationRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.matchedRowIds,
    required this.rows,
    required this.targetCapabilities,
    required this.totalPoints,
    required this.returnedPoints,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'automation';
  final List<String> requestedFields;
  final List<int> matchedRowIds;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? targetCapabilities;
  final int totalPoints;
  final int returnedPoints;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'requested_fields': requestedFields,
        'matched_row_ids': matchedRowIds,
        'rows': rows,
        'target_capabilities': targetCapabilities,
        'counts': <String, dynamic>{
          'points_total': totalPoints,
          'points_returned': returnedPoints,
          'has_more': hasMore,
        },
      };
}

class AiV3MixRetrievalResult implements AiV3DomainRetrievalResult {
  const AiV3MixRetrievalResult({
    required this.requestId,
    required this.requestedFields,
    required this.matchedRowIds,
    required this.matchedGroupIds,
    required this.rowAnalysis,
    required this.groupState,
    required this.masterState,
    required this.referenceAnalysis,
    required this.engineCapabilities,
    required this.totalRecords,
    required this.returnedRecords,
    required this.hasMore,
  });

  @override
  final String requestId;
  @override
  String get domain => 'mix';
  final List<String> requestedFields;
  final List<int> matchedRowIds;
  final List<String> matchedGroupIds;
  final List<Map<String, dynamic>> rowAnalysis;
  final List<Map<String, dynamic>> groupState;
  final Map<String, dynamic>? masterState;
  final List<Map<String, dynamic>> referenceAnalysis;
  final Map<String, dynamic>? engineCapabilities;
  final int totalRecords;
  final int returnedRecords;
  final bool hasMore;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'domain': domain,
        'requested_fields': requestedFields,
        'matched_row_ids': matchedRowIds,
        'matched_group_ids': matchedGroupIds,
        'row_analysis': rowAnalysis,
        'group_state': groupState,
        'master_state': masterState,
        'reference_analysis': referenceAnalysis,
        'engine_capabilities': engineCapabilities,
        'counts': <String, dynamic>{
          'records_total': totalRecords,
          'records_returned': returnedRecords,
          'has_more': hasMore,
        },
      };
}

class AiV3ContextResult {
  const AiV3ContextResult({
    required this.snapshotId,
    required this.stateDigest,
    required this.results,
  });

  final String snapshotId;
  final String stateDigest;
  final List<AiV3DomainRetrievalResult> results;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': aiV3ContextResultVersion,
        'snapshot_id': snapshotId,
        'state_digest': stateDigest,
        'results': results.map((result) => result.toJson()).toList(),
      };
}

class AiV3MidiContextRetriever {
  const AiV3MidiContextRetriever();

  AiV3ContextResult retrieve({
    required PlanningSnapshotV3 snapshot,
    required AiV3ContextRequest request,
  }) {
    var remainingNotes = aiV3MaxRetrievedMidiNotes;
    final results = <AiV3DomainRetrievalResult>[];
    for (final rawQuery in request.requests) {
      if (rawQuery is! AiV3MidiContextQuery) {
        throw const AiV3RetrievalException('v3_retrieval_domain_invalid');
      }
      final result = retrieveQuery(
        snapshot: snapshot,
        query: rawQuery,
        remainingNotes: remainingNotes,
      );
      remainingNotes -= result.returnedNotes;
      results.add(result);
    }
    return AiV3ContextResult(
      snapshotId: snapshot.snapshotId,
      stateDigest: snapshot.stateDigest,
      results: List<AiV3DomainRetrievalResult>.unmodifiable(results),
    );
  }

  AiV3MidiRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3MidiContextQuery query,
    required int remainingNotes,
  }) {
    final clips = _resolveClips(snapshot, query);
    final wantsNotes = query.requestedFields.contains('clip_notes');
    final wantsInstruments = query.requestedFields.contains('clip_instruments');
    final noteCandidates = <Map<String, dynamic>>[];
    final clipResults = <Map<String, dynamic>>[];
    final matchedRows = <int>{
      for (final target in query.targetIds)
        if (target is int) target,
    };
    for (final clip in clips) {
      final rowId = clip['row_id'] as int;
      matchedRows.add(rowId);
      final notes = _notes(clip, query.timeRange);
      noteCandidates.addAll(notes);
      clipResults.add(<String, dynamic>{
        'clip_id': clip['clip_id'],
        'row_id': rowId,
        'name': clip['name']?.toString() ?? '',
        'start_beat': _startBeat(snapshot, clip),
        'length_beats': _lengthBeats(snapshot, clip),
        'instrument_id':
            wantsInstruments ? _instrumentId(snapshot, clip) : null,
        'notes': wantsNotes ? <Map<String, dynamic>>[] : null,
      });
    }
    final queryLimit =
        query.limit < remainingNotes ? query.limit : remainingNotes;
    final returned = wantsNotes
        ? noteCandidates.take(queryLimit).toList(growable: false)
        : const <Map<String, dynamic>>[];
    if (wantsNotes) {
      final returnedByClip = <String, List<Map<String, dynamic>>>{};
      for (final note in returned) {
        (returnedByClip[note.remove('_clip_id') as String] ??=
                <Map<String, dynamic>>[])
            .add(note);
      }
      for (final clip in clipResults) {
        clip['notes'] =
            returnedByClip[clip['clip_id']] ?? const <Map<String, dynamic>>[];
      }
    }
    final instruments = query.requestedFields.contains('edit_capabilities')
        ? _instrumentCatalog(snapshot)
        : const <String>[];
    return AiV3MidiRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      matchedRowIds: matchedRows.toList()..sort(),
      midiClips: clipResults,
      instrumentIds: instruments,
      editCapabilities: query.requestedFields.contains('edit_capabilities')
          ? <String, dynamic>{
              'can_transpose': clips.isNotEmpty,
              'can_replace': clips.isNotEmpty,
              'can_append': clips.isNotEmpty,
              'can_chop': clips.isNotEmpty,
              'can_create': instruments.isNotEmpty,
              'max_generated_notes': aiV3MaxGeneratedMidiNotes,
            }
          : null,
      totalNotes: wantsNotes ? noteCandidates.length : 0,
      returnedNotes: returned.length,
      hasMore: wantsNotes && returned.length < noteCandidates.length,
    );
  }

  List<Map<String, dynamic>> _resolveClips(
    PlanningSnapshotV3 snapshot,
    AiV3MidiContextQuery query,
  ) {
    final resolved = <String, Map<String, dynamic>>{};
    for (final target in query.targetIds) {
      if (target is int) {
        final row = snapshot.rowById[target];
        if (row == null) {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_unknown',
          );
        }
        final ids = (row['clip_ids'] as List? ?? const <Object>[])
            .map((value) => value.toString());
        var foundMidi = false;
        for (final id in ids) {
          final clip = snapshot.clipById[id];
          if (clip == null || clip['kind'] != 'midi') continue;
          foundMidi = true;
          resolved[id] = clip;
        }
        if (!foundMidi &&
            query.requestedFields
                .any((field) => field != 'edit_capabilities')) {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_not_midi',
          );
        }
      } else {
        final id = target as String;
        final clip = snapshot.clipById[id];
        if (clip == null) {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_unknown',
          );
        }
        if (clip['kind'] != 'midi') {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_not_midi',
          );
        }
        resolved[id] = clip;
      }
    }
    final values = resolved.values.toList(growable: false)
      ..sort((left, right) {
        final byStart =
            _startBeat(snapshot, left).compareTo(_startBeat(snapshot, right));
        if (byStart != 0) return byStart;
        return left['clip_id']
            .toString()
            .compareTo(right['clip_id'].toString());
      });
    return values;
  }

  List<Map<String, dynamic>> _notes(
    Map<String, dynamic> clip,
    AiV3BeatRange? range,
  ) {
    final clipId = clip['clip_id'].toString();
    final notes = (clip['midi_notes'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .where((note) {
          if (range == null) return true;
          final start = (note['start_beat'] as num).toDouble();
          final end = start + (note['length_beats'] as num).toDouble();
          return start < range.endBeat && end > range.startBeat;
        })
        .map((note) => <String, dynamic>{
              '_clip_id': clipId,
              'note_id': note['note_id'],
              'pitch': note['pitch'],
              'start_beat': note['start_beat'],
              'length_beats': note['length_beats'],
              'velocity': note['velocity'],
            })
        .toList(growable: false)
      ..sort((left, right) {
        final byStart = (left['start_beat'] as num)
            .toDouble()
            .compareTo((right['start_beat'] as num).toDouble());
        if (byStart != 0) return byStart;
        final byPitch = (left['pitch'] as int).compareTo(right['pitch'] as int);
        if (byPitch != 0) return byPitch;
        return left['note_id']
            .toString()
            .compareTo(right['note_id'].toString());
      });
    return notes;
  }

  List<String> _instrumentCatalog(PlanningSnapshotV3 snapshot) {
    final catalogs = snapshot.data['catalogs'] as Map;
    final values = (catalogs['instrument_ids'] as List? ?? const <Object>[])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return List<String>.unmodifiable(
      values.take(aiV3MaxRetrievedInstrumentIds),
    );
  }

  String? _instrumentId(
    PlanningSnapshotV3 snapshot,
    Map<String, dynamic> clip,
  ) {
    final clipInstrument = clip['instrument_id']?.toString().trim() ?? '';
    if (clipInstrument.isNotEmpty) return clipInstrument;
    final row = snapshot.rowById[clip['row_id']];
    final rowInstrument = row?['instrument_id']?.toString().trim() ?? '';
    return rowInstrument.isEmpty ? null : rowInstrument;
  }

  double _startBeat(
    PlanningSnapshotV3 snapshot,
    Map<String, dynamic> clip,
  ) {
    final bpm = ((snapshot.data['project'] as Map)['bpm'] as num).toDouble();
    return ((clip['start_seconds'] as num?)?.toDouble() ?? 0) * bpm / 60;
  }

  double _lengthBeats(
    PlanningSnapshotV3 snapshot,
    Map<String, dynamic> clip,
  ) {
    final bpm = ((snapshot.data['project'] as Map)['bpm'] as num).toDouble();
    final start = (clip['trim_start_ms'] as num?)?.toDouble() ?? 0;
    final end = (clip['trim_end_ms'] as num?)?.toDouble() ?? start;
    return (end - start).clamp(0.0, double.infinity) * bpm / 60000;
  }
}

class AiV3ClipAdvancedContextRetriever {
  const AiV3ClipAdvancedContextRetriever();

  AiV3ClipAdvancedRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3ClipAdvancedContextQuery query,
    required int remainingRecords,
  }) {
    final resolved = <String, Map<String, dynamic>>{};
    final matchedRows = <int>{};
    for (final target in query.targetIds) {
      if (target is int) {
        final row = snapshot.rowById[target];
        if (row == null) {
          throw const AiV3RetrievalException('v3_retrieval_target_unknown');
        }
        matchedRows.add(target);
        var foundAudio = false;
        for (final value in row['clip_ids'] as List? ?? const <Object>[]) {
          final clip = snapshot.clipById[value.toString()];
          if (clip == null || clip['kind'] != 'audio') continue;
          foundAudio = true;
          resolved[clip['clip_id'].toString()] = clip;
        }
        if (!foundAudio) {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_not_audio',
          );
        }
      } else {
        final clip = snapshot.clipById[target as String];
        if (clip == null) {
          throw const AiV3RetrievalException('v3_retrieval_target_unknown');
        }
        if (clip['kind'] != 'audio') {
          throw const AiV3RetrievalException(
            'v3_retrieval_target_not_audio',
          );
        }
        resolved[target] = clip;
        matchedRows.add(clip['row_id'] as int);
      }
    }
    final bpm = ((snapshot.data['project'] as Map)['bpm'] as num).toDouble();
    final candidates = resolved.values.toList(growable: false)
      ..sort((left, right) {
        final leftStart =
            ((left['start_seconds'] as num?)?.toDouble() ?? 0) * bpm / 60;
        final rightStart =
            ((right['start_seconds'] as num?)?.toDouble() ?? 0) * bpm / 60;
        final byStart = leftStart.compareTo(rightStart);
        if (byStart != 0) return byStart;
        final byRow =
            (left['row_index'] as int).compareTo(right['row_index'] as int);
        if (byRow != 0) return byRow;
        return left['clip_id']
            .toString()
            .compareTo(right['clip_id'].toString());
      });
    final allowed =
        query.limit < remainingRecords ? query.limit : remainingRecords;
    final returned = query.requestedFields.contains('clip_details')
        ? candidates.take(allowed).map((clip) {
            final trimStart = (clip['trim_start_ms'] as num?)?.toDouble() ?? 0;
            final trimEnd =
                (clip['trim_end_ms'] as num?)?.toDouble() ?? trimStart;
            final pitch = (clip['pitch_semitones'] as num?)?.toDouble();
            final timelineDurationMs =
                (clip['timeline_duration_ms'] as num?)?.toDouble();
            if (pitch == null || !pitch.isFinite) {
              throw const AiV3RetrievalException(
                'v3_retrieval_clip_pitch_missing',
              );
            }
            if (timelineDurationMs == null ||
                !timelineDurationMs.isFinite ||
                timelineDurationMs < 0) {
              throw const AiV3RetrievalException(
                'v3_retrieval_clip_timeline_length_missing',
              );
            }
            return <String, dynamic>{
              'clip_id': clip['clip_id'],
              'row_id': clip['row_id'],
              'name': clip['name']?.toString() ?? '',
              'start_beat':
                  ((clip['start_seconds'] as num?)?.toDouble() ?? 0) * bpm / 60,
              'length_beats':
                  (trimEnd - trimStart).clamp(0.0, double.infinity) *
                      bpm /
                      60000,
              'timeline_length_beats': timelineDurationMs * bpm / 60000,
              'pitch_semitones': pitch,
              'source_tempo_bpm':
                  (clip['source_tempo_bpm'] as num?)?.toDouble() ?? 0.0,
              'stretch_to_project_tempo':
                  clip['stretch_to_project_tempo'] == true,
              'tempo_stretch_preserve_pitch':
                  clip['tempo_stretch_preserve_pitch'] == true,
              'tempo_warp_mode': clip['tempo_warp_mode']?.toString() ?? '',
            };
          }).toList(growable: false)
        : const <Map<String, dynamic>>[];
    final total =
        query.requestedFields.contains('clip_details') ? candidates.length : 0;
    return AiV3ClipAdvancedRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      matchedRowIds: matchedRows.toList()..sort(),
      audioClips: returned,
      transformCapabilities:
          query.requestedFields.contains('transform_capabilities')
              ? const <String, dynamic>{
                  'can_set_pitch': true,
                  'can_adjust_pitch': true,
                  'minimum_pitch_semitones': -12.0,
                  'maximum_pitch_semitones': 12.0,
                  'can_set_timeline_length': true,
                  'can_scale_timeline_length': true,
                  'minimum_timeline_duration_seconds': 0.05,
                  'maximum_timeline_duration_seconds': 36000.0,
                  'minimum_playback_ratio': 0.05,
                  'maximum_playback_ratio': 20.0,
                  'can_set_source_tempo': true,
                  'can_detect_source_tempo': true,
                  'can_align_tempo_to_project': true,
                  'can_set_project_tempo_from_clip': true,
                  'can_trim_detected_edge_silence': true,
                  'can_align_detected_first_sound': true,
                  'can_glue_audio_clips': true,
                  'minimum_glue_clip_count': 2,
                  'maximum_glue_clip_count': 32,
                  'can_separate_vocal_instrumental_stems': true,
                  'can_convert_audio_clip_to_midi': true,
                  'silence_trim_edges': <String>['start', 'end', 'both'],
                  'first_sound_destinations': <String>[
                    'project_beat',
                    'nearest_beat',
                    'nearest_bar',
                    'playhead',
                    'project_start',
                  ],
                  'minimum_source_tempo_bpm': 20.0,
                  'maximum_source_tempo_bpm': 999.0,
                  'tempo_follow_modes': <String>[
                    'off',
                    'repitch',
                    'preserve_pitch',
                  ],
                }
              : null,
      totalRecords: total,
      returnedRecords: returned.length,
      hasMore: returned.length < total,
    );
  }
}

class AiV3EffectsContextRetriever {
  const AiV3EffectsContextRetriever();

  AiV3EffectsRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3EffectsContextQuery query,
    required int remainingRecords,
    required int remainingParameterDefinitions,
  }) {
    final rows = <Map<String, dynamic>>[];
    for (final rowId in query.targetIds) {
      final row = snapshot.rowById[rowId];
      if (row == null) {
        throw const AiV3RetrievalException('v3_retrieval_target_unknown');
      }
      rows.add(row);
    }
    rows.sort((left, right) => (left['display_index'] as int)
        .compareTo(right['display_index'] as int));

    final catalog = _catalog(snapshot);
    final catalogById = <String, Map<String, dynamic>>{
      for (final effect in catalog) effect['effect_id'] as String: effect,
    };
    final instanceCandidates = <Map<String, dynamic>>[];
    if (query.requestedFields.contains('instances')) {
      for (final row in rows) {
        final rowId = row['row_id'] as int;
        final effects = (row['effects'] as List? ?? const <Object>[])
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList(growable: false)
          ..sort((left, right) {
            final byIndex = (left['effect_index'] as int)
                .compareTo(right['effect_index'] as int);
            if (byIndex != 0) return byIndex;
            return (left['effect_instance_id']?.toString() ?? '')
                .compareTo(right['effect_instance_id']?.toString() ?? '');
          });
        for (final effect in effects) {
          final instanceId =
              effect['effect_instance_id']?.toString().trim() ?? '';
          final effectId = effect['effect_id']?.toString().trim() ?? '';
          final definition = catalogById[effectId];
          if (instanceId.isEmpty || definition == null) continue;
          final exposed = (definition['parameter_ids'] as List)
              .map((value) => value.toString())
              .toSet();
          final parameters = (effect['parameters'] as List? ?? const <Object>[])
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .map((parameter) {
                final id =
                    (parameter['name'] ?? parameter['id'])?.toString().trim() ??
                        '';
                final value = parameter['value'];
                if (id.isEmpty ||
                    !exposed.contains(id) ||
                    value is! num ||
                    !value.isFinite) {
                  return null;
                }
                final minimum = parameter['min'];
                final maximum = parameter['max'];
                final normalized = minimum is num &&
                        maximum is num &&
                        minimum.isFinite &&
                        maximum.isFinite &&
                        maximum > minimum
                    ? ((value.toDouble() - minimum.toDouble()) /
                            (maximum.toDouble() - minimum.toDouble()))
                        .clamp(0.0, 1.0)
                        .toDouble()
                    : value.toDouble().clamp(0.0, 1.0).toDouble();
                return <String, dynamic>{
                  'parameter_id': id,
                  'value': normalized,
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList(growable: false)
            ..sort((left, right) => left['parameter_id']
                .toString()
                .compareTo(right['parameter_id'].toString()));
          instanceCandidates.add(<String, dynamic>{
            'effect_instance_id': instanceId,
            'row_id': rowId,
            'effect_index': effect['effect_index'],
            'effect_id': effectId,
            'name': effect['name']?.toString() ?? effectId,
            'bypassed': effect['bypassed'] == true,
            'parameters': parameters,
          });
        }
      }
    }

    final catalogCandidates = query.requestedFields.contains('catalog')
        ? catalog
        : const <Map<String, dynamic>>[];
    final recordBudget = <int>[
      query.limit,
      remainingRecords,
    ].reduce((left, right) => left < right ? left : right);
    final returnedInstances =
        instanceCandidates.take(recordBudget).toList(growable: false);
    final remainingQueryRecords = recordBudget - returnedInstances.length;
    final returnedCatalog =
        catalogCandidates.take(remainingQueryRecords).toList(growable: false);

    final parameterCandidates = <Map<String, dynamic>>[];
    if (query.requestedFields.contains('parameter_definitions')) {
      for (final effect in catalog) {
        for (final parameterId in (effect['parameter_ids'] as List)
            .map((value) => value.toString())) {
          parameterCandidates.add(<String, dynamic>{
            'effect_id': effect['effect_id'],
            'parameter_id': parameterId,
            'minimum': 0.0,
            'maximum': 1.0,
          });
        }
      }
    }
    final returnedDefinitions = parameterCandidates
        .take(remainingParameterDefinitions)
        .toList(growable: false);
    final totalRecords = instanceCandidates.length + catalogCandidates.length;
    final returnedRecords = returnedInstances.length + returnedCatalog.length;
    return AiV3EffectsRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      matchedRowIds: rows.map((row) => row['row_id'] as int).toList(),
      instances: returnedInstances,
      catalog: returnedCatalog,
      parameterDefinitions: returnedDefinitions,
      targetCapabilities: query.requestedFields.contains('target_capabilities')
          ? <String, dynamic>{
              'scope': 'row',
              'can_ensure_configured': catalog.isNotEmpty,
              'can_remove': true,
              'can_set_bypassed': true,
              'max_configure_parameters': 16,
              'hosted_plugins_supported': false,
            }
          : null,
      totalRecords: totalRecords,
      returnedRecords: returnedRecords,
      totalParameterDefinitions: parameterCandidates.length,
      returnedParameterDefinitions: returnedDefinitions.length,
      hasMore: returnedRecords < totalRecords ||
          returnedDefinitions.length < parameterCandidates.length,
    );
  }

  List<Map<String, dynamic>> _catalog(PlanningSnapshotV3 snapshot) {
    final catalogs = snapshot.data['catalogs'] as Map;
    final result = (catalogs['effects'] as List? ?? const <Object>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map((effect) {
          final ids = (effect['parameter_ids'] as List? ?? const <Object>[])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          return <String, dynamic>{
            'effect_id': effect['effect_id']?.toString().trim() ?? '',
            'parameter_ids': ids,
          };
        })
        .where((effect) => (effect['effect_id'] as String).isNotEmpty)
        .toList(growable: false)
      ..sort((left, right) => left['effect_id']
          .toString()
          .compareTo(right['effect_id'].toString()));
    return result;
  }
}

class AiV3SamplesContextRetriever {
  const AiV3SamplesContextRetriever();

  AiV3SamplesRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3SamplesContextQuery query,
    required int remainingRecords,
  }) {
    final candidates = <String, Map<String, dynamic>>{};
    for (final assetId in query.targetIds) {
      final asset = snapshot.libraryAssetById[assetId];
      if (asset == null) {
        throw const AiV3RetrievalException('v3_retrieval_target_unknown');
      }
      candidates[assetId] = _candidate(asset, const <String>[]);
    }

    if (query.queryTerms.isNotEmpty) {
      final normalizedTerms = <String>{
        for (final term in query.queryTerms)
          ..._normalize(term)
              .split(RegExp(r'\s+'))
              .where((token) => token.isNotEmpty),
      }.toList(growable: false);
      for (final asset in snapshot.libraryAssetById.values) {
        final path = asset['path']?.toString() ?? '';
        final filename = _filename(path);
        final role = asset['role']?.toString() ?? '';
        final bpm = asset['bpm']?.toString() ?? '';
        final haystack = _normalize('$path $filename $role $bpm');
        final matched = <String>[
          for (final term in normalizedTerms)
            if (haystack.contains(term)) term,
        ];
        if (matched.isEmpty) continue;
        final assetId = asset['asset_id'].toString();
        final value = _candidate(asset, matched);
        final existing = candidates[assetId];
        if (existing == null ||
            (value['_match_count'] as int) >
                (existing['_match_count'] as int)) {
          candidates[assetId] = value;
        }
      }
    }

    final ordered = candidates.values.toList(growable: false)
      ..sort((left, right) {
        final byMatches = (right['_match_count'] as int)
            .compareTo(left['_match_count'] as int);
        if (byMatches != 0) return byMatches;
        final byExact = (right['_exact_matches'] as int)
            .compareTo(left['_exact_matches'] as int);
        if (byExact != 0) return byExact;
        return left['asset_id']
            .toString()
            .compareTo(right['asset_id'].toString());
      });
    final budget = <int>[query.limit, remainingRecords]
        .reduce((left, right) => left < right ? left : right);
    final returned = <Map<String, dynamic>>[];
    for (var index = 0; index < ordered.length && index < budget; index++) {
      final candidate = ordered[index];
      returned.add(<String, dynamic>{
        'asset_id': candidate['asset_id'],
        'filename': candidate['filename'],
        'role': candidate['role'],
        if (candidate['bpm'] != null) 'bpm': candidate['bpm'],
        'matched_terms': candidate['matched_terms'],
        'match_count': candidate['_match_count'],
        'rank': index + 1,
      });
    }

    final rowCapacity =
        (snapshot.data['project'] as Map)['row_capacity'] as Map;
    return AiV3SamplesRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      assets: returned,
      placementCapabilities:
          query.requestedFields.contains('placement_capabilities')
              ? <String, dynamic>{
                  'destination_kinds': <String>[
                    'existing_audio_row',
                    if (rowCapacity['can_create'] == true) 'new_audio_row',
                  ],
                  'position_unit': 'project_beat',
                  'max_placements_per_command': 128,
                }
              : null,
      totalRecords: ordered.length,
      returnedRecords: returned.length,
      hasMore: returned.length < ordered.length,
    );
  }

  Map<String, dynamic> _candidate(
    Map<String, dynamic> asset,
    List<String> matchedTerms,
  ) {
    final path = asset['path']?.toString() ?? '';
    final filename = _filename(path);
    final role = asset['role']?.toString() ?? '';
    final exactMatches = matchedTerms.where((term) {
      final normalized = _normalize(term);
      return normalized == _normalize(filename) ||
          normalized == _normalize(role);
    }).length;
    return <String, dynamic>{
      'asset_id': asset['asset_id'],
      'filename': filename,
      'role': role,
      'bpm': asset['bpm'],
      'matched_terms': List<String>.unmodifiable(matchedTerms),
      '_match_count': matchedTerms.length,
      '_exact_matches': exactMatches,
    };
  }

  String _filename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  String _normalize(String value) => value.trim().toLowerCase();
}

class AiV3AutomationContextRetriever {
  const AiV3AutomationContextRetriever();

  AiV3AutomationRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3AutomationContextQuery query,
    required int remainingPoints,
  }) {
    final sourceRows = <Map<String, dynamic>>[];
    for (final rowId in query.targetIds) {
      final row = snapshot.rowById[rowId];
      if (row == null) {
        throw const AiV3RetrievalException('v3_retrieval_target_unknown');
      }
      sourceRows.add(row);
    }
    sourceRows.sort((left, right) => (left['display_index'] as int)
        .compareTo(right['display_index'] as int));

    final includeGainPoints = query.requestedFields.contains('gain_points');
    final includeTargets = query.requestedFields.contains('automation_targets');
    final includeAutomationPoints =
        query.requestedFields.contains('automation_points');
    final pointBudget = <int>[query.limit, remainingPoints]
        .reduce((left, right) => left < right ? left : right);
    var totalPoints = 0;
    var returnedPoints = 0;
    final rows = <Map<String, dynamic>>[];
    for (final row in sourceRows) {
      List<Map<String, dynamic>> normalizedPoints(Object? rawPoints) =>
          (rawPoints as List? ?? const <Object>[])
              .whereType<Map>()
              .map((raw) {
                final time = raw['time_ms'];
                final value = raw['value'];
                if (time is! num ||
                    !time.isFinite ||
                    time < 0 ||
                    value is! num ||
                    !value.isFinite) {
                  return null;
                }
                return <String, dynamic>{
                  'time_ms': time.toDouble(),
                  'value': value.toDouble(),
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList(growable: false)
            ..sort((left, right) => (left['time_ms'] as double)
                .compareTo(right['time_ms'] as double));

      final targetRecords = (row['automation_targets'] as List? ??
              const <Object>[])
          .whereType<Map>()
          .map((raw) {
            final id = (raw['target_id'] ?? raw['id'])?.toString().trim() ?? '';
            if (id.isEmpty ||
                raw['isOrphan'] == true ||
                raw['is_orphan'] == true ||
                raw['uiVisible'] == false ||
                raw['ui_visible'] == false) {
              return null;
            }
            return <String, dynamic>{
              'automation_target_id': id,
              'label': (raw['fullLabel'] ?? raw['full_label'] ?? raw['label'])
                      ?.toString() ??
                  id,
              'unit': raw['unit']?.toString() ?? '',
              'min': raw['min'],
              'max': raw['max'],
              'current_normalized':
                  raw['initialNormalized'] ?? raw['initial_normalized'],
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList(growable: false)
        ..sort((left, right) => left['automation_target_id']
            .toString()
            .compareTo(right['automation_target_id'].toString()));

      final lanes = <String, List<Map<String, dynamic>>>{};
      final rawLanes = row['automation_points'];
      if (rawLanes is Map) {
        for (final entry in rawLanes.entries) {
          final targetId = entry.key.toString().trim();
          if (targetId.isEmpty) continue;
          lanes[targetId] = normalizedPoints(entry.value);
        }
      }
      lanes.putIfAbsent(
        'volume',
        () => normalizedPoints(row['volume_automation']),
      );

      final requestedLaneIds = <String>{
        if (includeGainPoints) 'volume',
        if (includeAutomationPoints)
          ...targetRecords.map(
            (target) => target['automation_target_id'].toString(),
          ),
      }.toList()
        ..sort();
      final returnedLanes = <String, List<Map<String, dynamic>>>{};
      for (final targetId in requestedLaneIds) {
        final candidates = lanes[targetId] ?? const <Map<String, dynamic>>[];
        totalPoints += candidates.length;
        final remainingForLane = pointBudget - returnedPoints;
        final returned = remainingForLane > 0
            ? candidates.take(remainingForLane).toList(growable: false)
            : const <Map<String, dynamic>>[];
        returnedPoints += returned.length;
        returnedLanes[targetId] = returned;
      }
      rows.add(<String, dynamic>{
        'row_id': row['row_id'],
        if (includeTargets) 'automation_targets': targetRecords,
        if (includeGainPoints)
          'gain_points':
              returnedLanes['volume'] ?? const <Map<String, dynamic>>[],
        if (includeAutomationPoints)
          'automation_points': <String, dynamic>{
            for (final entry in returnedLanes.entries) entry.key: entry.value,
          },
      });
    }

    return AiV3AutomationRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      matchedRowIds:
          sourceRows.map((row) => row['row_id'] as int).toList(growable: false),
      rows: rows,
      targetCapabilities: query.requestedFields.contains('target_capabilities')
          ? const <String, dynamic>{
              'scope': 'row',
              'supports_exact_target_ids': true,
              'supports_set_points': true,
              'supports_clear': true,
              'position_unit': 'project_beat',
              'value_unit': 'normalized_0_to_1',
              'max_set_points': aiV3MaxAutomationPoints,
              'gain_fade_automation_target_id': 'volume',
              'from_gain_db_min': -120.0,
              'from_gain_db_max': 24.0,
              'to_gain_db_min': -120.0,
              'to_gain_db_max': 24.0,
              'to_current_supported': true,
            }
          : null,
      totalPoints:
          includeGainPoints || includeAutomationPoints ? totalPoints : 0,
      returnedPoints:
          includeGainPoints || includeAutomationPoints ? returnedPoints : 0,
      hasMore: (includeGainPoints || includeAutomationPoints) &&
          returnedPoints < totalPoints,
    );
  }
}

class AiV3MixContextRetriever {
  const AiV3MixContextRetriever();

  AiV3MixRetrievalResult retrieveQuery({
    required PlanningSnapshotV3 snapshot,
    required AiV3MixContextQuery query,
    required int remainingRecords,
  }) {
    final sourceRows = <Map<String, dynamic>>[];
    final sourceGroups = <Map<String, dynamic>>[];
    for (final target in query.targetIds) {
      if (target is int) {
        final row = snapshot.rowById[target];
        if (row == null) {
          throw const AiV3RetrievalException('v3_retrieval_target_unknown');
        }
        sourceRows.add(row);
      } else {
        final group = snapshot.groupById[target as String];
        if (group == null) {
          throw const AiV3RetrievalException('v3_retrieval_target_unknown');
        }
        sourceGroups.add(group);
      }
    }
    sourceRows.sort((left, right) => (left['display_index'] as int)
        .compareTo(right['display_index'] as int));
    sourceGroups.sort((left, right) =>
        left['group_id'].toString().compareTo(right['group_id'].toString()));

    final budget = <int>[query.limit, remainingRecords]
        .reduce((left, right) => left < right ? left : right);
    final returnedRows = sourceRows.take(budget).toList(growable: false);
    final remainingForGroups = budget - returnedRows.length;
    final returnedGroups = sourceGroups
        .take(remainingForGroups < 0 ? 0 : remainingForGroups)
        .toList(growable: false);
    final totalRecords = sourceRows.length + sourceGroups.length;
    final returnedRecords = returnedRows.length + returnedGroups.length;
    final wantsRows = query.requestedFields.contains('row_analysis');
    final wantsReferences =
        query.requestedFields.contains('reference_analysis');
    final wantsGroups = query.requestedFields.contains('group_state');

    return AiV3MixRetrievalResult(
      requestId: query.requestId,
      requestedFields: query.requestedFields.toList()..sort(),
      matchedRowIds: returnedRows
          .map((row) => row['row_id'] as int)
          .toList(growable: false),
      matchedGroupIds: returnedGroups
          .map((group) => group['group_id'].toString())
          .toList(growable: false),
      rowAnalysis: wantsRows
          ? returnedRows.map(_rowAnalysis).toList(growable: false)
          : const <Map<String, dynamic>>[],
      groupState: wantsGroups
          ? returnedGroups.map(_groupState).toList(growable: false)
          : const <Map<String, dynamic>>[],
      masterState: query.requestedFields.contains('master_state')
          ? _masterState(snapshot)
          : null,
      referenceAnalysis: wantsReferences
          ? returnedRows.map(_referenceAnalysis).toList(growable: false)
          : const <Map<String, dynamic>>[],
      engineCapabilities: query.requestedFields.contains('engine_capabilities')
          ? const <String, dynamic>{
              'local_heuristic_available': true,
              'subjective_mix_supported': true,
              'reference_mix_supported': true,
              'target_scopes': <String>[
                'row',
                'group',
                'all_rows',
                'master',
              ],
              'learned_refinement': 'resolved_during_materialization',
            }
          : null,
      totalRecords: totalRecords,
      returnedRecords: returnedRecords,
      hasMore: returnedRecords < totalRecords,
    );
  }

  Map<String, dynamic> _rowAnalysis(Map<String, dynamic> row) {
    final analysis = _stringMap(row['analysis']);
    final interpretation = _stringMap(analysis['interpretation']);
    final audioFacts = _stringMap(row['audio_facts']);
    return <String, dynamic>{
      'row_id': row['row_id'],
      'mix_processing_supported':
          audioFacts['mix_processing_supported'] == true,
      'has_usable_signal': audioFacts['has_usable_signal'] == true,
      'analysis_available': audioFacts['analysis_available'] == true,
      'approx_rms': analysis['approx_rms'],
      'approx_crest': analysis['approx_crest'],
      'top_role': interpretation['top_role'],
      'source_type': interpretation['source_type'],
      'interpretation_flags':
          List<Object?>.from(interpretation['flags'] as List? ?? const []),
    };
  }

  Map<String, dynamic> _referenceAnalysis(Map<String, dynamic> row) {
    final analysis = _stringMap(row['analysis']);
    final interpretation = _stringMap(analysis['interpretation']);
    final audioFacts = _stringMap(row['audio_facts']);
    final flags = (interpretation['flags'] as List? ?? const <Object>[])
        .map((value) => value.toString())
        .toSet();
    return <String, dynamic>{
      'row_id': row['row_id'],
      'reference_suitable': audioFacts['reference_suitable'] == true,
      'has_usable_signal': audioFacts['has_usable_signal'] == true,
      'analysis_available': audioFacts['analysis_available'] == true,
      'full_mix_likely': flags.contains('full_mix'),
      'bus_like_likely': flags.contains('bus_like'),
    };
  }

  Map<String, dynamic> _groupState(Map<String, dynamic> group) {
    return <String, dynamic>{
      'group_id': group['group_id'],
      'name': group['name'],
      'member_row_ids': List<Object?>.from(
        group['member_row_ids'] as List? ?? const [],
      ),
      'gain_db': rowGainUiToDb(
        (group['gain_ui'] as num?)?.toDouble() ?? 2.0,
      ),
      'pan_signed':
          (((group['pan_01'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0) *
                  2.0) -
              1.0,
      'muted': group['muted'] == true,
      'soloed': group['soloed'] == true,
      'effects': _effectIdentities(group['effects']),
    };
  }

  Map<String, dynamic> _masterState(PlanningSnapshotV3 snapshot) {
    final master = _stringMap(snapshot.data['master']);
    return <String, dynamic>{
      'gain_db': rowGainUiToDb(
        (master['gain_ui'] as num?)?.toDouble() ?? 2.0,
      ),
      'pan_signed':
          (((master['pan_01'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0) *
                  2.0) -
              1.0,
      'effects': _effectIdentities(master['effects']),
    };
  }

  List<Map<String, dynamic>> _effectIdentities(Object? raw) =>
      (raw as List? ?? const <Object>[])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .map((effect) => <String, dynamic>{
                if ((effect['effect_instance_id']?.toString().trim() ?? '')
                    .isNotEmpty)
                  'effect_instance_id': effect['effect_instance_id'],
                'effect_id': effect['effect_id'],
                'name': effect['name'],
                'bypassed': effect['bypassed'] == true,
              })
          .toList(growable: false);

  Map<String, dynamic> _stringMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

class AiV3ContextRetriever {
  const AiV3ContextRetriever({
    this.clipAdvanced = const AiV3ClipAdvancedContextRetriever(),
    this.midi = const AiV3MidiContextRetriever(),
    this.effects = const AiV3EffectsContextRetriever(),
    this.samples = const AiV3SamplesContextRetriever(),
    this.automation = const AiV3AutomationContextRetriever(),
    this.mix = const AiV3MixContextRetriever(),
  });

  final AiV3ClipAdvancedContextRetriever clipAdvanced;
  final AiV3MidiContextRetriever midi;
  final AiV3EffectsContextRetriever effects;
  final AiV3SamplesContextRetriever samples;
  final AiV3AutomationContextRetriever automation;
  final AiV3MixContextRetriever mix;

  AiV3ContextResult retrieve({
    required PlanningSnapshotV3 snapshot,
    required AiV3ContextRequest request,
  }) {
    var remainingNotes = aiV3MaxRetrievedMidiNotes;
    var remainingEffectRecords = aiV3MaxRetrievedEffectRecords;
    var remainingParameterDefinitions =
        aiV3MaxRetrievedEffectParameterDefinitions;
    var remainingSampleRecords = aiV3MaxRetrievedSampleRecords;
    var remainingAutomationPoints = aiV3MaxRetrievedAutomationPoints;
    var remainingMixRecords = aiV3MaxRetrievedMixRecords;
    var remainingAdvancedClipRecords = aiV3MaxRetrievedAdvancedClipRecords;
    final results = <AiV3DomainRetrievalResult>[];
    for (final query in request.requests) {
      switch (query) {
        case AiV3ClipAdvancedContextQuery():
          final result = clipAdvanced.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingRecords: remainingAdvancedClipRecords,
          );
          remainingAdvancedClipRecords -= result.returnedRecords;
          results.add(result);
        case AiV3MidiContextQuery():
          final result = midi.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingNotes: remainingNotes,
          );
          remainingNotes -= result.returnedNotes;
          results.add(result);
        case AiV3EffectsContextQuery():
          final result = effects.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingRecords: remainingEffectRecords,
            remainingParameterDefinitions: remainingParameterDefinitions,
          );
          remainingEffectRecords -= result.returnedRecords;
          remainingParameterDefinitions -= result.returnedParameterDefinitions;
          results.add(result);
        case AiV3SamplesContextQuery():
          final result = samples.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingRecords: remainingSampleRecords,
          );
          remainingSampleRecords -= result.returnedRecords;
          results.add(result);
        case AiV3AutomationContextQuery():
          final result = automation.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingPoints: remainingAutomationPoints,
          );
          remainingAutomationPoints -= result.returnedPoints;
          results.add(result);
        case AiV3MixContextQuery():
          final result = mix.retrieveQuery(
            snapshot: snapshot,
            query: query,
            remainingRecords: remainingMixRecords,
          );
          remainingMixRecords -= result.returnedRecords;
          results.add(result);
      }
    }
    return AiV3ContextResult(
      snapshotId: snapshot.snapshotId,
      stateDigest: snapshot.stateDigest,
      results: List<AiV3DomainRetrievalResult>.unmodifiable(results),
    );
  }
}

Map<String, dynamic> aiV3GetContextDomainsTool() => <String, dynamic>{
      'type': 'function',
      'name': 'get_context_domains',
      'description':
          'Request one bounded batch of immutable facts from enabled domains when compact context is insufficient to complete the request.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'schema_version': <String, dynamic>{
            'type': 'string',
            'enum': <String>[aiV3ContextRequestVersion],
          },
          'requests': <String, dynamic>{
            'type': 'array',
            'minItems': 1,
            'maxItems': aiV3MaxRetrievalQueries,
            'items': <String, dynamic>{
              'anyOf': <Map<String, dynamic>>[
                ...aiV3RetrievalEnabledDomains.map(_querySchemaForDomain),
              ],
            },
          },
        },
        'required': <String>['schema_version', 'requests'],
        'additionalProperties': false,
      },
      'strict': true,
    };

Map<String, dynamic> _querySchemaForDomain(
  AiV3DomainDefinition definition,
) =>
    switch (definition.id) {
      'clip_advanced' => _clipAdvancedQuerySchema(),
      'midi' => _midiQuerySchema(),
      'effects' => _effectsQuerySchema(),
      'samples' => _samplesQuerySchema(),
      'automation' => _automationQuerySchema(),
      'mix' => _mixQuerySchema(),
      _ => throw StateError(
          'Missing typed query schema for ${definition.id}',
        ),
    };

Map<String, dynamic> _clipAdvancedQuerySchema() => _querySchema(
      domain: 'clip_advanced',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxRetrievalTargetIds,
        'description':
            'Exact audio row or clip IDs. Row IDs return their audio clips. Empty is allowed only for transform_capabilities.',
        'items': <String, dynamic>{
          'anyOf': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'integer', 'minimum': 0},
            <String, dynamic>{'type': 'string', 'minLength': 1},
          ],
        },
      },
      timeRangeSchema: <String, dynamic>{'type': 'null'},
      fields: aiV3ClipAdvancedRequestedFields,
      maxLimit: aiV3MaxRetrievedAdvancedClipRecords,
      limitDescription: 'Maximum number of audio clip records returned.',
    );

Map<String, dynamic> _midiQuerySchema() => _querySchema(
      domain: 'midi',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxRetrievalTargetIds,
        'description':
            'Exact MIDI row or clip IDs. Include every plausible match when a name is ambiguous. When creating a new instrument row and the exact instrument ID is absent from compact context, use an empty array and request edit_capabilities; it returns bounded allowed instrument IDs.',
        'items': <String, dynamic>{
          'anyOf': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'integer', 'minimum': 0},
            <String, dynamic>{'type': 'string', 'minLength': 1},
          ],
        },
      },
      timeRangeSchema: <String, dynamic>{
        'anyOf': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'start_beat': <String, dynamic>{'type': 'number', 'minimum': 0},
              'end_beat': <String, dynamic>{
                'type': 'number',
                'exclusiveMinimum': 0,
              },
            },
            'required': <String>['start_beat', 'end_beat'],
            'additionalProperties': false,
          },
          <String, dynamic>{'type': 'null'},
        ],
      },
      fields: aiV3MidiRequestedFields,
      maxLimit: aiV3MaxRetrievedMidiNotes,
      limitDescription:
          'Maximum number of MIDI notes returned across all matched clips.',
    );

Map<String, dynamic> _effectsQuerySchema() => _querySchema(
      domain: 'effects',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxEffectTargetIds,
        'description':
            'Exact row IDs. Required for instances; empty is allowed for catalog, parameter_definitions, or general built-in target capabilities.',
        'items': <String, dynamic>{'type': 'integer', 'minimum': 0},
      },
      timeRangeSchema: <String, dynamic>{'type': 'null'},
      fields: aiV3EffectRequestedFields,
      fieldsDescription:
          'Request instances for existing effect-instance operations. To add or configure an effect, request the target row plus catalog or parameter_definitions so the continuation receives authoritative effect and parameter IDs.',
      maxLimit: aiV3MaxRetrievedEffectRecords,
      limitDescription:
          'Maximum number of top-level effect instance and catalog records returned.',
    );

Map<String, dynamic> _samplesQuerySchema() => _querySchema(
      domain: 'samples',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxSampleTargetIds,
        'description':
            'Exact sample asset IDs. Use query_terms to search the catalog. Asset metadata requires IDs or query terms.',
        'items': <String, dynamic>{'type': 'string', 'minLength': 1},
      },
      timeRangeSchema: <String, dynamic>{'type': 'null'},
      queryTermsSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxSampleQueryTerms,
        'description':
            'Factual words or short phrases for deterministic filename, role, and BPM matching. Phrases are matched by their words. Required for search_results.',
        'items': <String, dynamic>{
          'type': 'string',
          'minLength': 1,
          'maxLength': aiV3MaxSampleQueryTermLength,
        },
      },
      fields: aiV3SampleRequestedFields,
      maxLimit: aiV3MaxRetrievedSampleRecordsPerQuery,
      limitDescription: 'Maximum number of sample asset records returned.',
    );

Map<String, dynamic> _automationQuerySchema() => _querySchema(
      domain: 'automation',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'minItems': 1,
        'maxItems': aiV3MaxAutomationTargetIds,
        'description':
            'Exact row IDs whose volume-automation facts are required.',
        'items': <String, dynamic>{'type': 'integer', 'minimum': 0},
      },
      timeRangeSchema: <String, dynamic>{'type': 'null'},
      fields: aiV3AutomationRequestedFields,
      maxLimit: aiV3MaxRetrievedAutomationPoints,
      limitDescription:
          'Maximum number of volume-automation points returned across matched rows.',
    );

Map<String, dynamic> _mixQuerySchema() => _querySchema(
      domain: 'mix',
      targetSchema: <String, dynamic>{
        'type': 'array',
        'maxItems': aiV3MaxMixTargetIds,
        'description':
            'Exact integer row_id values for row/reference analysis and exact string group_id values from context.groups for group state. Never use a row ID or display number for group_state. Empty returns no row/reference records and is allowed for master state or engine capabilities.',
        'items': <String, dynamic>{
          'anyOf': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'integer', 'minimum': 0},
            <String, dynamic>{'type': 'string', 'minLength': 1},
          ],
        },
      },
      timeRangeSchema: <String, dynamic>{'type': 'null'},
      fields: aiV3MixRequestedFields,
      maxLimit: aiV3MaxRetrievedMixRecords,
      limitDescription:
          'Maximum number of unique row and group records returned.',
    );

Map<String, dynamic> _querySchema({
  required String domain,
  required Map<String, dynamic> targetSchema,
  required Map<String, dynamic> timeRangeSchema,
  Map<String, dynamic>? queryTermsSchema,
  required Set<String> fields,
  String? fieldsDescription,
  required int maxLimit,
  required String limitDescription,
}) =>
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'request_id': <String, dynamic>{
          'type': 'string',
          'minLength': 1,
          'maxLength': 80,
        },
        'domain': <String, dynamic>{
          'type': 'string',
          'enum': <String>[domain],
        },
        'target_ids': targetSchema,
        'time_range': timeRangeSchema,
        'query_terms': queryTermsSchema ??
            <String, dynamic>{
              'type': 'array',
              'maxItems': 0,
              'items': <String, dynamic>{'type': 'string'},
            },
        'requested_fields': <String, dynamic>{
          'type': 'array',
          'minItems': 1,
          'maxItems': fields.length,
          if (fieldsDescription != null) 'description': fieldsDescription,
          'items': <String, dynamic>{
            'type': 'string',
            'enum': fields.toList()..sort(),
          },
        },
        'limit': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'maximum': maxLimit,
          'description': limitDescription,
        },
      },
      'required': <String>[
        'request_id',
        'domain',
        'target_ids',
        'time_range',
        'query_terms',
        'requested_fields',
        'limit',
      ],
      'additionalProperties': false,
    };

void _requireExactKeys(
  Map<String, dynamic> map,
  Set<String> expected,
  String code,
) {
  if (map.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(map.keys.toSet()).isNotEmpty) {
    throw AiV3RetrievalException(code);
  }
}
