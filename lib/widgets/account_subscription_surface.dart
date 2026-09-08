import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/widgets/account_glass_ui.dart';

typedef ManageSubscriptionAction =
    void Function({BillingProvider? provider, String? managementChannel});

String _t(BuildContext context, String key) => L10n.translate(context, key);

String _tr(BuildContext context, String key, Map<String, Object> values) {
  var text = _t(context, key);
  values.forEach((name, value) {
    text = text.replaceAll('{$name}', '$value');
  });
  return text;
}

String _localizedPlanLabel(
  BuildContext context, {
  required String planCode,
  required String fallback,
}) {
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return _t(context, 'Free');
    case 'education':
      return _t(context, 'Education');
    case 'enterprise':
      return _t(context, 'Enterprise');
    case 'starter':
      return 'Starter';
    case 'producer':
      return 'Producer';
    case 'studio':
      return 'Studio';
    default:
      return _t(context, fallback);
  }
}

bool _localeLooksKorean(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode.trim().toLowerCase() == 'ko' ||
      (locale.countryCode ?? '').trim().toUpperCase() == 'KR';
}

String _formatKrwPrice(
  BuildContext context, {
  required int amount,
  required String billingInterval,
}) {
  final formatted = NumberFormat.decimalPattern('ko_KR').format(amount);
  final suffix = _krwBillingSuffix(context, billingInterval);
  return '₩$formatted$suffix';
}

String _krwBillingSuffix(BuildContext context, String billingInterval) {
  final koreanLanguage =
      Localizations.localeOf(context).languageCode.trim().toLowerCase() == 'ko';
  switch (billingInterval.trim().toLowerCase()) {
    case 'monthly':
      return koreanLanguage ? '/월' : '/mo';
    case 'yearly':
    case 'annual':
      return koreanLanguage ? '/년' : '/yr';
    case 'daily':
      return koreanLanguage ? '/일' : '/day';
    default:
      return '';
  }
}

String _localizedRoleLabel(BuildContext context, String role) {
  switch (role.trim().toLowerCase()) {
    case 'owner':
      return _t(context, 'Owner');
    case 'admin':
      return _t(context, 'Admin');
    case 'manager':
      return _t(context, 'Manager');
    case 'teacher':
      return _t(context, 'Teacher');
    case 'student':
      return _t(context, 'Student');
    case 'viewer':
      return _t(context, 'Viewer');
    case 'member':
    default:
      return _t(context, 'Member');
  }
}

class AccountSubscriptionSurface extends StatefulWidget {
  const AccountSubscriptionSurface({
    super.key,
    required this.entitlementService,
    required this.iapService,
    required this.aiUsageStatus,
    required this.isAiUsageLoading,
    required this.platformKey,
    required this.regionCode,
    required this.platformProvider,
    required this.isActionBusy,
    required this.inlineMessage,
    required this.onRefresh,
    required this.onManageSubscription,
    required this.onRestorePurchases,
    required this.onContactSupport,
    required this.onSelectProduct,
  });

  final EntitlementService entitlementService;
  final IapService iapService;
  final AiPromptRateLimitStatus? aiUsageStatus;
  final bool isAiUsageLoading;
  final String platformKey;
  final String regionCode;
  final BillingProvider platformProvider;
  final bool isActionBusy;
  final String? inlineMessage;
  final VoidCallback onRefresh;
  final ManageSubscriptionAction onManageSubscription;
  final VoidCallback onRestorePurchases;
  final VoidCallback onContactSupport;
  final ValueChanged<BillingProductDefinition> onSelectProduct;

  @override
  State<AccountSubscriptionSurface> createState() =>
      _AccountSubscriptionSurfaceState();
}

List<BillingProductDefinition> _visibleBillingProducts(
  BillingCatalogSnapshot? catalog,
  String platformKey,
) {
  if (catalog == null) return const <BillingProductDefinition>[];
  final byCode = <String, BillingProductDefinition>{};
  for (final product in catalog.enabledProductsForPlatform(platformKey)) {
    byCode[product.code] = product;
  }
  for (final product in catalog.products) {
    if (!product.enabled) continue;
    final plan = catalog.planByCode(product.planCode);
    if (plan?.code != 'studio') continue;
    if (product.type != 'subscription') continue;
    if (product.managementChannel.trim().toLowerCase() != 'web') continue;
    byCode.putIfAbsent(product.code, () => product);
  }
  final products = byCode.values.toList(growable: false);
  products.sort((a, b) {
    final rankCompare = _billingProductSortRank(
      catalog,
      a,
    ).compareTo(_billingProductSortRank(catalog, b));
    if (rankCompare != 0) return rankCompare;
    return a.code.compareTo(b.code);
  });
  return products;
}

int _billingProductSortRank(
  BillingCatalogSnapshot catalog,
  BillingProductDefinition product,
) {
  if (product.rank > 0) {
    return product.rank;
  }
  final planRank =
      catalog.planByCode(product.planCode)?.rank ??
      _fallbackBillingPlanRank(product.planCode);
  return planRank * 100 + _billingIntervalSortRank(product.billingInterval);
}

int _fallbackBillingPlanRank(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'starter':
      return 10;
    case 'producer':
      return 20;
    case 'studio':
      return 30;
    case 'enterprise':
      return 40;
    case 'education':
      return 50;
    default:
      return 0;
  }
}

int _billingIntervalSortRank(String interval) {
  switch (interval.trim().toLowerCase()) {
    case 'monthly':
      return 0;
    case 'yearly':
    case 'annual':
      return 1;
    case 'custom':
      return 90;
    default:
      return 50;
  }
}

class _AccountSubscriptionSurfaceState
    extends State<AccountSubscriptionSurface> {
  final TextEditingController _educationAcceptController =
      TextEditingController();
  bool _educationAcceptBusy = false;
  String? _educationAcceptMessage;

  @override
  void dispose() {
    _educationAcceptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entitlement =
        widget.entitlementService.entitlement ??
        EntitlementSnapshot.free(userId: '');
    final catalog = widget.entitlementService.billingCatalog;
    final accessSummary = widget.entitlementService.effectiveAccessSummary;
    final products = _visibleBillingProducts(catalog, widget.platformKey);
    final busy = widget.isActionBusy || widget.iapService.isPurchaseInProgress;
    final studentEducationOrganizations = widget
        .entitlementService
        .effectiveOrganizations
        .where(_isEducationStudentOrganization)
        .toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PlanHero(
                entitlement: entitlement,
                billing: widget.entitlementService.billingAccount,
                aiUsageStatus: widget.aiUsageStatus,
                isAiUsageLoading: widget.isAiUsageLoading,
                isBusy: busy,
                onManageSubscription: widget.onManageSubscription,
              ),
              const SizedBox(height: 10),
              _BillingActions(
                isBusy: busy,
                isRefreshing: widget.entitlementService.isAccountSurfaceLoading,
                onRestorePurchases: widget.onRestorePurchases,
                onContactSupport: widget.onContactSupport,
                onRefresh: widget.onRefresh,
              ),
              const SizedBox(height: 26),
              _PlansPanel(
                entitlement: entitlement,
                catalog: catalog,
                products: products,
                platformProvider: widget.platformProvider,
                regionCode: widget.regionCode,
                iapService: widget.iapService,
                isBusy: busy,
                onManageSubscription: widget.onManageSubscription,
                onSelectProduct: widget.onSelectProduct,
              ),
              if (accessSummary.hasAnyAccess) ...[
                const SizedBox(height: 14),
                _TeamAccessSummary(
                  accessSummary: accessSummary,
                  organizations:
                      widget.entitlementService.effectiveOrganizations,
                  onManageSubscription: widget.onManageSubscription,
                  onOpenEducationDashboard: _openEducationDashboard,
                ),
              ],
              if (studentEducationOrganizations.isNotEmpty) ...[
                const SizedBox(height: 14),
                _EducationStudentAccessPanel(
                  organization: studentEducationOrganizations.first,
                ),
              ],
              if (widget.entitlementService.effectiveOrganizations
                      .where(_isEducationTeacherOrganization)
                      .isEmpty &&
                  studentEducationOrganizations.isEmpty) ...[
                const SizedBox(height: 14),
                _EducationInviteAcceptPanel(
                  controller: _educationAcceptController,
                  isBusy: _educationAcceptBusy,
                  message: _educationAcceptMessage,
                  onAccept: _acceptEducationInvite,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptEducationInvite() async {
    if (_educationAcceptBusy) return;
    final token = _educationInviteTokenFromInput(
      _educationAcceptController.text,
    );
    if (token.isEmpty) {
      setState(() {
        _educationAcceptMessage = _t(
          context,
          'Paste a valid education invite link or code.',
        );
      });
      return;
    }
    setState(() {
      _educationAcceptBusy = true;
      _educationAcceptMessage = null;
    });
    try {
      await widget.entitlementService.acceptEducationInvite(inviteToken: token);
      if (!mounted) return;
      _educationAcceptController.clear();
      setState(() {
        _educationAcceptMessage = _t(
          context,
          'Education access activated.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _educationAcceptMessage = _t(
          context,
          'Could not accept this invite. It may have expired or already been used.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _educationAcceptBusy = false;
        });
      }
    }
  }

  void _openEducationDashboard(OrganizationAccessItem organization) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EducationTeacherDashboardPage(
          entitlementService: widget.entitlementService,
          initialOrganization: organization,
          onRequestSeatChange: widget.onContactSupport,
        ),
      ),
    );
  }
}

String _educationMembershipLabel(OrganizationMembershipItem membership) {
  final email = membership.email.trim();
  if (email.isNotEmpty) return email;
  final userId = membership.userId.trim();
  return userId.isNotEmpty ? userId : 'student';
}

String _educationInviteTokenFromInput(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return '';
  final uri = Uri.tryParse(raw);
  if (uri != null) {
    final invite = uri.queryParameters['invite']?.trim();
    if (invite != null && invite.isNotEmpty) return invite;
    final segments = uri.pathSegments;
    final inviteIndex = segments.indexOf('invites');
    if (inviteIndex >= 0 && inviteIndex + 1 < segments.length) {
      final candidate = segments[inviteIndex + 1].trim();
      if (candidate.isNotEmpty && candidate != 'accept') return candidate;
    }
  }
  return raw
      .replaceFirst('invite=', '')
      .replaceAll(RegExp(r'[\s#?&].*$'), '')
      .trim();
}

bool _isEducationTeacherOrganization(OrganizationAccessItem organization) {
  if (organization.planCode.trim().toLowerCase() != 'education') {
    return false;
  }
  return {
    'owner',
    'admin',
    'manager',
    'teacher',
  }.contains(organization.role.trim().toLowerCase());
}

bool _isEducationStudentOrganization(OrganizationAccessItem organization) {
  return organization.planCode.trim().toLowerCase() == 'education' &&
      organization.role.trim().toLowerCase() == 'student' &&
      organization.membershipStatus.trim().toLowerCase() == 'active';
}

String _membershipRoleReadout(BuildContext context, String role) {
  final normalized = role.trim().toLowerCase();
  final label = _localizedRoleLabel(context, role);
  if (normalized == 'owner') {
    return _tr(context, 'You are the {role}', {'role': label});
  }
  return _tr(context, 'You are a {role}', {'role': label});
}

class _PlanHero extends StatelessWidget {
  const _PlanHero({
    required this.entitlement,
    required this.billing,
    required this.aiUsageStatus,
    required this.isAiUsageLoading,
    required this.isBusy,
    required this.onManageSubscription,
  });

  final EntitlementSnapshot entitlement;
  final BillingAccountSnapshot? billing;
  final AiPromptRateLimitStatus? aiUsageStatus;
  final bool isAiUsageLoading;
  final bool isBusy;
  final ManageSubscriptionAction onManageSubscription;

  @override
  Widget build(BuildContext context) {
    return _EntitlementOverviewCard(
      entitlement: entitlement,
      billing: billing,
      aiUsageStatus: aiUsageStatus,
      isAiUsageLoading: isAiUsageLoading,
      isBusy: isBusy,
      onManageSubscription: onManageSubscription,
    );
  }
}

class _EntitlementOverviewCard extends StatelessWidget {
  const _EntitlementOverviewCard({
    required this.entitlement,
    required this.billing,
    required this.aiUsageStatus,
    required this.isAiUsageLoading,
    required this.isBusy,
    required this.onManageSubscription,
  });

