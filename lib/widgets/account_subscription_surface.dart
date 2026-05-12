import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/entitlement_models.dart';

typedef ManageSubscriptionAction = void Function({
  BillingProvider? provider,
  String? managementChannel,
});

String _t(BuildContext context, String key) => L10n.translate(context, key);

String _tr(
  BuildContext context,
  String key,
  Map<String, Object> values,
) {
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
    final rankCompare = _billingProductSortRank(catalog, a)
        .compareTo(_billingProductSortRank(catalog, b));
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
  final planRank = catalog.planByCode(product.planCode)?.rank ??
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
    final entitlement = widget.entitlementService.entitlement ??
        EntitlementSnapshot.free(userId: '');
    final catalog = widget.entitlementService.billingCatalog;
    final accessSummary = widget.entitlementService.effectiveAccessSummary;
    final products = _visibleBillingProducts(catalog, widget.platformKey);
    final busy = widget.isActionBusy || widget.iapService.isPurchaseInProgress;
    final debugMessages = _debugMessages();
    final studentEducationOrganizations = widget
        .entitlementService.effectiveOrganizations
        .where(_isEducationStudentOrganization)
        .toList(growable: false);

    return _SectionCard(
      icon: Icons.workspace_premium_rounded,
      title: _t(context, 'Plan & Billing'),
      subtitle: _t(context, 'Manage your current plan and available upgrades.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kDebugMode && debugMessages.isNotEmpty) ...[
            _DebugBanner(messages: debugMessages),
            const SizedBox(height: 12),
          ],
          _PlanHero(
            entitlement: entitlement,
            organizations: widget.entitlementService.effectiveOrganizations,
            isBusy: busy,
            onManageSubscription: widget.onManageSubscription,
          ),
          const SizedBox(height: 12),
          _BillingActions(
            isBusy: busy,
            isRefreshing: widget.entitlementService.isAccountSurfaceLoading,
            onRestorePurchases: widget.onRestorePurchases,
            onContactSupport: widget.onContactSupport,
            onRefresh: widget.onRefresh,
          ),
          const SizedBox(height: 14),
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
              organizations: widget.entitlementService.effectiveOrganizations,
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
    );
  }

  Future<void> _acceptEducationInvite() async {
    if (_educationAcceptBusy) return;
    final token =
        _educationInviteTokenFromInput(_educationAcceptController.text);
    if (token.isEmpty) {
      setState(() {
        _educationAcceptMessage =
            _t(context, 'Paste a valid education invite link.');
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
        _educationAcceptMessage =
            _t(context, 'Education student seat activated.');
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

  List<String> _debugMessages() {
    if (!kDebugMode) {
      return const <String>[];
    }
    final values = <String>[];
    void add(String? message) {
      final normalized = (message ?? '').trim();
      if (normalized.isEmpty || values.contains(normalized)) {
        return;
      }
      values.add(normalized);
    }

    add(widget.inlineMessage);
    add(widget.iapService.lastMessage);
    add(widget.entitlementService.lastError);
    add(widget.entitlementService.accountSurfaceError);
    add(widget.iapService.lastError);
    return values;
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
  return {'owner', 'admin', 'manager', 'teacher'}
      .contains(organization.role.trim().toLowerCase());
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D7FFF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: const Color(0xFF82B5FF).withValues(alpha: 0.22),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: const Color(0xFFA4C2FF), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DebugBanner extends StatelessWidget {
  const _DebugBanner({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB84D).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFC56D).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Debug only'),
            style: const TextStyle(
              color: Color(0xFFFFD48A),
              fontSize: 11.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...messages.map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.6,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanHero extends StatelessWidget {
  const _PlanHero({
    required this.entitlement,
    required this.organizations,
    required this.isBusy,
    required this.onManageSubscription,
  });

  final EntitlementSnapshot entitlement;
  final List<OrganizationAccessItem> organizations;
  final bool isBusy;
  final ManageSubscriptionAction onManageSubscription;

  @override
  Widget build(BuildContext context) {
    return _AccessOverview(
      entitlement: entitlement,
      organizations: organizations,
      isBusy: isBusy,
      onManageSubscription: onManageSubscription,
    );
  }
}

class _AccessOverview extends StatelessWidget {
  const _AccessOverview({
    required this.entitlement,
    required this.organizations,
    required this.isBusy,
    required this.onManageSubscription,
  });

  final EntitlementSnapshot entitlement;
  final List<OrganizationAccessItem> organizations;
  final bool isBusy;
  final ManageSubscriptionAction onManageSubscription;

  @override
  Widget build(BuildContext context) {
    final personal = _personalAccessDisplay(context, entitlement);
    final activeOrganizations = _activeTeamOrganizations(organizations);
    return Column(
      children: [
        _AccessOverviewRow(
          icon: Icons.person_rounded,
          label: _t(context, 'Personal plan'),
          value: personal.title,
          detail: personal.detail,
          actionLabel: personal.actionLabel,
          actionIcon: personal.actionIcon,
          onActionPressed: personal.canManage && !isBusy
              ? () => onManageSubscription(
                    provider: personal.actionProvider,
                    managementChannel: personal.actionManagementChannel,
                  )
              : null,
        ),
        for (final organization in activeOrganizations) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final teamAction = _teamAccessAction(organization);
              return _AccessOverviewRow(
                icon: _teamAccessIcon(organization),
                label: _t(context, 'Team access'),
                value: _teamAccessTitle(context, organization),
                detail: _teamAccessDetail(context, organization),
                actionLabel: teamAction.actionLabel.isEmpty
                    ? ''
                    : _t(context, teamAction.actionLabel),
                actionIcon: teamAction.actionIcon,
                onActionPressed: teamAction.canManage && !isBusy
                    ? () => onManageSubscription(
                          provider: teamAction.actionProvider,
                          managementChannel: teamAction.actionManagementChannel,
                        )
                    : null,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _AccessOverviewRow extends StatelessWidget {
  const _AccessOverviewRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.actionLabel,
    required this.actionIcon,
    required this.onActionPressed,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: const Color(0xFFBFD7FF), size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.4,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                    ),
                    if (detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11.4,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onActionPressed,
                icon: Icon(actionIcon, size: 15),
                label: Text(actionLabel),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
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
            if (kDebugMode)
              _QuietActionButton(
                label: isRefreshing || isBusy
                    ? _t(context, 'Refreshing')
                    : _t(context, 'Refresh'),
                icon: Icons.refresh_rounded,
                onPressed: isRefreshing || isBusy ? null : onRefresh,
              ),
          ],
        ),
      ],
    );
  }
}

class _PlansPanel extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _LoadingPlansCard(
        message: catalog == null
            ? _t(context, 'Plans are loading.')
            : _t(context, 'No plans are currently available for this device.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubsectionLabel(label: _t(context, 'Available plans')),
        const SizedBox(height: 10),
        ...products.map(
          (product) {
            final purchaseContext = _purchaseContextForProduct(
              entitlement,
              catalog,
              product,
            );
            final isCurrentPlan = _isCurrentPlan(purchaseContext, product);
            final managedChange = _requiresManagedPlanChange(
              purchaseContext,
              catalog,
              product,
              platformProvider,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProductCard(
                product: product,
                plan: catalog?.planByCode(product.planCode),
                storePrice: _storePriceForProduct(catalog, product),
                actionLabel: _actionLabel(
                  context,
                  purchaseContext,
                  catalog,
                  product,
                ),
                isCurrentPlan: isCurrentPlan,
                isBusy: isBusy,
                onPressed: isBusy
                    ? null
                    : managedChange
                        ? () => onManageSubscription(
                              provider: purchaseContext.sourceProvider,
                              managementChannel:
                                  purchaseContext.managementChannel,
                            )
                        : () => onSelectProduct(product),
              ),
            );
          },
        ),
      ],
    );
  }

  String? _storePriceForProduct(
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    final providerProduct = catalog?.bestProviderProductForProduct(
      productCode: product.code,
      provider: platformProvider,
      regionCode: regionCode,
    );
    if (providerProduct == null) {
      return null;
    }
    return iapService.findProductById(providerProduct.providerProductId)?.price;
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
      platformProvider,
    )) {
      return _managePlanChangeLabel(context, purchaseContext);
    }
    if (_isPlanUpgrade(purchaseContext, catalog, product)) {
      return _t(context, 'Upgrade');
    }
    if (_isPlanDowngrade(purchaseContext, catalog, product) &&
        _isMobileStorePlanChange(purchaseContext, product, platformProvider)) {
      return _t(context, 'Change plan');
    }
    if (_isMobileStorePlanChange(purchaseContext, product, platformProvider)) {
      return _t(context, 'Change plan');
    }
    final providerProduct = catalog?.bestProviderProductForProduct(
      productCode: product.code,
      provider: platformProvider,
      regionCode: regionCode,
    );
    if (product.managementChannel.trim().toLowerCase() == 'web') {
      return _t(context, 'Buy on web');
    }
    return providerProduct != null
        ? _t(context, 'Choose plan')
        : _t(context, 'Open checkout');
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
    final currentRank = catalog?.planByCode(purchaseContext.planCode)?.rank ??
        _fallbackPlanRank(purchaseContext.planCode);
    final nextRank = catalog?.planByCode(product.planCode)?.rank ??
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
    final currentRank = catalog?.planByCode(purchaseContext.planCode)?.rank ??
        _fallbackPlanRank(purchaseContext.planCode);
    final nextRank = catalog?.planByCode(product.planCode)?.rank ??
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
    detail: renewalCopy ??
        _t(context, 'Applies to your personal cloud and app upgrades'),
    actionLabel: actionLabel,
    actionIcon: _manageActionIconForContext(purchaseContext),
    canManage: actionLabel.isNotEmpty,
    actionProvider: purchaseContext.sourceProvider,
    actionManagementChannel: purchaseContext.managementChannel,
  );
}

class _TeamAccessAction {
  const _TeamAccessAction({
    required this.actionLabel,
    required this.actionIcon,
    required this.canManage,
    required this.actionProvider,
    required this.actionManagementChannel,
  });

  final String actionLabel;
  final IconData actionIcon;
  final bool canManage;
  final BillingProvider? actionProvider;
  final String actionManagementChannel;
}

_TeamAccessAction _teamAccessAction(OrganizationAccessItem organization) {
  final canManage = {
    'owner',
    'admin',
    'manager',
    'teacher',
  }.contains(organization.role.trim().toLowerCase());
  return _TeamAccessAction(
    actionLabel: canManage ? 'Manage on web' : '',
    actionIcon: Icons.language_rounded,
    canManage: canManage,
    actionProvider: BillingProvider.unknown,
    actionManagementChannel: 'web',
  );
}

List<OrganizationAccessItem> _activeTeamOrganizations(
  List<OrganizationAccessItem> organizations,
) {
  return organizations
      .where((item) => item.membershipStatus.trim().toLowerCase() == 'active')
      .toList(growable: false);
}

IconData _teamAccessIcon(OrganizationAccessItem organization) {
  switch (organization.planCode.trim().toLowerCase()) {
    case 'education':
      return Icons.school_rounded;
    case 'enterprise':
      return Icons.apartment_rounded;
    default:
      return Icons.groups_2_rounded;
  }
}

String _teamAccessTitle(
  BuildContext context,
  OrganizationAccessItem organization,
) {
  final planLabel = _localizedPlanLabel(
    context,
    planCode: organization.planCode,
    fallback: organization.planLabel,
  );
  return '${organization.name} · $planLabel';
}

String _teamAccessDetail(
  BuildContext context,
  OrganizationAccessItem organization,
) {
  final role = _localizedRoleLabel(context, organization.role);
  final planCode = organization.planCode.trim().toLowerCase();
  if (planCode == 'education') {
    return _tr(
      context,
      '{role} access to education workspace and class cloud storage',
      {'role': role},
    );
  }
  if (planCode == 'enterprise') {
    return _tr(
      context,
      '{role} access to enterprise workspace and shared cloud storage',
      {'role': role},
    );
  }
  return _tr(
    context,
    '{role} access to shared workspace and cloud storage',
    {'role': role},
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
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Team access'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.6,
              fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF10251E).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF8DF2C2).withValues(alpha: 0.16)),
      ),
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
                    fontSize: 12.8,
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
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Education invite'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.8,
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
                    hintText: _t(context, 'Paste invite link'),
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.36)),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(color: Color(0xFF8DF2C2)),
                    ),
                  ),
                  onSubmitted: (_) => onAccept(),
                ),
              ),
              const SizedBox(width: 9),
              ElevatedButton(
                onPressed: isBusy ? null : onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFECF6FF),
                  foregroundColor: const Color(0xFF101820),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                    isBusy ? _t(context, 'Accepting') : _t(context, 'Accept')),
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
      OrganizationAccessItem organization) async {
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
            ? _tr(
                context,
                'Invite email sent to {email}.',
                {'email': invitedEmail},
              )
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
          'active' => _tr(
              context,
              'Student seat restored for {student}.',
              {'student': _educationMembershipLabel(membership)},
            ),
          'removed' => _tr(
              context,
              'Removed {student}.',
              {'student': _educationMembershipLabel(membership)},
            ),
          'revoked' => _tr(
              context,
              'Invite cancelled for {student}.',
              {'student': _educationMembershipLabel(membership)},
            ),
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
    final organization =
        _currentEducationOrganization(_snapshot, widget.initialOrganization);
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
                        message: _t(context, 'Loading education workspace...'),
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
        return _EducationDashboardOverviewPane(
          organization: organization,
          memberships: memberships,
          studentUsage: studentUsage,
          activeCount: activeCount,
          invitedCount: invitedCount,
          emailController: _inviteController,
          isBusy: _inviteBusy,
          onInvite: () => _inviteEducationStudent(organization),
        );
    }
  }
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
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.72),
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
        ? _tr(
            context,
            '{used} / {limit} student seats',
            {
              'used': organization.seatsUsed,
              'limit': organization.seatLimit,
            },
          )
        : _tr(
            context,
            '{count} student seats used',
            {'count': organization.seatsUsed},
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF10202B).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF7FD4FF).withValues(alpha: 0.16)),
      ),
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
                  label: _localizedRoleLabel(context, organization.role)),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
    final studentsWithProjects =
        studentUsage.where((usage) => usage.projectCount > 0).length;
    final releasedCount = memberships
        .where((item) => {'inactive', 'revoked', 'removed'}
            .contains(item.status.trim().toLowerCase()))
        .length;
    final recentlyActiveCount = studentUsage
        .where((usage) =>
            usage.lastActiveAt != null &&
            usage.lastActiveAt!.isAfter(
              DateTime.now().toUtc().subtract(const Duration(days: 7)),
            ))
        .length;
    final lastActivity = _latestStudentActivity(studentUsage);
    final seatUtilization = organization.seatLimit > 0
        ? organization.seatsUsed / organization.seatLimit
        : 0.0;
    final activationRate =
        memberships.isEmpty ? 0.0 : activeCount / memberships.length;
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
              detail: _tr(
                context,
                '{count} pending invites',
                {'count': invitedCount},
              ),
              icon: Icons.school_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Available student seats'),
              value: '${organization.seatsAvailable}',
              detail: _tr(
                context,
                '{used} of {limit} student seats',
                {
                  'used': organization.seatsUsed,
                  'limit': organization.seatLimit,
                },
              ),
              icon: Icons.event_seat_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Class projects'),
              value: '$projectCount',
              detail: _tr(
                context,
                '{count} students have projects',
                {'count': studentsWithProjects},
              ),
              icon: Icons.library_music_rounded,
            ),
            _EducationMetricCard(
              label: _t(context, 'Recent activity'),
              value: '$recentlyActiveCount',
              detail: lastActivity == null
                  ? _t(context, 'No recent activity')
                  : _tr(
                      context,
                      'Last class activity {date}',
                      {
                        'date':
                            DateFormat('MMM d').format(lastActivity.toLocal()),
                      },
                    ),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7FD4FF), size: 18),
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
  const _EducationInsightPanel({
    required this.title,
    required this.rows,
  });

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
  const _EducationPanelShell({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
      ),
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
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF7FD4FF)),
              ),
            ),
            onSubmitted: (_) => onInvite(),
          ),
        ),
        const SizedBox(width: 9),
        ElevatedButton(
          onPressed: isBusy ? null : onInvite,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFECF6FF),
            foregroundColor: const Color(0xFF101820),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
  ) onMembershipStatusChange;

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
      children: visible.map((membership) {
        final label =
            membership.email.isNotEmpty ? membership.email : membership.userId;
        return _EducationStudentRow(
          organization: organization,
          membership: membership,
          usage: _usageForMembership(studentUsage, membership),
          label: label,
          actionKey: actionKey,
          onMembershipStatusChange: onMembershipStatusChange,
        );
      }).toList(growable: false),
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
  ) onMembershipStatusChange;

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
      'removed' =>
        _t(context, 'Restore student seat'),
      _ => '',
    };
    final currentActionKey =
        '${organization.organizationId}:${membership.userId}:$nextStatus';
    final isBusy = actionKey == currentActionKey;
    final canAct = nextStatus.isNotEmpty && actionKey == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
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
      return _tr(
        context,
        '{projects} • last active {date}',
        {
          'projects': projects,
          'date': DateFormat('MMM d').format(lastActive.toLocal()),
        },
      );
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
      'inactive' =>
        _t(context, 'Student seat released'),
      _ => _t(context, 'Student seat'),
    };
  }
  final formatted = DateFormat('MMM d').format(date.toLocal());
  return switch (status) {
    'pending' => _tr(context, 'Invited {date}', {'date': formatted}),
    'active' => _tr(context, 'Active since {date}', {'date': formatted}),
    'removed' ||
    'revoked' ||
    'inactive' =>
      _tr(context, 'Released {date}', {'date': formatted}),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
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
        ? _tr(
            context,
            '{used} / {limit} seats',
            {
              'used': organization.seatsUsed,
              'limit': organization.seatLimit,
            },
          )
        : _tr(
            context,
            '{count} seats used',
            {'count': organization.seatsUsed},
          );
    final roleReadout = _membershipRoleReadout(context, organization.role);
    final canManage = {
      'owner',
      'admin',
      'manager',
      'teacher',
    }.contains(organization.role.trim().toLowerCase());
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
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
                    fontSize: 13.2,
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
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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

class _PlanHighlights extends StatelessWidget {
  const _PlanHighlights({required this.plan});

  final BillingPlanDefinition? plan;

  @override
  Widget build(BuildContext context) {
    final highlights = _planHighlightLabels(context, plan);
    if (highlights.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: highlights
          .map(
            (label) => _CapabilityChip(
              label: label,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _PlanLimitSummary extends StatelessWidget {
  const _PlanLimitSummary({required this.plan});

  final BillingPlanDefinition? plan;

  @override
  Widget build(BuildContext context) {
    final limits = plan?.limits ?? const <String, dynamic>{};
    final chips = <Widget>[];
    void add(String key) {
      final value = limits[key];
      if (_showLimit(value)) {
        chips.add(
          _MetricChip(
            label: _limitLabel(context, key),
            value: _formattedLimitValue(context, key, value),
          ),
        );
      }
    }

    add('ai_prompts_daily');
    add('ai_prompts_weekly');
    add('cloud_projects');
    add('storage_gb');
    add('platform_upload_hours');
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
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
        foregroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CurrentPlanPill extends StatelessWidget {
  const _CurrentPlanPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F3A2D).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF78E2AA).withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFFA4FFCA),
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            _t(context, 'Current plan'),
            style: const TextStyle(
              color: Color(0xFFA4FFCA),
              fontSize: 11.7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingSourcePill extends StatelessWidget {
  const _BillingSourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ContactSalesNote extends StatelessWidget {
  const _ContactSalesNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2738).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        _t(
          context,
          'Studio checkout is available on web. Enterprise and Education plans are handled by sales.',
        ),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11.9,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
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
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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

class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF153024).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6FE0A4).withValues(alpha: 0.48),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFFA4FFCA),
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA4FFCA),
              fontSize: 11.7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.plan,
    required this.storePrice,
    required this.actionLabel,
    required this.isCurrentPlan,
    required this.isBusy,
    required this.onPressed,
  });

  final BillingProductDefinition product;
  final BillingPlanDefinition? plan;
  final String? storePrice;
  final String actionLabel;
  final bool isCurrentPlan;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final price = (storePrice ?? '').trim().isNotEmpty
        ? storePrice!.trim()
        : product.priceDisplay.trim().isNotEmpty
            ? product.priceDisplay
            : _t(context, 'See pricing');
    final cadence = _cadenceLabel(context, product.billingInterval);
    final planLabel = _localizedPlanLabel(
      context,
      planCode: product.planCode,
      fallback: plan?.label ?? product.planCode,
    );
    final productLabel = _localizedProductLabel(context, product);
    final description = product.description.isEmpty
        ? _tr(context, '{plan} plan access.', {'plan': planLabel})
        : _t(context, product.description);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (cadence != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      cadence,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PlanHighlights(plan: plan),
          const SizedBox(height: 10),
          _PlanLimitSummary(plan: plan),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isCurrentPlan) const _CurrentPlanPill(),
              _BillingSourcePill(
                  label: _purchaseChannelLabel(context, product)),
              if (product.type == 'contract' ||
                  product.managementChannel == 'admin')
                _MetricChip(
                  label: _t(context, 'Purchase'),
                  value: _t(context, 'Sales'),
                ),
              if (product.trialDays > 0)
                _MetricChip(
                  label: _t(context, 'Trial'),
                  value: _tr(
                    context,
                    '{count} days',
                    {'count': product.trialDays},
                  ),
                ),
            ],
          ),
          if (product.type == 'contract' ||
              product.managementChannel == 'admin') ...[
            const SizedBox(height: 10),
            const _ContactSalesNote(),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: isCurrentPlan || isBusy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3E82FF),
                foregroundColor: Colors.white,
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

