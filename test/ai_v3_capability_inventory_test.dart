import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_contract.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _stringMap(Object? value) {
  if (value is! Map) {
    throw StateError('Expected a map, got ${value.runtimeType}.');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<dynamic> _list(Object? value) {
  if (value is! List) {
    throw StateError('Expected a list, got ${value.runtimeType}.');
  }
  return value;
}

Set<String> _strings(Object? value) =>
    _list(value).map((item) => item.toString()).toSet();

Map<String, dynamic> _loadInventory() {
  final text = File('tool/ai_v3_eval/v3_capabilities.yaml').readAsStringSync();
  return _stringMap(loadYaml(text));
}

Map<String, dynamic> _loadAdaptiveArchitecture() {
  final text =
      File('tool/ai_v3_eval/v3_adaptive_architecture.yaml').readAsStringSync();
  return _stringMap(loadYaml(text));
}

Iterable<Map<String, dynamic>> _families(Map<String, dynamic> inventory) =>
    _list(inventory['direct_action_families']).map(_stringMap);

Iterable<Map<String, dynamic>> _operations(
    Map<String, dynamic> inventory) sync* {
  for (final family in _families(inventory)) {
    for (final operation in _list(family['operations'])) {
      yield <String, dynamic>{
        ...family,
        ..._stringMap(operation),
        'family': family['family'],
      };
    }
  }
}

Iterable<Map<String, dynamic>> _allAuditedEntries(
  Map<String, dynamic> inventory,
) sync* {
  for (final key in <String>[
    'entry_surfaces',
    'mix_engines',
    'audio_and_context_models',
    'cross_cutting_capabilities',
  ]) {
    yield* _list(inventory[key]).map(_stringMap);
  }
  yield* _families(inventory).where(
    (family) => _list(family['operations']).isEmpty,
  );
  yield* _operations(inventory);
  yield _stringMap(inventory['mix_goal_contract']);
  yield _stringMap(inventory['reference_mixing']);

  final mixActions = _stringMap(inventory['mix_actions']);
  final common = _stringMap(mixActions['common']);
  for (final value in _list(mixActions['actions'])) {
    yield <String, dynamic>{...common, ..._stringMap(value)};
  }
}

void main() {
  late Map<String, dynamic> inventory;

  setUpAll(() {
    inventory = _loadInventory();
  });

  test('inventory exactly covers the canonical 22 families and 87 operations',
      () {
    final auditedFamilies = <String, Map<String, dynamic>>{
      for (final family in _families(inventory))
        family['family'].toString(): family,
    };

    expect(auditedFamilies, hasLength(22));
    final operationCount = auditedFamilies.values
        .map((family) => _list(family['operations']).length)
        .fold<int>(0, (total, count) => total + count);
    expect(operationCount, 87);
  });

  test('adaptive architecture accounts for every V1 family and V3 command', () {
    expect(
      _stringMap(inventory['inventory_rules'])['v3_prototype_command_count'],
      aiV3CommandTypes.length,
    );
    final adaptive = _loadAdaptiveArchitecture();
    final canonicalFamilies = <String, Map<String, dynamic>>{
      for (final family in _families(inventory))
        family['family'].toString(): family,
    };
    final placement = _stringMap(adaptive['v1_capability_placement']);
    final familyDefaults = _stringMap(placement['family_defaults']);
    expect(familyDefaults.keys.toSet(), canonicalFamilies.keys.toSet());

    final common = _stringMap(adaptive['common_commands']);
    final commonCommands = _strings(common['commands']);
    expect(common['count'], 17);
    expect(commonCommands, hasLength(17));

    final domains = _stringMap(adaptive['domains']);
    final requestedFields = _stringMap(adaptive['domain_requested_fields']);
    expect(requestedFields.keys.toSet(), domains.keys.toSet());
    for (final entry in requestedFields.entries) {
      expect(
        _strings(entry.value),
        isNotEmpty,
        reason: 'Missing requested-field registry for ${entry.key}.',
      );
    }
    final domainCommands = <String>{};
    for (final raw in domains.values) {
      final domain = _stringMap(raw);
      domainCommands.addAll(_strings(domain['current_commands']));
    }
    expect(commonCommands.intersection(domainCommands), isEmpty);
    expect(commonCommands.union(domainCommands), aiV3CommandTypes);

    final operationOverrides = _stringMap(placement['operation_overrides']);
    for (final key in operationOverrides.keys) {
      final separator = key.indexOf('.');
      expect(separator, greaterThan(0), reason: 'Malformed override: $key');
      final family = key.substring(0, separator);
      final operation = key.substring(separator + 1);
      expect(canonicalFamilies, contains(family));
      expect(
        _list(canonicalFamilies[family]!['operations'])
            .map(_stringMap)
            .map((entry) => entry['operation'].toString())
            .toSet(),
        contains(operation),
        reason: 'Unknown operation override: $key',
      );
    }
  });

  test(
      'every audited entry has status, evidence, implementation, and V3 disposition',
      () {
    final rules = _stringMap(inventory['inventory_rules']);
    final statuses = _strings(rules['allowed_v1_statuses']);
    final dispositions = _strings(rules['allowed_v3_dispositions']);
    final ids = <String>{};

    for (final entry in _allAuditedEntries(inventory)) {
      final id = entry['id']?.toString() ?? '';
      expect(id, isNotEmpty, reason: 'Missing stable ID: $entry');
      expect(ids.add(id), isTrue, reason: 'Duplicate inventory ID: $id');

      final status = entry['status']?.toString();
      expect(statuses, contains(status), reason: 'Invalid status for $id.');
      expect(status, isNot('not_audited'));
      expect(entry['category']?.toString(), isNotEmpty,
          reason: 'Missing category for $id.');
      expect(entry['purpose']?.toString(), isNotEmpty,
          reason: 'Missing purpose for $id.');
      expect(entry['inputs'], isA<List>(), reason: 'Missing inputs for $id.');
      expect(entry['target_semantics']?.toString(), isNotEmpty,
          reason: 'Missing target semantics for $id.');
      expect(entry['context'], isNotNull, reason: 'Missing context for $id.');
      expect(_list(entry['evidence']), isNotEmpty,
          reason: 'Missing evidence for $id.');
      expect(entry['implementation'], isA<Map>(),
          reason: 'Missing implementation trace for $id.');
      expect(entry['execution'], isA<Map>(),
          reason: 'Missing execution behavior for $id.');
      expect(entry['dependencies'], isA<List>(),
          reason: 'Missing dependencies for $id.');
      expect(entry['gaps'], isA<List>(), reason: 'Missing gaps for $id.');

      final v3 = _stringMap(entry['v3']);
      expect(dispositions, contains(v3['disposition']),
          reason: 'Invalid V3 disposition for $id.');
      expect(v3['phase']?.toString(), isNotEmpty,
          reason: 'Missing V3 phase for $id.');
      expect(v3.containsKey('dependency'), isTrue,
          reason: 'Missing V3 dependency for $id.');
    }
  });

  test('all V1 top-level response surfaces are inventoried', () {
    final surfaces = _list(inventory['entry_surfaces'])
        .map(_stringMap)
        .map((entry) => entry['id'].toString())
        .toSet();
    expect(
      surfaces,
      containsAll(<String>{
        'entry.daw_assistant_actions',
        'entry.mix_model_request',
        'entry.informational_response',
        'entry.tutorial',
        'entry.clarify',
        'entry.compound_calls',
        'entry.one_button_mix',
      }),
    );
  });

  test('inventory declares its DAW-only boundary', () {
    final scope = _stringMap(inventory['scope']);
    expect(scope['included']?.toString(), contains('DAW'));
    expect(scope['excluded']?.toString(), contains('Video Editor AI'));
  });

  test('editor alias drift and automation templates remain explicit', () {
    final discrepancy = _list(inventory['known_discrepancies'])
        .map(_stringMap)
        .singleWhere((entry) => entry['id'] == 'discrepancy.alias_authority');
    expect(discrepancy['finding']?.toString(), contains('set_points'));
    expect(discrepancy['finding']?.toString(), contains('create_clip'));

    final automation = _families(inventory)
        .singleWhere((family) => family['family'] == 'automation_edit');
    expect(
      _stringMap(automation['template_catalog']).keys.toSet(),
      <String>{
        'sidechain_pump',
        'sidechain_from_kick',
        'reverb_tail',
        'filter_sweep',
        'auto_pan',
      },
    );
  });

  test('mix executor and materialized action tokens are inventoried', () {
    final mixActions = _stringMap(inventory['mix_actions']);
    final inventoried = _list(mixActions['actions'])
        .map(_stringMap)
        .map((entry) => entry['type'].toString())
        .toSet();

    final editor = File('lib/screens/audio_editor.dart').readAsStringSync();
    final start = editor.indexOf('Future<MixApplyReport> applyMixingResult(');
    final end = editor.indexOf('Future<', start + 1);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final executorBody = editor.substring(start, end);
    final executorTypes = RegExp("case '([^']+)':")
        .allMatches(executorBody)
        .map((match) => match.group(1)!)
        .toSet();

    final model = File('lib/ai/local_mixing_model.dart').readAsStringSync();
    final emittedTypes = RegExp("MixAction\\(\\s*'([^']+)'")
        .allMatches(model)
        .map((match) => match.group(1)!)
        .toSet();

    expect(inventoried, containsAll(executorTypes));
    expect(inventoried, containsAll(emittedTypes));
  });

  test('mix engines and audio/model routes are explicit', () {
    final engines = _list(inventory['mix_engines'])
        .map(_stringMap)
        .map((entry) => entry['id'].toString())
        .toSet();
    expect(
      engines,
      containsAll(<String>{
        'mixing.engine.local_heuristic',
        'mixing.engine.local_onnx_refinement',
        'mixing.engine.remote_refinement',
        'mixing.engine.disabled_refinement',
      }),
    );

    final models = _list(inventory['audio_and_context_models'])
        .map(_stringMap)
        .map((entry) => entry['id'].toString())
        .toSet();
    expect(
      models,
      containsAll(<String>{
        'audio_model.spleeter_two_stem',
        'audio_model.basic_pitch',
        'audio_model.yamnet_instrument_classifier',
        'audio_model.project_state_analysis',
        'audio_processing.phone_mic_cleanup',
        'catalog.sample_library',
        'catalog.instruments_effects_plugins',
      }),
    );
  });

  test('reference modes and closeness values match the Dart contract', () {
    final reference = _stringMap(inventory['reference_mixing']);
    expect(
      _strings(reference['modes']),
      <String>{'tone', 'loudness', 'width', 'glue', 'full_mix'},
    );
    expect(
      _strings(reference['closeness']),
      <String>{'loose', 'balanced', 'close'},
    );
  });

  test('mix goal inventory records the closed GPT-facing vocabulary', () {
    final goal = _stringMap(inventory['mix_goal_contract']);
    final fields = _stringMap(goal['fields']);
    final intents = _stringMap(fields['intents']);
    expect(
      _strings(intents['kinds']),
      <String>{
        'gain',
        'pan',
        'eq',
        'reverb',
        'delay',
        'distortion',
        'deesser',
        'compressor',
        'limiter',
        'clipper',
        'balance',
      },
    );
    expect(
      _stringMap(fields['style_tags'])['reachability'],
      'accepted_by_downstream_normalizers_but_not_declared_in_current_gpt_tool_schema',
    );
    expect(
      _stringMap(fields['destructive_ok'])['reachability'],
      'accepted_by_downstream_normalizers_but_not_declared_in_current_gpt_tool_schema',
    );
  });

  test('every current PlanV3 command has a V1 mapping', () {
    final mappings = _list(inventory['v3_prototype_commands'])
        .map(_stringMap)
        .map((entry) => entry['command'].toString())
        .toSet();
    expect(mappings, aiV3CommandTypes);
    for (final entry
        in _list(inventory['v3_prototype_commands']).map(_stringMap)) {
      expect(entry['maps_to'], isNotNull,
          reason: 'Missing V1 mapping for ${entry['command']}.');
    }
  });
}
