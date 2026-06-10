import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

const double kDefaultGainUi = 2.0;

enum ClipKind { audio, midi }

extension ClipKindWire on ClipKind {
  String get wireName => this == ClipKind.midi ? 'midi' : 'audio';

  static ClipKind fromWire(String? raw) {
    if ((raw ?? '').toLowerCase() == 'midi') return ClipKind.midi;
    return ClipKind.audio;
  }
}

const String kTempoWarpModeBeats = 'beats';
const String kTempoWarpModeComplex = 'complex';
const String kTempoWarpModeRepitch = 'repitch';

const Set<String> kTrackRoleOverrideValues = <String>{
  'vocals',
  'drums',
  'bass',
  'guitar',
  'synth',
  'other',
};

String normalizeTrackRoleOverride(String? rawRole) {
  final role = (rawRole ?? '').trim().toLowerCase();
  if (role.isEmpty || role == 'auto' || role == 'automatic') return '';
  switch (role) {
    case 'vocal':
    case 'vox':
    case 'lead_vocal':
    case 'lead vocals':
      return 'vocals';
    case 'drum':
    case 'percussion':
      return 'drums';
    case 'keys':
    case 'piano':
    case 'keyboard':
      return 'synth';
    default:
      return kTrackRoleOverrideValues.contains(role) ? role : '';
  }
}

String normalizeTempoWarpMode(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case kTempoWarpModeBeats:
      return kTempoWarpModeBeats;
    case kTempoWarpModeRepitch:
      return kTempoWarpModeRepitch;
    case kTempoWarpModeComplex:
    default:
      return kTempoWarpModeComplex;
  }
}

class MidiNote {
  String id;
  int pitch; // MIDI note number (0..127)
  double startBeat;
  double lengthBeats;
  double velocity; // 0..1

  MidiNote({
    required this.id,
    required this.pitch,
    required this.startBeat,
    required this.lengthBeats,
    required this.velocity,
  });

  MidiNote copy() => MidiNote(
        id: id,
        pitch: pitch,
        startBeat: startBeat,
        lengthBeats: lengthBeats,
        velocity: velocity,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pitch': pitch,
        'startBeat': startBeat,
        'lengthBeats': lengthBeats,
        'velocity': velocity,
      };

  static MidiNote fromJson(Map<String, dynamic> json) {
    return MidiNote(
      id: (json['id'] as String?) ?? '',
      pitch: (json['pitch'] as num?)?.toInt() ?? 60,
      startBeat: (json['startBeat'] as num?)?.toDouble() ?? 0.0,
      lengthBeats: (json['lengthBeats'] as num?)?.toDouble() ?? 1.0,
      velocity: ((json['velocity'] as num?)?.toDouble() ?? 0.8).clamp(0.0, 1.0),
    );
  }
}

// TODO: rename to AudioClip, because 'Tracks' should be equivalent to 'Rows' in the project, rather than a single audio clip
class AudioTrack {
  File file; // should be the saved file name in project/audio when persisted
  File originalFile; // might be deprecated
  Duration
      audioDuration; // consider storing these 3 duration fields in just ms? rather than duration object
  Duration trimStart;
  Duration trimEnd;
  double offset;
  double crossfade; // deprecated
  Timer? audioStartTimer; // deprecated
  bool audioStarted; // unused, should deprecate
  List<AutomationPoint> volumeAutomation; // probably deprecated
  Duration currentPosition; // I think deprecated/unused
  late List<double> normWaveformData;
  List<double>? _reversedWaveformCache;
  List<double>? _reversedWaveformSource;
  double gain;
  bool normalizeVolume;
  double normalizeGain;
  // Legacy migration field for projects saved while normalize was stored in gain.
  double preNormalizeGain;
  double pitchSemitones; // clip pitch shift in semitones
  bool isReversed; // clip plays the source waveform in reverse
  double sourceTempoBpm; // detected/imported source BPM (<=0 means unknown)
  bool stretchToProjectTempo; // clip follows project tempo when enabled
  bool tempoStretchPreservePitch; // false=resample, true=stretch-preserve
  String tempoWarpMode; // beats, complex, or repitch for desktop warp UI
  double recordingLatencyMs; // capture/device compensation applied at insert
  double alignmentOffsetMs; // onset/grid alignment delta applied after insert
  String audioEnhancementPreset; // non-empty when a cleanup preset was applied
  double reverb; // deprecated
  double echo; // deprecated
  bool didExtractWaveform;
  double y; // deprecated
  int rowIndex; // -1 = unassigned (shouldn't exist), can be 0-x where 0 is first row at top
  int rowId; // stable JUCE row identifier
  int engineClipId; // stable JUCE clip slot identifier
  String clipId; // stable Mixroom clip identifier
  String label; // UI name (renameable, non-unique)
  ClipKind clipKind;
  String instrumentId; // non-empty only for MIDI/instrument clips
  String instrumentName;
  Map<String, double> instrumentParams;
  List<MidiNote> midiNotes;
  String hostedInstrumentStateBase64;

