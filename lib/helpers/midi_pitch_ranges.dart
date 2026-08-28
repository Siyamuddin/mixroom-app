List<Map<String, int>> compactMidiPitchRanges(Iterable<int> pitches) {
  final sorted =
      pitches
          .where((pitch) => pitch >= 0 && pitch <= 127)
          .toSet()
          .toList(growable: false)
        ..sort();
  if (sorted.isEmpty) return const <Map<String, int>>[];

  final ranges = <Map<String, int>>[];
  var low = sorted.first;
  var high = low;
  for (final pitch in sorted.skip(1)) {
    if (pitch == high + 1) {
      high = pitch;
      continue;
    }
    ranges.add(<String, int>{'low': low, 'high': high});
    low = pitch;
    high = pitch;
  }
  ranges.add(<String, int>{'low': low, 'high': high});
  return List<Map<String, int>>.unmodifiable(ranges);
}

List<Map<String, int>> normalizeMidiPitchRanges(Object? raw) {
  if (raw == null) return const <Map<String, int>>[];
  if (raw is! List) {
    throw const FormatException('MIDI pitch ranges must be a list.');
  }

  final pitches = <int>{};
  for (final value in raw) {
    if (value is! Map) {
      throw const FormatException('MIDI pitch range must be an object.');
    }
    final lowValue = value['low'];
    final highValue = value['high'];
    if (lowValue is! int ||
        highValue is! int ||
        lowValue < 0 ||
        highValue > 127 ||
        highValue < lowValue) {
      throw const FormatException('MIDI pitch range is invalid.');
    }
    for (var pitch = lowValue; pitch <= highValue; pitch++) {
      if (!pitches.add(pitch)) {
        throw const FormatException('MIDI pitch ranges overlap.');
      }
    }
  }
  return compactMidiPitchRanges(pitches);
}

bool midiPitchRangesContain(List<Map<String, int>> ranges, int pitch) {
  if (pitch < 0 || pitch > 127) return false;
  return ranges.any(
    (range) => pitch >= range['low']! && pitch <= range['high']!,
  );
}

String formatMidiPitchRanges(List<Map<String, int>> ranges) {
  return ranges
      .map((range) {
        final low = range['low']!;
        final high = range['high']!;
        return low == high ? '$low' : '$low-$high';
      })
      .join(',');
}
