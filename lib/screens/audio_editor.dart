import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';
import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../helpers/youtube_upload.dart';
import 'package:mixroom/models/models.dart';
// import 'package:mixroom/chat/_old_chat_screen.dart';
import 'package:mixroom/ai/chat_pipeline.dart';
import 'package:mixroom/ai/goal_vector_builder.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
// import 'package:mixroom/ai/local_llm_service.dart';
import 'package:mixroom/ai/cloud_llm_service.dart';
import 'package:mixroom/ai/local_mixing_model.dart';
import 'package:mixroom/ai/magnitude_predictor.dart';
import 'package:mixroom/ai/magnitude_predictor_flags.dart';
import 'package:mixroom/ai/onnx_magnitude_predictor.dart';
import 'package:mixroom/ai/producer_data_collector.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/goal_vector.dart';

// import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/ffprobe_kit.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/log.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/session.dart';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/log.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/session.dart';

// import 'package:ffmpeg_kit_16kb/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_16kb/abstract_session.dart';
// import 'package:ffmpeg_kit_16kb/arch_detect.dart';
// import 'package:ffmpeg_kit_16kb/chapter.dart';
// import 'package:ffmpeg_kit_16kb/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_16kb/ffmpeg_kit_config.dart';
// import 'package:ffmpeg_kit_16kb/ffmpeg_session.dart';
// import 'package:ffmpeg_kit_16kb/ffmpeg_session_complete_callback.dart';
// import 'package:ffmpeg_kit_16kb/ffprobe_kit.dart';
// import 'package:ffmpeg_kit_16kb/ffprobe_session.dart';
// import 'package:ffmpeg_kit_16kb/ffprobe_session_complete_callback.dart';
// import 'package:ffmpeg_kit_16kb/level.dart';
// import 'package:ffmpeg_kit_16kb/log.dart';
// import 'package:ffmpeg_kit_16kb/log_callback.dart';
// import 'package:ffmpeg_kit_16kb/log_redirection_strategy.dart';
// import 'package:ffmpeg_kit_16kb/media_information.dart';
// import 'package:ffmpeg_kit_16kb/media_information_json_parser.dart';
// import 'package:ffmpeg_kit_16kb/media_information_session.dart';
// import 'package:ffmpeg_kit_16kb/media_information_session_complete_callback.dart';
// import 'package:ffmpeg_kit_16kb/packages.dart';
// import 'package:ffmpeg_kit_16kb/platform_interface/ffmpeg_kit_flutter_platform_interface.dart';
// import 'package:ffmpeg_kit_16kb/platform_interface/method_channel_ffmpeg_kit_flutter.dart';
// import 'package:ffmpeg_kit_16kb/return_code.dart';
// import 'package:ffmpeg_kit_16kb/session.dart';
// import 'package:ffmpeg_kit_16kb/session_state.dart';
// import 'package:ffmpeg_kit_16kb/signal.dart';
// import 'package:ffmpeg_kit_16kb/statistics.dart';
// import 'package:ffmpeg_kit_16kb/statistics_callback.dart';
// import 'package:ffmpeg_kit_16kb/stream_information.dart';

import 'package:file_picker/file_picker.dart';
import 'package:accessing_security_scoped_resource/accessing_security_scoped_resource.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:fftea/fftea.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/screens/home.dart';
import 'package:mixroom/widgets/effects_panel.dart';
import 'package:mixroom/widgets/piano_roll_editor.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:record/record.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';

Completer<void> _cancelSignal = Completer();

const List<String> kMixroomBuiltInEffects = [
  "EQ 3-Band",
  "Compressor",
  "Limiter",
  "Clipper",
  "De-Esser",
  "Distortion",
  "Delay",
  "Reverb",
  "EQ Parametric",
  "Pitch Shift",
  "Chorus",
  "Vibrato",
];

const List<Map<String, dynamic>> kInstrumentCatalog = [
  {
    "id": "mixroom.basic_synth",
    "name": "Basic Synth",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 3200.0,
    "attackMs": 18.0,
    "releaseMs": 180.0,
    "drive": 0.08,
  },
  {
    "id": "mixroom.bass_mono",
    "name": "Bass Mono",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 1200.0,
    "attackMs": 8.0,
    "releaseMs": 220.0,
    "drive": 0.28,
  },
  {
    "id": "mixroom.soft_pad",
    "name": "Soft Pad",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 2100.0,
    "attackMs": 80.0,
    "releaseMs": 620.0,
    "drive": 0.02,
  },
  {
    "id": "mixroom.figbug_wavetable",
    "name": "Bright Lead",
    "category": "instrument",
    "sourceProject": "FigBug/Wavetable",
    "sourceLicense": "BSD-3-Clause",
    "oscillator": 1.0,
    "cutoffHz": 5200.0,
    "attackMs": 6.0,
    "releaseMs": 240.0,
    "drive": 0.18,
  },
  {
    "id": "mixroom.sarah_harmonic",
    "name": "Dream Pad",
    "category": "instrument",
    "sourceProject": "getdunne/SARAH",
    "sourceLicense": "MIT",
    "oscillator": 3.0,
    "cutoffHz": 2800.0,
    "attackMs": 34.0,
    "releaseMs": 540.0,
    "drive": 0.1,
  },
  {
    "id": "mixroom.vanilla_poly",
    "name": "Simple Keys",
    "category": "instrument",
    "sourceProject": "getdunne/VanillaJuce",
    "sourceLicense": "MIT",
    "oscillator": 0.0,
    "cutoffHz": 3600.0,
    "attackMs": 12.0,
    "releaseMs": 260.0,
    "drive": 0.05,
  },
  {
    "id": "mixroom.duck_synth",
    "name": "Deep Mono Bass",
    "category": "instrument",
    "sourceProject": "jsvaldezv/duck-synth",
    "sourceLicense": "MIT",
    "oscillator": 2.0,
    "cutoffHz": 1600.0,
    "attackMs": 2.0,
    "releaseMs": 140.0,
    "drive": 0.26,
  },
  {
    "id": "mixroom.chow_kick",
    "name": "Punch Kick",
    "category": "drum",
    "sourceProject": "jatinchowdhury18/ChowKick",
    "sourceLicense": "BSD-3-Clause",
    "oscillator": 0.0,
    "cutoffHz": 900.0,
    "attackMs": 0.0,
    "releaseMs": 90.0,
    "drive": 0.42,
  },
  {
    "id": "mixroom.warm_keys",
    "name": "Warm Keys",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 3000.0,
    "attackMs": 14.0,
    "releaseMs": 320.0,
    "drive": 0.06,
  },
  {
    "id": "mixroom.super_saw",
    "name": "Super Saw Lead",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 6200.0,
    "attackMs": 4.0,
    "releaseMs": 180.0,
    "drive": 0.22,
  },
  {
    "id": "mixroom.gentle_pluck",
    "name": "Gentle Pluck",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 4800.0,
    "attackMs": 2.0,
    "releaseMs": 130.0,
    "drive": 0.08,
  },
  {
    "id": "mixroom.sub_bass",
    "name": "Sub Bass",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 900.0,
    "attackMs": 3.0,
    "releaseMs": 200.0,
    "drive": 0.24,
  },
  {
    "id": "mixroom.analog_brass",
    "name": "Analog Brass",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 2600.0,
    "attackMs": 25.0,
    "releaseMs": 300.0,
    "drive": 0.14,
  },
  {
    "id": "mixroom.drum_acoustic_easy",
    "name": "Easy Acoustic Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 2300.0,
    "attackMs": 0.0,
    "releaseMs": 120.0,
    "drive": 0.18,
  },
  {
    "id": "mixroom.drum_808_starter",
    "name": "808 Starter Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 1100.0,
    "attackMs": 0.0,
    "releaseMs": 190.0,
    "drive": 0.36,
  },
  {
    "id": "mixroom.drum_lofi",
    "name": "Lo-Fi Beat Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 1700.0,
    "attackMs": 1.0,
    "releaseMs": 150.0,
    "drive": 0.28,
  },
  {
    "id": "mixroom.drum_house",
    "name": "House Beat Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 2600.0,
    "attackMs": 0.0,
    "releaseMs": 95.0,
    "drive": 0.24,
  },
  {
    "id": "mixroom.night_bell",
    "name": "Night Bell",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 5600.0,
    "attackMs": 1.0,
    "releaseMs": 540.0,
    "drive": 0.06,
  },
  {
    "id": "mixroom.fm_keys",
    "name": "FM Keys",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 4100.0,
    "attackMs": 5.0,
    "releaseMs": 340.0,
    "drive": 0.07,
  },
  {
    "id": "mixroom.vintage_strings",
    "name": "Vintage Strings",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 2400.0,
    "attackMs": 32.0,
    "releaseMs": 640.0,
    "drive": 0.08,
  },
  {
    "id": "mixroom.neo_brass",
    "name": "Neo Brass",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 3100.0,
    "attackMs": 16.0,
    "releaseMs": 250.0,
    "drive": 0.15,
  },
  {
    "id": "mixroom.reese_bass",
    "name": "Reese Bass",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 1300.0,
    "attackMs": 4.0,
    "releaseMs": 200.0,
    "drive": 0.26,
  },
  {
    "id": "mixroom.air_pluck",
    "name": "Air Pluck",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 5200.0,
    "attackMs": 1.0,
    "releaseMs": 210.0,
    "drive": 0.08,
  },
  {
    "id": "mixroom.cinematic_pad",
    "name": "Cinematic Pad",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 1900.0,
    "attackMs": 95.0,
    "releaseMs": 760.0,
    "drive": 0.05,
  },
  {
    "id": "mixroom.velvet_ep",
    "name": "Velvet EP",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 3700.0,
    "attackMs": 7.0,
    "releaseMs": 380.0,
    "drive": 0.07,
    "tone": 0.66,
    "transient": 0.18,
    "noise": 0.02,
  },
  {
    "id": "mixroom.house_organ",
    "name": "House Organ",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 3400.0,
    "attackMs": 0.0,
    "releaseMs": 210.0,
    "drive": 0.11,
    "tone": 0.62,
    "stereoWidth": 0.1,
  },
  {
    "id": "mixroom.glass_pluck",
    "name": "Glass Pluck",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 5600.0,
    "attackMs": 1.0,
    "releaseMs": 170.0,
    "drive": 0.09,
    "tone": 0.74,
    "transient": 0.24,
    "noise": 0.03,
  },
  {
    "id": "mixroom.neon_lead",
    "name": "Neon Lead",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 6400.0,
    "attackMs": 3.0,
    "releaseMs": 210.0,
    "drive": 0.24,
    "detune": 0.012,
    "stereoWidth": 0.18,
    "tone": 0.78,
  },
  {
    "id": "mixroom.mellow_sub",
    "name": "Mellow Sub",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 980.0,
    "attackMs": 4.0,
    "releaseMs": 260.0,
    "drive": 0.19,
    "tone": 0.42,
    "transient": 0.1,
  },
  {
    "id": "mixroom.wide_air_pad",
    "name": "Wide Air Pad",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 3.0,
    "cutoffHz": 2300.0,
    "attackMs": 74.0,
    "releaseMs": 700.0,
    "drive": 0.04,
    "detune": 0.02,
    "stereoWidth": 0.3,
    "tone": 0.5,
    "noise": 0.02,
  },
  {
    "id": "mixroom.horn_stack",
    "name": "Horn Stack",
    "category": "instrument",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 1.0,
    "cutoffHz": 2900.0,
    "attackMs": 20.0,
    "releaseMs": 280.0,
    "drive": 0.16,
    "tone": 0.58,
    "stereoWidth": 0.12,
  },
  {
    "id": "mixroom.drum_trap",
    "name": "Trap Starter Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 0.0,
    "cutoffHz": 2100.0,
    "attackMs": 0.0,
    "releaseMs": 110.0,
    "drive": 0.32,
  },
  {
    "id": "mixroom.drum_breakbeat",
    "name": "Breakbeat Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 2400.0,
    "attackMs": 0.0,
    "releaseMs": 130.0,
    "drive": 0.26,
  },
  {
    "id": "mixroom.drum_dnb",
    "name": "DNB Starter Kit",
    "category": "drum",
    "sourceProject": "Mixroom Stock",
    "sourceLicense": "Built-in",
    "oscillator": 2.0,
    "cutoffHz": 2600.0,
    "attackMs": 0.0,
    "releaseMs": 105.0,
    "drive": 0.33,
  },
];

enum _FallbackInstrumentFamily {
  basic,
  bass,
  pad,
  lead,
  pluck,
  keys,
  brass,
  wavetable,
  harmonic,
  drum,
}

class _FallbackInstrumentPreset {
  final _FallbackInstrumentFamily family;
  final int oscillator;
  final double cutoffHz;
  final double attackMs;
  final double releaseMs;
  final double drive;
  final double outputGain;
  final double detune;
  final double stereoWidth;
  final double tone;
  final double transient;
  final double pitchDropSemitones;
  final double noise;

  const _FallbackInstrumentPreset({
    this.family = _FallbackInstrumentFamily.basic,
    this.oscillator = 1,
    this.cutoffHz = 3200.0,
    this.attackMs = 18.0,
    this.releaseMs = 180.0,
    this.drive = 0.08,
    this.outputGain = 0.36,
    this.detune = 0.0,
    this.stereoWidth = 0.12,
    this.tone = 0.55,
    this.transient = 0.08,
    this.pitchDropSemitones = 0.0,
    this.noise = 0.02,
  });

  _FallbackInstrumentPreset copyWith({
    _FallbackInstrumentFamily? family,
    int? oscillator,
    double? cutoffHz,
    double? attackMs,
    double? releaseMs,
    double? drive,
    double? outputGain,
    double? detune,
    double? stereoWidth,
    double? tone,
    double? transient,
    double? pitchDropSemitones,
    double? noise,
  }) {
    return _FallbackInstrumentPreset(
      family: family ?? this.family,
      oscillator: oscillator ?? this.oscillator,
      cutoffHz: cutoffHz ?? this.cutoffHz,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      drive: drive ?? this.drive,
      outputGain: outputGain ?? this.outputGain,
      detune: detune ?? this.detune,
      stereoWidth: stereoWidth ?? this.stereoWidth,
      tone: tone ?? this.tone,
      transient: transient ?? this.transient,
      pitchDropSemitones: pitchDropSemitones ?? this.pitchDropSemitones,
      noise: noise ?? this.noise,
    );
  }
}

class _FallbackNoteState {
  double phaseA;
  double phaseB;
  double low = 0.0;
  double aux = 0.0;
  final int seed;

  _FallbackNoteState({
    required this.phaseA,
    required this.phaseB,
    required this.seed,
  });
}

const _FallbackInstrumentPreset _kFallbackDefaultPreset =
    _FallbackInstrumentPreset();

const Map<String, _FallbackInstrumentPreset> _kFallbackInstrumentPresets = {
  'mixroom.basic_synth': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.basic,
    oscillator: 1,
    cutoffHz: 3200.0,
    attackMs: 18.0,
    releaseMs: 180.0,
    drive: 0.08,
    outputGain: 0.36,
    detune: 0.002,
    stereoWidth: 0.12,
    tone: 0.56,
    transient: 0.08,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.bass_mono': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.bass,
    oscillator: 2,
    cutoffHz: 1200.0,
    attackMs: 8.0,
    releaseMs: 220.0,
    drive: 0.28,
    outputGain: 0.34,
    detune: 0.001,
    stereoWidth: 0.04,
    tone: 0.52,
    transient: 0.18,
    pitchDropSemitones: 4.0,
    noise: 0.04,
  ),
  'mixroom.soft_pad': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pad,
    oscillator: 3,
    cutoffHz: 2100.0,
    attackMs: 80.0,
    releaseMs: 620.0,
    drive: 0.02,
    outputGain: 0.31,
    detune: 0.012,
    stereoWidth: 0.28,
    tone: 0.47,
    transient: 0.04,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.figbug_wavetable': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.wavetable,
    oscillator: 1,
    cutoffHz: 5200.0,
    attackMs: 6.0,
    releaseMs: 240.0,
    drive: 0.18,
    outputGain: 0.33,
    detune: 0.006,
    stereoWidth: 0.16,
    tone: 0.72,
    transient: 0.14,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.sarah_harmonic': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.harmonic,
    oscillator: 3,
    cutoffHz: 2800.0,
    attackMs: 34.0,
    releaseMs: 540.0,
    drive: 0.10,
    outputGain: 0.32,
    detune: 0.008,
    stereoWidth: 0.20,
    tone: 0.54,
    transient: 0.08,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.vanilla_poly': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.keys,
    oscillator: 0,
    cutoffHz: 3600.0,
    attackMs: 12.0,
    releaseMs: 260.0,
    drive: 0.05,
    outputGain: 0.33,
    detune: 0.004,
    stereoWidth: 0.13,
    tone: 0.58,
    transient: 0.10,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.duck_synth': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.bass,
    oscillator: 2,
    cutoffHz: 1600.0,
    attackMs: 2.0,
    releaseMs: 140.0,
    drive: 0.26,
    outputGain: 0.35,
    detune: 0.002,
    stereoWidth: 0.06,
    tone: 0.62,
    transient: 0.20,
    pitchDropSemitones: 8.0,
    noise: 0.03,
  ),
  'mixroom.chow_kick': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 0,
    cutoffHz: 900.0,
    attackMs: 0.0,
    releaseMs: 90.0,
    drive: 0.42,
    outputGain: 0.42,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.52,
    transient: 0.40,
    pitchDropSemitones: 16.0,
    noise: 0.14,
  ),
  'mixroom.warm_keys': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.keys,
    oscillator: 0,
    cutoffHz: 3000.0,
    attackMs: 14.0,
    releaseMs: 320.0,
    drive: 0.06,
    outputGain: 0.32,
    detune: 0.005,
    stereoWidth: 0.12,
    tone: 0.52,
    transient: 0.12,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.super_saw': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.lead,
    oscillator: 1,
    cutoffHz: 6200.0,
    attackMs: 4.0,
    releaseMs: 180.0,
    drive: 0.22,
    outputGain: 0.34,
    detune: 0.010,
    stereoWidth: 0.20,
    tone: 0.75,
    transient: 0.11,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.gentle_pluck': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pluck,
    oscillator: 3,
    cutoffHz: 4800.0,
    attackMs: 2.0,
    releaseMs: 130.0,
    drive: 0.08,
    outputGain: 0.33,
    detune: 0.004,
    stereoWidth: 0.11,
    tone: 0.68,
    transient: 0.24,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.sub_bass': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.bass,
    oscillator: 2,
    cutoffHz: 900.0,
    attackMs: 3.0,
    releaseMs: 200.0,
    drive: 0.24,
    outputGain: 0.35,
    detune: 0.001,
    stereoWidth: 0.03,
    tone: 0.46,
    transient: 0.12,
    pitchDropSemitones: 5.0,
    noise: 0.03,
  ),
  'mixroom.analog_brass': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.brass,
    oscillator: 1,
    cutoffHz: 2600.0,
    attackMs: 25.0,
    releaseMs: 300.0,
    drive: 0.14,
    outputGain: 0.33,
    detune: 0.003,
    stereoWidth: 0.12,
    tone: 0.55,
    transient: 0.08,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.drum_acoustic_easy': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 1,
    cutoffHz: 2300.0,
    attackMs: 0.0,
    releaseMs: 120.0,
    drive: 0.18,
    outputGain: 0.41,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.52,
    transient: 0.26,
    pitchDropSemitones: 10.0,
    noise: 0.15,
  ),
  'mixroom.drum_808_starter': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 0,
    cutoffHz: 1100.0,
    attackMs: 0.0,
    releaseMs: 190.0,
    drive: 0.36,
    outputGain: 0.44,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.60,
    transient: 0.35,
    pitchDropSemitones: 24.0,
    noise: 0.18,
  ),
  'mixroom.drum_lofi': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 3,
    cutoffHz: 1700.0,
    attackMs: 1.0,
    releaseMs: 150.0,
    drive: 0.28,
    outputGain: 0.41,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.45,
    transient: 0.20,
    pitchDropSemitones: 12.0,
    noise: 0.20,
  ),
  'mixroom.drum_house': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 1,
    cutoffHz: 2600.0,
    attackMs: 0.0,
    releaseMs: 95.0,
    drive: 0.24,
    outputGain: 0.42,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.58,
    transient: 0.28,
    pitchDropSemitones: 14.0,
    noise: 0.17,
  ),
  'mixroom.night_bell': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.harmonic,
    oscillator: 0,
    cutoffHz: 5600.0,
    attackMs: 1.0,
    releaseMs: 540.0,
    drive: 0.06,
    outputGain: 0.30,
    detune: 0.002,
    stereoWidth: 0.22,
    tone: 0.76,
    transient: 0.16,
    pitchDropSemitones: 0.0,
    noise: 0.01,
  ),
  'mixroom.fm_keys': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.harmonic,
    oscillator: 0,
    cutoffHz: 4100.0,
    attackMs: 5.0,
    releaseMs: 340.0,
    drive: 0.07,
    outputGain: 0.32,
    detune: 0.004,
    stereoWidth: 0.14,
    tone: 0.66,
    transient: 0.14,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.vintage_strings': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pad,
    oscillator: 1,
    cutoffHz: 2400.0,
    attackMs: 32.0,
    releaseMs: 640.0,
    drive: 0.08,
    outputGain: 0.31,
    detune: 0.015,
    stereoWidth: 0.24,
    tone: 0.50,
    transient: 0.07,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.neo_brass': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.brass,
    oscillator: 1,
    cutoffHz: 3100.0,
    attackMs: 16.0,
    releaseMs: 250.0,
    drive: 0.15,
    outputGain: 0.33,
    detune: 0.004,
    stereoWidth: 0.14,
    tone: 0.61,
    transient: 0.08,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.reese_bass': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.bass,
    oscillator: 1,
    cutoffHz: 1300.0,
    attackMs: 4.0,
    releaseMs: 200.0,
    drive: 0.26,
    outputGain: 0.35,
    detune: 0.015,
    stereoWidth: 0.08,
    tone: 0.57,
    transient: 0.16,
    pitchDropSemitones: 5.0,
    noise: 0.05,
  ),
  'mixroom.air_pluck': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pluck,
    oscillator: 3,
    cutoffHz: 5200.0,
    attackMs: 1.0,
    releaseMs: 210.0,
    drive: 0.08,
    outputGain: 0.33,
    detune: 0.008,
    stereoWidth: 0.14,
    tone: 0.72,
    transient: 0.20,
    pitchDropSemitones: 0.0,
    noise: 0.05,
  ),
  'mixroom.cinematic_pad': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pad,
    oscillator: 3,
    cutoffHz: 1900.0,
    attackMs: 95.0,
    releaseMs: 760.0,
    drive: 0.05,
    outputGain: 0.30,
    detune: 0.018,
    stereoWidth: 0.30,
    tone: 0.44,
    transient: 0.05,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.velvet_ep': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.keys,
    oscillator: 0,
    cutoffHz: 3700.0,
    attackMs: 7.0,
    releaseMs: 380.0,
    drive: 0.07,
    outputGain: 0.32,
    detune: 0.005,
    stereoWidth: 0.16,
    tone: 0.66,
    transient: 0.18,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.house_organ': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.keys,
    oscillator: 2,
    cutoffHz: 3400.0,
    attackMs: 0.0,
    releaseMs: 210.0,
    drive: 0.11,
    outputGain: 0.33,
    detune: 0.003,
    stereoWidth: 0.10,
    tone: 0.62,
    transient: 0.12,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.glass_pluck': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pluck,
    oscillator: 3,
    cutoffHz: 5600.0,
    attackMs: 1.0,
    releaseMs: 170.0,
    drive: 0.09,
    outputGain: 0.33,
    detune: 0.007,
    stereoWidth: 0.14,
    tone: 0.74,
    transient: 0.24,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.neon_lead': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.lead,
    oscillator: 1,
    cutoffHz: 6400.0,
    attackMs: 3.0,
    releaseMs: 210.0,
    drive: 0.24,
    outputGain: 0.34,
    detune: 0.012,
    stereoWidth: 0.18,
    tone: 0.78,
    transient: 0.13,
    pitchDropSemitones: 0.0,
    noise: 0.03,
  ),
  'mixroom.mellow_sub': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.bass,
    oscillator: 2,
    cutoffHz: 980.0,
    attackMs: 4.0,
    releaseMs: 260.0,
    drive: 0.19,
    outputGain: 0.35,
    detune: 0.001,
    stereoWidth: 0.04,
    tone: 0.42,
    transient: 0.10,
    pitchDropSemitones: 3.0,
    noise: 0.02,
  ),
  'mixroom.wide_air_pad': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.pad,
    oscillator: 3,
    cutoffHz: 2300.0,
    attackMs: 74.0,
    releaseMs: 700.0,
    drive: 0.04,
    outputGain: 0.30,
    detune: 0.020,
    stereoWidth: 0.30,
    tone: 0.50,
    transient: 0.05,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.horn_stack': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.brass,
    oscillator: 1,
    cutoffHz: 2900.0,
    attackMs: 20.0,
    releaseMs: 280.0,
    drive: 0.16,
    outputGain: 0.33,
    detune: 0.004,
    stereoWidth: 0.12,
    tone: 0.58,
    transient: 0.09,
    pitchDropSemitones: 0.0,
    noise: 0.02,
  ),
  'mixroom.drum_trap': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 0,
    cutoffHz: 2100.0,
    attackMs: 0.0,
    releaseMs: 110.0,
    drive: 0.32,
    outputGain: 0.42,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.62,
    transient: 0.32,
    pitchDropSemitones: 18.0,
    noise: 0.20,
  ),
  'mixroom.drum_breakbeat': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 2,
    cutoffHz: 2400.0,
    attackMs: 0.0,
    releaseMs: 130.0,
    drive: 0.26,
    outputGain: 0.42,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.55,
    transient: 0.25,
    pitchDropSemitones: 12.0,
    noise: 0.18,
  ),
  'mixroom.drum_dnb': _FallbackInstrumentPreset(
    family: _FallbackInstrumentFamily.drum,
    oscillator: 2,
    cutoffHz: 2600.0,
    attackMs: 0.0,
    releaseMs: 105.0,
    drive: 0.33,
    outputGain: 0.43,
    detune: 0.0,
    stereoWidth: 0.0,
    tone: 0.67,
    transient: 0.34,
    pitchDropSemitones: 20.0,
    noise: 0.22,
  ),
};

double _clampDouble(num value, double min, double max) =>
    value.toDouble().clamp(min, max).toDouble();

double _wrapUnitPhase(double phase) {
  var wrapped = phase - phase.floorToDouble();
  if (wrapped < 0.0) wrapped += 1.0;
  return wrapped;
}

double _waveFromType(int type, double phase) {
  final p = _wrapUnitPhase(phase);
  switch (type) {
    case 0:
      return math.sin(2.0 * math.pi * p);
    case 1:
      return (2.0 * p) - 1.0;
    case 2:
      return p < 0.5 ? 1.0 : -1.0;
    default:
      return p < 0.5 ? (-1.0 + 4.0 * p) : (3.0 - 4.0 * p);
  }
}

double _hashNoise(int seed) {
  var x = (seed * 747796405 + 2891336453) & 0xFFFFFFFF;
  x ^= (x >> 16);
  x = (x * 2246822519) & 0xFFFFFFFF;
  x ^= (x >> 13);
  x = (x * 3266489917) & 0xFFFFFFFF;
  x ^= (x >> 16);
  final n01 = (x & 0x00ffffff) / 0x01000000;
  return (n01 * 2.0) - 1.0;
}

double _noiseForSample(int seed, int sampleIndex) {
  return _hashNoise(seed + sampleIndex * 17);
}

double _lowPassSample({
  required _FallbackNoteState state,
  required bool auxiliaryState,
  required double input,
  required double cutoffHz,
  required double sampleRate,
}) {
  final clampedCutoff = _clampDouble(cutoffHz, 50.0, sampleRate * 0.45);
  final alpha = 1.0 - math.exp((-2.0 * math.pi * clampedCutoff) / sampleRate);
  if (auxiliaryState) {
    state.aux += alpha * (input - state.aux);
    return state.aux;
  }
  state.low += alpha * (input - state.low);
  return state.low;
}

double _highPassSample({
  required _FallbackNoteState state,
  required double input,
  required double cutoffHz,
  required double sampleRate,
}) {
  final lp = _lowPassSample(
    state: state,
    auxiliaryState: true,
    input: input,
    cutoffHz: cutoffHz,
    sampleRate: sampleRate,
  );
  return input - lp;
}

void _advancePhase({
  required _FallbackNoteState state,
  required bool primary,
  required double frequencyHz,
  required double sampleRate,
}) {
  final next =
      (primary ? state.phaseA : state.phaseB) + (frequencyHz / sampleRate);
  final wrapped = _wrapUnitPhase(next);
  if (primary) {
    state.phaseA = wrapped;
  } else {
    state.phaseB = wrapped;
  }
}

_FallbackInstrumentPreset _fallbackPresetFromKeywords(String text) {
  if (text.contains('drum') || text.contains('kick') || text.contains('808')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.drum,
      oscillator: 0,
      cutoffHz: 2000.0,
      attackMs: 0.0,
      releaseMs: 120.0,
      drive: 0.30,
      outputGain: 0.42,
      detune: 0.0,
      stereoWidth: 0.0,
      tone: 0.58,
      transient: 0.30,
      pitchDropSemitones: 16.0,
      noise: 0.20,
    );
  }
  if (text.contains('bass')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.bass,
      oscillator: 2,
      cutoffHz: 1200.0,
      attackMs: 6.0,
      releaseMs: 220.0,
      drive: 0.24,
      outputGain: 0.34,
      detune: 0.004,
      stereoWidth: 0.06,
      tone: 0.52,
      transient: 0.16,
      pitchDropSemitones: 6.0,
      noise: 0.04,
    );
  }
  if (text.contains('pad') || text.contains('string')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.pad,
      oscillator: 3,
      cutoffHz: 2200.0,
      attackMs: 80.0,
      releaseMs: 620.0,
      drive: 0.05,
      outputGain: 0.30,
      detune: 0.012,
      stereoWidth: 0.24,
      tone: 0.48,
      transient: 0.06,
      pitchDropSemitones: 0.0,
      noise: 0.03,
    );
  }
  if (text.contains('pluck') || text.contains('bell')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.pluck,
      oscillator: 3,
      cutoffHz: 5100.0,
      attackMs: 2.0,
      releaseMs: 190.0,
      drive: 0.08,
      outputGain: 0.33,
      detune: 0.005,
      stereoWidth: 0.13,
      tone: 0.74,
      transient: 0.20,
      pitchDropSemitones: 0.0,
      noise: 0.03,
    );
  }
  if (text.contains('brass') || text.contains('horn')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.brass,
      oscillator: 1,
      cutoffHz: 2800.0,
      attackMs: 18.0,
      releaseMs: 290.0,
      drive: 0.14,
      outputGain: 0.33,
      detune: 0.004,
      stereoWidth: 0.13,
      tone: 0.56,
      transient: 0.08,
      pitchDropSemitones: 0.0,
      noise: 0.02,
    );
  }
  if (text.contains('key') ||
      text.contains('piano') ||
      text.contains('organ')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.keys,
      oscillator: 0,
      cutoffHz: 3300.0,
      attackMs: 10.0,
      releaseMs: 280.0,
      drive: 0.06,
      outputGain: 0.32,
      detune: 0.004,
      stereoWidth: 0.12,
      tone: 0.58,
      transient: 0.12,
      pitchDropSemitones: 0.0,
      noise: 0.02,
    );
  }
  if (text.contains('wave')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.wavetable,
      oscillator: 1,
      cutoffHz: 4800.0,
      attackMs: 6.0,
      releaseMs: 240.0,
      drive: 0.16,
      outputGain: 0.33,
      detune: 0.006,
      stereoWidth: 0.14,
      tone: 0.68,
      transient: 0.12,
      pitchDropSemitones: 0.0,
      noise: 0.03,
    );
  }
  if (text.contains('harmonic') || text.contains('fm')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.harmonic,
      oscillator: 0,
      cutoffHz: 3400.0,
      attackMs: 12.0,
      releaseMs: 360.0,
      drive: 0.09,
      outputGain: 0.32,
      detune: 0.005,
      stereoWidth: 0.15,
      tone: 0.62,
      transient: 0.12,
      pitchDropSemitones: 0.0,
      noise: 0.02,
    );
  }
  if (text.contains('lead') || text.contains('saw')) {
    return const _FallbackInstrumentPreset(
      family: _FallbackInstrumentFamily.lead,
      oscillator: 1,
      cutoffHz: 5600.0,
      attackMs: 4.0,
      releaseMs: 200.0,
      drive: 0.18,
      outputGain: 0.34,
      detune: 0.008,
      stereoWidth: 0.16,
      tone: 0.74,
      transient: 0.10,
      pitchDropSemitones: 0.0,
      noise: 0.03,
    );
  }
  return _kFallbackDefaultPreset;
}

_FallbackInstrumentPreset _fallbackPresetForInstrument({
  required String instrumentId,
  required String instrumentName,
  required Map<String, double> params,
}) {
  final id = instrumentId.trim().toLowerCase();
  final text = '$id ${instrumentName.toLowerCase()}';
  var preset =
      _kFallbackInstrumentPresets[id] ?? _fallbackPresetFromKeywords(text);

  double getParam(String key, double fallback, double min, double max) {
    final raw = params[key];
    if (raw == null || !raw.isFinite) return fallback;
    return _clampDouble(raw, min, max);
  }

  final oscillator =
      getParam('oscillator', preset.oscillator.toDouble(), 0.0, 3.0)
          .round()
          .clamp(0, 3);

  preset = preset.copyWith(
    oscillator: oscillator,
    cutoffHz: getParam('cutoffHz', preset.cutoffHz, 200.0, 16000.0),
    attackMs: getParam('attackMs', preset.attackMs, 0.0, 1000.0),
    releaseMs: getParam('releaseMs', preset.releaseMs, 20.0, 2400.0),
    drive: getParam('drive', preset.drive, 0.0, 1.0),
    outputGain: getParam('outputGain', preset.outputGain, 0.15, 0.75),
    detune: getParam('detune', preset.detune, 0.0, 0.03),
    stereoWidth: getParam('stereoWidth', preset.stereoWidth, 0.0, 0.45),
    tone: getParam('tone', preset.tone, 0.0, 1.0),
    transient: getParam('transient', preset.transient, 0.0, 1.0),
    pitchDropSemitones:
        getParam('pitchDropSemitones', preset.pitchDropSemitones, 0.0, 36.0),
    noise: getParam('noise', preset.noise, 0.0, 0.45),
  );

  return preset;
}

double _renderFallbackRawSample({
  required _FallbackInstrumentPreset preset,
  required _FallbackNoteState state,
  required int pitch,
  required int noteSampleIndex,
  required double frequencyHz,
  required double noteProgress,
  required double envelope,
  required double sampleRate,
}) {
  switch (preset.family) {
    case _FallbackInstrumentFamily.bass:
      {
        final body = _waveFromType(2, state.phaseA) * 0.52;
        final sub = _waveFromType(0, state.phaseB) * 0.66;
        final growl = _waveFromType(1, state.phaseA) * 0.20;
        final transient = (0.04 + preset.transient * 0.22) *
            math.exp(-22.0 * noteProgress) *
            _noiseForSample(state.seed, noteSampleIndex);
        final dynamicCutoff = preset.cutoffHz *
            _clampDouble(1.0 - noteProgress * 0.55, 0.45, 1.05);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: body + sub + growl + transient,
          cutoffHz: dynamicCutoff,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 0.5,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.pad:
      {
        final det = _clampDouble(preset.detune + 0.008, 0.001, 0.03);
        final lfo =
            math.sin(2.0 * math.pi * noteSampleIndex / sampleRate * 0.23);
        final left = _waveFromType(0, state.phaseA);
        final right = _waveFromType(3, state.phaseB);
        final shimmer = _waveFromType(1, state.phaseA + 0.25) * 0.18;
        final noise =
            preset.noise * 0.5 * _noiseForSample(state.seed, noteSampleIndex);
        final openAmount = _clampDouble(
          0.7 + (1.0 - noteProgress) * 0.5 + lfo * 0.15,
          0.5,
          1.35,
        );
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: left * 0.48 + right * 0.4 + shimmer + noise,
          cutoffHz: preset.cutoffHz * openAmount,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz * (1.0 - det),
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * (1.0 + det),
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.lead:
      {
        final vibrato = 1.0 +
            math.sin(2.0 * math.pi * noteSampleIndex / sampleRate * 5.1) *
                (0.001 + 0.002 * envelope);
        final saw = _waveFromType(1, state.phaseA);
        final pulse = _waveFromType(2, state.phaseB) * 0.42;
        final edge = _waveFromType(3, state.phaseA * 1.99) * 0.18;
        final noise = preset.noise *
            0.35 *
            math.exp(-12.0 * noteProgress) *
            _noiseForSample(state.seed, noteSampleIndex);
        final cutoffOpen = _clampDouble(1.2 - noteProgress * 0.35, 0.8, 1.55);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: saw * 0.68 + pulse + edge + noise,
          cutoffHz: preset.cutoffHz * cutoffOpen,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz * vibrato,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 1.01 * vibrato,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.pluck:
      {
        final decay = math.exp(-6.5 * noteProgress);
        final tri = _waveFromType(3, state.phaseA) * 0.62;
        final tone = _waveFromType(0, state.phaseB) * 0.36;
        final pick = (preset.transient + 0.12) *
            math.exp(-28.0 * noteProgress) *
            _noiseForSample(state.seed, noteSampleIndex);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: (tri + tone) * decay + pick,
          cutoffHz: preset.cutoffHz * (1.1 + (1.0 - noteProgress) * 0.25),
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 2.0,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.keys:
      {
        final style = preset.oscillator.clamp(0, 3).toInt();
        final keyOpen = _clampDouble(
          0.75 + preset.tone * 0.75 + (1.0 - noteProgress) * 0.2,
          0.6,
          1.7,
        );

        if (style == 2) {
          final fundamental = _waveFromType(2, state.phaseA) * 0.48;
          final octave = _waveFromType(2, state.phaseB) * 0.28;
          final twelfth = _waveFromType(2, state.phaseB * 1.5) * 0.16;
          final chorus = _waveFromType(1, state.phaseB + 0.13) * 0.11;
          final click = (0.04 + preset.transient * 0.18) *
              math.exp(-52.0 * noteProgress) *
              _noiseForSample(state.seed + 31, noteSampleIndex);
          final raw = _lowPassSample(
            state: state,
            auxiliaryState: false,
            input: fundamental + octave + twelfth + chorus + click,
            cutoffHz: preset.cutoffHz * keyOpen,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: true,
            frequencyHz: frequencyHz,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: false,
            frequencyHz: frequencyHz * 2.0,
            sampleRate: sampleRate,
          );
          return raw;
        }

        final inharmonic =
            1.0 + _clampDouble(frequencyHz * 0.0000005, 0.0, 0.005);
        final hammer = (0.09 + preset.transient * 0.30) *
            math.exp(-36.0 * noteProgress) *
            _noiseForSample(state.seed + 21, noteSampleIndex);
        final body = _waveFromType(0, state.phaseA) * 0.58;
        final second = _waveFromType(0, state.phaseB * inharmonic) * 0.26;
        final third =
            _waveFromType(style == 1 ? 1 : 0, state.phaseB * 1.5 * inharmonic) *
                0.15;
        final tine = _waveFromType(
                style == 3 ? 3 : 0, state.phaseB * (2.4 + style * 0.25)) *
            0.11;
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: body + second + third + tine + hammer,
          cutoffHz: preset.cutoffHz * keyOpen,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 2.0,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.brass:
      {
        final style = preset.oscillator.clamp(0, 3).toInt();
        final vibratoDepth = 0.0011 + envelope * (0.001 + style * 0.0003);
        final vibratoRate = 4.8 + style * 0.5;
        final vibrato = 1.0 +
            math.sin(2.0 *
                    math.pi *
                    noteSampleIndex /
                    sampleRate *
                    vibratoRate) *
                vibratoDepth;
        final saw = _waveFromType(1, state.phaseA) * 0.48;
        final pulse = _waveFromType(2, state.phaseB) * 0.35;
        final upper = _waveFromType(style >= 2 ? 1 : 0, state.phaseA * 2.0) *
            (0.15 + 0.03 * style);
        final breath = (0.02 + preset.noise * 0.55) *
            math.exp(-7.0 * noteProgress) *
            _noiseForSample(state.seed + 41, noteSampleIndex);
        final t = noteSampleIndex / sampleRate;
        final formantA =
            math.sin(2.0 * math.pi * (760.0 + style * 110.0) * t) * 0.07;
        final formantB =
            math.sin(2.0 * math.pi * (1320.0 + style * 140.0) * t) * 0.05;
        final dynamicCutoff = preset.cutoffHz *
            _clampDouble(
                0.85 + envelope * 0.65 - noteProgress * 0.12, 0.65, 1.6);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: saw + pulse + upper + breath + formantA + formantB,
          cutoffHz: dynamicCutoff,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz * vibrato,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 0.994 * vibrato,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.wavetable:
      {
        final modLfo =
            math.sin(2.0 * math.pi * noteSampleIndex / sampleRate * 0.35);
        final pd = _wrapUnitPhase(
          state.phaseA + 0.18 * math.sin(2.0 * math.pi * state.phaseB + modLfo),
        );
        final main = math.sin(2.0 * math.pi * pd);
        final upper = math.sin(2.0 * math.pi * pd * 2.0) * 0.33;
        final sparkle = _waveFromType(1, pd * 1.5) * 0.22;
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: main + upper + sparkle,
          cutoffHz: preset.cutoffHz * (1.1 - noteProgress * 0.25),
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: 0.27,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.harmonic:
      {
        final style = preset.oscillator.clamp(0, 3).toInt();
        final modRatio = style <= 1 ? 2.0 : 3.0;
        final modDepth = 0.05 + preset.tone * 0.13 + style * 0.02;
        final mod = math.sin(2.0 * math.pi * state.phaseB * modRatio);
        final carrier = _wrapUnitPhase(state.phaseA + mod * modDepth);
        final p = 2.0 * math.pi * carrier;
        final body = math.sin(p) * 0.50;
        final even = math.sin(2.0 * p) * 0.26;
        final odd = math.sin(3.0 * p) * 0.18;
        final air = math.sin(5.0 * p) * 0.10;
        final sheen = _waveFromType(style == 3 ? 1 : 3, state.phaseB) * 0.12;
        final transient = (0.02 + preset.transient * 0.12) *
            math.exp(-24.0 * noteProgress) *
            _noiseForSample(state.seed + 57, noteSampleIndex);
        final dynamicCutoff =
            preset.cutoffHz * (0.9 + (1.0 - noteProgress) * 0.35);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: body + even + odd + air + sheen + transient,
          cutoffHz: dynamicCutoff,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 0.5,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.drum:
      {
        final style = preset.oscillator.clamp(0, 3).toInt();
        if (pitch <= 36) {
          final extraDrop = style == 0
              ? 22.0
              : style == 1
                  ? 12.0
                  : style == 2
                      ? 16.0
                      : 14.0;
          final curve = style == 0 ? 1.35 : 1.0;
          final dropSemis =
              _clampDouble(preset.pitchDropSemitones + extraDrop, 0.0, 36.0);
          final dropProgress = math.pow(1.0 - noteProgress, curve).toDouble();
          final ratio = math.pow(
            2.0,
            -(dropSemis * dropProgress) / 12.0,
          );
          final tunedFreq = _clampDouble(
            frequencyHz * ratio.toDouble(),
            24.0,
            1400.0,
          );
          final body =
              math.sin(2.0 * math.pi * state.phaseA) * (0.80 + 0.06 * style);
          final sub = math.sin(2.0 * math.pi * state.phaseB) *
              (style == 0 ? 0.36 : 0.22);
          final click = (0.07 + preset.transient * (0.34 + style * 0.07)) *
              math.exp(-40.0 * noteProgress) *
              _noiseForSample(state.seed + 7, noteSampleIndex);
          final beater = ((style == 1 || style == 2) ? 0.08 : 0.03) *
              math.exp(-58.0 * noteProgress) *
              math.sin(2.0 * math.pi * state.phaseB * 10.0);
          final raw = _lowPassSample(
            state: state,
            auxiliaryState: false,
            input: body + sub + click + beater,
            cutoffHz: preset.cutoffHz * (0.75 + (1.0 - noteProgress) * 0.9),
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: true,
            frequencyHz: tunedFreq,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: false,
            frequencyHz: tunedFreq * 0.5,
            sampleRate: sampleRate,
          );
          return raw;
        }
        if (pitch <= 44) {
          final toneMult = style == 0
              ? 1.25
              : style == 1
                  ? 1.6
                  : style == 2
                      ? 1.85
                      : 1.45;
          final toneA = math.sin(2.0 * math.pi * state.phaseA) *
              math.exp(-8.0 * noteProgress) *
              0.36;
          final toneB = math.sin(2.0 * math.pi * state.phaseB) *
              math.exp(-10.0 * noteProgress) *
              0.20;
          final noise = _noiseForSample(state.seed + 17, noteSampleIndex) *
              math.exp(-(9.0 + style * 1.2) * noteProgress) *
              (0.55 + 0.16 * style + preset.noise * 0.55);
          final raw = _highPassSample(
            state: state,
            input: toneA + toneB + noise,
            cutoffHz: 780.0 + style * 140.0,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: true,
            frequencyHz: frequencyHz * toneMult,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: false,
            frequencyHz: frequencyHz * toneMult * 1.72,
            sampleRate: sampleRate,
          );
          return raw;
        }
        if (pitch <= 52) {
          if (style == 1) {
            final rimTone = math.sin(2.0 * math.pi * state.phaseA) *
                math.exp(-22.0 * noteProgress) *
                0.34;
            final rimSnap = _noiseForSample(state.seed + 29, noteSampleIndex) *
                math.exp(-26.0 * noteProgress) *
                0.28;
            _advancePhase(
              state: state,
              primary: true,
              frequencyHz: frequencyHz * 3.2,
              sampleRate: sampleRate,
            );
            return rimTone + rimSnap;
          }

          final burst0 = math.exp(-95.0 * math.pow(noteProgress - 0.028, 2.0));
          final burst1 = math.exp(-125.0 * math.pow(noteProgress - 0.068, 2.0));
          final burst2 = math.exp(-165.0 * math.pow(noteProgress - 0.112, 2.0));
          final envelopeNoise =
              _clampDouble(burst0 + burst1 + burst2, 0.0, 1.0);
          final tail = math.exp(-(10.0 + style * 1.5) * noteProgress);
          final noise = _noiseForSample(state.seed + 29, noteSampleIndex);
          return noise * (envelopeNoise * 0.78 + tail * 0.22);
        }
        if (pitch <= 63) {
          final tomMul = style == 0
              ? 0.85
              : style == 1
                  ? 1.0
                  : style == 2
                      ? 1.18
                      : 0.95;
          final tomFreq = _clampDouble(frequencyHz * tomMul, 70.0, 900.0);
          final tone = math.sin(2.0 * math.pi * state.phaseA) *
              math.exp(-6.5 * noteProgress) *
              0.56;
          final ring = _waveFromType(3, state.phaseB) *
              math.exp(-8.5 * noteProgress) *
              0.24;
          final stick = (0.03 + preset.transient * 0.14) *
              math.exp(-42.0 * noteProgress) *
              _noiseForSample(state.seed + 37, noteSampleIndex);
          final raw = _lowPassSample(
            state: state,
            auxiliaryState: false,
            input: tone + ring + stick,
            cutoffHz: preset.cutoffHz * 1.1,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: true,
            frequencyHz: tomFreq,
            sampleRate: sampleRate,
          );
          _advancePhase(
            state: state,
            primary: false,
            frequencyHz: tomFreq * 1.6,
            sampleRate: sampleRate,
          );
          return raw;
        }
        final hatDecay = style == 0
            ? 14.0
            : style == 1
                ? 18.0
                : style == 2
                    ? 16.0
                    : 11.0;
        final noise = _noiseForSample(state.seed + 47, noteSampleIndex) *
            math.exp(-hatDecay * noteProgress);
        final metallic = _waveFromType(2, state.phaseA) * 0.23 +
            _waveFromType(1, state.phaseB) * 0.16;
        final air = _waveFromType(0, state.phaseA * 1.7) * 0.06;
        final raw = _highPassSample(
          state: state,
          input: noise + metallic + air,
          cutoffHz: 4800.0 + style * 380.0,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: 6400.0 + style * 750.0,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: 8900.0 + style * 980.0,
          sampleRate: sampleRate,
        );
        return raw;
      }
    case _FallbackInstrumentFamily.basic:
      {
        final main = _waveFromType(preset.oscillator, state.phaseA);
        final sub = 0.30 * _waveFromType(0, state.phaseB);
        final second = _waveFromType(0, state.phaseA * 2.0) * 0.12;
        final noise =
            preset.noise * _noiseForSample(state.seed, noteSampleIndex);
        final raw = _lowPassSample(
          state: state,
          auxiliaryState: false,
          input: main * 0.72 + sub + second + noise,
          cutoffHz: preset.cutoffHz,
          sampleRate: sampleRate,
        );

        _advancePhase(
          state: state,
          primary: true,
          frequencyHz: frequencyHz,
          sampleRate: sampleRate,
        );
        _advancePhase(
          state: state,
          primary: false,
          frequencyHz: frequencyHz * 0.5,
          sampleRate: sampleRate,
        );
        return raw;
      }
  }
}

enum _ExportAudioFormat { wav, mp3 }

enum _ExportChannelMode { stereo, mono }

enum _ExportResampleQuality { draft, good, best }

enum _ExportMp3Mode { cbr, vbr }

class _AudioExportSettings {
  final _ExportAudioFormat format;
  final int sampleRate;
  final int wavBitDepth;
  final bool wavDithering;
  final int mp3BitrateKbps;
  final _ExportMp3Mode mp3Mode;
  final int mp3VbrQuality;
  final _ExportChannelMode channelMode;
  final bool normalize;
  final double normalizeTargetDb;
  final _ExportResampleQuality resampleQuality;

  const _AudioExportSettings({
    required this.format,
    required this.sampleRate,
    required this.wavBitDepth,
    required this.wavDithering,
    required this.mp3BitrateKbps,
    required this.mp3Mode,
    required this.mp3VbrQuality,
    required this.channelMode,
    required this.normalize,
    required this.normalizeTargetDb,
    required this.resampleQuality,
  });

  String get fileExtension => format == _ExportAudioFormat.wav ? 'wav' : 'mp3';
}

class _CopiedClipGroupEntry {
  final AudioTrack clip;
  final Duration trimStart;
  final Duration trimEnd;
  final double offsetDeltaMs;
  final int rowDelta;

  const _CopiedClipGroupEntry({
    required this.clip,
    required this.trimStart,
    required this.trimEnd,
    required this.offsetDeltaMs,
    required this.rowDelta,
  });
}

class AudioEditorScreen extends StatefulWidget {
  final String mode;
  final Directory projectDir;

  const AudioEditorScreen(
      {Key? key, required this.mode, required this.projectDir})
      : super(key: key);
  @override
  State<AudioEditorScreen> createState() => _AudioEditorScreenState2();
}

class _AudioEditorScreenState2 extends State<AudioEditorScreen>
    with WidgetsBindingObserver {
  static const double _kTransportBarHeight = 94.0;
  static const double _kChatBarStackHeight = 70.0;
  static const double _kChatHistoryHeight = 380.0;
  static const double _kChatChromeOpacity = 0.08;
  static const double _kChatBarFixedHeight = 50.0;
  static const double _kSamplePanelCollapsedTopFactor = 0.34;
  static const double _kSamplePanelExpandedTop = 68.0;
  static const double _kSamplePanelBottomGap = 0.0;
  static const double _kAddActionsPanelWidth = 312.0;
  static const double _kProducerBannerHeightEstimate = 62.0;
  static const Set<String> _kSampleAudioExtensions = <String>{
    '.wav',
    '.wave',
    '.mp3',
    '.flac',
    '.aif',
    '.aiff',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.caf',
  };

  static const MethodChannel _edgeGesturesChannel =
      MethodChannel('mixroom/edge_gestures');
  static void _noopRefreshRowFx(int row) {}

  late Directory _projectDir;
  String _projectName = "Untitled Project";
  bool _everSaved = false;
  bool _loadedOnce = false;

  Duration _scrubPosition = Duration.zero;
  bool _isPlaying = false;

  // Multi-track support
  List<AudioTrack> _audioTracks = []; // ONLY NEED TO USE THIS FOR MULTI-TRACK
  double _universalCrossfade = 0.5;

  // UI: AI sync progress bar
  bool _isSyncing = false;
  double _syncProgress = 0.0;

  double _downloadProgress = 0.0;
  bool _showProgressDialog = false;
  String _progressMessage = "";
  String _currentOperation = "";

  // A timer to update automation and the scrubber in audio-only mode.
  // NOTE: DO NOT USE TIMER class. it is not based on monotonic timer, so it will be inaccurate
  // Timer? _audioAutomationTimer;
  Duration _globalAudioClock = Duration.zero;
  final Stopwatch _transportUiStopwatch = Stopwatch()..start();
  bool _transportPollBusy = false;
  Duration _lastTransportPollElapsed = Duration.zero;
  Duration _lastTransportSampleElapsed = Duration.zero;
  double _lastTransportSampleSeconds = 0.0;
  double _transportRateSecPerSec = 0.0;
  Ticker? _transportTicker;
  final ValueNotifier<Duration> _transportClock = ValueNotifier(Duration.zero);
  static const Duration _kTransportPollInterval = Duration(milliseconds: 50);
  static const Duration _kTransportMaxExtrapolation =
      Duration(milliseconds: 120);

  // string of export filter to pass to effects screen
  String filterString = "";

  // PICK MEDIA
  bool _isLoadingAudio = false;
  bool _isLoadingNextScreen = true;

  StateSetter? _audioEditorStateSetter; // Store the StateSetter
  static void _noopStateSetter(VoidCallback _) {}
  StateSetter get _safeAudioEditorStateSetter =>
      _audioEditorStateSetter ?? _noopStateSetter;

  Duration _audioOnlyOverallDuration = Duration.zero;

  final int kWaveformSPS = 200; // samples per second for UI
  final int kMinSamples = 1024; // ensure enough resolution for short clips
  final int kMaxSamples = 200000; // safety cap for very long files

  static const List<int> _kExportSampleRates = [44100, 48000, 88200, 96000];
  static const List<int> _kExportWavBitDepths = [16, 24, 32];
  static const List<int> _kExportMp3Bitrates = [128, 192, 256, 320];
  static const List<int> _kExportMp3VbrQualities = [0, 2, 4, 6];
  static const List<double> _kExportNormalizeTargetsDb = [-0.3, -1.0, -2.0];

  _AudioExportSettings _audioExportSettings = const _AudioExportSettings(
    format: _ExportAudioFormat.wav,
    sampleRate: 44100,
    wavBitDepth: 16,
    wavDithering: true,
    mp3BitrateKbps: 192,
    mp3Mode: _ExportMp3Mode.cbr,
    mp3VbrQuality: 2,
    channelMode: _ExportChannelMode.stereo,
    normalize: false,
    normalizeTargetDb: -1.0,
    resampleQuality: _ExportResampleQuality.best,
  );
  _AudioExportSettings? _activeAudioExportSettings;

  static const int kMaxRows = 100; // source of truth is from JuceEngine.h
  static const int kNumClips =
      500; // pro-mode opportunity to restrict to arbitrary number for free ver
  static const double _kClipPitchMinSemitones = -12.0;
  static const double _kClipPitchMaxSemitones = 12.0;

  int _selectedRow = 0;
  List<TimelineRow> _rows = [];

  void _setGlobalAudioClock(Duration value) {
    if (_globalAudioClock == value && _transportClock.value == value) {
      return;
    }
    _globalAudioClock = value;
    if (_transportClock.value != value) {
      _transportClock.value = value;
    }
  }

  void _syncTransportClock(Duration value, {required bool playing}) {
    final now = _transportUiStopwatch.elapsed;
    _lastTransportSampleSeconds = value.inMilliseconds / 1000.0;
    _lastTransportSampleElapsed = now;
    _lastTransportPollElapsed = now;
    _transportRateSecPerSec = playing ? 1.0 : 0.0;
    _setGlobalAudioClock(value);
  }

  Duration _estimateTransportClockFromSample() {
    if (!_isPlaying) {
      return Duration(
          milliseconds: (_lastTransportSampleSeconds * 1000).round());
    }
    final elapsedSinceSample =
        _transportUiStopwatch.elapsed - _lastTransportSampleElapsed;
    final boundedElapsed = elapsedSinceSample > _kTransportMaxExtrapolation
        ? _kTransportMaxExtrapolation
        : elapsedSinceSample;
    final estimatedSeconds = _lastTransportSampleSeconds +
        (boundedElapsed.inMicroseconds / 1e6) * _transportRateSecPerSec;
    return Duration(milliseconds: (estimatedSeconds * 1000).round());
  }

  Future<void> _pollTransportFromJuceIfNeeded({bool force = false}) async {
    if (_transportPollBusy) return;
    final now = _transportUiStopwatch.elapsed;
    if (!force && now - _lastTransportPollElapsed < _kTransportPollInterval) {
      return;
    }
    _transportPollBusy = true;
    _lastTransportPollElapsed = now;
    final prevSampleSeconds = _lastTransportSampleSeconds;
    final prevSampleElapsed = _lastTransportSampleElapsed;
    try {
      final t = await JuceAudioEngine.getTransportSeconds();
      final sampleElapsed = _transportUiStopwatch.elapsed;
      final wallDeltaUs = (sampleElapsed - prevSampleElapsed).inMicroseconds;
      if (wallDeltaUs > 0) {
        final measuredRate =
            ((t - prevSampleSeconds) / (wallDeltaUs / 1e6)).clamp(0.0, 2.0);
        if (_isPlaying) {
          if (measuredRate < 0.05) {
            _transportRateSecPerSec = 0.0;
          } else if (_transportRateSecPerSec <= 0.0) {
            _transportRateSecPerSec = measuredRate;
          } else {
            _transportRateSecPerSec =
                (_transportRateSecPerSec * 0.7) + (measuredRate * 0.3);
          }
        } else {
          _transportRateSecPerSec = 0.0;
        }
      }
      _lastTransportSampleSeconds = t;
      _lastTransportSampleElapsed = sampleElapsed;
      _setGlobalAudioClock(Duration(milliseconds: (t * 1000.0).round()));
    } catch (_) {
      // Ignore transient bridge errors; next poll will recover.
    } finally {
      _transportPollBusy = false;
    }
  }

  // === Recording state (Dart-only, no JUCE) ===
  final AudioRecorder _micRecorder = AudioRecorder();

  bool _isRecording = false;
  double _recordingStartMs = 0; // project time where the recording starts
  String? _recordingFilePath; // temp recorded file (m4a/wav/etc)
  Timer? _recordingPeakTimer;

  // for live preview waveform
  List<double> _recordingPeaks = []; // 0..1 peaks while recording
  StreamSubscription<Amplitude>? _amplitudeSub;

  // so keeping this local state might be unnecessary (and cause a factor of drift from source of truth which is JUCE) (maybe consider removing?)
  final List<double> _rowPan = [];
  final List<double> _rowGain = [];
  final List<List<AutomationPoint>> _rowVolumeAutomation = [];
  final List<bool> _rowMuted = [];
  final List<bool> _rowSoloed = [];
  final List<bool?> _rowMuteApplied = [];
  final List<bool> _rowExpanded = [];

  // for copy/paste logic
  AudioTrack? _copiedClip;
  List<_CopiedClipGroupEntry>? _copiedClipGroup;
  Duration _copiedTrimStart = Duration.zero;
  Duration _copiedTrimEnd = Duration.zero;

  // Piano roll / instrument editor
  bool _showPianoRoll = false;
  bool _pianoRollFullscreen = false;
  int? _activeMidiClipEngineId;
  bool _liveMidiEventPlaybackSupported = false;
  final Map<int, int> _midiRenderSyncTokens = <int, int>{};
  final Map<int, Timer> _midiRenderDebounceTimers = <int, Timer>{};
  int _nextMidiRenderSyncToken = 0;
  bool _timelineMagnetEnabled = false;
  int _timelineQuantizeDivisionsPerBar = 4;

  bool _loopEnabled = false;
  int _loopStartMs = 0;
  int _loopEndMs = 0;

  // master rack
  bool _showMasterRack = false;
  double _masterGain = 1.0;
  double _masterPan = 0.5;
  double? _masterGainDragStart;
  double? _masterPanDragStart;
  final Map<int, double> _masterRackRowGainDragStart = <int, double>{};
  Map<int, List<bool>> _rowFxBypassSnapshot = {};
  List<bool> _masterFxBypassSnapshot = [];
  bool _globalFxBypass = false;
  final Map<int, double> _rowPeakHoldDb = <int, double>{};
  final Map<int, DateTime> _rowPeakHoldLastUpdate = <int, DateTime>{};
  final Map<int, DateTime> _rowPeakHoldFreezeUntil = <int, DateTime>{};

  final List<double> _rowGainSnapshot = [];
  final List<double> _rowPanSnapshot = [];
  final List<List<AutomationPoint>> _rowAutomationSnapshot = [];

  // BPM/time
  double _tempo = 120.0;
  bool _tempoStretchEnabled = false;
  bool _tempoStretchPreservePitchDefault = false;
  bool _showTempoRollDown = false;
  bool _tempoSyncInFlight = false;
  bool _tempoSyncQueued = false;

  List<MediaDeviceInfo> _inputs = [];
  List<MediaDeviceInfo> _outputs = [];
  MediaDeviceInfo? _selectedInput;
  MediaDeviceInfo? _selectedOutput;

  List<String> _inputDevices = [];
  String? _selectedDevice;

  int _numInputChannels = 0;
  int _selectedChannelStart = 0;
  int _selectedChannelCount = 1;

  bool _loadingDevices = true;

  bool _metronomeEnabled = false;
  double _metronomeVolume = 0.5; // 0–1

  final EditorUndoManager _undoManager = EditorUndoManager(maxHistory: 5);

  bool _chatExpanded = false;
  bool _chatInputActive = false;
  bool _chatHasText = false;
  final TextEditingController _chatTextController = TextEditingController();
  late final InstrumentClassifier _classifier;
  final FocusNode _chatFocusNode = FocusNode();
  late final ChatPipeline _chatPipeline;
  late final MixingMagnitudePredictor _magnitudePredictor;
  late final ProducerDataCollector _producerCollector;
  bool _producerDataMode = false;
  bool _showProducerCaptureUi = false;
  bool _producerUiBusy = false;
  late final ChatController _chatController;
  void Function(int row) _refreshRowFx = _noopRefreshRowFx;
  bool _isThinking = false;
  late final MixChangeHighlighter _mixHighlighter = MixChangeHighlighter();
  bool _chatWarm = false;
  bool _isDialogOpen =
      false; // to fix weird issue on iPad iOS 26 where opening some dialogue would insta-close it
  bool _isMasterPopupOpen = false; // same thing as above
  StateSetter? _projectSettingsStateSetter;

  bool _sampleBrowserVisible = false;
  bool _sampleBrowserExpanded = false;
  bool _sampleDragActive = false;
  bool _filePickerInFlight = false;
  bool _reopenSampleBrowserAfterDrag = false;
  bool _reopenSampleBrowserExpanded = false;
  bool _showAddActionsPanel = false;
  String? _activeAddActionId;
  bool _addButtonPressed = false;
  final List<String> _sampleBrowserRoots = <String>[];
  final AccessingSecurityScopedResource _securityScopedResource =
      AccessingSecurityScopedResource();
  final Set<String> _startedSecurityScopeKeys = <String>{};
  int _securityScopeStartCount = 0;
  final Map<String, Duration?> _sampleDurationCache = <String, Duration?>{};
  late final ja.AudioPlayer _samplePreviewPlayer;
  StreamSubscription<ja.PlayerState>? _samplePreviewStateSub;
  String? _auditioningSamplePath;
  bool _samplePreviewPlaying = false;
  int _pianoPreviewToken = 0;
  final Map<String, String> _pianoPreviewRenderCache = <String, String>{};
  final Set<String> _pianoPreviewPrimedInstruments = <String>{};

  late MeterBus _meters;
  Timer? _meterTimer;
  bool _meterPollingBusy = false; // overlap guard
  static const int _meterStride = 5; // peakL, peakR, rmsL, rmsR, clip(0/1)
  Timer? _meterDecayTimer;
  bool _meterPolling = false;

  int get _rowCount => _rows.length;

  int _rowIdAt(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return -1;
    return _rows[rowIndex].rowId;
  }

  int _rowIndexForId(int rowId) {
    return _rows.indexWhere((r) => r.rowId == rowId);
  }

  int _allocateEngineClipId() {
    final usedIds = <int>{};
    for (final track in _audioTracks) {
      if (track.engineClipId >= 0) {
        usedIds.add(track.engineClipId);
      }
    }
    for (int id = 0; id < kNumClips; id++) {
      if (!usedIds.contains(id)) return id;
    }
    return -1;
  }

  void _handleChatTextChanged() {
    final hasText = _chatTextController.text.trim().isNotEmpty;
    if (_chatHasText == hasText || !mounted) return;
    setState(() {
      _chatHasText = hasText;
    });
  }

  // This is needed in iOS so that hold actions (like track headers) are immediately responsive
  // without gesture gate issues. But the tradeoff is that swipe to go back/forward will not work.
  // Since those actions might be needed in other parts of app, make it toggleable like this.
  Future<void> _setIOSSystemGestureDeferral(bool enabled) async {
    if (!Platform.isIOS) return;
    try {
      await _edgeGesturesChannel
          .invokeMethod<void>('setDeferred', {'enabled': enabled});
    } catch (_) {}
  }

  void _setStateAndRefreshProjectSettings(VoidCallback updater) {
    if (!mounted) return;
    setState(updater);
    final dialogSetState = _projectSettingsStateSetter;
    if (dialogSetState != null) {
      dialogSetState(() {});
    }
  }

  void _syncRowLocalStateToRowCount() {
    while (_rowPan.length < _rowCount) {
      _rowPan.add(0.5);
      _rowGain.add(1.0);
      _rowVolumeAutomation.add([AutomationPoint(x: 0.0, volume: 0.75)]);
      _rowMuted.add(false);
      _rowSoloed.add(false);
      _rowMuteApplied.add(null);
      _rowExpanded.add(false);
      _rowGainSnapshot.add(1.0);
      _rowPanSnapshot.add(0.5);
      _rowAutomationSnapshot.add([]);
    }
    if (_rowPan.length > _rowCount) {
      _rowPan.removeRange(_rowCount, _rowPan.length);
      _rowGain.removeRange(_rowCount, _rowGain.length);
      _rowVolumeAutomation.removeRange(_rowCount, _rowVolumeAutomation.length);
      _rowMuted.removeRange(_rowCount, _rowMuted.length);
      _rowSoloed.removeRange(_rowCount, _rowSoloed.length);
      _rowMuteApplied.removeRange(_rowCount, _rowMuteApplied.length);
      _rowExpanded.removeRange(_rowCount, _rowExpanded.length);
      _rowGainSnapshot.removeRange(_rowCount, _rowGainSnapshot.length);
      _rowPanSnapshot.removeRange(_rowCount, _rowPanSnapshot.length);
      _rowAutomationSnapshot.removeRange(
          _rowCount, _rowAutomationSnapshot.length);
    }
    if (_selectedRow >= _rowCount) {
      _selectedRow = _rowCount == 0 ? 0 : _rowCount - 1;
    }
    if (_meters.rows.length != _rowCount) {
      _meters.dispose();
      _meters = MeterBus(numRows: _rowCount);
    }
    _rowPeakHoldDb
        .removeWhere((row, _) => row != -1 && (row < 0 || row >= _rowCount));
    _rowPeakHoldLastUpdate
        .removeWhere((row, _) => row != -1 && (row < 0 || row >= _rowCount));
    _rowPeakHoldFreezeUntil
        .removeWhere((row, _) => row != -1 && (row < 0 || row >= _rowCount));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_setIOSSystemGestureDeferral(true));
    WidgetsBinding.instance.addObserver(this);
    // prewarmFFT(); // so that AI sync first run is not heavy (this was for video/audio sync)

    _transportTicker = Ticker((_) {
      if (!_isPlaying) return;
      _setGlobalAudioClock(_estimateTransportClockFromSample());
      unawaited(_pollTransportFromJuceIfNeeded());

      // ===== END / LOOP LOGIC (same as before) =====
      final endPoint = Duration(
        milliseconds: math.max(_audioOnlyOverallDuration.inMilliseconds,
            msFor128Bars(_tempo).toInt()),
      );

      final reachedEnd = _globalAudioClock >= endPoint;
      final reachedLoopEnd = _loopEnabled &&
          _globalAudioClock >= Duration(milliseconds: _loopEndMs);

      if (reachedLoopEnd) {
        if (_isRecording) {
          _transportTicker?.stop();
          _stopRecordingJuce(keepPlaying: false);
          return;
        }
        _restartAudio(_safeAudioEditorStateSetter);
        _togglePlayPauseAudio(_safeAudioEditorStateSetter);
        return;
      }

      if (reachedEnd) {
        if (_isRecording) return;
        _togglePlayPauseAudio(_safeAudioEditorStateSetter);
      }
    });

    // _loadAudioDevices();
    _loadInputDevicesFromJuce();

    _projectDir = widget.projectDir;

    _classifier = InstrumentClassifier();
    // _classifier.debugLog = (msg) {
    //   print('msg: $msg');
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text(msg),
    //       duration: const Duration(seconds: 3),
    //     ),
    //   );
    // };
    _classifier.load(); // Load once
    _producerCollector = ProducerDataCollector();
    _producerCollector.setEnabled(_producerDataMode);
    _magnitudePredictor = kUseLearnedMagnitudePredictor
        ? OnnxMixingMagnitudePredictor(
            enabled: true,
            applyModelAsset: kMixApplyClassifierAsset,
            magnitudeModelAsset: kMixMagnitudeRegressorAsset,
          )
        : const NoopMixingMagnitudePredictor();
    unawaited(_magnitudePredictor.load());

    _chatPipeline = ChatPipeline(
      llm: CloudLlmService(
        apiKey:
            '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',
        //TODO: keep API key in the backend server. const String.fromEnvironment('OPENAI_API_KEY'),
        /*
        Prod-safe high level:

        1) Move OpenAI calls to your backend.
          App never sees OpenAI API key.
          Backend stores key in secret manager/env.
        2) App calls your API endpoint (e.g. /mix/llm).
          Send prompt + project snapshot.
          Backend forwards to OpenAI Responses API and returns tool output.
        3) Protect backend.
          Authenticate users (JWT/session).
          Rate-limit per user/device/IP.
          Add abuse checks, logging, and request size limits.
        4) Keep behavior stable.
          Reuse same system prompt/tools schema on server.
          Version prompts/models server-side for rollback.
        5) Ship keys safely.
          Rotate keys without app update.
          Separate dev/staging/prod keys.
        */
      ), // LocalLlmService(),
      projectBuilder: ProjectStateBuilder(classifier: _classifier),
      mixModel: LocalMixingModel(),
      magnitudePredictor: _magnitudePredictor,
      onThinkingChanged: (isThinking) {
        setState(() {
          _isThinking = isThinking;
        });
      },
    );

    _chatController = InMemoryChatController();
    _chatTextController.addListener(_handleChatTextChanged);

    _samplePreviewPlayer = ja.AudioPlayer(handleAudioSessionActivation: false);
    _samplePreviewStateSub =
        _samplePreviewPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _samplePreviewPlaying = state.playing;
        if (state.processingState == ja.ProcessingState.completed) {
          _auditioningSamplePath = null;
          _samplePreviewPlaying = false;
        }
      });
    });

    // Optional welcome message
    _chatController.insertMessage(
      TextMessage(
        id: const Uuid().v4(),
        authorId: 'assistant',
        createdAt: DateTime.now().toUtc(),
        text: "I'm your AI Co-Producer. Ask me about your mix.",
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _chatWarm = true;
      });
    });

    _meters = MeterBus(numRows: 0);
    // _startMeterPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await JuceAudioEngine.initialise(); // heavy blocking native call
      JuceAudioEngine.initialiseEventListeners();
      _liveMidiEventPlaybackSupported =
          await JuceAudioEngine.supportsLiveMidiClipPlayback();
      await _reloadRowsFromEngine();
      await _loadProjectIfAny();
      setState(() => _isLoadingNextScreen = false);
    });
  }

  Future<void> _reloadRowsFromEngine() async {
    final oldRows = List<TimelineRow>.from(_rows);
    final oldPanById = <int, double>{};
    final oldGainById = <int, double>{};
    final oldMutedById = <int, bool>{};
    final oldSoloById = <int, bool>{};
    final oldExpandedById = <int, bool>{};
    final oldMuteAppliedById = <int, bool?>{};
    final oldAutomationById = <int, List<AutomationPoint>>{};
    for (int i = 0; i < oldRows.length; i++) {
      final id = oldRows[i].rowId;
      if (i < _rowPan.length) oldPanById[id] = _rowPan[i];
      if (i < _rowGain.length) oldGainById[id] = _rowGain[i];
      if (i < _rowMuted.length) oldMutedById[id] = _rowMuted[i];
      if (i < _rowSoloed.length) oldSoloById[id] = _rowSoloed[i];
      if (i < _rowExpanded.length) oldExpandedById[id] = _rowExpanded[i];
      if (i < _rowMuteApplied.length)
        oldMuteAppliedById[id] = _rowMuteApplied[i];
      if (i < _rowVolumeAutomation.length) {
        oldAutomationById[id] =
            _rowVolumeAutomation[i].map((p) => p.copy()).toList();
      }
    }

    final rawRows = await JuceAudioEngine.getRows();
    _rows = rawRows
        .map(
          (m) => TimelineRow(
            rowId: (m['rowId'] as num?)?.toInt() ?? -1,
            name: (m['name'] as String?) ?? '',
            iconId: (m['iconId'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((r) => r.rowId >= 0)
        .toList();
    _syncRowLocalStateToRowCount();

    for (int i = 0; i < _rows.length; i++) {
      final id = _rows[i].rowId;
      _rowPan[i] = oldPanById[id] ?? _rowPan[i];
      _rowGain[i] = oldGainById[id] ?? _rowGain[i];
      _rowMuted[i] = oldMutedById[id] ?? _rowMuted[i];
      _rowSoloed[i] = oldSoloById[id] ?? _rowSoloed[i];
      _rowExpanded[i] = oldExpandedById[id] ?? _rowExpanded[i];
      _rowMuteApplied[i] = oldMuteAppliedById[id];
      _rowVolumeAutomation[i] =
          oldAutomationById[id] ?? _rowVolumeAutomation[i];
    }

    if (mounted) setState(() {});
  }

  Future<void> _ensureRowExistsForClipInsertion() async {
    if (_rowCount > 0) return;
    final id = await JuceAudioEngine.addRow('Track 1', iconId: 0);
    if (id >= 0) {
      await _reloadRowsFromEngine();
    }
  }

  Future<void> _ensureRowIndexExists(int rowIndex) async {
    if (rowIndex < 0) return;
    while (_rowCount <= rowIndex) {
      final next = _rowCount + 1;
      final id = await JuceAudioEngine.addRow('Track $next', iconId: 0);
      if (id < 0) break;
      await _reloadRowsFromEngine();
    }
  }

  Future<void> _restoreRowsFromProjectJson(
      List<Map<String, dynamic>> savedRows, List tracks) async {
    const int kDefaultRows = 5;
    final bool isFreshProject = savedRows.isEmpty && tracks.isEmpty;
    int targetRowCount = savedRows.length;
    if (targetRowCount <= 0 && tracks.isNotEmpty) {
      int maxTrackRow = -1;
      for (final t in tracks) {
        final map = (t as Map).cast<String, dynamic>();
        final row = (map["rowIndex"] as int?) ?? 0;
        if (row > maxTrackRow) maxTrackRow = row;
      }
      targetRowCount = maxTrackRow + 1;
    }
    if (targetRowCount <= 0) {
      targetRowCount =
          isFreshProject ? kDefaultRows : (_rowCount > 0 ? _rowCount : 1);
    }

    final currentIds = _rows.map((r) => r.rowId).toList();

    while (currentIds.length < targetRowCount) {
      final next = currentIds.length + 1;
      final id = await JuceAudioEngine.addRow('Track $next', iconId: 0);
      if (id < 0) break;
      currentIds.add(id);
    }

    while (currentIds.length > targetRowCount && currentIds.length > 1) {
      final rowId = currentIds.removeLast();
      final ok = await JuceAudioEngine.removeRow(rowId);
      if (!ok) break;
    }

    await _reloadRowsFromEngine();

    if (isFreshProject) {
      for (int i = 0; i < _rowCount; i++) {
        final rowId = _rowIdAt(i);
        if (rowId < 0) continue;
        await JuceAudioEngine.renameRow(rowId, 'Track ${i + 1}');
        await JuceAudioEngine.setRowIcon(rowId, 0);
      }
      await _reloadRowsFromEngine();
      await _recomputeAudibleState();
      return;
    }

    for (int i = 0; i < savedRows.length && i < _rowCount; i++) {
      final row = savedRows[i];
      final name = (row["name"] as String?)?.trim() ?? "";
      final iconId = (row["iconId"] as num?)?.toInt() ?? 0;
      final rowId = _rowIdAt(i);
      if (rowId < 0) continue;
      if (name.isNotEmpty) {
        await JuceAudioEngine.renameRow(rowId, name);
      }
      await JuceAudioEngine.setRowIcon(rowId, iconId);
    }

    await _reloadRowsFromEngine();
  }

  @override
  void dispose() {
    unawaited(_setIOSSystemGestureDeferral(false));
    unawaited(_producerCollector.closeSession(reason: 'screen_dispose'));
    WidgetsBinding.instance.removeObserver(this);
    _amplitudeSub?.cancel();
    _micRecorder.dispose();
    for (var track in _audioTracks) {
      track.audioStartTimer?.cancel();
    }
    _transportTicker?.dispose();
    _chatTextController.removeListener(_handleChatTextChanged);
    _chatTextController.dispose();
    _chatFocusNode.dispose();
    _samplePreviewStateSub?.cancel();
    _samplePreviewPlayer.dispose();
    _stopAllSecurityScopedAccess();
    for (final timer in _midiRenderDebounceTimers.values) {
      timer.cancel();
    }
    _midiRenderDebounceTimers.clear();
    _midiRenderSyncTokens.clear();

    _stopMeterPolling(decayToZero: false);
    _meterTimer?.cancel();
    _meterTimer = null;
    _meterDecayTimer?.cancel();
    _meters.dispose();
    _transportClock.dispose();
    // JuceAudioEngine.shutdown();
    // print("JUCE shutdown called");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (state == AppLifecycleState.resumed) {
        debugPrint("App Resumed on Android - Re-initializing.");
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        debugPrint("App Paused or Inactive on Android - Disposing.");
        _pausePlayback();
        setState(() {
          _isPlaying = false;
        });
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (state == AppLifecycleState.resumed) {
        // debugPrint("App Resumed on iOS");
      } else if (state == AppLifecycleState.paused) {
        //} || state == AppLifecycleState.inactive) {
        // debugPrint("App Paused or Inactive on iOS");
        _pauseAudio(_safeAudioEditorStateSetter);
        setState(() {
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _loadProjectIfAny() async {
    if (_loadedOnce) return;
    _loadedOnce = true;

    try {
      // File browser roots should be per-session only, not persisted per project.
      _sampleBrowserRoots.clear();
      _sampleDurationCache.clear();
      _sampleBrowserVisible = false;
      _sampleBrowserExpanded = false;
      _sampleDragActive = false;
      _reopenSampleBrowserAfterDrag = false;
      _reopenSampleBrowserExpanded = false;
      final json = await ProjectManager.readProjectJson(_projectDir);
      _projectName = (json["name"] ?? "Untitled Project") as String;
      _tempo = (((json["tempoBpm"] as num?) ?? (json["bpm"] as num?) ?? _tempo)
              .toDouble())
          .clamp(20.0, 999.0);
      _tempoStretchEnabled = (json["tempoStretchEnabled"] as bool?) ?? false;
      _tempoStretchPreservePitchDefault =
          (json["tempoStretchPreservePitchDefault"] as bool?) ?? false;
      final uiSettings = (json["ui"] as Map?)?.cast<String, dynamic>();
      _showProducerCaptureUi =
          (uiSettings?["showProducerCaptureUi"] as bool?) ?? false;
      await JuceAudioEngine.setMetronomeBpm(_tempo);

      // mark opened time
      json["lastOpenedAt"] = DateTime.now().millisecondsSinceEpoch;
      await ProjectManager.writeProjectJson(_projectDir, json);

      final rowsJson = ((json["rows"] as List?) ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final tracks = (json["tracks"] as List?) ?? [];
      await _restoreRowsFromProjectJson(rowsJson, tracks);

      // Load all clips (audio + MIDI/instrument)
      for (final t in tracks) {
        final map = (t as Map).cast<String, dynamic>();
        final fileName = map["fileName"] as String;
        final label = (map["label"] as String?) ?? '';
        final storedRowId = (map["rowId"] as int?) ?? -1;
        int rowIndex = (map["rowIndex"] as int?) ?? 0;
        if (storedRowId >= 0) {
          final idx = _rowIndexForId(storedRowId);
          if (idx >= 0) rowIndex = idx;
        }

        final clipKind =
            ClipKindWire.fromWire((map['clipType'] as String?) ?? 'audio');
        final instrumentId = (map['instrumentId'] as String?) ?? '';
        final fallbackName =
            instrumentId.isEmpty ? '' : _instrumentNameFromId(instrumentId);
        final instrumentName =
            (map['instrumentName'] as String?) ?? fallbackName;
        final rawParams =
            (map['instrumentParams'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        final instrumentParams = <String, double>{};
        for (final e in rawParams.entries) {
          if (e.value is num) {
            instrumentParams[e.key] = (e.value as num).toDouble();
          }
        }
        final midiNotes = ((map['midiNotes'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => MidiNote.fromJson(e.cast<String, dynamic>()))
            .toList();

        final trimStartMs = (map["trimStartMs"] as int?) ?? 0;
        final trimEndMs = (map["trimEndMs"] as int?) ?? 0;
        final offsetSec = ((map["offset"] as num?) ?? 0).toDouble();
        final crossfade = ((map["crossfade"] as num?) ?? 0).toDouble();
        final gain = ((map["gain"] as num?) ?? 1.0).toDouble();
        final pitchSemitones =
            ((map["pitchSemitones"] as num?) ?? 0.0).toDouble();
        final parsedSourceTempoBpm =
            ((map["sourceTempoBpm"] as num?) ?? 0.0).toDouble();
        double sourceTempoBpm = parsedSourceTempoBpm;
        bool stretchToProjectTempo =
            (map["stretchToProjectTempo"] as bool?) ?? false;
        bool tempoStretchPreservePitch =
            (map["tempoStretchPreservePitch"] as bool?) ??
                _tempoStretchPreservePitchDefault;
        if (clipKind == ClipKind.midi) {
          if (sourceTempoBpm <= 0.0) {
            sourceTempoBpm = _tempo;
          }
          stretchToProjectTempo = true;
          tempoStretchPreservePitch = true;
        }

        final automationList = (map["automation"] as List?) ?? [];
        final automation = automationList
            .map((e) => AutomationPointJson.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList();

        final audioFile =
            File(p.join(ProjectManager.audioDir(_projectDir).path, fileName));
        if (!audioFile.existsSync()) {
          if (clipKind == ClipKind.midi) {
            await _ensureRowIndexExists(rowIndex);
            await _ensureRowExistsForClipInsertion();
            final beforeCount = _audioTracks.length;
            await _addMidiTrack(
              instrumentId:
                  instrumentId.isEmpty ? 'mixroom.basic_synth' : instrumentId,
              instrumentName:
                  instrumentName.isEmpty ? 'Basic Synth' : instrumentName,
              instrumentParams: instrumentParams.isNotEmpty
                  ? instrumentParams
                  : _instrumentParamsFromSpec(
                      _instrumentSpecById(instrumentId.isEmpty
                          ? 'mixroom.basic_synth'
                          : instrumentId),
                    ),
              midiNotes: midiNotes,
              row: rowIndex,
              timeMs: offsetSec * 1000.0,
              trimStartRequested: Duration(milliseconds: trimStartMs),
              trimEndRequested: Duration(milliseconds: trimEndMs),
              label: label.isEmpty ? instrumentName : label,
              gain: gain,
              pitchSemitones: pitchSemitones,
              sourceTempoBpm: sourceTempoBpm,
              stretchToProjectTempo: stretchToProjectTempo,
              tempoStretchPreservePitch: tempoStretchPreservePitch,
              crossfade: crossfade,
              automation: automation.isNotEmpty ? automation : null,
            );
            if (_audioTracks.length > beforeCount) {
              final tr = _audioTracks.last;
              tr.crossfade = crossfade;
              tr.gain = gain;
              tr.pitchSemitones = pitchSemitones;
              tr.sourceTempoBpm = sourceTempoBpm;
              tr.stretchToProjectTempo = stretchToProjectTempo;
              tr.tempoStretchPreservePitch = tempoStretchPreservePitch;
              tr.volumeAutomation = automation.isNotEmpty
                  ? automation
                  : [
                      AutomationPoint(x: 0.0, volume: 1.0),
                      AutomationPoint(x: 1.0, volume: 1.0)
                    ];
            }
            continue;
          }
          debugPrint("Missing audio file: ${audioFile.path}");
          continue;
        }

        await _ensureRowIndexExists(rowIndex);
        await _ensureRowExistsForClipInsertion();
        final beforeCount = _audioTracks.length;
        if (clipKind == ClipKind.midi) {
          await _addMidiTrackFromProjectFile(
            projectAudioFile: audioFile,
            label: label.isEmpty ? instrumentName : label,
            row: rowIndex,
            timeMs: offsetSec * 1000.0,
            instrumentId:
                instrumentId.isEmpty ? 'mixroom.basic_synth' : instrumentId,
            instrumentName:
                instrumentName.isEmpty ? 'Basic Synth' : instrumentName,
            instrumentParams: instrumentParams.isNotEmpty
                ? instrumentParams
                : _instrumentParamsFromSpec(
                    _instrumentSpecById(instrumentId.isEmpty
                        ? 'mixroom.basic_synth'
                        : instrumentId),
                  ),
            midiNotes: midiNotes,
            trimStartRequested: Duration(milliseconds: trimStartMs),
            trimEndRequested: Duration(milliseconds: trimEndMs),
            gain: gain,
            pitchSemitones: pitchSemitones,
            sourceTempoBpm: sourceTempoBpm,
            stretchToProjectTempo: stretchToProjectTempo,
            tempoStretchPreservePitch: tempoStretchPreservePitch,
            crossfade: crossfade,
            automation: automation.isNotEmpty ? automation : null,
          );
        } else {
          await _addAudioTrackFromProjectFile(
            projectAudioFile: audioFile,
            label: label,
            row: rowIndex,
            timeMs: offsetSec * 1000.0,
            trimStartRequested: Duration(milliseconds: trimStartMs),
            trimEndRequested: Duration(milliseconds: trimEndMs),
            gain: gain,
            pitchSemitones: pitchSemitones,
            sourceTempoBpm: sourceTempoBpm,
            stretchToProjectTempo: stretchToProjectTempo,
            tempoStretchPreservePitch: tempoStretchPreservePitch,
            crossfade: crossfade,
            automation: automation.isNotEmpty ? automation : null,
          );
        }
        if (_audioTracks.length <= beforeCount) {
          continue;
        }

        // After _addAudioTrackFromFile, the newest track is last
        // I think this code is deprecated
        final tr = _audioTracks.last;
        tr.crossfade = crossfade;
        tr.gain = gain;
        tr.pitchSemitones = pitchSemitones;
        tr.sourceTempoBpm = sourceTempoBpm;
        tr.stretchToProjectTempo = stretchToProjectTempo;
        tr.tempoStretchPreservePitch = tempoStretchPreservePitch;
        tr.volumeAutomation = automation.isNotEmpty
            ? automation
            : [
                AutomationPoint(x: 0.0, volume: 1.0),
                AutomationPoint(x: 1.0, volume: 1.0)
              ];
      }

      final rowStatesList = (json["rowStates"] as List?) ?? [];

      for (final rs in rowStatesList) {
        final snap =
            RowStateSnapshot.fromJson((rs as Map).cast<String, dynamic>());
        final r = snap.row;

        // Safety check
        if (r < 0 || r >= _rowCount) continue;

        // Restore pan & gain
        _rowPan[r] = snap.pan;
        _rowGain[r] = snap.gain;

        // Restore automation (deep copy!)
        _rowVolumeAutomation[r] =
            snap.volumeAutomation.map((p) => p.copy()).toList();

        await JuceAudioEngine.setRowGain(r, snap.gain);
        await JuceAudioEngine.setRowPan(r, snap.pan);
        await JuceAudioEngine.setTrackAutomationPoints(
            r, (_rowVolumeAutomation[r]).map((p) => p.toMap()).toList());
      }

      // Restore FX snapshots after tracks exist
      final rowFxList = (json["rowEffects"] as List?) ?? [];
      for (final rf in rowFxList) {
        final snap = RowEffectsSnapshotJson.fromJson(
            (rf as Map).cast<String, dynamic>());
        await restoreRowSnapshot(snap);
      }

      final master = json["master"] as Map<String, dynamic>?;

      if (master != null) {
        // Restore FX chain FIRST
        final masterFx = master["effects"];
        if (masterFx != null) {
          final ms = MasterEffectsSnapshotJson.fromJson(masterFx);
          await restoreMasterSnapshot(ms);
        }

        // THEN restore gain & pan
        final gain = (master["gain"] as num?)?.toDouble() ?? 1.0;
        final pan = (master["pan"] as num?)?.toDouble() ?? 0.5;

        _masterGain = gain;
        _masterPan = pan;
        await JuceAudioEngine.setMasterGain(_masterGain);
        await JuceAudioEngine.setMasterPan(_masterPan);
      }

      _everSaved = true;
      // Stabilize first playback after loading by forcing transport to start.
      _setGlobalAudioClock(Duration.zero);
      await JuceAudioEngine.setTransportSeconds(0.001);
      await JuceAudioEngine.setTransportSeconds(0.0);
      await JuceAudioEngine.setMetronomeTransportMs(0.0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (int row = 0; row < _rowCount; row++) {
          _refreshRowFx(row);
        }
      });
      setState(() {});
    } catch (e) {
      debugPrint("Project load failed: $e");
    }
  }

  Future<void> _saveProject({bool showSnackBar = true}) async {
    try {
      final audioDir = ProjectManager.audioDir(_projectDir);
      if (!await audioDir.exists()) await audioDir.create(recursive: true);

      // Copy audio sources into project/audio
      final tracksJson = <Map<String, dynamic>>[];
      for (int i = 0; i < _audioTracks.length; i++) {
        final tr = _audioTracks[i];

        // final src = tr.originalFile.existsSync() ? tr.originalFile : tr.file;
        final src = tr.file;

        if (!src.existsSync()) continue;

        // Keep original filename
        final fileName = p.basename(src.path);
        final dst = File(p.join(audioDir.path, fileName));

        // Copy only if not already inside project
        if (src.path != dst.path) {
          if (dst.existsSync()) await dst.delete();
          await src.copy(dst.path);
        }

        tracksJson.add({
          "fileName": fileName, //tr.file.path,
          "label": tr.label, // what user sees, doesn't have to be unique
          "clipType": tr.clipKind.wireName,
          "trimStartMs": tr.trimStart.inMilliseconds,
          "trimEndMs": tr.trimEnd.inMilliseconds,
          "offset": tr.offset,
          "crossfade": tr.crossfade,
          "gain": tr.gain,
          "pitchSemitones": tr.pitchSemitones,
          "sourceTempoBpm": tr.sourceTempoBpm,
          "stretchToProjectTempo": tr.stretchToProjectTempo,
          "tempoStretchPreservePitch": tr.tempoStretchPreservePitch,
          "rowIndex": tr.rowIndex,
          "rowId": tr.rowId,
          "automation": tr.volumeAutomation.map((p) => p.toJson()).toList(),
          "instrumentId": tr.instrumentId,
          "instrumentName": tr.instrumentName,
          "instrumentParams": tr.instrumentParams,
          "midiNotes": tr.midiNotes.map((n) => n.toJson()).toList(),
        });
      }

      // Garbage collect unreferenced audio files
      final referenced = _audioTracks
          .map((t) => p.basename(t.file.path))
          .whereType<String>()
          .toSet();
      final files = audioDir.listSync().whereType<File>();
      for (final f in files) {
        final name = p.basename(f.path);
        if (!referenced.contains(name)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // Capture FX snapshots (maybe don't do this since it is destructive, user could have FX chains on empty rows)
      // final usedRows = _audioTracks.map((t) => t.rowIndex).where((r) => r >= 0).toSet().toList()..sort();
      final usedRows = List<int>.generate(_rowCount, (i) => i);

      final rowFx = <Map<String, dynamic>>[];
      for (final r in usedRows) {
        final snap = await captureRowSnapshot(r);
        rowFx.add(snap.toJson());
      }

      final rowStates = <Map<String, dynamic>>[];
      for (final r in usedRows) {
        final snap = RowStateSnapshot(
          row: r,
          gain: _rowGain[r],
          pan: _rowPan[r],
          volumeAutomation:
              _rowVolumeAutomation[r].map((p) => p.copy()).toList(),
        );
        rowStates.add(snap.toJson());
      }

      final masterSnap = await captureMasterSnapshot();

      // Load existing json if present, preserve createdAt
      final existing = await ProjectManager.readProjectJson(_projectDir);
      final createdAt =
          existing["createdAt"] ?? DateTime.now().millisecondsSinceEpoch;

      final now = DateTime.now().millisecondsSinceEpoch;
      final rowsJson = _rows
          .map((r) => {
                "name": r.name,
                "iconId": r.iconId,
              })
          .toList();
      final json = <String, dynamic>{
        "version": 1,
        "name": _projectName,
        "createdAt": createdAt,
        "lastOpenedAt": now,
        "tempoBpm": _tempo,
        "tempoStretchEnabled": _tempoStretchEnabled,
        "tempoStretchPreservePitchDefault": _tempoStretchPreservePitchDefault,
        "rows": rowsJson,
        "tracks": tracksJson,
        "rowStates": rowStates,
        "rowEffects": rowFx,
        "master": {
          "gain": _masterGain,
          "pan": _masterPan,
          "effects": masterSnap.toJson()
        },
        "ui": {
          "showProducerCaptureUi": _showProducerCaptureUi,
        }
      };

      await ProjectManager.writeProjectJson(_projectDir, json);

      _everSaved = true;

      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("✅ Project saved")));
      }
    } catch (e) {
      debugPrint("Project save failed: $e");
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("⚠️ Save failed: $e")));
      }
    }
  }

  Future<String?> _showProjectNameDialog({
    required String title,
    required String initialName,
    String hint = 'Project name',
  }) async {
    final controller = TextEditingController(text: initialName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => MediaQuery.removeViewInsets(
        context: ctx,
        removeBottom: true,
        child: Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
          backgroundColor: const Color(0xFF1A2233),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.drive_file_rename_outline,
                        color: Color(0xFFB9D4FF)),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 50,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        Navigator.pop(ctx, controller.text.trim()),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E6EEB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureProjectNamedOnFirstExit() async {
    if (_everSaved) return true;
    final renamed = await _showProjectNameDialog(
      title: 'Name Your Project',
      initialName: _projectName,
      hint: 'Project name',
    );
    if (renamed == null) return false;
    final newName = renamed.trim();
    if (newName.isEmpty) return false;
    setState(() => _projectName = newName);
    return true;
  }

  Future<void> _handleBackPressed() async {
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    if (_isPlaying) {
      _isPlaying = false;
      await _pauseAudio(_audioEditorStateSetter ?? (fn) {});
    }

    final canExit = await _ensureProjectNamedOnFirstExit();
    if (!canExit) {
      _isDialogOpen = false;
      return;
    }

    await _saveProject(showSnackBar: false);

    if (mounted) {
      _pausePlayback();
      for (var track in _audioTracks) {
        track.audioStartTimer?.cancel();
      }
      JuceAudioEngine.shutdown();
      Navigator.of(context).pop();
    }
  }

  // Helper: Format Duration as mm:ss:xx (first two digits of ms).
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String firstTwoMsDigits(int milliseconds) {
      final msString = milliseconds.toString().padLeft(3, '0');
      return msString.substring(0, 2);
    }

    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final millisecondsFirstTwo =
        firstTwoMsDigits(duration.inMilliseconds.remainder(1000));

    return "$minutes:$seconds:$millisecondsFirstTwo";
  }

  void prewarmFFT() async {
    // Create a small dummy signal
    List<double> dummySignal = List.filled(1024, 0.0);
    // Fill it with some dummy data
    for (int i = 0; i < dummySignal.length; i++) {
      dummySignal[i] = sin(2 * pi * i / dummySignal.length);
    }
    // Get a padded length for the dummy signal (e.g., next power of 2)
    int paddedLength = _nextPowerOf2(dummySignal.length);
    final fft = FFT(paddedLength);
    // Perform a dummy FFT
    List<double> paddedDummy = List.filled(paddedLength, 0.0);
    paddedDummy.setAll(0, dummySignal);
    normalize(paddedDummy);
    fft.realFft(paddedDummy);
  }

  void _startMeterPolling() {
    if (_meterPolling) return;
    _meterPolling = true;

    _meterTimer?.cancel();
    _meterDecayTimer?.cancel();

    _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      // prevent overlapping async ticks (super important)
      if (!_meterPolling) return; // stopped mid-flight
      if (_meterPollingBusy) return; // prevent overlap
      _meterPollingBusy = true;

      try {
        final packed = await JuceAudioEngine.getAllMeterValues();
        if (!_meterPolling || packed.isEmpty) return;

        // expected length: 5 * (1 + kNumRows)
        final stride = _meterStride;

        // ---- MASTER ----
        if (packed.length >= stride) {
          final m0 = 0;

          _meters.setMaster(
            MeterFrame(
              peakL: packed[m0 + 0].clamp(0.0, 1.0),
              peakR: packed[m0 + 1].clamp(0.0, 1.0),
              rmsL: packed[m0 + 2].clamp(0.0, 1.0),
              rmsR: packed[m0 + 3].clamp(0.0, 1.0),
              clip: packed[m0 + 4] > 0.5,
            ),
          );
        }

        // ---- ROWS ----
        // Use whichever source of truth you already have:
        // - kNumRows (your constant)
        // - or _meters.rows.length
        final rowCount = _rowCount; // or: _meters.rows.length

        for (int row = 0; row < rowCount; row++) {
          final base = stride * (1 + row);
          if (base + 4 >= packed.length) break;

          _meters.setRow(
            row,
            MeterFrame(
              peakL: packed[base + 0].clamp(0.0, 1.0),
              peakR: packed[base + 1].clamp(0.0, 1.0),
              rmsL: packed[base + 2].clamp(0.0, 1.0),
              rmsR: packed[base + 3].clamp(0.0, 1.0),
              clip: packed[base + 4] > 0.5,
            ),
          );
        }
      } catch (_) {
        // ignore transient channel errors
      } finally {
        _meterPollingBusy = false;
      }
    });
  }

  void _stopMeterPolling({bool decayToZero = true}) {
    _meterPolling = false;
    _meterTimer?.cancel();
    _meterTimer = null;

    // in case we stopped while an await was in-flight
    _meterPollingBusy = false;

    if (!decayToZero) {
      _meterDecayTimer?.cancel();
      _meters.zeroAll();
      return;
    }

    _startMeterDecayToZero();
  }

  void _startMeterDecayToZero() {
    _meterDecayTimer?.cancel();

    // ~30fps-ish but cheap
    _meterDecayTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      // if we started polling again, stop decaying
      if (_meterPolling) {
        _meterDecayTimer?.cancel();
        _meterDecayTimer = null;
        return;
      }

      _meters.decayAll(mul: 0.82); // tweak feel: 0.75 faster, 0.9 slower

      if (_meters.isAllZero) {
        _meterDecayTimer?.cancel();
        _meterDecayTimer = null;
      }
    });
  }

  /// Calculate effective audio position for a given track based on video position.
  Duration _calculateEffectiveAudioPositionForTrack(
      AudioTrack track, Duration videoPos) {
    final offsetDuration =
        Duration(milliseconds: (track.offset * 1000).toInt());
    if (videoPos < offsetDuration) {
      return track.trimStart;
    } else {
      var effectiveAudioPos = track.trimStart + (videoPos - offsetDuration);
      if (effectiveAudioPos > track.trimEnd) {
        effectiveAudioPos = track.trimEnd;
      }
      return effectiveAudioPos;
    }
  }

  // PLAY/PAUSE TOGGLE using a global _audioStarted flag.
  Future<void> _togglePlayPause() async {
    await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    return;
  }

  Future<void> _togglePlayPauseAudio(StateSetter setLocalState) async {
    // if (_audioTracks.isEmpty) {
    //   return;
    // }

    setState(() {
      //NOTE: before it was setLocalState, shouldn't have broke anything tho
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _resumeAudio(setLocalState);
    } else {
      _pauseAudio(setLocalState);
    }
  }

  Future<void> _resumeAudio(StateSetter setLocalState) async {
    JuceAudioEngine.setTransportSeconds(
        _globalAudioClock.inMilliseconds.toDouble() / 1000.0);
    JuceAudioEngine.setMetronomeTransportMs(
        _globalAudioClock.inMilliseconds.toDouble());
    JuceAudioEngine.play();
    _syncTransportClock(_globalAudioClock, playing: true);
    unawaited(_pollTransportFromJuceIfNeeded(force: true));

    _transportTicker?.start();

    _startMeterPolling();
  }

  Future<void> _pauseAudio(StateSetter setLocalState) async {
    // On pause, cancel the timer, pause each track, and importantly, reset audioStarted.
    // _audioAutomationTimer?.cancel();
    _transportTicker?.stop();

    for (var track in _audioTracks) {
      // await track.player.pause();
      // maybe below deprecated?
      track.audioStarted =
          false; // Reset flag on pause so that resume triggers play.
    }
    await JuceAudioEngine.pause();
    await _pollTransportFromJuceIfNeeded(force: true);
    _syncTransportClock(_globalAudioClock, playing: false);

    _stopMeterPolling();
  }

  Future<void> _restartAudio(StateSetter setLocalState) async {
    // Pause all tracks and seek them to their trimStart.
    // _audioAutomationTimer?.cancel();
    _transportTicker?.stop();

    Duration newStartPoint = Duration.zero;

    // Case of loop is enabled
    if (_loopEnabled) {
      newStartPoint = Duration(milliseconds: _loopStartMs);
    }

    for (final track in _audioTracks) {
      track.audioStarted = false;
      track.audioStartTimer?.cancel();
      track.currentPosition = newStartPoint;
    }
    JuceAudioEngine.pause();
    JuceAudioEngine.setTransportSeconds(newStartPoint.inMilliseconds / 1000.0);

    // Reset the global audio clock.
    setState(() {
      _syncTransportClock(newStartPoint, playing: false);
      _isPlaying = false;
    });

    _stopMeterPolling();
  }

  // Pause helper
  Future<void> _pausePlayback() async {
    _transportTicker?.stop();

    // Pause all audio tracks at precise position
    for (var track in _audioTracks) {
      track.audioStartTimer
          ?.cancel(); // NEED THIS IN CASE THERE WAS A TIMER STARTED
    }
    await JuceAudioEngine.pause();
    await _pollTransportFromJuceIfNeeded(force: true);
    _syncTransportClock(_globalAudioClock, playing: false);
  }

  Future<_AudioExportSettings?> _showAudioExportSettingsSheet() async {
    _ExportAudioFormat selectedFormat = _audioExportSettings.format;
    int selectedSampleRate = _audioExportSettings.sampleRate;
    int selectedWavBitDepth = _audioExportSettings.wavBitDepth;
    bool selectedWavDithering = _audioExportSettings.wavDithering;
    int selectedMp3Bitrate = _audioExportSettings.mp3BitrateKbps;
    _ExportMp3Mode selectedMp3Mode = _audioExportSettings.mp3Mode;
    int selectedMp3VbrQuality = _audioExportSettings.mp3VbrQuality;
    _ExportChannelMode selectedChannelMode = _audioExportSettings.channelMode;
    bool selectedNormalize = _audioExportSettings.normalize;
    double selectedNormalizeTargetDb = _audioExportSettings.normalizeTargetDb;
    _ExportResampleQuality selectedResampleQuality =
        _audioExportSettings.resampleQuality;
    bool showAdvanced = false;
    if (!_kExportSampleRates.contains(selectedSampleRate)) {
      selectedSampleRate = _kExportSampleRates.first;
    }
    if (!_kExportWavBitDepths.contains(selectedWavBitDepth)) {
      selectedWavBitDepth = _kExportWavBitDepths.first;
    }
    if (!_kExportMp3Bitrates.contains(selectedMp3Bitrate)) {
      selectedMp3Bitrate = _kExportMp3Bitrates.first;
    }
    if (!_kExportMp3VbrQualities.contains(selectedMp3VbrQuality)) {
      selectedMp3VbrQuality = _kExportMp3VbrQualities.first;
    }
    if (!_kExportNormalizeTargetsDb.contains(selectedNormalizeTargetDb)) {
      selectedNormalizeTargetDb = _kExportNormalizeTargetsDb[1];
    }
    if (!_ExportMp3Mode.values.contains(selectedMp3Mode)) {
      selectedMp3Mode = _ExportMp3Mode.cbr;
    }
    if (!_ExportChannelMode.values.contains(selectedChannelMode)) {
      selectedChannelMode = _ExportChannelMode.stereo;
    }
    if (!_ExportResampleQuality.values.contains(selectedResampleQuality)) {
      selectedResampleQuality = _ExportResampleQuality.best;
    }

    return showDialog<_AudioExportSettings>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.58),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        const panelTop = Color(0xFF1A2233);
        const panelBottom = Color(0xFF111725);
        const accent = Color(0xFF6EA7FF);
        const border = Color(0x334B6F9E);
        const fieldFill = Color(0xFF151D2B);
        final mutedText = Colors.white.withOpacity(0.74);

        Widget buildDropdownField<T>({
          required String label,
          required T value,
          required List<T> options,
          required ValueChanged<T?> onChanged,
          required String Function(T) textBuilder,
        }) {
          return DropdownButtonFormField<T>(
            value: value,
            dropdownColor: const Color(0xFF232E42),
            iconEnabledColor: Colors.white.withOpacity(0.76),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.68)),
              filled: true,
              fillColor: fieldFill,
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: accent, width: 1.1),
              ),
            ),
            items: options
                .map((option) => DropdownMenuItem<T>(
                      value: option,
                      child: Text(textBuilder(option)),
                    ))
                .toList(),
            onChanged: onChanged,
          );
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget buildFormatOption({
              required _ExportAudioFormat format,
              required String label,
              required bool isLeft,
            }) {
              final isSelected = selectedFormat == format;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.horizontal(
                    left: isLeft ? const Radius.circular(12) : Radius.zero,
                    right: isLeft ? Radius.zero : const Radius.circular(12),
                  ),
                  onTap: () => setSheetState(() => selectedFormat = format),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0x553F73C8)
                          : Colors.transparent,
                      borderRadius: BorderRadius.horizontal(
                        left: isLeft ? const Radius.circular(12) : Radius.zero,
                        right: isLeft ? Radius.zero : const Radius.circular(12),
                      ),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6EA7FF)
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w700,
                            color: isSelected ? Colors.white : mutedText,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: Color(0xFF9BC4FF),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(dialogContext).viewInsets.bottom + 16,
              ),
              child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [panelTop, panelBottom],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Export',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: border),
                              color: const Color(0xFF141C2A),
                            ),
                            child: Row(
                              children: [
                                buildFormatOption(
                                  format: _ExportAudioFormat.wav,
                                  label: 'WAV',
                                  isLeft: true,
                                ),
                                Container(
                                  width: 1,
                                  height: 48,
                                  color: const Color(0x223A5A88),
                                ),
                                buildFormatOption(
                                  format: _ExportAudioFormat.mp3,
                                  label: 'MP3',
                                  isLeft: false,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setSheetState(() => showAdvanced = !showAdvanced);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Advanced options',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withOpacity(0.86),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    showAdvanced
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: mutedText,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (showAdvanced) ...[
                            const SizedBox(height: 10),
                            Theme(
                              data: theme.copyWith(
                                unselectedWidgetColor:
                                    Colors.white.withOpacity(0.45),
                                colorScheme: theme.colorScheme.copyWith(
                                  primary: accent,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  buildDropdownField(
                                    label: 'Sample rate',
                                    value: selectedSampleRate,
                                    options: _kExportSampleRates,
                                    textBuilder: (value) => '$value Hz',
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setSheetState(() {
                                        selectedSampleRate = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  buildDropdownField(
                                    label: 'Channels',
                                    value: selectedChannelMode,
                                    options: _ExportChannelMode.values,
                                    textBuilder: (value) =>
                                        value == _ExportChannelMode.stereo
                                            ? 'Stereo'
                                            : 'Mono',
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setSheetState(() {
                                        selectedChannelMode = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  buildDropdownField(
                                    label: 'Resample quality',
                                    value: selectedResampleQuality,
                                    options: _ExportResampleQuality.values,
                                    textBuilder: (value) {
                                      switch (value) {
                                        case _ExportResampleQuality.draft:
                                          return 'Draft (fast)';
                                        case _ExportResampleQuality.good:
                                          return 'Good';
                                        case _ExportResampleQuality.best:
                                          return 'Best';
                                      }
                                    },
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setSheetState(() {
                                        selectedResampleQuality = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Normalize loudness',
                                      style: TextStyle(color: mutedText),
                                    ),
                                    value: selectedNormalize,
                                    activeColor: accent,
                                    onChanged: (value) {
                                      setSheetState(() {
                                        selectedNormalize = value;
                                      });
                                    },
                                  ),
                                  if (selectedNormalize) ...[
                                    const SizedBox(height: 4),
                                    buildDropdownField(
                                      label: 'Limiter ceiling (dBTP)',
                                      value: selectedNormalizeTargetDb,
                                      options: _kExportNormalizeTargetsDb,
                                      textBuilder: (value) =>
                                          '${value.toStringAsFixed(1)} dB',
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setSheetState(() {
                                          selectedNormalizeTargetDb = value;
                                        });
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  if (selectedFormat ==
                                      _ExportAudioFormat.wav) ...[
                                    buildDropdownField(
                                      label: 'Bit depth',
                                      value: selectedWavBitDepth,
                                      options: _kExportWavBitDepths,
                                      textBuilder: (value) => '$value-bit',
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setSheetState(() {
                                          selectedWavBitDepth = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'Enable dithering',
                                        style: TextStyle(color: mutedText),
                                      ),
                                      value: selectedWavDithering,
                                      activeColor: accent,
                                      onChanged: (value) {
                                        setSheetState(() {
                                          selectedWavDithering = value;
                                        });
                                      },
                                    ),
                                  ] else ...[
                                    buildDropdownField(
                                      label: 'Encoding mode',
                                      value: selectedMp3Mode,
                                      options: _ExportMp3Mode.values,
                                      textBuilder: (value) =>
                                          value == _ExportMp3Mode.cbr
                                              ? 'CBR'
                                              : 'VBR',
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setSheetState(() {
                                          selectedMp3Mode = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    if (selectedMp3Mode == _ExportMp3Mode.cbr)
                                      buildDropdownField(
                                        label: 'Bit rate',
                                        value: selectedMp3Bitrate,
                                        options: _kExportMp3Bitrates,
                                        textBuilder: (value) => '${value} kbps',
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setSheetState(() {
                                            selectedMp3Bitrate = value;
                                          });
                                        },
                                      )
                                    else
                                      buildDropdownField(
                                        label: 'VBR quality',
                                        value: selectedMp3VbrQuality,
                                        options: _kExportMp3VbrQualities,
                                        textBuilder: (value) =>
                                            'V$value (${value == 0 ? "highest" : "smaller file"})',
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setSheetState(() {
                                            selectedMp3VbrQuality = value;
                                          });
                                        },
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Colors.white.withOpacity(0.74),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E6EEB),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(
                                      dialogContext,
                                      _AudioExportSettings(
                                        format: selectedFormat,
                                        sampleRate: selectedSampleRate,
                                        wavBitDepth: selectedWavBitDepth,
                                        wavDithering: selectedWavDithering,
                                        mp3BitrateKbps: selectedMp3Bitrate,
                                        mp3Mode: selectedMp3Mode,
                                        mp3VbrQuality: selectedMp3VbrQuality,
                                        channelMode: selectedChannelMode,
                                        normalize: selectedNormalize,
                                        normalizeTargetDb:
                                            selectedNormalizeTargetDb,
                                        resampleQuality:
                                            selectedResampleQuality,
                                      ),
                                    );
                                  },
                                  child: const Text('Start export'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _wavCodecForBitDepth(int bitDepth) {
    switch (bitDepth) {
      case 24:
        return 'pcm_s24le';
      case 32:
        return 'pcm_f32le';
      case 16:
      default:
        return 'pcm_s16le';
    }
  }

  String _buildResampleFilter(_AudioExportSettings settings) {
    final isWav = settings.format == _ExportAudioFormat.wav;
    final ditherMethod = settings.wavDithering ? 'triangular' : 'none';
    switch (settings.resampleQuality) {
      case _ExportResampleQuality.draft:
        return isWav
            ? 'aresample=${settings.sampleRate}:resampler=swr:dither_method=$ditherMethod'
            : 'aresample=${settings.sampleRate}:resampler=swr';
      case _ExportResampleQuality.good:
        return isWav
            ? 'aresample=${settings.sampleRate}:resampler=soxr:precision=20:dither_method=$ditherMethod'
            : 'aresample=${settings.sampleRate}:resampler=soxr:precision=20';
      case _ExportResampleQuality.best:
        return isWav
            ? 'aresample=${settings.sampleRate}:resampler=soxr:precision=28:dither_method=$ditherMethod'
            : 'aresample=${settings.sampleRate}:resampler=soxr:precision=28';
    }
  }

  String _buildExportFilter(
    _AudioExportSettings settings, {
    double safetyTrimDb = 0.0,
  }) {
    final List<String> filters = [_buildResampleFilter(settings)];
    if (settings.channelMode == _ExportChannelMode.mono) {
      filters.add('aformat=channel_layouts=mono');
    } else {
      filters.add('aformat=channel_layouts=stereo');
    }
    if (settings.normalize) {
      filters.add(
        'loudnorm=I=-14:LRA=11:TP=${settings.normalizeTargetDb.toStringAsFixed(1)}:linear=true',
      );
    } else {
      if (safetyTrimDb < -0.01) {
        filters.add('volume=${safetyTrimDb.toStringAsFixed(2)}dB');
      }
      if (settings.format == _ExportAudioFormat.mp3) {
        // MP3 encoding can accentuate near-full-scale low-end transients.
        filters.add('alimiter=limit=0.89:level=disabled:asc=true');
      }
    }
    return filters.join(',');
  }

  double _targetPeakDbForSafetyTrim(_AudioExportSettings settings) {
    if (settings.format == _ExportAudioFormat.mp3) {
      return -2.0;
    }
    return -1.0;
  }

  double? _parseMaxVolumeDb(String text) {
    if (text.trim().isEmpty) return null;
    final maxVolumeRegex = RegExp(
      r'max_volume:\s*(-?\d+(?:\.\d+)?)\s*dB',
      caseSensitive: false,
    );

    double? maxVolumeDb;
    for (final match in maxVolumeRegex.allMatches(text)) {
      final parsed = double.tryParse(match.group(1) ?? '');
      if (parsed != null) {
        maxVolumeDb = parsed;
      }
    }
    return maxVolumeDb;
  }

  Future<double> _computeExportSafetyTrimDb({
    required String inputPath,
    required _AudioExportSettings settings,
  }) async {
    if (settings.normalize) return 0.0;

    final targetPeakDb = _targetPeakDbForSafetyTrim(settings);

    try {
      final Session session = await FFmpegKit.execute(
        '-hide_banner -nostats -i "$inputPath" -af volumedetect -f null -',
      );
      final output = await session.getOutput();
      final logsAsString = await session.getLogsAsString();
      final List<Log> logs = await session.getLogs();
      final combined = StringBuffer();
      if (output != null && output.isNotEmpty) {
        combined.writeln(output);
      }
      if (logsAsString.isNotEmpty) {
        combined.writeln(logsAsString);
      }
      for (final log in logs) {
        final line = log.getMessage();
        if (line.isNotEmpty) {
          combined.writeln(line);
        }
      }

      final maxVolumeDb = _parseMaxVolumeDb(combined.toString());
      if (maxVolumeDb == null) {
        // Keep a conservative fallback headroom when analysis output is unavailable.
        return targetPeakDb;
      }

      if (maxVolumeDb <= targetPeakDb) return 0.0;

      return (targetPeakDb - maxVolumeDb).clamp(-24.0, 0.0).toDouble();
    } catch (_) {
      return targetPeakDb;
    }
  }

  Future<String> _convertMixWithExportSettings({
    required String inputPath,
    required _AudioExportSettings settings,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.${settings.fileExtension}';

    final safetyTrimDb = await _computeExportSafetyTrimDb(
      inputPath: inputPath,
      settings: settings,
    );
    final filter = _buildExportFilter(
      settings,
      safetyTrimDb: safetyTrimDb,
    );
    final channelCount =
        settings.channelMode == _ExportChannelMode.mono ? '1' : '2';
    final List<String> ffmpegCmd;
    if (settings.format == _ExportAudioFormat.wav) {
      ffmpegCmd = [
        '-i',
        '"$inputPath"',
        if (filter.isNotEmpty) ...['-af', filter],
        '-c:a',
        _wavCodecForBitDepth(settings.wavBitDepth),
        '-ac',
        channelCount,
        '-ar',
        '${settings.sampleRate}',
        '-y',
        '"$outPath"',
      ];
    } else {
      ffmpegCmd = [
        '-i',
        '"$inputPath"',
        if (filter.isNotEmpty) ...['-af', filter],
        '-c:a',
        'libmp3lame',
        if (settings.mp3Mode == _ExportMp3Mode.cbr) ...[
          '-b:a',
          '${settings.mp3BitrateKbps}k',
        ] else ...[
          '-q:a',
          '${settings.mp3VbrQuality}',
        ],
        '-ac',
        channelCount,
        '-ar',
        '${settings.sampleRate}',
        '-y',
        '"$outPath"',
      ];
    }

    try {
      final Session session = await FFmpegKit.execute(ffmpegCmd.join(' '));
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogs();
        final logLines = logs
            .map((log) => log.getMessage())
            .whereType<String>()
            .where((line) => line.trim().isNotEmpty)
            .toList();
        final tail = logLines.length <= 6
            ? logLines.join('\n')
            : logLines.sublist(logLines.length - 6).join('\n');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tail.isNotEmpty
                  ? tail
                  : '${L10n.translate(context, "Export failed")} (RC: $returnCode)',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        return "";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${L10n.translate(context, "Export error")}: ${e.toString().split('\n').first}',
          ),
        ),
      );
      return "";
    }

    final outFile = File(outPath);
    if (!await outFile.exists() || (await outFile.length()) < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.translate(
                context, 'Export failed: Output file missing or too small.'),
          ),
        ),
      );
      return "";
    }
    return outPath;
  }

  Future<int> _resolveRawRenderSampleRate(_AudioExportSettings settings) async {
    final fallback = settings.sampleRate.clamp(8000, 192000).toInt();
    final hostSampleRate = await JuceAudioEngine.getHostSampleRate();
    final hostRateInt = hostSampleRate.round();
    if (hostRateInt >= 8000 && hostRateInt <= 192000) {
      return hostRateInt;
    }
    return fallback;
  }

  bool _canUseNativeWavExport(_AudioExportSettings settings) {
    return settings.format == _ExportAudioFormat.wav &&
        settings.channelMode == _ExportChannelMode.stereo &&
        !settings.normalize;
  }

  Future<String> _exportAudioOnly(ValueChanged<double> onProgress) async {
    if (_audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L10n.translate(context,
                'No audio tracks selected'))), // TODO: FIX THIS WORDING
      );
      return "";
    }

    onProgress(0.0);
    final settings = _activeAudioExportSettings ?? _audioExportSettings;
    final rawRenderSampleRate = await _resolveRawRenderSampleRate(settings);
    final tempDir = await getTemporaryDirectory();

    if (_canUseNativeWavExport(settings)) {
      final nativeOutPath =
          '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.wav';
      try {
        final exportedPath = await JuceAudioEngine.exportMix(
          nativeOutPath,
          format: 'wav',
          sampleRate: rawRenderSampleRate,
          wavBitDepth: settings.wavBitDepth,
          wavDithering: settings.wavDithering,
          mp3BitrateKbps: settings.mp3BitrateKbps,
        );
        onProgress(1.0);

        if (exportedPath.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.translate(context, "Export failed"))),
          );
          return "";
        }

        final outFile = File(exportedPath);
        if (!await outFile.exists() || (await outFile.length()) < 1000) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.translate(context,
                    'Export failed: Output file missing or too small.'),
              ),
            ),
          );
          return "";
        }
        return exportedPath;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${L10n.translate(context, "Export error")}: ${e.toString().split('\n').first}'),
            duration: const Duration(seconds: 5),
          ),
        );
        return "";
      }
    }

    final rawOutPath =
        '${tempDir.path}/audio_export_raw_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      final exportedPath = await JuceAudioEngine.exportMix(
        rawOutPath,
        format: 'wav',
        sampleRate: rawRenderSampleRate,
        wavBitDepth: 32,
        wavDithering: false,
        mp3BitrateKbps: settings.mp3BitrateKbps,
      );
      onProgress(0.8);

      if (exportedPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.translate(context, "Export failed"))));
        return "";
      }

      final outFile = File(exportedPath);
      if (!await outFile.exists() || (await outFile.length()) < 1000) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.translate(
                context, 'Export failed: Output file missing or too small.')),
          ),
        );
        return "";
      }

      onProgress(0.9);
      final convertedPath = await _convertMixWithExportSettings(
        inputPath: exportedPath,
        settings: settings,
      );
      onProgress(1.0);
      return convertedPath;
    } catch (e) {
      print("Full export error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${L10n.translate(context, "Export error")}: ${e.toString().split('\n').first}'),
          duration: Duration(seconds: 5),
        ),
      );
    }
    return "";
  }

  // THINGS FOR AI SYNC---------

  // Extract PCM samples from raw bytes
  List<double> extractPcmSamples(Uint8List audioBytes) {
    List<double> samples = [];

    // Ensure we read in **pairs** of bytes (16-bit PCM)
    for (int i = 0; i < audioBytes.length - 1; i += 2) {
      int sample = audioBytes[i] | (audioBytes[i + 1] << 8);

      // Convert to signed 16-bit integer
      if (sample >= 0x8000) sample -= 0x10000;

      // Normalize to range -1.0 to 1.0
      samples.add(sample / 32768.0);
    }

    print("✅ Extracted ${samples.length} PCM samples.");

    return samples;
  }

  double computeCorrelation(List<double> signalA, List<double> signalB) {
    double sum = 0;
    int len = min(signalA.length, signalB.length);

    for (int i = 0; i < len; i++) {
      sum += signalA[i] * signalB[i];
    }

    return sum;
  }

  Future<int> findBestSyncOffset(
      String videoAudioPath, String trackAudioPath) async {
    final ReceivePort receivePort = ReceivePort();
    final ReceivePort progressPort = ReceivePort(); // for reporting UI progress

    // ✅ Extract Audio Before Processing
    String extractedVideoAudio = await extractAudioFromVideo(videoAudioPath);
    String convertedTrackAudio = await convertAudioToWav(trackAudioPath);

    double videoSampleRate = await getSampleRate(extractedVideoAudio);
    double trackSampleRate = await getSampleRate(convertedTrackAudio);

    // Listen for progress updates
    progressPort.listen((message) {
      if (message is double) {
        setState(() {
          _syncProgress = message;
        });
      }
    });

    await Isolate.spawn(_findSyncOffsetInBackground, [
      receivePort.sendPort,
      extractedVideoAudio,
      convertedTrackAudio,
      trackSampleRate,
      progressPort.sendPort,
    ]);

    final result = await receivePort.first as int;
    progressPort.close();
    return result;
  }

  Future<void> applyBestSyncOffset(
      AudioTrack track, String videoAudioPath) async {
    int syncOffset = await findBestSyncOffset(videoAudioPath, track.file.path);
    final int audioLengthMs = track.audioDuration.inMilliseconds;
    final int offsetLimit = 180000; // 180 seconds

    if (syncOffset >= 0 && syncOffset > offsetLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L10n.translate(context,
                'AI Sync failed: Computed offset exceeds audio length.'))),
      );
      return;
    } else if (syncOffset < 0 && syncOffset.abs() > audioLengthMs) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L10n.translate(context,
                'AI Sync failed: Computed trim exceeds audio length.'))),
      );
      return;
    }

    setState(() {
      // Adjust track offset or trim start based on offset direction
      if (syncOffset >= 0) {
        // Delay the track (shift right)
        track.offset = syncOffset / 1000.0;
        track.trimStart = Duration(seconds: 0);
      } else {
        // Trim the track (shift left)
        // double trimAdjustment = syncOffset.abs() / 1000.0;
        track.trimStart =
            Duration(milliseconds: syncOffset.abs()); //trimAdjustment.toInt());
        track.offset = 0.0;
      }
    });

    // Refresh UI
    setState(() {});
    print(
        "✅ AI Sync applied. Adjusted Offset: ${track.offset}, Trim Start: ${track.trimStart}");
  }

  // THINGS FOR AI SYNC END-----

  List<double> normalizeWaveform(List<double> data) {
    if (data.isEmpty) return [];

    final maxAmplitude =
        data.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    if (maxAmplitude == 0) return List.filled(data.length, 0.0);

    return data.map((v) => v / maxAmplitude).toList();
  }

  List<double> amplifyAndCapWaveform(List<double> data) {
    if (data.isEmpty) return [];

    return data.map((v) {
      final amplified = v * 4.0;

      if (amplified > 1.0) return 1.0;
      if (amplified < -1.0) return -1.0;
      return amplified;
    }).toList();
  }

  // FOR ANDROID ONLY SINCE EXTRACTWAVEFORM IS WEIRD
  List<double> resampleLinear(List<double> data, int targetCount) {
    if (data.isEmpty || targetCount <= 0) return const [];
    if (data.length == targetCount) return List<double>.from(data);

    final n = data.length;
    return List<double>.generate(targetCount, (i) {
      final t = i * (n - 1) / (targetCount - 1);
      final a = t.floor();
      final b = (a + 1 < n) ? a + 1 : a;
      final f = t - a;
      return data[a] * (1.0 - f) + data[b] * f;
    });
  }

  // 4. Progress Indicator Widget (add to your build method)
  Widget _buildProgressIndicator() {
    if (!_showProgressDialog) return const SizedBox.shrink();

    return AlertDialog(
      title: Text(_currentOperation),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_progressMessage),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _downloadProgress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecordingJuce() async {
    // 1) Require a selected row
    if (_rowCount <= 0 || _selectedRow < 0 || _selectedRow >= _rowCount) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a track to record on first.')));
      return;
    }

    if (_loopEnabled) {
      await _restartAudio(_safeAudioEditorStateSetter);
    }

    // 2) Determine where in the project we start recording (UNCHANGED)
    _recordingStartMs = _globalAudioClock.inMilliseconds.toDouble();

    // 3) If not already playing, start playback (UNCHANGED)
    if (!_isPlaying) {
      await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    }

    // 4) Prepare file path (CHANGE → WAV)
    final audioDir = ProjectManager.audioDir(_projectDir);
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    final filePath = p.join(audioDir.path,
        'mixroom_rec_${DateTime.now().millisecondsSinceEpoch}.wav');

    // 5) Start JUCE recording (NEW)
    final ok = await JuceAudioEngine.startRecording(
      filePath,
      _selectedChannelStart,
      2, //_selectedChannelCount, TODO: (TEMP TO ALLOW NANOCORTEX RECORDING) (do the 1+2, 3+4 selection stuff)
    );

    print("printing $_selectedChannelStart $_selectedChannelCount");

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start recording')));
      return;
    }

    // 6) UI state (UNCHANGED)
    setState(() {
      _recordingFilePath = filePath;
      _isRecording = true;
    });

    _recordingPeaks.clear();

    _recordingPeakTimer?.cancel();
    _recordingPeakTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!_isRecording) return;

      final peak = await JuceAudioEngine.getRecordingPeak();
      setState(() {
        _recordingPeaks.add(peak.clamp(0.0, 1.0).toDouble());
      });
    });
  }

  Future<void> _stopRecordingJuce({bool keepPlaying = true}) async {
    if (!_isRecording) return;

    _recordingPeakTimer?.cancel();
    _recordingPeakTimer = null;

    // 1) Stop JUCE recorder
    await JuceAudioEngine.stopRecording();

    if (_recordingFilePath == null || !File(_recordingFilePath!).existsSync()) {
      setState(() {
        _isRecording = false;
        _recordingFilePath = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(
          content: Text('Recording failed or no data captured.')));
      return;
    }

    final int row =
        (_selectedRow >= 0 && _selectedRow < _rowCount) ? _selectedRow : 0;
    final double startMs = _recordingStartMs;

    setState(() {
      _isRecording = false;
    });

    // 2) Insert recorded clip (UNCHANGED)
    try {
      await _undoManager.execute(
        AddAudioTrackAction(
          addTrack: ({
            required File file,
            required int row,
            required double timeMs,
            Duration? trimStartRequested,
            Duration? trimEndRequested,
          }) =>
              _addAudioTrackFromFile(file, row, timeMs),
          tracks: _audioTracks,
          file: File(_recordingFilePath!),
          row: row,
          timeMs: startMs,
        ),
      );
    } catch (e) {
      debugPrint("Error adding recorded track: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add recorded track.')));
    }

    // 3) Optionally stop playback (UNCHANGED)
    if (!keepPlaying && _isPlaying) {
      await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    }
  }

  Future<void> _addAudioTrackFromFile(
    File fromFile,
    int row,
    double timeMs, {
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) async {
    if (_audioTracks.length >= kNumClips) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }

    _pausePlayback();
    await _ensureRowIndexExists(row);
    await _ensureRowExistsForClipInsertion();
    final safeRow = _rowCount == 0 ? 0 : row.clamp(0, _rowCount - 1);
    final rowId = _rowIdAt(safeRow);
    final engineClipId = _allocateEngineClipId();
    if (engineClipId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }
    setState(() {
      _isLoadingAudio = true;
    });

    final newFile = fromFile; //File(result.files.single.path!);

    final audioDir = ProjectManager.audioDir(_projectDir);
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    if (!newFile.existsSync()) return;

    final baseName = p.basename(newFile.path);
    final baseNameNoExt = baseName.contains('.')
        ? baseName.substring(0, baseName.lastIndexOf('.'))
        : baseName;

    // --- collision-safe temp name ---
    String candidatePath = p.join(audioDir.path, '$baseNameNoExt.wav');

    int suffix = 1;

    // Keep incrementing if another track already uses this temp path
    while (_audioTracks.any((t) => t.file.path == candidatePath)) {
      candidatePath = p.join(audioDir.path, '$baseNameNoExt #$suffix.wav');
      suffix++;
    }

    final resampledPath = candidatePath;

    // 1) Transcode to 48 kHz PCM WAV (fast, one‐time cost):
    // TODO: maybe change this to preserve user's input data
    await FFmpegKit.execute(
      '-i "${newFile.path}" -ar 48000 -y "$resampledPath"', // DO .WAV
    );
    final newFile_48 = File(resampledPath);

    final startSec = timeMs / 1000.0;
    final requestedTrimStart = trimStartRequested ?? Duration.zero;
    final requestedInFileOffsetSec = requestedTrimStart.inMilliseconds / 1000.0;
    final requestedLengthSec = trimEndRequested != null
        ? math.max(
            0.0,
            (trimEndRequested - requestedTrimStart).inMilliseconds / 1000.0,
          )
        : 0.0;
    await JuceAudioEngine.loadClip(
      engineClipId,
      rowId,
      newFile_48.path,
      startSec: startSec,
      lengthSec: requestedLengthSec,
      inFileOffsetSec: math.max(0.0, requestedInFileOffsetSec),
    );

    // final dur = await JuceAudioEngine.getTrackDuration(0);
    final durSeconds = await JuceAudioEngine.getTrackDuration(engineClipId);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());

    // Create a new AudioTrack instance with a fixed audioDuration.
    final newTrack = await AudioTrack.create(
      file: newFile_48,
      originalFile: newFile_48, // might be unused
      audioDuration: dur, // Fixed duration for this track.
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0,
      crossfade: 1.0,
      rowIndex: safeRow,
      rowId: rowId,
      engineClipId: engineClipId,
      label: baseNameNoExt,
    );

    _startWaveformExtraction(newTrack);

    setState(() {
      newTrack.offset = startSec;
      newTrack.trimStart = trimStartRequested ?? Duration.zero;
      newTrack.trimEnd = trimEndRequested ?? dur;
      _audioTracks.add(newTrack);
      _isLoadingAudio = false;
    });
    await _syncClipMixToEngine(newTrack);
    _updateOverallDurationIfNeeded();
  }

  // optimized to not make unnecessary calls that normal addAudioTrack needs
  Future<void> _pasteAudioTrack(
    AudioTrack clip,
    int row,
    double timeMs, {
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) async {
    if (_audioTracks.length >= kNumClips) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }

    await _ensureRowIndexExists(row);
    await _ensureRowExistsForClipInsertion();
    final safeRow = _rowCount == 0 ? 0 : row.clamp(0, _rowCount - 1);
    final rowId = _rowIdAt(safeRow);
    final engineClipId = _allocateEngineClipId();
    if (engineClipId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }
    final requestedTrimStart = trimStartRequested ?? Duration.zero;
    final requestedTrimEnd = trimEndRequested ?? clip.audioDuration;
    final requestedLengthSec = math.max(
      0.0,
      (requestedTrimEnd - requestedTrimStart).inMilliseconds / 1000.0,
    );
    final requestedInFileOffsetSec = requestedTrimStart.inMilliseconds / 1000.0;
    await JuceAudioEngine.loadClip(
      engineClipId,
      rowId,
      clip.file.path,
      startSec: timeMs / 1000.0,
      lengthSec: requestedLengthSec,
      inFileOffsetSec: math.max(0.0, requestedInFileOffsetSec),
    );
    final dur = clip.audioDuration;

    // Create a new AudioTrack instance with a fixed audioDuration.
    final newTrack = await AudioTrack.create(
      file: clip.file,
      originalFile: clip.file, // might be unused
      audioDuration: dur, // Fixed duration for this track.
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0,
      crossfade: 1.0,
      rowIndex: safeRow,
      rowId: rowId,
      engineClipId: engineClipId,
      label: clip.label,
    );

    newTrack.normWaveformData = clip.normWaveformData;

    setState(() {
      newTrack.offset = timeMs / 1000.0;
      newTrack.trimStart = trimStartRequested ?? Duration.zero;
      newTrack.trimEnd = trimEndRequested ?? dur;
      newTrack.gain = clip.gain;
      newTrack.pitchSemitones = clip.pitchSemitones;
      newTrack.sourceTempoBpm = clip.sourceTempoBpm;
      newTrack.stretchToProjectTempo = clip.stretchToProjectTempo;
      newTrack.tempoStretchPreservePitch = clip.tempoStretchPreservePitch;
      _audioTracks.add(newTrack);
    });
    await _syncClipMixToEngine(newTrack);
    _updateOverallDurationIfNeeded();
  }

  // used by loadProject, skips renaming logic in normal addAudioTrack
  Future<void> _addAudioTrackFromProjectFile({
    required File projectAudioFile,
    required String label,
    required int row,
    required double timeMs,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
    double? gain,
    double? pitchSemitones,
    double? sourceTempoBpm,
    bool? stretchToProjectTempo,
    bool? tempoStretchPreservePitch,
    double? crossfade,
    List<AutomationPoint>? automation,
  }) async {
    // no FFmpeg, no temp renaming
    await _ensureRowIndexExists(row);
    await _ensureRowExistsForClipInsertion();
    final safeRow = _rowCount == 0 ? 0 : row.clamp(0, _rowCount - 1);
    final rowId = _rowIdAt(safeRow);
    final engineClipId = _allocateEngineClipId();
    if (engineClipId < 0) return;
    final requestedTrimStart = trimStartRequested ?? Duration.zero;
    final requestedInFileOffsetSec = requestedTrimStart.inMilliseconds / 1000.0;
    final requestedLengthSec = trimEndRequested != null
        ? math.max(
            0.0,
            (trimEndRequested - requestedTrimStart).inMilliseconds / 1000.0,
          )
        : 0.0;
    await JuceAudioEngine.loadClip(
      engineClipId,
      rowId,
      projectAudioFile.path,
      startSec: timeMs / 1000.0,
      lengthSec: requestedLengthSec,
      inFileOffsetSec: math.max(0.0, requestedInFileOffsetSec),
    );

    final durSeconds = await JuceAudioEngine.getTrackDuration(engineClipId);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());

    final newTrack = await AudioTrack.create(
      file: projectAudioFile, // points directly to project/audio
      originalFile: projectAudioFile, // unused
      audioDuration: dur,
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0,
      crossfade: 1.0,
      rowIndex: safeRow,
      rowId: rowId,
      engineClipId: engineClipId,
      label: label,
    );

    newTrack.offset = timeMs / 1000.0;
    newTrack.trimStart = trimStartRequested ?? Duration.zero;
    newTrack.trimEnd = trimEndRequested ?? dur;

    if (gain != null) newTrack.gain = gain;
    if (pitchSemitones != null) newTrack.pitchSemitones = pitchSemitones;
    if (sourceTempoBpm != null) newTrack.sourceTempoBpm = sourceTempoBpm;
    if (stretchToProjectTempo != null) {
      newTrack.stretchToProjectTempo = stretchToProjectTempo;
    }
    if (tempoStretchPreservePitch != null) {
      newTrack.tempoStretchPreservePitch = tempoStretchPreservePitch;
    }
    if (crossfade != null) newTrack.crossfade = crossfade;
    if (automation != null && automation.isNotEmpty) {
      newTrack.volumeAutomation = automation;
    }

    await JuceAudioEngine.setClipTime(
      engineClipId,
      startSec: newTrack.offset,
      lengthSec: _clipTimelineDurationSec(newTrack),
      inFileOffsetSec: newTrack.trimStart.inMilliseconds / 1000.0,
    );

    _startWaveformExtraction(newTrack);
    await _syncClipMixToEngine(newTrack);

    setState(() {
      _audioTracks.add(newTrack);
    });

    _updateOverallDurationIfNeeded();
  }

  Map<String, dynamic> _instrumentSpecById(String id) {
    for (final spec in kInstrumentCatalog) {
      if (spec['id'] == id) return spec;
    }
    return kInstrumentCatalog.first;
  }

  String _instrumentNameFromId(String id) {
    final spec = _instrumentSpecById(id);
    return (spec['name'] as String?) ?? 'Basic Synth';
  }

  Map<String, double> _instrumentParamsFromSpec(Map<String, dynamic> spec) {
    final params = <String, double>{};
    for (final entry in spec.entries) {
      final value = entry.value;
      if (value is num) {
        params[entry.key] = value.toDouble();
      }
    }
    params.putIfAbsent('oscillator', () => 1.0);
    params.putIfAbsent('cutoffHz', () => 3200.0);
    params.putIfAbsent('attackMs', () => 18.0);
    params.putIfAbsent('releaseMs', () => 180.0);
    params.putIfAbsent('drive', () => 0.08);
    return params;
  }

  List<MidiNote> _defaultMidiNotesForInstrument(String instrumentId) {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (instrumentId == 'mixroom.bass_mono') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.9),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.5,
            lengthBeats: 0.75,
            velocity: 0.86),
        MidiNote(
            id: '${now}_2',
            pitch: 38,
            startBeat: 2.5,
            lengthBeats: 1.25,
            velocity: 0.84),
      ];
    }
    if (instrumentId == 'mixroom.soft_pad') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.72),
        MidiNote(
            id: '${now}_1',
            pitch: 64,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.68),
        MidiNote(
            id: '${now}_2',
            pitch: 67,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.68),
      ];
    }
    if (instrumentId == 'mixroom.figbug_wavetable') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 72,
            startBeat: 0.0,
            lengthBeats: 0.75,
            velocity: 0.85),
        MidiNote(
            id: '${now}_1',
            pitch: 74,
            startBeat: 1.0,
            lengthBeats: 0.75,
            velocity: 0.8),
        MidiNote(
            id: '${now}_2',
            pitch: 77,
            startBeat: 2.0,
            lengthBeats: 1.5,
            velocity: 0.88),
      ];
    }
    if (instrumentId == 'mixroom.sarah_harmonic') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 57,
            startBeat: 0.0,
            lengthBeats: 2.0,
            velocity: 0.72),
        MidiNote(
            id: '${now}_1',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 2.0,
            velocity: 0.7),
        MidiNote(
            id: '${now}_2',
            pitch: 64,
            startBeat: 2.0,
            lengthBeats: 2.0,
            velocity: 0.74),
        MidiNote(
            id: '${now}_3',
            pitch: 67,
            startBeat: 2.0,
            lengthBeats: 2.0,
            velocity: 0.7),
      ];
    }
    if (instrumentId == 'mixroom.vanilla_poly') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 0.75,
            velocity: 0.82),
        MidiNote(
            id: '${now}_1',
            pitch: 64,
            startBeat: 0.75,
            lengthBeats: 0.75,
            velocity: 0.8),
        MidiNote(
            id: '${now}_2',
            pitch: 67,
            startBeat: 1.5,
            lengthBeats: 0.75,
            velocity: 0.78),
        MidiNote(
            id: '${now}_3',
            pitch: 72,
            startBeat: 2.25,
            lengthBeats: 1.25,
            velocity: 0.84),
      ];
    }
    if (instrumentId == 'mixroom.duck_synth') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 43,
            startBeat: 0.0,
            lengthBeats: 0.5,
            velocity: 0.9),
        MidiNote(
            id: '${now}_1',
            pitch: 43,
            startBeat: 1.0,
            lengthBeats: 0.5,
            velocity: 0.86),
        MidiNote(
            id: '${now}_2',
            pitch: 46,
            startBeat: 2.0,
            lengthBeats: 0.5,
            velocity: 0.88),
        MidiNote(
            id: '${now}_3',
            pitch: 43,
            startBeat: 3.0,
            lengthBeats: 0.5,
            velocity: 0.9),
      ];
    }
    if (instrumentId == 'mixroom.chow_kick') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.95),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.95),
        MidiNote(
            id: '${now}_2',
            pitch: 36,
            startBeat: 2.0,
            lengthBeats: 0.25,
            velocity: 0.95),
        MidiNote(
            id: '${now}_3',
            pitch: 36,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.95),
      ];
    }
    if (instrumentId == 'mixroom.warm_keys') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.78),
        MidiNote(
            id: '${now}_1',
            pitch: 64,
            startBeat: 1.0,
            lengthBeats: 1.0,
            velocity: 0.74),
        MidiNote(
            id: '${now}_2',
            pitch: 67,
            startBeat: 2.0,
            lengthBeats: 1.0,
            velocity: 0.74),
        MidiNote(
            id: '${now}_3',
            pitch: 72,
            startBeat: 3.0,
            lengthBeats: 1.0,
            velocity: 0.8),
      ];
    }
    if (instrumentId == 'mixroom.super_saw') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 72,
            startBeat: 0.0,
            lengthBeats: 0.5,
            velocity: 0.86),
        MidiNote(
            id: '${now}_1',
            pitch: 74,
            startBeat: 0.5,
            lengthBeats: 0.5,
            velocity: 0.84),
        MidiNote(
            id: '${now}_2',
            pitch: 76,
            startBeat: 1.0,
            lengthBeats: 0.5,
            velocity: 0.84),
        MidiNote(
            id: '${now}_3',
            pitch: 79,
            startBeat: 1.5,
            lengthBeats: 0.5,
            velocity: 0.88),
        MidiNote(
            id: '${now}_4',
            pitch: 81,
            startBeat: 2.0,
            lengthBeats: 0.5,
            velocity: 0.9),
        MidiNote(
            id: '${now}_5',
            pitch: 79,
            startBeat: 3.0,
            lengthBeats: 1.0,
            velocity: 0.86),
      ];
    }
    if (instrumentId == 'mixroom.gentle_pluck') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 67,
            startBeat: 0.0,
            lengthBeats: 0.5,
            velocity: 0.8),
        MidiNote(
            id: '${now}_1',
            pitch: 72,
            startBeat: 1.0,
            lengthBeats: 0.5,
            velocity: 0.78),
        MidiNote(
            id: '${now}_2',
            pitch: 74,
            startBeat: 2.0,
            lengthBeats: 0.5,
            velocity: 0.8),
        MidiNote(
            id: '${now}_3',
            pitch: 79,
            startBeat: 3.0,
            lengthBeats: 0.5,
            velocity: 0.82),
      ];
    }
    if (instrumentId == 'mixroom.sub_bass') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 1.0,
            velocity: 0.9),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.25,
            lengthBeats: 0.75,
            velocity: 0.88),
        MidiNote(
            id: '${now}_2',
            pitch: 38,
            startBeat: 2.25,
            lengthBeats: 0.75,
            velocity: 0.88),
        MidiNote(
            id: '${now}_3',
            pitch: 34,
            startBeat: 3.25,
            lengthBeats: 0.75,
            velocity: 0.9),
      ];
    }
    if (instrumentId == 'mixroom.analog_brass') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 55,
            startBeat: 0.0,
            lengthBeats: 1.5,
            velocity: 0.8),
        MidiNote(
            id: '${now}_1',
            pitch: 59,
            startBeat: 0.0,
            lengthBeats: 1.5,
            velocity: 0.76),
        MidiNote(
            id: '${now}_2',
            pitch: 62,
            startBeat: 2.0,
            lengthBeats: 1.5,
            velocity: 0.8),
        MidiNote(
            id: '${now}_3',
            pitch: 67,
            startBeat: 2.0,
            lengthBeats: 1.5,
            velocity: 0.76),
      ];
    }
    if (instrumentId == 'mixroom.drum_acoustic_easy') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.95),
        MidiNote(
            id: '${now}_1',
            pitch: 38,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.86),
        MidiNote(
            id: '${now}_2',
            pitch: 36,
            startBeat: 2.0,
            lengthBeats: 0.25,
            velocity: 0.94),
        MidiNote(
            id: '${now}_3',
            pitch: 38,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.88),
        MidiNote(
            id: '${now}_4',
            pitch: 42,
            startBeat: 0.0,
            lengthBeats: 0.125,
            velocity: 0.62),
        MidiNote(
            id: '${now}_5',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_8',
            pitch: 42,
            startBeat: 3.5,
            lengthBeats: 0.125,
            velocity: 0.62),
      ];
    }
    if (instrumentId == 'mixroom.drum_808_starter') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.98),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.5,
            lengthBeats: 0.25,
            velocity: 0.94),
        MidiNote(
            id: '${now}_2',
            pitch: 36,
            startBeat: 2.0,
            lengthBeats: 0.25,
            velocity: 0.96),
        MidiNote(
            id: '${now}_3',
            pitch: 36,
            startBeat: 3.25,
            lengthBeats: 0.25,
            velocity: 0.92),
        MidiNote(
            id: '${now}_4',
            pitch: 38,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.84),
        MidiNote(
            id: '${now}_5',
            pitch: 38,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.86),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.6),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 1.0,
            lengthBeats: 0.125,
            velocity: 0.56),
        MidiNote(
            id: '${now}_8',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.6),
        MidiNote(
            id: '${now}_9',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_10',
            pitch: 46,
            startBeat: 3.5,
            lengthBeats: 0.25,
            velocity: 0.72),
      ];
    }
    if (instrumentId == 'mixroom.drum_lofi') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.9),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 2.0,
            lengthBeats: 0.25,
            velocity: 0.88),
        MidiNote(
            id: '${now}_2',
            pitch: 38,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.8),
        MidiNote(
            id: '${now}_3',
            pitch: 38,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.82),
        MidiNote(
            id: '${now}_4',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.54),
        MidiNote(
            id: '${now}_5',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.52),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.5),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 3.5,
            lengthBeats: 0.125,
            velocity: 0.56),
        MidiNote(
            id: '${now}_8',
            pitch: 50,
            startBeat: 2.75,
            lengthBeats: 0.25,
            velocity: 0.64),
      ];
    }
    if (instrumentId == 'mixroom.drum_house') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.96),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.96),
        MidiNote(
            id: '${now}_2',
            pitch: 36,
            startBeat: 2.0,
            lengthBeats: 0.25,
            velocity: 0.96),
        MidiNote(
            id: '${now}_3',
            pitch: 36,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.96),
        MidiNote(
            id: '${now}_4',
            pitch: 39,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.84),
        MidiNote(
            id: '${now}_5',
            pitch: 39,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.86),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.62),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.62),
        MidiNote(
            id: '${now}_8',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.62),
        MidiNote(
            id: '${now}_9',
            pitch: 46,
            startBeat: 3.5,
            lengthBeats: 0.25,
            velocity: 0.74),
      ];
    }
    if (instrumentId == 'mixroom.reese_bass') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.75,
            velocity: 0.9),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.0,
            lengthBeats: 0.5,
            velocity: 0.86),
        MidiNote(
            id: '${now}_2',
            pitch: 39,
            startBeat: 2.0,
            lengthBeats: 0.75,
            velocity: 0.9),
        MidiNote(
            id: '${now}_3',
            pitch: 34,
            startBeat: 3.0,
            lengthBeats: 0.75,
            velocity: 0.88),
      ];
    }
    if (instrumentId == 'mixroom.cinematic_pad') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 48,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.7),
        MidiNote(
            id: '${now}_1',
            pitch: 55,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.64),
        MidiNote(
            id: '${now}_2',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.62),
      ];
    }
    if (instrumentId == 'mixroom.drum_trap') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.98),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 1.75,
            lengthBeats: 0.25,
            velocity: 0.92),
        MidiNote(
            id: '${now}_2',
            pitch: 36,
            startBeat: 2.5,
            lengthBeats: 0.25,
            velocity: 0.94),
        MidiNote(
            id: '${now}_3',
            pitch: 39,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.86),
        MidiNote(
            id: '${now}_4',
            pitch: 39,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.88),
        MidiNote(
            id: '${now}_5',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.56),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.6),
        MidiNote(
            id: '${now}_8',
            pitch: 46,
            startBeat: 3.5,
            lengthBeats: 0.125,
            velocity: 0.72),
        MidiNote(
            id: '${now}_9',
            pitch: 46,
            startBeat: 3.75,
            lengthBeats: 0.125,
            velocity: 0.7),
      ];
    }
    if (instrumentId == 'mixroom.drum_breakbeat') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.94),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 2.5,
            lengthBeats: 0.25,
            velocity: 0.88),
        MidiNote(
            id: '${now}_2',
            pitch: 39,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.86),
        MidiNote(
            id: '${now}_3',
            pitch: 39,
            startBeat: 1.75,
            lengthBeats: 0.25,
            velocity: 0.8),
        MidiNote(
            id: '${now}_4',
            pitch: 39,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.84),
        MidiNote(
            id: '${now}_5',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.62),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.6),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 2.0,
            lengthBeats: 0.125,
            velocity: 0.58),
        MidiNote(
            id: '${now}_8',
            pitch: 46,
            startBeat: 3.5,
            lengthBeats: 0.125,
            velocity: 0.66),
      ];
    }
    if (instrumentId == 'mixroom.drum_dnb') {
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 36,
            startBeat: 0.0,
            lengthBeats: 0.25,
            velocity: 0.98),
        MidiNote(
            id: '${now}_1',
            pitch: 36,
            startBeat: 2.75,
            lengthBeats: 0.25,
            velocity: 0.92),
        MidiNote(
            id: '${now}_2',
            pitch: 39,
            startBeat: 1.0,
            lengthBeats: 0.25,
            velocity: 0.9),
        MidiNote(
            id: '${now}_3',
            pitch: 39,
            startBeat: 3.0,
            lengthBeats: 0.25,
            velocity: 0.9),
        MidiNote(
            id: '${now}_4',
            pitch: 42,
            startBeat: 0.5,
            lengthBeats: 0.125,
            velocity: 0.64),
        MidiNote(
            id: '${now}_5',
            pitch: 42,
            startBeat: 1.5,
            lengthBeats: 0.125,
            velocity: 0.64),
        MidiNote(
            id: '${now}_6',
            pitch: 42,
            startBeat: 2.5,
            lengthBeats: 0.125,
            velocity: 0.66),
        MidiNote(
            id: '${now}_7',
            pitch: 42,
            startBeat: 3.5,
            lengthBeats: 0.125,
            velocity: 0.66),
      ];
    }
    return <MidiNote>[
      MidiNote(
          id: '${now}_0',
          pitch: 60,
          startBeat: 0.0,
          lengthBeats: 1.0,
          velocity: 0.84),
      MidiNote(
          id: '${now}_1',
          pitch: 64,
          startBeat: 1.0,
          lengthBeats: 1.0,
          velocity: 0.8),
      MidiNote(
          id: '${now}_2',
          pitch: 67,
          startBeat: 2.0,
          lengthBeats: 1.0,
          velocity: 0.8),
    ];
  }

  Future<File> _nextInstrumentRenderFile(String instrumentId) async {
    final audioDir = ProjectManager.audioDir(_projectDir);
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    final stem = instrumentId.replaceAll('.', '_');
    final path = p.join(
      audioDir.path,
      '${stem}_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    return File(path);
  }

  Future<void> _renderInstrumentClipToFile({
    required File outFile,
    required String instrumentId,
    required String instrumentName,
    required List<MidiNote> notes,
    required Map<String, double> params,
  }) async {
    if (!await outFile.parent.exists()) {
      await outFile.parent.create(recursive: true);
    }

    final noteMaps = notes
        .map((n) => {
              'id': n.id,
              'pitch': n.pitch,
              'startBeat': n.startBeat,
              'lengthBeats': n.lengthBeats,
              'velocity': n.velocity,
            })
        .toList();

    final renderedPath = await JuceAudioEngine.renderInstrumentClip(
      outPath: outFile.path,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      bpm: _tempo,
      notes: noteMaps,
      params: params,
    );

    if (renderedPath.isNotEmpty && File(renderedPath).existsSync()) {
      return;
    }

    await _renderInstrumentClipWithDartSynth(
      outFile: outFile,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      notes: notes,
      params: params,
      bpm: _tempo,
    );
  }

  Future<void> _renderInstrumentClipWithDartSynth({
    required File outFile,
    required String instrumentId,
    required String instrumentName,
    required List<MidiNote> notes,
    required Map<String, double> params,
    required double bpm,
    double minimumDurationMs = 1200.0,
  }) async {
    const double sampleRate = 48000.0;
    final msPerBeat = 60000.0 / bpm.clamp(1.0, 400.0);
    final preset = _fallbackPresetForInstrument(
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      params: params,
    );

    double endBeat = 4.0;
    for (final n in notes) {
      endBeat = math.max(endBeat, n.startBeat + n.lengthBeats);
    }

    final totalMs = math.max(
        minimumDurationMs, endBeat * msPerBeat + preset.releaseMs + 120.0);
    final totalSamples = math.max(2048, (totalMs * sampleRate / 1000.0).ceil());
    final left = Float32List(totalSamples);
    final right = Float32List(totalSamples);

    final cleanedNotes = notes
        .map((n) => MidiNote(
              id: n.id,
              pitch: n.pitch.clamp(0, 127).toInt(),
              startBeat: math.max(0.0, n.startBeat),
              lengthBeats: math.max(0.0625, n.lengthBeats),
              velocity: n.velocity.clamp(0.0, 1.0).toDouble(),
            ))
        .toList(growable: false);

    for (final note in cleanedNotes) {
      final noteStart =
          (note.startBeat * msPerBeat * sampleRate / 1000.0).round();
      final sustainSamples = math.max(
        1,
        (note.lengthBeats * msPerBeat * sampleRate / 1000.0).round(),
      );
      final attackSamples =
          math.max(1, (preset.attackMs * sampleRate / 1000.0).round());
      final releaseSamples =
          math.max(1, (preset.releaseMs * sampleRate / 1000.0).round());
      final totalNoteSamples = sustainSamples + releaseSamples;
      final freq = 440.0 * math.pow(2.0, (note.pitch - 69) / 12.0);
      final seed = note.pitch * 97 + noteStart * 7 + totalNoteSamples * 13;
      final state = _FallbackNoteState(
        phaseA: _wrapUnitPhase(((note.pitch * 19) % 100) / 100.0),
        phaseB: _wrapUnitPhase(((note.pitch * 37) % 100) / 100.0),
        seed: seed,
      );
      final pan = _clampDouble(
        math.sin(note.pitch * 0.23 + seed * 0.013) * preset.stereoWidth,
        -0.95,
        0.95,
      );
      final leftGain = math.sqrt(0.5 * (1.0 - pan));
      final rightGain = math.sqrt(0.5 * (1.0 + pan));

      for (int i = 0; i < totalNoteSamples; i++) {
        final idx = noteStart + i;
        if (idx < 0 || idx >= left.length) break;

        double env;
        if (i < attackSamples) {
          env = i / attackSamples;
        } else if (i < sustainSamples) {
          env = 1.0;
        } else {
          final relPos = i - sustainSamples;
          env = 1.0 - (relPos / releaseSamples);
        }
        env = env.clamp(0.0, 1.0);
        final noteProgress = totalNoteSamples <= 1
            ? 1.0
            : (i / (totalNoteSamples - 1)).clamp(0.0, 1.0).toDouble();
        final raw = _renderFallbackRawSample(
          preset: preset,
          state: state,
          pitch: note.pitch,
          noteSampleIndex: i,
          frequencyHz: freq.toDouble(),
          noteProgress: noteProgress,
          envelope: env,
          sampleRate: sampleRate,
        );

        final drivenInput = (1.0 + preset.drive * 5.0) * raw;
        final driven = drivenInput / (1.0 + drivenInput.abs());
        final sample = driven * env * note.velocity * preset.outputGain;
        left[idx] += (sample * leftGain).toDouble();
        right[idx] += (sample * rightGain).toDouble();
      }
    }

    double peak = 0.0;
    for (int i = 0; i < left.length; i++) {
      final a = left[i].abs();
      final b = right[i].abs();
      if (a > peak) peak = a;
      if (b > peak) peak = b;
    }
    final norm = peak > 0.98 ? (0.98 / peak) : 1.0;
    for (int i = 0; i < left.length; i++) {
      left[i] = (left[i] * norm).clamp(-1.0, 1.0).toDouble();
      right[i] = (right[i] * norm).clamp(-1.0, 1.0).toDouble();
    }

    await _writeStereoPcm16Wav(
      path: outFile.path,
      sampleRate: sampleRate.toInt(),
      left: left,
      right: right,
    );
  }

  Future<void> _writeStereoPcm16Wav({
    required String path,
    required int sampleRate,
    required Float32List left,
    required Float32List right,
  }) async {
    final frameCount = math.min(left.length, right.length);
    const int channels = 2;
    const int bitsPerSample = 16;
    const int bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = frameCount * channels * bytesPerSample;
    final totalSize = 44 + dataSize;
    final bytes = Uint8List(totalSize);
    final bd = ByteData.view(bytes.buffer);

    void writeAscii(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        bd.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little); // PCM chunk size
    bd.setUint16(20, 1, Endian.little); // PCM format
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
    bd.setUint16(32, channels * bytesPerSample, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    int ptr = 44;
    for (int i = 0; i < frameCount; i++) {
      final l = (left[i].clamp(-1.0, 1.0) * 32767.0).round();
      final r = (right[i].clamp(-1.0, 1.0) * 32767.0).round();
      bd.setInt16(ptr, l, Endian.little);
      bd.setInt16(ptr + 2, r, Endian.little);
      ptr += 4;
    }

    await File(path).writeAsBytes(bytes, flush: true);
  }

  List<Map<String, dynamic>> _midiNotesToEnginePayload(List<MidiNote> notes) {
    return notes
        .map((n) => <String, dynamic>{
              'id': n.id,
              'pitch': n.pitch,
              'startBeat': n.startBeat,
              'lengthBeats': n.lengthBeats,
              'velocity': n.velocity,
            })
        .toList();
  }

  Future<bool> _loadMidiClipIntoEngineLive({
    required int engineClipId,
    required int rowId,
    required String instrumentId,
    required String instrumentName,
    required List<MidiNote> midiNotes,
    required Map<String, double> instrumentParams,
    required double sourceTempoBpm,
    required double startSec,
    required double lengthSec,
    required double inFileOffsetSec,
  }) async {
    if (!_liveMidiEventPlaybackSupported) return false;
    if (engineClipId < 0 || rowId < 0) return false;
    return JuceAudioEngine.loadMidiClip(
      engineClipId,
      rowId,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      notes: _midiNotesToEnginePayload(midiNotes),
      params: Map<String, double>.from(instrumentParams),
      sourceTempoBpm: sourceTempoBpm,
      startSec: startSec,
      lengthSec: math.max(0.0, lengthSec),
      inFileOffsetSec: math.max(0.0, inFileOffsetSec),
    );
  }

  Future<bool> _updateMidiClipEventsLive(AudioTrack clip) async {
    if (!_liveMidiEventPlaybackSupported) return false;
    if (!clip.isMidi || clip.engineClipId < 0) return false;
    return JuceAudioEngine.updateMidiClipEvents(
      clip.engineClipId,
      instrumentId: clip.instrumentId,
      instrumentName: clip.instrumentName,
      notes: _midiNotesToEnginePayload(clip.midiNotes),
      params: Map<String, double>.from(clip.instrumentParams),
      sourceTempoBpm: _resolvedClipSourceTempoBpm(clip),
    );
  }

  void _queueMidiRenderCacheRefresh(AudioTrack clip) {
    if (!clip.isMidi || clip.file.path.isEmpty || clip.engineClipId < 0) return;
    final clipId = clip.engineClipId;
    final token = ++_nextMidiRenderSyncToken;
    _midiRenderSyncTokens[clipId] = token;
    _midiRenderDebounceTimers[clipId]?.cancel();

    final notesSnapshot = clip.midiNotes.map((n) => n.copy()).toList();
    final paramsSnapshot = Map<String, double>.from(clip.instrumentParams);
    final instrumentIdSnapshot = clip.instrumentId;
    final instrumentNameSnapshot = clip.instrumentName;
    final filePathSnapshot = clip.file.path;

    late final Timer debounceTimer;
    debounceTimer = Timer(const Duration(milliseconds: 280), () {
      unawaited(() async {
        try {
          await _renderInstrumentClipToFile(
            outFile: File(filePathSnapshot),
            instrumentId: instrumentIdSnapshot,
            instrumentName: instrumentNameSnapshot,
            notes: notesSnapshot,
            params: paramsSnapshot,
          );
          if (_midiRenderSyncTokens[clipId] != token) return;

          final idx = _clipIndexForEngineId(clipId);
          if (idx < 0 || idx >= _audioTracks.length) return;
          final target = _audioTracks[idx];
          final resolvedDuration =
              await _resolveSampleDuration(filePathSnapshot);
          if (resolvedDuration != null) {
            target.audioDuration = resolvedDuration;
          }
          _startWaveformExtraction(target);
          _updateOverallDurationIfNeeded();
          if (mounted) {
            setState(() {});
          }
        } catch (_) {
          // Best effort cache refresh only.
        } finally {
          if (_midiRenderDebounceTimers[clipId] == debounceTimer) {
            _midiRenderDebounceTimers.remove(clipId);
          }
          if (_midiRenderSyncTokens[clipId] == token) {
            _midiRenderSyncTokens.remove(clipId);
          }
        }
      }());
    });
    _midiRenderDebounceTimers[clipId] = debounceTimer;
  }

  Future<void> _addMidiTrack({
    required String instrumentId,
    required String instrumentName,
    required Map<String, double> instrumentParams,
    required List<MidiNote> midiNotes,
    required int row,
    required double timeMs,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
    File? renderedFile,
    String? label,
    double? gain,
    double? pitchSemitones,
    double? sourceTempoBpm,
    bool? stretchToProjectTempo,
    bool? tempoStretchPreservePitch,
    double? crossfade,
    List<AutomationPoint>? automation,
  }) async {
    if (_audioTracks.length >= kNumClips) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }

    await _ensureRowIndexExists(row);
    await _ensureRowExistsForClipInsertion();
    final safeRow = _rowCount == 0 ? 0 : row.clamp(0, _rowCount - 1);
    final rowId = _rowIdAt(safeRow);
    final engineClipId = _allocateEngineClipId();
    if (engineClipId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }

    final outFile =
        renderedFile ?? await _nextInstrumentRenderFile(instrumentId);
    if (!outFile.existsSync()) {
      await _renderInstrumentClipToFile(
        outFile: outFile,
        instrumentId: instrumentId,
        instrumentName: instrumentName,
        notes: midiNotes,
        params: instrumentParams,
      );
    }

    final requestedTrimStart = trimStartRequested ?? Duration.zero;
    final requestedInFileOffsetSec = requestedTrimStart.inMilliseconds / 1000.0;
    final requestedLengthSec = trimEndRequested != null
        ? math.max(
            0.0,
            (trimEndRequested - requestedTrimStart).inMilliseconds / 1000.0,
          )
        : 0.0;
    final resolvedSourceTempoBpm =
        (sourceTempoBpm != null && sourceTempoBpm > 0.0)
            ? sourceTempoBpm
            : _tempo;
    final resolvedStretchToProjectTempo = stretchToProjectTempo ?? true;
    final resolvedTempoStretchPreservePitch = tempoStretchPreservePitch ?? true;
    final startSec = timeMs / 1000.0;

    final loadedLiveMidi = await _loadMidiClipIntoEngineLive(
      engineClipId: engineClipId,
      rowId: rowId,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      midiNotes: midiNotes,
      instrumentParams: instrumentParams,
      sourceTempoBpm: resolvedSourceTempoBpm,
      startSec: startSec,
      lengthSec: requestedLengthSec,
      inFileOffsetSec: requestedInFileOffsetSec,
    );

    if (!loadedLiveMidi) {
      await JuceAudioEngine.loadClip(
        engineClipId,
        rowId,
        outFile.path,
        startSec: startSec,
        lengthSec: requestedLengthSec,
        inFileOffsetSec: math.max(0.0, requestedInFileOffsetSec),
      );
    }

    final durSeconds = await JuceAudioEngine.getTrackDuration(engineClipId);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());

    final newTrack = await AudioTrack.create(
      file: outFile,
      originalFile: outFile,
      audioDuration: dur,
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0,
      crossfade: 1.0,
      rowIndex: safeRow,
      rowId: rowId,
      engineClipId: engineClipId,
      label: label ?? instrumentName,
      clipKind: ClipKind.midi,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      instrumentParams: Map<String, double>.from(instrumentParams),
      midiNotes: midiNotes.map((n) => n.copy()).toList(),
      sourceTempoBpm: resolvedSourceTempoBpm,
      stretchToProjectTempo: resolvedStretchToProjectTempo,
      tempoStretchPreservePitch: resolvedTempoStretchPreservePitch,
    );

    newTrack.offset = startSec;
    newTrack.trimStart = trimStartRequested ?? Duration.zero;
    newTrack.trimEnd = trimEndRequested ?? dur;

    if (gain != null) newTrack.gain = gain;
    if (pitchSemitones != null) newTrack.pitchSemitones = pitchSemitones;
    newTrack.sourceTempoBpm = resolvedSourceTempoBpm;
    newTrack.stretchToProjectTempo = resolvedStretchToProjectTempo;
    newTrack.tempoStretchPreservePitch = resolvedTempoStretchPreservePitch;
    if (crossfade != null) newTrack.crossfade = crossfade;
    if (automation != null && automation.isNotEmpty) {
      newTrack.volumeAutomation = automation;
    }

    await JuceAudioEngine.setClipTime(
      engineClipId,
      startSec: newTrack.offset,
      lengthSec: _clipTimelineDurationSec(newTrack),
      inFileOffsetSec: newTrack.trimStart.inMilliseconds / 1000.0,
    );

    _startWaveformExtraction(newTrack);
    await _syncClipMixToEngine(newTrack);
    setState(() {
      _audioTracks.add(newTrack);
    });
    _updateOverallDurationIfNeeded();
  }

  Future<void> _pasteMidiTrack(
    AudioTrack clip,
    int row,
    double timeMs, {
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) async {
    if (!clip.isMidi) return;
    await _addMidiTrack(
      instrumentId: clip.instrumentId,
      instrumentName: clip.instrumentName,
      instrumentParams: Map<String, double>.from(clip.instrumentParams),
      midiNotes: clip.midiNotes.map((n) => n.copy()).toList(),
      row: row,
      timeMs: timeMs,
      trimStartRequested: trimStartRequested,
      trimEndRequested: trimEndRequested,
      label: clip.label,
      gain: clip.gain,
      pitchSemitones: clip.pitchSemitones,
      sourceTempoBpm: clip.sourceTempoBpm,
      stretchToProjectTempo: clip.stretchToProjectTempo,
      tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
    );
  }

  Future<void> _addMidiTrackFromProjectFile({
    required File projectAudioFile,
    required String label,
    required int row,
    required double timeMs,
    required String instrumentId,
    required String instrumentName,
    required Map<String, double> instrumentParams,
    required List<MidiNote> midiNotes,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
    double? gain,
    double? pitchSemitones,
    double? sourceTempoBpm,
    bool? stretchToProjectTempo,
    bool? tempoStretchPreservePitch,
    double? crossfade,
    List<AutomationPoint>? automation,
  }) async {
    await _addMidiTrack(
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      instrumentParams: instrumentParams,
      midiNotes: midiNotes,
      row: row,
      timeMs: timeMs,
      trimStartRequested: trimStartRequested,
      trimEndRequested: trimEndRequested,
      renderedFile: projectAudioFile,
      label: label,
      gain: gain,
      pitchSemitones: pitchSemitones,
      sourceTempoBpm: sourceTempoBpm,
      stretchToProjectTempo: stretchToProjectTempo,
      tempoStretchPreservePitch: tempoStretchPreservePitch,
      crossfade: crossfade,
      automation: automation,
    );
  }

  double _rawClipDurationSec(AudioTrack clip) {
    final ms = (clip.trimEnd - clip.trimStart).inMilliseconds.toDouble();
    return math.max(0.0, ms / 1000.0);
  }

  double _resolvedClipSourceTempoBpm(AudioTrack clip) {
    if (clip.sourceTempoBpm > 0.0) {
      return _clampTempo(clip.sourceTempoBpm);
    }
    if (clip.isMidi) {
      return _clampTempo(_tempo);
    }
    return 0.0;
  }

  bool _clipFollowsProjectTempo(AudioTrack clip) {
    if (clip.isMidi) return true;
    if (!_tempoStretchEnabled) return false;
    return clip.stretchToProjectTempo;
  }

  double _clipTimelineDurationSec(AudioTrack clip) {
    final rawSec = _rawClipDurationSec(clip);
    if (rawSec <= 0.0) return 0.0;
    if (!_clipFollowsProjectTempo(clip)) return rawSec;
    final sourceTempoBpm = _resolvedClipSourceTempoBpm(clip);
    if (sourceTempoBpm <= 0.0) return rawSec;
    final clampedProjectTempo = _clampTempo(_tempo);
    final stretchMultiplier = sourceTempoBpm / clampedProjectTempo;
    return (rawSec * stretchMultiplier).clamp(0.001, 36000.0);
  }

  double _clipTimelineDurationMs(AudioTrack clip) {
    return _clipTimelineDurationSec(clip) * 1000.0;
  }

  double _clipFullDurationMsForTrim(AudioTrack clip) {
    if (!clip.isMidi) {
      return clip.audioDuration.inMilliseconds.toDouble();
    }
    // MIDI clips should be extendable beyond rendered note material.
    return 1000.0 * 60.0 * 60.0 * 8.0;
  }

  double _clipTempoStretchPlaybackRatio(AudioTrack clip) {
    final rawSec = _rawClipDurationSec(clip);
    final timelineSec = _clipTimelineDurationSec(clip);
    if (rawSec <= 0.0 || timelineSec <= 0.0) return 1.0;
    return rawSec / timelineSec;
  }

  double _tempoPlaybackRatioForEngine(AudioTrack clip) {
    if (!_clipFollowsProjectTempo(clip)) return 1.0;
    if (_resolvedClipSourceTempoBpm(clip) <= 0.0) return 1.0;
    return _clipTempoStretchPlaybackRatio(clip).clamp(0.05, 20.0);
  }

  bool _clipPreserveTempoPitchInEngine(AudioTrack clip) {
    if (!_clipFollowsProjectTempo(clip)) return false;
    if (clip.isMidi) return true;
    return clip.tempoStretchPreservePitch;
  }

  double _effectiveClipPitchSemitones(AudioTrack clip) {
    return clip.pitchSemitones
        .clamp(_kClipPitchMinSemitones, _kClipPitchMaxSemitones);
  }

  Future<void> _syncAllTempoStretchToEngine() async {
    if (_audioTracks.isEmpty) return;
    for (int i = 0; i < _audioTracks.length; i++) {
      await _syncClipTimingToEngine(i);
      await _syncClipMixToEngine(_audioTracks[i]);
    }
    _updateOverallDurationIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _queueTempoEngineSync() async {
    if (_tempoSyncInFlight) {
      _tempoSyncQueued = true;
      return;
    }
    _tempoSyncInFlight = true;
    do {
      _tempoSyncQueued = false;
      await JuceAudioEngine.setMetronomeBpm(_tempo);
      await _syncAllTempoStretchToEngine();
    } while (_tempoSyncQueued);
    _tempoSyncInFlight = false;
  }

  double _clampTempo(double bpm) => bpm.clamp(20.0, 999.0).toDouble();

  String _formatTempoBpm(double bpm) {
    final t = _clampTempo(bpm);
    if ((t - t.roundToDouble()).abs() < 0.0001) {
      return t.toStringAsFixed(0);
    }
    return t.toStringAsFixed(1);
  }

  Future<void> _promptTempoInput() async {
    final controller = TextEditingController(text: _formatTempoBpm(_tempo));
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Set Tempo', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '20.0 - 999.0',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (raw == null || raw.isEmpty) return;
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null || parsed < 20.0 || parsed > 999.0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter 20.0 to 999.0 BPM')),
      );
      return;
    }
    _setProjectTempoFromUi(parsed);
  }

  Future<void> _showTempoModeInfoDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        title: const Text(
          'Tempo Mode',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Off: Clips ignore project tempo.\n'
          'Resample: Clips follow tempo and shift pitch.\n'
          'Stretch: Clips follow tempo and keep pitch.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _setProjectTempoFromUi(double bpm) {
    final next = _clampTempo(bpm);
    if (next == _tempo) return;
    _setStateAndRefreshProjectSettings(() => _tempo = next);
    unawaited(_queueTempoEngineSync());
  }

  Future<void> _setTempoStretchUiMode({
    required bool enabled,
    required bool preservePitch,
  }) async {
    final follows = _audioTracks
        .where((clip) => !clip.isMidi && clip.stretchToProjectTempo)
        .toList();
    final clipModesAlreadyMatch = follows
        .every((clip) => clip.tempoStretchPreservePitch == preservePitch);
    if (_tempoStretchEnabled == enabled &&
        _tempoStretchPreservePitchDefault == preservePitch &&
        clipModesAlreadyMatch) {
      return;
    }

    _setStateAndRefreshProjectSettings(() {
      _tempoStretchEnabled = enabled;
      _tempoStretchPreservePitchDefault = preservePitch;
      for (final clip in follows) {
        clip.tempoStretchPreservePitch = preservePitch;
      }
    });

    await _syncAllTempoStretchToEngine();
  }

  Future<void> _rerenderMidiTrack(AudioTrack clip) async {
    if (!clip.isMidi || clip.engineClipId < 0) return;
    if (clip.file.path.isEmpty) return;
    clip.sourceTempoBpm = _clampTempo(_tempo);
    clip.stretchToProjectTempo = true;
    clip.tempoStretchPreservePitch = true;

    await _renderInstrumentClipToFile(
      outFile: clip.file,
      instrumentId: clip.instrumentId,
      instrumentName: clip.instrumentName,
      notes: clip.midiNotes,
      params: clip.instrumentParams,
    );

    final rowId = clip.rowId >= 0 ? clip.rowId : _rowIdAt(clip.rowIndex);
    if (rowId < 0) return;
    final startSec = clip.offset;
    final lengthSec = _clipTimelineDurationSec(clip);
    final inFileOffsetSec = clip.trimStart.inMilliseconds.toDouble() / 1000.0;

    await JuceAudioEngine.unloadClip(clip.engineClipId);
    await JuceAudioEngine.loadClip(
      clip.engineClipId,
      rowId,
      clip.file.path,
      startSec: startSec,
      lengthSec: math.max(0.0, lengthSec),
      inFileOffsetSec: math.max(0.0, inFileOffsetSec),
    );
    await _syncClipMixToEngine(clip);

    final durSeconds =
        await JuceAudioEngine.getTrackDuration(clip.engineClipId);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());
    clip.audioDuration = dur;

    _startWaveformExtraction(clip);
    if (mounted) {
      setState(() {});
    }
    _updateOverallDurationIfNeeded();
  }

  Future<void> _syncClipTimingToEngine(int clipIndex,
      {bool skipMoveToRow = false}) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.engineClipId < 0) return;
    if (_rowCount == 0) return;

    final boundedRow = clip.rowIndex.clamp(0, _rowCount - 1);
    clip.rowIndex = boundedRow;
    if (clip.rowId < 0 || _rowIndexForId(clip.rowId) < 0) {
      clip.rowId = _rowIdAt(boundedRow);
    }

    final startSec = clip.offset;
    final lengthSec = _clipTimelineDurationSec(clip);
    final inFileOffsetSec = clip.trimStart.inMilliseconds / 1000.0;

    if (!skipMoveToRow) {
      await JuceAudioEngine.moveClipToRow(clip.engineClipId, clip.rowId);
    }
    await JuceAudioEngine.setClipTime(
      clip.engineClipId,
      startSec: startSec,
      lengthSec: math.max(0.0, lengthSec),
      inFileOffsetSec: math.max(0.0, inFileOffsetSec),
    );
    await JuceAudioEngine.setClipStretchOptions(
      clip.engineClipId,
      tempoRatio: _tempoPlaybackRatioForEngine(clip),
      preservePitch: _clipPreserveTempoPitchInEngine(clip),
    );
  }

  Future<void> _syncClipMixToEngine(AudioTrack clip) async {
    if (clip.engineClipId < 0) return;
    final gain = clip.gain.clamp(0.0, 3.0);
    final pitch = _effectiveClipPitchSemitones(clip);
    final tempoRatio = _tempoPlaybackRatioForEngine(clip);
    final preservePitch = _clipPreserveTempoPitchInEngine(clip);
    await JuceAudioEngine.setClipGain(clip.engineClipId, gain);
    await JuceAudioEngine.setClipStretchOptions(
      clip.engineClipId,
      tempoRatio: tempoRatio,
      preservePitch: preservePitch,
    );
    await JuceAudioEngine.setClipPitch(clip.engineClipId, pitch);
  }

  Future<void> _setClipGainLive(int clipIndex, double gain) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.engineClipId < 0) return;
    final next = gain.clamp(0.0, 3.0);
    clip.gain = next;
    await JuceAudioEngine.setClipGain(clip.engineClipId, next);
    if (mounted) setState(() {});
  }

  Future<void> _setClipPitchLive(int clipIndex, double semitones) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.engineClipId < 0) return;
    final next =
        semitones.clamp(_kClipPitchMinSemitones, _kClipPitchMaxSemitones);
    clip.pitchSemitones = next;
    await JuceAudioEngine.setClipPitch(
      clip.engineClipId,
      _effectiveClipPitchSemitones(clip),
    );
    if (mounted) setState(() {});
  }

  void _startWaveformExtraction(AudioTrack c) async {
    if (c.didExtractWaveform) return;
    c.didExtractWaveform = true;

    try {
      final inputPath = c.file.path;

      // ---- Timeline truth ----
      final durSec = (c.audioDuration.inMilliseconds / 1000.0)
          .clamp(0.001, double.infinity);

      // ---- Resolution knob (bars per second) ----
      const int kWaveformSPS = 150;

      // ---- Safety caps ----
      const int minPoints = 256;
      const int maxPoints = 20000;

      // Target points is now time-based
      int target = (durSec * kWaveformSPS).round();
      target = target.clamp(minPoints, maxPoints);

      // Placeholder (flat waveform until done)
      c.normWaveformData = List<double>.filled(target, 0.0, growable: false);
      setState(() {});

      // ---- Decode speed knob ----
      const int pcmRate = 8000;

      final tmpDir = await getTemporaryDirectory();
      final rawPath = "${tmpDir.path}/wf_${c.hashCode}.raw";

      // Decode mono PCM
      await FFmpegKit.execute(
        '-i "$inputPath" -ac 1 -ar $pcmRate -f s16le -y "$rawPath"',
      );

      final bytes = await File(rawPath).readAsBytes();
      if (bytes.length < 2) return;

      final totalSamples = bytes.length ~/ 2;

      // Expected timeline samples (duration-based, stable)
      final expectedSamples = (durSec * pcmRate).round().clamp(1, 1 << 30);

      // Map expected timeline → decoded samples
      double mapExpectedToDecoded(double expectedIndex) {
        return expectedIndex * totalSamples / expectedSamples;
      }

      // ---- Compute RMS buckets ----
      final out = List<double>.filled(target, 0.0, growable: false);

      for (int i = 0; i < target; i++) {
        final expStart = (i / target) * expectedSamples;
        final expEnd = ((i + 1) / target) * expectedSamples;

        int start = mapExpectedToDecoded(expStart).floor();
        int end = mapExpectedToDecoded(expEnd).floor();

        start = start.clamp(0, totalSamples);
        end = end.clamp(0, totalSamples);

        if (end <= start) continue;

        double sumSq = 0.0;
        int count = 0;

        for (int s = start; s < end; s++) {
          final bi = s * 2;
          int v = bytes[bi] | (bytes[bi + 1] << 8);
          if ((v & 0x8000) != 0) v -= 0x10000;

          final f = v / 32768.0;
          sumSq += f * f;
          count++;
        }

        final rms = math.sqrt(sumSq / count);
        out[i] = rms.clamp(0.0, 1.0);
      }

      final norm = amplifyAndCapWaveform(out);

      if (!mounted) return;
      setState(() {
        c.normWaveformData = norm;
      });
    } catch (e) {
      debugPrint("Waveform extraction failed: $e");
    }
  }

  Future<void> _exportAndNavigate() async {
    _AudioExportSettings? selectedSettings;
    try {
      selectedSettings = await _showAudioExportSettingsSheet();
    } catch (e) {
      debugPrint('Failed to open export dialog: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _audioExportSettings = const _AudioExportSettings(
          format: _ExportAudioFormat.wav,
          sampleRate: 44100,
          wavBitDepth: 16,
          wavDithering: true,
          mp3BitrateKbps: 192,
          mp3Mode: _ExportMp3Mode.cbr,
          mp3VbrQuality: 2,
          channelMode: _ExportChannelMode.stereo,
          normalize: false,
          normalizeTargetDb: -1.0,
          resampleQuality: _ExportResampleQuality.best,
        );
      });
      try {
        selectedSettings = await _showAudioExportSettingsSheet();
      } catch (retryError) {
        debugPrint('Retry open export dialog failed: $retryError');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open export options.')),
        );
        return;
      }
    }
    if (!mounted || selectedSettings == null) {
      return;
    }
    final effectiveSettings = selectedSettings;

    setState(() {
      _audioExportSettings = effectiveSettings;
      _activeAudioExportSettings = effectiveSettings;
      _isLoadingNextScreen = true;
    });
    if (_isPlaying) {
      await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    }
    final exportPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExportProgressPage(exportFn: _exportAudioOnly, videoFile: ""),
      ),
    );
    if (!mounted) {
      _activeAudioExportSettings = null;
      return;
    }

    setState(() {
      _activeAudioExportSettings = null;
      _isLoadingNextScreen = false;
    });

    if (exportPath == null || exportPath.isEmpty) {
      final failStr = L10n.translate(context, 'Export canceled or failed.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failStr)));
      return;
    }

    final ext = p.extension(exportPath).replaceAll('.', '');
    final params = SaveFileDialogParams(
      sourceFilePath: exportPath,
      fileName: 'export_file.$ext',
    );
    final savedPath = await FlutterFileDialog.saveFile(params: params);

    if (savedPath != null) {
      // final success_str = L10n.translate(context, 'Exported file saved!');
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text(success_str)),// at: $savedPath')),
      // );
      final bool? done = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExportSuccessScreen(
            filePath: exportPath, // savedPath,
            isVideo: false,
          ),
        ),
      );

      if (done == true) {
        //****TEMPORARY: REMOVE return LINE FOR Mixroom FULL RELEASE****
        return;

        _pausePlayback();
        JuceAudioEngine.shutdown();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomeScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              const beginScale = 0.96;
              const endScale = 1.0;
              const curve = Curves.easeOutCubic;
              final tween = Tween<double>(begin: beginScale, end: endScale)
                  .chain(CurveTween(curve: curve));
              final fadeTween = Tween<double>(begin: 0.0, end: 1.0)
                  .chain(CurveTween(curve: curve));
              return FadeTransition(
                opacity: animation.drive(fadeTween),
                child: ScaleTransition(
                    scale: animation.drive(tween), child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
          (route) => false,
        );
      }
    } else {
      final fail_str = L10n.translate(context, 'Export canceled or failed.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(fail_str)));
    }
  }

  bool _isSampleAudioFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _kSampleAudioExtensions.contains(ext);
  }

  Future<bool> _ensureCanAddAnotherClip({
    required String basicModeMessage,
  }) async {
    if (widget.mode != "Basic" || _audioTracks.length < 3) {
      return true;
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          L10n.translate(context, 'Pro Mode Feature'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          L10n.translate(context, basicModeMessage),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _insertAudioFileAtTimeline(
    String filePath, {
    int? row,
    double? timeMs,
    bool enforceKnownAudioExtension = true,
  }) async {
    if (enforceKnownAudioExtension && !_isSampleAudioFile(filePath)) return;
    if (!await _ensureCanAddAnotherClip(
      basicModeMessage:
          'Upgrade to Pro mode to import more than 3 audio tracks.',
    )) {
      return;
    }
    if (!File(filePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is unavailable.')),
      );
      return;
    }

    await _stopSampleAudition();
    await _undoManager.execute(
      AddAudioTrackAction(
        addTrack: ({
          required File file,
          required int row,
          required double timeMs,
          Duration? trimStartRequested,
          Duration? trimEndRequested,
        }) =>
            _addAudioTrackFromFile(file, row, timeMs),
        tracks: _audioTracks,
        file: File(filePath),
        row: row ?? _selectedRow,
        timeMs: timeMs ?? _globalAudioClock.inMilliseconds.toDouble(),
      ),
    );
  }

  Future<void> _pickAndInsertAudioTrack() async {
    if (!await _ensureCanAddAnotherClip(
      basicModeMessage:
          'Upgrade to Pro mode to import more than 3 audio tracks.',
    )) {
      return;
    }

    await _pausePlayback();
    final result = await _runFilePickerRequest<FilePickerResult?>(
      () => FilePicker.platform.pickFiles(type: FileType.any),
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return;
    }
    final pickedPath = result.files.single.path!;
    await _insertAudioFileAtTimeline(
      pickedPath,
      enforceKnownAudioExtension: false,
    );
  }

  Future<void> _addSampleBrowserRootFolder() async {
    final directoryPath = await _runFilePickerRequest<String?>(
      () => FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose Sample Folder',
      ),
    );
    if (directoryPath == null) return;
    final normalized = _normalizePickedDirectoryPath(directoryPath);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open that folder. Choose a local folder that Mixroom can access.',
          ),
        ),
      );
      return;
    }

    if (_sampleBrowserRoots.contains(normalized)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Folder already loaded for this project.')),
      );
      return;
    }

    await _startSecurityScopedAccessForPath(normalized);

    setState(() {
      _sampleBrowserRoots.add(normalized);
      _sampleBrowserVisible = true;
    });
  }

  Future<T?> _runFilePickerRequest<T>(Future<T?> Function() request) async {
    if (_filePickerInFlight) return null;
    _filePickerInFlight = true;
    try {
      return await request();
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        return await request();
      } on PlatformException catch (retryError) {
        if (retryError.code == 'multiple_request') {
          debugPrint(
            'FilePicker still reported multiple_request after retry; dropping duplicate picker call.',
          );
          return null;
        }
        rethrow;
      }
    } finally {
      _filePickerInFlight = false;
    }
  }

  Future<void> _startSecurityScopedAccessForPath(String path) async {
    if (!Platform.isIOS) return;
    final normalized = _normalizePickedDirectoryPath(path);
    if (normalized.isEmpty) return;

    final keys = <String>{
      normalized,
      if (normalized.startsWith('/private/'))
        normalized.replaceFirst('/private', ''),
      if (normalized.startsWith('/var/')) '/private$normalized',
      'uri:${Uri.file(normalized).toString()}',
    };

    for (final key in keys) {
      if (_startedSecurityScopeKeys.contains(key)) continue;
      bool granted = false;
      try {
        if (key.startsWith('uri:')) {
          granted = await _securityScopedResource
              .startAccessingSecurityScopedResourceWithURL(key.substring(4));
        } else {
          granted = await _securityScopedResource
              .startAccessingSecurityScopedResourceWithFilePath(key);
        }
      } catch (_) {
        granted = false;
      }
      if (!granted) continue;
      _startedSecurityScopeKeys.add(key);
      _securityScopeStartCount += 1;
    }
  }

  void _stopAllSecurityScopedAccess() {
    if (!Platform.isIOS || _startedSecurityScopeKeys.isEmpty) return;
    for (final key in _startedSecurityScopeKeys) {
      try {
        if (key.startsWith('uri:')) {
          unawaited(_securityScopedResource
              .stopAccessingSecurityScopedResourceWithURL(key.substring(4)));
        } else {
          unawaited(_securityScopedResource
              .stopAccessingSecurityScopedResourceWithFilePath(key));
        }
      } catch (_) {}
    }
    _securityScopeStartCount = 0;
    _startedSecurityScopeKeys.clear();
  }

  String _normalizePickedDirectoryPath(String rawPath) {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';

    final candidates = <String>{};

    void addCandidate(String value) {
      var path = value.trim();
      if (path.isEmpty) return;

      if (path.startsWith('file://')) {
        try {
          path = Uri.parse(path).toFilePath();
        } catch (_) {}
      }

      try {
        path = Uri.decodeFull(path);
      } catch (_) {}

      path = path.replaceAll('\\', '/');
      if (!path.startsWith('/')) return;
      path = p.normalize(path);
      candidates.add(path);

      if (path.startsWith('/private/')) {
        candidates.add(p.normalize(path.replaceFirst('/private', '')));
      } else if (path.startsWith('/var/')) {
        candidates.add(p.normalize('/private$path'));
      }
    }

    addCandidate(raw);
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme == 'file') {
        addCandidate(uri.toFilePath());
      }
    } catch (_) {}

    for (final candidate in candidates) {
      if (Directory(candidate).existsSync()) return candidate;
    }

    if (candidates.isNotEmpty) {
      return candidates.first;
    }

    return '';
  }

  void _removeSampleBrowserRoot(String rootPath) {
    final normalizedRoot = p.normalize(rootPath);
    final rootPrefix =
        normalizedRoot.endsWith('/') ? normalizedRoot : '$normalizedRoot/';
    final removedAuditionPath = _auditioningSamplePath;
    final shouldStopAudition = removedAuditionPath != null &&
        (p.normalize(removedAuditionPath) == normalizedRoot ||
            p.normalize(removedAuditionPath).startsWith(rootPrefix));

    void stopSecurityScope(String key) {
      if (!Platform.isIOS || !_startedSecurityScopeKeys.contains(key)) return;
      _startedSecurityScopeKeys.remove(key);
      _securityScopeStartCount = math.max(0, _securityScopeStartCount - 1);
      try {
        if (key.startsWith('uri:')) {
          unawaited(_securityScopedResource
              .stopAccessingSecurityScopedResourceWithURL(key.substring(4)));
        } else {
          unawaited(_securityScopedResource
              .stopAccessingSecurityScopedResourceWithFilePath(key));
        }
      } catch (_) {}
    }

    final normalizedCandidates = <String>{
      normalizedRoot,
      if (normalizedRoot.startsWith('/private/'))
        normalizedRoot.replaceFirst('/private', ''),
      if (normalizedRoot.startsWith('/var/')) '/private$normalizedRoot',
      'uri:${Uri.file(normalizedRoot).toString()}',
    };

    setState(() {
      _sampleBrowserRoots
          .removeWhere((root) => p.normalize(root) == normalizedRoot);
      _sampleDurationCache.removeWhere((k, _) {
        final normalized = p.normalize(k);
        return normalized == normalizedRoot ||
            normalized.startsWith(rootPrefix);
      });
      if (_sampleBrowserRoots.isEmpty) {
        _sampleBrowserExpanded = false;
      }
    });

    for (final key in normalizedCandidates) {
      stopSecurityScope(key);
    }

    if (shouldStopAudition) {
      unawaited(_stopSampleAudition());
    }
  }

  Future<void> _openSampleBrowser({bool promptFolderIfEmpty = false}) async {
    if (promptFolderIfEmpty && _sampleBrowserRoots.isEmpty) {
      await _addSampleBrowserRootFolder();
    }
    if (!mounted) return;
    setState(() {
      _sampleBrowserVisible = true;
      _showAddActionsPanel = false;
      _chatExpanded = false;
      _chatInputActive = false;
      _reopenSampleBrowserAfterDrag = false;
      _reopenSampleBrowserExpanded = false;
    });
    _chatFocusNode.unfocus();
  }

  Future<void> _closeSampleBrowser() async {
    await _stopSampleAudition();
    if (!mounted) return;
    setState(() {
      _sampleBrowserVisible = false;
      _sampleBrowserExpanded = false;
      _sampleDragActive = false;
      _reopenSampleBrowserAfterDrag = false;
      _reopenSampleBrowserExpanded = false;
    });
  }

  void _setSampleDragActive(bool active) {
    if (!mounted) return;
    bool shouldReopenAfterDelay = false;
    bool reopenExpanded = false;
    setState(() {
      _sampleDragActive = active;
      if (active && _sampleBrowserVisible && _sampleBrowserExpanded) {
        _reopenSampleBrowserAfterDrag = true;
        _reopenSampleBrowserExpanded = true;
        _sampleBrowserExpanded = false;
      }
      if (!active && _reopenSampleBrowserAfterDrag) {
        shouldReopenAfterDelay = true;
        reopenExpanded = _reopenSampleBrowserExpanded;
        _reopenSampleBrowserAfterDrag = false;
        _reopenSampleBrowserExpanded = false;
      }
    });

    if (!shouldReopenAfterDelay) return;
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted || _sampleDragActive || _sampleBrowserRoots.isEmpty) return;
      setState(() {
        _sampleBrowserVisible = true;
        _sampleBrowserExpanded = reopenExpanded;
      });
    });
  }

  void _handleSampleDragExitedBrowserPanel() {
    if (!mounted || !_sampleBrowserVisible) return;
    setState(() {
      _reopenSampleBrowserAfterDrag = true;
      _reopenSampleBrowserExpanded = _sampleBrowserExpanded;
      _sampleBrowserVisible = false;
      _sampleBrowserExpanded = false;
    });
  }

  Future<Duration?> _resolveSampleDuration(String filePath) async {
    if (_sampleDurationCache.containsKey(filePath)) {
      return _sampleDurationCache[filePath];
    }

    try {
      final escaped = filePath.replaceAll('"', r'\"');
      final session = await FFprobeKit.execute(
        '-v error -show_entries format=duration '
        '-of default=noprint_wrappers=1:nokey=1 "$escaped"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        final rawOutput = await session.getOutput();
        final firstLine = (rawOutput ?? '')
            .split('\n')
            .map((s) => s.trim())
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
        final seconds = double.tryParse(firstLine);
        if (seconds != null && seconds.isFinite && seconds > 0) {
          final duration = Duration(milliseconds: (seconds * 1000).round());
          _sampleDurationCache[filePath] = duration;
          return duration;
        }
      }
    } catch (_) {}

    _sampleDurationCache[filePath] = null;
    return null;
  }

  Future<void> _stopSampleAudition() async {
    try {
      await _samplePreviewPlayer.stop();
    } catch (_) {}
    if (!mounted) return;
    if (_auditioningSamplePath != null || _samplePreviewPlaying) {
      setState(() {
        _auditioningSamplePath = null;
        _samplePreviewPlaying = false;
      });
    }
  }

  Future<void> _auditionSampleFile(String filePath) async {
    if (!_isSampleAudioFile(filePath) || !File(filePath).existsSync()) return;
    if (_auditioningSamplePath == filePath && _samplePreviewPlayer.playing) {
      await _stopSampleAudition();
      return;
    }

    if (_isPlaying) {
      await _pausePlayback();
      _stopMeterPolling();
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    }

    try {
      if (!mounted) return;
      setState(() {
        _auditioningSamplePath = filePath;
        _samplePreviewPlaying = true;
      });
      await _samplePreviewPlayer.stop();
      await _samplePreviewPlayer.setFilePath(filePath);
      await _samplePreviewPlayer.seek(Duration.zero);
      await _samplePreviewPlayer.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auditioningSamplePath = null;
        _samplePreviewPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to preview sample: $e')),
      );
    }
  }

  void _openAddActionsPanel() {
    if (!mounted) return;
    setState(() {
      _showAddActionsPanel = true;
      _activeAddActionId = null;
      _chatExpanded = false;
      _chatInputActive = false;
    });
    _chatFocusNode.unfocus();
  }

  void _closeAddActionsPanel() {
    if (!mounted || !_showAddActionsPanel) return;
    setState(() {
      _showAddActionsPanel = false;
      _activeAddActionId = null;
      _addButtonPressed = false;
    });
  }

  String _instrumentPickerCategory(Map<String, dynamic> spec) {
    final declared = ((spec['category'] as String?) ?? '').toLowerCase();
    final id = ((spec['id'] as String?) ?? '').toLowerCase();
    final name = ((spec['name'] as String?) ?? '').toLowerCase();
    final text = '$id $name';

    if (declared == 'drum' ||
        text.contains('drum') ||
        text.contains('kick') ||
        text.contains('808') ||
        text.contains('kit') ||
        text.contains('snare') ||
        text.contains('hat')) {
      return 'Drums';
    }
    if (text.contains('bass') ||
        text.contains('sub') ||
        text.contains('reese')) {
      return 'Bass';
    }
    if (text.contains('pad') ||
        text.contains('string') ||
        text.contains('ambient') ||
        text.contains('cinematic')) {
      return 'Pads';
    }
    if (text.contains('pluck') || text.contains('bell')) {
      return 'Plucks';
    }
    if (text.contains('key') ||
        text.contains('piano') ||
        text.contains('organ') ||
        text.contains('ep')) {
      return 'Keys';
    }
    if (text.contains('brass') || text.contains('horn')) {
      return 'Brass';
    }
    if (text.contains('lead') ||
        text.contains('saw') ||
        text.contains('wave')) {
      return 'Leads';
    }
    return 'Other';
  }

  List<String> _instrumentPickerCategories() {
    const ordered = <String>[
      'Keys',
      'Pads',
      'Leads',
      'Bass',
      'Plucks',
      'Brass',
      'Drums',
      'Other',
    ];
    final available = kInstrumentCatalog
        .map(_instrumentPickerCategory)
        .toSet()
        .toList(growable: false);
    return <String>[
      'All',
      ...ordered.where((category) => available.contains(category)),
    ];
  }

  Color _instrumentPickerAccent(String category) {
    switch (category) {
      case 'Keys':
        return const Color(0xFF53A8FF);
      case 'Pads':
        return const Color(0xFF4BC9B6);
      case 'Leads':
        return const Color(0xFFFFA749);
      case 'Bass':
        return const Color(0xFF5FD36A);
      case 'Plucks':
        return const Color(0xFFDF7EFF);
      case 'Brass':
        return const Color(0xFFF2C14E);
      case 'Drums':
        return const Color(0xFFFF6E6E);
      default:
        return const Color(0xFFA1B1C5);
    }
  }

  IconData _instrumentPickerIcon(String category) {
    switch (category) {
      case 'Keys':
        return Icons.piano_outlined;
      case 'Pads':
        return Icons.waves_rounded;
      case 'Leads':
        return Icons.bolt_rounded;
      case 'Bass':
        return Icons.graphic_eq_rounded;
      case 'Plucks':
        return Icons.tune_rounded;
      case 'Brass':
        return Icons.campaign_outlined;
      case 'Drums':
        return Icons.album_outlined;
      default:
        return Icons.music_note_rounded;
    }
  }

  Widget _buildInstrumentPickerCard({
    required Map<String, dynamic> spec,
    required VoidCallback onTap,
  }) {
    final category = _instrumentPickerCategory(spec);
    final accent = _instrumentPickerAccent(category);
    final source = (spec['sourceProject'] as String?) ?? '';
    final name = (spec['name'] as String?) ?? 'Instrument';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF232D3F),
                const Color(0xFF1A2231),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      _instrumentPickerIcon(category),
                      color: accent,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                source.isEmpty ? 'Mixroom preset' : 'Inspired by $source',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 11.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addInstrumentClipFromPicker() async {
    if (!await _ensureCanAddAnotherClip(
      basicModeMessage: 'Upgrade to Pro mode to add more than 3 clips.',
    )) {
      return;
    }

    if (!mounted) return;
    final categories = _instrumentPickerCategories();
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        var selectedCategory = categories.first;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final viewport = MediaQuery.of(ctx).size;
            final dialogWidth = math.min(560.0, viewport.width - 48.0);
            final dialogHeight =
                math.min(480.0, math.max(320.0, viewport.height * 0.68));
            final filtered = kInstrumentCatalog.where((spec) {
              if (selectedCategory == 'All') return true;
              return _instrumentPickerCategory(spec) == selectedCategory;
            }).toList(growable: false);
            return AlertDialog(
              backgroundColor: const Color(0xFF1A2230),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Choose Instrument',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final selected = category == selectedCategory;
                          final accent = _instrumentPickerAccent(category);
                          return InkWell(
                            onTap: () => setModalState(
                                () => selectedCategory = category),
                            borderRadius: BorderRadius.circular(999),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              height: 30,
                              alignment: Alignment.center,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 13),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          accent.withValues(alpha: 0.24),
                                          accent.withValues(alpha: 0.14),
                                        ],
                                      )
                                    : null,
                                color: selected
                                    ? null
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: selected
                                      ? accent.withValues(alpha: 0.70)
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.20),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                category,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: selected ? accent : Colors.white70,
                                  fontSize: 11.3,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No instruments in this category.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 430;
                                final crossAxisCount = compact ? 1 : 2;
                                final cardHeight = compact ? 126.0 : 132.0;
                                return GridView.builder(
                                  itemCount: filtered.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    mainAxisExtent: cardHeight,
                                  ),
                                  itemBuilder: (_, index) {
                                    final spec = filtered[index];
                                    return _buildInstrumentPickerCard(
                                      spec: spec,
                                      onTap: () => Navigator.pop(ctx, spec),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;

    final instrumentId = (selected['id'] as String?) ?? 'mixroom.basic_synth';
    final instrumentName = (selected['name'] as String?) ?? 'Basic Synth';
    final params = _instrumentParamsFromSpec(selected);
    final notes = _defaultMidiNotesForInstrument(instrumentId);

    await _undoManager.execute(
      AddMidiClipAction(
        addMidiClip: ({
          required String instrumentId,
          required String instrumentName,
          required Map<String, double> instrumentParams,
          required List<MidiNote> midiNotes,
          required int row,
          required double timeMs,
        }) =>
            _addMidiTrack(
          instrumentId: instrumentId,
          instrumentName: instrumentName,
          instrumentParams: instrumentParams,
          midiNotes: midiNotes,
          row: row,
          timeMs: timeMs,
        ),
        tracks: _audioTracks,
        instrumentId: instrumentId,
        instrumentName: instrumentName,
        instrumentParams: params,
        midiNotes: notes,
        row: _selectedRow,
        timeMs: _globalAudioClock.inMilliseconds.toDouble(),
      ),
    );
  }

  Future<void> _handleAddActionSelection(String action) async {
    if (mounted) {
      setState(() {
        _activeAddActionId = action;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 65));
    _closeAddActionsPanel();
    if (action == 'audio') {
      await _pickAndInsertAudioTrack();
      return;
    }
    if (action == 'sample_browser') {
      await _openSampleBrowser(promptFolderIfEmpty: true);
      return;
    }
    if (action == 'instrument') {
      await _addInstrumentClipFromPicker();
    }
  }

  Widget _buildAddActionTile({
    required String id,
    required IconData icon,
    required String title,
    String? subtitle,
    double topPadding = 6,
    double bottomPadding = 0,
    required VoidCallback onTap,
  }) {
    final selected = _activeAddActionId == id;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topPadding, 8, bottomPadding),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 85),
        decoration: BoxDecoration(
          color: selected ? const Color(0x334D8DFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0x887DB4FF) : Colors.transparent,
          ),
        ),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          minVerticalPadding: 0,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          subtitleTextStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
          textColor: Colors.white,
          iconColor: Colors.white,
          onTap: onTap,
        ),
      ),
    );
  }

  Future<void> _snapshotFxBypassState() async {
    _rowFxBypassSnapshot.clear();
    _masterFxBypassSnapshot.clear();

    // --- Rows ---
    for (int row = 0; row < _rowCount; row++) {
      // FX
      final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
      if (effects.isNotEmpty) {
        final states = <bool>[];
        for (int i = 0; i < effects.length; i++) {
          states.add(await JuceAudioEngine.getRowEffectBypassState(row, i));
        }
        _rowFxBypassSnapshot[row] = states;
      }

      // Gain / Pan
      _rowGainSnapshot[row] = _rowGain[row];
      _rowPanSnapshot[row] = _rowPan[row];

      // Automation (deep copy!)
      _rowAutomationSnapshot[row] =
          _rowVolumeAutomation[row].map((p) => p.copy()).toList();
    }

    // --- Master FX ---
    final masterFx = await JuceAudioEngine.getMasterEffects();
    for (int i = 0; i < masterFx.length; i++) {
      _masterFxBypassSnapshot
          .add(await JuceAudioEngine.getMasterEffectBypassState(i));
    }
  }

  Future<void> _forceBypassAllFx(bool bypass) async {
    for (int row = 0; row < _rowCount; row++) {
      // --- FX ---
      final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
      for (int i = 0; i < effects.length; i++) {
        await JuceAudioEngine.bypassRowEffect(row, i, bypass);
      }

      if (bypass) {
        // --- Gain ---
        await JuceAudioEngine.setRowGain(row, 1.0);

        // --- Pan ---
        await JuceAudioEngine.setRowPan(row, 0.5);

        // --- Automation (flat unity) ---
        await JuceAudioEngine.setTrackAutomationPoints(
            row, _toMaps([AutomationPoint(x: 0.0, volume: 0.75)]));
      }
    }

    // --- Master FX ---
    final masterFx = await JuceAudioEngine.getMasterEffects();
    for (int i = 0; i < masterFx.length; i++) {
      await JuceAudioEngine.bypassMasterEffect(i, bypass);
    }
  }

  Future<void> _restoreFxBypassState() async {
    // --- Rows ---
    for (int row = 0; row < _rowCount; row++) {
      // FX
      final states = _rowFxBypassSnapshot[row];
      if (states != null) {
        for (int i = 0; i < states.length; i++) {
          await JuceAudioEngine.bypassRowEffect(row, i, states[i]);
        }
      }

      // Gain / Pan
      await JuceAudioEngine.setRowGain(row, _rowGainSnapshot[row]);
      await JuceAudioEngine.setRowPan(row, _rowPanSnapshot[row]);

      // Automation
      await JuceAudioEngine.setTrackAutomationPoints(
          row, _toMaps(_rowAutomationSnapshot[row]));
    }

    // --- Master FX ---
    for (int i = 0; i < _masterFxBypassSnapshot.length; i++) {
      await JuceAudioEngine.bypassMasterEffect(i, _masterFxBypassSnapshot[i]);
    }
  }

  Future<void> _toggleGlobalFxBypass(bool enable) async {
    if (enable) {
      await _snapshotFxBypassState();
      await _forceBypassAllFx(true);
    } else {
      await _restoreFxBypassState();
    }

    setState(() => _globalFxBypass = enable);
  }

  Widget _buildMasterPopup() {
    if (!_showMasterRack) return const SizedBox.shrink();
    final double deviceWidth = MediaQuery.of(context).size.width;
    // We center horizontally (ignoring the old "right: 16")
    return Positioned(
      top: 68,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _showMasterRack ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          offset: _showMasterRack ? Offset.zero : const Offset(0, -0.05),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ▼ Small connector arrow
                  // Container(
                  //   width: 18,
                  //   height: 10,
                  //   decoration: const BoxDecoration(
                  //     color: Colors.transparent,
                  //   ),
                  //   child: CustomPaint(
                  //     painter: _TrianglePainter(),
                  //   ),
                  // ),// === GLOBAL FX BYPASS HEADER ===
                  Container(
                    constraints: BoxConstraints(
                      minWidth: 320,
                      maxWidth: math.min(deviceWidth * 0.96, 980),
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 34, 41, 61),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ───────────── HEADER ─────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "MASTER BUS",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 10),

                              // meter in the middle
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: AnimatedBuilder(
                                    animation: _meters,
                                    builder: (_, __) {
                                      return MiniStereoMeterHorizontal(
                                        frame: _meters.master,
                                        width: 160,
                                        height: 18,
                                      );
                                    },
                                  ),
                                ),
                              ),

                              const SizedBox(width: 12),

                              Row(
                                children: [
                                  const Text(
                                    "FX Bypass",
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: _globalFxBypass,
                                    activeColor: Colors.orangeAccent,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (v) async {
                                      await _toggleGlobalFxBypass(v);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // subtle divider
                        Container(
                            height: 1, color: Colors.white.withOpacity(0.08)),

                        // ───────────── CONTENT ─────────────
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: DynamicRackContent(
                            volumePage: _buildMasterVolumePage(),
                            effectsPage: _buildMasterEffectsPage(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  /*
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Global FX Bypass",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Switch(
                            value: _globalFxBypass,
                            activeColor: Colors.orangeAccent,
                            onChanged: (v) async {
                              await _toggleGlobalFxBypass(v);
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(
                      // IMPORTANT: Remove ALL height constraints here!
                      // The new widget handles the sizing.
                      constraints: BoxConstraints(minWidth: 280, maxWidth: 0.9 * deviceWidth),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 34, 41, 61),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                        // ... (rest of decoration)
                      ),
                      // 3. Use the new isolated widget!
                      child: DynamicRackContent(
                        volumePage: _buildMasterVolumePage(), // Pass your existing methods
                        effectsPage: _buildMasterEffectsPage(),
                      ),
                    ),
                  */
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterVolumePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PrettyGainSlider(
                  value: _masterGain,
                  onChangeStart: (v) {
                    _masterGainDragStart = v;
                  },
                  onChanged: (v) {
                    setState(() => _masterGain = v);
                    JuceAudioEngine.setMasterGain(v);
                  },
                  onChangeEnd: (v) {
                    _undoManager.execute(
                      SetMasterGainAction(
                        oldGain: _masterGainDragStart!,
                        newGain: _masterGain,
                        applyToState: (g) {
                          setState(() {
                            _masterGain = g;
                          });
                        },
                      ),
                    );
                    _recordProducerManualEdit('master_gain', {
                      'old_gain': _masterGainDragStart,
                      'new_gain': _masterGain,
                    });
                    _masterGainDragStart = null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PrettyStereoSlider(
                  value: _masterPan,
                  onChangeStart: (v) {
                    _masterPanDragStart = v;
                  },
                  onChanged: (v) {
                    setState(() => _masterPan = v);
                    JuceAudioEngine.setMasterPan(v);
                  },
                  onChangeEnd: (v) {
                    _undoManager.execute(
                      SetMasterPanAction(
                        oldPan: _masterPanDragStart!,
                        newPan: _masterPan,
                        applyToState: (p) {
                          setState(() {
                            _masterPan = p;
                          });
                        },
                      ),
                    );
                    _recordProducerManualEdit('master_pan', {
                      'old_pan': _masterPanDragStart,
                      'new_pan': _masterPan,
                    });
                    _masterPanDragStart = null;
                  },
                ),
              ),
              const SizedBox(height: 10),
              _buildMasterBusGainStagingRow(),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _rowCount == 0
              ? Center(
                  child: Text(
                    "No rows available",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                  itemCount: _rowCount,
                  itemBuilder: (context, row) =>
                      _buildMasterTrackGainStagingRow(row),
                  separatorBuilder: (_, __) => Divider(
                    height: 10,
                    thickness: 1,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMasterTrackGainStagingRow(int row) {
    final rowInfo = _rows[row];
    final String rowName =
        rowInfo.name.trim().isEmpty ? "Track ${row + 1}" : rowInfo.name.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _meters,
            builder: (_, __) {
              final MeterFrame frame = row < _meters.rows.length
                  ? _meters.rows[row]
                  : MeterFrame.zero;
              final double heldPeakDb = _heldPeakDbForRow(row, frame);
              final String levelLabel = _technicalLevelLabel(heldPeakDb);
              final Color levelColor = _technicalLevelColor(heldPeakDb);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _iconForMasterGainStagingRow(rowInfo.iconId),
                        size: 18,
                        color: Colors.white.withOpacity(0.88),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          rowName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: levelColor.withOpacity(0.17),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: levelColor.withOpacity(0.48)),
                        ),
                        child: Text(
                          levelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: levelColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: TrackGainStagingDbMeter(frame: frame),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          PrettyGainSlider(
            value: _rowGain[row],
            showLabel: false,
            onChangeStart: (v) {
              _masterRackRowGainDragStart[row] = v;
            },
            onChanged: (v) {
              setState(() => _rowGain[row] = v);
              JuceAudioEngine.setRowGain(row, v);
            },
            onChangeEnd: (v) {
              final oldGain = _masterRackRowGainDragStart.remove(row) ?? v;
              final newGain = _rowGain[row];
              if ((newGain - oldGain).abs() < 0.00001) return;

              _undoManager.execute(
                SetRowGainAction(
                  row: row,
                  oldGain: oldGain,
                  newGain: newGain,
                  applyToState: (r, g) {
                    setState(() {
                      _rowGain[r] = g;
                    });
                  },
                ),
              );
              _recordProducerManualEdit('row_gain', {
                'row': row,
                'old_gain': oldGain,
                'new_gain': newGain,
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMasterBusGainStagingRow() {
    return AnimatedBuilder(
      animation: _meters,
      builder: (_, __) {
        final frame = _meters.master;
        final double heldPeakDb = _heldPeakDbForRow(-1, frame);
        final String levelLabel = _technicalLevelLabel(heldPeakDb);
        final Color levelColor = _technicalLevelColor(heldPeakDb);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.surround_sound_outlined,
                    size: 18,
                    color: Colors.white.withOpacity(0.88),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Master',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.17),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: levelColor.withOpacity(0.48)),
                    ),
                    child: Text(
                      levelLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: levelColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 30,
                child: TrackGainStagingDbMeter(
                  frame: frame,
                  showClipIndicator: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForMasterGainStagingRow(int iconId) {
    switch (iconId) {
      case 1:
        return Icons.piano;
      case 2:
        return Icons.graphic_eq;
      case 3:
        return Icons.queue_music;
      case 4:
        return Icons.music_note;
      case 5:
        return Icons.podcasts;
      default:
        return Icons.audio_file;
    }
  }

  String _technicalLevelLabel(double peakDb) {
    if (peakDb >= -0.1) return "0.0 dB";
    if (!peakDb.isFinite) return "-inf dB";
    return "${peakDb.toStringAsFixed(1)} dB";
  }

  Color _technicalLevelColor(double peakDb) {
    if (peakDb >= -0.1) return const Color(0xFFFF8C8C);
    if (peakDb >= -3.0) return const Color(0xFFFFB86B);
    if (peakDb >= -12.0) return const Color(0xFF9ED9FF);
    if (peakDb >= -24.0) return const Color(0xFF7EBFFF);
    return const Color(0xFF6EA1D8);
  }

  double _heldPeakDbForRow(int row, MeterFrame frame) {
    final now = DateTime.now();
    final currentPeakDb = _ampToDbFs(math.max(frame.rmsL, frame.rmsR));

    final prevDb = _rowPeakHoldDb[row] ?? currentPeakDb;
    final lastUpdate = _rowPeakHoldLastUpdate[row] ?? now;
    final freezeUntil = _rowPeakHoldFreezeUntil[row] ?? now;
    final dt = (now.difference(lastUpdate).inMicroseconds / 1000000.0)
        .clamp(0.0, 0.25);

    double heldDb = prevDb;
    if (currentPeakDb >= prevDb || !prevDb.isFinite) {
      heldDb = currentPeakDb;
      _rowPeakHoldFreezeUntil[row] = now.add(const Duration(milliseconds: 900));
    } else if (now.isAfter(freezeUntil)) {
      const decayDbPerSec = 11.0;
      heldDb = math.max(currentPeakDb, prevDb - (decayDbPerSec * dt));
    }

    _rowPeakHoldDb[row] = heldDb;
    _rowPeakHoldLastUpdate[row] = now;
    return heldDb;
  }

  double _ampToDbFs(double amp01) {
    final double amp = amp01.clamp(0.0, 1.0).toDouble();
    if (amp <= 0.000001) return double.negativeInfinity;
    return 20 * math.log(amp) / math.ln10;
  }

  Widget _buildMasterEffectsPage() {
    return MasterEffectsPanel(
      key: ValueKey("master_effects_panel"),
      mode: widget.mode,
      getMasterEffects: () => JuceAudioEngine.getMasterEffects(),
      getMasterEffectIds: () => JuceAudioEngine.getMasterEffectIds(),
      getMasterEffectBypassState: (i) =>
          JuceAudioEngine.getMasterEffectBypassState(i),
      bypassMasterEffect: (i, bp) async {
        await _undoManager.execute(
          BypassMasterEffectAction(
              effectIndex: i, oldState: !bp, newState: bp, onChange: () {}),
        );
        _recordProducerManualEdit(
            'master_fx_bypass', {'index': i, 'bypassed': bp});
      }, //JuceAudioEngine.bypassMasterEffect(i, bp),
      // reorderMasterEffects: (from, to) => JuceAudioEngine.reorderMasterEffects(from, to),
      // removeMasterEffect: (i) => JuceAudioEngine.removeMasterEffect(i),
      // insertMasterEffect: (path) => JuceAudioEngine.insertMasterEffect(path),
      insertMasterEffect: (pathOrName) async {
        final before = await JuceAudioEngine.getMasterEffects();
        await _undoManager.execute(
            InsertMasterEffectAction(pathOrName: pathOrName, onChange: () {}));
        final after = await JuceAudioEngine.getMasterEffects();
        if (after.length <= before.length) {
          _showSmallNotice('Could not load this effect plugin.');
          return;
        }
        _recordProducerManualEdit('master_fx_insert', {'effect': pathOrName});
      },

      // need name of effects so undo action can add it back later
      removeMasterEffect: (effectIndex, name, applyingPreset) async {
        if (applyingPreset) {
          await JuceAudioEngine.removeMasterEffect(effectIndex);
          return;
        }
        await _undoManager.execute(
          RemoveMasterEffectAction(
              effectIndex: effectIndex, pathOrName: name, onChange: () {}),
        );
        _recordProducerManualEdit(
            'master_fx_remove', {'index': effectIndex, 'effect': name});
      },

      reorderMasterEffects: (from, to) async {
        await _undoManager.execute(
            ReorderMasterEffectAction(from: from, to: to, onChange: () {}));
        _recordProducerManualEdit(
            'master_fx_reorder', {'from': from, 'to': to});
      },
      scanPlugins: () => JuceAudioEngine.scanPlugins(),
      getMasterPluginParameters: (i) =>
          JuceAudioEngine.getMasterPluginParameters(i),
      setMasterEffectParam: (i, id, v) =>
          JuceAudioEngine.setMasterEffect(i, id, v),
      onMasterPluginParamCommit: (idx, paramId, oldValue, newValue) async {
        await _undoManager.execute(
          SetMasterEffectParamAction(
            effectIndex: idx,
            paramId: paramId,
            oldValue: oldValue,
            newValue: newValue,
            onChange: () {},
          ),
        );
        _recordProducerManualEdit('master_fx_param', {
          'index': idx,
          'param_id': paramId,
          'old_value': oldValue,
          'new_value': newValue,
        });
      },
      onMasterPresetCommit: (before, after) async {
        await _undoManager.execute(
          MasterPresetChangeAction(
              before: before, after: after, onChange: () => setState(() {})),
        );
        _recordProducerManualEdit('master_preset_commit', {
          'before_count': before.effects.length,
          'after_count': after.effects.length,
        });
      },
      projectBpm: _tempo,
      meters: _meters,
      getMasterCompressorMeter: (fx) =>
          JuceAudioEngine.getMasterCompressorMeter(fx),
      getMasterEqWaveform: (fx, sampleCount) =>
          JuceAudioEngine.getMasterEqWaveform(fx, sampleCount: sampleCount),
    );
  }

  Widget _buildTopBar(Duration currentClock) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Left: back
          _Glass(
            radius: 24,
            padding: EdgeInsets.zero,
            opacity: 0.10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: _handleBackPressed,
            ),
          ),
          const SizedBox(width: 10),
          // NEW PROJECT SETTINGS BUTTON
          _Glass(
            radius: 22,
            padding: EdgeInsets.zero,
            opacity: 0.10,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 20),
              onPressed: _openProjectSettings,
            ),
          ),

          const SizedBox(width: 10),
          // CENTER: Time pill (true center on iPad)
          Expanded(
            child: Center(
              child: _timePill(
                current: _formatDuration(currentClock),
                total: _formatDuration(_audioOnlyOverallDuration),
              ),
            ),
          ),

          // CENTER: make flexible & scale down if needed
          // Expanded(
          //   child: Align(
          //     alignment: Alignment.centerLeft,
          //     child: _tempoTimePill(
          //       tempo: _tempo,
          //       current: _formatDuration(_globalAudioClock),
          //       total: _formatDuration(_audioOnlyOverallDuration),
          //     ),
          //   ),
          // ),
          const SizedBox(width: 8),

          // RIGHT: allow this cluster to also scale when narrow
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                _Glass(
                  radius: 22,
                  padding: EdgeInsets.zero,
                  opacity: 0.10,
                  child: IconButton(
                    icon: const Icon(Icons.settings_input_composite,
                        color: Colors.white, size: 20),
                    onPressed: () {
                      _isMasterPopupOpen = !_isMasterPopupOpen;
                      setState(() => _showMasterRack = !_showMasterRack);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _exportAndNavigate,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // color: Colors.white.withOpacity(0.08),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          // blurRadius: 18,
                          // offset: const Offset(0, 6),
                        ),
                        const BoxShadow(
                          color: Color(0x22FFFFFF),
                          // offset: Offset(0, -1),
                          // blurRadius: 0,
                          // spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.ios_share_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openProjectSettings() async {
    if (_isDialogOpen) return;
    if (_showTempoRollDown) {
      setState(() => _showTempoRollDown = false);
    }
    _isDialogOpen = true;
    String draftProjectName = _projectName;
    Future<void> commitProjectName() async {
      final renamed = draftProjectName.trim();
      if (renamed.isEmpty) {
        draftProjectName = _projectName;
        return;
      }
      if (renamed == _projectName) return;
      try {
        final oldProjectDir = _projectDir;
        final newDir = await ProjectManager.renameProject(_projectDir, renamed);
        final oldAudioDir = ProjectManager.audioDir(oldProjectDir).path;
        final newAudioDir = ProjectManager.audioDir(newDir).path;
        _setStateAndRefreshProjectSettings(() {
          _projectDir = newDir;
          _projectName = p.basename(newDir.path);
          for (final tr in _audioTracks) {
            final oldFilePath = tr.file.path;
            final oldOriginalPath = tr.originalFile.path;
            final fileName = p.basename(oldFilePath);
            final originalName = p.basename(oldOriginalPath);

            // Track audio files move with the project directory; remap in-memory
            // absolute paths so subsequent saves do not skip missing sources.
            final shouldRemapFile = oldFilePath.startsWith(oldAudioDir) ||
                !File(oldFilePath).existsSync();
            final shouldRemapOriginal =
                oldOriginalPath.startsWith(oldAudioDir) ||
                    !File(oldOriginalPath).existsSync();

            if (shouldRemapFile) {
              tr.file = File(p.join(newAudioDir, fileName));
            }
            if (shouldRemapOriginal) {
              tr.originalFile = File(p.join(newAudioDir, originalName));
            }
          }
        });
        draftProjectName = _projectName;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Rename failed: $e')),
        );
        draftProjectName = _projectName;
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Project renamed')),
      );
    }

    try {
      await showDialog(
        context: context,
        builder: (context) {
          return MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: StatefulBuilder(
              builder: (context, localSetState) {
                _projectSettingsStateSetter = localSetState;
                return Dialog(
                  backgroundColor: const Color(0xFF1A1F2E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 560, maxWidth: 360),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Project Settings",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: ValueKey('project_name_field_$_projectName'),
                            initialValue: _projectName,
                            readOnly: false,
                            textInputAction: TextInputAction.done,
                            onChanged: (value) {
                              draftProjectName = value;
                            },
                            onFieldSubmitted: (_) async {
                              await commitProjectName();
                            },
                            onTapOutside: (_) async {
                              FocusScope.of(context).unfocus();
                              await commitProjectName();
                            },
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Project name',
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.white.withOpacity(0.12)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: Color(0xFF4C8DFF), width: 1.3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildInputSelector(),
                          if (_numInputChannels > 0) ...[
                            const SizedBox(height: 20),
                            DropdownButtonFormField<int>(
                              key: ValueKey(_numInputChannels),
                              value: _selectedChannelStart,
                              decoration: const InputDecoration(
                                  labelText: 'Input Channel',
                                  border: OutlineInputBorder()),
                              items: List.generate(
                                _numInputChannels,
                                (i) => DropdownMenuItem(
                                    value: i, child: Text('Channel ${i + 1}')),
                              ),
                              onChanged: _isRecording
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      _setStateAndRefreshProjectSettings(() {
                                        _selectedChannelStart = v;
                                        _selectedChannelCount = 1;
                                      });
                                    },
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (!Platform.isIOS) ...[
                            _buildOutputSelector(),
                            const SizedBox(height: 20)
                          ],
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetronomeToggle(),
                              const SizedBox(height: 20),
                              _buildMetronomeVolumeSlider(),
                              const SizedBox(height: 16),
                              _buildProducerCaptureUiToggle(),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () async {
                              await commitProjectName();
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white10,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text("Close"),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      await commitProjectName();
      _projectSettingsStateSetter = null;
      _isDialogOpen = false;
    }
  }

  Widget _buildMetronomeToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Metronome",
            style: TextStyle(
                color: Color.fromARGB(210, 255, 255, 255), fontSize: 15)),
        Switch(
          value: _metronomeEnabled,
          activeColor: Colors.blueAccent,
          onChanged: (v) {
            _setStateAndRefreshProjectSettings(() => _metronomeEnabled = v);
            JuceAudioEngine.setMetronomeEnabled(v);
          },
        ),
      ],
    );
  }

  Widget _buildMetronomeVolumeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Metronome Volume",
                style: TextStyle(
                    color: Color.fromARGB(210, 255, 255, 255), fontSize: 15)),
            Text(
              (_metronomeVolume * 100).round().toString(),
              style: const TextStyle(color: Color.fromARGB(210, 255, 255, 255)),
            ),
          ],
        ),
        Slider(
          value: _metronomeVolume,
          min: 0.0,
          max: 1.0,
          activeColor: Colors.blueAccent,
          inactiveColor: Colors.white12,
          onChanged: (v) {
            _setStateAndRefreshProjectSettings(() => _metronomeVolume = v);
            JuceAudioEngine.setMetronomeVolume(v);
          },
        ),
      ],
    );
  }

  Widget _buildProducerCaptureUiToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Text(
            "Show Producer Capture UI",
            style: TextStyle(
              color: Color.fromARGB(210, 255, 255, 255),
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: _showProducerCaptureUi,
          activeColor: Colors.blueAccent,
          onChanged: (v) {
            _setStateAndRefreshProjectSettings(
                () => _showProducerCaptureUi = v);
          },
        ),
      ],
    );
  }

  Future<void> _selectInputDevice(MediaDeviceInfo device) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'deviceId': device.deviceId},
      'video': false,
    });

    // Stop immediately — we are only probing
    for (var t in stream.getTracks()) {
      t.stop();
    }

    setState(() {
      _selectedInput = device;
    });
  }

  // iOS restricts this from happening, so give some message indicating it will have no effect, or prevent it
  Future<void> _selectOutputDevice(MediaDeviceInfo device) async {
    try {
      await Helper.selectAudioOutput(device.deviceId);
    } catch (e) {
      debugPrint("selectAudioOutput failed (falling back): $e");
    }
  }

  Future<void> _loadInputDevicesFromJuce() async {
    _setStateAndRefreshProjectSettings(() => _loadingDevices = true);

    final devices = await JuceAudioEngine.getInputDevices();
    final current = await JuceAudioEngine.getCurrentDeviceName();
    final channels = await JuceAudioEngine.getNumInputChannels();
    _setStateAndRefreshProjectSettings(() {
      _inputDevices = devices;
      _selectedDevice = devices.contains(current)
          ? current
          : (devices.isNotEmpty ? devices.first : null);
      _numInputChannels = channels;

      _selectedChannelStart =
          _selectedChannelStart.clamp(0, (_numInputChannels - 1).clamp(0, 999));
      _selectedChannelCount = _selectedChannelCount.clamp(
          1, (_numInputChannels - _selectedChannelStart).clamp(1, 999));

      _loadingDevices = false;
    });

    print("loaded ${devices.toString()}  $current $_numInputChannels");
  }

  Future<void> _loadAudioDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();

    final inputs = devices.where((d) => d.kind == 'audioinput').toList();
    final outputs = devices.where((d) => d.kind == 'audiooutput').toList();

    MediaDeviceInfo? newSelectedInput;
    MediaDeviceInfo? newSelectedOutput;

    // --- Preserve input selection if possible ---
    if (_selectedInput != null) {
      try {
        newSelectedInput =
            inputs.firstWhere((d) => d.deviceId == _selectedInput!.deviceId);
      } catch (_) {
        newSelectedInput = inputs.isNotEmpty ? inputs.first : null;
      }
    } else {
      newSelectedInput = inputs.isNotEmpty ? inputs.first : null;
    }

    // --- Preserve output selection if possible ---
    if (_selectedOutput != null) {
      try {
        newSelectedOutput =
            outputs.firstWhere((d) => d.deviceId == _selectedOutput!.deviceId);
      } catch (_) {
        newSelectedOutput = outputs.isNotEmpty ? outputs.first : null;
      }
    } else {
      newSelectedOutput = outputs.isNotEmpty ? outputs.first : null;
    }

    setState(() {
      _inputs = inputs;
      _outputs = outputs;
      _selectedInput = newSelectedInput;
      _selectedOutput = newSelectedOutput;
      _loadingDevices = false;
    });

    navigator.mediaDevices.ondevicechange = (event) {
      _loadAudioDevices(); // refresh device list
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text("Audio devices updated")),
      // );
    };
  }

  Widget _buildInputSelector() {
    if (_loadingDevices) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedDevice,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: "Input Device",
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        suffixIcon: IconButton(
          tooltip: "Refresh audio devices",
          icon: const Icon(Icons.refresh, color: Colors.white70),
          onPressed: () async {
            _loadInputDevicesFromJuce();
            print("audio devices reloaded from JUCE");
          },
        ),
      ),
      items: _inputDevices
          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
          .toList(),
      onChanged: (name) async {
        if (name == null) return;

        final ok = await JuceAudioEngine.selectInputDevice(name);
        if (!ok) return;

        final channels = await JuceAudioEngine.getNumInputChannels();

        _setStateAndRefreshProjectSettings(() {
          _selectedDevice = name;
          _numInputChannels = channels;

          _selectedChannelStart = _selectedChannelStart.clamp(
              0, (_numInputChannels - 1).clamp(0, 999));
          _selectedChannelCount = 1;
        });
      },
    );
  }

  Widget _buildOutputSelector() {
    if (_loadingDevices) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    // Some Android devices may not expose any audiooutput devices.
    if (_outputs.isEmpty) {
      return const Text("No selectable output devices",
          style: TextStyle(color: Colors.white54));
    }

    return DropdownButtonFormField<MediaDeviceInfo>(
      dropdownColor: const Color(0xFF2A2F3D),
      initialValue: _selectedOutput,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: "Output Device",
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
      ),
      items: _outputs.map((d) {
        return DropdownMenuItem(
          value: d,
          child: Text(d.label.isNotEmpty ? d.label : d.deviceId,
              style: const TextStyle(color: Colors.white)),
        );
      }).toList(),
      onChanged: (d) {
        if (d == null) return;
        _setStateAndRefreshProjectSettings(() => _selectedOutput = d);
        _selectOutputDevice(d);
      },
    );
  }

  Widget _buildTempoSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Tempo (BPM)", style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2F3D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: CupertinoPicker(
            scrollController:
                FixedExtentScrollController(initialItem: _tempo.round() - 20),
            itemExtent: 36,
            magnification: 1.15,
            squeeze: 1.2,
            useMagnifier: true,
            backgroundColor: Colors.transparent,
            onSelectedItemChanged: (index) {
              final bpm = index + 20;
              _setProjectTempoFromUi(bpm.toDouble());
            },
            children: [
              for (int bpm = 20; bpm <= 999; bpm++)
                Center(
                  child: Text("$bpm",
                      style:
                          const TextStyle(color: Colors.white, fontSize: 20)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tempoTimePill(
      {required int tempo, required String current, required String total}) {
    return LayoutBuilder(
      builder: (context, c) {
        final double pillWidth = c.maxWidth;
        const double sidePad = 18;
        const double gap = 14;

        // --- Adaptive font scaling ---
        final double screenWidth = MediaQuery.of(context).size.width;
        double fontScale;
        if (screenWidth >= 1000) {
          fontScale = 1.3;
        } else if (screenWidth >= 700) {
          fontScale = 1.15;
        } else if (screenWidth >= 500) {
          fontScale = 1.0;
        } else {
          fontScale = 0.9;
        }

        TextStyle bigNum = TextStyle(
          fontSize: 22 * fontScale,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        TextStyle smallNum = TextStyle(
          fontSize: 12 * fontScale,
          color: Colors.white.withOpacity(0.65),
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        TextStyle smallLabel = TextStyle(
          fontSize: 12 * fontScale,
          letterSpacing: 0.6,
          color: Colors.white.withOpacity(0.75),
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        return _Glass(
          radius: 22,
          // 🔽 slightly reduce horizontal padding so inner content has more breathing room
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          opacity: 0.10,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, maxHeight: 54),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ---- Left column: TEMPO ----
                Padding(
                  padding:
                      const EdgeInsets.only(left: 4), // keep visually centered
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$tempo',
                          style: bigNum, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text('TEMPO',
                          style: smallLabel, textAlign: TextAlign.center),
                    ],
                  ),
                ),

                const SizedBox(width: gap),
                const _PillDivider(height: 30),
                const SizedBox(width: gap),

                // ---- Right column: Time (Expanded, slight right padding to prevent clipping) ----
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                        right: 0), // ✅ fixes shadow/clipping on last digit
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          current,
                          style: bigNum,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          total,
                          style: smallNum,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timePill({required String current, required String total}) {
    return GestureDetector(
      onTap: () => setState(() => _showTempoRollDown = !_showTempoRollDown),
      child: LayoutBuilder(
        builder: (context, c) {
          return _Glass(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            opacity: 0.10,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50, maxHeight: 70),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _promptTempoInput,
                        child: Text(
                          '${_formatTempoBpm(_tempo)} BPM',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.78),
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showTempoRollDown
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      current,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.0,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      total,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTempoRollDownPanel() {
    return Positioned(
      top: 72,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_showTempoRollDown,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: _showTempoRollDown ? 1.0 : 0.0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            offset: _showTempoRollDown ? Offset.zero : const Offset(0, -0.08),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 258),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111725).withOpacity(0.97),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Tempo',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              minimumSize: const Size(0, 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: Colors.white12),
                              ),
                            ),
                            onPressed: _promptTempoInput,
                            icon: const Icon(
                              Icons.keyboard_alt_rounded,
                              size: 14,
                            ),
                            label: const Text(
                              'Type',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        height: 82,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: CupertinoPicker.builder(
                          scrollController: FixedExtentScrollController(
                            initialItem: _clampTempo(_tempo).round() - 20,
                          ),
                          itemExtent: 24,
                          diameterRatio: 1.35,
                          squeeze: 1.16,
                          magnification: 1.06,
                          useMagnifier: true,
                          backgroundColor: Colors.transparent,
                          selectionOverlay: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              border: Border(
                                top: BorderSide(color: Colors.white24),
                                bottom: BorderSide(color: Colors.white24),
                              ),
                            ),
                          ),
                          onSelectedItemChanged: (index) {
                            _setProjectTempoFromUi((index + 20).toDouble());
                          },
                          itemBuilder: (context, index) {
                            if (index < 0 || index > 979) return null;
                            final bpm = index + 20;
                            return Center(
                              child: Text(
                                '$bpm',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            );
                          },
                          childCount: 980,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          const Text(
                            'Tempo Mode',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 22, minHeight: 22),
                            padding: const EdgeInsets.only(right: 2),
                            splashRadius: 12,
                            onPressed: _showTempoModeInfoDialog,
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => unawaited(
                                  _setTempoStretchUiMode(
                                    enabled: false,
                                    preservePitch:
                                        _tempoStretchPreservePitchDefault,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: !_tempoStretchEnabled
                                        ? Colors.blueAccent.withOpacity(0.75)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Off',
                                    style: TextStyle(
                                      color: !_tempoStretchEnabled
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => unawaited(
                                  _setTempoStretchUiMode(
                                    enabled: true,
                                    preservePitch: false,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: _tempoStretchEnabled &&
                                            !_tempoStretchPreservePitchDefault
                                        ? Colors.blueAccent.withOpacity(0.75)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Resample',
                                    style: TextStyle(
                                      color: _tempoStretchEnabled &&
                                              !_tempoStretchPreservePitchDefault
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => unawaited(
                                  _setTempoStretchUiMode(
                                    enabled: true,
                                    preservePitch: true,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: _tempoStretchEnabled &&
                                            _tempoStretchPreservePitchDefault
                                        ? Colors.blueAccent.withOpacity(0.75)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Stretch',
                                    style: TextStyle(
                                      color: _tempoStretchEnabled &&
                                              _tempoStretchPreservePitchDefault
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRecordPressed() async {
    if (_isRecording) {
      // Second press of record stops recording and leaves playback alone
      // await _stopRecording(keepPlaying: false); // true);
      await _stopRecordingJuce(keepPlaying: false); // true);
    } else {
      // await _startRecording();
      await _startRecordingJuce();
    }
  }

  String? pickMixroomEffect(String effectContains) {
    final needle = effectContains.toLowerCase();

    for (final name in kMixroomBuiltInEffects) {
      if (name.toLowerCase().contains(needle)) {
        return name;
      }
    }
    return null;
  }

  Future<void> applyMixingResult(MixingResult mix) async {
    if (mix.isNoOp || mix.actions.isEmpty) return;

    final List<EditorUndoAction> groupedActions = [];

    for (final a in mix.actions) {
      switch (a.type) {
        case 'set_row_gain':
          final row = a.data['row'] as int;
          final mode = a.data['mode'] ?? 'delta';

          final oldGain = _rowGain[row];
          double newGain;

          if (mode == 'set') {
            newGain = (a.data['value'] as num).toDouble().clamp(0.0, 3.0);
          } else {
            final delta = (a.data['delta'] as num).toDouble();
            newGain = (oldGain + delta).clamp(0.0, 3.0);
          }

          // _undoManager.execute(
          //   SetRowGainAction(
          //     row: row,
          //     oldGain: oldGain,
          //     newGain: newGain,
          //     applyToState: (r, g) {
          //       setState(() {
          //         _rowGain[r] = g;
          //       });
          //     },
          //   ),
          // );

          EditorUndoAction finalAct = SetRowGainAction(
            row: row,
            oldGain: oldGain,
            newGain: newGain,
            applyToState: (r, g) {
              setState(() {
                _rowGain[r] = g;
              });
            },
          );

          _undoManager.executeWithoutAdd(
            finalAct,
          ); // need this so that you can make a compound undo action while preserving execute order
          groupedActions.add(finalAct);

          _mixHighlighter
              .trigger([HaloKey('row:$row'), HaloKey('row:$row:mixer')]);

          final summary =
              '• Adjusted Gain from ${_gainToDb(oldGain)} to ${_gainToDb(newGain)} on Track ${row + 1} •';
          _chatController.insertMessage(ActionSummaryMessage(text: summary));

          continue;

        case 'set_row_pan':
          final row = (a.data['row'] as int);

          final oldPan01 = _rowPan[row]; // 0..1

          double newPan01;

          if (a.data.containsKey('value')) {
            // ABSOLUTE SET (0..1, center = 0.5)
            newPan01 = (a.data['value'] as num).toDouble().clamp(0.0, 1.0);
          } else {
            // DELTA in signed space (-1..+1)
            final deltaSigned = (a.data['delta'] as num).toDouble();

            final oldPanSigned = (oldPan01 * 2.0) - 1.0;
            final newPanSigned = (oldPanSigned + deltaSigned).clamp(-1.0, 1.0);
            newPan01 = ((newPanSigned + 1.0) * 0.5).clamp(0.0, 1.0);
          }

          // _undoManager.execute(
          //   SetRowPanAction(
          //     row: row,
          //     oldPan: oldPan01,
          //     newPan: newPan01,
          //     applyToState: (r, p) {
          //       setState(() {
          //         _rowPan[r] = p;
          //       });
          //     },
          //   ),
          // );

          EditorUndoAction finalAct = SetRowPanAction(
            row: row,
            oldPan: oldPan01,
            newPan: newPan01,
            applyToState: (r, p) {
              setState(() {
                _rowPan[r] = p;
              });
            },
          );

          _undoManager.executeWithoutAdd(
            finalAct,
          ); // need this so that you can make a compound undo action while preserving execute order
          groupedActions.add(finalAct);

          final summary =
              '• Adjusted pan from ${panToText(oldPan01)} to ${panToText(newPan01)} on Track ${row + 1} •';
          _chatController.insertMessage(ActionSummaryMessage(text: summary));
          continue;

        case 'set_master_gain':
          {
            final mode = a.data['mode'] ?? 'delta';
            final oldGain = _masterGain;

            final double newGain;
            if (mode == 'set') {
              newGain = (a.data['value'] as num).toDouble().clamp(0.0, 3.0);
            } else {
              final delta = (a.data['delta'] as num?)?.toDouble() ?? 0.0;
              newGain = (oldGain + delta).clamp(0.0, 3.0);
            }

            final finalAct = SetMasterGainAction(
              oldGain: oldGain,
              newGain: newGain,
              applyToState: (g) {
                setState(() {
                  _masterGain = g;
                });
              },
            );

            await _undoManager.executeWithoutAdd(finalAct);
            groupedActions.add(finalAct);

            _chatController.insertMessage(
              ActionSummaryMessage(
                text:
                    '• Adjusted Master Gain from ${_gainToDb(oldGain)} to ${_gainToDb(newGain)} •',
              ),
            );
            continue;
          }

        case 'set_master_pan':
          {
            final oldPan01 = _masterPan;
            final mode = (a.data['mode'] as String?) ?? 'delta';

            final double newPan01;
            if (mode == 'set' || a.data.containsKey('value')) {
              newPan01 = (a.data['value'] as num).toDouble().clamp(0.0, 1.0);
            } else {
              final deltaSigned = (a.data['delta'] as num?)?.toDouble() ?? 0.0;
              final oldPanSigned = (oldPan01 * 2.0) - 1.0;
              final nextSigned = (oldPanSigned + deltaSigned).clamp(-1.0, 1.0);
              newPan01 = ((nextSigned + 1.0) * 0.5).clamp(0.0, 1.0);
            }

            final finalAct = SetMasterPanAction(
              oldPan: oldPan01,
              newPan: newPan01,
              applyToState: (p) {
                setState(() {
                  _masterPan = p;
                });
              },
            );

            await _undoManager.executeWithoutAdd(finalAct);
            groupedActions.add(finalAct);

            _chatController.insertMessage(
              ActionSummaryMessage(
                text:
                    '• Adjusted Master Pan from ${panToText(oldPan01)} to ${panToText(newPan01)} •',
              ),
            );
            continue;
          }

        case 'delete_effect':
          {
            final row = (a.data['row'] as int);
            final contains =
                (a.data['effect_name_contains'] as String).toLowerCase();

            final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
            final idx =
                effects.indexWhere((e) => e.toLowerCase().contains(contains));
            if (idx == -1) continue;

            // If you have a true remove action, use it.
            // Otherwise: implement RemoveEffectAction or temporarily bypass.
            // await _undoManager.execute(
            //   RemoveEffectAction(
            //     row: row,
            //     effectIndex: idx,
            //     pathOrName: contains,
            //     onChange: () {
            //       setState(() {});
            //       _refreshRowFx(row);
            //     },
            //   ),
            // );

            EditorUndoAction finalAct = RemoveEffectAction(
              row: row,
              effectIndex: idx,
              pathOrName: contains,
              onChange: () {
                setState(() {});
                _refreshRowFx(row);
              },
            );

            await _undoManager.executeWithoutAdd(
              finalAct,
            ); // need this so that you can make a compound undo action while preserving execute order
            groupedActions.add(finalAct);

            _mixHighlighter.trigger([
              HaloKey('row:$row'),
              HaloKey('row:$row:effects_tab'),
              HaloKey('row:$row:fx_list'),
              HaloKey('row:$row:fx_contains:$contains'),
            ]);

            _chatController.insertMessage(
              ActionSummaryMessage(
                  text: '• Removed ${effects[idx]} from Track ${row + 1} •'),
            );
            continue;
          }

        case 'delete_master_effect':
          {
            final contains =
                (a.data['effect_name_contains'] as String).toLowerCase();
            final effects = await JuceAudioEngine.getMasterEffects();
            final idx =
                effects.indexWhere((e) => e.toLowerCase().contains(contains));
            if (idx == -1) continue;

            final finalAct = RemoveMasterEffectAction(
              effectIndex: idx,
              pathOrName: effects[idx],
              onChange: () => setState(() {}),
            );

            await _undoManager.executeWithoutAdd(finalAct);
            groupedActions.add(finalAct);

            _chatController.insertMessage(
              ActionSummaryMessage(
                  text: '• Removed ${effects[idx]} from Master Bus •'),
            );
            continue;
          }

        case 'ensure_effect':
          final row = (a.data['row'] as int);
          final contains =
              (a.data['effect_name_contains'] as String).toLowerCase();

          final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
          final already =
              effects.indexWhere((e) => e.toLowerCase().contains(contains));
          if (already != -1) continue;

          // Insert: find best matching plugin path (only Mixroom effects)
          final effectName = pickMixroomEffect(contains);
          if (effectName == null) continue;

          // await _undoManager.execute(
          //   InsertEffectAction(
          //     row: row,
          //     pathOrName: effectName,
          //     onChange: () {
          //       setState(() {});
          //       _refreshRowFx(row);
          //     },
          //   ),
          // );

          EditorUndoAction finalAct = InsertEffectAction(
            row: row,
            pathOrName: effectName,
            onChange: () {
              setState(() {});
              _refreshRowFx(row);
            },
          );

          await _undoManager.executeWithoutAdd(
            finalAct,
          ); // need this so that you can make a compound undo action while preserving execute order
          groupedActions.add(finalAct);

          _mixHighlighter.trigger([
            HaloKey('row:$row'),
            HaloKey('row:$row:effects_tab'),
            HaloKey('row:$row:fx_list'),
            HaloKey('row:$row:fx_contains:$contains'),
          ]);

          final summary = '• Added $effectName to Track ${row + 1} •';
          _chatController.insertMessage(ActionSummaryMessage(text: summary));
          continue;

        case 'ensure_master_effect':
          {
            final contains =
                (a.data['effect_name_contains'] as String).toLowerCase();
            final effects = await JuceAudioEngine.getMasterEffects();
            final already =
                effects.indexWhere((e) => e.toLowerCase().contains(contains));
            if (already != -1) continue;

            final effectName = pickMixroomEffect(contains);
            if (effectName == null) continue;

            final finalAct = InsertMasterEffectAction(
              pathOrName: effectName,
              onChange: () => setState(() {}),
            );

            await _undoManager.executeWithoutAdd(finalAct);
            groupedActions.add(finalAct);

            _chatController.insertMessage(
              ActionSummaryMessage(text: '• Added $effectName to Master Bus •'),
            );
            continue;
          }

        case 'adjust_effect_param_by_name':
          {
            final row = (a.data['row'] as int);
            final effectContains =
                (a.data['effect_name_contains'] as String).toLowerCase();

            final skipIfMissing =
                (a.data['skip_if_missing_effect'] as bool?) ?? true;

            final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
            final fxIndex = effects
                .indexWhere((e) => e.toLowerCase().contains(effectContains));
            if (fxIndex == -1) {
              if (skipIfMissing) continue;
              // else: you could ensure_effect first; but typically model emits ensure_effect already
              continue;
            }

            final paramsRaw =
                await JuceAudioEngine.getTrackPluginParameters(row, fxIndex);
            final params =
                paramsRaw.map((e) => Map<String, dynamic>.from(e)).toList();

            final exactParamName = a.data['param_name'] as String?;
            final containsAny = (a.data['param_name_contains_any'] as List?)
                ?.map((e) => e.toString())
                .toList();

            final picked = _pickParam(params,
                exactName: exactParamName, containsAny: containsAny);
            if (picked == null) continue;

            final paramId = (picked['id'] as String?) ??
                (picked['name'] as String); // robust
            final paramName = (picked['name'] as String?) ?? paramId;
            final current = (picked['value'] as num).toDouble();

            final double? pMin =
                picked['min'] is num ? (picked['min'] as num).toDouble() : null;
            final double? pMax =
                picked['max'] is num ? (picked['max'] as num).toDouble() : null;

            final clamp01 = (a.data['clamp_0_1'] as bool?) ?? false;

            final mode = (a.data['mode'] as String?) ?? 'delta';

            double next = current;

            if (mode == 'set') {
              if (a.data.containsKey('value_norm') &&
                  pMin != null &&
                  pMax != null) {
                final vn =
                    (a.data['value_norm'] as num).toDouble().clamp(0.0, 1.0);
                next = pMin + (pMax - pMin) * vn;
              } else {
                next = (a.data['value'] as num).toDouble();
              }
            } else {
              // delta mode
              double delta;
              if (a.data.containsKey('delta_norm')) {
                final dn = (a.data['delta_norm'] as num).toDouble();
                if (pMin != null && pMax != null) {
                  delta = dn * (pMax - pMin);
                } else {
                  delta = dn;
                }
              } else {
                delta = (a.data['delta'] as num).toDouble();
              }
              next = current + delta;
            }

            // -----------------------------
            // HARD SAFETY CLAMPS (action-level)
            // -----------------------------
            final double? hardMin = a.data['clamp_min'] is num
                ? (a.data['clamp_min'] as num).toDouble()
                : null;
            final double? hardMax = a.data['clamp_max'] is num
                ? (a.data['clamp_max'] as num).toDouble()
                : null;

            // Apply hard clamps FIRST (authoritative)
            if (hardMin != null || hardMax != null) {
              final lo = hardMin ?? double.negativeInfinity;
              final hi = hardMax ?? double.infinity;
              next = next.clamp(lo, hi);
            }

            // -----------------------------
            // Plugin range clamp
            // -----------------------------
            if (pMin != null && pMax != null) {
              next = next.clamp(pMin, pMax);
            } else if (clamp01) {
              next = next.clamp(0.0, 1.0);
            }

            // await _undoManager.execute(
            //   SetEffectParamAction(
            //     row: row,
            //     effectIndex: fxIndex,
            //     paramId: paramName, // if your engine needs name instead, use paramName
            //     oldValue: current,
            //     newValue: next,
            //     onChange: () {
            //       setState(() {});
            //       _refreshRowFx(row);
            //     },
            //   ),
            // );

            EditorUndoAction finalAct = SetEffectParamAction(
              row: row,
              effectIndex: fxIndex,
              paramId:
                  paramName, // if your engine needs name instead, use paramName
              oldValue: current,
              newValue: next,
              onChange: () {
                setState(() {});
                _refreshRowFx(row);
              },
            );

            await _undoManager.executeWithoutAdd(
              finalAct,
            ); // need this so that you can make a compound undo action while preserving execute order
            groupedActions.add(finalAct);

            _mixHighlighter.trigger([
              HaloKey('row:$row'),
              HaloKey('row:$row:effects_tab'),
              HaloKey('row:$row:fx_list'),
              HaloKey('row:$row:fx_index:$fxIndex'),
              HaloKey(
                  'row:$row:fx_index:$fxIndex:param:$paramId'), // TODO: put paramName instead of paramId maybe
            ]);

            _chatController.insertMessage(
              ActionSummaryMessage(
                text:
                    '• Adjusted $paramName from ${current.toStringAsFixed(2)} to ${next.toStringAsFixed(2)} on ${effects[fxIndex]} (Track ${row + 1}) •',
              ),
            );
            continue;
          }

        case 'adjust_master_effect_param_by_name':
          {
            final effectContains =
                (a.data['effect_name_contains'] as String).toLowerCase();
            final skipIfMissing =
                (a.data['skip_if_missing_effect'] as bool?) ?? true;

            final effects = await JuceAudioEngine.getMasterEffects();
            final fxIndex = effects
                .indexWhere((e) => e.toLowerCase().contains(effectContains));
            if (fxIndex == -1) {
              if (skipIfMissing) continue;
              continue;
            }

            final paramsRaw =
                await JuceAudioEngine.getMasterPluginParameters(fxIndex);
            final params =
                paramsRaw.map((e) => Map<String, dynamic>.from(e)).toList();

            final exactParamName = a.data['param_name'] as String?;
            final containsAny = (a.data['param_name_contains_any'] as List?)
                ?.map((e) => e.toString())
                .toList();

            final picked = _pickParam(params,
                exactName: exactParamName, containsAny: containsAny);
            if (picked == null) continue;

            final paramId =
                (picked['id'] as String?) ?? (picked['name'] as String);
            final paramName = (picked['name'] as String?) ?? paramId;
            final current = (picked['value'] as num).toDouble();

            final double? pMin =
                picked['min'] is num ? (picked['min'] as num).toDouble() : null;
            final double? pMax =
                picked['max'] is num ? (picked['max'] as num).toDouble() : null;

            final clamp01 = (a.data['clamp_0_1'] as bool?) ?? false;
            final mode = (a.data['mode'] as String?) ?? 'delta';

            double next = current;
            if (mode == 'set') {
              if (a.data.containsKey('value_norm') &&
                  pMin != null &&
                  pMax != null) {
                final vn =
                    (a.data['value_norm'] as num).toDouble().clamp(0.0, 1.0);
                next = pMin + (pMax - pMin) * vn;
              } else {
                next = (a.data['value'] as num).toDouble();
              }
            } else {
              double delta;
              if (a.data.containsKey('delta_norm')) {
                final dn = (a.data['delta_norm'] as num).toDouble();
                if (pMin != null && pMax != null) {
                  delta = dn * (pMax - pMin);
                } else {
                  delta = dn;
                }
              } else {
                delta = (a.data['delta'] as num).toDouble();
              }
              next = current + delta;
            }

            final double? hardMin = a.data['clamp_min'] is num
                ? (a.data['clamp_min'] as num).toDouble()
                : null;
            final double? hardMax = a.data['clamp_max'] is num
                ? (a.data['clamp_max'] as num).toDouble()
                : null;

            if (hardMin != null || hardMax != null) {
              final lo = hardMin ?? double.negativeInfinity;
              final hi = hardMax ?? double.infinity;
              next = next.clamp(lo, hi);
            }

            if (pMin != null && pMax != null) {
              next = next.clamp(pMin, pMax);
            } else if (clamp01) {
              next = next.clamp(0.0, 1.0);
            }

            final finalAct = SetMasterEffectParamAction(
              effectIndex: fxIndex,
              paramId: paramName,
              oldValue: current,
              newValue: next,
              onChange: () => setState(() {}),
            );

            await _undoManager.executeWithoutAdd(finalAct);
            groupedActions.add(finalAct);

            _chatController.insertMessage(
              ActionSummaryMessage(
                text:
                    '• Adjusted $paramName from ${current.toStringAsFixed(2)} to ${next.toStringAsFixed(2)} on ${effects[fxIndex]} (Master Bus) •',
              ),
            );
            continue;
          }

        case 'hard_reset_row_fx':
          {
            final row = (a.data['row'] as int);

            // Query actual FX list
            final effects = await JuceAudioEngine.getTrackEffectsForRow(row);

            if (effects.isEmpty) continue;

            // IMPORTANT: delete back-to-front to keep indices valid
            for (int fxIndex = effects.length - 1; fxIndex >= 0; fxIndex--) {
              final fxName = effects[fxIndex];

              EditorUndoAction act = RemoveEffectAction(
                row: row,
                effectIndex: fxIndex,
                pathOrName: fxName,
                onChange: () {
                  setState(() {});
                  _refreshRowFx(row);
                },
              );

              await _undoManager.executeWithoutAdd(act);
              groupedActions.add(act);
            }

            _chatController.insertMessage(ActionSummaryMessage(
                text: '• Removed all effects on Track ${row + 1} •'));

            continue;
          }

        case 'hard_reset_master_fx':
          {
            final effects = await JuceAudioEngine.getMasterEffects();
            if (effects.isEmpty) continue;

            for (int fxIndex = effects.length - 1; fxIndex >= 0; fxIndex--) {
              final fxName = effects[fxIndex];
              final act = RemoveMasterEffectAction(
                effectIndex: fxIndex,
                pathOrName: fxName,
                onChange: () => setState(() {}),
              );

              await _undoManager.executeWithoutAdd(act);
              groupedActions.add(act);
            }

            _chatController.insertMessage(
              ActionSummaryMessage(
                  text: '• Removed all effects on Master Bus •'),
            );
            continue;
          }

        default:
          // Unknown / noop → ignore safely
          continue;
      }
    }
    if (groupedActions.isEmpty) return;

    await _undoManager.addWithoutExecute(
        CompoundUndoAction('AI mixing adjustments', groupedActions));
  }

  Map<String, dynamic>? _pickParam(List<Map<String, dynamic>> params,
      {String? exactName, List<String>? containsAny}) {
    final lowerExact = exactName?.toLowerCase();

    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final p in params) {
      final name = (p['name']?.toString() ?? '');
      final n = name.toLowerCase();

      int score = 0;
      if (lowerExact != null && n == lowerExact) score += 100;
      if (containsAny != null &&
          containsAny.any((s) => n.contains(s.toLowerCase()))) score += 50;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }

    return bestScore > 0 ? best : null;
  }

  Future<Map<String, dynamic>> _buildProducerSnapshot() async {
    final maxRows = math.max(_rowCount, 1);

    final rowGain = List<double>.generate(
        maxRows, (i) => i < _rowGain.length ? _rowGain[i] : 1.0);
    final rowPan = List<double>.generate(
        maxRows, (i) => i < _rowPan.length ? _rowPan[i] : 0.5);
    final rowAutomation = List<List<AutomationPoint>>.generate(maxRows, (i) {
      if (i < _rowVolumeAutomation.length) {
        return _rowVolumeAutomation[i]
            .map((p) => AutomationPoint(x: p.x, volume: p.volume))
            .toList();
      }
      return [AutomationPoint(x: 0.0, volume: 1.0)];
    });

    final builder =
        ProjectStateBuilder(classifier: _classifier, maxRows: maxRows);
    final projectState = await builder.build(
      audioTracks: _audioTracks,
      bpmFallback: _tempo,
      rowGain: rowGain,
      rowPan: rowPan,
      rowAutomation: rowAutomation,
      masterGain0to3: _masterGain,
      masterPan0to1: _masterPan,
    );

    final masterEffects = await JuceAudioEngine.getMasterEffects();
    final masterFx = <Map<String, dynamic>>[];
    for (int i = 0; i < masterEffects.length; i++) {
      final params = await JuceAudioEngine.getMasterPluginParameters(i);
      final bypassed = await JuceAudioEngine.getMasterEffectBypassState(i);
      masterFx.add({
        'index': i,
        'name': masterEffects[i],
        'bypassed': bypassed,
        'params': params,
      });
    }

    return {
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'tempo_bpm': _tempo,
      'project_state': projectState.toJson(),
      'master': {
        'gain': _masterGain,
        'pan': _masterPan,
        'effects': masterFx,
      },
    };
  }

  void _recordProducerManualEdit(String kind, Map<String, dynamic> payload) {
    if (!_producerDataMode) return;
    unawaited(
      _producerCollector.recordManualEdit(
        kind: kind,
        payload: {
          ...payload,
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  void _insertAssistantChatText(String text) {
    _chatController.insertMessage(
      TextMessage(
        id: const Uuid().v4(),
        authorId: 'assistant',
        createdAt: DateTime.now().toUtc(),
        text: text,
      ),
    );
  }

  Future<void> _setProducerDataMode(bool enabled,
      {String closeReason = 'ui_toggle'}) async {
    if (enabled == _producerDataMode) return;
    if (_producerUiBusy) return;
    setState(() => _producerUiBusy = true);
    try {
      if (enabled) {
        _producerDataMode = true;
        await _producerCollector.setEnabled(true);
        _insertAssistantChatText(
            'Producer data mode enabled. AI steps and manual edits are now being captured.');
      } else {
        if (_producerCollector.hasActiveSession) {
          await _producerCollector.closeSession(reason: closeReason);
        }
        _producerDataMode = false;
        await _producerCollector.setEnabled(false);
        _insertAssistantChatText('Producer data mode disabled.');
      }
    } finally {
      if (mounted) {
        setState(() => _producerUiBusy = false);
      }
    }
  }

  Future<void> _exportProducerSession() async {
    final file = await _producerCollector.exportActiveSession();
    if (file == null) {
      _insertAssistantChatText('No active producer session to export yet.');
      return;
    }
    _insertAssistantChatText('Exported producer session: ${file.path}');
  }

  Future<bool> _handleProducerCommand(String text) async {
    final raw = text.trim();
    if (!raw.toLowerCase().startsWith('/producer')) return false;

    final parts = raw.split(RegExp(r'\s+'));
    final cmd = parts.length >= 2 ? parts[1].toLowerCase() : 'help';

    switch (cmd) {
      case 'on':
        await _setProducerDataMode(true, closeReason: 'command_on');
        return true;

      case 'off':
        await _setProducerDataMode(false, closeReason: 'command_off');
        return true;

      case 'export':
        await _exportProducerSession();
        return true;

      default:
        _insertAssistantChatText(
          'Producer commands:\\n'
          '/producer on\\n'
          '/producer off\\n'
          '/producer export',
        );
        return true;
    }
  }

  Future<void> runOneButtonMix() async {
    // optional: show system “Mixing…” message
    _chatController.insertMessage(
      TextMessage(
        id: const Uuid().v4(),
        authorId: 'system',
        createdAt: DateTime.now().toUtc(),
        text: 'Mixing…',
        metadata: {'typing': true},
      ),
    );

    final prompt = "Make this mix sound like a finished, professional release. "
        "Balance levels, reduce masking, tame harshness, and set tasteful space. "
        "Keep it natural and avoid extreme changes, and don't make it that quiet, prefer loud over soft. "
        "This is not a proposal but an execution. You may proceed without my approval";

    Map<String, dynamic>? producerPreSnapshot;
    if (_producerDataMode) {
      producerPreSnapshot = await _buildProducerSnapshot();
    }

    final reply = await _chatPipeline.handleUserText(
      text: prompt,
      audioTracks: _audioTracks,
      bpmFallback: _tempo,
      rowGain: _rowGain,
      rowPan: _rowPan,
      rowAutomation: _rowVolumeAutomation,
      masterGain0to3: _masterGain,
      masterPan0to1: _masterPan,
      autoApplyProposals: true, // <-- key
    );

    if (reply.hasMix) {
      await applyMixingResult(reply.mixing!);
      _chatPipeline.recordAppliedMix(reply.mixing!);

      if (_producerDataMode && producerPreSnapshot != null) {
        final producerPostSnapshot = await _buildProducerSnapshot();
        await _producerCollector.recordAiStep(
          prompt: prompt,
          preSnapshot: producerPreSnapshot,
          postSnapshot: producerPostSnapshot,
          resolvedActions:
              reply.mixing!.actions.map((a) => a.toJson()).toList(),
          llmPayload: reply.meta,
        );
      }
    }

    _chatController.insertMessage(
      TextMessage(
          id: const Uuid().v4(),
          authorId: 'assistant',
          createdAt: DateTime.now().toUtc(),
          text: reply.message),
    );

    // show a snackbar/modal if you want:
    // ScaffoldMessenger.of(context).showSnackBar(...)
  }

  Widget _buildBottomChatAndTransport({
    bool includeChatBar = true,
    bool includeProducerCapture = true,
    bool includeTransport = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (includeProducerCapture)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(_kChatChromeOpacity),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.science_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _producerDataMode
                              ? (_producerCollector.hasActiveSession
                                  ? 'Producer Capture: ON'
                                  : 'Producer Capture: ON (waiting for first AI step)')
                              : 'Producer Capture: OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        tooltip: 'Export producer session',
                        onPressed: _producerDataMode
                            ? () async {
                                await _exportProducerSession();
                                if (mounted) setState(() {});
                              }
                            : null,
                        icon: Icon(
                          Icons.ios_share_rounded,
                          size: 17,
                          color: _producerDataMode
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                      Switch.adaptive(
                        value: _producerDataMode,
                        onChanged: _producerUiBusy
                            ? null
                            : (v) async {
                                await _setProducerDataMode(v);
                                if (mounted) setState(() {});
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // === Chat Field Section WITH padding ===
        // Padding(
        //   padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        //   child: _Glass(
        //     radius: 22,
        //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        //     opacity: 0.10,
        //     child: Row(
        //       children: [
        //         Container(
        //           width: 28,
        //           height: 28,
        //           decoration: BoxDecoration(
        //             color: Colors.white.withOpacity(0.12),
        //             borderRadius: BorderRadius.circular(10),
        //             border: Border.all(color: Colors.white.withOpacity(0.14)),
        //           ),
        //           child: const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
        //         ),
        //         const SizedBox(width: 10),
        //         Text(
        //           'Type...',
        //           style: TextStyle(
        //             color: Colors.white.withOpacity(0.72),
        //             fontSize: 15,
        //           ),
        //         ),
        //       ],
        //     ),
        //   ),
        // ),
        if (includeChatBar)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // === GLASS CHAT BAR (fills available space) ===
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: _ChatBar(
                    expanded: _chatInputActive,
                    hasText: _chatHasText,
                    controller: _chatTextController,
                    focusNode: _chatFocusNode,
                    onTapBar: () {
                      if (_sampleBrowserVisible) {
                        unawaited(_stopSampleAudition());
                      }
                      if (!_chatExpanded) {
                        setState(() {
                          _showAddActionsPanel = false;
                          _sampleBrowserVisible = false;
                          _sampleBrowserExpanded = false;
                          _sampleDragActive = false;
                          _reopenSampleBrowserAfterDrag = false;
                          _reopenSampleBrowserExpanded = false;
                          _chatExpanded = true;
                          _chatInputActive = false;
                        });
                        return;
                      }
                      if (!_chatInputActive) {
                        setState(() {
                          _showAddActionsPanel = false;
                          _sampleBrowserVisible = false;
                          _sampleBrowserExpanded = false;
                          _sampleDragActive = false;
                          _reopenSampleBrowserAfterDrag = false;
                          _reopenSampleBrowserExpanded = false;
                          _chatInputActive = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _chatFocusNode.requestFocus();
                        });
                        return;
                      }
                      if (!_chatFocusNode.hasFocus) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _chatFocusNode.requestFocus();
                        });
                      }
                    },
                    onSubmit: () async {
                      final text = _chatTextController.text.trim();
                      if (text.isEmpty) return;

                      _chatTextController.clear();
                      _chatFocusNode.unfocus();

                      final userText = text;
                      // 1. Push user message
                      _chatController.insertMessage(
                        TextMessage(
                          id: const Uuid().v4(),
                          authorId: 'user',
                          createdAt: DateTime.now().toUtc(),
                          text: userText,
                        ),
                      );

                      if (await _handleProducerCommand(userText)) {
                        setState(() {});
                        return;
                      }

                      Map<String, dynamic>? producerPreSnapshot;
                      if (_producerDataMode) {
                        producerPreSnapshot = await _buildProducerSnapshot();
                      }

                      // 2. Run pipeline
                      ChatPipelineResult reply =
                          await _chatPipeline.handleUserText(
                        text: userText,
                        audioTracks: _audioTracks,
                        bpmFallback: _tempo,
                        rowGain: _rowGain,
                        rowPan: _rowPan,
                        rowAutomation: _rowVolumeAutomation,
                        masterGain0to3: _masterGain,
                        masterPan0to1: _masterPan,
                        // autoApplyProposals: true, // does not ask for approval, just execute
                      );

                      print(reply.toString());

                      // await applyMixingResult(reply);
                      if (reply.hasMix) {
                        await applyMixingResult(reply.mixing!);

                        // IMPORTANT: teach the assistant what actually changed
                        _chatPipeline.recordAppliedMix(reply.mixing!);

                        if (_producerDataMode && producerPreSnapshot != null) {
                          final producerPostSnapshot =
                              await _buildProducerSnapshot();
                          await _producerCollector.recordAiStep(
                            prompt: userText,
                            preSnapshot: producerPreSnapshot,
                            postSnapshot: producerPostSnapshot,
                            resolvedActions: reply.mixing!.actions
                                .map((a) => a.toJson())
                                .toList(),
                            llmPayload: reply.meta,
                          );
                        }
                      }

                      // 3. Push assistant reply
                      _chatController.insertMessage(
                        TextMessage(
                          id: const Uuid().v4(),
                          authorId: 'assistant',
                          createdAt: DateTime.now().toUtc(),
                          text: reply.message!,
                        ),
                      );

                      if (!_chatExpanded) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(
                            content: Text(reply.message),
                            duration: const Duration(seconds: 4)));
                      }

                      setState(() {});
                      //TODO: refetch effects and stuff like that

                      // debugPrint('AI: $reply');
                    },
                  ),
                ),
              ),

              if (!_chatInputActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        scale: _addButtonPressed ? 0.94 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _showAddActionsPanel
                                ? const Color(0x33558DFF)
                                : Colors.white.withOpacity(_kChatChromeOpacity),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _showAddActionsPanel
                                  ? const Color(0xAA8BB6FF)
                                  : Colors.white.withOpacity(0.14),
                            ),
                            boxShadow: _showAddActionsPanel
                                ? [
                                    BoxShadow(
                                      color: const Color(0x662E6EEB)
                                          .withOpacity(0.45),
                                      blurRadius: 14,
                                      spreadRadius: 1.5,
                                    ),
                                  ]
                                : const [],
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onHighlightChanged: (pressed) {
                              if (!mounted) return;
                              setState(() {
                                _addButtonPressed = pressed;
                              });
                            },
                            onTap: () {
                              if (_sampleBrowserVisible) {
                                _closeAddActionsPanel();
                                unawaited(_closeSampleBrowser());
                                return;
                              }
                              if (_showAddActionsPanel) {
                                _closeAddActionsPanel();
                              } else {
                                _openAddActionsPanel();
                              }
                            },
                            child: const Icon(Icons.add,
                                color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

        // ==== Transport Drawer =============================================
        if (includeTransport)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.transparent),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              // child: BackdropFilter(
              // filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07), // softer white glass
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.08))),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 30,
                        offset: const Offset(0, -12)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main transport drawer
                    SizedBox(
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // --- Left: Undo / Redo -----------------------------------
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final height = constraints.maxHeight * 0.6;
                                  return Container(
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                          color:
                                              Colors.white.withOpacity(0.14)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Expanded(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topLeft: Radius.circular(22),
                                                bottomLeft: Radius.circular(22),
                                              ),
                                              onTap: _undoManager.canUndo
                                                  ? () async {
                                                      final action =
                                                          await _undoManager
                                                              .undo();
                                                      if (!mounted ||
                                                          action == null)
                                                        return;

                                                      final messenger =
                                                          ScaffoldMessenger.of(
                                                              context);
                                                      messenger
                                                          .hideCurrentSnackBar();
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Undo: ${action.description}'),
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      1200),
                                                        ),
                                                      );

                                                      setState(() {});
                                                    }
                                                  : null,
                                              child: SizedBox.expand(
                                                child: Center(
                                                  child: Icon(
                                                    Icons.undo,
                                                    size: 20,
                                                    color: _undoManager.canUndo
                                                        ? Colors.white
                                                        : Colors.white
                                                            .withOpacity(0.3),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                            width: 1,
                                            height: 28,
                                            color:
                                                Colors.white.withOpacity(0.2)),
                                        Expanded(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topRight: Radius.circular(22),
                                                bottomRight:
                                                    Radius.circular(22),
                                              ),
                                              onTap: _undoManager.canRedo
                                                  ? () async {
                                                      final action =
                                                          await _undoManager
                                                              .redo();
                                                      if (!mounted ||
                                                          action == null)
                                                        return;

                                                      final messenger =
                                                          ScaffoldMessenger.of(
                                                              context);
                                                      messenger
                                                          .hideCurrentSnackBar();
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Redo: ${action.description}'),
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      1200),
                                                        ),
                                                      );
                                                      setState(() {});
                                                    }
                                                  : null,
                                              child: SizedBox.expand(
                                                child: Center(
                                                  child: Icon(
                                                    Icons.redo,
                                                    size: 20,
                                                    color: _undoManager.canRedo
                                                        ? Colors.white
                                                        : Colors.white
                                                            .withOpacity(0.3),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          // --- Center Transport ------------------------------------
                          Expanded(
                            flex: 4,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(3, 0, 3, 0),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final height = constraints.maxHeight * 0.6;
                                  final iconSize = height * 0.55;
                                  final borderRadius =
                                      BorderRadius.circular(height / 2);

                                  return Container(
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: borderRadius,
                                      border: Border.all(
                                          color:
                                              Colors.white.withOpacity(0.14)),
                                    ),
                                    child: Row(
                                      children: [
                                        _transportSegment(
                                          icon: Icons.skip_previous,
                                          onTap: () async {
                                            if (_isRecording)
                                              return; // disabled during recording
                                            await _restartAudio(
                                                _safeAudioEditorStateSetter);
                                          },
                                          radius: BorderRadius.only(
                                            topLeft:
                                                Radius.circular(height / 2),
                                            bottomLeft:
                                                Radius.circular(height / 2),
                                          ),
                                          iconSize: iconSize,
                                        ),
                                        _verticalDivider(height),
                                        _transportSegment(
                                          icon: _isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          onTap: () async {
                                            if (_isRecording) {
                                              // Pause button should also stop recording and stop playback
                                              await _stopRecordingJuce(
                                                  keepPlaying: false);
                                            } else {
                                              await _togglePlayPause();
                                            }
                                          },
                                          iconSize: iconSize,
                                        ),
                                        _verticalDivider(height),
                                        _transportSegment(
                                          icon: _isRecording
                                              ? Icons.stop_circle
                                              : Icons.fiber_manual_record,
                                          onTap: _onRecordPressed,
                                          radius: BorderRadius.only(
                                            topRight:
                                                Radius.circular(height / 2),
                                            bottomRight:
                                                Radius.circular(height / 2),
                                          ),
                                          iconSize: iconSize,
                                          iconColor: _isRecording
                                              ? Colors.white
                                              : Colors.red,
                                          backgroundColor: _isRecording
                                              ? const Color(0xCCFF3B30)
                                              : Colors.transparent,
                                          borderColor: _isRecording
                                              ? const Color(0xFFFF8A80)
                                              : null,
                                          boxShadow: _isRecording
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.redAccent
                                                        .withOpacity(0.45),
                                                    blurRadius: 12,
                                                    spreadRadius: 1.5,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          // --- Right: AI Mixer -------------------------------------------------
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final totalHeight = constraints.maxHeight;
                                  final pillHeight = totalHeight *
                                      0.6; // e.g. ~42 if container is 76
                                  final logoSize =
                                      pillHeight * 0.9; // keep proportional
                                  final spacing = totalHeight * 0.08;
                                  final fontSize = totalHeight * 0.2;

                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // --- Blue glossy pill with logo only ---
                                      // --- Blue glossy pill with logo only ---
                                      // Wrap with Material + InkWell for proper tap + ripple on rounded pill
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                              pillHeight / 2),
                                          onTap: () async {
                                            // optional: haptic
                                            // HapticFeedback.lightImpact();
                                            final run = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text(
                                                    'One-Button Mix'),
                                                content: const Text(
                                                  'This will:\n'
                                                  '• Balance levels\n'
                                                  '• Reduce masking\n'
                                                  '• Improve clarity\n\n'
                                                  'You can undo everything.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text('Run'),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (run != true) return;

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(const SnackBar(
                                                content: Text('Mixing…')));

                                            await runOneButtonMix();

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'One-Button Mix executed. Open chat for details.'),
                                                duration: Duration(seconds: 3),
                                              ),
                                            );
                                          },
                                          child: SizedBox(
                                            height: pillHeight,
                                            width: double.infinity,
                                            child: Ink(
                                              // height: pillHeight,
                                              // width: pillHeight * 1.7,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFF5C7AFF),
                                                    Color(0xFF3050FF)
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        pillHeight / 2),
                                                border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.18)),
                                                // boxShadow: [
                                                //   BoxShadow(
                                                //     color: const Color(0xFF4A6BFF).withOpacity(0.55),
                                                //     blurRadius: 20,
                                                //     offset: const Offset(0, 6),
                                                //   ),
                                                //   const BoxShadow(
                                                //     color: Color(0x22FFFFFF),
                                                //     blurRadius: 0,
                                                //     spreadRadius: 1,
                                                //     offset: Offset(0, -1),
                                                //   ),
                                                // ],
                                              ),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    pillHeight /
                                                                        2),
                                                        gradient:
                                                            LinearGradient(
                                                          begin: Alignment
                                                              .topCenter,
                                                          end: Alignment
                                                              .bottomCenter,
                                                          colors: [
                                                            Colors.white
                                                                .withOpacity(
                                                                    0.18),
                                                            Colors.transparent,
                                                            Colors.transparent,
                                                            Colors.white
                                                                .withOpacity(
                                                                    0.12),
                                                          ],
                                                          stops: const [
                                                            0.0,
                                                            0.35,
                                                            0.65,
                                                            1.0
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Center(
                                                    child: Image.asset(
                                                      // 'assets/mixroom_logo_202.png',
                                                      'assets/fading_w_logo_crop.png',
                                                      // width: logoSize,
                                                      height: pillHeight * 0.6,
                                                      color: Colors.white,
                                                      fit: BoxFit.fitWidth,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // SizedBox(height: spacing),

                                      // --- Label below pill ---
                                      // Text(
                                      //   'AI Mixer',
                                      //   style: TextStyle(
                                      //     color: Colors.white,
                                      //     fontSize: fontSize,
                                      //     fontWeight: FontWeight.w500,
                                      //     letterSpacing: 0.3,
                                      //   ),
                                      // ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom spacer with same translucent background
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(0)),
                      child: Container(
                        height: 10, // or more
                        width: double.infinity,
                      ),
                    ),
                  ],
                ),
              ),
              // ),
            ),
          ),
      ],
    );
  }

  Widget _transportSegment({
    required IconData icon,
    required VoidCallback onTap,
    BorderRadius? radius,
    double iconSize = 20,
    Color? iconColor,
    Color? backgroundColor,
    Color? borderColor,
    List<BoxShadow>? boxShadow,
  }) {
    final resolvedRadius = radius ?? BorderRadius.zero;
    return Expanded(
      child: InkWell(
        borderRadius: resolvedRadius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: resolvedRadius,
            border: borderColor != null
                ? Border.all(color: borderColor, width: 1.2)
                : null,
            boxShadow: boxShadow,
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: iconColor ?? Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _verticalDivider(double height) {
    return Container(
        width: 1, height: height * 0.6, color: Colors.white.withOpacity(0.2));
  }

  List<double> _buildOnsetEnvelopeFromSamples(
    Float32List samples, {
    int frameSize = 1024,
    int hopSize = 256,
  }) {
    if (samples.length < frameSize || hopSize <= 0) return const <double>[];
    final env = <double>[];
    double prevRms = 0.0;
    for (int i = 0; i + frameSize <= samples.length; i += hopSize) {
      double sumSq = 0.0;
      for (int j = 0; j < frameSize; j++) {
        final s = samples[i + j];
        sumSq += s * s;
      }
      final rms = math.sqrt(sumSq / frameSize);
      final flux = math.max(0.0, rms - prevRms);
      env.add(flux);
      prevRms = rms;
    }
    return env;
  }

  double? _detectTempoFromOnsetEnvelope(
    List<double> onsetEnv,
    double envSampleRateHz,
  ) {
    if (onsetEnv.length < 24 || envSampleRateHz <= 0.0) return null;

    final env = List<double>.from(onsetEnv);
    final mean = env.reduce((a, b) => a + b) / env.length;
    for (int i = 0; i < env.length; i++) {
      env[i] = math.max(0.0, env[i] - mean * 0.65);
    }

    for (int i = 1; i < env.length - 1; i++) {
      env[i] = (env[i - 1] + env[i] + env[i + 1]) / 3.0;
    }

    int minLag = (envSampleRateHz * 60.0 / 240.0).round(); // 240 BPM
    int maxLag = (envSampleRateHz * 60.0 / 40.0).round(); // 40 BPM
    minLag = minLag.clamp(1, env.length - 2);
    maxLag = maxLag.clamp(minLag + 1, env.length - 1);
    if (minLag >= maxLag) return null;

    double corrAt(int lag) {
      double s = 0.0;
      for (int i = lag; i < env.length; i++) {
        s += env[i] * env[i - lag];
      }
      return s;
    }

    double bestScore = -1.0;
    int bestLag = -1;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double score = corrAt(lag);
      final lag2 = lag * 2;
      final lag3 = lag * 3;
      if (lag2 <= maxLag) score += 0.5 * corrAt(lag2);
      if (lag3 <= maxLag) score += 0.25 * corrAt(lag3);
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }

    if (bestLag <= 0 || bestScore <= 0.0) return null;
    double bpm = 60.0 * envSampleRateHz / bestLag;
    while (bpm < 70.0) bpm *= 2.0;
    while (bpm > 190.0) bpm /= 2.0;
    return bpm;
  }

  Future<double?> _detectClipTempoBpm(AudioTrack clip) async {
    if (clip.isMidi) return null;

    const int sampleRate = 16000;
    Float32List decoded = Float32List(0);
    try {
      decoded = await JuceAudioEngine.decodeAudioMono16k(clip.file.path);
    } catch (_) {
      decoded = Float32List(0);
    }

    if (decoded.isNotEmpty) {
      int start = (clip.trimStart.inMilliseconds * sampleRate / 1000).round();
      int end = (clip.trimEnd.inMilliseconds * sampleRate / 1000).round();
      start = start.clamp(0, decoded.length);
      end = end.clamp(start, decoded.length);
      Float32List segment = decoded;
      if (end > start && end - start >= sampleRate * 4) {
        segment = Float32List.sublistView(decoded, start, end);
      }
      final env = _buildOnsetEnvelopeFromSamples(segment);
      if (env.isNotEmpty) {
        final bpm = _detectTempoFromOnsetEnvelope(
          env,
          sampleRate / 256.0,
        );
        if (bpm != null) return bpm;
      }
    }

    final wf = clip.normWaveformData;
    if (wf.length >= 64 && clip.audioDuration.inMilliseconds > 0) {
      final totalMs = clip.audioDuration.inMilliseconds.toDouble();
      final startIdx =
          ((clip.trimStart.inMilliseconds / totalMs) * wf.length).floor();
      final endIdx = ((clip.trimEnd.inMilliseconds / totalMs) * wf.length)
          .ceil()
          .clamp(0, wf.length);
      final s = startIdx.clamp(0, wf.length);
      final e = endIdx.clamp(s, wf.length);
      final subset = (e > s && (e - s) >= 64) ? wf.sublist(s, e) : wf;
      final envHz = wf.length / (totalMs / 1000.0);
      return _detectTempoFromOnsetEnvelope(subset, envHz);
    }

    return null;
  }

  Future<void> _setClipTempoFollowMode(
    int clipIndex, {
    required bool preservePitch,
  }) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;

    if (clip.sourceTempoBpm <= 0.0) {
      final detected = await _detectClipTempoBpm(clip);
      clip.sourceTempoBpm = detected ?? _tempo;
    }

    _setStateAndRefreshProjectSettings(() {
      _tempoStretchEnabled = true;
      clip.stretchToProjectTempo = true;
      clip.tempoStretchPreservePitch = preservePitch;
    });

    await _syncClipTimingToEngine(clipIndex);
    await _syncClipMixToEngine(clip);
    _updateOverallDurationIfNeeded();
    if (mounted) setState(() {});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preservePitch
              ? 'Clip now follows tempo and preserves pitch.'
              : 'Clip now follows tempo with resample mode.',
        ),
      ),
    );
  }

  Future<void> _handleDisableClipTempoFollow(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;
    if (!clip.stretchToProjectTempo) return;

    _setStateAndRefreshProjectSettings(() {
      clip.stretchToProjectTempo = false;
      final hasAudioTempoFollow = _audioTracks
          .where((t) => !t.isMidi)
          .any((t) => t.stretchToProjectTempo);
      if (!hasAudioTempoFollow) {
        _tempoStretchEnabled = false;
      }
    });

    await _syncClipTimingToEngine(clipIndex);
    await _syncClipMixToEngine(clip);
    _updateOverallDurationIfNeeded();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clip tempo mode turned off.')),
    );
  }

  Future<void> _handleStretchClipToTempoPreservePitch(int clipIndex) async {
    await _setClipTempoFollowMode(clipIndex, preservePitch: true);
  }

  Future<void> _handleAdjustClipToTempo(int clipIndex) async {
    await _setClipTempoFollowMode(clipIndex, preservePitch: false);
  }

  void _handleStretchClipResize(
    int clipIndex,
    double newTimelineDurationMs, {
    double? newStartMs,
  }) {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;

    final rawSec = _rawClipDurationSec(clip);
    if (rawSec <= 0.0) return;

    final targetTimelineSec =
        (newTimelineDurationMs / 1000.0).clamp(0.05, 36000.0);
    final projectTempo = _clampTempo(_tempo);
    final nextSourceTempo =
        ((targetTimelineSec * projectTempo) / rawSec).clamp(20.0, 999.0);

    if (!mounted) return;
    setState(() {
      _tempoStretchEnabled = true;
      clip.stretchToProjectTempo = true;
      clip.sourceTempoBpm = nextSourceTempo;
      if (newStartMs != null) {
        clip.offset = math.max(0.0, newStartMs / 1000.0);
      }
    });
    _updateOverallDurationIfNeeded();
  }

  Future<void> _handleStretchClipResizeCommit(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;

    await _syncClipTimingToEngine(clipIndex);
    await _syncClipMixToEngine(clip);
    _updateOverallDurationIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _handleDetectClipTempoAndSetProjectTempo(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detecting clip tempo...')),
      );
    }

    final detected = await _detectClipTempoBpm(clip);
    if (detected == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect clip tempo.')),
      );
      return;
    }

    final rounded = detected.round().clamp(40, 240);
    bool applyProjectTempo = false;

    if (mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A2233),
          title: const Text(
            'Change Project BPM?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Detected ${detected.toStringAsFixed(1)} BPM from this clip.\n'
            'Change project BPM from ${_formatTempoBpm(_tempo)} to $rounded?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change BPM'),
            ),
          ],
        ),
      );
      applyProjectTempo = confirmed == true;
    }

    _setStateAndRefreshProjectSettings(() {
      clip.sourceTempoBpm = detected;
      if (applyProjectTempo) {
        clip.stretchToProjectTempo = true;
        clip.tempoStretchPreservePitch = _tempoStretchPreservePitchDefault;
        _tempoStretchEnabled = true;
        _tempo = rounded.toDouble();
      }
    });

    if (applyProjectTempo) {
      await _queueTempoEngineSync();
    } else {
      await _syncClipTimingToEngine(clipIndex);
      await _syncClipMixToEngine(clip);
      _updateOverallDurationIfNeeded();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applyProjectTempo
              ? 'Detected ${detected.toStringAsFixed(1)} BPM. Project set to $rounded BPM.'
              : 'Detected ${detected.toStringAsFixed(1)} BPM. Project BPM unchanged.',
        ),
      ),
    );
  }

  void _clearCopiedClip() {
    if (_copiedClip == null &&
        (_copiedClipGroup == null || _copiedClipGroup!.isEmpty)) {
      return;
    }
    setState(() {
      _copiedClip = null;
      _copiedClipGroup = null;
      _copiedTrimStart = Duration.zero;
      _copiedTrimEnd = Duration.zero;
    });
  }

  void _handleCopyClip(int clipIndex) {
    _handleCopyClips(<int>[clipIndex]);
  }

  void _handleCopyClips(List<int> clipIndices) {
    final valid = clipIndices
        .where((i) => i >= 0 && i < _audioTracks.length)
        .toSet()
        .toList();
    if (valid.isEmpty) return;

    valid.sort((a, b) {
      final da = _audioTracks[a].offset;
      final db = _audioTracks[b].offset;
      final cmpOffset = da.compareTo(db);
      if (cmpOffset != 0) return cmpOffset;
      final cmpRow =
          _audioTracks[a].rowIndex.compareTo(_audioTracks[b].rowIndex);
      if (cmpRow != 0) return cmpRow;
      return a.compareTo(b);
    });

    final anchor = _audioTracks[valid.first];
    final anchorStartMs = anchor.offset * 1000.0;
    final anchorRow = anchor.rowIndex;
    final group = valid
        .map(
          (index) => _CopiedClipGroupEntry(
            clip: _audioTracks[index],
            trimStart: _audioTracks[index].trimStart,
            trimEnd: _audioTracks[index].trimEnd,
            offsetDeltaMs: _audioTracks[index].offset * 1000.0 - anchorStartMs,
            rowDelta: _audioTracks[index].rowIndex - anchorRow,
          ),
        )
        .toList(growable: false);

    setState(() {
      _copiedClip = anchor;
      _copiedTrimStart = anchor.trimStart;
      _copiedTrimEnd = anchor.trimEnd;
      _copiedClipGroup = group.length > 1 ? group : null;
    });
  }

  EditorUndoAction _buildPasteAction({
    required AudioTrack clip,
    required int row,
    required double timeMs,
    required Duration trimStart,
    required Duration trimEnd,
  }) {
    if (clip.isMidi) {
      return PasteMidiClipAction(
        pasteMidiClip: ({
          required AudioTrack clip,
          required int row,
          required double timeMs,
          Duration? trimStartRequested,
          Duration? trimEndRequested,
        }) =>
            _pasteMidiTrack(
          clip,
          row,
          timeMs,
          trimStartRequested: trimStartRequested,
          trimEndRequested: trimEndRequested,
        ),
        tracks: _audioTracks,
        clip: clip,
        row: row,
        timeMs: timeMs,
        trimStart: trimStart,
        trimEnd: trimEnd,
      );
    }

    return PasteAudioClipAction(
      pasteClip: ({
        required AudioTrack clip,
        required int row,
        required double timeMs,
        Duration? trimStartRequested,
        Duration? trimEndRequested,
      }) =>
          _pasteAudioTrack(
        clip,
        row,
        timeMs,
        trimStartRequested: trimStartRequested,
        trimEndRequested: trimEndRequested,
      ),
      tracks: _audioTracks,
      clip: clip,
      row: row,
      timeMs: timeMs,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );
  }

  DeleteClipAction _buildDeleteClipAction(AudioTrack clip) {
    return DeleteClipAction(
      tracks: _audioTracks,
      clip: clip,
      addTrack: ({
        required AudioTrack clip,
        required int row,
        required double timeMs,
        required Duration trimStartRequested,
        required Duration trimEndRequested,
      }) =>
          clip.isMidi
              ? _addMidiTrack(
                  instrumentId: clip.instrumentId,
                  instrumentName: clip.instrumentName,
                  instrumentParams:
                      Map<String, double>.from(clip.instrumentParams),
                  midiNotes: clip.midiNotes.map((n) => n.copy()).toList(),
                  row: row,
                  timeMs: timeMs,
                  trimStartRequested: trimStartRequested,
                  trimEndRequested: trimEndRequested,
                  renderedFile: clip.file,
                  label: clip.label,
                  gain: clip.gain,
                  pitchSemitones: clip.pitchSemitones,
                  sourceTempoBpm: clip.sourceTempoBpm,
                  stretchToProjectTempo: clip.stretchToProjectTempo,
                  tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
                  crossfade: clip.crossfade,
                  automation:
                      clip.volumeAutomation.map((p) => p.copy()).toList(),
                )
              : _addAudioTrackFromProjectFile(
                  projectAudioFile: clip.file,
                  label: clip.label,
                  row: row,
                  timeMs: timeMs,
                  trimStartRequested: trimStartRequested,
                  trimEndRequested: trimEndRequested,
                  gain: clip.gain,
                  pitchSemitones: clip.pitchSemitones,
                  sourceTempoBpm: clip.sourceTempoBpm,
                  stretchToProjectTempo: clip.stretchToProjectTempo,
                  tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
                  crossfade: clip.crossfade,
                  automation:
                      clip.volumeAutomation.map((p) => p.copy()).toList(),
                ),
      onChange: () {
        _updateOverallDurationIfNeeded();
      },
    );
  }

  Future<void> _handleDeleteClip(int clipIndex) async {
    await _handleDeleteClips(<int>[clipIndex]);
  }

  Future<void> _handleDeleteClips(List<int> clipIndices) async {
    final validDescending = clipIndices
        .where((i) => i >= 0 && i < _audioTracks.length)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (validDescending.isEmpty) return;

    final actions = <EditorUndoAction>[];
    bool deletedActiveMidi = false;
    for (final index in validDescending) {
      if (index < 0 || index >= _audioTracks.length) continue;
      final clip = _audioTracks[index];
      if (_activeMidiClipEngineId != null &&
          clip.engineClipId == _activeMidiClipEngineId) {
        deletedActiveMidi = true;
      }
      actions.add(_buildDeleteClipAction(clip));
    }
    if (actions.isEmpty) return;

    if (actions.length == 1) {
      await _undoManager.execute(actions.first);
    } else {
      await _undoManager.execute(CompoundUndoAction('Delete clips', actions));
    }

    if (deletedActiveMidi) {
      _closeMidiClipEditor();
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _handleCutClipAt(int clipIndex, double cutTimeMs) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    final startMs = clip.offset * 1000.0;
    final timelineDurationMs = _clipTimelineDurationMs(clip);
    final endMs = startMs + timelineDurationMs;
    if (timelineDurationMs <= 1.0) return;
    if (cutTimeMs <= startMs + 1.0 || cutTimeMs >= endMs - 1.0) return;

    final rawSpanMs = (clip.trimEnd - clip.trimStart).inMilliseconds.toDouble();
    if (rawSpanMs <= 1.0) return;
    final ratio = ((cutTimeMs - startMs) / timelineDurationMs).clamp(0.0, 1.0);
    final cutTrimMs =
        clip.trimStart.inMilliseconds.toDouble() + rawSpanMs * ratio;
    final leftTrimEnd = Duration(milliseconds: cutTrimMs.round());
    final minTrimGap = const Duration(milliseconds: 50);
    if ((leftTrimEnd - clip.trimStart) < minTrimGap) return;
    if ((clip.trimEnd - leftTrimEnd) < minTrimGap) return;

    final oldTrimStart = clip.trimStart;
    final oldTrimEnd = clip.trimEnd;
    final oldOffset = clip.offset;
    final trimLeftAction = TrimClipAction(
      tracks: _audioTracks,
      originalIndex: clipIndex,
      oldTrimStart: oldTrimStart,
      oldTrimEnd: oldTrimEnd,
      oldOffset: oldOffset,
      newTrimStart: oldTrimStart,
      newTrimEnd: leftTrimEnd,
      newOffset: null,
      onChange: () {
        unawaited(_syncClipTimingToEngine(clipIndex));
        _updateOverallDurationIfNeeded();
      },
    );
    final pasteRightAction = _buildPasteAction(
      clip: clip,
      row: clip.rowIndex,
      timeMs: cutTimeMs,
      trimStart: leftTrimEnd,
      trimEnd: oldTrimEnd,
    );
    await _undoManager.execute(
      CompoundUndoAction('Cut clip', <EditorUndoAction>[
        trimLeftAction,
        pasteRightAction,
      ]),
    );
  }

  Future<void> _handlePasteClipAt(int row, double timeMs) async {
    final group = _copiedClipGroup;
    if (group != null && group.isNotEmpty) {
      if (_audioTracks.length + group.length > kNumClips) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
        return;
      }
      final actions = <EditorUndoAction>[];
      for (final entry in group) {
        final targetRow = row + entry.rowDelta;
        final targetTime = timeMs + entry.offsetDeltaMs;
        actions.add(
          _buildPasteAction(
            clip: entry.clip,
            row: targetRow,
            timeMs: targetTime,
            trimStart: entry.trimStart,
            trimEnd: entry.trimEnd,
          ),
        );
      }
      if (actions.isNotEmpty) {
        await _undoManager.execute(
          CompoundUndoAction('Paste clips', actions),
        );
      }
      return;
    }

    if (_copiedClip == null) return;
    if (_audioTracks.length >= kNumClips) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Max number of audio clips reached ($kNumClips). Unable to add more clips.")));
      return;
    }

    await _undoManager.execute(
      _buildPasteAction(
        clip: _copiedClip!,
        row: row,
        timeMs: timeMs,
        trimStart: _copiedTrimStart,
        trimEnd: _copiedTrimEnd,
      ),
    );
  }

  int _clipIndexForEngineId(int engineClipId) {
    if (engineClipId < 0) return -1;
    return _audioTracks.indexWhere((t) => t.engineClipId == engineClipId);
  }

  void _openMidiClipEditor(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (!clip.isMidi) return;
    setState(() {
      _activeMidiClipEngineId = clip.engineClipId;
      _showPianoRoll = true;
    });
    unawaited(_primePianoPreviewCache(clip));
  }

  void _closeMidiClipEditor() {
    setState(() {
      _showPianoRoll = false;
      _pianoRollFullscreen = false;
      _activeMidiClipEngineId = null;
    });
  }

  String _pianoPreviewCacheKey(AudioTrack clip, int pitch, double velocity) {
    final sb = StringBuffer()
      ..write(clip.instrumentId)
      ..write('|')
      ..write(clip.instrumentName)
      ..write('|')
      ..write(pitch)
      ..write('|')
      ..write(velocity.toStringAsFixed(3))
      ..write('|tempo=')
      ..write(_tempo.toStringAsFixed(3));
    final keys = clip.instrumentParams.keys.toList()..sort();
    for (final key in keys) {
      sb
        ..write('|')
        ..write(key)
        ..write('=')
        ..write((clip.instrumentParams[key] ?? 0.0).toStringAsFixed(5));
    }
    return sb.toString();
  }

  Future<File> _pianoPreviewRenderFile(String cacheKey) async {
    final tempDir = await getTemporaryDirectory();
    final safeHash = cacheKey.hashCode.toUnsigned(32).toRadixString(16);
    return File(p.join(tempDir.path, 'mixroom_midi_preview_$safeHash.wav'));
  }

  Future<void> _primePianoPreviewCache(AudioTrack clip) async {
    final paramKeys = clip.instrumentParams.keys.toList()..sort();
    final paramSig = paramKeys
        .map(
            (k) => '$k=${(clip.instrumentParams[k] ?? 0.0).toStringAsFixed(4)}')
        .join('|');
    final instrumentSig =
        '${clip.instrumentId}|${clip.instrumentName}|t=${_tempo.toStringAsFixed(3)}|$paramSig';
    if (_pianoPreviewPrimedInstruments.contains(instrumentSig)) return;
    _pianoPreviewPrimedInstruments.add(instrumentSig);

    const primePitches = <int>[60, 64, 67];
    const primeVelocity = 0.875;
    for (final pitch in primePitches) {
      try {
        final cacheKey = _pianoPreviewCacheKey(clip, pitch, primeVelocity);
        final existing = _pianoPreviewRenderCache[cacheKey];
        if (existing != null && File(existing).existsSync()) continue;
        final outFile = await _pianoPreviewRenderFile(cacheKey);
        final previewNote = MidiNote(
          id: 'prime_${DateTime.now().microsecondsSinceEpoch}_$pitch',
          pitch: pitch,
          startBeat: 0.0,
          lengthBeats: 0.42,
          velocity: primeVelocity,
        );
        await _renderInstrumentClipToFile(
          outFile: outFile,
          instrumentId: clip.instrumentId,
          instrumentName: clip.instrumentName,
          notes: <MidiNote>[previewNote],
          params: Map<String, double>.from(clip.instrumentParams),
        );
        if (outFile.existsSync()) {
          _pianoPreviewRenderCache[cacheKey] = outFile.path;
        }
      } catch (_) {
        // Best effort only.
      }
    }
  }

  Future<void> _previewPianoRollNote(int pitch, double velocity) async {
    if (_activeMidiClipEngineId == null) return;
    final idx = _clipIndexForEngineId(_activeMidiClipEngineId!);
    if (idx < 0 || idx >= _audioTracks.length) return;
    final clip = _audioTracks[idx];
    if (!clip.isMidi) return;

    final token = ++_pianoPreviewToken;
    try {
      final safePitch = pitch.clamp(0, 127);
      final velocityBucket = (velocity.clamp(0.0, 1.0) * 24.0).round() / 24.0;
      final cacheKey = _pianoPreviewCacheKey(clip, safePitch, velocityBucket);
      var cachedPath = _pianoPreviewRenderCache[cacheKey];
      if (cachedPath == null || !File(cachedPath).existsSync()) {
        final outFile = await _pianoPreviewRenderFile(cacheKey);
        final previewNote = MidiNote(
          id: 'preview_${DateTime.now().microsecondsSinceEpoch}',
          pitch: safePitch,
          startBeat: 0.0,
          lengthBeats: 0.42,
          velocity: velocityBucket,
        );
        await _renderInstrumentClipToFile(
          outFile: outFile,
          instrumentId: clip.instrumentId,
          instrumentName: clip.instrumentName,
          notes: <MidiNote>[previewNote],
          params: Map<String, double>.from(clip.instrumentParams),
        );
        if (!outFile.existsSync()) return;
        _pianoPreviewRenderCache[cacheKey] = outFile.path;
        cachedPath = outFile.path;
        if (_pianoPreviewRenderCache.length > 48) {
          _pianoPreviewRenderCache.remove(_pianoPreviewRenderCache.keys.first);
        }
      }

      if (!mounted || token != _pianoPreviewToken) return;
      await _samplePreviewPlayer.stop();
      await _samplePreviewPlayer.setFilePath(cachedPath);
      await _samplePreviewPlayer.seek(Duration.zero);
      await _samplePreviewPlayer.play();
    } catch (_) {
      // Silent fail for preview taps.
    }
  }

  bool _midiNotesEqual(List<MidiNote> a, List<MidiNote> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.pitch != y.pitch) return false;
      if ((x.startBeat - y.startBeat).abs() > 0.00001) return false;
      if ((x.lengthBeats - y.lengthBeats).abs() > 0.00001) return false;
      if ((x.velocity - y.velocity).abs() > 0.00001) return false;
    }
    return true;
  }

  bool _doubleMapsEqual(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final v = b[e.key];
      if (v == null) return false;
      if ((e.value - v).abs() > 0.00001) return false;
    }
    return true;
  }

  Future<void> _commitMidiClipFromPianoRoll({
    required List<MidiNote> notes,
    required Map<String, double> instrumentParams,
    required String instrumentId,
    required String instrumentName,
  }) async {
    if (_activeMidiClipEngineId == null) return;
    final index = _clipIndexForEngineId(_activeMidiClipEngineId!);
    if (index < 0 || index >= _audioTracks.length) return;
    final clip = _audioTracks[index];
    if (!clip.isMidi) return;

    final oldNotes = clip.midiNotes.map((n) => n.copy()).toList();
    final newNotes = notes.map((n) => n.copy()).toList();
    final oldParams = Map<String, double>.from(clip.instrumentParams);
    final newParams = Map<String, double>.from(instrumentParams);
    final oldInstrumentId = clip.instrumentId;
    final oldInstrumentName = clip.instrumentName;

    final notesChanged = !_midiNotesEqual(oldNotes, newNotes);
    final paramsChanged = !_doubleMapsEqual(oldParams, newParams);
    final instrumentChanged =
        oldInstrumentId != instrumentId || oldInstrumentName != instrumentName;
    if (!notesChanged && !paramsChanged && !instrumentChanged) {
      return;
    }

    await _undoManager.execute(
      EditMidiClipAction(
        tracks: _audioTracks,
        originalIndex: index,
        oldNotes: oldNotes,
        newNotes: newNotes,
        oldInstrumentId: oldInstrumentId,
        oldInstrumentName: oldInstrumentName,
        oldInstrumentParams: oldParams,
        newInstrumentId: instrumentId,
        newInstrumentName: instrumentName,
        newInstrumentParams: newParams,
        applyToClip: (target, notesToApply, nextInstrumentId,
            nextInstrumentName, nextParams) async {
          target.midiNotes = notesToApply.map((n) => n.copy()).toList();
          target.instrumentId = nextInstrumentId;
          target.instrumentName = nextInstrumentName;
          target.instrumentParams = Map<String, double>.from(nextParams);
          target.sourceTempoBpm = _clampTempo(_tempo);
          target.stretchToProjectTempo = true;
          target.tempoStretchPreservePitch = true;
          final updatedLive = await _updateMidiClipEventsLive(target);
          if (updatedLive) {
            final clipIdx = _clipIndexForEngineId(target.engineClipId);
            if (clipIdx >= 0) {
              await _syncClipTimingToEngine(clipIdx);
            }
            await _syncClipMixToEngine(target);
            _queueMidiRenderCacheRefresh(target);
            _updateOverallDurationIfNeeded();
          } else {
            await _rerenderMidiTrack(target);
          }
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  Future<void> _recomputeAudibleState() async {
    final soloActive = _rowSoloed.any((s) => s);
    final futures = <Future<void>>[];

    for (int row = 0; row < _rowCount; row++) {
      bool shouldMute;

      if (soloActive) {
        // SOLO MODE: mute everything that is NOT soloed
        shouldMute = !_rowSoloed[row];
      } else {
        // NORMAL MODE: respect mute buttons
        shouldMute = _rowMuted[row];
      }

      if (row < _rowMuteApplied.length && _rowMuteApplied[row] == shouldMute) {
        continue;
      }
      if (row < _rowMuteApplied.length) {
        _rowMuteApplied[row] = shouldMute;
      }
      futures.add(JuceAudioEngine.muteRow(row, shouldMute));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<_RowLayoutSnapshot> _captureRowLayoutSnapshot() async {
    final rows = _rows
        .map((r) => TimelineRow(rowId: r.rowId, name: r.name, iconId: r.iconId))
        .toList();
    final clipRowIndices = _audioTracks.map((c) => c.rowIndex).toList();
    return _RowLayoutSnapshot(rows: rows, clipRowIndices: clipRowIndices);
  }

  Future<void> _applyRowLayoutSnapshot(_RowLayoutSnapshot snap) async {
    var targetCount = snap.rows.length;
    if (targetCount <= 0) targetCount = 1;

    final currentIds = _rows.map((r) => r.rowId).toList();

    while (currentIds.length < targetCount) {
      final next = currentIds.length + 1;
      final id = await JuceAudioEngine.addRow('Track $next', iconId: 0);
      if (id < 0) break;
      currentIds.add(id);
    }

    while (currentIds.length > targetCount && currentIds.length > 1) {
      final rowId = currentIds.removeLast();
      final ok = await JuceAudioEngine.removeRow(rowId);
      if (!ok) break;
    }

    // Reorder JUCE rows to match snapshot row identity (moves FX/meters with rows).
    final reorderCount = math.min(currentIds.length, snap.rows.length);
    for (int i = 0; i < reorderCount; i++) {
      final desiredId = snap.rows[i].rowId;
      final from = currentIds.indexOf(desiredId);
      if (from < 0 || from == i) continue;
      final ok = await JuceAudioEngine.moveRowOrder(from, i);
      if (!ok) continue;
      final moved = currentIds.removeAt(from);
      currentIds.insert(i, moved);
    }

    final applyCount = math.min(snap.rows.length, currentIds.length);
    for (int i = 0; i < applyCount; i++) {
      final rowId = currentIds[i];
      if (rowId < 0) continue;
      final row = snap.rows[i];
      await JuceAudioEngine.renameRow(rowId, row.name);
      await JuceAudioEngine.setRowIcon(rowId, row.iconId);
    }

    await _reloadRowsFromEngine();

    final clipCount = math.min(_audioTracks.length, snap.clipRowIndices.length);
    for (int i = 0; i < clipCount; i++) {
      final clip = _audioTracks[i];
      final bounded =
          _rowCount == 0 ? 0 : snap.clipRowIndices[i].clamp(0, _rowCount - 1);
      final targetRowId = _rowIdAt(bounded);
      final rowChanged = targetRowId >= 0 && clip.rowId != targetRowId;

      clip.rowIndex = bounded;
      if (targetRowId >= 0) {
        clip.rowId = targetRowId;
      }

      if (rowChanged && clip.engineClipId >= 0) {
        await JuceAudioEngine.moveClipToRow(clip.engineClipId, clip.rowId);
      }
    }

    // Keep local rowIndex aligned for clips not encoded in the snapshot.
    for (int i = clipCount; i < _audioTracks.length; i++) {
      final clip = _audioTracks[i];
      final idx = _rowIndexForId(clip.rowId);
      if (idx >= 0) {
        clip.rowIndex = idx;
      } else if (_rowCount == 0) {
        clip.rowIndex = 0;
      } else {
        clip.rowId = _rowIdAt(0);
        clip.rowIndex = 0;
      }
    }

    await _recomputeAudibleState();
    _updateOverallDurationIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _runRowLayoutActionWithUndo({
    required String description,
    required Future<bool> Function() perform,
  }) async {
    final before = await _captureRowLayoutSnapshot();
    final changed = await perform();
    if (!changed) return;
    final after = await _captureRowLayoutSnapshot();
    await _undoManager.addWithoutExecute(_RowLayoutSnapshotAction(
      descriptionText: description,
      before: before,
      after: after,
      applySnapshot: _applyRowLayoutSnapshot,
    ));
  }

  Future<bool> _addRowImpl() async {
    final nextIndex = _rowCount + 1;
    final rowId = await JuceAudioEngine.addRow('Track $nextIndex', iconId: 0);
    if (rowId >= 0) {
      await _reloadRowsFromEngine();
      if (_rowSoloed.any((s) => s)) {
        final idx = _rowIndexForId(rowId);
        if (idx >= 0) {
          _rowMuteApplied[idx] = true;
          await JuceAudioEngine.muteRow(idx, true);
        }
      }
      return true;
    }
    return false;
  }

  Future<void> _addRow() async {
    if (_rowCount >= kMaxRows) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Maximum of ${kMaxRows} rows reached.')),
        );
      }
      return;
    }
    await _runRowLayoutActionWithUndo(
      description: 'Add row',
      perform: _addRowImpl,
    );
  }

  Future<bool> _insertRowAboveImpl(int row) async {
    if (row < 0 || row >= _rowCount) return false;
    final refRowId = _rowIdAt(row);
    final rowId = await JuceAudioEngine.insertRowAbove(
        refRowId, 'Track ${_rowCount + 1}',
        iconId: 0);
    if (rowId < 0) return false;
    await _reloadRowsFromEngine();
    for (final clip in _audioTracks) {
      final idx = _rowIndexForId(clip.rowId);
      if (idx >= 0) clip.rowIndex = idx;
    }
    if (_rowSoloed.any((s) => s)) {
      final idx = _rowIndexForId(rowId);
      if (idx >= 0) {
        _rowMuteApplied[idx] = true;
        await JuceAudioEngine.muteRow(idx, true);
      }
    }
    setState(() {});
    return true;
  }

  Future<void> _insertRowAbove(int row) async {
    if (_rowCount >= kMaxRows) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Maximum of ${kMaxRows} rows reached.')),
        );
      }
      return;
    }
    await _runRowLayoutActionWithUndo(
      description: 'Insert row above',
      perform: () => _insertRowAboveImpl(row),
    );
  }

  Future<bool> _insertRowBelowImpl(int row) async {
    if (row < 0 || row >= _rowCount) return false;
    final refRowId = _rowIdAt(row);
    final rowId = await JuceAudioEngine.insertRowBelow(
        refRowId, 'Track ${_rowCount + 1}',
        iconId: 0);
    if (rowId < 0) return false;
    await _reloadRowsFromEngine();
    for (final clip in _audioTracks) {
      final idx = _rowIndexForId(clip.rowId);
      if (idx >= 0) clip.rowIndex = idx;
    }
    if (_rowSoloed.any((s) => s)) {
      final idx = _rowIndexForId(rowId);
      if (idx >= 0) {
        _rowMuteApplied[idx] = true;
        await JuceAudioEngine.muteRow(idx, true);
      }
    }
    setState(() {});
    return true;
  }

  Future<void> _insertRowBelow(int row) async {
    if (_rowCount >= kMaxRows) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Maximum of ${kMaxRows} rows reached.')),
        );
      }
      return;
    }
    await _runRowLayoutActionWithUndo(
      description: 'Insert row below',
      perform: () => _insertRowBelowImpl(row),
    );
  }

  void _showSmallNotice(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearRowContent(int row) async {
    if (row < 0 || row >= _rowCount) return;
    final rowId = _rowIdAt(row);

    // Remove clips on this row (descending so indices stay valid for removal).
    for (int i = _audioTracks.length - 1; i >= 0; i--) {
      final clip = _audioTracks[i];
      final matchesRowId = rowId >= 0 && clip.rowId == rowId;
      final matchesRowIndex = clip.rowIndex == row;
      if (matchesRowId || matchesRowIndex) {
        clip.audioStartTimer?.cancel();
        _audioTracks.removeAt(i);
        if (clip.engineClipId >= 0) {
          await JuceAudioEngine.removeTrack(clip.engineClipId);
        }
      }
    }

    // Clear row FX chain.
    final fx = await JuceAudioEngine.getTrackEffectsForRow(row);
    for (int i = fx.length - 1; i >= 0; i--) {
      await JuceAudioEngine.removeTrackEffect(row, i);
    }

    // Reset row controls.
    _rowMuted[row] = false;
    _rowSoloed[row] = false;
    _rowGain[row] = 1.0;
    _rowPan[row] = 0.5;
    _rowVolumeAutomation[row] = [AutomationPoint(x: 0.0, volume: 0.75)];

    await JuceAudioEngine.setRowGain(row, 1.0);
    await JuceAudioEngine.setRowPan(row, 0.5);
    await JuceAudioEngine.setTrackAutomationPoints(
      row,
      _toMaps(_rowVolumeAutomation[row]),
    );
    await _recomputeAudibleState();
    _updateOverallDurationIfNeeded();
  }

  Future<bool> _deleteRowImpl(int row) async {
    if (row < 0 || row >= _rowCount) return false;
    if (_rowCount == 1) {
      await _clearRowContent(row);
      final rowId = _rowIdAt(row);
      if (rowId >= 0) {
        await JuceAudioEngine.renameRow(rowId, 'Track 1');
        await JuceAudioEngine.setRowIcon(rowId, 0);
        await _reloadRowsFromEngine();
        await _recomputeAudibleState();
      }
      setState(() {});
      return true;
    }
    final deletingRowId = _rowIdAt(row);
    if (deletingRowId < 0) return false;

    // Delete clips that belong to the removed row.
    for (int i = _audioTracks.length - 1; i >= 0; i--) {
      final clip = _audioTracks[i];
      if (clip.rowId != deletingRowId) continue;
      clip.audioStartTimer?.cancel();
      _audioTracks.removeAt(i);
      if (clip.engineClipId >= 0) {
        await JuceAudioEngine.removeTrack(clip.engineClipId);
      }
    }

    final ok = await JuceAudioEngine.removeRow(deletingRowId);
    if (!ok) return false;

    await _reloadRowsFromEngine();
    for (final clip in _audioTracks) {
      final idx = _rowIndexForId(clip.rowId);
      if (idx >= 0) {
        clip.rowIndex = idx;
      } else if (_rowCount == 0) {
        clip.rowIndex = 0;
      } else {
        clip.rowId = _rowIdAt(0);
        clip.rowIndex = 0;
      }
    }
    await _recomputeAudibleState();
    _updateOverallDurationIfNeeded();
    setState(() {});
    return true;
  }

  Future<void> _deleteRow(int row) async {
    // Row delete now removes clips on that row. The row-layout snapshot undo
    // path does not capture full clip payloads, so avoid recording a partial undo.
    await _deleteRowImpl(row);
  }

  Future<bool> _renameRowImpl(int row, String name) async {
    if (row < 0 || row >= _rowCount) return false;
    final ok = await JuceAudioEngine.renameRow(_rowIdAt(row), name);
    if (ok) {
      await _reloadRowsFromEngine();
      return true;
    }
    return false;
  }

  Future<void> _renameRow(int row, String name) async {
    await _runRowLayoutActionWithUndo(
      description: 'Rename row',
      perform: () => _renameRowImpl(row, name),
    );
  }

  Future<bool> _setRowIconImpl(int row, int iconId) async {
    if (row < 0 || row >= _rowCount) return false;
    final ok = await JuceAudioEngine.setRowIcon(_rowIdAt(row), iconId);
    if (ok) {
      await _reloadRowsFromEngine();
      return true;
    }
    return false;
  }

  Future<void> _setRowIcon(int row, int iconId) async {
    await _runRowLayoutActionWithUndo(
      description: 'Change row icon',
      perform: () => _setRowIconImpl(row, iconId),
    );
  }

  Future<bool> _moveRowImpl(int fromIndex, int toIndex) async {
    if (fromIndex < 0 ||
        fromIndex >= _rowCount ||
        toIndex < 0 ||
        toIndex >= _rowCount) return false;
    final ok = await JuceAudioEngine.moveRowOrder(fromIndex, toIndex);
    if (!ok) return false;
    await _reloadRowsFromEngine();
    for (final clip in _audioTracks) {
      final idx = _rowIndexForId(clip.rowId);
      if (idx >= 0) clip.rowIndex = idx;
    }
    setState(() {});
    return true;
  }

  Future<void> _moveRow(int fromIndex, int toIndex) async {
    await _runRowLayoutActionWithUndo(
      description: 'Move row',
      perform: () => _moveRowImpl(fromIndex, toIndex),
    );
  }

  void _updateOverallDurationIfNeeded() {
    Duration newDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      newDuration = _audioTracks.map((track) {
        final offsetDuration =
            Duration(milliseconds: (track.offset * 1000).round());
        final trackDuration =
            Duration(milliseconds: _clipTimelineDurationMs(track).round());
        return offsetDuration + trackDuration;
      }).reduce((a, b) => a > b ? a : b);
    }
    if (newDuration != _audioOnlyOverallDuration) {
      setState(() {
        _audioOnlyOverallDuration = newDuration;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Main app UI (Scaffold)
            Scaffold(
              extendBody: false,
              resizeToAvoidBottomInset: false,
              body: SafeArea(
                bottom: false,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setLocalState) {
                    _audioEditorStateSetter = setLocalState;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          children: [
                            // TOP ROW OF BUTTONS
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: ValueListenableBuilder<Duration>(
                                  valueListenable: _transportClock,
                                  builder: (_, clock, __) =>
                                      _buildTopBar(clock),
                                )),

                            Flexible(
                              fit: FlexFit.loose,
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _transportClock,
                                builder: (_, clock, __) => AudioCanvasTimeline(
                                  rows: _rows,
                                  clips: _audioTracks, // your list
                                  rowGain: _rowGain,
                                  rowPan: _rowPan,
                                  rowVolumeAutomation: _rowVolumeAutomation,
                                  // extractors
                                  getStartMs: (t) =>
                                      t.offset * 1000.0, // adjust to your model
                                  getDurationMs: (t) =>
                                      _clipTimelineDurationMs(t),
                                  getTimelineDurationMs: (t) =>
                                      _clipTimelineDurationMs(t),
                                  getTrimStartMs: (t) =>
                                      t.trimStart.inMilliseconds.toDouble(),
                                  getTrimEndMs: (t) =>
                                      t.trimEnd.inMilliseconds.toDouble(),
                                  // getRowIndex: (t) => (t.rowIndex >= 0 && t.rowIndex < kNumRows) ? t.rowIndex : 0,
                                  getPeaks: (c) {
                                    return c.normWaveformData;
                                  },
                                  getY: (c) =>
                                      c.y, // store a visual Y in your model
                                  // commit (persist in your model, then setState)
                                  onMoveClipCommit:
                                      (i, newStartMs, newRowIndex) async {
                                    if (newRowIndex < 0 ||
                                        newRowIndex >= _rowCount) return;
                                    final clip = _audioTracks[i];
                                    // clip.offset = newStartMs / 1000.0;
                                    // clip.rowIndex = newRowIndex; // <-- move across rows
                                    // setState(() {});
                                    // JuceAudioEngine.moveClipToRow(i, newRowIndex);
                                    // _updateOverallDurationIfNeeded();
                                    await _undoManager.execute(
                                      MoveClipAction(
                                        tracks: _audioTracks,
                                        // clip: clip,
                                        originalIndex: i,
                                        oldOffset: clip.offset,
                                        oldRow: clip.rowIndex,
                                        newOffset: newStartMs / 1000.0,
                                        newRow: newRowIndex,
                                        onChange: () {
                                          clip.rowId = _rowIdAt(clip.rowIndex);
                                          _syncClipTimingToEngine(i);
                                          _updateOverallDurationIfNeeded();
                                        },
                                      ),
                                    );
                                    setState(() {});
                                  },
                                  onTrimClip: (i, s, e,
                                      {double? newStartMs}) async {
                                    final clip = _audioTracks[i];

                                    // 1. Update the internal trim values (where in the source file we start/end)
                                    clip.trimStart =
                                        Duration(milliseconds: s.round());
                                    clip.trimEnd =
                                        Duration(milliseconds: e.round());

                                    // 2. === FIX: Use the calculated newStartMs for the timeline offset ===
                                    // newStartMs is ONLY sent by the timeline widget during a 'trim-start' operation.
                                    if (newStartMs != null) {
                                      // newStartMs is the intended start time in milliseconds.
                                      // Convert to seconds (assuming clip.offset is in seconds).
                                      clip.offset = newStartMs / 1000.0;
                                    }
                                    // If newStartMs is null (during 'trim-end'), the clip.offset must not change.
                                    // await _undoManager.execute(
                                    //   TrimClipAction(
                                    //     clip: clip,
                                    //     oldTrimStart: clip.trimStart,
                                    //     oldTrimEnd: clip.trimEnd,
                                    //     oldOffset: clip.offset,
                                    //     newTrimStart: Duration(milliseconds: s.round()),
                                    //     newTrimEnd: Duration(milliseconds: e.round()),
                                    //     newOffset: newStartMs != null ? newStartMs / 1000.0 : null,
                                    //     onChange: _updateOverallDurationIfNeeded,
                                    //   ),
                                    // );
                                    setState(() {});
                                    _updateOverallDurationIfNeeded();
                                    // Defer JUCE update until trim commit (pointer-up) to avoid UI lag.
                                  },

                                  // for the undo history
                                  onTrimClipCommit: (i, s, e, os, oe, oo,
                                      {double? newStartMs}) async {
                                    // final clip = _audioTracks[i];
                                    await _undoManager.execute(
                                      TrimClipAction(
                                        // clip: clip,
                                        tracks: _audioTracks,
                                        originalIndex: i,
                                        oldTrimStart:
                                            Duration(milliseconds: os.round()),
                                        oldTrimEnd:
                                            Duration(milliseconds: oe.round()),
                                        oldOffset: oo / 1000.0,
                                        newTrimStart:
                                            Duration(milliseconds: s.round()),
                                        newTrimEnd:
                                            Duration(milliseconds: e.round()),
                                        newOffset: newStartMs != null
                                            ? newStartMs / 1000.0
                                            : null,
                                        onChange: () {
                                          _syncClipTimingToEngine(i);
                                          _updateOverallDurationIfNeeded();
                                        },
                                      ),
                                    );
                                  },

                                  // selection + headers
                                  // numRows: kNumRows,
                                  // selectedRowIndex: _selectedRow,
                                  onSelectRow: (row) =>
                                      setState(() => _selectedRow = row),
                                  // rowMuted: _rowMuted,
                                  // rowExpanded: _rowExpanded,
                                  recordingInProgress: _isRecording,
                                  onToggleExpanded: (row) => setState(() =>
                                      _rowExpanded[row] = !_rowExpanded[row]),
                                  onAddRow: _addRow,
                                  onInsertRowAbove: _insertRowAbove,
                                  onInsertRowBelow: _insertRowBelow,
                                  onDeleteRow: _deleteRow,
                                  onMoveRow: _moveRow,
                                  onRenameRow: _renameRow,
                                  onSetRowIcon: _setRowIcon,

                                  // transport
                                  playheadMs: clock.inMilliseconds
                                      .toDouble(), // your existing clock
                                  // isPlaying: _isPlaying,
                                  onScrubRequested: (ms) {
                                    if (_isRecording) {
                                      return; // do nothing while recording (hopefully no bug where you can still physically scrub but does nothing here)
                                    }

                                    final newPosition =
                                        Duration(milliseconds: ms.toInt());
                                    _syncTransportClock(
                                      newPosition,
                                      playing: _isPlaying,
                                    );
                                    // for (int i = 0; i < _audioTracks.length; i++) {
                                    //   final track = _audioTracks[i];
                                    //   final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);
                                    //   JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
                                    //   setState(() {
                                    //     track.currentPosition = effectivePos;
                                    //   });
                                    // }
                                    JuceAudioEngine.setTransportSeconds(
                                        ms / 1000.0);
                                    JuceAudioEngine.setMetronomeTransportMs(ms);
                                  },
                                  maxDuration: _audioOnlyOverallDuration,
                                  getFullDurationMs: (t) =>
                                      _clipFullDurationMsForTrim(t),
                                  isPlaying: _isPlaying,

                                  // ruler/grid
                                  bpm: _tempo,
                                  beatsPerBar: 4,

                                  // layout
                                  // numRows: kNumRows,
                                  height:
                                      520, // THIS VALUE is effectively unused, the height is just natural now
                                  // ============================
                                  // NEW: Row FX callbacks
                                  // ============================
                                  getRowEffects: (row) =>
                                      JuceAudioEngine.getTrackEffectsForRow(
                                          row),
                                  getRowEffectIds: (row) =>
                                      JuceAudioEngine.getTrackEffectIdsForRow(
                                          row),

                                  getRowEffectBypassState: (row, effectIndex) =>
                                      JuceAudioEngine.getRowEffectBypassState(
                                          row, effectIndex),

                                  insertRowEffect: (row, pathOrName) async {
                                    final before = await JuceAudioEngine
                                        .getTrackEffectsForRow(row);
                                    await _undoManager.execute(
                                      InsertEffectAction(
                                        row: row,
                                        pathOrName: pathOrName,
                                        onChange: () {
                                          setState(() {});
                                          _refreshRowFx(row);
                                        },
                                      ),
                                    );
                                    final after = await JuceAudioEngine
                                        .getTrackEffectsForRow(row);
                                    if (after.length <= before.length) {
                                      _showSmallNotice(
                                          'Could not load this effect plugin.');
                                      return;
                                    }
                                    _recordProducerManualEdit('row_fx_insert',
                                        {'row': row, 'effect': pathOrName});
                                  }, //=> JuceAudioEngine.insertTrackEffect(row, pathOrName),
                                  // need name of effects so undo action can add it back later
                                  removeRowEffect: (row, effectIndex, name,
                                      applyingPreset) async {
                                    if (applyingPreset) {
                                      await JuceAudioEngine.removeTrackEffect(
                                          row, effectIndex);
                                      return;
                                    }
                                    await _undoManager.execute(
                                      RemoveEffectAction(
                                        row: row,
                                        effectIndex: effectIndex,
                                        pathOrName: name,
                                        onChange: () {
                                          setState(() {});
                                          _refreshRowFx(row);
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_fx_remove', {
                                      'row': row,
                                      'index': effectIndex,
                                      'effect': name,
                                    });
                                  }, //=> JuceAudioEngine.removeTrackEffect(row, effectIndex),

                                  reorderRowEffects: (row, from, to) async {
                                    await _undoManager.execute(
                                      ReorderEffectAction(
                                        row: row,
                                        from: from,
                                        to: to,
                                        onChange: () {
                                          setState(() {});
                                          _refreshRowFx(row);
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_fx_reorder',
                                        {'row': row, 'from': from, 'to': to});
                                  }, //JuceAudioEngine.reorderTrackEffects(row, from, to),

                                  setRowEffectBypassed:
                                      (row, effectIndex, bypass) async {
                                    await _undoManager.execute(
                                      BypassEffectAction(
                                        row: row,
                                        effectIndex: effectIndex,
                                        oldState: !bypass,
                                        newState: bypass,
                                        onChange: () {
                                          setState(() {});
                                          _refreshRowFx(row);
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_fx_bypass', {
                                      'row': row,
                                      'index': effectIndex,
                                      'bypassed': bypass,
                                    });
                                  }, //=> JuceAudioEngine.bypassRowEffect(row, effectIndex, bypass),

                                  getRowPluginParameters: (row, effectIndex) =>
                                      JuceAudioEngine.getTrackPluginParameters(
                                          row, effectIndex),

                                  setRowEffectParam:
                                      (row, effectIndex, paramId, value) =>
                                          JuceAudioEngine.setTrackEffect(
                                              row, effectIndex, paramId, value),

                                  // for commiting to undo history
                                  onPluginParamCommit: (row, idx, paramId,
                                      oldValue, newValue) async {
                                    await _undoManager.execute(
                                      SetEffectParamAction(
                                        row: row,
                                        effectIndex: idx,
                                        paramId: paramId,
                                        oldValue: oldValue,
                                        newValue: newValue,
                                        onChange: () {
                                          setState(() {});
                                          _refreshRowFx(row);
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_fx_param', {
                                      'row': row,
                                      'index': idx,
                                      'param_id': paramId,
                                      'old_value': oldValue,
                                      'new_value': newValue,
                                    });
                                  },

                                  onPresetCommit: (before, after) async {
                                    await _undoManager.execute(
                                      TrackPresetChangeAction(
                                        before: before,
                                        after: after,
                                        onChange: () => setState(() {}),
                                      ),
                                    );
                                    _recordProducerManualEdit(
                                        'row_preset_commit', {
                                      'row': before.row,
                                      'before_count': before.effects.length,
                                      'after_count': after.effects.length,
                                    });
                                  },

                                  scanPlugins: () =>
                                      JuceAudioEngine.scanPlugins(),

                                  setTrackAutomationPoints: (row, points) =>
                                      JuceAudioEngine.setTrackAutomationPoints(
                                          row, points),

                                  onAutomationCommit:
                                      (row, oldPoints, newPoints) {
                                    _undoManager.execute(
                                      SetAutomationPointsAction(
                                        row: row,
                                        oldPoints: oldPoints,
                                        newPoints: newPoints,
                                        applyToState: (r, points) {
                                          setState(() {
                                            _rowVolumeAutomation[r] = points
                                                .map((p) => AutomationPoint(
                                                    x: p.x, volume: p.volume))
                                                .toList();
                                          });
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit(
                                        'row_automation', {
                                      'row': row,
                                      'old_count': oldPoints.length,
                                      'new_count': newPoints.length,
                                    });
                                  },

                                  setRowGain: (row, gain0to3) =>
                                      JuceAudioEngine.setRowGain(row, gain0to3),
                                  onRowGainCommit: (row, oldGain, newGain) {
                                    _undoManager.execute(
                                      SetRowGainAction(
                                        row: row,
                                        oldGain: oldGain,
                                        newGain: newGain,
                                        applyToState: (r, g) {
                                          setState(() {
                                            _rowGain[r] = g;
                                          });
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_gain', {
                                      'row': row,
                                      'old_gain': oldGain,
                                      'new_gain': newGain,
                                    });
                                  },

                                  muteRow: (row, mute) async {
                                    // await JuceAudioEngine.muteRow(row, mute);
                                    setState(() => _rowMuted[row] = mute);
                                    await _recomputeAudibleState(); // this handles all mute/solo logic

                                    // mute not counted in the undo history
                                    // await _undoManager.execute(
                                    //   MuteRowAction(row, !mute, mute, () => setState(() => _rowMuted[row] = mute)),
                                    // );
                                  },

                                  // isRowMuted: (row) => JuceAudioEngine.isRowMuted(row),
                                  rowMuted: _rowMuted,

                                  soloRow: (row, solo) async {
                                    // await JuceAudioEngine.muteRow(row, mute);
                                    setState(() => _rowSoloed[row] = solo);
                                    await _recomputeAudibleState(); // this handles all mute/solo logic
                                  },

                                  // isRowMuted: (row) => JuceAudioEngine.isRowMuted(row),
                                  rowSoloed: _rowSoloed,

                                  setRowPan: (row, newPan) =>
                                      JuceAudioEngine.setRowPan(row, newPan),
                                  onRowPanCommit: (row, oldPan, newPan) {
                                    _undoManager.execute(
                                      SetRowPanAction(
                                        row: row,
                                        oldPan: oldPan,
                                        newPan: newPan,
                                        applyToState: (r, p) {
                                          setState(() {
                                            _rowPan[r] = p;
                                          });
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('row_pan', {
                                      'row': row,
                                      'old_pan': oldPan,
                                      'new_pan': newPan,
                                    });
                                  },

                                  setClipGain: _setClipGainLive,
                                  onClipGainCommit:
                                      (clipIndex, oldGain, newGain) {
                                    _undoManager.execute(
                                      SetClipGainAction(
                                        tracks: _audioTracks,
                                        originalIndex: clipIndex,
                                        oldGain: oldGain,
                                        newGain: newGain,
                                        applyToState: (clip, gain) {
                                          clip.gain = gain;
                                          setState(() {});
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('clip_gain', {
                                      'clip': clipIndex,
                                      'old_gain': oldGain,
                                      'new_gain': newGain,
                                    });
                                  },
                                  setClipPitch: _setClipPitchLive,
                                  onClipPitchCommit:
                                      (clipIndex, oldPitch, newPitch) {
                                    _undoManager.execute(
                                      SetClipPitchAction(
                                        tracks: _audioTracks,
                                        originalIndex: clipIndex,
                                        oldPitch: oldPitch,
                                        newPitch: newPitch,
                                        applyToState: (clip, pitch) {
                                          clip.pitchSemitones = pitch;
                                          setState(() {});
                                        },
                                      ),
                                    );
                                    _recordProducerManualEdit('clip_pitch', {
                                      'clip': clipIndex,
                                      'old_pitch': oldPitch,
                                      'new_pitch': newPitch,
                                    });
                                  },
                                  onAdjustClipToTempo: _handleAdjustClipToTempo,
                                  onStretchClipToTempoPreservePitch:
                                      _handleStretchClipToTempoPreservePitch,
                                  onDisableClipTempoFollow:
                                      _handleDisableClipTempoFollow,
                                  onDetectClipTempoAndSetProjectTempo:
                                      _handleDetectClipTempoAndSetProjectTempo,
                                  onStretchClip: _handleStretchClipResize,
                                  onStretchClipCommit:
                                      _handleStretchClipResizeCommit,
                                  onRenameClip: (clipIndex, newLabel) async {
                                    if (clipIndex < 0 ||
                                        clipIndex >= _audioTracks.length) {
                                      return;
                                    }
                                    final oldLabel =
                                        _audioTracks[clipIndex].label;
                                    final nextLabel = newLabel.trim();
                                    if (nextLabel.isEmpty ||
                                        oldLabel == nextLabel) {
                                      return;
                                    }

                                    await _undoManager.execute(
                                      SetClipLabelAction(
                                        tracks: _audioTracks,
                                        originalIndex: clipIndex,
                                        oldLabel: oldLabel,
                                        newLabel: nextLabel,
                                        applyToState: (clip, label) {
                                          clip.label = label;
                                          setState(() {});
                                        },
                                      ),
                                    );

                                    _recordProducerManualEdit('clip_rename', {
                                      'clip': clipIndex,
                                      'old_label': oldLabel,
                                      'new_label': nextLabel,
                                    });
                                  },

                                  onCopyClip: _handleCopyClip,
                                  onDeleteClip: _handleDeleteClip,
                                  onCopyClips: _handleCopyClips,
                                  onDeleteClips: _handleDeleteClips,
                                  onCutClipAt: _handleCutClipAt,
                                  hasCopiedClip: _copiedClip != null ||
                                      (_copiedClipGroup?.isNotEmpty ?? false),
                                  onPasteClipAt: _handlePasteClipAt,
                                  onClearCopiedClip: _clearCopiedClip,
                                  onOpenMidiClip: _openMidiClipEditor,
                                  onSnapSettingsChanged:
                                      (magnetEnabled, quantizeDivisionsPerBar) {
                                    if (_timelineMagnetEnabled ==
                                            magnetEnabled &&
                                        _timelineQuantizeDivisionsPerBar ==
                                            quantizeDivisionsPerBar) {
                                      return;
                                    }
                                    setState(() {
                                      _timelineMagnetEnabled = magnetEnabled;
                                      _timelineQuantizeDivisionsPerBar =
                                          quantizeDivisionsPerBar;
                                    });
                                  },
                                  onLoopToggle: (enabled) {
                                    setState(() => _loopEnabled = enabled);
                                  },

                                  onLoopRegionChanged: (start, end) {
                                    setState(() {
                                      _loopStartMs = start;
                                      _loopEndMs = end;
                                    });
                                  },
                                  isRecording: _isRecording,
                                  recordingRowIndex: _selectedRow,
                                  recordingStartMs: _recordingStartMs,
                                  recordingPeaks:
                                      _recordingPeaks, // TODO: FIX TO USE WITH JUCE
                                  registerRowFxRefresher: (fn) {
                                    _refreshRowFx = fn;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      for (int row = 0;
                                          row < _rowCount;
                                          row++) {
                                        _refreshRowFx(row);
                                      }
                                    });
                                  },
                                  meters: _meters,
                                  getRowCompressorMeter: (row, fx) =>
                                      JuceAudioEngine.getRowCompressorMeter(
                                          row, fx),
                                  getRowEqWaveform: (row, fx, sampleCount) =>
                                      JuceAudioEngine.getRowEqWaveform(row, fx,
                                          sampleCount: sampleCount),
                                  onExternalSampleDrop:
                                      (data, row, timeMs) async {
                                    await _insertAudioFileAtTimeline(
                                      data.filePath,
                                      row: row,
                                      timeMs: timeMs,
                                    );
                                  },
                                  onExternalSampleDragEntered: () {
                                    _handleSampleDragExitedBrowserPanel();
                                  },
                                  externalSampleDragActive: _sampleDragActive,

                                  mode: widget.mode, // or "Basic"/"Pro" etc
                                ),
                              ),
                            ),
                          ],
                        ),
                        Builder(
                          builder: (overlayContext) {
                            final keyboardInset =
                                MediaQuery.viewInsetsOf(overlayContext).bottom;
                            final chatTypingActive = _chatFocusNode.hasFocus;
                            final chatLift = math.max(
                              0.0,
                              chatTypingActive
                                  ? keyboardInset - _kTransportBarHeight
                                  : 0.0,
                            );
                            final mediaSize = MediaQuery.sizeOf(overlayContext);
                            final samplePanelBottom = chatLift +
                                _kChatBarStackHeight +
                                (_showProducerCaptureUi
                                    ? _kProducerBannerHeightEstimate
                                    : 0.0) +
                                _kSamplePanelBottomGap;
                            final collapsedTop = math.max(
                              _kSamplePanelExpandedTop + 24.0,
                              mediaSize.height *
                                  _kSamplePanelCollapsedTopFactor,
                            );
                            final maxPanelTop = math.max(
                              _kSamplePanelExpandedTop,
                              mediaSize.height - samplePanelBottom - 120.0,
                            );
                            final desiredPanelTop = _sampleBrowserExpanded
                                ? _kSamplePanelExpandedTop
                                : collapsedTop;
                            final samplePanelTop = desiredPanelTop
                                .clamp(_kSamplePanelExpandedTop, maxPanelTop)
                                .toDouble();
                            final addActionsBottom = chatLift + 54.0;
                            final addActionsRight = 10.0;
                            final addActionsWidth = math.min(
                                _kAddActionsPanelWidth, mediaSize.width - 20.0);
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (_showAddActionsPanel)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _closeAddActionsPanel,
                                      child: const SizedBox.shrink(),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: chatLift,
                                  child: _buildBottomChatAndTransport(
                                    includeChatBar: true,
                                    includeProducerCapture:
                                        _showProducerCaptureUi,
                                    includeTransport: false,
                                  ),
                                ),
                                Positioned(
                                  right: addActionsRight,
                                  bottom: addActionsBottom,
                                  child: IgnorePointer(
                                    ignoring: !_showAddActionsPanel,
                                    child: TweenAnimationBuilder<double>(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      curve: _showAddActionsPanel
                                          ? Curves.easeOutCubic
                                          : Curves.easeInCubic,
                                      tween: Tween<double>(
                                        begin: 0.0,
                                        end: _showAddActionsPanel ? 1.0 : 0.0,
                                      ),
                                      builder: (context, t, child) {
                                        final clampedT = t.clamp(0.0, 1.0);
                                        return Transform.translate(
                                          offset:
                                              Offset(0, (1 - clampedT) * 22),
                                          child: Opacity(
                                            opacity: clampedT,
                                            child: ClipRect(
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomRight,
                                                heightFactor:
                                                    math.max(0.0001, clampedT),
                                                child: child,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: addActionsWidth,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1D2435),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border:
                                              Border.all(color: Colors.white12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.28),
                                              blurRadius: 24,
                                              offset: const Offset(0, -8),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildAddActionTile(
                                              id: 'audio',
                                              icon: Icons.audiotrack,
                                              title: L10n.translate(
                                                  context, 'Add Audio Clip'),
                                              onTap: () {
                                                unawaited(
                                                    _handleAddActionSelection(
                                                        'audio'));
                                              },
                                            ),
                                            _buildAddActionTile(
                                              id: 'instrument',
                                              icon: Icons.piano,
                                              title: L10n.translate(context,
                                                  'Add Instrument Clip'),
                                              onTap: () {
                                                unawaited(
                                                    _handleAddActionSelection(
                                                        'instrument'));
                                              },
                                            ),
                                            _buildAddActionTile(
                                              id: 'sample_browser',
                                              icon: Icons.folder_open,
                                              title: 'Open File Browser',
                                              topPadding: 0,
                                              bottomPadding: 4,
                                              subtitle:
                                                  'Audition folders and drag files to timeline',
                                              onTap: () {
                                                unawaited(
                                                    _handleAddActionSelection(
                                                        'sample_browser'));
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_sampleBrowserVisible)
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 190),
                                    curve: Curves.easeOutCubic,
                                    left: 0,
                                    right: 0,
                                    top: samplePanelTop,
                                    bottom: samplePanelBottom,
                                    child: SampleBrowserPanel(
                                      rootFolders: _sampleBrowserRoots,
                                      auditioningPath: _auditioningSamplePath,
                                      onAuditionTap: _auditionSampleFile,
                                      onInsertSample: (filePath) =>
                                          _insertAudioFileAtTimeline(filePath),
                                      onAddFolder: _addSampleBrowserRootFolder,
                                      onRemoveFolder: _removeSampleBrowserRoot,
                                      resolveDuration: _resolveSampleDuration,
                                      previewPositionStream:
                                          _samplePreviewPlayer.positionStream,
                                      previewDurationStream:
                                          _samplePreviewPlayer.durationStream,
                                      previewPlaying: _samplePreviewPlaying,
                                      onPreviewSeek: (pos) =>
                                          _samplePreviewPlayer.seek(pos),
                                      onDragActivityChanged:
                                          _setSampleDragActive,
                                      onClose: () {
                                        unawaited(_closeSampleBrowser());
                                      },
                                      expanded: _sampleBrowserExpanded,
                                      onExpandedChanged: (expanded) {
                                        setState(() {
                                          _sampleBrowserExpanded = expanded;
                                        });
                                      },
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: _kChatBarStackHeight + chatLift,
                                  child: AnimatedSlide(
                                    offset: _chatExpanded
                                        ? Offset.zero
                                        : const Offset(0, 0.3),
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    child: SizedBox(
                                      height: _kChatHistoryHeight,
                                      child: _chatWarm
                                          ? Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              child: IgnorePointer(
                                                ignoring: !_chatExpanded,
                                                child: AnimatedOpacity(
                                                  duration: const Duration(
                                                      milliseconds: 140),
                                                  curve: Curves.easeOutCubic,
                                                  opacity:
                                                      _chatExpanded ? 1 : 0,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            22),
                                                    child: BackdropFilter(
                                                      filter: ImageFilter.blur(
                                                          sigmaX: 18,
                                                          sigmaY: 18),
                                                      child: Container(
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  _kChatChromeOpacity),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(22),
                                                          border: Border.all(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.14)),
                                                        ),
                                                        child: MediaQuery
                                                            .removePadding(
                                                          context:
                                                              overlayContext,
                                                          removeBottom: true,
                                                          child: MediaQuery
                                                              .removeViewInsets(
                                                            context:
                                                                overlayContext,
                                                            removeBottom: true,
                                                            child: Chat(
                                                              chatController:
                                                                  _chatController,
                                                              currentUserId:
                                                                  'user',
                                                              onMessageSend:
                                                                  null, // message sending is handled by a component outside. this is simply showing the chat history
                                                              timeFormat: null,
                                                              onMessageLongPress:
                                                                  (
                                                                BuildContext
                                                                    context,
                                                                Message
                                                                    message, {
                                                                required LongPressStartDetails
                                                                    details,
                                                                required int
                                                                    index,
                                                              }) async {
                                                                // Only copy text messages
                                                                if (message
                                                                    is TextMessage) {
                                                                  await Clipboard
                                                                      .setData(
                                                                    ClipboardData(
                                                                        text: message
                                                                            .text),
                                                                  );

                                                                  await AppHaptics.impact(
                                                                      AppHapticImpact
                                                                          .light);

                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                    const SnackBar(
                                                                      content: Text(
                                                                          'Message copied to clipboard'),
                                                                      duration: Duration(
                                                                          milliseconds:
                                                                              1500),
                                                                      behavior:
                                                                          SnackBarBehavior
                                                                              .floating,
                                                                    ),
                                                                  );
                                                                }
                                                              },
                                                              builders:
                                                                  Builders(
                                                                composerBuilder: (_) =>
                                                                    const SizedBox
                                                                        .shrink(),
                                                                // chatAnimatedListBuilder: (context, itemBuilder) {
                                                                //   return MediaQuery.removePadding(
                                                                //     context: context,
                                                                //     removeBottom: true,
                                                                //     child: ChatAnimatedList(
                                                                //       itemBuilder: itemBuilder,
                                                                //     ),
                                                                //   );
                                                                // },
                                                                // emptyChatListBuilder: (_) => const SizedBox.shrink(),
                                                                chatAnimatedListBuilder:
                                                                    (context,
                                                                        itemBuilder) {
                                                                  return Column(
                                                                    children: [
                                                                      Expanded(
                                                                        child: MediaQuery
                                                                            .removePadding(
                                                                          context:
                                                                              context,
                                                                          removeBottom:
                                                                              true,
                                                                          child:
                                                                              ChatAnimatedList(itemBuilder: itemBuilder),
                                                                        ),
                                                                      ),
                                                                      if (_isThinking)
                                                                        Padding(
                                                                          padding:
                                                                              const EdgeInsets.only(
                                                                            left:
                                                                                14,
                                                                            right:
                                                                                14,
                                                                            bottom:
                                                                                10,
                                                                            top:
                                                                                4,
                                                                          ),
                                                                          child:
                                                                              Align(
                                                                            alignment:
                                                                                Alignment.centerLeft,
                                                                            child:
                                                                                _AssistantThinkingBubble(),
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  );
                                                                },
                                                                textMessageBuilder:
                                                                    (
                                                                  BuildContext
                                                                      context,
                                                                  TextMessage
                                                                      message,
                                                                  int index, {
                                                                  required bool
                                                                      isSentByMe,
                                                                  MessageGroupStatus?
                                                                      groupStatus,
                                                                }) {
                                                                  // SYSTEM / ACTION MESSAGE
                                                                  if (message
                                                                          .authorId ==
                                                                      'system') {
                                                                    return Padding(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          vertical:
                                                                              10),
                                                                      child:
                                                                          Center(
                                                                        child:
                                                                            Text(
                                                                          message
                                                                              .text,
                                                                          textAlign:
                                                                              TextAlign.center,
                                                                          style:
                                                                              const TextStyle(
                                                                            fontFamily:
                                                                                'Pretendard',
                                                                            fontSize:
                                                                                13,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            letterSpacing:
                                                                                0.4,
                                                                            color:
                                                                                Colors.white70,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    );
                                                                  }
                                                                  return Align(
                                                                    alignment: isSentByMe
                                                                        ? Alignment
                                                                            .centerRight
                                                                        : Alignment
                                                                            .centerLeft,
                                                                    child:
                                                                        Container(
                                                                      margin: const EdgeInsets
                                                                          .symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            4,
                                                                      ),
                                                                      padding:
                                                                          const EdgeInsets
                                                                              .symmetric(
                                                                        horizontal:
                                                                            14,
                                                                        vertical:
                                                                            10,
                                                                      ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: isSentByMe
                                                                            ? const Color.fromARGB(
                                                                                180,
                                                                                56,
                                                                                98,
                                                                                161,
                                                                              ) // user bubble
                                                                            : Color.fromARGB(
                                                                                100,
                                                                                170,
                                                                                170,
                                                                                170,
                                                                              ), // assistant bubble
                                                                        borderRadius:
                                                                            BorderRadius.circular(14),
                                                                      ),
                                                                      child: isSentByMe
                                                                          ? Text(
                                                                              message.text,
                                                                              style: const TextStyle(
                                                                                fontFamily: 'Pretendard',
                                                                                fontSize: 15,
                                                                                height: 1.2,
                                                                                color: Colors.white,
                                                                              ),
                                                                            )
                                                                          : RollingText(
                                                                              text: message.text,
                                                                              style: const TextStyle(
                                                                                fontFamily: 'Pretendard',
                                                                                fontSize: 15,
                                                                                height: 1.2,
                                                                                color: Colors.white,
                                                                              ),
                                                                            ),
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                              theme:
                                                                  const ChatTheme(
                                                                colors:
                                                                    ChatColors(
                                                                  // User message bubble (you)
                                                                  primary: Color
                                                                      .fromARGB(
                                                                          180,
                                                                          56,
                                                                          98,
                                                                          161),
                                                                  onPrimary:
                                                                      Colors
                                                                          .white,
                                                                  // Message list surface layers (kill them)
                                                                  surface: Colors
                                                                      .transparent,
                                                                  onSurface:
                                                                      Colors
                                                                          .white,
                                                                  surfaceContainer:
                                                                      Colors
                                                                          .transparent, //Color.fromARGB(100, 170, 170, 170),
                                                                  surfaceContainerLow:
                                                                      Colors
                                                                          .transparent,
                                                                  surfaceContainerHigh:
                                                                      Colors
                                                                          .transparent,
                                                                ),
                                                                typography:
                                                                    ChatTypography(
                                                                  bodyLarge:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        15,
                                                                    height:
                                                                        1.35,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                  bodyMedium:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        14,
                                                                    height:
                                                                        1.35,
                                                                    color: Colors
                                                                        .white70,
                                                                  ),
                                                                  bodySmall:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        13,
                                                                    height: 1.3,
                                                                    color: Colors
                                                                        .white60,
                                                                  ),
                                                                  labelLarge:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    color: Colors
                                                                        .white70,
                                                                  ),
                                                                  labelMedium:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .white60,
                                                                  ),
                                                                  labelSmall:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Pretendard',
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .white54,
                                                                  ),
                                                                ),

                                                                // Message bubble shape — keep subtle, not “chat app rounded”
                                                                shape: BorderRadius
                                                                    .all(Radius
                                                                        .circular(
                                                                            14)),
                                                              ),
                                                              resolveUser:
                                                                  (UserID
                                                                      id) async {
                                                                if (id ==
                                                                    'user') {
                                                                  return const User(
                                                                      id:
                                                                          'user',
                                                                      name:
                                                                          'You');
                                                                }
                                                                return const User(
                                                                    id:
                                                                        'assistant',
                                                                    name:
                                                                        'MixAssistant');
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            )
                                          : const SizedBox(),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        if (_showPianoRoll && _activeMidiClipEngineId != null)
                          ValueListenableBuilder<Duration>(
                            valueListenable: _transportClock,
                            builder: (_, clock, __) => Builder(
                              builder: (panelContext) {
                                final idx = _clipIndexForEngineId(
                                    _activeMidiClipEngineId!);
                                if (idx < 0 || idx >= _audioTracks.length) {
                                  return const SizedBox.shrink();
                                }
                                final clip = _audioTracks[idx];
                                if (!clip.isMidi) {
                                  return const SizedBox.shrink();
                                }

                                final media = MediaQuery.of(panelContext);
                                final screenH = media.size.height;
                                final safeTopInset = media.padding.top;
                                final fullscreenTopGap = math.max(
                                  152.0,
                                  safeTopInset + _kTransportBarHeight + 44.0,
                                );
                                final maxFullscreenHeight = math.max(
                                  280.0,
                                  screenH -
                                      _kChatBarStackHeight -
                                      fullscreenTopGap,
                                );
                                final targetHeight = _pianoRollFullscreen
                                    ? maxFullscreenHeight
                                    : (screenH * 0.42);
                                final panelHeight =
                                    math.max(260.0, targetHeight);

                                return AnimatedPositioned(
                                  duration: const Duration(milliseconds: 190),
                                  curve: Curves.easeOutCubic,
                                  left: 0,
                                  right: 0,
                                  bottom: _kChatBarStackHeight,
                                  height: panelHeight,
                                  child: PianoRollEditor(
                                    clip: clip,
                                    bpm: _tempo,
                                    projectPlayheadMs:
                                        clock.inMilliseconds.toDouble(),
                                    isPlaying: _isPlaying,
                                    beatsPerBar: 4,
                                    magnetEnabled: _timelineMagnetEnabled,
                                    quantizeDivisionsPerBar:
                                        _timelineQuantizeDivisionsPerBar,
                                    fullscreen: _pianoRollFullscreen,
                                    onFullscreenChanged: (v) {
                                      setState(() => _pianoRollFullscreen = v);
                                    },
                                    onClose: _closeMidiClipEditor,
                                    onCommit: _commitMidiClipFromPianoRoll,
                                    onPreviewNote: _previewPianoRollNote,
                                  ),
                                );
                              },
                            ),
                          ),
                        if (_showTempoRollDown)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setState(() => _showTempoRollDown = false),
                              child: Container(color: Colors.transparent),
                            ),
                          ),
                        _buildTempoRollDownPanel(),
                        // tap-away closing
                        if (_showMasterRack)
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () {
                                if (!_isMasterPopupOpen) return;
                                setState(() {
                                  _isMasterPopupOpen = false;
                                  _showMasterRack = false;
                                });
                              },
                              child: Container(color: Colors.transparent),
                            ),
                          ),
                        _buildMasterPopup(),
                      ],
                    );
                  },
                ),
              ),
              bottomNavigationBar: _buildBottomChatAndTransport(
                includeChatBar: false,
                includeProducerCapture: false,
                includeTransport: true,
              ),
              // floatingActionButton: Padding(
              //   padding: const EdgeInsets.only(bottom: 0.0, right: 0.0), // above bottom nav
              //   child: FloatingActionButton(
              //     onPressed: () => _showAddMediaOptions(),
              //     backgroundColor: const Color.fromARGB(255, 212, 212, 212),
              //     child: const Icon(Icons.add, color: Colors.black),
              //     shape: const CircleBorder(),
              //     elevation: 4,
              //   ),
              // ),
            ),
            if (_isSyncing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.75),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DotsLoader(),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 250,
                          child: LinearProgressIndicator(
                            value: _syncProgress,
                            backgroundColor: Colors.white30,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.lightBlueAccent),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_syncProgress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isLoadingAudio || _isLoadingNextScreen)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            _buildProgressIndicator(),
            if (_chatExpanded)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: _kChatHistoryHeight +
                    _kChatBarStackHeight +
                    _kTransportBarHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    setState(() {
                      _chatExpanded = false;
                      _chatInputActive = false;
                      _chatFocusNode.unfocus();
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PillDivider extends StatelessWidget {
  final double height;
  const _PillDivider({this.height = 22, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.28),
            Colors.white.withOpacity(0.08)
          ],
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final double radius;
  final EdgeInsets padding;
  final Widget child;
  final double opacity;
  final double blur;
  final Gradient? overlay;
  final List<BoxShadow>? shadows;

  const _Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(12),
    this.opacity = 0.08,
    this.blur = 18,
    this.overlay,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      // child: BackdropFilter(
      // filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(opacity),
          gradient: overlay,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: shadows ??
              [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
        ),
        child: child,
      ),
      // ),
    );
  }
}

class DotsLoader extends StatefulWidget {
  const DotsLoader({Key? key}) : super(key: key);

  @override
  State<DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<DotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dotCount;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..repeat();
    _dotCount = StepTween(begin: 0, end: 4).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxDots = 4;
    const dotWidth = 6.0; // each dot ~6px
    final totalDotSpace = maxDots * dotWidth;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${L10n.translate(context, 'Syncing Audio')}',
            style: TextStyle(color: Colors.white, fontSize: 20)),
        const SizedBox(width: 2),
        SizedBox(
          width: totalDotSpace,
          child: AnimatedBuilder(
            animation: _dotCount,
            builder: (context, _) {
              return Text('.' * _dotCount.value,
                  style: const TextStyle(color: Colors.white, fontSize: 20));
            },
          ),
        ),
      ],
    );
  }
}

double getVolumeForAutomation(
    List<AutomationPoint> points, double normalizedTime) {
  if (points.isEmpty) return 1.0;
  if (normalizedTime <= points.first.x) return points.first.volume;
  if (normalizedTime >= points.last.x) return points.last.volume;
  for (int i = 0; i < points.length - 1; i++) {
    if (normalizedTime >= points[i].x && normalizedTime <= points[i + 1].x) {
      double t =
          (normalizedTime - points[i].x) / (points[i + 1].x - points[i].x);
      return points[i].volume + t * (points[i + 1].volume - points[i].volume);
    }
  }
  return 1.0;
}

void _findSyncOffsetInBackground(List<Object?> args) {
  final SendPort sendPort = args[0] as SendPort;
  final String videoAudioPath = args[1] as String;
  final String convertedTrackPath = args[2] as String;
  final double sampleRate = args[3] as double;
  final SendPort progressPort = args[4] as SendPort;

  void run() async {
    List<double> videoSamples = await loadAudioSamplesAsync(videoAudioPath);
    List<double> trackSamples = await loadAudioSamplesAsync(convertedTrackPath);

    int bestOffset =
        findOffsetFFT(videoSamples, trackSamples, sampleRate, progressPort);
    sendPort.send(bestOffset);
  }

  run();
}

// Synchronous function to load audio samples
List<double> loadAudioSamples(String filePath, {int numChannels = 2}) {
  final file = File(filePath);
  final bytes = file.readAsBytesSync();

  final Uint8List audioBytes = Uint8List.fromList(bytes);
  List<double> samples = [];

  for (int i = 0; i < audioBytes.length - 1; i += 2 * numChannels) {
    int sample = audioBytes[i] | (audioBytes[i + 1] << 8);
    if (sample >= 0x8000) sample -= 0x10000;
    samples.add(sample / 32768.0);
  }

  return samples;
}

Future<List<double>> loadAudioSamplesAsync(String filePath,
    {int numChannels = 2}) async {
  final file = File(filePath);
  final bytes = await file.readAsBytes();

  final Uint8List audioBytes = Uint8List.fromList(bytes);
  List<double> samples = [];

  for (int i = 0; i < audioBytes.length - 1; i += 2 * numChannels) {
    int sample = audioBytes[i] | (audioBytes[i + 1] << 8);
    if (sample >= 0x8000) sample -= 0x10000;
    samples.add(sample / 32768.0);
  }

  // print("printing samples");
  // for (int i = 0; i<200; i++) {
  //   print(samples[i]);
  // }

  return samples;
}

int findOffsetFFT(List<double> videoSamples, List<double> trackSamples,
    double sampleRate, SendPort progressPort) {
  // 1. Downsample first (Key optimization)
  const int targetSampleRate = 8000; // Adequate for sync
  final double ratio = sampleRate / targetSampleRate;

  final videoDown = _downsample(videoSamples, ratio);
  final trackDown = _downsample(trackSamples, ratio);
  final effectiveRate = sampleRate / ratio;

  // 2. Calculate optimal FFT size
  final minLength = videoDown.length + trackDown.length - 1;
  final fftSize = _nextPowerOf2(minLength);
  final fft = FFT(fftSize);

  progressPort.send(0.1);

  // 3. Memory-efficient windowing
  final windowedVideo = _applyWindow(videoDown, fftSize);
  final windowedTrack = _applyWindow(trackDown, fftSize);

  progressPort.send(0.3);

  // 4. Compute FFTs (using your original FFT calls)
  final videoFFT = fft.realFft(windowedVideo);
  progressPort.send(0.5);
  final trackFFT = fft.realFft(windowedTrack);
  progressPort.send(0.6);

  // 5. Frequency-domain multiplication (fixed type)
  // final productFFT = List<Float64x2>.generate(videoFFT.length, (i) {
  //   final v = videoFFT[i], t = trackFFT[i];
  //   return Float64x2(
  //     v.x * t.x + v.y * t.y, // real
  //     v.y * t.x - v.x * t.y  // imag
  //   );
  // });
  // 5) GCC-PHAT weighting (phase transform)
  final productFFT = List<Float64x2>.generate(videoFFT.length, (i) {
    final v = videoFFT[i]; // V[k]
    final t = trackFFT[i]; // T[k]
    // Cross-spectrum with conj(T): V * conj(T)
    final double r = v.x * t.x + v.y * t.y; // real
    final double im = v.y * t.x - v.x * t.y; // imag
    final double mag = sqrt(r * r + im * im) + 1e-12; // avoid div/0
    return Float64x2(r / mag, im / mag); // PHAT normalization
  });
  progressPort.send(0.7);

  // 6. Inverse FFT and peak finding
  final productFFTList = Float64x2List.fromList(productFFT);
  final correlation = fft.realInverseFft(productFFTList);
  // final correlation = fft.realInverseFft(productFFT);
  progressPort.send(0.8);

  final peakIndex = _findPeakIndex(correlation);
  final refinedLag = _refinePeak(correlation, peakIndex, fftSize);
  final offsetMs = (refinedLag / effectiveRate * 1000).round();

  progressPort.send(1.0);
  return offsetMs;
}

// ---- Helper Functions ---- //

List<double> _downsample(List<double> input, double ratio) {
  final newLength = (input.length / ratio).floor();
  return List.generate(newLength, (i) => input[(i * ratio).floor()]);
}

List<double> _applyWindow(List<double> input, int fftSize) {
  final output = List<double>.filled(fftSize, 0.0);
  final length = min(input.length, fftSize);

  for (int i = 0; i < length; i++) {
    final hann = 0.5 * (1 - cos(2 * pi * i / (length - 1)));
    output[i] = input[i] * hann;
  }
  return output;
}

int _findPeakIndex(List<double> data) {
  int maxIndex = 0;
  for (int i = 1; i < data.length; i++) {
    if (data[i] > data[maxIndex]) maxIndex = i;
  }
  return maxIndex;
}

double _refinePeak(List<double> data, int index, int fftSize) {
  if (index <= 0 || index >= data.length - 1) return index.toDouble();

  final double delta = 0.5 *
      (data[index - 1] - data[index + 1]) /
      (data[index - 1] - 2 * data[index] + data[index + 1]);

  final refined = index + delta;
  return refined < fftSize / 2 ? refined : refined - fftSize;
}

// int _nextPowerOf2(int n) => 1 << (n.bitLength + (n & (n - 1) == 0 ? 0 : 1));

// int findOffsetFFT(List<double> videoSamples, List<double> trackSamples, double sampleRate, SendPort progressPort) {
//   final int videoLength = videoSamples.length;
//   final int trackLength = trackSamples.length;

//   // Compute minimum padded length, then optionally choose a higher power of 2 for more resolution.
//   final int minPaddedLength = videoLength + trackSamples.length - 1;
//   final int paddedLength = _nextPowerOf2(minPaddedLength);
//   final fft = FFT(paddedLength);

//   progressPort.send(0.05);

//   // Zero-pad both signals.
//   // Optionally, apply a Hann window to improve accuracy.
//   List<double> windowedVideo = applyHannWindow(videoSamples);
//   List<double> windowedTrack = applyHannWindow(trackSamples);

//   List<double> paddedVideo = List.filled(paddedLength, 0.0);
//   List<double> paddedTrack = List.filled(paddedLength, 0.0);
//   paddedVideo.setAll(0, windowedVideo);
//   paddedTrack.setAll(0, windowedTrack);

//   progressPort.send(0.25);

//   normalize(paddedVideo);
//   normalize(paddedTrack);
//   progressPort.send(0.35);

//   // Compute FFTs.
//   final videoFFT = fft.realFft(paddedVideo);
//   progressPort.send(0.45);
//   final trackFFT = fft.realFft(paddedTrack);
//   progressPort.send(0.55);

//   // Multiply in frequency domain.
//   for (int i = 0; i < videoFFT.length; i++) {
//     final double real1 = videoFFT[i].x;
//     final double imag1 = videoFFT[i].y;
//     final double real2 = trackFFT[i].x;
//     final double imag2 = trackFFT[i].y;
//     trackFFT[i] = Float64x2(
//       real1 * real2 + imag1 * imag2, // Real
//       imag1 * real2 - real1 * imag2  // Imaginary
//     );
//   }
//   progressPort.send(0.65);

//   // Inverse FFT to compute correlation.
//   final correlation = fft.realInverseFft(trackFFT);
//   progressPort.send(0.75);

//   // Find maximum correlation index.
//   int bestIndex = 0;
//   double maxCorrValue = double.negativeInfinity;
//   for (int i = 0; i < correlation.length; i++) {
//     if (correlation[i] > maxCorrValue) {
//       maxCorrValue = correlation[i];
//       bestIndex = i;
//     }
//   }
//   progressPort.send(0.85);

//   // Quadratic interpolation to refine the peak.
//   double refinedIndexDouble = bestIndex.toDouble();
//   if (bestIndex > 0 && bestIndex < correlation.length - 1) {
//     double prevVal = correlation[bestIndex - 1];
//     double centerVal = correlation[bestIndex];
//     double nextVal = correlation[bestIndex + 1];
//     double denominator = prevVal - 2 * centerVal + nextVal;
//     if (denominator != 0) {
//       double shift = 0.5 * (prevVal - nextVal) / denominator;
//       refinedIndexDouble = bestIndex + shift;
//     }
//   }

//   // Convert index to lag.
//   int refinedLag;
//   if (refinedIndexDouble < paddedLength / 2) {
//     refinedLag = refinedIndexDouble.round();
//   } else {
//     refinedLag = (refinedIndexDouble - paddedLength).round();
//   }
//   progressPort.send(0.95);

//   int finalOffsetMs = (refinedLag / sampleRate * 1000).round();

//   print("""
// ======== SYNC DEBUG ========
//   Video Samples: $videoLength
//   Track Samples: $trackLength
//   Best Peak Index: $bestIndex
//   Refined Index (fractional): $refinedIndexDouble
//   Refined Lag (samples): $refinedLag
//   Final Offset: $finalOffsetMs ms
// ======== END DEBUG ========
// """);

//   progressPort.send(1.0);
//   return finalOffsetMs;
// }

List<double> applyHannWindow(List<double> samples) {
  final int N = samples.length;
  List<double> windowed = List.filled(N, 0.0);
  for (int n = 0; n < N; n++) {
    double w = 0.5 * (1 - cos(2 * pi * n / (N - 1)));
    windowed[n] = samples[n] * w;
  }
  return windowed;
}

// Future<String> extractAudioFromVideo(String videoPath) async {
//   final tempDir = await getTemporaryDirectory();
//   final audioPath = '${tempDir.path}/video_audio.pcm';

//   final command = '-i "$videoPath" -vn -ac 2 -ar 44100 -f s16le -y "$audioPath"';

//   await FFmpegKit.execute(command);

//   return audioPath;
// }

// Future<String> convertAudioToWav(String inputPath) async {
//   final tempDir = await getTemporaryDirectory();
//   final outputPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.pcm';

//   // final command = '-i "$inputPath" -ar 44100 -y "$outputPath"';
//   final command = '-i "$inputPath" -vn -ac 2 -ar 44100 -f s16le -y "$outputPath"';
//   await FFmpegKit.execute(command);

//   return outputPath;
// }

// UPDATED FIX FOR AUDIO EXTRACTION (SIMPLE PCM EXTRACTION ABOVE WASN'T WORKING FOR IOS ADDED +50-70MS, WAS FINE FOR ANDROID)
// TODO: TEST FOR ANDROID TOO

/*

6) If it’s still off by a hair on iOS

Add these:

-af "... , highpass=f=30, adeclick" before resample to remove DC/very low rumble that can bias correlation.

-fflags +bitexact -flags:a +bitexact to both commands.

Make sure your comparison code normalizes both vectors (mean-center, divide by rms) before correlation.

*/

Future<String> extractAudioFromVideo(String videoPath) async {
  final tmp = await getTemporaryDirectory();
  final out = '${tmp.path}/video_${DateTime.now().millisecondsSinceEpoch}.pcm';
  final iosCmd = '-y -i "$videoPath" '
      '-af "pan=mono|c0=0.5*c0+0.5*c1, asetpts=PTS-STARTPTS, aresample=resampler=soxr:precision=28" '
      '-ar 48000 -ac 2 -f s16le "$out"';
  final androidCmd = '-i "$videoPath" -vn -ac 2 -ar 44100 -f s16le -y "$out"';

  await FFmpegKit.execute(Platform.isAndroid ? androidCmd : iosCmd);
  return out;
}

Future<String> convertAudioToWav(String inputPath) async {
  final tmp = await getTemporaryDirectory();
  final out = '${tmp.path}/audio_${DateTime.now().millisecondsSinceEpoch}.pcm';
  final iosCmd = '-y -i "$inputPath" '
      '-af "pan=mono|c0=0.5*c0+0.5*c1, asetpts=PTS-STARTPTS, aresample=resampler=soxr:precision=28" '
      '-ar 48000 -ac 2 -f s16le "$out"';
  final androidCmd = '-i "$inputPath" -vn -ac 2 -ar 44100 -f s16le -y "$out"';

  await FFmpegKit.execute(Platform.isAndroid ? androidCmd : iosCmd);
  return out;
}

int _nextPowerOf2(int n) {
  int power = 1;
  while (power < n) {
    power *= 2;
  }
  return power;
}

void normalize(List<double> samples) {
  double maxVal = samples.reduce((a, b) => a.abs() > b.abs() ? a : b);
  if (maxVal > 0) {
    for (int i = 0; i < samples.length; i++) {
      samples[i] /= maxVal; // Scale values between -1 and 1
    }
  }
}

Future<double> getSampleRate(String filePath) async {
  final session = await FFmpegKit.execute('-i "$filePath" -hide_banner');
  final logs = await session.getLogsAsString() ?? "";

  final sampleRateRegex = RegExp(r'(\d+) Hz');
  final match = sampleRateRegex.firstMatch(logs);

  if (match != null) {
    return double.parse(match.group(1)!);
  } else {
    print("⚠️ Could not detect sample rate. Defaulting to 44100 Hz.");
    return 44100.0; // Fallback to 44.1kHz only if detection fails
  }
}

String generateVolumeAutomationFilter(
    AudioTrack track, int offsetMs, double universalCrossfade) {
  // If no automation points, default to universal crossfade value.
  if (track.volumeAutomation.isEmpty)
    return min(1.0, universalCrossfade * 2).toStringAsFixed(2);

  List<String> conditions = [];
  double trackOffsetSec = offsetMs / 1000.0;
  double trackStartSec = track.trimStart.inSeconds.toDouble();
  double trackEndSec = track.trimEnd.inSeconds.toDouble();
  double trackDuration = trackEndSec - trackStartSec;

  for (int i = 0; i < track.volumeAutomation.length - 1; i++) {
    AutomationPoint startPoint = track.volumeAutomation[i];
    AutomationPoint endPoint = track.volumeAutomation[i + 1];

    // Adjust the time positions by the track offset.
    double pointStart = (startPoint.x * trackDuration) + trackOffsetSec;
    double pointEnd = (endPoint.x * trackDuration) + trackOffsetSec;
    double volumeStart = startPoint.volume;
    double volumeEnd = endPoint.volume;

    // Use linear interpolation for smooth volume transition.
    conditions.add(
      "if(between(t,max($pointStart,0),max($pointEnd,0)),"
      "$volumeStart+($volumeEnd-$volumeStart)*(t-$pointStart)/($pointEnd-$pointStart),",
    );
  }

  // Close all nested ifs.
  String closingBrackets = List.filled(conditions.length, ")").join("");
  // Build the automation expression.
  String automationExpr = "${conditions.join("")}1.0$closingBrackets";
  // Multiply the automation by the universal crossfade factor.
  return "'($automationExpr)*(${min(1.0, universalCrossfade * 2).toStringAsFixed(2)})'";
}

// EXPORT PROGRESS SCREEN

class ExportProgressPage extends StatefulWidget {
  final Future<String> Function(ValueChanged<double>) exportFn;
  final String videoFile;

  const ExportProgressPage(
      {required this.exportFn, required this.videoFile, super.key});

  @override
  State<ExportProgressPage> createState() => _ExportProgressPageState();
}

class _ExportProgressPageState extends State<ExportProgressPage> {
  double _progress = 0.0;
  Uint8List? _thumbnail;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _cancelSignal = Completer();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      _startExport();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _startExport() async {
    final path = await widget.exportFn((value) {
      if (!_cancelled) setState(() => _progress = value.clamp(0.0, 1.0));
    });
    if (!_cancelled && mounted) Navigator.of(context).pop(path); // return path
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cancel button
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() => _cancelled = true);
                _cancelSignal.complete();
                print("cancelling export progress");
                Navigator.of(context).pop("");
              },
            ),
            const SizedBox(height: 24),
            Text(
              L10n.translate(context, 'Exporting...'),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.translate(
                  context, "Please don't close the app or lock your screen."),
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 24),
            if (_thumbnail != null)
              SizedBox(
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _thumbnail!,
                          height: 160,
                          fit: BoxFit.contain, // or omit fit entirely
                        ),
                      ),
                    ),
                    Text(
                      "${(_progress * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// EXPORT PROGRESS SCREEN END

// EXPORT SUCCESS SCREEN

class ExportSuccessScreen extends StatelessWidget {
  final String filePath;
  final bool isVideo;

  const ExportSuccessScreen(
      {super.key, required this.filePath, required this.isVideo});

  Future<void> _shareFile(BuildContext context) async {
    try {
      await Share.shareXFiles(
          [XFile(filePath)]); // doesn't work on android (only iOS)
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share.')), // ${e.toString()}')),
      );
    }
  }

  Future<void> _openSocialMedia(String deepLink, String fallbackUrl) async {
    try {
      if (await canLaunchUrl(Uri.parse(deepLink))) {
        await launchUrl(Uri.parse(deepLink));
      } else {
        await launchUrl(Uri.parse(fallbackUrl));
      }
    } catch (e) {
      debugPrint('Error launching social media.'); // $e');
    }
  }

  Future<Map<String, String>?> showUploadDialog(BuildContext context) {
    final titleController = TextEditingController(text: 'My Mixroom Video');
    final descController =
        TextEditingController(text: 'Made with Mixroom 🎸🎬');

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Upload to YouTube'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: descController,
                decoration: InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor:
                    const Color.fromARGB(255, 255, 255, 255), // or onPrimary
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'title': titleController.text,
                  'description': descController.text
                });
              },
              child: Text('Upload'),
            ),
          ],
        );
      },
    );
  }

  Future<File> extractFirstFrame(File videoFile) async {
    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/frame.jpg';

    final cmd = '-i "${videoFile.path}" -frames:v 1 "$outPath"';
    await FFmpegKit.execute(cmd);

    final frame = File(outPath);
    if (!await frame.exists()) throw Exception('Failed to extract frame');
    return frame;
  }

  Future<File> generateThumbnailWithQR(String videoId) async {
    final url = 'https://youtube.com/watch?v=$videoId';

    // 1. Generate QR Code
    final qrValidationResult = QrValidator.validate(
      data: url,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    final qrCode = qrValidationResult.qrCode!;
    final painter = QrPainter.withQr(
      qr: qrCode,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
      gapless: true,
    );
    final qrImageData =
        await painter.toImageData(300, format: ImageByteFormat.png);

    final qrBytes = qrImageData!.buffer.asUint8List();

    // 2. Get YouTube default thumbnail
    // final thumbRes = await http.get(Uri.parse('https://img.youtube.com/vi/$videoId/maxresdefault.jpg'));
    // final thumbnail = img.decodeImage(thumbRes.bodyBytes);
    final frameFile = await extractFirstFrame(File(filePath));
    final thumbnail = img.decodeImage(await frameFile.readAsBytes());
    final qr = img.decodeImage(qrBytes);

    if (thumbnail == null || qr == null)
      throw Exception("Failed to process images");

    // 3. Overlay QR on top-left
    final qrSize = (thumbnail.width * 0.25).toInt(); // ~25% width
    final qrResized = img.copyResize(qr, width: qrSize);
    img.compositeImage(thumbnail, qrResized, dstX: 10, dstY: 10);

    // 4. Save to temp file
    final tempDir = await getTemporaryDirectory();
    final outFile = File('${tempDir.path}/yt_thumb_with_qr.jpg');
    await outFile.writeAsBytes(img.encodePng(thumbnail));
    return outFile;
  }

  void showQRPopup(BuildContext context, File qrImage) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text('🎉 Video Uploaded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your video is live!'),
              SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(qrImage,
                    width: 280, height: 158, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text("Save Image"),
                onPressed: () async {
                  final result = await ImageGallerySaver.saveFile(qrImage.path);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(result['isSuccess'] == true
                            ? '✅ Saved to gallery!'
                            : '❌ Failed to save')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color.fromARGB(255, 22, 22, 22),
            actions: [
              TextButton(
                onPressed: () {
                  // Navigator.pushAndRemoveUntil(
                  //   context,
                  //   PageRouteBuilder(
                  //     pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(),
                  //     transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  //       const beginScale = 0.96;
                  //       const endScale = 1.0;
                  //       const curve = Curves.easeOutCubic;

                  //       final tween = Tween<double>(begin: beginScale, end: endScale)
                  //           .chain(CurveTween(curve: curve));
                  //       final fadeTween = Tween<double>(begin: 0.0, end: 1.0)
                  //           .chain(CurveTween(curve: curve));

                  //       return FadeTransition(
                  //         opacity: animation.drive(fadeTween),
                  //         child: ScaleTransition(
                  //           scale: animation.drive(tween),
                  //           child: child,
                  //         ),
                  //       );
                  //     },
                  //     transitionDuration: const Duration(milliseconds: 300),
                  //   ),
                  //   (route) => false,
                  // );
                  Navigator.pop(context, true);
                },
                child: Text(L10n.translate(context, 'Done'),
                    style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ), //title: Text(L10n.translate(context, 'Export Successful'))),
          body: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 100),
                      const SizedBox(height: 20),
                      // Text(
                      //   'Your ${isVideo ? 'video' : 'audio'} was exported successfully!',
                      //   style: Theme.of(context).textTheme.headlineSmall,
                      //   textAlign: TextAlign.center,
                      // ),
                      isVideo
                          ? Text(
                              L10n.translate(context,
                                  'Your video was exported successfully!'),
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            )
                          : Text(
                              L10n.translate(context,
                                  'Your audio was exported successfully!'),
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                      const SizedBox(height: 40),
                      // ElevatedButton(
                      //   onPressed: () => _shareFile(context),
                      //   child: const Text('Share File'),
                      // ),
                      // const SizedBox(height: 20),
                      Text(L10n.translate(context, 'Share directly to:')),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Wrap(
                          spacing: 32,
                          runSpacing: 24,
                          alignment: WrapAlignment.start,
                          children: [
                            if (isVideo)
                              _SocialButton(
                                iconWidget: Image.asset(
                                    'assets/youtube_icon.png',
                                    width: 56),
                                label: 'YouTube',
                                onTap: () async {
                                  final info = await showUploadDialog(context);
                                  if (info == null) return;

                                  try {
                                    final videoId =
                                        await YoutubeService.uploadVideo(
                                      file: File(filePath),
                                      title: info['title']!,
                                      description: info['description']!,
                                    );

                                    if (videoId == null) {
                                      print('upload failed, videoId == null');
                                      return;
                                    }

                                    final qrThumb =
                                        await generateThumbnailWithQR(videoId);
                                    await YoutubeService.uploadThumbnail(
                                        videoId, qrThumb);
                                    showQRPopup(context, qrThumb);
                                  } catch (e) {
                                    print("❌ Upload failed: $e");
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(SnackBar(
                                        content: Text('❌ Upload failed')));
                                  }

                                  // try {
                                  //   final videoId = await YoutubeService.uploadVideo(
                                  //     file: File(filePath),
                                  //     title: 'My Mixroom Video',
                                  //     description: 'Made with Mixroom 🎸🎬',
                                  //   );
                                  //   if(videoId == null) {
                                  //     print('upload failed, videoId == null');
                                  //     return;
                                  //   }
                                  //   final url = 'https://youtube.com/watch?v=$videoId';
                                  //   ScaffoldMessenger.of(context).showSnackBar(
                                  //     SnackBar(content: Text('✅ Uploaded: $url')),
                                  //   );
                                  // } catch (e) {
                                  //   ScaffoldMessenger.of(context).showSnackBar(
                                  //     SnackBar(content: Text('Upload failed: $e')),
                                  //   );
                                  //   print("upload error reason: $e");
                                  // }
                                },
                              ),
                            if (isVideo)
                              _SocialButton(
                                iconWidget: Image.asset('assets/ig_icon.png',
                                    width: 56),
                                label: 'Instagram',
                                onTap: () => _openSocialMedia(
                                    'instagram://library',
                                    'https://www.instagram.com/'),
                              ),
                            if (isVideo)
                              _SocialButton(
                                iconWidget: Image.asset(
                                    'assets/tiktok_icon.png',
                                    width: 56),
                                label: 'TikTok',
                                onTap: () => _openSocialMedia(
                                    'snssdk1233://upload',
                                    'https://www.tiktok.com/upload'),
                              ),
                            if (!isVideo)
                              _SocialButton(
                                iconWidget: Image.asset(
                                    'assets/soundcloud_icon.png',
                                    width: 56),
                                label: 'SoundCloud',
                                onTap: () => _openSocialMedia(
                                    'soundcloud://upload',
                                    'https://soundcloud.com/upload'),
                              ),
                          ],
                        ),
                      ),
                      // const SizedBox(height: 40),
                      // OutlinedButton(
                      //   onPressed: () => Navigator.popUntil(
                      //       context, (route) => route.isFirst),
                      //   child: Text(L10n.translate(context, 'Back to Editor')),
                      // ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class QRThumbnailScreen extends StatelessWidget {
  final String videoUrl;

  const QRThumbnailScreen({super.key, required this.videoUrl});

  Future<void> _saveThumbnailWithQR(BuildContext context) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(480, 270); // 16:9 thumbnail

    final paint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final qrPainter =
        QrPainter(data: videoUrl, version: QrVersions.auto, gapless: true);

    final qrImage = await qrPainter.toImage(100);
    final qrBytes = await qrImage.toByteData(format: ui.ImageByteFormat.png);

    final qr = await decodeImageFromList(qrBytes!.buffer.asUint8List());
    canvas.drawImage(qr, const Offset(20, 20), Paint());

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/youtube_qr_thumb.png');
    await file.writeAsBytes(byteData!.buffer.asUint8List());

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thumbnail saved to ${file.path}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('YouTube QR Thumbnail')),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text('Your video has been uploaded!'),
            const SizedBox(height: 20),
            QrImageView(data: videoUrl, size: 200),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => _saveThumbnailWithQR(context),
                child: const Text('Download QR Thumbnail')),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;

  const _SocialButton(
      {this.icon, this.iconWidget, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: Colors.white12, shape: BoxShape.circle),
            child: ClipOval(
              child: Center(
                  child:
                      iconWidget ?? Icon(icon, size: 26, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

// EXPORT SUCCESS SCREEN END

// Place this new class definition outside of your main widget's State class.
class DynamicRackContent extends StatefulWidget {
  // Pass the needed page builders/widgets here.
  final Widget volumePage;
  final Widget effectsPage;

  const DynamicRackContent(
      {required this.volumePage, required this.effectsPage, super.key});

  @override
  State<DynamicRackContent> createState() => _DynamicRackContentState();
}

class _DynamicRackContentState extends State<DynamicRackContent>
    with SingleTickerProviderStateMixin {
  // <-- Ticker is now ISOLATED here!

  late TabController _tabController;
  int _currentTabIndex = 0; // State variable to trigger rebuilds

  static const double _volumeContentHeight = 450.0;
  static const double _effectsMaxHeight = 450.0;

  @override
  void initState() {
    super.initState();
    // Initialize the controller using the isolated TickerProvider
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      // Trigger a rebuild only within this small widget
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  // Inside _DynamicRackContentState (in DynamicRackContent.dart)

  @override
  Widget build(BuildContext context) {
    // Height calculation logic remains the same
    final double currentHeight =
        _currentTabIndex == 0 ? _volumeContentHeight : _effectsMaxHeight;

    // 1. Return an AnimatedContainer as the root.
    return AnimatedContainer(
      // 2. Apply the dynamic height and minWidth directly to AnimatedContainer.
      constraints: BoxConstraints(maxHeight: currentHeight, minWidth: 280),
      duration: const Duration(milliseconds: 0), // Smooth transition duration
      curve: Curves.easeOut,

      // 3. The inner content (Column) must now use Expanded to fill this space.
      child: Column(
        mainAxisSize:
            MainAxisSize.min, // The Column must shrink-wrap vertically
        children: [
          // Tabs (TabBar logic with onTap remains the same)
          Container(
            height: 36,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF121927),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: EdgeInsets.zero,
              indicator: BoxDecoration(
                color: const Color(0xFF2D3F5D),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
              overlayColor:
                  MaterialStatePropertyAll(Colors.white.withOpacity(0.03)),
              splashBorderRadius: BorderRadius.circular(8),
              onTap: (newIndex) {
                // Keep the instant jump for TabBarView to avoid flicker
                _tabController.animateTo(newIndex,
                    duration: Duration.zero, curve: Curves.linear);
                // Trigger rebuild for AnimatedContainer
                setState(() {
                  _currentTabIndex = newIndex;
                });
              },
              tabs: const [
                Tab(text: "Master Volume"),
                Tab(text: "Master Effects"),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Content
          Expanded(
            // Now fills the space provided by the AnimatedContainer
            child: TabBarView(
              key: ValueKey(_currentTabIndex),
              physics: const NeverScrollableScrollPhysics(),

              controller: _tabController,
              // physics: const NeverScrollableScrollPhysics(),
              children: [widget.volumePage, widget.effectsPage],
            ),
          ),
        ],
      ),
    );
  }
}

double msFor128Bars(double bpm) {
  return 512 * (60000 / bpm);
}

// ----------------------------------------------------------------
// UNDO/REDO HISTORY
// ----------------------------------------------------------------

class _RowLayoutSnapshot {
  final List<TimelineRow> rows;
  final List<int> clipRowIndices;

  _RowLayoutSnapshot({
    required this.rows,
    required this.clipRowIndices,
  });
}

abstract class EditorUndoAction {
  String get description;

  Future<void> undo();
  Future<void> redo();
}

class EditorUndoManager {
  final int maxHistory;
  final List<EditorUndoAction> _undo = [];
  final List<EditorUndoAction> _redo = [];

  EditorUndoManager({this.maxHistory = 5});

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> execute(EditorUndoAction action) async {
    await action.redo();
    _undo.add(action);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  // yes it is redundant, but works for the edge case of:
  // execute an AI action where you want a compound undo history
  // but you need to execute in sequence before you add, because they depend on each other
  Future<void> executeWithoutAdd(EditorUndoAction action) async {
    await action.redo();
  }

  // same comment here as above
  Future<void> addWithoutExecute(EditorUndoAction action) async {
    _undo.add(action);
    if (_undo.length > maxHistory) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  Future<EditorUndoAction?> undo() async {
    if (_undo.isEmpty) return null;
    final a = _undo.removeLast();
    await a.undo();
    _redo.add(a);
    return a;
  }

  Future<EditorUndoAction?> redo() async {
    if (_redo.isEmpty) return null;
    final a = _redo.removeLast();
    await a.redo();
    _undo.add(a);
    return a;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

class _RowLayoutSnapshotAction extends EditorUndoAction {
  final String descriptionText;
  final _RowLayoutSnapshot before;
  final _RowLayoutSnapshot after;
  final Future<void> Function(_RowLayoutSnapshot snap) applySnapshot;

  _RowLayoutSnapshotAction({
    required this.descriptionText,
    required this.before,
    required this.after,
    required this.applySnapshot,
  });

  @override
  String get description => descriptionText;

  @override
  Future<void> redo() => applySnapshot(after);

  @override
  Future<void> undo() => applySnapshot(before);
}

class AddAudioTrackAction extends EditorUndoAction {
  final Future<void> Function({
    required File file,
    required int row,
    required double timeMs,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) addTrack;

  final List<AudioTrack> tracks;
  final File file;
  final int row;
  final double timeMs;
  final Duration? trimStart;
  final Duration? trimEnd;

  AudioTrack? _addedTrack;

  AddAudioTrackAction({
    required this.addTrack,
    required this.tracks,
    required this.file,
    required this.row,
    required this.timeMs,
    this.trimStart,
    this.trimEnd,
  });

  @override
  String get description => 'Add audio clip';

  @override
  Future<void> redo() async {
    final beforeCount = tracks.length;

    await addTrack(
        file: file,
        row: row,
        timeMs: timeMs,
        trimStartRequested: trimStart,
        trimEndRequested: trimEnd);

    // capture the newly added track
    if (tracks.length > beforeCount) {
      _addedTrack = tracks.last;
    }
  }

  @override
  Future<void> undo() async {
    if (_addedTrack == null) return;

    final track = _addedTrack!;
    track.audioStartTimer?.cancel();

    final removed = tracks.remove(track);
    if (!removed && track.engineClipId >= 0) {
      final idx =
          tracks.indexWhere((t) => t.engineClipId == track.engineClipId);
      if (idx >= 0) {
        tracks.removeAt(idx);
      }
    }
    if (track.engineClipId >= 0) {
      await JuceAudioEngine.removeTrack(track.engineClipId);
    }

    _addedTrack = null;
  }
}

class PasteAudioClipAction extends EditorUndoAction {
  final Future<void> Function({
    required AudioTrack clip,
    required int row,
    required double timeMs,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) pasteClip;

  final List<AudioTrack> tracks;
  final AudioTrack clip;
  final int row;
  final double timeMs;
  final Duration? trimStart;
  final Duration? trimEnd;

  AudioTrack? _addedTrack;

  PasteAudioClipAction({
    required this.pasteClip,
    required this.tracks,
    required this.clip,
    required this.row,
    required this.timeMs,
    this.trimStart,
    this.trimEnd,
  });

  @override
  String get description => 'Paste audio clip';

  @override
  Future<void> redo() async {
    final beforeCount = tracks.length;

    await pasteClip(
        clip: clip,
        row: row,
        timeMs: timeMs,
        trimStartRequested: trimStart,
        trimEndRequested: trimEnd);

    // capture the newly added track
    if (tracks.length > beforeCount) {
      _addedTrack = tracks.last;
    }
  }

  @override
  Future<void> undo() async {
    if (_addedTrack == null) return;

    final track = _addedTrack!;
    track.audioStartTimer?.cancel();

    final removed = tracks.remove(track);
    if (!removed && track.engineClipId >= 0) {
      final idx =
          tracks.indexWhere((t) => t.engineClipId == track.engineClipId);
      if (idx >= 0) {
        tracks.removeAt(idx);
      }
    }
    if (track.engineClipId >= 0) {
      await JuceAudioEngine.removeTrack(track.engineClipId);
    }

    _addedTrack = null;
  }
}

class AddMidiClipAction extends EditorUndoAction {
  final Future<void> Function({
    required String instrumentId,
    required String instrumentName,
    required Map<String, double> instrumentParams,
    required List<MidiNote> midiNotes,
    required int row,
    required double timeMs,
  }) addMidiClip;

  final List<AudioTrack> tracks;
  final String instrumentId;
  final String instrumentName;
  final Map<String, double> instrumentParams;
  final List<MidiNote> midiNotes;
  final int row;
  final double timeMs;

  AudioTrack? _addedTrack;

  AddMidiClipAction({
    required this.addMidiClip,
    required this.tracks,
    required this.instrumentId,
    required this.instrumentName,
    required this.instrumentParams,
    required this.midiNotes,
    required this.row,
    required this.timeMs,
  });

  @override
  String get description => 'Add instrument clip';

  @override
  Future<void> redo() async {
    final beforeCount = tracks.length;
    await addMidiClip(
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      instrumentParams: Map<String, double>.from(instrumentParams),
      midiNotes: midiNotes.map((n) => n.copy()).toList(),
      row: row,
      timeMs: timeMs,
    );
    if (tracks.length > beforeCount) {
      _addedTrack = tracks.last;
    }
  }

  @override
  Future<void> undo() async {
    if (_addedTrack == null) return;
    final track = _addedTrack!;
    track.audioStartTimer?.cancel();
    final removed = tracks.remove(track);
    if (!removed && track.engineClipId >= 0) {
      final idx =
          tracks.indexWhere((t) => t.engineClipId == track.engineClipId);
      if (idx >= 0) tracks.removeAt(idx);
    }
    if (track.engineClipId >= 0) {
      await JuceAudioEngine.removeTrack(track.engineClipId);
    }
    _addedTrack = null;
  }
}

class PasteMidiClipAction extends EditorUndoAction {
  final Future<void> Function({
    required AudioTrack clip,
    required int row,
    required double timeMs,
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) pasteMidiClip;

  final List<AudioTrack> tracks;
  final AudioTrack clip;
  final int row;
  final double timeMs;
  final Duration? trimStart;
  final Duration? trimEnd;

  AudioTrack? _addedTrack;

  PasteMidiClipAction({
    required this.pasteMidiClip,
    required this.tracks,
    required this.clip,
    required this.row,
    required this.timeMs,
    this.trimStart,
    this.trimEnd,
  });

  @override
  String get description => 'Paste instrument clip';

  @override
  Future<void> redo() async {
    final beforeCount = tracks.length;
    await pasteMidiClip(
      clip: clip,
      row: row,
      timeMs: timeMs,
      trimStartRequested: trimStart,
      trimEndRequested: trimEnd,
    );
    if (tracks.length > beforeCount) {
      _addedTrack = tracks.last;
    }
  }

  @override
  Future<void> undo() async {
    if (_addedTrack == null) return;
    final track = _addedTrack!;
    track.audioStartTimer?.cancel();
    final removed = tracks.remove(track);
    if (!removed && track.engineClipId >= 0) {
      final idx =
          tracks.indexWhere((t) => t.engineClipId == track.engineClipId);
      if (idx >= 0) tracks.removeAt(idx);
    }
    if (track.engineClipId >= 0) {
      await JuceAudioEngine.removeTrack(track.engineClipId);
    }
    _addedTrack = null;
  }
}

class EditMidiClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;

  final List<MidiNote> oldNotes;
  final List<MidiNote> newNotes;
  final String oldInstrumentId;
  final String oldInstrumentName;
  final Map<String, double> oldInstrumentParams;
  final String newInstrumentId;
  final String newInstrumentName;
  final Map<String, double> newInstrumentParams;
  final Future<void> Function(
    AudioTrack clip,
    List<MidiNote> notes,
    String instrumentId,
    String instrumentName,
    Map<String, double> instrumentParams,
  ) applyToClip;

  EditMidiClipAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldNotes,
    required this.newNotes,
    required this.oldInstrumentId,
    required this.oldInstrumentName,
    required this.oldInstrumentParams,
    required this.newInstrumentId,
    required this.newInstrumentName,
    required this.newInstrumentParams,
    required this.applyToClip,
  });

  @override
  String get description => 'Edit MIDI clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    await applyToClip(
      clip,
      newNotes.map((n) => n.copy()).toList(),
      newInstrumentId,
      newInstrumentName,
      Map<String, double>.from(newInstrumentParams),
    );
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    await applyToClip(
      clip,
      oldNotes.map((n) => n.copy()).toList(),
      oldInstrumentId,
      oldInstrumentName,
      Map<String, double>.from(oldInstrumentParams),
    );
  }
}

class DeleteClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final AudioTrack clip;

  final Future<void> Function({
    required AudioTrack clip,
    required int row,
    required double timeMs,
    required Duration trimStartRequested,
    required Duration trimEndRequested,
  }) addTrack;

  final VoidCallback onChange;

  // snapshot
  // can deprecate all fields except clip, since all of them derive from clip anyways
  late final File file;
  late final int row;
  late final double timeMs;
  late final Duration trimStart;
  late final Duration trimEnd;

  DeleteClipAction({
    required this.tracks,
    required this.clip,
    required this.addTrack,
    required this.onChange,
  }) {
    file = clip.file;
    row = clip.rowIndex;
    timeMs = clip.offset * 1000.0;
    trimStart = clip.trimStart;
    trimEnd = clip.trimEnd;
  }

  @override
  String get description =>
      clip.isMidi ? 'Delete instrument clip' : 'Delete audio clip';

  @override
  Future<void> redo() async {
    int idx = tracks.indexOf(clip);
    if (idx < 0 && clip.engineClipId >= 0) {
      idx = tracks.indexWhere((t) => t.engineClipId == clip.engineClipId);
    }
    if (idx < 0) return;
    final existing = tracks[idx];

    existing.audioStartTimer?.cancel();
    tracks.removeAt(idx);
    if (existing.engineClipId >= 0) {
      await JuceAudioEngine.removeTrack(existing.engineClipId);
    }

    onChange();
  }

  @override
  Future<void> undo() async {
    await addTrack(
        clip: clip,
        row: row,
        timeMs: timeMs,
        trimStartRequested: trimStart,
        trimEndRequested: trimEnd);
    onChange();
  }
}

class TrimClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;

  final Duration oldTrimStart;
  final Duration oldTrimEnd;
  final double oldOffset;

  final Duration newTrimStart;
  final Duration newTrimEnd;
  final double? newOffset;

  final VoidCallback onChange;

  TrimClipAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldTrimStart,
    required this.oldTrimEnd,
    required this.oldOffset,
    required this.newTrimStart,
    required this.newTrimEnd,
    required this.newOffset,
    required this.onChange,
  });

  @override
  String get description => 'Trim audio clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.trimStart = newTrimStart;
    clip.trimEnd = newTrimEnd;
    if (newOffset != null) clip.offset = newOffset!;

    onChange();
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.trimStart = oldTrimStart;
    clip.trimEnd = oldTrimEnd;
    clip.offset = oldOffset;

    onChange();
  }
}

class MoveClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;

  final double oldOffset;
  final int oldRow;

  final double newOffset;
  final int newRow;

  final VoidCallback onChange;

  MoveClipAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldOffset,
    required this.oldRow,
    required this.newOffset,
    required this.newRow,
    required this.onChange,
  });

  @override
  String get description => 'Move audio clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.offset = newOffset;
    clip.rowIndex = newRow;
    onChange();
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.offset = oldOffset;
    clip.rowIndex = oldRow;
    onChange();
  }
}

class SetClipGainAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;
  final double oldGain;
  final double newGain;
  final void Function(AudioTrack clip, double gain) applyToState;

  SetClipGainAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldGain,
    required this.newGain,
    required this.applyToState,
  });

  @override
  String get description => 'Change clip gain';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null || clip.engineClipId < 0) return;
    await JuceAudioEngine.setClipGain(clip.engineClipId, newGain);
    applyToState(clip, newGain);
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null || clip.engineClipId < 0) return;
    await JuceAudioEngine.setClipGain(clip.engineClipId, oldGain);
    applyToState(clip, oldGain);
  }
}

class SetClipPitchAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;
  final double oldPitch;
  final double newPitch;
  final void Function(AudioTrack clip, double pitch) applyToState;

  SetClipPitchAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldPitch,
    required this.newPitch,
    required this.applyToState,
  });

  @override
  String get description => 'Change clip pitch';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null || clip.engineClipId < 0) return;
    await JuceAudioEngine.setClipPitch(clip.engineClipId, newPitch);
    applyToState(clip, newPitch);
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null || clip.engineClipId < 0) return;
    await JuceAudioEngine.setClipPitch(clip.engineClipId, oldPitch);
    applyToState(clip, oldPitch);
  }
}

class SetClipLabelAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;
  final String oldLabel;
  final String newLabel;
  final void Function(AudioTrack clip, String label) applyToState;

  SetClipLabelAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldLabel,
    required this.newLabel,
    required this.applyToState,
  });

  @override
  String get description => 'Rename clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    applyToState(clip, newLabel);
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    applyToState(clip, oldLabel);
  }
}

class SetRowGainAction extends EditorUndoAction {
  final int row;
  final double oldGain;
  final double newGain;
  final void Function(int row, double gain) applyToState;

  SetRowGainAction(
      {required this.row,
      required this.oldGain,
      required this.newGain,
      required this.applyToState});

  @override
  String get description => 'Change track gain';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setRowGain(row, newGain);
    applyToState(row, newGain);
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setRowGain(row, oldGain);
    applyToState(row, oldGain);
  }
}

class SetRowPanAction extends EditorUndoAction {
  final int row;
  final double oldPan;
  final double newPan;
  final void Function(int row, double pan) applyToState;

  SetRowPanAction(
      {required this.row,
      required this.oldPan,
      required this.newPan,
      required this.applyToState});

  @override
  String get description => 'Change track pan';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setRowPan(row, newPan);
    applyToState(row, newPan);
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setRowPan(row, oldPan);
    applyToState(row, oldPan);
  }
}

class SetMasterGainAction extends EditorUndoAction {
  final double oldGain;
  final double newGain;
  final void Function(double gain) applyToState;

  SetMasterGainAction(
      {required this.oldGain,
      required this.newGain,
      required this.applyToState});

  @override
  String get description => 'Change master gain';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setMasterGain(newGain);
    applyToState(newGain);
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setMasterGain(oldGain);
    applyToState(oldGain);
  }
}

class SetMasterPanAction extends EditorUndoAction {
  final double oldPan;
  final double newPan;
  final void Function(double pan) applyToState;

  SetMasterPanAction(
      {required this.oldPan, required this.newPan, required this.applyToState});

  @override
  String get description => 'Change master pan';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setMasterPan(newPan);
    applyToState(newPan);
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setMasterPan(oldPan);
    applyToState(oldPan);
  }
}

class SetAutomationPointsAction extends EditorUndoAction {
  final int row;
  final List<AutomationPoint> oldPoints;
  final List<AutomationPoint> newPoints;
  final void Function(int row, List<AutomationPoint> points) applyToState;

  SetAutomationPointsAction({
    required this.row,
    required List<AutomationPoint> oldPoints,
    required List<AutomationPoint> newPoints,
    required this.applyToState,
  })  : oldPoints = oldPoints
            .map((p) => AutomationPoint(x: p.x, volume: p.volume))
            .toList(),
        newPoints = newPoints
            .map((p) => AutomationPoint(x: p.x, volume: p.volume))
            .toList();

  @override
  String get description => 'Edit volume automation';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setTrackAutomationPoints(row, _toMaps(newPoints));
    applyToState(row, newPoints);
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setTrackAutomationPoints(row, _toMaps(oldPoints));
    applyToState(row, oldPoints);
  }
}

class BypassEffectAction extends EditorUndoAction {
  final int row;
  final int effectIndex;
  final bool oldState;
  final bool newState;
  final VoidCallback onChange;

  BypassEffectAction({
    required this.row,
    required this.effectIndex,
    required this.oldState,
    required this.newState,
    required this.onChange,
  });

  @override
  String get description => 'Bypass track effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.bypassRowEffect(row, effectIndex, newState);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.bypassRowEffect(row, effectIndex, oldState);
    onChange();
  }
}

class InsertEffectAction extends EditorUndoAction {
  final int row;
  final String pathOrName;
  final VoidCallback onChange;

  int? insertedIndex;

  InsertEffectAction(
      {required this.row, required this.pathOrName, required this.onChange});

  @override
  String get description => 'Insert track effect';

  @override
  Future<void> redo() async {
    final before = (await JuceAudioEngine.getTrackEffectsForRow(row)).length;

    await JuceAudioEngine.insertTrackEffect(row, pathOrName);

    final after = (await JuceAudioEngine.getTrackEffectsForRow(row)).length;

    if (after > before) {
      insertedIndex = after - 1;
    }

    onChange();
  }

  @override
  Future<void> undo() async {
    if (insertedIndex == null) return;

    await JuceAudioEngine.removeTrackEffect(row, insertedIndex!);
    onChange();
  }
}

class RemoveEffectAction extends EditorUndoAction {
  final int row;
  final int effectIndex;
  final String pathOrName;
  final VoidCallback onChange;

  RemoveEffectAction(
      {required this.row,
      required this.effectIndex,
      required this.pathOrName,
      required this.onChange});

  @override
  String get description => 'Remove track effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.removeTrackEffect(row, effectIndex);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.insertTrackEffect(row, pathOrName);
    await JuceAudioEngine.reorderTrackEffects(
      row,
      (await JuceAudioEngine.getTrackEffectsForRow(row)).length - 1,
      effectIndex,
    );
    onChange();
  }
}

class ReorderEffectAction extends EditorUndoAction {
  final int row;
  final int from;
  final int to;
  final VoidCallback onChange;

  ReorderEffectAction(
      {required this.row,
      required this.from,
      required this.to,
      required this.onChange});

  @override
  String get description => 'Reorder track effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.reorderTrackEffects(row, from, to);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.reorderTrackEffects(row, to, from);
    onChange();
  }
}

class InsertMasterEffectAction extends EditorUndoAction {
  final String pathOrName;
  final VoidCallback onChange;

  int? insertedIndex;

  InsertMasterEffectAction({required this.pathOrName, required this.onChange});

  @override
  String get description => 'Insert master effect';

  @override
  Future<void> redo() async {
    final before = (await JuceAudioEngine.getMasterEffects()).length;

    await JuceAudioEngine.insertMasterEffect(pathOrName);

    final after = (await JuceAudioEngine.getMasterEffects()).length;

    if (after > before) {
      insertedIndex = after - 1;
    }

    onChange();
  }

  @override
  Future<void> undo() async {
    if (insertedIndex == null) return;

    await JuceAudioEngine.removeMasterEffect(insertedIndex!);
    onChange();
  }
}

class RemoveMasterEffectAction extends EditorUndoAction {
  final int effectIndex;
  final String pathOrName;
  final VoidCallback onChange;

  RemoveMasterEffectAction(
      {required this.effectIndex,
      required this.pathOrName,
      required this.onChange});

  @override
  String get description => 'Remove master effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.removeMasterEffect(effectIndex);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.insertMasterEffect(pathOrName);
    await JuceAudioEngine.reorderMasterEffects(
        (await JuceAudioEngine.getMasterEffects()).length - 1, effectIndex);
    onChange();
  }
}

class ReorderMasterEffectAction extends EditorUndoAction {
  final int from;
  final int to;
  final VoidCallback onChange;

  ReorderMasterEffectAction(
      {required this.from, required this.to, required this.onChange});

  @override
  String get description => 'Reorder master effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.reorderMasterEffects(from, to);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.reorderMasterEffects(to, from);
    onChange();
  }
}

class BypassMasterEffectAction extends EditorUndoAction {
  final int effectIndex;
  final bool oldState;
  final bool newState;
  final VoidCallback onChange;

  BypassMasterEffectAction({
    required this.effectIndex,
    required this.oldState,
    required this.newState,
    required this.onChange,
  });

  @override
  String get description => 'Bypass master effect';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.bypassMasterEffect(effectIndex, newState);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.bypassMasterEffect(effectIndex, oldState);
    onChange();
  }
}

class SetEffectParamAction extends EditorUndoAction {
  final int row;
  final int effectIndex;
  final String paramId;
  final dynamic oldValue;
  final dynamic newValue;
  final VoidCallback onChange;

  SetEffectParamAction({
    required this.row,
    required this.effectIndex,
    required this.paramId,
    required this.oldValue,
    required this.newValue,
    required this.onChange,
  });

  @override
  String get description => 'Set track effect parameter';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setTrackEffect(row, effectIndex, paramId, newValue);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setTrackEffect(row, effectIndex, paramId, oldValue);
    onChange();
  }
}

class SetMasterEffectParamAction extends EditorUndoAction {
  final int effectIndex;
  final String paramId;
  final dynamic oldValue;
  final dynamic newValue;
  final VoidCallback onChange;

  SetMasterEffectParamAction({
    required this.effectIndex,
    required this.paramId,
    required this.oldValue,
    required this.newValue,
    required this.onChange,
  });

  @override
  String get description => 'Set master effect parameter';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.setMasterEffect(effectIndex, paramId, newValue);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.setMasterEffect(effectIndex, paramId, oldValue);
    onChange();
  }
}

// DEPRECATED: mute will not be counted as an undo action
class MuteRowAction extends EditorUndoAction {
  final int row;
  final bool oldState;
  final bool newState;
  final VoidCallback onChange;

  MuteRowAction(this.row, this.oldState, this.newState, this.onChange);

  @override
  String get description => 'Toggle mute row';

  @override
  Future<void> redo() async {
    await JuceAudioEngine.muteRow(row, newState);
    onChange();
  }

  @override
  Future<void> undo() async {
    await JuceAudioEngine.muteRow(row, oldState);
    onChange();
  }
}

class CompoundUndoAction extends EditorUndoAction {
  final String _description;
  final List<EditorUndoAction> actions;

  CompoundUndoAction(this._description, this.actions);

  @override
  String get description => _description;

  @override
  Future<void> redo() async {
    for (final a in actions) {
      await a.redo();
    }
  }

  @override
  Future<void> undo() async {
    for (final a in actions.reversed) {
      await a.undo();
    }
  }
}

// ----------------------------------------------------------------
// SNAPSHOT HISTORY
// ----------------------------------------------------------------

Future<RowEffectsSnapshot> captureRowSnapshot(int row) async {
  var effectIds = await JuceAudioEngine.getTrackEffectIdsForRow(row);
  final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
  if (effectIds.length != effects.length) {
    effectIds = List<String>.from(effects);
  }
  final snapshots = <EffectSnapshot>[];

  final count = effects.length;
  for (int i = 0; i < count; i++) {
    final params = await JuceAudioEngine.getTrackPluginParameters(row, i);
    final isBypassed = await JuceAudioEngine.getRowEffectBypassState(row, i);
    snapshots.add(EffectSnapshot(effectIds[i], isBypassed,
        {for (final p in params) p['name']: p['value']}));
  }

  return RowEffectsSnapshot(row, snapshots);
}

Future<void> _waitUntilAsync(
  Future<bool> Function() predicate, {
  int maxAttempts = 30,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (int i = 0; i < maxAttempts; i++) {
    if (await predicate()) return;
    await Future.delayed(step);
  }
}

Future<void> restoreRowSnapshot(RowEffectsSnapshot snap) async {
  // remove all
  final current = await JuceAudioEngine.getTrackEffectsForRow(snap.row);
  for (int i = current.length - 1; i >= 0; i--) {
    await JuceAudioEngine.removeTrackEffect(snap.row, i);
  }

  // reinsert + restore params
  for (int i = 0; i < snap.effects.length; i++) {
    final fx = snap.effects[i];
    await JuceAudioEngine.insertTrackEffect(snap.row, fx.effectId);
    bool inserted = false;
    await _waitUntilAsync(() async {
      final names = await JuceAudioEngine.getTrackEffectsForRow(snap.row);
      inserted = names.length > i;
      return inserted;
    }, maxAttempts: 8, step: const Duration(milliseconds: 80));
    if (!inserted) {
      debugPrint(
          "restoreRowSnapshot: failed to materialize row=${snap.row} fx=${fx.effectId} at index=$i");
      continue;
    }
    if (fx.params.isNotEmpty) {
      await _waitUntilAsync(() async {
        final params =
            await JuceAudioEngine.getTrackPluginParameters(snap.row, i);
        return params.isNotEmpty;
      }, maxAttempts: 8, step: const Duration(milliseconds: 80));
    }

    for (final e in fx.params.entries) {
      await JuceAudioEngine.setTrackEffect(snap.row, i, e.key, e.value);
    }

    if (fx.bypassed) {
      await JuceAudioEngine.bypassRowEffect(snap.row, i, true);
    }
  }
}

Future<MasterEffectsSnapshot> captureMasterSnapshot() async {
  var effectIds = await JuceAudioEngine.getMasterEffectIds();
  final effects = await JuceAudioEngine.getMasterEffects();
  if (effectIds.length != effects.length) {
    effectIds = List<String>.from(effects);
  }
  final snapshots = <EffectSnapshot>[];

  final count = effects.length;
  for (int i = 0; i < count; i++) {
    final params = await JuceAudioEngine.getMasterPluginParameters(i);
    final isBypassed = await JuceAudioEngine.getMasterEffectBypassState(i);
    snapshots.add(EffectSnapshot(effectIds[i], isBypassed,
        {for (final p in params) p['name']: p['value']}));
  }

  return MasterEffectsSnapshot(snapshots);
}

Future<void> restoreMasterSnapshot(MasterEffectsSnapshot snap) async {
  // remove all
  final current = await JuceAudioEngine.getMasterEffects();
  for (int i = current.length - 1; i >= 0; i--) {
    await JuceAudioEngine.removeMasterEffect(i);
  }

  // reinsert + restore params
  for (int i = 0; i < snap.effects.length; i++) {
    final fx = snap.effects[i];
    await JuceAudioEngine.insertMasterEffect(fx.effectId);
    bool inserted = false;
    await _waitUntilAsync(() async {
      final names = await JuceAudioEngine.getMasterEffects();
      inserted = names.length > i;
      return inserted;
    }, maxAttempts: 8, step: const Duration(milliseconds: 80));
    if (!inserted) {
      debugPrint(
          "restoreMasterSnapshot: failed to materialize fx=${fx.effectId} at index=$i");
      continue;
    }
    if (fx.params.isNotEmpty) {
      await _waitUntilAsync(() async {
        final params = await JuceAudioEngine.getMasterPluginParameters(i);
        return params.isNotEmpty;
      }, maxAttempts: 8, step: const Duration(milliseconds: 80));
    }

    for (final e in fx.params.entries) {
      await JuceAudioEngine.setMasterEffect(i, e.key, e.value);
    }

    if (fx.bypassed) {
      await JuceAudioEngine.bypassMasterEffect(i, true);
    }
  }
}

class TrackPresetChangeAction extends EditorUndoAction {
  final RowEffectsSnapshot before;
  final RowEffectsSnapshot after;
  final VoidCallback onChange;

  TrackPresetChangeAction(
      {required this.before, required this.after, required this.onChange});

  @override
  String get description => 'Load track preset';

  @override
  Future<void> redo() async {
    await restoreRowSnapshot(after);
    onChange();
  }

  @override
  Future<void> undo() async {
    await restoreRowSnapshot(before);
    onChange();
  }
}

class MasterPresetChangeAction extends EditorUndoAction {
  final MasterEffectsSnapshot before;
  final MasterEffectsSnapshot after;
  final VoidCallback onChange;

  MasterPresetChangeAction(
      {required this.before, required this.after, required this.onChange});

  @override
  String get description => 'Load master preset';

  @override
  Future<void> redo() async {
    await restoreMasterSnapshot(after);
    onChange();
  }

  @override
  Future<void> undo() async {
    await restoreMasterSnapshot(before);
    onChange();
  }
}

AudioTrack? _resolveClip(List<AudioTrack> tracks, int index) {
  if (index < 0 || index >= tracks.length) return null;
  return tracks[index];
}

Widget _chatIcon() {
  return Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withOpacity(0.14)),
    ),
    child: const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
  );
}

class _ChatBar extends StatelessWidget {
  final bool expanded;
  final bool hasText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTapBar;
  final VoidCallback onSubmit;

  const _ChatBar({
    super.key,
    required this.expanded,
    required this.hasText,
    required this.controller,
    required this.focusNode,
    required this.onTapBar,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final barHeight = _AudioEditorScreenState2._kChatBarFixedHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapBar,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: barHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white
                  .withOpacity(_AudioEditorScreenState2._kChatChromeOpacity),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: !expanded
                      ? Row(
                          children: [
                            _chatIcon(),
                            const SizedBox(width: 10),
                            const Text(
                              'Type...',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15.5,
                                height: 1.0,
                                color: Colors.white70,
                              ),
                              strutStyle: StrutStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                height: 1.0,
                                forceStrutHeight: true,
                              ),
                            ),
                          ],
                        )
                      : Material(
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 15,
                                      height: 1.0),
                                  strutStyle: const StrutStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 15,
                                    height: 1.0,
                                    forceStrutHeight: true,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Type...',
                                    hintStyle: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 15,
                                        height: 1.0),
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  textAlignVertical: TextAlignVertical.center,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => onSubmit(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: IgnorePointer(
                                  ignoring: !hasText,
                                  child: Opacity(
                                    opacity: hasText ? 1 : 0,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: onSubmit,
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E6EEB),
                                          shape: BoxShape.circle,
                                          border:
                                              Border.all(color: Colors.white24),
                                        ),
                                        child: const Icon(
                                          Icons.arrow_upward_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActionSummaryMessage extends TextMessage {
  ActionSummaryMessage({required String text})
      : super(
            id: const Uuid().v4(),
            authorId: 'system',
            createdAt: DateTime.now().toUtc(),
            text: text);
}

// NOTE: this is copied over from audio_timeline_pro.dart PrettyGainSlider. make sure no diffs
String _gainToDb(double sliderValue) {
  if (sliderValue <= 0.0001) return "–∞ dB";

  // Match your DSP: perceptualGain = sliderValue^2 (clamped to 9)
  double perceptual = math.min(sliderValue * sliderValue, 9.0);

  double db = 20 * math.log(perceptual) / math.log(10); // log10

  return db > 0
      ? "+${db.toStringAsFixed(1)} dB"
      : "${db.toStringAsFixed(1)} dB";
}

String panToText(double pan01) {
  // Clamp defensively (UI space)
  final p = pan01.clamp(0.0, 1.0);

  // Center is 0.5
  final signed = (p * 2.0) - 1.0; // -1..+1

  // Treat very small offsets as center
  if (signed.abs() < 0.02) {
    return 'Center';
  }

  final percent = (signed.abs() * 100).round();

  if (signed < 0) {
    return 'Left $percent%';
  } else {
    return 'Right $percent%';
  }
}

class _AssistantThinkingBubble extends StatefulWidget {
  @override
  State<_AssistantThinkingBubble> createState() =>
      _AssistantThinkingBubbleState();
}

class _AssistantThinkingBubbleState extends State<_AssistantThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _opacity = Tween(begin: 0.35, end: 0.85)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color.fromARGB(90, 170, 170, 170),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('•••',
            style: TextStyle(
                fontSize: 20, letterSpacing: 2, color: Colors.white70)),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final count = ((_c.value * 3).floor() + 1);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: i < count ? 1.0 : 0.25,
                child: const CircleAvatar(
                    radius: 3, backgroundColor: Colors.white70),
              ),
            ),
          ),
        );
      },
    );
  }
}

class RollingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration totalDuration;

  const RollingText({
    super.key,
    required this.text,
    required this.style,
    this.totalDuration = const Duration(milliseconds: 420),
  });

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  String _visible = '';
  int _index = 0;

  @override
  void initState() {
    super.initState();

    final text = widget.text;
    if (text.isEmpty) return;

    final steps = math.max(6, text.length ~/ 4); // chunked
    final interval = widget.totalDuration.inMilliseconds ~/ steps;

    Timer.periodic(Duration(milliseconds: interval), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _index = math.min(text.length, _index + (text.length ~/ steps));
      setState(() {
        _visible = text.substring(0, _index);
      });

      if (_index >= text.length) {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(_visible, style: widget.style);
  }
}

List<Map<String, dynamic>> _toMaps(List<AutomationPoint> points) {
  return points.map((p) => p.toMap()).toList();
}

class TrackGainStagingDbMeter extends StatelessWidget {
  final MeterFrame frame;
  final bool showClipIndicator;

  const TrackGainStagingDbMeter({
    super.key,
    required this.frame,
    this.showClipIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 1.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 20.0;
        return CustomPaint(
          size: Size(width, height),
          painter: _TrackGainStagingDbMeterPainter(
            frame,
            showClipIndicator: showClipIndicator,
          ),
        );
      },
    );
  }
}

class _TrackGainStagingDbMeterPainter extends CustomPainter {
  final MeterFrame f;
  final bool showClipIndicator;
  _TrackGainStagingDbMeterPainter(this.f, {required this.showClipIndicator});

  @override
  void paint(Canvas c, Size s) {
    const pad = 2.0;
    const laneGap = 2.0;
    const labelStripH = 8.0;

    final bg = Paint()..color = const Color(0xFF101622);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.12);

    final meterRect = Offset.zero & s;
    c.drawRect(meterRect, bg);
    c.drawRect(meterRect, border);

    final innerWidth = math.max(0.0, s.width - (pad * 2));
    final meterBottomY = math.max(pad, s.height - pad - labelStripH);
    final innerHeight = math.max(0.0, meterBottomY - pad);
    final laneHeight = math.max(0.0, (innerHeight - laneGap) / 2);

    final laneBgPaint = Paint()..color = Colors.white.withOpacity(0.07);
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    final peakPaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..strokeWidth = 1.2;
    final clipPaint = Paint()..color = const Color(0xFFFF6464);

    final dbTicks = [-36.0, -24.0, -12.0, -6.0, -3.0, 0.0];
    for (final db in dbTicks) {
      final amp = math.pow(10.0, db / 20.0).toDouble();
      final x = (pad + (amp.clamp(0.0, 1.0) * innerWidth));
      c.drawLine(Offset(x, pad), Offset(x, meterBottomY), tickPaint);
    }

    void drawLane({
      required double top,
      required double rms,
      required double peak,
    }) {
      final laneRect = Rect.fromLTWH(pad, top, innerWidth, laneHeight);
      c.drawRect(laneRect, laneBgPaint);

      final rmsNorm = rms.clamp(0.0, 1.0).toDouble();
      final peakNorm = peak.clamp(0.0, 1.0).toDouble();

      final rmsWidth = innerWidth * rmsNorm;
      if (rmsWidth > 0.0) {
        final rmsRect = Rect.fromLTWH(pad, top, rmsWidth, laneHeight);
        final gradient = const LinearGradient(
          colors: [Color(0xFF2EC96D), Color(0xFFF5C94D), Color(0xFFE55A5A)],
          stops: [0.0, 0.78, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );
        c.drawRect(
          rmsRect,
          Paint()..shader = gradient.createShader(laneRect),
        );
      }

      final peakX =
          (pad + (innerWidth * peakNorm)).clamp(pad, pad + innerWidth);
      c.drawLine(
        Offset(peakX, top),
        Offset(peakX, top + laneHeight),
        peakPaint,
      );
    }

    drawLane(top: pad, rms: f.rmsL, peak: f.peakL);
    drawLane(top: pad + laneHeight + laneGap, rms: f.rmsR, peak: f.peakR);

    final labelTicks = [-36.0, -24.0, -12.0, -6.0, 0.0];
    for (final db in labelTicks) {
      final amp = math.pow(10.0, db / 20.0).toDouble().clamp(0.0, 1.0);
      final x = pad + (innerWidth * amp);
      final text = db.toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.42),
            fontSize: 6.6,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final drawX = (x - tp.width / 2).clamp(pad, s.width - pad - tp.width);
      tp.paint(c, Offset(drawX, meterBottomY + 0.5));
    }

    if (showClipIndicator && f.clip) {
      c.drawCircle(Offset(s.width - 5, 5), 2.1, clipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackGainStagingDbMeterPainter oldDelegate) {
    return oldDelegate.f != f ||
        oldDelegate.showClipIndicator != showClipIndicator;
  }
}

class MiniStereoMeterHorizontal extends StatelessWidget {
  final MeterFrame frame;
  final double width;
  final double height;

  const MiniStereoMeterHorizontal({
    super.key,
    required this.frame,
    this.width = 120,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _MiniStereoMeterHorizontalPainter(frame),
    );
  }
}

class _MiniStereoMeterHorizontalPainter extends CustomPainter {
  final MeterFrame f;
  _MiniStereoMeterHorizontalPainter(this.f);

  @override
  void paint(Canvas c, Size s) {
    // ===== Background slot =====
    final bg = Paint()
      ..color = const Color(0xFF1A2230); // richer dark blue-gray

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.10);

    // NO rounding: clean rectangle
    final rect = Offset.zero & s;
    c.drawRect(rect, bg);
    c.drawRect(rect, border);

    // ===== Tick lines (scale feel) =====
    final tick = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final x = s.width * (i / 5.0);
      c.drawLine(
        Offset(x, 1),
        Offset(x, s.height - 1),
        tick,
      );
    }

    // ===== Meter paints =====
    final peakPaint = Paint()..color = Colors.white.withOpacity(0.80);
    final rmsPaint = Paint()..color = Colors.white.withOpacity(0.22);

    // Idle floor prevents dead-empty look
    const idleFloor = 0.015;

    double wFor(double v) => ((v + idleFloor).clamp(0.0, 1.0)) * s.width;

    // Split into two lanes
    const laneGap = 1.0;
    final laneH = (s.height - laneGap) / 2.0;

    Rect laneRect(int laneIdx) {
      final top = laneIdx == 0 ? 0.0 : laneH + laneGap;
      return Rect.fromLTWH(0, top, s.width, laneH);
    }

    // ===== Left lane (Top) =====
    final topLane = laneRect(0);

    final lRmsW = wFor(f.rmsL);
    final lPeakW = wFor(f.peakL);

    c.drawRect(
      Rect.fromLTWH(topLane.left, topLane.top, lRmsW, topLane.height),
      rmsPaint,
    );
    c.drawRect(
      Rect.fromLTWH(topLane.left, topLane.top, lPeakW, topLane.height),
      peakPaint,
    );

    // ===== Right lane (Bottom) =====
    final botLane = laneRect(1);

    final rRmsW = wFor(f.rmsR);
    final rPeakW = wFor(f.peakR);

    c.drawRect(
      Rect.fromLTWH(botLane.left, botLane.top, rRmsW, botLane.height),
      rmsPaint,
    );
    c.drawRect(
      Rect.fromLTWH(botLane.left, botLane.top, rPeakW, botLane.height),
      peakPaint,
    );

    // ===== Clip indicator (optional) =====
    // if (f.clip) {
    //   final clipPaint = Paint()..color = const Color(0xFFFF4A4A);

    //   // Small square light (pro look)
    //   c.drawRect(
    //     Rect.fromLTWH(s.width - 6, 2, 4, 4),
    //     clipPaint,
    //   );
    // }
  }

  @override
  bool shouldRepaint(covariant _MiniStereoMeterHorizontalPainter old) {
    return old.f != f;
  }
}
