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

enum BillingProvider { apple, google, kakao, paddle, toss, adminGrant, unknown }

extension BillingProviderX on BillingProvider {
  String get value {
    switch (this) {
      case BillingProvider.apple:
        return 'apple';
      case BillingProvider.google:
        return 'google';
      case BillingProvider.kakao:
        return 'kakao';
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
      case 'kakao':
        return BillingProvider.kakao;
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
  static const String cloudProjects = 'cloud_projects';
  static const String teamWorkspaces = 'team_workspaces';
  static const String prioritySupport = 'priority_support';
  static const String educationVisibilityControls =
      'education_visibility_controls';
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
    SubscriptionCapability.cloudProjects: false,
    SubscriptionCapability.teamWorkspaces: false,
    SubscriptionCapability.prioritySupport: false,
    SubscriptionCapability.educationVisibilityControls: false,
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
        SubscriptionCapability.cloudProjects: true,
        SubscriptionCapability.teamWorkspaces: true,
        SubscriptionCapability.prioritySupport: true,
      };
  }
}

Map<String, dynamic> defaultLimitsForPlanCode(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'starter':
      return <String, dynamic>{
        'members': 1,
        'workspaces': 0,
        'cloud_projects': 0,
        'storage_gb': 5,
      };
    case 'producer':
      return <String, dynamic>{
        'members': 1,
        'workspaces': 0,
        'cloud_projects': 0,
        'storage_gb': 20,
      };
    case 'studio':
      return <String, dynamic>{
        'members': 5,
        'workspaces': 3,
        'cloud_projects': 50,
        'storage_gb': 200,
      };
    case 'enterprise':
      return <String, dynamic>{
        'members': 500,
        'workspaces': 100,
        'cloud_projects': 5000,
        'storage_gb': 5000,
      };
    case 'education':
      return <String, dynamic>{
        'members': 200,
        'workspaces': 40,
        'cloud_projects': 1000,
        'storage_gb': 1000,
      };
    default:
      return <String, dynamic>{
        'members': 1,
        'workspaces': 0,
        'cloud_projects': 0,
        'storage_gb': 0,
      };
  }
}

String defaultPlanCodeForTier(PlanTier tier) {
  switch (tier) {
    case PlanTier.free:
      return 'free';
    case PlanTier.pro:
      return 'producer';
    case PlanTier.studio:
      return 'studio';
  }
}

String defaultPlanLabelForCode(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'starter':
      return 'Starter';
    case 'producer':
      return 'Producer';
    case 'studio':
      return 'Studio';
    case 'enterprise':
      return 'Enterprise';
    case 'education':
      return 'Education';
    default:
      return 'Free';
  }
}

String defaultPlanGroupForCode(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'studio':
      return 'team';
    case 'enterprise':
      return 'enterprise';
    case 'education':
      return 'education';
    default:
      return 'individual';
  }
}

class BillingSupportInfo {
  const BillingSupportInfo({
    required this.supportEmail,
    required this.supportUrl,
    required this.faqUrl,
    required this.manageSubscriptionUrl,
    required this.refundPolicyUrl,
    required this.contactLabel,
    required this.defaultCheckoutUrl,
  });

  final String supportEmail;
  final String supportUrl;
  final String faqUrl;
  final String manageSubscriptionUrl;
  final String refundPolicyUrl;
  final String contactLabel;
  final String defaultCheckoutUrl;

  static const String _defaultSupportEmail = 'support@mixroom.ai';
  static const String _defaultSupportUrl = 'https://www.mixroom.ai/support';
  static const String _defaultManageUrl = 'https://www.mixroom.ai/account';
  static const String _defaultTermsUrl = 'https://www.mixroom.ai/terms';

  factory BillingSupportInfo.defaults() {
    return const BillingSupportInfo(
      supportEmail: _defaultSupportEmail,
      supportUrl: _defaultSupportUrl,
      faqUrl: _defaultSupportUrl,
      manageSubscriptionUrl: _defaultManageUrl,
      refundPolicyUrl: _defaultTermsUrl,
      contactLabel: 'Contact support',
      defaultCheckoutUrl: _defaultManageUrl,
    );
  }