  AudioTrack._({
    required this.file,
    required this.originalFile,
    required this.audioDuration,
    required this.trimStart,
    required this.trimEnd,
    required this.offset,
    required this.crossfade,
    this.audioStartTimer,
    this.audioStarted = false,
    List<AutomationPoint>? volumeAutomation,
    Duration? currentPosition,
    this.normWaveformData = const [],
    this.gain = kDefaultGainUi,
    this.normalizeVolume = false,
    this.normalizeGain = 1.0,
    this.preNormalizeGain = kDefaultGainUi,
    this.pitchSemitones = 0.0,
    this.isReversed = false,
    this.sourceTempoBpm = 0.0,
    this.stretchToProjectTempo = false,
    this.tempoStretchPreservePitch = false,
    String tempoWarpMode = kTempoWarpModeComplex,
    this.recordingLatencyMs = 0.0,
    this.alignmentOffsetMs = 0.0,
    this.audioEnhancementPreset = '',
    this.reverb = 0.0,
    this.echo = 0.0,
    this.didExtractWaveform = false,
    this.y = 0.0,
    this.rowIndex = -1,
    this.rowId = -1,
    this.engineClipId = -1,
    String? clipId,
    required this.label,
    this.clipKind = ClipKind.audio,
    this.instrumentId = '',
    this.instrumentName = '',
    Map<String, double>? instrumentParams,
    List<MidiNote>? midiNotes,
    this.hostedInstrumentStateBase64 = '',
  })  : clipId = _normalizeAudioTrackClipId(clipId),
        tempoWarpMode = normalizeTempoWarpMode(tempoWarpMode),
        currentPosition = currentPosition ?? Duration.zero,
        instrumentParams = instrumentParams ?? const <String, double>{},
        midiNotes = midiNotes ?? const <MidiNote>[],
        volumeAutomation = volumeAutomation ??
            [
              AutomationPoint(x: 0.0, volume: 1.0),
              AutomationPoint(x: 1.0, volume: 1.0)
            ];

  static Future<AudioTrack> create({
    required File file,
    required File originalFile,
    required Duration audioDuration,
    Duration trimStart = Duration.zero,
    Duration trimEnd = Duration.zero,
    double offset = 0.0,
    double crossfade = 0.0,
    Timer? audioStartTimer,
    bool audioStarted = false,
    List<AutomationPoint>? volumeAutomation,
    Duration? currentPosition,
    double gain = kDefaultGainUi,
    bool normalizeVolume = false,
    double normalizeGain = 1.0,
    double preNormalizeGain = kDefaultGainUi,
    double pitchSemitones = 0.0,
    bool isReversed = false,
    double sourceTempoBpm = 0.0,
    bool stretchToProjectTempo = false,
    bool tempoStretchPreservePitch = false,
    String tempoWarpMode = kTempoWarpModeComplex,
    double recordingLatencyMs = 0.0,
    double alignmentOffsetMs = 0.0,
    String audioEnhancementPreset = '',
    double reverb = 0.0,
    double echo = 0.0,
    bool didExtractWaveform = false,
    double y = 0, // deprecated
    int rowIndex = -1,
    int rowId = -1,
    int engineClipId = -1,
    String? clipId,
    required String label,
    ClipKind clipKind = ClipKind.audio,
    String instrumentId = '',
    String instrumentName = '',
    Map<String, double>? instrumentParams,
    List<MidiNote>? midiNotes,
    String hostedInstrumentStateBase64 = '',
  }) async {
    // Then create instance
    return AudioTrack._(
      file: file,
      originalFile: originalFile,
      audioDuration: audioDuration,
      trimStart: trimStart,
      trimEnd: trimEnd,
      offset: offset,
      crossfade: crossfade,
      audioStartTimer: audioStartTimer,
      audioStarted: audioStarted,
      volumeAutomation: volumeAutomation,
      currentPosition: currentPosition,
      normWaveformData: const [],
      gain: gain,
      normalizeVolume: normalizeVolume,
      normalizeGain: normalizeGain,
      preNormalizeGain: preNormalizeGain,
      pitchSemitones: pitchSemitones,
      isReversed: isReversed,
      sourceTempoBpm: sourceTempoBpm,
      stretchToProjectTempo: stretchToProjectTempo,
      tempoStretchPreservePitch: tempoStretchPreservePitch,
      tempoWarpMode: tempoWarpMode,
      recordingLatencyMs: recordingLatencyMs,
      alignmentOffsetMs: alignmentOffsetMs,
      audioEnhancementPreset: audioEnhancementPreset,
      reverb: reverb,
      echo: echo,
      didExtractWaveform: didExtractWaveform,
      y: 0, // deprecated
      rowIndex: rowIndex,
      rowId: rowId,
      engineClipId: engineClipId,
      clipId: clipId,
      label: label,
      clipKind: clipKind,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      instrumentParams: instrumentParams,
      midiNotes: midiNotes,
      hostedInstrumentStateBase64: hostedInstrumentStateBase64,
    );
  }