  final EntitlementSnapshot entitlement;
  final BillingAccountSnapshot? billing;
  final AiPromptRateLimitStatus? aiUsageStatus;
  final bool isAiUsageLoading;
  final bool isBusy;
  final ManageSubscriptionAction onManageSubscription;

  @override
  Widget build(BuildContext context) {
    final personal = _personalAccessDisplay(context, entitlement);
    final purchaseContext = _personalPurchaseContext(entitlement);
    final planCode = purchaseContext.planCode.trim().isNotEmpty
        ? purchaseContext.planCode.trim().toLowerCase()
        : entitlement.planCode.trim().toLowerCase();
    final status = _subscriptionStatusLabel(context, entitlement.status);
    final canManagePersonal = personal.canManage && !isBusy;
    final billingDetails = _billingDetailsForOverview(
      context,
      billing,
      isBusy: isBusy,
      onManageSubscription: onManageSubscription,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(context, 'Current plan'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      personal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PlanStatusPill(
                label: status,
                active: entitlement.isAccessActive,
              ),
            ],
          ),
          if (billingDetails.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final item in billingDetails)
                  _BillingDetailLine(item: item),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 8,
            children: [
              if (personal.actionLabel.trim().isNotEmpty)
                _SubscriptionActionButton(
                  label: personal.actionLabel,
                  icon: personal.actionIcon,
                  onPressed: canManagePersonal
                      ? () => onManageSubscription(
                          provider: personal.actionProvider,
                          managementChannel: personal.actionManagementChannel,
                        )
                      : null,
                ),
              _SubscriptionActionButton(
                label: _t(context, 'View on web'),
                icon: Icons.language_rounded,
                onPressed: isBusy
                    ? null
                    : () => onManageSubscription(
                        provider: BillingProvider.unknown,
                        managementChannel: 'web_plans',
                      ),
                emphasized: true,
              ),
            ],
          ),
          if (planCode != 'free') ...[
            const SizedBox(height: 14),
            _AiUsageCard(status: aiUsageStatus, isLoading: isAiUsageLoading),
          ],
        ],
      ),
    );
  }
}

List<_BillingDetailItem> _billingDetailsForOverview(
  BuildContext context,
  BillingAccountSnapshot? billing, {
  required bool isBusy,
  required ManageSubscriptionAction onManageSubscription,
}) {
  if (billing == null) return const <_BillingDetailItem>[];

  final oneTimeAccessEndsAt = _isTossOneTimeBilling(billing)
      ? billing.expiresAt
      : null;
  final shouldShowProvider =
      billing.provider != BillingProvider.adminGrant &&
      billing.provider != BillingProvider.unknown;

  return [
    if (shouldShowProvider)
      _BillingDetailItem(
        label: _t(context, 'Billed through'),
        value: _providerLabel(context, billing.provider),
        onPressed:
            isBusy ||
                billing.provider == BillingProvider.unknown ||
                billing.provider == BillingProvider.adminGrant
            ? null
            : () => onManageSubscription(
                provider: billing.provider,
                managementChannel: billing.managementChannel,
              ),
      ),
    if (oneTimeAccessEndsAt != null)
      _BillingDetailItem(
        label: _t(context, 'Access ends'),
        value: _formatDate(oneTimeAccessEndsAt),
      )
    else if (billing.nextBilledAt != null)
      _BillingDetailItem(
        label: _t(context, 'Renews'),
        value: _formatDate(billing.nextBilledAt!),
      ),
    if (billing.seatCount != null && billing.seatCount! > 0)
      _BillingDetailItem(
        label: _t(context, 'Seats'),
        value: '${billing.seatCount}',
      ),
    if (billing.extraStorageTb > 0)
      _BillingDetailItem(
        label: _t(context, 'Extra storage'),
        value: '+${billing.extraStorageTb} TB',
      ),
    if (billing.paymentMethod != null)
      _BillingDetailItem(
        label: _t(context, 'Payment'),
        value: _paymentMethodLabel(billing.paymentMethod!),
      ),
  ];
}

class _PlanStatusPill extends StatelessWidget {
  const _PlanStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF8CFFCD) : const Color(0xFFFFC06F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.2,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _SubscriptionActionButton extends StatelessWidget {
  const _SubscriptionActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (!emphasized) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.72),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 11.2,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: FilledButton.styleFrom(
        foregroundColor: kAccountGlassText,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.34),
        backgroundColor: kAccountGlassBlue.withValues(alpha: 0.88),
        disabledBackgroundColor: kAccountGlassBlue.withValues(alpha: 0.30),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11.4, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _AiUsageCard extends StatelessWidget {
  const _AiUsageCard({required this.status, required this.isLoading});

  final AiPromptRateLimitStatus? status;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.26)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _t(context, 'AI usage'),
                style: const TextStyle(
                  color: Color(0xFFF4F4F4),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white54,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _AiUsageRow(
          label: _t(context, 'Daily'),
          remainingPercent: status?.daily.remainingPercent,
        ),
        Divider(height: 14, color: Colors.white.withValues(alpha: 0.24)),
        _AiUsageRow(
          label: _t(context, 'Weekly'),
          remainingPercent: status?.weekly.remainingPercent,
        ),
      ],
    );
  }
}

class _AiUsageRow extends StatelessWidget {
  const _AiUsageRow({required this.label, required this.remainingPercent});

  final String label;
  final int? remainingPercent;