String _localizedProductLabel(
  BuildContext context,
  BillingProductDefinition product,
) {
  final translated = _t(context, product.label);
  if (translated != product.label) return translated;
  return product.label
      .replaceAll('Education', _t(context, 'Education'))
      .replaceAll('Enterprise', _t(context, 'Enterprise'));
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

String _purchaseChannelLabel(
  BuildContext context,
  BillingProductDefinition product,
) {
  final channel = product.managementChannel.trim().toLowerCase();
  if (product.type == 'contract' || channel == 'admin') {
    return _t(context, 'Contact sales');
  }
  if (channel == 'in_app') {
    return _t(context, 'In-app purchase');
  }
  if (channel == 'web') {
    return _t(context, 'Web checkout');
  }
  return _t(context, _titleCase(channel.isEmpty ? product.type : channel));
}

List<String> _planHighlightLabels(
  BuildContext context,
  BillingPlanDefinition? plan,
) {
  final capabilities = plan?.capabilities ?? const <String, bool>{};
  final labels = <String>[];

  void add(String key) {
    if (capabilities[key] == true) {
      labels.add(_capabilityLabel(context, key));
    }
  }

  add(SubscriptionCapability.allPlugins);
  add(SubscriptionCapability.highQualityExport);
  add(SubscriptionCapability.selectableAiModels);
  add(SubscriptionCapability.advancedAiModels);
  add(SubscriptionCapability.customSamplePacks);
  add(SubscriptionCapability.teamWorkspaces);
  add(SubscriptionCapability.prioritySupport);

  if (labels.isEmpty && plan != null) {
    return <String>[
      _localizedPlanLabel(
        context,
        planCode: plan.code,
        fallback: plan.label,
      ),
    ];
  }
  return labels.take(3).toList(growable: false);
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

String? _renewalCopy(BuildContext context, EntitlementSnapshot entitlement) {
  final expiresAt = entitlement.expiresAt;
  if (expiresAt == null) {
    return null;
  }
  final date = _formatDate(expiresAt);
  if (entitlement.isAccessActive) {
    return _tr(context, 'Renews on {date}.', {'date': date});
  }
  return _tr(context, 'Access ended on {date}.', {'date': date});
}

String _capabilityLabel(BuildContext context, String key) {
  switch (key) {
    case SubscriptionCapability.allPlugins:
      return _t(context, 'All plugins');
    case SubscriptionCapability.highQualityExport:
      return _t(context, 'High-quality export');
    case SubscriptionCapability.wavStarterSamples:
      return _t(context, 'WAV starter samples');
    case SubscriptionCapability.selectableAiModels:
      return _t(context, 'Selectable AI models');
    case SubscriptionCapability.advancedAiModels:
      return _t(context, 'Advanced AI models');
    case SubscriptionCapability.producerProfilePresets:
      return _t(context, 'Producer profile presets');
    case SubscriptionCapability.premiumSoundLibraries:
      return _t(context, 'Premium sound libraries');
    case SubscriptionCapability.cloudFileBrowser:
      return _t(context, 'Cloud file browser');
    case SubscriptionCapability.customSamplePacks:
      return _t(context, 'Custom sample packs');
    case SubscriptionCapability.profilePlanBadge:
      return _t(context, 'Profile plan badge');
    case SubscriptionCapability.dedicatedSupport:
      return _t(context, 'Dedicated support');
    case SubscriptionCapability.customAiModels:
      return _t(context, 'Custom AI models');
    case SubscriptionCapability.complianceControls:
      return _t(context, 'Compliance controls');
    case SubscriptionCapability.educationSandbox:
      return _t(context, 'Education sandbox');
    case SubscriptionCapability.videoProjects:
      return _t(context, 'Video projects');
    case SubscriptionCapability.webCheckout:
      return _t(context, 'Web checkout');
    case SubscriptionCapability.mobileIap:
      return _t(context, 'In-app purchase');
    case SubscriptionCapability.studioFeatures:
      return _t(context, 'Studio tools');
    case SubscriptionCapability.cloudProjects:
      return _t(context, 'Cloud projects');
    case SubscriptionCapability.teamWorkspaces:
      return _t(context, 'Shared project space');
    case SubscriptionCapability.prioritySupport:
      return _t(context, 'Priority support');
    case SubscriptionCapability.educationVisibilityControls:
      return _t(context, 'Education privacy controls');
    default:
      return _t(context, _titleCase(key));
  }
}

String _limitLabel(BuildContext context, String key) {
  switch (key) {
    case 'members':
      return _t(context, 'Members');
    case 'workspaces':
      return _t(context, 'Workspaces');
    case 'cloud_projects':
      return _t(context, 'Cloud projects');
    case 'storage_gb':
      return _t(context, 'Storage');
    case 'platform_upload_hours':
      return _t(context, 'Upload hours');
    case 'ai_prompts_daily':
      return _t(context, 'Daily AI prompts');
    case 'ai_prompts_weekly':
      return _t(context, 'Weekly AI prompts');
    case 'ai_model_tier':
      return _t(context, 'AI model tier');
    case 'sample_pack_storage_gb':
      return _t(context, 'Sample pack storage');
    case 'shared_storage_gb':
      return _t(context, 'Shared storage');
    case 'producer_profile_presets':
      return _t(context, 'Producer presets');
    default:
      return _t(context, _titleCase(key));
  }
}

bool _showLimit(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is num) {
    return value > 0;
  }
  final normalized = '$value'.trim();
  return normalized.isNotEmpty && normalized != '0';
}

String _limitValue(Object? value) {
  if (value == null) {
    return '0';
  }
  if (value is num) {
    return value == value.roundToDouble() ? value.toInt().toString() : '$value';
  }
  return '$value';
}

String _formattedLimitValue(BuildContext context, String key, Object? value) {
  final raw = _limitValue(value);
  switch (key) {
    case 'storage_gb':
    case 'sample_pack_storage_gb':
    case 'shared_storage_gb':
      return raw.toLowerCase() == 'custom' ? _t(context, 'Custom') : '$raw GB';
    case 'platform_upload_hours':
      return raw.toLowerCase() == 'custom'
          ? _t(context, 'Custom')
          : _tr(context, '{count} hours', {'count': raw});
    case 'ai_prompts_daily':
      return raw.toLowerCase() == 'custom'
          ? _t(context, 'Custom')
          : _tr(context, '{count}/day', {'count': raw});
    case 'ai_prompts_weekly':
      return raw.toLowerCase() == 'custom'
          ? _t(context, 'Custom')
          : _tr(context, '{count}/week', {'count': raw});
    case 'cloud_projects':
      return raw.toLowerCase() == 'custom' ? _t(context, 'Unlimited') : raw;
    default:
      return raw;
  }
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

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.trim().isNotEmpty)
      .map(
        (part) => part[0].toUpperCase() + part.substring(1).toLowerCase(),
      )
      .join(' ');
}

String _formatDate(DateTime value) {
  return DateFormat.yMMMd().format(value.toLocal());
}