  factory BillingSupportInfo.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final defaults = BillingSupportInfo.defaults();
    return BillingSupportInfo(
      supportEmail: _asNonEmptyString(
        json['support_email'],
        fallback: defaults.supportEmail,
      ),
      supportUrl: _asNonEmptyString(
        json['support_url'],
        fallback: defaults.supportUrl,
      ),
      faqUrl: _asNonEmptyString(
        json['faq_url'],
        fallback: defaults.faqUrl,
      ),
      manageSubscriptionUrl: _asNonEmptyString(
        json['manage_subscription_url'],
        fallback: defaults.manageSubscriptionUrl,
      ),
      refundPolicyUrl: _asNonEmptyString(
        json['refund_policy_url'],
        fallback: defaults.refundPolicyUrl,
      ),
      contactLabel: _asNonEmptyString(
        json['contact_label'],
        fallback: defaults.contactLabel,
      ),
      defaultCheckoutUrl: _asNonEmptyString(
        json['default_checkout_url'],
        fallback: defaults.defaultCheckoutUrl,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'support_email': supportEmail,
      'support_url': supportUrl,
      'faq_url': faqUrl,
      'manage_subscription_url': manageSubscriptionUrl,
      'refund_policy_url': refundPolicyUrl,
      'contact_label': contactLabel,
      'default_checkout_url': defaultCheckoutUrl,
    };
  }

  bool get hasSupportRoute =>
      supportUrl.trim().isNotEmpty || supportEmail.trim().isNotEmpty;

  bool get hasManageRoute =>
      manageSubscriptionUrl.trim().isNotEmpty ||
      defaultCheckoutUrl.trim().isNotEmpty;
}

class CollaborationAccessSummary {
  const CollaborationAccessSummary({
    required this.organizationCount,
    required this.workspaceCount,
    required this.cloudProjectCount,
  });

  final int organizationCount;
  final int workspaceCount;
  final int cloudProjectCount;

  factory CollaborationAccessSummary.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CollaborationAccessSummary(
      organizationCount: _asInt(json['organization_count']),
      workspaceCount: _asInt(json['workspace_count']),
      cloudProjectCount: _asInt(json['cloud_project_count']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'organization_count': organizationCount,
      'workspace_count': workspaceCount,
      'cloud_project_count': cloudProjectCount,
    };
  }

  bool get hasAnyAccess =>
      organizationCount > 0 || workspaceCount > 0 || cloudProjectCount > 0;
}