  @override
  Widget build(BuildContext context) {
    final normalizedPercent = remainingPercent?.clamp(0, 100).toInt();
    final value = normalizedPercent == null
        ? '--%'
        : '$normalizedPercent% ${_t(context, 'left')}';

    return Semantics(
      label: '$label $value',
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF4F4F4),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeSemantics(
              child: _AiUsageProgressBar(remainingPercent: normalizedPercent),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: ExcludeSemantics(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageProgressBar extends StatelessWidget {
  const _AiUsageProgressBar({required this.remainingPercent});

  final int? remainingPercent;

  @override
  Widget build(BuildContext context) {
    final target = (remainingPercent ?? 0) / 100;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        final color = _aiUsageProgressColor(progress);
        return Container(
          height: 7,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.72), color],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.34),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _aiUsageProgressColor(double progress) {
  final normalized = progress.clamp(0.0, 1.0);
  if (normalized <= 0.5) {
    return Color.lerp(
      const Color(0xFFFF6673),
      const Color(0xFFFFC15C),
      normalized * 2,
    )!;
  }
  return Color.lerp(
    const Color(0xFFFFC15C),
    const Color(0xFF67E8A5),
    (normalized - 0.5) * 2,
  )!;
}

class _AccessDisplay {
  const _AccessDisplay({
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.actionIcon,
    required this.canManage,
    required this.actionProvider,
    required this.actionManagementChannel,
  });

  final String title;
  final String detail;
  final String actionLabel;
  final IconData actionIcon;
  final bool canManage;
  final BillingProvider? actionProvider;
  final String actionManagementChannel;
}

class _BillingActions extends StatelessWidget {
  const _BillingActions({
    required this.isBusy,
    required this.isRefreshing,
    required this.onRestorePurchases,
    required this.onContactSupport,
    required this.onRefresh,
  });

  final bool isBusy;
  final bool isRefreshing;
  final VoidCallback onRestorePurchases;
  final VoidCallback onContactSupport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        _QuietActionButton(
          label: _t(context, 'Restore purchases'),
          icon: Icons.restore_rounded,
          onPressed: isBusy ? null : onRestorePurchases,
        ),
        _QuietActionButton(
          label: _t(context, 'Contact support'),
          icon: Icons.support_agent_rounded,
          onPressed: isBusy ? null : onContactSupport,
        ),
        IconButton(
          tooltip: isRefreshing || isBusy
              ? _t(context, 'Refreshing')
              : _t(context, 'Refresh'),
          onPressed: isRefreshing || isBusy ? null : onRefresh,
          icon: isRefreshing
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white60,
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          color: Colors.white60,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _BillingDetailItem {
  const _BillingDetailItem({
    required this.label,
    required this.value,
    this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;
}

class _BillingDetailLine extends StatelessWidget {
  const _BillingDetailLine({required this.item});

  final _BillingDetailItem item;

  @override
  Widget build(BuildContext context) {
    final child = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${item.label}  ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.46),
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: item.value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 11.6,
              fontWeight: FontWeight.w700,
              decoration: item.onPressed == null
                  ? TextDecoration.none
                  : TextDecoration.underline,
              decorationColor: const Color(0xFFA4C2FF),
            ),
          ),
        ],
      ),
    );
    if (item.onPressed == null) return child;
    return GestureDetector(
      onTap: item.onPressed,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

String _providerLabel(BuildContext context, BillingProvider provider) {
  switch (provider) {
    case BillingProvider.apple:
      return 'App Store';
    case BillingProvider.google:
      return 'Google Play';
    case BillingProvider.paddle:
      return 'Paddle';
    case BillingProvider.toss:
      return 'Toss';
    case BillingProvider.kakao:
      return 'Kakao';
    case BillingProvider.adminGrant:
      return _t(context, 'Admin');
    case BillingProvider.unknown:
      return _t(context, 'Unknown');
  }
}

String _paymentMethodLabel(BillingPaymentMethodDisplay method) {
  final brand = method.brand.trim();
  final last4 = method.last4.trim();
  final expiry = method.expMonth != null && method.expYear != null
      ? ' ${method.expMonth}/${method.expYear}'
      : '';
  if (brand.isNotEmpty && last4.isNotEmpty) {
    return '$brand ending $last4$expiry';
  }
  if (last4.isNotEmpty) return 'Ending $last4$expiry';
  if (brand.isNotEmpty) return '$brand$expiry';
  return expiry.trim();
}

class AccountPlansCarousel extends StatelessWidget {
  const AccountPlansCarousel({
    super.key,
    required this.entitlementService,
    required this.iapService,
    required this.platformKey,
    required this.regionCode,
    required this.platformProvider,
    required this.onOpenAccountPlans,
    this.scrollbarGutter = 0,
    this.railEdgeInset = 6,
  });

  final EntitlementService entitlementService;
  final IapService iapService;
  final String platformKey;
  final String regionCode;
  final BillingProvider platformProvider;
  final VoidCallback onOpenAccountPlans;
  final double scrollbarGutter;
  final double railEdgeInset;

  @override
  Widget build(BuildContext context) {
    final entitlement =
        entitlementService.entitlement ?? EntitlementSnapshot.free(userId: '');
    final catalog = entitlementService.billingCatalog;
    final products = _visibleBillingProducts(catalog, platformKey);
    final busy =
        entitlementService.isAccountSurfaceLoading ||
        iapService.isPurchaseInProgress;
    return _PlansPanel(
      entitlement: entitlement,
      catalog: catalog,
      products: products,
      platformProvider: platformProvider,
      regionCode: regionCode,
      iapService: iapService,
      isBusy: busy,
      onManageSubscription: ({provider, managementChannel}) =>
          onOpenAccountPlans(),
      onSelectProduct: (_) => onOpenAccountPlans(),
      scrollbarGutter: scrollbarGutter,
      railEdgeInset: railEdgeInset,
    );
  }
}

class _PlansPanel extends StatefulWidget {
  const _PlansPanel({
    required this.entitlement,
    required this.catalog,
    required this.products,
    required this.platformProvider,
    required this.regionCode,
    required this.iapService,
    required this.isBusy,
    required this.onManageSubscription,
    required this.onSelectProduct,
    this.scrollbarGutter = 0,
    this.railEdgeInset = 6,
  });

  final EntitlementSnapshot entitlement;
  final BillingCatalogSnapshot? catalog;
  final List<BillingProductDefinition> products;
  final BillingProvider platformProvider;
  final String regionCode;
  final IapService iapService;
  final bool isBusy;
  final ManageSubscriptionAction onManageSubscription;
  final ValueChanged<BillingProductDefinition> onSelectProduct;
  final double scrollbarGutter;
  final double railEdgeInset;

  @override
  State<_PlansPanel> createState() => _PlansPanelState();
}

class _PlansPanelState extends State<_PlansPanel> {
  final ScrollController _plansScrollController = ScrollController();
  final FocusNode _plansFocusNode = FocusNode(debugLabel: 'billing_plans');
  double _currentCardStep = 0;
  int _currentCardCount = 0;
  bool _centerCards = false;

  @override
  void dispose() {
    _plansScrollController.dispose();
    _plansFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = _planDisplayCards(widget.catalog, widget.products);
    if (cards.isEmpty) {
      return _LoadingPlansCard(
        message: widget.catalog == null
            ? _t(context, 'Plans are loading.')
            : _t(context, 'No plans are currently available for this device.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t(context, 'Explore More Plans'),
                  style: const TextStyle(
                    color: Color(0xFFF4F4F4),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ),
              _PlanScrollButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => _scrollPlans(-1),
              ),
              const SizedBox(width: 6),
              _PlanScrollButton(
                icon: Icons.arrow_forward_rounded,
                onPressed: () => _scrollPlans(1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        KeyboardListener(
          focusNode: _plansFocusNode,
          autofocus: true,
          onKeyEvent: _handlePlanKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _plansFocusNode.requestFocus,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const railPadding = 10.0;
                const cardGap = 10.0;
                final contentWidth = (constraints.maxWidth - railPadding * 2)
                    .clamp(0.0, double.infinity);
                final usableContentWidth =
                    (contentWidth - widget.railEdgeInset * 2).clamp(
                      0.0,
                      double.infinity,
                    );
                final visibleCardCount = usableContentWidth >= 740
                    ? 3
                    : usableContentWidth >= 500
                    ? 2
                    : 1;
                final cardWidth = visibleCardCount == 1
                    ? usableContentWidth
                    : ((usableContentWidth - cardGap * (visibleCardCount - 1)) /
                              visibleCardCount)
                          .clamp(224.0, 264.0);
                final cardStep = cardWidth + cardGap;
                final cardCenteringInset = (contentWidth - cardWidth) / 2;
                final centerCards = visibleCardCount == 1;
                final railInset = centerCards
                    ? (cardCenteringInset > widget.railEdgeInset
                          ? cardCenteringInset
                          : widget.railEdgeInset)
                    : widget.railEdgeInset;
                _currentCardStep = cardStep;
                _currentCardCount = cards.length;
                _centerCards = centerCards;
                final scrollbarGutter = widget.scrollbarGutter;
                final plansScrollView = SingleChildScrollView(
                  controller: _plansScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.hardEdge,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: railInset),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in cards.asMap().entries) ...[
                          SizedBox(
                            width: cardWidth,
                            height: 450,
                            child: _PlanListRow(
                              data: entry.value,
                              planIsCurrent: _isCurrentPlanCard(entry.value),
                              priceLabel: _priceLabelForCard(
                                context,
                                entry.value,
                              ),
                              billingCaption: _billingCaptionForCard(
                                context,
                                entry.value,
                              ),
                              isBusy: widget.isBusy,
                              productActions: _productActionsForCard(
                                context,
                                entry.value,
                              ),
                              fallbackAction: _fallbackActionForCard(
                                context,
                                entry.value,
                                _isCurrentPlanCard(entry.value),
                              ),
                            ),
                          ),
                          if (entry.key != cards.length - 1)
                            const SizedBox(width: cardGap),
                        ],
                      ],
                    ),
                  ),
                );

                return Container(
                  padding: const EdgeInsets.fromLTRB(
                    railPadding,
                    railPadding,
                    railPadding,
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis == Axis.horizontal) {
                        _snapPlansToNearest(cardStep);
                      }
                      return false;
                    },
                    child: scrollbarGutter > 0
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 450, child: plansScrollView),
                              SizedBox(height: scrollbarGutter),
                              _PlanRailProgressIndicator(
                                controller: _plansScrollController,
                              ),
                            ],
                          )
                        : Scrollbar(
                            controller: _plansScrollController,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SizedBox(
                              height: 450,
                              child: plansScrollView,
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _handlePlanKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _scrollPlans(1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _scrollPlans(-1);
    }
  }

  void _scrollPlans(int direction) {
    if (!_plansScrollController.hasClients) return;
    final position = _plansScrollController.position;
    final points = _planSnapPoints(position);
    if (points.length < 2) return;
    final currentIndex = _nearestSnapPointIndex(points, position.pixels);
    final targetIndex = (currentIndex + direction).clamp(0, points.length - 1);
    _animatePlansTo(points[targetIndex]);
  }

  void _snapPlansToNearest(double cardStep) {
    if (!_plansScrollController.hasClients || cardStep <= 0) return;
    final position = _plansScrollController.position;
    final points = _planSnapPoints(position, cardStep: cardStep);
    if (points.isEmpty) return;
    _animatePlansTo(points[_nearestSnapPointIndex(points, position.pixels)]);
  }

  List<double> _planSnapPoints(ScrollPosition position, {double? cardStep}) {
    final step = cardStep ?? _currentCardStep;
    if (step <= 0) return <double>[position.minScrollExtent];

    if (_centerCards) {
      return List<double>.generate(
        _currentCardCount,
        (index) => (position.minScrollExtent + index * step).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }

    final points = <double>[position.minScrollExtent];
    var next = position.minScrollExtent + step;
    while (next < position.maxScrollExtent - 0.5) {
      points.add(next);
      next += step;
    }
    if ((points.last - position.maxScrollExtent).abs() > 0.5) {
      points.add(position.maxScrollExtent);
    }
    return points;
  }

  int _nearestSnapPointIndex(List<double> points, double pixels) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final distance = (points[index] - pixels).abs();
      if (distance < nearestDistance) {
        nearestIndex = index;
        nearestDistance = distance;
      }
    }
    return nearestIndex;
  }

  void _animatePlansTo(double target) {
    if (!_plansScrollController.hasClients) return;
    final current = _plansScrollController.position.pixels;
    if ((target - current).abs() < 0.5) return;
    _plansScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String? _storePriceForProduct(
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    final providerProduct = catalog?.bestProviderProductForProduct(
      productCode: product.code,
      provider: widget.platformProvider,
      regionCode: widget.regionCode,
    );
    if (providerProduct == null) {
      return null;
    }
    return widget.iapService
        .findProductById(providerProduct.providerProductId)
        ?.price;
  }

  String _actionLabel(
    BuildContext context,
    _PlanPurchaseContext purchaseContext,
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    if (_isCurrentPlan(purchaseContext, product)) {
      return _t(context, 'Current plan');
    }
    if (product.managementChannel == 'admin' || product.type == 'contract') {
      return _t(context, 'Contact sales');
    }
    if (_requiresManagedPlanChange(
      purchaseContext,
      catalog,
      product,
      widget.platformProvider,
    )) {
      return _managePlanChangeLabel(context, purchaseContext);
    }
    if (_isPlanUpgrade(purchaseContext, catalog, product)) {
      return _t(context, 'Upgrade');
    }
    if (_isPlanDowngrade(purchaseContext, catalog, product) &&
        _isMobileStorePlanChange(
          purchaseContext,
          product,
          widget.platformProvider,
        )) {
      return _t(context, 'Change plan');
    }
    if (_isMobileStorePlanChange(
      purchaseContext,
      product,
      widget.platformProvider,
    )) {
      return _t(context, 'Change plan');
    }
    final providerProduct = catalog?.bestProviderProductForProduct(
      productCode: product.code,
      provider: widget.platformProvider,
      regionCode: widget.regionCode,
    );
    if (product.managementChannel.trim().toLowerCase() == 'web') {
      return _t(context, 'Buy on web');
    }
    return providerProduct != null
        ? _t(context, 'Choose plan')
        : _t(context, 'Open checkout');
  }

  bool _isCurrentPlanCard(_PlanDisplayCardData card) {
    final planCode = card.plan.code.trim().toLowerCase();
    if (planCode == 'free') {
      final purchaseContext = _personalPurchaseContext(widget.entitlement);
      return purchaseContext.isAccessActive &&
          purchaseContext.planCode.trim().toLowerCase() == 'free';
    }
    for (final product in card.products) {
      final purchaseContext = _purchaseContextForProduct(
        widget.entitlement,
        widget.catalog,
        product,
      );
      if (_isCurrentPlan(purchaseContext, product)) {
        return true;
      }
    }
    return widget.entitlement.isAccessActive &&
        widget.entitlement.planCode.trim().toLowerCase() == planCode;
  }

  String _priceLabelForCard(BuildContext context, _PlanDisplayCardData card) {
    final planCode = card.plan.code.trim().toLowerCase();
    if (planCode == 'free') {
      return _t(context, 'Free');
    }
    if (card.products.isEmpty) {
      return _fallbackWebsitePriceLabel(
        context,
        planCode,
        useKrw: _shouldUseKrwPricing(context),
      );
    }
    final product = _preferredProduct(card.products);
    final price = (_displayPriceForProduct(context, product) ?? '').trim();
    if (price.isEmpty) {
      return _t(context, 'See pricing');
    }
    return price;
  }

  bool _shouldUseKrwPricing(BuildContext context) {
    return _localeLooksKorean(context) ||
        widget.regionCode.trim().toUpperCase() == 'KR';
  }

  String? _displayPriceForProduct(
    BuildContext context,
    BillingProductDefinition product,
  ) {
    if (_shouldUseKrwPricing(context) && product.priceKrw > 0) {
      return _formatKrwPrice(
        context,
        amount: product.priceKrw,
        billingInterval: product.billingInterval,
      );
    }
    final storePrice = _storePriceForProduct(widget.catalog, product)?.trim();
    if (storePrice != null && storePrice.isNotEmpty) {
      return storePrice;
    }
    final fallbackPrice = product.priceDisplay.trim();
    return fallbackPrice.isEmpty ? null : fallbackPrice;
  }

  String _billingCaptionForCard(
    BuildContext context,
    _PlanDisplayCardData card,
  ) {
    if (card.products.isEmpty) {
      return _planAudienceLabel(context, card.plan.code);
    }
    final product = _preferredProduct(card.products);
    final cadence = _cadenceLabel(context, product.billingInterval);
    final alternatives = card.products
        .where((item) => item.code != product.code)
        .map((item) {
          final labelPrice = (_displayPriceForProduct(context, item) ?? '')
              .trim();
          final interval = _cadenceLabel(context, item.billingInterval);
          if (labelPrice.isEmpty) return interval ?? '';
          return interval == null ? labelPrice : '$interval $labelPrice';
        })
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    if (alternatives.isEmpty) {
      return cadence ?? _planAudienceLabel(context, card.plan.code);
    }
    return '${cadence ?? _t(context, 'Plan')} · ${alternatives.first}';
  }

  List<_PlanProductAction> _productActionsForCard(
    BuildContext context,
    _PlanDisplayCardData card,
  ) {
    return card.products
        .map((product) {
          final purchaseContext = _purchaseContextForProduct(
            widget.entitlement,
            widget.catalog,
            product,
          );
          final isCurrentPlan = _isCurrentPlan(purchaseContext, product);
          final managedChange = _requiresManagedPlanChange(
            purchaseContext,
            widget.catalog,
            product,
            widget.platformProvider,
          );
          return _PlanProductAction(
            label: _actionLabel(
              context,
              purchaseContext,
              widget.catalog,
              product,
            ),
            detail: _productActionDetail(
              context,
              product,
              priceOverride: _displayPriceForProduct(context, product),
            ),
            isPrimary: product.code == _preferredProduct(card.products).code,
            onPressed: isCurrentPlan || widget.isBusy
                ? null
                : managedChange
                ? () => widget.onManageSubscription(
                    provider: purchaseContext.sourceProvider,
                    managementChannel: purchaseContext.managementChannel,
                  )
                : () => widget.onSelectProduct(product),
          );
        })
        .toList(growable: false);
  }

  _PlanProductAction? _fallbackActionForCard(
    BuildContext context,
    _PlanDisplayCardData card,
    bool planIsCurrent,
  ) {
    if (card.products.isNotEmpty) return null;
    final planCode = card.plan.code.trim().toLowerCase();
    if (planIsCurrent) {
      return _PlanProductAction(
        label: _t(context, 'Current plan'),
        detail: '',
        isPrimary: true,
        onPressed: null,
      );
    }
    if (planCode == 'free') {
      return _PlanProductAction(
        label: _t(context, 'Included'),
        detail: '',
        isPrimary: true,
        onPressed: null,
      );
    }
    final syntheticProduct = _syntheticSalesProductForPlan(card.plan);
    return _PlanProductAction(
      label: _t(context, 'Contact sales'),
      detail: '',
      isPrimary: true,
      onPressed: widget.isBusy
          ? null
          : () => widget.onSelectProduct(syntheticProduct),
    );
  }

  bool _isCurrentPlan(
    _PlanPurchaseContext purchaseContext,
    BillingProductDefinition product,
  ) {
    if (!purchaseContext.isAccessActive || product.type != 'subscription') {
      return false;
    }
    final currentProductCode = purchaseContext.productCode.trim();
    if (currentProductCode.isNotEmpty) {
      return currentProductCode == product.code;
    }
    if (purchaseContext.planCode == product.planCode &&
        product.managementChannel.trim().toLowerCase() == 'web') {
      return true;
    }
    return purchaseContext.planCode == product.planCode &&
        product.billingInterval == 'monthly';
  }

  bool _requiresManagedPlanChange(
    _PlanPurchaseContext purchaseContext,
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
    BillingProvider platformProvider,
  ) {
    if (!purchaseContext.isAccessActive ||
        !purchaseContext.isPaidPlan ||
        product.type != 'subscription') {
      return false;
    }
    if (_isMobileStorePlanChange(purchaseContext, product, platformProvider)) {
      return false;
    }
    if (_isCurrentPlan(purchaseContext, product)) {
      return false;
    }
    return purchaseContext.sourceProvider != platformProvider ||
        !_isPlanUpgrade(purchaseContext, catalog, product);
  }

  bool _isMobileStorePlanChange(
    _PlanPurchaseContext purchaseContext,
    BillingProductDefinition product,
    BillingProvider platformProvider,
  ) {
    if (!purchaseContext.isAccessActive ||
        !purchaseContext.isPaidPlan ||
        product.type != 'subscription' ||
        _isCurrentPlan(purchaseContext, product)) {
      return false;
    }
    return (purchaseContext.sourceProvider == BillingProvider.apple &&
            platformProvider == BillingProvider.apple) ||
        (purchaseContext.sourceProvider == BillingProvider.google &&
            platformProvider == BillingProvider.google);
  }

  bool _isPlanUpgrade(
    _PlanPurchaseContext purchaseContext,
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    if (!purchaseContext.isAccessActive ||
        !purchaseContext.isPaidPlan ||
        product.type != 'subscription') {
      return false;
    }
    if (_isCurrentPlan(purchaseContext, product)) {
      return false;
    }
    final currentRank =
        catalog?.planByCode(purchaseContext.planCode)?.rank ??
        _fallbackPlanRank(purchaseContext.planCode);
    final nextRank =
        catalog?.planByCode(product.planCode)?.rank ??
        _fallbackPlanRank(product.planCode);
    return nextRank > currentRank;
  }

  bool _isPlanDowngrade(
    _PlanPurchaseContext purchaseContext,
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    if (!purchaseContext.isAccessActive ||
        !purchaseContext.isPaidPlan ||
        product.type != 'subscription') {
      return false;
    }
    if (_isCurrentPlan(purchaseContext, product)) {
      return false;
    }
    final currentRank =
        catalog?.planByCode(purchaseContext.planCode)?.rank ??
        _fallbackPlanRank(purchaseContext.planCode);
    final nextRank =
        catalog?.planByCode(product.planCode)?.rank ??
        _fallbackPlanRank(product.planCode);
    return nextRank < currentRank;
  }

  int _fallbackPlanRank(String planCode) {
    switch (planCode.trim().toLowerCase()) {
      case 'starter':
        return 10;
      case 'producer':
        return 20;
      case 'studio':
        return 30;
      case 'enterprise':
        return 40;
      case 'education':
        return 50;
      default:
        return 0;
    }
  }

  String _managePlanChangeLabel(
    BuildContext context,
    _PlanPurchaseContext purchaseContext,
  ) {
    switch (purchaseContext.sourceProvider) {
      case BillingProvider.apple:
      case BillingProvider.google:
        return _t(context, 'Manage plan');
      case BillingProvider.paddle:
      case BillingProvider.toss:
        return _t(context, 'Manage on web');
      case BillingProvider.kakao:
      case BillingProvider.adminGrant:
      case BillingProvider.unknown:
        break;
    }
    final channel = purchaseContext.managementChannel.trim().toLowerCase();
    if (channel == 'web') return _t(context, 'Manage on web');
    if (channel == 'admin') return _t(context, 'Contact sales');
    return _t(context, 'Manage plan');
  }
}

class _PlanPurchaseContext {
  const _PlanPurchaseContext({
    required this.planCode,
    required this.productCode,
    required this.sourceProvider,
    required this.managementChannel,
    required this.isAccessActive,
  });

  final String planCode;
  final String productCode;
  final BillingProvider sourceProvider;
  final String managementChannel;
  final bool isAccessActive;

  bool get isPaidPlan => planCode.trim().toLowerCase() != 'free';
}

class _PlanDisplayCardData {
  const _PlanDisplayCardData({required this.plan, required this.products});

  final BillingPlanDefinition plan;
  final List<BillingProductDefinition> products;
}

class _PlanScrollButton extends StatelessWidget {
  const _PlanScrollButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: icon == Icons.arrow_back_rounded
          ? _t(context, 'Previous')
          : _t(context, 'Next'),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      color: Colors.white.withValues(alpha: 0.82),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.14),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.14),
        minimumSize: const Size(32, 32),
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
      ),
    );
  }
}

