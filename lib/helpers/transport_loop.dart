/// Wrap a playhead into an active loop region without overshooting the end.
///
/// Tiny loop ranges are shorter than UI tick and poll intervals, so the
/// visual clock must wrap in the same way the audio engine does.
Duration wrapTransportClockToLoop({
  required Duration clock,
  required bool loopEnabled,
  required int loopStartMs,
  required int loopEndMs,
}) {
  if (!isTransportLoopRegionValid(
    loopEnabled: loopEnabled,
    loopStartMs: loopStartMs,
    loopEndMs: loopEndMs,
  )) {
    return clock;
  }
  final int startUs = loopStartMs * 1000;
  final int endUs = loopEndMs * 1000;
  final int clockUs = clock.inMicroseconds;
  if (clockUs < endUs) return clock;
  final int lengthUs = endUs - startUs;
  if (lengthUs <= 0) return Duration(microseconds: startUs);
  return Duration(microseconds: startUs + ((clockUs - startUs) % lengthUs));
}

/// True when looping is on and the region has a positive length.
bool isTransportLoopRegionValid({
  required bool loopEnabled,
  required int loopStartMs,
  required int loopEndMs,
}) => loopEnabled && loopEndMs > loopStartMs;
