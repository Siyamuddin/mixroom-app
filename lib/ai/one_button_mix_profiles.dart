import '../models/mixing_result.dart';

/// Stable, all-tier profiles for One-Button Mix.
///
/// The learned magnitude model remains the producer-derived baseline. Profiles
/// add a bounded style bias after refinement and a matching instruction before
/// planning, so they are distinct without requiring separate model weights.
class OneButtonMixProfile {
  const OneButtonMixProfile({
    required this.id,
    required this.label,
    required this.description,
    required this.planningInstruction,
  });

  final String id;
  final String label;
  final String description;
  final String planningInstruction;
}

class OneButtonMixProfiles {
  const OneButtonMixProfiles._();

  static const String producerId = 'mixroom_producer';
  static const String warmSpaciousId = 'warm_spacious';
  static const String punchyEnergeticId = 'punchy_energetic';

  static const OneButtonMixProfile producer = OneButtonMixProfile(
    id: producerId,
    label: 'Mixroom Producer',
    description: 'Balanced, clear, and natural.',
    planningInstruction:
        'Use the balanced Mixroom Producer profile: prioritize clean level '
        'balance, masking reduction, controlled harshness, tasteful space, '
        'and a natural release-ready result.',
  );

  static const OneButtonMixProfile warmSpacious = OneButtonMixProfile(
    id: warmSpaciousId,
    label: 'Warm & Spacious',
    description: 'Rounder tone, softer edges, and deeper space.',
    planningInstruction:
        'Use the Warm & Spacious profile. Make an audibly warmer, wider, and '
        'more spacious mix with round low mids, softened harsh upper mids, '
        'gentler dynamics, and tasteful reverb or delay where appropriate. '
        'Preserve clarity and headroom; do not make the result dull or washed out.',
  );

  static const OneButtonMixProfile punchyEnergetic = OneButtonMixProfile(
    id: punchyEnergeticId,
    label: 'Punchy & Energetic',
    description: 'Tighter lows, stronger transients, and forward energy.',
    planningInstruction:
        'Use the Punchy & Energetic profile. Make an audibly tighter, more '
        'forward, and energetic mix with defined transients, controlled low-end '
        'masking, focused ambience, firm compression, and competitive perceived '
        'loudness. Avoid pumping, clipping, brittle brightness, or excessive limiting.',
  );

  static const List<OneButtonMixProfile> all = <OneButtonMixProfile>[
    producer,
    warmSpacious,
    punchyEnergetic,
  ];

  static OneButtonMixProfile byId(String? rawId) {
    final id = (rawId ?? '').trim().toLowerCase();
    for (final profile in all) {
      if (profile.id == id) return profile;
    }
    return producer;
  }

  static String buildPrompt(String? profileId) {
    final profile = byId(profileId);
    return 'Make this mix sound like a finished, professional release. '
        'Balance levels, reduce masking, tame harshness, and retain safe headroom. '
        '${profile.planningInstruction} '
        'Keep every change musical and bounded. This is an execution, not a '
        'proposal; proceed without asking for approval.';
  }

  static List<MixAction> tuneActions(
    List<MixAction> actions, {
    required String? profileId,
  }) {
    final profile = byId(profileId);
    if (profile.id == producerId || actions.isEmpty) return actions;
    return actions
        .map((action) => _tuneAction(action, profile.id))
        .toList(growable: false);
  }

  static MixAction _tuneAction(MixAction action, String profileId) {
    final factor = _factorFor(action, profileId);
    if ((factor - 1.0).abs() < 0.001) return action;

    final data = Map<String, dynamic>.from(action.data);
    // Delta actions are safe to bias because the existing planner/model has
    // already selected their direction and bounded their initial magnitude.
    for (final key in const <String>['delta', 'delta_norm']) {
      final value = data[key];
      if (value is num) {
        data[key] = value.toDouble() * factor.clamp(0.72, 1.22);
      }
    }
    return MixAction(action.type, data);
  }

  static double _factorFor(MixAction action, String profileId) {
    final type = action.type.trim().toLowerCase();
    final effect = '${action.data['effect_name_contains'] ?? ''}'
        .trim()
        .toLowerCase();

    if (profileId == warmSpaciousId) {
      if (effect.contains('reverb')) return 1.22;
      if (effect.contains('delay')) return 1.16;
      if (effect.contains('compress')) return 0.90;
      if (effect.contains('limiter') || effect.contains('clipper')) return 0.88;
      if (type == 'set_master_gain') return 0.94;
      if (type == 'set_row_pan' || type == 'set_master_pan') return 1.10;
      return _warmEqFactor(action);
    }

    if (profileId == punchyEnergeticId) {
      if (effect.contains('reverb')) return 0.75;
      if (effect.contains('delay')) return 0.82;
      if (effect.contains('compress')) return 1.18;
      if (effect.contains('limiter') || effect.contains('clipper')) return 1.12;
      if (type == 'set_master_gain') return 1.08;
      if (type == 'set_row_pan' || type == 'set_master_pan') return 0.92;
      return _punchyEqFactor(action);
    }
    return 1.0;
  }

  static double _warmEqFactor(MixAction action) {
    if (!_isEqAction(action)) return 1.0;
    final parameter = _parameterText(action);
    final delta = _deltaValue(action);
    if (parameter.contains('high')) return delta >= 0 ? 0.82 : 1.15;
    if (parameter.contains('low')) return delta >= 0 ? 1.12 : 0.92;
    return 1.0;
  }

  static double _punchyEqFactor(MixAction action) {
    if (!_isEqAction(action)) return 1.0;
    final parameter = _parameterText(action);
    final delta = _deltaValue(action);
    if (parameter.contains('high')) return delta >= 0 ? 1.08 : 0.94;
    if (parameter.contains('low')) return delta >= 0 ? 0.86 : 1.12;
    return 1.0;
  }

  static bool _isEqAction(MixAction action) =>
      '${action.data['effect_name_contains'] ?? ''}'.toLowerCase().contains(
        'eq',
      );

  static String _parameterText(MixAction action) {
    final exact = '${action.data['param_name'] ?? ''}';
    final fuzzy = action.data['param_name_contains_any'];
    return '$exact ${fuzzy is List ? fuzzy.join(' ') : ''}'.toLowerCase();
  }

  static double _deltaValue(MixAction action) {
    final value = action.data['delta'] ?? action.data['delta_norm'];
    return value is num ? value.toDouble() : 0.0;
  }
}
