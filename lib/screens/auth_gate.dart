import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/screens/login.dart';
import 'package:mixroom/screens/signed_in_shell.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastStageKey;

  bool _needsRequiredProfile(
    AuthUserProfile user,
    AppUserSnapshot? profile,
    AppUserService appUser,
  ) {
    if (!appUser.supportsRemoteProfileEdits || profile == null) {
      return false;
    }
    if (user.provider == AuthProviderType.email) {
      return false;
    }
    return !profile.isSignupComplete;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, AppUserService>(
      builder: (context, auth, appUser, _) {
        late final Widget destination;
        late final String stageKey;

        if (auth.isInitializing) {
          destination = const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
          stageKey = 'auth_initializing';
        } else if (!auth.isSignedIn) {
          destination = const LoginScreen();
          stageKey = 'signed_out';
        } else {
          final signedInUser = auth.signedInUser;
          if (signedInUser == null) {
            destination = const LoginScreen();
            stageKey = 'signed_out_null_user';
          } else if (appUser.isResolvingPostSignIn || !appUser.isInitialized) {
            destination = _SignupCompletionGate(
              busy: appUser.isResolvingPostSignIn ||
                  appUser.isLoading ||
                  !appUser.isInitialized,
              isResolvingPostSignIn: appUser.isResolvingPostSignIn,
              hasPendingSignupProfileSync: false,
              onSignOut: auth.isBusy ? null : auth.signOut,
            );
            stageKey = 'profile_loading';
          } else if (_needsRequiredProfile(
            signedInUser,
            appUser.current,
            appUser,
          )) {
            destination = _RequiredProfileCompletionGate(
              user: signedInUser,
              profile: appUser.current!,
              busy: appUser.isLoading,
              error: appUser.lastError,
              onSignOut: auth.isBusy ? null : auth.signOut,
            );
            stageKey = 'required_profile';
          } else if (appUser.hasPendingSignupProfileSync) {
            destination = _SignupCompletionGate(
              busy: appUser.isLoading,
              isResolvingPostSignIn: false,
              hasPendingSignupProfileSync: true,
              onSignOut: auth.isBusy ? null : auth.signOut,
            );
            stageKey = 'pending_signup_sync';
          } else {
            destination = const SignedInShell();
            stageKey = 'signed_in_shell';
          }
        }

        final showLoginLoadingShell =
            stageKey == 'profile_loading' &&
            (_lastStageKey == 'signed_out' ||
                _lastStageKey == 'signed_out_null_user');
        final animatedChild = showLoginLoadingShell
            ? const _AuthGateLoginLoadingScreen()
            : destination;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _lastStageKey = stageKey;
        });

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: child,
            );
          },
          child: KeyedSubtree(
            key: ValueKey(showLoginLoadingShell ? 'login_loading_shell' : stageKey),
            child: animatedChild,
          ),
        );
      },
    );
  }
}

