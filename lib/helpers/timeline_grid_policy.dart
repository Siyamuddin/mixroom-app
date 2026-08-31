enum TimelineGridMode { adaptive, fixed }

class TimelineGridPolicy {
  static const int defaultDivisionsPerBar = 4;
  static const double minimumAdaptiveSpacingPx = 30.0;
  static const List<int> adaptiveDivisionsPerBar = <int>[4, 8, 16, 32];

  const TimelineGridPolicy._();

  static double barLengthInQuarterNotes({
    required int beatsPerBar,
    required int beatUnit,
  }) {
    final safeBeatsPerBar = beatsPerBar > 0 ? beatsPerBar : 1;
    final safeBeatUnit = beatUnit > 0 ? beatUnit : 4;
    return safeBeatsPerBar * 4.0 / safeBeatUnit;
  }

  static double arrangementPixelsPerBar({
    required double bpm,
    required int beatsPerBar,
    required int beatUnit,
    required double pixelsPerMs,
  }) {
    if (!bpm.isFinite ||
        bpm <= 0.0 ||
        !pixelsPerMs.isFinite ||
        pixelsPerMs <= 0.0) {
      return 0.0;
    }
    final barLengthQuarterNotes = barLengthInQuarterNotes(
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
    );
    return (60000.0 / bpm) * barLengthQuarterNotes * pixelsPerMs;
  }

  static double pianoRollPixelsPerBar({
    required int beatsPerBar,
    required int beatUnit,
    required double pixelsPerBeat,
  }) {
    if (!pixelsPerBeat.isFinite || pixelsPerBeat <= 0.0) return 0.0;
    return barLengthInQuarterNotes(
          beatsPerBar: beatsPerBar,
          beatUnit: beatUnit,
        ) *
        pixelsPerBeat;
  }

  static int resolveDivisionsPerBar({
    required TimelineGridMode mode,
    required int fixedDivisionsPerBar,
    required double pixelsPerBar,
  }) {
    if (mode == TimelineGridMode.fixed) {
      return fixedDivisionsPerBar > 0
          ? fixedDivisionsPerBar
          : defaultDivisionsPerBar;
    }
    if (!pixelsPerBar.isFinite || pixelsPerBar <= 0.0) {
      return defaultDivisionsPerBar;
    }

    var effective = defaultDivisionsPerBar;
    for (final divisions in adaptiveDivisionsPerBar.skip(1)) {
      if (pixelsPerBar / divisions < minimumAdaptiveSpacingPx) break;
      effective = divisions;
    }
    return effective;
  }
}
