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
  double gain;
  double pitchSemitones; // clip pitch shift in semitones
  double sourceTempoBpm; // detected/imported source BPM (<=0 means unknown)
  bool stretchToProjectTempo; // clip follows project tempo when enabled
  bool tempoStretchPreservePitch; // false=resample, true=stretch-preserve
  double reverb; // deprecated
  double echo; // deprecated
  bool didExtractWaveform;
  double y; // deprecated
  int rowIndex; // -1 = unassigned (shouldn't exist), can be 0-x where 0 is first row at top
  int rowId; // stable JUCE row identifier
  int engineClipId; // stable JUCE clip slot identifier
  String label; // UI name (renameable, non-unique)
  ClipKind clipKind;
  String instrumentId; // non-empty only for MIDI/instrument clips
  String instrumentName;
  Map<String, double> instrumentParams;
  List<MidiNote> midiNotes;

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
    this.pitchSemitones = 0.0,
    this.sourceTempoBpm = 0.0,
    this.stretchToProjectTempo = false,
    this.tempoStretchPreservePitch = false,
    this.reverb = 0.0,
    this.echo = 0.0,
    this.didExtractWaveform = false,
    this.y = 0.0,
    this.rowIndex = -1,
    this.rowId = -1,
    this.engineClipId = -1,
    required this.label,
    this.clipKind = ClipKind.audio,
    this.instrumentId = '',
    this.instrumentName = '',
    Map<String, double>? instrumentParams,
    List<MidiNote>? midiNotes,
  })  : currentPosition = currentPosition ?? Duration.zero,
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
    double pitchSemitones = 0.0,
    double sourceTempoBpm = 0.0,
    bool stretchToProjectTempo = false,
    bool tempoStretchPreservePitch = false,
    double reverb = 0.0,
    double echo = 0.0,
    bool didExtractWaveform = false,
    double y = 0, // deprecated
    int rowIndex = -1,
    int rowId = -1,
    int engineClipId = -1,
    required String label,
    ClipKind clipKind = ClipKind.audio,
    String instrumentId = '',
    String instrumentName = '',
    Map<String, double>? instrumentParams,
    List<MidiNote>? midiNotes,
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
      pitchSemitones: pitchSemitones,
      sourceTempoBpm: sourceTempoBpm,
      stretchToProjectTempo: stretchToProjectTempo,
      tempoStretchPreservePitch: tempoStretchPreservePitch,
      reverb: reverb,
      echo: echo,
      didExtractWaveform: didExtractWaveform,
      y: 0, // deprecated
      rowIndex: rowIndex,
      rowId: rowId,
      engineClipId: engineClipId,
      label: label,
      clipKind: clipKind,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      instrumentParams: instrumentParams,
      midiNotes: midiNotes,
    );
  }

  bool get isMidi => clipKind == ClipKind.midi;
}

class TimelineRow {
  final int rowId;
  String name;
  int iconId;

  TimelineRow({
    required this.rowId,
    required this.name,
    required this.iconId,
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
  final bool bypassed;
  final Map<String, dynamic> params;

  EffectSnapshot(this.effectId, this.bypassed, this.params);
}

class RowEffectsSnapshot {
  final int row;
  final List<EffectSnapshot> effects;

  RowEffectsSnapshot(this.row, this.effects);
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
      "pitchSemitones": pitchSemitones,
      "sourceTempoBpm": sourceTempoBpm,
      "stretchToProjectTempo": stretchToProjectTempo,
      "tempoStretchPreservePitch": tempoStretchPreservePitch,
      "rowIndex": rowIndex,
      "rowId": rowId,
      "automation": volumeAutomation.map((e) => e.toJson()).toList(),
      "instrumentId": instrumentId,
      "instrumentName": instrumentName,
      "instrumentParams": instrumentParams,
      "midiNotes": midiNotes.map((n) => n.toJson()).toList(),
    };
  }
}

// ---- JSON helpers for project save/load ----

class RowStateSnapshot {
  final int row;
  final double gain; // row/bus gain
  final double pan; // row/bus pan (-1..1 or 0..1 depending on your app)
  final List<AutomationPoint> volumeAutomation; // row-level automation
  final List<AutomationLaneSnapshot> automationLanes;
  final List<AutomationClipSnapshot> automationClips;
  final String? selectedAutomationTargetId;

  RowStateSnapshot({
    required this.row,
    required this.gain,
    required this.pan,
    required this.volumeAutomation,
    this.automationLanes = const <AutomationLaneSnapshot>[],
    this.automationClips = const <AutomationClipSnapshot>[],
    this.selectedAutomationTargetId,
  });

  Map<String, dynamic> toJson() {
    return {
      "row": row,
      "gain": gain,
      "pan": pan,
      "volumeAutomation": volumeAutomation.map((e) => e.toJson()).toList(),
      "automationLanes": automationLanes.map((e) => e.toJson()).toList(),
      "automationClips": automationClips.map((e) => e.toJson()).toList(),
      "selectedAutomationTargetId": selectedAutomationTargetId,
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
      row: (json["row"] as int?) ?? 0,
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
        "bypassed": bypassed,
        "params": params,
      };

  static EffectSnapshot fromJson(Map<String, dynamic> json) {
    final rawParams = (json["params"] as Map).cast<String, dynamic>();
    return EffectSnapshot(
      json["effectId"] as String,
      json["bypassed"] as bool,
      rawParams,
    );
  }
}

extension RowEffectsSnapshotJson on RowEffectsSnapshot {
  Map<String, dynamic> toJson() => {
        "row": row,
        "effects": effects.map((e) => e.toJson()).toList(),
      };

  static RowEffectsSnapshot fromJson(Map<String, dynamic> json) {
    return RowEffectsSnapshot(
      json["row"] as int,
      (json["effects"] as List)
          .map((e) =>
              EffectSnapshotJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
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
