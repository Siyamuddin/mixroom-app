import 'dart:math' as math;

import 'package:juce_audio_engine/juce_audio_engine.dart';

import '../models/mixing_result.dart';

class ActionExecutorService {
  Future<void> executeAll(List<MixAction> actions) async {
    for (final a in actions) {
      await _executeOne(a);
    }
  }

  Future<void> _executeOne(MixAction action) async {
    switch (action.type) {
      case 'noop':
        return;

      case 'set_row_gain':
        return _setRowGain(action.data);

      case 'set_row_pan':
        return _setRowPan(action.data);

      case 'ensure_effect':
        return _ensureEffect(action.data);

      case 'set_effect_param_by_name':
        return _setEffectParamByName(action.data, isDelta: false);

      case 'adjust_effect_param_by_name':
        return _setEffectParamByName(action.data, isDelta: true);

      default:
        return;
    }
  }

  Future<void> _setRowGain(Map<String, dynamic> d) async {
    final row = d['row'] as int;
    final mode = (d['mode'] ?? 'absolute') as String;

    // If you later add getters, use them. For now we track “delta” by reading nothing and applying from 1.0 baseline.
    // MVP approach: clamp around 1.0.
    if (mode == 'delta') {
      final delta = (d['delta'] as num).toDouble();
      final next = (1.0 + delta).clamp(0.0, 3.0);
      print("setting row gain ${row} ${next}");
      await JuceAudioEngine.setRowGain(row, next);
    } else {
      final gain = (d['gain_0to3'] as num).toDouble().clamp(0.0, 3.0);
      await JuceAudioEngine.setRowGain(row, gain);
    }
  }

  Future<void> _setRowPan(Map<String, dynamic> d) async {
    final row = d['row'] as int;
    final pan = (d['pan_-1to1'] as num).toDouble().clamp(-1.0, 1.0);
    await JuceAudioEngine.setRowPan(row, pan);
  }

  Future<void> _ensureEffect(Map<String, dynamic> d) async {
    final row = d['row'] as int;
    final contains = (d['effect_name_contains'] as String).toLowerCase();

    final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
    final already = effects.indexWhere((e) => e.toLowerCase().contains(contains));
    if (already != -1) return;

    // Insert: find best matching plugin path
    final plugins = await JuceAudioEngine.scanPlugins();
    final match = plugins.firstWhere(
      (p) => (p['name'] ?? '').toLowerCase().contains(contains),
      orElse: () => const {},
    );
    if (match.isEmpty || match['path'] is! String) return;

    final path = match['path'];
    if (path == null || path.isEmpty) {
      // No plugin found; do nothing safely.
      return;
    }

    await JuceAudioEngine.insertTrackEffect(row, path);
  }

  Future<void> _setEffectParamByName(Map<String, dynamic> d, {required bool isDelta}) async {
    final row = d['row'] as int;
    final effectContains = (d['effect_name_contains'] as String).toLowerCase();

    final paramAny = (d['param_name_contains_any'] as List?)?.cast<String>() ?? const ['mix', 'wet'];
    final clamp01 = (d['clamp_0_1'] as bool?) ?? false;
    final skipIfMissing = (d['skip_if_missing_effect'] as bool?) ?? false;

    final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
    final effectIndex = effects.indexWhere((e) => e.toLowerCase().contains(effectContains));
    if (effectIndex == -1) {
      if (skipIfMissing) return;
      // If required, try to ensure then re-find
      await _ensureEffect({'row': row, 'effect_name_contains': effectContains});
    }

    final effects2 = await JuceAudioEngine.getTrackEffectsForRow(row);
    final idx2 = effects2.indexWhere((e) => e.toLowerCase().contains(effectContains));
    if (idx2 == -1) return;

    final params = await JuceAudioEngine.getTrackPluginParameters(row, idx2);

    final picked = _pickParam(params, paramAny);
    if (picked == null) return;

    final paramId = picked['id'] as String;
    final current = _asDouble(picked['value']);

    double next;
    if (isDelta) {
      final delta = (d['delta'] as num).toDouble();
      next = current + delta;
    } else {
      next = (d['value'] as num).toDouble();
    }

    if (clamp01) next = next.clamp(0.0, 1.0);

    await JuceAudioEngine.setTrackEffect(row, idx2, paramId, next);
  }

  Map<String, dynamic>? _pickParam(List<Map<String, dynamic>> params, List<String> nameContainsAny) {
    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final p in params) {
      final name = ((p['name'] ?? '') as String).toLowerCase();
      int score = 0;

      for (final k in nameContainsAny) {
        final kk = k.toLowerCase();
        if (name.contains(kk)) score += 10;
      }
      if (name == 'mix' || name == 'wet') score += 3;

      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }

    if (bestScore <= 0) return null;
    return best;
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
