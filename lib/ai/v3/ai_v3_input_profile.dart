import 'dart:convert';

class AiV3InputMeasurement {
  const AiV3InputMeasurement({
    required this.utf8Bytes,
    required this.approximateTokens,
  });

  factory AiV3InputMeasurement.text(String value) => AiV3InputMeasurement(
        utf8Bytes: utf8.encode(value).length,
        approximateTokens: (value.length / 4).ceil(),
      );

  factory AiV3InputMeasurement.json(Object? value) =>
      AiV3InputMeasurement.text(jsonEncode(value));

  final int utf8Bytes;
  final int approximateTokens;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'utf8_bytes': utf8Bytes,
        'approximate_tokens': approximateTokens,
      };
}

/// Diagnostic-only breakdown of the exact V3 request payload.
///
/// Component token figures are deliberately labelled as approximations. Only
/// the provider usage value, when present, is an exact model token count.
class AiV3PlannerInputProfile {
  const AiV3PlannerInputProfile({
    required this.fullPayload,
    required this.primarySections,
    required this.contextDetails,
    required this.commandSchemaBranches,
    required this.sharedPlanSchema,
    required this.repeatedScalarFields,
    this.providerInputTokens,
  });

  factory AiV3PlannerInputProfile.measure({
    required Map<String, dynamic> requestBody,
    required Map<String, dynamic> contextData,
    int? providerInputTokens,
  }) {
    final content = _inputTextContent(requestBody);
    final plannerContext = Map<String, dynamic>.from(contextData)
      ..remove('original_request')
      ..remove('conversation');
    final primary = <String, AiV3InputMeasurement>{
      'planner_instructions': AiV3InputMeasurement.text(
          requestBody['instructions']?.toString() ?? ''),
      'original_request': AiV3InputMeasurement.text(
        content.isNotEmpty ? _stripLabel(content[0]) : '',
      ),
      'recent_conversation': AiV3InputMeasurement.json(
        contextData['conversation'] ?? const <Object>[],
      ),
      for (final entry in plannerContext.entries)
        'context.${entry.key}': AiV3InputMeasurement.json(entry.value),
      'tool_schema': AiV3InputMeasurement.json(requestBody['tools']),
      'request_envelope': AiV3InputMeasurement.json(
        _requestEnvelope(requestBody),
      ),
    };
    final tools = requestBody['tools'];
    final tool = tools is List && tools.isNotEmpty && tools.first is Map
        ? Map<String, dynamic>.from(tools.first as Map)
        : const <String, dynamic>{};
    final branches = _commandBranches(tool);
    return AiV3PlannerInputProfile(
      fullPayload: AiV3InputMeasurement.json(requestBody),
      primarySections: primary,
      contextDetails: _contextDetails(plannerContext),
      commandSchemaBranches: <String, AiV3InputMeasurement>{
        for (final entry in branches.entries)
          entry.key: AiV3InputMeasurement.json(entry.value),
      },
      sharedPlanSchema: AiV3InputMeasurement.json(
        _toolWithoutCommandBranches(tool),
      ),
      repeatedScalarFields: _repeatedScalarFields(<Object?>[
        plannerContext,
        tool,
      ]),
      providerInputTokens: providerInputTokens,
    );
  }

  final AiV3InputMeasurement fullPayload;
  final Map<String, AiV3InputMeasurement> primarySections;
  final Map<String, AiV3InputMeasurement> contextDetails;
  final Map<String, AiV3InputMeasurement> commandSchemaBranches;
  final AiV3InputMeasurement sharedPlanSchema;
  final List<Map<String, dynamic>> repeatedScalarFields;
  final int? providerInputTokens;

