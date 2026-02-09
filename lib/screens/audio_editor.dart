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
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:record/record.dart';

Completer<void> _cancelSignal = Completer();

const List<String> kMixroomBuiltInEffects = [
  "EQ 3-Band",
  "Compressor",
  "De-Esser",
  "Distortion",
  "Delay",
  "Reverb",
  "EQ Parametric",
];

class AudioEditorScreen extends StatefulWidget {
  final String mode;
  final Directory projectDir;

  const AudioEditorScreen({Key? key, required this.mode, required this.projectDir}) : super(key: key);
  @override
  State<AudioEditorScreen> createState() => _AudioEditorScreenState2();
}

class _AudioEditorScreenState2 extends State<AudioEditorScreen> with WidgetsBindingObserver {
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
  Stopwatch _transportStopwatch = Stopwatch();
  Ticker? _transportTicker;
  Duration _transportBase = Duration.zero;
  StateSetter? _transportStateSetter;

  // string of export filter to pass to effects screen
  String filterString = "";

  // PICK MEDIA
  bool _isLoadingAudio = false;
  bool _isLoadingNextScreen = false;

  StateSetter? _audioEditorStateSetter; // Store the StateSetter

  Duration _audioOnlyOverallDuration = Duration.zero;

  final int kWaveformSPS = 200; // samples per second for UI
  final int kMinSamples = 1024; // ensure enough resolution for short clips
  final int kMaxSamples = 200000; // safety cap for very long files

  // NOTE: these must have parity with the same variables in JuceEngine.h
  // think about moving these numbers out so they are adjustable from externally, one source of truth
  static const int kNumRows = 5;
  static const int kNumClips = 500; // pro-mode opportunity to restrict to arbitrary number for free ver

  int _selectedRow = 0; // one row always selected (by default row 0 (row 1 visually))
  int? _recordRow; // only one can be armed

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
  final List<double> _rowPan = List.filled(kNumRows, 0.5);
  final List<double> _rowGain = List.filled(kNumRows, 1.0);
  final List<List<AutomationPoint>> _rowVolumeAutomation = List.generate(
    kNumRows,
    (_) => [AutomationPoint(x: 0.0, volume: 0.75)],
  );
  final List<bool> _rowMuted = List<bool>.filled(kNumRows, false);
  final List<bool> _rowSoloed = List<bool>.filled(kNumRows, false);
  final List<bool> _rowExpanded = List<bool>.filled(kNumRows, false);

  // for copy/paste logic
  AudioTrack? _copiedAudioClip;
  Duration _copiedTrimStart = Duration.zero;
  Duration _copiedTrimEnd = Duration.zero;

  bool _loopEnabled = false;
  int _loopStartMs = 0;
  int _loopEndMs = 0;

  // master rack
  bool _showMasterRack = false;
  double _masterGain = 1.0;
  double _masterPan = 0.5;
  double? _masterGainDragStart;
  double? _masterPanDragStart;
  Map<int, List<bool>> _rowFxBypassSnapshot = {};
  List<bool> _masterFxBypassSnapshot = [];
  bool _globalFxBypass = false;

  final List<double> _rowGainSnapshot = List.filled(kNumRows, 1.0);
  final List<double> _rowPanSnapshot = List.filled(kNumRows, 0.5);
  final List<List<AutomationPoint>> _rowAutomationSnapshot = List.generate(kNumRows, (_) => []);

  // BPM/time
  int _tempo = 120;

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
  final TextEditingController _chatTextController = TextEditingController();
  late final InstrumentClassifier _classifier;
  final FocusNode _chatFocusNode = FocusNode();
  late final ChatPipeline _chatPipeline;
  late final ChatController _chatController;
  late void Function(int row) _refreshRowFx;
  bool _isThinking = false;
  late final MixChangeHighlighter _mixHighlighter = MixChangeHighlighter();
  bool _chatWarm = false;
  bool _isDialogOpen = false; // to fix weird issue on iPad iOS 26 where opening some dialogue would insta-close it
  bool _isMasterPopupOpen = false; // same thing as above

  late final MeterBus _meters;
  Timer? _meterTimer;
  bool _meterPollingBusy = false; // overlap guard
  static const int _meterStride = 5; // peakL, peakR, rmsL, rmsR, clip(0/1)
  Timer? _meterDecayTimer;
  bool _meterPolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // prewarmFFT(); // so that AI sync first run is not heavy (this was for video/audio sync)

    _transportTicker = Ticker((_) {
      if (!_isPlaying) return;

      _transportStateSetter?.call(() {
        _globalAudioClock = _transportBase + _transportStopwatch.elapsed;
      });

      _updateAudioAutomation(_globalAudioClock);

      // ===== END / LOOP LOGIC (same as before) =====
      final endPoint = Duration(
        milliseconds: math.max(_audioOnlyOverallDuration.inMilliseconds, msFor128Bars(_tempo.toDouble()).toInt()),
      );

      final reachedEnd = _globalAudioClock >= endPoint;
      final reachedLoopEnd = _loopEnabled && _globalAudioClock >= Duration(milliseconds: _loopEndMs);

      if (reachedLoopEnd) {
        if (_isRecording) {
          _transportTicker?.stop();
          _transportStopwatch.stop();
          _stopRecordingJuce(keepPlaying: false);
          return;
        }
        _restartAudio(_audioEditorStateSetter!);
        _togglePlayPauseAudio(_audioEditorStateSetter!);
        return;
      }

      if (reachedEnd) {
        if (_isRecording) return;
        _togglePlayPauseAudio(_audioEditorStateSetter!);
      }
    });

    // _loadAudioDevices();
    _loadInputDevicesFromJuce();

