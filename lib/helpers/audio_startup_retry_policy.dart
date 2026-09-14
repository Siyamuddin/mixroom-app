const Set<String> kTransientAudioStartupCodes = {
  'route_unstable',
  'actual_state_unavailable',
  'juce_open_failed',
};

const Set<String> kTerminalAudioStartupCodes = {
  'no_output',
  'bluetooth_duplex_forbidden',
  'implementation_conflict',
  'input_open',
};

class AudioStartupRetryDecision {
  const AudioStartupRetryDecision({
    required this.retry,
    this.delay = Duration.zero,
  });

  final bool retry;
  final Duration delay;
}

/// Decides whether a failed audio-engine open should be retried.
///
/// [attempt] is the number of opens already tried (1 after the first failure).
/// Legacy paths that never produce a diagnostic code do not retry.
AudioStartupRetryDecision decideStartupRetry({
  required String? diagnosticCode,
  required int attempt,
  int maxAttempts = 3,
}) {
  if (diagnosticCode == null || diagnosticCode.isEmpty) {
    return const AudioStartupRetryDecision(retry: false);
  }
  if (attempt >= maxAttempts) {
    return const AudioStartupRetryDecision(retry: false);
  }
  if (kTerminalAudioStartupCodes.contains(diagnosticCode)) {
    return const AudioStartupRetryDecision(retry: false);
  }
  if (!kTransientAudioStartupCodes.contains(diagnosticCode)) {
    return const AudioStartupRetryDecision(retry: false);
  }
  final delay = attempt <= 1
      ? const Duration(milliseconds: 250)
      : const Duration(milliseconds: 500);
  return AudioStartupRetryDecision(retry: true, delay: delay);
}