class _AuthGateLoginLoadingScreen extends StatelessWidget {
  const _AuthGateLoginLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: const [
        LoginScreen(),
        ColoredBox(
          color: Color(0x660C1A32),
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequiredProfileCompletionGate extends StatefulWidget {
  const _RequiredProfileCompletionGate({
    required this.user,
    required this.profile,
    required this.busy,
    required this.error,
    required this.onSignOut,
  });

  final AuthUserProfile user;
  final AppUserSnapshot profile;
  final bool busy;
  final String? error;
  final Future<void> Function()? onSignOut;

  @override
  State<_RequiredProfileCompletionGate> createState() =>
      _RequiredProfileCompletionGateState();
}

class _RequiredProfileCompletionGateState
    extends State<_RequiredProfileCompletionGate> {
  static final RegExp _usernamePattern =
      RegExp(r'^[a-z0-9](?:[a-z0-9_-]{0,28}[a-z0-9])?$');
  static const Set<String> _reservedUsernames = <String>{
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

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();

  DateTime? _selectedBirthdateUtc;
  bool _newsletterOptIn = false;
  String? _inlineError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final existingUsername = (widget.profile.username ?? '').trim();
    _usernameController.text =
        existingUsername.isNotEmpty ? existingUsername : _suggestUsername();
    final rawBirthdate = (widget.profile.birthdate ?? '').trim();
    if (rawBirthdate.isNotEmpty) {
      final parsed = DateTime.tryParse(rawBirthdate)?.toUtc();
      if (parsed != null) {
        _selectedBirthdateUtc =
            DateTime.utc(parsed.year, parsed.month, parsed.day);
        _birthdateController.text = _formatBirthdate(_selectedBirthdateUtc!);
      }
    }
    _newsletterOptIn = widget.profile.newsletterOptIn;
  }

  String _suggestUsername() {
    final candidates = <String>[
      (widget.profile.username ?? '').trim(),
      [
        (widget.profile.givenName ?? '').trim(),
        (widget.profile.familyName ?? '').trim(),
      ].where((value) => value.isNotEmpty).join('_'),
      widget.profile.displayName.trim(),
      widget.user.displayName.trim(),
      widget.user.email.split('@').first.trim(),
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeSuggestedUsername(candidate);
      if (normalized != null) return normalized;
    }

    final userIdSuffix = widget.user.userId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .padRight(4, '0')
        .substring(0, 4);
    return 'mixroom$userIdSuffix';
  }

  String? _normalizeSuggestedUsername(String raw) {
    var safe = raw.trim().toLowerCase();
    if (safe.isEmpty) return null;

    safe = safe.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    safe = safe.replaceAll(RegExp(r'[_-]{2,}'), '_');
    safe = safe.replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
    if (safe.isEmpty) return null;

    if (_reservedUsernames.contains(safe)) {
      final emailSeed = widget.user.email.split('@').first.toLowerCase();
      final suffix = emailSeed.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final tail = suffix.isNotEmpty
          ? suffix.substring(0, suffix.length.clamp(1, 4))
          : widget.user.userId
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '')
              .padRight(4, '0')
              .substring(0, 4);
      safe = '${safe}_$tail';
    }

    if (safe.length > 30) {
      safe = safe.substring(0, 30);
      safe = safe.replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
    }

    if (safe.isEmpty) return null;
    return _usernamePattern.hasMatch(safe) ? safe : null;
  }

  @override
  void didUpdateWidget(covariant _RequiredProfileCompletionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error &&
        (widget.error ?? '').trim().isNotEmpty &&
        !_isSubmitting) {
      _inlineError = widget.error;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _birthdateController.dispose();
    super.dispose();
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

  String? _validateUsername(String value) {
    final safe = value.trim().toLowerCase();
    if (safe.isEmpty) {
      return 'Please choose a username.';
    }
    if (safe.length > 30) {
      return 'Username must be 30 characters or fewer.';
    }
    if (_reservedUsernames.contains(safe)) {
      return 'That username is reserved.';
    }
    if (safe.contains('--') ||
        safe.contains('__') ||
        safe.contains('-_') ||
        safe.contains('_-')) {
      return 'Username cannot contain repeated separators.';
    }
    if (!_usernamePattern.hasMatch(safe)) {
      return 'Use lowercase letters, numbers, underscores, or hyphens.';
    }
    return null;
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
      _inlineError = null;
    });
  }

  Future<String?> _checkUsernameAvailability(String username) async {
    final currentUsername =
        (widget.profile.username ?? '').trim().toLowerCase();
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty || normalized == currentUsername) {
      return null;
    }

    try {
      final base = AppApiConfig.apiBaseUrl.trim();
      final normalizedBase =
          base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final response = await http.get(
        Uri.parse('$normalizedBase/v1/users/username-availability').replace(
          queryParameters: <String, String>{
            'username': normalized,
          },
        ),
        headers: const <String, String>{
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: AppApiConfig.requestTimeoutSeconds));
      if (response.statusCode < 200 || response.statusCode >= 300) {
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

  Future<void> _submit() async {
    if (_isSubmitting || widget.busy) return;
    final username = _usernameController.text.trim().toLowerCase();
    final usernameError = _validateUsername(username);
    if (usernameError != null) {
      setState(() => _inlineError = usernameError);
      return;
    }
    final birthdate = _selectedBirthdateUtc;
    if (birthdate == null) {
      setState(() => _inlineError = 'Please select your birthday.');
      return;
    }

    final availabilityError = await _checkUsernameAvailability(username);
    if (availabilityError != null) {
      if (!mounted) return;
      setState(() => _inlineError = availabilityError);
      return;
    }

    if (!mounted) return;
    final appUser = context.read<AppUserService>();
    setState(() {
      _inlineError = null;
      _isSubmitting = true;
    });

    try {
      await appUser.stageSignupConsents(
        email: widget.user.email,
        username: username,
        displayName: widget.profile.displayName,
        givenName: widget.profile.givenName,
        familyName: widget.profile.familyName,
        birthdate: _formatBirthdate(birthdate),
        newsletterOptIn: _newsletterOptIn,
      );
      await appUser.refresh(force: true);
      if (!mounted) return;
      final nextProfile = appUser.current;
      if (nextProfile == null ||
          !nextProfile.isSignupComplete) {
        setState(() {
          _inlineError = (appUser.lastError ?? '').trim().isNotEmpty
              ? appUser.lastError
              : 'Mixroom could not finish creating your account. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched || !mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.busy || _isSubmitting;
    final errorText = (_inlineError ?? '').trim();
    final inlineLinkStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF09111E),
              Color(0xFF0C182A),
              Color(0xFF101D31),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6BA8FF).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF8CBAFF).withOpacity(0.28),
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFFCFE1FF),
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Almost done',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick a username and confirm your birthday to finish setting up your Mixroom account.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _usernameController,
                      enabled: !busy,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'your_username',
                      ),
                      onChanged: (_) {
                        if (_inlineError != null) {
                          setState(() => _inlineError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You can change this later.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _birthdateController,
                      enabled: !busy,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Birthday',
                        hintText: 'Select birthday',
                        suffixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      onTap: busy ? null : _pickBirthdate,
                    ),
                    const SizedBox(height: 14),
                    CheckboxListTile(
                      value: _newsletterOptIn,
                      onChanged: busy
                          ? null
                          : (next) {
                              setState(() => _newsletterOptIn = next ?? false);
                            },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Email me product updates and news.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'By continuing, you agree to the ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _openUrl(LegalConfig.termsUrl),
                          style: inlineLinkStyle,
                          child: const Text('Terms of Service'),
                        ),
                        Text(
                          ' and ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _openUrl(LegalConfig.privacyUrl),
                          style: inlineLinkStyle,
                          child: const Text('Privacy Policy'),
                        ),
                        Text(
                          '.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A1F25).withOpacity(0.72),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFF9AA2).withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          errorText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFFFC9CF),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: Text(busy ? 'Finishing...' : 'Finish setup'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : widget.onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignupCompletionGate extends StatelessWidget {
  const _SignupCompletionGate({
    required this.busy,
    required this.isResolvingPostSignIn,
    required this.hasPendingSignupProfileSync,
    required this.onSignOut,
  });

  final bool busy;
  final bool isResolvingPostSignIn;
  final bool hasPendingSignupProfileSync;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = hasPendingSignupProfileSync ? 'Finishing setup' : 'Loading';
    final body = hasPendingSignupProfileSync
        ? (busy ? 'Almost there...' : 'Preparing your account...')
        : (isResolvingPostSignIn
            ? 'Checking your sign-in...'
            : 'Preparing your account...');
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.8),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (onSignOut != null) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: busy ? null : onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
