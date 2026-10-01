import 'package:mixroom/config/hackathon_config.dart';

import 'dart:async';

// import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:mixroom/config/dev_flags.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/crash_reporting/crash_reporting_service.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/desktop_file_ingress_service.dart';
import 'package:mixroom/helpers/desktop_auto_update_service.dart';
import 'package:mixroom/helpers/iap_service.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/helpers/orientation_policy.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/l10n/l10n.dart';

// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';

import 'screens/auth_gate.dart';
import 'screens/hackathon_home.dart';

import 'package:provider/provider.dart'; // Import Provider
import 'package:mixroom/providers/locale_provider.dart'; // Import LocaleProvider

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

class _BundledLicenseNotice {
  const _BundledLicenseNotice({
    required this.packages,
    required this.licenseAssetPath,
    this.noticeAssetPath,
  });

  final List<String> packages;
  final String licenseAssetPath;
  final String? noticeAssetPath;
}

const List<_BundledLicenseNotice> _bundledLicenseNotices =
    <_BundledLicenseNotice>[
  _BundledLicenseNotice(
    packages: <String>[
      'Basic Pitch',
      'Spotify AB',
    ],
    licenseAssetPath: 'assets/licenses/basic_pitch/LICENSE',
    noticeAssetPath: 'assets/licenses/basic_pitch/NOTICE',
  ),
  _BundledLicenseNotice(
    packages: <String>[
      'VSCO 2 CE',
      'VCSL Upright Piano, Knight',
    ],
    licenseAssetPath: 'assets/instruments/VSCO-2-CE-1.1.0/LICENSE',
    noticeAssetPath: 'assets/instruments/VSCO-2-CE-1.1.0/NOTICE.md',
  ),
  _BundledLicenseNotice(
    packages: <String>[
      'Acoustic Guitar',
      'FreePats Spanish Classical Guitar',
      'Roberto, FreePats',
    ],
    licenseAssetPath:
        'assets/instruments/FreePats-Spanish-Classical-Guitar-2019-06-18/LICENSE',
    noticeAssetPath:
        'assets/instruments/FreePats-Spanish-Classical-Guitar-2019-06-18/NOTICE.md',
  ),
  _BundledLicenseNotice(
    packages: <String>[
      'Electric Guitar',
      'Karoryfer Black And Green Guitars',
      'Karoryfer Lecolds',
      'Brian Wood',
    ],
    licenseAssetPath:
        'assets/instruments/Karoryfer-Black-And-Green-Guitars-1.000/LICENSE',
    noticeAssetPath:
        'assets/instruments/Karoryfer-Black-And-Green-Guitars-1.000/NOTICE.md',
  ),
];

Future<void> _registerBundledThirdPartyLicenses() async {
  for (final notice in _bundledLicenseNotices) {
    try {
      final licenseText = await rootBundle.loadString(notice.licenseAssetPath);
      final noticeText = notice.noticeAssetPath == null
          ? null
          : await rootBundle.loadString(notice.noticeAssetPath!);
      final combinedText = noticeText == null || noticeText.trim().isEmpty
          ? licenseText
          : '$licenseText\n\nNOTICE\n\n$noticeText';
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(notice.packages, combinedText);
      });
    } catch (error) {
      debugPrint(
        'Bundled license registration skipped for '
        '${notice.licenseAssetPath}: $error',
      );
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  Locale? _appLocale;

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadLocale() async {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    await localeProvider.loadLocale();
    if (!mounted) return;
    setState(() {
      _appLocale = L10n.resolveSupportedLocale(localeProvider.locale);
    });
  }

  // Method to set the locale from anywhere
  void setAppLocale(Locale newLocale) {
    setState(() {
      _appLocale = L10n.resolveSupportedLocale(newLocale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final providerLocale = context.watch<LocaleProvider>().locale;
    final effectiveLocale = providerLocale ?? _appLocale;
    return MaterialApp(
      title: 'Mixroom App',
      locale: L10n.resolveSupportedLocale(effectiveLocale),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        return L10n.resolveSupportedLocale(locale);
      },
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey,
      navigatorObservers: <NavigatorObserver>[
        if (!HackathonConfig.enabled) SentryNavigatorObserver(),
      ],
      theme: ThemeData(
        fontFamily: 'Pretendard',
        brightness: Brightness.dark,
        primaryColor:
            const Color(0xFF0C1A32), //const Color.fromARGB(255, 98, 98, 98),
        scaffoldBackgroundColor: const Color(0xFF0C1A32),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 107, 107, 107),
          brightness: Brightness.dark,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color.fromARGB(255, 255, 255, 255),
          thumbColor: const Color.fromARGB(255, 255, 255, 255),
          inactiveTrackColor: Colors.white24,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 103, 103, 103),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF162641),
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          contentTextStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF13233D),
          elevation: 14,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          titleTextStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: const Color(0xFF13233D),
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: const Color(0xFF13233D),
          modalBarrierColor: Colors.black.withOpacity(0.55),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          elevation: 12,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF13233D),
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB9D4FF),
          ),
        ),

        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          titleLarge: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
          titleMedium: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white70),
          bodyMedium: TextStyle(fontSize: 14, color: Colors.white60),
          labelLarge: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      //****TEMPORARY****
      home: HackathonConfig.enabled ? const HackathonHomeScreen() : const AuthGate(),
    );
  }
}

