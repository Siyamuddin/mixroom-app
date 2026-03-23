import 'dart:math' as math;

import 'package:mixroom/models/models.dart';

class AssistantActionUtils {
  const AssistantActionUtils._();

  static const Map<String, String> tutorialAliases = <String, String>{
    'chatbar': 'tutorial:chatbar',
    'chat': 'tutorial:chatbar',
    'toolbar': 'tutorial:toolbar',
    'tool_bar': 'tutorial:toolbar',
    'tools': 'tutorial:toolbar',
    'transport': 'tutorial:toolbar',
    'transport_controls': 'tutorial:toolbar',
    'play': 'tutorial:transport:play',
    'play_button': 'tutorial:transport:play',
    'record': 'tutorial:transport:record',
    'record_button': 'tutorial:transport:record',
    'restart': 'tutorial:transport:restart',
    'rewind': 'tutorial:transport:restart',
    'mute': 'tutorial:mute',
    'mute_button': 'tutorial:mute',
    'track_mute': 'tutorial:mute',
    'mute_track': 'tutorial:mute',
    'track_header_mute': 'tutorial:mute',
    'track_mute_button': 'tutorial:mute',
    'mute_track_button': 'tutorial:mute',
    'solo': 'tutorial:solo',
    'solo_button': 'tutorial:solo',
    'track_solo': 'tutorial:solo',
    'solo_track': 'tutorial:solo',
    'track_header_solo': 'tutorial:solo',
    'track_solo_button': 'tutorial:solo',
    'solo_track_button': 'tutorial:solo',
    'export': 'tutorial:export',
    'export_button': 'tutorial:export',
    'settings': 'tutorial:project_settings',
    'project_settings': 'tutorial:project_settings',
    'plugins': 'tutorial:plugins',
    'effects': 'tutorial:plugins',
    'timeline': 'tutorial:timeline',
    'track_area': 'tutorial:timeline',
    'tracks': 'tutorial:timeline',
    'arrangement': 'tutorial:timeline',
    'arrangement_view': 'tutorial:timeline',
    'timeline_area': 'tutorial:timeline',
    'loop': 'tutorial:timeline',
    'clip': 'tutorial:timeline',
    'clips': 'tutorial:timeline',
    'clip_edge': 'tutorial:timeline',
    'trim_handle': 'tutorial:timeline',
    'stretch_handle': 'tutorial:timeline',
    'timeline_clip': 'tutorial:timeline',
    'timeline_clip_edge': 'tutorial:timeline',
    'midi_editor_button': 'tutorial:timeline',
    'open_midi_editor': 'tutorial:timeline',
    'piano_roll': 'tutorial:piano_roll',
    'midi_editor': 'tutorial:piano_roll',
    'note_properties': 'tutorial:piano_roll',
    'note_length': 'tutorial:piano_roll',
    'note_velocity': 'tutorial:piano_roll',
  };

  static Map<String, dynamic> toActionMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  static double? toActionDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  static int? toActionInt(dynamic raw) {
    final v = toActionDouble(raw);
    if (v == null || !v.isFinite) return null;
    return v.round();
  }

