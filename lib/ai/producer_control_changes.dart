import 'dart:convert';

/// Observed control transitions, including changes from native plugin windows.
/// These are final-state differences, not a reconstruction of gesture timing.
List<Map<String, dynamic>> producerControlChanges(
  Map<String, dynamic> beforeSnapshot,
  Map<String, dynamic> afterSnapshot,
) {
  final before = (beforeSnapshot['project_state'] as Map?) ?? const {};
  final after = (afterSnapshot['project_state'] as Map?) ?? const {};
  final changes = <Map<String, dynamic>>[];
  void field(
    String kind,
    Object? oldValue,
    Object? newValue,
    Map<String, dynamic> target,
  ) {
    if (jsonEncode(oldValue) == jsonEncode(newValue)) return;
    changes.add({
      'kind': kind,
      ...target,
      'before': oldValue,
      'after': newValue,
    });
  }

  void effects(Object? oldChain, Object? newChain, Map<String, dynamic> scope) {
    if (oldChain is! List || newChain is! List) return;
    Map<String, Map> indexed(List chain) => {
      for (final effect in chain.whereType<Map>())
        if ((effect['instanceId']?.toString() ?? '').isNotEmpty)
          effect['instanceId'].toString(): effect,
    };
    final oldEffects = indexed(oldChain), newEffects = indexed(newChain);
    for (final id in {...oldEffects.keys, ...newEffects.keys}) {
      final oldEffect = oldEffects[id], newEffect = newEffects[id];
      final effect = newEffect ?? oldEffect!;
      final target = <String, dynamic>{
        ...scope,
        'instance_id': id,
        'plugin_id': effect['effectId'],
        'effect_name': effect['name'],
      };
      if (oldEffect == null || newEffect == null) {
        field(
          oldEffect == null ? 'plugin_insert' : 'plugin_remove',
          oldEffect,
          newEffect,
          target,
        );
        continue;
      }
      field(
        'plugin_bypass',
        oldEffect['isBypassed'],
        newEffect['isBypassed'],
        target,
      );
      // Compare the relative order of surviving instances. Inserting an effect
      // before an existing instance is not a producer reorder of that instance.
      final oldOrder = oldEffects.keys.where(newEffects.containsKey).toList();
      final newOrder = newEffects.keys.where(oldEffects.containsKey).toList();
      field(
        'plugin_reorder',
        oldOrder.indexOf(id),
        newOrder.indexOf(id),
        target,
      );
      final oldParams = <String, Map>{
        for (final p in (oldEffect['parameters'] as List?) ?? const [])
          if (p is Map && (p['id']?.toString() ?? '').isNotEmpty)
            p['id'].toString(): p,
      };
      for (final parameter in (newEffect['parameters'] as List?) ?? const []) {
        if (parameter is! Map) continue;
        final old = oldParams[parameter['id']?.toString()];
        if (old == null) continue;
        field('plugin_parameter', old['value'], parameter['value'], {
          ...target,
          'parameter_id': parameter['id'],
          'parameter_name': parameter['name'],
          'parameter_type': parameter['type'],
          if (parameter['unit'] != null) 'unit': parameter['unit'],
          if (parameter['min'] != null) 'min': parameter['min'],
          if (parameter['max'] != null) 'max': parameter['max'],
        });
      }
    }
  }

  const master = {'scope': 'master'};
  field('gain', before['master_gain_0to3'], after['master_gain_0to3'], master);
  field('pan', before['master_pan_0to1'], after['master_pan_0to1'], master);
  effects(before['master_effects'], after['master_effects'], master);
  final oldRows = <String, Map>{
    for (final row in (before['rows'] as List?) ?? const [])
      if (row is Map && row['row_id'] != null) row['row_id'].toString(): row,
  };
  for (final row in (after['rows'] as List?) ?? const []) {
    if (row is! Map) continue;
    final old = oldRows[row['row_id']?.toString()];
    if (old == null) continue;
    final scope = {'scope': 'row', 'row': row['row'], 'row_id': row['row_id']};
    final oldMix = (old['mix'] as Map?) ?? const {};
    final newMix = (row['mix'] as Map?) ?? const {};
    field('gain', oldMix['gain_0to3'], newMix['gain_0to3'], scope);
    field('pan', oldMix['pan_0to1'], newMix['pan_0to1'], scope);
    field(
      'automation',
      old['volumeAutomation'],
      row['volumeAutomation'],
      scope,
    );
    effects(old['effects'], row['effects'], scope);
  }
  final oldBuses = {
    for (final bus in (before['group_buses'] as List?) ?? const [])
      if (bus is Map) bus['group_id']: bus,
  };
  for (final bus in (after['group_buses'] as List?) ?? const []) {
    if (bus is! Map) continue;
    final old = oldBuses[bus['group_id']];
    if (old == null) continue;
    final scope = {'scope': 'group', 'group_id': bus['group_id']};
    for (final key in ['gain', 'pan', 'muted', 'soloed']) {
      field(key, old[key], bus[key], scope);
    }
    effects(old['effects'], bus['effects'], scope);
  }
  field('track_groups', before['track_groups'], after['track_groups'], {
    'scope': 'project',
  });
  return changes;
}
