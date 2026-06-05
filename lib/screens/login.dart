// ignore_for_file: unused_element, unused_catch_clause

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/config/cognito_config.dart';
import 'package:mixroom/config/dev_flags.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/password_policy.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:mixroom/widgets/email_verification_sheet.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum LoginEntryMode { signIn, createAccount }

enum _RegisterStep { account, profile }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialMode = LoginEntryMode.signIn,
  });

  final LoginEntryMode initialMode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const int _confirmationCodeLength = 6;
  static const Duration _confirmationCodeExpiry = Duration(minutes: 20);
  static final math.Random _usernameRandom = math.Random();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _confirmationCodeController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _signupUsernameController =
      TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final FocusNode _signInEmailFocusNode = FocusNode();
  final FocusNode _signInPasswordFocusNode = FocusNode();

  LoginEntryMode _mode = LoginEntryMode.signIn;
  _RegisterStep _registerStep = _RegisterStep.account;
  Timer? _confirmationCodeTimer;
  DateTime? _confirmationCodeSentAtUtc;

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _newsletterOptIn = false;
  DateTime? _selectedBirthdateUtc;

  String? _signInEmailError;
  String? _signInPasswordError;
  String? _signInInlineError;
  String? _registerEmailError;
  String? _registerCodeError;
  String? _registerPasswordError;
  String? _registerConfirmPasswordError;
  String? _registerUsernameError;
  String? _registerBirthdateError;
  String? _registerInlineError;
  String? _registerInlineInfo;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode &&
        widget.initialMode != _mode) {
      _mode = widget.initialMode;
      _registerStep = _RegisterStep.account;
      _clearSignInErrors();
      _clearRegisterErrors();
    }
  }

  @override
  void dispose() {
    _confirmationCodeTimer?.cancel();
    _emailController.dispose();
    _confirmationCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _signupUsernameController.dispose();
    _birthdateController.dispose();
    _signInEmailFocusNode.dispose();
    _signInPasswordFocusNode.dispose();
    super.dispose();
  }

  bool get _isRegisterMode => _mode == LoginEntryMode.createAccount;

  bool _isLikelyEmail(String value) {
    final safe = value.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(safe);
  }

  bool _isLikelyLoginIdentifier(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return false;
    if (_isLikelyEmail(safe)) return true;
    return _validateUsername(safe) == null;
  }

  String? _validateUsername(String value) {
    final safe = value.trim().toLowerCase();
    if (safe.isEmpty) {
      return 'Please choose a username.';
    }
    if (safe.length > 30) {
      return 'Username must be 30 characters or fewer.';
    }
    const reserved = <String>{
      'about',
      'account',
      'admin',
      'api',
      'app',
      'auth',
      'billing',
      'create',
      'discover',
      'download',
      'edit',
      'email',
      'explore',
      'feed',
      'help',
      'home',
      'legal',
      'login',
      'logout',
      'me',
      'mixroom',
      'privacy',
      'search',
      'security',
      'settings',
      'signup',
      'studio',
      'support',
      'terms',
      'upload',
      'user',
      'users',
      'verify',
    };
    if (reserved.contains(safe)) {
      return 'That username is reserved.';
    }
    if (safe.contains('--') ||
        safe.contains('__') ||
        safe.contains('-_') ||
        safe.contains('_-')) {
      return 'Username cannot contain repeated separators.';
    }
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9_-]{0,28}[a-z0-9])?$').hasMatch(safe)) {
      return 'Use lowercase letters, numbers, underscores, or hyphens.';
    }
    return null;
  }

  String _normalizeError(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  bool _isSocialSignInCancelled(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized == 'social sign-in was cancelled.' ||
        normalized == 'sign in was cancelled.' ||
        normalized == 'sign-in was cancelled.';
  }

  void _clearSignInErrors() {
    _signInEmailError = null;
    _signInPasswordError = null;
    _signInInlineError = null;
  }

  void _clearRegisterErrors() {
    _registerEmailError = null;
    _registerCodeError = null;
    _registerPasswordError = null;
    _registerConfirmPasswordError = null;
    _registerUsernameError = null;
    _registerBirthdateError = null;
    _registerInlineError = null;
    _registerInlineInfo = null;
  }

  bool _validateRegisterAccountStep() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    final emailError =
        _isLikelyEmail(email) ? null : 'Please enter a valid email address.';
    final passwordIssues = PasswordPolicy.validateIssues(password);
    final passwordError =
        passwordIssues.isEmpty ? null : passwordIssues.join('\n');
    final confirmError = password == confirm ? null : 'Passwords do not match.';

    setState(() {
      _registerEmailError = emailError;
      _registerPasswordError = passwordError;
      _registerConfirmPasswordError = confirmError;
      _registerInlineError = null;
    });

    return emailError == null && passwordError == null && confirmError == null;
  }

  bool _validateRegisterProfileStep() {
    final usernameError = _validateOptionalUsername(
      _signupUsernameController.text,
    );
    final birthdateError = _validateBirthdate(_selectedBirthdateUtc);

    setState(() {
      _registerUsernameError = usernameError;
      _registerBirthdateError = birthdateError;
      _registerInlineError = null;
    });

    return usernameError == null && birthdateError == null;
  }

  String _trimmedFirstName() => _firstNameController.text.trim();

  String _trimmedLastName() => _lastNameController.text.trim();

  String? _validateOptionalUsername(String value) {
    final safe = value.trim();
    if (safe.isEmpty) return null;
    return _validateUsername(safe);
  }

  String _generateMixroomUsername() {
    final suffix =
        _usernameRandom.nextInt(1000000000).toString().padLeft(9, '0');
    return 'mixroom-user$suffix';
  }

  void _generateSignupUsername() {
    setState(() {
      _signupUsernameController.text = _generateMixroomUsername();
      _registerUsernameError = null;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });
  }

  String _composeSignupDisplayName() {
    final parts = <String>[
      _trimmedFirstName(),
      _trimmedLastName(),
    ].where((part) => part.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return '';
  }

  Future<void> _stagePendingSignupProfile(
    AppUserService appUserService,
    String safeEmail,
  ) {
    final safeUsername = _signupUsernameController.text.trim().toLowerCase();
    final displayName = _composeSignupDisplayName();
    final localeCode = Localizations.localeOf(context).languageCode;
    return appUserService.stageSignupConsents(
      email: safeEmail,
      username: safeUsername.isEmpty ? null : safeUsername,
      displayName: displayName.isEmpty ? null : displayName,
      givenName: _trimmedFirstName(),
      familyName: _trimmedLastName(),
      birthdate: _birthdateController.text.trim(),
      newsletterOptIn: _newsletterOptIn,
      localeCode: localeCode,
    );
  }

  String? _validateBirthdate(DateTime? birthdateUtc) {
    if (birthdateUtc == null) return null;
    final latestAllowed = _latestAllowedBirthdateUtc();
    if (birthdateUtc.isAfter(latestAllowed)) {
      return 'You must be at least ${LegalConfig.minimumSignupAgeYears} years old to use Mixroom.';
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
      helpText: 'Select birthday',
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      _selectedBirthdateUtc = normalized;
      _birthdateController.text = _formatBirthdate(normalized);
      _registerBirthdateError = null;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });
  }

  void _clearBirthdate() {
    setState(() {
      _selectedBirthdateUtc = null;
      _birthdateController.clear();
      _registerBirthdateError = null;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });
  }

  void _switchMode(LoginEntryMode next) {
    if (_mode == next) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = next;
      _registerStep = _RegisterStep.account;
      _newsletterOptIn = false;
      _clearSignInErrors();
      _clearRegisterErrors();
    });
  }

  void _goBackRegisterStep() {
    setState(() {
      if (_registerStep == _RegisterStep.profile) {
        _registerStep = _RegisterStep.account;
      }
      _registerInlineError = null;
      _registerInlineInfo = null;
    });
  }

  void _goNextRegisterStep() {
    switch (_registerStep) {
      case _RegisterStep.account:
        if (!_validateRegisterAccountStep()) return;
        setState(() {
          _registerStep = _RegisterStep.profile;
          _registerUsernameError = null;
          _registerBirthdateError = null;
          _registerInlineInfo = null;
        });
        return;
      case _RegisterStep.profile:
        if (!_validateRegisterProfileStep()) return;
        return;
    }
  }

  String? _pendingCreateAccountEmail(AuthService auth) {
    if (!auth.hasPendingEmailVerification) return null;
    final pendingEmail = auth.currentUser?.email.trim().toLowerCase() ?? '';
    return pendingEmail.isEmpty ? null : pendingEmail;
  }

  bool _isAwaitingCreateAccountCode(AuthService auth) {
    final pendingEmail = _pendingCreateAccountEmail(auth);
    if (pendingEmail == null) return false;
    return pendingEmail == _emailController.text.trim().toLowerCase();
  }

  void _startConfirmationCodeCountdown() {
    _confirmationCodeTimer?.cancel();
    _confirmationCodeSentAtUtc = DateTime.now().toUtc();
    _confirmationCodeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if ((_confirmationCodeSentAtUtc ?? DateTime.now().toUtc())
          .add(_confirmationCodeExpiry)
          .isBefore(DateTime.now().toUtc())) {
        _confirmationCodeTimer?.cancel();
      }
      setState(() {});
    });
  }

  String? _confirmationCodeCountdownLabel() {
    final sentAt = _confirmationCodeSentAtUtc;
    if (sentAt == null) return null;
    final remaining =
        _confirmationCodeExpiry - DateTime.now().toUtc().difference(sentAt);
    if (remaining.isNegative) {
      return '00:00';
    }
    final minutes =
        remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool _validateCreateAccountStep({
    required bool requiresCode,
  }) {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    final code = _confirmationCodeController.text.trim();

    final emailError =
        _isLikelyEmail(email) ? null : 'Please enter a valid email address.';
    final codeError = requiresCode && code.isEmpty
        ? 'Please enter the confirmation code.'
        : null;
    final passwordIssues = PasswordPolicy.validateIssues(password);
    final passwordError =
        passwordIssues.isEmpty ? null : passwordIssues.join('\n');
    final confirmError = password == confirm ? null : 'Passwords do not match.';

    setState(() {
      _registerEmailError = emailError;
      _registerCodeError = codeError;
      _registerPasswordError = passwordError;
      _registerConfirmPasswordError = confirmError;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    return emailError == null &&
        codeError == null &&
        passwordError == null &&
        confirmError == null;
  }

  bool _canSendCreateAccountCodeLocally() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    return _isLikelyEmail(email) &&
        PasswordPolicy.validateIssues(password).isEmpty &&
        password == confirm;
  }

  bool get _hasReadyCreateAccountEmail => _isLikelyEmail(_emailController.text);

  bool get _hasReadyConfirmationCode =>
      _confirmationCodeController.text.trim().length >= _confirmationCodeLength;

  Future<void> _openEmailVerificationFlow(AuthService auth) async {
    await showEmailVerificationSheet(
      context,
      auth: auth,
      initialEmail: _emailController.text.trim().toLowerCase(),
      initialPassword: _passwordController.text,
    );
  }

  Future<void> _showSocialConflictGuidance(
    AuthService auth,
    AuthSocialAccountConflictException conflict,
  ) async {
    final safeEmail = conflict.email.trim().toLowerCase();
    final existingProvider = conflict.existingProvider;
    final existingProviderLabel =
        conflict.existingProviderLabel?.trim().isNotEmpty == true
            ? conflict.existingProviderLabel!.trim()
            : existingProvider?.label ?? 'Email';
    final canVerifyPendingEmail = auth.hasPendingEmailVerification &&
        (auth.currentUser?.email.trim().toLowerCase() ?? '') == safeEmail;
    final shouldOfferVerification =
        conflict.verificationRequired && canVerifyPendingEmail;
    final shouldOfferPasswordReset = conflict.passwordResetAvailable &&
        existingProvider == AuthProviderType.email;
    final primaryActionLabel = _socialConflictPrimaryActionLabel(
      existingProvider,
    );
    final description = _socialConflictDescription(
      email: safeEmail,
      existingProviderLabel: existingProviderLabel,
      verificationRequired: conflict.verificationRequired,
    );
    final guidance = _socialConflictGuidance(
      existingProvider: existingProvider,
      verificationRequired: conflict.verificationRequired,
      shouldOfferVerification: shouldOfferVerification,
      shouldOfferPasswordReset: shouldOfferPasswordReset,
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F2038),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  L10n.translate(context, 'Account already exists'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.translate(
                    context,
                    description,
                  ),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.translate(
                    context,
                    guidance,
                  ),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                _PrimaryButton(
                  label: primaryActionLabel,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _handleSocialConflictPrimaryAction(
                      auth,
                      conflict,
                      safeEmail: safeEmail,
                    );
                  },
                ),
                if (shouldOfferVerification) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _openEmailVerificationFlow(auth);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.14)),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(L10n.translate(context, 'Verify Email')),
                  ),
                ],
                if (shouldOfferPasswordReset) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      setState(() {
                        _mode = LoginEntryMode.signIn;
                        _emailController.text = safeEmail;
                        _passwordController.clear();
                      });
                      await _openForgotPasswordFlow(auth);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.14)),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(L10n.translate(context, 'Forgot Password')),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(L10n.translate(context, 'Close')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _socialConflictPrimaryActionLabel(AuthProviderType? provider) {
    switch (provider) {
      case AuthProviderType.google:
        return 'Use Google Sign-In';
      case AuthProviderType.apple:
        return 'Use Apple Sign-In';
      case AuthProviderType.kakao:
        return 'Use Kakao Sign-In';
      case AuthProviderType.email:
      case null:
        return 'Use Email Sign-In';
    }
  }

  String _socialConflictDescription({
    required String email,
    required String existingProviderLabel,
    required bool verificationRequired,
  }) {
    if (email.isEmpty) {
      return verificationRequired
          ? 'That social account matches an existing unverified Mixroom account.'
          : 'That social account matches an existing Mixroom account.';
    }
    if (verificationRequired) {
      return 'Mixroom already has an unverified account for $email.';
    }
    return 'Mixroom already has an account for $email using $existingProviderLabel sign-in.';
  }

  String _socialConflictGuidance({
    required AuthProviderType? existingProvider,
    required bool verificationRequired,
    required bool shouldOfferVerification,
    required bool shouldOfferPasswordReset,
  }) {
    if (verificationRequired) {
      if (shouldOfferVerification) {
        return 'Finish verifying that email account first, then keep using email sign-in for Mixroom.';
      }
      return 'Finish verifying the original email account first. After that, keep using email sign-in for Mixroom.';
    }
    switch (existingProvider) {
      case AuthProviderType.google:
        return 'Use Google on the sign-in screen for this account. Mixroom does not auto-merge a confirmed account into a different provider.';
      case AuthProviderType.apple:
        return 'Use Apple on the sign-in screen for this account. Mixroom does not auto-merge a confirmed account into a different provider.';
      case AuthProviderType.kakao:
        return 'Use Kakao on the sign-in screen for this account. Mixroom does not auto-merge a confirmed account into a different provider.';
      case AuthProviderType.email:
      case null:
        if (shouldOfferPasswordReset) {
          return 'Switch to email sign-in. If you forgot the password, use Forgot password for the same email.';
        }
        return 'Switch to email sign-in for this account.';
    }
  }

  Future<void> _handleSocialConflictPrimaryAction(
    AuthService auth,
    AuthSocialAccountConflictException conflict, {
    required String safeEmail,
  }) async {
    switch (conflict.existingProvider) {
      case AuthProviderType.google:
        await _submitSocialProvider(auth, AuthProviderType.google);
        return;
      case AuthProviderType.apple:
        await _submitSocialProvider(auth, AuthProviderType.apple);
        return;
      case AuthProviderType.kakao:
        await _submitSocialProvider(auth, AuthProviderType.kakao);
        return;
      case AuthProviderType.email:
      case null:
        if (!mounted) return;
        setState(() {
          _mode = LoginEntryMode.signIn;
          _emailController.text = safeEmail;
          _passwordController.clear();
          _signInInlineError = conflict.message;
        });
        return;
    }
  }

  Future<void> _submitSignIn(AuthService auth) async {
    FocusScope.of(context).unfocus();

    if (!_isLikelyLoginIdentifier(_emailController.text.trim())) {
      setState(() {
        _signInEmailError = 'Please enter a valid email or username.';
      });
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _signInEmailError = null;
        _signInPasswordError = 'Please enter your password.';
      });
      return;
    }

    setState(() {
      _signInEmailError = null;
      _signInPasswordError = null;
      _signInInlineError = null;
    });

    try {
      await auth.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthEmailConfirmationRequiredException catch (e) {
      if (!mounted) return;
      if (auth.isSignedIn) return;
      setState(() {
        _signInInlineError = e.message;
      });
      await _openEmailVerificationFlow(auth);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signInInlineError = _normalizeError(e);
      });
    }
  }

  Future<void> _submitRegister(AuthService auth) async {
    FocusScope.of(context).unfocus();
    final appUserService = context.read<AppUserService>();
    final safeEmail = _emailController.text.trim().toLowerCase();
    final localeCode = Localizations.localeOf(context).languageCode;
    final requiresCode = _isAwaitingCreateAccountCode(auth);

    if (!_validateCreateAccountStep(requiresCode: requiresCode)) return;

    setState(() {
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    try {
      final availabilityError = await _checkUsernameAvailability();
      if (availabilityError != null) {
        if (!mounted) return;
        setState(() {
          _registerUsernameError = availabilityError;
        });
        return;
      }
      if (requiresCode) {
        await auth.confirmEmailSignUp(
          email: safeEmail,
          code: _confirmationCodeController.text,
          passwordToSignIn: _passwordController.text,
        );
      } else {
        await auth.registerWithEmail(
          name: _composeSignupDisplayName(),
          givenName: _trimmedFirstName(),
          familyName: _trimmedLastName(),
          birthdate: _birthdateController.text.trim(),
          email: safeEmail,
          password: _passwordController.text,
          localeCode: localeCode,
        );
      }
      await _stagePendingSignupProfile(appUserService, safeEmail);
    } on AuthEmailConfirmationRequiredException catch (e) {
      await _stagePendingSignupProfile(appUserService, safeEmail);
      if (!mounted) return;
      if (auth.isSignedIn) return;
      _startConfirmationCodeCountdown();
      setState(() {
        _registerInlineError = null;
        _registerInlineInfo =
            L10n.translate(context, 'Confirmation code sent!');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registerInlineError = _normalizeError(e);
      });
    }
  }

  Future<void> _sendCreateAccountCode(AuthService auth) async {
    FocusScope.of(context).unfocus();
    final appUserService = context.read<AppUserService>();
    final safeEmail = _emailController.text.trim().toLowerCase();
    final localeCode = Localizations.localeOf(context).languageCode;

    if (!_validateCreateAccountStep(requiresCode: false)) return;

    setState(() {
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    try {
      final availabilityError = await _checkUsernameAvailability();
      if (availabilityError != null) {
        if (!mounted) return;
        setState(() {
          _registerUsernameError = availabilityError;
        });
        return;
      }
      await auth.registerWithEmail(
        name: _composeSignupDisplayName(),
        givenName: _trimmedFirstName(),
        familyName: _trimmedLastName(),
        birthdate: _birthdateController.text.trim(),
        email: safeEmail,
        password: _passwordController.text,
        localeCode: localeCode,
      );
      await _stagePendingSignupProfile(appUserService, safeEmail);
    } on AuthEmailConfirmationRequiredException {
      await _stagePendingSignupProfile(appUserService, safeEmail);
      if (!mounted) return;
      if (auth.isSignedIn) return;
      _startConfirmationCodeCountdown();
      setState(() {
        _registerInlineError = null;
        _registerInlineInfo =
            L10n.translate(context, 'Confirmation code sent!');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registerInlineError = _normalizeError(e);
      });
    }
  }

  Future<void> _resendCreateAccountCode(AuthService auth) async {
    final safeEmail = _emailController.text.trim().toLowerCase();
    if (!_isLikelyEmail(safeEmail)) {
      setState(() {
        _registerEmailError = 'Please enter a valid email address.';
      });
      return;
    }

    try {
      await auth.resendSignUpCode(
        email: safeEmail,
        localeCode: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      _startConfirmationCodeCountdown();
      setState(() {
        _registerInlineError = null;
        _registerInlineInfo =
            L10n.translate(context, 'Confirmation code sent!');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _registerInlineError = _normalizeError(e);
      });
    }
  }

  Future<String?> _checkUsernameAvailability() async {
    if (!AppApiConfig.hasApiBaseUrl) {
      return null;
    }

    final normalizedUsername =
        _signupUsernameController.text.trim().toLowerCase();
    if (normalizedUsername.isEmpty) {
      return null;
    }

    try {
      final base = AppApiConfig.apiBaseUrl.trim();
      final normalizedBase =
          base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final response = await http.get(
        Uri.parse(
          '$normalizedBase/v1/users/username-availability',
        ).replace(
          queryParameters: <String, String>{
            'username': normalizedUsername,
          },
        ),
        headers: const <String, String>{
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 429) {
          return 'Too many username checks right now. Please wait a moment and try again.';
        }
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (payload['available'] == true) {
        return null;
      }
      final reason = (payload['reason'] ?? '').toString().trim();
      return reason.isEmpty ? 'That username is already taken.' : reason;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitSocial(AuthService auth, Future<void> Function() action,
      {required String providerLabel}) async {
    final appUserService = context.read<AppUserService>();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _signInInlineError = null;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    var resolvingPostSignIn = false;
    try {
      appUserService.beginPostSignInResolution();
      resolvingPostSignIn = true;
      await action();
    } on AuthSocialAccountConflictException catch (e) {
      if (!mounted) return;
      final message = _normalizeError(e);
      setState(() {
        if (_isRegisterMode) {
          _registerInlineError = message;
          _registerInlineInfo = null;
        } else {
          _signInInlineError = message;
        }
      });
      await _showSocialConflictGuidance(auth, e);
    } catch (e) {
      if (!mounted) return;
      final message = _normalizeError(e);
      if (_isSocialSignInCancelled(message)) {
        return;
      }
      setState(() {
        if (_isRegisterMode) {
          _registerInlineError = message;
          _registerInlineInfo = null;
        } else {
          _signInInlineError = message;
        }
      });
    } finally {
      if (resolvingPostSignIn) {
        appUserService.completePostSignInResolution();
      }
    }
  }

  Future<void> _submitSocialProvider(
    AuthService auth,
    AuthProviderType provider,
  ) async {
    switch (provider) {
      case AuthProviderType.google:
        await _submitSocial(
          auth,
          auth.signInWithGoogle,
          providerLabel: provider.label,
        );
        return;
      case AuthProviderType.apple:
        await _submitSocial(
          auth,
          auth.signInWithApple,
          providerLabel: provider.label,
        );
        return;
      case AuthProviderType.kakao:
        await _submitSocial(
          auth,
          auth.signInWithKakao,
          providerLabel: provider.label,
        );
        return;
      case AuthProviderType.email:
        return;
    }
  }

  Future<void> _openForgotPasswordFlow(AuthService auth) async {
    final initialEmail = _emailController.text.trim();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ForgotPasswordSheet(
          auth: auth,
          initialEmail: initialEmail,
          isLikelyEmail: _isLikelyEmail,
        );
      },
    );
  }

  Future<void> _devRealLogin(AuthService auth) async {
    FocusScope.of(context).unfocus();

    final configuredIdentifier = kDevLoginEmail.trim();
    final configuredPassword = kDevLoginPassword;
    final identifier = configuredIdentifier.isNotEmpty
        ? configuredIdentifier
        : _emailController.text.trim();
    final password = configuredPassword.isNotEmpty
        ? configuredPassword
        : _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      if (!mounted) return;
      setState(() {
        _mode = LoginEntryMode.signIn;
        _signInEmailError = identifier.isEmpty
            ? 'Please provide a dev login email/username.'
            : null;
        _signInPasswordError =
            password.isEmpty ? 'Please provide a dev login password.' : null;
        _signInInlineError =
            'Dev Login needs real credentials. Set DEV_LOGIN_EMAIL and DEV_LOGIN_PASSWORD via --dart-define, or type them above.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _mode = LoginEntryMode.signIn;
      _emailController.text = identifier;
      _signInEmailError = null;
      _signInPasswordError = null;
      _signInInlineError = null;
    });

    try {
      await auth.signInWithEmail(email: identifier, password: password);
    } on AuthEmailConfirmationRequiredException catch (e) {
      if (!mounted) return;
      if (auth.isSignedIn) return;
      setState(() {
        _signInInlineError = e.message;
      });
      await _openEmailVerificationFlow(auth);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signInInlineError = _normalizeError(e);
      });
    }
  }

  Widget _slideFadeTransition(Widget child, Animation<double> animation) {
    final offset = Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: offset,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final busy = auth.isBusy;
    final supportsSocialSignIn = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final showGoogle = supportsSocialSignIn && CognitoConfig.enableGoogleSignIn;
    final showApple = supportsSocialSignIn &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        CognitoConfig.enableAppleSignIn;
    final showKakao = supportsSocialSignIn && CognitoConfig.enableKakaoSignIn;
    final showAnySocial = showGoogle || showApple || showKakao;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(
            child: MixroomAuthBackground(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                final minHeight = math.max(
                  0.0,
                  constraints.maxHeight - bottomInset - 24,
                );

                return AnimatedPadding(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(27, 14, 27, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 402,
                          minHeight: minHeight,
                        ),
                        child: _isRegisterMode
                            ? _buildRegisterStage(
                                auth: auth,
                                busy: busy,
                              )
                            : _buildSignInFlow(
                                auth: auth,
                                busy: busy,
                                showGoogle: showGoogle,
                                showApple: showApple,
                                showKakao: showKakao,
                                showAnySocial: showAnySocial,
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterStage({
    required AuthService auth,
    required bool busy,
  }) {
    final awaitingCode = _isAwaitingCreateAccountCode(auth);
    final passwordIssues =
        PasswordPolicy.validateIssues(_passwordController.text);
    final hasPasswordInteraction = _passwordController.text.isNotEmpty ||
        _confirmPasswordController.text.isNotEmpty;
    final confirmMismatch = _confirmPasswordController.text.isNotEmpty &&
        _passwordController.text != _confirmPasswordController.text;
    final emailCardHasError = _registerEmailError != null ||
        (awaitingCode && _registerCodeError != null);
    final passwordCardHasError =
        _registerPasswordError != null || _registerConfirmPasswordError != null;
    final showPasswordRequirementAccent = passwordCardHasError ||
        (hasPasswordInteraction &&
            (passwordIssues.isNotEmpty || confirmMismatch));
    final codeStatusText = awaitingCode
        ? (_registerInlineInfo ??
            L10n.translate(context, 'Confirmation code sent!'))
        : L10n.translate(
            context,
            'Confirmation code will be sent to your email inbox.',
          );
    final countdownLabel = _confirmationCodeCountdownLabel();

    return Column(
      key: const ValueKey('create-account-stage'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MixroomAuthTopBar(
          onBack: busy ? null : () => _switchMode(LoginEntryMode.signIn),
        ),
        const SizedBox(height: 52),
        const MixroomBrandLockup(showMark: false),
        const SizedBox(height: 56),
        MixroomGlassPanel(
          borderColor: emailCardHasError
              ? const Color.fromRGBO(255, 157, 71, 0.72)
              : const Color.fromRGBO(244, 244, 244, 0.14),
          child: Column(
            children: [
              SizedBox(
                height: 58,
                child: MixroomGlassTextFieldRow(
                  controller: _emailController,
                  label: L10n.translate(context, 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    setState(() {
                      _registerEmailError = null;
                      _registerCodeError = null;
                      _registerInlineError = null;
                      _registerInlineInfo = null;
                    });
                  },
                ),
              ),
              if (awaitingCode) ...[
                const MixroomGlassDivider(),
                MixroomGlassTextFieldRow(
                  controller: _confirmationCodeController,
                  label: L10n.translate(context, 'Confirmation code'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    setState(() {
                      _registerCodeError = null;
                      _registerInlineError = null;
                      _registerInlineInfo = null;
                    });
                  },
                  onSubmitted: (_) {
                    if (busy) return;
                    _submitRegister(auth);
                  },
                  trailingText: countdownLabel,
                  suffix: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy ? null : () => _resendCreateAccountCode(auth),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Text(
                          L10n.translate(context, 'Resend code'),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 15,
                            height: 22 / 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          codeStatusText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Pretendard',
            color: const Color(0xFFF4F4F4),
            fontSize: 12,
            height: 15 / 12,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 18),
        MixroomGlassPanel(
          borderColor: passwordCardHasError
              ? const Color.fromRGBO(255, 157, 71, 0.72)
              : const Color.fromRGBO(244, 244, 244, 0.14),
          child: Column(
            children: [
              MixroomGlassTextFieldRow(
                controller: _passwordController,
                label: L10n.translate(context, 'Password'),
                obscureText: _hidePassword,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() {
                    _registerPasswordError = null;
                    _registerInlineError = null;
                    _registerInlineInfo = null;
                  });
                },
                suffix: IconButton(
                  onPressed: () {
                    setState(() {
                      _hidePassword = !_hidePassword;
                    });
                  },
                  splashRadius: 18,
                  icon: SvgPicture.asset(
                    _hidePassword
                        ? kMixroomEyeIconAsset
                        : kMixroomEyeOffIconAsset,
                    width: 20,
                    height: 15,
                  ),
                ),
              ),
              const MixroomGlassDivider(),
              MixroomGlassTextFieldRow(
                controller: _confirmPasswordController,
                label: L10n.translate(context, 'Confirm Password'),
                obscureText: _hideConfirmPassword,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  setState(() {
                    _registerConfirmPasswordError = null;
                    _registerInlineError = null;
                    _registerInlineInfo = null;
                  });
                },
                onSubmitted: (_) {
                  if (busy) return;
                  if (awaitingCode) {
                    _submitRegister(auth);
                  } else {
                    _sendCreateAccountCode(auth);
                  }
                },
                suffix: IconButton(
                  onPressed: () {
                    setState(() {
                      _hideConfirmPassword = !_hideConfirmPassword;
                    });
                  },
                  splashRadius: 18,
                  icon: SvgPicture.asset(
                    _hideConfirmPassword
                        ? kMixroomEyeIconAsset
                        : kMixroomEyeOffIconAsset,
                    width: 20,
                    height: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          PasswordPolicy.requirementsTextLocalized(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Pretendard',
            color: showPasswordRequirementAccent
                ? const Color(0xFFFF9D47)
                : const Color(0xFFF4F4F4),
            fontSize: 12,
            height: 15 / 12,
            fontWeight: FontWeight.w400,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _buildCreateAccountMessages(),
        ),
        const SizedBox(height: 36),
        Center(
          child: MixroomPillButton(
            label: L10n.translate(context, 'Next'),
            width: 124,
            busy: busy,
            onTap: busy
                ? null
                : () {
                    if (awaitingCode) {
                      _submitRegister(auth);
                    } else {
                      _sendCreateAccountCode(auth);
                    }
                  },
          ),
        ),
        if (isDevLoginButtonEnabled) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : () => _devRealLogin(auth),
              icon: const Icon(
                Icons.developer_mode_rounded,
                size: 16,
              ),
              label: Text(
                hasConfiguredDevLoginCredentials
                    ? 'Dev Login (Real)'
                    : 'Dev Login (Use Typed)',
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.72),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignInFlow({
    required AuthService auth,
    required bool busy,
    required bool showGoogle,
    required bool showApple,
    required bool showKakao,
    required bool showAnySocial,
  }) {
    return Column(
      key: const ValueKey('sign-in-flow'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: MixroomLocaleSelector(),
        ),
        const SizedBox(height: 28),
        const MixroomBrandLockup(),
        const SizedBox(height: 40),
        MixroomSignInFieldsCard(
          emailController: _emailController,
          passwordController: _passwordController,
          emailFocusNode: _signInEmailFocusNode,
          passwordFocusNode: _signInPasswordFocusNode,
          hidePassword: _hidePassword,
          hasError: _signInEmailError != null || _signInPasswordError != null,
          onEmailChanged: (_) {
            setState(() {
              _signInEmailError = null;
              _signInInlineError = null;
            });
          },
          onPasswordChanged: (_) {
            setState(() {
              _signInPasswordError = null;
              _signInInlineError = null;
            });
          },
          onEmailEditingComplete: () {
            if (busy) return;
            _signInPasswordFocusNode.requestFocus();
          },
          onPasswordSubmitted: (_) {
            if (busy) return;
            _submitSignIn(auth);
          },
          onTogglePasswordVisibility: () {
            setState(() {
              _hidePassword = !_hidePassword;
            });
          },
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: busy ? null : () => _openForgotPasswordFlow(auth),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFF4F4F4),
            textStyle: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              height: 22 / 15,
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFF4F4F4),
              fontWeight: FontWeight.w400,
            ),
          ),
          child: Text(L10n.translate(context, 'Forgot password?')),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _buildSignInMessages(auth: auth, busy: busy),
        ),
        const SizedBox(height: 16),
        MixroomPillButton(
          label: busy
              ? L10n.translate(context, 'Signing In...')
              : L10n.translate(context, 'Sign In'),
          width: 124,
          busy: busy,
          onTap: busy ? null : () => _submitSignIn(auth),
        ),
        if (showAnySocial) ...[
          const SizedBox(height: 42),
          Text(
            L10n.translate(context, 'Or continue with'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 15,
              height: 22 / 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showGoogle)
                MixroomSocialIconButton(
                  assetPath: kMixroomGoogleSocialAsset,
                  semanticLabel: 'Continue with Google',
                  onTap: busy
                      ? null
                      : () => _submitSocial(
                            auth,
                            auth.signInWithGoogle,
                            providerLabel: AuthProviderType.google.label,
                          ),
                ),
              if (showApple) ...[
                if (showGoogle) const SizedBox(width: 10),
                MixroomSocialIconButton(
                  assetPath: kMixroomAppleSocialAsset,
                  semanticLabel: 'Continue with Apple',
                  onTap: busy
                      ? null
                      : () => _submitSocial(
                            auth,
                            auth.signInWithApple,
                            providerLabel: AuthProviderType.apple.label,
                          ),
                ),
              ],
              if (showKakao) ...[
                if (showGoogle || showApple) const SizedBox(width: 10),
                MixroomSocialIconButton(
                  assetPath: kMixroomKakaoSocialAsset,
                  semanticLabel: 'Continue with Kakao',
                  onTap: busy
                      ? null
                      : () => _submitSocial(
                            auth,
                            auth.signInWithKakao,
                            providerLabel: AuthProviderType.kakao.label,
                          ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 28),
        MixroomPillButton(
          label: L10n.translate(context, 'Create account'),
          width: 164,
          onTap: busy ? null : () => _switchMode(LoginEntryMode.createAccount),
        ),
        if (isDevLoginButtonEnabled) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: busy ? null : () => _devRealLogin(auth),
            icon: const Icon(Icons.developer_mode_rounded, size: 16),
            label: Text(
              hasConfiguredDevLoginCredentials
                  ? 'Dev Login (Real)'
                  : 'Dev Login (Use Typed)',
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.72),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignInMessages({
    required AuthService auth,
    required bool busy,
  }) {
    final children = <Widget>[];
    if (_signInEmailError != null) {
      children.add(_InlineErrorBanner(message: _signInEmailError!));
    }
    if (_signInPasswordError != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(_InlineErrorBanner(message: _signInPasswordError!));
    }
    if (_signInInlineError != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(_InlineErrorBanner(message: _signInInlineError!));
    }
    if (auth.hasPendingEmailVerification) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: busy ? null : () => _openEmailVerificationFlow(auth),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF4F4F4),
              textStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                height: 22 / 15,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFFF4F4F4),
                fontWeight: FontWeight.w400,
              ),
            ),
            child: Text(L10n.translate(context, 'Enter verification code')),
          ),
        ),
      );
    }
    if (children.isEmpty) {
      return const SizedBox(height: 0);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildCreateAccountMessages() {
    final messages = <String>[
      if ((_registerEmailError ?? '').trim().isNotEmpty) _registerEmailError!,
      if ((_registerCodeError ?? '').trim().isNotEmpty) _registerCodeError!,
      if ((_registerPasswordError ?? '').trim().isNotEmpty)
        _registerPasswordError!,
      if ((_registerConfirmPasswordError ?? '').trim().isNotEmpty)
        _registerConfirmPasswordError!,
      if ((_registerInlineError ?? '').trim().isNotEmpty) _registerInlineError!,
    ];
    if (messages.isEmpty) {
      return const SizedBox(height: 0);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: messages
            .map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF9D47),
                    fontSize: 12,
                    height: 15 / 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildRegisterFlow({required AuthService auth, required bool busy}) {
    return Column(
      key: const ValueKey('register-flow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepIndicator(step: _registerStep),
        const SizedBox(height: 14),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _slideFadeTransition,
            child: _buildRegisterStepContent(),
          ),
        ),
        const SizedBox(height: 8),
        if (_registerStep != _RegisterStep.account)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : _goBackRegisterStep,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(L10n.translate(context, 'Back')),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
            ),
          ),
        if (_registerInlineError != null) ...[
          _InlineErrorBanner(message: _registerInlineError!),
          const SizedBox(height: 10),
        ],
        if (_registerInlineInfo != null) ...[
          _InlineInfoBanner(message: _registerInlineInfo!),
          const SizedBox(height: 10),
        ],
        if (auth.hasPendingEmailVerification) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : () => _openEmailVerificationFlow(auth),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF4F4F4),
                textStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  height: 22 / 15,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFFF4F4F4),
                  fontWeight: FontWeight.w400,
                ),
              ),
              child: Text(L10n.translate(context, 'Enter verification code')),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const _SignupLegalNotice(),
        const SizedBox(height: 8),
        _PrimaryButton(
          label: _registerStep == _RegisterStep.profile
              ? (busy
                  ? L10n.translate(context, 'Creating...')
                  : L10n.translate(context, 'Create Account'))
              : L10n.translate(context, 'Continue'),
          busy: busy && _registerStep == _RegisterStep.profile,
          onTap: busy
              ? null
              : () {
                  if (_registerStep == _RegisterStep.profile) {
                    _submitRegister(auth);
                  } else {
                    _goNextRegisterStep();
                  }
                },
        ),
      ],
    );
  }

  Widget _buildRegisterStepContent() {
    switch (_registerStep) {
      case _RegisterStep.account:
        return Column(
          key: const ValueKey('register-step-account'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'Email',
              hint: 'you@example.com',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              errorText: _registerEmailError,
              onChanged: (_) {
                setState(() {
                  _registerEmailError = null;
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Password',
              hint: 'At least ${PasswordPolicy.minLength} characters',
              controller: _passwordController,
              obscureText: _hidePassword,
              errorText: _registerPasswordError,
              helperText: PasswordPolicy.requirementsText(),
              onChanged: (_) {
                setState(() {
                  _registerPasswordError = null;
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
              suffix: IconButton(
                onPressed: () {
                  setState(() {
                    _hidePassword = !_hidePassword;
                  });
                },
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Field(
              label: 'Confirm Password',
              hint: 'Re-enter password',
              controller: _confirmPasswordController,
              obscureText: _hideConfirmPassword,
              errorText: _registerConfirmPasswordError,
              onChanged: (_) {
                setState(() {
                  _registerConfirmPasswordError = null;
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
              suffix: IconButton(
                onPressed: () {
                  setState(() {
                    _hideConfirmPassword = !_hideConfirmPassword;
                  });
                },
                icon: Icon(
                  _hideConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        );
      case _RegisterStep.profile:
        return Column(
          key: const ValueKey('register-step-profile'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'First name (optional)',
              hint: 'First name',
              controller: _firstNameController,
              onChanged: (_) {
                setState(() {
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Last name (optional)',
              hint: 'Last name',
              controller: _lastNameController,
              onChanged: (_) {
                setState(() {
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Username (optional)',
              hint: 'your_username',
              controller: _signupUsernameController,
              errorText: _registerUsernameError,
              helperText:
                  'Used for your username and sign-in. Leave blank to get an auto-generated mixroom-user name.',
              onChanged: (_) {
                setState(() {
                  _registerUsernameError = null;
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _generateSignupUsername,
                child: Text(L10n.translate(context, 'Generate username')),
              ),
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Birthday (optional)',
              hint: 'Select birthday',
              controller: _birthdateController,
              readOnly: true,
              errorText: _registerBirthdateError,
              helperText:
                  'Optional. If you add it, you must be at least ${LegalConfig.minimumSignupAgeYears} years old to use Mixroom.',
              onTap: _pickBirthdate,
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_birthdateController.text.trim().isNotEmpty)
                    IconButton(
                      onPressed: _clearBirthdate,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  IconButton(
                    onPressed: _pickBirthdate,
                    icon: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _NewsletterCheckbox(
              value: _newsletterOptIn,
              onChanged: (next) {
                setState(() {
                  _newsletterOptIn = next;
                  _registerInlineInfo = null;
                });
              },
            ),
          ],
        );
    }
  }
}

class _SignupLegalNotice extends StatelessWidget {
  const _SignupLegalNotice();

  Future<void> _openUrl(BuildContext context, String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this link right now.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        Text(
          'By creating an account, you agree to the',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextButton(
          onPressed: () => _openUrl(context, LegalConfig.termsUrl),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 26),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Terms of Service'),
        ),
        Text(
          'and',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextButton(
          onPressed: () => _openUrl(context, LegalConfig.privacyUrl),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 26),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Privacy Policy'),
        ),
        Text(
          '.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _NewsletterCheckbox extends StatelessWidget {
  const _NewsletterCheckbox({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
              activeColor: const Color(0xFF5F96FF),
              side: BorderSide(color: Colors.white.withOpacity(0.40)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Text(
                  'Email me product updates and news.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.80),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ResetStep { requestCode, confirmReset }

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({
    required this.auth,
    required this.initialEmail,
    required this.isLikelyEmail,
  });

  final AuthService auth;
  final String initialEmail;
  final bool Function(String) isLikelyEmail;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  _ResetStep _step = _ResetStep.requestCode;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (!widget.isLikelyEmail(email)) {
      _showSnack('Enter a valid email address.');
      return;
    }

    try {
      await widget.auth.requestPasswordReset(
        email: email,
        localeCode: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() => _step = _ResetStep.confirmReset);
      _showSnack('Verification code sent.');
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _confirmReset() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (!widget.isLikelyEmail(email)) {
      _showSnack('Enter a valid email address.');
      return;
    }
    if (code.isEmpty) {
      _showSnack('Enter the verification code.');
      return;
    }
    final passwordIssues = PasswordPolicy.validateIssues(newPassword);
    if (passwordIssues.isNotEmpty) {
      _showSnack(passwordIssues.join('\n'));
      return;
    }
    if (newPassword != confirm) {
      _showSnack('Passwords do not match.');
      return;
    }

    try {
      await widget.auth.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.translate(
              context, 'Password updated. You can sign in now.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.translate(context, message))));
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
                    _step == _ResetStep.requestCode
                        ? L10n.translate(context, 'Reset your password')
                        : L10n.translate(context, 'Enter verification code'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _step == _ResetStep.requestCode
                        ? L10n.translate(context,
                            'We will send a verification code to your email.')
                        : L10n.translate(context,
                            'Use the code from email and set a new password.'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Email',
                    hint: 'you@example.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (busy) return;
                      if (_step == _ResetStep.requestCode) _requestCode();
                    },
                  ),
                  if (_step == _ResetStep.confirmReset) ...[
                    const SizedBox(height: 10),
                    _Field(
                      label: 'Verification Code',
                      hint: 'Enter code',
                      controller: _codeController,
                    ),
                    const SizedBox(height: 10),
                    _Field(
                      label: 'New Password',
                      hint: 'At least ${PasswordPolicy.minLength} characters',
                      controller: _newPasswordController,
                      obscureText: _hideNewPassword,
                      suffix: IconButton(
                        onPressed: () => setState(
                            () => _hideNewPassword = !_hideNewPassword),
                        icon: Icon(
                          _hideNewPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Field(
                      label: 'Confirm New Password',
                      hint: 'Re-enter password',
                      controller: _confirmPasswordController,
                      obscureText: _hideConfirmPassword,
                      suffix: IconButton(
                        onPressed: () => setState(
                            () => _hideConfirmPassword = !_hideConfirmPassword),
                        icon: Icon(
                          _hideConfirmPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : _requestCode,
                        child: Text(L10n.translate(context, 'Resend code')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _PrimaryButton(
                    label: _step == _ResetStep.requestCode
                        ? 'Send Reset Code'
                        : 'Update Password',
                    busy: busy,
                    onTap: busy
                        ? null
                        : () {
                            if (_step == _ResetStep.requestCode) {
                              _requestCode();
                            } else {
                              _confirmReset();
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(L10n.translate(context, 'Cancel')),
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

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.mode,
    required this.onModeChanged,
    required this.child,
  });

  final LoginEntryMode mode;
  final ValueChanged<LoginEntryMode>? onModeChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeSwitcher(
            mode: mode,
            onChanged: onModeChanged,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SocialCard extends StatelessWidget {
  const _SocialCard({
    required this.showGoogle,
    required this.showApple,
    required this.showKakao,
    required this.onGoogleTap,
    required this.onAppleTap,
    required this.onKakaoTap,
  });

  final bool showGoogle;
  final bool showApple;
  final bool showKakao;
  final VoidCallback? onGoogleTap;
  final VoidCallback? onAppleTap;
  final VoidCallback? onKakaoTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            L10n.translate(context, 'Or continue with'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (showGoogle) ...[
            _SocialButton(
              label: 'Continue with Google',
              iconWidget: const _GoogleGlyph(),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1F1F1F),
              borderColor: const Color(0xFFE6E6E6),
              onTap: onGoogleTap,
            ),
          ],
          if (showApple) ...[
            if (showGoogle) const SizedBox(height: 8),
            _SocialButton(
              label: 'Continue with Apple',
              iconWidget: const Icon(Icons.apple, size: 20),
              backgroundColor: const Color(0xFF121212),
              foregroundColor: Colors.white,
              onTap: onAppleTap,
            ),
          ],
          if (showKakao) ...[
            if (showGoogle || showApple) const SizedBox(height: 8),
            _SocialButton(
              label: 'Continue with KakaoTalk',
              iconWidget: const Icon(Icons.chat_bubble_rounded, size: 18),
              backgroundColor: const Color(0xFFFEE500),
              foregroundColor: const Color(0xFF3B1E1E),
              onTap: onKakaoTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({
    required this.mode,
    required this.onChanged,
  });

  final LoginEntryMode mode;
  final ValueChanged<LoginEntryMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: L10n.translate(context, 'Sign In'),
              active: mode == LoginEntryMode.signIn,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(LoginEntryMode.signIn),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeTab(
              label: L10n.translate(context, 'Create Account'),
              active: mode == LoginEntryMode.createAccount,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(LoginEntryMode.createAccount),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF3D7FFF), Color(0xFF54BEFF)],
                )
              : null,
        ),
        child: Text(
          L10n.translate(context, label),
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final _RegisterStep step;

  @override
  Widget build(BuildContext context) {
    final idx = step.index;
    final stepLabel = L10n.translate(context, 'Step {current} of {total}')
        .replaceAll('{current}', '${idx + 1}')
        .replaceAll('{total}', '2');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: i <= idx
                        ? const Color(0xFF56B0FF)
                        : Colors.white.withOpacity(0.16),
                  ),
                ),
              ),
              if (i != 1) const SizedBox(width: 8),
            ]
          ],
        ),
        const SizedBox(height: 10),
        Text(
          stepLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.errorText,
    this.helperText,
    this.readOnly = false,
    this.onTap,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final String? errorText;
  final String? helperText;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: L10n.translate(context, label),
        hintText: L10n.translate(context, hint),
        suffixIcon: suffix,
        errorText:
            errorText == null ? null : L10n.translate(context, errorText!),
        helperText:
            helperText == null ? null : L10n.translate(context, helperText!),
        helperMaxLines: 6,
        errorMaxLines: 8,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.86),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.40),
          fontSize: 13,
        ),
        helperStyle: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFFF9AA2),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.11)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF5F96FF), width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF7E88), width: 1.1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF7E88), width: 1.3),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: const LinearGradient(
            colors: [Color(0xFF3D7FFF), Color(0xFF49CFC9)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3D7FFF).withOpacity(0.30),
              blurRadius: 16,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      L10n.translate(context, label),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6E78).withOpacity(0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFFF8D96).withOpacity(0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: Color(0xFFFFAFB5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.translate(context, message),
              style: const TextStyle(
                color: Color(0xFFFFD7DA),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfoBanner extends StatelessWidget {
  const _InlineInfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF5F96FF).withOpacity(0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF8FB3FF).withOpacity(0.60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Color(0xFFCFE0FF),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.translate(context, message),
              style: const TextStyle(
                color: Color(0xFFE5EEFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.iconWidget,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final Widget iconWidget;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withOpacity(0.42),
          disabledForegroundColor: foregroundColor.withOpacity(0.72),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: BorderSide(color: borderColor ?? Colors.transparent),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Text(
              L10n.translate(context, label),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) {
        return const SweepGradient(
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
        ).createShader(rect);
      },
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