  bool get isMidi => clipKind == ClipKind.midi;

  List<double> get displayWaveformData {
    if (!isReversed || normWaveformData.isEmpty) return normWaveformData;
    if (identical(_reversedWaveformSource, normWaveformData) &&
        _reversedWaveformCache != null) {
      return _reversedWaveformCache!;
    }
    final reversed = List<double>.unmodifiable(normWaveformData.reversed);
    _reversedWaveformSource = normWaveformData;
    _reversedWaveformCache = reversed;
    return reversed;
  }
}

int _audioTrackClipIdCounter = 0;

String _normalizeAudioTrackClipId(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isNotEmpty) return trimmed;
  _audioTrackClipIdCounter += 1;
  return 'clip_${DateTime.now().microsecondsSinceEpoch}_$_audioTrackClipIdCounter';
}

enum TimelineRowKind {
  audio('audio'),
  instrument('instrument');

  final String wireName;

  const TimelineRowKind(this.wireName);

  static TimelineRowKind fromWire(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'instrument':
      case 'instrument_lane':
      case 'midi':
        return TimelineRowKind.instrument;
      case 'audio':
      default:
        return TimelineRowKind.audio;
    }
  }
}

class TimelineRow {
  final int rowId;
  String name;
  int iconId;
  TimelineRowKind kind;
  String instrumentId;
  String instrumentName;
  Map<String, double> instrumentParams;
  String roleOverride;
  String groupId;
  String inputDeviceName;
  int inputChannelStart;
  int inputChannelCount;

  TimelineRow({
    required this.rowId,
    required this.name,
    required this.iconId,
    this.kind = TimelineRowKind.audio,
    this.instrumentId = '',
    this.instrumentName = '',
    Map<String, double>? instrumentParams,
    String roleOverride = '',
    this.groupId = '',
    this.inputDeviceName = '',
    this.inputChannelStart = 0,
    this.inputChannelCount = 1,
  })  : roleOverride = normalizeTrackRoleOverride(roleOverride),
        instrumentParams = instrumentParams ?? const <String, double>{};

  bool get isInstrumentLane => kind == TimelineRowKind.instrument;

  TimelineRow copyWith({
    int? rowId,
    String? name,
    int? iconId,
    TimelineRowKind? kind,
    String? instrumentId,
    String? instrumentName,
    Map<String, double>? instrumentParams,
    String? roleOverride,
    String? groupId,
    String? inputDeviceName,
    int? inputChannelStart,
    int? inputChannelCount,
  }) {
    return TimelineRow(
      rowId: rowId ?? this.rowId,
      name: name ?? this.name,
      iconId: iconId ?? this.iconId,
      kind: kind ?? this.kind,
      instrumentId: instrumentId ?? this.instrumentId,
      instrumentName: instrumentName ?? this.instrumentName,
      instrumentParams: instrumentParams ?? this.instrumentParams,
      roleOverride: roleOverride ?? this.roleOverride,
      groupId: groupId ?? this.groupId,
      inputDeviceName: inputDeviceName ?? this.inputDeviceName,
      inputChannelStart: inputChannelStart ?? this.inputChannelStart,
      inputChannelCount: inputChannelCount ?? this.inputChannelCount,
    );
  }
}