class _PlanProductAction {
  const _PlanProductAction({
    required this.label,
    required this.detail,
    required this.isPrimary,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final bool isPrimary;
  final VoidCallback? onPressed;
}

class _PlanMarketingContent {
  const _PlanMarketingContent({
    required this.subtitle,
    required this.tagline,
    required this.sections,
  });

  final String subtitle;
  final String tagline;
  final List<_PlanMarketingSection> sections;
}

class _PlanMarketingSection {
  const _PlanMarketingSection({required this.heading, required this.items});

  final String heading;
  final List<String> items;
}

List<_PlanDisplayCardData> _planDisplayCards(
  BillingCatalogSnapshot? catalog,
  List<BillingProductDefinition> visibleProducts,
) {
  const planOrder = <String>[
    'free',
    'starter',
    'producer',
    'studio',
    'enterprise',
    'education',
  ];
  final productsByPlan = <String, List<BillingProductDefinition>>{};
  for (final product in visibleProducts) {
    // Keep annual products in the catalog for future use, but do not surface
    // them in the Explore More Plans cards until annual billing is available.
    if (_isAnnualBillingProduct(product)) continue;
    final planCode = product.planCode.trim().toLowerCase();
    productsByPlan.putIfAbsent(planCode, () => <BillingProductDefinition>[]);
    productsByPlan[planCode]!.add(product);
  }
  for (final entry in productsByPlan.entries) {
    entry.value.sort((a, b) {
      final rankCompare = a.rank.compareTo(b.rank);
      if (rankCompare != 0) return rankCompare;
      return _billingIntervalSortRank(
        a.billingInterval,
      ).compareTo(_billingIntervalSortRank(b.billingInterval));
    });
  }

  return planOrder
      .map((planCode) {
        final plan = catalog?.planByCode(planCode) ?? _fallbackPlan(planCode);
        return _PlanDisplayCardData(
          plan: plan,
          products: List<BillingProductDefinition>.unmodifiable(
            productsByPlan[planCode] ?? const <BillingProductDefinition>[],
          ),
        );
      })
      .toList(growable: false);
}

bool _isAnnualBillingProduct(BillingProductDefinition product) {
  switch (product.billingInterval.trim().toLowerCase()) {
    case 'yearly':
    case 'annual':
      return true;
    default:
      return false;
  }
}

BillingPlanDefinition _fallbackPlan(String planCode) {
  final normalized = planCode.trim().toLowerCase();
  return BillingPlanDefinition(
    code: normalized,
    label: defaultPlanLabelForCode(normalized),
    group: defaultPlanGroupForCode(normalized),
    rank: _fallbackBillingPlanRank(normalized),
    active: true,
    description: _fallbackPlanDescription(normalized),
    capabilities: defaultCapabilitiesForPlanCode(normalized),
    limits: defaultLimitsForPlanCode(normalized),
  );
}

String _fallbackPlanDescription(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return 'Start ideas anywhere with cross-platform project sync.';
    case 'starter':
      return 'Expanded creation tools, higher-quality export, more storage, and full DAW access.';
    case 'producer':
      return 'The full solo creator suite with advanced AI, high-quality export, and expanded storage.';
    case 'studio':
      return 'Shared project space, team seats, studio tools, and priority support for small teams.';
    case 'enterprise':
      return 'Custom workspace, security, AI models, storage, and support for larger organizations.';
    case 'education':
      return 'Classroom-ready seats, teacher controls, and a safer student creation environment.';
    default:
      return '${defaultPlanLabelForCode(planCode)} plan access.';
  }
}

BillingProductDefinition _syntheticSalesProductForPlan(
  BillingPlanDefinition plan,
) {
  final planCode = plan.code.trim().toLowerCase();
  return BillingProductDefinition(
    code: '${planCode}_sales',
    planCode: planCode,
    type: 'contract',
    billingInterval: 'custom',
    label: '${defaultPlanLabelForCode(planCode)} Sales',
    description: _fallbackPlanDescription(planCode),
    enabled: true,
    managementChannel: 'admin',
    platforms: const <String>[],
    priceDisplay: 'Custom',
    trialDays: 0,
    rank: _fallbackBillingPlanRank(planCode) * 100,
  );
}

BillingProductDefinition _preferredProduct(
  List<BillingProductDefinition> products,
) {
  if (products.isEmpty) {
    throw ArgumentError.value(products, 'products', 'Must not be empty');
  }
  for (final product in products) {
    if (product.billingInterval.trim().toLowerCase() == 'monthly') {
      return product;
    }
  }
  return products.first;
}

String _contactPriceLabel(BuildContext context, String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'enterprise':
    case 'education':
      return _t(context, 'Custom');
    default:
      return _t(context, 'Contact sales');
  }
}

String _fallbackWebsitePriceLabel(
  BuildContext context,
  String planCode, {
  bool useKrw = false,
}) {
  switch (planCode.trim().toLowerCase()) {
    case 'studio':
      if (useKrw) {
        return _formatKrwPrice(
          context,
          amount: 149000,
          billingInterval: 'monthly',
        );
      }
      return '\$100/mo';
    case 'enterprise':
      return '\$1,000+';
    case 'education':
      return _t(context, 'Per seat');
    default:
      return _contactPriceLabel(context, planCode);
  }
}

String _planAudienceLabel(BuildContext context, String planCode) {
  return _t(context, _planMarketingContent(planCode).subtitle);
}

