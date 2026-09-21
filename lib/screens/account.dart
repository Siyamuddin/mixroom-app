import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/config/llm_config.dart';
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/feedback_service.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/helpers/password_policy.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/helpers/profile_avatar_codec.dart';
import 'package:mixroom/helpers/profile_avatar_picker.dart';
import 'package:mixroom/helpers/project_version_preferences.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/music_profile_option.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/legal_privacy_center.dart';
import 'package:mixroom/widgets/app_responsive_body.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:mixroom/widgets/account_subscription_surface.dart';
import 'package:mixroom/widgets/account_glass_ui.dart';
import 'package:mixroom/widgets/email_verification_sheet.dart';
import 'package:mixroom/widgets/language_selector.dart';
import 'package:mixroom/widgets/mixroom_glass_dropdown.dart';
import 'package:mixroom/widgets/mixroom_profile_avatar.dart';
import 'package:mixroom/widgets/remote_welcome_onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    this.showTopBar = true,
    this.enforceProfileCompletion = false,
    this.scrollToTopSignal = 0,
  });

  final bool showTopBar;
  final bool enforceProfileCompletion;
  final int scrollToTopSignal;

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
                          scrollToTopSignal: scrollToTopSignal,
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
                            scrollToTopSignal: scrollToTopSignal,
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
                  await Future<void>.delayed(const Duration(milliseconds: 180));
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
    required this.scrollToTopSignal,
    this.onSignOut,
  });

  final AuthUserProfile user;
  final AppUserSnapshot? appUser;
  final bool canEditAppProfile;
  final bool enforceProfileCompletion;
  final bool embeddedMode;
  final int scrollToTopSignal;
  final Future<void> Function()? onSignOut;

  @override
  State<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<_AccountBody> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _birthdateController;
  late TextEditingController _bioController;
  final ScrollController _scrollController = ScrollController();
  String? _musicProfileValue;
  DateTime? _selectedBirthdateUtc;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isAvatarBusy = false;
  bool _isAvatarFlowOpen = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _usernameController = TextEditingController();
    _birthdateController = TextEditingController();
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
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal) {
      _scrollToTop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _birthdateController.dispose();
    _bioController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _syncFromUser() {
    _nameController.text = widget.user.displayName;
    _usernameController.text = widget.appUser?.username ?? '';
    _bioController.text = widget.appUser?.bio ?? '';
    _musicProfileValue = (widget.appUser?.musicProfile ?? '').trim().isEmpty
        ? null
        : widget.appUser?.musicProfile;
    final rawBirthdate = (widget.appUser?.birthdate ?? '').trim();
    _selectedBirthdateUtc = _parseStoredBirthdate(rawBirthdate);
    _birthdateController.text = _selectedBirthdateUtc == null
        ? rawBirthdate
        : _formatBirthdate(_selectedBirthdateUtc!);
  }

  bool get _hasAuthChanges {
    return _nameController.text.trim() != widget.user.displayName.trim();
  }

  bool get _hasAppProfileChanges {
    return _usernameController.text.trim() !=
            (widget.appUser?.username ?? '').trim() ||
        _birthdateController.text.trim() !=
            (widget.appUser?.birthdate ?? '').trim() ||
        _bioController.text.trim() != (widget.appUser?.bio ?? '').trim() ||
        ((_musicProfileValue ?? '').trim().toLowerCase() !=
            (widget.appUser?.musicProfile ?? '').trim().toLowerCase());
  }

  String? _validateBirthdate(BuildContext context, DateTime? birthdateUtc) {
    if (birthdateUtc == null) return null;
    final latestAllowed = _latestAllowedBirthdateUtc();
    if (birthdateUtc.isAfter(latestAllowed)) {
      return L10n.translate(
        context,
        'You must be at least {age} years old to use Mixroom.',
      ).replaceAll('{age}', '${LegalConfig.minimumSignupAgeYears}');
    }
    return null;
  }

  DateTime _latestAllowedBirthdateUtc() {
    final now = DateTime.now().toUtc();
    final normalizedNow = DateTime.utc(now.year, now.month, now.day);
    return DateTime.utc(
      normalizedNow.year - LegalConfig.minimumSignupAgeYears,
      normalizedNow.month,
      normalizedNow.day,
    );
  }

  DateTime _earliestSelectableBirthdateUtc() {
    final latestAllowed = _latestAllowedBirthdateUtc();
    return DateTime.utc(latestAllowed.year - 120, 1, 1);
  }

  String _formatBirthdate(DateTime birthdateUtc) {
    final year = birthdateUtc.year.toString().padLeft(4, '0');
    final month = birthdateUtc.month.toString().padLeft(2, '0');
    final day = birthdateUtc.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DateTime _defaultBirthdateForPickerUtc() {
    final now = DateTime.now().toUtc();
    final defaultDate = DateTime.utc(now.year - 18, now.month, now.day);
    final first = _earliestSelectableBirthdateUtc();
    final last = _latestAllowedBirthdateUtc();
    if (defaultDate.isBefore(first)) return first;
    if (defaultDate.isAfter(last)) return last;
    return defaultDate;
  }

  Future<void> _pickBirthdate() async {
    final initialDate =
        _selectedBirthdateUtc ?? _defaultBirthdateForPickerUtc();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _earliestSelectableBirthdateUtc(),
      lastDate: _latestAllowedBirthdateUtc(),
      helpText: L10n.translate(context, 'Select birthday'),
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      _selectedBirthdateUtc = normalized;
      _birthdateController.text = _formatBirthdate(normalized);
    });
  }

  void _clearBirthdate() {
    setState(() {
      _selectedBirthdateUtc = null;
      _birthdateController.clear();
    });
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
    final safeBirthdate = _birthdateController.text.trim();
    final safeBio = _bioController.text.trim();
    if (safeName.isEmpty) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Name cannot be empty.'),
      );
      return;
    }
    final birthdateError = _validateBirthdate(context, _selectedBirthdateUtc);
    if (birthdateError != null) {
      showAppSnackBar(context, birthdateError);
      return;
    }
    if (_isSaving) return;
    if (!widget.canEditAppProfile && _hasAppProfileChanges) {
      showAppSnackBar(
        context,
        L10n.translate(
          context,
          'Username, birthday, and bio require the deployed account backend before they can be saved.',
        ),
      );
      return;
    }
    if (!_hasAuthChanges && !_hasAppProfileChanges) {
      setState(() => _isEditing = false);
      return;
    }

    final updated = widget.user.copyWith(displayName: safeName);
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
          birthdate: safeBirthdate,
          musicProfile: _musicProfileValue,
          bio: safeBio,
        );
      }
      if (!mounted) return;
      setState(() => _isEditing = false);
      showAppSnackBar(context, L10n.translate(context, 'Account updated.'));
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String? get _avatarUrl {
    final url = widget.appUser?.avatarUrl?.trim() ?? '';
    return url.isEmpty ? null : url;
  }

  void _showProfileBackendUnavailable() {
    showAppSnackBar(
      context,
      'Username, birthday, and bio require the deployed account backend before they can be saved.',
    );
  }

  Future<void> _onAvatarTap() async {
    if (_isAvatarBusy || _isAvatarFlowOpen) return;
    if (!widget.canEditAppProfile) {
      _showProfileBackendUnavailable();
      return;
    }
    final avatarUrl = _avatarUrl;
    if (avatarUrl != null) {
      await showMixroomProfileAvatarViewer(
        context: context,
        avatarUrl: avatarUrl,
        onChangePhoto: () {
          unawaited(_changeAvatar());
        },
        onRemovePhoto: () {
          unawaited(_removeAvatar());
        },
      );
      return;
    }
    await _changeAvatar();
  }

  Future<void> _changeAvatar() async {
    if (_isAvatarBusy || _isAvatarFlowOpen) return;
    if (!widget.canEditAppProfile) {
      _showProfileBackendUnavailable();
      return;
    }

    _isAvatarFlowOpen = true;
    Uint8List? cropped;
    try {
      cropped = await ProfileAvatarPicker.pickAndCrop(context);
    } on PlatformException catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        ProfileAvatarPicker.messageForPickerError(error, null) ??
            "Couldn't read that image.",
      );
      return;
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, "Couldn't read that image.");
      return;
    } finally {
      _isAvatarFlowOpen = false;
    }
    if (cropped == null || !mounted) return;

    setState(() => _isAvatarBusy = true);
    try {
      final encoded = await compute(
        ProfileAvatarCodec.encodeJpegIsolate,
        cropped,
      );
      final error = encoded['error'] as String?;
      if (error != null) {
        throw ProfileAvatarCodecException(error);
      }
      final jpeg = encoded['bytes'] as Uint8List?;
      if (jpeg == null || jpeg.isEmpty) {
        throw const ProfileAvatarCodecException("Couldn't read that image.");
      }
      await context.read<AppUserService>().uploadAvatar(jpeg);
      if (!mounted) return;
      showAppSnackBar(context, 'Photo updated');
    } on ProfileAvatarCodecException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isAvatarBusy = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_isAvatarBusy || _isAvatarFlowOpen) return;
    if (!widget.canEditAppProfile) {
      _showProfileBackendUnavailable();
      return;
    }

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text(L10n.translate(context, 'Remove profile photo?')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(L10n.translate(context, 'Cancel')),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(L10n.translate(context, 'Remove')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isAvatarBusy = true);
    try {
      await context.read<AppUserService>().deleteAvatar();
      if (!mounted) return;
      showAppSnackBar(context, 'Photo removed');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isAvatarBusy = false);
      }
    }
  }

  Future<void> _openFeedbackComposer() async {
    final authService = context.read<AuthService>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogContext) {
        return MediaQuery.removeViewInsets(
          context: dialogContext,
          removeBottom: true,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 440,
                  maxHeight: 760,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(29, 33, 36, 0.96),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.56),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
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

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _AccountSettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final appUserService = context.watch<AppUserService>();
    final joinedAt = widget.embeddedMode
        ? _formatCompactDate(widget.user.createdAt.toLocal())
        : _formatReadableDate(context, widget.user.createdAt.toLocal());
    final birthdayValue = widget.embeddedMode
        ? _formatStoredBirthdateCompact(context, widget.appUser?.birthdate)
        : _formatStoredBirthdateForDisplay(context, widget.appUser?.birthdate);
    final usernameValue = (widget.appUser?.username ?? '').trim();
    final musicProfileLabelText = musicProfileLabel(
      widget.appUser?.musicProfile,
    );
    final musicProfileValue = musicProfileLabelText.isEmpty
        ? ''
        : L10n.translate(context, musicProfileLabelText);
    final needsEmailVerification =
        widget.user.provider == AuthProviderType.email &&
        !widget.user.emailVerified;

    final horizontalPadding = widget.embeddedMode ? 27.0 : 16.0;

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        widget.embeddedMode ? 10 : 14,
        horizontalPadding,
        widget.embeddedMode ? mixroomShellBottomPadding(context) : 20,
      ),
      children: [
        if (widget.embeddedMode)
          _EmbeddedAccountChrome(
            isEditing: _isEditing,
            onEditToggle: _handleEditToggle,
            onOpenSettings: _openSettings,
            avatarUrl: _avatarUrl,
            isAvatarBusy: _isAvatarBusy,
            onAvatarTap: _onAvatarTap,
          )
        else
          _ProfileHero(
            user: widget.user,
            username: _usernameController.text,
            overrideName: _nameController.text,
            isEditing: _isEditing,
            onEditToggle: _handleEditToggle,
            avatarUrl: _avatarUrl,
            isAvatarBusy: _isAvatarBusy,
            onAvatarTap: _onAvatarTap,
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
                      L10n.translate(context, 'Verification email sent.'),
                    ),
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
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _ReferenceProfileDetails(
              email: widget.user.email,
              username: usernameValue,
              nameController: _nameController,
              usernameController: _usernameController,
              bioController: _bioController,
              birthdayValue: birthdayValue,
              musicProfileValue: musicProfileValue,
              selectedMusicProfile: _musicProfileValue,
              joinedAt: joinedAt,
              isEditing: _isEditing,
              canEditAppProfile: widget.canEditAppProfile,
              onPickBirthdate: _pickBirthdate,
              onMusicProfileChanged: (next) {
                setState(() => _musicProfileValue = next);
              },
            ),
          ),
        ),
        if (widget.embeddedMode && _isEditing) ...[
          const SizedBox(height: 12),
          _ReferenceProfileDoneButton(
            isBusy: _isSaving || auth.isBusy || appUserService.isLoading,
            onPressed: _handleEditToggle,
          ),
        ],
        if (widget.embeddedMode) ...[
          SizedBox(height: _isEditing ? 32 : 64),
          const _AccountDetailsHeading(),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 12),
        const _SubscriptionEntitlementCard(),
        const SizedBox(height: 28),
        AccountSectionHeading(
          title: L10n.translate(context, 'Sign-In | Password'),
          subtitle: L10n.translate(
            context,
            'Authentication methods and account security',
          ),
        ),
        const SizedBox(height: 12),
        _SignInMethodsCard(user: widget.user),
        const SizedBox(height: 12),
        _SecurityAccessCard(user: widget.user, auth: auth),
        const SizedBox(height: 28),
        AccountSectionHeading(
          title: L10n.translate(context, 'Help & Privacy'),
          subtitle: L10n.translate(
            context,
            'Feedback, documents, privacy controls, and data rights',
          ),
        ),
        const SizedBox(height: 12),
        _FeedbackEntryCard(onOpen: _openFeedbackComposer),
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
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          const _DebugOnboardingCard(),
        ],
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