    _projectDir = widget.projectDir;
    // Load project file if it has content
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadProjectIfAny();
    });

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

    _chatPipeline = ChatPipeline(
      llm: CloudLlmService(
        apiKey:
            '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',
      ), // LocalLlmService(),
      projectBuilder: ProjectStateBuilder(classifier: _classifier),
      mixModel: LocalMixingModel(),
      onThinkingChanged: (isThinking) {
        setState(() {
          _isThinking = isThinking;
        });
      },
    );

    _chatController = InMemoryChatController();

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

    _meters = MeterBus(numRows: kNumRows);
    // _startMeterPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _isLoadingNextScreen = true);
      JuceAudioEngine.initialise(); // heavy blocking native call
      JuceAudioEngine.initialiseEventListeners();
      await Future.delayed(const Duration(milliseconds: 300)); // so that juce.init doesn't block UI load
      setState(() => _isLoadingNextScreen = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amplitudeSub?.cancel();
    _micRecorder.dispose();
    for (var track in _audioTracks) {
      track.audioStartTimer?.cancel();
    }
    _transportTicker?.dispose();

    _stopMeterPolling(decayToZero: false);
    _meterTimer?.cancel();
    _meterTimer = null;
    _meterDecayTimer?.cancel();
    _meters.dispose();
    // JuceAudioEngine.shutdown();
    // print("JUCE shutdown called");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (state == AppLifecycleState.resumed) {
        debugPrint("App Resumed on Android - Re-initializing.");
      } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
        _pauseAudio(_audioEditorStateSetter!);
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
      final json = await ProjectManager.readProjectJson(_projectDir);
      _projectName = (json["name"] ?? "Untitled Project") as String;

      // mark opened time
      json["lastOpenedAt"] = DateTime.now().millisecondsSinceEpoch;
      await ProjectManager.writeProjectJson(_projectDir, json);

      final tracks = (json["tracks"] as List?) ?? [];
      if (tracks.isEmpty) {
        setState(() {});
        return;
      }

      // Load all audio tracks first
      for (final t in tracks) {
        final map = (t as Map).cast<String, dynamic>();
        final fileName = map["fileName"] as String;
        final label = map["label"] as String;
        final rowIndex = (map["rowIndex"] as int?) ?? 0;

        final trimStartMs = (map["trimStartMs"] as int?) ?? 0;
        final trimEndMs = (map["trimEndMs"] as int?) ?? 0;
        final offsetSec = ((map["offset"] as num?) ?? 0).toDouble();
        final crossfade = ((map["crossfade"] as num?) ?? 0).toDouble();
        final gain = ((map["gain"] as num?) ?? 1.0).toDouble();

        final automationList = (map["automation"] as List?) ?? [];
        final automation =
            automationList.map((e) => AutomationPointJson.fromJson((e as Map).cast<String, dynamic>())).toList();

        final audioFile = File(p.join(ProjectManager.audioDir(_projectDir).path, fileName));
        if (!audioFile.existsSync()) {
          debugPrint("Missing audio file: ${audioFile.path}");
          continue;
        }

        await _addAudioTrackFromProjectFile(
          projectAudioFile: audioFile,
          label: label,
          row: rowIndex,
          timeMs: offsetSec * 1000.0,
          trimStartRequested: Duration(milliseconds: trimStartMs),
          trimEndRequested: Duration(milliseconds: trimEndMs),
          gain: gain,
          crossfade: crossfade,
          automation: automation.isNotEmpty ? automation : null,
        );

        // After _addAudioTrackFromFile, the newest track is last
        // I think this code is deprecated
        final tr = _audioTracks.last;
        tr.crossfade = crossfade;
        tr.gain = gain;
        tr.volumeAutomation = automation.isNotEmpty
            ? automation
            : [AutomationPoint(x: 0.0, volume: 1.0), AutomationPoint(x: 1.0, volume: 1.0)];
      }

      final rowStatesList = (json["rowStates"] as List?) ?? [];

      for (final rs in rowStatesList) {
        final snap = RowStateSnapshot.fromJson((rs as Map).cast<String, dynamic>());
        final r = snap.row;

        // Safety check
        if (r < 0 || r >= kNumRows) continue;

        // Restore pan & gain
        _rowPan[r] = snap.pan;
        _rowGain[r] = snap.gain;

        // Restore automation (deep copy!)
        _rowVolumeAutomation[r] = snap.volumeAutomation.map((p) => p.copy()).toList();

        await JuceAudioEngine.setRowGain(r, snap.gain);
        await JuceAudioEngine.setRowPan(r, snap.pan);
        await JuceAudioEngine.setTrackAutomationPoints(r, (_rowVolumeAutomation[r]).map((p) => p.toMap()).toList());
      }

      // Restore FX snapshots after tracks exist
      final rowFxList = (json["rowEffects"] as List?) ?? [];
      for (final rf in rowFxList) {
        final snap = RowEffectsSnapshotJson.fromJson((rf as Map).cast<String, dynamic>());
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
      setState(() {});
    } catch (e) {
      debugPrint("Project load failed: $e");
    }
  }

  Future<void> _saveProject() async {
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
          "trimStartMs": tr.trimStart.inMilliseconds,
          "trimEndMs": tr.trimEnd.inMilliseconds,
          "offset": tr.offset,
          "crossfade": tr.crossfade,
          "gain": tr.gain,
          "rowIndex": tr.rowIndex,
          "automation": tr.volumeAutomation.map((p) => p.toJson()).toList(),
        });
      }

      // Garbage collect unreferenced audio files
      final referenced = _audioTracks.map((t) => p.basename(t.file.path)).whereType<String>().toSet();
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
      final usedRows = List<int>.generate(kNumRows, (i) => i);

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
          volumeAutomation: _rowVolumeAutomation[r].map((p) => p.copy()).toList(),
        );
        rowStates.add(snap.toJson());
      }

      final masterSnap = await captureMasterSnapshot();

      // Load existing json if present, preserve createdAt
      final existing = await ProjectManager.readProjectJson(_projectDir);
      final createdAt = existing["createdAt"] ?? DateTime.now().millisecondsSinceEpoch;

      final now = DateTime.now().millisecondsSinceEpoch;
      final json = <String, dynamic>{
        "version": 1,
        "name": _projectName,
        "createdAt": createdAt,
        "lastOpenedAt": now,
        "tracks": tracksJson,
        "rowStates": rowStates,
        "rowEffects": rowFx,
        "master": {"gain": _masterGain, "pan": _masterPan, "effects": masterSnap.toJson()},
      };

      await ProjectManager.writeProjectJson(_projectDir, json);

      _everSaved = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Project saved")));
      }
    } catch (e) {
      debugPrint("Project save failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Save failed: $e")));
      }
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
    final millisecondsFirstTwo = firstTwoMsDigits(duration.inMilliseconds.remainder(1000));

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
        final rowCount = kNumRows; // or: _meters.rows.length

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
  Duration _calculateEffectiveAudioPositionForTrack(AudioTrack track, Duration videoPos) {
    final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
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
    await _togglePlayPauseAudio(_audioEditorStateSetter!);
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

  // TODO: maybe fixed already but slight chance that JuceAudioEngine.play and the _globalAudioClock could have a slight mismatch (sometimes)
  // think for play -> pause -> play -> pause... chance they could desync until a seek event matches them
  // in cases where mismatch, the JUCE is always early and the UI lags. so try to do UI calculations first and then play JUCE
  // usually seems to happen after opening effects maybe? i don't know
  Future<void> _resumeAudio(StateSetter setLocalState) async {
    JuceAudioEngine.play();
    JuceAudioEngine.setAutomationTransport(_globalAudioClock.inMilliseconds.toDouble() / 1000.0);
    JuceAudioEngine.setMetronomeTransportMs(_globalAudioClock.inMilliseconds.toDouble());
    // Resume playback: do not reset the global clock.
    // For each track, if its offset has been reached, start (or resume) playback.
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
      if (_globalAudioClock >= offsetDuration) {
        final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _globalAudioClock);
        // await track.player.play(DeviceFileSource(track.file.path));
        // await track.player.seek(effectivePos);
        JuceAudioEngine.bypassTrack(i, false);
        JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
        track.audioStarted = true;
        track.currentPosition = effectivePos;
      } else {
        JuceAudioEngine.bypassTrack(i, true);
        track.audioStarted = false;
      }
    }
    // Restart the automation timer
    // _audioAutomationTimer?.cancel();
    /*
    _audioAutomationTimer = Timer.periodic(const Duration(milliseconds: 5), (timer) async {
      setLocalState(() {
        _globalAudioClock += const Duration(milliseconds: 5);
      });

      // end point is at least 128 bars
      // overallDuration will not be changed since it must equal final point of last audio clip (for export purposes)
      Duration endPoint = Duration(
          milliseconds: math.max(_audioOnlyOverallDuration.inMilliseconds, msFor128Bars(_tempo.toDouble()).toInt()));
      final reachedEnd = _globalAudioClock >= endPoint;
      final reachedLoopEnd = _loopEnabled && _globalAudioClock >= Duration(milliseconds: _loopEndMs);

      if (reachedLoopEnd) {
        if (_isRecording) {
          // Stop recording & stop playback
          _audioAutomationTimer?.cancel(); // this should work (to prevent duplicate call of _stopRecording)
          await _stopRecordingJuce(keepPlaying: false);
          return; // return because we want user's recording to keep going even if reach end of timeline
        }
        await _restartAudio(setLocalState);
        // setLocalState(() {
        //   _isPlaying = true;
        // });
        await _togglePlayPauseAudio(setLocalState);
        return;
      } else if (reachedEnd) {
        if (_isRecording) {
          // Stop recording & stop playback
          // await _stopRecording(keepPlaying: false);
          return; // return because we want user's recording to keep going even if reach end of timeline
        }
        // await _restartAudio(setLocalState);
        // setLocalState(() {
        //   _isPlaying = true;
        // });
        await _togglePlayPauseAudio(setLocalState);
        return;
      }
      _updateAudioAutomation(_globalAudioClock);
    });
    */
    _transportStateSetter = setLocalState;
    _transportBase = _globalAudioClock;

    _transportStopwatch
      ..reset()
      ..start();

    _transportTicker?.start();

    _startMeterPolling();
  }

  Future<void> _pauseAudio(StateSetter setLocalState) async {
    // On pause, cancel the timer, pause each track, and importantly, reset audioStarted.
    // _audioAutomationTimer?.cancel();
    _transportTicker?.stop();
    _transportStopwatch.stop();

    for (var track in _audioTracks) {
      // await track.player.pause();
      track.audioStarted = false; // Reset flag on pause so that resume triggers play.
    }
    JuceAudioEngine.pause();

    _stopMeterPolling();
  }

  Future<void> _restartAudio(StateSetter setLocalState) async {
    // Pause all tracks and seek them to their trimStart.
    // _audioAutomationTimer?.cancel();
    _transportTicker?.stop();
    _transportStopwatch.reset();

    Duration newStartPoint = Duration.zero;

    // Case of loop is enabled
    if (_loopEnabled) {
      newStartPoint = Duration(milliseconds: _loopStartMs);
    }

    for (int i = 0; i < _audioTracks.length; i++) {
      // await track.player.pause();
      // await track.player.seek(track.trimStart);
      final track = _audioTracks[i];
      track.audioStarted = false;
      track.audioStartTimer?.cancel();
      final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newStartPoint);
      JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
      track.currentPosition = newStartPoint;
    }
    JuceAudioEngine.pause();

    // Reset the global audio clock.
    setState(() {
      _globalAudioClock = newStartPoint;
      _isPlaying = false;
    });

    _stopMeterPolling();
  }

  // basically calling this every 'frame' to see if every audio clip should start, remain playing, or be paused
  // pretty unscaleable/overkill, so move this to JUCE
  void _updateAudioAutomation(Duration globalClock) {
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      // Convert track.offset (in seconds) to a Duration.
      final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
      Duration effectiveAudioPos;
      if (globalClock < offsetDuration) {
        // Global clock hasn’t reached the track's offset: use trimStart.
        effectiveAudioPos = track.trimStart;
      } else {
        // Once past offset, effective position is trimStart + (globalClock - offset).
        effectiveAudioPos = track.trimStart + (globalClock - offsetDuration);
        if (effectiveAudioPos > track.trimEnd) {
          effectiveAudioPos = track.trimEnd;
          // hack for pausing if trimEnd is reached
          JuceAudioEngine.bypassTrack(i, true);
          track.audioStarted = false;
          continue;
        }
      }

      // Start the track if the offset has been reached and it hasn't started yet.
      if (globalClock >= offsetDuration && !track.audioStarted) {
        // track.player.seek(effectiveAudioPos);
        JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6);
        // track.player.play(DeviceFileSource(track.file.path));
        JuceAudioEngine.bypassTrack(i, false); // TODO: verify that this resumes the track playback
        track.audioStarted = true;
      }
      track.currentPosition = effectiveAudioPos;
    }
  }

  // Pause helper
  Future<void> _pausePlayback() async {
    // Pause all audio tracks at precise position
    for (var track in _audioTracks) {
      track.audioStartTimer?.cancel(); // NEED THIS IN CASE THERE WAS A TIMER STARTED
    }
    await JuceAudioEngine.pause();
  }

  Future<String> _exportAudioOnly(ValueChanged<double> onProgress) async {
    if (_audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.translate(context, 'No audio tracks selected'))), // TODO: FIX THIS WORDING
      );
      return "";
    }

    onProgress(0.0);

    final overallDuration = _audioTracks.map((track) {
      final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
      final trackDuration = track.trimEnd - track.trimStart;
      return offsetDuration + trackDuration;
    }).reduce((a, b) => a > b ? a : b);

    // Build input arguments
    List<String> inputArgs = [];
    // for (final track in _audioTracks) {
    //   inputArgs.add('-i "${track.file.path}"');
    // }

    for (int i = 0; i < _audioTracks.length; i++) {
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/juce_track${i}_export.wav';
      final outDir = await JuceAudioEngine.exportTrack(i, outPath);
      print("_exportAudioOnly: track ${i} exported at ${outDir}");
      inputArgs.add('-i "${outDir}"');
    }

    // Build filter complex
    List<String> filterLines = [];
    List<String> trackLabels = [];

    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      final offsetMs = (track.offset * 1000).round();
      final startSec = track.trimStart.inMilliseconds / 1000.0;
      final endSec = track.trimEnd.inMilliseconds / 1000.0;
      final String label = 'a${i}';

      String volumeFilter;
      if (track.volumeAutomation.isNotEmpty) {
        final String volumeAutomationExpression = generateVolumeAutomationFilter(track, offsetMs, _universalCrossfade);
        volumeFilter = 'volume=eval=frame:volume="${volumeAutomationExpression}"'; //*${track.gain}"';
      } else {
        volumeFilter = 'volume=${min(1.0, _universalCrossfade * 2).toStringAsFixed(2)}'; //*${track.gain}';
      }

      filterLines.add(
        '[${i}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
        'adelay=${offsetMs}|${offsetMs},asetpts=PTS-STARTPTS,'
        '$volumeFilter[$label];',
      );

      trackLabels.add('[$label]');
      onProgress(((i + 1).toDouble() / _audioTracks.length) * 0.5);
    }
    onProgress(0.6);

    // Mix all tracks (matches video export's amix approach)
    final String amixInputs =
        trackLabels.join('') + 'amix=inputs=${_audioTracks.length}:duration=longest:normalize=0[aout]';
    filterLines.add(amixInputs);

    final String filterComplex = filterLines.join('');

    setState(() {
      filterString = filterComplex;
    });

    // Build FFmpeg command (matches video export structure)
    List<String> ffmpegCmd = [
      ...inputArgs,
      '-filter_complex',
      filterComplex,
      '-map',
      '[aout]',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '192k',
      '-ar',
      '44100',
      '-loglevel',
      'verbose',
      '-y',
    ];

    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.mp3';
    ffmpegCmd.add('"$outPath"');

    // print("FFmpeg command: ${ffmpegCmd.join(' ')}");

    try {
      final session = await FFmpegKit.execute(ffmpegCmd.join(' '));
      onProgress(1.0);
      final returnCode = await session.getReturnCode();

      final allLogs = await session.getAllLogs() ?? [];
      final errorLogs = await session.getLogs() ?? [];

      String getLogMessages(List<Log> logs) {
        return logs.map((log) => log.getMessage() ?? "null").join('\n');
      }

      final lastErrorCount = min(10, errorLogs.length);
      final lastErrors = errorLogs.sublist(max(0, errorLogs.length - lastErrorCount));
      final lastErrorMessages = getLogMessages(lastErrors);

      print("═════════ LAST ERRORS ═════════");
      print(lastErrorMessages);

      if (ReturnCode.isSuccess(returnCode)) {
        final outFile = File(outPath);
        int retries = 0;
        while (!await outFile.exists() && retries < 20) {
          await Future.delayed(const Duration(milliseconds: 250));
          retries++;
        }

        if (!await outFile.exists() || (await outFile.length()) < 1000) {
          print("❌ ERROR: Output file is missing or too small!");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.translate(context, 'Export failed: Output file missing or too small.'))),
          );
          return "";
        }

        print("✅ File found: $outPath");

        return outPath;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${L10n.translate(context, "Export failed")}:\n${lastErrorMessages.isNotEmpty ? lastErrorMessages : "${L10n.translate(context, 'Unknown error')} (RC: $returnCode)"}',
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }
    } catch (e) {
      print("Full export error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.translate(context, "Export error")}: ${e.toString().split('\n').first}'),
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

  Future<int> findBestSyncOffset(String videoAudioPath, String trackAudioPath) async {
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

  Future<void> applyBestSyncOffset(AudioTrack track, String videoAudioPath) async {
    int syncOffset = await findBestSyncOffset(videoAudioPath, track.file.path);
    final int audioLengthMs = track.audioDuration.inMilliseconds;
    final int offsetLimit = 180000; // 180 seconds

    if (syncOffset >= 0 && syncOffset > offsetLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.translate(context, 'AI Sync failed: Computed offset exceeds audio length.'))),
      );
      return;
    } else if (syncOffset < 0 && syncOffset.abs() > audioLengthMs) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.translate(context, 'AI Sync failed: Computed trim exceeds audio length.'))),
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
        track.trimStart = Duration(milliseconds: syncOffset.abs()); //trimAdjustment.toInt());
        track.offset = 0.0;
      }
    });

    // Refresh UI
    setState(() {});
    print("✅ AI Sync applied. Adjusted Offset: ${track.offset}, Trim Start: ${track.trimStart}");
  }

  // THINGS FOR AI SYNC END-----

  List<double> normalizeWaveform(List<double> data) {
    if (data.isEmpty) return [];

    final maxAmplitude = data.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

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
    // 1) Require an armed row (UNCHANGED)
    if (_recordRow == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a track to record on first.')));
      return;
    }

    if (_loopEnabled) {
      await _restartAudio(_audioEditorStateSetter!);
    }

    // 2) Determine where in the project we start recording (UNCHANGED)
    _recordingStartMs = _globalAudioClock.inMilliseconds.toDouble();

    // 3) If not already playing, start playback (UNCHANGED)
    if (!_isPlaying) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!);
    }

    // 4) Prepare file path (CHANGE → WAV)
    final audioDir = ProjectManager.audioDir(_projectDir);
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    final filePath = p.join(audioDir.path, 'mixroom_rec_${DateTime.now().millisecondsSinceEpoch}.wav');

    // 5) Start JUCE recording (NEW)
    final ok = await JuceAudioEngine.startRecording(
      filePath,
      _selectedChannelStart,
      2, //_selectedChannelCount, TODO: (TEMP TO ALLOW NANOCORTEX RECORDING) (do the 1+2, 3+4 selection stuff)
    );

    print("printing $_selectedChannelStart $_selectedChannelCount");

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start recording')));
      return;
    }

    // 6) UI state (UNCHANGED)
    setState(() {
      _recordingFilePath = filePath;
      _isRecording = true;
    });

    _recordingPeaks.clear();

    _recordingPeakTimer?.cancel();
    _recordingPeakTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
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
      ).showSnackBar(const SnackBar(content: Text('Recording failed or no data captured.')));
      return;
    }

    final int row = _recordRow ?? 0;
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add recorded track.')));
    }

    // 3) Optionally stop playback (UNCHANGED)
    if (!keepPlaying && _isPlaying) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Max number of audio clips reached (500). Unable to add more clips.")));
      return;
    }

    _pausePlayback();
    setState(() {
      _isLoadingAudio = true;
    });

    final newFile = fromFile; //File(result.files.single.path!);

    final audioDir = ProjectManager.audioDir(_projectDir);
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    if (!newFile.existsSync()) return;

    final baseName = p.basename(newFile.path);
    final baseNameNoExt = baseName.contains('.') ? baseName.substring(0, baseName.lastIndexOf('.')) : baseName;

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

    await JuceAudioEngine.loadClip(_audioTracks.length, row, newFile_48.path);

    // final dur = await JuceAudioEngine.getTrackDuration(0);
    final durSeconds = await JuceAudioEngine.getTrackDuration(_audioTracks.length);
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
      rowIndex: row,
      label: baseNameNoExt,
    );

    _startWaveformExtraction(newTrack);

    setState(() {
      newTrack.offset = timeMs / 1000.0;
      newTrack.trimStart = trimStartRequested ?? Duration.zero;
      newTrack.trimEnd = trimEndRequested ?? dur;
      _audioTracks.add(newTrack);
      _isLoadingAudio = false;
    });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Max number of audio clips reached (500). Unable to add more clips.")));
      return;
    }

    await JuceAudioEngine.loadClip(_audioTracks.length, row, clip.file.path);
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
      rowIndex: row,
      label: clip.label,
    );

    newTrack.normWaveformData = clip.normWaveformData;

    setState(() {
      newTrack.offset = timeMs / 1000.0;
      newTrack.trimStart = trimStartRequested ?? Duration.zero;
      newTrack.trimEnd = trimEndRequested ?? dur;
      _audioTracks.add(newTrack);
    });
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
    double? crossfade,
    List<AutomationPoint>? automation,
  }) async {
    // no FFmpeg, no temp renaming
    await JuceAudioEngine.loadClip(_audioTracks.length, row, projectAudioFile.path);

    final durSeconds = await JuceAudioEngine.getTrackDuration(_audioTracks.length);
    final dur = Duration(milliseconds: (durSeconds * 1000).round());

    final newTrack = await AudioTrack.create(
      file: projectAudioFile, // points directly to project/audio
      originalFile: projectAudioFile, // unused
      audioDuration: dur,
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0,
      crossfade: 1.0,
      rowIndex: row,
      label: label,
    );

    newTrack.offset = timeMs / 1000.0;
    newTrack.trimStart = trimStartRequested ?? Duration.zero;
    newTrack.trimEnd = trimEndRequested ?? dur;

    if (gain != null) newTrack.gain = gain;
    if (crossfade != null) newTrack.crossfade = crossfade;
    if (automation != null && automation.isNotEmpty) {
      newTrack.volumeAutomation = automation;
    }

    _startWaveformExtraction(newTrack);

    setState(() {
      _audioTracks.add(newTrack);
    });

    _updateOverallDurationIfNeeded();
  }

  void _startWaveformExtraction(AudioTrack c) async {
    if (c.didExtractWaveform) return;
    c.didExtractWaveform = true;

    try {
      final inputPath = c.file.path;

      // ---- Timeline truth ----
      final durSec = (c.audioDuration.inMilliseconds / 1000.0).clamp(0.001, double.infinity);

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
    // TEMP: for CES (no export)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export disabled for CES Demo.")));
    return;

    setState(() {
      _isLoadingNextScreen = true;
    });
    if (_isPlaying) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!);
    }
    final exportPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExportProgressPage(exportFn: _exportAudioOnly, videoFile: ""),
      ),
    );
    if (!mounted) return;

    setState(() {
      _isLoadingNextScreen = false;
    });

    final params = SaveFileDialogParams(sourceFilePath: exportPath, fileName: 'export_file.${'mp3'}');
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
            filePath: exportPath!, // savedPath,
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
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const beginScale = 0.96;
              const endScale = 1.0;
              const curve = Curves.easeOutCubic;
              final tween = Tween<double>(begin: beginScale, end: endScale).chain(CurveTween(curve: curve));
              final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
              return FadeTransition(
                opacity: animation.drive(fadeTween),
                child: ScaleTransition(scale: animation.drive(tween), child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
          (route) => false,
        );
      }
    } else {
      final fail_str = L10n.translate(context, 'Export canceled or failed.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fail_str)));
    }
  }

  void _showAddMediaOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(L10n.translate(context, 'Add Audio Track')),
                onTap: () async {
                  Navigator.pop(context);

                  if (widget.mode == "Basic" && _audioTracks.length == 3) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text(L10n.translate(context, 'Pro Mode Feature'), style: TextStyle(color: Colors.white)),
                        content: Text(
                          L10n.translate(context, 'Upgrade to Pro mode to import more than 3 audio tracks.'),
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              "OK",
                              // style: TextStyle(color: Color(0xFF2F44FF)),
                            ),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  // _addAudioTrack();
                  _pausePlayback();
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
                  if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
                    // _addAudioTrackFromFile(File(result.files.single.path!), _selectedRow, 0.0);

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
                        file: File(result.files.single.path!),
                        row: _selectedRow,
                        timeMs: _globalAudioClock.inMilliseconds.toDouble(), //0.0 sets it to start
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _snapshotFxBypassState() async {
    _rowFxBypassSnapshot.clear();
    _masterFxBypassSnapshot.clear();

    // --- Rows ---
    for (int row = 0; row < kNumRows; row++) {
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
      _rowAutomationSnapshot[row] = _rowVolumeAutomation[row].map((p) => p.copy()).toList();
    }

    // --- Master FX ---
    final masterFx = await JuceAudioEngine.getMasterEffects();
    for (int i = 0; i < masterFx.length; i++) {
      _masterFxBypassSnapshot.add(await JuceAudioEngine.getMasterEffectBypassState(i));
    }
  }

  Future<void> _forceBypassAllFx(bool bypass) async {
    for (int row = 0; row < kNumRows; row++) {
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
        await JuceAudioEngine.setTrackAutomationPoints(row, _toMaps([AutomationPoint(x: 0.0, volume: 0.75)]));
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
    for (int row = 0; row < kNumRows; row++) {
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
      await JuceAudioEngine.setTrackAutomationPoints(row, _toMaps(_rowAutomationSnapshot[row]));
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
                    constraints: BoxConstraints(minWidth: 280, maxWidth: 0.9 * deviceWidth),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: _globalFxBypass,
                                    activeColor: Colors.orangeAccent,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        Container(height: 1, color: Colors.white.withOpacity(0.08)),

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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        children: [
          PrettyGainSlider(
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
              _masterGainDragStart = null;
            },
          ),
          const SizedBox(height: 16),
          PrettyStereoSlider(
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
              _masterPanDragStart = null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMasterEffectsPage() {
    return MasterEffectsPanel(
      key: ValueKey("master_effects_panel"),
      mode: widget.mode,
      getMasterEffects: () => JuceAudioEngine.getMasterEffects(),
      getMasterEffectBypassState: (i) => JuceAudioEngine.getMasterEffectBypassState(i),
      bypassMasterEffect: (i, bp) async {
        await _undoManager.execute(
          BypassMasterEffectAction(effectIndex: i, oldState: !bp, newState: bp, onChange: () => setState(() {})),
        );
      }, //JuceAudioEngine.bypassMasterEffect(i, bp),
      // reorderMasterEffects: (from, to) => JuceAudioEngine.reorderMasterEffects(from, to),
      // removeMasterEffect: (i) => JuceAudioEngine.removeMasterEffect(i),
      // insertMasterEffect: (path) => JuceAudioEngine.insertMasterEffect(path),
      insertMasterEffect: (pathOrName) async {
        await _undoManager.execute(InsertMasterEffectAction(pathOrName: pathOrName, onChange: () => setState(() {})));
      },

      // need name of effects so undo action can add it back later
      removeMasterEffect: (effectIndex, name, applyingPreset) async {
        if (applyingPreset) {
          await JuceAudioEngine.removeMasterEffect(effectIndex);
          return;
        }
        await _undoManager.execute(
          RemoveMasterEffectAction(effectIndex: effectIndex, pathOrName: name, onChange: () => setState(() {})),
        );
      },

      reorderMasterEffects: (from, to) async {
        await _undoManager.execute(ReorderMasterEffectAction(from: from, to: to, onChange: () => setState(() {})));
      },
      scanPlugins: () => JuceAudioEngine.scanPlugins(),
      getMasterPluginParameters: (i) => JuceAudioEngine.getMasterPluginParameters(i),
      setMasterEffectParam: (i, id, v) => JuceAudioEngine.setMasterEffect(i, id, v),
      onMasterPluginParamCommit: (idx, paramId, oldValue, newValue) async {
        await _undoManager.execute(
          SetMasterEffectParamAction(
            effectIndex: idx,
            paramId: paramId,
            oldValue: oldValue,
            newValue: newValue,
            onChange: () => setState(() {}),
          ),
        );
      },
      onMasterPresetCommit: (before, after) async {
        await _undoManager.execute(
          MasterPresetChangeAction(before: before, after: after, onChange: () => setState(() {})),
        );
      },
      projectBpm: _tempo.toDouble(),
      meters: _meters,
      getMasterCompressorMeter: (fx) => JuceAudioEngine.getMasterCompressorMeter(fx),
    );
  }

  Widget _buildTopBar() {
    final t = _globalAudioClock;
    final hhmmss = _formatDuration(t);
    final total = _formatDuration(_audioOnlyOverallDuration);

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
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              // onPressed: () => Navigator.of(context).maybePop(),
              onPressed: () async {
                if (_isDialogOpen) return;
                _isDialogOpen = true;

                // If playing, pause first
                if (_isPlaying) {
                  _isPlaying = false;
                  await _pauseAudio(_audioEditorStateSetter ?? (fn) {});
                }

                await _saveProject();

                if (mounted) {
                  // Dispose resources before navigating
                  _pausePlayback();
                  for (var track in _audioTracks) {
                    track.audioStartTimer?.cancel();
                  }
                  JuceAudioEngine.shutdown();
                  Navigator.of(context).pop();
                }
              },
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
                current: _formatDuration(_globalAudioClock),
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
                    icon: const Icon(Icons.settings_input_composite, color: Colors.white, size: 20),
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
                    child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 22),
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
    _isDialogOpen = true;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, localSetState) {
            return Dialog(
              backgroundColor: const Color(0xFF1A1F2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(20),
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Project Settings",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    _buildInputSelector(),
                    if (_numInputChannels > 0) ...[
                      const SizedBox(height: 20),
                      DropdownButtonFormField<int>(
                        key: ValueKey(_numInputChannels),
                        value: _selectedChannelStart,
                        decoration: const InputDecoration(labelText: 'Input Channel', border: OutlineInputBorder()),
                        items: List.generate(
                          _numInputChannels,
                          (i) => DropdownMenuItem(value: i, child: Text('Channel ${i + 1}')),
                        ),
                        onChanged: _isRecording
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() {
                                  _selectedChannelStart = v;
                                  _selectedChannelCount = 1;
                                });
                              },
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!Platform.isIOS) ...[_buildOutputSelector(), const SizedBox(height: 20)],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTempoSelector(),
                        const SizedBox(height: 20),
                        _buildMetronomeToggle(localSetState),
                        const SizedBox(height: 20),
                        _buildMetronomeVolumeSlider(localSetState),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Close"),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    _isDialogOpen = false;
  }

  Widget _buildMetronomeToggle(void Function(void Function()) localSetState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Metronome", style: TextStyle(color: Color.fromARGB(210, 255, 255, 255), fontSize: 15)),
        Switch(
          value: _metronomeEnabled,
          activeColor: Colors.blueAccent,
          onChanged: (v) {
            localSetState(() => _metronomeEnabled = v);
            JuceAudioEngine.setMetronomeEnabled(v);
          },
        ),
      ],
    );
  }

  Widget _buildMetronomeVolumeSlider(void Function(void Function()) localSetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Metronome Volume", style: TextStyle(color: Color.fromARGB(210, 255, 255, 255), fontSize: 15)),
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
            localSetState(() => _metronomeVolume = v);
            JuceAudioEngine.setMetronomeVolume(v);
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
    setState(() => _loadingDevices = true);

    final devices = await JuceAudioEngine.getInputDevices();
    final current = await JuceAudioEngine.getCurrentDeviceName();
    final channels = await JuceAudioEngine.getNumInputChannels();
    setState(() {
      _inputDevices = devices;
      _selectedDevice = devices.contains(current) ? current : (devices.isNotEmpty ? devices.first : null);
      _numInputChannels = channels;

      _selectedChannelStart = _selectedChannelStart.clamp(0, (_numInputChannels - 1).clamp(0, 999));
      _selectedChannelCount = _selectedChannelCount.clamp(1, (_numInputChannels - _selectedChannelStart).clamp(1, 999));

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
        newSelectedInput = inputs.firstWhere((d) => d.deviceId == _selectedInput!.deviceId);
      } catch (_) {
        newSelectedInput = inputs.isNotEmpty ? inputs.first : null;
      }
    } else {
      newSelectedInput = inputs.isNotEmpty ? inputs.first : null;
    }

    // --- Preserve output selection if possible ---
    if (_selectedOutput != null) {
      try {
        newSelectedOutput = outputs.firstWhere((d) => d.deviceId == _selectedOutput!.deviceId);
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
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        suffixIcon: IconButton(
          tooltip: "Refresh audio devices",
          icon: const Icon(Icons.refresh, color: Colors.white70),
          onPressed: () async {
            _loadInputDevicesFromJuce();
            print("audio devices reloaded from JUCE");
          },
        ),
      ),
      items: _inputDevices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
      onChanged: (name) async {
        if (name == null) return;

        final ok = await JuceAudioEngine.selectInputDevice(name);
        if (!ok) return;

        final channels = await JuceAudioEngine.getNumInputChannels();

        setState(() {
          _selectedDevice = name;
          _numInputChannels = channels;

          _selectedChannelStart = _selectedChannelStart.clamp(0, (_numInputChannels - 1).clamp(0, 999));
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
      return const Text("No selectable output devices", style: TextStyle(color: Colors.white54));
    }

    return DropdownButtonFormField<MediaDeviceInfo>(
      dropdownColor: const Color(0xFF2A2F3D),
      initialValue: _selectedOutput,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: "Output Device",
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
      ),
      items: _outputs.map((d) {
        return DropdownMenuItem(
          value: d,
          child: Text(d.label.isNotEmpty ? d.label : d.deviceId, style: const TextStyle(color: Colors.white)),
        );
      }).toList(),
      onChanged: (d) {
        if (d == null) return;
        setState(() => _selectedOutput = d);
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
            scrollController: FixedExtentScrollController(initialItem: _tempo - 40),
            itemExtent: 36,
            magnification: 1.15,
            squeeze: 1.2,
            useMagnifier: true,
            backgroundColor: Colors.transparent,
            onSelectedItemChanged: (index) {
              final bpm = index + 40;
              setState(() => _tempo = bpm);
              // Optional: send to engine
              JuceAudioEngine.setMetronomeBpm(bpm.toDouble());
            },
            children: [
              for (int bpm = 40; bpm <= 240; bpm++)
                Center(
                  child: Text("$bpm", style: const TextStyle(color: Colors.white, fontSize: 20)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tempoTimePill({required int tempo, required String current, required String total}) {
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
                  padding: const EdgeInsets.only(left: 4), // keep visually centered
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$tempo', style: bigNum, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text('TEMPO', style: smallLabel, textAlign: TextAlign.center),
                    ],
                  ),
                ),

                const SizedBox(width: gap),
                const _PillDivider(height: 30),
                const SizedBox(width: gap),

                // ---- Right column: Time (Expanded, slight right padding to prevent clipping) ----
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 0), // ✅ fixes shadow/clipping on last digit
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
    return LayoutBuilder(
      builder: (context, c) {
        final double pillWidth = c.maxWidth;

        return _Glass(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          opacity: 0.10,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, maxHeight: 54),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    current,
                    style: const TextStyle(
                      fontSize: 22, // ← “ideal” size
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    total,
                    style: TextStyle(
                      fontSize: 12, // ← “ideal” size
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

          _mixHighlighter.trigger([HaloKey('row:$row'), HaloKey('row:$row:mixer')]);

          final summary = '• Adjusted Gain from ${_gainToDb(oldGain)} to ${_gainToDb(newGain)} on Track ${row + 1} •';
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

          final summary = '• Adjusted pan from ${panToText(oldPan01)} to ${panToText(newPan01)} on Track ${row + 1} •';
          _chatController.insertMessage(ActionSummaryMessage(text: summary));
          continue;

        case 'delete_effect':
          {
            final row = (a.data['row'] as int);
            final contains = (a.data['effect_name_contains'] as String).toLowerCase();

            final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
            final idx = effects.indexWhere((e) => e.toLowerCase().contains(contains));
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
              ActionSummaryMessage(text: '• Removed ${effects[idx]} from Track ${row + 1} •'),
            );
            continue;
          }

        case 'ensure_effect':
          final row = (a.data['row'] as int);
          final contains = (a.data['effect_name_contains'] as String).toLowerCase();

          final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
          final already = effects.indexWhere((e) => e.toLowerCase().contains(contains));
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

        case 'adjust_effect_param_by_name':
          {
            final row = (a.data['row'] as int);
            final effectContains = (a.data['effect_name_contains'] as String).toLowerCase();

            final skipIfMissing = (a.data['skip_if_missing_effect'] as bool?) ?? true;

            final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
            final fxIndex = effects.indexWhere((e) => e.toLowerCase().contains(effectContains));
            if (fxIndex == -1) {
              if (skipIfMissing) continue;
              // else: you could ensure_effect first; but typically model emits ensure_effect already
              continue;
            }

            final paramsRaw = await JuceAudioEngine.getTrackPluginParameters(row, fxIndex);
            final params = paramsRaw.map((e) => Map<String, dynamic>.from(e)).toList();

            final exactParamName = a.data['param_name'] as String?;
            final containsAny = (a.data['param_name_contains_any'] as List?)?.map((e) => e.toString()).toList();

            final picked = _pickParam(params, exactName: exactParamName, containsAny: containsAny);
            if (picked == null) continue;

            final paramId = (picked['id'] as String?) ?? (picked['name'] as String); // robust
            final paramName = (picked['name'] as String?) ?? paramId;
            final current = (picked['value'] as num).toDouble();

            final double? pMin = picked['min'] is num ? (picked['min'] as num).toDouble() : null;
            final double? pMax = picked['max'] is num ? (picked['max'] as num).toDouble() : null;

            final clamp01 = (a.data['clamp_0_1'] as bool?) ?? false;

            final mode = (a.data['mode'] as String?) ?? 'delta';

            double next = current;

            if (mode == 'set') {
              if (a.data.containsKey('value_norm') && pMin != null && pMax != null) {
                final vn = (a.data['value_norm'] as num).toDouble().clamp(0.0, 1.0);
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
            final double? hardMin = a.data['clamp_min'] is num ? (a.data['clamp_min'] as num).toDouble() : null;
            final double? hardMax = a.data['clamp_max'] is num ? (a.data['clamp_max'] as num).toDouble() : null;

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
              paramId: paramName, // if your engine needs name instead, use paramName
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
              HaloKey('row:$row:fx_index:$fxIndex:param:$paramId'), // TODO: put paramName instead of paramId maybe
            ]);

            _chatController.insertMessage(
              ActionSummaryMessage(
                text:
                    '• Adjusted $paramName from ${current.toStringAsFixed(2)} to ${next.toStringAsFixed(2)} on ${effects[fxIndex]} (Track ${row + 1}) •',
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

            _chatController.insertMessage(ActionSummaryMessage(text: '• Removed all effects on Track ${row + 1} •'));

            continue;
          }

        default:
          // Unknown / noop → ignore safely
          continue;
      }
    }
    if (groupedActions.isEmpty) return;

    await _undoManager.addWithoutExecute(CompoundUndoAction('AI mixing adjustments', groupedActions));
  }

  Map<String, dynamic>? _pickParam(List<Map<String, dynamic>> params, {String? exactName, List<String>? containsAny}) {
    final lowerExact = exactName?.toLowerCase();

    Map<String, dynamic>? best;
    int bestScore = -1;

    for (final p in params) {
      final name = (p['name']?.toString() ?? '');
      final n = name.toLowerCase();

      int score = 0;
      if (lowerExact != null && n == lowerExact) score += 100;
      if (containsAny != null && containsAny.any((s) => n.contains(s.toLowerCase()))) score += 50;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }

    return bestScore > 0 ? best : null;
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
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

    final reply = await _chatPipeline.handleUserText(
      text: prompt,
      audioTracks: _audioTracks,
      bpmFallback: _tempo.toDouble(),
      rowGain: _rowGain,
      rowPan: _rowPan,
      rowAutomation: _rowVolumeAutomation,
      autoApplyProposals: true, // <-- key
    );

    if (reply.hasMix) {
      await applyMixingResult(reply.mixing!);
      _chatPipeline.recordAppliedMix(reply.mixing!);
    }

    _chatController.insertMessage(
      TextMessage(id: const Uuid().v4(), authorId: 'assistant', createdAt: DateTime.now().toUtc(), text: reply.message),
    );

    // show a snackbar/modal if you want:
    // ScaffoldMessenger.of(context).showSnackBar(...)
  }

  Widget _buildBottomChatAndTransport() {
    final media = MediaQuery.of(context);

    final keyboard = media.viewInsets.bottom;
    final safeBottom = media.padding.bottom;

    // height of UI already below the chat bar
    const double transportHeight = 94; // 84 + bottom spacer

    final lift = (keyboard - transportHeight - safeBottom).clamp(0.0, double.infinity);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          // padding: EdgeInsets.only(
          //   bottom: MediaQuery.of(context).viewInsets.bottom,
          // ),
          padding: EdgeInsets.only(bottom: lift),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // === GLASS CHAT BAR (fills available space) ===
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _ChatBar(
                    expanded: _chatExpanded,
                    controller: _chatTextController,
                    focusNode: _chatFocusNode,
                    onTapCollapsed: () {
                      setState(() => _chatExpanded = true);
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

                      // 2. Run pipeline
                      ChatPipelineResult reply = await _chatPipeline.handleUserText(
                        text: userText,
                        audioTracks: _audioTracks,
                        bpmFallback: _tempo.toDouble(),
                        rowGain: _rowGain,
                        rowPan: _rowPan,
                        rowAutomation: _rowVolumeAutomation,
                        // autoApplyProposals: true, // does not ask for approval, just execute
                      );

                      print(reply.toString());

                      // await applyMixingResult(reply);
                      if (reply.hasMix) {
                        await applyMixingResult(reply.mixing!);

                        // IMPORTANT: teach the assistant what actually changed
                        _chatPipeline.recordAppliedMix(reply.mixing!);
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
                        ).showSnackBar(SnackBar(content: Text(reply.message), duration: const Duration(seconds: 4)));
                      }

                      setState(() {});
                      //TODO: refetch effects and stuff like that

                      // debugPrint('AI: $reply');
                    },
                  ),
                ),
              ),

              // const SizedBox(width: 12),

              // === ADD (+) BUTTON (inline with chat bar) ===
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _showAddMediaOptions(),
                    child: const Icon(Icons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ==== Transport Drawer =============================================
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            // child: BackdropFilter(
            // filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07), // softer white glass
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, -12)),
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
                                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(22),
                                              bottomLeft: Radius.circular(22),
                                            ),
                                            onTap: _undoManager.canUndo
                                                ? () async {
                                                    final action = await _undoManager.undo();
                                                    if (!mounted || action == null) return;

                                                    final messenger = ScaffoldMessenger.of(context);
                                                    messenger.hideCurrentSnackBar();
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text('Undo: ${action.description}'),
                                                        duration: const Duration(milliseconds: 1200),
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
                                                      : Colors.white.withOpacity(0.3),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(width: 1, height: 28, color: Colors.white.withOpacity(0.2)),
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: const BorderRadius.only(
                                              topRight: Radius.circular(22),
                                              bottomRight: Radius.circular(22),
                                            ),
                                            onTap: _undoManager.canRedo
                                                ? () async {
                                                    final action = await _undoManager.redo();
                                                    if (!mounted || action == null) return;

                                                    final messenger = ScaffoldMessenger.of(context);
                                                    messenger.hideCurrentSnackBar();
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text('Redo: ${action.description}'),
                                                        duration: const Duration(milliseconds: 1200),
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
                                                      : Colors.white.withOpacity(0.3),
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
                                final borderRadius = BorderRadius.circular(height / 2);

                                return Container(
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: borderRadius,
                                    border: Border.all(color: Colors.white.withOpacity(0.14)),
                                  ),
                                  child: Row(
                                    children: [
                                      _transportSegment(
                                        icon: Icons.skip_previous,
                                        onTap: () async {
                                          if (_isRecording) return; // disabled during recording
                                          await _restartAudio(_audioEditorStateSetter!);
                                        },
                                        radius: BorderRadius.only(
                                          topLeft: Radius.circular(height / 2),
                                          bottomLeft: Radius.circular(height / 2),
                                        ),
                                        iconSize: iconSize,
                                      ),
                                      _verticalDivider(height),
                                      _transportSegment(
                                        icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                                        onTap: () async {
                                          if (_isRecording) {
                                            // Pause button should also stop recording and stop playback
                                            await _stopRecordingJuce(keepPlaying: false);
                                          } else {
                                            await _togglePlayPause();
                                          }
                                        },
                                        iconSize: iconSize,
                                      ),
                                      _verticalDivider(height),
                                      _transportSegment(
                                        icon: Icons.fiber_manual_record,
                                        onTap: _onRecordPressed,
                                        radius: BorderRadius.only(
                                          topRight: Radius.circular(height / 2),
                                          bottomRight: Radius.circular(height / 2),
                                        ),
                                        iconSize: iconSize,
                                        iconColor: _isRecording ? Colors.redAccent : Colors.red,
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
                                final pillHeight = totalHeight * 0.6; // e.g. ~42 if container is 76
                                final logoSize = pillHeight * 0.9; // keep proportional
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
                                        borderRadius: BorderRadius.circular(pillHeight / 2),
                                        onTap: () async {
                                          // optional: haptic
                                          // HapticFeedback.lightImpact();
                                          final run = await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: const Text('One-Button Mix'),
                                              content: const Text(
                                                'This will:\n'
                                                '• Balance levels\n'
                                                '• Reduce masking\n'
                                                '• Improve clarity\n\n'
                                                'You can undo everything.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text('Run'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (run != true) return;

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(const SnackBar(content: Text('Mixing…')));

                                          await runOneButtonMix();

                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('One-Button Mix executed. Open chat for details.'),
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
                                                colors: [Color(0xFF5C7AFF), Color(0xFF3050FF)],
                                              ),
                                              borderRadius: BorderRadius.circular(pillHeight / 2),
                                              border: Border.all(color: Colors.white.withOpacity(0.18)),
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
                                                      borderRadius: BorderRadius.circular(pillHeight / 2),
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                        colors: [
                                                          Colors.white.withOpacity(0.18),
                                                          Colors.transparent,
                                                          Colors.transparent,
                                                          Colors.white.withOpacity(0.12),
                                                        ],
                                                        stops: const [0.0, 0.35, 0.65, 1.0],
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
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(0)),
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
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: radius ?? BorderRadius.zero,
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: iconSize, color: iconColor ?? Colors.white),
        ),
      ),
    );
  }

  Widget _verticalDivider(double height) {
    return Container(width: 1, height: height * 0.6, color: Colors.white.withOpacity(0.2));
  }

  void _handleCopyClip(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];

    setState(() {
      _copiedAudioClip = clip;
      _copiedTrimStart = clip.trimStart;
      _copiedTrimEnd = clip.trimEnd;
    });
  }

  Future<void> _handleDeleteClip(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;

    final clip = _audioTracks[clipIndex];

    // track.audioStartTimer?.cancel();

    // setState(() {
    //   _audioTracks.removeAt(clipIndex);
    // });
    // await JuceAudioEngine.removeTrack(clipIndex);
    // await JuceAudioEngine.pause();
    // _updateOverallDurationIfNeeded();

    await _undoManager.execute(
      DeleteClipAction(
        tracks: _audioTracks,
        clip: clip,
        originalIndex: clipIndex,
        addTrack: ({
          required AudioTrack clip,
          required int row,
          required double timeMs,
          required Duration trimStartRequested,
          required Duration trimEndRequested,
        }) =>
            _pasteAudioTrack(
          // NOTE: undo action for deleteclip is closer to _pasteAudioTrack than _addAudioTrack since we don't need to rehandle encoding + name conflict
          clip,
          row,
          timeMs,
          trimStartRequested: trimStartRequested,
          trimEndRequested: trimEndRequested,
        ),
        onChange: () {
          _updateOverallDurationIfNeeded();
        },
      ),
    );

    // NOTE: this means deleting a track deletes all undo history. can delete this if that's not desired
    // of course, the undoManager.execute above doesn't get added to history
    // _undoManager.clear();

    // TODO: not sure if this part/delay is needed
    Future.delayed(Duration(milliseconds: 50), () {
      setState(() {}); // force a repaint
    });
  }

  Future<void> _handlePasteClipAt(int row, double timeMs) async {
    if (_copiedAudioClip == null) return;

    if (_audioTracks.length >= kNumClips) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Max number of audio clips reached (500). Unable to add more clips.")));
      return;
    }

    await _undoManager.execute(
      PasteAudioClipAction(
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
        clip: _copiedAudioClip!,
        row: row,
        timeMs: timeMs,
        trimStart: _copiedTrimStart,
        trimEnd: _copiedTrimEnd,
      ),
    );
  }

  Future<void> _recomputeAudibleState() async {
    final soloActive = _rowSoloed.any((s) => s);

    for (int row = 0; row < kNumRows; row++) {
      bool shouldMute;

      if (soloActive) {
        // SOLO MODE: mute everything that is NOT soloed
        shouldMute = !_rowSoloed[row];
      } else {
        // NORMAL MODE: respect mute buttons
        shouldMute = _rowMuted[row];
      }

      await JuceAudioEngine.muteRow(row, shouldMute);
    }
  }

  void _updateOverallDurationIfNeeded() {
    Duration newDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      newDuration = _audioTracks.map((track) {
        final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
        final trackDuration = track.trimEnd - track.trimStart;
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
              extendBody: true,
              body: SafeArea(
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setLocalState) {
                    _audioEditorStateSetter = setLocalState;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          children: [
                            // TOP ROW OF BUTTONS
                            Padding(padding: const EdgeInsets.only(bottom: 12.0), child: _buildTopBar()),

                            Flexible(
                              fit: FlexFit.loose,
                              child: AudioCanvasTimeline(
                                clips: _audioTracks, // your list
                                rowGain: _rowGain,
                                rowPan: _rowPan,
                                rowVolumeAutomation: _rowVolumeAutomation,
                                // extractors
                                getStartMs: (t) => t.offset * 1000.0, // adjust to your model
                                getDurationMs: (t) => t.audioDuration.inMilliseconds.toDouble(),
                                getTrimStartMs: (t) => t.trimStart.inMilliseconds.toDouble(),
                                getTrimEndMs: (t) => t.trimEnd.inMilliseconds.toDouble(),
                                // getRowIndex: (t) => (t.rowIndex >= 0 && t.rowIndex < kNumRows) ? t.rowIndex : 0,
                                getPeaks: (c) {
                                  return c.normWaveformData;
                                },
                                getY: (c) => c.y, // store a visual Y in your model
                                // commit (persist in your model, then setState)
                                onMoveClipCommit: (i, newStartMs, newRowIndex) async {
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
                                      onChange: _updateOverallDurationIfNeeded,
                                    ),
                                  );
                                  setState(() {});
                                },
                                onTrimClip: (i, s, e, {double? newStartMs}) async {
                                  final clip = _audioTracks[i];

                                  // 1. Update the internal trim values (where in the source file we start/end)
                                  clip.trimStart = Duration(milliseconds: s.round());
                                  clip.trimEnd = Duration(milliseconds: e.round());

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
                                },

                                // for the undo history
                                onTrimClipCommit: (i, s, e, os, oe, oo, {double? newStartMs}) async {
                                  // final clip = _audioTracks[i];
                                  await _undoManager.execute(
                                    TrimClipAction(
                                      // clip: clip,
                                      tracks: _audioTracks,
                                      originalIndex: i,
                                      oldTrimStart: Duration(milliseconds: os.round()),
                                      oldTrimEnd: Duration(milliseconds: oe.round()),
                                      oldOffset: oo / 1000.0,
                                      newTrimStart: Duration(milliseconds: s.round()),
                                      newTrimEnd: Duration(milliseconds: e.round()),
                                      newOffset: newStartMs != null ? newStartMs / 1000.0 : null,
                                      onChange: _updateOverallDurationIfNeeded,
                                    ),
                                  );
                                },

                                // selection + headers
                                // numRows: kNumRows,
                                // selectedRowIndex: _selectedRow,
                                onSelectRow: (row) => setState(() => _selectedRow = row),
                                // rowMuted: _rowMuted,
                                // recordRowIndex: _recordRow,
                                // rowExpanded: _rowExpanded,
                                recordingInProgress: _isRecording,
                                onToggleRecord: (row) => setState(() {
                                  _recordRow = _recordRow == row ? null : row;
                                }),
                                onToggleExpanded: (row) => setState(() => _rowExpanded[row] = !_rowExpanded[row]),

                                // transport
                                playheadMs: _globalAudioClock.inMilliseconds.toDouble(), // your existing clock
                                // isPlaying: _isPlaying,
                                onScrubRequested: (ms) {
                                  if (_isRecording) {
                                    return; // do nothing while recording (hopefully no bug where you can still physically scrub but does nothing here)
                                  }

                                  final newPosition = Duration(milliseconds: ms.toInt());
                                  _audioEditorStateSetter!(() {
                                    _globalAudioClock = newPosition;
                                  });
                                  for (int i = 0; i < _audioTracks.length; i++) {
                                    final track = _audioTracks[i];
                                    final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);
                                    JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
                                    setState(() {
                                      track.currentPosition = effectivePos;
                                    });
                                  }
                                  JuceAudioEngine.setAutomationTransport(ms / 1000.0);
                                  JuceAudioEngine.setMetronomeTransportMs(ms);

                                  if (_isPlaying) {
                                    _resumeAudio(setLocalState);
                                  }
                                },
                                maxDuration: _audioOnlyOverallDuration,
                                getFullDurationMs: (t) => t.audioDuration.inMilliseconds.toDouble(),
                                isPlaying: _isPlaying,

                                // ruler/grid
                                bpm: _tempo.toDouble(),
                                beatsPerBar: 4,

                                // layout
                                // numRows: kNumRows,
                                height: 520, // THIS VALUE is effectively unused, the height is just natural now
                                // ============================
                                // NEW: Row FX callbacks
                                // ============================
                                getRowEffects: (row) => JuceAudioEngine.getTrackEffectsForRow(row),

                                getRowEffectBypassState: (row, effectIndex) =>
                                    JuceAudioEngine.getRowEffectBypassState(row, effectIndex),

                                insertRowEffect: (row, pathOrName) async {
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
                                }, //=> JuceAudioEngine.insertTrackEffect(row, pathOrName),
                                // need name of effects so undo action can add it back later
                                removeRowEffect: (row, effectIndex, name, applyingPreset) async {
                                  if (applyingPreset) {
                                    await JuceAudioEngine.removeTrackEffect(row, effectIndex);
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
                                }, //JuceAudioEngine.reorderTrackEffects(row, from, to),

                                setRowEffectBypassed: (row, effectIndex, bypass) async {
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
                                }, //=> JuceAudioEngine.bypassRowEffect(row, effectIndex, bypass),

                                getRowPluginParameters: (row, effectIndex) =>
                                    JuceAudioEngine.getTrackPluginParameters(row, effectIndex),

                                setRowEffectParam: (row, effectIndex, paramId, value) =>
                                    JuceAudioEngine.setTrackEffect(row, effectIndex, paramId, value),

                                // for commiting to undo history
                                onPluginParamCommit: (row, idx, paramId, oldValue, newValue) async {
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
                                },

                                onPresetCommit: (before, after) async {
                                  await _undoManager.execute(
                                    TrackPresetChangeAction(
                                      before: before,
                                      after: after,
                                      onChange: () => setState(() {}),
                                    ),
                                  );
                                },

                                scanPlugins: () => JuceAudioEngine.scanPlugins(),

                                setTrackAutomationPoints: (row, points) =>
                                    JuceAudioEngine.setTrackAutomationPoints(row, points),

                                onAutomationCommit: (row, oldPoints, newPoints) {
                                  _undoManager.execute(
                                    SetAutomationPointsAction(
                                      row: row,
                                      oldPoints: oldPoints,
                                      newPoints: newPoints,
                                      applyToState: (r, points) {
                                        setState(() {
                                          _rowVolumeAutomation[r] =
                                              points.map((p) => AutomationPoint(x: p.x, volume: p.volume)).toList();
                                        });
                                      },
                                    ),
                                  );
                                },

                                setRowGain: (row, gain0to3) => JuceAudioEngine.setRowGain(row, gain0to3),
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

                                setRowPan: (row, newPan) => JuceAudioEngine.setRowPan(row, newPan),
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
                                },

                                onCopyClip: _handleCopyClip,
                                onDeleteClip: _handleDeleteClip,
                                hasCopiedClip: _copiedAudioClip != null,
                                onPasteClipAt: _handlePasteClipAt,
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
                                recordingRowIndex: _recordRow,
                                recordingStartMs: _recordingStartMs,
                                recordingPeaks: _recordingPeaks, // TODO: FIX TO USE WITH JUCE
                                registerRowFxRefresher: (fn) {
                                  _refreshRowFx = fn;
                                },
                                meters: _meters,
                                getRowCompressorMeter: (row, fx) => JuceAudioEngine.getRowCompressorMeter(row, fx),

                                mode: widget.mode, // or "Basic"/"Pro" etc
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0, // space for chat bar + transport
                          child: AnimatedSlide(
                            offset: _chatExpanded ? Offset.zero : const Offset(0, 0.3),
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: SizedBox(
                              height: 380,
                              child: _chatWarm
                                  ? AnimatedContainer(
                                      duration: const Duration(milliseconds: 260),
                                      curve: Curves.easeOutCubic,
                                      height: _chatExpanded ? 380 : 0,
                                      margin: const EdgeInsets.symmetric(horizontal: 12),
                                      child: IgnorePointer(
                                        ignoring: !_chatExpanded,
                                        child: Opacity(
                                          opacity: _chatExpanded ? 1 : 0,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(22),
                                            child: BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.08), // ← glass tint
                                                  borderRadius: BorderRadius.circular(22),
                                                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                                                ),
                                                child: MediaQuery.removePadding(
                                                  context: context,
                                                  removeBottom: true,
                                                  child: MediaQuery.removeViewInsets(
                                                    context: context,
                                                    removeBottom: true,
                                                    child: Chat(
                                                      chatController: _chatController,
                                                      currentUserId: 'user',
                                                      onMessageSend:
                                                          null, // message sending is handled by a component outside. this is simply showing the chat history
                                                      timeFormat: null,
                                                      onMessageLongPress: (
                                                        BuildContext context,
                                                        Message message, {
                                                        required LongPressStartDetails details,
                                                        required int index,
                                                      }) async {
                                                        // Only copy text messages
                                                        if (message is TextMessage) {
                                                          await Clipboard.setData(
                                                            ClipboardData(text: message.text),
                                                          );

                                                          // NOTE: this doesn't work. maybe have to enable haptic feedback in app permissions/settings
                                                          HapticFeedback.lightImpact();

                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            const SnackBar(
                                                              content: Text('Message copied to clipboard'),
                                                              duration: Duration(milliseconds: 1500),
                                                              behavior: SnackBarBehavior.floating,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      builders: Builders(
                                                        composerBuilder: (_) => const SizedBox.shrink(),
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
                                                        chatAnimatedListBuilder: (context, itemBuilder) {
                                                          return Column(
                                                            children: [
                                                              Expanded(
                                                                child: MediaQuery.removePadding(
                                                                  context: context,
                                                                  removeBottom: true,
                                                                  child: ChatAnimatedList(itemBuilder: itemBuilder),
                                                                ),
                                                              ),
                                                              if (_isThinking)
                                                                Padding(
                                                                  padding: const EdgeInsets.only(
                                                                    left: 14,
                                                                    right: 14,
                                                                    bottom: 10,
                                                                    top: 4,
                                                                  ),
                                                                  child: Align(
                                                                    alignment: Alignment.centerLeft,
                                                                    child: _AssistantThinkingBubble(),
                                                                  ),
                                                                ),
                                                            ],
                                                          );
                                                        },
                                                        textMessageBuilder: (
                                                          BuildContext context,
                                                          TextMessage message,
                                                          int index, {
                                                          required bool isSentByMe,
                                                          MessageGroupStatus? groupStatus,
                                                        }) {
                                                          // SYSTEM / ACTION MESSAGE
                                                          if (message.authorId == 'system') {
                                                            return Padding(
                                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                                              child: Center(
                                                                child: Text(
                                                                  message.text,
                                                                  textAlign: TextAlign.center,
                                                                  style: const TextStyle(
                                                                    fontFamily: 'Pretendard',
                                                                    fontSize: 13,
                                                                    fontWeight: FontWeight.w600,
                                                                    letterSpacing: 0.4,
                                                                    color: Colors.white70,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                          return Align(
                                                            alignment: isSentByMe
                                                                ? Alignment.centerRight
                                                                : Alignment.centerLeft,
                                                            child: Container(
                                                              margin: const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 4,
                                                              ),
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 10,
                                                              ),
                                                              decoration: BoxDecoration(
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
                                                                borderRadius: BorderRadius.circular(14),
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
                                                      theme: const ChatTheme(
                                                        colors: ChatColors(
                                                          // User message bubble (you)
                                                          primary: Color.fromARGB(180, 56, 98, 161),
                                                          onPrimary: Colors.white,
                                                          // Message list surface layers (kill them)
                                                          surface: Colors.transparent,
                                                          onSurface: Colors.white,
                                                          surfaceContainer:
                                                              Colors.transparent, //Color.fromARGB(100, 170, 170, 170),
                                                          surfaceContainerLow: Colors.transparent,
                                                          surfaceContainerHigh: Colors.transparent,
                                                        ),
                                                        typography: ChatTypography(
                                                          bodyLarge: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 15,
                                                            height: 1.35,
                                                            color: Colors.white,
                                                          ),
                                                          bodyMedium: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 14,
                                                            height: 1.35,
                                                            color: Colors.white70,
                                                          ),
                                                          bodySmall: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 13,
                                                            height: 1.3,
                                                            color: Colors.white60,
                                                          ),
                                                          labelLarge: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w500,
                                                            color: Colors.white70,
                                                          ),
                                                          labelMedium: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 12,
                                                            color: Colors.white60,
                                                          ),
                                                          labelSmall: TextStyle(
                                                            fontFamily: 'Pretendard',
                                                            fontSize: 11,
                                                            color: Colors.white54,
                                                          ),
                                                        ),

                                                        // Message bubble shape — keep subtle, not “chat app rounded”
                                                        shape: BorderRadius.all(Radius.circular(14)),
                                                      ),
                                                      resolveUser: (UserID id) async {
                                                        if (id == 'user') {
                                                          return const User(id: 'user', name: 'You');
                                                        }
                                                        return const User(id: 'assistant', name: 'MixAssistant');
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
              bottomNavigationBar: _buildBottomChatAndTransport(),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
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
                bottom: 380 + 190, // panel height + bottom UI
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    setState(() {
                      _chatExpanded = false;
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
          colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.28), Colors.white.withOpacity(0.08)],
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

class _DotsLoaderState extends State<DotsLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dotCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 1), vsync: this)..repeat();
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
        Text('${L10n.translate(context, 'Syncing Audio')}', style: TextStyle(color: Colors.white, fontSize: 20)),
        const SizedBox(width: 2),
        SizedBox(
          width: totalDotSpace,
          child: AnimatedBuilder(
            animation: _dotCount,
            builder: (context, _) {
              return Text('.' * _dotCount.value, style: const TextStyle(color: Colors.white, fontSize: 20));
            },
          ),
        ),
      ],
    );
  }
}

double getVolumeForAutomation(List<AutomationPoint> points, double normalizedTime) {
  if (points.isEmpty) return 1.0;
  if (normalizedTime <= points.first.x) return points.first.volume;
  if (normalizedTime >= points.last.x) return points.last.volume;
  for (int i = 0; i < points.length - 1; i++) {
    if (normalizedTime >= points[i].x && normalizedTime <= points[i + 1].x) {
      double t = (normalizedTime - points[i].x) / (points[i + 1].x - points[i].x);
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

    int bestOffset = findOffsetFFT(videoSamples, trackSamples, sampleRate, progressPort);
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

Future<List<double>> loadAudioSamplesAsync(String filePath, {int numChannels = 2}) async {
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

int findOffsetFFT(List<double> videoSamples, List<double> trackSamples, double sampleRate, SendPort progressPort) {
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

  final double delta =
      0.5 * (data[index - 1] - data[index + 1]) / (data[index - 1] - 2 * data[index] + data[index + 1]);

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

String generateVolumeAutomationFilter(AudioTrack track, int offsetMs, double universalCrossfade) {
  // If no automation points, default to universal crossfade value.
  if (track.volumeAutomation.isEmpty) return min(1.0, universalCrossfade * 2).toStringAsFixed(2);

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

  const ExportProgressPage({required this.exportFn, required this.videoFile, super.key});

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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.translate(context, "Please don't close the app or lock your screen."),
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

  const ExportSuccessScreen({super.key, required this.filePath, required this.isVideo});

  Future<void> _shareFile(BuildContext context) async {
    try {
      await Share.shareXFiles([XFile(filePath)]); // doesn't work on android (only iOS)
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
    final descController = TextEditingController(text: 'Made with Mixroom 🎸🎬');

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
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: const Color.fromARGB(255, 255, 255, 255), // or onPrimary
              ),
              onPressed: () {
                Navigator.pop(context, {'title': titleController.text, 'description': descController.text});
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
    final qrImageData = await painter.toImageData(300, format: ImageByteFormat.png);

    final qrBytes = qrImageData!.buffer.asUint8List();

    // 2. Get YouTube default thumbnail
    // final thumbRes = await http.get(Uri.parse('https://img.youtube.com/vi/$videoId/maxresdefault.jpg'));
    // final thumbnail = img.decodeImage(thumbRes.bodyBytes);
    final frameFile = await extractFirstFrame(File(filePath));
    final thumbnail = img.decodeImage(await frameFile.readAsBytes());
    final qr = img.decodeImage(qrBytes);

    if (thumbnail == null || qr == null) throw Exception("Failed to process images");

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
                child: Image.file(qrImage, width: 280, height: 158, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text("Save Image"),
                onPressed: () async {
                  final result = await ImageGallerySaver.saveFile(qrImage.path);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['isSuccess'] == true ? '✅ Saved to gallery!' : '❌ Failed to save')),
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
                child: Text(L10n.translate(context, 'Done'), style: TextStyle(fontSize: 16, color: Colors.white)),
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
                              L10n.translate(context, 'Your video was exported successfully!'),
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            )
                          : Text(
                              L10n.translate(context, 'Your audio was exported successfully!'),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Wrap(
                          spacing: 32,
                          runSpacing: 24,
                          alignment: WrapAlignment.start,
                          children: [
                            if (isVideo)
                              _SocialButton(
                                iconWidget: Image.asset('assets/youtube_icon.png', width: 56),
                                label: 'YouTube',
                                onTap: () async {
                                  final info = await showUploadDialog(context);
                                  if (info == null) return;

                                  try {
                                    final videoId = await YoutubeService.uploadVideo(
                                      file: File(filePath),
                                      title: info['title']!,
                                      description: info['description']!,
                                    );

                                    if (videoId == null) {
                                      print('upload failed, videoId == null');
                                      return;
                                    }

                                    final qrThumb = await generateThumbnailWithQR(videoId);
                                    await YoutubeService.uploadThumbnail(videoId, qrThumb);
                                    showQRPopup(context, qrThumb);
                                  } catch (e) {
                                    print("❌ Upload failed: $e");
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(SnackBar(content: Text('❌ Upload failed')));
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
                                iconWidget: Image.asset('assets/ig_icon.png', width: 56),
                                label: 'Instagram',
                                onTap: () => _openSocialMedia('instagram://library', 'https://www.instagram.com/'),
                              ),
                            if (isVideo)
                              _SocialButton(
                                iconWidget: Image.asset('assets/tiktok_icon.png', width: 56),
                                label: 'TikTok',
                                onTap: () => _openSocialMedia('snssdk1233://upload', 'https://www.tiktok.com/upload'),
                              ),
                            if (!isVideo)
                              _SocialButton(
                                iconWidget: Image.asset('assets/soundcloud_icon.png', width: 56),
                                label: 'SoundCloud',
                                onTap: () => _openSocialMedia('soundcloud://upload', 'https://soundcloud.com/upload'),
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

    final qrPainter = QrPainter(data: videoUrl, version: QrVersions.auto, gapless: true);

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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thumbnail saved to ${file.path}')));
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
            ElevatedButton(onPressed: () => _saveThumbnailWithQR(context), child: const Text('Download QR Thumbnail')),
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

  const _SocialButton({this.icon, this.iconWidget, required this.label, required this.onTap});

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
            decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
            child: ClipOval(
              child: Center(child: iconWidget ?? Icon(icon, size: 26, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
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

  const DynamicRackContent({required this.volumePage, required this.effectsPage, super.key});

  @override
  State<DynamicRackContent> createState() => _DynamicRackContentState();
}

class _DynamicRackContentState extends State<DynamicRackContent> with SingleTickerProviderStateMixin {
  // <-- Ticker is now ISOLATED here!

  late TabController _tabController;
  int _currentTabIndex = 0; // State variable to trigger rebuilds

  static const double _volumeContentHeight = 150.0;
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
    final double currentHeight = _currentTabIndex == 0 ? _volumeContentHeight : _effectsMaxHeight;

    // 1. Return an AnimatedContainer as the root.
    return AnimatedContainer(
      // 2. Apply the dynamic height and minWidth directly to AnimatedContainer.
      constraints: BoxConstraints(maxHeight: currentHeight, minWidth: 280),
      duration: const Duration(milliseconds: 0), // Smooth transition duration
      curve: Curves.easeOut,

      // 3. The inner content (Column) must now use Expanded to fill this space.
      child: Column(
        mainAxisSize: MainAxisSize.min, // The Column must shrink-wrap vertically
        children: [
          // Tabs (TabBar logic with onTap remains the same)
          Container(
            // ... (TabBar decoration)
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              onTap: (newIndex) {
                // Keep the instant jump for TabBarView to avoid flicker
                _tabController.animateTo(newIndex, duration: Duration.zero, curve: Curves.linear);
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
          const SizedBox(height: 12),

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
  int? _addedIndex;

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

    await addTrack(file: file, row: row, timeMs: timeMs, trimStartRequested: trimStart, trimEndRequested: trimEnd);

    // capture the newly added track
    if (tracks.length > beforeCount) {
      _addedIndex = tracks.length - 1;
      _addedTrack = tracks[_addedIndex!];
    }
  }

  @override
  Future<void> undo() async {
    if (_addedIndex == null || _addedTrack == null) return;

    final track = _addedTrack!;
    track.audioStartTimer?.cancel();

    tracks.removeAt(_addedIndex!);
    await JuceAudioEngine.removeTrack(_addedIndex!);
    await JuceAudioEngine.pause();

    _addedTrack = null;
    _addedIndex = null;
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
  int? _addedIndex;

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

    await pasteClip(clip: clip, row: row, timeMs: timeMs, trimStartRequested: trimStart, trimEndRequested: trimEnd);

    // capture the newly added track
    if (tracks.length > beforeCount) {
      _addedIndex = tracks.length - 1;
      _addedTrack = tracks[_addedIndex!];
    }
  }

  @override
  Future<void> undo() async {
    if (_addedIndex == null || _addedTrack == null) return;

    final track = _addedTrack!;
    track.audioStartTimer?.cancel();

    tracks.removeAt(_addedIndex!);
    await JuceAudioEngine.removeTrack(_addedIndex!);
    await JuceAudioEngine.pause();

    _addedTrack = null;
    _addedIndex = null;
  }
}

class DeleteClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final AudioTrack clip;
  final int originalIndex;

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
    required this.originalIndex,
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
  String get description => 'Delete audio clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.audioStartTimer?.cancel();

    tracks.removeAt(originalIndex);
    await JuceAudioEngine.removeTrack(originalIndex);
    await JuceAudioEngine.pause();

    onChange();
  }

  @override
  Future<void> undo() async {
    await addTrack(clip: clip, row: row, timeMs: timeMs, trimStartRequested: trimStart, trimEndRequested: trimEnd);
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

    await JuceAudioEngine.moveClipToRow(originalIndex, newRow);
    onChange();
  }

  @override
  Future<void> undo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.offset = oldOffset;
    clip.rowIndex = oldRow;

    await JuceAudioEngine.moveClipToRow(originalIndex, oldRow);
    onChange();
  }
}

class SetRowGainAction extends EditorUndoAction {
  final int row;
  final double oldGain;
  final double newGain;
  final void Function(int row, double gain) applyToState;

  SetRowGainAction({required this.row, required this.oldGain, required this.newGain, required this.applyToState});

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

  SetRowPanAction({required this.row, required this.oldPan, required this.newPan, required this.applyToState});

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

  SetMasterGainAction({required this.oldGain, required this.newGain, required this.applyToState});

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

  SetMasterPanAction({required this.oldPan, required this.newPan, required this.applyToState});

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
  })  : oldPoints = oldPoints.map((p) => AutomationPoint(x: p.x, volume: p.volume)).toList(),
        newPoints = newPoints.map((p) => AutomationPoint(x: p.x, volume: p.volume)).toList();

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

  InsertEffectAction({required this.row, required this.pathOrName, required this.onChange});

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

  RemoveEffectAction({required this.row, required this.effectIndex, required this.pathOrName, required this.onChange});

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

  ReorderEffectAction({required this.row, required this.from, required this.to, required this.onChange});

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

  RemoveMasterEffectAction({required this.effectIndex, required this.pathOrName, required this.onChange});

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
    await JuceAudioEngine.reorderMasterEffects((await JuceAudioEngine.getMasterEffects()).length - 1, effectIndex);
    onChange();
  }
}

class ReorderMasterEffectAction extends EditorUndoAction {
  final int from;
  final int to;
  final VoidCallback onChange;

  ReorderMasterEffectAction({required this.from, required this.to, required this.onChange});

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
  final effects = await JuceAudioEngine.getTrackEffectsForRow(row);
  final snapshots = <EffectSnapshot>[];

  for (int i = 0; i < effects.length; i++) {
    final params = await JuceAudioEngine.getTrackPluginParameters(row, i);
    final isBypassed = await JuceAudioEngine.getRowEffectBypassState(row, i);
    snapshots.add(EffectSnapshot(effects[i], isBypassed, {for (final p in params) p['name']: p['value']}));
  }

  return RowEffectsSnapshot(row, snapshots);
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

    for (final e in fx.params.entries) {
      await JuceAudioEngine.setTrackEffect(snap.row, i, e.key, e.value);
    }

    if (fx.bypassed) {
      await JuceAudioEngine.bypassRowEffect(snap.row, i, true);
    }
  }
}

Future<MasterEffectsSnapshot> captureMasterSnapshot() async {
  final effects = await JuceAudioEngine.getMasterEffects();
  final snapshots = <EffectSnapshot>[];

  for (int i = 0; i < effects.length; i++) {
    final params = await JuceAudioEngine.getMasterPluginParameters(i);
    final isBypassed = await JuceAudioEngine.getMasterEffectBypassState(i);
    snapshots.add(EffectSnapshot(effects[i], isBypassed, {for (final p in params) p['name']: p['value']}));
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

  TrackPresetChangeAction({required this.before, required this.after, required this.onChange});

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

  MasterPresetChangeAction({required this.before, required this.after, required this.onChange});

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
    width: 28,
    height: 28,
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
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTapCollapsed;
  final VoidCallback onSubmit;

  const _ChatBar({
    super.key,
    required this.expanded,
    required this.controller,
    required this.focusNode,
    required this.onTapCollapsed,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: expanded ? null : onTapCollapsed,
      child: _Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        opacity: 0.10,
        child: Row(
          children: [
            _chatIcon(),
            const SizedBox(width: 10),
            Expanded(
              child: expanded
                  ? Material(
                      color: Colors.transparent,
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,

                        // ✅ match Text() metrics exactly
                        style: const TextStyle(fontFamily: 'Pretendard', fontSize: 15, height: 1.0),
                        strutStyle: const StrutStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15,
                          height: 1.0,
                          forceStrutHeight: true,
                        ),

                        decoration: const InputDecoration(
                          hintText: 'Type...',
                          hintStyle: TextStyle(color: Colors.white70, fontSize: 15, height: 1.0),
                          border: InputBorder.none,
                          isCollapsed: true,

                          // ✅ kills extra internal padding that can sneak in
                          contentPadding: EdgeInsets.zero,
                        ),

                        textAlignVertical: TextAlignVertical.center, // ✅ keeps it centered
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSubmit(),
                      ),
                    )
                  : Text(
                      'Type...',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15.5,
                        height: 1.0,
                        color: Colors.white70,
                      ),
                      strutStyle: const StrutStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        height: 1.0,
                        forceStrutHeight: true,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionSummaryMessage extends TextMessage {
  ActionSummaryMessage({required String text})
      : super(id: const Uuid().v4(), authorId: 'system', createdAt: DateTime.now().toUtc(), text: text);
}

// NOTE: this is copied over from audio_timeline_pro.dart PrettyGainSlider. make sure no diffs
String _gainToDb(double sliderValue) {
  if (sliderValue <= 0.0001) return "–∞ dB";

  // Match your DSP: perceptualGain = sliderValue^2 (clamped to 9)
  double perceptual = math.min(sliderValue * sliderValue, 9.0);

  double db = 20 * math.log(perceptual) / math.log(10); // log10

  return db > 0 ? "+${db.toStringAsFixed(1)} dB" : "${db.toStringAsFixed(1)} dB";
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
  State<_AssistantThinkingBubble> createState() => _AssistantThinkingBubbleState();
}

class _AssistantThinkingBubbleState extends State<_AssistantThinkingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

    _opacity = Tween(begin: 0.35, end: 0.85).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
        child: const Text('•••', style: TextStyle(fontSize: 20, letterSpacing: 2, color: Colors.white70)),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
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
                child: const CircleAvatar(radius: 3, backgroundColor: Colors.white70),
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
    final bg = Paint()..color = const Color(0xFF1A2230); // richer dark blue-gray

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