class AccountAccessSource {
  const AccountAccessSource({
    required this.sourceType,
    required this.planCode,
    required this.planLabel,
    required this.planGroup,
    required this.status,
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  final String sourceType;
  final String planCode;
  final String planLabel;
  final String planGroup;
  final String status;
  final String organizationId;
  final String organizationName;
  final String role;

  factory AccountAccessSource.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final planCode = _asNonEmptyString(json['plan_code'], fallback: 'free');
    return AccountAccessSource(
      sourceType: _asNonEmptyString(json['source_type'], fallback: 'personal'),
      planCode: planCode,
      planLabel: _asNonEmptyString(
        json['plan_label'],
        fallback: defaultPlanLabelForCode(planCode),
      ),
      planGroup: _asNonEmptyString(
        json['plan_group'],
        fallback: defaultPlanGroupForCode(planCode),
      ),
      status: (json['status'] ?? '').toString(),
      organizationId: (json['organization_id'] ?? '').toString(),
      organizationName: (json['organization_name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'source_type': sourceType,
      'plan_code': planCode,
      'plan_label': planLabel,
      'plan_group': planGroup,
      'status': status,
      'organization_id': organizationId,
      'organization_name': organizationName,
      'role': role,
    };
  }
}

class OrganizationAccessItem {
  const OrganizationAccessItem({
    required this.organizationId,
    required this.name,
    required this.planCode,
    required this.planLabel,
    required this.planGroup,
    required this.role,
    required this.status,
    required this.membershipStatus,
    required this.seatLimit,
    required this.sharedWorkspaceEnabled,
    required this.supportNotes,
  });

  final String organizationId;
  final String name;
  final String planCode;
  final String planLabel;
  final String planGroup;
  final String role;
  final String status;
  final String membershipStatus;
  final int seatLimit;
  final bool sharedWorkspaceEnabled;
  final String supportNotes;

  factory OrganizationAccessItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final planCode = _asNonEmptyString(json['plan_code'], fallback: 'studio');
    return OrganizationAccessItem(
      organizationId: (json['organization_id'] ?? '').toString(),
      name: _asNonEmptyString(
        json['name'],
        fallback: (json['organization_id'] ?? '').toString(),
      ),
      planCode: planCode,
      planLabel: _asNonEmptyString(
        json['plan_label'],
        fallback: defaultPlanLabelForCode(planCode),
      ),
      planGroup: _asNonEmptyString(
        json['plan_group'],
        fallback: defaultPlanGroupForCode(planCode),
      ),
      role: (json['role'] ?? json['membership_role'] ?? '').toString(),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      membershipStatus:
          (json['membership_status'] ?? json['status'] ?? '').toString(),
      seatLimit: _asInt(json['seat_limit']),
      sharedWorkspaceEnabled: _asBool(
        json['shared_workspace_enabled'],
        defaultValue: true,
      ),
      supportNotes: (json['support_notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'organization_id': organizationId,
      'name': name,
      'plan_code': planCode,
      'plan_label': planLabel,
      'plan_group': planGroup,
      'role': role,
      'status': status,
      'membership_status': membershipStatus,
      'seat_limit': seatLimit,
      'shared_workspace_enabled': sharedWorkspaceEnabled,
      'support_notes': supportNotes,
    };
  }
}

class OrganizationMembershipItem {
  const OrganizationMembershipItem({
    required this.organizationId,
    required this.userId,
    required this.role,
    required this.status,
    required this.seatConsumed,
  });

  final String organizationId;
  final String userId;
  final String role;
  final String status;
  final bool seatConsumed;

  factory OrganizationMembershipItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return OrganizationMembershipItem(
      organizationId: (json['organization_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      seatConsumed: _asBool(json['seat_consumed']),
    );
  }
}

class WorkspaceAccessItem {
  const WorkspaceAccessItem({
    required this.workspaceId,
    required this.organizationId,
    required this.ownerUserId,
    required this.name,
    required this.status,
    required this.visibility,
    required this.defaultProjectPrivacy,
  });

  final String workspaceId;
  final String organizationId;
  final String ownerUserId;
  final String name;
  final String status;
  final String visibility;
  final String defaultProjectPrivacy;

  factory WorkspaceAccessItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return WorkspaceAccessItem(
      workspaceId: (json['workspace_id'] ?? '').toString(),
      organizationId: (json['organization_id'] ?? '').toString(),
      ownerUserId: (json['user_id'] ?? '').toString(),
      name: _asNonEmptyString(
        json['name'],
        fallback: (json['workspace_id'] ?? '').toString(),
      ),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      visibility: (json['visibility'] ?? '').toString(),
      defaultProjectPrivacy:
          (json['default_project_privacy'] ?? '').toString(),
    );
  }
}

class CloudProjectAccessItem {
  const CloudProjectAccessItem({
    required this.projectId,
    required this.workspaceId,
    required this.organizationId,
    required this.ownerUserId,
    required this.name,
    required this.status,
    required this.storageMode,
    required this.documentRevision,
  });

  final String projectId;
  final String workspaceId;
  final String organizationId;
  final String ownerUserId;
  final String name;
  final String status;
  final String storageMode;
  final int documentRevision;

  factory CloudProjectAccessItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CloudProjectAccessItem(
      projectId: (json['project_id'] ?? '').toString(),
      workspaceId: (json['workspace_id'] ?? '').toString(),
      organizationId: (json['organization_id'] ?? '').toString(),
      ownerUserId: (json['user_id'] ?? '').toString(),
      name: _asNonEmptyString(
        json['name'],
        fallback: (json['project_id'] ?? '').toString(),
      ),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      storageMode: (json['storage_mode'] ?? '').toString(),
      documentRevision: _asInt(json['document_revision']),
    );
  }
}

class OrganizationAccessSnapshot {
  const OrganizationAccessSnapshot({
    required this.organizations,
    required this.memberships,
    required this.summary,
    required this.configurable,
  });

  final List<OrganizationAccessItem> organizations;
  final List<OrganizationMembershipItem> memberships;
  final CollaborationAccessSummary summary;
  final bool configurable;

  factory OrganizationAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return OrganizationAccessSnapshot(
      organizations: _asListOfStringDynamicMaps(json['organizations'])
          .map(OrganizationAccessItem.fromJson)
          .toList(growable: false),
      memberships: _asListOfStringDynamicMaps(json['memberships'])
          .map(OrganizationMembershipItem.fromJson)
          .toList(growable: false),
      summary: CollaborationAccessSummary.fromJson(json['summary']),
      configurable: _asBool(json['configurable']),
    );
  }
}

class WorkspaceAccessSnapshot {
  const WorkspaceAccessSnapshot({
    required this.workspaces,
    required this.summary,
    required this.configurable,
  });

  final List<WorkspaceAccessItem> workspaces;
  final CollaborationAccessSummary summary;
  final bool configurable;

  factory WorkspaceAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkspaceAccessSnapshot(
      workspaces: _asListOfStringDynamicMaps(json['workspaces'])
          .map(WorkspaceAccessItem.fromJson)
          .toList(growable: false),
      summary: CollaborationAccessSummary.fromJson(json['summary']),
      configurable: _asBool(json['configurable']),
    );
  }
}

class CloudProjectAccessSnapshot {
  const CloudProjectAccessSnapshot({
    required this.cloudProjects,
    required this.summary,
    required this.configurable,
  });