_PlanMarketingContent _planMarketingContent(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return const _PlanMarketingContent(
        subtitle: 'Casual enthusiasts',
        tagline: 'Start on mobile, tablet, or desktop.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'DAW · Storage',
            items: <String>[
              '1 cloud project · sync across devices',
              '10 local projects · 5 tracks per project',
              'Core effects and instruments',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Export',
            items: <String>['16-bit / 44.1 kHz stereo', 'MP3 export'],
          ),
          _PlanMarketingSection(
            heading: 'AI usage',
            items: <String>['Light AI usage', 'Standard AI model'],
          ),
        ],
      );
    case 'starter':
      return const _PlanMarketingContent(
        subtitle: 'Aspiring producers',
        tagline: 'More room to arrange, export, and finish tracks.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'DAW · Storage',
            items: <String>['5 GB cloud', 'No free-tier track or project cap'],
          ),
          _PlanMarketingSection(
            heading: 'Export',
            items: <String>[
              'High-quality export',
              'WAV, MP3, and FLAC formats',
            ],
          ),
          _PlanMarketingSection(
            heading: 'AI usage',
            items: <String>['Expanded AI usage', 'Standard AI model'],
          ),
        ],
      );
    case 'producer':
      return const _PlanMarketingContent(
        subtitle: 'Serious / Professional producers',
        tagline: 'Full production stack with advanced AI and more storage.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'DAW · Storage',
            items: <String>[
              '250 GB cloud',
              'No free-tier track or project cap',
            ],
          ),
          _PlanMarketingSection(
            heading: 'AI usage',
            items: <String>[
              'High-volume AI usage',
              'Advanced reasoning AI options',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Other',
            items: <String>['High-quality export formats', 'Priority support'],
          ),
        ],
      );
    case 'studio':
      return const _PlanMarketingContent(
        subtitle: 'Teams · High-volume pros',
        tagline: 'Producer for everyone on the team.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'Seats',
            items: <String>[
              '5 seats included',
              'Add seats: \$15/seat/mo (\$153/seat/yr)',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Shared storage',
            items: <String>[
              '1 TB shared storage',
              '+1 TB: \$10/mo (does not scale per seat)',
            ],
          ),
          _PlanMarketingSection(
            heading: 'AI & access',
            items: <String>[
              'High-volume AI for every seat',
              'Studio badge on profile',
            ],
          ),
        ],
      );
    case 'enterprise':
      return const _PlanMarketingContent(
        subtitle: 'Large businesses · studios · labels',
        tagline: 'Built for scale and compliance.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'Pricing',
            items: <String>[
              'Starting from \$1,000/mo',
              'Custom pricing · multi-user licensing',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Customization',
            items: <String>[
              'Custom AI model development',
              'API integrations · white-label options',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Support',
            items: <String>['Dedicated account manager', 'DPA · SOC 2 roadmap'],
          ),
        ],
      );
    case 'education':
      return const _PlanMarketingContent(
        subtitle: 'Schools · Teachers · Institutions',
        tagline: 'Classroom licensing with teacher tools.',
        sections: <_PlanMarketingSection>[
          _PlanMarketingSection(
            heading: 'Seat options',
            items: <String>[
              '10 · 20 · 30 seat packages',
              '\$10/seat/mo (parity with Starter)',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Per seat',
            items: <String>[
              'Each seat = Starter-equivalent features',
              '5 GB storage per seat',
            ],
          ),
          _PlanMarketingSection(
            heading: 'Teacher Mode',
            items: <String>[
              'Invite students by email · invite links',
              'Activate / deactivate / reclaim seats',
            ],
          ),
        ],
      );
    default:
      return _PlanMarketingContent(
        subtitle: defaultPlanLabelForCode(planCode),
        tagline: '${defaultPlanLabelForCode(planCode)} plan access.',
        sections: const <_PlanMarketingSection>[],
      );
  }
}

List<String> _planFeatureItems(
  BuildContext context,
  BillingPlanDefinition plan,
) {
  final code = plan.code.trim().toLowerCase();
  final limits = plan.limits;
  final capabilities = plan.capabilities;
  final storage = _formatStorageAmount(limits['storage_gb']);
  final sharedStorage = _formatStorageAmount(limits['shared_storage_gb']);
  final aiUsage = _formatPlanAiUsageFeature(context, code, limits);
  final members = _formatInteger(limits['members']);

  switch (code) {
    case 'free':
      return _compactFeatureItems([
        _t(context, '1 cloud project, sync across devices'),
        _formatDawCapacityFeature(context, code),
        _t(context, 'Core effects and instruments'),
        _t(context, 'MP3 export'),
        _t(context, 'Light AI usage'),
      ]);
    case 'starter':
      return _compactFeatureItems([
        _formatDawCapacityFeature(context, code),
        _t(context, 'All effects and instruments'),
        capabilities['high_quality_export'] == true
            ? _t(context, 'High-quality export in WAV, MP3, and FLAC')
            : _t(context, 'MP3 export'),
        storage == null
            ? null
            : _tr(context, '{storage} cloud storage', {'storage': storage}),
        aiUsage,
      ]);
    case 'producer':
      return _compactFeatureItems([
        _formatDawCapacityFeature(context, code),
        storage == null
            ? null
            : _tr(context, '{storage} cloud storage', {'storage': storage}),
        _t(context, 'All effects and instruments'),
        capabilities['high_quality_export'] == true
            ? _t(context, 'High-quality export in WAV, MP3, and FLAC')
            : null,
        aiUsage,
      ]);
    case 'studio':
      return _compactFeatureItems([
        members == null
            ? null
            : _tr(context, '{count} seats included', {'count': members}),
        sharedStorage == null
            ? null
            : _tr(context, '{storage} shared storage', {
                'storage': sharedStorage,
              }),
        _t(context, 'Producer DAW access for each seat'),
        _t(context, 'Team workspace and priority support'),
      ]);
    case 'enterprise':
      return _compactFeatureItems([
        _t(context, 'Custom seats and storage'),
        capabilities['custom_ai_models'] == true
            ? _t(context, 'Custom AI models')
            : _t(context, 'Custom AI usage'),
        _t(context, 'Team workspace and admin controls'),
        capabilities['compliance_controls'] == true
            ? _t(context, 'Compliance controls + dedicated support')
            : _t(context, 'Dedicated support'),
      ]);
    case 'education':
      return _compactFeatureItems([
        _formatSeatOptions(context, limits['seat_options']),
        _t(context, 'Starter DAW access per seat'),
        storage == null
            ? null
            : _tr(context, '{storage} storage per seat', {'storage': storage}),
        capabilities['education_sandbox'] == true ||
                capabilities['education_visibility_controls'] == true
            ? _t(context, 'Education sandbox + visibility controls')
            : _t(context, 'Starter-level classroom seats'),
      ]);
    default:
      return _compactFeatureItems([
        _formatDawCapacityFeature(context, code),
        storage == null
            ? null
            : _tr(context, '{storage} storage', {'storage': storage}),
        aiUsage,
      ]);
  }
}

List<String> _compactFeatureItems(Iterable<String?> items) {
  return items
      .where((item) => item != null && item.trim().isNotEmpty)
      .map((item) => item!.trim())
      .toList(growable: false);
}

String _formatDawCapacityFeature(BuildContext context, String planCode) {
  final normalized = planCode.trim().toLowerCase();
  if (normalized == 'free') {
    return _tr(context, '{projects} local projects, {tracks} tracks', {
      'projects': SubscriptionLimits.freeLocalProjects,
      'tracks': SubscriptionLimits.freeRowsPerProject,
    });
  }
  return _t(context, 'No free-tier track or project cap');
}

String? _formatSeatOptions(BuildContext context, Object? raw) {
  if (raw is Iterable) {
    final values = raw
        .map((item) => _formatInteger(item))
        .where((item) => item != null && item.trim().isNotEmpty)
        .map((item) => item!)
        .toList(growable: false);
    if (values.isNotEmpty) {
      return _tr(context, '{seats} seat packages', {
        'seats': values.join(' / '),
      });
    }
  }
  return null;
}

String? _formatPlanAiUsageFeature(
  BuildContext context,
  String planCode,
  Map<String, dynamic> limits,
) {
  final tier = (limits['ai_model_tier'] ?? '').toString().trim().toLowerCase();
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return _t(context, 'Light AI usage');
    case 'starter':
    case 'education':
      return _t(context, 'Expanded AI usage');
    case 'producer':
      return _t(context, 'High-volume AI usage');
    case 'studio':
      return _t(context, 'High-volume AI for every seat');
    case 'enterprise':
      return _t(context, 'Custom AI usage');
  }
  return switch (tier) {
    'advanced' => _t(context, 'High-volume advanced AI usage'),
    'custom' => _t(context, 'Custom AI usage'),
    'standard' => _t(context, 'Standard AI usage'),
    _ => null,
  };
}

String? _formatStorageAmount(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return null;
  final normalized = text.toLowerCase();
  if (normalized == 'custom') return 'Custom';
  final value = raw is num ? raw.toDouble() : double.tryParse(text);
  if (value == null || value <= 0) return null;
  if (value < 1) {
    return '${(value * 1000).round()} MB';
  }
  if (value >= 1024) {
    return '${_trimDecimal(value / 1024)} TB';
  }
  return '${_trimDecimal(value)} GB';
}

String? _formatInteger(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return null;
  final normalized = text.toLowerCase();
  if (normalized == 'custom') return 'Custom';
  final value = raw is num ? raw.round() : int.tryParse(text);
  if (value == null) return null;
  return NumberFormat.decimalPattern('en_US').format(value);
}

String _trimDecimal(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _productActionDetail(
  BuildContext context,
  BillingProductDefinition product, {
  String? priceOverride,
}) {
  final cadence = _cadenceLabel(context, product.billingInterval);
  final price = (priceOverride ?? product.priceDisplay).trim();
  if (cadence == null) return price;
  if (price.isEmpty) return cadence;
  return '$cadence · $price';
}

Color _planAccentColor(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return const Color(0xFFB7C7D8);
    case 'starter':
      return const Color(0xFF79B7FF);
    case 'producer':
      return const Color(0xFF8CFFCD);
    case 'studio':
      return const Color(0xFFFFCB73);
    case 'enterprise':
      return const Color(0xFFFF8FCA);
    case 'education':
      return const Color(0xFFC4A7FF);
    default:
      return const Color(0xFFA4C2FF);
  }
}

IconData _planIcon(String planCode) {
  switch (planCode.trim().toLowerCase()) {
    case 'free':
      return Icons.music_note_rounded;
    case 'starter':
      return Icons.bolt_rounded;
    case 'producer':
      return Icons.auto_awesome_rounded;
    case 'studio':
      return Icons.groups_2_rounded;
    case 'enterprise':
      return Icons.apartment_rounded;
    case 'education':
      return Icons.school_rounded;
    default:
      return Icons.workspace_premium_rounded;
  }
}

String _subscriptionStatusLabel(
  BuildContext context,
  SubscriptionStatus status,
) {
  switch (status) {
    case SubscriptionStatus.trialing:
      return _t(context, 'Trial');
    case SubscriptionStatus.active:
      return _t(context, 'Active');
    case SubscriptionStatus.gracePeriod:
      return _t(context, 'Grace');
    case SubscriptionStatus.pastDue:
      return _t(context, 'Past due');
    case SubscriptionStatus.paused:
      return _t(context, 'Paused');
    case SubscriptionStatus.canceled:
      return _t(context, 'Canceled');
    case SubscriptionStatus.expired:
      return _t(context, 'Expired');
    case SubscriptionStatus.refunded:
      return _t(context, 'Refunded');
    case SubscriptionStatus.revoked:
      return _t(context, 'Revoked');
  }
}

String _modelTierReadout(BuildContext context, dynamic value) {
  switch ('$value'.trim().toLowerCase()) {
    case 'advanced':
      return _t(context, 'Advanced model');
    case 'custom':
      return _t(context, 'Custom model access');
    case 'standard':
      return _t(context, 'Standard model');
    default:
      return _t(context, 'Standard model');
  }
}

String _advancedPromptReadout(
  BuildContext context,
  Map<String, dynamic> limits,
) {
  final hasBetter = limits.containsKey('ai_better_prompts_daily');
  final hasPremium = limits.containsKey('ai_premium_prompts_daily');
  if (!hasBetter && !hasPremium) return '';

  if (hasBetter && hasPremium) {
    return _t(context, 'Enhanced + premium AI');
  }
  if (hasBetter) {
    return _t(context, 'Enhanced reasoning');
  }
  return _t(context, 'Premium reasoning');
}