  static bool toActionBool(dynamic raw, {bool fallback = false}) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final t = raw.trim().toLowerCase();
      if (t == 'true' || t == 'yes' || t == '1') return true;
      if (t == 'false' || t == 'no' || t == '0') return false;
    }
    return fallback;
  }

  static int resolveBeatsPerBar(
    Map<String, dynamic> data,
    Map<String, dynamic> target, {
    int fallback = 4,
  }) {
    final raw = toActionInt(
          data['beats_per_bar'] ??
              target['beats_per_bar'] ??
              data['meter_numerator'] ??
              target['meter_numerator'],
        ) ??
        fallback;
    return raw.clamp(1, 32);
  }

  static double? resolveMoveMusicalStartMs({
    required Map<String, dynamic> data,
    required Map<String, dynamic> target,
    required double bpm,
    int defaultBeatsPerBar = 4,
  }) {
    final beatsPerBar = resolveBeatsPerBar(
      data,
      target,
      fallback: defaultBeatsPerBar,
    );
    final msPerBeat = 60000.0 / bpm.clamp(1.0, 400.0);

    final measure = toActionDouble(
      data['new_start_measure'] ??
          target['new_start_measure'] ??
          data['new_start_bar'] ??
          target['new_start_bar'] ??
          data['measure_index'] ??
          target['measure_index'] ??
          data['bar_index'] ??
          target['bar_index'],
    );
    if (measure != null && measure.isFinite) {
      final clampedMeasure = math.max(1.0, measure);
      return (clampedMeasure - 1.0) * beatsPerBar * msPerBeat;
    }

    final beat = toActionDouble(
      data['new_start_beat'] ??
          target['new_start_beat'] ??
          data['beat_index'] ??
          target['beat_index'],
    );
    if (beat != null && beat.isFinite) {
      final clampedBeat = math.max(1.0, beat);
      return (clampedBeat - 1.0) * msPerBeat;
    }

    return null;
  }

  static double? resolveMoveMusicalDeltaMs({
    required Map<String, dynamic> data,
    required Map<String, dynamic> target,
    required double bpm,
    int defaultBeatsPerBar = 4,
  }) {
    final beatsPerBar = resolveBeatsPerBar(
      data,
      target,
      fallback: defaultBeatsPerBar,
    );
    final msPerBeat = 60000.0 / bpm.clamp(1.0, 400.0);

    final measureDelta = toActionDouble(
      data['delta_measures'] ??
          target['delta_measures'] ??
          data['delta_bars'] ??
          target['delta_bars'],
    );
    if (measureDelta != null && measureDelta.isFinite) {
      return measureDelta * beatsPerBar * msPerBeat;
    }

    final beatDelta = toActionDouble(
      data['delta_beats'] ?? target['delta_beats'],
    );
    if (beatDelta != null && beatDelta.isFinite) {
      return beatDelta * msPerBeat;
    }

    return null;
  }

  static String? normalizeTutorialTargetId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.contains(':')) return t;

    final normalizedKey = t
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalizedKey.isEmpty) return null;

    return tutorialAliases[normalizedKey] ?? 'tutorial:$normalizedKey';
  }

  static String normalizeClipEditOperation(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'dialog_cleanup':
      case 'clean_dialog':
      case 'podcast_cleanup':
      case 'remove_cough':
      case 'remove_coughs':
      case 'remove_artifacts':
      case 'remove_noises':
      case 'remove_clicks':
      case 'remove_breaths':
        return 'dialog_cleanup';
      case 'dialog_remove_range':
      case 'remove_range':
      case 'remove_section':
      case 'delete_range':
      case 'cut_range':
      case 'remove_phrase':
      case 'delete_phrase':
      case 'remove_sentence':
        return 'dialog_remove_range';
      case 'dialog_lift_quiet':
      case 'lift_quiet':
      case 'boost_quiet':
      case 'fix_quiet':
      case 'raise_quiet':
      case 'loudness_match':
        return 'dialog_lift_quiet';
      case 'dialog_tighten_pauses':
      case 'tighten_pauses':
      case 'remove_long_pauses':
      case 'shorten_pauses':
      case 'trim_pauses':
        return 'dialog_tighten_pauses';
      case 'trim_start':
      case 'trim_beginning':
      case 'trim_head':
      case 'trim_in':
      case 'trim_end':
      case 'trim_tail':
      case 'trim_out':
        return 'trim';
      case 'split':
      case 'split_clip':
      case 'slice':
      case 'slice_clip':
      case 'splice':
      case 'splice_clip':
      case 'chop_clip':
        return 'cut';
      case 'time_stretch':
      case 'stretch_clip':
      case 'resize':
      case 'resize_clip':
      case 'duration':
        return 'stretch';
      case 'reposition':
      case 'shift':
      case 'shift_clip':
      case 'nudge':
      case 'nudge_clip':
      case 'slide':
      case 'slide_clip':
      case 'move_clip':
        return 'move';
      case 'copy':
      case 'copy_clip':
      case 'clone':
      case 'clone_clip':
        return 'duplicate';
      case 'remove':
      case 'remove_clip':
        return 'delete';
      case 'align_to_tempo':
      case 'follow_tempo':
        return 'tempo_follow';
      case 'detect_tempo_set_project':
      case 'set_project_tempo_from_clip':
      case 'tempo_detect':
        return 'tempo_detect_set_project';
      case 'trim_silence':
      case 'auto_trim_silence':
        return 'auto_trim';
      case 'tempo_align':
      case 'align_tempo':
      case 'bpm_align':
        return 'auto_bpm_align';
      default:
        return raw;
    }
  }

  static String normalizeMidiComposeOperation(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'compose':
      case 'compose_notes':
      case 'write_pattern':
      case 'generate_pattern':
      case 'make_pattern':
        return 'compose_pattern';
      case 'compose_bass':
      case 'write_bassline':
      case 'generate_bassline':
      case 'make_bassline':
        return 'compose_bassline';
      case 'replace':
      case 'overwrite_notes':
      case 'set_notes':
        return 'replace_notes';
      case 'append':
      case 'add_notes':
      case 'extend_notes':
        return 'append_notes';
      case 'chop':
      case 'chop_note':
      case 'chop_notes':
      case 'note_chop':
      case 'note_chopper':
      case 'splice_notes':
      case 'slice_notes':
      case 'split_notes':
      case 'grid_chop':
      case 'ratchet':
      case 'stutter':
        return 'chop_notes';
      default:
        return raw;
    }
  }

  static List<MidiNote> chopMidiNotes({
    required List<MidiNote> notes,
    int subdivision = 16,
    double? stepBeats,
    double sustainRatio = 1.0,
    double minLengthBeats = 0.03125,
    double velocityDecayPerSlice = 0.0,
    double velocityJitter = 0.0,
    double velocityFloor = 0.05,
    double? fromBeat,
    double? toBeat,
    String noteIdPrefix = 'ai_chop',
    int? nowMicros,
  }) {
    if (notes.isEmpty) return const <MidiNote>[];

    final safeSubdivision = subdivision.clamp(1, 128).toInt();
    var safeStepBeats = stepBeats ?? (4.0 / safeSubdivision.toDouble());
    if (!safeStepBeats.isFinite || safeStepBeats <= 0.0) {
      safeStepBeats = 4.0 / 16.0;
    }
    final safeSustainRatio = sustainRatio.clamp(0.05, 1.0).toDouble();
    var safeMinLengthBeats = minLengthBeats.clamp(0.0005, 4.0).toDouble();
    if (safeMinLengthBeats > safeStepBeats) {
      safeMinLengthBeats = safeStepBeats;
    }
    final safeVelocityDecay = velocityDecayPerSlice.clamp(-1.0, 1.0).toDouble();
    final safeVelocityJitter = velocityJitter.clamp(0.0, 1.0).toDouble();
    final safeVelocityFloor = velocityFloor.clamp(0.0, 1.0).toDouble();
    final idSeed = nowMicros ?? DateTime.now().microsecondsSinceEpoch;

    const tiny = 0.000001;
    final hasRangeStart = fromBeat != null && fromBeat.isFinite;
    final hasRangeEnd = toBeat != null && toBeat.isFinite;
    final rangeStart = hasRangeStart ? fromBeat : -double.infinity;
    var rangeEnd = hasRangeEnd ? toBeat : double.infinity;
    if (rangeEnd <= rangeStart) rangeEnd = double.infinity;

    final out = <MidiNote>[];
    int noteCounter = 0;
    int jitterCounter = 0;

    double nextJitterUnit() {
      // Deterministic pseudo-random unit value in [-1, 1].
      int x = idSeed ^ (jitterCounter++ * 0x45d9f3b);
      x ^= (x << 13);
      x ^= (x >> 17);
      x ^= (x << 5);
      final normalized = (x & 0x7fffffff) / 0x7fffffff;
      return (normalized * 2.0) - 1.0;
    }

    void pushSegment(
      MidiNote source,
      double startBeat,
      double lengthBeats, {
      int? sliceIndex,
    }) {
      if (!startBeat.isFinite || !lengthBeats.isFinite) return;
      final safeLength = math.max(tiny, lengthBeats);
      double velocity = source.velocity.clamp(0.0, 1.0).toDouble();
      if (sliceIndex != null) {
        velocity -= (sliceIndex * safeVelocityDecay);
        if (safeVelocityJitter > 0.0) {
          velocity += nextJitterUnit() * safeVelocityJitter;
        }
      }
      velocity = velocity.clamp(safeVelocityFloor, 1.0).toDouble();
      out.add(
        MidiNote(
          id: '${noteIdPrefix}_${idSeed}_${noteCounter++}',
          pitch: source.pitch.clamp(0, 127).toInt(),
          startBeat: math.max(0.0, startBeat),
          lengthBeats: safeLength,
          velocity: velocity,
        ),
      );
    }

    for (final source in notes) {
      final start = math.max(0.0, source.startBeat);
      final end = math.max(start + tiny, source.startBeat + source.lengthBeats);

      final overlapsRange = end > rangeStart && start < rangeEnd;
      if (!overlapsRange) {
        pushSegment(source, start, end - start);
        continue;
      }

      final chopStart = math.max(start, rangeStart);
      final chopEnd = math.min(end, rangeEnd);

      if (chopStart - start > tiny) {
        pushSegment(source, start, chopStart - start);
      }

      var cursor = chopStart;
      int sliceIndex = 0;
      while (cursor < chopEnd - tiny) {
        final boundary = math.min(chopEnd, cursor + safeStepBeats);
        final sliceSpan = math.max(0.0, boundary - cursor);
        if (sliceSpan <= tiny) break;

        var sliceLength = sliceSpan * safeSustainRatio;
        if (sliceLength < safeMinLengthBeats) {
          sliceLength = safeMinLengthBeats;
        }
        if (sliceLength > sliceSpan) {
          sliceLength = sliceSpan;
        }
        if (sliceLength > tiny) {
          pushSegment(
            source,
            cursor,
            sliceLength,
            sliceIndex: sliceIndex,
          );
        }
        cursor = boundary;
        sliceIndex++;
      }

      if (end - chopEnd > tiny) {
        pushSegment(source, chopEnd, end - chopEnd);
      }
    }

    out.sort((a, b) {
      final byBeat = a.startBeat.compareTo(b.startBeat);
      if (byBeat != 0) return byBeat;
      final byPitch = a.pitch.compareTo(b.pitch);
      if (byPitch != 0) return byPitch;
      return a.lengthBeats.compareTo(b.lengthBeats);
    });
    return out;
  }

  static MapEntry<double, double>? estimateAutoTrimBoundsMs({
    required List<double> waveform,
    required double fullMs,
    required double trimStartMs,
    required double trimEndMs,
    double thresholdFloor = 0.012,
    double thresholdRatio = 0.08,
    double paddingMs = 8.0,
    double minTrimLengthMs = 50.0,
  }) {
    if (waveform.isEmpty) return null;
    if (!fullMs.isFinite || fullMs <= 1.0) return null;
    if (trimEndMs <= trimStartMs + 1.0) return null;

    final totalBins = waveform.length;
    int startBin = ((trimStartMs / fullMs) * totalBins).floor();
    int endBin = ((trimEndMs / fullMs) * totalBins).ceil();
    startBin = startBin.clamp(0, math.max(0, totalBins - 1));
    endBin = endBin.clamp(startBin + 1, totalBins);
    if (endBin <= startBin) return null;

    double peak = 0.0;
    for (int i = startBin; i < endBin; i++) {
      final v = waveform[i].abs();
      if (v > peak) peak = v;
    }
    if (!peak.isFinite || peak <= 0.0) return null;

    final threshold = math.max(thresholdFloor, peak * thresholdRatio);
    int first = -1;
    int last = -1;
    for (int i = startBin; i < endBin; i++) {
      if (waveform[i].abs() >= threshold) {
        first = i;
        break;
      }
    }
    for (int i = endBin - 1; i >= startBin; i--) {
      if (waveform[i].abs() >= threshold) {
        last = i;
        break;
      }
    }
    if (first < 0 || last < 0 || last <= first) return null;

    final estStartMs =
        ((first / totalBins) * fullMs - paddingMs).clamp(0.0, fullMs);
    final estEndMs = (((last + 1) / totalBins) * fullMs + paddingMs)
        .clamp(0.0, fullMs)
        .toDouble();
    final safeStart =
        estStartMs.clamp(0.0, fullMs - minTrimLengthMs).toDouble();
    final safeEnd =
        estEndMs.clamp(safeStart + minTrimLengthMs, fullMs).toDouble();
    return MapEntry<double, double>(safeStart, safeEnd);
  }

  static int? pitchClassFromToken(String token) {
    switch (token.toUpperCase()) {
      case 'C':
        return 0;
      case 'C#':
      case 'DB':
        return 1;
      case 'D':
        return 2;
      case 'D#':
      case 'EB':
        return 3;
      case 'E':
      case 'FB':
        return 4;
      case 'F':
      case 'E#':
        return 5;
      case 'F#':
      case 'GB':
        return 6;
      case 'G':
        return 7;
      case 'G#':
      case 'AB':
        return 8;
      case 'A':
        return 9;
      case 'A#':
      case 'BB':
        return 10;
      case 'B':
      case 'CB':
        return 11;
      default:
        return null;
    }
  }

  static int? midiPitchFromRaw(dynamic raw, {int fallbackOctave = 3}) {
    if (raw is num) return raw.toInt().clamp(0, 127);
    if (raw is! String) return null;

    final text = raw.trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt.clamp(0, 127);

    final match = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)?').firstMatch(text);
    if (match == null) return null;
    final note = (match.group(1) ?? '').toUpperCase();
    final accidental = (match.group(2) ?? '').toUpperCase();
    final octaveRaw = match.group(3);
    final pitchClass = pitchClassFromToken('$note$accidental');
    if (pitchClass == null) return null;

    final octave = int.tryParse(octaveRaw ?? '') ?? fallbackOctave;
    final midi = ((octave + 1) * 12) + pitchClass;
    return midi.clamp(0, 127).toInt();
  }

  static int? rootMidiFromChordToken(String token, {int octave = 2}) {
    final text = token.trim();
    if (text.isEmpty) return null;
    final match = RegExp(r'([A-Ga-g])([#b]?)').firstMatch(text);
    if (match == null) return midiPitchFromRaw(text, fallbackOctave: octave);
    final pitchClass = pitchClassFromToken(
      '${(match.group(1) ?? '').toUpperCase()}${(match.group(2) ?? '').toUpperCase()}',
    );
    if (pitchClass == null) return null;
    int midi = ((octave + 1) * 12) + pitchClass;
    if (midi > 52) midi -= 12;
    if (midi < 24) midi += 12;
    return midi.clamp(0, 127).toInt();
  }

  static List<String> progressionTokensFromRaw(dynamic rawProgression) {
    if (rawProgression is List) {
      return rawProgression
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    if (rawProgression is String) {
      return rawProgression
          .split(RegExp(r'[\s,|/>-]+'))
          .map((e) => e.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static List<MidiNote> fallbackMidiNotesFromProgression({
    required dynamic progressionRaw,
    double beatsPerChord = 4.0,
    int notesPerChord = 4,
    int octave = 2,
    double velocity = 0.78,
    String noteIdPrefix = 'ai_prog',
    int? nowMicros,
  }) {
    final tokens = progressionTokensFromRaw(progressionRaw);
    if (tokens.isEmpty) return const <MidiNote>[];

    final safeNotesPerChord = notesPerChord.clamp(1, 8).toInt();
    final safeOctave = octave.clamp(-1, 8).toInt();
    final safeVelocity = velocity.clamp(0.2, 1.0).toDouble();
    final idSeed = nowMicros ?? DateTime.now().microsecondsSinceEpoch;

    final out = <MidiNote>[];
    final stepBeats = beatsPerChord / safeNotesPerChord.toDouble();
    final noteLengthBeats = math.max(0.125, stepBeats * 0.92);

    int i = 0;
    for (int chordIndex = 0; chordIndex < tokens.length; chordIndex++) {
      final rootMidi =
          rootMidiFromChordToken(tokens[chordIndex], octave: safeOctave);
      if (rootMidi == null) continue;
      final baseBeat = chordIndex * beatsPerChord;
      for (int step = 0; step < safeNotesPerChord; step++) {
        final noteVelocity =
            (step == 0 ? (safeVelocity + 0.06).clamp(0.0, 1.0) : safeVelocity)
                .toDouble();
        out.add(
          MidiNote(
            id: '${noteIdPrefix}_${idSeed}_${i++}',
            pitch: rootMidi,
            startBeat: baseBeat + (step * stepBeats),
            lengthBeats: noteLengthBeats,
            velocity: noteVelocity,
          ),
        );
      }
    }

    return out;
  }
}