  List<Map<String, dynamic>> get rankedContributors {
    final entries = primarySections.entries.toList()
      ..sort((a, b) => b.value.utf8Bytes.compareTo(a.value.utf8Bytes));
    return entries
        .map((entry) => <String, dynamic>{
              'section': entry.key,
              ...entry.value.toJson(),
            })
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'full_payload': fullPayload.toJson(),
        'provider_input_tokens': providerInputTokens,
        if (providerInputTokens != null)
          'provider_minus_local_approximation':
              providerInputTokens! - fullPayload.approximateTokens,
        'primary_sections': <String, dynamic>{
          for (final entry in primarySections.entries)
            entry.key: entry.value.toJson(),
        },
        'ranked_contributors': rankedContributors,
        'overlapping_context_details': <String, dynamic>{
          for (final entry in contextDetails.entries)
            entry.key: entry.value.toJson(),
        },
        'tool_schema_details': <String, dynamic>{
          'shared_without_command_branches': sharedPlanSchema.toJson(),
          'command_branches': <String, dynamic>{
            for (final entry in commandSchemaBranches.entries)
              entry.key: entry.value.toJson(),
          },
        },
        'repeated_scalar_fields': repeatedScalarFields,
        'measurement_note':
            'Per-section token counts use the labelled characters/4 approximation; provider_input_tokens is exact when present. Detail measurements overlap their parent sections.',
      };
}

List<String> _inputTextContent(Map<String, dynamic> body) {
  final input = body['input'];
  if (input is! List || input.isEmpty || input.first is! Map) return const [];
  final content = (input.first as Map)['content'];
  if (content is! List) return const [];
  return content
      .whereType<Map>()
      .map((entry) => entry['text']?.toString() ?? '')
      .toList(growable: false);
}

String _stripLabel(String value) {
  final newline = value.indexOf('\n');
  return newline < 0 ? value : value.substring(newline + 1);
}

Map<String, dynamic> _requestEnvelope(Map<String, dynamic> body) {
  final clone = _jsonMap(body);
  clone['instructions'] = '';
  clone['tools'] = const <Object>[];
  final input = clone['input'];
  if (input is List) {
    for (final item in input.whereType<Map>()) {
      final content = item['content'];
      if (content is List) {
        for (final part in content.whereType<Map>()) {
          part['text'] = '';
        }
      }
    }
  }
  return clone;
}

Map<String, dynamic> _commandBranches(Map<String, dynamic> tool) {
  Object? current = tool['parameters'];
  if (current is! Map) return const <String, dynamic>{};
  current = current['properties'];
  if (current is! Map) return const <String, dynamic>{};
  current = current['commands'];
  if (current is! Map) return const <String, dynamic>{};
  current = current['items'];
  if (current is! Map) return const <String, dynamic>{};
  final variants = current['anyOf'];
  if (variants is! List) return const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final raw in variants.whereType<Map>()) {
    final properties = raw['properties'];
    final typeSchema = properties is Map ? properties['type'] : null;
    final values = typeSchema is Map ? typeSchema['enum'] : null;
    final type = values is List && values.length == 1
        ? values.single.toString()
        : 'unknown_${out.length}';
    out[type] = Map<String, dynamic>.from(raw);
  }
  return out;
}

Map<String, dynamic> _toolWithoutCommandBranches(Map<String, dynamic> tool) {
  final clone = _jsonMap(tool);
  final parameters = clone['parameters'];
  final properties = parameters is Map ? parameters['properties'] : null;
  final commands = properties is Map ? properties['commands'] : null;
  final items = commands is Map ? commands['items'] : null;
  if (items is Map) items['anyOf'] = const <Object>[];
  return clone;
}

