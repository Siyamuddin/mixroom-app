import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mixroom/config/iap_config.dart';
import 'package:mixroom/config/subscription_config.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/helpers/subscription_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/subscription_models.dart';
import 'package:mixroom/screens/legal_privacy_center.dart';
import 'package:mixroom/widgets/language_selector.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.showTopBar = true});

  final bool showTopBar;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: showTopBar
          ? const PreferredSize(
              preferredSize: Size.fromHeight(86),
              child: _AccountTopBar(),
            )
          : null,
      body: user == null
          ? const SizedBox.expand()
          : (showTopBar
              ? _AccountBody(user: user)
              : SafeArea(top: true, child: _AccountBody(user: user))),
      bottomNavigationBar: user == null
          ? null
          : _AccountActions(
              isBusy: auth.isBusy,
              onSignOut: () async {
                await context.read<AuthService>().signOut();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
    );
  }
}

class _AccountTopBar extends StatelessWidget {
  const _AccountTopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: L10n.translate(context, 'Back'),
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withOpacity(0.10)),
                ),
              ),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                L10n.translate(context, 'Account'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountBody extends StatefulWidget {
  const _AccountBody({required this.user});

  final AuthUserProfile user;

  @override
  State<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<_AccountBody> {
  static const List<String> _useCaseOptions = <String>[
    'Music enthusiast',
    'Beginner producer',
    'For work',
    'Songwriting',
    'Mix/master practice',
  ];

  late TextEditingController _nameController;
  late DateTime? _birthday;
  late String _useMixroomFor;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _syncFromUser();
  }

  @override
  void didUpdateWidget(covariant _AccountBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user && !_isEditing) {
      _syncFromUser();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _syncFromUser() {
    _nameController.text = widget.user.displayName;
    _birthday = widget.user.birthday;
    _useMixroomFor = widget.user.useMixroomFor;
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4F8BFF),
              surface: Color(0xFF12233E),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (!mounted || picked == null) return;
    setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    final safeName = _nameController.text.trim();
    if (safeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L10n.translate(context, 'Name cannot be empty.'))),
      );
      return;
    }

    final updated = widget.user.copyWith(
      displayName: safeName,
      birthday: _birthday,
      useMixroomFor: _useMixroomFor,
    );

    await context.read<AuthService>().updateProfile(updated);
    if (!mounted) return;

    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.translate(context, 'Account updated.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final subscription = context.watch<SubscriptionService>();
    final iap = context.watch<IapService>();
    final joinedAt = _formatDate(widget.user.createdAt.toLocal());
    final birthday = _birthday == null
        ? L10n.translate(context, 'Not provided')
        : _formatDate(_birthday!.toLocal());
    final needsEmailVerification =
        widget.user.provider == AuthProviderType.email &&
            !widget.user.emailVerified;

    return ListView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _ProfileHero(
          user: widget.user,
          overrideName: _nameController.text,
          isEditing: _isEditing,
          onEditToggle: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (_isEditing) {
                _syncFromUser();
              }
              _isEditing = !_isEditing;
            });
          },
        ),
        if (needsEmailVerification) ...[
          const SizedBox(height: 10),
          _EmailVerificationBanner(
            busy: auth.isBusy,
            onResend: () async {
              try {
                await context.read<AuthService>().resendEmailVerification();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(L10n.translate(context, 'Verification email sent.')),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Bad state: ', '')),
                  ),
                );
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                _ReadonlyRow(label: 'Email', value: widget.user.email),
                _DividerLine(),
                _EditableNameRow(
                  isEditing: _isEditing,
                  controller: _nameController,
                ),
                _DividerLine(),
                _EditableBirthdayRow(
                  isEditing: _isEditing,
                  value: birthday,
                  onTap: _pickBirthday,
                ),
                _DividerLine(),
                _EditableUseCaseRow(
                  isEditing: _isEditing,
                  value: _useMixroomFor,
                  options: _useCaseOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _useMixroomFor = value);
                  },
                ),
                _DividerLine(),
                const _LanguagePreferenceRow(),
                _DividerLine(),
                _ReadonlyRow(
                  label: 'Provider',
                  value: L10n.translate(context, widget.user.provider.label),
                ),
                _DividerLine(),
                _ReadonlyRow(label: 'Joined', value: joinedAt),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: !_isEditing
                      ? const SizedBox.shrink()
                      : Column(
                          key: const ValueKey<String>('editing-actions'),
                          children: [
                            _DividerLine(),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _syncFromUser();
                                          _isEditing = false;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                            color:
                                                Colors.white.withOpacity(0.2)),
                                        foregroundColor: Colors.white70,
                                      ),
                                      child: Text(
                                          L10n.translate(context, 'Cancel')),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        HapticFeedback.mediumImpact();
                                        _save();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF3E82FF),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(L10n.translate(
                                          context, 'Save Changes')),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _SubscriptionEntitlementCard(subscription: subscription, iap: iap),
        const SizedBox(height: 12),
        _LegalPrivacyEntryCard(
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LegalPrivacyCenterScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EmailVerificationBanner extends StatelessWidget {
  const _EmailVerificationBanner({
    required this.busy,
    required this.onResend,
  });

  final bool busy;
  final Future<void> Function() onResend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2A1A).withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8C86D).withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              color: Color(0xFFE8C86D), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Email not verified'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.translate(context,
                      'Please verify your email for better account security.'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy ? null : onResend,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFFFFD774),
                  ),
                  child: Text(
                    busy
                        ? L10n.translate(context, 'Sending...')
                        : L10n.translate(context, 'Resend verification email'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.overrideName,
    required this.isEditing,
    required this.onEditToggle,
  });

  final AuthUserProfile user;
  final String overrideName;
  final bool isEditing;
  final VoidCallback onEditToggle;

  @override
  Widget build(BuildContext context) {
    final displayName =
        overrideName.trim().isEmpty ? user.displayName : overrideName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF2B63D8), Color(0xFF3F8EFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3573EC).withOpacity(0.36),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.20),
            child: Text(
              _initials(displayName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isEditing
                ? L10n.translate(context, 'Done')
                : L10n.translate(context, 'Edit'),
            onPressed: onEditToggle,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.16),
            ),
            icon: Icon(
              isEditing ? Icons.close_rounded : Icons.edit_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccountFieldLabel(label: label),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableNameRow extends StatelessWidget {
  const _EditableNameRow({required this.isEditing, required this.controller});

  final bool isEditing;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'Name', value: controller.text.trim());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const _AccountFieldLabel(label: 'Name'),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.translate(context, 'Your name'),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: Color(0xFF5F96FF), width: 1.1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableBirthdayRow extends StatelessWidget {
  const _EditableBirthdayRow({
    required this.isEditing,
    required this.value,
    required this.onTap,
  });

  final bool isEditing;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'Birthday', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const _AccountFieldLabel(label: 'Birthday'),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.calendar_month_outlined,
                        size: 16, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableUseCaseRow extends StatelessWidget {
  const _EditableUseCaseRow({
    required this.isEditing,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final bool isEditing;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(
        label: 'Using Mixroom for',
        value: L10n.translate(context, value),
      );
    }

    final dropdownOptions = <String>{
      ...options,
      if (value.trim().isNotEmpty) value.trim(),
    }.toList();
    final selectedValue = dropdownOptions.contains(value)
        ? value
        : (dropdownOptions.isEmpty ? null : dropdownOptions.first);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'Using Mixroom for'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A2E49),
              iconEnabledColor: Colors.white70,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: Color(0xFF5F96FF), width: 1.1),
                ),
              ),
              items: dropdownOptions
                  .map(
                    (opt) => DropdownMenuItem<String>(
                      value: opt,
                      child: Text(
                        L10n.translate(context, opt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePreferenceRow extends StatelessWidget {
  const _LanguagePreferenceRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'Language'),
          const SizedBox(width: 8),
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: LanguageSelector(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                fontSize: 11.5,
                backgroundColor: Color(0x1AFFFFFF),
                borderColor: Color(0x26FFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountFieldLabel extends StatelessWidget {
  const _AccountFieldLabel({required this.label});

  final String label;

  double _labelWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 350) return 92;
    if (width <= 390) return 102;
    return 120;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _labelWidth(context),
      child: Text(
        L10n.translate(context, label),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(0.08));
  }
}

class _SubscriptionEntitlementCard extends StatelessWidget {
  const _SubscriptionEntitlementCard({
    required this.subscription,
    required this.iap,
  });

  final SubscriptionService subscription;
  final IapService iap;

  String _tierLabel(PlanTier tier) {
    switch (tier) {
      case PlanTier.free:
        return 'Free';
      case PlanTier.pro:
        return 'Pro';
      case PlanTier.studio:
        return 'Studio';
    }
  }

  String _statusLabel(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.trialing:
        return 'Trialing';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.gracePeriod:
        return 'Grace Period';
      case SubscriptionStatus.pastDue:
        return 'Past Due';
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

  String _providerLabel(BillingProvider provider) {
    switch (provider) {
      case BillingProvider.apple:
        return 'Apple';
      case BillingProvider.google:
        return 'Google';
      case BillingProvider.paddle:
        return 'Paddle';
      case BillingProvider.toss:
        return 'Toss';
      case BillingProvider.adminGrant:
        return 'Admin';
      case BillingProvider.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (iap.isMobilePlatformSupported &&
        !iap.isInitialized &&
        !iap.isInitializing) {
      Future<void>.microtask(iap.initialize);
    }

    final ent = subscription.entitlement;
    final tier = _tierLabel(subscription.currentTier);
    final status = _statusLabel(ent?.status ?? SubscriptionStatus.active);
    final source =
        _providerLabel(ent?.sourceProvider ?? BillingProvider.adminGrant);
    final expiresAt =
        ent?.expiresAt == null ? 'N/A' : _formatDate(ent!.expiresAt!.toLocal());
    final revision = ent?.revision ?? 0;
    final iapMode = iap.purchasesEnabled ? 'Enabled' : 'Coming Soon';
    final storeAvailable = iap.isStoreAvailable ? 'Available' : 'Unavailable';
    final productCount = iap.products.length;

    Future<void> handleManage() async {
      try {
        final url = await subscription.fetchPortalUrl();
        if (url == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(L10n.translate(
                    context, 'No management URL is available yet.'))),
          );
          return;
        }
        final launched = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(L10n.translate(
                    context, 'Could not open subscription management URL.'))),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }

    Future<void> handleUpgradeTap() async {
      if (!iap.purchasesEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.translate(context,
                  'Purchases are disabled for now (placeholder mode).'),
            ),
          ),
        );
        return;
      }

      final productId = IapConfig.primaryProductIdForCurrentPlatform();
      final product = iap.findProductById(productId);
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.translate(
                  context, 'Pro monthly product is not available yet.'),
            ),
          ),
        );
        return;
      }
      await iap.buyProduct(product);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFA4C2FF)),
              const SizedBox(width: 8),
              Text(
                L10n.translate(context, 'Subscription'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (subscription.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tier: $tier · Status: $status',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Source: $source · Expires: $expiresAt',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Revision: $revision',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (iap.isMobilePlatformSupported) ...[
            const SizedBox(height: 2),
            Text(
              'Mobile IAP: $iapMode · Store: $storeAvailable · Products: $productCount',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (iap.products.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...iap.products.map(
              (ProductDetails product) => Text(
                '${product.title} (${product.id}) · ${product.price}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if ((subscription.lastError ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subscription.lastError!,
              style: const TextStyle(
                color: Color(0xFFFFC7C7),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if ((iap.lastError ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              iap.lastError!,
              style: const TextStyle(
                color: Color(0xFFFFC7C7),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: subscription.isLoading
                    ? null
                    : () {
                        subscription.refresh(force: true);
                      },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFBBD2FF),
                  minimumSize: const Size(0, 34),
                ),
                child: Text(L10n.translate(context, 'Refresh')),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: (!SubscriptionConfig.hasApiBaseUrl ||
                        subscription.isLoading)
                    ? null
                    : handleManage,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFBBD2FF),
                  minimumSize: const Size(0, 34),
                ),
                child: Text(L10n.translate(context, 'Manage')),
              ),
              if (iap.isMobilePlatformSupported) ...[
                TextButton(
                  onPressed: iap.isInitializing
                      ? null
                      : () {
                          iap.refreshProducts();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBBD2FF),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(L10n.translate(context, 'Refresh Store')),
                ),
                TextButton(
                  onPressed: (!iap.isStoreAvailable ||
                          iap.isInitializing ||
                          iap.isPurchaseInProgress)
                      ? null
                      : () {
                          iap.restorePurchases();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBBD2FF),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(L10n.translate(context, 'Restore')),
                ),
                TextButton(
                  onPressed: (!iap.isStoreAvailable ||
                          iap.isInitializing ||
                          iap.isPurchaseInProgress)
                      ? null
                      : handleUpgradeTap,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBBD2FF),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(
                    iap.purchasesEnabled
                        ? L10n.translate(context, 'Upgrade to Pro')
                        : L10n.translate(context, 'Upgrade (Soon)'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LegalPrivacyEntryCard extends StatelessWidget {
  const _LegalPrivacyEntryCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, color: Color(0xFFA4C2FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Legal & Privacy'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.translate(context,
                      'Manage privacy controls, legal documents, and data requests.'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBBD2FF),
              minimumSize: const Size(0, 34),
            ),
            child: Text(L10n.translate(context, 'Open')),
          ),
        ],
      ),
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.isBusy,
    required this.onSignOut,
  });

  final bool isBusy;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isBusy ? null : onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                L10n.translate(context, 'Log Out'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBE3E3E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _initials(String name) {
  final parts = name
      .split(' ')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'M';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
