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

  static const String allPlugins = 'all_plugins';
  static const String highQualityExport = 'high_quality_export';
  static const String wavStarterSamples = 'wav_starter_samples';
  static const String selectableAiModels = 'selectable_ai_models';
  static const String advancedAiModels = 'advanced_ai_models';
  static const String producerProfilePresets = 'producer_profile_presets';
  static const String premiumSoundLibraries = 'premium_sound_libraries';
  static const String cloudFileBrowser = 'cloud_file_browser';
  static const String customSamplePacks = 'custom_sample_packs';
  static const String profilePlanBadge = 'profile_plan_badge';
  static const String dedicatedSupport = 'dedicated_support';
  static const String customAiModels = 'custom_ai_models';
  static const String complianceControls = 'compliance_controls';
  static const String educationSandbox = 'education_sandbox';
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

Map<String, bool> defaultCapabilitiesForPlanCode(String planCode) {
  final normalizedPlanCode = normalizePlanCode(planCode);
  final freeCapabilities = <String, bool>{
    SubscriptionCapability.allPlugins: false,
    SubscriptionCapability.highQualityExport: false,
    SubscriptionCapability.wavStarterSamples: false,
    SubscriptionCapability.selectableAiModels: false,
    SubscriptionCapability.advancedAiModels: false,
    SubscriptionCapability.producerProfilePresets: false,
    SubscriptionCapability.premiumSoundLibraries: false,
    SubscriptionCapability.cloudFileBrowser: false,
    SubscriptionCapability.customSamplePacks: false,
    SubscriptionCapability.profilePlanBadge: false,
    SubscriptionCapability.dedicatedSupport: false,
    SubscriptionCapability.customAiModels: false,
    SubscriptionCapability.complianceControls: false,
    SubscriptionCapability.educationSandbox: false,
    SubscriptionCapability.videoProjects: true,
    SubscriptionCapability.webCheckout: true,
    SubscriptionCapability.mobileIap: true,
    SubscriptionCapability.studioFeatures: false,
    SubscriptionCapability.cloudProjects: true,
    SubscriptionCapability.teamWorkspaces: false,
    SubscriptionCapability.prioritySupport: false,
    SubscriptionCapability.educationVisibilityControls: false,
  };

  switch (normalizedPlanCode) {
    case 'starter':
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.allPlugins: true,
        SubscriptionCapability.highQualityExport: true,
        SubscriptionCapability.wavStarterSamples: true,
        SubscriptionCapability.producerProfilePresets: true,
        SubscriptionCapability.cloudProjects: true,
      };
    case 'producer':
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.allPlugins: true,
        SubscriptionCapability.highQualityExport: true,
        SubscriptionCapability.wavStarterSamples: true,
        SubscriptionCapability.selectableAiModels: true,
        SubscriptionCapability.advancedAiModels: true,
        SubscriptionCapability.producerProfilePresets: true,
        SubscriptionCapability.profilePlanBadge: true,
        SubscriptionCapability.cloudProjects: true,
      };
    case 'studio':
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.allPlugins: true,
        SubscriptionCapability.highQualityExport: true,
        SubscriptionCapability.wavStarterSamples: true,
        SubscriptionCapability.selectableAiModels: true,
        SubscriptionCapability.advancedAiModels: true,
        SubscriptionCapability.producerProfilePresets: true,
        SubscriptionCapability.profilePlanBadge: true,
        SubscriptionCapability.studioFeatures: true,
        SubscriptionCapability.cloudProjects: true,
        SubscriptionCapability.teamWorkspaces: true,
        SubscriptionCapability.prioritySupport: true,
      };
    case 'enterprise':
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.allPlugins: true,
        SubscriptionCapability.highQualityExport: true,
        SubscriptionCapability.wavStarterSamples: true,
        SubscriptionCapability.selectableAiModels: true,
        SubscriptionCapability.advancedAiModels: true,
        SubscriptionCapability.producerProfilePresets: true,
        SubscriptionCapability.profilePlanBadge: true,
        SubscriptionCapability.studioFeatures: true,
        SubscriptionCapability.cloudProjects: true,
        SubscriptionCapability.teamWorkspaces: true,
        SubscriptionCapability.prioritySupport: true,
        SubscriptionCapability.dedicatedSupport: true,
        SubscriptionCapability.customAiModels: true,
        SubscriptionCapability.complianceControls: true,
      };
    case 'education':
      return <String, bool>{
        ...freeCapabilities,
        SubscriptionCapability.allPlugins: true,
        SubscriptionCapability.highQualityExport: true,
        SubscriptionCapability.wavStarterSamples: true,
        SubscriptionCapability.producerProfilePresets: true,
        SubscriptionCapability.cloudProjects: true,
        SubscriptionCapability.teamWorkspaces: false,
        SubscriptionCapability.educationSandbox: true,
        SubscriptionCapability.complianceControls: true,
        SubscriptionCapability.educationVisibilityControls: true,
      };
    default:
      return freeCapabilities;
  }
}

