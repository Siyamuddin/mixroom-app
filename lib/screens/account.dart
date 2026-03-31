import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/password_policy.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/glass_ui_tokens.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/music_profile_option.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/legal_privacy_center.dart';
import 'package:mixroom/widgets/app_responsive_body.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:mixroom/widgets/email_verification_sheet.dart';
import 'package:mixroom/widgets/language_selector.dart';
import 'package:provider/provider.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    this.showTopBar = true,
    this.enforceProfileCompletion = false,
  });

  final bool showTopBar;
  final bool enforceProfileCompletion;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final appUser = context.watch<AppUserService>();
    context.watch<LocaleProvider>();
    final user = auth.signedInUser;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: showTopBar
          ? const PreferredSize(
              preferredSize: Size.fromHeight(86),
              child: _AccountTopBar(),
            )
          : null,
      body: user == null
          ? const SizedBox.expand()
          : Stack(
              children: [
                if (!showTopBar)
                  const Positioned.fill(child: MixroomShellBackground()),
                AppResponsiveBody(
                  maxWidth: 920,
                  expandToHeight: true,
                  child: showTopBar
                      ? _AccountBody(
                          user: user,
                          appUser: appUser.current,
                          canEditAppProfile: appUser.supportsRemoteProfileEdits,
                          enforceProfileCompletion: enforceProfileCompletion,
                          embeddedMode: false,
                        )
                      : SafeArea(
                          top: true,
                          child: _AccountBody(
                            user: user,
                            appUser: appUser.current,
                            canEditAppProfile:
                                appUser.supportsRemoteProfileEdits,
                            enforceProfileCompletion: enforceProfileCompletion,
                            embeddedMode: true,
                            onSignOut: () async {
                              await context.read<AuthService>().signOut();
                            },
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: user == null
          ? null
          : showTopBar
              ? _AccountActions(
                  isBusy: auth.isBusy,
                  onSignOut: () async {
                    final authService = context.read<AuthService>();
                    final navigator = Navigator.of(context);
                    final shouldDismissRoute = showTopBar && navigator.canPop();
                    if (shouldDismissRoute) {
                      navigator.pop();
                      await Future<void>.delayed(
                        const Duration(milliseconds: 180),
                      );
                    }
                    await authService.signOut();
                  },
                )
              : null,
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
  const _AccountBody({
    required this.user,
    required this.appUser,
    required this.canEditAppProfile,
    required this.enforceProfileCompletion,
    required this.embeddedMode,
    this.onSignOut,
  });

  final AuthUserProfile user;
  final AppUserSnapshot? appUser;
  final bool canEditAppProfile;
  final bool enforceProfileCompletion;
  final bool embeddedMode;
  final Future<void> Function()? onSignOut;

  @override
  State<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<_AccountBody> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  String? _musicProfileValue;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _usernameController = TextEditingController();
    _bioController = TextEditingController();
    _syncFromUser();
  }

  @override
  void didUpdateWidget(covariant _AccountBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.user != widget.user ||
            oldWidget.appUser != widget.appUser) &&
        !_isEditing) {
      _syncFromUser();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _syncFromUser() {
    _nameController.text = widget.user.displayName;
    _usernameController.text = widget.appUser?.username ?? '';
    _bioController.text = widget.appUser?.bio ?? '';
    _musicProfileValue = (widget.appUser?.musicProfile ?? '').trim().isEmpty
        ? null
        : widget.appUser?.musicProfile;
  }

  bool get _hasAuthChanges {
    return _nameController.text.trim() != widget.user.displayName.trim();
  }

  bool get _hasAppProfileChanges {
    return _usernameController.text.trim() !=
            (widget.appUser?.username ?? '').trim() ||
        _bioController.text.trim() != (widget.appUser?.bio ?? '').trim() ||
        ((_musicProfileValue ?? '').trim().toLowerCase() !=
            (widget.appUser?.musicProfile ?? '').trim().toLowerCase());
  }

  void _handleEditToggle() {
    if (_isSaving) return;
    if (_isEditing) {
      HapticFeedback.mediumImpact();
      _save();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _isEditing = true);
  }

  Future<void> _save() async {
    final safeName = _nameController.text.trim();
    final safeUsername = _usernameController.text.trim().toLowerCase();
    final safeBio = _bioController.text.trim();
    if (safeName.isEmpty) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Name cannot be empty.'),
      );
      return;
    }
    if (_isSaving) return;
    if (!widget.canEditAppProfile && _hasAppProfileChanges) {
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          'Username and bio require the deployed account backend before they can be saved.',
        ),
      );
      return;
    }
    if (!_hasAuthChanges && !_hasAppProfileChanges) {
      setState(() => _isEditing = false);
      return;
    }

    final updated = widget.user.copyWith(
      displayName: safeName,
    );
    final authService = context.read<AuthService>();
    final appUserService = context.read<AppUserService>();

    setState(() => _isSaving = true);
    try {
      if (_hasAuthChanges) {
        await authService.updateProfile(updated);
      }
      if (widget.canEditAppProfile) {
        await appUserService.updateProfile(
          displayName: safeName,
          username: safeUsername,
          musicProfile: _musicProfileValue,
          bio: safeBio,
        );
      }
      if (!mounted) return;
      setState(() => _isEditing = false);
      showAppSnackBar(
        context,
        L10n.translate(context, 'Account updated.'),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        e.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openFeedbackComposer() async {
    final authService = context.read<AuthService>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        return MediaQuery.removeViewInsets(
          context: dialogContext,
          removeBottom: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 440, maxHeight: 760),
                child: Material(
                  color: Colors.transparent,
                  child: MixroomShellSurface(
                    radius: 32,
                    strong: true,
                    color: const Color.fromRGBO(24, 34, 48, 0.92),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 6),
                          child: MixroomInlineFeedbackComposer(
                            compact: true,
                            onSubmit: (category, message, allowEmailContact) {
                              return FeedbackService.instance.submit(
                                auth: authService,
                                request: FeedbackSubmissionRequest(
                                  category: category,
                                  source: FeedbackSource.account,
                                  message: message,
                                  allowEmailContact: allowEmailContact,
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: MixroomShellRoundButton(
                            size: 42,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            onTap: () => Navigator.of(dialogContext).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final appUserService = context.watch<AppUserService>();
    final joinedAt = _formatDate(widget.user.createdAt.toLocal());
    final usernameValue = (widget.appUser?.username ?? '').trim();
    final bioValue = (widget.appUser?.bio ?? '').trim();
    final musicProfileValue = musicProfileLabel(widget.appUser?.musicProfile);
    final needsEmailVerification =
        widget.user.provider == AuthProviderType.email &&
            !widget.user.emailVerified;

    return ListView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        16,
        widget.embeddedMode ? 10 : 14,
        16,
        widget.embeddedMode ? mixroomShellBottomPadding(context) : 20,
      ),
      children: [
        if (widget.embeddedMode)
          _EmbeddedAccountChrome(
            isEditing: _isEditing,
            onEditToggle: _handleEditToggle,
          )
        else
          _ProfileHero(
            user: widget.user,
            username: _usernameController.text,
            overrideName: _nameController.text,
            isEditing: _isEditing,
            onEditToggle: _handleEditToggle,
          ),
        if (needsEmailVerification) ...[
          const SizedBox(height: 10),
          _EmailVerificationBanner(
            busy: auth.isBusy,
            onVerifyNow: () async {
              await showEmailVerificationSheet(
                context,
                auth: context.read<AuthService>(),
              );
            },
            onResend: () async {
              try {
                await context.read<AuthService>().resendEmailVerification(
                      localeCode: Localizations.localeOf(context).languageCode,
                    );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        L10n.translate(context, 'Verification email sent.')),
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
        MixroomShellSurface(
          radius: 24,
          padding: EdgeInsets.zero,
          color: widget.embeddedMode
              ? (_isEditing
                  ? const Color.fromRGBO(244, 244, 244, 0.28)
                  : const Color.fromRGBO(244, 244, 244, 0.16))
              : const Color.fromRGBO(244, 244, 244, 0.08),
          child: Column(
            children: [
              _ReadonlyRow(label: 'Email', value: widget.user.email),
              _DividerLine(),
              _EditableNameRow(
                isEditing: _isEditing,
                controller: _nameController,
              ),
              _DividerLine(),
              _EditableUsernameRow(
                isEditing: _isEditing,
                controller: _usernameController,
                enabled: widget.canEditAppProfile,
                value: usernameValue.isEmpty
                    ? L10n.translate(context, 'Not set')
                    : usernameValue,
              ),
              _DividerLine(),
              _EditableMusicProfileRow(
                isEditing: _isEditing,
                enabled: widget.canEditAppProfile,
                value: musicProfileValue.isEmpty
                    ? L10n.translate(context, 'Not set')
                    : musicProfileValue,
                selectedValue: _musicProfileValue,
                onChanged: (next) {
                  setState(() {
                    _musicProfileValue = next;
                  });
                },
              ),
              _DividerLine(),
              _EditableBioRow(
                isEditing: _isEditing,
                controller: _bioController,
                enabled: widget.canEditAppProfile,
                value: bioValue.isEmpty
                    ? L10n.translate(context, 'No bio yet')
                    : bioValue,
              ),
              if (!widget.embeddedMode) ...[
                _DividerLine(),
                const _LanguagePreferenceRow(),
              ],
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
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              _syncFromUser();
                                              _isEditing = false;
                                            });
                                          },
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                          color: Colors.white.withOpacity(0.2)),
                                      foregroundColor: Colors.white70,
                                    ),
                                    child: Text(
                                      L10n.translate(context, 'Cancel'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: (_isSaving ||
                                            auth.isBusy ||
                                            appUserService.isLoading)
                                        ? null
                                        : () {
                                            HapticFeedback.mediumImpact();
                                            _save();
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3E82FF),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: Text(L10n.translate(
                                        context,
                                        _isSaving
                                            ? 'Saving...'
                                            : 'Save Changes')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.canEditAppProfile)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Text(
                                L10n.translate(
                                  context,
                                  'Username and bio save after the account backend is deployed.',
                                ),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _SubscriptionEntitlementCard(),
        const SizedBox(height: 12),
        _SignInMethodsCard(user: widget.user),
        const SizedBox(height: 12),
        _SecurityAccessCard(
          user: widget.user,
          auth: auth,
        ),
        const SizedBox(height: 12),
        _FeedbackEntryCard(
          onOpen: _openFeedbackComposer,
        ),
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
        if (widget.embeddedMode) ...[
          const SizedBox(height: 16),
          _EmbeddedLogoutButton(
            isBusy: auth.isBusy,
            onSignOut: widget.onSignOut,
          ),
        ],
      ],
    );
  }
}

class _EmbeddedAccountChrome extends StatelessWidget {
  const _EmbeddedAccountChrome({
    required this.isEditing,
    required this.onEditToggle,
  });

  final bool isEditing;
  final VoidCallback onEditToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            MixroomShellRoundButton(
              assetPath: isEditing
                  ? kMixroomShellAccountEditCheckAsset
                  : kMixroomShellAccountEditPencilAsset,
              iconExtent: isEditing ? 20 : 17,
              onTap: onEditToggle,
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onEditToggle,
              child: Text(
                L10n.translate(context, isEditing ? 'Finish' : 'Edit'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 15,
                  height: 22 / 15,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Spacer(),
            const MixroomLocaleSelector(),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isEditing
                ? const Color.fromRGBO(244, 244, 244, 0.30)
                : const Color.fromRGBO(244, 244, 244, 0.20),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: isEditing ? 0.12 : 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            kMixroomShellAccountProfileHeadAsset,
            width: 40,
            height: 40,
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _EmbeddedLogoutButton extends StatelessWidget {
  const _EmbeddedLogoutButton({
    required this.isBusy,
    required this.onSignOut,
  });

  final bool isBusy;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 212),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isBusy ? null : onSignOut,
            borderRadius: BorderRadius.circular(24),
            child: MixroomShellSurface(
              radius: 24,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              color: const Color.fromRGBO(84, 112, 143, 0.82),
              strong: true,
              child: SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: isBusy
                      ? const SizedBox(
                          key: ValueKey('logout_spinner_embedded'),
                          height: 22,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFF4F4F4),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Text(
                          key: const ValueKey('logout_text_embedded'),
                          L10n.translate(context, 'Log Out'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 15,
                            height: 22 / 15,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailVerificationBanner extends StatelessWidget {
  const _EmailVerificationBanner({
    required this.busy,
    required this.onVerifyNow,
    required this.onResend,
  });

  final bool busy;
  final Future<void> Function() onVerifyNow;
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
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: busy ? null : onVerifyNow,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFFFFD774),
                      ),
                      child: Text(
                        L10n.translate(context, 'Verify now'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
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
                            : L10n.translate(
                                context,
                                'Resend verification email',
                              ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInMethodsCard extends StatelessWidget {
  const _SignInMethodsCard({
    required this.user,
  });

  final AuthUserProfile user;

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
          Text(
            L10n.translate(context, 'Sign-In Methods'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _SignInMethodRow(
            provider: AuthProviderType.email,
            stateLabel: user.provider == AuthProviderType.email
                ? 'Current'
                : 'Optional later',
            active: user.provider == AuthProviderType.email,
          ),
          const SizedBox(height: 8),
          _SignInMethodRow(
            provider: AuthProviderType.google,
            stateLabel: user.provider == AuthProviderType.google
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.google,
          ),
          const SizedBox(height: 8),
          _SignInMethodRow(
            provider: AuthProviderType.apple,
            stateLabel: user.provider == AuthProviderType.apple
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.apple,
          ),
          const SizedBox(height: 8),
          _SignInMethodRow(
            provider: AuthProviderType.kakao,
            stateLabel: user.provider == AuthProviderType.kakao
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.kakao,
          ),
          const SizedBox(height: 10),
          Text(
            L10n.translate(
              context,
              'This page shows your current sign-in method. More linking options can come later.',
            ),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInMethodRow extends StatelessWidget {
  const _SignInMethodRow({
    required this.provider,
    required this.stateLabel,
    required this.active,
  });

  final AuthProviderType provider;
  final String stateLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2E65D8).withOpacity(0.22)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? const Color(0xFF76A2FF).withOpacity(0.55)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            provider.label.substring(0, 1),
            style: TextStyle(
              color: active ? const Color(0xFFC9DBFF) : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            provider.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2E65D8).withOpacity(0.22)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? const Color(0xFF76A2FF).withOpacity(0.55)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Text(
            L10n.translate(context, stateLabel),
            style: TextStyle(
              color: active ? const Color(0xFFC9DBFF) : Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.username,
    required this.overrideName,
    required this.isEditing,
    required this.onEditToggle,
  });

  final AuthUserProfile user;
  final String username;
  final String overrideName;
  final bool isEditing;
  final VoidCallback? onEditToggle;

  @override
  Widget build(BuildContext context) {
    final displayName =
        overrideName.trim().isEmpty ? user.displayName : overrideName;
    final safeUsername = username.trim().toLowerCase();

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
                if (safeUsername.isNotEmpty) ...[
                  Text(
                    safeUsername,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
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
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
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

class _EditableUsernameRow extends StatelessWidget {
  const _EditableUsernameRow({
    required this.isEditing,
    required this.controller,
    required this.enabled,
    required this.value,
  });

  final bool isEditing;
  final TextEditingController controller;
  final bool enabled;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'Username', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'Username'),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  enabled: enabled,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9_-]'),
                    ),
                    LengthLimitingTextInputFormatter(30),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: L10n.translate(context, 'your_username'),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.12)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.08)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide:
                          BorderSide(color: Color(0xFF5F96FF), width: 1.1),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  enabled
                      ? L10n.translate(
                          context,
                          '1-30 chars. Lowercase letters, numbers, underscores, and hyphens.',
                        )
                      : L10n.translate(
                          context,
                          'Available after the account backend is deployed.',
                        ),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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

class _EditableBioRow extends StatelessWidget {
  const _EditableBioRow({
    required this.isEditing,
    required this.controller,
    required this.enabled,
    required this.value,
  });

  final bool isEditing;
  final TextEditingController controller;
  final bool enabled;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'Bio', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'Bio'),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              minLines: 2,
              maxLines: 3,
              maxLength: 160,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                counterStyle: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                hintText: L10n.translate(
                  context,
                  'Tell listeners what you make.',
                ),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                filled: true,
                fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
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

class _EditableMusicProfileRow extends StatelessWidget {
  const _EditableMusicProfileRow({
    required this.isEditing,
    required this.enabled,
    required this.value,
    required this.selectedValue,
    required this.onChanged,
  });

  final bool isEditing;
  final bool enabled;
  final String value;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'You are', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'You are'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              key: ValueKey<String>(selectedValue ?? '__unset__'),
              initialValue: selectedValue,
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(L10n.translate(context, 'Not set')),
                ),
                ...kMusicProfileOptions.map(
                  (option) => DropdownMenuItem<String?>(
                    value: option.value,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: enabled ? onChanged : null,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              dropdownColor: kMixroomGlassDropdownMenuColor,
              iconEnabledColor: Colors.white70,
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.translate(context, 'Select one'),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                filled: true,
                fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
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

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(0.08));
  }
}

class _SubscriptionEntitlementCard extends StatelessWidget {
  const _SubscriptionEntitlementCard();

  @override
  Widget build(BuildContext context) {
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
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFA4C2FF),
              ),
              const SizedBox(width: 8),
              Text(
                L10n.translate(context, 'Subscription'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            L10n.translate(context, 'Subscriptions are not enabled yet.'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            L10n.translate(
              context,
              'When billing opens, you will be able to upgrade and manage your plan from this screen.',
            ),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: Colors.white54,
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              child: Text(L10n.translate(context, 'Coming soon')),
            ),
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

class _FeedbackEntryCard extends StatelessWidget {
  const _FeedbackEntryCard({
    required this.onOpen,
  });

  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return MixroomShellSurface(
      radius: 20,
      color: const Color.fromRGBO(244, 244, 244, 0.10),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF3E82FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: Color(0xFF9FC2FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Feedback / bug report'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.translate(
                    context,
                    'Tell us what is working, what is broken, or what you want to see next.',
                  ),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onOpen(),
                    borderRadius: BorderRadius.circular(22),
                    child: MixroomShellSurface(
                      radius: 22,
                      color: const Color.fromRGBO(244, 244, 244, 0.14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                L10n.translate(
                                  context,
                                  'Send feedback or bug report',
                                ),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _SecurityAccessCard extends StatelessWidget {
  const _SecurityAccessCard({
    required this.user,
    required this.auth,
  });

  final AuthUserProfile user;
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final isEmailAccount = user.provider == AuthProviderType.email;
    final providerLabel = user.provider.label;
    final email = user.email.trim();
    final socialDescription = email.isEmpty
        ? 'You sign in with $providerLabel.'
        : 'You sign in with $providerLabel using $email.';
    final socialSupportingText = email.isEmpty
        ? 'If you want to add a password later, sign out and use Forgot password from the sign-in screen.'
        : 'If you want to add a password later, sign out and use Forgot password with that email on the sign-in screen.';

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
          const Icon(Icons.lock_outline_rounded, color: Color(0xFFA4C2FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Password'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.translate(
                    context,
                    isEmailAccount
                        ? 'You sign in with email and password.'
                        : socialDescription,
                  ),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                if (!isEmailAccount) ...[
                  const SizedBox(height: 6),
                  Text(
                    L10n.translate(
                      context,
                      socialSupportingText,
                    ),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isEmailAccount)
            TextButton(
              onPressed: auth.isBusy
                  ? null
                  : () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _ChangePasswordSheet(auth: auth),
                      );
                    },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBBD2FF),
                minimumSize: const Size(0, 34),
              ),
              child: Text(L10n.translate(context, 'Change')),
            ),
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({
    required this.auth,
  });

  final AuthService auth;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.trim().isEmpty) {
      _showSnack('Please enter your current password.');
      return;
    }
    final passwordIssue = PasswordPolicy.validate(newPassword);
    if (passwordIssue != null) {
      _showSnack(passwordIssue);
      return;
    }
    if (newPassword != confirmPassword) {
      _showSnack('Passwords do not match.');
      return;
    }
    if (currentPassword == newPassword) {
      _showSnack('New password must be different from current password.');
      return;
    }

    try {
      await widget.auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(L10n.translate(context, 'Password updated successfully.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.translate(context, message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        final busy = widget.auth.isBusy;
        final insets = MediaQuery.of(context).viewInsets;

        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F2038),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.30),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    L10n.translate(context, 'Change Password'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.translate(
                      context,
                      PasswordPolicy.requirementsText(),
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PasswordField(
                    label: 'Current Password',
                    hint: 'Enter current password',
                    controller: _currentPasswordController,
                    obscureText: _hideCurrentPassword,
                    onToggleVisibility: () => setState(
                      () => _hideCurrentPassword = !_hideCurrentPassword,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PasswordField(
                    label: 'New Password',
                    hint: 'At least ${PasswordPolicy.minLength} characters',
                    controller: _newPasswordController,
                    obscureText: _hideNewPassword,
                    onToggleVisibility: () => setState(
                      () => _hideNewPassword = !_hideNewPassword,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PasswordField(
                    label: 'Confirm New Password',
                    hint: 'Re-enter password',
                    controller: _confirmPasswordController,
                    obscureText: _hideConfirmPassword,
                    onToggleVisibility: () => setState(
                      () => _hideConfirmPassword = !_hideConfirmPassword,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3E82FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        L10n.translate(
                          context,
                          busy ? 'Updating...' : 'Update Password',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.obscureText,
    required this.onToggleVisibility,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.translate(context, label),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: L10n.translate(context, hint),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            suffixIcon: IconButton(
              onPressed: onToggleVisibility,
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: Colors.white70,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4F8BFF)),
            ),
          ),
        ),
      ],
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
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              L10n.translate(
                context,
                'Project files are stored locally.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isBusy ? null : onSignOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBE3E3E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: isBusy
                    ? const SizedBox(
                        key: ValueKey('logout_spinner_footer'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        key: const ValueKey('logout_label_footer'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.logout_rounded),
                          const SizedBox(width: 8),
                          Text(
                            L10n.translate(context, 'Log Out'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
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
  return parts.first[0].toUpperCase();
}
