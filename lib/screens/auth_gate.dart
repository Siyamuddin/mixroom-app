// ignore_for_file: unused_element

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/config/app_api_config.dart';
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/app_user_models.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/models/music_profile_option.dart';
import 'package:mixroom/screens/login.dart';
import 'package:mixroom/screens/signed_in_shell.dart';
import 'package:mixroom/widgets/auth_figma_shell.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastStageKey;
  LoginEntryMode _signedOutLoginMode = LoginEntryMode.signIn;

  bool _needsRequiredProfile(
    AppUserSnapshot? profile,
    AppUserService appUser,
  ) {
    if (!appUser.supportsRemoteProfileEdits || profile == null) {
      return false;
    }
    return !profile.isSignupComplete;
  }

  Future<void> _handleRequiredProfileBack(AuthUserProfile user) async {
    setState(() {
      _signedOutLoginMode = user.provider == AuthProviderType.email
          ? LoginEntryMode.createAccount
          : LoginEntryMode.signIn;
    });
    await context.read<AuthService>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, AppUserService>(
      builder: (context, auth, appUser, _) {
        late final Widget destination;
        late final String stageKey;

        if (auth.isInitializing) {
          destination = const MixroomLaunchSplash();
          stageKey = 'auth_initializing';
        } else if (!auth.isSignedIn) {
          destination = LoginScreen(initialMode: _signedOutLoginMode);
          stageKey = 'signed_out';
        } else {
          final signedInUser = auth.signedInUser;
          if (signedInUser == null) {
            destination = LoginScreen(initialMode: _signedOutLoginMode);
            stageKey = 'signed_out_null_user';
          } else if (appUser.isResolvingPostSignIn || !appUser.isInitialized) {
            destination = _SignupCompletionGate(
              busy: appUser.isResolvingPostSignIn ||
                  appUser.isLoading ||
                  !appUser.isInitialized,
              isResolvingPostSignIn: appUser.isResolvingPostSignIn,
              hasPendingSignupProfileSync: false,
            );
            stageKey = 'profile_loading';
          } else if (_needsRequiredProfile(
            appUser.current,
            appUser,
          )) {
            destination = _RequiredProfileCompletionGate(
              user: signedInUser,
              profile: appUser.current!,
              busy: appUser.isLoading,
              error: appUser.lastError,
              onBack: auth.isBusy
                  ? null
                  : () => _handleRequiredProfileBack(signedInUser),
            );
            stageKey = 'required_profile';
          } else if (appUser.hasPendingSignupProfileSync) {
            destination = _SignupCompletionGate(
              busy: appUser.isLoading,
              isResolvingPostSignIn: false,
              hasPendingSignupProfileSync: true,
            );
            stageKey = 'pending_signup_sync';
          } else {
            destination = const SignedInShell();
            stageKey = 'signed_in_shell';
          }
        }

        final showLoginLoadingShell = stageKey == 'profile_loading' &&
            (_lastStageKey == 'signed_out' ||
                _lastStageKey == 'signed_out_null_user');
        final animatedChild = showLoginLoadingShell
            ? const _AuthGateLoginLoadingScreen()
            : destination;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _lastStageKey = stageKey;
          if (stageKey == 'signed_in_shell' &&
              _signedOutLoginMode != LoginEntryMode.signIn &&
              mounted) {
            setState(() {
              _signedOutLoginMode = LoginEntryMode.signIn;
            });
          }
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
            key: ValueKey(
                showLoginLoadingShell ? 'login_loading_shell' : stageKey),
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
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MixroomAuthBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: _AuthGateStatusPanel(
                  title: L10n.translate(context, 'Loading your account'),
                  body: L10n.translate(context, 'Checking your sign-in...'),
                  compact: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthGateStatusPanel extends StatelessWidget {
  const _AuthGateStatusPanel({
    required this.title,
    required this.body,
    this.compact = false,
  });

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compact ? 24 : 26,
            height: compact ? 24 : 26,
            child: const CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color(0xFFF4F4F4),
              ),
            ),
          ),
          SizedBox(height: compact ? 18 : 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: const Color(0xFFF4F4F4),
              fontSize: compact ? 22 : 24,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color.fromRGBO(244, 244, 244, 0.82),
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredProfileCompletionGate extends StatefulWidget {
  const _RequiredProfileCompletionGate({
    required this.user,
    required this.profile,
    required this.busy,
    required this.error,
    required this.onBack,
  });

  final AuthUserProfile user;
  final AppUserSnapshot profile;
  final bool busy;
  final String? error;
  final Future<void> Function()? onBack;

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
  String? _musicProfileValue;
  bool _musicProfileMenuOpen = false;
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
    _musicProfileValue = (widget.profile.musicProfile ?? '').trim().isEmpty
        ? null
        : widget.profile.musicProfile!.trim().toLowerCase();
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

  DateTime _defaultBirthdateForPickerUtc() {
    final now = DateTime.now().toUtc();
    final defaultDate = DateTime.utc(now.year - 18, now.month, now.day);
    final first = _earliestSelectableBirthdateUtc();
    final last = _latestAllowedBirthdateUtc();
    if (defaultDate.isBefore(first)) return first;
    if (defaultDate.isAfter(last)) return last;
    return defaultDate;
  }

  Widget _buildMusicProfileSelector({required bool busy}) {
    final triggerText = _musicProfileValue == null
        ? L10n.translate(context, 'Select one (optional)')
        : musicProfileLabel(_musicProfileValue);
    final textColor = _musicProfileValue == null
        ? const Color.fromRGBO(244, 244, 244, 0.72)
        : const Color(0xFFF4F4F4);
    final options = <MapEntry<String, String>>[
      MapEntry('__unset__', L10n.translate(context, 'Not set')),
      ...kMusicProfileOptions.map(
        (option) => MapEntry(option.value, option.label),
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color.fromRGBO(244, 244, 244, 0.30),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.25),
                blurRadius: 15,
                spreadRadius: 8,
              ),
            ],
            border: Border.all(
              color: const Color.fromRGBO(244, 244, 244, 0.12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: busy
                      ? null
                      : () {
                          setState(() {
                            _musicProfileMenuOpen = !_musicProfileMenuOpen;
                          });
                        },
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(23, 0, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              triggerText,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: textColor,
                                fontSize: 15,
                                height: 22 / 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Opacity(
                            opacity: busy ? 0.45 : 1,
                            child: SizedBox(
                              width: 11.25,
                              height: 11.25,
                              child: Center(
                                child: Transform.rotate(
                                  angle: _musicProfileMenuOpen ? 0 : math.pi,
                                  child: SvgPicture.asset(
                                    kMixroomDropdownIconAsset,
                                    width: 11.25,
                                    height: 11.25,
                                    colorFilter: const ColorFilter.mode(
                                      Color(0x80F4F4F4),
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _musicProfileMenuOpen
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 23),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Color.fromRGBO(244, 244, 244, 0.15),
                            ),
                          ),
                          ...options.map((entry) {
                            final isSelected = entry.key == '__unset__'
                                ? _musicProfileValue == null
                                : _musicProfileValue == entry.key;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: busy
                                    ? null
                                    : () {
                                        setState(() {
                                          _musicProfileValue =
                                              entry.key == '__unset__'
                                                  ? null
                                                  : entry.key;
                                          _inlineError = null;
                                          _musicProfileMenuOpen = false;
                                        });
                                      },
                                child: SizedBox(
                                  height: 44,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 23,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            entry.value,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Pretendard',
                                              color: const Color(0xFFF4F4F4),
                                              fontSize: 15,
                                              height: 22 / 15,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_rounded,
                                            color: Color(0xFFF4F4F4),
                                            size: 16,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
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
        displayName: widget.profile.displayName.trim().isNotEmpty
            ? widget.profile.displayName
            : widget.user.displayName,
        givenName: widget.profile.givenName,
        familyName: widget.profile.familyName,
        birthdate: _formatBirthdate(birthdate),
        musicProfile: _musicProfileValue,
        newsletterOptIn: _newsletterOptIn,
        syncImmediately: false,
      );
      await appUser.completeSignupProfile(
        email: widget.user.email,
        username: username,
        displayName: widget.profile.displayName.trim().isNotEmpty
            ? widget.profile.displayName
            : widget.user.displayName,
        givenName: widget.profile.givenName,
        familyName: widget.profile.familyName,
        birthdate: _formatBirthdate(birthdate),
        musicProfile: _musicProfileValue,
        newsletterOptIn: _newsletterOptIn,
      );
      if (!mounted) return;
      final nextProfile = appUser.current;
      final expectedMusicProfile =
          (_musicProfileValue ?? '').trim().toLowerCase();
      final persistedMusicProfile =
          (nextProfile?.musicProfile ?? '').trim().toLowerCase();
      final missingExpectedMusicProfile = expectedMusicProfile.isNotEmpty &&
          persistedMusicProfile != expectedMusicProfile;
      if (nextProfile == null ||
          !nextProfile.isSignupComplete ||
          missingExpectedMusicProfile) {
        setState(() {
          _inlineError = missingExpectedMusicProfile
              ? 'Mixroom could not save your music profile. Please try again.'
              : (appUser.lastError ?? '').trim().isNotEmpty
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
    final busy = widget.busy || _isSubmitting;
    final errorText = (_inlineError ?? '').trim();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: MixroomAuthBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                final minHeight = constraints.maxHeight - bottomInset - 24;

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
                          minHeight: minHeight < 0 ? 0 : minHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MixroomAuthTopBar(
                              onBack: busy
                                  ? null
                                  : () {
                                      widget.onBack?.call();
                                    },
                            ),
                            const SizedBox(height: 52),
                            const MixroomBrandLockup(showMark: false),
                            const SizedBox(height: 28),
                            Text(
                              L10n.translate(
                                context,
                                'Finish your account setup',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 22,
                                height: 28 / 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              L10n.translate(
                                context,
                                'Add the last few details to start using Mixroom.',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color.fromRGBO(244, 244, 244, 0.72),
                                fontSize: 14,
                                height: 20 / 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 34),
                            MixroomGlassPanel(
                              borderColor: errorText.isNotEmpty
                                  ? const Color.fromRGBO(255, 157, 71, 0.72)
                                  : const Color.fromRGBO(244, 244, 244, 0.14),
                              child: Column(
                                children: [
                                  MixroomGlassTextFieldRow(
                                    controller: _usernameController,
                                    label: L10n.translate(context, 'Username'),
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) {
                                      if (_inlineError != null) {
                                        setState(() => _inlineError = null);
                                      }
                                    },
                                  ),
                                  const MixroomGlassDivider(),
                                  MixroomGlassTextFieldRow(
                                    controller: _birthdateController,
                                    label: L10n.translate(
                                      context,
                                      'Birthday (yyyy.mm.dd)',
                                    ),
                                    readOnly: true,
                                    onTap: busy ? null : _pickBirthdate,
                                    suffix: SvgPicture.asset(
                                      kMixroomCalendarIconAsset,
                                      width: 18,
                                      height: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 15,
                              child: Text(
                                errorText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color(0xFFFF9D47),
                                  fontSize: 12,
                                  height: 15 / 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              L10n.translate(
                                context,
                                'What describes you best?',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 15,
                                height: 22 / 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildMusicProfileSelector(busy: busy),
                            const SizedBox(height: 60),
                            Center(
                              child: MixroomPillButton(
                                label: L10n.translate(context, 'Done'),
                                width: 124,
                                busy: busy,
                                onTap: busy ? null : _submit,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: MixroomSecondaryPillButton(
                                label: L10n.translate(context, 'Back'),
                                width: 124,
                                onTap: busy
                                    ? null
                                    : () {
                                        widget.onBack?.call();
                                      },
                              ),
                            ),
                          ],
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
}

class _SignupCompletionGate extends StatelessWidget {
  const _SignupCompletionGate({
    required this.busy,
    required this.isResolvingPostSignIn,
    required this.hasPendingSignupProfileSync,
  });

  final bool busy;
  final bool isResolvingPostSignIn;
  final bool hasPendingSignupProfileSync;

  @override
  Widget build(BuildContext context) {
    final title = hasPendingSignupProfileSync
        ? L10n.translate(context, 'Finishing setup')
        : L10n.translate(context, 'Loading your account');
    final body = hasPendingSignupProfileSync
        ? (busy
            ? L10n.translate(context, 'Almost there...')
            : L10n.translate(context, 'Preparing your account...'))
        : (isResolvingPostSignIn
            ? L10n.translate(context, 'Checking your sign-in...')
            : L10n.translate(
                context,
                'We are getting everything ready for you.',
              ));
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MixroomAuthBackground(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _AuthGateStatusPanel(
                    title: title,
                    body: body,
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