Map<String, dynamic> defaultLimitsForPlanCode(String planCode) {
  switch (normalizePlanCode(planCode)) {
    case 'starter':
      return <String, dynamic>{
        'members': 1,
        'cloud_projects': 'custom',
        'storage_gb': 5,
        'platform_upload_hours': 100,
        'ai_prompts_daily': 400,
        'ai_prompts_weekly': 1500,
        'ai_model_tier': 'standard',
        'producer_profile_presets': 'expanded',
      };
    case 'producer':
      return <String, dynamic>{
        'members': 1,
        'cloud_projects': 'custom',
        'storage_gb': 250,
        'platform_upload_hours': 10000,
        'ai_prompts_daily': 1000,
        'ai_prompts_weekly': 4000,
        'ai_basic_prompts_daily': 1000,
        'ai_better_prompts_daily': 250,
        'ai_premium_prompts_daily': 50,
        'ai_model_tier': 'advanced',
        'sample_pack_storage_gb': 250,
        'storage_addons_gb': <int>[250, 1024, 2048],
        'producer_profile_presets': 'expanded',
      };
    case 'studio':
      return <String, dynamic>{
        'members': 5,
        'cloud_projects': 'custom',
        'platform_upload_hours': 10000,
        'ai_prompts_daily': 1000,
        'ai_prompts_weekly': 4000,
        'ai_basic_prompts_daily': 1000,
        'ai_better_prompts_daily': 250,
        'ai_premium_prompts_daily': 50,
        'ai_model_tier': 'advanced',
        'sample_pack_storage_gb': 1000,
        'shared_storage_gb': 1024,
        'storage_addons_gb': <int>[1024],
        'additional_seat_price_usd_monthly': 15,
        'producer_profile_presets': 'expanded',
      };
    case 'enterprise':
      return <String, dynamic>{
        'members': 500,
        'cloud_projects': 'custom',
        'platform_upload_hours': 'custom',
        'ai_prompts_daily': 'custom',
        'ai_prompts_weekly': 'custom',
        'ai_model_tier': 'custom',
        'sample_pack_storage_gb': 'custom',
        'shared_storage_gb': 'custom',
        'producer_profile_presets': 'custom',
      };
    case 'education':
      return <String, dynamic>{
        'members': 20,
        'seat_options': <int>[10, 20, 30],
        'default_seats': 20,
        'cloud_projects': 'custom',
        'storage_gb': 5,
        'platform_upload_hours': 100,
        'ai_prompts_daily': 400,
        'ai_prompts_weekly': 1500,
        'ai_model_tier': 'standard',
        'producer_profile_presets': 'expanded',
      };
    default:
      return <String, dynamic>{
        'members': 1,
        'cloud_projects': 1,
        'storage_gb': 0.1,
        'platform_upload_hours': 1,
        'ai_prompts_daily': 200,
        'ai_prompts_weekly': 600,
        'ai_model_tier': 'standard',
        'producer_profile_presets': 'mixroom_producer',
      };
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
    required this.salesEmail,
    required this.supportUrl,
    required this.faqUrl,
    required this.manageSubscriptionUrl,
    required this.refundPolicyUrl,
    required this.contactLabel,
    required this.defaultCheckoutUrl,
  });

  final String supportEmail;
  final String salesEmail;
  final String supportUrl;
  final String faqUrl;
  final String manageSubscriptionUrl;
  final String refundPolicyUrl;
  final String contactLabel;
  final String defaultCheckoutUrl;

  static const String _defaultSupportEmail = 'support@mixroom.ai';
  static const String _defaultSalesEmail = 'sales@mixroom.ai';
  static const String _defaultSupportUrl = 'https://www.mixroom.ai/support';
  static const String _defaultManageUrl = 'https://www.mixroom.ai/account';
  static const String _defaultTermsUrl = 'https://www.mixroom.ai/terms';

  factory BillingSupportInfo.defaults() {
    return const BillingSupportInfo(
      supportEmail: _defaultSupportEmail,
      salesEmail: _defaultSalesEmail,
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
      salesEmail: _asNonEmptyString(
        json['sales_email'],
        fallback: defaults.salesEmail,
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
      'sales_email': salesEmail,
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
    required this.sourceProvider,
    required this.sourceSubscriptionId,
    required this.managementChannel,
    required this.productCode,
    required this.nextBilledAt,
    required this.seatCount,
    required this.extraStorageTb,
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  final String sourceType;
  final String planCode;
  final String planLabel;
  final String planGroup;
  final String status;
  final BillingProvider sourceProvider;
  final String sourceSubscriptionId;
  final String managementChannel;
  final String productCode;
  final DateTime? nextBilledAt;
  final int? seatCount;
  final int extraStorageTb;
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
      sourceProvider: BillingProviderX.fromValue(
        (json['source_provider'] ?? '').toString(),
      ),
      sourceSubscriptionId: (json['source_subscription_id'] ?? '').toString(),
      managementChannel: (json['management_channel'] ?? '').toString(),
      productCode: (json['product_code'] ?? '').toString(),
      nextBilledAt: _parseDate(json['next_billed_at']),
      seatCount: _asNullableInt(json['seat_count']),
      extraStorageTb: _asInt(json['extra_storage_tb']),
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
      'source_provider': sourceProvider.value,
      'source_subscription_id': sourceSubscriptionId,
      'management_channel': managementChannel,
      'product_code': productCode,
      'next_billed_at': nextBilledAt?.toUtc().toIso8601String(),
      'seat_count': seatCount,
      'extra_storage_tb': extraStorageTb,
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
    required this.seatsUsed,
    required this.seatsActive,
    required this.seatsInvited,
    required this.seatsAvailable,
    required this.sharedWorkspaceEnabled,
    required this.supportNotes,
    required this.canWrite,
    required this.accessStatus,
    required this.lockedAt,
    required this.retentionExpiresAt,
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
  final int seatsUsed;
  final int seatsActive;
  final int seatsInvited;
  final int seatsAvailable;
  final bool sharedWorkspaceEnabled;
  final String supportNotes;
  final bool canWrite;
  final String accessStatus;
  final DateTime? lockedAt;
  final DateTime? retentionExpiresAt;

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
      seatsUsed: _asInt(json['seats_used']),
      seatsActive: _asInt(json['seats_active']),
      seatsInvited: _asInt(json['seats_invited']),
      seatsAvailable: _asInt(json['seats_available']),
      sharedWorkspaceEnabled: _asBool(
        json['shared_workspace_enabled'],
        defaultValue: true,
      ),
      supportNotes: (json['support_notes'] ?? '').toString(),
      canWrite: _asBool(json['can_write'], defaultValue: true),
      accessStatus:
          _asNonEmptyString(json['access_status'], fallback: 'active'),
      lockedAt: _parseDate(json['locked_at']),
      retentionExpiresAt: _parseDate(json['retention_expires_at']),
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
      'seats_used': seatsUsed,
      'seats_active': seatsActive,
      'seats_invited': seatsInvited,
      'seats_available': seatsAvailable,
      'shared_workspace_enabled': sharedWorkspaceEnabled,
      'support_notes': supportNotes,
      'can_write': canWrite,
      'access_status': accessStatus,
      'locked_at': lockedAt?.toUtc().toIso8601String(),
      'retention_expires_at': retentionExpiresAt?.toUtc().toIso8601String(),
    };
  }
}

