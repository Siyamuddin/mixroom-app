import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/models/entitlement_models.dart';

enum _BillingPanelSection { overview, plans, access }

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
  final VoidCallback onManageSubscription;
  final VoidCallback onRestorePurchases;
  final VoidCallback onContactSupport;
  final ValueChanged<BillingProductDefinition> onSelectProduct;

  @override
  State<AccountSubscriptionSurface> createState() =>
      _AccountSubscriptionSurfaceState();
}

class _AccountSubscriptionSurfaceState extends State<AccountSubscriptionSurface> {
  _BillingPanelSection _section = _BillingPanelSection.overview;

  @override
  Widget build(BuildContext context) {
    final entitlement = widget.entitlementService.entitlement ??
        EntitlementSnapshot.free(userId: '');
    final catalog = widget.entitlementService.billingCatalog;
    final support = widget.entitlementService.effectiveBillingSupport;
    final accessSummary = widget.entitlementService.effectiveAccessSummary;
    final products = catalog?.enabledProductsForPlatform(widget.platformKey) ??
        const <BillingProductDefinition>[];
    final busy = widget.isActionBusy || widget.iapService.isPurchaseInProgress;
    final userFacingMessage = _userFacingMessage();
    final debugMessages = _debugMessages();

    return _SectionCard(
      icon: Icons.workspace_premium_rounded,
      title: 'Plan & Billing',
      subtitle: widget.entitlementService.isLoading
          ? 'Refreshing your current plan details.'
          : 'Subscription, upgrades, support, and shared workspace access.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (userFacingMessage != null) ...[
            _NoticeBanner(message: userFacingMessage),
            const SizedBox(height: 12),
          ],
          if (kDebugMode && debugMessages.isNotEmpty) ...[
            _DebugBanner(messages: debugMessages),
            const SizedBox(height: 12),
          ],
          _PlanHero(
            entitlement: entitlement,
            accessSummary: accessSummary,
            supportLabel: support.contactLabel,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'Manage',
                icon: Icons.open_in_new_rounded,
                onPressed: busy ? null : widget.onManageSubscription,
              ),
              _ActionButton(
                label: 'Restore',
                icon: Icons.restore_rounded,
                onPressed: busy ? null : widget.onRestorePurchases,
              ),
              _ActionButton(
                label: 'Support',
                icon: Icons.support_agent_rounded,
                onPressed: busy ? null : widget.onContactSupport,
              ),
              _ActionButton(
                label: widget.entitlementService.isAccountSurfaceLoading || busy
                    ? 'Refreshing...'
                    : 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: widget.entitlementService.isAccountSurfaceLoading || busy
                    ? null
                    : widget.onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PanelSubnav(
            current: _section,
            onChanged: (section) {
              setState(() {
                _section = section;
              });
            },
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<_BillingPanelSection>(_section),
              child: switch (_section) {
                _BillingPanelSection.overview => _OverviewPanel(
                    entitlement: entitlement,
                    accessSummary: accessSummary,
                    support: support,
                    isLoading: widget.entitlementService.isAccountSurfaceLoading,
                  ),
                _BillingPanelSection.plans => _PlansPanel(
                    entitlement: entitlement,
                    catalog: catalog,
                    products: products,
                    platformProvider: widget.platformProvider,
                    regionCode: widget.regionCode,
                    iapService: widget.iapService,
                    isBusy: busy,
                    onSelectProduct: widget.onSelectProduct,
                  ),
                _BillingPanelSection.access => _AccessPanel(
                    entitlementService: widget.entitlementService,
                    entitlement: entitlement,
                    accessSummary: accessSummary,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _userFacingMessage() {
    final inline = (widget.inlineMessage ?? '').trim();
    if (inline.isNotEmpty &&
        !inline.toLowerCase().contains('failed') &&
        !inline.toLowerCase().contains('401') &&
        !inline.toLowerCase().contains('403')) {
      return inline;
    }

    final hasServiceIssue = (widget.entitlementService.lastError ?? '').trim().isNotEmpty ||
        (widget.entitlementService.accountSurfaceError ?? '').trim().isNotEmpty ||
        (widget.iapService.lastError ?? '').trim().isNotEmpty;
    if (hasServiceIssue) {
      return 'Some billing details are temporarily unavailable.';
    }
    if (inline.isNotEmpty) {
      return 'Billing details were updated.';
    }
    return null;
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
    add(widget.entitlementService.lastError);
    add(widget.entitlementService.accountSurfaceError);
    add(widget.iapService.lastError);
    return values;
  }
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

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A3551).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF8CB5FF).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.2,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
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
          const Text(
            'Debug only',
            style: TextStyle(
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
    required this.accessSummary,
    required this.supportLabel,
  });

  final EntitlementSnapshot entitlement;
  final CollaborationAccessSummary accessSummary;
  final String supportLabel;

  @override
  Widget build(BuildContext context) {
    final renewalCopy = _renewalCopy(entitlement);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF203A6B), Color(0xFF111B31)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1325).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
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
                      entitlement.effectivePlanLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _planSummaryText(entitlement, accessSummary),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.6,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PlanBadge(label: _statusLabel(entitlement.status)),
            ],
          ),
          if (renewalCopy != null) ...[
            const SizedBox(height: 14),
            _HeroLine(
              icon: entitlement.isAccessActive
                  ? Icons.event_repeat_rounded
                  : Icons.event_busy_rounded,
              text: renewalCopy,
            ),
          ],
          if (accessSummary.hasAnyAccess) ...[
            const SizedBox(height: 10),
            _HeroLine(
              icon: Icons.groups_2_rounded,
              text: _teamSummary(accessSummary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Need help with billing? $supportLabel is available from this page.',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11.7,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFBFD7FF), size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelSubnav extends StatelessWidget {
  const _PanelSubnav({
    required this.current,
    required this.onChanged,
  });

  final _BillingPanelSection current;
  final ValueChanged<_BillingPanelSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SubnavChip(
          label: 'Overview',
          selected: current == _BillingPanelSection.overview,
          onTap: () => onChanged(_BillingPanelSection.overview),
        ),
        _SubnavChip(
          label: 'Plans',
          selected: current == _BillingPanelSection.plans,
          onTap: () => onChanged(_BillingPanelSection.plans),
        ),
        _SubnavChip(
          label: 'Access',
          selected: current == _BillingPanelSection.access,
          onTap: () => onChanged(_BillingPanelSection.access),
        ),
      ],
    );
  }
}

