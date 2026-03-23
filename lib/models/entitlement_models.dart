import 'package:mixroom/config/app_api_config.dart';

enum PlanTier { free, pro, studio }

extension PlanTierX on PlanTier {
  String get value {
    switch (this) {
      case PlanTier.free:
        return 'free';
      case PlanTier.pro:
        return 'pro';
      case PlanTier.studio:
        return 'studio';
    }
  }

  static PlanTier fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pro':
        return PlanTier.pro;
      case 'studio':
        return PlanTier.studio;
      default:
        return PlanTier.free;
    }
  }
}

enum BillingProvider { apple, google, paddle, toss, adminGrant, unknown }

extension BillingProviderX on BillingProvider {
  String get value {
    switch (this) {
      case BillingProvider.apple:
        return 'apple';
      case BillingProvider.google:
        return 'google';
      case BillingProvider.paddle:
        return 'paddle';
      case BillingProvider.toss:
        return 'toss';
      case BillingProvider.adminGrant:
        return 'admin_grant';
      case BillingProvider.unknown:
        return 'unknown';
    }
  }

  static BillingProvider fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'apple':
        return BillingProvider.apple;
      case 'google':
        return BillingProvider.google;
      case 'paddle':
        return BillingProvider.paddle;
      case 'toss':
        return BillingProvider.toss;
      case 'admin_grant':
        return BillingProvider.adminGrant;
      default:
        return BillingProvider.unknown;
    }
  }
}

enum SubscriptionStatus {
  trialing,
  active,
  gracePeriod,
  pastDue,
  paused,
  canceled,
  expired,
  refunded,
  revoked
}

extension SubscriptionStatusX on SubscriptionStatus {
  String get value {
    switch (this) {
      case SubscriptionStatus.trialing:
        return 'trialing';
      case SubscriptionStatus.active:
        return 'active';
      case SubscriptionStatus.gracePeriod:
        return 'grace_period';
      case SubscriptionStatus.pastDue:
        return 'past_due';
      case SubscriptionStatus.paused:
        return 'paused';
      case SubscriptionStatus.canceled:
        return 'canceled';
      case SubscriptionStatus.expired:
        return 'expired';
      case SubscriptionStatus.refunded:
        return 'refunded';
      case SubscriptionStatus.revoked:
        return 'revoked';
    }
  }

  static SubscriptionStatus fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'trialing':
        return SubscriptionStatus.trialing;
      case 'active':
        return SubscriptionStatus.active;
      case 'grace_period':
        return SubscriptionStatus.gracePeriod;
      case 'past_due':
        return SubscriptionStatus.pastDue;
      case 'paused':
        return SubscriptionStatus.paused;
      case 'canceled':
        return SubscriptionStatus.canceled;
      case 'refunded':
        return SubscriptionStatus.refunded;
      case 'revoked':
        return SubscriptionStatus.revoked;
      default:
        return SubscriptionStatus.expired;
    }
  }
}

class SubscriptionCapability {
  const SubscriptionCapability._();

  static const String proEditor = 'pro_editor';
  static const String unlimitedAudioTracks = 'unlimited_audio_tracks';
  static const String multiVideoImport = 'multi_video_import';
  static const String premiumEffects = 'premium_effects';
  static const String videoProjects = 'video_projects';
  static const String webCheckout = 'web_checkout';
  static const String mobileIap = 'mobile_iap';
  static const String studioFeatures = 'studio_features';
}

Map<String, bool> defaultCapabilitiesForTier(PlanTier tier) {
  final freeCapabilities = <String, bool>{
    SubscriptionCapability.proEditor: false,
    SubscriptionCapability.unlimitedAudioTracks: false,
    SubscriptionCapability.multiVideoImport: false,
    SubscriptionCapability.premiumEffects: false,
    SubscriptionCapability.videoProjects: true,
    SubscriptionCapability.webCheckout: true,
    SubscriptionCapability.mobileIap: true,
    SubscriptionCapability.studioFeatures: false,
  };

  switch (tier) {
    case PlanTier.free:
      return freeCapabilities;
    case PlanTier.pro:
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.proEditor: true,
        SubscriptionCapability.unlimitedAudioTracks: true,
        SubscriptionCapability.multiVideoImport: true,
        SubscriptionCapability.premiumEffects: true,
      };
    case PlanTier.studio:
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.proEditor: true,
        SubscriptionCapability.unlimitedAudioTracks: true,
        SubscriptionCapability.multiVideoImport: true,
        SubscriptionCapability.premiumEffects: true,
        SubscriptionCapability.studioFeatures: AppApiConfig.allowStudioTier,
      };
  }
}