class OrganizationMembershipItem {
  const OrganizationMembershipItem({
    required this.organizationId,
    required this.userId,
    required this.email,
    required this.role,
    required this.status,
    required this.seatConsumed,
    required this.inviteUrl,
    required this.inviteToken,
    required this.invitedAt,
    required this.activatedAt,
    required this.releasedAt,
    required this.updatedAt,
  });

  final String organizationId;
  final String userId;
  final String email;
  final String role;
  final String status;
  final bool seatConsumed;
  final String inviteUrl;
  final String inviteToken;
  final DateTime? invitedAt;
  final DateTime? activatedAt;
  final DateTime? releasedAt;
  final DateTime? updatedAt;

  factory OrganizationMembershipItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return OrganizationMembershipItem(
      organizationId: (json['organization_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      seatConsumed: _asBool(json['seat_consumed']),
      inviteUrl: (json['invite_url'] ?? '').toString(),
      inviteToken: (json['invite_token'] ?? '').toString(),
      invitedAt: _parseDate(json['invited_at']),
      activatedAt: _parseDate(json['activated_at']),
      releasedAt: _parseDate(json['released_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }
}

class EducationStudentUsageItem {
  const EducationStudentUsageItem({
    required this.organizationId,
    required this.userId,
    required this.email,
    required this.status,
    required this.seatConsumed,
    required this.projectCount,
    required this.lastProjectUpdatedAt,
    required this.lastActiveAt,
    required this.invitedAt,
    required this.activatedAt,
    required this.releasedAt,
  });

  final String organizationId;
  final String userId;
  final String email;
  final String status;
  final bool seatConsumed;
  final int projectCount;
  final DateTime? lastProjectUpdatedAt;
  final DateTime? lastActiveAt;
  final DateTime? invitedAt;
  final DateTime? activatedAt;
  final DateTime? releasedAt;

  factory EducationStudentUsageItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return EducationStudentUsageItem(
      organizationId: (json['organization_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      seatConsumed: _asBool(json['seat_consumed']),
      projectCount: _asInt(json['project_count']),
      lastProjectUpdatedAt: _parseDate(json['last_project_updated_at']),
      lastActiveAt: _parseDate(json['last_active_at']),
      invitedAt: _parseDate(json['invited_at']),
      activatedAt: _parseDate(json['activated_at']),
      releasedAt: _parseDate(json['released_at']),
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
    required this.canWrite,
    required this.accessStatus,
  });

  final String workspaceId;
  final String organizationId;
  final String ownerUserId;
  final String name;
  final String status;
  final String visibility;
  final String defaultProjectPrivacy;
  final bool canWrite;
  final String accessStatus;

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
      defaultProjectPrivacy: (json['default_project_privacy'] ?? '').toString(),
      canWrite: _asBool(json['can_write'], defaultValue: true),
      accessStatus:
          _asNonEmptyString(json['access_status'], fallback: 'active'),
    );
  }
}

class CloudProjectUserSummary {
  const CloudProjectUserSummary({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String userId;
  final String username;
  final String displayName;

  bool get hasLabel =>
      username.trim().isNotEmpty || displayName.trim().isNotEmpty;

  String get label {
    final safeUsername = username.trim();
    if (safeUsername.isNotEmpty) return '@$safeUsername';
    final safeDisplayName = displayName.trim();
    if (safeDisplayName.isNotEmpty) return safeDisplayName;
    return 'Unknown member';
  }

  factory CloudProjectUserSummary.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CloudProjectUserSummary(
      userId: (json['user_id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
    );
  }
}

class CloudProjectAccessItem {
  const CloudProjectAccessItem({
    required this.projectId,
    required this.workspaceId,
    required this.organizationId,
    required this.ownerUserId,
    required this.updatedByUserId,
    required this.name,
    required this.status,
    required this.visibility,
    required this.storageMode,
    required this.storageProvider,
    required this.documentRevision,
    required this.documentSizeBytes,
    required this.localProjectId,
    required this.canWrite,
    required this.ownerProfile,
    required this.updatedByProfile,
    this.createdAt,
    this.updatedAt,
  });

  final String projectId;
  final String workspaceId;
  final String organizationId;
  final String ownerUserId;
  final String updatedByUserId;
  final String name;
  final String status;
  final String visibility;
  final String storageMode;
  final String storageProvider;
  final int documentRevision;
  final int documentSizeBytes;
  final String localProjectId;
  final bool canWrite;
  final CloudProjectUserSummary ownerProfile;
  final CloudProjectUserSummary updatedByProfile;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CloudProjectAccessItem.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CloudProjectAccessItem(
      projectId: (json['project_id'] ?? '').toString(),
      workspaceId: (json['workspace_id'] ?? '').toString(),
      organizationId: (json['organization_id'] ?? '').toString(),
      ownerUserId: (json['user_id'] ?? '').toString(),
      updatedByUserId: (json['updated_by_user_id'] ?? '').toString(),
      name: _asNonEmptyString(
        json['name'],
        fallback: (json['project_id'] ?? '').toString(),
      ),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      visibility: (json['visibility'] ?? '').toString(),
      storageMode: (json['storage_mode'] ?? '').toString(),
      storageProvider: (json['storage_provider'] ?? '').toString(),
      documentRevision: _asInt(json['document_revision']),
      documentSizeBytes: _asInt(json['document_size_bytes']),
      localProjectId:
          (json['local_project_id'] ?? json['client_project_id'] ?? '')
              .toString(),
      canWrite: _asBool(json['can_write'], defaultValue: true),
      ownerProfile: CloudProjectUserSummary.fromJson(json['owner_profile']),
      updatedByProfile:
          CloudProjectUserSummary.fromJson(json['updated_by_profile']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  bool get isBundleStorage {
    final mode = storageMode.trim().toLowerCase();
    return mode == 'blob_mixroom' || mode == 's3_mixroom';
  }
}

class CloudProjectStorageSummary {
  const CloudProjectStorageSummary({
    required this.usedBytes,
    required this.limitBytes,
    required this.projectCount,
    required this.projectLimit,
    required this.locations,
  });

  final int usedBytes;
  final int? limitBytes;
  final int projectCount;
  final int? projectLimit;
  final List<CloudProjectStorageLocation> locations;

  double get usedFraction {
    final limit = limitBytes;
    if (limit == null || limit <= 0) return 0;
    return (usedBytes / limit).clamp(0.0, 1.0).toDouble();
  }

  factory CloudProjectStorageSummary.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CloudProjectStorageSummary(
      usedBytes: _asInt(json['used_bytes']),
      limitBytes: _asNullableInt(json['limit_bytes']),
      projectCount: _asInt(json['project_count']),
      projectLimit: _asNullableInt(json['project_limit']),
      locations: _asListOfStringDynamicMaps(json['locations'])
          .map(CloudProjectStorageLocation.fromJson)
          .toList(growable: false),
    );
  }
}

class CloudProjectStorageLocation {
  const CloudProjectStorageLocation({
    required this.storageScope,
    required this.workspaceId,
    required this.organizationId,
    required this.label,
    required this.usedBytes,
    required this.limitBytes,
    required this.projectCount,
    required this.projectLimit,
    required this.planCode,
    required this.status,
    required this.workspaceStatus,
    required this.organizationStatus,
    required this.canWrite,
  });

  final String storageScope;
  final String workspaceId;
  final String organizationId;
  final String label;
  final int usedBytes;
  final int? limitBytes;
  final int projectCount;
  final int? projectLimit;
  final String planCode;
  final String status;
  final String workspaceStatus;
  final String organizationStatus;
  final bool canWrite;

  factory CloudProjectStorageLocation.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return CloudProjectStorageLocation(
      storageScope: (json['storage_scope'] ?? '').toString(),
      workspaceId: (json['workspace_id'] ?? '').toString(),
      organizationId: (json['organization_id'] ?? '').toString(),
      label: _asNonEmptyString(json['label'], fallback: 'Cloud Storage'),
      usedBytes: _asInt(json['used_bytes']),
      limitBytes: _asNullableInt(json['limit_bytes']),
      projectCount: _asInt(json['project_count']),
      projectLimit: _asNullableInt(json['project_limit']),
      planCode: (json['plan_code'] ?? '').toString(),
      status: _asNonEmptyString(json['status'], fallback: 'active'),
      workspaceStatus: (json['workspace_status'] ?? '').toString(),
      organizationStatus: (json['organization_status'] ?? '').toString(),
      canWrite: _asBool(json['can_write'], defaultValue: true),
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

class EducationAdminSnapshot {
  const EducationAdminSnapshot({
    required this.organizations,
    required this.memberships,
    required this.studentUsage,
    required this.summary,
    required this.configurable,
  });

  final List<OrganizationAccessItem> organizations;
  final List<OrganizationMembershipItem> memberships;
  final List<EducationStudentUsageItem> studentUsage;
  final CollaborationAccessSummary summary;
  final bool configurable;

  factory EducationAdminSnapshot.fromJson(Map<String, dynamic> json) {
    return EducationAdminSnapshot(
      organizations: _asListOfStringDynamicMaps(json['organizations'])
          .map(OrganizationAccessItem.fromJson)
          .toList(growable: false),
      memberships: _asListOfStringDynamicMaps(json['memberships'])
          .map(OrganizationMembershipItem.fromJson)
          .toList(growable: false),
      studentUsage: _asListOfStringDynamicMaps(json['student_usage'])
          .map(EducationStudentUsageItem.fromJson)
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
    required this.storage,
  });

  final List<CloudProjectAccessItem> cloudProjects;
  final CollaborationAccessSummary summary;
  final bool configurable;
  final CloudProjectStorageSummary storage;

  factory CloudProjectAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return CloudProjectAccessSnapshot(
      cloudProjects: _asListOfStringDynamicMaps(json['cloud_projects'])
          .map(CloudProjectAccessItem.fromJson)
          .toList(growable: false),
      summary: CollaborationAccessSummary.fromJson(json['summary']),
      configurable: _asBool(json['configurable']),
      storage: CloudProjectStorageSummary.fromJson(json['storage']),
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
    required this.description,
    required this.capabilities,
    required this.limits,
  });

  final String code;
  final String label;
  final String group;
  final int rank;
  final bool active;
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
      description: (json['description'] ?? '').toString(),
      capabilities: EntitlementSnapshot._parseCapabilities(
        json['capabilities'],
        fallbackPlanCode: code,
      ),
      limits: _parseDynamicMap(
        json['limits'],
        fallback: defaultLimitsForPlanCode(code),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'label': label,
      'group': group,
      'rank': rank,
      'active': active,
      'description': description,
      'capabilities': capabilities,
      'limits': limits,
    };
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
    this.priceKrw = 0,
    required this.trialDays,
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
  final int priceKrw;
  final int trialDays;
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
      priceKrw: _asInt(json['price_krw']),
      trialDays: _asInt(json['trial_days']),
      rank: _asInt(json['rank']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'plan_code': planCode,
      'type': type,
      'billing_interval': billingInterval,
      'label': label,
      'description': description,
      'enabled': enabled,
      'management_channel': managementChannel,
      'platforms': platforms,
      'price_display': priceDisplay,
      'price_krw': priceKrw,
      'trial_days': trialDays,
      'rank': rank,
    };
  }

  bool supportsPlatform(String platform) {
    if (platforms.isEmpty) return true;
    return platforms.contains(platform.trim().toLowerCase());
  }
}

class BillingProviderProductDefinition {
  const BillingProviderProductDefinition({
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

  factory BillingProviderProductDefinition.fromJson(Object? raw) {
    final json = _asStringDynamicMap(raw);
    return BillingProviderProductDefinition(
      code: _asNonEmptyString(json['code'], fallback: 'provider_product'),
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'provider': provider.value,
      'product_code': productCode,
      'provider_product_id': providerProductId,
      'base_plan_id': basePlanId,
      'offer_id': offerId,
      'regions': regions,
      'enabled': enabled,
    };
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
    required this.providerProducts,
    required this.support,
  });

  final String requestedByUserId;
  final List<BillingPlanDefinition> plans;
  final List<BillingProductDefinition> products;
  final List<BillingProviderProductDefinition> providerProducts;
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
      providerProducts: _asListOfStringDynamicMaps(
        json['provider_products'] ?? json['offers'],
      ).map(BillingProviderProductDefinition.fromJson).toList(growable: false),
      support: BillingSupportInfo.fromJson(json['support']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'requested_by_user_id': requestedByUserId,
      'plans': plans.map((plan) => plan.toJson()).toList(growable: false),
      'products':
          products.map((product) => product.toJson()).toList(growable: false),
      'provider_products': providerProducts
          .map((providerProduct) => providerProduct.toJson())
          .toList(growable: false),
      'support': support.toJson(),
    };
  }

  factory BillingCatalogSnapshot.localDefaults({
    String requestedByUserId = '',
  }) {
    return BillingCatalogSnapshot(
      requestedByUserId: requestedByUserId,
      plans: const <BillingPlanDefinition>[
        BillingPlanDefinition(
          code: 'free',
          label: 'Free',
          group: 'individual',
          rank: 0,
          active: true,
          description:
              'Basic DAW functionality, limited AI, starter samples, and standard sharing.',
          capabilities: <String, bool>{
            SubscriptionCapability.cloudProjects: true,
          },
          limits: <String, dynamic>{
            'members': 1,
            'cloud_projects': 1,
            'storage_gb': 0.1,
            'platform_upload_hours': 1,
            'ai_prompts_daily': 200,
            'ai_prompts_weekly': 600,
            'ai_model_tier': 'standard',
            'producer_profile_presets': 'mixroom_producer',
          },
        ),
        BillingPlanDefinition(
          code: 'starter',
          label: 'Starter',
          group: 'individual',
          rank: 10,
          active: true,
          description:
              'Expanded DAW features, WAV starter samples, higher-quality export, and more storage.',
          capabilities: <String, bool>{
            SubscriptionCapability.allPlugins: true,
            SubscriptionCapability.highQualityExport: true,
            SubscriptionCapability.wavStarterSamples: true,
            SubscriptionCapability.producerProfilePresets: true,
            SubscriptionCapability.cloudProjects: true,
          },
          limits: <String, dynamic>{
            'members': 1,
            'cloud_projects': 'custom',
            'storage_gb': 5,
            'platform_upload_hours': 100,
            'ai_prompts_daily': 400,
            'ai_prompts_weekly': 1500,
            'ai_model_tier': 'standard',
            'producer_profile_presets': 'expanded',
          },
        ),
        BillingPlanDefinition(
          code: 'producer',
          label: 'Producer',
          group: 'individual',
          rank: 20,
          active: true,
          description:
              'Full solo creator suite with advanced AI, high-quality export, and expanded storage.',
          capabilities: <String, bool>{
            SubscriptionCapability.allPlugins: true,
            SubscriptionCapability.highQualityExport: true,
            SubscriptionCapability.wavStarterSamples: true,
            SubscriptionCapability.selectableAiModels: true,
            SubscriptionCapability.advancedAiModels: true,
            SubscriptionCapability.producerProfilePresets: true,
            SubscriptionCapability.profilePlanBadge: true,
          },
          limits: <String, dynamic>{
            'members': 1,
            'cloud_projects': 'custom',
            'storage_gb': 250,
            'platform_upload_hours': 10000,
            'ai_prompts_daily': 1000,
            'ai_prompts_weekly': 4000,
            'ai_basic_prompts_daily': 1000,
            'ai_better_prompts_daily': 250,
            'ai_premium_prompts_daily': 50,
            'ai_model_tier': 'advanced',
            'sample_pack_storage_gb': 250,
            'producer_profile_presets': 'expanded',
          },
        ),
      ],
      products: const <BillingProductDefinition>[
        BillingProductDefinition(
          code: 'starter_monthly',
          planCode: 'starter',
          type: 'subscription',
          billingInterval: 'monthly',
          label: 'Starter Monthly',
          description: 'Monthly Starter access.',
          enabled: true,
          managementChannel: 'web_or_mobile',
          platforms: <String>['ios', 'android', 'web'],
          priceDisplay: '\$5/mo',
          priceKrw: 6600,
          trialDays: 30,
          rank: 10,
        ),
        BillingProductDefinition(
          code: 'starter_yearly',
          planCode: 'starter',
          type: 'subscription',
          billingInterval: 'yearly',
          label: 'Starter Yearly',
          description: 'Annual Starter access.',
          enabled: true,
          managementChannel: 'web_or_mobile',
          platforms: <String>['ios', 'android', 'web'],
          priceDisplay: '\$54/yr',
          priceKrw: 77000,
          trialDays: 30,
          rank: 11,
        ),
        BillingProductDefinition(
          code: 'producer_monthly',
          planCode: 'producer',
          type: 'subscription',
          billingInterval: 'monthly',
          label: 'Producer Monthly',
          description: 'Monthly Producer access.',
          enabled: true,
          managementChannel: 'web_or_mobile',
          platforms: <String>['ios', 'android', 'web'],
          priceDisplay: '\$20/mo',
          priceKrw: 29000,
          trialDays: 0,
          rank: 20,
        ),
        BillingProductDefinition(
          code: 'producer_yearly',
          planCode: 'producer',
          type: 'subscription',
          billingInterval: 'yearly',
          label: 'Producer Yearly',
          description: 'Annual Producer access.',
          enabled: true,
          managementChannel: 'web_or_mobile',
          platforms: <String>['ios', 'android', 'web'],
          priceDisplay: '\$214.99/yr',
          priceKrw: 299000,
          trialDays: 0,
          rank: 21,
        ),
      ],
      providerProducts: const <BillingProviderProductDefinition>[
        BillingProviderProductDefinition(
          code: 'apple_starter_monthly',
          provider: BillingProvider.apple,
          productCode: 'starter_monthly',
          providerProductId: 'mixroom_starter_monthly',
          basePlanId: '',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'apple_starter_yearly',
          provider: BillingProvider.apple,
          productCode: 'starter_yearly',
          providerProductId: 'mixroom_starter_yearly',
          basePlanId: '',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'apple_producer_monthly',
          provider: BillingProvider.apple,
          productCode: 'producer_monthly',
          providerProductId: 'mixroom_producer_monthly',
          basePlanId: '',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'apple_producer_yearly',
          provider: BillingProvider.apple,
          productCode: 'producer_yearly',
          providerProductId: 'mixroom_producer_yearly',
          basePlanId: '',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'google_starter_monthly',
          provider: BillingProvider.google,
          productCode: 'starter_monthly',
          providerProductId: 'mixroom_starter_monthly',
          basePlanId: 'monthly',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'google_starter_yearly',
          provider: BillingProvider.google,
          productCode: 'starter_yearly',
          providerProductId: 'mixroom_starter_yearly',
          basePlanId: 'yearly',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'google_producer_monthly',
          provider: BillingProvider.google,
          productCode: 'producer_monthly',
          providerProductId: 'mixroom_producer_monthly',
          basePlanId: 'monthly',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
        BillingProviderProductDefinition(
          code: 'google_producer_yearly',
          provider: BillingProvider.google,
          productCode: 'producer_yearly',
          providerProductId: 'mixroom_producer_yearly',
          basePlanId: 'yearly',
          offerId: '',
          regions: <String>[],
          enabled: true,
        ),
      ],
      support: BillingSupportInfo.defaults(),
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
        .where(
            (product) => product.enabled && product.supportsPlatform(platform))
        .toList(growable: false);
  }

  BillingProviderProductDefinition? bestProviderProductForProduct({
    required String productCode,
    required BillingProvider provider,
    String? regionCode,
  }) {
    for (final providerProduct in providerProducts) {
      if (!providerProduct.enabled) continue;
      if (providerProduct.productCode != productCode) continue;
      if (providerProduct.provider != provider) continue;
      if (!providerProduct.supportsRegion(regionCode)) continue;
      return providerProduct;
    }
    return null;
  }
}

class BillingAccountSnapshot {
  const BillingAccountSnapshot({
    required this.provider,
    required this.managementChannel,
    required this.plan,
    required this.status,
    required this.productCode,
    required this.nextBilledAt,
    required this.expiresAt,
    required this.cancelAtPeriodEnd,
    required this.seatCount,
    required this.extraStorageTb,
    required this.billingEmail,
    required this.paymentMethod,
    required this.manageUrl,
    required this.updatePaymentMethodUrl,
    required this.cancelSubscriptionUrl,
    required this.invoicesUrl,
    required this.providerManagementConfigured,
    required this.providerManagementReason,
  });

  final BillingProvider provider;
  final String managementChannel;
  final String plan;
  final SubscriptionStatus status;
  final String productCode;
  final DateTime? nextBilledAt;
  final DateTime? expiresAt;
  final bool cancelAtPeriodEnd;
  final int? seatCount;
  final int extraStorageTb;
  final String billingEmail;
  final BillingPaymentMethodDisplay? paymentMethod;
  final String manageUrl;
  final String updatePaymentMethodUrl;
  final String cancelSubscriptionUrl;
  final String invoicesUrl;
  final bool providerManagementConfigured;
  final String providerManagementReason;

  factory BillingAccountSnapshot.fromJson(Map<String, dynamic> json) {
    return BillingAccountSnapshot(
      provider: BillingProviderX.fromValue((json['provider'] ?? '').toString()),
      managementChannel: (json['management_channel'] ?? '').toString(),
      plan: normalizePlanCode((json['plan'] ?? '').toString()),
      status: SubscriptionStatusX.fromValue((json['status'] ?? '').toString()),
      productCode: (json['product_code'] ?? '').toString(),
      nextBilledAt:
          _parseDate(json['next_billed_at'] ?? json['next_billing_at']),
      expiresAt: _parseDate(json['expires_at'] ?? json['current_period_end']),
      cancelAtPeriodEnd: _asBool(json['cancel_at_period_end']),
      seatCount: _asNullableInt(json['seat_count']),
      extraStorageTb: _asInt(json['extra_storage_tb']),
      billingEmail: (json['billing_email'] ?? '').toString(),
      paymentMethod:
          BillingPaymentMethodDisplay.fromJsonOrNull(json['payment_method']),
      manageUrl: (json['manage_url'] ?? '').toString(),
      updatePaymentMethodUrl:
          (json['update_payment_method_url'] ?? '').toString(),
      cancelSubscriptionUrl: (json['cancel_subscription_url'] ?? '').toString(),
      invoicesUrl: (json['invoices_url'] ?? '').toString(),
      providerManagementConfigured: _asBool(
          _asStringDynamicMap(json['provider_management'])['configured']),
      providerManagementReason:
          (_asStringDynamicMap(json['provider_management'])['reason'] ?? '')
              .toString(),
    );
  }
}

class BillingPaymentMethodDisplay {
  const BillingPaymentMethodDisplay({
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });

  final String brand;
  final String last4;
  final int? expMonth;
  final int? expYear;

  static BillingPaymentMethodDisplay? fromJsonOrNull(Object? raw) {
    final json = _asStringDynamicMap(raw);
    final brand = (json['brand'] ?? '').toString().trim();
    final last4 = (json['last4'] ?? '').toString().trim();
    final expMonth = _asNullableInt(json['exp_month']);
    final expYear = _asNullableInt(json['exp_year']);
    if (brand.isEmpty && last4.isEmpty && expMonth == null && expYear == null) {
      return null;
    }
    return BillingPaymentMethodDisplay(
      brand: brand,
      last4: last4,
      expMonth: expMonth,
      expYear: expYear,
    );
  }
}

class EntitlementSnapshot {
  const EntitlementSnapshot({
    required this.userId,
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
    required this.productCode,
    required this.nextBilledAt,
    required this.seatCount,
    required this.extraStorageTb,
    required this.paddleSubscriptionId,
    required this.limits,
    required this.accessSources,
    required this.workspaceAccessSummary,
    required this.organizations,
    required this.billingSupport,
  });

  final String userId;
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
  final String productCode;
  final DateTime? nextBilledAt;
  final int? seatCount;
  final int extraStorageTb;
  final String paddleSubscriptionId;
  final Map<String, dynamic> limits;
  final List<AccountAccessSource> accessSources;
  final CollaborationAccessSummary workspaceAccessSummary;
  final List<OrganizationAccessItem> organizations;
  final BillingSupportInfo billingSupport;

  bool hasCapability(String key) => capabilities[key] == true;

  bool get isPaidPlan => planCode != 'free';

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
      'product_code': productCode,
      'next_billed_at': nextBilledAt?.toUtc().toIso8601String(),
      'seat_count': seatCount,
      'extra_storage_tb': extraStorageTb,
      'paddle_subscription_id': paddleSubscriptionId,
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
    final status =
        SubscriptionStatusX.fromValue((json['status'] ?? '').toString());
    final planCode = normalizePlanCode(
      _asNonEmptyString(
        json['plan_code'],
        fallback: _fallbackPlanCodeFromText((json['tier'] ?? '').toString()),
      ),
    );

    return EntitlementSnapshot(
      userId: userId,
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
        fallbackPlanCode: planCode,
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
      productCode: (json['product_code'] ?? '').toString(),
      nextBilledAt: _parseDate(json['next_billed_at']),
      seatCount: _asNullableInt(json['seat_count']),
      extraStorageTb: _asInt(json['extra_storage_tb']),
      paddleSubscriptionId: (json['paddle_subscription_id'] ?? '').toString(),
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
      status: SubscriptionStatus.active,
      effectiveAt: DateTime.now().toUtc(),
      expiresAt: null,
      sourceProvider: BillingProvider.adminGrant,
      sourceSubscriptionId: 'free-default',
      capabilities: defaultCapabilitiesForPlanCode('free'),
      managementChannel: 'free',
      revision: revision,
      planCode: 'free',
      planLabel: 'Free',
      planGroup: 'individual',
      productCode: '',
      nextBilledAt: null,
      seatCount: null,
      extraStorageTb: 0,
      paddleSubscriptionId: '',
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
    required String fallbackPlanCode,
  }) {
    final defaults = defaultCapabilitiesForPlanCode(fallbackPlanCode);
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

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final raw = value.toString().trim();
  if (raw.isEmpty || raw.toLowerCase() == 'custom') return null;
  return int.tryParse(raw);
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

String normalizePlanCode(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'pro') {
    return 'producer';
  }
  if (normalized == 'basic') {
    return 'free';
  }
  if (RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(normalized)) {
    return normalized;
  }
  return 'free';
}

String _fallbackPlanCodeFromText(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'starter':
      return 'starter';
    case 'producer':
    case 'pro':
      return 'producer';
    case 'studio':
      return 'studio';
    case 'enterprise':
      return 'enterprise';
    case 'education':
      return 'education';
    default:
      return 'free';
  }
}

String _titleizeCode(String value) {
  final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
  if (normalized.isEmpty) return value;
  return normalized.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }).join(' ');
}
