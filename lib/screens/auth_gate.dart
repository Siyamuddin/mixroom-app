// ignore_for_file: unused_element

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mixroom/widgets/mixroom_glass_dropdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const Duration _androidExitBackInterval = Duration(seconds: 2);

  String? _lastStageKey;
  LoginEntryMode _signedOutLoginMode = LoginEntryMode.signIn;
  VoidCallback? _signedOutVisibleBackHandler;
  DateTime? _lastAndroidExitBackPressedAt;

  bool get _usesAndroidBackGuard =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _needsRequiredProfile(
    AppUserSnapshot? profile,
    AppUserService appUser,
  ) {
    if (!appUser.supportsRemoteProfileEdits || profile == null) {
      return false;
    }
    final username = (profile.username ?? '').trim();
    return !profile.isSignupComplete || username.isEmpty;
  }

  Future<void> _handleRequiredProfileBack(AuthUserProfile user) async {
    setState(() {
      _signedOutLoginMode = user.provider == AuthProviderType.email
          ? LoginEntryMode.createAccount
          : LoginEntryMode.signIn;
    });
    await context.read<AuthService>().signOut();
  }

  void _handleSignedOutModeChanged(LoginEntryMode mode) {
    if (_signedOutLoginMode == mode) return;
    setState(() {
      _signedOutLoginMode = mode;
      _lastAndroidExitBackPressedAt = null;
    });
  }

  void _handleSignedOutVisibleBackHandlerChanged(VoidCallback? handler) {
    _signedOutVisibleBackHandler = handler;
    _lastAndroidExitBackPressedAt = null;
  }

  void _handleAndroidBack({
    required bool didPop,
    required String stageKey,
    Future<void> Function()? stageBackHandler,
  }) {
    if (didPop || !_usesAndroidBackGuard) return;

    if (stageBackHandler != null) {
      stageBackHandler();
      _lastAndroidExitBackPressedAt = null;
      return;
    }

    final visibleBackHandler = _signedOutVisibleBackHandler;
    if ((stageKey == 'signed_out' || stageKey == 'signed_out_null_user') &&
        visibleBackHandler != null) {
      visibleBackHandler();
      _lastAndroidExitBackPressedAt = null;
      return;
    }

    final now = DateTime.now();
    final previous = _lastAndroidExitBackPressedAt;
    if (previous != null &&
        now.difference(previous) <= _androidExitBackInterval) {
      SystemNavigator.pop();
      return;
    }

    _lastAndroidExitBackPressedAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(L10n.translate(context, 'Press back again to exit Mixroom')),
          duration: _androidExitBackInterval,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, AppUserService>(
      builder: (context, auth, appUser, _) {
        late final Widget destination;
        late final String stageKey;
        Future<void> Function()? stageBackHandler;

        if (auth.isInitializing) {
          destination = const MixroomLaunchSplash();
          stageKey = 'auth_initializing';
        } else if (!auth.isSignedIn) {
          destination = LoginScreen(
            initialMode: _signedOutLoginMode,
            onModeChanged: _handleSignedOutModeChanged,
            onVisibleBackHandlerChanged:
                _handleSignedOutVisibleBackHandlerChanged,
          );
          stageKey = 'signed_out';
        } else {
          final signedInUser = auth.signedInUser;
          if (signedInUser == null) {
            destination = LoginScreen(
              initialMode: _signedOutLoginMode,
              onModeChanged: _handleSignedOutModeChanged,
              onVisibleBackHandlerChanged:
                  _handleSignedOutVisibleBackHandlerChanged,
            );
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
            Future<void> requiredProfileBackHandler() {
              return _handleRequiredProfileBack(signedInUser);
            }

            final requiredProfileBusy = auth.isBusy || appUser.isLoading;
            stageBackHandler =
                requiredProfileBusy ? () async {} : requiredProfileBackHandler;
            destination = _RequiredProfileCompletionGate(
              user: signedInUser,
              profile: appUser.current!,
              busy: requiredProfileBusy,
              error: appUser.lastError,
              onBack: requiredProfileBusy ? null : requiredProfileBackHandler,
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

        return PopScope(
          canPop: !_usesAndroidBackGuard,
          onPopInvokedWithResult: (didPop, _) {
            _handleAndroidBack(
              didPop: didPop,
              stageKey: stageKey,
              stageBackHandler: stageBackHandler,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              final slide = Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved);
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: SlideTransition(
                  position: slide,
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(
                  showLoginLoadingShell ? 'login_loading_shell' : stageKey),
              child: animatedChild,
            ),
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
    return MixroomAuthPageScaffold(
      body: SafeArea(
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
  static const double _tabletProfileContentWidth = 348;
  static final math.Random _usernameRandom = math.Random();

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
  final TextEditingController _bioController = TextEditingController();

  DateTime? _selectedBirthdateUtc;
  String? _musicProfileValue;
  bool _musicProfileMenuOpen = false;
  bool _acceptedLegalTerms = false;
  bool _requiresProfileConsent = false;
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
    _bioController.text = (widget.profile.bio ?? '').trim();
    final hasAcceptedLegalTerms = _profileHasAcceptedLegalTerms(widget.profile);
    _acceptedLegalTerms = hasAcceptedLegalTerms;
    _requiresProfileConsent = !hasAcceptedLegalTerms;
    _newsletterOptIn = widget.profile.newsletterOptIn;
  }

  bool _profileHasAcceptedLegalTerms(AppUserSnapshot profile) {
    return (profile.acceptedTermsVersion ?? '').trim().isNotEmpty &&
        (profile.acceptedPrivacyVersion ?? '').trim().isNotEmpty &&
        profile.acceptedAt != null;
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

  String _generateMixroomUsername() {
    final suffix =
        _usernameRandom.nextInt(1000000000).toString().padLeft(9, '0');
    return 'mixroom-user$suffix';
  }

  void _generateUsername() {
    setState(() {
      _usernameController.text = _generateMixroomUsername();
      _inlineError = null;
    });
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
    if (!_acceptedLegalTerms && _profileHasAcceptedLegalTerms(widget.profile)) {
      _acceptedLegalTerms = true;
      _requiresProfileConsent = false;
    }
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
    _bioController.dispose();
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
    final selectedMusicProfileLabel = musicProfileLabel(_musicProfileValue);
    final triggerText = selectedMusicProfileLabel.isEmpty
        ? L10n.translate(context, 'Select one')
        : L10n.translate(context, selectedMusicProfileLabel);
    final textColor = _musicProfileValue == null
        ? const Color.fromRGBO(244, 244, 244, 0.72)
        : const Color(0xFFF4F4F4);
    final options = kMusicProfileOptions
        .map((option) => MapEntry(option.value, option.label))
        .toList();
    final useOverlayDropdown = mixroomUseTabletDesktopAuthLayout(context);

    return Builder(
      builder: (anchorContext) {
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
                          : () async {
                              if (!useOverlayDropdown) {
                                setState(() {
                                  _musicProfileMenuOpen =
                                      !_musicProfileMenuOpen;
                                });
                                return;
                              }

                              setState(() => _musicProfileMenuOpen = true);
                              final selected =
                                  await showMixroomGlassDropdown<String>(
                                anchorContext: anchorContext,
                                verticalGap: 0,
                                horizontalInset: 24,
                                minWidth: _tabletProfileContentWidth,
                                maxWidth: _tabletProfileContentWidth,
                                preferredHeight: math.min(
                                  356.0,
                                  1.0 + (options.length * 44.0),
                                ),
                                radius: 24,
                                color: const Color.fromRGBO(78, 88, 96, 0.94),
                                padding: EdgeInsets.zero,
                                child: _buildMusicProfileDropdownMenu(options),
                              );
                              if (!mounted) return;
                              setState(() {
                                _musicProfileMenuOpen = false;
                                if (selected != null) {
                                  _musicProfileValue = selected;
                                  _inlineError = null;
                                }
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
                                      angle:
                                          _musicProfileMenuOpen ? 0 : math.pi,
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
                    child: !useOverlayDropdown && _musicProfileMenuOpen
                        ? _buildInlineMusicProfileDropdownMenu(
                            options: options,
                            busy: busy,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineMusicProfileDropdownMenu({
    required List<MapEntry<String, String>> options,
    required bool busy,
  }) {
    return Column(
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
          final isSelected = _musicProfileValue == entry.key;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: busy
                  ? null
                  : () {
                      setState(() {
                        _musicProfileValue = entry.key;
                        _inlineError = null;
                        _musicProfileMenuOpen = false;
                      });
                    },
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 23),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          L10n.translate(context, entry.value),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: const Color(0xFFF4F4F4),
                            fontSize: 15,
                            height: 22 / 15,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
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
    );
  }

  Widget _buildMusicProfileDropdownMenu(
    List<MapEntry<String, String>> options,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      child: Column(
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
            final isSelected = _musicProfileValue == entry.key;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(entry.key),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 23),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            L10n.translate(context, entry.value),
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

  void _clearBirthdate() {
    setState(() {
      _selectedBirthdateUtc = null;
      _birthdateController.clear();
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
    final bio = _bioController.text.trim();
    final latestAllowedBirthdate = _latestAllowedBirthdateUtc();
    if (birthdate != null && birthdate.isAfter(latestAllowedBirthdate)) {
      setState(() {
        _inlineError =
            'You must be at least ${LegalConfig.minimumSignupAgeYears} years old to use Mixroom.';
      });
      return;
    }
    if (_musicProfileValue == null) {
      setState(() {
        _inlineError = L10n.translate(
          context,
          'Please choose what you use Mixroom for.',
        );
      });
      return;
    }
    if (bio.length > 160) {
      setState(() {
        _inlineError = L10n.translate(
          context,
          'Bio must be 160 characters or fewer.',
        );
      });
      return;
    }
    if (!_acceptedLegalTerms) {
      setState(() {
        _inlineError = L10n.translate(
          context,
          'Please agree to the Terms of Service and Privacy Policy.',
        );
      });
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
    final localeCode = Localizations.localeOf(context).languageCode;
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
        birthdate: birthdate == null ? null : _formatBirthdate(birthdate),
        musicProfile: _musicProfileValue,
        bio: bio.isEmpty ? null : bio,
        newsletterOptIn: _newsletterOptIn,
        localeCode: localeCode,
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
        birthdate: birthdate == null ? null : _formatBirthdate(birthdate),
        musicProfile: _musicProfileValue,
        bio: bio.isEmpty ? null : bio,
        newsletterOptIn: _newsletterOptIn,
        localeCode: localeCode,
      );
      if (!mounted) return;
      final nextProfile = appUser.current;
      final persistedUsername = (nextProfile?.username ?? '').trim();
      if (nextProfile == null ||
          !nextProfile.isSignupComplete ||
          persistedUsername.isEmpty) {
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

  Widget _buildTabletProfileLayout({
    required bool busy,
    required BoxConstraints constraints,
    required double bottomInset,
    required String errorText,
    required String legalErrorText,
    required String musicProfileErrorText,
    required String bioErrorText,
    required bool highlightsUsernameSection,
    required bool highlightsConsentSection,
  }) {
    final minHeight = math.max(0.0, constraints.maxHeight - bottomInset);
    final showConsentRows = _requiresProfileConsent || highlightsConsentSection;
    final contentTop = _tabletProfileContentTop(constraints.maxHeight);
    final estimatedContentHeight = showConsentRows ? 716.0 : 590.0;
    final scrollHeight = math.max(
      minHeight,
      contentTop + estimatedContentHeight + 36.0,
    );

    return Stack(
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              height: scrollHeight,
              child: Stack(
                children: [
                  Positioned(
                    top: contentTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        width: _tabletProfileContentWidth,
                        child: _buildTabletProfileContent(
                          busy: busy,
                          errorText: errorText,
                          legalErrorText: legalErrorText,
                          musicProfileErrorText: musicProfileErrorText,
                          bioErrorText: bioErrorText,
                          highlightsUsernameSection: highlightsUsernameSection,
                          highlightsConsentSection: highlightsConsentSection,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          left: 24,
          child: MixroomAuthBackCircleButton(
            onTap: busy
                ? null
                : () {
                    widget.onBack?.call();
                  },
          ),
        ),
        const Positioned(
          top: 14,
          right: 24,
          child: MixroomLocaleSelector(),
        ),
      ],
    );
  }

  double _tabletProfileContentTop(double availableHeight) {
    return math.min(164.0, math.max(96.0, availableHeight * 0.17));
  }

  Widget _buildTabletProfileContent({
    required bool busy,
    required String errorText,
    required String legalErrorText,
    required String musicProfileErrorText,
    required String bioErrorText,
    required bool highlightsUsernameSection,
    required bool highlightsConsentSection,
  }) {
    final usernameErrorText = highlightsUsernameSection ? errorText : '';
    final musicErrorText = errorText == musicProfileErrorText ? errorText : '';
    final bioInlineErrorText = errorText == bioErrorText ? errorText : '';
    final legalInlineErrorText = errorText == legalErrorText ? errorText : '';
    final handledError = usernameErrorText.isNotEmpty ||
        musicErrorText.isNotEmpty ||
        bioInlineErrorText.isNotEmpty ||
        legalInlineErrorText.isNotEmpty;
    final genericErrorText =
        errorText.isNotEmpty && !handledError ? errorText : '';
    final showConsentRows = _requiresProfileConsent || highlightsConsentSection;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MixroomBrandLockup(showMark: false),
        const SizedBox(height: 28),
        MixroomGlassPanel(
          borderColor: highlightsUsernameSection
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
                label: L10n.translate(context, 'Birthday (yyyy.mm.dd)'),
                readOnly: true,
                onTap: busy ? null : _pickBirthdate,
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_birthdateController.text.trim().isNotEmpty)
                      IconButton(
                        onPressed: busy ? null : _clearBirthdate,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFFF4F4F4),
                          size: 18,
                        ),
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    GestureDetector(
                      onTap: busy ? null : _pickBirthdate,
                      behavior: HitTestBehavior.translucent,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SvgPicture.asset(
                          kMixroomCalendarIconAsset,
                          width: 18,
                          height: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (usernameErrorText.isNotEmpty) ...[
          const SizedBox(height: 9),
          _TabletProfileInlineError(message: usernameErrorText),
          const SizedBox(height: 26),
        ] else
          const SizedBox(height: 36),
        Text(
          L10n.translate(context, 'What describes you best?'),
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
        if (musicErrorText.isNotEmpty) ...[
          const SizedBox(height: 8),
          _TabletProfileInlineError(message: musicErrorText),
          const SizedBox(height: 18),
        ] else
          const SizedBox(height: 28),
        Text(
          L10n.translate(context, 'Bio'),
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
        _buildTabletBioPanel(busy: busy),
        if (bioInlineErrorText.isNotEmpty) ...[
          const SizedBox(height: 8),
          _TabletProfileInlineError(message: bioInlineErrorText),
        ],
        if (showConsentRows) ...[
          const SizedBox(height: 18),
          _buildTabletProfileConsentRows(
            busy: busy,
            highlightsConsentSection: highlightsConsentSection,
          ),
          if (legalInlineErrorText.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TabletProfileInlineError(message: legalInlineErrorText),
          ],
        ],
        if (genericErrorText.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TabletProfileInlineError(message: genericErrorText),
        ],
        const SizedBox(height: 30),
        Center(
          child: MixroomPillButton(
            label: L10n.translate(context, 'Done'),
            width: 124,
            busy: busy,
            onTap: busy ? null : _submit,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletBioPanel({required bool busy}) {
    return MixroomGlassPanel(
      child: SizedBox(
        height: 112,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(23, 14, 23, 12),
          child: TextField(
            controller: _bioController,
            enabled: !busy,
            minLines: null,
            maxLines: null,
            expands: true,
            maxLength: 160,
            cursorColor: Colors.white,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 15,
              height: 22 / 15,
              fontWeight: FontWeight.w400,
            ),
            onChanged: (_) {
              if (_inlineError != null) {
                setState(() => _inlineError = null);
              }
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              hintText: L10n.translate(
                context,
                'Tell people a bit about yourself',
              ),
              hintStyle: const TextStyle(
                fontFamily: 'Pretendard',
                color: Color.fromRGBO(244, 244, 244, 0.72),
                fontSize: 15,
                height: 22 / 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletProfileConsentRows({
    required bool busy,
    required bool highlightsConsentSection,
  }) {
    final legalLabel = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 3,
      runSpacing: 2,
      children: [
        Text(L10n.translate(context, "I agree to Mixroom's")),
        MixroomAuthInlineLink(
          label: L10n.translate(context, 'terms'),
          onTap: busy ? null : () => _openUrl(LegalConfig.termsUrl),
        ),
        Text(L10n.translate(context, 'and')),
        MixroomAuthInlineLink(
          label: L10n.translate(context, 'privacy policy'),
          onTap: busy ? null : () => _openUrl(LegalConfig.privacyUrl),
        ),
        const Text('.'),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlightsConsentSection
              ? const Color.fromRGBO(255, 157, 71, 0.72)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          MixroomAuthConsentRow(
            value: _newsletterOptIn,
            onChanged: busy
                ? null
                : (next) {
                    setState(() {
                      _newsletterOptIn = next;
                      _inlineError = null;
                    });
                  },
            label: L10n.translate(
              context,
              'I agree to receive marketing and promotional material.',
            ),
          ),
          MixroomAuthConsentRow(
            value: _acceptedLegalTerms,
            onChanged: busy
                ? null
                : (next) {
                    setState(() {
                      _acceptedLegalTerms = next;
                      _inlineError = null;
                    });
                  },
            richLabel: legalLabel,
          ),
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: 136,
              child: MixroomAuthConsentRow(
                value: _acceptedLegalTerms && _newsletterOptIn,
                onChanged: busy
                    ? null
                    : (next) {
                        setState(() {
                          _acceptedLegalTerms = next;
                          _newsletterOptIn = next;
                          _inlineError = null;
                        });
                      },
                label: L10n.translate(context, 'Agree to all.'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _isSubmitting;
    final errorText = (_inlineError ?? '').trim();
    final legalErrorText = L10n.translate(
      context,
      'Please agree to the Terms of Service and Privacy Policy.',
    );
    final musicProfileErrorText = L10n.translate(
      context,
      'Please choose what you use Mixroom for.',
    );
    final bioErrorText = L10n.translate(
      context,
      'Bio must be 160 characters or fewer.',
    );
    final normalizedError = errorText.toLowerCase();
    final highlightsUsernameSection = errorText.isNotEmpty &&
        errorText != legalErrorText &&
        errorText != musicProfileErrorText &&
        errorText != bioErrorText &&
        (normalizedError.contains('username') ||
            errorText.startsWith('You must be at least '));
    final highlightsConsentSection = errorText == legalErrorText;

    return MixroomAuthPageScaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            if (mixroomUseTabletLandscapeAuthLayout(context)) {
              return _buildTabletProfileLayout(
                busy: busy,
                constraints: constraints,
                bottomInset: bottomInset,
                errorText: errorText,
                legalErrorText: legalErrorText,
                musicProfileErrorText: musicProfileErrorText,
                bioErrorText: bioErrorText,
                highlightsUsernameSection: highlightsUsernameSection,
                highlightsConsentSection: highlightsConsentSection,
              );
            }
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
                          borderColor: highlightsUsernameSection
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
                                suffix: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_birthdateController.text
                                        .trim()
                                        .isNotEmpty)
                                      IconButton(
                                        onPressed:
                                            busy ? null : _clearBirthdate,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: Color(0xFFF4F4F4),
                                          size: 18,
                                        ),
                                        splashRadius: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                      ),
                                    GestureDetector(
                                      onTap: busy ? null : _pickBirthdate,
                                      behavior: HitTestBehavior.translucent,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: SvgPicture.asset(
                                          kMixroomCalendarIconAsset,
                                          width: 18,
                                          height: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: busy ? null : _generateUsername,
                            icon: const Icon(Icons.autorenew_rounded, size: 16),
                            label: Text(
                              L10n.translate(context, 'Generate username'),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFF4F4F4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          L10n.translate(context, 'Bio'),
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
                        MixroomGlassPanel(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(23, 18, 23, 14),
                            child: TextField(
                              controller: _bioController,
                              enabled: !busy,
                              minLines: 4,
                              maxLines: 4,
                              maxLength: 160,
                              cursorColor: Colors.white,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 15,
                                height: 22 / 15,
                                fontWeight: FontWeight.w400,
                              ),
                              onChanged: (_) {
                                if (_inlineError != null) {
                                  setState(() => _inlineError = null);
                                }
                              },
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: L10n.translate(
                                  context,
                                  'Tell people a bit about yourself',
                                ),
                                hintStyle: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color.fromRGBO(244, 244, 244, 0.72),
                                  fontSize: 15,
                                  height: 22 / 15,
                                  fontWeight: FontWeight.w400,
                                ),
                                counterStyle: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color.fromRGBO(244, 244, 244, 0.72),
                                  fontSize: 11,
                                  height: 1.3,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (errorText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
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
                          const SizedBox(height: 10),
                        ] else
                          const SizedBox(height: 8),
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
                        const SizedBox(height: 22),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: highlightsConsentSection
                                  ? const Color.fromRGBO(
                                      255,
                                      157,
                                      71,
                                      0.72,
                                    )
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            children: [
                              _SignupConsentCheckbox(
                                value: _acceptedLegalTerms && _newsletterOptIn,
                                onChanged: busy
                                    ? null
                                    : (next) {
                                        setState(() {
                                          _acceptedLegalTerms = next;
                                          _newsletterOptIn = next;
                                          _inlineError = null;
                                        });
                                      },
                                label: L10n.translate(context, 'Agree to all'),
                              ),
                              const SizedBox(height: 6),
                              _SignupConsentCheckbox(
                                value: _acceptedLegalTerms,
                                onChanged: busy
                                    ? null
                                    : (next) {
                                        setState(() {
                                          _acceptedLegalTerms = next;
                                          _inlineError = null;
                                        });
                                      },
                                richLabel: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 2,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      L10n.translate(
                                        context,
                                        'I agree to the',
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color.fromRGBO(
                                          244,
                                          244,
                                          244,
                                          0.82,
                                        ),
                                        fontSize: 13,
                                        height: 18 / 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    _ConsentLinkText(
                                      label: L10n.translate(
                                        context,
                                        'Terms of Service',
                                      ),
                                      onTap: busy
                                          ? null
                                          : () => _openUrl(
                                                LegalConfig.termsUrl,
                                              ),
                                    ),
                                    Text(
                                      L10n.translate(context, 'and'),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color.fromRGBO(
                                          244,
                                          244,
                                          244,
                                          0.82,
                                        ),
                                        fontSize: 13,
                                        height: 18 / 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    _ConsentLinkText(
                                      label: L10n.translate(
                                        context,
                                        'Privacy Policy',
                                      ),
                                      onTap: busy
                                          ? null
                                          : () => _openUrl(
                                                LegalConfig.privacyUrl,
                                              ),
                                    ),
                                    const Text(
                                      '.',
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color.fromRGBO(
                                          244,
                                          244,
                                          244,
                                          0.82,
                                        ),
                                        fontSize: 13,
                                        height: 18 / 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              _SignupConsentCheckbox(
                                value: _newsletterOptIn,
                                onChanged: busy
                                    ? null
                                    : (next) {
                                        setState(() {
                                          _newsletterOptIn = next;
                                          _inlineError = null;
                                        });
                                      },
                                label: L10n.translate(
                                  context,
                                  'Receive marketing and update emails',
                                ),
                              ),
                            ],
                          ),
                        ),
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
    );
  }
}

class _SignupConsentCheckbox extends StatelessWidget {
  const _SignupConsentCheckbox({
    required this.value,
    required this.onChanged,
    this.label,
    this.richLabel,
  }) : assert(label != null || richLabel != null);

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? richLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged!(next ?? false) : null,
              activeColor: const Color(0xFF5F96FF),
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -2,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.40)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: richLabel ??
                  Text(
                    label!,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color.fromRGBO(244, 244, 244, 0.82),
                      fontSize: 13,
                      height: 18 / 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletProfileInlineError extends StatelessWidget {
  const _TabletProfileInlineError({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      L10n.translate(context, message),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Pretendard',
        color: Color(0xFFFF9D47),
        fontSize: 12,
        height: 15 / 12,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _ConsentLinkText extends StatelessWidget {
  const _ConsentLinkText({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          color: Color(0xFFF4F4F4),
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFF4F4F4),
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
    return MixroomAuthPageScaffold(
      body: SafeArea(
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
    );
  }
}
