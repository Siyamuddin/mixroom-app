import 'dart:async';
import 'dart:collection';
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
import 'package:mixroom/helpers/halo.dart';
import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/models/mixing_result.dart';
import 'package:mixroom/screens/audio_timeline_pro.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../helpers/youtube_upload.dart';
import 'package:mixroom/models/models.dart';
// import 'package:mixroom/chat/_old_chat_screen.dart';
import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/ai/ai_debug.dart';
import 'package:mixroom/ai/chat_pipeline.dart';
import 'package:mixroom/ai/spleeter_stem_separator.dart';
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
import 'package:mixroom/helpers/export_save_dialog.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/helpers/project_manager.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/subscription_service.dart';
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
import 'package:mixroom/models/subscription_models.dart';
import 'package:mixroom/widgets/effects_panel.dart';
import 'package:mixroom/widgets/piano_roll_editor.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:record/record.dart';
import 'package:mixroom/widgets/sample_browser_panel.dart';
import 'package:mixroom/widgets/export_success_preview_player.dart';

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

const List<Map<String, dynamic>> kBundledSfzFallbackCatalog = [
  {
    'id': 'sfz.vsco.violin_ens_sus_vib',
    'name': 'Violin Ensemble Sustain Vibrato',
    'category': 'instrument',
    'pickerCategory': 'Strings',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/ViolinEnsSusVib.sfz',
    'outputGain': 0.72,
    'attackMs': 8.0,
    'releaseMs': 620.0,
  },
  {
    'id': 'sfz.vsco.cello_ens_sus_vib',
    'name': 'Cello Ensemble Sustain Vibrato',
    'category': 'instrument',
    'pickerCategory': 'Strings',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/CelloEnsSusVib.sfz',
    'outputGain': 0.74,
    'attackMs': 8.0,
    'releaseMs': 680.0,
  },
  {
    'id': 'sfz.vsco.trumpet_sus',
    'name': 'Trumpet Sustain',
    'category': 'instrument',
    'pickerCategory': 'Brass',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/TrumpetSus.sfz',
    'outputGain': 0.68,
    'attackMs': 6.0,
    'releaseMs': 420.0,
  },
  {
    'id': 'sfz.vsco.fhorn_sus',
    'name': 'French Horn Sustain',
    'category': 'instrument',
    'pickerCategory': 'Brass',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/FHornSus.sfz',
    'outputGain': 0.68,
    'attackMs': 7.0,
    'releaseMs': 460.0,
  },
  {
    'id': 'sfz.vsco.flute_sus_vib',
    'name': 'Flute Sustain Vibrato',
    'category': 'instrument',
    'pickerCategory': 'Woodwinds',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/FluteSusVib.sfz',
    'outputGain': 0.66,
    'attackMs': 4.0,
    'releaseMs': 380.0,
  },
  {
    'id': 'sfz.vsco.clarinet_sus',
    'name': 'Clarinet Sustain',
    'category': 'instrument',
    'pickerCategory': 'Woodwinds',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/ClarinetSus.sfz',
    'outputGain': 0.68,
    'attackMs': 5.0,
    'releaseMs': 420.0,
  },
  {
    'id': 'sfz.vsco.organ_quiet',
    'name': 'Organ Quiet',
    'category': 'instrument',
    'pickerCategory': 'Keys',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/OrganQuiet.sfz',
    'outputGain': 0.58,
    'attackMs': 2.0,
    'releaseMs': 280.0,
  },
  {
    'id': 'sfz.vsco.organ_loud',
    'name': 'Organ Loud',
    'category': 'instrument',
    'pickerCategory': 'Keys',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/OrganLoud.sfz',
    'outputGain': 0.56,
    'attackMs': 2.0,
    'releaseMs': 260.0,
  },
  {
    'id': 'sfz.vsco.marimba',
    'name': 'Marimba',
    'category': 'instrument',
    'pickerCategory': 'Percussion',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/Marimba.sfz',
    'outputGain': 0.74,
    'attackMs': 2.0,
    'releaseMs': 520.0,
  },
  {
    'id': 'sfz.vsco.glockenspiel',
    'name': 'Glockenspiel',
    'category': 'instrument',
    'pickerCategory': 'Percussion',
    'sourceProject': 'VSCO-2 CE',
    'sourceLicense': 'See bundled LICENSE',
    'isSampled': true,
    'sfzAssetPath': 'assets/instruments/VSCO-2-CE-1.1.0/Glockenspiel.sfz',
    'outputGain': 0.82,
    'attackMs': 2.0,
    'releaseMs': 820.0,
  },
];

class _SfzRegion {
  const _SfzRegion({
    required this.sampleAssetPath,
    required this.loKey,
    required this.hiKey,
    required this.keyCenter,
    required this.loVel,
    required this.hiVel,
    required this.gainLinear,
    required this.attackSec,
    required this.releaseSec,
  });

  final String sampleAssetPath;
  final int loKey;
  final int hiKey;
  final int keyCenter;
  final int loVel;
  final int hiVel;
  final double gainLinear;
  final double attackSec;
  final double releaseSec;
}

class _SfzDefinition {
  const _SfzDefinition({
    required this.sfzAssetPath,
    required this.regions,
    required this.defaultAttackSec,
    required this.defaultReleaseSec,
  });

  final String sfzAssetPath;
  final List<_SfzRegion> regions;
  final double defaultAttackSec;
  final double defaultReleaseSec;
}

class _SfzParsedLine {
  const _SfzParsedLine({
    this.blockTag,
    this.opcodes = const <String, String>{},
  });

  final String? blockTag;
  final Map<String, String> opcodes;
}

class _DecodedStereoPcm {
  const _DecodedStereoPcm({
    required this.sampleRate,
    required this.left,
    required this.right,
  });

  final int sampleRate;
  final Float32List left;
  final Float32List right;

  int get frameCount => math.min(left.length, right.length);
}

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

class _InputChannelRouteOption {
  final int channelStart;
  final int channelCount;

  const _InputChannelRouteOption({
    required this.channelStart,
    required this.channelCount,
  });

  String get label {
    if (channelCount <= 1) {
      return 'Mono ${channelStart + 1}';
    }
    return 'Stereo ${channelStart + 1}+${channelStart + channelCount}';
  }
}

class _AutomationTargetMeta {
  final String targetId;
  final String label;
  final int effectIndex; // -1 = row volume
  final String paramId;
  final String type; // float|bool|choice
  final double min;
  final double max;
  final double initialNormalized;

  const _AutomationTargetMeta({
    required this.targetId,
    required this.label,
    required this.effectIndex,
    required this.paramId,
    required this.type,
    required this.min,
    required this.max,
    this.initialNormalized = 0.5,
  });

  bool get isVolume => targetId == 'volume';

  Map<String, dynamic> toUiMap() => <String, dynamic>{
        'id': targetId,
        'label': label,
        'isVolume': isVolume,
        'effectIndex': effectIndex,
        'paramId': paramId,
        'type': type,
        'min': min,
        'max': max,
        'initialNormalized': initialNormalized.clamp(0.0, 1.0),
      };

  AutomationLaneSnapshot toLaneSnapshot(List<AutomationPoint> points) {
    return AutomationLaneSnapshot(
      targetId: targetId,
      label: label,
      effectIndex: effectIndex,
      paramId: paramId,
      type: type,
      min: min,
      max: max,
      points: points.map((p) => p.copy()).toList(growable: false),
    );
  }

  static _AutomationTargetMeta fromLaneSnapshot(AutomationLaneSnapshot lane) {
    final laneInitial = lane.points.isNotEmpty
        ? lane.points.first.volume.clamp(0.0, 1.0).toDouble()
        : (lane.targetId == 'volume' ? 0.75 : 0.5);
    return _AutomationTargetMeta(
      targetId: lane.targetId,
      label: lane.label,
      effectIndex: lane.effectIndex,
      paramId: lane.paramId,
      type: lane.type,
      min: lane.min,
      max: lane.max,
      initialNormalized: laneInitial,
    );
  }
}

class _ParsedAutomationTargetId {
  final bool isVolume;
  final int legacyEffectIndex;
  final String effectKey;
  final String paramId;

  const _ParsedAutomationTargetId({
    required this.isVolume,
    required this.legacyEffectIndex,
    required this.effectKey,
    required this.paramId,
  });
}

class _ClipMono16kSegment {
  final Float32List samples;
  final int sampleRate;
  final double timelineStartMs;
  final double timelineEndMs;
  final double timelineMsPerLocalMs;

  const _ClipMono16kSegment({
    required this.samples,
    required this.sampleRate,
    required this.timelineStartMs,
    required this.timelineEndMs,
    required this.timelineMsPerLocalMs,
  });
}

enum AudioEditorInitialAction { exportWav, exportMp3 }

class _EditorLayoutSpec {
  final EdgeInsets topBarPadding;
  final double topBarBottomGap;
  final double topBarClusterGap;
  final double topBarActionButtonSize;

  const _EditorLayoutSpec({
    required this.topBarPadding,
    required this.topBarBottomGap,
    required this.topBarClusterGap,
    required this.topBarActionButtonSize,
  });

  factory _EditorLayoutSpec.fromSize(Size size) {
    final isDesktop = PlatformCapabilities.current.isDesktop;
    final width = size.width;
    final scale = isDesktop
        ? (width >= 1900
            ? 1.26
            : width >= 1600
                ? 1.16
                : width >= 1360
                    ? 1.08
                    : 1.0)
        : 1.0;
    return _EditorLayoutSpec(
      topBarPadding: EdgeInsets.fromLTRB(
        16.0 * scale,
        12.0 * scale,
        16.0 * scale,
        8.0 * scale,
      ),
      topBarBottomGap: isDesktop ? 14.0 : 12.0,
      topBarClusterGap: 10.0 * scale,
      topBarActionButtonSize: 48.0 * scale,
    );
  }
}

class AudioEditorScreen extends StatefulWidget {
  final String mode;
  final Directory projectDir;
  final bool? isProEntitled;
  final AudioEditorInitialAction? initialAction;

  const AudioEditorScreen(
      {Key? key,
      required this.mode,
      required this.projectDir,
      this.isProEntitled,
      this.initialAction})
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

  bool _subscriptionCapabilityOrLegacy(String capability) {
    try {
      return context.read<SubscriptionService>().canUseCapability(capability);
    } catch (_) {
      return widget.mode == 'Pro';
    }
  }

  bool get _isProEntitled {
    final explicit = widget.isProEntitled;
    if (explicit != null) return explicit;
    return _subscriptionCapabilityOrLegacy(SubscriptionCapability.proEditor);
  }

  String get _resolvedMode => _isProEntitled ? "Pro" : "Basic";
  PlatformCapabilities _platformCapabilities = PlatformCapabilities.current;

  bool get _desktopNativeWavOnlyExport =>
      _platformCapabilities.desktopNativeWavOnlyExport;

  static const MethodChannel _edgeGesturesChannel =
      MethodChannel('mixroom/edge_gestures');
  static void _noopRefreshRowFx(int row) {}

  late Directory _projectDir;
  String _projectName = "Untitled Project";
  bool _everSaved = false;
  bool _loadedOnce = false;
  bool _handledInitialAction = false;

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
  Duration _lastTransportUiNotifyElapsed = Duration.zero;
  Duration _lastFxPlaybackRefreshElapsed = Duration.zero;
  Duration _transportPlayStartSyncGraceUntil = Duration.zero;
  Duration _transportEndCheckGraceUntil = Duration.zero;
  double _lastTransportSampleSeconds = 0.0;
  double _transportRateSecPerSec = 0.0;
  Ticker? _transportTicker;
  final ValueNotifier<Duration> _transportClock = ValueNotifier(Duration.zero);
  static const Duration _kTransportPollInterval = Duration(milliseconds: 50);
  static const Duration _kTransportPlayStartSyncGrace =
      Duration(milliseconds: 180);
  static const Duration _kTransportUiNotifyInterval = Duration.zero;
  static const Duration _kTransportMaxExtrapolation =
      Duration(milliseconds: 120);
  static const Duration _kFxPlaybackRefreshInterval =
      Duration(milliseconds: 90);

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
  List<int> _timelineSelectedClipIndices = const <int>[];
  int _timelinePrimarySelectedClipIndex = -1;

  void _setGlobalAudioClock(Duration value, {bool forceNotify = false}) {
    if (_globalAudioClock == value && _transportClock.value == value) {
      return;
    }
    _globalAudioClock = value;
    final now = _transportUiStopwatch.elapsed;
    final elapsedSinceUiNotify = now - _lastTransportUiNotifyElapsed;
    final bool shouldNotify = forceNotify ||
        !_isPlaying ||
        elapsedSinceUiNotify >= _kTransportUiNotifyInterval;
    if (!shouldNotify) return;
    _lastTransportUiNotifyElapsed = now;
    if (_transportClock.value != value) _transportClock.value = value;
  }

