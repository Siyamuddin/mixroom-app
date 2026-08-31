import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/transport_loop.dart';

void main() {
  group('wrapTransportClockToLoop', () {
    test('leaves clocks inside the region unchanged', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 180),
        loopEnabled: true,
        loopStartMs: 100,
        loopEndMs: 250,
      );

      expect(actual, const Duration(milliseconds: 180));
    });

    test('wraps a 200ms loop at the end marker', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 300),
        loopEnabled: true,
        loopStartMs: 100,
        loopEndMs: 300,
      );

      expect(actual, const Duration(milliseconds: 100));
    });

    test('wraps overshoot on a 120ms loop instead of running past it', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 520),
        loopEnabled: true,
        loopStartMs: 400,
        loopEndMs: 520,
      );

      expect(actual, const Duration(milliseconds: 400));
    });

    test('wraps multiple overshoots on a 100ms loop', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 350),
        loopEnabled: true,
        loopStartMs: 0,
        loopEndMs: 100,
      );

      expect(actual, const Duration(milliseconds: 50));
    });

    test('does not wrap when looping is off', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 800),
        loopEnabled: false,
        loopStartMs: 0,
        loopEndMs: 100,
      );

      expect(actual, const Duration(milliseconds: 800));
    });

    test('does not wrap an empty loop region', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 800),
        loopEnabled: true,
        loopStartMs: 200,
        loopEndMs: 200,
      );

      expect(actual, const Duration(milliseconds: 800));
    });

    test('wraps a clock sitting exactly on the end marker', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 150),
        loopEnabled: true,
        loopStartMs: 50,
        loopEndMs: 150,
      );

      expect(actual, const Duration(milliseconds: 50));
    });

    test('leaves a clock one millisecond before the end unchanged', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 149),
        loopEnabled: true,
        loopStartMs: 50,
        loopEndMs: 150,
      );

      expect(actual, const Duration(milliseconds: 149));
    });

    test('does not pull a paused clock from past the loop back in', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 40),
        loopEnabled: true,
        loopStartMs: 100,
        loopEndMs: 200,
      );

      expect(actual, const Duration(milliseconds: 40));
    });

    test('wraps the 50ms UI minimum loop length', () {
      final actual = wrapTransportClockToLoop(
        clock: const Duration(milliseconds: 175),
        loopEnabled: true,
        loopStartMs: 100,
        loopEndMs: 150,
      );

      expect(actual, const Duration(milliseconds: 125));
    });
  });

  group('isTransportLoopRegionValid', () {
    test('requires a positive-length enabled region', () {
      expect(
        isTransportLoopRegionValid(
          loopEnabled: true,
          loopStartMs: 0,
          loopEndMs: 120,
        ),
        isTrue,
      );
      expect(
        isTransportLoopRegionValid(
          loopEnabled: true,
          loopStartMs: 120,
          loopEndMs: 120,
        ),
        isFalse,
      );
      expect(
        isTransportLoopRegionValid(
          loopEnabled: false,
          loopStartMs: 0,
          loopEndMs: 120,
        ),
        isFalse,
      );
      expect(
        isTransportLoopRegionValid(
          loopEnabled: true,
          loopStartMs: 200,
          loopEndMs: 100,
        ),
        isFalse,
      );
    });
  });
}
