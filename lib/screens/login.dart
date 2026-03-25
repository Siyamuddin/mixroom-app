import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:mixroom/widgets/email_verification_sheet.dart';
import 'package:mixroom/widgets/language_selector.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum _AuthMode { signIn, register }

enum _SignInStep { email, password }

enum _RegisterStep { account, profile }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
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

  _AuthMode _mode = _AuthMode.signIn;
  _SignInStep _signInStep = _SignInStep.email;
  _RegisterStep _registerStep = _RegisterStep.account;

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _newsletterOptIn = false;
  DateTime? _selectedBirthdateUtc;

  String? _signInEmailError;
  String? _signInPasswordError;
  String? _signInInlineError;
  String? _registerEmailError;
  String? _registerPasswordError;
  String? _registerConfirmPasswordError;
  String? _registerUsernameError;
  String? _registerBirthdateError;
  String? _registerInlineError;
  String? _registerInlineInfo;

  @override
  void dispose() {
    _emailController.dispose();
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

  bool get _isRegisterMode => _mode == _AuthMode.register;

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
    final usernameError = _validateUsername(_signupUsernameController.text);
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

  String _composeSignupDisplayName() {
    final parts = <String>[
      _trimmedFirstName(),
      _trimmedLastName(),
    ].where((part) => part.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    return _signupUsernameController.text.trim().toLowerCase();
  }

  String? _validateBirthdate(DateTime? birthdateUtc) {
    if (birthdateUtc == null) {
      return 'Please select your birthday.';
    }
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

  Future<void> _pickBirthdate() async {
    final initialDate = _selectedBirthdateUtc ?? _latestAllowedBirthdateUtc();
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

  void _switchMode(_AuthMode next) {
    if (_mode == next) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = next;
      _signInStep = _SignInStep.email;
      _registerStep = _RegisterStep.account;
      _newsletterOptIn = false;
      _clearSignInErrors();
      _clearRegisterErrors();
    });
  }

  void _continueToPasswordStep() {
    if (!_isLikelyLoginIdentifier(_emailController.text.trim())) {
      setState(() {
        _signInEmailError = 'Please enter a valid email or username.';
      });
      _signInEmailFocusNode.requestFocus();
      return;
    }

    setState(() {
      _signInEmailError = null;
      _signInInlineError = null;
      _signInStep = _SignInStep.password;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _signInPasswordFocusNode.requestFocus();
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
                        _mode = _AuthMode.signIn;
                        _signInStep = _SignInStep.password;
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
        await _submitSocial(
          auth,
          auth.signInWithGoogle,
          providerLabel: AuthProviderType.google.label,
        );
        return;
      case AuthProviderType.apple:
        await _submitSocial(
          auth,
          auth.signInWithApple,
          providerLabel: AuthProviderType.apple.label,
        );
        return;
      case AuthProviderType.kakao:
        await _submitSocial(
          auth,
          auth.signInWithKakao,
          providerLabel: AuthProviderType.kakao.label,
        );
        return;
      case AuthProviderType.email:
      case null:
        if (!mounted) return;
        setState(() {
          _mode = _AuthMode.signIn;
          _signInStep = _SignInStep.password;
          _emailController.text = safeEmail;
          _passwordController.clear();
          _signInInlineError = conflict.message;
        });
        return;
    }
  }

  Future<void> _submitSignIn(AuthService auth) async {
    FocusScope.of(context).unfocus();

    if (_passwordController.text.isEmpty) {
      setState(() {
        _signInPasswordError = 'Please enter your password.';
      });
      return;
    }

    setState(() {
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

    if (!_validateRegisterProfileStep()) return;

    setState(() {
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    final usernameAvailabilityError = await _checkUsernameAvailability();
    if (usernameAvailabilityError != null) {
      if (!mounted) return;
      setState(() {
        _registerUsernameError = usernameAvailabilityError;
      });
      return;
    }

    try {
      await auth.registerWithEmail(
        name: _composeSignupDisplayName(),
        givenName: _trimmedFirstName(),
        familyName: _trimmedLastName(),
        birthdate: _birthdateController.text.trim(),
        email: _emailController.text,
        password: _passwordController.text,
      );
      await appUserService.stageSignupConsents(
        email: safeEmail,
        username: _signupUsernameController.text,
        displayName: _composeSignupDisplayName(),
        givenName: _trimmedFirstName(),
        familyName: _trimmedLastName(),
        birthdate: _birthdateController.text.trim(),
        newsletterOptIn: _newsletterOptIn,
      );
    } on AuthEmailConfirmationRequiredException catch (e) {
      await appUserService.stageSignupConsents(
        email: safeEmail,
        username: _signupUsernameController.text,
        displayName: _composeSignupDisplayName(),
        givenName: _trimmedFirstName(),
        familyName: _trimmedLastName(),
        birthdate: _birthdateController.text.trim(),
        newsletterOptIn: _newsletterOptIn,
      );
      if (!mounted) return;
      if (auth.isSignedIn) return;
      setState(() {
        _registerInlineError = e.message;
      });
      await _openEmailVerificationFlow(auth);
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
      return 'Please choose a username.';
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
    final isRegisterSocialFlow = _isRegisterMode;
    if (isRegisterSocialFlow) {
      if (_registerStep != _RegisterStep.profile) {
        FocusScope.of(context).unfocus();
        setState(() {
          _registerStep = _RegisterStep.profile;
          _registerInlineError = null;
          _registerInlineInfo =
              'Choose a username and birthday, then continue with $providerLabel.';
        });
        return;
      }
      if (!_validateRegisterProfileStep()) {
        return;
      }
      final usernameAvailabilityError = await _checkUsernameAvailability();
      if (usernameAvailabilityError != null) {
        if (!mounted) return;
        setState(() {
          _registerUsernameError = usernameAvailabilityError;
          _registerInlineInfo = null;
        });
        return;
      }
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _signInInlineError = null;
      _registerInlineError = null;
      _registerInlineInfo = null;
    });

    var resolvingPostSignIn = false;
    try {
      if (isRegisterSocialFlow) {
        appUserService.beginPostSignInResolution();
        resolvingPostSignIn = true;
      }
      await action();
      if (isRegisterSocialFlow &&
          auth.lastSocialSignInRequiresSignupCompletion &&
          auth.signedInUser != null) {
        try {
          await appUserService.stageSignupConsents(
            email: auth.signedInUser!.email,
            username: _signupUsernameController.text,
            displayName: _composeSignupDisplayName(),
            givenName: _trimmedFirstName(),
            familyName: _trimmedLastName(),
            birthdate: _birthdateController.text.trim(),
            newsletterOptIn: _newsletterOptIn,
          );
        } catch (_) {
          await auth.signOut();
          throw StateError(
            'Mixroom could not finish preparing your signup details. Please try again.',
          );
        }
      }
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
        _mode = _AuthMode.signIn;
        _signInStep = _SignInStep.password;
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
      _mode = _AuthMode.signIn;
      _signInStep = _SignInStep.password;
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
            defaultTargetPlatform == TargetPlatform.iOS);
    final showGoogle = supportsSocialSignIn && CognitoConfig.enableGoogleSignIn;
    final showApple = supportsSocialSignIn &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        CognitoConfig.enableAppleSignIn;
    final showKakao = supportsSocialSignIn && CognitoConfig.enableKakaoSignIn;
    final showAnySocial = showGoogle || showApple || showKakao;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        color: const Color(0xFF15498E),
        child: Stack(
          children: [
            const Positioned.fill(
              child: _MusicBackdrop(),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, _) {
                  final bottomInset = MediaQuery.of(context).viewInsets.bottom;

                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: ListView(
                      physics: const ClampingScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 2),
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: LanguageSelector(),
                                ),
                                const SizedBox(height: 12),
                                const _BrandHeader(),
                                const SizedBox(height: 22),
                                _AuthCard(
                                  mode: _mode,
                                  onModeChanged: busy ? null : _switchMode,
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    alignment: Alignment.topCenter,
                                    clipBehavior: Clip.hardEdge,
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: _slideFadeTransition,
                                      layoutBuilder:
                                          (currentChild, previousChildren) =>
                                              currentChild ??
                                              const SizedBox.shrink(),
                                      child: _isRegisterMode
                                          ? _buildRegisterFlow(
                                              auth: auth,
                                              busy: busy,
                                            )
                                          : _buildSignInFlow(
                                              auth: auth,
                                              busy: busy,
                                            ),
                                    ),
                                  ),
                                ),
                                if (showAnySocial) ...[
                                  const SizedBox(height: 14),
                                  _SocialCard(
                                    showGoogle: showGoogle,
                                    showApple: showApple,
                                    showKakao: showKakao,
                                    onGoogleTap: busy
                                        ? null
                                        : () => _submitSocial(
                                              auth,
                                              auth.signInWithGoogle,
                                              providerLabel:
                                                  AuthProviderType.google.label,
                                            ),
                                    onAppleTap: busy
                                        ? null
                                        : () => _submitSocial(
                                              auth,
                                              auth.signInWithApple,
                                              providerLabel:
                                                  AuthProviderType.apple.label,
                                            ),
                                    onKakaoTap: busy
                                        ? null
                                        : () => _submitSocial(
                                              auth,
                                              auth.signInWithKakao,
                                              providerLabel:
                                                  AuthProviderType.kakao.label,
                                            ),
                                  ),
                                ],
                                if (isDevLoginButtonEnabled) ...[
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => _devRealLogin(auth),
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
                                        foregroundColor:
                                            Colors.white.withOpacity(0.72),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInFlow({required AuthService auth, required bool busy}) {
    return Column(
      key: const ValueKey('sign-in-flow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            child: _signInStep == _SignInStep.email
                ? Column(
                    key: const ValueKey('sign-in-email-step'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Field(
                        label: 'Email or username',
                        hint: 'Email or username',
                        controller: _emailController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        focusNode: _signInEmailFocusNode,
                        errorText: _signInEmailError,
                        onChanged: (_) {
                          setState(() {
                            _signInEmailError = null;
                            _signInInlineError = null;
                          });
                        },
                        onSubmitted: (_) {
                          if (busy) return;
                          _continueToPasswordStep();
                        },
                      ),
                      const SizedBox(height: 14),
                      if (_signInInlineError != null) ...[
                        _InlineErrorBanner(message: _signInInlineError!),
                        const SizedBox(height: 10),
                      ],
                      _PrimaryButton(
                        label: 'Continue',
                        onTap: busy ? null : _continueToPasswordStep,
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('sign-in-password-step'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SignedInEmailChip(
                        email: _emailController.text.trim(),
                        onTap: busy
                            ? null
                            : () {
                                setState(() {
                                  _signInStep = _SignInStep.email;
                                  _signInPasswordError = null;
                                  _signInInlineError = null;
                                });
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _signInEmailFocusNode.requestFocus();
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Password',
                        hint: 'Enter password',
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        textInputAction: TextInputAction.done,
                        focusNode: _signInPasswordFocusNode,
                        errorText: _signInPasswordError,
                        onChanged: (_) {
                          setState(() {
                            _signInPasswordError = null;
                            _signInInlineError = null;
                          });
                        },
                        onSubmitted: (_) {
                          if (busy) return;
                          _submitSignIn(auth);
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              busy ? null : () => _openForgotPasswordFlow(auth),
                          child:
                              Text(L10n.translate(context, 'Forgot password?')),
                        ),
                      ),
                      if (_signInInlineError != null) ...[
                        const SizedBox(height: 6),
                        _InlineErrorBanner(message: _signInInlineError!),
                      ],
                      if (auth.hasPendingEmailVerification) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: busy
                                ? null
                                : () => _openEmailVerificationFlow(auth),
                            child: Text(
                              L10n.translate(
                                  context, 'Enter verification code'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _PrimaryButton(
                        label: busy ? 'Signing In...' : 'Sign In',
                        busy: busy,
                        onTap: busy ? null : () => _submitSignIn(auth),
                      ),
                    ],
                  ),
          ),
        ),
      ],
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
              child: Text(L10n.translate(context, 'Enter verification code')),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const _SignupLegalNotice(),
        const SizedBox(height: 8),
        _PrimaryButton(
          label: _registerStep == _RegisterStep.profile
              ? (busy ? 'Creating...' : 'Create Account')
              : 'Continue',
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
              label: 'Username',
              hint: 'your_username',
              controller: _signupUsernameController,
              errorText: _registerUsernameError,
              helperText:
                  'Used for your username and sign-in. Lowercase letters, numbers, underscores, and hyphens only.',
              onChanged: (_) {
                setState(() {
                  _registerUsernameError = null;
                  _registerInlineError = null;
                  _registerInlineInfo = null;
                });
              },
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Birthday',
              hint: 'Select birthday',
              controller: _birthdateController,
              readOnly: true,
              errorText: _registerBirthdateError,
              helperText:
                  'Required. You must be at least ${LegalConfig.minimumSignupAgeYears} years old to use Mixroom.',
              onTap: _pickBirthdate,
              suffix: IconButton(
                onPressed: _pickBirthdate,
                icon: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white70,
                ),
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
      await widget.auth.requestPasswordReset(email: email);
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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/short_white.png',
          height: 30,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 14),
        Text(
          L10n.translate(context, 'Welcome to Mixroom'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          L10n.translate(context, 'Fast, AI-assisted music production.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.mode,
    required this.onModeChanged,
    required this.child,
  });

  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onModeChanged;
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

  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

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
              label: 'Sign In',
              active: mode == _AuthMode.signIn,
              onTap:
                  onChanged == null ? null : () => onChanged!(_AuthMode.signIn),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeTab(
              label: 'Create Account',
              active: mode == _AuthMode.register,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(_AuthMode.register),
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

class _SignedInEmailChip extends StatelessWidget {
  const _SignedInEmailChip({required this.email, required this.onTap});

  final String email;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.11)),
      ),
      child: Row(
        children: [
          const Icon(Icons.email_outlined, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(L10n.translate(context, 'Change')),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.focusNode,
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
  final FocusNode? focusNode;
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
      focusNode: focusNode,
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

class _MusicBackdrop extends StatelessWidget {
  const _MusicBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: const _TexturedBlueBackdropPainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TexturedBlueBackdropPainter extends CustomPainter {
  const _TexturedBlueBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    _paintColorWash(canvas, bounds);
    _paintDiagonalTexture(canvas, size);
    _paintMusicLines(canvas, size);
    _paintDust(canvas, size);
    _paintVignette(canvas, bounds);
  }

  void _paintColorWash(Canvas canvas, Rect bounds) {
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF112F5E).withValues(alpha: 0.34),
          const Color(0xFF1D5CA6).withValues(alpha: 0.16),
          const Color(0xFF0E2951).withValues(alpha: 0.36),
        ],
      ).createShader(bounds);
    canvas.drawRect(bounds, fill);

    final centerGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.10, -0.35),
        radius: 1.0,
        colors: [
          const Color(0xFF9BCCFF).withValues(alpha: 0.14),
          Colors.transparent,
        ],
      ).createShader(bounds);
    canvas.drawRect(bounds, centerGlow);
  }

  void _paintDiagonalTexture(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < 24; i++) {
      final t = i / 23;
      linePaint.color = const Color(0xFFE2F3FF).withValues(
        alpha: 0.010 + (i % 4) * 0.003,
      );
      canvas.drawLine(
        Offset(-size.width * 0.24, size.height * (t + 0.14)),
        Offset(size.width * 1.18, size.height * (t - 0.16)),
        linePaint,
      );
    }
  }

  void _paintMusicLines(Canvas canvas, Size size) {
    _paintWave(
      canvas,
      size,
      baselineFactor: 0.30,
      amplitudeFactor: 0.010,
      frequency: 2.2,
      color: const Color(0xFFA9DCFF).withValues(alpha: 0.20),
    );
    _paintWave(
      canvas,
      size,
      baselineFactor: 0.72,
      amplitudeFactor: 0.008,
      frequency: 3.4,
      color: const Color(0xFFBFE4FF).withValues(alpha: 0.17),
    );
  }

  void _paintWave(
    Canvas canvas,
    Size size, {
    required double baselineFactor,
    required double amplitudeFactor,
    required double frequency,
    required Color color,
  }) {
    final baseline = size.height * baselineFactor;
    final amplitude = size.height * amplitudeFactor;
    final path = Path();
    for (double x = 0; x <= size.width; x += 3.5) {
      final n = x / size.width;
      final y = baseline +
          math.sin(n * math.pi * 2 * frequency) * amplitude +
          math.sin(n * math.pi * 2 * (frequency * 0.62) + 1.8) *
              (amplitude * 0.46);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.20),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.62),
    );
  }

  void _paintDust(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 220; i++) {
      final dx = _unit(i * 71 + 3) * size.width;
      final dy = _unit(i * 43 + 11) * size.height;
      final radius = 0.35 + _unit(i * 89 + 17) * 0.85;
      paint.color = const Color(0xFFEAF7FF).withValues(
        alpha: 0.010 + _unit(i * 97 + 5) * 0.030,
      );
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  double _unit(int seed) {
    final value = (seed * 1103515245 + 12345) & 0x7fffffff;
    return value / 0x7fffffff;
  }

  void _paintVignette(Canvas canvas, Rect bounds) {
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.05),
        radius: 1.2,
        colors: [
          Colors.transparent,
          const Color(0xFF02060C).withValues(alpha: 0.60),
        ],
        stops: const [0.52, 1.0],
      ).createShader(bounds);
    canvas.drawRect(bounds, vignette);
  }

  @override
  bool shouldRepaint(covariant _TexturedBlueBackdropPainter oldDelegate) =>
      false;
}
