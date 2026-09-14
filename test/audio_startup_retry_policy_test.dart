import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_startup_retry_policy.dart';

void main() {
  test('null diagnostic code does not retry', () {
    final decision = decideStartupRetry(diagnosticCode: null, attempt: 1);

    expect(decision.retry, isFalse);
    expect(decision.delay, Duration.zero);
  });

  test('empty diagnostic code does not retry', () {
    final decision = decideStartupRetry(diagnosticCode: '', attempt: 1);

    expect(decision.retry, isFalse);
  });

  test('transient codes retry with a short delay on the first failure', () {
    for (final code in kTransientAudioStartupCodes) {
      final decision = decideStartupRetry(diagnosticCode: code, attempt: 1);

      expect(decision.retry, isTrue, reason: code);
      expect(decision.delay, const Duration(milliseconds: 250));
    }
  });

  test('second transient failure waits longer before the last attempt', () {
    final decision = decideStartupRetry(
      diagnosticCode: 'route_unstable',
      attempt: 2,
    );

    expect(decision.retry, isTrue);
    expect(decision.delay, const Duration(milliseconds: 500));
  });

  test('third attempt is the last and does not retry', () {
    final decision = decideStartupRetry(
      diagnosticCode: 'juce_open_failed',
      attempt: 3,
    );

    expect(decision.retry, isFalse);
  });

  test('terminal codes never retry', () {
    for (final code in kTerminalAudioStartupCodes) {
      final decision = decideStartupRetry(diagnosticCode: code, attempt: 1);

      expect(decision.retry, isFalse, reason: code);
    }
  });

  test('unknown codes never retry', () {
    final decision = decideStartupRetry(
      diagnosticCode: 'session_activation_failed',
      attempt: 1,
    );

    expect(decision.retry, isFalse);
  });

  test('maxAttempts can be lowered', () {
    final decision = decideStartupRetry(
      diagnosticCode: 'route_unstable',
      attempt: 1,
      maxAttempts: 1,
    );

    expect(decision.retry, isFalse);
  });
}