class EntitlementSnapshot {
  const EntitlementSnapshot({
    required this.userId,
    required this.tier,
    required this.status,
    required this.effectiveAt,
    required this.expiresAt,
    required this.sourceProvider,
    required this.sourceSubscriptionId,
    required this.capabilities,
    required this.managementChannel,
    required this.revision,
  });

  final String userId;
  final PlanTier tier;
  final SubscriptionStatus status;
  final DateTime effectiveAt;
  final DateTime? expiresAt;
  final BillingProvider sourceProvider;
  final String sourceSubscriptionId;
  final Map<String, bool> capabilities;
  final String managementChannel;
  final int revision;

  bool hasCapability(String key) => capabilities[key] == true;

  bool get isPaidTier => tier == PlanTier.pro || tier == PlanTier.studio;

  bool get isAccessActive {
    switch (status) {
      case SubscriptionStatus.trialing:
      case SubscriptionStatus.active:
      case SubscriptionStatus.gracePeriod:
        return true;
      case SubscriptionStatus.pastDue:
      case SubscriptionStatus.paused:
      case SubscriptionStatus.canceled:
      case SubscriptionStatus.expired:
      case SubscriptionStatus.refunded:
      case SubscriptionStatus.revoked:
        return false;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'tier': tier.value,
      'status': status.value,
      'effective_at': effectiveAt.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'source_provider': sourceProvider.value,
      'source_subscription_id': sourceSubscriptionId,
      'capabilities': capabilities,
      'management_channel': managementChannel,
      'revision': revision,
    };
  }

  factory EntitlementSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String fallbackUserId,
  }) {
    final userId = (json['user_id'] ?? fallbackUserId).toString();
    final tier = PlanTierX.fromValue((json['tier'] ?? '').toString());
    final status =
        SubscriptionStatusX.fromValue((json['status'] ?? '').toString());
    final parsedCapabilities =
        _parseCapabilities(json['capabilities'], fallbackTier: tier);

    return EntitlementSnapshot(
      userId: userId,
      tier: tier,
      status: status,
      effectiveAt: _parseDate(
            json['effective_at'],
          ) ??
          DateTime.now().toUtc(),
      expiresAt: _parseDate(json['expires_at']),
      sourceProvider: BillingProviderX.fromValue(
          (json['source_provider'] ?? '').toString()),
      sourceSubscriptionId: (json['source_subscription_id'] ?? '').toString(),
      capabilities: parsedCapabilities,
      managementChannel:
          (json['management_channel'] ?? '').toString().trim().isEmpty
              ? 'in_app'
              : (json['management_channel'] ?? '').toString(),
      revision: _asInt(json['revision']),
    );
  }

  factory EntitlementSnapshot.free({
    required String userId,
    int revision = 0,
  }) {
    return EntitlementSnapshot(
      userId: userId,
      tier: PlanTier.free,
      status: SubscriptionStatus.active,
      effectiveAt: DateTime.now().toUtc(),
      expiresAt: null,
      sourceProvider: BillingProvider.adminGrant,
      sourceSubscriptionId: 'free-default',
      capabilities: defaultCapabilitiesForTier(PlanTier.free),
      managementChannel: 'free',
      revision: revision,
    );
  }

  static Map<String, bool> _parseCapabilities(
    Object? raw, {
    required PlanTier fallbackTier,
  }) {
    final defaults = defaultCapabilitiesForTier(fallbackTier);
    if (raw is Map<String, dynamic>) {
      final out = <String, bool>{...defaults};
      raw.forEach((key, value) {
        out[key] = _asBool(value);
      });
      return out;
    }
    if (raw is Map) {
      final out = <String, bool>{...defaults};
      raw.forEach((key, value) {
        out[key.toString()] = _asBool(value);
      });
      return out;
    }
    return defaults;
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  final raw = value?.toString().trim().toLowerCase() ?? '';
  return raw == 'true' || raw == '1' || raw == 'yes';
}
