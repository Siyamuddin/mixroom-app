import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// TODO: rename to AudioClip, because 'Tracks' should be equivalent to 'Rows' in the project, rather than a single audio clip
class AudioTrack {
  File file; // should be the saved file name in project/audio when persisted
  File originalFile; // might be deprecated
  final Duration audioDuration; // consider storing these 3 duration fields in just ms? rather than duration object
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
  double reverb; // deprecated
  double echo; // deprecated
  bool didExtractWaveform;
  double y; // deprecated
  int rowIndex; // -1 = unassigned (shouldn't exist), can be 0-x where 0 is first row at top
  String label; // UI name (renameable, non-unique)

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
    this.gain = 1.0,
    this.reverb = 0.0,
    this.echo = 0.0,
    this.didExtractWaveform = false,
    this.y = 0.0,
    this.rowIndex = -1,
    required this.label,
  })  : currentPosition = currentPosition ?? Duration.zero,
        volumeAutomation =
            volumeAutomation ?? [AutomationPoint(x: 0.0, volume: 1.0), AutomationPoint(x: 1.0, volume: 1.0)];

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
    double gain = 1.0,
    double reverb = 0.0,
    double echo = 0.0,
    bool didExtractWaveform = false,
    double y = 0, // deprecated
    int rowIndex = -1,
    required String label,
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
      reverb: reverb,
      echo: echo,
      didExtractWaveform: didExtractWaveform,
      y: 0, // deprecated
      rowIndex: rowIndex,
      label: label,
    );
  }
}

// consider making extendable to general automation points, not just volume
// so can change 'volume' to 'value' or something
class AutomationPoint {
  double x; // UPDATED: X = time in ms in the timeline.   OLD: normalized x (0.0 = left, 1.0 = right)
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

extension AudioTrackSerialization on AudioTrack {
  Map<String, dynamic> toJson(String fileName) {
    return {
      "fileName": fileName,
      "trimStartMs": trimStart.inMilliseconds,
      "trimEndMs": trimEnd.inMilliseconds,
      "offset": offset,
      "crossfade": crossfade,
      "gain": gain,
      "rowIndex": rowIndex,
      "automation": volumeAutomation.map((e) => e.toJson()).toList(),
    };
  }
}

// ---- JSON helpers for project save/load ----

class RowStateSnapshot {
  final int row;
  final double gain; // row/bus gain
  final double pan; // row/bus pan (-1..1 or 0..1 depending on your app)
  final List<AutomationPoint> volumeAutomation; // row-level automation

  RowStateSnapshot({
    required this.row,
    required this.gain,
    required this.pan,
    required this.volumeAutomation,
  });

  Map<String, dynamic> toJson() {
    return {
      "row": row,
      "gain": gain,
      "pan": pan,
      "volumeAutomation": volumeAutomation.map((e) => e.toJson()).toList(),
    };
  }

  static RowStateSnapshot fromJson(Map<String, dynamic> json) {
    return RowStateSnapshot(
      row: (json["row"] as int?) ?? 0,
      gain: ((json["gain"] as num?) ?? 1.0).toDouble(),
      pan: ((json["pan"] as num?) ?? 0.5).toDouble(),
      volumeAutomation: ((json["volumeAutomation"] as List?) ?? [])
          .map((e) => AutomationPointJson.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
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
      (json["effects"] as List).map((e) => EffectSnapshotJson.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }
}

extension MasterEffectsSnapshotJson on MasterEffectsSnapshot {
  Map<String, dynamic> toJson() => {
        "effects": effects.map((e) => e.toJson()).toList(),
      };

  static MasterEffectsSnapshot fromJson(Map<String, dynamic> json) {
    return MasterEffectsSnapshot(
      (json["effects"] as List).map((e) => EffectSnapshotJson.fromJson((e as Map).cast<String, dynamic>())).toList(),
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

  static const zero = MeterFrame(peakL: 0, peakR: 0, rmsL: 0, rmsR: 0, clip: false);
}

class MeterBus extends ChangeNotifier {
  final int numRows;

  MeterFrame master = MeterFrame.zero;
  late final List<MeterFrame> rows = List.filled(numRows, MeterFrame.zero, growable: false);

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
      return f.peakL == 0.0 && f.peakR == 0.0 && f.rmsL == 0.0 && f.rmsR == 0.0 && f.clip == false;
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
