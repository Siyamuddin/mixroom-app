import 'dart:async';
import 'package:flutter/foundation.dart';

class HaloKey {
  final String key;
  const HaloKey(this.key);

  @override
  bool operator ==(Object other) => other is HaloKey && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class MixChangeHighlighter {
  final ValueNotifier<Set<HaloKey>> active =
      ValueNotifier<Set<HaloKey>>(<HaloKey>{});
  final Map<HaloKey, Timer> _timers = {};

  void trigger(List<HaloKey> keys,
      {Duration duration = const Duration(milliseconds: 800)}) {
    if (keys.isEmpty) {
      clear();
      return;
    }
    final next = {...active.value};
    for (final k in keys) {
      next.add(k);

      _timers[k]?.cancel();
      _timers[k] = Timer(duration, () {
        final cur = {...active.value};
        cur.remove(k);
        active.value = cur;
        _timers.remove(k);
      });
    }
    active.value = next;
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    if (active.value.isEmpty) return;
    active.value = <HaloKey>{};
  }

  void dispose() {
    clear();
    active.dispose();
  }
}