class TrackGroup {
  final String id;
  final String name;
  final int color;
  final List<int> rowIds;
  final double gain;
  final double pan;
  final bool muted;
  final bool soloed;
  final bool collapsed;
  final List<EffectSnapshot> effects;

  const TrackGroup({
    required this.id,
    required this.name,
    this.color = 0,
    this.rowIds = const <int>[],
    this.gain = kDefaultGainUi,
    this.pan = 0.5,
    this.muted = false,
    this.soloed = false,
    this.collapsed = false,
    this.effects = const <EffectSnapshot>[],
  });
}

// consider making extendable to general automation points, not just volume
// so can change 'volume' to 'value' or something
class AutomationPoint {
  double
      x; // UPDATED: X = time in ms in the timeline.   OLD: normalized x (0.0 = left, 1.0 = right)
  double volume; // normalized volume (0.0 = silent, 1.0 = full)
  AutomationPoint({required this.x, required this.volume});
  AutomationPoint copy() => AutomationPoint(x: x, volume: volume);

  Map<String, dynamic> toMap() {
    return {
      "x": x,
      "volume": volume,
    };
  }

  Map<String, dynamic> toJson() => toMap();
}

class EffectSnapshot {
  final String effectId; // name or path
  final String displayName;
  final bool bypassed;
  final Map<String, dynamic> params;
  final String stateBase64;

  EffectSnapshot(
    this.effectId,
    this.bypassed,
    this.params, {
    this.displayName = '',
    this.stateBase64 = '',
  });
}

class RowEffectsSnapshot {
  final int row;
  final int rowId;
  final List<EffectSnapshot> effects;

  RowEffectsSnapshot(this.row, this.effects, {this.rowId = -1});
}

class MasterEffectsSnapshot {
  final List<EffectSnapshot> effects;

  MasterEffectsSnapshot(this.effects);
}

class AutomationLaneSnapshot {
  final String targetId;
  final String label;
  final int effectIndex;
  final String paramId;
  final String type;
  final double min;
  final double max;
  final List<AutomationPoint> points;

  const AutomationLaneSnapshot({
    required this.targetId,
    required this.label,
    required this.effectIndex,
    required this.paramId,
    required this.type,
    required this.min,
    required this.max,
    required this.points,
  });

  Map<String, dynamic> toJson() {
    return {
      "targetId": targetId,
      "label": label,
      "effectIndex": effectIndex,
      "paramId": paramId,
      "type": type,
      "min": min,
      "max": max,
      "points": points.map((p) => p.toJson()).toList(),
    };
  }

  static AutomationLaneSnapshot fromJson(Map<String, dynamic> json) {
    final rawTargetId = (json["targetId"] ?? '').toString().trim();
    final rawLabel = (json["label"] ?? '').toString().trim();
    final effectIndex = (json["effectIndex"] as num?)?.toInt() ?? -1;
    final paramId = (json["paramId"] ?? '').toString();
    final type = (json["type"] ?? 'float').toString();
    final min = (json["min"] as num?)?.toDouble() ?? 0.0;
    final max = (json["max"] as num?)?.toDouble() ?? 1.0;
    final points = ((json["points"] as List?) ?? const [])
        .map((e) =>
            AutomationPointJson.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);

    return AutomationLaneSnapshot(
      targetId: rawTargetId.isNotEmpty ? rawTargetId : 'volume',
      label: rawLabel.isNotEmpty ? rawLabel : 'Volume',
      effectIndex: effectIndex,
      paramId: paramId,
      type: type,
      min: min,
      max: max,
      points: points,
    );
  }
}

class AutomationClipSnapshot {
  final String id;
  final String targetId;
  final String label;
  final String patternId;
  final int row;
  final int lane;
  final double startMs;
  final double lengthMs;
  final bool muted;
  final List<AutomationPoint> points; // relative to clip start

  const AutomationClipSnapshot({
    required this.id,
    required this.targetId,
    required this.label,
    this.patternId = '',
    required this.row,
    this.lane = 0,
    required this.startMs,
    required this.lengthMs,
    required this.muted,
    required this.points,
  });