  final List<CloudProjectAccessItem> cloudProjects;
  final CollaborationAccessSummary summary;
  final bool configurable;

  factory CloudProjectAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return CloudProjectAccessSnapshot(
      cloudProjects: _asListOfStringDynamicMaps(json['cloud_projects'])
          .map(CloudProjectAccessItem.fromJson)
          .toList(growable: false),
      summary: CollaborationAccessSummary.fromJson(json['summary']),
      configurable: _asBool(json['configurable']),
    );
  }
}

class BillingPlanDefinition {
  const BillingPlanDefinition({
    required this.code,
    required this.label,
    required this.group,
    required this.rank,
    required this.active,
    required this.legacyTier,
    required this.description,
    required this.capabilities,
    required this.limits,
  });

  final String code;
  final String label;
  final String group;
  final int rank;
  final bool active;
  final String legacyTier;
  final String description;
  final Map<String, bool> capabilities;
  final Map<String, dynamic> limits;

  factory BillingPlanDefinition.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final code = _asNonEmptyString(json['code'], fallback: 'free');
    return BillingPlanDefinition(
      code: code,
      label: _asNonEmptyString(
        json['label'],
        fallback: defaultPlanLabelForCode(code),
      ),
      group: _asNonEmptyString(
        json['group'],
        fallback: defaultPlanGroupForCode(code),
      ),
      rank: _asInt(json['rank']),
      active: _asBool(json['active'], defaultValue: true),
      legacyTier: _asNonEmptyString(
        json['legacy_tier'],
        fallback: _legacyTierToPlanTier(code).value,
      ),
      description: (json['description'] ?? '').toString(),
      capabilities: EntitlementSnapshot._parseCapabilities(
        json['capabilities'],
        fallbackTier: _legacyTierToPlanTier(
          (json['legacy_tier'] ?? code).toString(),
        ),
      ),
      limits: _parseDynamicMap(
        json['limits'],
        fallback: defaultLimitsForPlanCode(code),
      ),
    );
  }
}

class BillingProductDefinition {
  const BillingProductDefinition({
    required this.code,
    required this.planCode,
    required this.type,
    required this.billingInterval,
    required this.label,
    required this.description,
    required this.enabled,
    required this.managementChannel,
    required this.platforms,
    required this.priceDisplay,
    required this.rank,
  });

  final String code;
  final String planCode;
  final String type;
  final String billingInterval;
  final String label;
  final String description;
  final bool enabled;
  final String managementChannel;
  final List<String> platforms;
  final String priceDisplay;
  final int rank;