class _PlanRailProgressIndicator extends StatelessWidget {
  const _PlanRailProgressIndicator({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (!controller.hasClients) {
                return const SizedBox.shrink();
              }
              final position = controller.position;
              final totalExtent =
                  position.maxScrollExtent + position.viewportDimension;
              final thumbFraction = totalExtent <= 0
                  ? 1.0
                  : (position.viewportDimension / totalExtent).clamp(0.0, 1.0);
              final thumbWidth = (constraints.maxWidth * thumbFraction).clamp(
                36.0,
                constraints.maxWidth,
              );
              final travel = constraints.maxWidth - thumbWidth;
              final progress = position.maxScrollExtent <= 0
                  ? 0.0
                  : (position.pixels / position.maxScrollExtent).clamp(
                      0.0,
                      1.0,
                    );
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: travel * progress,
                    top: 0,
                    bottom: 0,
                    width: thumbWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PlanListRow extends StatelessWidget {
  const _PlanListRow({
    required this.data,
    required this.planIsCurrent,
    required this.priceLabel,
    required this.billingCaption,
    required this.isBusy,
    required this.productActions,
    required this.fallbackAction,
  });

  final _PlanDisplayCardData data;
  final bool planIsCurrent;
  final String priceLabel;
  final String billingCaption;
  final bool isBusy;
  final List<_PlanProductAction> productActions;
  final _PlanProductAction? fallbackAction;

  @override
  Widget build(BuildContext context) {
    final plan = data.plan;
    final planCode = plan.code.trim().toLowerCase();
    final accent = _planAccentColor(planCode);
    final marketing = _planMarketingContent(planCode);
    final featureItems = _planFeatureItems(context, plan);
    final actions = productActions.isNotEmpty
        ? productActions
        : fallbackAction == null
        ? const <_PlanProductAction>[]
        : <_PlanProductAction>[fallbackAction!];

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: accountGlassDecoration(
        radius: 24,
        strong: planIsCurrent,
        selected: planIsCurrent,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PlanIconBadge(planCode: planCode, accent: accent),
              const Spacer(),
              if (planIsCurrent) const _CurrentPlanCheck(),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            plan.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(context, marketing.tagline),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            priceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            billingCaption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11.4,
              fontWeight: FontWeight.w400,
              height: 1.22,
            ),
          ),
          const SizedBox(height: 16),
          _PlanFeaturePreview(items: featureItems, accent: accent),
          const Spacer(),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PlanInlineActions(actions: actions, isBusy: isBusy),
          ],
        ],
      ),
    );
  }
}

class _PlanIconBadge extends StatelessWidget {
  const _PlanIconBadge({required this.planCode, required this.accent});

  final String planCode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      alignment: Alignment.center,
      child: Icon(_planIcon(planCode), color: accent, size: 17),
    );
  }
}

class _CurrentPlanCheck extends StatelessWidget {
  const _CurrentPlanCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFF123321).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF78E2AA).withValues(alpha: 0.36),
        ),
      ),
      child: const Icon(
        Icons.check_rounded,
        color: Color(0xFFA4FFCA),
        size: 15,
      ),
    );
  }
}

class _PlanFeaturePreview extends StatelessWidget {
  const _PlanFeaturePreview({required this.items, required this.accent});

  final List<String> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items
          .map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _PlanInlineActions extends StatelessWidget {
  const _PlanInlineActions({required this.actions, required this.isBusy});

  final List<_PlanProductAction> actions;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final primary = actions.firstWhere(
      (action) => action.isPrimary,
      orElse: () => actions.first,
    );

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 132, maxWidth: 180),
        child: FilledButton(
          onPressed: isBusy ? null : primary.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: kAccountGlassBlue,
            foregroundColor: kAccountGlassText,
            disabledBackgroundColor: Colors.white.withValues(
              alpha: primary.onPressed == null ? 0.12 : 0.22,
            ),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.44),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            textStyle: const TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            primary.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

_PlanPurchaseContext _purchaseContextForProduct(
  EntitlementSnapshot entitlement,
  BillingCatalogSnapshot? catalog,
  BillingProductDefinition product,
) {
  final planGroup =
      catalog?.planByCode(product.planCode)?.group.trim().toLowerCase() ??
      defaultPlanGroupForCode(product.planCode);
  if (planGroup == 'individual') {
    return _personalPurchaseContext(entitlement);
  }
  return _PlanPurchaseContext(
    planCode: entitlement.planCode,
    productCode: entitlement.productCode,
    sourceProvider: entitlement.sourceProvider,
    managementChannel: entitlement.managementChannel,
    isAccessActive: entitlement.isAccessActive,
  );
}

_PlanPurchaseContext _personalPurchaseContext(EntitlementSnapshot entitlement) {
  AccountAccessSource? source;
  for (final item in entitlement.accessSources) {
    if (item.sourceType.trim().toLowerCase() == 'personal') {
      source = item;
      break;
    }
  }
  if (source == null) {
    if (entitlement.planGroup.trim().toLowerCase() == 'individual') {
      return _PlanPurchaseContext(
        planCode: entitlement.planCode,
        productCode: entitlement.productCode,
        sourceProvider: entitlement.sourceProvider,
        managementChannel: entitlement.managementChannel,
        isAccessActive: entitlement.isAccessActive,
      );
    }
    return const _PlanPurchaseContext(
      planCode: 'free',
      productCode: '',
      sourceProvider: BillingProvider.adminGrant,
      managementChannel: 'free',
      isAccessActive: true,
    );
  }
  return _PlanPurchaseContext(
    planCode: source.planCode,
    productCode: source.productCode,
    sourceProvider: source.sourceProvider,
    managementChannel: source.managementChannel,
    isAccessActive: _accessSourceIsActive(source.status),
  );
}

_AccessDisplay _personalAccessDisplay(
  BuildContext context,
  EntitlementSnapshot entitlement,
) {
  AccountAccessSource? source;
  for (final item in entitlement.accessSources) {
    if (item.sourceType.trim().toLowerCase() == 'personal') {
      source = item;
      break;
    }
  }
  final planCode = source?.planCode.trim().isNotEmpty == true
      ? source!.planCode
      : entitlement.planGroup.trim().toLowerCase() == 'individual'
      ? entitlement.planCode
      : 'free';
  final planLabel = source?.planLabel.trim().isNotEmpty == true
      ? source!.planLabel.trim()
      : entitlement.planGroup.trim().toLowerCase() == 'individual'
      ? entitlement.effectivePlanLabel
      : defaultPlanLabelForCode(planCode);
  final purchaseContext = _personalPurchaseContext(entitlement);
  final actionLabel = _manageActionLabelForContext(context, purchaseContext);
  final entitlementDescribesPersonalPlan =
      entitlement.planGroup.trim().toLowerCase() == 'individual' &&
      entitlement.planCode.trim().toLowerCase() ==
          purchaseContext.planCode.trim().toLowerCase();
  final renewalCopy = entitlementDescribesPersonalPlan
      ? _renewalCopy(context, entitlement)
      : null;
  return _AccessDisplay(
    title: _localizedPlanLabel(
      context,
      planCode: planCode,
      fallback: planLabel,
    ),
    detail:
        renewalCopy ??
        _t(context, 'Applies to your personal cloud and app upgrades'),
    actionLabel: actionLabel,
    actionIcon: _manageActionIconForContext(purchaseContext),
    canManage: actionLabel.isNotEmpty,
    actionProvider: purchaseContext.sourceProvider,
    actionManagementChannel: purchaseContext.managementChannel,
  );
}

bool _accessSourceIsActive(String status) {
  switch (status.trim().toLowerCase()) {
    case 'trialing':
    case 'active':
    case 'grace_period':
      return true;
    default:
      return false;
  }
}

class _TeamAccessSummary extends StatelessWidget {
  const _TeamAccessSummary({
    required this.accessSummary,
    required this.organizations,
    required this.onManageSubscription,
    required this.onOpenEducationDashboard,
  });