Map<String, AiV3InputMeasurement> _contextDetails(
  Map<String, dynamic> context,
) {
  final rows = (context['rows'] as List? ?? const <Object>[])
      .whereType<Map>()
      .toList(growable: false);
  final clips = (context['clips'] as List? ?? const <Object>[])
      .whereType<Map>()
      .toList(growable: false);
  Object rowFields(Set<String> fields) => rows
      .map((row) => <String, dynamic>{
            for (final key in fields)
              if (row.containsKey(key)) key: row[key],
          })
      .toList(growable: false);
  Object clipFields(Set<String> fields) => clips
      .map((clip) => <String, dynamic>{
            for (final key in fields)
              if (clip.containsKey(key)) key: clip[key],
          })
      .toList(growable: false);
  return <String, AiV3InputMeasurement>{
    'rows.identity': AiV3InputMeasurement.json(rowFields(const <String>{
      'row_id',
      'display_index',
      'name',
      'lane_kind',
      'group_id',
      'clip_ids',
    })),
    'rows.mixer_state': AiV3InputMeasurement.json(rowFields(const <String>{
      'instrument_id',
      'has_usable_signal',
      'analysis_available',
      'has_analyzable_audio',
      'gain_db',
      'pan_signed',
      'muted',
      'soloed',
    })),
    'rows.effects':
        AiV3InputMeasurement.json(rowFields(const <String>{'effects'})),
    'rows.effect_parameters': AiV3InputMeasurement.json(rows
        .expand((row) => (row['effects'] as List? ?? const <Object>[]))
        .whereType<Map>()
        .map((effect) => effect['parameters'] ?? const <Object>[])
        .toList(growable: false)),
    'rows.automation': AiV3InputMeasurement.json(
      rowFields(const <String>{'automation_targets'}),
    ),
    'clips.identity_and_timing': AiV3InputMeasurement.json(clipFields(
      const <String>{
        'clip_id',
        'row_id',
        'display_index',
        'kind',
        'name',
        'start_beat',
        'length_beats',
      },
    )),
    'clips.source_metadata': AiV3InputMeasurement.json(clipFields(
      const <String>{'source_file', 'instrument_id', 'pitch_semitones'},
    )),
    'clips.midi_notes': AiV3InputMeasurement.json(
      clipFields(const <String>{'midi_notes'}),
    ),
    'catalogs.instruments':
        AiV3InputMeasurement.json(context['instruments'] ?? const <Object>[]),
    'catalogs.effects':
        AiV3InputMeasurement.json(context['effects'] ?? const <Object>[]),
    'catalogs.library_assets': AiV3InputMeasurement.json(
      context['library_assets'] ?? const <Object>[],
    ),
    'groups': AiV3InputMeasurement.json(context['groups'] ?? const <Object>[]),
    'master': AiV3InputMeasurement.json(
      context['master'] ?? const <String, dynamic>{},
    ),
    'pending_plan': AiV3InputMeasurement.json(
      context['pending_plan'] ?? const <String, dynamic>{},
    ),
  };
}

List<Map<String, dynamic>> _repeatedScalarFields(Iterable<Object?> roots) {
  final valuesByField = <String, Map<String, int>>{};
  void visit(Object? value, String field) {
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, entry.key.toString());
      }
    } else if (value is Iterable) {
      for (final item in value) {
        visit(item, field);
      }
    } else if (value is String || value is num || value is bool) {
      final encoded = jsonEncode(value);
      (valuesByField[field] ??= <String, int>{})
          .update(encoded, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  for (final root in roots) {
    visit(root, 'root');
  }
  final results = <Map<String, dynamic>>[];
  for (final entry in valuesByField.entries) {
    var duplicateOccurrences = 0;
    var estimatedRepeatedBytes = 0;
    for (final value in entry.value.entries) {
      if (value.value < 2) continue;
      duplicateOccurrences += value.value - 1;
      estimatedRepeatedBytes +=
          (value.value - 1) * utf8.encode(value.key).length;
    }
    if (duplicateOccurrences == 0) continue;
    results.add(<String, dynamic>{
      'field': entry.key,
      'duplicate_occurrences': duplicateOccurrences,
      'estimated_repeated_value_bytes': estimatedRepeatedBytes,
    });
  }
  results.sort((a, b) => (b['estimated_repeated_value_bytes'] as int)
      .compareTo(a['estimated_repeated_value_bytes'] as int));
  return results.take(40).toList(growable: false);
}

Map<String, dynamic> _jsonMap(Map<dynamic, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