  factory BillingProductDefinition.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final code = _asNonEmptyString(json['code'], fallback: 'product');
    return BillingProductDefinition(
      code: code,
      planCode: _asNonEmptyString(json['plan_code'], fallback: 'free'),
      type: _asNonEmptyString(json['type'], fallback: 'subscription'),
      billingInterval:
          _asNonEmptyString(json['billing_interval'], fallback: 'monthly'),
      label: _asNonEmptyString(json['label'], fallback: _titleizeCode(code)),
      description: (json['description'] ?? '').toString(),
      enabled: _asBool(json['enabled'], defaultValue: true),
      managementChannel:
          _asNonEmptyString(json['management_channel'], fallback: 'web'),
      platforms: _asStringList(json['platforms']),
      priceDisplay: (json['price_display'] ?? '').toString(),
      rank: _asInt(json['rank']),
    );
  }

  bool supportsPlatform(String platform) {
    if (platforms.isEmpty) return true;
    return platforms.contains(platform.trim().toLowerCase());
  }
}

class BillingOfferDefinition {
  const BillingOfferDefinition({
    required this.code,
    required this.provider,
    required this.productCode,
    required this.providerProductId,
    required this.basePlanId,
    required this.offerId,
    required this.regions,
    required this.enabled,
  });

  final String code;
  final BillingProvider provider;
  final String productCode;
  final String providerProductId;
  final String basePlanId;
  final String offerId;
  final List<String> regions;
  final bool enabled;

  factory BillingOfferDefinition.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return BillingOfferDefinition(
      code: _asNonEmptyString(json['code'], fallback: 'offer'),
      provider: BillingProviderX.fromValue((json['provider'] ?? '').toString()),
      productCode: (json['product_code'] ?? '').toString(),
      providerProductId: (json['provider_product_id'] ?? '').toString(),
      basePlanId: (json['base_plan_id'] ?? '').toString(),
      offerId: (json['offer_id'] ?? '').toString(),
      regions: _asStringList(json['regions'])
          .map((value) => value.toUpperCase())
          .toList(growable: false),
      enabled: _asBool(json['enabled'], defaultValue: true),
    );
  }

  bool supportsRegion(String? regionCode) {
    final normalized = (regionCode ?? '').trim().toUpperCase();
    if (regions.isEmpty || normalized.isEmpty) return true;
    return regions.contains(normalized);
  }
}

class BillingCatalogSnapshot {
  const BillingCatalogSnapshot({
    required this.requestedByUserId,
    required this.plans,
    required this.products,
    required this.offers,
    required this.support,
  });

  final String requestedByUserId;
  final List<BillingPlanDefinition> plans;
  final List<BillingProductDefinition> products;
  final List<BillingOfferDefinition> offers;
  final BillingSupportInfo support;

  factory BillingCatalogSnapshot.fromJson(Map<String, dynamic> json) {
    return BillingCatalogSnapshot(
      requestedByUserId: (json['requested_by_user_id'] ?? '').toString(),
      plans: _asListOfStringDynamicMaps(json['plans'])
          .map(BillingPlanDefinition.fromJson)
          .toList(growable: false),
      products: _asListOfStringDynamicMaps(json['products'])
          .map(BillingProductDefinition.fromJson)
          .toList(growable: false),
      offers: _asListOfStringDynamicMaps(json['offers'])
          .map(BillingOfferDefinition.fromJson)
          .toList(growable: false),
      support: BillingSupportInfo.fromJson(json['support']),
    );
  }

  BillingPlanDefinition? planByCode(String planCode) {
    final normalized = planCode.trim().toLowerCase();
    for (final plan in plans) {
      if (plan.code == normalized) return plan;
    }
    return null;
  }

  List<BillingProductDefinition> enabledProductsForPlatform(String platform) {
    return products
        .where((product) => product.enabled && product.supportsPlatform(platform))
        .toList(growable: false);
  }