  AutomationClipSnapshot copyWith({
    String? id,
    String? targetId,
    String? label,
    String? patternId,
    int? row,
    int? lane,
    double? startMs,
    double? lengthMs,
    bool? muted,
    List<AutomationPoint>? points,
  }) {
    return AutomationClipSnapshot(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      label: label ?? this.label,
      patternId: patternId ?? this.patternId,
      row: row ?? this.row,
      lane: lane ?? this.lane,
      startMs: startMs ?? this.startMs,
      lengthMs: lengthMs ?? this.lengthMs,
      muted: muted ?? this.muted,
      points:
          (points ?? this.points).map((p) => p.copy()).toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "targetId": targetId,
      "label": label,
      "patternId": patternId,
      "row": row,
      "lane": lane,
      "startMs": startMs,
      "lengthMs": lengthMs,
      "muted": muted,
      "points": points.map((p) => p.toJson()).toList(growable: false),
    };
  }

  static AutomationClipSnapshot fromJson(Map<String, dynamic> json) {
    final targetId = (json["targetId"] ?? '').toString().trim();
    final startMs = (json["startMs"] as num?)?.toDouble() ?? 0.0;
    final lengthMs = (json["lengthMs"] as num?)?.toDouble() ?? 1000.0;
    final fallbackId =
        'clip_${targetId.isEmpty ? 'volume' : targetId}_${startMs.round()}';
    return AutomationClipSnapshot(
      id: ((json["id"] as String?) ?? '').trim().isEmpty
          ? fallbackId
          : (json["id"] as String).trim(),
      targetId: targetId.isEmpty ? 'volume' : targetId,
      label: (json["label"] as String?)?.trim() ?? '',
      patternId: (json["patternId"] as String?)?.trim() ?? '',
      row: (json["row"] as num?)?.toInt() ?? 0,
      lane: (((json["lane"] as num?)?.toInt() ?? 0).clamp(0, 1 << 20)).toInt(),
      startMs: startMs,
      lengthMs: lengthMs,
      muted: (json["muted"] as bool?) ?? false,
      points: ((json["points"] as List?) ?? const [])
          .map((e) =>
              AutomationPointJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

extension AudioTrackSerialization on AudioTrack {
  Map<String, dynamic> toJson(String fileName) {
    return {
      "fileName": fileName,
      "label": label,
      "clipType": clipKind.wireName,
      "trimStartMs": trimStart.inMilliseconds,
      "trimEndMs": trimEnd.inMilliseconds,
      "offset": offset,
      "crossfade": crossfade,
      "gain": gain,
      "normalizeVolume": normalizeVolume,
      "normalizeGain": normalizeGain,
      "preNormalizeGain": preNormalizeGain,
      "pitchSemitones": pitchSemitones,
      "isReversed": isReversed,
      "sourceTempoBpm": sourceTempoBpm,
      "stretchToProjectTempo": stretchToProjectTempo,
      "tempoStretchPreservePitch": tempoStretchPreservePitch,
      "tempoWarpMode": normalizeTempoWarpMode(tempoWarpMode),
      "recordingLatencyMs": recordingLatencyMs,
      "alignmentOffsetMs": alignmentOffsetMs,
      if (audioEnhancementPreset.trim().isNotEmpty)
        "audioEnhancementPreset": audioEnhancementPreset.trim(),
      "rowIndex": rowIndex,
      "rowId": rowId,
      "clipId": clipId,
      "automation": volumeAutomation.map((e) => e.toJson()).toList(),
      "instrumentId": instrumentId,
      "instrumentName": instrumentName,
      "instrumentParams": instrumentParams,
      "midiNotes": midiNotes.map((n) => n.toJson()).toList(),
      "hostedInstrumentStateB64": hostedInstrumentStateBase64,
    };
  }
}

// ---- JSON helpers for project save/load ----

class RowStateSnapshot {
  final int row;
  final int rowId;
  final double gain; // row/bus gain
  final double pan; // row/bus pan (-1..1 or 0..1 depending on your app)
  final List<AutomationPoint> volumeAutomation; // row-level automation
  final List<AutomationLaneSnapshot> automationLanes;
  final List<AutomationClipSnapshot> automationClips;
  final String? selectedAutomationTargetId;
  final bool muted;
  final bool soloed;
  final String roleOverride;
  final String groupId;
  final String inputDeviceName;
  final int inputChannelStart;
  final int inputChannelCount;

  RowStateSnapshot({
    required this.row,
    this.rowId = -1,
    required this.gain,
    required this.pan,
    required this.volumeAutomation,
    this.automationLanes = const <AutomationLaneSnapshot>[],
    this.automationClips = const <AutomationClipSnapshot>[],
    this.selectedAutomationTargetId,
    this.muted = false,
    this.soloed = false,
    String roleOverride = '',
    this.groupId = '',
    this.inputDeviceName = '',
    this.inputChannelStart = 0,
    this.inputChannelCount = 1,
  }) : roleOverride = normalizeTrackRoleOverride(roleOverride);

  Map<String, dynamic> toJson() {
    return {
      "row": row,
      "rowId": rowId,
      "gain": gain,
      "pan": pan,
      "volumeAutomation": volumeAutomation.map((e) => e.toJson()).toList(),
      "automationLanes": automationLanes.map((e) => e.toJson()).toList(),
      "automationClips": automationClips.map((e) => e.toJson()).toList(),
      "selectedAutomationTargetId": selectedAutomationTargetId,
      "muted": muted,
      "soloed": soloed,
      if (roleOverride.isNotEmpty) "roleOverride": roleOverride,
      if (groupId.trim().isNotEmpty) "groupId": groupId.trim(),
      if (inputDeviceName.trim().isNotEmpty)
        "inputDeviceName": inputDeviceName.trim(),
      "inputChannelStart": inputChannelStart,
      "inputChannelCount": inputChannelCount,
    };
  }

  static RowStateSnapshot fromJson(Map<String, dynamic> json) {
    final lanes = ((json["automationLanes"] as List?) ?? const [])
        .map((e) =>
            AutomationLaneSnapshot.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
    final clips = ((json["automationClips"] as List?) ?? const [])
        .map((e) =>
            AutomationClipSnapshot.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);

    return RowStateSnapshot(
      row: (json["row"] as num?)?.toInt() ?? 0,
      rowId: (json["rowId"] as num?)?.toInt() ?? -1,
      gain: ((json["gain"] as num?) ?? kDefaultGainUi).toDouble(),
      pan: ((json["pan"] as num?) ?? 0.5).toDouble(),
      volumeAutomation: ((json["volumeAutomation"] as List?) ?? [])
          .map((e) =>
              AutomationPointJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      automationLanes: lanes,
      automationClips: clips,
      selectedAutomationTargetId:
          (json["selectedAutomationTargetId"] as String?)?.trim(),
      muted: json["muted"] == true,
      soloed: json["soloed"] == true,
      roleOverride: (json["roleOverride"] as String?)?.trim() ?? '',
      groupId: (json["groupId"] as String?)?.trim() ?? '',
      inputDeviceName: (json["inputDeviceName"] as String?)?.trim() ?? '',
      inputChannelStart:
          ((json["inputChannelStart"] as num?)?.toInt() ?? 0).clamp(0, 999),
      inputChannelCount:
          ((json["inputChannelCount"] as num?)?.toInt() ?? 1).clamp(1, 999),
    );
  }
}

extension AutomationPointJson on AutomationPoint {
  static AutomationPoint fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      x: (json['x'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
    );
  }
}

extension EffectSnapshotJson on EffectSnapshot {
  Map<String, dynamic> toJson() => {
        "effectId": effectId,
        if (displayName.trim().isNotEmpty) "displayName": displayName.trim(),
        "bypassed": bypassed,
        "params": params,
        if (stateBase64.trim().isNotEmpty) "stateBase64": stateBase64.trim(),
      };

  static EffectSnapshot fromJson(Map<String, dynamic> json) {
    final rawParams = (json["params"] as Map).cast<String, dynamic>();
    return EffectSnapshot(
      json["effectId"] as String,
      json["bypassed"] as bool,
      rawParams,
      displayName: (json["displayName"] as String?)?.trim() ?? '',
      stateBase64: (json["stateBase64"] as String?)?.trim() ?? '',
    );
  }
}

extension RowEffectsSnapshotJson on RowEffectsSnapshot {
  Map<String, dynamic> toJson() => {
        "row": row,
        "rowId": rowId,
        "effects": effects.map((e) => e.toJson()).toList(),
      };

  static RowEffectsSnapshot fromJson(Map<String, dynamic> json) {
    return RowEffectsSnapshot(
      (json["row"] as num?)?.toInt() ?? 0,
      (json["effects"] as List)
          .map((e) =>
              EffectSnapshotJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      rowId: (json["rowId"] as num?)?.toInt() ?? -1,
    );
  }
}

extension MasterEffectsSnapshotJson on MasterEffectsSnapshot {
  Map<String, dynamic> toJson() => {
        "effects": effects.map((e) => e.toJson()).toList(),
      };

  static MasterEffectsSnapshot fromJson(Map<String, dynamic> json) {
    return MasterEffectsSnapshot(
      (json["effects"] as List)
          .map((e) =>
              EffectSnapshotJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

extension TrackGroupJson on TrackGroup {
  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "name": name,
        "color": color,
        "rowIds": rowIds,
        "gain": gain,
        "pan": pan,
        "muted": muted,
        "soloed": soloed,
        "collapsed": collapsed,
        "effects": effects.map((e) => e.toJson()).toList(),
      };

  static TrackGroup fromJson(Map<String, dynamic> json) {
    return TrackGroup(
      id: (json["id"] as String?)?.trim() ?? '',
      name: (json["name"] as String?)?.trim() ?? 'Group',
      color: (json["color"] as num?)?.toInt() ?? 0,
      rowIds: ((json["rowIds"] as List?) ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value >= 0)
          .toList(growable: false),
      gain: ((json["gain"] as num?) ?? kDefaultGainUi).toDouble(),
      pan: ((json["pan"] as num?) ?? 0.5).toDouble(),
      muted: json["muted"] == true,
      soloed: json["soloed"] == true,
      collapsed: json["collapsed"] == true,
      effects: ((json["effects"] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EffectSnapshotJson.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

// Wrappers for any metering bars
class MeterFrame {
  final double peakL, peakR; // 0..1
  final double rmsL, rmsR; // 0..1
  final bool clip; // latched clip indicator (optional)

  const MeterFrame({
    required this.peakL,
    required this.peakR,
    required this.rmsL,
    required this.rmsR,
    required this.clip,
  });

  static const zero =
      MeterFrame(peakL: 0, peakR: 0, rmsL: 0, rmsR: 0, clip: false);
}

class MeterBus extends ChangeNotifier {
  final int numRows;

  MeterFrame master = MeterFrame.zero;
  late final List<MeterFrame> rows =
      List.filled(numRows, MeterFrame.zero, growable: false);

  MeterBus({required this.numRows});

  void setMaster(MeterFrame v) {
    master = v;
    notifyListeners();
  }

  void setRow(int row, MeterFrame v) {
    if (row < 0 || row >= rows.length) return;
    rows[row] = v;
    notifyListeners();
  }

  void zeroAll() {
    master = MeterFrame.zero;
    for (int i = 0; i < rows.length; i++) {
      rows[i] = MeterFrame.zero;
    }
    notifyListeners();
  }

  void decayAll({double mul = 0.85}) {
    MeterFrame decay(MeterFrame f) {
      final peakL = (f.peakL * mul);
      final peakR = (f.peakR * mul);
      final rmsL = (f.rmsL * mul);
      final rmsR = (f.rmsR * mul);

      // clamp tiny values to 0 to avoid infinite tail
      double z(double v) => (v < 0.001) ? 0.0 : v;

      return MeterFrame(
        peakL: z(peakL),
        peakR: z(peakR),
        rmsL: z(rmsL),
        rmsR: z(rmsR),
        clip: false, // drop clip when stopped (simple)
      );
    }

    master = decay(master);
    for (int i = 0; i < rows.length; i++) {
      rows[i] = decay(rows[i]);
    }
    notifyListeners();
  }

  bool get isAllZero {
    bool frameIsZero(MeterFrame f) {
      return f.peakL == 0.0 &&
          f.peakR == 0.0 &&
          f.rmsL == 0.0 &&
          f.rmsR == 0.0 &&
          f.clip == false;
    }

    // master
    if (!frameIsZero(master)) return false;

    // rows
    for (final r in rows) {
      if (!frameIsZero(r)) return false;
    }

    return true;
  }
}
