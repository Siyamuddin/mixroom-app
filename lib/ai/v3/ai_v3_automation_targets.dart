import 'ai_v3_contract.dart';

/// Mix automation IDs the planner may legally target on an audio row.
const List<String> aiV3RequiredRowAutomationTargetIds = <String>[
  'volume',
  'mix:gain',
  'mix:pan',
];

String _automationTargetId(Map<String, dynamic> target) {
  for (final key in const <String>['target_id', 'id', 'automation_target_id']) {
    final id = target[key]?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return '';
}

/// Ensures every audio row exposes volume, mix:gain, and mix:pan so spatial
/// and gain automation can be planned without a retrieval round.
List<Map<String, dynamic>> aiV3EnsureRowMixAutomationTargets(
  Iterable<Object?> existing,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final raw in existing) {
    if (raw is! Map) continue;
    final target = Map<String, dynamic>.from(raw);
    final id = _automationTargetId(target);
    if (id.isEmpty) continue;
    target.putIfAbsent('target_id', () => id);
    target.putIfAbsent('id', () => id);
    byId[id] = target;
  }
  for (final id in aiV3RequiredRowAutomationTargetIds) {
    byId.putIfAbsent(
      id,
      () => <String, dynamic>{
        'target_id': id,
        'id': id,
        'kind': id == 'mix:pan' ? 'pan' : 'gain',
        'uiVisible': true,
        'isOrphan': false,
      },
    );
  }
  final ordered = <Map<String, dynamic>>[
    for (final id in aiV3RequiredRowAutomationTargetIds) byId[id]!,
    for (final entry in byId.entries)
      if (!aiV3RequiredRowAutomationTargetIds.contains(entry.key)) entry.value,
  ];
  return ordered;
}

/// True when this plan already writes mix:pan motion.
bool aiV3PlanWritesMixPanAutomation(Iterable<AiV3Command> commands) {
  for (final command in commands) {
    if (command.type != 'automation.set_points') continue;
    final id =
        command.arguments['automation_target_id']?.toString().trim() ?? '';
    if (id == 'mix:pan') return true;
  }
  return false;
}

/// Drops pan intents so mix.apply_goal cannot fight pan automation.
List<Map<String, dynamic>> aiV3MixIntentsWithoutPan(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in raw)
      if (item is Map && item['kind']?.toString().trim() != 'pan')
        Map<String, dynamic>.from(item),
  ];
}

/// Keeps mix intents unless this plan already automates mix:pan.
Object? aiV3ResolvedMixGoalIntents({
  required Iterable<AiV3Command> commands,
  required Object? intents,
}) {
  if (!aiV3PlanWritesMixPanAutomation(commands)) return intents;
  return aiV3MixIntentsWithoutPan(intents);
}
