import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/timed_native_operation.dart';

void main() {
  test(
    'never-returning native load releases its Dart caller at timeout',
    () async {
      final nativeReply = Completer<bool>();
      final messages = <String>[];

      final result = await runTimedNativeOperation<bool>(
        'MIDI instrument load clip=7',
        () => nativeReply.future,
        timeout: const Duration(milliseconds: 20),
        logger: messages.add,
      );

      expect(result, isNull);
      expect(messages.first, contains('start'));
      expect(messages.last, contains('timeout'));
    },
  );

  test(
    'success after timeout cannot change the completed Dart result',
    () async {
      final nativeReply = Completer<bool>();
      final resultFuture = runTimedNativeOperation<bool>(
        'MIDI instrument load clip=7',
        () => nativeReply.future,
        timeout: const Duration(milliseconds: 20),
        logger: (_) {},
      );

      expect(await resultFuture, isNull);
      nativeReply.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(await resultFuture, isNull);
    },
  );
}
