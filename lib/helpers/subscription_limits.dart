import 'package:mixroom/models/entitlement_models.dart';

class SubscriptionLimits {
  const SubscriptionLimits._();

  static const int freeLocalProjects = 10;
  static const int paidLocalProjects = 10000;
  static const int freeRowsPerProject = 5;
  static const int paidRowsPerProject = 100;

  static const Set<String> freeBuiltInEffects = <String>{
    'Gain',
    'Reverb',
    'EQ 3-Band',
    'EQ Parametric',
    'Delay',
    'Compressor',
    'Chorus',
    'Limiter',
  };

  static const Set<String> freeBuiltInInstrumentIds = <String>{
    'sfz.vsco.mixroom_acoustic_drum_kit',
    'sfz.vsco.mixroom_dry_drum_kit',
    'sfz.vsco.upright_piano',
    'mixroom.basic_synth',
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

  static int rowLimitFor(EntitlementSnapshot? entitlement) {
    return isFreePlan(entitlement) ? freeRowsPerProject : paidRowsPerProject;
  }

  static bool canUseInstrument(
    EntitlementSnapshot? entitlement,
    String instrumentId,
  ) {
    if (!isFreePlan(entitlement)) return true;
    return freeBuiltInInstrumentIds.contains(instrumentId.trim());
  }
}
