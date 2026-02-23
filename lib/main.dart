import 'dart:async';
import 'dart:io';

// import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/helpers/open_mixroom_service.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:path_provider/path_provider.dart';

// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';

import 'screens/home.dart';
import 'screens/projects.dart';
// import 'screens/video_editor.dart';
import 'screens/video_editor2.dart';
import 'screens/audio_editor.dart';

import 'screens/effects.dart';
import 'screens/account.dart';
import 'widgets/side_menu.dart';
import 'screens/login.dart';
import 'package:mixroom/l10n/l10n.dart';

import 'package:provider/provider.dart'; // Import Provider
import 'package:mixroom/providers/locale_provider.dart'; // Import LocaleProvider

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

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
    setState(() {
      // _appLocale = localeProvider.locale ?? const Locale('en');
      // TODO: just make all English for now (can support language selector later)
      _appLocale = const Locale('en');
    });
  }

  // Method to set the locale from anywhere
  void setAppLocale(Locale newLocale) {
    setState(() {
      _appLocale = newLocale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mixroom App',
      locale: _appLocale,
      // supportedLocales: L10n.supportedLocales,
      // localizationsDelegates: const <LocalizationsDelegate<dynamic>>[],
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey,
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
      home:
          const ProjectsScreen(), //const AudioEditorScreen(mode: 'Pro'), //HomeScreen(), //VideoEditorScreen(), //VideoEditorScreen(),
    );
  }
}

// Top level global
bool _zeroOffsetPointerGuardInstalled = false;

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TEMP FIX FOR IOS 26 IPAD
  _installZeroOffsetPointerGuard();

  await _cleanupAllTempFiles();
  // Directory dir1 = await getApplicationDocumentsDirectory();
  // Directory dir2 = await getApplicationSupportDirectory();
  // await _deleteAllInDirectory(dir1);
  // await _deleteAllInDirectory(dir2);

  listenForNativeLogs();

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // FlutterError.onError = (details) {
  //   JuceAudioEngine.shutdown();
  //   FlutterError.dumpErrorToConsole(details);
  // };

  PlatformDispatcher.instance.onError = (error, stack) {
    // print("it's here bruh");
    // comment out cuz if export gets cancelled this gets called
    // JuceAudioEngine.shutdown();
    // return true to prevent the error from propagating further
    return true;
  };

  await OpenMixroomService.init();

  runApp(ChangeNotifierProvider(
      create: (context) => LocaleProvider(), child: const MyApp()));
}

void listenForNativeLogs() {
  const logEvents = EventChannel('juce_audio_engine/logs');
  logEvents.receiveBroadcastStream().listen((event) {
    print('[JUCE DEBUG] ${event['message']}');
  });
}

Future<void> _cleanupAllTempFiles() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync();

    int deletedCount = 0;
    int totalBytes = 0;

    for (var file in files) {
      try {
        if (file is File) {
          final length = await file.length();
          await file.delete();
          deletedCount++;
          totalBytes += length;
        } else if (file is Directory) {
          final dirSize = await _getDirectorySize(file);
          await file.delete(recursive: true);
          deletedCount++;
          totalBytes += dirSize;
        }
      } catch (_) {
        // Skip errors silently
      }
    }

    final sizeMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    if (deletedCount > 0) {
      print(
          "🧹 Deleted $deletedCount item${deletedCount == 1 ? '' : 's'} ($sizeMB MB) from temp directory.");
    } else {
      print("🧼 Temp directory was already clean.");
    }
  } catch (e) {
    print("⚠️ Temp cleanup failed: $e");
  }
}

Future<int> _getDirectorySize(Directory dir) async {
  int size = 0;
  try {
    await for (var entity in dir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
  } catch (_) {}
  return size;
}

Future<void> _deleteAllInDirectory(Directory dir) async {
  if (!await dir.exists()) return;
  for (var entity in dir.listSync(recursive: true)) {
    try {
      await entity.delete(recursive: true);
    } catch (_) {}
  }
}