class _SubnavChip extends StatelessWidget {
  const _SubnavChip({
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3E82FF).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF76A8FF).withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFD4E4FF) : Colors.white70,
            fontSize: 11.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.entitlement,
    required this.accessSummary,
    required this.support,
    required this.isLoading,
  });

  final EntitlementSnapshot entitlement;
  final CollaborationAccessSummary accessSummary;
  final BillingSupportInfo support;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(
              label: 'Plan',
              value: entitlement.effectivePlanLabel,
            ),
            if (entitlement.expiresAt != null)
              _MetricChip(
                label: entitlement.isAccessActive ? 'Renews' : 'Ends',
                value: _formatDate(entitlement.expiresAt!),
              ),
            if (accessSummary.organizationCount > 0)
              _MetricChip(
                label: 'Organizations',
                value: accessSummary.organizationCount.toString(),
              ),
            if (accessSummary.workspaceCount > 0)
              _MetricChip(
                label: 'Workspaces',
                value: accessSummary.workspaceCount.toString(),
              ),
            if (accessSummary.cloudProjectCount > 0)
              _MetricChip(
                label: 'Cloud projects',
                value: accessSummary.cloudProjectCount.toString(),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _InfoTile(
          title: 'Billing support',
          body: support.supportUrl.trim().isNotEmpty
              ? 'Help and billing questions are handled from the Mixroom support site.'
              : 'Billing support is available from your account support entry.',
        ),
        const SizedBox(height: 10),
        _InfoTile(
          title: 'Restore purchases',
          body:
              'Use Restore if you already purchased on this store account and need Mixroom to pick it up again.',
        ),
        const SizedBox(height: 10),
        _InfoTile(
          title: 'Availability',
          body: isLoading
              ? 'Billing details are still loading.'
              : 'Plan management, upgrades, and team access all live here.',
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
    required this.onSelectProduct,
  });

  final EntitlementSnapshot entitlement;
  final BillingCatalogSnapshot? catalog;
  final List<BillingProductDefinition> products;
  final BillingProvider platformProvider;
  final String regionCode;
  final IapService iapService;
  final bool isBusy;
  final ValueChanged<BillingProductDefinition> onSelectProduct;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Text(
        catalog == null
            ? 'Plans will appear here once billing catalog data is available.'
            : 'No upgrade plans are currently available for this device.',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12.3,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      );
    }

    return Column(
      children: products
          .map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProductCard(
                product: product,
                plan: catalog?.planByCode(product.planCode),
                storePrice: _storePriceForProduct(catalog, product),
                actionLabel: _actionLabel(entitlement, catalog, product),
                isCurrentPlan: _isCurrentPlan(entitlement, product),
                isBusy: isBusy,
                onPressed: isBusy ? null : () => onSelectProduct(product),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String? _storePriceForProduct(
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    final offer = catalog?.bestOfferForProduct(
      productCode: product.code,
      provider: platformProvider,
      regionCode: regionCode,
    );
    if (offer == null) {
      return null;
    }
    return iapService.findProductById(offer.providerProductId)?.price;
  }

  String _actionLabel(
    EntitlementSnapshot entitlement,
    BillingCatalogSnapshot? catalog,
    BillingProductDefinition product,
  ) {
    if (_isCurrentPlan(entitlement, product)) {
      return 'Current plan';
    }
    if (product.managementChannel == 'admin' || product.type == 'contract') {
      return 'Contact support';
    }
    final offer = catalog?.bestOfferForProduct(
      productCode: product.code,
      provider: platformProvider,
      regionCode: regionCode,
    );
    return offer != null ? 'Choose plan' : 'Open checkout';
  }

  bool _isCurrentPlan(
    EntitlementSnapshot entitlement,
    BillingProductDefinition product,
  ) {
    if (!entitlement.isAccessActive || product.type != 'subscription') {
      return false;
    }
    return entitlement.planCode == product.planCode;
  }
}

class _AccessPanel extends StatelessWidget {
  const _AccessPanel({
    required this.entitlementService,
    required this.entitlement,
    required this.accessSummary,
  });

  final EntitlementService entitlementService;
  final EntitlementSnapshot entitlement;
  final CollaborationAccessSummary accessSummary;

  @override
  Widget build(BuildContext context) {
    final capabilityEntries = entitlement.capabilities.entries
        .where((entry) => entry.value)
        .toList(growable: false)
      ..sort((a, b) => _capabilityLabel(a.key).compareTo(_capabilityLabel(b.key)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (capabilityEntries.isNotEmpty) ...[
          const _SubsectionLabel(label: 'Included in your plan'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: capabilityEntries
                .map(
                  (entry) => _CapabilityChip(
                    label: _capabilityLabel(entry.key),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (entitlement.limits.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SubsectionLabel(label: 'Limits'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entitlement.limits.entries
                .where((entry) => _showLimit(entry.value))
                .map(
                  (entry) => _MetricChip(
                    label: _limitLabel(entry.key),
                    value: _limitValue(entry.value),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 14),
        const _SubsectionLabel(label: 'Shared access'),
        const SizedBox(height: 8),
        if (!accessSummary.hasAnyAccess)
          const Text(
            'No shared workspace or cloud-project access is currently attached to this account.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.2,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'Organizations',
                    value: accessSummary.organizationCount.toString(),
                  ),
                  _MetricChip(
                    label: 'Workspaces',
                    value: accessSummary.workspaceCount.toString(),
                  ),
                  _MetricChip(
                    label: 'Cloud projects',
                    value: accessSummary.cloudProjectCount.toString(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AccessGroup<OrganizationAccessItem>(
                title: 'Organizations',
                emptyLabel: 'No organizations',
                items: entitlementService.effectiveOrganizations,
                itemLabel: (item) =>
                    '${item.name}${item.role.trim().isEmpty ? '' : ' • ${item.role}'}',
              ),
              const SizedBox(height: 10),
              _AccessGroup<WorkspaceAccessItem>(
                title: 'Workspaces',
                emptyLabel: 'No workspaces',
                items: entitlementService.effectiveWorkspaces,
                itemLabel: (item) => item.name,
              ),
              const SizedBox(height: 10),
              _AccessGroup<CloudProjectAccessItem>(
                title: 'Cloud projects',
                emptyLabel: 'No cloud projects',
                items: entitlementService.effectiveCloudProjects,
                itemLabel: (item) => item.name,
              ),
            ],
          ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.9,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
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
            : 'See pricing';
    final cadence = _cadenceLabel(product.billingInterval);

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
                      product.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.description.isEmpty
                          ? '${plan?.label ?? product.planCode} plan access.'
                          : product.description,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Plan', value: plan?.label ?? product.planCode),
              if (product.type == 'contract' || product.managementChannel == 'admin')
                const _MetricChip(label: 'Purchase', value: 'Support'),
            ],
          ),
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

class _AccessGroup<T> extends StatelessWidget {
  const _AccessGroup({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.itemLabel,
  });

  final String title;
  final String emptyLabel;
  final List<T> items;
  final String Function(T item) itemLabel;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(4).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (visibleItems.isEmpty)
          Text(
            emptyLabel,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11.8,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          Column(
            children: visibleItems
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: Color(0xFFA4C2FF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            itemLabel(item),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.9,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

String _planSummaryText(
  EntitlementSnapshot entitlement,
  CollaborationAccessSummary accessSummary,
) {
  if (entitlement.planGroup == 'team' ||
      entitlement.planGroup == 'enterprise' ||
      entitlement.planGroup == 'education' ||
      accessSummary.hasAnyAccess) {
    return 'Includes shared workspace and cloud access where available.';
  }
  if (entitlement.isPaidTier) {
    return 'Your paid tools and upgrades are managed from this page.';
  }
  return 'Upgrade any time for more creative tools and team features.';
}

String? _renewalCopy(EntitlementSnapshot entitlement) {
  final expiresAt = entitlement.expiresAt;
  if (expiresAt == null) {
    return null;
  }
  final date = _formatDate(expiresAt);
  if (entitlement.isAccessActive) {
    return 'Renews on $date.';
  }
  return 'Access ended on $date.';
}

String _teamSummary(CollaborationAccessSummary summary) {
  final parts = <String>[];
  if (summary.organizationCount > 0) {
    parts.add(
      summary.organizationCount == 1
          ? '1 organization'
          : '${summary.organizationCount} organizations',
    );
  }
  if (summary.workspaceCount > 0) {
    parts.add(
      summary.workspaceCount == 1
          ? '1 workspace'
          : '${summary.workspaceCount} workspaces',
    );
  }
  if (summary.cloudProjectCount > 0) {
    parts.add(
      summary.cloudProjectCount == 1
          ? '1 cloud project'
          : '${summary.cloudProjectCount} cloud projects',
    );
  }
  return parts.join(' • ');
}

String _statusLabel(SubscriptionStatus status) {
  switch (status) {
    case SubscriptionStatus.active:
      return 'Active';
    case SubscriptionStatus.trialing:
      return 'Trial';
    case SubscriptionStatus.gracePeriod:
      return 'Grace period';
    case SubscriptionStatus.pastDue:
      return 'Past due';
    case SubscriptionStatus.paused:
      return 'Paused';
    case SubscriptionStatus.canceled:
      return 'Canceled';
    case SubscriptionStatus.expired:
      return 'Expired';
    case SubscriptionStatus.refunded:
      return 'Refunded';
    case SubscriptionStatus.revoked:
      return 'Revoked';
  }
}

String _capabilityLabel(String key) {
  switch (key) {
    case SubscriptionCapability.proEditor:
      return 'Pro editor';
    case SubscriptionCapability.unlimitedAudioTracks:
      return 'Unlimited audio tracks';
    case SubscriptionCapability.multiVideoImport:
      return 'Multi-video import';
    case SubscriptionCapability.premiumEffects:
      return 'Premium effects';
    case SubscriptionCapability.videoProjects:
      return 'Video projects';
    case SubscriptionCapability.webCheckout:
      return 'Web checkout';
    case SubscriptionCapability.mobileIap:
      return 'In-app purchase';
    case SubscriptionCapability.studioFeatures:
      return 'Studio tools';
    case SubscriptionCapability.cloudProjects:
      return 'Cloud projects';
    case SubscriptionCapability.teamWorkspaces:
      return 'Team workspaces';
    case SubscriptionCapability.prioritySupport:
      return 'Priority support';
    case SubscriptionCapability.educationVisibilityControls:
      return 'Education privacy controls';
    default:
      return _titleCase(key);
  }
}

String _limitLabel(String key) {
  switch (key) {
    case 'members':
      return 'Members';
    case 'workspaces':
      return 'Workspaces';
    case 'cloud_projects':
      return 'Cloud projects';
    case 'storage_gb':
      return 'Storage';
    default:
      return _titleCase(key);
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

String? _cadenceLabel(String interval) {
  switch (interval.trim().toLowerCase()) {
    case 'monthly':
      return 'Monthly';
    case 'yearly':
      return 'Annual';
    case 'daily':
      return 'Daily';
    case 'one_time':
      return 'One-time';
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
