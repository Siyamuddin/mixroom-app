import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';

class AudioTrack {
  File file;
  File originalFile; // for gain
  // final AudioPlayer player;
  final PlayerController waveformController;
  final Duration audioDuration;
  Duration trimStart;
  Duration trimEnd;
  double offset;
  double crossfade;
  Timer? audioStartTimer;
  bool audioStarted;
  List<AutomationPoint> volumeAutomation; // NEW property
  Duration currentPosition;
  late List<double> normWaveformData;
  double gain;
  // consider moving the below FX into a separate class
  double reverb;
  double echo;
  bool didExtractWaveform;
  double y; // deprecated
  int rowIndex; // -1 = unassigned (shouldn't exist), can be 0-x where 0 is first row at top

  AudioTrack._({
    required this.file,
    required this.originalFile,
    // required this.player,
    required this.waveformController,
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
  })  : currentPosition = currentPosition ?? Duration.zero,
        volumeAutomation =
            volumeAutomation ?? [AutomationPoint(x: 0.0, volume: 1.0), AutomationPoint(x: 1.0, volume: 1.0)];

  static Future<AudioTrack> create({
    required File file,
    required File originalFile,
    // required AudioPlayer player,
    required PlayerController waveformController,
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
  }) async {
    // Then create instance
    return AudioTrack._(
      file: file,
      originalFile: originalFile,
      // player: player,
      waveformController: waveformController,
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
    );
  }
}

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
  final Map<String, dynamic> params;

  EffectSnapshot(this.effectId, this.params);
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
        "params": params,
      };

  static EffectSnapshot fromJson(Map<String, dynamic> json) {
    final rawParams = (json["params"] as Map).cast<String, dynamic>();
    return EffectSnapshot(
      json["effectId"] as String,
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
