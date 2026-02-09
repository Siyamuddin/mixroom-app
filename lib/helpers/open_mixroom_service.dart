import 'dart:async';
import 'package:flutter/services.dart';

// for "Open in Mixroom" actions or .mixroom open from outside app
class OpenMixroomService {
  OpenMixroomService._();

  static const MethodChannel _ch = MethodChannel('mixroom/open_file');

  static final StreamController<String> _controller = StreamController<String>.broadcast();
  static Stream<String> get stream => _controller.stream;

  static String? _pendingInitialPath;

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openMixroomPath') {
        final path = (call.arguments as String?)?.trim();
        if (path == null || path.isEmpty) return;

        _pendingInitialPath ??= path; // store for cold start
        _controller.add(path); // broadcast for warm start
      }
    });

    // ask native for cold start path
    final initial = (await _ch.invokeMethod<String>('getInitialMixroomPath'))?.trim();
    if (initial != null && initial.isNotEmpty) {
      _pendingInitialPath ??= initial;
      _controller.add(initial);
    }
  }

  static String? consumeInitialPathOnce() {
    final p = _pendingInitialPath;
    _pendingInitialPath = null;
    return p;
  }
}
