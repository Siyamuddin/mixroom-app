import 'dart:async';
import 'package:flutter/services.dart';

// for "Open in Mixroom" actions or .mixroom open from outside app
class OpenMixroomService {
  OpenMixroomService._();

  static const MethodChannel _ch = MethodChannel('mixroom/open_file');

  static final StreamController<String> _controller =
      StreamController<String>.broadcast();
  static Stream<String> get stream => _controller.stream;
  static final StreamController<String> _urlController =
      StreamController<String>.broadcast();
  static Stream<String> get urlStream => _urlController.stream;

  static String? _pendingInitialPath;
  static String? _pendingInitialUrl;

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openMixroomPath') {
        final path = (call.arguments as String?)?.trim();
        if (path == null || path.isEmpty) return;

        _pendingInitialPath ??= path; // store for cold start
        _controller.add(path); // broadcast for warm start
      } else if (call.method == 'openMixroomUrl') {
        final url = (call.arguments as String?)?.trim();
        if (url == null || url.isEmpty) return;

        _pendingInitialUrl ??= url;
        _urlController.add(url);
      }
    });

    try {
      // Ask native for cold start path, but never block startup indefinitely.
      final initial = (await _ch
              .invokeMethod<String>('getInitialMixroomPath')
              .timeout(const Duration(seconds: 2)))
          ?.trim();
      if (initial != null && initial.isNotEmpty) {
        _pendingInitialPath ??= initial;
        _controller.add(initial);
      }
    } on TimeoutException {
      // Channel not ready yet; continue app startup.
    } on MissingPluginException {
      // Channel can bind slightly later in app lifecycle; continue startup.
    } on PlatformException {
      // Ignore transient startup channel errors.
    }

    try {
      final initialUrl = (await _ch
              .invokeMethod<String>('getInitialMixroomUrl')
              .timeout(const Duration(seconds: 2)))
          ?.trim();
      if (initialUrl != null && initialUrl.isNotEmpty) {
        _pendingInitialUrl ??= initialUrl;
        _urlController.add(initialUrl);
      }
    } on TimeoutException {
      // Channel not ready yet; continue app startup.
    } on MissingPluginException {
      // Channel can bind slightly later in app lifecycle; continue startup.
    } on PlatformException {
      // Ignore transient startup channel errors.
    }
  }

  static String? consumeInitialPathOnce() {
    final p = _pendingInitialPath;
    _pendingInitialPath = null;
    return p;
  }

  static String? consumeInitialUrlOnce() {
    final url = _pendingInitialUrl;
    _pendingInitialUrl = null;
    return url;
  }

  static void clearInitialUrl(String url) {
    if (_pendingInitialUrl == url) {
      _pendingInitialUrl = null;
    }
  }
}
