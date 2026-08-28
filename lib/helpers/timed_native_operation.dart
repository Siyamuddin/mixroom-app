import 'dart:async';

import 'package:flutter/foundation.dart';

typedef NativeOperationLogger = void Function(String message);
typedef NativeOperationTimeoutHandler = FutureOr<void> Function();

/// Runs a native operation without allowing a missing platform-channel reply
/// to leave its Dart caller pending forever.
Future<T?> runTimedNativeOperation<T>(
  String label,
  Future<T> Function() task, {
  required Duration timeout,
  NativeOperationLogger? logger,
  NativeOperationTimeoutHandler? onTimeout,
}) async {
  final log = logger ?? debugPrint;
  final stopwatch = Stopwatch()..start();
  log('[PluginRestore] start $label');
  try {
    final result = await task().timeout(timeout);
    log(
      '[PluginRestore] done $label in '
      '${stopwatch.elapsedMilliseconds}ms result=$result',
    );
    return result;
  } on TimeoutException {
    log(
      '[PluginRestore] timeout $label after '
      '${stopwatch.elapsedMilliseconds}ms',
    );
    if (onTimeout != null) {
      try {
        await onTimeout();
      } catch (error, stackTrace) {
        log(
          '[PluginRestore] timeout cleanup failed $label: '
          '$error\n$stackTrace',
        );
      }
    }
    return null;
  } catch (error, stackTrace) {
    log(
      '[PluginRestore] failed $label after '
      '${stopwatch.elapsedMilliseconds}ms: $error\n$stackTrace',
    );
    return null;
  }
}