// Top level global
bool _zeroOffsetPointerGuardInstalled = false;
bool _orientationPolicyObserverInstalled = false;
Timer? _orientationPolicyDebounce;

void _installZeroOffsetPointerGuard() {
  if (_zeroOffsetPointerGuardInstalled) return;
  GestureBinding.instance.pointerRouter
      .addGlobalRoute(_absorbZeroOffsetPointerEvent);
  _zeroOffsetPointerGuardInstalled = true;
}

void _absorbZeroOffsetPointerEvent(PointerEvent event) {
  if (event.position == Offset.zero) {
    GestureBinding.instance.cancelPointer(event.pointer);
  }
}

class _OrientationPolicyObserver extends WidgetsBindingObserver {
  @override
  void didChangeMetrics() {
    _orientationPolicyDebounce?.cancel();
    _orientationPolicyDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(applyPreferredOrientationsForCurrentWindow());
    });
  }
}

void _installOrientationPolicyObserver() {
  if (_orientationPolicyObserverInstalled) return;
  WidgetsBinding.instance.addObserver(_OrientationPolicyObserver());
  _orientationPolicyObserverInstalled = true;
}

Future<void> _runStartupStep(
  String name,
  Future<void> Function() step,
) async {
  try {
    await step();
  } catch (error, stackTrace) {
    debugPrint('Startup step failed ($name): $error');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'mixroom.startup',
        context: ErrorDescription('while running startup step "$name"'),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TEMP FIX FOR IOS 26 IPAD
  _installZeroOffsetPointerGuard();

  if (isNativeJuceLoggingEnabled) {
    listenForNativeLogs();
  }

  await _runStartupStep('orientation.apply', () async {
    await applyPreferredOrientationsForCurrentWindow();
    _installOrientationPolicyObserver();
  });

  await _runStartupStep('platform_capabilities.refresh', () async {
    await PlatformCapabilities.refresh();
  });

  await _runStartupStep('analytics.initialize', () async {
    await AnalyticsService.instance.initialize();
  });
  await _runStartupStep('licenses.register', () async {
    await _registerBundledThirdPartyLicenses();
  });
  await _runStartupStep('crash_reporting.initialize', () async {
    await CrashReportingService.instance.initialize();
  });

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(CrashReportingService.instance.captureFlutterError(details));
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      CrashReportingService.instance.captureException(
        error,
        stackTrace: stack,
      ),
    );
    return true;
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => LocaleProvider()),
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, AppUserService>(
          create: (_) => AppUserService(),
          update: (_, auth, service) {
            final next = service ?? AppUserService();
            next.bindAuth(auth);
            return next;
          },
        ),
        ChangeNotifierProxyProvider<AuthService, EntitlementService>(
          create: (_) => EntitlementService(),
          update: (_, auth, service) {
            final next = service ?? EntitlementService();
            next.bindAuth(auth);
            return next;
          },
        ),
        ChangeNotifierProxyProvider<EntitlementService, IapService>(
          create: (_) => IapService(),
          update: (_, entitlementService, service) {
            final next = service ?? IapService();
            next.bindEntitlementService(entitlementService);
            return next;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );

  // Never block first frame on startup method channels.
  unawaited(OpenMixroomService.init());
  unawaited(DesktopFileIngressService.init());
  unawaited(DesktopAutoUpdateService.instance.initialize());
}

void listenForNativeLogs() {
  const logEvents = EventChannel('juce_audio_engine/logs');
  logEvents.receiveBroadcastStream().listen((event) {
    debugPrint('[JUCE DEBUG] ${event['message']}');
  });
}
