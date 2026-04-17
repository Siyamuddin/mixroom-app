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

    final beat = toActionDouble(
      data['new_start_beat'] ??
          data['paste_start_beat'] ??
          data['start_beat'] ??
          data['at_beat'] ??
          target['new_start_beat'] ??
          target['paste_start_beat'] ??
          target['start_beat'] ??
          target['at_beat'] ??
          data['beat'] ??
          target['beat'] ??
          data['beat_index'] ??
          target['beat_index'],
    );

    final measure = toActionDouble(
      data['new_start_measure'] ??
          data['paste_start_measure'] ??
          data['start_measure'] ??
          data['at_measure'] ??
          target['new_start_measure'] ??
          target['paste_start_measure'] ??
          target['start_measure'] ??
          target['at_measure'] ??
          data['new_start_bar'] ??
          data['paste_start_bar'] ??
          data['start_bar'] ??
          data['at_bar'] ??
          target['new_start_bar'] ??
          target['paste_start_bar'] ??
          target['start_bar'] ??
          target['at_bar'] ??
          data['measure'] ??
          target['measure'] ??
          data['bar'] ??
          target['bar'] ??
          data['measure_index'] ??
          target['measure_index'] ??
          data['bar_index'] ??
          target['bar_index'],
    );
    if (measure != null && measure.isFinite) {
      final clampedMeasure = math.max(1.0, measure);
      final withinMeasure =
          beat != null && beat.isFinite && beat > 0.0 ? beat - 1.0 : 0.0;
      return ((clampedMeasure - 1.0) * beatsPerBar + withinMeasure) *
          msPerBeat;
    }

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
          data['step_measures'] ??
          data['spacing_measures'] ??
          data['repeat_every_measures'] ??
          target['delta_measures'] ??
          target['step_measures'] ??
          target['spacing_measures'] ??
          target['repeat_every_measures'] ??
          data['delta_bars'] ??
          data['step_bars'] ??
          data['spacing_bars'] ??
          data['repeat_every_bars'] ??
          target['delta_bars'] ??
          target['step_bars'] ??
          target['spacing_bars'] ??
          target['repeat_every_bars'],
    );
    final beatDelta = toActionDouble(
      data['delta_beats'] ??
          data['step_beats'] ??
          data['spacing_beats'] ??
          data['repeat_every_beats'] ??
          target['delta_beats'] ??
          target['step_beats'] ??
          target['spacing_beats'] ??
          target['repeat_every_beats'],
    );
    if ((measureDelta != null && measureDelta.isFinite) ||
        (beatDelta != null && beatDelta.isFinite)) {
      return ((measureDelta ?? 0.0) * beatsPerBar * msPerBeat) +
          ((beatDelta ?? 0.0) * msPerBeat);
    }

    return null;
  }

  static double? resolveMoveMusicalEndMs({
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

    final beat = toActionDouble(
      data['until_beat'] ??
          data['end_beat'] ??
          data['stop_beat'] ??
          data['through_beat'] ??
          target['until_beat'] ??
          target['end_beat'] ??
          target['stop_beat'] ??
          target['through_beat'],
    );

    final measure = toActionDouble(
      data['until_measure'] ??
          data['end_measure'] ??
          data['stop_measure'] ??
          data['through_measure'] ??
          target['until_measure'] ??
          target['end_measure'] ??
          target['stop_measure'] ??
          target['through_measure'] ??
          data['until_bar'] ??
          data['end_bar'] ??
          data['stop_bar'] ??
          data['through_bar'] ??
          target['until_bar'] ??
          target['end_bar'] ??
          target['stop_bar'] ??
          target['through_bar'],
    );
    if (measure != null && measure.isFinite) {
      final clampedMeasure = math.max(1.0, measure);
      final withinMeasure =
          beat != null && beat.isFinite ? math.max(1.0, beat) : beatsPerBar;
      return (((clampedMeasure - 1.0) * beatsPerBar) + withinMeasure) *
          msPerBeat;
    }

    if (beat != null && beat.isFinite) {
      return math.max(1.0, beat) * msPerBeat;
    }

    return null;
  }

  static double? resolveMoveMusicalSpanMs({
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

    final measureSpan = toActionDouble(
      data['length_measures'] ??
          data['span_measures'] ??
          data['duration_measures'] ??
          target['length_measures'] ??
          target['span_measures'] ??
          target['duration_measures'] ??
          data['length_bars'] ??
          data['span_bars'] ??
          data['duration_bars'] ??
          target['length_bars'] ??
          target['span_bars'] ??
          target['duration_bars'],
    );
    if (measureSpan != null && measureSpan.isFinite && measureSpan > 0.0) {
      return measureSpan * beatsPerBar * msPerBeat;
    }

    final beatSpan = toActionDouble(
      data['length_beats'] ??
          data['span_beats'] ??
          data['duration_beats'] ??
          target['length_beats'] ??
          target['span_beats'] ??
          target['duration_beats'],
    );
    if (beatSpan != null && beatSpan.isFinite && beatSpan > 0.0) {
      return beatSpan * msPerBeat;
    }

    return null;
  }

  static double? normalizeMidiVelocity(dynamic raw) {
    final parsed = toActionDouble(raw);
    if (parsed == null || !parsed.isFinite) return null;
    if (parsed > 1.0) {
      return (parsed / 127.0).clamp(0.0, 1.0);
    }
    return parsed.clamp(0.0, 1.0);
  }

  static double? resolveMidiNoteStartBeat(
    Map<String, dynamic> note, {
    int beatsPerBar = 4,
  }) {
    final absoluteBeat = toActionDouble(
      note['start_beat'] ??
          note['startBeat'] ??
          note['time_beats'] ??
          note['timeBeats'] ??
          note['time_beat'] ??
          note['timeBeat'] ??
          note['absolute_beat'] ??
          note['absoluteBeat'] ??
          note['timeline_beat'] ??
          note['timelineBeat'] ??
          note['at_beat'] ??
          note['atBeat'] ??
          note['offset_beats'] ??
          note['offsetBeats'] ??
          note['start'],
    );
    if (absoluteBeat != null && absoluteBeat.isFinite) {
      return absoluteBeat;
    }

    final measure = toActionDouble(
      note['start_measure'] ??
          note['startMeasure'] ??
          note['start_bar'] ??
          note['startBar'] ??
          note['measure'] ??
          note['bar'],
    );
    final beatInMeasure = toActionDouble(
      note['beat_in_measure'] ??
          note['beatInMeasure'] ??
          note['beat'] ??
          note['beat_index'] ??
          note['beatIndex'],
    );
    if (measure != null && measure.isFinite) {
      final clampedMeasure = math.max(1.0, measure);
      final withinMeasure =
          beatInMeasure != null && beatInMeasure.isFinite && beatInMeasure > 0
              ? beatInMeasure - 1.0
              : 0.0;
      return ((clampedMeasure - 1.0) * beatsPerBar) + withinMeasure;
    }

    if (beatInMeasure != null && beatInMeasure.isFinite) {
      return beatInMeasure;
    }

    return null;
  }

  static double? resolveMidiNoteLengthBeats(Map<String, dynamic> note) {
    final lengthBeats = toActionDouble(
      note['length_beats'] ??
          note['lengthBeats'] ??
          note['lengthBeat'] ??
          note['length'] ??
          note['duration_beats'] ??
          note['durationBeats'] ??
          note['duration'],
    );
    if (lengthBeats != null && lengthBeats.isFinite) {
      return lengthBeats;
    }

    final measureLength = toActionDouble(
      note['duration_measures'] ??
          note['durationMeasures'] ??
          note['length_measures'] ??
          note['lengthMeasures'] ??
          note['duration_bars'] ??
          note['durationBars'],
    );
    if (measureLength != null && measureLength.isFinite) {
      return measureLength * 4.0;
    }

    return null;
  }

  static double? resolveMidiTargetLengthBeatsFromAction(
    Map<String, dynamic> data, {
    Map<String, dynamic> target = const <String, dynamic>{},
    int defaultBeatsPerBar = 4,
  }) {
    final beatsPerBar =
        resolveBeatsPerBar(data, target, fallback: defaultBeatsPerBar)
            .toDouble();
    final lengthMeasures = toActionDouble(
      data['length_measures'] ??
          target['length_measures'] ??
          data['length_bars'] ??
          target['length_bars'],
    );
    if (lengthMeasures != null &&
        lengthMeasures.isFinite &&
        lengthMeasures > 0.0) {
      return lengthMeasures * beatsPerBar;
    }
    final lengthBeats = toActionDouble(
      data['length_beats'] ?? target['length_beats'],
    );
    if (lengthBeats != null && lengthBeats.isFinite && lengthBeats > 0.0) {
      return lengthBeats;
    }
    return null;
  }

  static bool hasStyleDrivenMidiGenerationDirectives(
    Map<String, dynamic> data, {
    Map<String, dynamic> target = const <String, dynamic>{},
  }) {
    bool hasValue(dynamic raw) => raw?.toString().trim().isNotEmpty == true;
    return hasValue(data['style']) ||
        hasValue(target['style']) ||
        hasValue(data['register']) ||
        hasValue(target['register']) ||
        hasValue(data['density']) ||
        hasValue(target['density']) ||
        hasValue(data['direction']) ||
        hasValue(target['direction']) ||
        hasValue(data['contour']) ||
        hasValue(target['contour']) ||
        hasValue(data['rhythm']) ||
        hasValue(target['rhythm']) ||
        hasValue(data['phrase']) ||
        hasValue(target['phrase']);
  }

  static List<MidiNote> generateStyledMidiNotesFromSource({
    required List<MidiNote> sourceNotes,
    required Map<String, dynamic> data,
    Map<String, dynamic> target = const <String, dynamic>{},
    String noteIdPrefix = 'ai_gen',
  }) {
    if (sourceNotes.isEmpty) return const <MidiNote>[];

    final sortedSource =
        sourceNotes.map((n) => n.copy()).toList(growable: false)
          ..sort((a, b) {
            final byStart = a.startBeat.compareTo(b.startBeat);
            if (byStart != 0) return byStart;
            return a.pitch.compareTo(b.pitch);
          });
    final sourceEndBeat = sortedSource
        .map((n) => n.startBeat + n.lengthBeats)
        .fold<double>(0.0, math.max);
    if (!sourceEndBeat.isFinite || sourceEndBeat <= 0.0) {
      return const <MidiNote>[];
    }

    final targetEndBeat =
        resolveMidiTargetLengthBeatsFromAction(data, target: target) ??
            sourceEndBeat;
    if (!targetEndBeat.isFinite || targetEndBeat <= 0.0) {
      return const <MidiNote>[];
    }

    final styleLower = <String>[
      data['style']?.toString() ?? '',
      target['style']?.toString() ?? '',
      data['phrase']?.toString() ?? '',
      target['phrase']?.toString() ?? '',
      data['rhythm']?.toString() ?? '',
      target['rhythm']?.toString() ?? '',
    ].join(' ').trim().toLowerCase();
    final densityLower =
        ((data['density'] ?? target['density'])?.toString() ?? '')
            .trim()
            .toLowerCase();
    final directionLower =
        ((data['direction'] ?? target['direction'])?.toString() ?? '')
            .trim()
            .toLowerCase();
    final registerLower =
        ((data['register'] ?? target['register'])?.toString() ?? '')
            .trim()
            .toLowerCase();

    double defaultStepBeats() {
      final explicitStep = toActionDouble(
        data['step_beats'] ?? target['step_beats'],
      );
      if (explicitStep != null && explicitStep.isFinite && explicitStep > 0.0) {
        return explicitStep;
      }
      final isRunning = styleLower.contains('running') ||
          styleLower.contains('arp') ||
          styleLower.contains('arpeggio') ||
          styleLower.contains('topline') ||
          styleLower.contains('lead');
      switch (densityLower) {
        case 'low':
        case 'sparse':
          return isRunning ? 1.0 : 2.0;
        case 'high':
        case 'dense':
        case 'busy':
          return isRunning ? 0.25 : 0.5;
        case 'medium':
        case 'mid':
        default:
          return isRunning ? 0.5 : 1.0;
      }
    }

    final stepBeats = defaultStepBeats().clamp(0.125, 4.0);
    final noteLengthBeats = math.max(
      0.125,
      math.min(stepBeats * 0.82, stepBeats),
    );
    final sourceMaxPitch =
        sortedSource.map((n) => n.pitch).fold<int>(0, math.max);
    final sourceMinPitch =
        sortedSource.map((n) => n.pitch).fold<int>(127, math.min);
    final sourceMidPitch = ((sourceMinPitch + sourceMaxPitch) / 2).round();

    int registerFloor() {
      switch (registerLower) {
        case 'upper':
        case 'high':
        case 'top':
          return math.max(60, sourceMaxPitch + 5);
        case 'lower':
        case 'low':
          return math.max(36, sourceMinPitch - 12);
        case 'middle':
        case 'mid':
        default:
          return math.max(48, sourceMidPitch - 3);
      }
    }

    int registerCeiling(int floor) {
      switch (registerLower) {
        case 'upper':
        case 'high':
        case 'top':
          return math.min(96, floor + 14);
        case 'lower':
        case 'low':
          return math.min(72, floor + 12);
        case 'middle':
        case 'mid':
        default:
          return math.min(84, floor + 12);
      }
    }

    Set<int> pitchClassesAtBeat(double beat) {
      final active = sortedSource.where((note) {
        final endBeat = note.startBeat + note.lengthBeats;
        return note.startBeat <= beat + 1e-6 && endBeat > beat + 1e-6;
      });
      final out = active.map((n) => n.pitch % 12).toSet();
      if (out.isNotEmpty) return out;

      final barStart = (beat / 4.0).floor() * 4.0;
      for (final note in sortedSource) {
        if (note.startBeat >= barStart && note.startBeat < barStart + 4.0) {
          out.add(note.pitch % 12);
        }
      }
      if (out.isNotEmpty) return out;
      return sortedSource.map((n) => n.pitch % 12).toSet();
    }

    List<int> candidatesForPitchClasses(Set<int> pitchClasses) {
      final floor = registerFloor();
      final ceiling = registerCeiling(floor);
      final out = <int>[];
      for (int pitch = floor; pitch <= ceiling; pitch++) {
        if (pitchClasses.contains(pitch % 12)) {
          out.add(pitch);
        }
      }
      if (out.isEmpty) {
        for (int pitch = floor; pitch <= ceiling; pitch++) {
          out.add(pitch);
        }
      }
      return out;
    }

    int choosePitch(List<int> candidates, int? previousPitch, double beat) {
      if (candidates.isEmpty) return sourceMaxPitch.clamp(48, 96);
      if (previousPitch == null) {
        final center = (registerFloor() + registerCeiling(registerFloor())) / 2;
        candidates.sort(
          (a, b) => (a - center).abs().compareTo((b - center).abs()),
        );
        return candidates.first;
      }
      num scoreFor(int candidate) {
        final delta = (candidate - previousPitch).abs();
        var score = delta.toDouble();
        if (styleLower.contains('mostly_stepwise') ||
            directionLower.contains('step')) {
          if (delta > 5) score += 5.0;
          if (delta >= 1 && delta <= 3) score -= 1.2;
        }
        if (candidate == previousPitch && candidates.length > 1) {
          score += 1.5;
        }
        if (directionLower.contains('up') || directionLower.contains('asc')) {
          if (candidate > previousPitch) score -= 0.6;
          if (candidate < previousPitch) score += 0.8;
        }
        if (directionLower.contains('down') ||
            directionLower.contains('desc')) {
          if (candidate < previousPitch) score -= 0.6;
          if (candidate > previousPitch) score += 0.8;
        }
        final beatInBar = beat % 4.0;
        if (beatInBar < 1e-6 && delta > 7) score += 1.0;
        return score;
      }

      candidates.sort((a, b) => scoreFor(a).compareTo(scoreFor(b)));
      return candidates.first;
    }

    final generated = <MidiNote>[];
    int? previousPitch;
    var index = 0;
    for (double beat = 0.0; beat < targetEndBeat - 1e-6; beat += stepBeats) {
      final remaining = targetEndBeat - beat;
      if (remaining <= 1e-6) break;
      final pitchClasses = pitchClassesAtBeat(beat);
      final candidates = candidatesForPitchClasses(pitchClasses);
      final pitch = choosePitch(candidates, previousPitch, beat);
      final velocity = ((beat % 4.0) < 1e-6 ? 0.84 : 0.74).clamp(0.0, 1.0);
      generated.add(
        MidiNote(
          id: '${noteIdPrefix}_$index',
          pitch: pitch.clamp(0, 127),
          startBeat: beat,
          lengthBeats: math.min(noteLengthBeats, remaining),
          velocity: velocity,
        ),
      );
      previousPitch = pitch;
      index++;
    }
    return generated;
  }

  static int resolvePlacementRepeatCount({
    required Map<String, dynamic> data,
    required Map<String, dynamic> target,
    required double bpm,
    required double startMs,
    required double stepMs,
    int defaultCount = 1,
    int maxCount = 128,
    bool preferSpanCoverageOverExplicitCount = false,
  }) {
    final explicitCount = toActionInt(
      data['repeat_count'] ??
          target['repeat_count'] ??
          data['copies'] ??
          target['copies'] ??
          data['count'] ??
          target['count'],
    );
    if (!stepMs.isFinite || stepMs <= 0.0) {
      if (explicitCount != null && explicitCount > 0) {
        return explicitCount.clamp(1, maxCount);
      }
      return defaultCount.clamp(1, maxCount);
    }

    final spanMs = resolveMoveMusicalSpanMs(
      data: data,
      target: target,
      bpm: bpm,
    );
    int? derivedCount;
    if (spanMs != null && spanMs > 0.0) {
      derivedCount = ((math.max(0.0, spanMs - 0.001)) / stepMs).floor() + 1;
    }
    if (derivedCount == null) {
      final endMs = resolveMoveMusicalEndMs(
        data: data,
        target: target,
        bpm: bpm,
      );
      if (endMs != null && endMs > startMs) {
        derivedCount =
            ((math.max(0.0, (endMs - startMs) - 0.001)) / stepMs).floor() + 1;
      }
    }

    if (derivedCount != null && derivedCount > 0) {
      final clampedDerived = derivedCount.clamp(1, maxCount);
      if (preferSpanCoverageOverExplicitCount) {
        if (explicitCount != null && explicitCount > 0) {
          return math.max(explicitCount, clampedDerived).clamp(1, maxCount);
        }
        return clampedDerived;
      }
      if (explicitCount != null && explicitCount > 0) {
        return explicitCount.clamp(1, maxCount);
      }
      return clampedDerived;
    }

    if (explicitCount != null && explicitCount > 0) {
      return explicitCount.clamp(1, maxCount);
    }

    return defaultCount.clamp(1, maxCount);
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

  static List<String> compactTutorialPlaybackTargets(List<String> sequence) {
    final cleaned = sequence
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (cleaned.length <= 2) return cleaned;

    final compact = <String>[];
    void add(String? key) {
      if (key == null || key.isEmpty || compact.contains(key)) return;
      compact.add(key);
    }

    add(cleaned.first);

    String? bridge;
    for (final candidate in cleaned.skip(1).take(cleaned.length - 2)) {
      if (candidate.endsWith(':effects_tab') ||
          candidate.endsWith(':fx_list') ||
          candidate.endsWith(':add_effect') ||
          candidate == 'tutorial:toolbar' ||
          candidate == 'tutorial:plugins' ||
          candidate == 'tutorial:chatbar' ||
          candidate == 'tutorial:timeline') {
        bridge = candidate;
        break;
      }
    }
    bridge ??= cleaned[cleaned.length - 2];
    add(bridge);
    add(cleaned.last);
    return compact;
  }

  static int tutorialPreviewDurationMs(int baseDurationMs) {
    final normalized = _clampInt(baseDurationMs, 1200, 18000);
    return _clampInt(math.max((normalized * 0.32).round(), 900), 900, 1400);
  }

  static int tutorialPreviewPauseMs(int previewDurationMs) {
    return _clampInt(
      math.min((previewDurationMs * 0.55).round(), previewDurationMs),
      480,
      1400,
    );
  }

  static int tutorialFinalDurationMs(int baseDurationMs) {
    final normalized = _clampInt(baseDurationMs, 1200, 18000);
    return _clampInt(math.max(normalized, 2800), 2600, 5200);
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static List<String> sampleRoleHintsFromText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return const <String>[];

    final normalized = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (normalized.isEmpty) return const <String>[];
    final tokens =
        normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

    bool hasToken(String token) => tokens.contains(token);
    bool hasPhrase(String phrase) => normalized.contains(phrase);
    bool hasAnyToken(Iterable<String> values) =>
        values.any((value) => hasToken(value));
    bool hasAnyPhrase(Iterable<String> values) =>
        values.any((value) => hasPhrase(value));

    final out = <String>[];
    void add(String role) {
      if (!out.contains(role)) out.add(role);
    }

    if (hasAnyToken(const <String>{'kick', 'bd'}) ||
        hasAnyPhrase(const <String>{'bass drum'})) {
      add('kick');
    }
    if (hasAnyToken(const <String>{'snare', 'snr'})) add('snare');
    if (hasToken('clap')) add('clap');
    if (hasAnyToken(const <String>{'rim', 'rimshot', 'snap'})) add('snare');
    if (hasAnyToken(const <String>{
          'hat',
          'hihat',
          'shaker',
          'tamb',
          'tambourine',
        }) ||
        hasAnyPhrase(const <String>{
          'hi hat',
          'closed hat',
          'open hat',
        })) {
      add('hat');
    }
    if (hasAnyToken(const <String>{'cymbal', 'crash', 'ride'})) add('cymbal');
    if (hasAnyToken(const <String>{
      'perc',
      'percussion',
      'bongo',
      'conga',
      'cowbell',
      'woodblock',
    })) {
      add('perc');
    }
    if (hasToken('tom')) add('tom');
    if (hasToken('loop')) add('loop');
    if (hasAnyToken(const <String>{
      'fx',
      'impact',
      'riser',
      'sweep',
      'uplifter',
      'downlifter',
      'transition',
    })) {
      add('fx');
    }
    if (hasAnyToken(const <String>{'vox', 'vocal', 'chant'})) add('vocal');
    if (!out.contains('kick') &&
        hasAnyToken(const <String>{'bass', 'sub', 'reese', '808'})) {
      add('bass');
    }
    if (hasAnyToken(const <String>{
      'piano',
      'keys',
      'key',
      'synth',
      'pluck',
      'organ',
      'melody',
      'chord',
      'pad',
      'lead',
    })) {
      add('melodic');
    }
    return out;
  }

  static int sampleRolePriorityScore(String raw, String role) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return 0;

    final normalized = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (normalized.isEmpty) return 0;
    final tokens =
        normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final inferredRoles = sampleRoleHintsFromText(raw).toSet();
    final targetRole = role.trim().toLowerCase();

    bool hasToken(String token) => tokens.contains(token);
    bool hasPhrase(String phrase) => normalized.contains(phrase);
    bool hasAnyToken(Iterable<String> values) =>
        values.any((value) => hasToken(value));

    var score = inferredRoles.contains(targetRole) ? 60 : 0;
    final isLoop = hasToken('loop');
    final isFx = hasAnyToken(const <String>{
      'fx',
      'impact',
      'riser',
      'sweep',
      'uplifter',
      'downlifter',
      'transition',
    });
    final isCrashLike = hasAnyToken(const <String>{'crash', 'ride', 'cymbal'});
    final is808Like = hasToken('808');
    final isProcessedDrums =
        hasPhrase('processed drums') || hasToken('processed');
    final isDrumset = hasToken('drumset');

    if (!isLoop) score += 12;
    if (isFx) score -= 60;

    switch (targetRole) {
      case 'kick':
        if (hasAnyToken(const <String>{'kick', 'bd'}) ||
            hasPhrase('bass drum')) {
          score += 120;
        }
        if (is808Like) score -= 60;
        if (isLoop) score -= 45;
        if (hasAnyToken(const <String>{'snare', 'clap', 'hat', 'hihat'})) {
          score -= 80;
        }
        if (isCrashLike) score -= 120;
        break;
      case 'snare':
        if (hasAnyToken(const <String>{'snare', 'snr'})) score += 120;
        if (hasAnyToken(const <String>{'rim', 'rimshot', 'snap'})) score += 85;
        if (isLoop) score -= 45;
        if (hasAnyToken(const <String>{'kick', '808', 'hat', 'hihat'})) {
          score -= 80;
        }
        if (isCrashLike) score -= 100;
        break;
      case 'clap':
        if (hasToken('clap')) score += 120;
        if (hasAnyToken(const <String>{'snare', 'snr'})) score += 20;
        if (isLoop) score -= 45;
        if (hasAnyToken(const <String>{'kick', '808', 'hat', 'hihat'})) {
          score -= 70;
        }
        if (isCrashLike) score -= 100;
        break;
      case 'hat':
        if (hasAnyToken(const <String>{
          'hat',
          'hihat',
          'shaker',
          'tamb',
          'tambourine',
        })) {
          score += 110;
        }
        if (isProcessedDrums) score += 28;
        if (isDrumset) score -= 12;
        if (hasAnyToken(const <String>{'closed', 'clsd'})) score += 8;
        if (hasAnyToken(const <String>{'open', 'opn'})) score -= 6;
        if (isLoop) score -= 35;
        if (hasAnyToken(const <String>{'kick', '808', 'snare', 'clap'})) {
          score -= 75;
        }
        if (isCrashLike) score -= 35;
        break;
      case 'perc':
        if (hasAnyToken(const <String>{
          'perc',
          'percussion',
          'bongo',
          'conga',
          'cowbell',
          'woodblock',
          'shaker',
          'tamb',
          'tambourine',
        })) {
          score += 105;
        }
        if (isLoop) score -= 20;
        if (hasAnyToken(const <String>{'kick', '808'})) score -= 60;
        if (hasAnyToken(const <String>{'snare', 'clap'})) score -= 35;
        break;
      case 'cymbal':
        if (isCrashLike) score += 110;
        if (isLoop) score -= 30;
        if (hasAnyToken(const <String>{'kick', '808', 'snare', 'clap'})) {
          score -= 80;
        }
        break;
      case 'loop':
        if (isLoop) score += 120;
        break;
      case 'bass':
        if (hasAnyToken(const <String>{'bass', 'sub', 'reese'})) score += 110;
        if (isLoop) score -= 80;
        if (is808Like) score += 130;
        if (hasAnyToken(const <String>{'kick', 'snare', 'hat'})) score -= 80;
        break;
    }

    return score;
  }

  static List<int> tempoHintsFromText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return const <int>[];
    final out = <int>{};
    for (final match in RegExp(r'(\d{2,3})(?:\s*bpm)?').allMatches(text)) {
      final token = match.group(1);
      if (token == null) continue;
      final value = int.tryParse(token);
      if (value == null) continue;
      if (value >= 60 && value <= 249) {
        out.add(value);
      }
    }
    final sorted = out.toList()..sort();
    return sorted;
  }

  static String? primarySampleRoleFromText(String raw) {
    final roles = sampleRoleHintsFromText(raw);
    if (roles.isEmpty) return null;
    const preferredRoleOrder = <String>[
      'kick',
      'snare',
      'clap',
      'hat',
      'perc',
      'cymbal',
      'tom',
      'loop',
      'fx',
      'bass',
      'vocal',
      'melodic',
    ];
    for (final role in preferredRoleOrder) {
      if (roles.contains(role)) return role;
    }
    return roles.first;
  }

  static double? defaultSampleInsertStartBeat(String raw) {
    switch (primarySampleRoleFromText(raw)) {
      case 'snare':
      case 'clap':
        return 1.0;
      default:
        return 0.0;
    }
  }

  static double? defaultSampleInsertStepBeats(
    String raw, {
    int repeatCount = 1,
  }) {
    final role = primarySampleRoleFromText(raw);
    if (repeatCount <= 1 && role != 'loop' && role != 'cymbal') {
      return null;
    }
    switch (role) {
      case 'kick':
        return 1.0;
      case 'snare':
      case 'clap':
        return 2.0;
      case 'hat':
        return 0.5;
      case 'perc':
        return 1.0;
      case 'tom':
        return 2.0;
      case 'cymbal':
        return 8.0;
      case 'loop':
        return 4.0;
      case 'bass':
        return 2.0;
      default:
        return repeatCount > 1 ? 4.0 : null;
    }
  }

  static double? defaultSampleInsertStartMs(
    String raw, {
    required double bpm,
  }) {
    final startBeat = defaultSampleInsertStartBeat(raw);
    if (startBeat == null || !startBeat.isFinite) return null;
    return startBeat * (60000.0 / bpm.clamp(1.0, 400.0));
  }

  static double? defaultSampleInsertStepMs(
    String raw, {
    required double bpm,
    int repeatCount = 1,
  }) {
    final stepBeats = defaultSampleInsertStepBeats(
      raw,
      repeatCount: repeatCount,
    );
    if (stepBeats == null || !stepBeats.isFinite || stepBeats <= 0.0) {
      return null;
    }
    return stepBeats * (60000.0 / bpm.clamp(1.0, 400.0));
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
      case 'create':
      case 'create_clip':
      case 'new_clip':
      case 'new_midi_clip':
        return 'create_clip';
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
      case 'transpose':
      case 'transpose_note':
      case 'transpose_notes':
      case 'shift_pitch':
      case 'pitch_shift':
      case 'octave_up':
      case 'octave_down':
        return 'transpose_notes';
      case 'audio_to_midi':
      case 'convert_to_midi':
      case 'transcribe_audio':
      case 'extract_midi':
        return 'convert_audio_to_midi';
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
          .map((e) {
            if (e is Map) {
              final chord = e['chord'] ?? e['symbol'] ?? e['name'] ?? e['token'];
              if (chord != null) return chord.toString().trim();
            }
            return e.toString().trim();
          })
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
    String mode = 'chords',
    String noteIdPrefix = 'ai_prog',
    int? nowMicros,
  }) {
    final tokens = progressionTokensFromRaw(progressionRaw);
    if (tokens.isEmpty) return const <MidiNote>[];

    final safeNotesPerChord = notesPerChord.clamp(1, 8).toInt();
    final safeOctave = octave.clamp(-1, 8).toInt();
    final safeVelocity = velocity.clamp(0.2, 1.0).toDouble();
    final normalizedMode = mode.trim().toLowerCase();
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
      if (normalizedMode == 'bass') {
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
        continue;
      }

      final chordPitches = _fallbackChordPitchesFromToken(
        tokens[chordIndex],
        octave: safeOctave,
        noteCount: safeNotesPerChord.clamp(2, 6),
      );
      if (chordPitches.isEmpty) continue;
      final chordLengthBeats = math.max(0.5, beatsPerChord * 0.95);
      for (int toneIndex = 0; toneIndex < chordPitches.length; toneIndex++) {
        final toneVelocity = (toneIndex == 0
                ? (safeVelocity + 0.04).clamp(0.0, 1.0)
                : safeVelocity)
            .toDouble();
        out.add(
          MidiNote(
            id: '${noteIdPrefix}_${idSeed}_${i++}',
            pitch: chordPitches[toneIndex],
            startBeat: baseBeat,
            lengthBeats: chordLengthBeats,
            velocity: toneVelocity,
          ),
        );
      }
    }

    return out;
  }

  static List<int> _fallbackChordPitchesFromToken(
    String token, {
    required int octave,
    required int noteCount,
  }) {
    final rootMidi = rootMidiFromChordToken(token, octave: octave);
    if (rootMidi == null) return const <int>[];

    final normalized = token.trim().toLowerCase();
    final hasMaj = normalized.contains('maj');
    final isMinor = !hasMaj &&
        (normalized.contains('min') ||
            RegExp(r'^[a-g](?:#|b)?m').hasMatch(normalized));
    final isDim = normalized.contains('dim');
    final isAug = normalized.contains('aug') || normalized.contains('+');
    final isSus2 = normalized.contains('sus2');
    final isSus4 = !isSus2 && normalized.contains('sus');
    final wantsSeventh = RegExp(r'(maj7|7|9|11|13)').hasMatch(normalized);

    List<int> intervals;
    if (isDim) {
      intervals = <int>[0, 3, 6];
    } else if (isAug) {
      intervals = <int>[0, 4, 8];
    } else if (isSus2) {
      intervals = <int>[0, 2, 7];
    } else if (isSus4) {
      intervals = <int>[0, 5, 7];
    } else if (isMinor) {
      intervals = <int>[0, 3, 7];
    } else {
      intervals = <int>[0, 4, 7];
    }

    if (wantsSeventh) {
      final seventh = hasMaj ? 11 : (isDim ? 9 : 10);
      if (!intervals.contains(seventh)) {
        intervals.add(seventh);
      }
    }

    final out = <int>[];
    int octaveLift = 0;
    while (out.length < noteCount) {
      final interval = intervals[out.length % intervals.length] + octaveLift;
      out.add((rootMidi + interval).clamp(0, 127));
      if ((out.length % intervals.length) == intervals.length - 1) {
        octaveLift += 12;
      }
    }
    return out;
  }
}