  void _syncTransportClock(Duration value, {required bool playing}) {
    final now = _transportUiStopwatch.elapsed;
    _lastTransportSampleSeconds = value.inMilliseconds / 1000.0;
    _lastTransportSampleElapsed = now;
    _lastTransportPollElapsed = now;
    _transportRateSecPerSec = playing ? 1.0 : 0.0;
    _setGlobalAudioClock(value, forceNotify: true);
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
      final suppressImmediateSnap = _isPlaying &&
          !force &&
          sampleElapsed < _transportPlayStartSyncGraceUntil;
      if (!suppressImmediateSnap) {
        _setGlobalAudioClock(Duration(milliseconds: (t * 1000.0).round()));
      }
    } catch (_) {
      // Ignore transient bridge errors; next poll will recover.
    } finally {
      _transportPollBusy = false;
    }
  }

  void _refreshFxUiForPlaybackTick() {
    if (!_isPlaying) return;
    final now = _transportUiStopwatch.elapsed;
    if (now - _lastFxPlaybackRefreshElapsed < _kFxPlaybackRefreshInterval) {
      return;
    }
    _lastFxPlaybackRefreshElapsed = now;
    for (int row = 0; row < _rowCount; row++) {
      _refreshRowFxPlayback(row);
    }
  }

  // === Recording state (Dart-only, no JUCE) ===
  final AudioRecorder _micRecorder = AudioRecorder();

  bool _isRecording = false;
  bool _isMidiClipRecording = false;
  double _recordingStartMs = 0; // project time where the recording starts
  String? _recordingFilePath; // temp recorded file (m4a/wav/etc)
  Timer? _recordingPeakTimer;
  Timer? _midiInputPollTimer;
  int? _midiRecordingClipEngineId;
  bool _midiInputDrainBusy = false;
  int _nextMidiRecordNoteToken = 0;
  double _lastMidiRecordTransportSec = 0.0;
  bool _midiRecordHasChanges = false;
  final Map<String, List<MidiNote>> _midiHeldNotesByKey =
      <String, List<MidiNote>>{};

  // for live preview waveform
  List<double> _recordingPeaks = []; // 0..1 peaks while recording
  StreamSubscription<Amplitude>? _amplitudeSub;

  // so keeping this local state might be unnecessary (and cause a factor of drift from source of truth which is JUCE) (maybe consider removing?)
  final List<double> _rowPan = [];
  final List<double> _rowGain = [];
  static const double _kGainUiMin = 0.0;
  static const double _kGainUiMax = 3.0;
  static const double _kGainDbMin = -60.0;
  static const double _kGainDbMax = 6.0;
  static const double _kGainUiUnity = 2.0;
  static const double _kLegacyLinearGainUiUnity = 2.727272727272727;
  final Map<int, _ClipStretchSnapshot> _pendingStretchUndoByClip =
      <int, _ClipStretchSnapshot>{};
  final List<List<AutomationPoint>> _rowVolumeAutomation = [];
  final Map<int, Map<String, List<AutomationPoint>>> _rowPluginAutomation =
      <int, Map<String, List<AutomationPoint>>>{};
  final Map<int, Map<String, List<AutomationClipSnapshot>>>
      _rowAutomationClips = <int, Map<String, List<AutomationClipSnapshot>>>{};
  final Map<int, Map<String, _AutomationTargetMeta>> _rowAutomationTargets =
      <int, Map<String, _AutomationTargetMeta>>{};
  final Map<int, String> _rowSelectedAutomationTarget = <int, String>{};
  final Map<String, double> _lastAppliedAutomationNormalized =
      <String, double>{};
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
  Timer? _midiDevicePollTimer;
  bool _midiDevicePollBusy = false;
  Map<String, String> _knownMidiDevicesById = <String, String>{};
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
  double _masterGain = _kGainUiUnity;
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

  bool _loadingDevices = false;

  bool _metronomeEnabled = false;
  double _metronomeVolume = 0.5; // 0–1

  final EditorUndoManager _undoManager = EditorUndoManager(maxHistory: 5);

  bool _chatExpanded = false;
  bool _chatInputActive = false;
  bool _chatHasText = false;
  final TextEditingController _chatTextController = TextEditingController();
  late final InstrumentClassifier _classifier;
  late final SpleeterStemSeparator _spleeterStemSeparator;
  final FocusNode _chatFocusNode = FocusNode();
  late final ChatPipeline _chatPipeline;
  late final MixingMagnitudePredictor _magnitudePredictor;
  Future<void>? _aiModelsWarmupFuture;
  late final ProducerDataCollector _producerCollector;
  bool _producerDataMode = false;
  bool _showProducerCaptureUi = false;
  bool _producerUiBusy = false;
  late final ChatController _chatController;
  void Function(int row) _refreshRowFx = _noopRefreshRowFx;
  void Function(int row) _refreshRowFxPlayback = _noopRefreshRowFx;
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
  List<Map<String, dynamic>> _instrumentCatalog = kBundledSfzFallbackCatalog
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: true);
  bool _instrumentCatalogReady = false;
  final Map<String, _SfzDefinition> _sfzDefinitionCache =
      <String, _SfzDefinition>{};
  final LinkedHashMap<String, _DecodedStereoPcm> _sfzSampleCache =
      LinkedHashMap<String, _DecodedStereoPcm>();
  static const int _kMaxSfzSampleCacheEntries = 10;

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
    final dialogSetState = _projectSettingsStateSetter;
    if (dialogSetState != null) {
      // While the settings dialog is open, avoid rebuilding the whole editor
      // tree for each control change. Refresh only the dialog subtree.
      updater();
      dialogSetState(() {});
      return;
    }
    setState(updater);
  }

  String _sanitizeInstrumentIdToken(String raw) {
    final lower = raw.toLowerCase();
    final collapsed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _prettyInstrumentNameFromSfzPreset(String presetFileName) {
    var stem = presetFileName.trim();
    if (stem.toLowerCase().endsWith('.sfz')) {
      stem = stem.substring(0, stem.length - 4);
    }
    stem = stem.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    stem = stem.replaceAll(RegExp(r'[_\-]+'), ' ');
    stem = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (stem.isEmpty) return 'Instrument';
    return stem
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _normalizePickerCategory(String raw) {
    final key = raw.trim().toLowerCase();
    switch (key) {
      case 'strings':
        return 'Strings';
      case 'brass':
        return 'Brass';
      case 'woodwinds':
        return 'Woodwinds';
      case 'keys':
        return 'Keys';
      case 'percussion':
        return 'Percussion';
      case 'drum':
      case 'drums':
        return 'Drums';
      default:
        return 'Other';
    }
  }

  Map<String, dynamic> _defaultInstrumentSpec() {
    if (_instrumentCatalog.isNotEmpty) return _instrumentCatalog.first;
    if (kBundledSfzFallbackCatalog.isNotEmpty) {
      return Map<String, dynamic>.from(kBundledSfzFallbackCatalog.first);
    }
    return Map<String, dynamic>.from(kInstrumentCatalog.first);
  }

  bool _isSampledInstrumentSpec(Map<String, dynamic> spec) {
    if (spec['isSampled'] == true) return true;
    final id = (spec['id'] as String? ?? '').toLowerCase();
    return id.startsWith('sfz.');
  }

  bool _isSampledInstrumentId(String instrumentId) {
    final id = instrumentId.trim().toLowerCase();
    if (id.startsWith('sfz.') || id.startsWith('sfz_asset:')) return true;
    final spec = _findInstrumentSpecById(instrumentId);
    if (spec == null) return false;
    return _isSampledInstrumentSpec(spec);
  }

  Future<void> _loadBundledInstrumentCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/instruments/index.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final pack = (decoded['pack'] as String?)?.trim();
      final presets = decoded['presets'];
      if (presets is! List) {
        return;
      }

      final loaded = <Map<String, dynamic>>[];
      for (final entry in presets) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        final presetFile = (map['preset'] as String?)?.trim() ?? '';
        if (presetFile.isEmpty) continue;
        final categoryRaw = (map['category'] as String?) ?? '';
        final pickerCategory = _normalizePickerCategory(categoryRaw);
        final displayName = (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : _prettyInstrumentNameFromSfzPreset(presetFile);
        final defaultOutputGain = pickerCategory == 'Drums' ? 0.84 : 0.72;
        final defaultAttackMs = pickerCategory == 'Drums' ? 2.0 : 6.0;
        final defaultReleaseMs = pickerCategory == 'Drums' ? 320.0 : 520.0;
        final idToken = _sanitizeInstrumentIdToken(
            '${pack ?? 'sfz'}_${presetFile.replaceAll('.sfz', '')}');
        loaded.add(<String, dynamic>{
          'id': 'sfz.$idToken',
          'name': displayName,
          'category': 'instrument',
          'pickerCategory': pickerCategory,
          'sourceProject': pack ?? 'Bundled SFZ',
          'sourceLicense': 'See bundled LICENSE',
          'isSampled': true,
          'sfzAssetPath': 'assets/instruments/${pack ?? ''}/$presetFile',
          'outputGain':
              ((map['outputGain'] as num?)?.toDouble() ?? defaultOutputGain)
                  .clamp(0.2, 2.0),
          'attackMs': ((map['attackMs'] as num?)?.toDouble() ?? defaultAttackMs)
              .clamp(0.0, 2400.0),
          'releaseMs':
              ((map['releaseMs'] as num?)?.toDouble() ?? defaultReleaseMs)
                  .clamp(20.0, 3600.0),
        });
      }

      if (loaded.isEmpty) {
        return;
      }
      if (!mounted) {
        _instrumentCatalog = loaded;
        _instrumentCatalogReady = true;
        return;
      }
      setState(() {
        _instrumentCatalog = loaded;
        _instrumentCatalogReady = true;
      });
    } catch (_) {
      if (_instrumentCatalogReady) return;
      if (!mounted) {
        _instrumentCatalog = kBundledSfzFallbackCatalog
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true);
        _instrumentCatalogReady = true;
        return;
      }
      setState(() {
        _instrumentCatalog = kBundledSfzFallbackCatalog
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true);
        _instrumentCatalogReady = true;
      });
    }
  }

  void _syncRowLocalStateToRowCount() {
    while (_rowPan.length < _rowCount) {
      final nextRow = _rowPan.length;
      _rowPan.add(0.5);
      _rowGain.add(_kGainUiUnity);
      _rowVolumeAutomation.add([AutomationPoint(x: 0.0, volume: 0.75)]);
      _rowPluginAutomation[nextRow] = <String, List<AutomationPoint>>{};
      _rowAutomationClips[nextRow] = <String, List<AutomationClipSnapshot>>{};
      _rowAutomationTargets[nextRow] = <String, _AutomationTargetMeta>{
        'volume': _volumeAutomationTargetMeta(),
      };
      _rowSelectedAutomationTarget[nextRow] = 'volume';
      _rowMuted.add(false);
      _rowSoloed.add(false);
      _rowMuteApplied.add(null);
      _rowExpanded.add(false);
      _rowGainSnapshot.add(_kGainUiUnity);
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

    _rowPluginAutomation.removeWhere((row, _) => row < 0 || row >= _rowCount);
    _rowAutomationClips.removeWhere((row, _) => row < 0 || row >= _rowCount);
    _rowAutomationTargets.removeWhere((row, _) => row < 0 || row >= _rowCount);
    _rowSelectedAutomationTarget
        .removeWhere((row, _) => row < 0 || row >= _rowCount);

    for (int row = 0; row < _rowCount; row++) {
      _rowPluginAutomation.putIfAbsent(
          row, () => <String, List<AutomationPoint>>{});
      _rowAutomationClips.putIfAbsent(
          row, () => <String, List<AutomationClipSnapshot>>{});
      _rowAutomationTargets.putIfAbsent(
          row,
          () => <String, _AutomationTargetMeta>{
                'volume': _volumeAutomationTargetMeta(),
              });
      _rowSelectedAutomationTarget.putIfAbsent(row, () => 'volume');
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

  Future<void> _refreshPlatformCapabilities() async {
    final capabilities = await PlatformCapabilities.refresh();
    if (!mounted) return;
    setState(() {
      _platformCapabilities = capabilities;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_setIOSSystemGestureDeferral(true));
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPlatformCapabilities());
    // prewarmFFT(); // so that AI sync first run is not heavy (this was for video/audio sync)

    _transportTicker = Ticker((_) {
      if (!_isPlaying) return;
      _setGlobalAudioClock(_estimateTransportClockFromSample());
      unawaited(_pollTransportFromJuceIfNeeded());
      _refreshFxUiForPlaybackTick();

      // ===== END / LOOP LOGIC (same as before) =====
      final endPoint = Duration(
        milliseconds: math.max(_audioOnlyOverallDuration.inMilliseconds,
            msFor128Bars(_tempo).toInt()),
      );
      final withinEndGuard =
          _transportUiStopwatch.elapsed < _transportEndCheckGraceUntil;

      final reachedEnd = _globalAudioClock >= endPoint;
      final reachedLoopEnd = _loopEnabled &&
          _globalAudioClock >= Duration(milliseconds: _loopEndMs);

      if (reachedLoopEnd && !withinEndGuard) {
        if (_isRecording) {
          _transportTicker?.stop();
          _stopRecordingJuce(keepPlaying: false);
          return;
        }
        unawaited(_restartAudio(_safeAudioEditorStateSetter));
        unawaited(_togglePlayPauseAudio(_safeAudioEditorStateSetter));
        return;
      }

      if (reachedEnd && !withinEndGuard) {
        if (_isRecording) return;
        unawaited(_togglePlayPauseAudio(_safeAudioEditorStateSetter));
      }
    });

    _projectDir = widget.projectDir;

    _classifier = InstrumentClassifier();
    _spleeterStemSeparator = SpleeterStemSeparator();
    // Warm model availability early so stem separation doesn't block on first tap.
    unawaited(_spleeterStemSeparator.prewarm(includeSession: false));
    // _classifier.debugLog = (msg) {
    //   print('msg: $msg');
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text(msg),
    //       duration: const Duration(seconds: 3),
    //     ),
    //   );
    // };
    // Defer AI model loads until AI features are actually used.
    _producerCollector = ProducerDataCollector();
    _producerCollector.setEnabled(_producerDataMode);
    _magnitudePredictor = kUseLearnedMagnitudePredictor
        ? OnnxMixingMagnitudePredictor(
            enabled: true,
            applyModelAsset: kMixApplyClassifierAsset,
            magnitudeModelAsset: kMixMagnitudeRegressorAsset,
          )
        : const NoopMixingMagnitudePredictor();

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
      await _loadBundledInstrumentCatalog();
      _liveMidiEventPlaybackSupported =
          await JuceAudioEngine.supportsLiveMidiClipPlayback();
      if (_liveMidiEventPlaybackSupported) {
        _startMidiDeviceConnectionPolling();
      }
      await _reloadRowsFromEngine();
      await _loadProjectIfAny();
      setState(() => _isLoadingNextScreen = false);
      await _runInitialActionIfNeeded();
    });
  }

  Future<void> _runInitialActionIfNeeded() async {
    if (_handledInitialAction || !mounted) return;
    final action = widget.initialAction;
    if (action == null) return;
    _handledInitialAction = true;

    final nextFormat = action == AudioEditorInitialAction.exportMp3
        ? _ExportAudioFormat.mp3
        : _ExportAudioFormat.wav;
    final current = _audioExportSettings;
    setState(() {
      _audioExportSettings = _AudioExportSettings(
        format: nextFormat,
        sampleRate: current.sampleRate,
        wavBitDepth: current.wavBitDepth,
        wavDithering: current.wavDithering,
        mp3BitrateKbps: current.mp3BitrateKbps,
        mp3Mode: current.mp3Mode,
        mp3VbrQuality: current.mp3VbrQuality,
        channelMode: current.channelMode,
        normalize: current.normalize,
        normalizeTargetDb: current.normalizeTargetDb,
        resampleQuality: current.resampleQuality,
      );
    });

    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _exportAndNavigate();
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
    final oldPluginAutomationById = <int, Map<String, List<AutomationPoint>>>{};
    final oldAutomationClipsById =
        <int, Map<String, List<AutomationClipSnapshot>>>{};
    final oldAutomationTargetsById =
        <int, Map<String, _AutomationTargetMeta>>{};
    final oldSelectedAutomationTargetById = <int, String>{};
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
      if (_rowPluginAutomation.containsKey(i)) {
        oldPluginAutomationById[id] = _rowPluginAutomation[i]!.map(
          (key, value) =>
              MapEntry(key, value.map((p) => p.copy()).toList(growable: false)),
        );
      }
      if (_rowAutomationClips.containsKey(i)) {
        oldAutomationClipsById[id] = _rowAutomationClips[i]!.map(
          (key, value) => MapEntry(
            key,
            value.map((c) => c.copyWith()).toList(growable: false),
          ),
        );
      }
      if (_rowAutomationTargets.containsKey(i)) {
        oldAutomationTargetsById[id] =
            Map<String, _AutomationTargetMeta>.from(_rowAutomationTargets[i]!);
      }
      if (_rowSelectedAutomationTarget.containsKey(i)) {
        oldSelectedAutomationTargetById[id] =
            _rowSelectedAutomationTarget[i] ?? 'volume';
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
      _rowGain[i] =
          (oldGainById[id] ?? _rowGain[i]).clamp(_kGainUiMin, _kGainUiMax);
      _rowMuted[i] = oldMutedById[id] ?? _rowMuted[i];
      _rowSoloed[i] = oldSoloById[id] ?? _rowSoloed[i];
      _rowExpanded[i] = oldExpandedById[id] ?? _rowExpanded[i];
      _rowMuteApplied[i] = oldMuteAppliedById[id];
      _rowVolumeAutomation[i] =
          oldAutomationById[id] ?? _rowVolumeAutomation[i];
      _rowPluginAutomation[i] =
          oldPluginAutomationById[id] ?? <String, List<AutomationPoint>>{};
      _rowAutomationClips[i] = oldAutomationClipsById[id] ??
          <String, List<AutomationClipSnapshot>>{};
      _rowAutomationTargets[i] = oldAutomationTargetsById[id] ??
          <String, _AutomationTargetMeta>{
            'volume': _volumeAutomationTargetMeta(),
          };
      _rowSelectedAutomationTarget[i] =
          oldSelectedAutomationTargetById[id] ?? 'volume';
    }

    await _refreshAutomationTargetsForAllRows();

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
    unawaited(_spleeterStemSeparator.dispose());
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
    _stopMidiDeviceConnectionPolling();
    _midiInputPollTimer?.cancel();
    _midiInputPollTimer = null;
    _midiHeldNotesByKey.clear();
    _midiRecordingClipEngineId = null;
    if (_liveMidiEventPlaybackSupported) {
      unawaited(JuceAudioEngine.setLiveMidiInputTargetClip(-1));
    }
    for (final timer in _midiRenderDebounceTimers.values) {
      timer.cancel();
    }
    _midiRenderDebounceTimers.clear();
    _midiRenderSyncTokens.clear();
    _sfzDefinitionCache.clear();
    _sfzSampleCache.clear();

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
      final projectVersion = (json["version"] as num?)?.toInt() ?? 1;
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
        final defaultSpec = _defaultInstrumentSpec();
        final defaultInstrumentId =
            (defaultSpec['id'] as String?) ?? 'mixroom.basic_synth';
        final defaultInstrumentName =
            (defaultSpec['name'] as String?) ?? 'Instrument';
        final midiNotes = ((map['midiNotes'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => MidiNote.fromJson(e.cast<String, dynamic>()))
            .toList();

        final trimStartMs = (map["trimStartMs"] as int?) ?? 0;
        final trimEndMs = (map["trimEndMs"] as int?) ?? 0;
        final offsetSec = ((map["offset"] as num?) ?? 0).toDouble();
        final crossfade = ((map["crossfade"] as num?) ?? 0).toDouble();
        final gain = _normalizeLoadedGainUi(
          (map["gain"] as num?)?.toDouble(),
          projectVersion: projectVersion,
        );
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
                  instrumentId.isEmpty ? defaultInstrumentId : instrumentId,
              instrumentName: instrumentName.isEmpty
                  ? defaultInstrumentName
                  : instrumentName,
              instrumentParams: instrumentParams.isNotEmpty
                  ? instrumentParams
                  : _instrumentParamsFromSpec(
                      _instrumentSpecById(instrumentId.isEmpty
                          ? defaultInstrumentId
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
                instrumentId.isEmpty ? defaultInstrumentId : instrumentId,
            instrumentName:
                instrumentName.isEmpty ? defaultInstrumentName : instrumentName,
            instrumentParams: instrumentParams.isNotEmpty
                ? instrumentParams
                : _instrumentParamsFromSpec(
                    _instrumentSpecById(instrumentId.isEmpty
                        ? defaultInstrumentId
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
        _rowGain[r] = _normalizeLoadedGainUi(
          snap.gain,
          projectVersion: projectVersion,
        );

        // Restore automation (deep copy!)
        _rowVolumeAutomation[r] =
            snap.volumeAutomation.map((p) => p.copy()).toList();
        _restoreAutomationLanesForRow(
          r,
          snap.automationLanes,
          selectedTargetId: snap.selectedAutomationTargetId,
        );
        _restoreAutomationClipsForRow(r, snap.automationClips);

        await JuceAudioEngine.setRowGain(r, _rowGain[r]);
        await JuceAudioEngine.setRowPan(r, snap.pan);
      }

      // Restore FX snapshots after tracks exist
      final rowFxList = (json["rowEffects"] as List?) ?? [];
      for (final rf in rowFxList) {
        final snap = RowEffectsSnapshotJson.fromJson(
            (rf as Map).cast<String, dynamic>());
        await restoreRowSnapshot(snap);
      }
      await _refreshAutomationTargetsForAllRows();

      final master = json["master"] as Map<String, dynamic>?;

      if (master != null) {
        // Restore FX chain FIRST
        final masterFx = master["effects"];
        if (masterFx != null) {
          final ms = MasterEffectsSnapshotJson.fromJson(masterFx);
          await restoreMasterSnapshot(ms);
        }

        // THEN restore gain & pan
        final gain = _normalizeLoadedGainUi(
          (master["gain"] as num?)?.toDouble(),
          projectVersion: projectVersion,
        );
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
      await _syncNativeAutomationForAllRows();
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
          automationLanes: _automationLanesForRowSave(r),
          automationClips: _automationClipsForRowSave(r),
          selectedAutomationTargetId: _rowSelectedAutomationTarget[r],
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
        "version": 4,
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
    final focusNode = FocusNode();
    bool focusScheduled = false;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        if (!focusScheduled) {
          focusScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!focusNode.canRequestFocus) return;
            focusNode.requestFocus();
          });
        }
        return MediaQuery.removeViewInsets(
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
                      focusNode: focusNode,
                      autofocus: false,
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
        );
      },
    );
    controller.dispose();
    focusNode.dispose();
    return result;
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
      await _resumeAudio(setLocalState);
    } else {
      await _pauseAudio(setLocalState);
    }
  }

  Future<void> _resumeAudio(StateSetter setLocalState) async {
    _transportPlayStartSyncGraceUntil =
        _transportUiStopwatch.elapsed + _kTransportPlayStartSyncGrace;
    _transportEndCheckGraceUntil =
        _transportUiStopwatch.elapsed + const Duration(milliseconds: 420);
    await JuceAudioEngine.setTransportSeconds(
        _globalAudioClock.inMilliseconds / 1000.0);
    await JuceAudioEngine.setMetronomeTransportMs(
        _globalAudioClock.inMilliseconds.toDouble());
    await JuceAudioEngine.play();
    _syncTransportClock(_globalAudioClock, playing: true);

    _transportTicker?.start();

    _startMeterPolling();

    // Android can occasionally miss the first transport start edge.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!_isPlaying) return;
    await _pollTransportFromJuceIfNeeded(force: true);
    if (_transportRateSecPerSec <= 0.0) {
      await JuceAudioEngine.play();
    }
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
    await JuceAudioEngine.pause();
    await JuceAudioEngine.setTransportSeconds(
        newStartPoint.inMilliseconds / 1000.0);

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
    final nativeWavOnly = _desktopNativeWavOnlyExport;
    if (nativeWavOnly) {
      selectedFormat = _ExportAudioFormat.wav;
      selectedChannelMode = _ExportChannelMode.stereo;
      selectedNormalize = false;
      selectedResampleQuality = _ExportResampleQuality.best;
    }
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
              required bool enabled,
            }) {
              final isSelected = selectedFormat == format;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.horizontal(
                    left: isLeft ? const Radius.circular(12) : Radius.zero,
                    right: isLeft ? Radius.zero : const Radius.circular(12),
                  ),
                  onTap: enabled
                      ? () => setSheetState(() => selectedFormat = format)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0x553F73C8)
                          : (enabled
                              ? Colors.transparent
                              : Colors.white.withOpacity(0.04)),
                      borderRadius: BorderRadius.horizontal(
                        left: isLeft ? const Radius.circular(12) : Radius.zero,
                        right: isLeft ? Radius.zero : const Radius.circular(12),
                      ),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6EA7FF)
                            : (enabled
                                ? Colors.transparent
                                : Colors.white.withOpacity(0.08)),
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
                            color: !enabled
                                ? Colors.white38
                                : (isSelected ? Colors.white : mutedText),
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
                                  enabled: true,
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
                                  enabled: !nativeWavOnly,
                                ),
                              ],
                            ),
                          ),
                          if (nativeWavOnly) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0x2237669C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.09)),
                              ),
                              child: Text(
                                'Windows desktop currently exports with native WAV render only. MP3 and post-processing controls are disabled.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.86),
                                  fontSize: 12.2,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
                                  if (!nativeWavOnly) ...[
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
                                  ],
                                  if (!nativeWavOnly && selectedNormalize) ...[
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
                                          _ExportAudioFormat.wav ||
                                      nativeWavOnly) ...[
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
                                        format: nativeWavOnly
                                            ? _ExportAudioFormat.wav
                                            : selectedFormat,
                                        sampleRate: selectedSampleRate,
                                        wavBitDepth: selectedWavBitDepth,
                                        wavDithering: selectedWavDithering,
                                        mp3BitrateKbps: selectedMp3Bitrate,
                                        mp3Mode: selectedMp3Mode,
                                        mp3VbrQuality: selectedMp3VbrQuality,
                                        channelMode: nativeWavOnly
                                            ? _ExportChannelMode.stereo
                                            : selectedChannelMode,
                                        normalize: nativeWavOnly
                                            ? false
                                            : selectedNormalize,
                                        normalizeTargetDb:
                                            selectedNormalizeTargetDb,
                                        resampleQuality: nativeWavOnly
                                            ? _ExportResampleQuality.best
                                            : selectedResampleQuality,
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

  String _buildExportFilter(_AudioExportSettings settings) {
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
    }
    return filters.join(',');
  }

  Future<String> _convertMixWithExportSettings({
    required String inputPath,
    required _AudioExportSettings settings,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.${settings.fileExtension}';

    final filter = _buildExportFilter(settings);
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
    if (_desktopNativeWavOnlyExport) {
      final tempDir = await getTemporaryDirectory();
      await _syncNativePluginAutomationForAllRows();
      final nativeOutPath =
          '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.wav';

      try {
        final exportedPath = await JuceAudioEngine.exportMix(
          nativeOutPath,
          format: 'wav',
          sampleRate: settings.sampleRate,
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

    final rawRenderSampleRate = await _resolveRawRenderSampleRate(settings);
    final tempDir = await getTemporaryDirectory();
    await _syncNativePluginAutomationForAllRows();

    final useNativeWavDirect = _canUseNativeWavExport(settings) &&
        settings.sampleRate == rawRenderSampleRate;
    if (useNativeWavDirect) {
      final nativeOutPath =
          '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.wav';
      try {
        final exportedPath = await JuceAudioEngine.exportMix(
          nativeOutPath,
          format: 'wav',
          sampleRate: settings.sampleRate,
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

  Future<void> _pollMidiDeviceConnections({bool seedOnly = false}) async {
    if (!_liveMidiEventPlaybackSupported || _midiDevicePollBusy) return;
    _midiDevicePollBusy = true;
    try {
      final devices = await JuceAudioEngine.getConnectedMidiInputDevices();
      final nextById = <String, String>{};
      for (final device in devices) {
        final id = (device['id'] ?? '').trim();
        if (id.isEmpty) continue;
        final name = (device['name'] ?? id).trim();
        nextById[id] = name.isEmpty ? id : name;
      }

      if (_knownMidiDevicesById.isEmpty || seedOnly) {
        _knownMidiDevicesById = nextById;
        return;
      }

      final added = <String>[];
      final removed = <String>[];

      for (final entry in nextById.entries) {
        if (!_knownMidiDevicesById.containsKey(entry.key)) {
          added.add(entry.value);
        }
      }
      for (final entry in _knownMidiDevicesById.entries) {
        if (!nextById.containsKey(entry.key)) {
          removed.add(entry.value);
        }
      }

      _knownMidiDevicesById = nextById;
      if (!mounted) return;
      if (added.isEmpty && removed.isEmpty) return;

      final parts = <String>[];
      if (added.isNotEmpty) {
        parts.add('MIDI connected: ${added.join(', ')}');
      }
      if (removed.isNotEmpty) {
        parts.add('MIDI disconnected: ${removed.join(', ')}');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(parts.join(' | '))),
      );
    } catch (_) {
      // Ignore transient bridge errors and keep polling.
    } finally {
      _midiDevicePollBusy = false;
    }
  }

  void _startMidiDeviceConnectionPolling() {
    _midiDevicePollTimer?.cancel();
    _knownMidiDevicesById = <String, String>{};
    unawaited(_pollMidiDeviceConnections(seedOnly: true));
    _midiDevicePollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pollMidiDeviceConnections();
    });
  }

  void _stopMidiDeviceConnectionPolling() {
    _midiDevicePollTimer?.cancel();
    _midiDevicePollTimer = null;
    _knownMidiDevicesById = <String, String>{};
  }

  int? _activeMidiRecordingClipIndex() {
    final activeEngineId = _activeMidiClipEngineId;
    if (activeEngineId == null || activeEngineId < 0) return null;
    final clipIndex = _clipIndexForEngineId(activeEngineId);
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return null;
    if (!_audioTracks[clipIndex].isMidi) return null;
    return clipIndex;
  }

  String _midiRecordHeldKey(int channel, int pitch) => '$channel:$pitch';

  double _transportSecToClipSourceBeat(AudioTrack clip, double transportSec) {
    final sourceTempo = _resolvedClipSourceTempoBpm(clip);
    if (sourceTempo <= 0.0) return 0.0;
    final safeTransportSec = transportSec.isFinite
        ? transportSec
        : _globalAudioClock.inMilliseconds.toDouble() / 1000.0;
    final timelineSec = math.max(0.0, safeTransportSec - clip.offset);
    final sourceSec = (timelineSec * _tempoPlaybackRatioForEngine(clip)) +
        (clip.trimStart.inMilliseconds / 1000.0);
    return math.max(0.0, sourceSec * sourceTempo / 60.0);
  }

  bool _extendMidiClipForBeat(AudioTrack clip, double endBeat) {
    final sourceTempo = _resolvedClipSourceTempoBpm(clip);
    if (sourceTempo <= 0.0) return false;

    final trimStartSec = clip.trimStart.inMilliseconds / 1000.0;
    final noteEndSourceSec = math.max(0.0, endBeat) * 60.0 / sourceTempo;
    final requiredRawSec = math.max(0.001, noteEndSourceSec - trimStartSec);
    final currentRawSec =
        (clip.trimEnd - clip.trimStart).inMilliseconds / 1000.0;
    if (requiredRawSec <= currentRawSec + 0.0005) return false;

    clip.trimEnd = clip.trimStart +
        Duration(milliseconds: (requiredRawSec * 1000.0).ceil());
    return true;
  }

  bool _updateHeldMidiRecordNotes(
    AudioTrack clip,
    double currentBeat, {
    bool closeAll = false,
  }) {
    bool changed = false;
    final keys = _midiHeldNotesByKey.keys.toList(growable: false);
    for (final key in keys) {
      final stack = _midiHeldNotesByKey[key];
      if (stack == null || stack.isEmpty) {
        _midiHeldNotesByKey.remove(key);
        continue;
      }
      for (final note in stack) {
        final nextLength = math.max(0.03125, currentBeat - note.startBeat);
        if ((nextLength - note.lengthBeats).abs() > 0.00001) {
          note.lengthBeats = nextLength;
          changed = true;
        }
        if (_extendMidiClipForBeat(clip, note.startBeat + note.lengthBeats)) {
          changed = true;
        }
      }
      if (closeAll) {
        stack.clear();
        _midiHeldNotesByKey.remove(key);
      }
    }
    return changed;
  }

  Future<void> _drainMidiInputEventsForRecording({
    bool closeHeldNotes = false,
  }) async {
    if (!_isMidiClipRecording || _midiRecordingClipEngineId == null) return;
    if (_midiInputDrainBusy) {
      if (!closeHeldNotes) return;
      for (int attempt = 0; attempt < 8 && _midiInputDrainBusy; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      if (_midiInputDrainBusy) return;
    }
    final clipIndex = _clipIndexForEngineId(_midiRecordingClipEngineId!);
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (!clip.isMidi) return;

    _midiInputDrainBusy = true;
    try {
      final events = await JuceAudioEngine.consumeLiveMidiInputEvents();
      bool changed = false;
      double latestTransportSec = _lastMidiRecordTransportSec;

      for (final event in events) {
        final clipId = (event['clip'] as num?)?.toInt() ?? -1;
        if (clipId != clip.engineClipId) continue;

        final type = (event['type'] as String?) ?? '';
        final noteOn = type == 'noteOn';
        final noteOff = type == 'noteOff';
        if (!noteOn && !noteOff) continue;

        final pitch =
            (((event['pitch'] as num?)?.toInt() ?? 60).clamp(0, 127)).toInt();
        final channel =
            (((event['channel'] as num?)?.toInt() ?? 1).clamp(1, 16)).toInt();
        final velocity =
            ((event['velocity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
        final transportSec = (event['transportSec'] as num?)?.toDouble() ??
            (_globalAudioClock.inMilliseconds.toDouble() / 1000.0);
        latestTransportSec = math.max(latestTransportSec, transportSec);

        final beat = _transportSecToClipSourceBeat(clip, transportSec);
        final key = _midiRecordHeldKey(channel, pitch);

        if (noteOn) {
          final note = MidiNote(
            id: 'live_rec_${clip.engineClipId}_${DateTime.now().microsecondsSinceEpoch}_${_nextMidiRecordNoteToken++}',
            pitch: pitch,
            startBeat: beat,
            lengthBeats: 0.0625,
            velocity: velocity,
          );
          clip.midiNotes.add(note);
          (_midiHeldNotesByKey[key] ??= <MidiNote>[]).add(note);
          if (_extendMidiClipForBeat(clip, note.startBeat + note.lengthBeats)) {
            changed = true;
          }
          changed = true;
          _midiRecordHasChanges = true;
          continue;
        }

        final stack = _midiHeldNotesByKey[key];
        if (stack == null || stack.isEmpty) continue;
        final note = stack.removeLast();
        if (stack.isEmpty) {
          _midiHeldNotesByKey.remove(key);
        }
        final nextLength = math.max(0.03125, beat - note.startBeat);
        if ((nextLength - note.lengthBeats).abs() > 0.00001) {
          note.lengthBeats = nextLength;
          changed = true;
        }
        if (_extendMidiClipForBeat(clip, note.startBeat + note.lengthBeats)) {
          changed = true;
        }
        _midiRecordHasChanges = true;
      }

      final fallbackTransportSec =
          _globalAudioClock.inMilliseconds.toDouble() / 1000.0;
      final currentTransportSec =
          math.max(latestTransportSec, fallbackTransportSec);
      _lastMidiRecordTransportSec = currentTransportSec;
      final currentBeat =
          _transportSecToClipSourceBeat(clip, currentTransportSec);
      if (_updateHeldMidiRecordNotes(
        clip,
        currentBeat,
        closeAll: closeHeldNotes,
      )) {
        changed = true;
        _midiRecordHasChanges = true;
      }

      if (changed) {
        _updateOverallDurationIfNeeded();
        if (mounted) {
          setState(() {});
        }
      }
    } finally {
      _midiInputDrainBusy = false;
    }
  }

  Future<void> _startMidiClipRecording(int clipIndex) async {
    if (!_liveMidiEventPlaybackSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Live MIDI controller input is not supported on this platform.'),
        ),
      );
      return;
    }
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;

    final clip = _audioTracks[clipIndex];
    if (!clip.isMidi || clip.engineClipId < 0) return;

    if (_loopEnabled) {
      await _restartAudio(_safeAudioEditorStateSetter);
    }

    _recordingStartMs = _globalAudioClock.inMilliseconds.toDouble();
    if (!_isPlaying) {
      await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    }

    final targetOk =
        await JuceAudioEngine.setLiveMidiInputTargetClip(clip.engineClipId);
    if (!targetOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to arm selected MIDI clip.')),
      );
      return;
    }

    await JuceAudioEngine.consumeLiveMidiInputEvents();
    _midiHeldNotesByKey.clear();
    _nextMidiRecordNoteToken = 0;
    _lastMidiRecordTransportSec =
        _globalAudioClock.inMilliseconds.toDouble() / 1000.0;
    _midiRecordHasChanges = false;
    _recordingPeakTimer?.cancel();
    _recordingPeakTimer = null;

    _midiInputPollTimer?.cancel();
    _midiInputPollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      unawaited(_drainMidiInputEventsForRecording());
    });

    setState(() {
      _selectedRow = clip.rowIndex.clamp(0, math.max(0, _rowCount - 1)).toInt();
      _recordingFilePath = null;
      _recordingPeaks.clear();
      _isRecording = true;
      _isMidiClipRecording = true;
      _midiRecordingClipEngineId = clip.engineClipId;
    });
  }

  Future<void> _stopMidiClipRecording({bool keepPlaying = true}) async {
    _recordingPeakTimer?.cancel();
    _recordingPeakTimer = null;
    _midiInputPollTimer?.cancel();
    _midiInputPollTimer = null;

    await _drainMidiInputEventsForRecording(closeHeldNotes: true);

    final recordingClipId = _midiRecordingClipEngineId;
    final clipIndex =
        recordingClipId == null ? -1 : _clipIndexForEngineId(recordingClipId);
    if (clipIndex >= 0 && clipIndex < _audioTracks.length) {
      final clip = _audioTracks[clipIndex];
      if (clip.isMidi && _midiRecordHasChanges) {
        clip.midiNotes.sort((a, b) {
          final timeCmp = a.startBeat.compareTo(b.startBeat);
          if (timeCmp != 0) return timeCmp;
          return a.pitch.compareTo(b.pitch);
        });
        final updatedLive = await _updateMidiClipEventsLive(clip);
        if (updatedLive) {
          await _syncClipTimingToEngine(clipIndex);
          await _syncClipMixToEngine(clip);
          _queueMidiRenderCacheRefresh(clip);
          _updateOverallDurationIfNeeded();
        } else {
          await _rerenderMidiTrack(clip);
        }
      }
    }

    if (_liveMidiEventPlaybackSupported) {
      final previewClip =
          (_activeMidiClipEngineId != null && _activeMidiClipEngineId! >= 0)
              ? _activeMidiClipEngineId!
              : -1;
      await JuceAudioEngine.setLiveMidiInputTargetClip(previewClip);
      await JuceAudioEngine.consumeLiveMidiInputEvents();
    }

    _midiHeldNotesByKey.clear();
    _midiRecordingClipEngineId = null;
    _isMidiClipRecording = false;
    _midiRecordHasChanges = false;
    _lastMidiRecordTransportSec = 0.0;

    setState(() {
      _isRecording = false;
      _recordingPeaks.clear();
      _recordingFilePath = null;
    });

    if (!keepPlaying && _isPlaying) {
      await _togglePlayPauseAudio(_safeAudioEditorStateSetter);
    }
  }

  Future<void> _startRecordingJuce() async {
    final midiClipIndex = _activeMidiRecordingClipIndex();
    if (midiClipIndex != null) {
      await _startMidiClipRecording(midiClipIndex);
      return;
    }
    await _startAudioRecordingJuce();
  }

  Future<void> _startAudioRecordingJuce() async {
    _midiInputPollTimer?.cancel();
    _midiInputPollTimer = null;
    _midiHeldNotesByKey.clear();

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

    // 5) Start JUCE recording
    final ok = await JuceAudioEngine.startRecording(
      filePath,
      _selectedChannelStart,
      _selectedChannelCount,
    );

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start recording')));
      return;
    }

    // 6) UI state (UNCHANGED)
    setState(() {
      _recordingFilePath = filePath;
      _isRecording = true;
      _isMidiClipRecording = false;
      _midiRecordingClipEngineId = null;
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
    if (_isMidiClipRecording) {
      await _stopMidiClipRecording(keepPlaying: keepPlaying);
      return;
    }
    await _stopAudioRecordingJuce(keepPlaying: keepPlaying);
  }

  Future<void> _stopAudioRecordingJuce({bool keepPlaying = true}) async {
    if (!_isRecording) return;
    _midiHeldNotesByKey.clear();

    _recordingPeakTimer?.cancel();
    _recordingPeakTimer = null;

    // 1) Stop JUCE recorder
    await JuceAudioEngine.stopRecording();

    if (_recordingFilePath == null || !File(_recordingFilePath!).existsSync()) {
      setState(() {
        _isRecording = false;
        _isMidiClipRecording = false;
        _midiRecordingClipEngineId = null;
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
      _isMidiClipRecording = false;
      _midiRecordingClipEngineId = null;
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
              _addAudioTrackFromFile(
            file,
            row,
            timeMs,
            transcodeTo48k: false,
          ),
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
    bool transcodeTo48k = true,
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

    File clipSourceFile = newFile;
    if (transcodeTo48k) {
      // --- collision-safe temp name ---
      String candidatePath = p.join(audioDir.path, '$baseNameNoExt.wav');
      int suffix = 1;

      // Keep incrementing if another track already uses this temp path
      while (_audioTracks.any((t) => t.file.path == candidatePath)) {
        candidatePath = p.join(audioDir.path, '$baseNameNoExt #$suffix.wav');
        suffix++;
      }

      // 1) Transcode to 48 kHz PCM WAV (fast, one-time cost for imports):
      // TODO: preserve original sample rate when native engine path is fully validated.
      await FFmpegKit.execute(
        '-i "${newFile.path}" -ar 48000 -y "$candidatePath"',
      );
      clipSourceFile = File(candidatePath);
    }

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
      clipSourceFile.path,
      startSec: startSec,
      lengthSec: requestedLengthSec,
      inFileOffsetSec: math.max(0.0, requestedInFileOffsetSec),
    );

    // final dur = await JuceAudioEngine.getTrackDuration(0);
    final durSeconds = await JuceAudioEngine.getTrackDuration(engineClipId);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());

    // Create a new AudioTrack instance with a fixed audioDuration.
    final newTrack = await AudioTrack.create(
      file: clipSourceFile,
      originalFile: clipSourceFile, // might be unused
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
    final found = _findInstrumentSpecById(id);
    if (found != null) return found;
    return _defaultInstrumentSpec();
  }

  String _normalizeInstrumentToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Map<String, dynamic>? _findLegacySfzSpecByToken(String id) {
    final token = _normalizeInstrumentToken(id);
    if (token.isEmpty) return null;

    final pool = <Map<String, dynamic>>[
      ..._instrumentCatalog,
      ...kBundledSfzFallbackCatalog,
    ];
    Map<String, dynamic>? best;
    var bestScore = 0;

    for (final spec in pool) {
      final sfzPath = (spec['sfzAssetPath'] as String?)?.trim() ?? '';
      if (sfzPath.isEmpty) continue;
      final stemToken = _normalizeInstrumentToken(
        p.basenameWithoutExtension(sfzPath),
      );
      final nameToken =
          _normalizeInstrumentToken((spec['name'] as String?) ?? '');
      final idToken = _normalizeInstrumentToken((spec['id'] as String?) ?? '');

      var score = 0;
      if (token == idToken || token == stemToken || token == nameToken) {
        score = 6;
      } else if (stemToken.isNotEmpty &&
          (token.contains(stemToken) || stemToken.contains(token))) {
        score = 5;
      } else if (nameToken.isNotEmpty &&
          (token.contains(nameToken) || nameToken.contains(token))) {
        score = 4;
      }

      if (score > bestScore) {
        bestScore = score;
        best = spec;
      }
    }
    return best;
  }

  Map<String, dynamic>? _findInstrumentSpecById(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    for (final spec in _instrumentCatalog) {
      if (spec['id'] == trimmed) return spec;
    }
    for (final spec in kBundledSfzFallbackCatalog) {
      if (spec['id'] == trimmed) return spec;
    }
    for (final spec in kInstrumentCatalog) {
      if (spec['id'] == trimmed) return spec;
    }

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('sfz_asset:')) {
      final sfzPath = trimmed.substring('sfz_asset:'.length).trim();
      if (sfzPath.isNotEmpty) {
        return <String, dynamic>{
          'id': trimmed,
          'name': _prettyInstrumentNameFromSfzPreset(p.basename(sfzPath)),
          'category': 'instrument',
          'pickerCategory': 'Other',
          'sourceProject': 'External SFZ',
          'sourceLicense': 'User-provided',
          'isSampled': true,
          'sfzAssetPath': sfzPath,
          'outputGain': 0.72,
          'attackMs': 6.0,
          'releaseMs': 520.0,
        };
      }
    }

    if (lower.startsWith('sfz.')) {
      final legacy = _findLegacySfzSpecByToken(trimmed);
      if (legacy != null) return legacy;
    }
    return null;
  }

  String _instrumentNameFromId(String id) {
    final spec = _instrumentSpecById(id);
    return (spec['name'] as String?) ??
        (_defaultInstrumentSpec()['name'] as String? ?? 'Instrument');
  }

  Map<String, double> _instrumentParamsFromSpec(Map<String, dynamic> spec) {
    final sampled = _isSampledInstrumentSpec(spec);
    final params = <String, double>{};
    for (final entry in spec.entries) {
      final value = entry.value;
      if (value is num) {
        params[entry.key] = value.toDouble();
      }
    }
    if (sampled) {
      params.putIfAbsent('outputGain', () => 0.72);
      params.putIfAbsent('attackMs', () => 6.0);
      params.putIfAbsent('releaseMs', () => 520.0);
      params.putIfAbsent('stereoWidth', () => 0.0);
      params['drive'] = 0.0;
      params['noise'] = 0.0;
      return params;
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
    if (_isSampledInstrumentId(instrumentId)) {
      final name = _instrumentNameFromId(instrumentId).toLowerCase();
      if (name.contains('timpani')) {
        return <MidiNote>[
          MidiNote(
              id: '${now}_0',
              pitch: 43,
              startBeat: 0.0,
              lengthBeats: 0.75,
              velocity: 0.86),
          MidiNote(
              id: '${now}_1',
              pitch: 46,
              startBeat: 1.0,
              lengthBeats: 0.75,
              velocity: 0.80),
          MidiNote(
              id: '${now}_2',
              pitch: 50,
              startBeat: 2.0,
              lengthBeats: 0.75,
              velocity: 0.84),
          MidiNote(
              id: '${now}_3',
              pitch: 53,
              startBeat: 3.0,
              lengthBeats: 1.0,
              velocity: 0.90),
        ];
      }
      if (name.contains('drum') ||
          name.contains('kit') ||
          name.contains('gm style perc')) {
        return <MidiNote>[
          MidiNote(
              id: '${now}_0',
              pitch: 36,
              startBeat: 0.0,
              lengthBeats: 0.25,
              velocity: 0.92),
          MidiNote(
              id: '${now}_1',
              pitch: 42,
              startBeat: 0.5,
              lengthBeats: 0.25,
              velocity: 0.72),
          MidiNote(
              id: '${now}_2',
              pitch: 38,
              startBeat: 1.0,
              lengthBeats: 0.25,
              velocity: 0.85),
          MidiNote(
              id: '${now}_3',
              pitch: 42,
              startBeat: 1.5,
              lengthBeats: 0.25,
              velocity: 0.72),
          MidiNote(
              id: '${now}_4',
              pitch: 36,
              startBeat: 2.0,
              lengthBeats: 0.25,
              velocity: 0.9),
          MidiNote(
              id: '${now}_5',
              pitch: 46,
              startBeat: 2.5,
              lengthBeats: 0.25,
              velocity: 0.74),
          MidiNote(
              id: '${now}_6',
              pitch: 38,
              startBeat: 3.0,
              lengthBeats: 0.25,
              velocity: 0.88),
          MidiNote(
              id: '${now}_7',
              pitch: 42,
              startBeat: 3.5,
              lengthBeats: 0.25,
              velocity: 0.76),
        ];
      }
      if (name.contains('marimba') ||
          name.contains('glock') ||
          name.contains('xylo') ||
          name.contains('bell') ||
          name.contains('perc')) {
        return <MidiNote>[
          MidiNote(
              id: '${now}_0',
              pitch: 60,
              startBeat: 0.0,
              lengthBeats: 0.5,
              velocity: 0.90),
          MidiNote(
              id: '${now}_1',
              pitch: 64,
              startBeat: 0.5,
              lengthBeats: 0.5,
              velocity: 0.82),
          MidiNote(
              id: '${now}_2',
              pitch: 67,
              startBeat: 1.0,
              lengthBeats: 0.5,
              velocity: 0.86),
          MidiNote(
              id: '${now}_3',
              pitch: 72,
              startBeat: 1.5,
              lengthBeats: 0.5,
              velocity: 0.90),
          MidiNote(
              id: '${now}_4',
              pitch: 67,
              startBeat: 2.0,
              lengthBeats: 0.5,
              velocity: 0.84),
          MidiNote(
              id: '${now}_5',
              pitch: 64,
              startBeat: 2.5,
              lengthBeats: 0.5,
              velocity: 0.80),
          MidiNote(
              id: '${now}_6',
              pitch: 60,
              startBeat: 3.0,
              lengthBeats: 1.0,
              velocity: 0.88),
        ];
      }
      return <MidiNote>[
        MidiNote(
            id: '${now}_0',
            pitch: 60,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.78),
        MidiNote(
            id: '${now}_1',
            pitch: 64,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.72),
        MidiNote(
            id: '${now}_2',
            pitch: 67,
            startBeat: 0.0,
            lengthBeats: 4.0,
            velocity: 0.72),
      ];
    }
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

  Map<String, String> _parseSfzOpcodes(String line) {
    final out = <String, String>{};
    final trimmed = line.split('//').first.trim();
    if (trimmed.isEmpty) return out;
    final matches =
        RegExp(r'([A-Za-z_][A-Za-z0-9_]*)=').allMatches(trimmed).toList();
    if (matches.isEmpty) return out;
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final key = (m.group(1) ?? '').trim().toLowerCase();
      final valueStart = m.end;
      final valueEnd =
          i + 1 < matches.length ? matches[i + 1].start : trimmed.length;
      final value = trimmed.substring(valueStart, valueEnd).trim();
      if (key.isEmpty || value.isEmpty) continue;
      out[key] = value;
    }
    return out;
  }

  String _stripSfzQuotes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith('\'') && trimmed.endsWith('\'')))) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  double? _parseSfzNumberOrNote(String raw) {
    final token = _stripSfzQuotes(raw);
    final numeric = double.tryParse(token);
    if (numeric != null) return numeric;

    final match = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)$').firstMatch(token);
    if (match == null) return null;
    final step = (match.group(1) ?? '').toUpperCase();
    final accidental = match.group(2) ?? '';
    final octave = int.tryParse(match.group(3) ?? '');
    if (octave == null) return null;

    const semitones = <String, int>{
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    var semitone = semitones[step];
    if (semitone == null) return null;
    if (accidental == '#') semitone += 1;
    if (accidental == 'b') semitone -= 1;

    final midi = ((octave + 1) * 12) + semitone;
    return midi.toDouble();
  }

  _SfzParsedLine _parseSfzLine(String rawLine) {
    final line = rawLine.split('//').first.trim();
    if (line.isEmpty) return const _SfzParsedLine();

    String? blockTag;
    var remainder = line;
    final tagMatch = RegExp(r'^<\s*([A-Za-z0-9_]+)\s*>').firstMatch(line);
    if (tagMatch != null) {
      blockTag = (tagMatch.group(1) ?? '').trim().toLowerCase();
      remainder = line.substring(tagMatch.end).trim();
    }
    final opcodes = remainder.isEmpty
        ? const <String, String>{}
        : _parseSfzOpcodes(remainder);
    return _SfzParsedLine(blockTag: blockTag, opcodes: opcodes);
  }

  Future<List<String>> _loadSfzExpandedLines(
    String sfzAssetPath, {
    Set<String>? includeStack,
    Map<String, String>? defines,
  }) async {
    final normalizedPath = p.posix.normalize(sfzAssetPath);
    final stack = includeStack ?? <String>{};
    if (stack.contains(normalizedPath)) return const <String>[];
    stack.add(normalizedPath);

    try {
      final text = await rootBundle.loadString(normalizedPath);
      final dir = p.posix.dirname(normalizedPath);
      final macroMap = defines ?? <String, String>{};
      final out = <String>[];

      for (final rawLine in const LineSplitter().convert(text)) {
        final line = rawLine.split('//').first.trim();
        if (line.isEmpty) continue;

        final includeMatch =
            RegExp(r'''^#include\s+["']([^"']+)["']''', caseSensitive: false)
                .firstMatch(line);
        if (includeMatch != null) {
          final includeRaw =
              _stripSfzQuotes((includeMatch.group(1) ?? '').trim());
          if (includeRaw.isNotEmpty) {
            final includePath = p.posix.normalize(
              p.posix.join(dir, includeRaw.replaceAll('\\', '/')),
            );
            final includeLines = await _loadSfzExpandedLines(
              includePath,
              includeStack: stack,
              defines: macroMap,
            );
            out.addAll(includeLines);
          }
          continue;
        }

        final defineMatch =
            RegExp(r'^#define\s+\$?([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$')
                .firstMatch(line);
        if (defineMatch != null) {
          final key = (defineMatch.group(1) ?? '').trim();
          final value = (defineMatch.group(2) ?? '').trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            macroMap[key] = value;
          }
          continue;
        }

        var expandedLine = rawLine;
        if (macroMap.isNotEmpty) {
          for (final entry in macroMap.entries) {
            expandedLine = expandedLine.replaceAll(
              '\$${entry.key}',
              entry.value,
            );
          }
        }
        out.add(expandedLine);
      }
      return out;
    } catch (_) {
      return const <String>[];
    } finally {
      stack.remove(normalizedPath);
    }
  }

  String _resolveSfzSampleAssetPath({
    required String sfzAssetPath,
    required String defaultPathRaw,
    required String samplePathRaw,
  }) {
    final sfzDir = p.posix.dirname(sfzAssetPath);
    final defaultPath = _stripSfzQuotes(defaultPathRaw).replaceAll('\\', '/');
    final samplePath = _stripSfzQuotes(samplePathRaw).replaceAll('\\', '/');
    if (samplePath.startsWith('assets/')) {
      return p.posix.normalize(samplePath);
    }
    return p.posix.normalize(
      p.posix.join(sfzDir, defaultPath, samplePath),
    );
  }

  double _readSfzNumeric(
      Map<String, String> values, String key, double fallback) {
    final raw = values[key];
    if (raw == null) return fallback;
    return _parseSfzNumberOrNote(raw) ?? fallback;
  }

  Future<_SfzDefinition?> _sfzDefinitionForInstrument(
      String instrumentId) async {
    final spec = _instrumentSpecById(instrumentId);
    if (!_isSampledInstrumentSpec(spec)) return null;
    final sfzAssetPath = (spec['sfzAssetPath'] as String?)?.trim() ?? '';
    if (sfzAssetPath.isEmpty) return null;

    final cached = _sfzDefinitionCache[sfzAssetPath];
    if (cached != null) return cached;

    try {
      final sfzLines = await _loadSfzExpandedLines(sfzAssetPath);
      if (sfzLines.isEmpty) return null;
      final control = <String, String>{};
      final global = <String, String>{};
      final master = <String, String>{};
      final group = <String, String>{};
      Map<String, String>? region;
      String currentBlock = '';

      final regions = <Map<String, String>>[];
      for (final rawLine in sfzLines) {
        final parsed = _parseSfzLine(rawLine);
        final tag = parsed.blockTag;
        if (tag != null && tag.isNotEmpty) {
          currentBlock = tag;
          if (tag == 'group') {
            group.clear();
          } else if (tag == 'master') {
            master.clear();
          } else if (tag == 'region') {
            region = <String, String>{}
              ..addAll(control)
              ..addAll(global)
              ..addAll(master)
              ..addAll(group);
            regions.add(region);
          }
        }

        final opcodes = parsed.opcodes;
        if (opcodes.isEmpty) continue;
        switch (currentBlock) {
          case 'control':
            control.addAll(opcodes);
            break;
          case 'global':
            global.addAll(opcodes);
            break;
          case 'master':
            master.addAll(opcodes);
            break;
          case 'group':
            group.addAll(opcodes);
            break;
          case 'region':
            region ??= <String, String>{}
              ..addAll(control)
              ..addAll(global)
              ..addAll(master)
              ..addAll(group);
            region.addAll(opcodes);
            break;
          default:
            break;
        }
      }

      final defaultPathRaw = control['default_path'] ?? '';
      final globalAttackSec = _readSfzNumeric(global, 'ampeg_attack', 0.005);
      final globalReleaseSec = _readSfzNumeric(global, 'ampeg_release', 0.35);
      final globalVol = _readSfzNumeric(global, 'volume', 0.0);

      final parsedRegions = <_SfzRegion>[];
      for (final r in regions) {
        final sampleRaw = r['sample'] ?? '';
        if (sampleRaw.isEmpty) continue;
        final sampleAssetPath = _resolveSfzSampleAssetPath(
          sfzAssetPath: sfzAssetPath,
          defaultPathRaw: r['default_path'] ?? defaultPathRaw,
          samplePathRaw: sampleRaw,
        );
        final loKey = _readSfzNumeric(r, 'lokey', 0).round().clamp(0, 127);
        final hiKey = _readSfzNumeric(r, 'hikey', 127).round().clamp(0, 127);
        final keyCenter = _readSfzNumeric(
          r,
          'pitch_keycenter',
          _readSfzNumeric(r, 'key', ((loKey + hiKey) / 2.0).roundToDouble()),
        ).round().clamp(0, 127);
        final loVel = _readSfzNumeric(r, 'lovel', 0).round().clamp(0, 127);
        final hiVel = _readSfzNumeric(r, 'hivel', 127).round().clamp(0, 127);
        final regionVolDb = _readSfzNumeric(r, 'volume', globalVol);
        final gainLinear = math
            .pow(
              10.0,
              (regionVolDb.clamp(-24.0, 12.0)) / 20.0,
            )
            .toDouble();
        final attackSec = _readSfzNumeric(r, 'ampeg_attack', globalAttackSec)
            .clamp(0.0, 4.0)
            .toDouble();
        final releaseSec = _readSfzNumeric(r, 'ampeg_release', globalReleaseSec)
            .clamp(0.02, 12.0)
            .toDouble();
        parsedRegions.add(
          _SfzRegion(
            sampleAssetPath: sampleAssetPath,
            loKey: loKey,
            hiKey: hiKey,
            keyCenter: keyCenter,
            loVel: loVel,
            hiVel: hiVel,
            gainLinear: gainLinear,
            attackSec: attackSec,
            releaseSec: releaseSec,
          ),
        );
      }

      if (parsedRegions.isEmpty) return null;
      final definition = _SfzDefinition(
        sfzAssetPath: sfzAssetPath,
        regions: parsedRegions,
        defaultAttackSec: globalAttackSec.clamp(0.0, 4.0),
        defaultReleaseSec: globalReleaseSec.clamp(0.02, 12.0),
      );
      _sfzDefinitionCache[sfzAssetPath] = definition;
      return definition;
    } catch (_) {
      return null;
    }
  }

  _SfzRegion? _pickSfzRegion(
      _SfzDefinition definition, int pitch, int velocity) {
    var candidates = definition.regions.where((region) {
      return pitch >= region.loKey &&
          pitch <= region.hiKey &&
          velocity >= region.loVel &&
          velocity <= region.hiVel;
    }).toList(growable: false);

    if (candidates.isEmpty) {
      candidates = definition.regions.where((region) {
        return pitch >= region.loKey && pitch <= region.hiKey;
      }).toList(growable: false);
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final keyA = (pitch - a.keyCenter).abs();
      final keyB = (pitch - b.keyCenter).abs();
      if (keyA != keyB) return keyA.compareTo(keyB);
      final velA = velocity < a.loVel
          ? a.loVel - velocity
          : velocity > a.hiVel
              ? velocity - a.hiVel
              : 0;
      final velB = velocity < b.loVel
          ? b.loVel - velocity
          : velocity > b.hiVel
              ? velocity - b.hiVel
              : 0;
      return velA.compareTo(velB);
    });
    return candidates.first;
  }

  int _findWavChunk(Uint8List bytes, String chunkId) {
    for (int i = 12; i + 8 <= bytes.length;) {
      final id = ascii.decode(bytes.sublist(i, i + 4), allowInvalid: true);
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      if (id == chunkId) return i;
      i += 8 + size + (size.isOdd ? 1 : 0);
    }
    return -1;
  }

  _DecodedStereoPcm? _decodePcmWav(ByteData wavData) {
    final bytes = wavData.buffer.asUint8List();
    if (bytes.length < 44) return null;
    final riff = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    final wave = ascii.decode(bytes.sublist(8, 12), allowInvalid: true);
    if (riff != 'RIFF' || wave != 'WAVE') return null;

    final fmtChunkStart = _findWavChunk(bytes, 'fmt ');
    final dataChunkStart = _findWavChunk(bytes, 'data');
    if (fmtChunkStart < 0 || dataChunkStart < 0) return null;

    final fmtSize =
        ByteData.sublistView(bytes, fmtChunkStart + 4, fmtChunkStart + 8)
            .getUint32(0, Endian.little);
    if (fmtSize < 16) return null;
    final fmt = ByteData.sublistView(
      bytes,
      fmtChunkStart + 8,
      fmtChunkStart + 8 + fmtSize,
    );
    final audioFormat = fmt.getUint16(0, Endian.little);
    final channels = fmt.getUint16(2, Endian.little);
    final sampleRate = fmt.getUint32(4, Endian.little);
    final bitsPerSample = fmt.getUint16(14, Endian.little);
    if (channels < 1 || channels > 2) return null;
    if (audioFormat != 1) return null;
    if (bitsPerSample != 16 && bitsPerSample != 24) return null;

    final dataSize = ByteData.sublistView(
      bytes,
      dataChunkStart + 4,
      dataChunkStart + 8,
    ).getUint32(0, Endian.little);
    final dataOffset = dataChunkStart + 8;
    if (dataOffset + dataSize > bytes.length) return null;

    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = bytesPerSample * channels;
    if (frameSize <= 0) return null;
    final frameCount = dataSize ~/ frameSize;
    if (frameCount <= 0) return null;

    final left = Float32List(frameCount);
    final right = Float32List(frameCount);

    int ptr = dataOffset;
    for (int i = 0; i < frameCount; i++) {
      double readSample() {
        if (bitsPerSample == 16) {
          final v = (bytes[ptr] | (bytes[ptr + 1] << 8));
          final signed = (v & 0x8000) != 0 ? v - 0x10000 : v;
          ptr += 2;
          return (signed / 32768.0).clamp(-1.0, 1.0).toDouble();
        }
        final v = bytes[ptr] | (bytes[ptr + 1] << 8) | (bytes[ptr + 2] << 16);
        final signed = (v & 0x800000) != 0 ? v - 0x1000000 : v;
        ptr += 3;
        return (signed / 8388608.0).clamp(-1.0, 1.0).toDouble();
      }

      final l = readSample();
      final r = channels > 1 ? readSample() : l;
      left[i] = l;
      right[i] = r;
    }

    return _DecodedStereoPcm(
      sampleRate: sampleRate,
      left: left,
      right: right,
    );
  }

  Future<_DecodedStereoPcm?> _decodedSfzSample(String assetPath) async {
    final cached = _sfzSampleCache.remove(assetPath);
    if (cached != null) {
      _sfzSampleCache[assetPath] = cached;
      return cached;
    }
    try {
      final data = await rootBundle.load(assetPath);
      final decoded = _decodePcmWav(data);
      if (decoded == null) return null;
      _sfzSampleCache[assetPath] = decoded;
      if (_sfzSampleCache.length > _kMaxSfzSampleCacheEntries) {
        _sfzSampleCache.remove(_sfzSampleCache.keys.first);
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _renderInstrumentClipWithSfz({
    required File outFile,
    required String instrumentId,
    required List<MidiNote> notes,
    required Map<String, double> params,
    required double bpm,
    double minimumDurationMs = 1200.0,
  }) async {
    final definition = await _sfzDefinitionForInstrument(instrumentId);
    if (definition == null || definition.regions.isEmpty) return false;

    const double sampleRate = 48000.0;
    final msPerBeat = 60000.0 / bpm.clamp(1.0, 400.0);
    double endBeat = 4.0;
    for (final n in notes) {
      endBeat = math.max(endBeat, n.startBeat + n.lengthBeats);
    }

    final outputGain = (params['outputGain'] ?? 0.72).clamp(0.2, 2.0);
    final attackOverrideSec = ((params['attackMs'] ?? -1.0) / 1000.0);
    final releaseOverrideSec = ((params['releaseMs'] ?? -1.0) / 1000.0);
    final tailSec = releaseOverrideSec > 0
        ? releaseOverrideSec
        : definition.defaultReleaseSec;
    final totalMs = math.max(
      minimumDurationMs,
      endBeat * msPerBeat + tailSec * 1000.0 + 180.0,
    );
    final totalSamples = math.max(2048, (totalMs * sampleRate / 1000.0).ceil());
    final left = Float32List(totalSamples);
    final right = Float32List(totalSamples);

    for (final note in notes) {
      final safePitch = note.pitch.clamp(0, 127);
      final safeVelocity = note.velocity.clamp(0.0, 1.0);
      final velocityMidi = (safeVelocity * 127.0).round().clamp(0, 127);
      final region = _pickSfzRegion(definition, safePitch, velocityMidi);
      if (region == null) continue;
      final sample = await _decodedSfzSample(region.sampleAssetPath);
      if (sample == null || sample.frameCount < 2) continue;

      final noteStart =
          (note.startBeat * msPerBeat * sampleRate / 1000.0).round();
      final sustainSamples = math.max(
        1,
        (note.lengthBeats * msPerBeat * sampleRate / 1000.0).round(),
      );
      final attackSec = attackOverrideSec > 0
          ? attackOverrideSec
          : region.attackSec.clamp(0.0, 2.0);
      final releaseSec = releaseOverrideSec > 0
          ? releaseOverrideSec
          : region.releaseSec.clamp(0.02, 12.0);
      final attackSamples = math.max(1, (attackSec * sampleRate).round());
      final releaseSamples = math.max(1, (releaseSec * sampleRate).round());
      final totalNoteSamples = sustainSamples + releaseSamples;

      final semitoneOffset = safePitch - region.keyCenter;
      final playbackRate = math.pow(2.0, semitoneOffset / 12.0).toDouble() *
          (sample.sampleRate / sampleRate);

      double samplePos = 0.0;
      final noteGain = safeVelocity * region.gainLinear * outputGain;
      for (int i = 0; i < totalNoteSamples; i++) {
        final idx = noteStart + i;
        if (idx < 0 || idx >= totalSamples) break;
        if (samplePos >= sample.frameCount - 1) break;

        double env;
        if (i < attackSamples) {
          env = i / attackSamples;
        } else if (i < sustainSamples) {
          env = 1.0;
        } else {
          env = 1.0 - ((i - sustainSamples) / releaseSamples);
        }
        env = env.clamp(0.0, 1.0);
        if (env <= 0.0) {
          samplePos += playbackRate;
          continue;
        }

        final baseIndex = samplePos.floor();
        final frac = samplePos - baseIndex;
        final nextIndex = math.min(baseIndex + 1, sample.frameCount - 1);
        final l = sample.left[baseIndex] * (1.0 - frac) +
            sample.left[nextIndex] * frac;
        final r = sample.right[baseIndex] * (1.0 - frac) +
            sample.right[nextIndex] * frac;

        left[idx] += (l * env * noteGain).toDouble();
        right[idx] += (r * env * noteGain).toDouble();
        samplePos += playbackRate;
      }
    }

    double peak = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      peak = math.max(peak, left[i].abs());
      peak = math.max(peak, right[i].abs());
    }
    final normalizeGain = peak > 0.98 ? (0.98 / peak) : 1.0;
    for (int i = 0; i < totalSamples; i++) {
      left[i] = (left[i] * normalizeGain).clamp(-1.0, 1.0).toDouble();
      right[i] = (right[i] * normalizeGain).clamp(-1.0, 1.0).toDouble();
    }

    await _writeStereoPcm16Wav(
      path: outFile.path,
      sampleRate: sampleRate.toInt(),
      left: left,
      right: right,
    );
    return true;
  }

  Future<bool> _renderInstrumentClipToFile({
    required File outFile,
    required String instrumentId,
    required String instrumentName,
    required List<MidiNote> notes,
    required Map<String, double> params,
  }) async {
    if (!await outFile.parent.exists()) {
      await outFile.parent.create(recursive: true);
    }

    if (_isSampledInstrumentId(instrumentId)) {
      final renderedWithSfz = await _renderInstrumentClipWithSfz(
        outFile: outFile,
        instrumentId: instrumentId,
        notes: notes,
        params: params,
        bpm: _tempo,
      );
      if (renderedWithSfz && outFile.existsSync()) {
        return true;
      }
      return false;
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

    final engineInstrumentId = _liveMidiEngineInstrumentId(instrumentId);
    final renderedPath = await JuceAudioEngine.renderInstrumentClip(
      outPath: outFile.path,
      instrumentId: engineInstrumentId,
      instrumentName: instrumentName,
      bpm: _tempo,
      notes: noteMaps,
      params: params,
    );

    if (renderedPath.isNotEmpty && File(renderedPath).existsSync()) {
      return true;
    }

    await _renderInstrumentClipWithDartSynth(
      outFile: outFile,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      notes: notes,
      params: params,
      bpm: _tempo,
    );
    return outFile.existsSync();
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

  String _liveMidiEngineInstrumentId(String instrumentId) {
    final id = instrumentId.trim();
    if (id.toLowerCase().startsWith('sfz_asset:')) {
      return id;
    }
    final spec = _findInstrumentSpecById(id);
    if (spec != null && _isSampledInstrumentSpec(spec)) {
      final sfzAssetPath = (spec['sfzAssetPath'] as String?)?.trim() ?? '';
      if (sfzAssetPath.isNotEmpty) {
        return 'sfz_asset:$sfzAssetPath';
      }
    }
    return id;
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
    if (_isSampledInstrumentId(instrumentId)) return false;
    if (engineClipId < 0 || rowId < 0) return false;
    final liveInstrumentId = _liveMidiEngineInstrumentId(instrumentId);
    return JuceAudioEngine.loadMidiClip(
      engineClipId,
      rowId,
      instrumentId: liveInstrumentId,
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
    if (_isSampledInstrumentId(clip.instrumentId)) return false;
    final liveInstrumentId = _liveMidiEngineInstrumentId(clip.instrumentId);
    return JuceAudioEngine.updateMidiClipEvents(
      clip.engineClipId,
      instrumentId: liveInstrumentId,
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
          final rendered = await _renderInstrumentClipToFile(
            outFile: File(filePathSnapshot),
            instrumentId: instrumentIdSnapshot,
            instrumentName: instrumentNameSnapshot,
            notes: notesSnapshot,
            params: paramsSnapshot,
          );
          if (!rendered || !File(filePathSnapshot).existsSync()) return;
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
    final shouldRefreshSampledRender =
        renderedFile != null && _isSampledInstrumentId(instrumentId);
    if (!outFile.existsSync() || shouldRefreshSampledRender) {
      final rendered = await _renderInstrumentClipToFile(
        outFile: outFile,
        instrumentId: instrumentId,
        instrumentName: instrumentName,
        notes: midiNotes,
        params: instrumentParams,
      );
      if (!rendered || !outFile.existsSync()) {
        if (mounted) {
          final msg = _isSampledInstrumentId(instrumentId)
              ? 'Could not render sampled instrument. Check SFZ assets.'
              : 'Could not render instrument clip.';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
        return;
      }
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

    final rendered = await _renderInstrumentClipToFile(
      outFile: clip.file,
      instrumentId: clip.instrumentId,
      instrumentName: clip.instrumentName,
      notes: clip.midiNotes,
      params: clip.instrumentParams,
    );
    if (!rendered || !clip.file.existsSync()) return;

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
    final savedPath = await ExportSaveDialog.saveExportedFile(
      sourceFilePath: exportPath,
      suggestedFileName: 'export_file.$ext',
      desktopDialogTitle: 'Save export',
    );

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
    if (_isProEntitled || _audioTracks.length < 3) {
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

    if (_isPlaying) {
      await _pausePlayback();
    }
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
      // Avoid presenting a native picker during an active Flutter route transition.
      await SchedulerBinding.instance.endOfFrame;
      return await request();
    } on PlatformException catch (e) {
      if (e.code != 'multiple_request') rethrow;
      await SchedulerBinding.instance.endOfFrame;
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
    final explicit = (spec['pickerCategory'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _normalizePickerCategory(explicit);
    }
    final declared = ((spec['category'] as String?) ?? '').toLowerCase();
    final id = ((spec['id'] as String?) ?? '').toLowerCase();
    final name = ((spec['name'] as String?) ?? '').toLowerCase();
    final text = '$id $name';

    if (text.contains('string') ||
        text.contains('violin') ||
        text.contains('cello')) {
      return 'Strings';
    }
    if (text.contains('woodwind') ||
        text.contains('flute') ||
        text.contains('clarinet') ||
        text.contains('oboe') ||
        text.contains('bassoon')) {
      return 'Woodwinds';
    }
    if (text.contains('perc') ||
        text.contains('marimba') ||
        text.contains('glock')) {
      return 'Percussion';
    }
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

  List<Map<String, dynamic>> _activeInstrumentCatalog() {
    if (_instrumentCatalog.isNotEmpty) return _instrumentCatalog;
    return kBundledSfzFallbackCatalog
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  List<String> _instrumentPickerCategories() {
    const ordered = <String>[
      'Keys',
      'Strings',
      'Woodwinds',
      'Brass',
      'Percussion',
      'Drums',
      'Pads',
      'Leads',
      'Bass',
      'Plucks',
      'Other',
    ];
    final available = _activeInstrumentCatalog()
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
      case 'Strings':
        return const Color(0xFF67A6FF);
      case 'Woodwinds':
        return const Color(0xFF4CC5AB);
      case 'Percussion':
        return const Color(0xFFF8B65E);
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
      case 'Strings':
        return Icons.multitrack_audio_rounded;
      case 'Woodwinds':
        return Icons.air_rounded;
      case 'Percussion':
        return Icons.music_note_outlined;
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
    final sampled = _isSampledInstrumentSpec(spec);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF263245),
                const Color(0xFF1B2433),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.52)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                top: -26,
                child: IgnorePointer(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withValues(alpha: 0.26),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.20),
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
                        constraints: const BoxConstraints(minHeight: 19),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.17),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.50),
                          ),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.north_east_rounded,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.48),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.4,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sampled
                              ? (source.isEmpty
                                  ? 'Sampled • Ready to play'
                                  : 'Sampled • $source')
                              : (source.isEmpty
                                  ? 'Synth preset'
                                  : 'Inspired by $source'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 10.9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.13),
                            ),
                          ),
                          child: Text(
                            sampled ? 'SFZ Layered' : 'Synth Engine',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.80),
                              fontSize: 9.8,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
    final catalog = _activeInstrumentCatalog();
    if (catalog.isEmpty) return;
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
            final filtered = catalog.where((spec) {
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
                              constraints: const BoxConstraints(
                                minHeight: 30,
                                minWidth: 74,
                              ),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
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
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _instrumentPickerIcon(category),
                                      size: 12.4,
                                      color: selected ? accent : Colors.white70,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      category,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color:
                                            selected ? accent : Colors.white70,
                                        fontSize: 11.1,
                                        fontWeight: FontWeight.w700,
                                        height: 1.0,
                                      ),
                                    ),
                                  ],
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
                                final cardHeight = compact ? 130.0 : 138.0;
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

    final defaultSpec = _defaultInstrumentSpec();
    final instrumentId =
        (selected['id'] as String?) ?? (defaultSpec['id'] as String?) ?? '';
    final instrumentName = (selected['name'] as String?) ??
        (defaultSpec['name'] as String?) ??
        'Instrument';
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
        await JuceAudioEngine.setRowGain(row, _kGainUiUnity);

        // --- Pan ---
        await JuceAudioEngine.setRowPan(row, 0.5);

        // --- Automation (flat unity) ---
        await JuceAudioEngine.setTrackAutomationPoints(
            row, _toMaps([AutomationPoint(x: 0.0, volume: 0.75)]));
        await JuceAudioEngine.clearTrackEffectAutomationForRow(row);
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
      await _syncNativeAutomationForRow(row);
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
    final currentPeakDb = _ampToDbFs(math.max(frame.peakL, frame.peakR));

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

  static double _uiFromGainDb(double db) {
    final clampedDb = db.clamp(_kGainDbMin, _kGainDbMax).toDouble();
    if (clampedDb <= 0.0) {
      final t = (clampedDb - _kGainDbMin) / (0.0 - _kGainDbMin);
      return _kGainUiMin + ((_kGainUiUnity - _kGainUiMin) * t);
    }
    final t = clampedDb / _kGainDbMax;
    return _kGainUiUnity + ((_kGainUiMax - _kGainUiUnity) * t);
  }

  double _normalizeLoadedGainUi(
    double? rawGain, {
    required int projectVersion,
  }) {
    if (rawGain == null || !rawGain.isFinite) return _kGainUiUnity;
    final clamped = rawGain.clamp(_kGainUiMin, _kGainUiMax).toDouble();

    // Backward compatibility: old projects often stored unity at 1.0 UI or at
    // the previous linear-mapped unity (~2.727). Map both to the current
    // piecewise unity position.
    if (projectVersion <= 1 &&
        ((clamped - 1.0).abs() < 0.02 ||
            (clamped - _kLegacyLinearGainUiUnity).abs() < 0.02)) {
      return _kGainUiUnity;
    }
    return clamped;
  }

  Widget _buildMasterEffectsPage() {
    return MasterEffectsPanel(
      key: ValueKey("master_effects_panel"),
      mode: _resolvedMode,
      isProEntitled: _isProEntitled,
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

  Widget _buildTopBar(Duration currentClock, _EditorLayoutSpec layoutSpec) {
    final pluginAffordanceEnabled =
        _platformCapabilities.supportsExternalPluginAffordances;
    return Halo(
      highlighter: _mixHighlighter,
      haloKey: const HaloKey('tutorial:toolbar'),
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: layoutSpec.topBarPadding,
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
            SizedBox(width: layoutSpec.topBarClusterGap),
            // NEW PROJECT SETTINGS BUTTON
            Halo(
              highlighter: _mixHighlighter,
              haloKey: const HaloKey('tutorial:project_settings'),
              borderRadius: BorderRadius.circular(22),
              child: _Glass(
                radius: 22,
                padding: EdgeInsets.zero,
                opacity: 0.10,
                child: IconButton(
                  icon:
                      const Icon(Icons.settings, color: Colors.white, size: 20),
                  onPressed: _openProjectSettings,
                ),
              ),
            ),

            SizedBox(width: layoutSpec.topBarClusterGap),
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
            SizedBox(width: layoutSpec.topBarClusterGap * 0.8),

            // RIGHT: allow this cluster to also scale when narrow
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  Halo(
                    highlighter: _mixHighlighter,
                    haloKey: const HaloKey('tutorial:plugins'),
                    borderRadius: BorderRadius.circular(22),
                    child: _Glass(
                      radius: 22,
                      padding: EdgeInsets.zero,
                      opacity: 0.10,
                      child: IconButton(
                        icon: Icon(
                          Icons.settings_input_composite,
                          color: pluginAffordanceEnabled
                              ? Colors.white
                              : Colors.white38,
                          size: 20,
                        ),
                        onPressed: pluginAffordanceEnabled
                            ? () {
                                _isMasterPopupOpen = !_isMasterPopupOpen;
                                setState(
                                    () => _showMasterRack = !_showMasterRack);
                              }
                            : () {
                                _showSmallNotice(
                                    'External plugins are not available on this platform.');
                              },
                      ),
                    ),
                  ),
                  SizedBox(width: layoutSpec.topBarClusterGap),
                  Halo(
                    highlighter: _mixHighlighter,
                    haloKey: const HaloKey('tutorial:export'),
                    borderRadius: BorderRadius.circular(24),
                    child: GestureDetector(
                      onTap: _exportAndNavigate,
                      child: Container(
                        width: layoutSpec.topBarActionButtonSize,
                        height: layoutSpec.topBarActionButtonSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white.withOpacity(0.1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                            ),
                            const BoxShadow(
                              color: Color(0x22FFFFFF),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.ios_share_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProjectSettings() async {
    if (_isDialogOpen) return;
    if (_showTempoRollDown) {
      setState(() => _showTempoRollDown = false);
    }
    _isDialogOpen = true;
    if (_inputDevices.isEmpty && !_loadingDevices) {
      unawaited(_loadInputDevicesFromJuce());
    }
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
                            _buildInputChannelRouteSelector(),
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
      if (mounted) {
        setState(() {});
      }
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

  List<_InputChannelRouteOption> _buildInputChannelRouteOptions(
      int numInputChannels) {
    if (numInputChannels <= 0) return const <_InputChannelRouteOption>[];

    final options = <_InputChannelRouteOption>[
      for (int ch = 0; ch < numInputChannels; ch++)
        _InputChannelRouteOption(channelStart: ch, channelCount: 1),
      for (int ch = 0; ch + 1 < numInputChannels; ch += 2)
        _InputChannelRouteOption(channelStart: ch, channelCount: 2),
    ];
    return options;
  }

  _InputChannelRouteOption? _findSelectedInputChannelRouteOption(
      List<_InputChannelRouteOption> options) {
    for (final option in options) {
      if (option.channelStart == _selectedChannelStart &&
          option.channelCount == _selectedChannelCount) {
        return option;
      }
    }
    return null;
  }

  void _normalizeInputChannelSelection() {
    if (_numInputChannels <= 0) {
      _selectedChannelStart = 0;
      _selectedChannelCount = 1;
      return;
    }

    _selectedChannelStart =
        _selectedChannelStart.clamp(0, (_numInputChannels - 1).clamp(0, 999));
    _selectedChannelCount = _selectedChannelCount.clamp(
        1, (_numInputChannels - _selectedChannelStart).clamp(1, 999));

    final options = _buildInputChannelRouteOptions(_numInputChannels);
    final selected = _findSelectedInputChannelRouteOption(options);
    if (selected != null) return;

    final monoFallback = options.firstWhere(
      (option) =>
          option.channelCount == 1 &&
          option.channelStart == _selectedChannelStart,
      orElse: () => options.first,
    );
    _selectedChannelStart = monoFallback.channelStart;
    _selectedChannelCount = monoFallback.channelCount;
  }

  Future<void> _loadInputDevicesFromJuce() async {
    if (_loadingDevices) return;
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
      _normalizeInputChannelSelection();

      _loadingDevices = false;
    });
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

    if (_inputDevices.isEmpty) {
      return const Text("No input devices available",
          style: TextStyle(color: Colors.white54));
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
          _normalizeInputChannelSelection();
        });
      },
    );
  }

  Widget _buildInputChannelRouteSelector() {
    final options = _buildInputChannelRouteOptions(_numInputChannels);
    if (options.isEmpty) return const SizedBox.shrink();

    final selected =
        _findSelectedInputChannelRouteOption(options) ?? options.first;

    return DropdownButtonFormField<_InputChannelRouteOption>(
      key: ValueKey(_numInputChannels),
      value: selected,
      isExpanded: true,
      dropdownColor: const Color(0xFF2A2F3D),
      decoration: const InputDecoration(
        labelText: 'Input Channel',
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<_InputChannelRouteOption>(
              value: option,
              child: Text(
                option.label,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: _isRecording
          ? null
          : (option) {
              if (option == null) return;
              _setStateAndRefreshProjectSettings(() {
                _selectedChannelStart = option.channelStart;
                _selectedChannelCount = option.channelCount;
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

  Map<String, dynamic> _toActionMap(dynamic raw) {
    return AssistantActionUtils.toActionMap(raw);
  }

  double? _toActionDouble(dynamic raw) {
    return AssistantActionUtils.toActionDouble(raw);
  }

  int? _toActionInt(dynamic raw) {
    return AssistantActionUtils.toActionInt(raw);
  }

  bool _toActionBool(dynamic raw, {bool fallback = false}) {
    return AssistantActionUtils.toActionBool(raw, fallback: fallback);
  }

  Map<String, dynamic> _actionTarget(Map<String, dynamic> data) {
    return _toActionMap(data['target']);
  }

  List<String> _actionStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  int? _resolveClipIndexFromActionTarget(
    Map<String, dynamic> data, {
    bool requireAudio = false,
    bool requireMidi = false,
  }) {
    bool passesKind(AudioTrack clip) {
      if (requireAudio && clip.isMidi) return false;
      if (requireMidi && !clip.isMidi) return false;
      return true;
    }

    bool isValidIndex(int idx) =>
        idx >= 0 && idx < _audioTracks.length && passesKind(_audioTracks[idx]);

    final target = _actionTarget(data);
    final direct = _toActionInt(data['clip_index']) ??
        _toActionInt(target['clip_index']) ??
        _toActionInt(data['clip']) ??
        _toActionInt(target['clip']);
    if (direct != null && isValidIndex(direct)) return direct;

    final preferSelected = _toActionBool(
      target['prefer_selected'] ?? data['prefer_selected'],
      fallback: true,
    );
    if (preferSelected && isValidIndex(_timelinePrimarySelectedClipIndex)) {
      return _timelinePrimarySelectedClipIndex;
    }

    final selected = _timelineSelectedClipIndices
        .where((i) => isValidIndex(i))
        .toList(growable: false);
    if (preferSelected && selected.length == 1) {
      return selected.first;
    }

    final rowIndex =
        _toActionInt(data['row_index']) ?? _toActionInt(target['row_index']);
    final fileContains =
        (target['file_name_contains'] ?? data['file_name_contains'])
            ?.toString()
            .trim()
            .toLowerCase();
    final labelContains = (target['label_contains'] ?? data['label_contains'])
        ?.toString()
        .trim()
        .toLowerCase();

    final candidates = <int>[];
    for (int i = 0; i < _audioTracks.length; i++) {
      final clip = _audioTracks[i];
      if (!passesKind(clip)) continue;
      if (rowIndex != null && clip.rowIndex != rowIndex) continue;
      if (fileContains != null &&
          fileContains.isNotEmpty &&
          !p.basename(clip.file.path).toLowerCase().contains(fileContains)) {
        continue;
      }
      if (labelContains != null &&
          labelContains.isNotEmpty &&
          !clip.label.toLowerCase().contains(labelContains)) {
        continue;
      }
      candidates.add(i);
    }

    if (candidates.length == 1) return candidates.first;
    if (candidates.length > 1) {
      final selectedIntersect =
          selected.where((i) => candidates.contains(i)).toList();
      if (selectedIntersect.length == 1) return selectedIntersect.first;
      return null;
    }

    if (isValidIndex(_timelinePrimarySelectedClipIndex)) {
      return _timelinePrimarySelectedClipIndex;
    }

    return null;
  }

  List<int> _resolveClipIndicesFromActionTarget(
    Map<String, dynamic> data, {
    bool requireAudio = false,
    bool requireMidi = false,
  }) {
    bool passesKind(AudioTrack clip) {
      if (requireAudio && clip.isMidi) return false;
      if (requireMidi && !clip.isMidi) return false;
      return true;
    }

    bool isValidIndex(int idx) =>
        idx >= 0 && idx < _audioTracks.length && passesKind(_audioTracks[idx]);

    final target = _actionTarget(data);
    final out = LinkedHashSet<int>();

    void add(int? idx) {
      if (idx != null && isValidIndex(idx)) {
        out.add(idx);
      }
    }

    final directListRaw =
        (data['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
    if (directListRaw != null) {
      for (final raw in directListRaw) {
        add(_toActionInt(raw));
      }
    }

    final scope = (target['scope'] ?? data['scope'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (scope == 'selected' || scope == 'selection') {
      for (final idx in _timelineSelectedClipIndices) {
        add(idx);
      }
      add(_timelinePrimarySelectedClipIndex);
    } else if (scope == 'all' ||
        scope == 'all_audio' ||
        scope == 'all_selected_audio') {
      for (int i = 0; i < _audioTracks.length; i++) {
        if (isValidIndex(i)) out.add(i);
      }
    }

    final rowIndex =
        _toActionInt(data['row_index']) ?? _toActionInt(target['row_index']);
    if (rowIndex != null) {
      for (int i = 0; i < _audioTracks.length; i++) {
        final clip = _audioTracks[i];
        if (clip.rowIndex != rowIndex) continue;
        if (!passesKind(clip)) continue;
        out.add(i);
      }
    }

    final single = _resolveClipIndexFromActionTarget(
      data,
      requireAudio: requireAudio,
      requireMidi: requireMidi,
    );
    add(single);

    if (out.isEmpty) {
      for (final idx in _timelineSelectedClipIndices) {
        add(idx);
      }
      add(_timelinePrimarySelectedClipIndex);
    }

    final sorted = out.toList()..sort();
    return sorted;
  }

  int? _pickPreferredClipIndex(List<int> candidates) {
    if (candidates.isEmpty) return null;
    final set = candidates.toSet();
    if (set.contains(_timelinePrimarySelectedClipIndex)) {
      return _timelinePrimarySelectedClipIndex;
    }
    for (final idx in _timelineSelectedClipIndices) {
      if (set.contains(idx)) return idx;
    }
    final sorted = candidates.toList(growable: false)
      ..sort((a, b) {
        final ao =
            (a >= 0 && a < _audioTracks.length) ? _audioTracks[a].offset : 0.0;
        final bo =
            (b >= 0 && b < _audioTracks.length) ? _audioTracks[b].offset : 0.0;
        final byOffset = ao.compareTo(bo);
        if (byOffset != 0) return byOffset;
        return a.compareTo(b);
      });
    return sorted.first;
  }

  int? _resolveSingleClipIndexWithFallback(
    Map<String, dynamic> data, {
    bool requireAudio = false,
    bool requireMidi = false,
  }) {
    final direct = _resolveClipIndexFromActionTarget(
      data,
      requireAudio: requireAudio,
      requireMidi: requireMidi,
    );
    if (direct != null) return direct;
    final candidates = _resolveClipIndicesFromActionTarget(
      data,
      requireAudio: requireAudio,
      requireMidi: requireMidi,
    );
    return _pickPreferredClipIndex(candidates);
  }

  int? _resolveRowIndexFromActionTarget(
    Map<String, dynamic> data, {
    int? fallbackClipIndex,
  }) {
    final target = _actionTarget(data);
    int? row =
        _toActionInt(data['row_index']) ?? _toActionInt(target['row_index']);
    if (row == null && fallbackClipIndex != null) {
      if (fallbackClipIndex >= 0 && fallbackClipIndex < _audioTracks.length) {
        row = _audioTracks[fallbackClipIndex].rowIndex;
      }
    }
    if (row == null && _rowCount > 0) {
      row = _selectedRow.clamp(0, _rowCount - 1);
    }
    if (row == null || _rowCount <= 0) return null;
    return row.clamp(0, _rowCount - 1);
  }

  bool _isKickLikeText(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return false;
    return text.contains('kick') ||
        text.contains('808') ||
        text.contains('bd') ||
        text.contains('bassdrum') ||
        text.contains('bass drum');
  }

  int? _resolveKickSourceClipIndexFromAction(
    Map<String, dynamic> data, {
    int? targetRow,
  }) {
    final target = _actionTarget(data);

    int? parseSourceIndex() {
      final idx = _toActionInt(
        data['source_clip_index'] ??
            target['source_clip_index'] ??
            data['kick_clip_index'] ??
            target['kick_clip_index'] ??
            data['trigger_clip_index'] ??
            target['trigger_clip_index'],
      );
      if (idx == null || idx < 0 || idx >= _audioTracks.length) return null;
      if (_audioTracks[idx].isMidi) return null;
      return idx;
    }

    int? fromIndex = parseSourceIndex();
    if (fromIndex != null) return fromIndex;

    int? sourceRow = _toActionInt(
      data['source_row_index'] ??
          target['source_row_index'] ??
          data['kick_row_index'] ??
          target['kick_row_index'],
    );
    if (sourceRow == null) {
      final sourceRole = (data['source_role'] ??
              target['source_role'] ??
              data['kick_role'] ??
              target['kick_role'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (sourceRole == 'drums' || sourceRole == 'kick') {
        sourceRow = _selectedRow;
      }
    }

    List<int> candidatesForRow(int row) {
      if (row < 0 || row >= _rowCount) return const <int>[];
      final out = <int>[];
      for (int i = 0; i < _audioTracks.length; i++) {
        final clip = _audioTracks[i];
        if (clip.isMidi) continue;
        if (clip.rowIndex != row) continue;
        out.add(i);
      }
      return out;
    }

    if (sourceRow != null) {
      final pick = _pickPreferredClipIndex(candidatesForRow(sourceRow));
      if (pick != null) return pick;
    }

    final kickNameCandidates = <int>[];
    for (int i = 0; i < _audioTracks.length; i++) {
      final clip = _audioTracks[i];
      if (clip.isMidi) continue;
      final file = p.basename(clip.file.path);
      if (_isKickLikeText(clip.label) || _isKickLikeText(file)) {
        kickNameCandidates.add(i);
      }
    }
    final namedKickPick = _pickPreferredClipIndex(kickNameCandidates);
    if (namedKickPick != null) return namedKickPick;

    final selectedAudioCandidates = _timelineSelectedClipIndices
        .where(
            (i) => i >= 0 && i < _audioTracks.length && !_audioTracks[i].isMidi)
        .toList(growable: false);
    final selectedPick = _pickPreferredClipIndex(selectedAudioCandidates);
    if (selectedPick != null) return selectedPick;

    if (targetRow != null) {
      final rowPick = _pickPreferredClipIndex(candidatesForRow(targetRow));
      if (rowPick != null) return rowPick;
    }

    final anyAudio = <int>[];
    for (int i = 0; i < _audioTracks.length; i++) {
      if (!_audioTracks[i].isMidi) anyAudio.add(i);
    }
    return _pickPreferredClipIndex(anyAudio);
  }

  static const Set<String> _supportedTutorialHaloTargets = <String>{
    'tutorial:chatbar',
    'tutorial:toolbar',
    'tutorial:transport:play',
    'tutorial:transport:record',
    'tutorial:transport:restart',
    'tutorial:mute',
    'tutorial:solo',
    'tutorial:export',
    'tutorial:project_settings',
    'tutorial:plugins',
    'tutorial:piano_roll',
    'tutorial:timeline',
  };

  String _tutorialSlug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String? _normalizeTutorialTargetId(String raw) {
    final normalized = AssistantActionUtils.normalizeTutorialTargetId(raw);
    if (normalized == null) return null;
    if (normalized.startsWith('row:')) {
      return normalized;
    }
    if (normalized == 'tutorial:effects_tab' ||
        normalized == 'tutorial:fx_list' ||
        normalized == 'tutorial:add_effect' ||
        normalized == 'tutorial:volume_tab' ||
        normalized == 'tutorial:automation_tab') {
      if (_rowCount <= 0) return 'tutorial:timeline';
      final row = _selectedRow.clamp(0, _rowCount - 1);
      switch (normalized) {
        case 'tutorial:effects_tab':
          return 'row:$row:effects_tab';
        case 'tutorial:fx_list':
          return 'row:$row:fx_list';
        case 'tutorial:add_effect':
          return 'row:$row:add_effect';
        case 'tutorial:volume_tab':
          return 'row:$row:volume_tab';
        case 'tutorial:automation_tab':
          return 'row:$row:automation_tab';
      }
    }
    if (normalized == 'tutorial:piano_roll' &&
        (!_showPianoRoll || _activeMidiClipEngineId == null)) {
      return 'tutorial:timeline';
    }
    if (_supportedTutorialHaloTargets.contains(normalized)) {
      return normalized;
    }
    if (normalized.startsWith('tutorial:')) {
      // Never no-op tutorial actions on unknown anchors; fall back to timeline.
      return 'tutorial:timeline';
    }
    return normalized;
  }

  List<String> _tutorialTargetSequenceForStep(
    Map<String, dynamic> step,
    Map<String, dynamic> rootData,
  ) {
    final out = <String>[];
    void add(String? key) {
      if (key == null) return;
      final trimmed = key.trim();
      if (trimmed.isEmpty || out.contains(trimmed)) return;
      out.add(trimmed);
    }

    final target = _toActionMap(step['target']);
    if (_rowCount <= 0) {
      final rawTarget = (step['target_id'] ??
              target['target_id'] ??
              rootData['target_id'] ??
              _toActionMap(rootData['target'])['target_id'] ??
              '')
          .toString();
      final fallback =
          _normalizeTutorialTargetId(rawTarget) ?? 'tutorial:timeline';
      return <String>[fallback];
    }
    final row = _toActionInt(
          step['row_index'] ??
              target['row_index'] ??
              rootData['row_index'] ??
              _toActionMap(rootData['target'])['row_index'],
        ) ??
        _selectedRow.clamp(0, _rowCount - 1);

    final effectName = (step['effect_name'] ??
            step['plugin_name'] ??
            target['effect_name'] ??
            target['plugin_name'] ??
            rootData['effect_name'] ??
            rootData['plugin_name'])
        .toString()
        .trim();
    final effectSlug = _tutorialSlug(effectName);
    final effectLower = effectName.toLowerCase();
    final effectIndex = _toActionInt(
      step['effect_index'] ??
          target['effect_index'] ??
          rootData['effect_index'] ??
          _toActionMap(rootData['target'])['effect_index'],
    );
    final paramName = (step['param_name'] ??
            step['param_id'] ??
            step['parameter'] ??
            target['param_name'] ??
            target['param_id'] ??
            rootData['param_name'] ??
            rootData['param_id'])
        .toString()
        .trim();
    final paramSlug = _tutorialSlug(paramName);
    final paramLower = paramName.toLowerCase();
    final addEffect = _toActionBool(
      step['show_add_effect'] ??
          step['effect_missing'] ??
          target['show_add_effect'] ??
          target['effect_missing'] ??
          rootData['show_add_effect'] ??
          rootData['effect_missing'],
      fallback: false,
    );

    final rawTarget = (step['target_id'] ??
            target['target_id'] ??
            rootData['target_id'] ??
            _toActionMap(rootData['target'])['target_id'] ??
            '')
        .toString();
    final normalized = _normalizeTutorialTargetId(rawTarget);

    final hasFxDrill =
        effectIndex != null || effectName.isNotEmpty || paramName.isNotEmpty;
    if (hasFxDrill || addEffect) {
      add('row:$row');
      add('row:$row:effects_tab');
      add('row:$row:fx_list');
      if (addEffect) add('row:$row:add_effect');
      if (effectIndex != null) add('row:$row:fx_index:$effectIndex');
      if (effectLower.isNotEmpty) add('row:$row:fx_contains:$effectLower');
      if (effectSlug.isNotEmpty) add('row:$row:fx_contains:$effectSlug');
      if (paramLower.isNotEmpty) add('row:$row:param:$paramLower');
      if (paramSlug.isNotEmpty) add('row:$row:param:$paramSlug');
      if (effectIndex != null && paramLower.isNotEmpty) {
        add('row:$row:fx_index:$effectIndex:param:$paramLower');
      }
      if (effectIndex != null && paramSlug.isNotEmpty) {
        add('row:$row:fx_index:$effectIndex:param:$paramSlug');
      }
      if (effectSlug.isNotEmpty && paramSlug.isNotEmpty) {
        add('row:$row:fx_contains:$effectSlug:param:$paramSlug');
      }
      if (effectLower.isNotEmpty && paramLower.isNotEmpty) {
        add('row:$row:fx_contains:$effectLower:param:$paramLower');
      }
    }

    if (normalized == 'tutorial:mute') {
      add('row:$row:mute');
    } else if (normalized == 'tutorial:solo') {
      add('row:$row:solo');
    } else if (normalized == 'tutorial:plugins') {
      add('row:$row:effects_tab');
      add('row:$row:fx_list');
    } else if (normalized == 'tutorial:timeline') {
      add('row:$row');
    }

    if (normalized != null && normalized.isNotEmpty) {
      add(normalized);
    }
    if (out.isEmpty) {
      add('tutorial:timeline');
    }
    return out;
  }

  Future<void> _applyAssistantActions(List<AssistantAction> actions) async {
    for (final action in actions) {
      final type = action.type.trim().toLowerCase();
      final data = _toActionMap(action.data);
      try {
        switch (type) {
          case 'tutorial':
            await _applyTutorialAction(data);
            break;
          case 'clip_edit':
            await _applyClipEditAction(data);
            break;
          case 'automation_edit':
            await _applyAutomationEditAction(data);
            break;
          case 'midi_compose':
            await _applyMidiComposeAction(data);
            break;
          case 'stem_separate':
            await _applyStemSeparateAction(data);
            break;
          case 'role_override':
            await _applyRoleOverrideAction(data);
            break;
          case 'clarify':
            final q = (data['question'] ?? '').toString().trim();
            if (q.isNotEmpty) {
              final options = _actionStringList(data['options']);
              if (options.isEmpty) {
                _insertAssistantChatText(q);
              } else {
                _insertAssistantChatText(
                    '$q\n\nOptions: ${options.join(' / ')}');
              }
            }
            break;
          default:
            break;
        }
      } catch (e, st) {
        debugPrint('Assistant action failed ($type): $e\n$st');
      }
    }
  }

  Future<void> _applyTutorialAction(Map<String, dynamic> data) async {
    final rawSteps = (data['steps'] as List?) ?? const [];
    final parsed = rawSteps.map(_toActionMap).toList(growable: false);
    final steps = parsed.isEmpty
        ? <Map<String, dynamic>>[data]
        : parsed.take(12).toList(growable: false);

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final sequence = _tutorialTargetSequenceForStep(step, data);
      final drilldown = _toActionBool(
        step['drilldown'] ?? data['drilldown'],
        fallback: true,
      );
      final targets = drilldown
          ? sequence
          : <String>[sequence.isEmpty ? 'tutorial:timeline' : sequence.last];
      if (targets.isEmpty) continue;

      final stepText = (step['text'] ?? '').toString().trim();
      if (stepText.isNotEmpty) {
        _showSmallNotice('Step ${i + 1}/${steps.length}: $stepText');
      }

      final baseDurationMs = (_toActionInt(step['duration_ms']) ??
              _toActionInt(data['duration_ms']) ??
              3200)
          .clamp(1200, 18000);
      final perTargetDurationMs = (targets.length <= 1)
          ? baseDurationMs
          : (baseDurationMs / math.min(targets.length, 3))
              .round()
              .clamp(1100, 4200);

      for (int j = 0; j < targets.length; j++) {
        final key = targets[j];
        _mixHighlighter.clear();
        _mixHighlighter.trigger(
          [HaloKey(key)],
          duration: Duration(milliseconds: perTargetDurationMs),
        );
        final pauseMs = (_toActionInt(step['pause_ms']) ??
                (perTargetDurationMs * 0.72).round())
            .clamp(650, 5200);
        await Future<void>.delayed(Duration(milliseconds: pauseMs));
      }
    }
  }

  String _normalizeClipEditOperation(String raw) {
    return AssistantActionUtils.normalizeClipEditOperation(raw);
  }

  String _normalizeMidiComposeOperation(String raw) {
    return AssistantActionUtils.normalizeMidiComposeOperation(raw);
  }

  MapEntry<double, double>? _estimateAutoTrimBoundsMs(
    AudioTrack clip, {
    double thresholdFloor = 0.012,
    double thresholdRatio = 0.08,
    double paddingMs = 8.0,
  }) {
    return AssistantActionUtils.estimateAutoTrimBoundsMs(
      waveform: clip.normWaveformData,
      fullMs: _clipFullDurationMsForTrim(clip),
      trimStartMs: clip.trimStart.inMilliseconds.toDouble(),
      trimEndMs: clip.trimEnd.inMilliseconds.toDouble(),
      thresholdFloor: thresholdFloor,
      thresholdRatio: thresholdRatio,
      paddingMs: paddingMs,
    );
  }

  Future<void> _applyTrimActionForClip(
    int clipIndex, {
    required double newTrimStartMs,
    required double newTrimEndMs,
    double? newOffsetSec,
  }) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];

    final fullMs = _clipFullDurationMsForTrim(clip).clamp(1.0, 1e12);
    final safeTrimStart = newTrimStartMs.clamp(0.0, fullMs - 50.0).toDouble();
    final safeTrimEnd =
        newTrimEndMs.clamp(safeTrimStart + 50.0, fullMs).toDouble();

    await _undoManager.execute(
      TrimClipAction(
        tracks: _audioTracks,
        originalIndex: clipIndex,
        oldTrimStart: clip.trimStart,
        oldTrimEnd: clip.trimEnd,
        oldOffset: clip.offset,
        newTrimStart: Duration(milliseconds: safeTrimStart.round()),
        newTrimEnd: Duration(milliseconds: safeTrimEnd.round()),
        newOffset: newOffsetSec,
        onChange: () {
          unawaited(_syncClipTimingToEngine(clipIndex));
          _updateOverallDurationIfNeeded();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _setProjectTempoFromDetectedClip(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) return;

    final detected = await _detectClipTempoBpm(clip);
    if (detected == null || !detected.isFinite) return;
    final roundedTempo = detected.round().clamp(40, 240).toDouble();

    _setStateAndRefreshProjectSettings(() {
      clip.sourceTempoBpm = detected;
      _tempo = roundedTempo;
      _tempoStretchEnabled = true;
    });
    await _queueTempoEngineSync();
  }

  Future<void> _applyAutoBpmAlignAction(Map<String, dynamic> data) async {
    final target = _actionTarget(data);
    final clipIndices =
        _resolveClipIndicesFromActionTarget(data, requireAudio: true);
    if (clipIndices.isEmpty) {
      _insertAssistantChatText(
          "I couldn't resolve which audio clips to align. Select clips and ask again.");
      return;
    }

    final preservePitch = _toActionBool(data['preserve_pitch'], fallback: true);
    final setProjectTempo = _toActionBool(
      data['set_project_tempo'] ?? data['detect_set_project_tempo'],
      fallback: false,
    );
    final explicitProjectTempo = _toActionDouble(
        data['project_tempo_bpm'] ?? target['project_tempo_bpm']);

    if (explicitProjectTempo != null && explicitProjectTempo.isFinite) {
      final clampedTempo = _clampTempo(explicitProjectTempo);
      if (clampedTempo != _tempo) {
        _setStateAndRefreshProjectSettings(() => _tempo = clampedTempo);
        await _queueTempoEngineSync();
      }
    } else if (setProjectTempo) {
      final sourceIdx = _toActionInt(
            data['project_tempo_source_clip_index'] ??
                target['project_tempo_source_clip_index'],
          ) ??
          (clipIndices.contains(_timelinePrimarySelectedClipIndex)
              ? _timelinePrimarySelectedClipIndex
              : clipIndices.first);
      await _setProjectTempoFromDetectedClip(sourceIdx);
    }

    for (final idx in clipIndices) {
      await _setClipTempoFollowMode(
        idx,
        preservePitch: preservePitch,
        showFeedback: false,
      );
    }
    _showSmallNotice(
        'Tempo-aligned ${clipIndices.length} clip${clipIndices.length == 1 ? '' : 's'}.');
  }

  double _clipTimelineStartMs(AudioTrack clip) => clip.offset * 1000.0;

  double _clipTimelineEndMs(AudioTrack clip) =>
      _clipTimelineStartMs(clip) + _clipTimelineDurationMs(clip);

  String _normalizedClipPath(String path) => p.normalize(path);

  int? _findAudioClipIndexAtTimelineMs(
    double timelineMs, {
    int? rowIndex,
    String? filePath,
    int? preferEngineClipId,
  }) {
    if (!timelineMs.isFinite) return null;
    final expectedPath =
        filePath == null ? null : _normalizedClipPath(filePath);
    final candidates = <int>[];
    for (int i = 0; i < _audioTracks.length; i++) {
      final clip = _audioTracks[i];
      if (clip.isMidi) continue;
      if (rowIndex != null && clip.rowIndex != rowIndex) continue;
      if (expectedPath != null &&
          _normalizedClipPath(clip.file.path) != expectedPath) {
        continue;
      }
      final startMs = _clipTimelineStartMs(clip);
      final endMs = _clipTimelineEndMs(clip);
      if (timelineMs < startMs - 0.5 || timelineMs > endMs + 0.5) continue;
      candidates.add(i);
    }
    if (candidates.isEmpty) return null;
    if (preferEngineClipId != null && preferEngineClipId >= 0) {
      for (final idx in candidates) {
        if (_audioTracks[idx].engineClipId == preferEngineClipId) {
          return idx;
        }
      }
    }
    candidates.sort((a, b) {
      final aStart = _clipTimelineStartMs(_audioTracks[a]);
      final bStart = _clipTimelineStartMs(_audioTracks[b]);
      final aDist = (aStart - timelineMs).abs();
      final bDist = (bStart - timelineMs).abs();
      final byDist = aDist.compareTo(bDist);
      if (byDist != 0) return byDist;
      return a.compareTo(b);
    });
    return candidates.first;
  }

  List<MapEntry<double, double>> _mergeTimelineRangesMs(
    Iterable<MapEntry<double, double>> ranges, {
    double minGapMs = 45.0,
    double minLengthMs = 25.0,
    double? minMs,
    double? maxMs,
  }) {
    final normalized = <MapEntry<double, double>>[];
    for (final r in ranges) {
      double start = r.key;
      double end = r.value;
      if (!start.isFinite || !end.isFinite) continue;
      if (end < start) {
        final tmp = start;
        start = end;
        end = tmp;
      }
      if (minMs != null || maxMs != null) {
        final lo = minMs ?? double.negativeInfinity;
        final hi = maxMs ?? double.infinity;
        start = start.clamp(lo, hi).toDouble();
        end = end.clamp(lo, hi).toDouble();
      }
      if (!start.isFinite || !end.isFinite) continue;
      if (end - start < minLengthMs) continue;
      normalized.add(MapEntry(start, end));
    }
    if (normalized.isEmpty) return const <MapEntry<double, double>>[];
    normalized.sort((a, b) => a.key.compareTo(b.key));

    final merged = <MapEntry<double, double>>[];
    double currentStart = normalized.first.key;
    double currentEnd = normalized.first.value;

    for (int i = 1; i < normalized.length; i++) {
      final next = normalized[i];
      if (next.key <= currentEnd + minGapMs) {
        currentEnd = math.max(currentEnd, next.value);
      } else {
        merged.add(MapEntry(currentStart, currentEnd));
        currentStart = next.key;
        currentEnd = next.value;
      }
    }
    merged.add(MapEntry(currentStart, currentEnd));
    return merged
        .where((r) => (r.value - r.key) >= minLengthMs)
        .toList(growable: false);
  }

  double _quantile(List<double> values, double q) {
    if (values.isEmpty) return 0.0;
    final sorted = List<double>.from(values)..sort();
    final safeQ = q.clamp(0.0, 1.0).toDouble();
    final pos = safeQ * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final t = pos - lo;
    return sorted[lo] * (1.0 - t) + sorted[hi] * t;
  }

  Future<_ClipMono16kSegment?> _decodeTrimmedClipMono16k(
    AudioTrack clip,
  ) async {
    if (clip.isMidi) return null;
    const sampleRate = 16000;
    Float32List decoded = Float32List(0);
    try {
      decoded = await JuceAudioEngine.decodeAudioMono16k(clip.file.path);
    } catch (_) {
      return null;
    }
    if (decoded.isEmpty) return null;

    int start = (clip.trimStart.inMilliseconds * sampleRate / 1000).round();
    int end = (clip.trimEnd.inMilliseconds * sampleRate / 1000).round();
    start = start.clamp(0, decoded.length);
    end = end.clamp(start, decoded.length);
    if (end <= start + 32) return null;

    final samples = Float32List.fromList(decoded.sublist(start, end));
    if (samples.isEmpty) return null;

    final localDurationMs = samples.length * 1000.0 / sampleRate;
    final timelineDurationMs =
        _clipTimelineDurationMs(clip).clamp(1.0, 1.0e12).toDouble();
    final timelineScale =
        localDurationMs > 0.0 ? timelineDurationMs / localDurationMs : 1.0;
    final timelineStartMs = _clipTimelineStartMs(clip);
    final timelineEndMs = timelineStartMs + localDurationMs * timelineScale;

    return _ClipMono16kSegment(
      samples: samples,
      sampleRate: sampleRate,
      timelineStartMs: timelineStartMs,
      timelineEndMs: timelineEndMs,
      timelineMsPerLocalMs: timelineScale,
    );
  }

  List<double> _frameRmsSeries(
    Float32List samples, {
    int frameSize = 320,
    int hopSize = 160,
  }) {
    if (samples.length < frameSize || hopSize <= 0) return const <double>[];
    final out = <double>[];
    for (int i = 0; i + frameSize <= samples.length; i += hopSize) {
      double sumSq = 0.0;
      for (int j = 0; j < frameSize; j++) {
        final s = samples[i + j];
        sumSq += s * s;
      }
      out.add(math.sqrt(sumSq / frameSize));
    }
    return out;
  }

  List<MapEntry<double, double>> _rangesFromFrameMask(
    List<bool> mask, {
    required int frameSize,
    required int hopSize,
    required int sampleRate,
    required int totalSamples,
    double minDurationMs = 80.0,
  }) {
    if (mask.isEmpty) return const <MapEntry<double, double>>[];
    final out = <MapEntry<double, double>>[];
    int startFrame = -1;

    for (int i = 0; i < mask.length; i++) {
      final active = mask[i];
      if (active && startFrame < 0) {
        startFrame = i;
      }
      final ended = startFrame >= 0 && (!active || i == mask.length - 1);
      if (!ended) continue;

      final endExclusive = (!active) ? i : i + 1;
      final startSample = startFrame * hopSize;
      final endSample =
          math.min(totalSamples, (endExclusive - 1) * hopSize + frameSize);
      final startMs = startSample * 1000.0 / sampleRate;
      final endMs = endSample * 1000.0 / sampleRate;
      if (endMs - startMs >= minDurationMs) {
        out.add(MapEntry(startMs, endMs));
      }
      startFrame = -1;
    }

    return out;
  }

  Future<List<MapEntry<double, double>>> _detectDialogActiveSpeechRangesForClip(
    AudioTrack clip, {
    double minDurationMs = 110.0,
    double mergeGapMs = 120.0,
    double floorRms = 0.01,
    double thresholdMultiplier = 2.35,
  }) async {
    final segment = await _decodeTrimmedClipMono16k(clip);
    if (segment == null) return const <MapEntry<double, double>>[];

    const frameSize = 320;
    const hopSize = 160;
    final rms = _frameRmsSeries(
      segment.samples,
      frameSize: frameSize,
      hopSize: hopSize,
    );
    if (rms.isEmpty) return const <MapEntry<double, double>>[];

    final noiseFloor = _quantile(rms, 0.2);
    final threshold =
        math.max(floorRms, noiseFloor * thresholdMultiplier).toDouble();
    final activeMask = rms.map((v) => v >= threshold).toList(growable: false);
    final localRanges = _rangesFromFrameMask(
      activeMask,
      frameSize: frameSize,
      hopSize: hopSize,
      sampleRate: segment.sampleRate,
      totalSamples: segment.samples.length,
      minDurationMs: minDurationMs,
    );
    if (localRanges.isEmpty) return const <MapEntry<double, double>>[];

    final localDurationMs =
        segment.samples.length * 1000.0 / segment.sampleRate.toDouble();
    final mergedLocal = _mergeTimelineRangesMs(
      localRanges,
      minGapMs: mergeGapMs,
      minLengthMs: minDurationMs,
      minMs: 0.0,
      maxMs: localDurationMs,
    );
    if (mergedLocal.isEmpty) return const <MapEntry<double, double>>[];

    final timelineRanges = mergedLocal
        .map((r) => MapEntry(
              segment.timelineStartMs + r.key * segment.timelineMsPerLocalMs,
              segment.timelineStartMs + r.value * segment.timelineMsPerLocalMs,
            ))
        .toList(growable: false);
    return _mergeTimelineRangesMs(
      timelineRanges,
      minGapMs: mergeGapMs * segment.timelineMsPerLocalMs,
      minLengthMs: minDurationMs * segment.timelineMsPerLocalMs,
      minMs: segment.timelineStartMs,
      maxMs: segment.timelineEndMs,
    );
  }

  MapEntry<double, double>? _deriveDialogPhraseRangeAroundAnchor(
    AudioTrack clip,
    List<MapEntry<double, double>> activeRanges,
    double anchorMs, {
    double prePadMs = 35.0,
    double postPadMs = 70.0,
  }) {
    if (activeRanges.isEmpty) return null;
    final clipStart = _clipTimelineStartMs(clip);
    final clipEnd = _clipTimelineEndMs(clip);
    final probe = anchorMs.clamp(clipStart, clipEnd).toDouble();

    MapEntry<double, double>? best;
    double bestScore = double.infinity;
    for (final r in activeRanges) {
      if (probe >= r.key && probe <= r.value) {
        best = r;
        break;
      }
      final center = (r.key + r.value) * 0.5;
      final dist = (center - probe).abs();
      if (dist < bestScore) {
        bestScore = dist;
        best = r;
      }
    }
    if (best == null) return null;

    final start = (best.key - prePadMs).clamp(clipStart, clipEnd).toDouble();
    final end =
        (best.value + postPadMs).clamp(start + 15.0, clipEnd).toDouble();
    if (end - start < 20.0) return null;
    return MapEntry(start, end);
  }

  List<MapEntry<double, double>> _dialogRangesFromActionDataForClip(
    Map<String, dynamic> data,
    AudioTrack clip, {
    bool preferClipRelative = false,
  }) {
    final target = _actionTarget(data);
    final clipStartMs = _clipTimelineStartMs(clip);
    final clipEndMs = _clipTimelineEndMs(clip);

    bool resolveClipRelative(Map<String, dynamic> source) {
      final explicit = _toActionBool(
        source['clip_relative'] ??
            source['local_ms'] ??
            source['relative_to_clip'],
        fallback: false,
      );
      if (explicit) return true;
      final domain = (source['time_domain'] ??
              source['range_domain'] ??
              source['domain'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (domain == 'clip' ||
          domain == 'local' ||
          domain == 'clip_local' ||
          domain == 'clip_relative') {
        return true;
      }
      return false;
    }

    final out = <MapEntry<double, double>>[];

    void parseRange(Map<String, dynamic> src) {
      final clipRelative = resolveClipRelative(src);
      double? from = _toActionDouble(
        src['from_ms'] ?? src['start_ms'] ?? src['begin_ms'] ?? src['in_ms'],
      );
      double? to = _toActionDouble(
        src['to_ms'] ?? src['end_ms'] ?? src['out_ms'],
      );
      final length = _toActionDouble(src['length_ms'] ?? src['duration_ms']);
      final at = _toActionDouble(src['at_ms'] ?? src['time_ms']);

      if (from == null && at != null && length != null) {
        from = at;
        to = at + length;
      } else if (to == null && from != null && length != null) {
        to = from + length;
      }
      if (from == null || to == null) return;

      if (clipRelative) {
        from += clipStartMs;
        to += clipStartMs;
      }
      if (!from.isFinite || !to.isFinite) return;
      out.add(MapEntry(from, to));
    }

    final rangeLists = <List?>[
      data['ranges'] as List?,
      target['ranges'] as List?,
      data['regions'] as List?,
      target['regions'] as List?,
      data['segments'] as List?,
      target['segments'] as List?,
    ];
    for (final rawList in rangeLists) {
      if (rawList == null) continue;
      for (final raw in rawList) {
        final m = _toActionMap(raw);
        if (m.isEmpty) continue;
        parseRange(m);
      }
    }

    final topRange = <String, dynamic>{
      ...target,
      ...data,
      if (preferClipRelative) 'clip_relative': true,
    };
    parseRange(topRange);

    return _mergeTimelineRangesMs(
      out,
      minGapMs: 10.0,
      minLengthMs: 18.0,
      minMs: clipStartMs,
      maxMs: clipEndMs,
    );
  }

  Future<List<MapEntry<double, double>>> _detectDialogCoughRangesForClip(
    AudioTrack clip, {
    double thresholdStd = 2.2,
    double minDurationMs = 40.0,
    double maxDurationMs = 650.0,
    double prePadMs = 18.0,
    double postPadMs = 120.0,
    double minHighFreqRatio = 0.42,
    int maxRanges = 12,
  }) async {
    final segment = await _decodeTrimmedClipMono16k(clip);
    if (segment == null) return const <MapEntry<double, double>>[];
    const frameSize = 256;
    const hopSize = 128;
    if (segment.samples.length < frameSize) {
      return const <MapEntry<double, double>>[];
    }

    final low = _lowPassMono(
      segment.samples,
      sampleRate: segment.sampleRate,
      cutoffHz: 900.0,
    );

    final scores = <double>[];
    final hfRatios = <double>[];
    for (int i = 0; i + frameSize <= segment.samples.length; i += hopSize) {
      double absSum = 0.0;
      double hfSum = 0.0;
      for (int j = 0; j < frameSize; j++) {
        final s = segment.samples[i + j];
        absSum += s.abs();
        hfSum += (s - low[i + j]).abs();
      }
      final energy = absSum / frameSize;
      final hfRatio = hfSum / (absSum + 1e-9);
      final score = energy * (0.35 + hfRatio);
      scores.add(score);
      hfRatios.add(hfRatio);
    }
    if (scores.length < 6) return const <MapEntry<double, double>>[];

    double mean = 0.0;
    for (final s in scores) {
      mean += s;
    }
    mean /= scores.length;

    double variance = 0.0;
    for (final s in scores) {
      final d = s - mean;
      variance += d * d;
    }
    variance /= scores.length;
    final std = math.sqrt(math.max(variance, 0.0));
    final threshold = math.max(mean + std * thresholdStd, mean * 2.6);

    final local = <MapEntry<double, double>>[];
    int startFrame = -1;
    for (int i = 0; i < scores.length; i++) {
      final hit = scores[i] >= threshold;
      if (hit && startFrame < 0) {
        startFrame = i;
      }
      final ended = startFrame >= 0 && (!hit || i == scores.length - 1);
      if (!ended) continue;

      final endExclusive = (!hit) ? i : i + 1;
      final segmentStartSample = startFrame * hopSize;
      final segmentEndSample = math.min(
        segment.samples.length,
        (endExclusive - 1) * hopSize + frameSize,
      );
      final durMs =
          (segmentEndSample - segmentStartSample) * 1000.0 / segment.sampleRate;
      if (durMs >= minDurationMs && durMs <= maxDurationMs) {
        double ratioSum = 0.0;
        int count = 0;
        for (int f = startFrame; f < endExclusive; f++) {
          ratioSum += hfRatios[f];
          count++;
        }
        final avgRatio = count > 0 ? ratioSum / count : 0.0;
        if (avgRatio >= minHighFreqRatio) {
          final startMs = segmentStartSample * 1000.0 / segment.sampleRate;
          final endMs = segmentEndSample * 1000.0 / segment.sampleRate;
          local.add(
            MapEntry(
              math.max(0.0, startMs - prePadMs),
              endMs + postPadMs,
            ),
          );
        }
      }
      startFrame = -1;
    }

    if (local.isEmpty) return const <MapEntry<double, double>>[];
    final localDurationMs =
        segment.samples.length * 1000.0 / segment.sampleRate.toDouble();
    final mergedLocal = _mergeTimelineRangesMs(
      local,
      minGapMs: 70.0,
      minLengthMs: minDurationMs,
      minMs: 0.0,
      maxMs: localDurationMs,
    );
    if (mergedLocal.isEmpty) return const <MapEntry<double, double>>[];

    final timeline = mergedLocal
        .take(maxRanges)
        .map((r) => MapEntry(
              segment.timelineStartMs + r.key * segment.timelineMsPerLocalMs,
              segment.timelineStartMs + r.value * segment.timelineMsPerLocalMs,
            ))
        .toList(growable: false);

    return _mergeTimelineRangesMs(
      timeline,
      minGapMs: 80.0,
      minLengthMs: minDurationMs * segment.timelineMsPerLocalMs,
      minMs: segment.timelineStartMs,
      maxMs: segment.timelineEndMs,
    );
  }

  Future<List<MapEntry<double, double>>> _detectDialogQuietRangesForClip(
    AudioTrack clip, {
    double quietRatio = 0.62,
    double minDurationMs = 180.0,
    int maxRanges = 10,
  }) async {
    final segment = await _decodeTrimmedClipMono16k(clip);
    if (segment == null) return const <MapEntry<double, double>>[];

    const frameSize = 320;
    const hopSize = 160;
    final rms = _frameRmsSeries(
      segment.samples,
      frameSize: frameSize,
      hopSize: hopSize,
    );
    if (rms.length < 6) return const <MapEntry<double, double>>[];

    final noiseFloor = _quantile(rms, 0.2);
    final activeThreshold = math.max(0.008, noiseFloor * 2.2);
    final activeMask = rms.map((v) => v >= activeThreshold).toList();
    final activeRms = <double>[];
    for (int i = 0; i < rms.length; i++) {
      if (activeMask[i]) activeRms.add(rms[i]);
    }
    if (activeRms.length < 3) return const <MapEntry<double, double>>[];

    final speechTargetRms = _quantile(activeRms, 0.68);
    final quietThreshold =
        math.max(noiseFloor * 2.0, speechTargetRms * quietRatio);
    final quietMask = List<bool>.generate(
      rms.length,
      (i) => activeMask[i] && rms[i] < quietThreshold,
      growable: false,
    );
    final localRanges = _rangesFromFrameMask(
      quietMask,
      frameSize: frameSize,
      hopSize: hopSize,
      sampleRate: segment.sampleRate,
      totalSamples: segment.samples.length,
      minDurationMs: minDurationMs,
    );
    if (localRanges.isEmpty) return const <MapEntry<double, double>>[];

    final localDurationMs =
        segment.samples.length * 1000.0 / segment.sampleRate.toDouble();
    final mergedLocal = _mergeTimelineRangesMs(
      localRanges,
      minGapMs: 80.0,
      minLengthMs: minDurationMs,
      minMs: 0.0,
      maxMs: localDurationMs,
    );
    if (mergedLocal.isEmpty) return const <MapEntry<double, double>>[];

    final timeline = mergedLocal
        .take(maxRanges)
        .map((r) => MapEntry(
              segment.timelineStartMs + r.key * segment.timelineMsPerLocalMs,
              segment.timelineStartMs + r.value * segment.timelineMsPerLocalMs,
            ))
        .toList(growable: false);

    return _mergeTimelineRangesMs(
      timeline,
      minGapMs: 90.0,
      minLengthMs: minDurationMs * segment.timelineMsPerLocalMs,
      minMs: segment.timelineStartMs,
      maxMs: segment.timelineEndMs,
    );
  }

  Future<List<MapEntry<double, double>>> _detectDialogPauseRemovalRangesForClip(
    AudioTrack clip, {
    double minPauseMs = 260.0,
    double keepPauseMs = 90.0,
    int maxRanges = 14,
  }) async {
    final activeRanges = await _detectDialogActiveSpeechRangesForClip(
      clip,
      minDurationMs: 110.0,
      mergeGapMs: 120.0,
    );
    if (activeRanges.length < 2) return const <MapEntry<double, double>>[];

    final clipStart = _clipTimelineStartMs(clip);
    final clipEnd = _clipTimelineEndMs(clip);
    final out = <MapEntry<double, double>>[];

    for (int i = 1; i < activeRanges.length; i++) {
      final prev = activeRanges[i - 1];
      final next = activeRanges[i];
      final pauseStart = prev.value;
      final pauseEnd = next.key;
      final pauseLength = pauseEnd - pauseStart;
      if (pauseLength < minPauseMs) continue;

      final keep = keepPauseMs.clamp(20.0, pauseLength - 20.0).toDouble();
      if (pauseLength <= keep + 20.0) continue;

      final removeStart =
          (pauseStart + keep * 0.5).clamp(clipStart, clipEnd).toDouble();
      final removeEnd =
          (pauseEnd - keep * 0.5).clamp(removeStart + 15.0, clipEnd).toDouble();
      if (removeEnd - removeStart >= 20.0) {
        out.add(MapEntry(removeStart, removeEnd));
      }
      if (out.length >= maxRanges) break;
    }

    return _mergeTimelineRangesMs(
      out,
      minGapMs: 50.0,
      minLengthMs: 20.0,
      minMs: clipStart,
      maxMs: clipEnd,
    );
  }

  Future<int?> _isolateTimelineRangeAsClipSegment({
    required double fromMs,
    required double toMs,
    required int rowIndex,
    required String filePath,
    int? preferEngineClipId,
  }) async {
    if (!fromMs.isFinite || !toMs.isFinite) return null;
    double safeFrom = math.min(fromMs, toMs);
    double safeTo = math.max(fromMs, toMs);
    if (safeTo - safeFrom < 20.0) return null;

    final midProbeInitial = (safeFrom + safeTo) * 0.5;
    int? targetIdx = _findAudioClipIndexAtTimelineMs(
      midProbeInitial,
      rowIndex: rowIndex,
      filePath: filePath,
      preferEngineClipId: preferEngineClipId,
    );
    if (targetIdx == null) return null;

    final targetClip = _audioTracks[targetIdx];
    final clipStart = _clipTimelineStartMs(targetClip);
    final clipEnd = _clipTimelineEndMs(targetClip);
    safeFrom = safeFrom.clamp(clipStart, clipEnd - 2.0).toDouble();
    safeTo = safeTo.clamp(safeFrom + 2.0, clipEnd).toDouble();
    if (safeTo - safeFrom < 20.0) return null;

    if (safeFrom > clipStart + 1.0) {
      await _handleCutClipAt(targetIdx, safeFrom);
    }

    final midProbe = (safeFrom + safeTo) * 0.5;
    int? midIdx = _findAudioClipIndexAtTimelineMs(
      midProbe,
      rowIndex: rowIndex,
      filePath: filePath,
      preferEngineClipId: preferEngineClipId,
    );
    if (midIdx == null) return null;

    final midClip = _audioTracks[midIdx];
    final midStart = _clipTimelineStartMs(midClip);
    final midEnd = _clipTimelineEndMs(midClip);
    final cutEnd = safeTo.clamp(midStart + 1.0, midEnd).toDouble();
    if (cutEnd < midEnd - 1.0) {
      await _handleCutClipAt(midIdx, cutEnd);
    }

    return _findAudioClipIndexAtTimelineMs(
      midProbe,
      rowIndex: rowIndex,
      filePath: filePath,
      preferEngineClipId: preferEngineClipId,
    );
  }

  Future<bool> _removeTimelineRangeFromClip({
    required double fromMs,
    required double toMs,
    required int rowIndex,
    required String filePath,
    int? preferEngineClipId,
  }) async {
    final isolatedIdx = await _isolateTimelineRangeAsClipSegment(
      fromMs: fromMs,
      toMs: toMs,
      rowIndex: rowIndex,
      filePath: filePath,
      preferEngineClipId: preferEngineClipId,
    );
    if (isolatedIdx == null ||
        isolatedIdx < 0 ||
        isolatedIdx >= _audioTracks.length) {
      return false;
    }
    await _handleDeleteClip(isolatedIdx);
    return true;
  }

  Future<bool> _boostTimelineRangeOnClip({
    required double fromMs,
    required double toMs,
    required int rowIndex,
    required String filePath,
    required double gainMultiplier,
    required double maxGain,
    int? preferEngineClipId,
  }) async {
    final isolatedIdx = await _isolateTimelineRangeAsClipSegment(
      fromMs: fromMs,
      toMs: toMs,
      rowIndex: rowIndex,
      filePath: filePath,
      preferEngineClipId: preferEngineClipId,
    );
    if (isolatedIdx == null ||
        isolatedIdx < 0 ||
        isolatedIdx >= _audioTracks.length) {
      return false;
    }
    final clip = _audioTracks[isolatedIdx];
    final oldGain = clip.gain;
    final nextGain = (oldGain * gainMultiplier).clamp(0.0, maxGain).toDouble();
    if ((nextGain - oldGain).abs() < 0.015) return false;

    await _undoManager.execute(
      SetClipGainAction(
        tracks: _audioTracks,
        originalIndex: isolatedIdx,
        oldGain: oldGain,
        newGain: nextGain,
        applyToState: (target, gain) {
          target.gain = gain;
          if (mounted) setState(() {});
        },
      ),
    );
    return true;
  }

  Future<int> _applyDialogRangeDeletesForClip(
    AudioTrack clip,
    List<MapEntry<double, double>> ranges, {
    int maxEdits = 12,
  }) async {
    if (ranges.isEmpty) return 0;
    final row = clip.rowIndex;
    final filePath = clip.file.path;
    final preferredEngine = clip.engineClipId >= 0 ? clip.engineClipId : null;
    final ordered = List<MapEntry<double, double>>.from(ranges)
      ..sort((a, b) => b.key.compareTo(a.key));

    int applied = 0;
    for (final range in ordered.take(maxEdits)) {
      final ok = await _removeTimelineRangeFromClip(
        fromMs: range.key,
        toMs: range.value,
        rowIndex: row,
        filePath: filePath,
        preferEngineClipId: preferredEngine,
      );
      if (ok) applied++;
    }
    return applied;
  }

  Future<int> _applyDialogLiftForClip(
    AudioTrack clip,
    List<MapEntry<double, double>> ranges, {
    required double gainMultiplier,
    required double maxGain,
    int maxEdits = 8,
  }) async {
    if (ranges.isEmpty) return 0;
    final row = clip.rowIndex;
    final filePath = clip.file.path;
    final preferredEngine = clip.engineClipId >= 0 ? clip.engineClipId : null;
    final ordered = List<MapEntry<double, double>>.from(ranges)
      ..sort((a, b) => b.key.compareTo(a.key));

    int applied = 0;
    for (final range in ordered.take(maxEdits)) {
      final ok = await _boostTimelineRangeOnClip(
        fromMs: range.key,
        toMs: range.value,
        rowIndex: row,
        filePath: filePath,
        preferEngineClipId: preferredEngine,
        gainMultiplier: gainMultiplier,
        maxGain: maxGain,
      );
      if (ok) applied++;
    }
    return applied;
  }

  Future<void> _applyDialogClipEditOperation(
    Map<String, dynamic> data, {
    required String operation,
  }) async {
    final target = _actionTarget(data);
    final clipIndices =
        _resolveClipIndicesFromActionTarget(data, requireAudio: true);
    if (clipIndices.isEmpty) {
      _insertAssistantChatText(
          "I couldn't resolve which audio clip to edit. Select a clip and ask again.");
      return;
    }

    final maxEdits = (_toActionInt(
              data['max_edits'] ?? target['max_edits'] ?? data['max_events'],
            ) ??
            10)
        .clamp(1, 48);
    final anchorMs = (_toActionDouble(
              data['at_ms'] ??
                  target['at_ms'] ??
                  data['time_ms'] ??
                  target['time_ms'],
            ) ??
            _globalAudioClock.inMilliseconds.toDouble())
        .toDouble();

    int deletedSegments = 0;
    int liftedSegments = 0;
    int touchedClips = 0;

    for (final clipIndex in clipIndices) {
      if (clipIndex < 0 || clipIndex >= _audioTracks.length) continue;
      final clip = _audioTracks[clipIndex];
      if (clip.isMidi) continue;

      if (operation == 'dialog_cleanup') {
        final manual = _dialogRangesFromActionDataForClip(
          data,
          clip,
          preferClipRelative: true,
        );
        final detected = await _detectDialogCoughRangesForClip(
          clip,
          thresholdStd: (_toActionDouble(data['artifact_threshold_std'] ??
                      target['artifact_threshold_std'] ??
                      data['transient_threshold_std'] ??
                      target['transient_threshold_std']) ??
                  2.2)
              .clamp(0.8, 4.8)
              .toDouble(),
          minDurationMs: (_toActionDouble(
                      data['min_event_ms'] ?? target['min_event_ms']) ??
                  40.0)
              .clamp(15.0, 1200.0)
              .toDouble(),
          maxDurationMs: (_toActionDouble(
                      data['max_event_ms'] ?? target['max_event_ms']) ??
                  650.0)
              .clamp(80.0, 2500.0)
              .toDouble(),
          minHighFreqRatio: (_toActionDouble(
                      data['min_hf_ratio'] ?? target['min_hf_ratio']) ??
                  0.42)
              .clamp(0.2, 0.9)
              .toDouble(),
          maxRanges: maxEdits,
        );
        final ranges = manual.isNotEmpty ? manual : detected;
        if (ranges.isEmpty) continue;
        final removed = await _applyDialogRangeDeletesForClip(
          clip,
          ranges,
          maxEdits: maxEdits,
        );
        if (removed > 0) {
          deletedSegments += removed;
          touchedClips++;
        }
        continue;
      }

      if (operation == 'dialog_remove_range') {
        var ranges = _dialogRangesFromActionDataForClip(
          data,
          clip,
          preferClipRelative: true,
        );
        if (ranges.isEmpty) {
          final clipStart = _clipTimelineStartMs(clip);
          final clipEnd = _clipTimelineEndMs(clip);
          final inClip = anchorMs >= clipStart && anchorMs <= clipEnd;
          if (!inClip && clipIndices.length > 1) {
            continue;
          }
          final active = await _detectDialogActiveSpeechRangesForClip(clip);
          final phrase = _deriveDialogPhraseRangeAroundAnchor(
            clip,
            active,
            anchorMs,
            prePadMs: (_toActionDouble(data['phrase_pre_pad_ms'] ??
                        target['phrase_pre_pad_ms']) ??
                    35.0)
                .clamp(0.0, 400.0)
                .toDouble(),
            postPadMs: (_toActionDouble(data['phrase_post_pad_ms'] ??
                        target['phrase_post_pad_ms']) ??
                    70.0)
                .clamp(0.0, 500.0)
                .toDouble(),
          );
          if (phrase != null) {
            ranges = <MapEntry<double, double>>[phrase];
          }
        }
        if (ranges.isEmpty) continue;
        final removed = await _applyDialogRangeDeletesForClip(
          clip,
          ranges,
          maxEdits: maxEdits,
        );
        if (removed > 0) {
          deletedSegments += removed;
          touchedClips++;
        }
        continue;
      }

      if (operation == 'dialog_tighten_pauses') {
        final ranges = await _detectDialogPauseRemovalRangesForClip(
          clip,
          minPauseMs: (_toActionDouble(
                      data['min_pause_ms'] ?? target['min_pause_ms']) ??
                  260.0)
              .clamp(80.0, 6000.0)
              .toDouble(),
          keepPauseMs: (_toActionDouble(
                      data['keep_pause_ms'] ?? target['keep_pause_ms']) ??
                  90.0)
              .clamp(20.0, 1400.0)
              .toDouble(),
          maxRanges: maxEdits,
        );
        if (ranges.isEmpty) continue;
        final removed = await _applyDialogRangeDeletesForClip(
          clip,
          ranges,
          maxEdits: maxEdits,
        );
        if (removed > 0) {
          deletedSegments += removed;
          touchedClips++;
        }
        continue;
      }

      if (operation == 'dialog_lift_quiet') {
        var ranges = _dialogRangesFromActionDataForClip(
          data,
          clip,
          preferClipRelative: true,
        );
        if (ranges.isEmpty) {
          ranges = await _detectDialogQuietRangesForClip(
            clip,
            quietRatio: (_toActionDouble(
                        data['quiet_ratio'] ?? target['quiet_ratio']) ??
                    0.62)
                .clamp(0.2, 0.95)
                .toDouble(),
            minDurationMs: (_toActionDouble(
                        data['min_quiet_ms'] ?? target['min_quiet_ms']) ??
                    180.0)
                .clamp(40.0, 3000.0)
                .toDouble(),
            maxRanges: maxEdits,
          );
        }
        if (ranges.isEmpty) continue;

        final boostDb = (_toActionDouble(
                  data['boost_db'] ??
                      target['boost_db'] ??
                      data['gain_db'] ??
                      target['gain_db'],
                ) ??
                4.0)
            .clamp(0.5, 12.0)
            .toDouble();
        final gainMultiplier = math.pow(10.0, boostDb / 20.0).toDouble();
        final maxGain =
            (_toActionDouble(data['max_gain'] ?? target['max_gain']) ?? 3.0)
                .clamp(0.2, 3.0)
                .toDouble();

        final lifted = await _applyDialogLiftForClip(
          clip,
          ranges,
          gainMultiplier: gainMultiplier,
          maxGain: maxGain,
          maxEdits: maxEdits,
        );
        if (lifted > 0) {
          liftedSegments += lifted;
          touchedClips++;
        }
      }
    }

    final totalEdits = deletedSegments + liftedSegments;
    if (totalEdits <= 0) {
      switch (operation) {
        case 'dialog_cleanup':
          _insertAssistantChatText(
              'No clear cough/noise events were detected in the target clip.');
          break;
        case 'dialog_remove_range':
          _insertAssistantChatText(
              "I couldn't resolve a dialog segment to remove. Provide a time range or place the playhead near the sentence.");
          break;
        case 'dialog_tighten_pauses':
          _insertAssistantChatText('No long pauses were found to tighten.');
          break;
        case 'dialog_lift_quiet':
          _insertAssistantChatText(
              'No quiet speech ranges were found to lift.');
          break;
        default:
          break;
      }
      return;
    }

    if (operation == 'dialog_lift_quiet' && liftedSegments > 0) {
      _showSmallNotice(
          'Boosted $liftedSegments quiet segment${liftedSegments == 1 ? '' : 's'} on $touchedClips clip${touchedClips == 1 ? '' : 's'}.');
      return;
    }

    _showSmallNotice(
        'Edited $deletedSegments dialog segment${deletedSegments == 1 ? '' : 's'} on $touchedClips clip${touchedClips == 1 ? '' : 's'}.');
  }

  Future<void> _applyClipEditAction(Map<String, dynamic> data) async {
    final rawOperation =
        (data['operation'] ?? '').toString().trim().toLowerCase();
    final operation = _normalizeClipEditOperation(
      rawOperation,
    );

    if (operation == 'auto_bpm_align') {
      await _applyAutoBpmAlignAction(data);
      return;
    }

    if (operation == 'auto_trim') {
      final clipIndices =
          _resolveClipIndicesFromActionTarget(data, requireAudio: true);
      if (clipIndices.isEmpty) {
        _insertAssistantChatText(
            "I couldn't resolve which audio clips to trim. Select clips and ask again.");
        return;
      }

      final thresholdFloor =
          _toActionDouble(data['threshold_floor'])?.clamp(0.001, 1.0) ?? 0.012;
      final thresholdRatio =
          _toActionDouble(data['threshold_ratio'])?.clamp(0.001, 1.0) ?? 0.08;
      final paddingMs =
          _toActionDouble(data['padding_ms'])?.clamp(0.0, 500.0) ?? 8.0;
      final preserveContentPosition =
          _toActionBool(data['preserve_content_position'], fallback: true);

      bool anyApplied = false;
      for (final clipIndex in clipIndices) {
        if (clipIndex < 0 || clipIndex >= _audioTracks.length) continue;
        final clip = _audioTracks[clipIndex];
        if (clip.isMidi) continue;

        final explicitTrimStartMs = _toActionDouble(data['trim_start_ms']);
        final explicitTrimEndMs = _toActionDouble(data['trim_end_ms']);
        final estimated = _estimateAutoTrimBoundsMs(
          clip,
          thresholdFloor: thresholdFloor.toDouble(),
          thresholdRatio: thresholdRatio.toDouble(),
          paddingMs: paddingMs.toDouble(),
        );

        final nextTrimStartMs = explicitTrimStartMs ?? estimated?.key;
        final nextTrimEndMs = explicitTrimEndMs ?? estimated?.value;
        if (nextTrimStartMs == null || nextTrimEndMs == null) continue;

        final startDeltaSec =
            (nextTrimStartMs - clip.trimStart.inMilliseconds.toDouble()) /
                1000.0;
        final nextOffset = preserveContentPosition
            ? math.max(0.0, clip.offset + startDeltaSec)
            : null;

        await _applyTrimActionForClip(
          clipIndex,
          newTrimStartMs: nextTrimStartMs,
          newTrimEndMs: nextTrimEndMs,
          newOffsetSec: nextOffset,
        );
        anyApplied = true;
      }

      if (!anyApplied) {
        _insertAssistantChatText(
            'No silence boundaries were detected for the target clip(s).');
      }
      return;
    }

    if (operation == 'trim') {
      final target = _actionTarget(data);
      final clipIndices =
          _resolveClipIndicesFromActionTarget(data, requireAudio: true);
      if (clipIndices.isEmpty) {
        _insertAssistantChatText(
            "I couldn't resolve which audio clips to trim. Select clips and ask again.");
        return;
      }

      final explicitTrimStartMs =
          _toActionDouble(data['trim_start_ms'] ?? target['trim_start_ms']);
      final explicitTrimEndMs =
          _toActionDouble(data['trim_end_ms'] ?? target['trim_end_ms']);
      final deltaTrimStartMs = _toActionDouble(
          data['delta_trim_start_ms'] ?? target['delta_trim_start_ms']);
      final deltaTrimEndMs = _toActionDouble(
          data['delta_trim_end_ms'] ?? target['delta_trim_end_ms']);
      final hasExplicitTrimValues = explicitTrimStartMs != null ||
          explicitTrimEndMs != null ||
          deltaTrimStartMs != null ||
          deltaTrimEndMs != null;

      final sideHint = (data['trim_side'] ??
              target['trim_side'] ??
              data['side'] ??
              target['side'] ??
              data['edge'] ??
              target['edge'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      final trimStartOnlyHint = sideHint.contains('start') ||
          sideHint.contains('left') ||
          sideHint == 'in' ||
          sideHint == 'head' ||
          sideHint.contains('begin');
      final trimEndOnlyHint = sideHint.contains('end') ||
          sideHint.contains('right') ||
          sideHint == 'out' ||
          sideHint == 'tail';

      final thresholdFloor = _toActionDouble(
            data['threshold_floor'] ?? target['threshold_floor'],
          )?.clamp(0.001, 1.0) ??
          0.012;
      final thresholdRatio = _toActionDouble(
            data['threshold_ratio'] ?? target['threshold_ratio'],
          )?.clamp(0.001, 1.0) ??
          0.08;
      final paddingMs =
          _toActionDouble(data['padding_ms'] ?? target['padding_ms'])
                  ?.clamp(0.0, 500.0) ??
              8.0;
      final preserveContentPosition = _toActionBool(
        data['preserve_content_position'] ??
            target['preserve_content_position'],
        fallback: true,
      );
      final fallbackTrimNudgeMs = (_toActionDouble(
                  data['fallback_trim_ms'] ?? target['fallback_trim_ms']) ??
              120.0)
          .clamp(10.0, 2000.0)
          .toDouble();

      bool anyApplied = false;
      for (final clipIndex in clipIndices) {
        if (clipIndex < 0 || clipIndex >= _audioTracks.length) continue;
        final clip = _audioTracks[clipIndex];
        if (clip.isMidi) continue;

        final oldTrimStartMs = clip.trimStart.inMilliseconds.toDouble();
        final oldTrimEndMs = clip.trimEnd.inMilliseconds.toDouble();
        double? nextTrimStartMs = explicitTrimStartMs;
        double? nextTrimEndMs = explicitTrimEndMs;

        if (nextTrimStartMs == null && deltaTrimStartMs != null) {
          nextTrimStartMs = oldTrimStartMs + deltaTrimStartMs;
        }
        if (nextTrimEndMs == null && deltaTrimEndMs != null) {
          nextTrimEndMs = oldTrimEndMs + deltaTrimEndMs;
        }

        if (!hasExplicitTrimValues &&
            nextTrimStartMs == null &&
            nextTrimEndMs == null) {
          final estimated = _estimateAutoTrimBoundsMs(
            clip,
            thresholdFloor: thresholdFloor.toDouble(),
            thresholdRatio: thresholdRatio.toDouble(),
            paddingMs: paddingMs.toDouble(),
          );
          if (estimated != null) {
            if (trimEndOnlyHint && !trimStartOnlyHint) {
              nextTrimEndMs = estimated.value;
            } else if (trimStartOnlyHint && !trimEndOnlyHint) {
              nextTrimStartMs = estimated.key;
            } else {
              nextTrimStartMs = estimated.key;
              nextTrimEndMs = estimated.value;
            }
          }
        }

        nextTrimStartMs ??= oldTrimStartMs;
        nextTrimEndMs ??= oldTrimEndMs;

        if ((nextTrimStartMs - oldTrimStartMs).abs() < 0.5 &&
            (nextTrimEndMs - oldTrimEndMs).abs() < 0.5) {
          if (trimEndOnlyHint && !trimStartOnlyHint) {
            nextTrimEndMs = oldTrimEndMs - fallbackTrimNudgeMs;
          } else {
            nextTrimStartMs = oldTrimStartMs + fallbackTrimNudgeMs;
          }
        }

        if ((nextTrimStartMs - oldTrimStartMs).abs() < 0.5 &&
            (nextTrimEndMs - oldTrimEndMs).abs() < 0.5) {
          continue;
        }

        final explicitNewStartMs = _toActionDouble(
          data['new_start_ms'] ??
              target['new_start_ms'] ??
              data['start_ms'] ??
              target['start_ms'],
        );
        final startDeltaSec = (nextTrimStartMs - oldTrimStartMs) / 1000.0;
        final newOffsetSec = explicitNewStartMs != null
            ? math.max(0.0, explicitNewStartMs / 1000.0)
            : (preserveContentPosition
                ? math.max(0.0, clip.offset + startDeltaSec)
                : null);

        await _applyTrimActionForClip(
          clipIndex,
          newTrimStartMs: nextTrimStartMs,
          newTrimEndMs: nextTrimEndMs,
          newOffsetSec: newOffsetSec,
        );
        anyApplied = true;
      }

      if (!anyApplied) {
        _insertAssistantChatText(
            'Could not trim the target clip(s). Try selecting the clip and asking again.');
      } else {
        _showSmallNotice(
            'Trimmed ${clipIndices.length} clip${clipIndices.length == 1 ? '' : 's'}.');
      }
      return;
    }

    if (operation == 'dialog_cleanup' ||
        operation == 'dialog_remove_range' ||
        operation == 'dialog_tighten_pauses' ||
        operation == 'dialog_lift_quiet') {
      await _applyDialogClipEditOperation(
        data,
        operation: operation,
      );
      return;
    }

    int? resolveSingleClipIndex({
      bool requireAudio = false,
      bool requireMidi = false,
      String failureMessage =
          "I couldn't resolve which clip to edit. Select a clip and ask again.",
    }) {
      final idx = _resolveSingleClipIndexWithFallback(
        data,
        requireAudio: requireAudio,
        requireMidi: requireMidi,
      );
      if (idx == null) {
        _insertAssistantChatText(failureMessage);
        return null;
      }
      if (idx < 0 || idx >= _audioTracks.length) return null;
      return idx;
    }

    switch (operation) {
      case 'cut':
        {
          final clipIndex = resolveSingleClipIndex(
            failureMessage:
                "I couldn't resolve which clip to cut. Select a clip and ask again.",
          );
          if (clipIndex == null) return;
          final clip = _audioTracks[clipIndex];
          final target = _actionTarget(data);
          final hasMidiChopHint = (rawOperation.contains('note') ||
                  rawOperation.contains('chop') ||
                  rawOperation.contains('splice') ||
                  rawOperation.contains('slice')) ||
              data.containsKey('subdivision') ||
              data.containsKey('subdivision_divisor') ||
              data.containsKey('grid') ||
              data.containsKey('resolution') ||
              target.containsKey('subdivision') ||
              target.containsKey('subdivision_divisor') ||
              target.containsKey('grid') ||
              target.containsKey('resolution');
          if (clip.isMidi && hasMidiChopHint) {
            final midiActionData = <String, dynamic>{
              ...data,
              'operation': 'chop_notes',
              'target': <String, dynamic>{
                ...target,
                'clip_index': clipIndex,
              },
            };
            await _applyMidiComposeAction(midiActionData);
            break;
          }
          final startMs = clip.offset * 1000.0;
          final endMs = startMs + _clipTimelineDurationMs(clip);
          final cutMs = _toActionDouble(data['cut_ms'] ?? data['time_ms']) ??
              ((startMs + endMs) / 2.0);
          await _handleCutClipAt(clipIndex, cutMs);
          _showSmallNotice('Cut clip.');
          break;
        }
      case 'move':
        {
          final target = _actionTarget(data);
          final clipIndices = _resolveClipIndicesFromActionTarget(data);
          if (clipIndices.isEmpty) {
            _insertAssistantChatText(
                "I couldn't resolve which clip(s) to move. Select clip(s) and ask again.");
            return;
          }

          int? clampRow(int? row) {
            if (row == null || _rowCount <= 0) return null;
            return row.clamp(0, _rowCount - 1);
          }

          final explicitStartMs = _toActionDouble(
            data['new_start_ms'] ??
                target['new_start_ms'] ??
                data['start_ms'] ??
                target['start_ms'],
          );
          final explicitDeltaMs = _toActionDouble(
            data['delta_ms'] ??
                target['delta_ms'] ??
                data['offset_ms'] ??
                target['offset_ms'] ??
                data['shift_ms'] ??
                target['shift_ms'],
          );
          final explicitDestRow = clampRow(
            _toActionInt(
              data['new_row_index'] ??
                  target['new_row_index'] ??
                  data['destination_row_index'] ??
                  target['destination_row_index'] ??
                  data['to_row_index'] ??
                  target['to_row_index'],
            ),
          );
          final explicitRowHint = clampRow(
            _toActionInt(data['row_index']) ??
                _toActionInt(target['row_index']),
          );
          final explicitRowDelta = _toActionInt(
                data['delta_rows'] ??
                    target['delta_rows'] ??
                    data['row_delta'] ??
                    target['row_delta'],
              ) ??
              0;
          final direction = (data['direction'] ?? target['direction'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final snapTo = (data['snap_to'] ??
                  target['snap_to'] ??
                  data['position'] ??
                  target['position'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();

          double moveStepMs = (_toActionDouble(
                    data['step_ms'] ??
                        target['step_ms'] ??
                        data['distance_ms'] ??
                        target['distance_ms'] ??
                        data['amount_ms'] ??
                        target['amount_ms'],
                  ) ??
                  0.0)
              .abs();
          if (moveStepMs < 1.0) {
            moveStepMs = (60000.0 / _tempo.clamp(1.0, 400.0))
                .clamp(1.0, 60000.0)
                .toDouble();
          }

          int directionRowDelta = 0;
          double directionStartDeltaMs = 0.0;
          bool moveToStart = snapTo.contains('start') ||
              snapTo.contains('begin') ||
              snapTo == 'zero';
          switch (direction) {
            case 'left':
            case 'earlier':
            case 'back':
            case 'backward':
              directionStartDeltaMs = -moveStepMs;
              break;
            case 'right':
            case 'later':
            case 'forward':
              directionStartDeltaMs = moveStepMs;
              break;
            case 'up':
            case 'above':
              directionRowDelta = -1;
              break;
            case 'down':
            case 'below':
              directionRowDelta = 1;
              break;
            case 'start':
            case 'beginning':
            case 'zero':
              moveToStart = true;
              break;
            default:
              break;
          }

          final hasHorizontalInstruction = explicitStartMs != null ||
              explicitDeltaMs != null ||
              directionStartDeltaMs != 0.0 ||
              moveToStart;
          final hasVerticalInstruction = explicitDestRow != null ||
              explicitRowDelta != 0 ||
              directionRowDelta != 0;

          // Last-resort fallback: if move is under-specified, default to
          // "move to timeline start" to avoid silent no-op actions.
          if (!hasHorizontalInstruction && !hasVerticalInstruction) {
            moveToStart = true;
          }

          bool anyApplied = false;
          for (final clipIndex in clipIndices) {
            if (clipIndex < 0 || clipIndex >= _audioTracks.length) continue;
            final clip = _audioTracks[clipIndex];
            final oldStartMs = clip.offset * 1000.0;
            final oldRow = clip.rowIndex;

            double nextStartMs = oldStartMs;
            if (explicitStartMs != null) {
              nextStartMs = explicitStartMs;
            } else if (explicitDeltaMs != null) {
              nextStartMs = oldStartMs + explicitDeltaMs;
            } else if (directionStartDeltaMs != 0.0) {
              nextStartMs = oldStartMs + directionStartDeltaMs;
            } else if (moveToStart) {
              nextStartMs = 0.0;
            }
            nextStartMs = math.max(0.0, nextStartMs);

            int nextRow = oldRow;
            if (explicitDestRow != null) {
              nextRow = explicitDestRow;
            } else if (directionRowDelta != 0) {
              nextRow = clampRow(oldRow + directionRowDelta) ?? oldRow;
            } else if (explicitRowDelta != 0) {
              nextRow = clampRow(oldRow + explicitRowDelta) ?? oldRow;
            } else if (clipIndices.length == 1 &&
                explicitRowHint != null &&
                explicitRowHint != oldRow) {
              // If there is a single target clip, treat row_index as destination
              // when no other row destination signal exists.
              nextRow = explicitRowHint;
            }

            final rowChanged = nextRow != oldRow;
            final startChanged = (nextStartMs - oldStartMs).abs() > 0.5;
            if (!rowChanged && !startChanged) continue;

            await _undoManager.execute(
              MoveClipAction(
                tracks: _audioTracks,
                originalIndex: clipIndex,
                oldOffset: clip.offset,
                oldRow: clip.rowIndex,
                newOffset: nextStartMs / 1000.0,
                newRow: nextRow,
                onChange: () {
                  clip.rowId = _rowIdAt(clip.rowIndex);
                  unawaited(_syncClipTimingToEngine(clipIndex));
                  _updateOverallDurationIfNeeded();
                },
              ),
            );
            anyApplied = true;
          }

          if (!anyApplied) {
            _insertAssistantChatText(
                "I couldn't apply that move because no destination or timing change was resolved.");
            return;
          }

          if (mounted) setState(() {});
          _showSmallNotice(
            'Moved ${clipIndices.length} clip${clipIndices.length == 1 ? '' : 's'}.',
          );
          break;
        }
      case 'stretch':
        {
          final clipIndex = resolveSingleClipIndex();
          if (clipIndex == null) return;
          final clip = _audioTracks[clipIndex];
          final target = _actionTarget(data);
          final explicitDurationMs = _toActionDouble(
            data['timeline_duration_ms'] ??
                data['duration_ms'] ??
                target['timeline_duration_ms'] ??
                target['duration_ms'] ??
                data['new_duration_ms'] ??
                target['new_duration_ms'],
          );
          final deltaDurationMs = _toActionDouble(
            data['delta_duration_ms'] ??
                target['delta_duration_ms'] ??
                data['duration_delta_ms'] ??
                target['duration_delta_ms'],
          );
          final factor = _toActionDouble(
            data['factor'] ??
                target['factor'] ??
                data['stretch_factor'] ??
                target['stretch_factor'] ??
                data['scale'] ??
                target['scale'],
          );
          final oldDurationMs = _clipTimelineDurationMs(clip);
          final durationMs = explicitDurationMs ??
              ((deltaDurationMs != null)
                  ? (oldDurationMs + deltaDurationMs)
                  : ((factor != null) ? (oldDurationMs * factor) : null));
          if (durationMs == null || clip.isMidi) {
            _insertAssistantChatText(
                "I couldn't resolve the new clip length to stretch.");
            return;
          }
          final newStartMs =
              _toActionDouble(data['new_start_ms'] ?? data['start_ms']);
          _handleStretchClipResize(
            clipIndex,
            durationMs,
            newStartMs: newStartMs,
          );
          await _handleStretchClipResizeCommit(clipIndex);
          _showSmallNotice('Stretched clip.');
          break;
        }
      case 'tempo_follow':
        {
          final targets =
              _resolveClipIndicesFromActionTarget(data, requireAudio: true);
          if (targets.isEmpty) {
            _insertAssistantChatText(
                "I couldn't resolve which audio clips to tempo-align.");
            return;
          }
          final preservePitch =
              _toActionBool(data['preserve_pitch'], fallback: true);
          for (final idx in targets) {
            await _setClipTempoFollowMode(
              idx,
              preservePitch: preservePitch,
              showFeedback: false,
            );
          }
          _showSmallNotice(
              'Tempo mode updated for ${targets.length} clip${targets.length == 1 ? '' : 's'}.');
          break;
        }
      case 'tempo_detect_set_project':
        {
          final clipIndex = resolveSingleClipIndex(requireAudio: true);
          if (clipIndex == null) return;
          final clip = _audioTracks[clipIndex];
          if (clip.isMidi) return;
          await _setProjectTempoFromDetectedClip(clipIndex);
          final preservePitch =
              _toActionBool(data['preserve_pitch'], fallback: true);
          await _setClipTempoFollowMode(
            clipIndex,
            preservePitch: preservePitch,
          );
          _showSmallNotice('Detected clip tempo and updated project tempo.');
          break;
        }
      case 'delete':
        {
          final clipIndices = _resolveClipIndicesFromActionTarget(data);
          if (clipIndices.isEmpty) {
            final clipIndex = resolveSingleClipIndex();
            if (clipIndex == null) return;
            await _handleDeleteClip(clipIndex);
            _showSmallNotice('Deleted clip.');
            break;
          }
          await _handleDeleteClips(clipIndices);
          _showSmallNotice(
              'Deleted ${clipIndices.length} clip${clipIndices.length == 1 ? '' : 's'}.');
        }
        break;
      case 'duplicate':
        {
          final clipIndex = resolveSingleClipIndex();
          if (clipIndex == null) return;
          final clip = _audioTracks[clipIndex];
          _handleCopyClip(clipIndex);
          final row = _resolveRowIndexFromActionTarget(
                data,
                fallbackClipIndex: clipIndex,
              ) ??
              clip.rowIndex;
          final pasteMs = _toActionDouble(data['paste_start_ms']) ??
              ((clip.offset * 1000.0) + _clipTimelineDurationMs(clip));
          await _handlePasteClipAt(row, pasteMs);
          _showSmallNotice('Duplicated clip.');
          break;
        }
      default:
        _insertAssistantChatText(
            'Unsupported clip edit operation "$operation".');
        break;
    }
  }

  double _maxAutomationTimelineMs() {
    return math.max(1.0, _audioOnlyOverallDuration.inMilliseconds.toDouble());
  }

  String _pluginAutomationTargetId(int effectIndex, String paramId) {
    return 'fx:$effectIndex:$paramId';
  }

  String _pluginAutomationEffectKey(String effectId, int ordinal) {
    final base = effectId.trim().isEmpty ? 'effect' : effectId.trim();
    final safeOrdinal = ordinal < 0 ? 0 : ordinal;
    return '$base#$safeOrdinal';
  }

  String _encodeAutomationIdComponent(String raw) {
    return Uri.encodeComponent(raw.trim());
  }

  String _decodeAutomationIdComponent(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  String _pluginAutomationTargetIdFromEffectKey(
    String effectKey,
    String paramId,
  ) {
    return 'fxid:${_encodeAutomationIdComponent(effectKey)}:${_encodeAutomationIdComponent(paramId)}';
  }

  _ParsedAutomationTargetId _parseAutomationTargetId(String targetId) {
    final trimmed = targetId.trim();
    if (trimmed == 'volume') {
      return const _ParsedAutomationTargetId(
        isVolume: true,
        legacyEffectIndex: -1,
        effectKey: '',
        paramId: 'volume',
      );
    }

    if (trimmed.startsWith('fxid:')) {
      final payload = trimmed.substring('fxid:'.length);
      final splitAt = payload.indexOf(':');
      if (splitAt > 0) {
        final encodedEffectKey = payload.substring(0, splitAt);
        final encodedParamId = payload.substring(splitAt + 1);
        return _ParsedAutomationTargetId(
          isVolume: false,
          legacyEffectIndex: -1,
          effectKey: _decodeAutomationIdComponent(encodedEffectKey),
          paramId: _decodeAutomationIdComponent(encodedParamId),
        );
      }
    }

    final parts = trimmed.split(':');
    if (parts.length >= 3 && parts.first == 'fx') {
      return _ParsedAutomationTargetId(
        isVolume: false,
        legacyEffectIndex: int.tryParse(parts[1]) ?? -1,
        effectKey: '',
        paramId: parts.sublist(2).join(':'),
      );
    }

    return _ParsedAutomationTargetId(
      isVolume: false,
      legacyEffectIndex: -1,
      effectKey: '',
      paramId: trimmed,
    );
  }

  List<AutomationClipSnapshot> _copyAutomationClipList(
    List<AutomationClipSnapshot> clips,
  ) {
    return clips.map((c) => c.copyWith()).toList(growable: false);
  }

  String _automationTargetLabelFor(int row, String targetId) {
    return _rowAutomationTargets[row]?[targetId]?.label ??
        _fallbackAutomationTargetMeta(targetId).label;
  }

  _AutomationTargetMeta _volumeAutomationTargetMeta() {
    return const _AutomationTargetMeta(
      targetId: 'volume',
      label: 'Volume',
      effectIndex: -1,
      paramId: 'volume',
      type: 'float',
      min: 0.0,
      max: 1.0,
      initialNormalized: 0.75,
    );
  }

  _AutomationTargetMeta _fallbackAutomationTargetMeta(String targetId) {
    if (targetId == 'volume') return _volumeAutomationTargetMeta();
    final parsed = _parseAutomationTargetId(targetId);
    return _AutomationTargetMeta(
      targetId: targetId,
      label: parsed.paramId.isNotEmpty ? parsed.paramId : targetId,
      effectIndex: parsed.legacyEffectIndex,
      paramId: parsed.paramId,
      type: 'float',
      min: 0.0,
      max: 1.0,
      initialNormalized: targetId == 'volume' ? 0.75 : 0.5,
    );
  }

  double _normalizeAutomationValue(
    double? rawValue, {
    required double min,
    required double max,
    double fallback = 0.5,
  }) {
    if (rawValue == null) return fallback.clamp(0.0, 1.0).toDouble();
    final span = max - min;
    if (!span.isFinite || span.abs() < 1e-9) {
      return fallback.clamp(0.0, 1.0).toDouble();
    }
    return ((rawValue - min) / span).clamp(0.0, 1.0).toDouble();
  }

  double _denormalizeAutomationValue(
    double normalized,
    _AutomationTargetMeta target,
  ) {
    if (target.isVolume) {
      return normalized.clamp(0.0, 1.0).toDouble();
    }
    final span = target.max - target.min;
    if (!span.isFinite || span.abs() < 1e-9) {
      return target.min;
    }
    return target.min + span * normalized.clamp(0.0, 1.0).toDouble();
  }

  List<Map<String, dynamic>> _toNormalizedAutomationMaps(
    List<AutomationPoint> points,
  ) {
    return points
        .map((p) => <String, dynamic>{
              'x': p.x,
              'value': p.volume.clamp(0.0, 1.0),
            })
        .toList(growable: false);
  }

  Future<void> _syncNativeAutomationForRow(int row) async {
    if (row < 0 || row >= _rowCount) return;

    final resolvedVolume = _resolvedAutomationPointsForTarget(row, 'volume');
    await JuceAudioEngine.setTrackAutomationPoints(
      row,
      _toMaps(resolvedVolume),
    );

    await JuceAudioEngine.clearTrackEffectAutomationForRow(row);

    final rowPlugin =
        _rowPluginAutomation[row] ?? const <String, List<AutomationPoint>>{};
    if (rowPlugin.isEmpty) {
      return;
    }

    final targets =
        _rowAutomationTargets[row] ?? const <String, _AutomationTargetMeta>{};
    for (final entry in rowPlugin.entries) {
      final targetId = entry.key;
      final target =
          targets[targetId] ?? _fallbackAutomationTargetMeta(targetId);
      if (target.isVolume) continue;
      if (target.effectIndex < 0) continue;
      if (target.paramId.trim().isEmpty) continue;

      final safePoints = _resolvedAutomationPointsForTarget(row, targetId);
      await JuceAudioEngine.setTrackEffectAutomationPoints(
        row,
        target.effectIndex,
        target.paramId,
        target.min,
        target.max,
        _toNormalizedAutomationMaps(safePoints),
      );
    }
  }

  Future<void> _syncNativePluginAutomationForRow(int row) async {
    await _syncNativeAutomationForRow(row);
  }

  Future<void> _syncNativeAutomationForAllRows() async {
    for (int row = 0; row < _rowCount; row++) {
      await _syncNativeAutomationForRow(row);
    }
  }

  Future<void> _syncNativePluginAutomationForAllRows() async {
    await _syncNativeAutomationForAllRows();
  }

  Future<void> _refreshAutomationTargetsForRow(
    int row, {
    bool setStateWhenDone = true,
    bool syncNativeWhenDone = true,
  }) async {
    if (row < 0 || row >= _rowCount) return;

    final previousTargets = Map<String, _AutomationTargetMeta>.from(
      _rowAutomationTargets[row] ?? const <String, _AutomationTargetMeta>{},
    );
    final discovered = <String, _AutomationTargetMeta>{
      'volume': _volumeAutomationTargetMeta(),
    };
    final discoveredByEffectKeyAndParam = <String, _AutomationTargetMeta>{};
    final discoveredByLegacyIndexAndParam = <String, _AutomationTargetMeta>{};
    final discoveredByParam = <String, List<_AutomationTargetMeta>>{};

    final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
    var effectInstanceIds =
        await JuceAudioEngine.getTrackEffectInstanceIdsForRow(row);
    if (effectInstanceIds.length != effects.length) {
      effectInstanceIds = List<String>.filled(effects.length, '');
    }
    var effectIds = await JuceAudioEngine.getTrackEffectIdsForRow(row);
    if (effectIds.length != effects.length) {
      effectIds = List<String>.from(effects);
    }
    final effectOrdinalById = <String, int>{};
    for (int effectIndex = 0; effectIndex < effects.length; effectIndex++) {
      final params =
          await JuceAudioEngine.getTrackPluginParameters(row, effectIndex);
      final effectName = effects[effectIndex].trim();
      final rawInstanceId = (effectIndex < effectInstanceIds.length
              ? effectInstanceIds[effectIndex]
              : '')
          .trim();
      final rawEffectId =
          (effectIndex < effectIds.length ? effectIds[effectIndex] : effectName)
              .trim();
      final effectIdentity = rawEffectId.isNotEmpty
          ? rawEffectId
          : (effectName.isNotEmpty ? effectName : 'effect');
      final effectOrdinal = effectOrdinalById.update(
        effectIdentity,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final effectKey = rawInstanceId.isNotEmpty
          ? 'inst:$rawInstanceId'
          : _pluginAutomationEffectKey(effectIdentity, effectOrdinal);
      for (final p in params) {
        final type = (p['type'] ?? '').toString().trim().toLowerCase();
        if (type != 'float') continue;

        final rawId = (p['id'] ?? p['name'] ?? '').toString().trim();
        final rawName = (p['name'] ?? rawId).toString().trim();
        if (rawId.isEmpty || rawName.isEmpty) continue;

        final min = (p['min'] as num?)?.toDouble() ?? 0.0;
        final max = (p['max'] as num?)?.toDouble() ?? 1.0;
        final targetId =
            _pluginAutomationTargetIdFromEffectKey(effectKey, rawId);
        final label = effectName.isEmpty ? rawName : '$effectName • $rawName';
        final previousTarget = previousTargets[targetId];
        final fallbackNormalized =
            (previousTarget?.initialNormalized ?? 0.5).clamp(0.0, 1.0);
        final currentNormalized = _normalizeAutomationValue(
          (p['value'] as num?)?.toDouble(),
          min: min,
          max: max,
          fallback: fallbackNormalized,
        );

        discovered[targetId] = _AutomationTargetMeta(
          targetId: targetId,
          label: label,
          effectIndex: effectIndex,
          paramId: rawId,
          type: type,
          min: min,
          max: max,
          initialNormalized: currentNormalized,
        );
        final paramLower = rawId.toLowerCase();
        discoveredByEffectKeyAndParam['$effectKey\u0000$paramLower'] =
            discovered[targetId]!;
        discoveredByLegacyIndexAndParam['$effectIndex\u0000$paramLower'] =
            discovered[targetId]!;
        discoveredByParam
            .putIfAbsent(paramLower, () => <_AutomationTargetMeta>[])
            .add(discovered[targetId]!);
      }
    }

    _AutomationTargetMeta? resolveRemappedTarget(String originalTargetId) {
      if (originalTargetId == 'volume') return discovered['volume'];
      final existing = discovered[originalTargetId];
      if (existing != null) return existing;

      final previousMeta = previousTargets[originalTargetId] ??
          _fallbackAutomationTargetMeta(originalTargetId);
      final parsed = _parseAutomationTargetId(originalTargetId);
      final normalizedParamId =
          (parsed.paramId.isNotEmpty ? parsed.paramId : previousMeta.paramId)
              .trim()
              .toLowerCase();
      if (normalizedParamId.isEmpty) return null;

      if (parsed.effectKey.isNotEmpty) {
        final byEffectKey = discoveredByEffectKeyAndParam[
            '${parsed.effectKey}\u0000$normalizedParamId'];
        if (byEffectKey != null) return byEffectKey;
      }

      if (parsed.legacyEffectIndex >= 0) {
        final byLegacy = discoveredByLegacyIndexAndParam[
            '${parsed.legacyEffectIndex}\u0000$normalizedParamId'];
        if (byLegacy != null) return byLegacy;
      }

      final candidates = discoveredByParam[normalizedParamId] ??
          const <_AutomationTargetMeta>[];
      if (candidates.isEmpty) return null;

      final previousLabelLower = previousMeta.label.trim().toLowerCase();
      if (previousLabelLower.isNotEmpty) {
        final byLabel = candidates
            .where((candidate) =>
                candidate.label.trim().toLowerCase() == previousLabelLower)
            .toList(growable: false);
        if (byLabel.length == 1) {
          return byLabel.first;
        }
      }

      if (previousMeta.effectIndex >= 0) {
        final byEffectIndex = candidates
            .where((candidate) =>
                candidate.effectIndex == previousMeta.effectIndex)
            .toList(growable: false);
        if (byEffectIndex.length == 1) {
          return byEffectIndex.first;
        }
      }

      if (candidates.length == 1) {
        return candidates.first;
      }

      return null;
    }

    final pluginByTarget = Map<String, List<AutomationPoint>>.from(
      _rowPluginAutomation[row] ?? const <String, List<AutomationPoint>>{},
    );
    final remappedPlugin = <String, List<AutomationPoint>>{};
    for (final entry in pluginByTarget.entries) {
      final originalTargetId = entry.key;
      if (originalTargetId == 'volume') continue;

      final resolvedTarget = resolveRemappedTarget(originalTargetId);
      if (resolvedTarget == null) continue;
      final resolvedTargetId = resolvedTarget.targetId;

      final safePoints = _sanitizeAutomationPointsForTarget(
        row,
        resolvedTargetId,
        entry.value,
      );
      final existing =
          remappedPlugin[resolvedTargetId] ?? const <AutomationPoint>[];
      remappedPlugin[resolvedTargetId] = _sanitizeAutomationPointsForTarget(
        row,
        resolvedTargetId,
        <AutomationPoint>[
          ...existing.map((p) => p.copy()),
          ...safePoints.map((p) => p.copy()),
        ],
      );
    }

    final clipsByTarget = Map<String, List<AutomationClipSnapshot>>.from(
      _rowAutomationClips[row] ??
          const <String, List<AutomationClipSnapshot>>{},
    );
    final remappedClips = <String, List<AutomationClipSnapshot>>{};
    for (final entry in clipsByTarget.entries) {
      final originalTargetId = entry.key;
      if (originalTargetId == 'volume') {
        remappedClips[originalTargetId] = _sanitizeAutomationClipsForTarget(
          row,
          originalTargetId,
          entry.value.map((c) => c.copyWith()).toList(growable: false),
        );
        continue;
      }

      final resolvedTarget = resolveRemappedTarget(originalTargetId);
      if (resolvedTarget == null) continue;
      final resolvedTargetId = resolvedTarget.targetId;

      final safeClips = _sanitizeAutomationClipsForTarget(
        row,
        resolvedTargetId,
        entry.value.map((c) => c.copyWith()).toList(growable: false),
      );
      if (safeClips.isEmpty) continue;
      final existing =
          remappedClips[resolvedTargetId] ?? const <AutomationClipSnapshot>[];
      remappedClips[resolvedTargetId] = _sanitizeAutomationClipsForTarget(
        row,
        resolvedTargetId,
        <AutomationClipSnapshot>[
          ...existing.map((c) => c.copyWith()),
          ...safeClips.map((c) => c.copyWith()),
        ],
      );
    }

    _rowPluginAutomation[row] = remappedPlugin;
    _rowAutomationClips[row] = remappedClips;
    _rowAutomationTargets[row] = discovered;
    final selected = _rowSelectedAutomationTarget[row];
    if (selected == null || !discovered.containsKey(selected)) {
      final fallback = discovered.containsKey('volume')
          ? 'volume'
          : (discovered.keys.isNotEmpty ? discovered.keys.first : 'volume');
      _rowSelectedAutomationTarget[row] = fallback;
    }

    if (setStateWhenDone && mounted) {
      setState(() {});
    }

    if (syncNativeWhenDone) {
      await _syncNativePluginAutomationForRow(row);
    }
  }

  Future<void> _refreshAutomationTargetsForAllRows() async {
    for (int row = 0; row < _rowCount; row++) {
      await _refreshAutomationTargetsForRow(
        row,
        setStateWhenDone: false,
        syncNativeWhenDone: false,
      );
      await _syncNativePluginAutomationForRow(row);
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _automationTargetsForRowUi(int row) {
    if (row < 0 || row >= _rowCount) return const <Map<String, dynamic>>[];
    final targets = _rowAutomationTargets[row] ??
        <String, _AutomationTargetMeta>{
          'volume': _volumeAutomationTargetMeta()
        };
    final values = targets.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isVolume && !b.isVolume) return -1;
        if (!a.isVolume && b.isVolume) return 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return values.map((e) => e.toUiMap()).toList(growable: false);
  }

  String _selectedAutomationTargetIdForRow(int row) {
    if (row < 0 || row >= _rowCount) return 'volume';
    final selected = _rowSelectedAutomationTarget[row];
    if (selected != null &&
        (_rowAutomationTargets[row]?.containsKey(selected) ?? false)) {
      return selected;
    }
    return 'volume';
  }

  void _setSelectedAutomationTargetIdForRow(int row, String targetId) {
    if (row < 0 || row >= _rowCount) return;
    final targets = _rowAutomationTargets[row] ??
        <String, _AutomationTargetMeta>{
          'volume': _volumeAutomationTargetMeta()
        };
    if (!targets.containsKey(targetId)) {
      targetId = 'volume';
    }
    _rowSelectedAutomationTarget[row] = targetId;
    if (mounted) setState(() {});
  }

  List<AutomationPoint> _defaultAutomationPointsForTarget(
    int row,
    String targetId,
  ) {
    double normalized = targetId == 'volume' ? 0.75 : 0.5;
    final target = _rowAutomationTargets[row]?[targetId];
    if (target != null) {
      normalized = target.initialNormalized.clamp(0.0, 1.0).toDouble();
    }
    return <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: normalized),
    ];
  }

  List<AutomationClipSnapshot> _clipsForAutomationTarget(
    int row,
    String targetId,
  ) {
    if (row < 0 || row >= _rowCount) return const <AutomationClipSnapshot>[];
    final rowMap = _rowAutomationClips[row];
    final existing = rowMap?[targetId];
    if (existing == null) return const <AutomationClipSnapshot>[];
    return existing;
  }

  List<AutomationPoint> _sanitizeAutomationClipPointsRelative(
    double lengthMs,
    List<AutomationPoint> points, {
    required double fallbackValue,
  }) {
    final safeLength = lengthMs.clamp(50.0, double.infinity).toDouble();
    final sanitized = points
        .map((p) => AutomationPoint(
              x: p.x.clamp(0.0, safeLength).toDouble(),
              volume: p.volume.clamp(0.0, 1.0).toDouble(),
            ))
        .toList(growable: false)
      ..sort((a, b) => a.x.compareTo(b.x));

    if (sanitized.isEmpty) {
      final fallback = fallbackValue.clamp(0.0, 1.0).toDouble();
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: fallback),
      ];
    }
    if (sanitized.length == 1) {
      final only = sanitized.first;
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: only.volume),
      ];
    }
    return sanitized;
  }

  List<AutomationClipSnapshot> _sanitizeAutomationClipsForTarget(
    int row,
    String targetId,
    List<AutomationClipSnapshot> clips,
  ) {
    final maxMs = _maxAutomationTimelineMs();
    final fallbackValue = targetId == 'volume' ? 0.75 : 0.5;
    final targetLabel = _automationTargetLabelFor(row, targetId);
    final seenIds = <String>{};
    int idCounter = 0;

    final out = <AutomationClipSnapshot>[];
    for (final clip in clips) {
      final safeLength = clip.lengthMs.clamp(50.0, maxMs).toDouble();
      final maxStart = math.max(0.0, maxMs - safeLength);
      final safeStart = clip.startMs.clamp(0.0, maxStart).toDouble();

      var id = clip.id.trim();
      if (id.isEmpty || seenIds.contains(id)) {
        id = 'ac_${row}_${targetId}_${idCounter}_${const Uuid().v4()}';
      }
      idCounter++;
      seenIds.add(id);

      final safePoints = _sanitizeAutomationClipPointsRelative(
        safeLength,
        clip.points,
        fallbackValue: fallbackValue,
      );

      out.add(
        clip.copyWith(
          id: id,
          row: row,
          targetId: targetId,
          lane: math.max(0, clip.lane),
          label: clip.label.trim().isEmpty ? targetLabel : clip.label.trim(),
          startMs: safeStart,
          lengthMs: safeLength,
          points: safePoints,
        ),
      );
    }

    out.sort((a, b) {
      final timeCmp = a.startMs.compareTo(b.startMs);
      if (timeCmp != 0) return timeCmp;
      return a.id.compareTo(b.id);
    });
    return out;
  }

  List<AutomationPoint> _pointsForAutomationTarget(int row, String targetId) {
    if (row < 0 || row >= _rowCount) return const <AutomationPoint>[];
    if (targetId == 'volume') return _rowVolumeAutomation[row];
    final rowMap = _rowPluginAutomation[row];
    final existing = rowMap?[targetId];
    if (existing != null) return existing;
    return _defaultAutomationPointsForTarget(row, targetId);
  }

  List<AutomationPoint> _sanitizeAutomationPointsForTarget(
    int row,
    String targetId,
    List<AutomationPoint> points,
  ) {
    final maxMs = _maxAutomationTimelineMs();
    final sanitized = points
        .map((p) => AutomationPoint(
              x: p.x.clamp(0.0, maxMs).toDouble(),
              volume: p.volume.clamp(0.0, 1.0).toDouble(),
            ))
        .toList(growable: false)
      ..sort((a, b) => a.x.compareTo(b.x));

    if (sanitized.isEmpty) {
      final defaults = _defaultAutomationPointsForTarget(row, targetId);
      return defaults.map((p) => p.copy()).toList(growable: false);
    }

    if (sanitized.length == 1) {
      final only = sanitized.first;
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: only.volume),
      ];
    }
    return sanitized;
  }

  double _evaluateAutomationClipAtRelativeMs(
    AutomationClipSnapshot clip,
    double relativeMs, {
    double fallback = 0.5,
  }) {
    final safeRel = relativeMs.clamp(0.0, clip.lengthMs).toDouble();
    return _evaluateAutomationAtMs(clip.points, safeRel, fallback: fallback);
  }

  double _resolvedAutomationValueAtMs(
    int row,
    String targetId,
    double timeMs, {
    List<AutomationPoint>? lanePointsOverride,
    List<AutomationClipSnapshot>? clipOverride,
  }) {
    final lanePoints = lanePointsOverride ??
        _sanitizeAutomationPointsForTarget(
          row,
          targetId,
          _pointsForAutomationTarget(row, targetId),
        );
    final baseValue = _evaluateAutomationAtMs(
      lanePoints,
      timeMs,
      fallback: targetId == 'volume' ? 0.75 : 0.5,
    );

    final clips = clipOverride ??
        _sanitizeAutomationClipsForTarget(
          row,
          targetId,
          _clipsForAutomationTarget(row, targetId),
        );
    if (clips.isEmpty) return baseValue;

    AutomationClipSnapshot? active;
    for (final clip in clips) {
      if (clip.muted) continue;
      final start = clip.startMs;
      final end = clip.startMs + clip.lengthMs;
      if (timeMs + 1e-6 < start || timeMs - 1e-6 > end) continue;
      if (active == null || clip.startMs >= active.startMs) {
        active = clip;
      }
    }
    if (active == null) return baseValue;
    final rel = timeMs - active.startMs;
    return _evaluateAutomationClipAtRelativeMs(
      active,
      rel,
      fallback: baseValue,
    );
  }

  List<AutomationPoint> _resolvedAutomationPointsForTarget(
    int row,
    String targetId,
  ) {
    final maxMs = _maxAutomationTimelineMs();
    final lanePoints = _sanitizeAutomationPointsForTarget(
      row,
      targetId,
      _pointsForAutomationTarget(row, targetId),
    );
    final clips = _sanitizeAutomationClipsForTarget(
      row,
      targetId,
      _clipsForAutomationTarget(row, targetId),
    );
    if (clips.isEmpty) {
      return lanePoints.map((p) => p.copy()).toList(growable: false);
    }

    final times = <double>{0.0, maxMs};
    for (final p in lanePoints) {
      times.add(p.x.clamp(0.0, maxMs).toDouble());
    }
    for (final clip in clips) {
      final start = clip.startMs.clamp(0.0, maxMs).toDouble();
      final end = (clip.startMs + clip.lengthMs).clamp(0.0, maxMs).toDouble();
      if (end <= start) continue;
      times.add(start);
      times.add(end);
      times.add((start - 0.001).clamp(0.0, maxMs).toDouble());
      times.add((end + 0.001).clamp(0.0, maxMs).toDouble());
      for (final p in clip.points) {
        final abs = (clip.startMs + p.x).clamp(start, end).toDouble();
        times.add(abs);
      }
    }

    final sortedTimes = times.toList(growable: false)..sort();
    final out = <AutomationPoint>[];
    double? lastX;
    double? lastValue;
    for (final t in sortedTimes) {
      final x = t.clamp(0.0, maxMs).toDouble();
      if (lastX != null && (x - lastX).abs() < 1e-7) {
        continue;
      }
      final value = _resolvedAutomationValueAtMs(
        row,
        targetId,
        x,
        lanePointsOverride: lanePoints,
        clipOverride: clips,
      ).clamp(0.0, 1.0);
      if (lastValue != null && lastX != null) {
        final unchanged = (value - lastValue).abs() < 1e-7;
        if (unchanged && (x - lastX).abs() < 0.0005) {
          continue;
        }
      }
      out.add(AutomationPoint(x: x, volume: value.toDouble()));
      lastX = x;
      lastValue = value.toDouble();
    }

    return _sanitizeAutomationPointsForTarget(row, targetId, out);
  }

  double _evaluateAutomationAtMs(
    List<AutomationPoint> points,
    double timeMs, {
    double fallback = 0.5,
  }) {
    if (points.isEmpty) return fallback;
    if (timeMs <= points.first.x) return points.first.volume;
    if (timeMs >= points.last.x) return points.last.volume;
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (timeMs < a.x || timeMs > b.x) continue;
      final span = (b.x - a.x).abs();
      if (span < 1e-6) return b.volume;
      final t = ((timeMs - a.x) / (b.x - a.x)).clamp(0.0, 1.0);
      return a.volume + ((b.volume - a.volume) * t);
    }
    return points.last.volume;
  }

  Future<void> _syncAutomationTargetToCurrentTime(
    int row,
    String targetId,
  ) async {
    if (targetId == 'volume') return;
    final target = _rowAutomationTargets[row]?[targetId];
    if (target == null || target.isVolume || target.effectIndex < 0) return;
    final timeMs = _globalAudioClock.inMilliseconds.toDouble();
    final normalized = _resolvedAutomationValueAtMs(
      row,
      targetId,
      timeMs,
    ).clamp(0.0, 1.0);
    final value = _denormalizeAutomationValue(normalized, target);
    await JuceAudioEngine.setTrackEffect(
      row,
      target.effectIndex,
      target.paramId,
      value,
    );
    _lastAppliedAutomationNormalized['$row|$targetId'] = normalized.toDouble();
  }

  Future<void> _setAutomationTargetPointsWithUndo(
    int row,
    String targetId,
    List<AutomationPoint> newPoints, {
    List<AutomationPoint>? oldPointsOverride,
  }) async {
    if (row < 0 || row >= _rowCount) return;
    if (targetId == 'volume') {
      await _setRowAutomationWithUndo(row, newPoints);
      return;
    }

    final oldPoints =
        (oldPointsOverride ?? _pointsForAutomationTarget(row, targetId))
            .map((p) => p.copy())
            .toList(growable: false);
    final safePoints =
        _sanitizeAutomationPointsForTarget(row, targetId, newPoints);

    await _undoManager.execute(
      SetTargetAutomationPointsAction(
        row: row,
        targetId: targetId,
        oldPoints: oldPoints,
        newPoints: safePoints,
        applyToState: (r, laneId, points) {
          setState(() {
            final rowMap = _rowPluginAutomation.putIfAbsent(
                r, () => <String, List<AutomationPoint>>{});
            rowMap[laneId] =
                points.map((p) => p.copy()).toList(growable: false);
          });
        },
        onApplied: (r, laneId, _) async {
          _lastAppliedAutomationNormalized.remove('$r|$laneId');
          await _syncNativePluginAutomationForRow(r);
          await _syncAutomationTargetToCurrentTime(r, laneId);
        },
      ),
    );
  }

  List<AutomationLaneSnapshot> _automationLanesForRowSave(int row) {
    if (row < 0 || row >= _rowCount) return const <AutomationLaneSnapshot>[];
    final lanes = <AutomationLaneSnapshot>[];

    final volumePoints = _sanitizeAutomationPointsForTarget(
      row,
      'volume',
      _rowVolumeAutomation[row],
    );
    lanes.add(_volumeAutomationTargetMeta().toLaneSnapshot(volumePoints));

    final rowPlugin =
        _rowPluginAutomation[row] ?? const <String, List<AutomationPoint>>{};
    final targets =
        _rowAutomationTargets[row] ?? const <String, _AutomationTargetMeta>{};
    rowPlugin.forEach((targetId, points) {
      if (targetId == 'volume') return;
      final safePoints =
          _sanitizeAutomationPointsForTarget(row, targetId, points);
      if (safePoints.isEmpty) return;
      final target =
          targets[targetId] ?? _fallbackAutomationTargetMeta(targetId);
      lanes.add(target.toLaneSnapshot(safePoints));
    });

    return lanes;
  }

  void _restoreAutomationLanesForRow(
    int row,
    List<AutomationLaneSnapshot> lanes, {
    String? selectedTargetId,
  }) {
    if (row < 0 || row >= _rowCount) return;
    final rowPlugin = <String, List<AutomationPoint>>{};
    final rowTargets = <String, _AutomationTargetMeta>{
      'volume': _volumeAutomationTargetMeta(),
    };

    for (final lane in lanes) {
      final targetId = lane.targetId.trim();
      if (targetId.isEmpty) continue;
      final safePoints = _sanitizeAutomationPointsForTarget(
        row,
        targetId,
        lane.points.map((p) => p.copy()).toList(growable: false),
      );
      if (targetId == 'volume') {
        _rowVolumeAutomation[row] = safePoints;
        continue;
      }
      rowPlugin[targetId] = safePoints;
      rowTargets[targetId] = _AutomationTargetMeta.fromLaneSnapshot(lane);
    }

    _rowPluginAutomation[row] = rowPlugin;
    _rowAutomationTargets[row] = rowTargets;
    final fallbackTarget = rowTargets.containsKey('volume')
        ? 'volume'
        : (rowTargets.keys.isNotEmpty ? rowTargets.keys.first : 'volume');
    _rowSelectedAutomationTarget[row] =
        (selectedTargetId != null && rowTargets.containsKey(selectedTargetId))
            ? selectedTargetId
            : fallbackTarget;
  }

  List<AutomationClipSnapshot> _automationClipsForRowSave(int row) {
    if (row < 0 || row >= _rowCount) {
      return const <AutomationClipSnapshot>[];
    }
    final rowMap = _rowAutomationClips[row] ??
        const <String, List<AutomationClipSnapshot>>{};
    final out = <AutomationClipSnapshot>[];
    for (final entry in rowMap.entries) {
      final targetId = entry.key;
      final safe = _sanitizeAutomationClipsForTarget(
        row,
        targetId,
        entry.value,
      );
      out.addAll(safe.map((clip) => clip.copyWith()));
    }
    out.sort((a, b) {
      final targetCmp = a.targetId.compareTo(b.targetId);
      if (targetCmp != 0) return targetCmp;
      final laneCmp = a.lane.compareTo(b.lane);
      if (laneCmp != 0) return laneCmp;
      final timeCmp = a.startMs.compareTo(b.startMs);
      if (timeCmp != 0) return timeCmp;
      return a.id.compareTo(b.id);
    });
    return out;
  }

  void _restoreAutomationClipsForRow(
    int row,
    List<AutomationClipSnapshot> clips,
  ) {
    if (row < 0 || row >= _rowCount) return;
    final grouped = <String, List<AutomationClipSnapshot>>{};
    for (final clip in clips) {
      final targetId = clip.targetId.trim().isEmpty ? 'volume' : clip.targetId;
      grouped.putIfAbsent(targetId, () => <AutomationClipSnapshot>[]).add(
            clip.copyWith(
              row: row,
              targetId: targetId,
            ),
          );
    }

    final sanitized = <String, List<AutomationClipSnapshot>>{};
    for (final entry in grouped.entries) {
      sanitized[entry.key] = _sanitizeAutomationClipsForTarget(
        row,
        entry.key,
        entry.value,
      );
    }
    _rowAutomationClips[row] = sanitized;
  }

  Future<void> _setAutomationClipsForTargetWithUndo(
    int row,
    String targetId,
    List<AutomationClipSnapshot> newClips, {
    List<AutomationClipSnapshot>? oldClipsOverride,
  }) async {
    if (row < 0 || row >= _rowCount) return;
    final oldClips = _copyAutomationClipList(
      oldClipsOverride ?? _clipsForAutomationTarget(row, targetId),
    );
    final safeClips =
        _sanitizeAutomationClipsForTarget(row, targetId, newClips);

    await _undoManager.execute(
      SetTargetAutomationClipsAction(
        row: row,
        targetId: targetId,
        oldClips: oldClips,
        newClips: safeClips,
        applyToState: (r, laneId, clips) {
          setState(() {
            final rowMap = _rowAutomationClips.putIfAbsent(
                r, () => <String, List<AutomationClipSnapshot>>{});
            rowMap[laneId] = _copyAutomationClipList(clips);
          });
        },
        onApplied: (r, _, __) async {
          await _syncNativeAutomationForRow(r);
        },
      ),
    );
  }

  List<AutomationPoint> _sanitizeAutomationPoints(
    int row,
    List<AutomationPoint> points,
  ) {
    final maxMs =
        math.max(1.0, _audioOnlyOverallDuration.inMilliseconds.toDouble());
    final sanitized = points
        .map((p) => AutomationPoint(
              x: p.x.clamp(0.0, maxMs).toDouble(),
              volume: p.volume.clamp(0.0, 1.0).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    if (sanitized.isEmpty) {
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 1.0),
      ];
    }

    if (sanitized.length == 1) {
      final only = sanitized.first;
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: only.volume),
      ];
    }
    return sanitized;
  }

  Future<void> _setRowAutomationWithUndo(
    int row,
    List<AutomationPoint> newPoints,
  ) async {
    if (row < 0 || row >= _rowVolumeAutomation.length) return;
    final oldPoints = _rowVolumeAutomation[row]
        .map((p) => AutomationPoint(x: p.x, volume: p.volume))
        .toList(growable: false);
    final safePoints = _sanitizeAutomationPoints(row, newPoints);
    await _undoManager.execute(
      SetAutomationPointsAction(
        row: row,
        oldPoints: oldPoints,
        newPoints: safePoints,
        applyToState: (r, points) {
          setState(() {
            _rowVolumeAutomation[r] = points
                .map((p) => AutomationPoint(x: p.x, volume: p.volume))
                .toList();
          });
        },
        onApplied: (r, _) async {
          await _syncNativeAutomationForRow(r);
        },
      ),
    );
  }

  String? _resolveAutomationTargetIdFromAction(
    int row,
    Map<String, dynamic> data, {
    bool allowVolumeFallback = true,
  }) {
    final target = _actionTarget(data);
    final targets =
        _rowAutomationTargets[row] ?? const <String, _AutomationTargetMeta>{};
    if (targets.isEmpty) {
      return allowVolumeFallback ? 'volume' : null;
    }

    String? pickTargetId(dynamic raw) {
      final id = (raw ?? '').toString().trim();
      if (id.isEmpty) return null;
      if (targets.containsKey(id)) return id;
      final parsed = _parseAutomationTargetId(id);
      if (parsed.isVolume || id.toLowerCase() == 'volume') return 'volume';
      final parsedParamLower = parsed.paramId.trim().toLowerCase();
      if (parsedParamLower.isEmpty) return null;
      final pluginTargets = targets.values.where((meta) => !meta.isVolume);
      if (parsed.effectKey.isNotEmpty) {
        final byEffectKey = pluginTargets.where((meta) {
          final candidateParsed = _parseAutomationTargetId(meta.targetId);
          return candidateParsed.effectKey == parsed.effectKey &&
              meta.paramId.trim().toLowerCase() == parsedParamLower;
        }).toList(growable: false);
        if (byEffectKey.length == 1) {
          return byEffectKey.first.targetId;
        }
      }
      if (parsed.legacyEffectIndex >= 0) {
        final byLegacyIndex = pluginTargets
            .where((meta) =>
                meta.effectIndex == parsed.legacyEffectIndex &&
                meta.paramId.trim().toLowerCase() == parsedParamLower)
            .toList(growable: false);
        if (byLegacyIndex.length == 1) {
          return byLegacyIndex.first.targetId;
        }
      }
      return null;
    }

    bool matchesToken(String haystack, String needle) {
      final h = haystack.trim().toLowerCase();
      final n = needle.trim().toLowerCase();
      if (h.isEmpty || n.isEmpty) return false;
      return h.contains(n) || n.contains(h);
    }

    final explicit = pickTargetId(data['automation_target_id']) ??
        pickTargetId(target['automation_target_id']) ??
        pickTargetId(data['target_id']) ??
        pickTargetId(target['target_id']) ??
        pickTargetId(data['lane_id']) ??
        pickTargetId(target['lane_id']);
    if (explicit != null) return explicit;

    final effectIndex = _toActionInt(data['effect_index'] ??
        target['effect_index'] ??
        data['effect'] ??
        target['effect']);
    final paramId = (data['param_id'] ??
            target['param_id'] ??
            data['parameter_id'] ??
            target['parameter_id'] ??
            data['param'] ??
            target['param'])
        .toString()
        .trim();
    final paramName = (data['param_name'] ??
            target['param_name'] ??
            data['parameter'] ??
            target['parameter'] ??
            data['name'] ??
            target['name'])
        .toString()
        .trim()
        .toLowerCase();
    final effectName = (data['effect_name'] ??
            target['effect_name'] ??
            data['plugin_name'] ??
            target['plugin_name'] ??
            data['plugin'] ??
            target['plugin'] ??
            data['effect'] ??
            target['effect'])
        .toString()
        .trim()
        .toLowerCase();

    if (effectIndex != null && paramId.isNotEmpty) {
      final byDirectId = _pluginAutomationTargetId(effectIndex, paramId);
      if (targets.containsKey(byDirectId)) return byDirectId;
    }

    int? resolvedEffectIndex = effectIndex;
    if (resolvedEffectIndex == null && effectName.isNotEmpty) {
      final matchingEffectIndices = targets.values
          .where((meta) {
            if (meta.isVolume) return false;
            return matchesToken(meta.label, effectName) ||
                matchesToken(meta.paramId, effectName);
          })
          .map((meta) => meta.effectIndex)
          .where((i) => i >= 0)
          .toSet()
          .toList(growable: false);
      if (matchingEffectIndices.length == 1) {
        resolvedEffectIndex = matchingEffectIndices.first;
      }
    }

    if (resolvedEffectIndex != null) {
      final scoped = targets.values
          .where((meta) =>
              !meta.isVolume && meta.effectIndex == resolvedEffectIndex)
          .toList(growable: false);
      if (scoped.isNotEmpty) {
        if (paramId.isNotEmpty) {
          final lowered = paramId.toLowerCase();
          for (final meta in scoped) {
            if (meta.paramId.toLowerCase() == lowered) return meta.targetId;
          }
        }
        if (paramName.isNotEmpty) {
          for (final meta in scoped) {
            final label = meta.label.toLowerCase();
            final pid = meta.paramId.toLowerCase();
            if (matchesToken(label, paramName) ||
                matchesToken(pid, paramName)) {
              return meta.targetId;
            }
          }
        }
        if (scoped.length == 1) return scoped.first.targetId;
      }
    }

    if (paramId.isNotEmpty) {
      final lowered = paramId.toLowerCase();
      for (final meta in targets.values) {
        if (meta.isVolume) continue;
        if (meta.paramId.toLowerCase() == lowered) return meta.targetId;
      }
    }

    if (paramName.isNotEmpty) {
      for (final meta in targets.values) {
        if (meta.isVolume) continue;
        final label = meta.label.toLowerCase();
        final pid = meta.paramId.toLowerCase();
        if (matchesToken(label, paramName) || matchesToken(pid, paramName)) {
          return meta.targetId;
        }
      }
    }

    final pluginIntent = effectName.isNotEmpty ||
        resolvedEffectIndex != null ||
        paramId.isNotEmpty ||
        paramName.isNotEmpty;
    if (pluginIntent && !allowVolumeFallback) {
      return null;
    }

    return 'volume';
  }

  bool _isPluginAutomationIntent(Map<String, dynamic> data) {
    final target = _actionTarget(data);

    bool hasField(String key) {
      final value = data[key] ?? target[key];
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is num) return true;
      return true;
    }

    if (hasField('automation_target_id') ||
        hasField('target_id') ||
        hasField('lane_id') ||
        hasField('effect_index') ||
        hasField('effect_name') ||
        hasField('plugin_name') ||
        hasField('plugin') ||
        hasField('param_id') ||
        hasField('parameter_id') ||
        hasField('param_name') ||
        hasField('parameter')) {
      final explicitTargetId = (data['automation_target_id'] ??
              target['automation_target_id'] ??
              data['target_id'] ??
              target['target_id'])
          .toString()
          .trim()
          .toLowerCase();
      if (explicitTargetId == 'volume') return false;
      return true;
    }

    final template = (data['template'] ??
            target['template'] ??
            data['pattern'] ??
            target['pattern'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (template == 'filter_sweep' ||
        template == 'lowpass_sweep' ||
        template == 'highpass_sweep' ||
        template == 'reverb_tail') {
      return true;
    }

    return false;
  }

  double _normalizedActionValueForTarget(
    dynamic rawValue,
    _AutomationTargetMeta target, {
    String valueMode = '',
    double fallback = 0.5,
  }) {
    final raw = _toActionDouble(rawValue);
    if (raw == null) return fallback.clamp(0.0, 1.0).toDouble();
    if (target.isVolume) {
      return raw.clamp(0.0, 1.0).toDouble();
    }

    final mode = valueMode.trim().toLowerCase();
    if (mode == 'real' || mode == 'absolute' || mode == 'native') {
      return _normalizeAutomationValue(
        raw,
        min: target.min,
        max: target.max,
        fallback: fallback,
      );
    }
    if (mode == 'normalized' || mode == '0to1') {
      return raw.clamp(0.0, 1.0).toDouble();
    }

    if (raw < 0.0 || raw > 1.0) {
      return _normalizeAutomationValue(
        raw,
        min: target.min,
        max: target.max,
        fallback: fallback,
      );
    }
    return raw.clamp(0.0, 1.0).toDouble();
  }

  String _normalizeAutomationEditOperation(String raw) {
    // Legacy mapping reference: 'set' || 'replace' => 'set_points'
    switch (raw.trim().toLowerCase()) {
      case 'set':
      case 'replace':
        return 'set_points';
      case 'ramp':
      case 'curve':
      case 'add_curve':
        return 'add_ramp';
      case 'create':
      case 'add':
      case 'add_clip':
      case 'new_clip':
      case 'insert_clip':
      case 'create_clip':
        return 'create_clip';
      case 'duplicate':
      case 'duplicate_clip':
        return 'duplicate_clip';
      case 'move':
      case 'move_clip':
        return 'move_clip';
      case 'remove_clip':
      case 'delete_clip':
        return 'delete_clip';
      case 'clear_clip':
      case 'remove_all_clips':
      case 'clear_clips':
        return 'clear_clips';
      case 'mute':
      case 'mute_clip':
        return 'mute_clip';
      case 'unmute':
      case 'unmute_clip':
        return 'unmute_clip';
      case 'toggle_mute':
      case 'toggle_clip_mute':
        return 'toggle_clip_mute';
      case 'replace_clip_points':
        return 'set_clip_points';
      case 'template':
      case 'apply_template':
      case 'generate_template':
        return 'apply_template';
      default:
        return raw.trim().toLowerCase();
    }
  }

  bool _automationClipListsEqual(
    List<AutomationClipSnapshot> a,
    List<AutomationClipSnapshot> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.targetId != y.targetId ||
          x.row != y.row ||
          x.lane != y.lane ||
          x.muted != y.muted ||
          (x.startMs - y.startMs).abs() > 1e-6 ||
          (x.lengthMs - y.lengthMs).abs() > 1e-6) {
        return false;
      }
      if (x.points.length != y.points.length) return false;
      for (int p = 0; p < x.points.length; p++) {
        final xp = x.points[p];
        final yp = y.points[p];
        if ((xp.x - yp.x).abs() > 1e-6 ||
            (xp.volume - yp.volume).abs() > 1e-6) {
          return false;
        }
      }
    }
    return true;
  }

  double _defaultAutomationClipLengthMs() {
    final msPerBeat = 60000.0 / _tempo.clamp(1.0, 400.0);
    final oneBarMs = msPerBeat * 4.0;
    final maxMs = _maxAutomationTimelineMs();
    return oneBarMs.clamp(200.0, math.max(200.0, maxMs)).toDouble();
  }

  String _newAutomationClipId(int row, String targetId) {
    return 'ac_${row}_${targetId}_${DateTime.now().microsecondsSinceEpoch}_${const Uuid().v4()}';
  }

  int? _resolveAutomationClipIndexFromAction(
    int row,
    String targetId,
    Map<String, dynamic> data,
  ) {
    final clips = _clipsForAutomationTarget(row, targetId);
    if (clips.isEmpty) return null;
    final target = _actionTarget(data);
    final explicitIndex = _toActionInt(data['clip_index'] ??
        target['clip_index'] ??
        data['automation_clip_index'] ??
        target['automation_clip_index']);
    if (explicitIndex != null &&
        explicitIndex >= 0 &&
        explicitIndex < clips.length) {
      return explicitIndex;
    }

    final explicitId = (data['clip_id'] ??
            target['clip_id'] ??
            data['automation_clip_id'] ??
            target['automation_clip_id'] ??
            '')
        .toString()
        .trim();
    if (explicitId.isNotEmpty) {
      final idx = clips.indexWhere((clip) => clip.id == explicitId);
      if (idx >= 0) return idx;
    }

    final atMs = _toActionDouble(
      data['at_ms'] ??
          target['at_ms'] ??
          data['time_ms'] ??
          target['time_ms'] ??
          data['start_ms'] ??
          target['start_ms'],
    );
    if (atMs != null && atMs.isFinite) {
      for (int i = 0; i < clips.length; i++) {
        final clip = clips[i];
        final endMs = clip.startMs + clip.lengthMs;
        if (atMs >= clip.startMs && atMs <= endMs) {
          return i;
        }
      }
      int nearest = 0;
      double nearestDist = (clips.first.startMs - atMs).abs();
      for (int i = 1; i < clips.length; i++) {
        final dist = (clips[i].startMs - atMs).abs();
        if (dist < nearestDist) {
          nearest = i;
          nearestDist = dist;
        }
      }
      return nearest;
    }

    return clips.length - 1;
  }

  List<AutomationPoint> _automationTemplatePointsRelative(
    String templateRaw,
    double lengthMs, {
    required double startValue,
    required double endValue,
    String direction = 'up',
  }) {
    final safeLength = lengthMs.clamp(80.0, double.infinity).toDouble();
    final start = startValue.clamp(0.0, 1.0).toDouble();
    final end = endValue.clamp(0.0, 1.0).toDouble();
    final template = templateRaw.trim().toLowerCase();
    final dirDown = direction.trim().toLowerCase() == 'down';

    if (template == 'sidechain' ||
        template == 'sidechain_pump' ||
        template == 'pump') {
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 1.0),
        AutomationPoint(x: safeLength * 0.08, volume: 0.14),
        AutomationPoint(x: safeLength * 0.36, volume: 0.78),
        AutomationPoint(x: safeLength, volume: 1.0),
      ];
    }

    if (template == 'reverb_tail' ||
        template == 'tail' ||
        template == 'decay') {
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: 0.05),
        AutomationPoint(x: safeLength * 0.12, volume: 1.0),
        AutomationPoint(x: safeLength * 0.45, volume: 0.56),
        AutomationPoint(x: safeLength, volume: 0.12),
      ];
    }

    if (template == 'filter_sweep' ||
        template == 'sweep' ||
        template == 'lowpass_sweep' ||
        template == 'highpass_sweep') {
      final from = dirDown ? 1.0 : 0.0;
      final to = dirDown ? 0.0 : 1.0;
      return <AutomationPoint>[
        AutomationPoint(x: 0.0, volume: from),
        AutomationPoint(x: safeLength, volume: to),
      ];
    }

    return <AutomationPoint>[
      AutomationPoint(x: 0.0, volume: start),
      AutomationPoint(x: safeLength, volume: end),
    ];
  }

  Future<void> _applyAutomationEditAction(Map<String, dynamic> data) async {
    final target = _actionTarget(data);
    final rawOperation =
        (data['operation'] ?? '').toString().trim().toLowerCase();
    var operation = _normalizeAutomationEditOperation(rawOperation);
    if (operation == 'clear') {
      final clearScope = (data['clear_scope'] ??
              target['clear_scope'] ??
              data['scope'] ??
              target['scope'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (clearScope.contains('clip')) {
        operation = 'clear_clips';
      }
    }
    final clipIndex = _resolveClipIndexFromActionTarget(data);
    final row = _resolveRowIndexFromActionTarget(
      data,
      fallbackClipIndex: clipIndex,
    );
    if (row == null) {
      _insertAssistantChatText(
          "I couldn't resolve which track automation to edit.");
      return;
    }

    final pluginIntent = _isPluginAutomationIntent(data);
    final targetId = _resolveAutomationTargetIdFromAction(
      row,
      data,
      allowVolumeFallback: !pluginIntent,
    );
    if (targetId == null || targetId.isEmpty) {
      final hasPluginTargets = (_rowAutomationTargets[row] ?? const {})
          .values
          .any((meta) => !meta.isVolume);
      if (pluginIntent) {
        if (!hasPluginTargets) {
          _insertAssistantChatText(
              "That track has no automatable plugin parameters yet. Add an effect first.");
        } else {
          _insertAssistantChatText(
              "I couldn't resolve which plugin parameter to automate. Specify plugin + parameter (for example: effect_name + param_name).");
        }
      } else {
        _insertAssistantChatText(
            "I couldn't resolve which automation lane to edit.");
      }
      return;
    }
    final targetMeta = _rowAutomationTargets[row]?[targetId] ??
        _fallbackAutomationTargetMeta(targetId);
    final valueMode = (data['value_mode'] ??
            target['value_mode'] ??
            data['value_domain'] ??
            target['value_domain'] ??
            '')
        .toString();
    final normalizedTemplate = (data['template'] ??
            target['template'] ??
            data['pattern'] ??
            target['pattern'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final defaultSpanMs = (60000.0 / _tempo.clamp(1.0, 400.0) * 4.0)
        .clamp(120.0, _maxAutomationTimelineMs())
        .toDouble();

    Future<void> applyClipList(
      List<AutomationClipSnapshot> nextClips, {
      List<AutomationClipSnapshot>? beforeOverride,
    }) async {
      final oldClips = _copyAutomationClipList(
        beforeOverride ?? _clipsForAutomationTarget(row, targetId),
      );
      final safeClips =
          _sanitizeAutomationClipsForTarget(row, targetId, nextClips);
      if (_automationClipListsEqual(oldClips, safeClips)) {
        return;
      }
      await _setAutomationClipsForTargetWithUndo(
        row,
        targetId,
        safeClips,
        oldClipsOverride: oldClips,
      );
    }

    if (operation == 'clear_clips') {
      await applyClipList(const <AutomationClipSnapshot>[]);
      _showSmallNotice('Cleared automation clips.');
      return;
    }

    final isKickSyncedSidechainTemplate = operation == 'apply_template' &&
        (normalizedTemplate == 'sidechain_from_kick' ||
            normalizedTemplate == 'kick_sidechain' ||
            normalizedTemplate == 'duck_to_kick' ||
            normalizedTemplate == 'kick_duck');
    if (isKickSyncedSidechainTemplate) {
      final sourceClipIndex =
          _resolveKickSourceClipIndexFromAction(data, targetRow: row);
      if (sourceClipIndex == null ||
          sourceClipIndex < 0 ||
          sourceClipIndex >= _audioTracks.length) {
        _insertAssistantChatText(
            "I couldn't find a kick source clip for sidechain automation.");
        return;
      }
      final sourceClip = _audioTracks[sourceClipIndex];
      if (sourceClip.isMidi) {
        _insertAssistantChatText(
            'Kick-synced sidechain needs an audio source clip.');
        return;
      }

      final lengthMs = (_toActionDouble(
                data['length_ms'] ??
                    target['length_ms'] ??
                    data['duration_ms'] ??
                    target['duration_ms'],
              ) ??
              (60000.0 / _tempo.clamp(1.0, 400.0)))
          .clamp(80.0, _maxAutomationTimelineMs())
          .toDouble();
      final minSpacingMs = (_toActionDouble(
                data['min_spacing_ms'] ??
                    target['min_spacing_ms'] ??
                    data['event_spacing_ms'] ??
                    target['event_spacing_ms'],
              ) ??
              math.max(80.0, lengthMs * 0.42))
          .clamp(40.0, 4000.0)
          .toDouble();
      final thresholdStd = (_toActionDouble(
                data['transient_threshold_std'] ??
                    target['transient_threshold_std'] ??
                    data['transient_sensitivity'] ??
                    target['transient_sensitivity'] ??
                    data['sensitivity'] ??
                    target['sensitivity'],
              ) ??
              1.25)
          .clamp(0.25, 4.0)
          .toDouble();
      final lowpassHz = (_toActionDouble(
                data['kick_lowpass_hz'] ??
                    target['kick_lowpass_hz'] ??
                    data['lowpass_hz'] ??
                    target['lowpass_hz'],
              ) ??
              220.0)
          .clamp(80.0, 1200.0)
          .toDouble();
      final maxEvents = (_toActionInt(
                data['max_events'] ?? target['max_events'],
              ) ??
              256)
          .clamp(1, 2048);
      final offsetMs = (_toActionDouble(
                data['offset_ms'] ?? target['offset_ms'],
              ) ??
              0.0)
          .toDouble();
      final fromMs = _toActionDouble(data['from_ms'] ?? target['from_ms']);
      final toMs = _toActionDouble(data['to_ms'] ?? target['to_ms']);

      var eventMs = await _detectKickTimelineOnsetsMsForClip(
        sourceClip,
        cutoffHz: lowpassHz,
        thresholdStd: thresholdStd,
        minSpacingMs: minSpacingMs,
        maxEvents: maxEvents,
      );
      if (eventMs.isEmpty) {
        _insertAssistantChatText(
            'No kick transients were detected for automatic sidechain.');
        return;
      }

      if (fromMs != null || toMs != null) {
        final startWindow = (fromMs ?? 0.0).toDouble();
        final endWindow = (toMs ?? _maxAutomationTimelineMs()).toDouble();
        eventMs = eventMs
            .where((x) => x >= startWindow && x <= endWindow)
            .toList(growable: false);
      }
      if (eventMs.isEmpty) {
        _insertAssistantChatText(
            'Kick transients were found, but none were in the requested time range.');
        return;
      }

      final recoverValue = _normalizedActionValueForTarget(
        data['recover_value'] ??
            data['end_value'] ??
            data['max_value'] ??
            target['recover_value'] ??
            target['end_value'] ??
            target['max_value'],
        targetMeta,
        valueMode: valueMode,
        fallback: targetId == 'volume' ? 1.0 : 0.8,
      );
      final duckValue = _normalizedActionValueForTarget(
        data['duck_value'] ??
            data['min_value'] ??
            data['depth'] ??
            target['duck_value'] ??
            target['min_value'] ??
            target['depth'],
        targetMeta,
        valueMode: valueMode,
        fallback: targetId == 'volume' ? 0.16 : 0.2,
      );
      final attackMs =
          (_toActionDouble(data['attack_ms'] ?? target['attack_ms']) ??
                  math.min(22.0, lengthMs * 0.2))
              .clamp(2.0, math.max(2.0, lengthMs * 0.7))
              .toDouble();
      final releaseRatio =
          (_toActionDouble(data['release_ratio'] ?? target['release_ratio']) ??
                  0.38)
              .clamp(0.08, 0.95)
              .toDouble();
      final recoveryMs =
          (lengthMs * releaseRatio).clamp(attackMs + 1.0, lengthMs).toDouble();
      final midValue =
          (duckValue + (recoverValue - duckValue) * 0.58).clamp(0.0, 1.0);
      final replaceExisting = _toActionBool(
        data['replace_existing'] ?? target['replace_existing'],
        fallback: false,
      );

      final before = _copyAutomationClipList(_clipsForAutomationTarget(
        row,
        targetId,
      ));
      final working = List<AutomationClipSnapshot>.from(before);
      final requestedLane = math.max(
        0,
        _toActionInt(
              data['lane_index'] ??
                  target['lane_index'] ??
                  data['lane'] ??
                  target['lane'],
            ) ??
            0,
      );
      if (replaceExisting && eventMs.isNotEmpty) {
        final regionStart = (eventMs.first + offsetMs) - lengthMs * 0.25;
        final regionEnd = (eventMs.last + offsetMs) + lengthMs * 1.1;
        working.removeWhere((clip) {
          final clipEnd = clip.startMs + clip.lengthMs;
          return clipEnd >= regionStart && clip.startMs <= regionEnd;
        });
      }

      final maxTimelineMs = _maxAutomationTimelineMs();
      int created = 0;
      final label = (data['label'] ??
              target['label'] ??
              _automationTargetLabelFor(row, targetId))
          .toString()
          .trim();
      for (final onsetMs in eventMs) {
        final startMs = (onsetMs + offsetMs).clamp(0.0, maxTimelineMs);
        if (startMs + 4.0 >= maxTimelineMs) continue;
        final clippedLength =
            math.min(lengthMs, math.max(40.0, maxTimelineMs - startMs));
        if (clippedLength <= 40.0) continue;

        final points = <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: recoverValue),
          AutomationPoint(
              x: attackMs.clamp(1.0, clippedLength), volume: duckValue),
          AutomationPoint(
              x: recoveryMs.clamp(attackMs + 1.0, clippedLength),
              volume: midValue.toDouble()),
          AutomationPoint(x: clippedLength, volume: recoverValue),
        ];

        working.add(
          AutomationClipSnapshot(
            id: _newAutomationClipId(row, targetId),
            targetId: targetId,
            label: label.isEmpty
                ? _automationTargetLabelFor(row, targetId)
                : label,
            row: row,
            lane: requestedLane,
            startMs: startMs.toDouble(),
            lengthMs: clippedLength.toDouble(),
            muted: false,
            points: points,
          ),
        );
        created++;
      }

      if (created <= 0) {
        _insertAssistantChatText(
            "I couldn't place sidechain clips in the current timeline range.");
        return;
      }

      await applyClipList(working, beforeOverride: before);
      _showSmallNotice('Created $created kick-synced sidechain clips.');
      return;
    }

    if (operation == 'create_clip' || operation == 'apply_template') {
      final before = _copyAutomationClipList(_clipsForAutomationTarget(
        row,
        targetId,
      ));
      final startMs = (_toActionDouble(
                data['start_ms'] ?? target['start_ms'] ?? data['at_ms'],
              ) ??
              _globalAudioClock.inMilliseconds.toDouble())
          .clamp(0.0, _maxAutomationTimelineMs());
      final lengthMs = (_toActionDouble(
                data['length_ms'] ??
                    target['length_ms'] ??
                    data['duration_ms'] ??
                    target['duration_ms'],
              ) ??
              _defaultAutomationClipLengthMs())
          .clamp(80.0, _maxAutomationTimelineMs());
      final startValue = _normalizedActionValueForTarget(
        data['start_value'] ?? data['from_value'],
        targetMeta,
        valueMode: valueMode,
        fallback: targetId == 'volume' ? 0.75 : 0.5,
      );
      final endValue = _normalizedActionValueForTarget(
        data['end_value'] ?? data['to_value'],
        targetMeta,
        valueMode: valueMode,
        fallback: targetId == 'volume' ? 0.75 : 0.5,
      );
      final template = normalizedTemplate;
      final direction =
          (data['direction'] ?? target['direction'] ?? 'up').toString();
      final rawPoints = (data['points'] as List?) ?? const [];
      final clipPoints = <AutomationPoint>[];
      for (final raw in rawPoints) {
        final m = _toActionMap(raw);
        final x = _toActionDouble(m['x_ms'] ?? m['x'] ?? m['time_ms']);
        final rawValue = m['value'] ??
            m['volume'] ??
            m['normalized_value'] ??
            m['normalized'] ??
            m['real_value'] ??
            m['native_value'];
        if (x == null || rawValue == null) continue;
        final pointValueMode = (m['value_mode'] ?? valueMode).toString();
        final normalized = _normalizedActionValueForTarget(
          rawValue,
          targetMeta,
          valueMode: pointValueMode,
          fallback: targetId == 'volume' ? 0.75 : 0.5,
        );
        clipPoints.add(
          AutomationPoint(
            x: x,
            volume: normalized,
          ),
        );
      }
      final points = clipPoints.isNotEmpty
          ? clipPoints
          : _automationTemplatePointsRelative(
              template.isEmpty ? 'ramp' : template,
              lengthMs,
              startValue: startValue,
              endValue: endValue,
              direction: direction,
            );
      final label = (data['label'] ??
              target['label'] ??
              _automationTargetLabelFor(row, targetId))
          .toString()
          .trim();
      final muted = _toActionBool(
        data['muted'] ?? target['muted'],
        fallback: false,
      );
      final requestedLane = math.max(
        0,
        _toActionInt(
              data['lane_index'] ??
                  target['lane_index'] ??
                  data['lane'] ??
                  target['lane'],
            ) ??
            0,
      );
      final clip = AutomationClipSnapshot(
        id: _newAutomationClipId(row, targetId),
        targetId: targetId,
        label: label.isEmpty ? _automationTargetLabelFor(row, targetId) : label,
        row: row,
        lane: requestedLane,
        startMs: startMs.toDouble(),
        lengthMs: lengthMs.toDouble(),
        muted: muted,
        points: points,
      );
      await applyClipList([...before, clip], beforeOverride: before);
      _showSmallNotice('Created automation clip.');
      return;
    }

    if (operation == 'duplicate_clip') {
      final before = _copyAutomationClipList(_clipsForAutomationTarget(
        row,
        targetId,
      ));
      final sourceIndex =
          _resolveAutomationClipIndexFromAction(row, targetId, data);
      if (sourceIndex == null ||
          sourceIndex < 0 ||
          sourceIndex >= before.length) {
        _insertAssistantChatText(
            "I couldn't find an automation clip to duplicate.");
        return;
      }
      final source = before[sourceIndex];
      final nextStart = (_toActionDouble(
                data['start_ms'] ??
                    target['start_ms'] ??
                    data['paste_start_ms'] ??
                    target['paste_start_ms'],
              ) ??
              (source.startMs + source.lengthMs))
          .toDouble();
      final duplicated = source.copyWith(
        id: _newAutomationClipId(row, targetId),
        startMs: nextStart,
      );
      await applyClipList([...before, duplicated], beforeOverride: before);
      _showSmallNotice('Duplicated automation clip.');
      return;
    }

    if (operation == 'move_clip' ||
        operation == 'delete_clip' ||
        operation == 'mute_clip' ||
        operation == 'unmute_clip' ||
        operation == 'toggle_clip_mute' ||
        operation == 'set_clip_points') {
      final before = _copyAutomationClipList(_clipsForAutomationTarget(
        row,
        targetId,
      ));
      final clipIdx =
          _resolveAutomationClipIndexFromAction(row, targetId, data);
      if (clipIdx == null || clipIdx < 0 || clipIdx >= before.length) {
        _insertAssistantChatText("I couldn't find that automation clip.");
        return;
      }

      if (operation == 'delete_clip') {
        final next = List<AutomationClipSnapshot>.from(before)
          ..removeAt(clipIdx);
        await applyClipList(next, beforeOverride: before);
        _showSmallNotice('Deleted automation clip.');
        return;
      }

      final working = List<AutomationClipSnapshot>.from(before);
      final current = working[clipIdx];

      if (operation == 'move_clip') {
        final explicitStartMs = _toActionDouble(
          data['start_ms'] ??
              target['start_ms'] ??
              data['new_start_ms'] ??
              target['new_start_ms'],
        );
        final deltaMs = _toActionDouble(
          data['delta_ms'] ??
              target['delta_ms'] ??
              data['offset_ms'] ??
              target['offset_ms'] ??
              data['shift_ms'] ??
              target['shift_ms'],
        );
        final direction = (data['direction'] ?? target['direction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final stepMs = (_toActionDouble(
                  data['step_ms'] ??
                      target['step_ms'] ??
                      data['amount_ms'] ??
                      target['amount_ms'],
                ) ??
                (defaultSpanMs / 4.0))
            .abs()
            .clamp(20.0, _maxAutomationTimelineMs());
        final directionDelta = switch (direction) {
          'left' || 'earlier' || 'back' || 'backward' => -stepMs,
          'right' || 'later' || 'forward' => stepMs,
          _ => 0.0,
        };
        final startMs = explicitStartMs ??
            (current.startMs + (deltaMs ?? 0.0) + directionDelta);
        final lengthMs = _toActionDouble(
              data['length_ms'] ??
                  target['length_ms'] ??
                  data['duration_ms'] ??
                  target['duration_ms'],
            ) ??
            current.lengthMs;
        final laneIndex = _toActionInt(
          data['lane_index'] ??
              target['lane_index'] ??
              data['lane'] ??
              target['lane'],
        );
        final nextLane =
            laneIndex == null ? current.lane : math.max(0, laneIndex);
        if ((startMs - current.startMs).abs() < 0.5 &&
            (lengthMs - current.lengthMs).abs() < 0.5 &&
            nextLane == current.lane) {
          _insertAssistantChatText(
              "I couldn't resolve where to move that automation clip.");
          return;
        }
        working[clipIdx] = current.copyWith(
          startMs: startMs,
          lengthMs: lengthMs,
          lane: nextLane,
        );
        await applyClipList(working, beforeOverride: before);
        _showSmallNotice('Moved automation clip.');
        return;
      }

      if (operation == 'mute_clip' ||
          operation == 'unmute_clip' ||
          operation == 'toggle_clip_mute') {
        final nextMuted = switch (operation) {
          'mute_clip' => true,
          'unmute_clip' => false,
          _ => !current.muted,
        };
        working[clipIdx] = current.copyWith(muted: nextMuted);
        await applyClipList(working, beforeOverride: before);
        _showSmallNotice(
            nextMuted ? 'Muted automation clip.' : 'Unmuted automation clip.');
        return;
      }

      if (operation == 'set_clip_points') {
        final rawPoints = (data['points'] as List?) ?? const [];
        final points = <AutomationPoint>[];
        for (final raw in rawPoints) {
          final m = _toActionMap(raw);
          final x = _toActionDouble(m['x_ms'] ?? m['x'] ?? m['time_ms']);
          final rawValue = m['value'] ??
              m['volume'] ??
              m['normalized_value'] ??
              m['normalized'] ??
              m['real_value'] ??
              m['native_value'];
          if (x == null || rawValue == null) continue;
          final pointValueMode = (m['value_mode'] ?? valueMode).toString();
          final normalized = _normalizedActionValueForTarget(
            rawValue,
            targetMeta,
            valueMode: pointValueMode,
            fallback: targetId == 'volume' ? 0.75 : 0.5,
          );
          points.add(AutomationPoint(x: x, volume: normalized));
        }
        if (points.isEmpty) {
          _insertAssistantChatText("I need clip automation points to apply.");
          return;
        }
        working[clipIdx] = current.copyWith(points: points);
        await applyClipList(working, beforeOverride: before);
        _showSmallNotice('Updated automation clip points.');
        return;
      }
    }

    if (operation == 'clear') {
      if (targetId == 'volume') {
        final maxMs =
            math.max(1.0, _audioOnlyOverallDuration.inMilliseconds.toDouble());
        await _setRowAutomationWithUndo(row, <AutomationPoint>[
          AutomationPoint(x: 0.0, volume: 1.0),
          AutomationPoint(x: maxMs, volume: 1.0),
        ]);
      } else {
        await _setAutomationTargetPointsWithUndo(
          row,
          targetId,
          _defaultAutomationPointsForTarget(row, targetId),
        );
      }
      _showSmallNotice('Cleared automation lane.');
      return;
    }

    if (operation == 'add_ramp') {
      final rawFromMs = _toActionDouble(
            data['from_ms'] ??
                target['from_ms'] ??
                data['start_ms'] ??
                target['start_ms'],
          ) ??
          _globalAudioClock.inMilliseconds.toDouble();
      final fromMs =
          rawFromMs.clamp(0.0, _maxAutomationTimelineMs()).toDouble();
      final rawToMs = _toActionDouble(
            data['to_ms'] ??
                target['to_ms'] ??
                data['end_ms'] ??
                target['end_ms'],
          ) ??
          (fromMs + defaultSpanMs);
      final toMs = math.max(fromMs + 40.0, rawToMs);
      final direction = (data['direction'] ?? target['direction'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final existingValue = _resolvedAutomationValueAtMs(
        row,
        targetId,
        fromMs,
      );
      final parsedStartValue = _normalizedActionValueForTarget(
        data['start_value'] ?? data['from_value'],
        targetMeta,
        valueMode: valueMode,
        fallback: existingValue,
      );
      final parsedEndValue = _normalizedActionValueForTarget(
        data['end_value'] ?? data['to_value'],
        targetMeta,
        valueMode: valueMode,
        fallback: direction == 'down'
            ? (parsedStartValue - 0.35).clamp(0.0, 1.0).toDouble()
            : direction == 'up'
                ? (parsedStartValue + 0.35).clamp(0.0, 1.0).toDouble()
                : parsedStartValue,
      );
      final next = _pointsForAutomationTarget(row, targetId)
          .map((p) => p.copy())
          .toList(growable: true);
      next.add(AutomationPoint(x: fromMs, volume: parsedStartValue));
      next.add(AutomationPoint(x: toMs, volume: parsedEndValue));
      await _setAutomationTargetPointsWithUndo(row, targetId, next);
      _showSmallNotice('Added automation ramp.');
      return;
    }

    final rawPoints = (data['points'] as List?) ?? const [];
    final points = <AutomationPoint>[];
    for (final raw in rawPoints) {
      final m = _toActionMap(raw);
      final x = _toActionDouble(m['x_ms'] ?? m['x'] ?? m['time_ms']);
      final rawValue = m['value'] ??
          m['volume'] ??
          m['normalized_value'] ??
          m['normalized'] ??
          m['real_value'] ??
          m['native_value'];
      if (x == null || rawValue == null) continue;
      final pointValueMode = (m['value_mode'] ?? valueMode).toString();
      final normalized = _normalizedActionValueForTarget(
        rawValue,
        targetMeta,
        valueMode: pointValueMode,
        fallback: targetId == 'volume' ? 1.0 : 0.5,
      );
      points.add(AutomationPoint(x: x, volume: normalized));
    }

    if (points.isEmpty) {
      if (operation == 'set_points') {
        final fromMs = (_toActionDouble(
                  data['from_ms'] ??
                      target['from_ms'] ??
                      data['start_ms'] ??
                      target['start_ms'],
                ) ??
                _globalAudioClock.inMilliseconds.toDouble())
            .clamp(0.0, _maxAutomationTimelineMs())
            .toDouble();
        final toMs = (_toActionDouble(
                  data['to_ms'] ??
                      target['to_ms'] ??
                      data['end_ms'] ??
                      target['end_ms'],
                ) ??
                (fromMs + defaultSpanMs))
            .clamp(fromMs + 40.0, _maxAutomationTimelineMs())
            .toDouble();
        final direction = (data['direction'] ?? target['direction'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final base = _resolvedAutomationValueAtMs(
          row,
          targetId,
          fromMs,
        );
        final v0 = _normalizedActionValueForTarget(
          data['start_value'] ?? data['from_value'] ?? data['value'],
          targetMeta,
          valueMode: valueMode,
          fallback: base,
        );
        final v1 = _normalizedActionValueForTarget(
          data['end_value'] ?? data['to_value'],
          targetMeta,
          valueMode: valueMode,
          fallback: direction == 'down'
              ? (v0 - 0.35).clamp(0.0, 1.0).toDouble()
              : direction == 'up'
                  ? (v0 + 0.35).clamp(0.0, 1.0).toDouble()
                  : v0,
        );
        await _setAutomationTargetPointsWithUndo(
            row, targetId, <AutomationPoint>[
          AutomationPoint(x: fromMs, volume: v0),
          AutomationPoint(x: toMs, volume: v1),
        ]);
        _showSmallNotice('Set automation points.');
        return;
      }
      _insertAssistantChatText(
          "I need automation points to apply (time/value pairs).");
      return;
    }

    await _setAutomationTargetPointsWithUndo(row, targetId, points);
    _showSmallNotice('Set automation points.');
  }

  int? _pitchClassFromToken(String token) {
    return AssistantActionUtils.pitchClassFromToken(token);
  }

  int? _midiPitchFromRaw(dynamic raw, {int fallbackOctave = 3}) {
    return AssistantActionUtils.midiPitchFromRaw(
      raw,
      fallbackOctave: fallbackOctave,
    );
  }

  int? _rootMidiFromChordToken(String token, {int octave = 2}) {
    return AssistantActionUtils.rootMidiFromChordToken(token, octave: octave);
  }

  List<String> _progressionTokensFromActionData(Map<String, dynamic> data) {
    final target = _actionTarget(data);
    final rawProgression = data['progression'] ??
        target['progression'] ??
        data['chords'] ??
        target['chords'] ??
        data['pattern'] ??
        target['pattern'] ??
        data['sequence'] ??
        target['sequence'] ??
        data['text'] ??
        target['text'] ??
        data['request'] ??
        target['request'];
    return AssistantActionUtils.progressionTokensFromRaw(rawProgression);
  }

  List<MidiNote> _fallbackMidiNotesFromProgression(Map<String, dynamic> data) {
    final tokens = _progressionTokensFromActionData(data);
    if (tokens.isEmpty) return const <MidiNote>[];

    final beatsPerChord = _toActionDouble(
            data['beats_per_chord'] ?? data['chord_length_beats']) ??
        4.0;
    final notesPerChord =
        (_toActionInt(data['notes_per_chord']) ?? 4).clamp(1, 8).toInt();
    final octave = (_toActionInt(data['octave']) ?? 2).clamp(-1, 8).toInt();
    final velocity =
        (_toActionDouble(data['velocity']) ?? 0.78).clamp(0.2, 1.0).toDouble();

    return AssistantActionUtils.fallbackMidiNotesFromProgression(
      progressionRaw: tokens,
      beatsPerChord: beatsPerChord,
      notesPerChord: notesPerChord,
      octave: octave,
      velocity: velocity,
      noteIdPrefix: 'ai_prog',
    );
  }

  List<MidiNote> _midiNotesFromActionData(Map<String, dynamic> data) {
    final rawNotes = (data['notes'] as List?) ?? const [];
    final out = <MidiNote>[];
    int i = 0;
    for (final raw in rawNotes) {
      final m = _toActionMap(raw);
      final pitch = _midiPitchFromRaw(
        m['pitch'] ?? m['midi'] ?? m['note'] ?? m['note_name'],
      );
      final startBeat = _toActionDouble(
        m['start_beat'] ?? m['startBeat'] ?? m['beat'] ?? m['start'],
      );
      final lengthBeats = _toActionDouble(
              m['length_beats'] ?? m['lengthBeat'] ?? m['length']) ??
          _toActionDouble(m['duration_beats'] ?? m['duration']);
      final velocity = _toActionDouble(m['velocity']) ?? 0.8;
      if (pitch == null || startBeat == null || lengthBeats == null) continue;
      out.add(
        MidiNote(
          id: 'ai_note_${DateTime.now().microsecondsSinceEpoch}_${i++}',
          pitch: pitch.clamp(0, 127).toInt(),
          startBeat: math.max(0.0, startBeat),
          lengthBeats: math.max(0.0625, lengthBeats),
          velocity: velocity.clamp(0.0, 1.0).toDouble(),
        ),
      );
    }
    return out;
  }

  int _midiSubdivisionFromActionData(
    Map<String, dynamic> data, {
    int fallback = 16,
  }) {
    final target = _actionTarget(data);

    int? parseSubdivision(dynamic raw) {
      if (raw is num) return raw.round();
      if (raw is! String) return null;

      final text = raw.trim().toLowerCase();
      if (text.isEmpty) return null;

      int? out;
      final fraction = RegExp(r'^1\s*/\s*(\d+)$').firstMatch(text);
      if (fraction != null) {
        out = int.tryParse(fraction.group(1) ?? '');
      }
      out ??= int.tryParse(text);
      if (out == null) {
        final embedded = RegExp(r'(\d+)').firstMatch(text);
        if (embedded != null) {
          out = int.tryParse(embedded.group(1) ?? '');
        }
      }
      out ??= () {
        if (text.contains('whole')) return 1;
        if (text.contains('half')) return 2;
        if (text.contains('quarter')) return 4;
        if (text.contains('8th') || text.contains('eighth')) return 8;
        if (text.contains('16th') || text.contains('sixteenth')) return 16;
        if (text.contains('32nd') || text.contains('thirty-second')) return 32;
        if (text.contains('64th') || text.contains('sixty-fourth')) return 64;
        return null;
      }();
      if (out == null || out <= 0) return null;
      if (text.contains('triplet')) {
        out = math.max(1, ((out * 3.0) / 2.0).round());
      }
      return out;
    }

    int? resolved;
    for (final raw in <dynamic>[
      data['subdivision'],
      target['subdivision'],
      data['subdivision_divisor'],
      target['subdivision_divisor'],
      data['grid'],
      target['grid'],
      data['resolution'],
      target['resolution'],
      data['note_value'],
      target['note_value'],
    ]) {
      final parsed = parseSubdivision(raw);
      if (parsed != null) {
        resolved = parsed;
        break;
      }
    }

    if (resolved == null) {
      final stepBeats = _toActionDouble(
        data['step_beats'] ??
            target['step_beats'] ??
            data['beats_per_slice'] ??
            target['beats_per_slice'] ??
            data['slice_beats'] ??
            target['slice_beats'],
      );
      if (stepBeats != null && stepBeats.isFinite && stepBeats > 0.0) {
        resolved = (4.0 / stepBeats).round();
      }
    }

    return (resolved ?? fallback).clamp(1, 128).toInt();
  }

  List<MidiNote> _chopMidiNotesFromActionData(
    Map<String, dynamic> data,
    List<MidiNote> sourceNotes, {
    int? subdivision,
  }) {
    final target = _actionTarget(data);
    final safeSubdivision = subdivision ??
        _midiSubdivisionFromActionData(
          data,
          fallback: 16,
        );
    final stepBeats = _toActionDouble(
      data['step_beats'] ??
          target['step_beats'] ??
          data['beats_per_slice'] ??
          target['beats_per_slice'] ??
          data['slice_beats'] ??
          target['slice_beats'],
    );
    final sustainRatio = (_toActionDouble(
              data['sustain_ratio'] ??
                  target['sustain_ratio'] ??
                  data['gate'] ??
                  target['gate'] ??
                  data['length_ratio'] ??
                  target['length_ratio'],
            ) ??
            1.0)
        .clamp(0.05, 1.0)
        .toDouble();
    final minLengthBeats = (_toActionDouble(
              data['min_length_beats'] ?? target['min_length_beats'],
            ) ??
            0.03125)
        .clamp(0.0005, 4.0)
        .toDouble();
    final velocityDecayPerSlice = (_toActionDouble(
              data['velocity_decay_per_slice'] ??
                  target['velocity_decay_per_slice'] ??
                  data['decay_per_slice'] ??
                  target['decay_per_slice'] ??
                  data['velocity_decay'] ??
                  target['velocity_decay'] ??
                  data['stutter_decay'] ??
                  target['stutter_decay'],
            ) ??
            0.0)
        .clamp(-1.0, 1.0)
        .toDouble();
    final velocityJitter = (_toActionDouble(
              data['velocity_jitter'] ??
                  target['velocity_jitter'] ??
                  data['humanize_velocity_jitter'] ??
                  target['humanize_velocity_jitter'],
            ) ??
            0.0)
        .clamp(0.0, 1.0)
        .toDouble();
    final velocityFloor = (_toActionDouble(
              data['velocity_floor'] ??
                  target['velocity_floor'] ??
                  data['min_velocity'] ??
                  target['min_velocity'],
            ) ??
            0.05)
        .clamp(0.0, 1.0)
        .toDouble();
    final fromBeat = _toActionDouble(
      data['from_beat'] ?? target['from_beat'] ?? data['start_beat'],
    );
    final toBeat = _toActionDouble(
      data['to_beat'] ?? target['to_beat'] ?? data['end_beat'],
    );

    return AssistantActionUtils.chopMidiNotes(
      notes: sourceNotes,
      subdivision: safeSubdivision,
      stepBeats: stepBeats,
      sustainRatio: sustainRatio,
      minLengthBeats: minLengthBeats,
      velocityDecayPerSlice: velocityDecayPerSlice,
      velocityJitter: velocityJitter,
      velocityFloor: velocityFloor,
      fromBeat: fromBeat,
      toBeat: toBeat,
      noteIdPrefix: 'ai_chop',
    );
  }

  Future<void> _applyMidiComposeAction(Map<String, dynamic> data) async {
    final operation = _normalizeMidiComposeOperation(
      (data['operation'] ?? '').toString().trim().toLowerCase(),
    );
    final target = _actionTarget(data);
    int? clipIndex = _resolveSingleClipIndexWithFallback(
      data,
      requireMidi: true,
    );
    if (clipIndex == null) {
      final rowHint = _resolveRowIndexFromActionTarget(data);
      if (rowHint != null) {
        final midiCandidates = <int>[];
        for (int i = 0; i < _audioTracks.length; i++) {
          final clip = _audioTracks[i];
          if (!clip.isMidi) continue;
          if (clip.rowIndex != rowHint) continue;
          midiCandidates.add(i);
        }
        clipIndex = _pickPreferredClipIndex(midiCandidates);
      }
    }

    if (operation == 'chop_notes') {
      if (clipIndex == null ||
          clipIndex < 0 ||
          clipIndex >= _audioTracks.length) {
        _insertAssistantChatText(
            "I couldn't resolve which MIDI clip to chop. Select a MIDI clip and ask again.");
        return;
      }
      final clip = _audioTracks[clipIndex];
      if (!clip.isMidi) {
        _insertAssistantChatText('The selected clip is not a MIDI clip.');
        return;
      }
      if (clip.midiNotes.isEmpty) {
        _insertAssistantChatText('The target MIDI clip has no notes to chop.');
        return;
      }

      final oldNotes = clip.midiNotes.map((n) => n.copy()).toList();
      final oldParams = Map<String, double>.from(clip.instrumentParams);
      final oldInstrumentId = clip.instrumentId;
      final oldInstrumentName = clip.instrumentName;
      final subdivision = _midiSubdivisionFromActionData(data, fallback: 16);
      final decayPerSlice = (_toActionDouble(
                data['velocity_decay_per_slice'] ??
                    data['decay_per_slice'] ??
                    data['velocity_decay'] ??
                    data['stutter_decay'],
              ) ??
              0.0)
          .toDouble();
      final nextNotes = _chopMidiNotesFromActionData(
        data,
        oldNotes,
        subdivision: subdivision,
      );

      if (_midiNotesEqual(oldNotes, nextNotes)) {
        _showSmallNotice('MIDI notes already match that chop grid.');
        return;
      }

      await _undoManager.execute(
        EditMidiClipAction(
          tracks: _audioTracks,
          originalIndex: clipIndex,
          oldNotes: oldNotes,
          newNotes: nextNotes,
          oldInstrumentId: oldInstrumentId,
          oldInstrumentName: oldInstrumentName,
          oldInstrumentParams: oldParams,
          newInstrumentId: oldInstrumentId,
          newInstrumentName: oldInstrumentName,
          newInstrumentParams: oldParams,
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
            if (mounted) setState(() {});
          },
        ),
      );
      final withDecay = decayPerSlice.abs() > 0.0001;
      _showSmallNotice(
        withDecay
            ? 'Chopped MIDI notes to 1/$subdivision with velocity decay.'
            : 'Chopped MIDI notes to 1/$subdivision.',
      );
      return;
    }

    var notes = _midiNotesFromActionData(data);
    if (notes.isEmpty) {
      notes = _fallbackMidiNotesFromProgression(data);
    }
    if (notes.isEmpty) {
      _insertAssistantChatText(
          "I need MIDI notes (or a chord progression) to write this part.");
      return;
    }

    if (clipIndex == null ||
        clipIndex < 0 ||
        clipIndex >= _audioTracks.length) {
      final row = _resolveRowIndexFromActionTarget(data) ??
          (_rowCount > 0 ? _selectedRow.clamp(0, _rowCount - 1) : 0);
      final instrumentId = (data['instrument_id'] ??
              target['instrument_id'] ??
              'mixroom.sub_bass')
          .toString()
          .trim();
      final instrumentName = (data['instrument_name'] ??
              target['instrument_name'] ??
              _instrumentNameFromId(instrumentId))
          .toString()
          .trim();
      final startMs = _toActionDouble(data['start_ms'] ?? target['start_ms']) ??
          _globalAudioClock.inMilliseconds.toDouble();

      await _addMidiTrack(
        instrumentId: instrumentId,
        instrumentName: instrumentName.isEmpty ? instrumentId : instrumentName,
        instrumentParams:
            _instrumentParamsFromSpec(_instrumentSpecById(instrumentId)),
        midiNotes: notes,
        row: row,
        timeMs: math.max(0.0, startMs),
        label: data['label']?.toString(),
      );
      _showSmallNotice('Created MIDI clip from AI notes.');
      return;
    }

    final clip = _audioTracks[clipIndex];
    if (!clip.isMidi) {
      _insertAssistantChatText('The selected clip is not a MIDI clip.');
      return;
    }

    final append = _toActionBool(
      data['append'],
      fallback: operation.contains('append'),
    );
    final oldNotes = clip.midiNotes.map((n) => n.copy()).toList();
    final oldParams = Map<String, double>.from(clip.instrumentParams);
    final oldInstrumentId = clip.instrumentId;
    final oldInstrumentName = clip.instrumentName;

    List<MidiNote> nextNotes = notes.map((n) => n.copy()).toList();
    if (append) {
      double appendStartBeat =
          _toActionDouble(data['append_start_beat']) ?? 0.0;
      final appendAtEnd = _toActionBool(data['append_at_end'], fallback: true);
      if (appendAtEnd && oldNotes.isNotEmpty) {
        appendStartBeat =
            oldNotes.map((n) => n.startBeat + n.lengthBeats).reduce(math.max);
      }
      nextNotes = [
        ...oldNotes.map((n) => n.copy()),
        ...notes.map((n) => MidiNote(
              id: 'ai_note_${DateTime.now().microsecondsSinceEpoch}_${n.pitch}',
              pitch: n.pitch,
              startBeat: n.startBeat + appendStartBeat,
              lengthBeats: n.lengthBeats,
              velocity: n.velocity,
            )),
      ];
    }

    await _undoManager.execute(
      EditMidiClipAction(
        tracks: _audioTracks,
        originalIndex: clipIndex,
        oldNotes: oldNotes,
        newNotes: nextNotes,
        oldInstrumentId: oldInstrumentId,
        oldInstrumentName: oldInstrumentName,
        oldInstrumentParams: oldParams,
        newInstrumentId: oldInstrumentId,
        newInstrumentName: oldInstrumentName,
        newInstrumentParams: oldParams,
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
          if (mounted) setState(() {});
        },
      ),
    );
    _showSmallNotice(
      append ? 'Appended MIDI notes.' : 'Updated MIDI notes.',
    );
  }

  Future<void> _applyStemSeparateAction(Map<String, dynamic> data) async {
    final target = _actionTarget(data);
    final clipIndices =
        _resolveClipIndicesFromActionTarget(data, requireAudio: true);
    if (clipIndices.isEmpty) {
      _insertAssistantChatText(
          "I couldn't resolve which audio clip to separate.");
      return;
    }

    final scope = (target['scope'] ?? data['scope'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final explicitMany =
        ((data['clip_indices'] as List?)?.isNotEmpty ?? false) ||
            ((target['clip_indices'] as List?)?.isNotEmpty ?? false) ||
            scope == 'all' ||
            scope == 'all_audio' ||
            scope == 'selected' ||
            scope == 'selection';

    final targets = explicitMany
        ? clipIndices
        : <int>[
            _resolveSingleClipIndexWithFallback(
                  data,
                  requireAudio: true,
                ) ??
                clipIndices.first
          ];

    int success = 0;
    for (final clipIndex in targets) {
      final ok = await _performStemSeparationForClip(
        clipIndex,
        showInlineFailureNotice: !explicitMany,
      );
      if (ok) success++;
    }

    if (success <= 0) {
      if (explicitMany) {
        _showSmallNotice('Stem separation failed for target clips.');
      }
      return;
    }

    if (explicitMany && success > 1) {
      _showSmallNotice('Created stems for $success clips.');
    }
  }

  Future<void> _applyRoleOverrideAction(Map<String, dynamic> data) async {
    final operation =
        (data['operation'] ?? 'set').toString().trim().toLowerCase();
    final row = _resolveRowIndexFromActionTarget(data);
    if (row == null) {
      _insertAssistantChatText(
          "I couldn't resolve which track role to update.");
      return;
    }

    if (operation == 'clear' ||
        operation == 'remove' ||
        operation == 'unset' ||
        operation == 'delete') {
      final cleared = _chatPipeline.clearRoleOverride(row);
      if (cleared) {
        _showSmallNotice('Cleared role override for Track ${row + 1}.');
      } else {
        _showSmallNotice('Track ${row + 1} had no role override set.');
      }
      return;
    }

    final target = _actionTarget(data);
    final role = (data['role'] ?? target['role'] ?? '').toString().trim();
    if (role.isEmpty) {
      _insertAssistantChatText(
          'I need a role value to apply (vocals, drums, bass, guitar, synth, other).');
      return;
    }

    final applied = _chatPipeline.setRoleOverride(rowIndex: row, role: role);
    if (!applied) {
      _insertAssistantChatText(
          'Unsupported role "$role". Use vocals, drums, bass, guitar, synth, or other.');
      return;
    }

    final roleText = role.toLowerCase().trim();
    _showSmallNotice('Track ${row + 1} role override set to $roleText.');
  }

  Future<void> _handleStemSeparationForClip(int clipIndex) async {
    await _performStemSeparationForClip(clipIndex);
  }

  Future<bool> _performStemSeparationForClip(
    int clipIndex, {
    bool showInlineFailureNotice = true,
  }) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return false;
    final clip = _audioTracks[clipIndex];
    if (clip.isMidi) {
      if (showInlineFailureNotice) {
        _showSmallNotice('Stem separation is only available for audio clips.');
      }
      return false;
    }
    if (_audioTracks.length + 2 > kNumClips) {
      if (showInlineFailureNotice) {
        _showSmallNotice(
            "Max number of audio clips reached ($kNumClips). Unable to add more clips.");
      }
      return false;
    }

    final sourcePath = clip.file.path;
    final source = File(sourcePath);
    if (!source.existsSync()) {
      if (showInlineFailureNotice) {
        _showSmallNotice('Selected clip file was not found.');
      }
      return false;
    }

    final audioDir = ProjectManager.audioDir(_projectDir);
    await audioDir.create(recursive: true);
    final stem = p.basenameWithoutExtension(source.path);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final vocalFile = File(p.join(audioDir.path, '${stem}_vocals_$ts.wav'));
    final instrumentalFile =
        File(p.join(audioDir.path, '${stem}_instrumental_$ts.wav'));

    if (showInlineFailureNotice) {
      _showSmallNotice('Separating stems with Spleeter...');
    }
    try {
      await _spleeterStemSeparator.separateVocalsInstrumental(
        inputPath: source.path,
        vocalsOutputPath: vocalFile.path,
        instrumentalOutputPath: instrumentalFile.path,
      );
    } catch (e) {
      debugPrint('Spleeter stem separation failed: $e');
      if (showInlineFailureNotice) {
        _showSmallNotice('Stem separation failed.');
      }
      return false;
    }

    if (!vocalFile.existsSync() || !instrumentalFile.existsSync()) {
      if (showInlineFailureNotice) {
        _showSmallNotice('Stem separation failed.');
      }
      return false;
    }

    final row = clip.rowIndex;
    final startMs = clip.offset * 1000.0;
    final trimStart = clip.trimStart;
    final trimEnd = clip.trimEnd;

    final addVocals = AddAudioTrackAction(
      addTrack: ({
        required File file,
        required int row,
        required double timeMs,
        Duration? trimStartRequested,
        Duration? trimEndRequested,
      }) =>
          _addAudioTrackFromProjectFile(
        projectAudioFile: file,
        label:
            clip.label.trim().isEmpty ? 'Vocals Stem' : '${clip.label} Vocals',
        row: row,
        timeMs: timeMs,
        trimStartRequested: trimStartRequested,
        trimEndRequested: trimEndRequested,
        gain: clip.gain,
        sourceTempoBpm: clip.sourceTempoBpm,
        stretchToProjectTempo: clip.stretchToProjectTempo,
        tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
      ),
      tracks: _audioTracks,
      file: vocalFile,
      row: row,
      timeMs: startMs,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );

    final addInstrumental = AddAudioTrackAction(
      addTrack: ({
        required File file,
        required int row,
        required double timeMs,
        Duration? trimStartRequested,
        Duration? trimEndRequested,
      }) =>
          _addAudioTrackFromProjectFile(
        projectAudioFile: file,
        label: clip.label.trim().isEmpty
            ? 'Instrumental Stem'
            : '${clip.label} Instrumental',
        row: row,
        timeMs: timeMs,
        trimStartRequested: trimStartRequested,
        trimEndRequested: trimEndRequested,
        gain: clip.gain,
        sourceTempoBpm: clip.sourceTempoBpm,
        stretchToProjectTempo: clip.stretchToProjectTempo,
        tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
      ),
      tracks: _audioTracks,
      file: instrumentalFile,
      row: row,
      timeMs: startMs,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );

    await _undoManager.execute(
      CompoundUndoAction('Separate stems', [addVocals, addInstrumental]),
    );
    if (showInlineFailureNotice) {
      _showSmallNotice('Created vocal/instrumental stems with Spleeter.');
    }
    return true;
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
        maxRows, (i) => i < _rowGain.length ? _rowGain[i] : _kGainUiUnity);
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

  Future<void> _ensureAiModelsLoaded() {
    _aiModelsWarmupFuture ??= _loadAiModels();
    return _aiModelsWarmupFuture!;
  }

  Future<void> _loadAiModels() async {
    await _classifier.load();
    await _magnitudePredictor.load();
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

    await _ensureAiModelsLoaded();
    final reply = await _chatPipeline.handleUserText(
      text: prompt,
      audioTracks: _audioTracks,
      bpmFallback: _tempo,
      rowGain: _rowGain,
      rowPan: _rowPan,
      rowAutomation: _rowVolumeAutomation,
      masterGain0to3: _masterGain,
      masterPan0to1: _masterPan,
      selectedClipIndices: _timelineSelectedClipIndices,
      primarySelectedClipIndex: _timelinePrimarySelectedClipIndex,
      selectedRowIndex: _selectedRow,
      autoApplyProposals: true, // <-- key
    );

    if (kAiDebugLogs) {
      aiDebugLog('audio-editor', 'one-button-mix reply:\n${reply.toString()}');
      if (reply.meta != null) {
        aiDebugLog(
          'audio-editor',
          'one-button-mix meta=${aiDebugShortMap(reply.meta!)}',
        );
      }
    }

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

    if (reply.hasAssistantActions) {
      await _applyAssistantActions(reply.assistantActions);
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
    const androidTransportBottomOffset = 10.0;
    final bottomInset =
        includeTransport && defaultTargetPlatform == TargetPlatform.android
            ? math.max(
                0.0,
                MediaQuery.of(context).viewPadding.bottom -
                    androidTransportBottomOffset,
              )
            : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                    child: Halo(
                      highlighter: _mixHighlighter,
                      haloKey: const HaloKey('tutorial:chatbar'),
                      borderRadius: BorderRadius.circular(18),
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
                            producerPreSnapshot =
                                await _buildProducerSnapshot();
                          }

                          // 2. Run pipeline
                          await _ensureAiModelsLoaded();
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
                            selectedClipIndices: _timelineSelectedClipIndices,
                            primarySelectedClipIndex:
                                _timelinePrimarySelectedClipIndex,
                            selectedRowIndex: _selectedRow,
                            // autoApplyProposals: true, // does not ask for approval, just execute
                          );

                          if (kAiDebugLogs) {
                            aiDebugLog('audio-editor', reply.toString());
                            if (reply.meta != null) {
                              aiDebugLog(
                                'audio-editor',
                                'reply.meta=${aiDebugShortMap(reply.meta!)}',
                              );
                            }
                          }

                          // await applyMixingResult(reply);
                          if (reply.hasMix) {
                            await applyMixingResult(reply.mixing!);

                            // IMPORTANT: teach the assistant what actually changed
                            _chatPipeline.recordAppliedMix(reply.mixing!);

                            if (_producerDataMode &&
                                producerPreSnapshot != null) {
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

                          if (reply.hasAssistantActions) {
                            await _applyAssistantActions(
                                reply.assistantActions);
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
                                  : Colors.white
                                      .withOpacity(_kChatChromeOpacity),
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
            Halo(
              highlighter: _mixHighlighter,
              haloKey: const HaloKey('tutorial:toolbar'),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: Container(
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
                      color:
                          Colors.white.withOpacity(0.07), // softer white glass
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(28)),
                      border: Border(
                          top: BorderSide(
                              color: Colors.white.withOpacity(0.08))),
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
                                      final height =
                                          constraints.maxHeight * 0.6;
                                      return Container(
                                        height: height,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withOpacity(0.14)),
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
                                                    topLeft:
                                                        Radius.circular(22),
                                                    bottomLeft:
                                                        Radius.circular(22),
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
                                                              ScaffoldMessenger
                                                                  .of(context);
                                                          messenger
                                                              .hideCurrentSnackBar();
                                                          messenger
                                                              .showSnackBar(
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
                                                        color: _undoManager
                                                                .canUndo
                                                            ? Colors.white
                                                            : Colors.white
                                                                .withOpacity(
                                                                    0.3),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Container(
                                                width: 1,
                                                height: 28,
                                                color: Colors.white
                                                    .withOpacity(0.2)),
                                            Expanded(
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topRight:
                                                        Radius.circular(22),
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
                                                              ScaffoldMessenger
                                                                  .of(context);
                                                          messenger
                                                              .hideCurrentSnackBar();
                                                          messenger
                                                              .showSnackBar(
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
                                                        color: _undoManager
                                                                .canRedo
                                                            ? Colors.white
                                                            : Colors.white
                                                                .withOpacity(
                                                                    0.3),
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
                                      final height =
                                          constraints.maxHeight * 0.6;
                                      final iconSize = height * 0.55;
                                      final borderRadius =
                                          BorderRadius.circular(height / 2);

                                      return Container(
                                        height: height,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.06),
                                          borderRadius: borderRadius,
                                          border: Border.all(
                                              color: Colors.white
                                                  .withOpacity(0.14)),
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
                                              haloKey:
                                                  'tutorial:transport:restart',
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
                                              haloKey:
                                                  'tutorial:transport:play',
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
                                              haloKey:
                                                  'tutorial:transport:record',
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          // --- Blue glossy pill with logo only ---
                                          // --- Blue glossy pill with logo only ---
                                          // Wrap with Material + InkWell for proper tap + ripple on rounded pill
                                          Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      pillHeight / 2),
                                              onTap: () async {
                                                // optional: haptic
                                                // HapticFeedback.lightImpact();
                                                final run =
                                                    await showDialog<bool>(
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
                                                        child: const Text(
                                                            'Cancel'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child:
                                                            const Text('Run'),
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
                                                    duration:
                                                        Duration(seconds: 3),
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
                                                    gradient:
                                                        const LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
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
                                                          decoration:
                                                              BoxDecoration(
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
                                                                Colors
                                                                    .transparent,
                                                                Colors
                                                                    .transparent,
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
                                                          height:
                                                              pillHeight * 0.6,
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
            ),
        ],
      ),
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
    String? haloKey,
  }) {
    final resolvedRadius = radius ?? BorderRadius.zero;
    Widget segmentChild = InkWell(
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
    );

    if (haloKey != null && haloKey.isNotEmpty) {
      segmentChild = Halo(
        highlighter: _mixHighlighter,
        haloKey: HaloKey(haloKey),
        borderRadius: resolvedRadius,
        child: segmentChild,
      );
    }

    return Expanded(
      child: segmentChild,
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

  Float32List _lowPassMono(
    Float32List input, {
    int sampleRate = 16000,
    double cutoffHz = 220.0,
  }) {
    if (input.isEmpty) return input;
    final clampedCutoff = cutoffHz.clamp(20.0, sampleRate * 0.45).toDouble();
    final alpha = math.exp(-2.0 * math.pi * clampedCutoff / sampleRate);
    final out = Float32List(input.length);
    double y = 0.0;
    for (int i = 0; i < input.length; i++) {
      y = (1.0 - alpha) * input[i] + alpha * y;
      out[i] = y.toDouble();
    }
    return out;
  }

  List<double> _detectTransientTimesMsFromOnsetEnvelope(
    List<double> onsetEnv, {
    required double envSampleRateHz,
    double thresholdStd = 1.25,
    double minSpacingMs = 110.0,
    int maxEvents = 256,
  }) {
    if (onsetEnv.length < 8 || envSampleRateHz <= 0.0) return const <double>[];
    final n = onsetEnv.length;

    double mean = 0.0;
    for (final v in onsetEnv) {
      mean += v;
    }
    mean /= n;

    double variance = 0.0;
    for (final v in onsetEnv) {
      final d = v - mean;
      variance += d * d;
    }
    variance /= n;
    final std = math.sqrt(math.max(variance, 0.0));
    final threshold =
        math.max(mean + std * thresholdStd, mean * 1.65 + 0.000015);

    final minFrames = math.max(
      1,
      (minSpacingMs * envSampleRateHz / 1000.0).round(),
    );
    int lastAccepted = -minFrames * 2;
    final out = <double>[];

    for (int i = 1; i < n - 1; i++) {
      final v = onsetEnv[i];
      if (v < threshold) continue;
      if (v <= onsetEnv[i - 1] || v < onsetEnv[i + 1]) continue;
      if (i - lastAccepted < minFrames) {
        if (out.isNotEmpty && v > onsetEnv[lastAccepted]) {
          out.removeLast();
          out.add((i * 1000.0) / envSampleRateHz);
          lastAccepted = i;
        }
        continue;
      }
      out.add((i * 1000.0) / envSampleRateHz);
      lastAccepted = i;
      if (out.length >= maxEvents) break;
    }
    return out;
  }

  Future<List<double>> _detectKickTimelineOnsetsMsForClip(
    AudioTrack clip, {
    double cutoffHz = 220.0,
    double thresholdStd = 1.25,
    double minSpacingMs = 110.0,
    int maxEvents = 256,
  }) async {
    if (clip.isMidi) return const <double>[];

    const int sampleRate = 16000;
    Float32List decoded = Float32List(0);
    try {
      decoded = await JuceAudioEngine.decodeAudioMono16k(clip.file.path);
    } catch (_) {
      return const <double>[];
    }
    if (decoded.isEmpty) return const <double>[];

    int start = (clip.trimStart.inMilliseconds * sampleRate / 1000).round();
    int end = (clip.trimEnd.inMilliseconds * sampleRate / 1000).round();
    start = start.clamp(0, decoded.length);
    end = end.clamp(start, decoded.length);
    if (end <= start) return const <double>[];
    final segment = Float32List.sublistView(decoded, start, end);
    final lowPassed = _lowPassMono(
      segment,
      sampleRate: sampleRate,
      cutoffHz: cutoffHz,
    );

    const int frameSize = 1024;
    const int hopSize = 256;
    final env = _buildOnsetEnvelopeFromSamples(
      lowPassed,
      frameSize: frameSize,
      hopSize: hopSize,
    );
    if (env.isEmpty) return const <double>[];
    final envHz = sampleRate / hopSize;
    final localMs = _detectTransientTimesMsFromOnsetEnvelope(
      env,
      envSampleRateHz: envHz,
      thresholdStd: thresholdStd,
      minSpacingMs: minSpacingMs,
      maxEvents: maxEvents,
    );
    if (localMs.isEmpty) return const <double>[];

    final clipStartMs = clip.offset * 1000.0;
    final maxTimelineMs = _maxAutomationTimelineMs();
    return localMs
        .map((ms) => (clipStartMs + ms).clamp(0.0, maxTimelineMs).toDouble())
        .toList(growable: false);
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
    bool showFeedback = true,
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

    if (!mounted || !showFeedback) return;
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
    _pendingStretchUndoByClip.putIfAbsent(
      clipIndex,
      () => _ClipStretchSnapshot(
        offsetSec: clip.offset,
        sourceTempoBpm: clip.sourceTempoBpm,
        stretchToProjectTempo: clip.stretchToProjectTempo,
        tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
      ),
    );

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
    final before = _pendingStretchUndoByClip.remove(clipIndex);
    final after = _ClipStretchSnapshot(
      offsetSec: clip.offset,
      sourceTempoBpm: clip.sourceTempoBpm,
      stretchToProjectTempo: clip.stretchToProjectTempo,
      tempoStretchPreservePitch: clip.tempoStretchPreservePitch,
    );

    if (before == null || before.approxEquals(after)) {
      await _syncClipTimingToEngine(clipIndex);
      await _syncClipMixToEngine(clip);
      _updateOverallDurationIfNeeded();
      if (mounted) setState(() {});
      return;
    }

    await _undoManager.execute(
      StretchClipResizeAction(
        tracks: _audioTracks,
        originalIndex: clipIndex,
        oldSnapshot: before,
        newSnapshot: after,
        applySnapshot: (target, snapshot) async {
          target.offset = snapshot.offsetSec;
          target.sourceTempoBpm = snapshot.sourceTempoBpm;
          target.stretchToProjectTempo = snapshot.stretchToProjectTempo;
          target.tempoStretchPreservePitch = snapshot.tempoStretchPreservePitch;
          _tempoStretchEnabled = _audioTracks
              .where((t) => !t.isMidi)
              .any((t) => t.stretchToProjectTempo);
          final targetIndex = _audioTracks.indexOf(target);
          if (targetIndex >= 0) {
            await _syncClipTimingToEngine(targetIndex);
          }
          await _syncClipMixToEngine(target);
          _updateOverallDurationIfNeeded();
          if (mounted) setState(() {});
        },
      ),
    );
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
      if (_rowCount > 0) {
        _selectedRow = clip.rowIndex.clamp(0, _rowCount - 1).toInt();
      }
      _activeMidiClipEngineId = clip.engineClipId;
      _showPianoRoll = true;
    });
    if (_liveMidiEventPlaybackSupported && clip.engineClipId >= 0) {
      unawaited(() async {
        await JuceAudioEngine.setLiveMidiInputTargetClip(clip.engineClipId);
        await JuceAudioEngine.consumeLiveMidiInputEvents();
      }());
    }
  }

  void _closeMidiClipEditor() {
    setState(() {
      _showPianoRoll = false;
      _pianoRollFullscreen = false;
      _activeMidiClipEngineId = null;
    });
    if (_liveMidiEventPlaybackSupported && !_isMidiClipRecording) {
      unawaited(() async {
        await JuceAudioEngine.setLiveMidiInputTargetClip(-1);
        await JuceAudioEngine.consumeLiveMidiInputEvents();
      }());
    }
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
        final rendered = await _renderInstrumentClipToFile(
          outFile: outFile,
          instrumentId: clip.instrumentId,
          instrumentName: clip.instrumentName,
          notes: <MidiNote>[previewNote],
          params: Map<String, double>.from(clip.instrumentParams),
        );
        if (!rendered || !outFile.existsSync()) return;
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
    _rowGain[row] = _kGainUiUnity;
    _rowPan[row] = 0.5;
    _rowVolumeAutomation[row] = [AutomationPoint(x: 0.0, volume: 0.75)];
    _rowPluginAutomation[row] = <String, List<AutomationPoint>>{};
    _rowAutomationClips[row] = <String, List<AutomationClipSnapshot>>{};
    _rowSelectedAutomationTarget[row] = 'volume';

    await JuceAudioEngine.setRowGain(row, _kGainUiUnity);
    await JuceAudioEngine.setRowPan(row, 0.5);
    await _syncNativeAutomationForRow(row);
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
        final editorLayoutSpec =
            _EditorLayoutSpec.fromSize(MediaQuery.of(context).size);
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
                                padding: EdgeInsets.only(
                                    bottom: editorLayoutSpec.topBarBottomGap),
                                child: ValueListenableBuilder<Duration>(
                                  valueListenable: _transportClock,
                                  builder: (_, clock, __) =>
                                      _buildTopBar(clock, editorLayoutSpec),
                                )),

                            Flexible(
                              fit: FlexFit.loose,
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _transportClock,
                                builder: (_, clock, __) => Halo(
                                  highlighter: _mixHighlighter,
                                  haloKey: const HaloKey('tutorial:timeline'),
                                  borderRadius: BorderRadius.circular(12),
                                  child: AudioCanvasTimeline(
                                    rows: _rows,
                                    clips: _audioTracks, // your list
                                    rowGain: _rowGain,
                                    rowPan: _rowPan,
                                    rowVolumeAutomation: _rowVolumeAutomation,
                                    getAutomationTargetsForRow:
                                        _automationTargetsForRowUi,
                                    getSelectedAutomationTargetId:
                                        _selectedAutomationTargetIdForRow,
                                    setSelectedAutomationTargetId:
                                        (row, targetId) {
                                      _setSelectedAutomationTargetIdForRow(
                                        row,
                                        targetId,
                                      );
                                      unawaited(
                                          _syncAutomationTargetToCurrentTime(
                                        row,
                                        targetId,
                                      ));
                                    },
                                    getAutomationPointsForTarget:
                                        (row, targetId) =>
                                            _pointsForAutomationTarget(
                                      row,
                                      targetId,
                                    )
                                                .map((p) => p.copy())
                                                .toList(growable: false),
                                    setAutomationPointsForTarget:
                                        (row, targetId, points) {
                                      if (row < 0 || row >= _rowCount) return;
                                      final safePoints =
                                          _sanitizeAutomationPointsForTarget(
                                        row,
                                        targetId,
                                        points,
                                      );
                                      if (targetId == 'volume') {
                                        setState(() {
                                          _rowVolumeAutomation[row] = safePoints
                                              .map((p) => p.copy())
                                              .toList(growable: false);
                                        });
                                        unawaited(
                                            _syncNativeAutomationForRow(row));
                                        return;
                                      }
                                      setState(() {
                                        final rowMap =
                                            _rowPluginAutomation.putIfAbsent(
                                          row,
                                          () =>
                                              <String, List<AutomationPoint>>{},
                                        );
                                        rowMap[targetId] = safePoints
                                            .map((p) => p.copy())
                                            .toList(growable: false);
                                      });
                                      unawaited(
                                          _syncNativePluginAutomationForRow(
                                              row));
                                    },
                                    getAutomationClipsForTarget:
                                        (row, targetId) =>
                                            _copyAutomationClipList(
                                      _clipsForAutomationTarget(row, targetId),
                                    ),
                                    setAutomationClipsForTarget:
                                        (row, targetId, clips) {
                                      if (row < 0 || row >= _rowCount) return;
                                      final safeClips =
                                          _sanitizeAutomationClipsForTarget(
                                        row,
                                        targetId,
                                        clips,
                                      );
                                      setState(() {
                                        final rowMap =
                                            _rowAutomationClips.putIfAbsent(
                                          row,
                                          () => <String,
                                              List<AutomationClipSnapshot>>{},
                                        );
                                        rowMap[targetId] =
                                            _copyAutomationClipList(safeClips);
                                      });
                                      unawaited(_syncNativeAutomationForRow(
                                        row,
                                      ));
                                    },
                                    onAutomationClipsCommit:
                                        (row, targetId, oldClips, newClips) {
                                      unawaited(
                                          _setAutomationClipsForTargetWithUndo(
                                        row,
                                        targetId,
                                        newClips,
                                        oldClipsOverride: oldClips,
                                      ));
                                      _recordProducerManualEdit(
                                          'row_automation_clips', {
                                        'row': row,
                                        'target_id': targetId,
                                        'old_count': oldClips.length,
                                        'new_count': newClips.length,
                                      });
                                    },
                                    onAutomationTargetCommit:
                                        (row, targetId, oldPoints, newPoints) {
                                      unawaited(
                                          _setAutomationTargetPointsWithUndo(
                                        row,
                                        targetId,
                                        newPoints,
                                        oldPointsOverride: oldPoints,
                                      ));
                                      _recordProducerManualEdit(
                                          'row_automation_target', {
                                        'row': row,
                                        'target_id': targetId,
                                        'old_count': oldPoints.length,
                                        'new_count': newPoints.length,
                                      });
                                    },
                                    // extractors
                                    getStartMs: (t) =>
                                        t.offset *
                                        1000.0, // adjust to your model
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
                                            clip.rowId =
                                                _rowIdAt(clip.rowIndex);
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
                                          oldTrimStart: Duration(
                                              milliseconds: os.round()),
                                          oldTrimEnd: Duration(
                                              milliseconds: oe.round()),
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
                                      JuceAudioEngine.setAutomationTransport(
                                          ms / 1000.0);
                                      JuceAudioEngine.setMetronomeTransportMs(
                                          ms);
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

                                    getRowEffectBypassState: (row,
                                            effectIndex) =>
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
                                      await _refreshAutomationTargetsForRow(
                                        row,
                                      );
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
                                      _recordProducerManualEdit(
                                          'row_fx_remove', {
                                        'row': row,
                                        'index': effectIndex,
                                        'effect': name,
                                      });
                                      await _refreshAutomationTargetsForRow(
                                        row,
                                      );
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
                                      _recordProducerManualEdit(
                                          'row_fx_reorder',
                                          {'row': row, 'from': from, 'to': to});
                                      await _refreshAutomationTargetsForRow(
                                        row,
                                      );
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
                                      _recordProducerManualEdit(
                                          'row_fx_bypass', {
                                        'row': row,
                                        'index': effectIndex,
                                        'bypassed': bypass,
                                      });
                                    }, //=> JuceAudioEngine.bypassRowEffect(row, effectIndex, bypass),

                                    getRowPluginParameters:
                                        (row, effectIndex) => JuceAudioEngine
                                            .getTrackPluginParameters(
                                                row, effectIndex),

                                    setRowEffectParam: (row, effectIndex,
                                            paramId, value) =>
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
                                      _recordProducerManualEdit(
                                          'row_fx_param', {
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
                                      await _refreshAutomationTargetsForRow(
                                        before.row,
                                      );
                                    },

                                    scanPlugins: () =>
                                        JuceAudioEngine.scanPlugins(),

                                    setTrackAutomationPoints: (row, points) =>
                                        _syncNativeAutomationForRow(row),

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
                                          onApplied: (r, _) async {
                                            await _syncNativeAutomationForRow(
                                                r);
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
                                        JuceAudioEngine.setRowGain(
                                            row, gain0to3),
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
                                    onAdjustClipToTempo:
                                        _handleAdjustClipToTempo,
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
                                    onStemSeparation:
                                        _handleStemSeparationForClip,
                                    onSelectionChanged: (selectedClipIndices,
                                        primaryClipIndex) {
                                      _timelineSelectedClipIndices =
                                          List<int>.from(selectedClipIndices);
                                      _timelinePrimarySelectedClipIndex =
                                          primaryClipIndex;
                                    },
                                    onSnapSettingsChanged: (magnetEnabled,
                                        quantizeDivisionsPerBar) {
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
                                    registerRowFxPlaybackRefresher: (fn) {
                                      _refreshRowFxPlayback = fn;
                                    },
                                    meters: _meters,
                                    getRowCompressorMeter: (row, fx) =>
                                        JuceAudioEngine.getRowCompressorMeter(
                                            row, fx),
                                    getRowEqWaveform: (row, fx, sampleCount) =>
                                        JuceAudioEngine.getRowEqWaveform(
                                            row, fx,
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
                                    tutorialHighlighter: _mixHighlighter,

                                    mode: _resolvedMode,
                                  ),
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
                                  child: Halo(
                                    highlighter: _mixHighlighter,
                                    haloKey:
                                        const HaloKey('tutorial:piano_roll'),
                                    borderRadius: BorderRadius.circular(18),
                                    child: PianoRollEditor(
                                      clip: clip,
                                      availableInstruments:
                                          _activeInstrumentCatalog(),
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
                                        setState(
                                            () => _pianoRollFullscreen = v);
                                      },
                                      onClose: _closeMidiClipEditor,
                                      onCommit: _commitMidiClipFromPianoRoll,
                                      onPreviewNote: _previewPianoRollNote,
                                    ),
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

  void _showUploadComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Platform upload coming soon')),
    );
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
    final message = isVideo
        ? L10n.translate(context, 'Your video was exported successfully!')
        : L10n.translate(context, 'Your audio was exported successfully!');
    const pageBg = Color(0xFF0F172A);
    const topBarBg = Color(0xFF0E1420);
    const accent = Color(0xFF6C8CFF);

    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return Scaffold(
          backgroundColor: pageBg,
          appBar: AppBar(
            backgroundColor: topBarBg,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              L10n.translate(context, 'Export Successful'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  icon:
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(L10n.translate(context, 'Done')),
                ),
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
                      TweenAnimationBuilder<double>(
                        key: ValueKey(filePath),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutBack,
                        tween: Tween(begin: 0.6, end: 1.0),
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Icon(
                          Icons.task_alt_rounded,
                          color: Colors.greenAccent,
                          size: 96,
                          shadows: const [
                            Shadow(
                              blurRadius: 12,
                              color: Color(0x6634D399),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Text(
                      //   'Your ${isVideo ? 'video' : 'audio'} was exported successfully!',
                      //   style: Theme.of(context).textTheme.headlineSmall,
                      //   textAlign: TextAlign.center,
                      // ),
                      Text(
                        message,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      ExportSuccessPreviewPlayer(
                          filePath: filePath, isVideo: isVideo),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _shareFile(context),
                              icon:
                                  const Icon(Icons.ios_share_rounded, size: 20),
                              label: Text(L10n.translate(context, 'share')),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showUploadComingSoon(context),
                              icon: const Icon(Icons.cloud_upload_rounded,
                                  size: 20),
                              label: const Text('Upload to platform'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: Colors.white70,
                                side: const BorderSide(
                                  color: Color(0xFF4F5A73),
                                ),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
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
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
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

class _ClipStretchSnapshot {
  final double offsetSec;
  final double sourceTempoBpm;
  final bool stretchToProjectTempo;
  final bool tempoStretchPreservePitch;

  const _ClipStretchSnapshot({
    required this.offsetSec,
    required this.sourceTempoBpm,
    required this.stretchToProjectTempo,
    required this.tempoStretchPreservePitch,
  });

  bool approxEquals(_ClipStretchSnapshot other) {
    return (offsetSec - other.offsetSec).abs() < 0.00001 &&
        (sourceTempoBpm - other.sourceTempoBpm).abs() < 0.0001 &&
        stretchToProjectTempo == other.stretchToProjectTempo &&
        tempoStretchPreservePitch == other.tempoStretchPreservePitch;
  }
}

class StretchClipResizeAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;
  final _ClipStretchSnapshot oldSnapshot;
  final _ClipStretchSnapshot newSnapshot;
  final Future<void> Function(AudioTrack clip, _ClipStretchSnapshot snapshot)
      applySnapshot;

  StretchClipResizeAction({
    required this.tracks,
    required this.originalIndex,
    required this.oldSnapshot,
    required this.newSnapshot,
    required this.applySnapshot,
  });

  @override
  String get description => 'Stretch clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    await applySnapshot(clip, newSnapshot);
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;
    await applySnapshot(clip, oldSnapshot);
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
  final Future<void> Function(int row, List<AutomationPoint> points)? onApplied;

  SetAutomationPointsAction({
    required this.row,
    required List<AutomationPoint> oldPoints,
    required List<AutomationPoint> newPoints,
    required this.applyToState,
    this.onApplied,
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
    applyToState(row, newPoints);
    if (onApplied != null) {
      await onApplied!(row, newPoints);
    }
  }

  @override
  Future<void> undo() async {
    applyToState(row, oldPoints);
    if (onApplied != null) {
      await onApplied!(row, oldPoints);
    }
  }
}

class SetTargetAutomationPointsAction extends EditorUndoAction {
  final int row;
  final String targetId;
  final List<AutomationPoint> oldPoints;
  final List<AutomationPoint> newPoints;
  final void Function(int row, String targetId, List<AutomationPoint> points)
      applyToState;
  final Future<void> Function(
    int row,
    String targetId,
    List<AutomationPoint> points,
  )? onApplied;

  SetTargetAutomationPointsAction({
    required this.row,
    required this.targetId,
    required List<AutomationPoint> oldPoints,
    required List<AutomationPoint> newPoints,
    required this.applyToState,
    this.onApplied,
  })  : oldPoints = oldPoints
            .map((p) => AutomationPoint(x: p.x, volume: p.volume))
            .toList(growable: false),
        newPoints = newPoints
            .map((p) => AutomationPoint(x: p.x, volume: p.volume))
            .toList(growable: false);

  @override
  String get description => 'Edit automation lane';

  @override
  Future<void> redo() async {
    applyToState(row, targetId, newPoints);
    if (onApplied != null) {
      await onApplied!(row, targetId, newPoints);
    }
  }

  @override
  Future<void> undo() async {
    applyToState(row, targetId, oldPoints);
    if (onApplied != null) {
      await onApplied!(row, targetId, oldPoints);
    }
  }
}

class SetTargetAutomationClipsAction extends EditorUndoAction {
  final int row;
  final String targetId;
  final List<AutomationClipSnapshot> oldClips;
  final List<AutomationClipSnapshot> newClips;
  final void Function(
    int row,
    String targetId,
    List<AutomationClipSnapshot> clips,
  ) applyToState;
  final Future<void> Function(
    int row,
    String targetId,
    List<AutomationClipSnapshot> clips,
  )? onApplied;

  SetTargetAutomationClipsAction({
    required this.row,
    required this.targetId,
    required List<AutomationClipSnapshot> oldClips,
    required List<AutomationClipSnapshot> newClips,
    required this.applyToState,
    this.onApplied,
  })  : oldClips =
            oldClips.map((clip) => clip.copyWith()).toList(growable: false),
        newClips =
            newClips.map((clip) => clip.copyWith()).toList(growable: false);

  @override
  String get description => 'Edit automation clips';

  @override
  Future<void> redo() async {
    applyToState(row, targetId, newClips);
    if (onApplied != null) {
      await onApplied!(row, targetId, newClips);
    }
  }

  @override
  Future<void> undo() async {
    applyToState(row, targetId, oldClips);
    if (onApplied != null) {
      await onApplied!(row, targetId, oldClips);
    }
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
  const dbMin = -60.0;
  const dbMax = 6.0;
  const uiMax = 3.0;
  const uiUnity = 2.0;

  final clamped = sliderValue.clamp(0.0, uiMax).toDouble();
  final double db;

  if (clamped <= uiUnity) {
    final t = uiUnity <= 0.0 ? 0.0 : (clamped / uiUnity).clamp(0.0, 1.0);
    db = dbMin + ((0.0 - dbMin) * t);
  } else {
    final t = uiMax <= uiUnity
        ? 0.0
        : ((clamped - uiUnity) / (uiMax - uiUnity)).clamp(0.0, 1.0);
    db = 0.0 + ((dbMax - 0.0) * t);
  }

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