  BillingOfferDefinition? bestOfferForProduct({
    required String productCode,
    required BillingProvider provider,
    String? regionCode,
  }) {
    for (final offer in offers) {
      if (!offer.enabled) continue;
      if (offer.productCode != productCode) continue;
      if (offer.provider != provider) continue;
      if (!offer.supportsRegion(regionCode)) continue;
      return offer;
    }
    return null;
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
    required this.planCode,
    required this.planLabel,
    required this.planGroup,
    required this.limits,
    required this.accessSources,
    required this.workspaceAccessSummary,
    required this.organizations,
    required this.billingSupport,
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
  final String planCode;
  final String planLabel;
  final String planGroup;
  final Map<String, dynamic> limits;
  final List<AccountAccessSource> accessSources;
  final CollaborationAccessSummary workspaceAccessSummary;
  final List<OrganizationAccessItem> organizations;
  final BillingSupportInfo billingSupport;

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

  String get effectivePlanLabel {
    if (planLabel.trim().isNotEmpty) return planLabel;
    return defaultPlanLabelForCode(planCode);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
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
      'plan_code': planCode,
      'plan_label': planLabel,
      'plan_group': planGroup,
      'limits': limits,
      'access_sources': accessSources.map((item) => item.toJson()).toList(),
      'workspace_access_summary': workspaceAccessSummary.toJson(),
      'organizations': organizations.map((item) => item.toJson()).toList(),
      'billing_support': billingSupport.toJson(),
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
    final planCode = _asNonEmptyString(
      json['plan_code'],
      fallback: defaultPlanCodeForTier(tier),
    );

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
        (json['source_provider'] ?? '').toString(),
      ),
      sourceSubscriptionId: (json['source_subscription_id'] ?? '').toString(),
      capabilities: _parseCapabilities(
        json['capabilities'],
        fallbackTier: tier,
      ),
      managementChannel:
          (json['management_channel'] ?? '').toString().trim().isEmpty
              ? 'in_app'
              : (json['management_channel'] ?? '').toString(),
      revision: _asInt(json['revision']),
      planCode: planCode,
      planLabel: _asNonEmptyString(
        json['plan_label'],
        fallback: defaultPlanLabelForCode(planCode),
      ),
      planGroup: _asNonEmptyString(
        json['plan_group'],
        fallback: defaultPlanGroupForCode(planCode),
      ),
      limits: _parseDynamicMap(
        json['limits'],
        fallback: defaultLimitsForPlanCode(planCode),
      ),
      accessSources: _asListOfStringDynamicMaps(json['access_sources'])
          .map(AccountAccessSource.fromJson)
          .toList(growable: false),
      workspaceAccessSummary:
          CollaborationAccessSummary.fromJson(json['workspace_access_summary']),
      organizations: _asListOfStringDynamicMaps(json['organizations'])
          .map(OrganizationAccessItem.fromJson)
          .toList(growable: false),
      billingSupport: BillingSupportInfo.fromJson(json['billing_support']),
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
      planCode: 'free',
      planLabel: 'Free',
      planGroup: 'individual',
      limits: defaultLimitsForPlanCode('free'),
      accessSources: const <AccountAccessSource>[],
      workspaceAccessSummary: const CollaborationAccessSummary(
        organizationCount: 0,
        workspaceCount: 0,
        cloudProjectCount: 0,
      ),
      organizations: const <OrganizationAccessItem>[],
      billingSupport: BillingSupportInfo.defaults(),
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

Map<String, dynamic> _parseDynamicMap(
  Object? raw, {
  Map<String, dynamic> fallback = const <String, dynamic>{},
}) {
  final out = <String, dynamic>{...fallback};
  if (raw is Map<String, dynamic>) {
    out.addAll(raw);
    return out;
  }
  if (raw is Map) {
    raw.forEach((key, value) {
      out[key.toString()] = value;
    });
  }
  return out;
}

Map<String, dynamic> _asStringDynamicMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfStringDynamicMaps(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

List<String> _asStringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(
  Object? value, {
  bool defaultValue = false,
}) {
  if (value is bool) return value;
  if (value == null) return defaultValue;
  final raw = value.toString().trim().toLowerCase();
  if (raw == 'true' || raw == '1' || raw == 'yes' || raw == 'on') {
    return true;
  }
  if (raw == 'false' || raw == '0' || raw == 'no' || raw == 'off') {
    return false;
  }
  return defaultValue;
}

String _asNonEmptyString(
  Object? value, {
  required String fallback,
}) {
  final raw = value?.toString().trim() ?? '';
  return raw.isEmpty ? fallback : raw;
}

PlanTier _legacyTierToPlanTier(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'starter':
    case 'producer':
    case 'pro':
      return PlanTier.pro;
    case 'studio':
    case 'enterprise':
    case 'education':
      return PlanTier.studio;
    default:
      return PlanTier.free;
  }
}

String _titleizeCode(String value) {
  final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
  if (normalized.isEmpty) return value;
  return normalized
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');
}
