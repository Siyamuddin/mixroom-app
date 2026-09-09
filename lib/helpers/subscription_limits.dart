import 'package:mixroom/models/entitlement_models.dart';

class SubscriptionLimits {
  const SubscriptionLimits._();

  static const int freeLocalProjects = 10;
  // Paid plans should not enforce a product-level local project cap. This is a
  // defensive guard for code paths that still require a finite integer.
  static const int paidLocalProjects = 0x3fffffff;
  static const int freeRowsPerProject = 5;

  static const Set<String> freeBuiltInEffects = <String>{
    'Gain',
    'Reverb',
    'EQ 3-Band',
    'EQ Parametric',
    'Delay',
    'Compressor',
    'Transient Shaper',
    'Chorus',
    'Limiter',
    'Volume Shaper',
  };

  static const Set<String> freeBuiltInInstrumentIds = <String>{
    'sfz.guitar.steel_acoustic',
    'sfz.guitar.clean_electric',
    'sfz.vsco.mixroom_acoustic_drum_kit',
    'sfz.vsco.mixroom_dry_drum_kit',
    'sfz.vsco.upright_piano',
    'mixroom.basic_synth',
    'mixroom.sampler',
    'mixroom.granularizer',
    'mixroom.bass_mono',
    'mixroom.mellow_sub',
  };

  static bool isFreePlan(EntitlementSnapshot? entitlement) {
    final planCode = entitlement?.planCode.trim().toLowerCase();
    if (planCode == null || planCode.isEmpty) return true;
    return planCode == 'free';
  }

  static bool canUseAllPlugins(EntitlementSnapshot? entitlement) {
    return entitlement?.hasCapability(SubscriptionCapability.allPlugins) ==
        true;
  }

  static bool canUseBuiltInEffect(
    EntitlementSnapshot? entitlement,
    String effectName,
  ) {
    if (canUseAllPlugins(entitlement)) return true;
    return freeBuiltInEffects.contains(effectName.trim());
  }

  static int localProjectLimitFor(EntitlementSnapshot? entitlement) {
    return isFreePlan(entitlement) ? freeLocalProjects : paidLocalProjects;
  }

  static int? rowCreationLimitFor(EntitlementSnapshot? entitlement) {
    return isFreePlan(entitlement) ? freeRowsPerProject : null;
  }

  static bool canCreateRows({
    required int currentRows,
    required int count,
    required int? creationLimit,
  }) {
    if (count <= 0) return true;
    if (currentRows < 0) return false;
    return creationLimit == null || currentRows + count <= creationLimit;
  }

  /// Compatibility adapter for code that still serializes a finite policy.
  /// New editor admission code must use [rowCreationLimitFor].
  static int rowLimitFor(EntitlementSnapshot? entitlement) {
    return rowCreationLimitFor(entitlement) ?? 0x3fffffff;
  }

  static bool canUseInstrument(
    EntitlementSnapshot? entitlement,
    String instrumentId,
  ) {
    if (!isFreePlan(entitlement)) return true;
    return freeBuiltInInstrumentIds.contains(instrumentId.trim());
  }
}