  final CollaborationAccessSummary accessSummary;
  final List<OrganizationAccessItem> organizations;
  final ManageSubscriptionAction onManageSubscription;
  final ValueChanged<OrganizationAccessItem> onOpenEducationDashboard;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Team access'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (accessSummary.cloudProjectCount > 0)
                _MetricChip(
                  label: _t(context, 'Cloud projects'),
                  value: accessSummary.cloudProjectCount.toString(),
                ),
            ],
          ),
          if (organizations.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...organizations.map((organization) {
              final isEducation =
                  organization.planCode.trim().toLowerCase() == 'education';
              final isTeacher = {
                'owner',
                'admin',
                'manager',
                'teacher',
              }.contains(organization.role.trim().toLowerCase());
              return _OrganizationAccessRow(
                organization: organization,
                showTeacherLayer: isEducation && isTeacher,
                onManageSubscription: onManageSubscription,
                onOpenEducationDashboard: onOpenEducationDashboard,
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _EducationStudentAccessPanel extends StatelessWidget {
  const _EducationStudentAccessPanel({required this.organization});

  final OrganizationAccessItem organization;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: accountGlassDecoration(radius: 24),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Color(0xFF8DF2C2),
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(context, 'Education access'),
                  style: const TextStyle(
                    color: Colors.white,
                  fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(
                    context,
                    'Active through {organization}. Your seat includes Starter-level Mixroom features.',
                    {'organization': organization.name},
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EducationInviteAcceptPanel extends StatelessWidget {
  const _EducationInviteAcceptPanel({
    required this.controller,
    required this.isBusy,
    required this.message,
    required this.onAccept,
  });

  final TextEditingController controller;
  final bool isBusy;
  final String? message;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: accountGlassDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Education invite'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isBusy,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _t(context, 'Paste invite link or code'),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.36),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                      borderSide: BorderSide(color: kAccountGlassBlue),
                    ),
                  ),
                  onSubmitted: (_) => onAccept(),
                ),
              ),
              const SizedBox(width: 9),
              ElevatedButton(
                onPressed: isBusy ? null : onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccountGlassBlue,
                  foregroundColor: kAccountGlassText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  isBusy ? _t(context, 'Accepting') : _t(context, 'Accept'),
                ),
              ),
            ],
          ),
          if ((message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 11.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EducationTeacherDashboardPage extends StatefulWidget {
  const EducationTeacherDashboardPage({
    super.key,
    required this.entitlementService,
    required this.initialOrganization,
    required this.onRequestSeatChange,
  });

  final EntitlementService entitlementService;
  final OrganizationAccessItem initialOrganization;
  final VoidCallback onRequestSeatChange;

  @override
  State<EducationTeacherDashboardPage> createState() =>
      _EducationTeacherDashboardPageState();
}

class _EducationTeacherDashboardPageState
    extends State<EducationTeacherDashboardPage> {
  final TextEditingController _inviteController = TextEditingController();
  EducationAdminSnapshot? _snapshot;
  bool _loading = true;
  bool _inviteBusy = false;
  int _tabIndex = 0;
  String? _message;
  String? _membershipActionKey;

  @override
  void initState() {
    super.initState();
    _loadEducationAdmin();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _loadEducationAdmin() async {
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }
    try {
      final snapshot = await widget.entitlementService.fetchEducationAdmin();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = _t(context, 'Could not load education admin data.');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _inviteEducationStudent(
    OrganizationAccessItem organization,
  ) async {
    if (_inviteBusy) return;
    final email = _inviteController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _message = _t(context, 'Enter a valid student email.');
      });
      return;
    }
    setState(() {
      _inviteBusy = true;
      _message = null;
    });
    try {
      final result = await widget.entitlementService.inviteEducationStudent(
        organizationId: organization.organizationId,
        email: email,
      );
      final snapshot = await widget.entitlementService.fetchEducationAdmin();
      if (!mounted) return;
      _inviteController.clear();
      final invitedEmail = result.membership?.email.isNotEmpty == true
          ? result.membership!.email
          : email;
      setState(() {
        _snapshot = snapshot;
        _message = result.emailSent
            ? _tr(context, 'Invite email sent to {email}.', {
                'email': invitedEmail,
              })
            : _tr(
                context,
                'Invite created for {email}, but the email could not be sent. Copy the invite link from Students.',
                {'email': invitedEmail},
              );
        if (_tabIndex == 0) _tabIndex = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = _t(
          context,
          'Could not create invite. Check available student seats and try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _inviteBusy = false;
        });
      }
    }
  }

  Future<void> _updateEducationMembership(
    OrganizationAccessItem organization,
    OrganizationMembershipItem membership,
    String status,
  ) async {
    final actionKey =
        '${organization.organizationId}:${membership.userId}:$status';
    if (_membershipActionKey != null || membership.userId.trim().isEmpty) {
      return;
    }
    setState(() {
      _membershipActionKey = actionKey;
      _message = null;
    });
    try {
      await widget.entitlementService.updateEducationMembership(
        organizationId: organization.organizationId,
        userId: membership.userId,
        status: status,
        email: membership.email,
      );
      final snapshot = await widget.entitlementService.fetchEducationAdmin();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _message = switch (status) {
          'active' => _tr(context, 'Student seat restored for {student}.', {
            'student': _educationMembershipLabel(membership),
          }),
          'removed' => _tr(context, 'Removed {student}.', {
            'student': _educationMembershipLabel(membership),
          }),
          'revoked' => _tr(context, 'Invite cancelled for {student}.', {
            'student': _educationMembershipLabel(membership),
          }),
          _ => _t(context, 'Student seat updated.'),
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = _t(context, 'Could not update student seat. Try again.');
      });
    } finally {
      if (mounted) {
        setState(() {
          _membershipActionKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final organization = _currentEducationOrganization(
      _snapshot,
      widget.initialOrganization,
    );
    final memberships =
        (_snapshot?.memberships ?? const <OrganizationMembershipItem>[])
            .where((item) => item.organizationId == organization.organizationId)
            .toList(growable: false);
    final studentMemberships = memberships
        .where((item) => item.role.trim().toLowerCase() == 'student')
        .toList(growable: false);
    final studentUsage =
        (_snapshot?.studentUsage ?? const <EducationStudentUsageItem>[])
            .where((item) => item.organizationId == organization.organizationId)
            .toList(growable: false);
    final activeCount = studentMemberships
        .where((item) => item.status.trim().toLowerCase() == 'active')
        .length;
    final invitedCount = studentMemberships
        .where((item) => item.status.trim().toLowerCase() == 'pending')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF070B10),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EducationDashboardHeader(
                      organization: organization,
                      onBack: () => Navigator.of(context).maybePop(),
                      onRefresh: _loadEducationAdmin,
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in [
                            _t(context, 'Overview'),
                            _t(context, 'Students'),
                            _t(context, 'Student seats'),
                            _t(context, 'Billing'),
                            _t(context, 'Settings'),
                          ].asMap().entries) ...[
                            _EducationTabButton(
                              label: entry.value,
                              selected: _tabIndex == entry.key,
                              onTap: () => setState(() {
                                _tabIndex = entry.key;
                              }),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      _LoadingPlansCard(
                        message: _t(context, 'Loading education dashboard...'),
                      )
                    else
                      _buildBody(
                        organization: organization,
                        memberships: studentMemberships,
                        studentUsage: studentUsage,
                        activeCount: activeCount,
                        invitedCount: invitedCount,
                      ),
                    if ((_message ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _EducationDashboardNotice(message: _message!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required OrganizationAccessItem organization,
    required List<OrganizationMembershipItem> memberships,
    required List<EducationStudentUsageItem> studentUsage,
    required int activeCount,
    required int invitedCount,
  }) {
    switch (_tabIndex) {
      case 1:
        return _EducationStudentsPane(
          organization: organization,
          memberships: memberships,
          studentUsage: studentUsage,
          actionKey: _membershipActionKey,
          onMembershipStatusChange: _updateEducationMembership,
        );
      case 2:
        return _EducationSeatsPane(
          organization: organization,
          activeCount: activeCount,
          invitedCount: invitedCount,
        );
      case 3:
        return _EducationSimplePane(
          title: _t(context, 'Education billing'),
          body: _tr(
            context,
            'Current plan: Education {count} student seats. Teacher/admin access is included separately. Seat changes are handled by the Mixroom team.',
            {'count': organization.seatLimit},
          ),
          actionLabel: _t(context, 'Request student seats'),
          onAction: widget.onRequestSeatChange,
        );
      case 4:
        return _EducationSimplePane(
          title: _t(context, 'Settings'),
          body: _t(
            context,
            'Education sandbox and classroom visibility controls are enabled for this account.',
          ),
          actionLabel: _t(context, 'Refresh'),
          onAction: _loadEducationAdmin,
        );
      case 0:
      default:
        return Column(children: [
          _EducationClassInvitePanel(service: widget.entitlementService, organizationId: organization.organizationId),
          const SizedBox(height: 14),
          _EducationDashboardOverviewPane(
          organization: organization,
          memberships: memberships,
          studentUsage: studentUsage,
          activeCount: activeCount,
          invitedCount: invitedCount,
          emailController: _inviteController,
          isBusy: _inviteBusy,
          onInvite: () => _inviteEducationStudent(organization),
        ),
        ]);
    }
  }
}

class _EducationClassInvitePanel extends StatefulWidget {
  const _EducationClassInvitePanel({required this.service, required this.organizationId});
  final EntitlementService service;
  final String organizationId;
  @override
  State<_EducationClassInvitePanel> createState() => _EducationClassInvitePanelState();
}

class _EducationClassInvitePanelState extends State<_EducationClassInvitePanel> {
  String _link = '';
  String? _message;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _updateLink('get');
  }
  Future<void> _updateLink(String action) async {
    setState(() { _busy = true; _message = null; });
    try {
      final result = await widget.service.educationClassLink(organizationId: widget.organizationId, action: action);
      if (!mounted) return;
      setState(() {
        _link = result['invite_url']?.toString() ?? '';
        if (action == 'revoke') _message = _t(context, 'Class link revoked.');
      });
    } catch (_) {
      if (mounted) setState(() { _message = _t(context, 'Could not update class link.'); });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }
  @override
  Widget build(BuildContext context) => _EducationPanelShell(
    title: _t(context, 'Class invite link'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_t(context, 'Anyone with this link can join while seats are available.'), style: const TextStyle(color: kAccountGlassMutedText)),
      if (_link.isNotEmpty) ...[
        const SizedBox(height: 10),
        SelectableText(_link, style: const TextStyle(color: kAccountGlassText)),
      ],
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        if (_link.isEmpty) OutlinedButton(onPressed: _busy ? null : () => _updateLink('create'), child: Text(_t(context, 'Generate class link'))),
        if (_link.isNotEmpty) ...[
          OutlinedButton(onPressed: _busy ? null : () async {
            try {
              await Clipboard.setData(ClipboardData(text: _link));
              if (mounted) setState(() { _message = _t(context, 'Class link copied.'); });
            } catch (_) {
              if (mounted) setState(() { _message = _t(context, 'Select and copy the link above.'); });
            }
          }, child: Text(_t(context, 'Copy link'))),
          TextButton(onPressed: _busy ? null : () => _updateLink('revoke'), child: Text(_t(context, 'Revoke link'))),
        ],
        if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (_message != null) Text(_message!, style: const TextStyle(color: kAccountGlassMutedText)),
    ]),
  );
}

OrganizationAccessItem _currentEducationOrganization(
  EducationAdminSnapshot? snapshot,
  OrganizationAccessItem fallback,
) {
  for (final organization
      in snapshot?.organizations ?? const <OrganizationAccessItem>[]) {
    if (organization.organizationId == fallback.organizationId) {
      return organization;
    }
  }
  return fallback;
}

class _EducationTabButton extends StatelessWidget {
  const _EducationTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF7FD4FF).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.72),
            fontSize: 11.6,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EducationDashboardHeader extends StatelessWidget {
  const _EducationDashboardHeader({
    required this.organization,
    required this.onBack,
    required this.onRefresh,
  });

  final OrganizationAccessItem organization;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final seatText = organization.seatLimit > 0
        ? _tr(context, '{used} / {limit} student seats', {
            'used': organization.seatsUsed,
            'limit': organization.seatLimit,
          })
        : _tr(context, '{count} student seats used', {
            'count': organization.seatsUsed,
          });
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                tooltip: _t(context, 'Back'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(context, 'Education dashboard'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontSize: 12.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      organization.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                color: Colors.white.withValues(alpha: 0.82),
                tooltip: _t(context, 'Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyBadge(
                label: _localizedRoleLabel(context, organization.role),
              ),
              _TinyBadge(label: seatText),
              _TinyBadge(label: _t(context, 'Student seats only')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EducationDashboardNotice extends StatelessWidget {
  const _EducationDashboardNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: accountGlassDecoration(radius: 18),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 12.2,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _EducationDashboardOverviewPane extends StatelessWidget {
  const _EducationDashboardOverviewPane({
    required this.organization,
    required this.memberships,
    required this.studentUsage,
    required this.activeCount,
    required this.invitedCount,
    required this.emailController,
    required this.isBusy,
    required this.onInvite,
  });

  final OrganizationAccessItem organization;
  final List<OrganizationMembershipItem> memberships;
  final List<EducationStudentUsageItem> studentUsage;
  final int activeCount;
  final int invitedCount;
  final TextEditingController emailController;
  final bool isBusy;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final projectCount = studentUsage.fold<int>(
      0,
      (sum, usage) => sum + usage.projectCount,
    );
    final studentsWithProjects = studentUsage
        .where((usage) => usage.projectCount > 0)
        .length;
    final releasedCount = memberships
        .where(
          (item) => {
            'inactive',
            'revoked',
            'removed',
          }.contains(item.status.trim().toLowerCase()),
        )
        .length;
    final recentlyActiveCount = studentUsage
        .where(
          (usage) =>
              usage.lastActiveAt != null &&
              usage.lastActiveAt!.isAfter(
                DateTime.now().toUtc().subtract(const Duration(days: 7)),
              ),
        )
        .length;
    final lastActivity = _latestStudentActivity(studentUsage);
    final seatUtilization = organization.seatLimit > 0
        ? organization.seatsUsed / organization.seatLimit
        : 0.0;
    final activationRate = memberships.isEmpty
        ? 0.0
        : activeCount / memberships.length;
    final averageProjects = activeCount == 0 ? 0.0 : projectCount / activeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.32,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _EducationMetricCard(
              label: _t(context, 'Active students'),
              value: '$activeCount',
              detail: _tr(context, '{count} pending invites', {
                'count': invitedCount,
              }),
              icon: Icons.school_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Available student seats'),
              value: '${organization.seatsAvailable}',
              detail: _tr(context, '{used} of {limit} student seats', {
                'used': organization.seatsUsed,
                'limit': organization.seatLimit,
              }),
              icon: Icons.event_seat_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Class projects'),
              value: '$projectCount',
              detail: _tr(context, '{count} students have projects', {
                'count': studentsWithProjects,
              }),
              icon: Icons.library_music_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Recent activity'),
              value: '$recentlyActiveCount',
              detail: lastActivity == null
                  ? _t(context, 'No recent activity')
                  : _tr(context, 'Last class activity {date}', {
                      'date': DateFormat(
                        'MMM d',
                      ).format(lastActivity.toLocal()),
                    }),
              icon: Icons.insights_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _EducationInsightPanel(
          title: _t(context, 'Student activity'),
          rows: [
            _EducationInsightRowData(
              label: _t(context, 'Student seat utilization'),
              value: _percentText(seatUtilization),
              progress: seatUtilization,
            ),
            _EducationInsightRowData(
              label: _t(context, 'Activated students'),
              value: _percentText(activationRate),
              progress: activationRate,
            ),
            _EducationInsightRowData(
              label: _t(context, 'Average projects per active student'),
              value: averageProjects.toStringAsFixed(1),
              progress: (averageProjects / 5).clamp(0.0, 1.0),
            ),
            _EducationInsightRowData(
              label: _t(context, 'Released student seats'),
              value: '$releasedCount',
              progress: memberships.isEmpty
                  ? 0.0
                  : (releasedCount / memberships.length).clamp(0.0, 1.0),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _EducationPanelShell(
          title: _t(context, 'Invite student'),
          child: _EducationInviteRow(
            controller: emailController,
            isBusy: isBusy,
            onInvite: onInvite,
          ),
        ),
      ],
    );
  }
}

class _EducationMetricCard extends StatelessWidget {
  const _EducationMetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: accountGlassDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kAccountGlassText, size: 18),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.46),
              fontSize: 10.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EducationInsightRowData {
  const _EducationInsightRowData({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;
}

class _EducationInsightPanel extends StatelessWidget {
  const _EducationInsightPanel({required this.title, required this.rows});

  final String title;
  final List<_EducationInsightRowData> rows;

  @override
  Widget build(BuildContext context) {
    return _EducationPanelShell(
      title: title,
      child: Column(
        children: [
          for (final row in rows) ...[
            _EducationInsightRow(row: row),
            if (row != rows.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _EducationInsightRow extends StatelessWidget {
  const _EducationInsightRow({required this.row});

  final _EducationInsightRowData row;

  @override
  Widget build(BuildContext context) {
    final progress = row.progress.clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 12.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              row.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.2,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7FD4FF)),
          ),
        ),
      ],
    );
  }
}

class _EducationPanelShell extends StatelessWidget {
  const _EducationPanelShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: accountGlassDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.0,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

DateTime? _latestStudentActivity(List<EducationStudentUsageItem> usage) {
  DateTime? latest;
  for (final item in usage) {
    final value = item.lastActiveAt;
    if (value == null) continue;
    if (latest == null || value.isAfter(latest)) {
      latest = value;
    }
  }
  return latest;
}

String _percentText(double value) {
  return '${(value.clamp(0.0, 1.0) * 100).round()}%';
}

class _EducationInviteRow extends StatelessWidget {
  const _EducationInviteRow({
    required this.controller,
    required this.isBusy,
    required this.onInvite,
  });

  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isBusy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: _t(context, 'student@example.com'),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.36)),
              isDense: true,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: kAccountGlassBlue),
              ),
            ),
            onSubmitted: (_) => onInvite(),
          ),
        ),
        const SizedBox(width: 9),
        ElevatedButton(
          onPressed: isBusy ? null : onInvite,
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccountGlassBlue,
            foregroundColor: kAccountGlassText,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(isBusy ? _t(context, 'Inviting') : _t(context, 'Invite')),
        ),
      ],
    );
  }
}

class _EducationStudentsPane extends StatelessWidget {
  const _EducationStudentsPane({
    required this.organization,
    required this.memberships,
    required this.studentUsage,
    required this.actionKey,
    required this.onMembershipStatusChange,
  });

  final OrganizationAccessItem organization;
  final List<OrganizationMembershipItem> memberships;
  final List<EducationStudentUsageItem> studentUsage;
  final String? actionKey;
  final void Function(
    OrganizationAccessItem organization,
    OrganizationMembershipItem membership,
    String status,
  )
  onMembershipStatusChange;

  @override
  Widget build(BuildContext context) {
    final visible = memberships
        .where((item) => item.role.trim().toLowerCase() == 'student')
        .toList(growable: false);
    if (visible.isEmpty) {
      return _EducationSimplePane(
        title: _t(context, 'Students'),
        body: _t(context, 'No students invited yet.'),
      );
    }
    return Column(
      children: visible
          .map((membership) {
            final label = membership.email.isNotEmpty
                ? membership.email
                : membership.userId;
            return _EducationStudentRow(
              organization: organization,
              membership: membership,
              usage: _usageForMembership(studentUsage, membership),
              label: label,
              actionKey: actionKey,
              onMembershipStatusChange: onMembershipStatusChange,
            );
          })
          .toList(growable: false),
    );
  }
}

EducationStudentUsageItem? _usageForMembership(
  List<EducationStudentUsageItem> usage,
  OrganizationMembershipItem membership,
) {
  for (final item in usage) {
    if (item.userId == membership.userId) return item;
  }
  final email = membership.email.trim().toLowerCase();
  if (email.isEmpty) return null;
  for (final item in usage) {
    if (item.email.trim().toLowerCase() == email) return item;
  }
  return null;
}

class _EducationStudentRow extends StatelessWidget {
  const _EducationStudentRow({
    required this.organization,
    required this.membership,
    required this.usage,
    required this.label,
    required this.actionKey,
    required this.onMembershipStatusChange,
  });

  final OrganizationAccessItem organization;
  final OrganizationMembershipItem membership;
  final EducationStudentUsageItem? usage;
  final String label;
  final String? actionKey;
  final void Function(
    OrganizationAccessItem organization,
    OrganizationMembershipItem membership,
    String status,
  )
  onMembershipStatusChange;

  @override
  Widget build(BuildContext context) {
    final status = membership.status.trim().toLowerCase();
    final nextStatus = switch (status) {
      'pending' => 'revoked',
      'active' => 'removed',
      'inactive' || 'revoked' || 'removed' => 'active',
      _ => '',
    };
    final actionLabel = switch (status) {
      'pending' => _t(context, 'Cancel invite'),
      'active' => _t(context, 'Remove'),
      'inactive' ||
      'revoked' ||
      'removed' => _t(context, 'Restore student seat'),
      _ => '',
    };
    final currentActionKey =
        '${organization.organizationId}:${membership.userId}:$nextStatus';
    final isBusy = actionKey == currentActionKey;
    final canAct = nextStatus.isNotEmpty && actionKey == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: accountGlassDecoration(radius: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _educationStudentSubtitle(context, membership, usage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _TinyBadge(label: _membershipStatusLabel(context, membership.status)),
          if (status == 'pending' && membership.inviteUrl.trim().isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: membership.inviteUrl));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(_t(context, 'Invite link copied.'))),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.82),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_t(context, 'Copy link')),
            ),
          if (actionLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: canAct
                  ? () => onMembershipStatusChange(
                      organization,
                      membership,
                      nextStatus,
                    )
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.82),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isBusy ? _t(context, 'Updating') : actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

String _educationStudentSubtitle(
  BuildContext context,
  OrganizationMembershipItem membership,
  EducationStudentUsageItem? usage,
) {
  final status = membership.status.trim().toLowerCase();
  if (status == 'active' && usage != null) {
    final projects = usage.projectCount == 1
        ? _t(context, '1 project')
        : _tr(context, '{count} projects', {'count': usage.projectCount});
    final lastActive = usage.lastActiveAt;
    if (lastActive != null) {
      return _tr(context, '{projects} • last active {date}', {
        'projects': projects,
        'date': DateFormat('MMM d').format(lastActive.toLocal()),
      });
    }
    return projects;
  }
  final date = switch (status) {
    'active' => membership.activatedAt,
    'pending' => membership.invitedAt,
    'removed' || 'revoked' || 'inactive' => membership.releasedAt,
    _ => membership.updatedAt,
  };
  if (date == null) {
    return switch (status) {
      'pending' => _t(context, 'Invite pending'),
      'active' => _t(context, 'Student seat active'),
      'removed' ||
      'revoked' ||
      'inactive' => _t(context, 'Student seat released'),
      _ => _t(context, 'Student seat'),
    };
  }
  final formatted = DateFormat('MMM d').format(date.toLocal());
  return switch (status) {
    'pending' => _tr(context, 'Invited {date}', {'date': formatted}),
    'active' => _tr(context, 'Active since {date}', {'date': formatted}),
    'removed' ||
    'revoked' ||
    'inactive' => _tr(context, 'Released {date}', {'date': formatted}),
    _ => _tr(context, 'Updated {date}', {'date': formatted}),
  };
}

String _membershipStatusLabel(BuildContext context, String status) {
  switch (status.trim().toLowerCase()) {
    case 'pending':
      return _t(context, 'Pending');
    case 'active':
      return _t(context, 'Active');
    case 'inactive':
      return _t(context, 'Inactive');
    case 'revoked':
      return _t(context, 'Revoked');
    case 'removed':
      return _t(context, 'Removed');
    default:
      return _t(context, status);
  }
}

class _EducationSeatsPane extends StatelessWidget {
  const _EducationSeatsPane({
    required this.organization,
    required this.activeCount,
    required this.invitedCount,
  });

  final OrganizationAccessItem organization;
  final int activeCount;
  final int invitedCount;

  @override
  Widget build(BuildContext context) {
    return _EducationSimplePane(
      title: _t(context, 'Student seats'),
      body: _tr(
        context,
        'Student seats used: {used} / {limit}. Active: {active}. Invited: {invited}. Available: {available}.',
        {
          'used': organization.seatsUsed,
          'limit': organization.seatLimit,
          'active': activeCount,
          'invited': invitedCount,
          'available': organization.seatsAvailable,
        },
      ),
    );
  }
}

class _EducationSimplePane extends StatelessWidget {
  const _EducationSimplePane({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: accountGlassDecoration(radius: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _OrganizationAccessRow extends StatelessWidget {
  const _OrganizationAccessRow({
    required this.organization,
    required this.showTeacherLayer,
    required this.onManageSubscription,
    required this.onOpenEducationDashboard,
  });

  final OrganizationAccessItem organization;
  final bool showTeacherLayer;
  final ManageSubscriptionAction onManageSubscription;
  final ValueChanged<OrganizationAccessItem> onOpenEducationDashboard;

  @override
  Widget build(BuildContext context) {
    final seatText = organization.seatLimit > 0
        ? _tr(context, '{used} / {limit} seats', {
            'used': organization.seatsUsed,
            'limit': organization.seatLimit,
          })
        : _tr(context, '{count} seats used', {'count': organization.seatsUsed});
    final roleReadout = _membershipRoleReadout(context, organization.role);
    final canManage = {
      'owner',
      'admin',
      'manager',
      'teacher',
    }.contains(organization.role.trim().toLowerCase());
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  organization.name,
                  style: const TextStyle(
                    color: Colors.white,
                  fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _TinyBadge(
                label: _localizedPlanLabel(
                  context,
                  planCode: organization.planCode,
                  fallback: organization.planLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$seatText • $roleReadout',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showTeacherLayer) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t(
                      context,
                      'Open the teacher dashboard to invite students, review student seat usage, and monitor class activity.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => onOpenEducationDashboard(organization),
                  child: Text(_t(context, 'View Dashboard')),
                ),
              ],
            ),
          ] else if (canManage) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t(
                      context,
                      'Seat and billing management opens on mixroom.ai/account.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => onManageSubscription(
                    provider: BillingProvider.unknown,
                    managementChannel: 'web',
                  ),
                  child: Text(_t(context, 'Manage on web')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 11.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuietActionButton extends StatelessWidget {
  const _QuietActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.66),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LoadingPlansCard extends StatelessWidget {
  const _LoadingPlansCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: accountGlassDecoration(radius: 24),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12.3,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _manageActionLabelForContext(
  BuildContext buildContext,
  _PlanPurchaseContext context,
) {
  if (!context.isAccessActive || !context.isPaidPlan) {
    return '';
  }
  switch (context.sourceProvider) {
    case BillingProvider.apple:
      return _t(buildContext, 'Manage in App Store');
    case BillingProvider.google:
      return _t(buildContext, 'Manage in Google Play');
    case BillingProvider.paddle:
    case BillingProvider.toss:
      return _t(buildContext, 'Manage on web');
    case BillingProvider.kakao:
    case BillingProvider.adminGrant:
    case BillingProvider.unknown:
      break;
  }
  final channel = context.managementChannel.trim().toLowerCase();
  if (channel == 'web') return _t(buildContext, 'Manage on web');
  if (channel == 'in_app') return _t(buildContext, 'Manage plan');
  return '';
}

IconData _manageActionIconForContext(_PlanPurchaseContext context) {
  switch (context.sourceProvider) {
    case BillingProvider.apple:
    case BillingProvider.google:
      return Icons.storefront_rounded;
    case BillingProvider.paddle:
    case BillingProvider.toss:
      return Icons.language_rounded;
    case BillingProvider.kakao:
    case BillingProvider.adminGrant:
    case BillingProvider.unknown:
      break;
  }
  final channel = context.managementChannel.trim().toLowerCase();
  if (channel == 'web') return Icons.language_rounded;
  return Icons.open_in_new_rounded;
}

bool _isTossOneTimeBilling(BillingAccountSnapshot billing) {
  final reason = billing.providerManagementReason.trim().toLowerCase();
  return billing.provider == BillingProvider.toss &&
      (reason == 'toss_one_time_payment' ||
          (billing.nextBilledAt == null &&
              billing.expiresAt != null &&
              !billing.providerManagementConfigured));
}

String? _renewalCopy(BuildContext context, EntitlementSnapshot entitlement) {
  if (entitlement.isAccessActive) {
    final nextBilledAt = entitlement.nextBilledAt;
    if (entitlement.sourceProvider == BillingProvider.toss &&
        nextBilledAt == null &&
        entitlement.expiresAt != null) {
      final date = _formatDate(entitlement.expiresAt!);
      return _tr(context, 'Access ends on {date}.', {'date': date});
    }
    if (nextBilledAt == null) {
      return null;
    }
    final date = _formatDate(nextBilledAt);
    return _tr(context, 'Renews on {date}.', {'date': date});
  }
  final expiresAt = entitlement.expiresAt;
  if (expiresAt == null) {
    return null;
  }
  final date = _formatDate(expiresAt);
  return _tr(context, 'Access ended on {date}.', {'date': date});
}

String? _cadenceLabel(BuildContext context, String interval) {
  switch (interval.trim().toLowerCase()) {
    case 'monthly':
      return _t(context, 'Monthly');
    case 'yearly':
      return _t(context, 'Annual');
    case 'daily':
      return _t(context, 'Daily');
    case 'one_time':
      return _t(context, 'One-time');
    default:
      return null;
  }
}

String _formatDate(DateTime value) {
  return DateFormat.yMMMd().format(value.toLocal());
}