class _DebugOnboardingCard extends StatelessWidget {
  const _DebugOnboardingCard();

  Future<void> _openWelcomeOnboarding(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => RemoteWelcomeOnboardingScreen(
          onCompleted: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MixroomShellSurface(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      color: const Color.fromRGBO(244, 244, 244, 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Debug Onboarding',
            style: TextStyle(
              color: Color(0xFFF4F4F4),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Visible only in debug builds. Opens onboarding flows without resetting stored state.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _openWelcomeOnboarding(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF54708F),
                foregroundColor: const Color(0xFFF4F4F4),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                'Open Welcome Onboarding',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedAccountChrome extends StatelessWidget {
  const _EmbeddedAccountChrome({
    required this.isEditing,
    required this.onEditToggle,
    required this.onOpenSettings,
    this.avatarUrl,
    this.isAvatarBusy = false,
    this.onAvatarTap,
  });

  final bool isEditing;
  final VoidCallback onEditToggle;
  final VoidCallback onOpenSettings;
  final String? avatarUrl;
  final bool isAvatarBusy;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: _AccountLocaleButton(),
              ),
              Text(
                L10n.translate(context, 'My Profile'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: MixroomShellRoundButton(
                  size: 48,
                  icon: const Icon(
                    Icons.settings_rounded,
                    size: 24,
                    color: Color(0xFFF4F4F4),
                  ),
                  onTap: onOpenSettings,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 4,
                  top: 4,
                  child: MixroomProfileAvatar(
                    size: 104,
                    avatarUrl: avatarUrl,
                    isBusy: isAvatarBusy,
                    onTap: onAvatarTap,
                    backgroundColor: const Color(0xFF4A4E50),
                    emptyChild: Center(
                      child: SvgPicture.asset(
                        kMixroomShellAccountProfileHeadAsset,
                        width: 54,
                        height: 54,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: MixroomShellRoundButton(
                    size: 46,
                    assetPath: kMixroomShellAccountEditPencilAsset,
                    iconExtent: 19,
                    onTap: isEditing ? null : onEditToggle,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _AccountLocaleButton extends StatelessWidget {
  const _AccountLocaleButton();

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final locale = L10n.resolveSupportedLocale(localeProvider.locale);
    final asset = switch (locale.languageCode) {
      'ko' => kMixroomLocaleFlagKoAsset,
      'ja' => kMixroomLocaleFlagJaAsset,
      _ => kMixroomLocaleFlagEnAsset,
    };
    return PopupMenuButton<Locale>(
      tooltip: L10n.translate(context, 'Language'),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 10),
      color: const Color(0xFF303638),
      surfaceTintColor: Colors.transparent,
      onSelected: (selected) => L10n.setLocale(context, selected),
      itemBuilder: (context) => L10n.supportedLocales
          .map(
            (supported) => PopupMenuItem<Locale>(
              value: supported,
              child: Text(
                '${L10n.languageFlag(supported)}  ${L10n.languageName(supported)}',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 14,
                ),
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(100, 100, 100, 0.62),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.32),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SvgPicture.asset(asset, width: 25, height: 25),
      ),
    );
  }
}

class _ReferenceProfileDetails extends StatelessWidget {
  const _ReferenceProfileDetails({
    required this.email,
    required this.username,
    required this.nameController,
    required this.usernameController,
    required this.bioController,
    required this.birthdayValue,
    required this.musicProfileValue,
    required this.selectedMusicProfile,
    required this.joinedAt,
    required this.isEditing,
    required this.canEditAppProfile,
    required this.onPickBirthdate,
    required this.onMusicProfileChanged,
  });

  final String email;
  final String username;
  final TextEditingController nameController;
  final TextEditingController usernameController;
  final TextEditingController bioController;
  final String birthdayValue;
  final String musicProfileValue;
  final String? selectedMusicProfile;
  final String joinedAt;
  final bool isEditing;
  final bool canEditAppProfile;
  final VoidCallback onPickBirthdate;
  final ValueChanged<String?> onMusicProfileChanged;

  @override
  Widget build(BuildContext context) {
    final notSet = L10n.translate(context, 'Not set');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReferenceGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReferenceProfileField(label: 'Email', value: email),
              const _ReferenceProfileDivider(),
              _ReferenceProfileField(
                label: 'Username',
                value: username.isEmpty ? notSet : username,
                controller: usernameController,
                editing: isEditing && canEditAppProfile,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                  LengthLimitingTextInputFormatter(30),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ReferenceGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReferenceProfileField(
                label: 'Name',
                value: nameController.text,
                controller: nameController,
                editing: isEditing,
              ),
              const _ReferenceProfileDivider(),
              _ReferenceProfileField(
                label: 'Bio',
                value: bioController.text.trim().isEmpty
                    ? L10n.translate(context, 'No bio yet')
                    : bioController.text,
                controller: bioController,
                editing: isEditing && canEditAppProfile,
                maxLength: 160,
              ),
              const _ReferenceProfileDivider(),
              _ReferenceProfileField(
                label: 'Birthday',
                value: birthdayValue,
                onTap: isEditing && canEditAppProfile ? onPickBirthdate : null,
              ),
              const _ReferenceProfileDivider(),
              _ReferenceMusicProfileField(
                value: musicProfileValue.isEmpty ? notSet : musicProfileValue,
                selectedValue: selectedMusicProfile,
                editing: isEditing && canEditAppProfile,
                onChanged: onMusicProfileChanged,
              ),
              const _ReferenceProfileDivider(),
              _ReferenceProfileField(label: 'Joined', value: joinedAt),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferenceGlassCard extends StatelessWidget {
  const _ReferenceGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: child,
    );
  }
}

class _ReferenceProfileDivider extends StatelessWidget {
  const _ReferenceProfileDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 0.8, color: Colors.white.withValues(alpha: 0.48));
  }
}

class _ReferenceProfileField extends StatelessWidget {
  const _ReferenceProfileField({
    required this.label,
    required this.value,
    this.controller,
    this.editing = false,
    this.onTap,
    this.inputFormatters,
    this.maxLength,
  });

  final String label;
  final String value;
  final TextEditingController? controller;
  final bool editing;
  final VoidCallback? onTap;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(
      fontFamily: 'Pretendard',
      color: Color(0xFFF4F4F4),
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.15,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              L10n.translate(context, label),
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 11.5,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            if (editing && controller != null)
              SizedBox(
                height: 22,
                child: TextField(
                  controller: controller,
                  inputFormatters: inputFormatters,
                  maxLength: maxLength,
                  style: valueStyle,
                  cursorColor: const Color(0xFFF4F4F4),
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              )
            else
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceMusicProfileField extends StatelessWidget {
  const _ReferenceMusicProfileField({
    required this.value,
    required this.selectedValue,
    required this.editing,
    required this.onChanged,
  });

  final String value;
  final String? selectedValue;
  final bool editing;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            L10n.translate(context, 'Using Mixroom for'),
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.56),
              fontSize: 11.5,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          if (editing)
            SizedBox(
              height: 24,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:
                      kMusicProfileOptions.any(
                        (option) => option.value == selectedValue,
                      )
                      ? selectedValue
                      : null,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF3E4447),
                  iconEnabledColor: Colors.white70,
                  hint: Text(
                    L10n.translate(context, 'Not set'),
                    style: const TextStyle(color: Color(0xFFF4F4F4)),
                  ),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 15.5,
                  ),
                  items: kMusicProfileOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option.value,
                          child: Text(L10n.translate(context, option.label)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onChanged,
                ),
              ),
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Color(0xFFF4F4F4),
                fontSize: 15.5,
                height: 1.15,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceProfileDoneButton extends StatelessWidget {
  const _ReferenceProfileDoneButton({
    required this.isBusy,
    required this.onPressed,
  });

  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 124,
        height: 48,
        child: FilledButton(
          onPressed: isBusy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color.fromRGBO(89, 111, 128, 0.94),
            disabledBackgroundColor: const Color.fromRGBO(89, 111, 128, 0.58),
            foregroundColor: const Color(0xFFF4F4F4),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.38),
                width: 0.8,
              ),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: isBusy
                ? const SizedBox(
                    key: ValueKey<String>('profile-saving'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF4F4F4),
                    ),
                  )
                : Text(
                    key: const ValueKey<String>('profile-done'),
                    L10n.translate(context, 'Done'),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AccountDetailsHeading extends StatelessWidget {
  const _AccountDetailsHeading();

  @override
  Widget build(BuildContext context) {
    return Text(
      L10n.translate(context, 'Subscription'),
      style: const TextStyle(
        fontFamily: 'Pretendard',
        color: Color(0xFFF4F4F4),
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EmbeddedLogoutButton extends StatelessWidget {
  const _EmbeddedLogoutButton({required this.isBusy, required this.onSignOut});

  final bool isBusy;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 212),
        child: Container(
          decoration: accountGlassDecoration(
            radius: 24,
            strong: true,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isBusy ? null : onSignOut,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
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
                                    kAccountGlassText,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Row(
                            key: const ValueKey('logout_text_embedded'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.logout_rounded,
                                size: 18,
                                color: kAccountGlassText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                L10n.translate(context, 'Log Out'),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: kAccountGlassText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 22 / 15,
                                ),
                              ),
                            ],
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
          const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFFE8C86D),
            size: 18,
          ),
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
                  L10n.translate(
                    context,
                    'Please verify your email for better account security.',
                  ),
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
  const _SignInMethodsCard({required this.user});

  final AuthUserProfile user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.translate(context, 'Sign-In Methods'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _SignInMethodRow(
            provider: AuthProviderType.email,
            stateLabel: user.provider == AuthProviderType.email
                ? 'Current'
                : 'Optional later',
            active: user.provider == AuthProviderType.email,
          ),
          const AccountGlassDivider(indent: 42),
          _SignInMethodRow(
            provider: AuthProviderType.google,
            stateLabel: user.provider == AuthProviderType.google
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.google,
          ),
          const AccountGlassDivider(indent: 42),
          _SignInMethodRow(
            provider: AuthProviderType.apple,
            stateLabel: user.provider == AuthProviderType.apple
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.apple,
          ),
          const AccountGlassDivider(indent: 42),
          _SignInMethodRow(
            provider: AuthProviderType.kakao,
            stateLabel: user.provider == AuthProviderType.kakao
                ? 'Current'
                : 'Not linked',
            active: user.provider == AuthProviderType.kakao,
          ),
          const SizedBox(height: 12),
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
    final providerLabel = L10n.translate(context, provider.label);
    final icon = switch (provider) {
      AuthProviderType.email => Icons.mail_outline_rounded,
      AuthProviderType.apple => Icons.apple,
      AuthProviderType.kakao => Icons.chat_bubble_rounded,
      _ => null,
    };
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: icon == null
                ? const Text(
                    'G',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kAccountGlassText,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Icon(icon, color: kAccountGlassText, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              providerLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            L10n.translate(context, stateLabel),
            style: TextStyle(
              color: active ? kAccountGlassText : kAccountGlassSubtleText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
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
    required this.username,
    required this.overrideName,
    required this.isEditing,
    required this.onEditToggle,
    this.avatarUrl,
    this.isAvatarBusy = false,
    this.onAvatarTap,
  });

  final AuthUserProfile user;
  final String username;
  final String overrideName;
  final bool isEditing;
  final VoidCallback? onEditToggle;
  final String? avatarUrl;
  final bool isAvatarBusy;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final displayName = overrideName.trim().isEmpty
        ? user.displayName
        : overrideName;
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
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
            child: MixroomProfileAvatar(
              size: 60,
              avatarUrl: avatarUrl,
              initials: _initials(displayName),
              isBusy: isAvatarBusy,
              onTap: onAvatarTap,
              backgroundColor: Colors.white.withValues(alpha: 0.20),
              borderColor: Colors.white.withValues(alpha: 0.42),
              initialsStyle: const TextStyle(
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
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
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
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
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(
                        color: Color(0xFF5F96FF),
                        width: 1.1,
                      ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
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

class _EditableBirthdayRow extends StatelessWidget {
  const _EditableBirthdayRow({
    required this.isEditing,
    required this.enabled,
    required this.controller,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final bool isEditing;
  final bool enabled;
  final TextEditingController controller;
  final String value;
  final Future<void> Function() onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return _ReadonlyRow(label: 'Birthday', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'Birthday'),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  enabled: enabled,
                  readOnly: true,
                  onTap: enabled ? onPick : null,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: L10n.translate(context, 'Select birthday'),
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(enabled ? 0.06 : 0.03),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      borderSide: BorderSide(
                        color: Color(0xFF5F96FF),
                        width: 1.1,
                      ),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (controller.text.trim().isNotEmpty)
                          IconButton(
                            onPressed: enabled ? onClear : null,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        IconButton(
                          onPressed: enabled ? onPick : null,
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    suffixIconConstraints: const BoxConstraints(),
                  ),
                ),
                if (!enabled) ...[
                  const SizedBox(height: 6),
                  Text(
                    L10n.translate(
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
              ],
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
      return _ReadonlyRow(label: 'What describes you', value: value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccountFieldLabel(label: 'What describes you'),
          const SizedBox(width: 8),
          Expanded(
            child: _MusicProfileDropdown(
              enabled: enabled,
              selectedValue: selectedValue,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

const String _kMusicProfileUnsetMenuValue = '__unset_music_profile__';

class _MusicProfileDropdown extends StatelessWidget {
  const _MusicProfileDropdown({
    required this.enabled,
    required this.selectedValue,
    required this.onChanged,
  });

  final bool enabled;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalizedValue = (selectedValue ?? '').trim().toLowerCase();
    final selectedLabel = normalizedValue.isEmpty
        ? 'Not set'
        : musicProfileLabel(normalizedValue).isEmpty
        ? 'Not set'
        : musicProfileLabel(normalizedValue);
    final selectedMenuValue = normalizedValue.isEmpty
        ? _kMusicProfileUnsetMenuValue
        : normalizedValue;
    final menuOptions = <({String value, String label})>[
      (value: _kMusicProfileUnsetMenuValue, label: 'Not set'),
      ...kMusicProfileOptions.map(
        (option) => (value: option.value, label: option.label),
      ),
    ];

    Future<void> showProfileMenu(BuildContext anchorContext) async {
      if (!enabled) return;
      final selected = await showMixroomGlassDropdown<String>(
        anchorContext: anchorContext,
        child: Builder(
          builder: (menuContext) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: menuOptions
                    .map((option) {
                      final isSelected = option.value == selectedMenuValue;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(menuContext, option.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            border: isSelected
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  L10n.translate(context, option.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.76),
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF8FB5FF),
                                  size: 17,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            );
          },
        ),
      );
      if (selected == null) return;
      onChanged(selected == _kMusicProfileUnsetMenuValue ? null : selected);
    }

    return Builder(
      builder: (anchorContext) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => showProfileMenu(anchorContext) : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: enabled ? 0.06 : 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.08),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    L10n.translate(context, selectedLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: enabled
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.48),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: enabled ? 0.70 : 0.34),
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(0.08));
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
  EntitlementSnapshot? entitlement,
  BillingCatalogSnapshot? catalog,
  BillingProductDefinition product,
) {
  if (entitlement == null) {
    return const _PlanPurchaseContext(
      planCode: 'free',
      productCode: '',
      sourceProvider: BillingProvider.adminGrant,
      managementChannel: 'free',
      isAccessActive: true,
    );
  }
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

class _SubscriptionEntitlementCard extends StatefulWidget {
  const _SubscriptionEntitlementCard();

  @override
  State<_SubscriptionEntitlementCard> createState() =>
      _SubscriptionEntitlementCardState();
}

class _SubscriptionEntitlementCardState
    extends State<_SubscriptionEntitlementCard> {
  bool _didBootstrap = false;
  bool _actionBusy = false;
  String? _inlineMessage;
  IapService? _boundIapService;
  String? _lastShownIapError;
  BillingProductDefinition? _pendingIapProduct;
  DateTime? _lastHandledCompletedPurchaseAtUtc;
  CloudLlmService? _aiUsageService;
  AiPromptRateLimitStatus? _aiUsageStatus;
  bool _aiUsageLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aiUsageService ??= _createAiUsageService();
    final iapService = context.read<IapService>();
    if (!identical(_boundIapService, iapService)) {
      _boundIapService?.removeListener(_handleIapServiceChanged);
      _boundIapService = iapService;
      iapService.addListener(_handleIapServiceChanged);
    }
    if (_didBootstrap) return;
    _didBootstrap = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshData(silent: true));
    });
  }

  @override
  void dispose() {
    _boundIapService?.removeListener(_handleIapServiceChanged);
    _aiUsageService?.dispose();
    super.dispose();
  }

  CloudLlmService _createAiUsageService() {
    final authService = context.read<AuthService>();
    return CloudLlmService(
      proxyApiBaseUrl: LlmConfig.effectiveProxyApiBaseUrl,
      proxyPath: LlmConfig.proxyPath,
      requestTimeout: Duration(seconds: LlmConfig.requestTimeoutSeconds),
      authTokenProvider: authService.getIdTokenOrNull,
      refreshAuthTokenProvider: authService.refreshIdTokenOrNull,
    );
  }

  Future<void> _refreshAiUsage() async {
    final service = _aiUsageService;
    if (service == null) return;
    if (mounted) {
      setState(() => _aiUsageLoading = true);
    }
    final status = await service.fetchPromptRateLimitStatus();
    if (!mounted) return;
    setState(() {
      _aiUsageStatus = status;
      _aiUsageLoading = false;
    });
  }

  void _handleIapServiceChanged() {
    if (!mounted) return;
    final iapService = _boundIapService;
    final completedAt = iapService?.lastCompletedPurchaseAtUtc;
    if (completedAt != null &&
        completedAt != _lastHandledCompletedPurchaseAtUtc) {
      _lastHandledCompletedPurchaseAtUtc = completedAt;
      unawaited(_handleCompletedIapPurchase(iapService!));
    }
    final message = (iapService?.lastMessage ?? '').trim().toLowerCase();
    if (message.contains('purchase canceled')) {
      _pendingIapProduct = null;
    }
    final error = (iapService?.lastError ?? '').trim();
    if (error.isEmpty || error == _lastShownIapError) {
      return;
    }
    _pendingIapProduct = null;
    final displayError = _friendlyAccountActionError(error);
    _lastShownIapError = error;
    showAppSnackBar(
      context,
      L10n.translate(context, displayError),
      tone: AppPopupTone.error,
      duration: _billingErrorSnackBarDuration(displayError),
    );
  }

  Duration _billingErrorSnackBarDuration(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('different mixroom account') ||
        normalized.contains('already linked to another mixroom account')) {
      return const Duration(seconds: 10);
    }
    return const Duration(seconds: 5);
  }

  Future<void> _handleCompletedIapPurchase(IapService iapService) async {
    final entitlementService = context.read<EntitlementService>();
    final product = _pendingIapProduct;
    final purchaseMayBeDeferred = iapService.lastCompletedPurchaseMayBeDeferred;
    // This signal is only for the immediate post-purchase confirmation. Clear
    // it before awaiting refresh work so reopening Account cannot show it again.
    iapService.consumeCompletedPurchaseNotice();
    await entitlementService.refresh(force: true);
    await Future.wait(<Future<void>>[
      entitlementService.refreshAccountSurface(force: true),
      _refreshAiUsage(),
    ]);
    if (!mounted) return;
    final planLabel = _completedPurchasePlanLabel(
      product,
      entitlementService.entitlement,
      entitlementService.billingCatalog,
    );
    final shouldManage = await _showPurchaseCompleteDialog(
      planLabel: planLabel,
      provider: _platformProvider(_regionCode(context)),
      deferred: purchaseMayBeDeferred,
    );
    _pendingIapProduct = null;
    if (shouldManage == true && mounted) {
      final provider = _platformProvider(_regionCode(context));
      unawaited(
        _runAction(
          () => _handleManageSubscription(
            providerOverride: provider,
            managementChannelOverride: 'in_app',
          ),
        ),
      );
    }
  }

  String _completedPurchasePlanLabel(
    BillingProductDefinition? product,
    EntitlementSnapshot? entitlement,
    BillingCatalogSnapshot? catalog,
  ) {
    final productPlanCode = product?.planCode.trim() ?? '';
    if (productPlanCode.isNotEmpty) {
      final plan = catalog?.planByCode(productPlanCode);
      final productLabel = product?.label.trim() ?? '';
      return plan?.label.trim().isNotEmpty == true
          ? plan!.label.trim()
          : productLabel.isNotEmpty
          ? productLabel
          : defaultPlanLabelForCode(productPlanCode);
    }
    final entitlementLabel = entitlement?.effectivePlanLabel.trim() ?? '';
    if (entitlementLabel.isNotEmpty) {
      return entitlementLabel;
    }
    return 'your new plan';
  }

  Future<bool?> _showPurchaseCompleteDialog({
    required String planLabel,
    required BillingProvider provider,
    required bool deferred,
  }) {
    final localizedPlanLabel = L10n.translate(context, planLabel);
    final storeLabel = _storeManagementLabel(provider);
    final detail = deferred
        ? L10n.translate(
            context,
            'Your plan change is synced. Store-managed downgrades or billing-cycle changes may take effect at renewal.',
          )
        : L10n.translate(
            context,
            'Your subscription is active and Mixroom has applied your new access.',
          );
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF5F666D),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF67E8A5).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF67E8A5).withValues(alpha: 0.26),
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFFB9FFD8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  L10n.translate(context, 'Plan activated'),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${L10n.translate(context, 'You are now on')} $localizedPlanLabel.',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 13.2,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                storeLabel,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF258AE6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(L10n.translate(context, 'Done')),
            ),
          ],
        );
      },
    );
  }

  String _storeManagementLabel(BillingProvider provider) {
    switch (provider) {
      case BillingProvider.apple:
        return L10n.translate(context, 'Manage in App Store');
      case BillingProvider.google:
        return L10n.translate(context, 'Manage in Google Play');
      case BillingProvider.paddle:
      case BillingProvider.toss:
      case BillingProvider.kakao:
      case BillingProvider.adminGrant:
      case BillingProvider.unknown:
        return L10n.translate(context, 'Manage plan');
    }
  }

  Future<void> _refreshData({bool force = false, bool silent = false}) async {
    final entitlementService = context.read<EntitlementService>();
    await entitlementService.refreshFeatureFlags(force: force);
    await entitlementService.refresh(
      force: force || !entitlementService.isInitialized,
    );
    if (!mounted) return;
    if (!entitlementService.isAccountPlanBillingEnabled) {
      if (!silent) {
        showAppSnackBar(
          context,
          L10n.translate(context, 'Subscription details refreshed.'),
          tone: AppPopupTone.success,
        );
      }
      return;
    }
    final iapService = context.read<IapService>();
    final accountSurfaceFuture = entitlementService.refreshAccountSurface(
      force: force || !entitlementService.isAccountSurfaceInitialized,
    );
    Future<void>? iapRefreshFuture;
    if (iapService.isMobilePlatformSupported) {
      iapRefreshFuture = () async {
        final wasInitialized = iapService.isInitialized;
        await iapService.initialize();
        if (wasInitialized &&
            iapService.isInitialized &&
            iapService.isStoreAvailable) {
          await iapService.refreshProducts();
        }
      }();
    }
    await Future.wait(<Future<void>>[
      accountSurfaceFuture,
      _refreshAiUsage(),
      if (iapRefreshFuture != null) iapRefreshFuture,
    ]);
    if (!silent && mounted) {
      showAppSnackBar(
        context,
        L10n.translate(context, 'Subscription details refreshed.'),
        tone: AppPopupTone.success,
      );
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? progressMessage,
    String? successMessage,
  }) async {
    if (_actionBusy) return;
    setState(() {
      _actionBusy = true;
      _inlineMessage = null;
    });
    try {
      if ((progressMessage ?? '').trim().isNotEmpty && mounted) {
        showAppSnackBar(
          context,
          L10n.translate(context, progressMessage!),
          tone: AppPopupTone.info,
        );
      }
      await action();
      if (!mounted) return;
      if ((successMessage ?? '').trim().isNotEmpty) {
        final translatedSuccess = L10n.translate(context, successMessage!);
        showAppSnackBar(context, translatedSuccess, tone: AppPopupTone.success);
        setState(() {
          _inlineMessage = translatedSuccess;
        });
      }
    } catch (error) {
      final message = _friendlyAccountActionError(error);
      final translatedMessage = L10n.translate(context, message);
      if (!mounted) return;
      showAppSnackBar(context, translatedMessage, tone: AppPopupTone.error);
      setState(() {
        _inlineMessage = translatedMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _actionBusy = false;
        });
      }
    }
  }

  String _friendlyAccountActionError(Object error) {
    var raw = error.toString().trim();
    if (error is PlatformException) {
      raw = <String>[
        error.code,
        if ((error.message ?? '').trim().isNotEmpty) error.message!,
        if ((error.details ?? '').toString().trim().isNotEmpty)
          error.details.toString(),
      ].join(' ');
    }
    raw = raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    final normalized = raw.toLowerCase();
    if (normalized.contains('storekit') ||
        normalized.contains('in_app_purchase_storekit')) {
      return 'The App Store could not complete that request. Please try again.';
    }
    if (normalized.contains('billingclient') ||
        normalized.contains('billingresponse') ||
        normalized.contains('google play')) {
      return 'Google Play could not complete that request. Please try again.';
    }
    if (normalized.contains('platformexception') ||
        normalized.contains('pigeonerror') ||
        normalized.contains('stacktrace') ||
        normalized.contains('runner.debug.dylib') ||
        normalized.contains('fluttererror')) {
      return 'Something went wrong. Please try again.';
    }
    if (raw.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return raw;
  }

  String _platformKey() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }

  String _regionCode(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final countryCode =
        locale?.countryCode ??
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final normalized = (countryCode ?? '').trim().toUpperCase();
    return normalized.isEmpty ? 'US' : normalized;
  }

  BillingProvider _platformProvider(String regionCode) {
    if (kIsWeb) {
      return regionCode == 'KR' ? BillingProvider.toss : BillingProvider.paddle;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return BillingProvider.apple;
      case TargetPlatform.android:
        return BillingProvider.google;
      default:
        return regionCode == 'KR'
            ? BillingProvider.toss
            : BillingProvider.paddle;
    }
  }

  Future<void> _launchUrlString(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw StateError('This route is not configured yet.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      throw StateError('This route is invalid.');
    }
    final mode = kIsWeb || uri.scheme == 'mailto'
        ? LaunchMode.platformDefault
        : LaunchMode.externalApplication;
    final launched = await launchUrl(uri, mode: mode);
    if (!launched) {
      throw StateError('Could not open ${uri.toString()}.');
    }
  }

  Future<void> _handleManageSubscription({
    BillingProvider? providerOverride,
    String? managementChannelOverride,
  }) async {
    final entitlementService = context.read<EntitlementService>();
    final entitlement = entitlementService.entitlement;
    final sourceProvider = providerOverride ?? entitlement?.sourceProvider;
    final managementChannel =
        (managementChannelOverride ?? entitlement?.managementChannel ?? '')
            .trim()
            .toLowerCase();
    if (managementChannel == 'web_plans') {
      await _launchUrlString('https://www.mixroom.ai/#pricing');
      return;
    }
    if (sourceProvider == BillingProvider.apple) {
      await _launchUrlString('https://apps.apple.com/account/subscriptions');
      return;
    }
    if (sourceProvider == BillingProvider.google) {
      await _launchUrlString(
        'https://play.google.com/store/account/subscriptions'
        '?package=com.mixroom.mixroomapp',
      );
      return;
    }
    final support = entitlementService.effectiveBillingSupport;
    String? portalUrl;
    if (managementChannel == 'web' ||
        sourceProvider == BillingProvider.paddle ||
        sourceProvider == BillingProvider.toss ||
        sourceProvider == BillingProvider.unknown ||
        sourceProvider == BillingProvider.adminGrant ||
        sourceProvider == null) {
      try {
        portalUrl = await entitlementService.fetchPortalUrl();
      } catch (_) {
        portalUrl = null;
      }
    }
    final target = (portalUrl ?? '').trim().isNotEmpty
        ? portalUrl!
        : support.manageSubscriptionUrl.trim().isNotEmpty
        ? support.manageSubscriptionUrl
        : support.defaultCheckoutUrl.trim().isNotEmpty
        ? support.defaultCheckoutUrl
        : 'https://mixroom.ai/account';
    await _launchUrlString(target);
  }

  Future<void> _handleRestorePurchases() async {
    final entitlementService = context.read<EntitlementService>();
    final iapService = context.read<IapService>();
    final provider = _platformProvider(_regionCode(context));
    if (iapService.isMobilePlatformSupported) {
      await iapService.initialize();
      await iapService.restorePurchases();
      final restoreError = (iapService.lastError ?? '').trim();
      if (restoreError.isNotEmpty) {
        throw StateError(restoreError);
      }
      await entitlementService.refresh(force: true);
      await entitlementService.refreshAccountSurface(force: true);
      return;
    }
    await entitlementService.restorePurchases(provider: provider);
  }

  Future<void> _handleContactSupport() async {
    final support = context.read<EntitlementService>().effectiveBillingSupport;
    if (support.supportUrl.trim().isNotEmpty) {
      await _launchUrlString(support.supportUrl);
      return;
    }
    if (support.supportEmail.trim().isNotEmpty) {
      final uri = Uri(scheme: 'mailto', path: support.supportEmail);
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!launched) {
        throw StateError('Could not open your email app.');
      }
      return;
    }
    throw StateError('Support contact is not configured yet.');
  }

  Future<void> _handleContactSalesForPlan([
    BillingProductDefinition? product,
  ]) async {
    final support = context.read<EntitlementService>().effectiveBillingSupport;
    final salesEmail = support.salesEmail.trim().isNotEmpty
        ? support.salesEmail.trim()
        : 'sales@mixroom.ai';
    final planLabel = _salesPlanLabel(product);
    final subject = planLabel == null
        ? 'Mixroom sales inquiry'
        : 'Mixroom sales inquiry - $planLabel';
    final uri = Uri(
      scheme: 'mailto',
      path: salesEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!launched) {
      throw StateError('Could not open your email app.');
    }
  }

  String? _salesPlanLabel(BillingProductDefinition? product) {
    final label = product?.label.trim() ?? '';
    if (label.isNotEmpty) {
      return label;
    }
    final planCode = product?.planCode.trim() ?? '';
    if (planCode.isEmpty) {
      return null;
    }
    return defaultPlanLabelForCode(planCode);
  }

  Future<void> _handleProductSelection(BillingProductDefinition product) async {
    final entitlementService = context.read<EntitlementService>();
    final iapService = context.read<IapService>();
    final catalog = entitlementService.billingCatalog;
    final regionCode = _regionCode(context);
    final provider = _platformProvider(regionCode);
    final entitlement = entitlementService.entitlement;
    final purchaseContext = _purchaseContextForProduct(
      entitlement,
      catalog,
      product,
    );

    if (product.managementChannel == 'admin' || product.type == 'contract') {
      await _handleContactSalesForPlan(product);
      return;
    }

    if (_requiresManagedPlanChange(
      purchaseContext,
      catalog,
      product,
      provider,
    )) {
      await _handleManageSubscription(
        providerOverride: purchaseContext.sourceProvider,
        managementChannelOverride: purchaseContext.managementChannel,
      );
      return;
    }

    final providerProduct = catalog?.bestProviderProductForProduct(
      productCode: product.code,
      provider: provider,
      regionCode: regionCode,
    );

    if (iapService.isMobilePlatformSupported && providerProduct != null) {
      if (mounted) {
        setState(() {
          _inlineMessage = 'Opening secure checkout...';
        });
      }
      await iapService.initialize();
      final storeProduct = iapService.findProductById(
        providerProduct.providerProductId,
      );
      if (storeProduct != null) {
        final isMobileStorePlanChange = _isMobileStorePlanChange(
          purchaseContext,
          product,
          provider,
        );
        _pendingIapProduct = product;
        await iapService.buyProduct(
          storeProduct,
          requiresAndroidSubscriptionChange:
              defaultTargetPlatform == TargetPlatform.android &&
              isMobileStorePlanChange,
          storePlanChangeMayBeDeferred: isMobileStorePlanChange,
        );
        if (mounted) {
          setState(() {
            _inlineMessage = null;
          });
        }
        final purchaseError = (iapService.lastError ?? '').trim();
        if (purchaseError.isNotEmpty) {
          _pendingIapProduct = null;
          throw StateError(purchaseError);
        }
        return;
      }
      throw StateError(
        'This store product is not configured for the current build yet.',
      );
    }

    final checkout = await entitlementService.createWebCheckoutSession(
      regionCode: regionCode,
      productCode: product.code,
    );
    final checkoutUrl =
        (checkout['checkout_url'] ?? '').toString().trim().isNotEmpty
        ? (checkout['checkout_url'] ?? '').toString().trim()
        : entitlementService.effectiveBillingSupport.defaultCheckoutUrl;
    await _launchUrlString(checkoutUrl);
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
    if (_isCurrentBillingProduct(purchaseContext, product)) {
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
        _isCurrentBillingProduct(purchaseContext, product)) {
      return false;
    }
    return (purchaseContext.sourceProvider == BillingProvider.apple &&
            platformProvider == BillingProvider.apple) ||
        (purchaseContext.sourceProvider == BillingProvider.google &&
            platformProvider == BillingProvider.google);
  }

  bool _isCurrentBillingProduct(
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
    if (_isCurrentBillingProduct(purchaseContext, product)) {
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

  @override
  Widget build(BuildContext context) {
    final entitlementService = context.watch<EntitlementService>();
    if (!entitlementService.isAccountPlanBillingEnabled) {
      final entitlement =
          entitlementService.entitlement ??
          EntitlementSnapshot.free(userId: '');
      return _SubscriptionComingSoonCard(
        entitlement: entitlement,
        isLoading: entitlementService.isLoading,
        onRefresh: entitlementService.isLoading || _actionBusy
            ? null
            : () {
                unawaited(
                  _runAction(
                    () => _refreshData(force: true, silent: true),
                    successMessage: 'Subscription details refreshed.',
                  ),
                );
              },
      );
    }

    final iapService = context.watch<IapService>();
    final regionCode = _regionCode(context);
    final provider = _platformProvider(regionCode);

    return AccountSubscriptionSurface(
      entitlementService: entitlementService,
      iapService: iapService,
      aiUsageStatus: _aiUsageStatus,
      isAiUsageLoading: _aiUsageLoading,
      platformKey: _platformKey(),
      regionCode: regionCode,
      platformProvider: provider,
      isActionBusy: _actionBusy,
      inlineMessage: _inlineMessage,
      onRefresh: () {
        unawaited(
          _runAction(
            () => _refreshData(force: true, silent: true),
            successMessage: 'Subscription details refreshed.',
          ),
        );
      },
      onManageSubscription: ({provider, managementChannel}) {
        unawaited(
          _runAction(
            () => _handleManageSubscription(
              providerOverride: provider,
              managementChannelOverride: managementChannel,
            ),
          ),
        );
      },
      onRestorePurchases: () {
        unawaited(
          _runAction(
            _handleRestorePurchases,
            progressMessage: 'Restoring purchases...',
          ),
        );
      },
      onContactSupport: () {
        unawaited(_runAction(_handleContactSupport));
      },
      onSelectProduct: (product) {
        unawaited(_runAction(() => _handleProductSelection(product)));
      },
    );
  }
}

class _SubscriptionComingSoonCard extends StatelessWidget {
  const _SubscriptionComingSoonCard({
    required this.entitlement,
    required this.isLoading,
    required this.onRefresh,
  });

  final EntitlementSnapshot entitlement;
  final bool isLoading;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final planLabel = entitlement.effectivePlanLabel.trim().isEmpty
        ? 'Free'
        : entitlement.effectivePlanLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.workspace_premium_rounded, color: kAccountGlassText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Subscription'),
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
                    'Plan and billing management is coming soon.',
                  ),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${L10n.translate(context, 'Current access')}: ${L10n.translate(context, planLabel)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: L10n.translate(context, 'Refresh'),
            onPressed: onRefresh,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFF4F4F4),
                      ),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
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
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, color: kAccountGlassText),
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
                  L10n.translate(
                    context,
                    'Manage privacy controls, legal documents, and data requests.',
                  ),
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
              foregroundColor: kAccountGlassText,
              minimumSize: const Size(0, 34),
            ),
            child: Text(L10n.translate(context, 'Open')),
          ),
        ],
      ),
    );
  }
}

const Color _accountSettingsRouteBackground = Color(0xFF06080D);

class _AccountSettingsScreen extends StatefulWidget {
  const _AccountSettingsScreen();

  @override
  State<_AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<_AccountSettingsScreen> {
  bool _versionHistoryEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await ProjectVersionPreferences.isEnabled();
    if (!mounted) return;
    setState(() {
      _versionHistoryEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setVersionHistoryEnabled(bool enabled) async {
    setState(() => _versionHistoryEnabled = enabled);
    await ProjectVersionPreferences.setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _accountSettingsRouteBackground,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: _accountSettingsRouteBackground),
          ),
          const Positioned.fill(child: MixroomShellBackground()),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              maxWidth: 920,
              expandToHeight: true,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  27,
                  8,
                  27,
                  mixroomShellBottomPadding(context),
                ),
                children: [
                  SizedBox(
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: MixroomShellRoundButton(
                            size: 48,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              L10n.translate(context, 'Settings'),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              L10n.translate(context, 'Local app preferences'),
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
                    decoration: accountGlassDecoration(
                      radius: 24,
                      strong: true,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          color: Color(0xFFF4F4F4),
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                L10n.translate(context, 'Version History'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                L10n.translate(
                                  context,
                                  'Keep lightweight local project snapshots so older saves can be restored as copies.',
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                L10n.translate(
                                  context,
                                  'Cloud sync stores only the latest project.',
                                ),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Switch.adaptive(
                          value: _versionHistoryEnabled,
                          onChanged: _loading
                              ? null
                              : _setVersionHistoryEnabled,
                          activeThumbColor: const Color(0xFF9FC2FF),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackEntryCard extends StatelessWidget {
  const _FeedbackEntryCard({required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.forum_outlined, color: kAccountGlassText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, 'Feedback / bug report'),
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
                    'Tell us what is working, what is broken, or what you want to see next.',
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
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => onOpen(),
            style: TextButton.styleFrom(
              foregroundColor: kAccountGlassText,
              minimumSize: const Size(0, 34),
            ),
            child: Text(L10n.translate(context, 'Open')),
          ),
        ],
      ),
    );
  }
}

String _localizedSocialSignInDescription({
  required String localeCode,
  required String providerLabel,
  required String email,
}) {
  switch (localeCode) {
    case 'ko':
      return email.isEmpty
          ? '$providerLabel로 로그인합니다.'
          : '$providerLabel로 로그인합니다. 이메일: $email';
    case 'ja':
      return email.isEmpty
          ? '$providerLabelでサインインしています。'
          : '$providerLabelでサインインしています。メール: $email';
    default:
      return email.isEmpty
          ? 'You sign in with $providerLabel.'
          : 'You sign in with $providerLabel using $email.';
  }
}

class _SecurityAccessCard extends StatelessWidget {
  const _SecurityAccessCard({required this.user, required this.auth});

  final AuthUserProfile user;
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final isEmailAccount = user.provider == AuthProviderType.email;
    final providerLabel = L10n.translate(context, user.provider.label);
    final email = user.email.trim();
    final socialDescription = _localizedSocialSignInDescription(
      localeCode: Localizations.localeOf(context).languageCode,
      providerLabel: providerLabel,
      email: email,
    );
    final socialSupportingText = email.isEmpty
        ? L10n.translate(
            context,
            'If you want to add a password later, sign out and use Forgot password from the sign-in screen.',
          )
        : L10n.translate(
            context,
            'If you want to add a password later, sign out and use Forgot password with that email on the sign-in screen.',
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: accountGlassDecoration(radius: 24, strong: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: kAccountGlassText),
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
                  isEmailAccount
                      ? L10n.translate(
                          context,
                          'You sign in with email and password.',
                        )
                      : socialDescription,
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
                    socialSupportingText,
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
                foregroundColor: kAccountGlassText,
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
  const _ChangePasswordSheet({required this.auth});

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
    final passwordIssue = PasswordPolicy.validateLocalized(
      context,
      newPassword,
    );
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
          content: Text(
            L10n.translate(context, 'Password updated successfully.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.translate(context, message))));
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xF05F6263), Color(0xF043484A)],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.38),
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
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
                      PasswordPolicy.requirementsTextLocalized(context),
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
                    hint: 'At least 8 characters',
                    controller: _newPasswordController,
                    obscureText: _hideNewPassword,
                    onToggleVisibility: () =>
                        setState(() => _hideNewPassword = !_hideNewPassword),
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
                        backgroundColor: kAccountGlassBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
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
            fillColor: Colors.black.withValues(alpha: 0.16),
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
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.26),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: kAccountGlassBlue),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({required this.isBusy, required this.onSignOut});

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
              L10n.translate(context, 'Project files are stored locally.'),
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

DateTime? _parseStoredBirthdate(String raw) {
  final safe = raw.trim();
  if (safe.isEmpty) return null;
  final parsed = DateTime.tryParse(safe);
  if (parsed == null) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

String _formatReadableDate(BuildContext context, DateTime value) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat('MMMM d, yyyy', locale).format(value);
}

String _formatCompactDate(DateTime value) {
  return DateFormat('yyyy.MM.dd').format(value);
}

String _formatStoredBirthdateCompact(BuildContext context, String? raw) {
  final safe = (raw ?? '').trim();
  if (safe.isEmpty) return L10n.translate(context, 'Not set');
  final parsed = _parseStoredBirthdate(safe);
  if (parsed == null) return safe;
  return _formatCompactDate(parsed);
}

String _formatStoredBirthdateForDisplay(BuildContext context, String? raw) {
  final safe = (raw ?? '').trim();
  if (safe.isEmpty) return L10n.translate(context, 'Not set');
  final parsed = _parseStoredBirthdate(safe);
  if (parsed == null) return safe;
  return _formatReadableDate(
    context,
    DateTime(parsed.year, parsed.month, parsed.day),
  );
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
