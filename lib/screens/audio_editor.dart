import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:audio_waveforms/audio_waveforms.dart';
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
import 'package:mixroom/widgets/side_menu.dart';
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
  bool _isScrubbing = false;
  bool _isPlaying = false;

  // Multi-track support
  List<AudioTrack> _audioTracks = []; // ONLY NEED TO USE THIS FOR MULTI-TRACK
  double _universalCrossfade = 0.5;

  // UI: AI sync progress bar
  bool _isSyncing = false;
  double _syncProgress = 0.0;

  // for bluetooth connection
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _deviceFound = false;
  double _downloadProgress = 0.0;
  bool _showProgressDialog = false;
  String _progressMessage = "";
  String _currentOperation = "";
  List<String> _guitarFiles = [];

  // late Ticker _ticker;
  Duration _lastKnownPosition = Duration.zero;

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

  // when press play, need to pre-warm audio, but volume should be muted during pre-warm
  bool _preWarmState = false;

  // PICK VIDEO
  bool _isPickingFile = false; // Add this flag to track file picker state
  bool _isLoadingVideo = false;
  bool _isLoadingAudio = false;
  bool _isLoadingNextScreen = false;

  StateSetter? _audioEditorStateSetter; // Store the StateSetter

  // for snapping automation points to seek line
  static const double _trimSnapPx = 8.0;
  static const double _autoSnapNorm = 0.02;

  int _expandedTrackIndex = -1;
  int _selectedTrackIndex = -1;

  Set<int> _expandedSegments = {};
  bool _isExporting = false;

  bool _showAutomationSection = false;

  Duration _audioOnlyOverallDuration = Duration.zero;

  final _timelineScroll = ScrollController();

  final int kWaveformSPS = 200; // samples per second for UI
  final int kMinSamples = 1024; // ensure enough resolution for short clips
  final int kMaxSamples = 200000; // safety cap for very long files

  static const int kNumRows = 5;

  int _selectedRow = 0; // one row always selected (by default row 0 (row 1 visually))
  int? _recordRow; // only one can be armed

  // === Recording state (Dart-only, no JUCE) ===
  final AudioRecorder _micRecorder = AudioRecorder();

  bool _isRecording = false;
  double _recordingStartMs = 0; // project time where the recording starts
  String? _recordingFilePath; // temp recorded file (m4a/wav/etc)
  DateTime? _recordingWallClockStart;
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
  bool get _anySoloActive => _rowSoloed.any((s) => s);
  final List<bool> _rowExpanded = List<bool>.filled(kNumRows, false);

  // for copy/paste logic
  // TODO: later this should be a quick copy in JUCE rather than a deep copy
  File? _copiedAudioFile;
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
  bool _isDialogOpen = false; // to fix an issue on iPad iOS 26 where opening some dialogue would insta-close it
  bool _isMasterPopupOpen = false; // same thing as above

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prewarmFFT(); // so that AI sync first run is not heavy
    // Initialize the ticker to update every ~16ms (about 60fps)
    // _ticker = createTicker((elapsed) async {
    //   // Use the elapsed time to compute an interpolated position.
    //   // For instance, add elapsed to _lastKnownPosition and update UI.
    //   final interpolatedPosition = _lastKnownPosition + elapsed;
    //   _updatePosition(interpolatedPosition);
    // });
    _transportTicker = Ticker((_) {
      if (!_isPlaying) return;

      // single source of truth
      // setState(() {
      //   _globalAudioClock = _transportBase + _transportStopwatch.elapsed;
      // });

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _isLoadingNextScreen = true);
      JuceAudioEngine.initialise(); // heavy blocking native call
      JuceAudioEngine.initialiseEventListeners();
      await Future.delayed(const Duration(milliseconds: 300)); // so that juce.init doesn't block UI load
      setState(() => _isLoadingNextScreen = false);
    });
  }

  // Future<void> _startTicker() async {
  //   // Stop any previous ticker.
  //   _ticker.stop();
  //   // Get the current position from the video controller.
  //   _lastKnownPosition = _scrubPosition; //_videoController!.value.position;
  //   _ticker.start();
  // }

  // Future<void> _stopTicker() async {
  //   _ticker.stop();
  // }

  // void _updatePosition(Duration position) async {
  //   // setState(() {
  //   // Update scrubPosition at a high frequency.
  //   WidgetsBinding.instance.addPostFrameCallback((_) async {
  //     _scrubPosition = position;
  //     if (position.inMilliseconds > _scrubPosition.inMilliseconds) {
  //       // _scrubPosition = duration;
  //       for (var track in _audioTracks) {
  //         // track.player.pause();
  //         track.audioStarted = false;
  //       }
  //       JuceAudioEngine.pause();
  //       // Optionally update _isPlaying state if needed.
  //       _isPlaying = false;
  //       _pausePlayback();
  //       _stopTicker();
  //     }
  //     // });

  //     if (!_isScrubbing && mounted && _isPlaying) {
  //       for (int i = 0; i < _audioTracks.length; i++) {
  //         final track = _audioTracks[i];
  //         final seconds = await JuceAudioEngine.getCurrentPosition(i);
  //         track.currentPosition = Duration(microseconds: (seconds * 1e6).round());

  //         if (track.currentPosition >= track.trimEnd) {
  //           await JuceAudioEngine.bypassTrack(i, true);
  //           continue;
  //         }

  //         // NOTE THAT this drift doesn't indicate the true distance between the video
  //         // and audio because the ticker is slightly off from the video
  //         // print("drift: ${((_videoPosition - track.currentPosition).inMilliseconds/10).round()/100}");

  //         final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
  //         if (position >= offsetDuration) {
  //           // Calculate how far the audio has progressed relative to its trim range.
  //           final effectiveTime = position - offsetDuration;
  //           final effectiveDuration = track.trimEnd - track.trimStart;
  //           double normalizedTime = effectiveDuration.inMilliseconds > 0
  //               ? effectiveTime.inMilliseconds / effectiveDuration.inMilliseconds
  //               : 0.0;
  //           normalizedTime = normalizedTime.clamp(0.0, 1.0);

  //           // Compute the new volume from the automation curve.
  //           double newVolume = getVolumeForAutomation(track.volumeAutomation, normalizedTime);

  //           // Optionally, combine this with your universal crossfade if desired.
  //           // For example, multiply with _universalCrossfade:
  //           newVolume *= min(1.0, _universalCrossfade * 2);

  //           // COMMENT OUT BECAUSE WE DO MAKE A NEW MP3 TIME GAIN IS CHANGED
  //           newVolume *= track.gain; // adjust for gain // this should not be above 1.0

  //           // SETVOLUME (1.0>) LEADS TO BUG IN THIS AUDIO PKG
  //           // Update the audio track volume.
  //           if (!_preWarmState) {
  //             // track.player.setVolume(newVolume);
  //             JuceAudioEngine.setTrackVolume(i, newVolume);
  //             //KIND OF BUG WHERE IF YOU SET A TRACK VOLUME BUT YOU DON'T PLAY IT BEFORE EXPORTING, IT WON'T APPLY
  //           }

  //           // If the track hasn’t started yet, start it.
  //           if (!track.audioStarted) {
  //             continue;
  //           }
  //         }
  //       }
  //     }
  //   });
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // _ticker.dispose();
    _amplitudeSub?.cancel();
    _micRecorder.dispose();
    for (var track in _audioTracks) {
      // track.player.dispose();
      track.waveformController.dispose();
      track.audioStartTimer?.cancel();
    }
    _transportTicker?.dispose();

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
        // _stopTicker();
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

        // This uses your existing pipeline (FFmpeg to temp wav, loadClip into JUCE, PlayerController)
        await _addAudioTrackFromFile(
          audioFile,
          rowIndex,
          offsetSec * 1000.0,
          trimStartRequested: Duration(milliseconds: trimStartMs),
          trimEndRequested: Duration(milliseconds: trimEndMs),
        );

        // After _addAudioTrackFromFile, the newest track is last
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

        final src = tr.originalFile.existsSync() ? tr.originalFile : tr.file;

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
          "trimStartMs": tr.trimStart.inMilliseconds,
          "trimEndMs": tr.trimEnd.inMilliseconds,
          "offset": tr.offset,
          "crossfade": tr.crossfade,
          "gain": tr.gain,
          "rowIndex": tr.rowIndex,
          "automation": tr.volumeAutomation.map((p) => p.toJson()).toList(),
        });
      }

      // Capture FX snapshots
      final usedRows = _audioTracks.map((t) => t.rowIndex).where((r) => r >= 0).toSet().toList()..sort();

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

  // TODO: slight chance that JuceAudioEngine.play and the _globalAudioClock could have a slight mismatch (sometimes)
  // think for play -> pause -> play -> pause... chance they could desync until a seek event matches them
  // try get to sync more consistently
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
  }

  // deprecated I think? maybe some parts of it should be refactored elsewhere
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

  Widget _buildTimeDisplay() {
    // if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) {
    //   return const SizedBox.shrink();
    // }

    //stuff for audio-only
    Duration overallDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      overallDuration = _audioTracks.map((track) {
        final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
        final trackDuration = track.trimEnd - track.trimStart;
        return offsetDuration + trackDuration;
      }).reduce((a, b) => a > b ? a : b);
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A), // slightly lighter than black
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(_scrubPosition), //_audioOnly ? _globalAudioClock : _videoPosition),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '/',
              style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.normal),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDuration(overallDuration),
              style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
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

  Future<void> createWaveformData(AudioTrack track, double width) async {
    final sampleCount = PlayerWaveStyle().getSamplesForWidth(width);
    final rawData = await track.waveformController.extractWaveformData(path: track.file.path, noOfSamples: sampleCount);
    setState(() {
      track.normWaveformData = normalizeWaveform(rawData);
    });
  }

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

  Widget _buildWaveformWithTrim(int index, AudioTrack track, Duration fullDuration) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double boxWidth = constraints.maxWidth;
        final double paddingH = 10.0;
        final double effectiveWidth = boxWidth - (2 * paddingH);
        final double totalMs = fullDuration.inMilliseconds.toDouble();

        if (totalMs <= 0) {
          return SizedBox(width: boxWidth, height: 80.0);
        }

        final ValueNotifier<double> trimStartNotifier = ValueNotifier(track.trimStart.inMilliseconds.toDouble());
        final ValueNotifier<double> trimEndNotifier = ValueNotifier(track.trimEnd.inMilliseconds.toDouble());

        // if(track.normWaveformData.isEmpty) {
        //   createWaveformData(track, boxWidth);
        // }
        if (!track.didExtractWaveform) {
          track.didExtractWaveform = true; // guard so we only ever do it once
          final samples = PlayerWaveStyle().getSamplesForWidth(boxWidth);
          // initialize it cuz on android it takes a long time to extract waveformdata
          track.normWaveformData = List<double>.filled(samples, 1.0, growable: false);
          track.waveformController.extractWaveformData(path: track.file.path, noOfSamples: samples).then((raw) {
            setState(() {
              if (Platform.isAndroid) {
                final shaped = resampleLinear(raw, samples);
                track.normWaveformData = normalizeWaveform(shaped);
              } else {
                track.normWaveformData = normalizeWaveform(raw);
              }
            });
          }).catchError((e) {
            print("Waveform extraction failed: $e");
          });
        }

        return ValueListenableBuilder<double>(
          valueListenable: trimStartNotifier,
          builder: (context, trimStartMs, child) {
            return ValueListenableBuilder<double>(
              valueListenable: trimEndNotifier,
              builder: (context, trimEndMs, child) {
                final double trimmedDurationMs = trimEndMs - trimStartMs;
                return SizedBox(
                  height: 80,
                  width: boxWidth,
                  child: Stack(
                    children: [
                      // ✅ Waveform
                      Positioned.fill(
                        // left: 0,//paddingH,
                        // top: 0,
                        // width: effectiveWidth,
                        // height: 80,
                        child: AudioFileWaveforms(
                          // key: ValueKey(track.file.path + String(track.normWaveformData.hashCode)),
                          key: ValueKey('${track.file.path}_${track.normWaveformData.hashCode}'),
                          size: Size(effectiveWidth, 80),
                          waveformData: track.normWaveformData, // NEW CHANGE
                          playerController: track.waveformController,
                          continuousWaveform: false,
                          enableSeekGesture: false,
                          waveformType: WaveformType.fitWidth,
                          playerWaveStyle: const PlayerWaveStyle(seekLineColor: Color(0xFF888888), showSeekLine: false),
                        ),
                      ),
                      // seek line for waveform
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _WaveformSeekLinePainter(
                            // videoPosition: _audioOnly ? _globalAudioClock : _videoPosition, // big change
                            audioPosition: track.currentPosition,
                            trimStart: track.trimStart,
                            trimEnd: track.trimEnd,
                            totalAudioDuration: fullDuration,
                            lineColor: Color.fromARGB(255, 255, 255, 255),
                          ),
                        ),
                      ),
                      // ✅ Left shading (Before Trim Start)
                      Positioned(
                        left: 0, //paddingH,
                        top: 0,
                        bottom: 0,
                        width: effectiveWidth * (trimStartMs / totalMs),
                        child: Container(color: Colors.black.withOpacity(0.3)),
                      ),

                      // ✅ Right shading (After Trim End)
                      Positioned(
                        left: paddingH + effectiveWidth * (trimEndMs / totalMs),
                        top: 0,
                        bottom: 0,
                        right: 0, //paddingH,
                        child: Container(color: Colors.black.withOpacity(0.3)),
                      ),

                      // ✅ Trim Start Handle
                      _buildTrimHandle(
                        left: paddingH + (effectiveWidth * (trimStartMs / totalMs)),
                        onDragUpdate: (dx) {
                          double newTrimStart = trimStartMs + (dx / effectiveWidth) * totalMs;
                          newTrimStart = newTrimStart.clamp(0, trimEndMs - 100);

                          // // --- SNAP LOGIC START ---
                          // // Compute current seek‐line X within this trimmed waveform
                          // final effectiveTimeMs = (_videoPosition.inMilliseconds - (track.offset * 1000)).clamp(0, trimmedDurationMs);
                          // final double seekX = paddingH + effectiveWidth * ((trimStartMs + effectiveTimeMs) / totalMs);
                          // final double handleX = paddingH + effectiveWidth * (newTrimStart / totalMs);
                          // if ((handleX - seekX).abs() < _trimSnapPx) {
                          //   newTrimStart = ((seekX - paddingH) / effectiveWidth) * totalMs;
                          // }
                          // // --- SNAP LOGIC END ---

                          trimStartNotifier.value = newTrimStart;
                          track.trimStart = Duration(milliseconds: newTrimStart.round());

                          final effectivePos = _calculateEffectiveAudioPositionForTrack(
                            track,
                            _globalAudioClock,
                          ); //or _scrubPosition
                          JuceAudioEngine.seek(index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        },
                      ),

                      // ✅ Trim End Handle
                      _buildTrimHandle(
                        left: paddingH + (effectiveWidth * (trimEndMs / totalMs)),
                        onDragUpdate: (dx) {
                          double newTrimEnd = trimEndMs + (dx / effectiveWidth) * totalMs;
                          newTrimEnd = newTrimEnd.clamp(trimStartMs + 100, totalMs);

                          // // --- SNAP LOGIC START ---
                          // final effectiveTimeMs = (_videoPosition.inMilliseconds - (track.offset * 1000)).clamp(0, trimmedDurationMs);
                          // final double seekX = paddingH
                          //   + effectiveWidth * ((trimStartMs + effectiveTimeMs) / totalMs);
                          // final double handleX = paddingH + effectiveWidth * (newTrimEnd / totalMs);
                          // if ((handleX - seekX).abs() < _trimSnapPx) {
                          //   newTrimEnd = ((seekX - paddingH) / effectiveWidth) * totalMs;
                          // }
                          // // --- SNAP LOGIC END ---

                          trimEndNotifier.value = newTrimEnd;
                          track.trimEnd = Duration(milliseconds: newTrimEnd.round());

                          final effectivePos = _calculateEffectiveAudioPositionForTrack(
                            track,
                            _globalAudioClock,
                          ); //or _scrubPosition
                          JuceAudioEngine.seek(index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTrimHandle({required double left, required Function(double) onDragUpdate}) {
    return Positioned(
      left: left - 10,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          onDragUpdate(details.delta.dx);
        },
        onHorizontalDragEnd: (details) {
          // ✅ Immediately refresh UI when user stops dragging
          setState(() {});
        },
        child: Container(width: 20, height: 80, color: Color(0x80B03A2E)),
      ),
    );
  }

  // 2. Progress and error handling methods
  void _showProgress(String message) {
    if (mounted) {
      setState(() {
        _progressMessage = message;
        _showProgressDialog = true;
        _downloadProgress = 0.0;
      });
    }
  }

  void _updateDownloadProgress(int bytesReceived, [int? totalBytes]) {
    if (mounted) {
      setState(() {
        if (totalBytes != null) {
          _downloadProgress = bytesReceived / totalBytes;
        }
        _progressMessage = "Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%";
      });
    }
  }

  void _hideProgress() {
    if (mounted) {
      setState(() {
        _showProgressDialog = false;
        _downloadProgress = 0.0;
      });
    }
  }

  void _showError(String message) {
    _hideProgress();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
    }
    print("Error: $message");
  }

  void _showOpenSettingsPrompt() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Bluetooth Required"),
        content: Text("Please enable Bluetooth to connect to your instrument"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(L10n.translate(context, 'Cancel'))),
          // TextButton(
          //   onPressed: () {
          //     Navigator.pop(context);
          //     FlutterBluePlus.openBluetoothSettings();
          //   },
          //   child: Text("Open Settings"),
          // ),
        ],
      ),
    );
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
    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/mixroom_rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    // 5) Start JUCE recording (NEW)
    final ok = await JuceAudioEngine.startRecording(
      filePath,
      _selectedChannelStart,
      2, //_selectedChannelCount, TODO: (TEMP TO ALLOW NANOCORTEX RECORDING)
    );

    print("printing $_selectedChannelStart $_selectedChannelCount");

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start recording')));
      return;
    }

    // 6) UI state (UNCHANGED)
    setState(() {
      _recordingFilePath = filePath;
      _recordingWallClockStart = DateTime.now();
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

    final recordedPath = _recordingFilePath;
    if (recordedPath == null || !File(recordedPath).existsSync()) {
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

    // final appDocs = await getApplicationDocumentsDirectory();
    // final processedPath = '${appDocs.path}/mixroom_rec_processed_${DateTime.now().millisecondsSinceEpoch}.wav';

    // setState(() {
    //   _isRecording = false;
    //   _recordingFilePath = processedPath; //recordedPath;
    // });

    final appDocs = await getApplicationDocumentsDirectory();
    final processedPath = '${appDocs.path}/mixroom_rec_processed_${DateTime.now().millisecondsSinceEpoch}.wav';

    // ACTUALLY CREATE THE FILE
    // await FFmpegKit.execute(
    //   '-y -i "$recordedPath" "$processedPath"',
    // );
    await File(recordedPath).copy(processedPath);

    setState(() {
      _isRecording = false;
      _recordingFilePath = processedPath;
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
          file: File(processedPath), //recordedPath),
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

  Future<void> _startRecording() async {
    // 1) Require an armed row
    if (_recordRow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Select a track to record on first.'),
        ), //L10n.translate(context, 'Select a track to record on first.'))),
      );
      return;
    }

    // 2) Mic permission
    final hasPerm = await _micRecorder.hasPermission();
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Microphone permission is required to record.'),
        ), //L10n.translate(context, 'Microphone permission is required to record.'))),
      );
      return;
    }

    // 3) Determine where in the project we start recording
    _recordingStartMs = _globalAudioClock.inMilliseconds.toDouble();

    // 4) If not already playing, start playback from current position
    if (!_isPlaying) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!); // this sets _isPlaying = true and starts automation
    }

    // 5) Prepare file path
    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/mixroom_rec_${DateTime.now().millisecondsSinceEpoch}.m4a'; // should be wav?

    // 6) Start recorder (48 kHz, AAC)
    // await _micRecorder.start(
    //   path: filePath,
    //   encoder: AudioEncoder.aacLc,
    //   bitRate: 128000,
    //   samplingRate: 48000,
    // );

    await _micRecorder.start(const RecordConfig(), path: filePath);

    // 7) Listen to amplitude for live preview (simple peak list 0..1)
    _amplitudeSub?.cancel();
    _recordingPeaks = [];
    _amplitudeSub = _micRecorder.onAmplitudeChanged(const Duration(milliseconds: 50)).listen((amp) {
      // amp.current is in dBFS, approx [-160..0], we map ~[-45..0] → [0..1]
      final normalized = (((amp.current ?? -45.0) + 45.0) / 45.0).clamp(0.0, 1.0);
      setState(() {
        _recordingPeaks.add(normalized);
      });
    });

    setState(() {
      _recordingFilePath = filePath;
      _recordingWallClockStart = DateTime.now();
      _isRecording = true;
    });
  }

  Future<void> _stopRecording({bool keepPlaying = true}) async {
    if (!_isRecording) return;

    _amplitudeSub?.cancel();
    _amplitudeSub = null;

    String? recordedPath;
    try {
      recordedPath = await _micRecorder.stop();
    } catch (e) {
      debugPrint("Recorder stop error: $e");
    }

    if (recordedPath == null || !File(recordedPath).existsSync()) {
      setState(() {
        _isRecording = false;
        _recordingPeaks = [];
        _recordingFilePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording failed or no data captured.'),
        ), //L10n.translate(context, 'Recording failed or no data captured.'))),
      );
      return;
    }

    final int? row = _recordRow;
    final double startMs = _recordingStartMs;

    setState(() {
      _isRecording = false;
      _recordingPeaks = [];
      _recordingFilePath = recordedPath;
    });

    // 1) Insert the recorded clip into the project using your existing pipeline
    try {
      // await _addAudioTrackFromFile(
      //   File(recordedPath),
      //   row ?? 0,
      //   startMs,
      // );

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
          file: File(recordedPath),
          row: row ?? 0,
          timeMs: startMs,
        ),
      );
    } catch (e) {
      debugPrint("Error adding recorded track: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add recorded track.'),
        ), //L10n.translate(context, 'Failed to add recorded track.'))),
      );
    }

    // 2) Optionally stop playback too (if user pressed pause/record)
    if (!keepPlaying && _isPlaying) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!);
    }
  }

  // DEPRECATED
  // Instead of the deprecated single-audio _pickAudioFile, use _addAudioTrack.
  Future<void> _addAudioTrack() async {
    _pausePlayback();
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      setState(() {
        _isLoadingAudio = true;
      });

      final newFile = File(result.files.single.path!);
      // final newPlayer = AudioPlayer();
      // NEW

      // TODO: figure out if there's setup required for juce like below
      // await newPlayer.setAudioContext(AudioContext(
      //   android: AudioContextAndroid(
      //     usageType: AndroidUsageType.media,
      //     contentType: AndroidContentType.music,
      //     audioFocus: AndroidAudioFocus.none, // because of android vid play issue
      //     isSpeakerphoneOn: true, // because of android vid play issue
      //   ),
      // ));

      // make it always 48k sample rate
      final tmpDir = await getTemporaryDirectory();
      final baseName = newFile.path.split('/').last;
      // final resampledPath = '${tmpDir.path}/$baseName';

      final baseNameNoExt = baseName.contains('.') ? baseName.substring(0, baseName.lastIndexOf('.')) : baseName;
      final resampledPath = '${tmpDir.path}/$baseNameNoExt.wav';

      // 1) Transcode to 48 kHz PCM WAV (fast, one‐time cost):
      await FFmpegKit.execute(
        '-i "${newFile.path}" -ar 48000 -y "$resampledPath"', // DO .WAV
      );
      final newFile_48 = File(resampledPath);

      // await newPlayer.setSourceDeviceFile(newFile.path);
      // final dur = await newPlayer.getDuration() ?? Duration.zero;

      // await JuceAudioEngine.loadTrack(_audioTracks.length, newFile_48.path);
      await JuceAudioEngine.loadClip(_audioTracks.length, _selectedRow, newFile_48.path);

      // final dur = await JuceAudioEngine.getTrackDuration(0);
      final durSeconds = await JuceAudioEngine.getTrackDuration(_audioTracks.length);
      final dur = Duration(milliseconds: (durSeconds * 1000).round());

      final newController = PlayerController();
      await newController.preparePlayer(path: newFile_48.path);

      // Create a new AudioTrack instance with a fixed audioDuration.
      final newTrack = await AudioTrack.create(
        file: newFile_48,
        originalFile: newFile_48,
        // player: newPlayer,
        waveformController: newController,
        audioDuration: dur, // Fixed duration for this track.
        trimStart: Duration.zero,
        trimEnd: dur,
        offset: 0.0,
        crossfade: 1.0,
        rowIndex: _selectedRow,
      );

      _startWaveformExtraction(newTrack);

      // Listen to the player's position to pause it when trimEnd is reached.
      // NOTE: THIS WAS INTENDED TO UPDATE CURRENTPOS SO THAT SEEK LINES PROGRESS BASED ON THIS VAL
      // newPlayer.onPositionChanged.listen((position) {
      //   setState(() {
      //     newTrack.currentPosition = position;
      //   });
      //   if (_isPlaying && position >= newTrack.trimEnd) {
      //     newPlayer.pause();
      //   }
      // });

      setState(() {
        newTrack.offset = _globalAudioClock.inMilliseconds.toDouble() / 1000.0; // place it where the playhead is
        _audioTracks.add(newTrack);
        _isLoadingAudio = false;
      });
      _updateOverallDurationIfNeeded();
    }
  }

  // this executes a deep copy, which is inefficient for a DAW
  // do a shallow copy in JUCE layer later
  Future<void> _addAudioTrackFromFile(
    File fromFile,
    int row,
    double timeMs, {
    Duration? trimStartRequested,
    Duration? trimEndRequested,
  }) async {
    _pausePlayback();
    setState(() {
      _isLoadingAudio = true;
    });

    final newFile = fromFile; //File(result.files.single.path!);

    // make it always 48k sample rate
    final tmpDir = await getTemporaryDirectory();
    final baseName = newFile.path.split('/').last;
    // final resampledPath = '${tmpDir.path}/$baseName';

    final baseNameNoExt = baseName.contains('.') ? baseName.substring(0, baseName.lastIndexOf('.')) : baseName;
    final resampledPath = '${tmpDir.path}/$baseNameNoExt.wav';

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

    // is this necessary anymore?
    // TODO: might be deprecated
    final newController = PlayerController();
    await newController.preparePlayer(path: newFile_48.path);

    // Create a new AudioTrack instance with a fixed audioDuration.
    final newTrack = await AudioTrack.create(
      file: newFile_48,
      originalFile: newFile_48,
      // player: newPlayer,
      waveformController: newController,
      audioDuration: dur, // Fixed duration for this track.
      trimStart: Duration.zero,
      trimEnd: dur,
      offset: 0.0, // TODO: set this to the current playheadMs if you want it to spawn where track is now
      crossfade: 1.0,
      rowIndex: row,
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

  void _startWaveformExtraction(AudioTrack c) async {
    if (!c.didExtractWaveform) {
      c.didExtractWaveform = true;

      final durMs = c.audioDuration.inMilliseconds;
      final durSec = (durMs / 1000.0).clamp(0.001, double.infinity);

      // final target = (durSec * kWaveformSPS).round().clamp(kMinSamples, kMaxSamples);
      //TODO: THIS IS TEMPORARY, FIGURE OUT HOW TO GET HI-RES EXTRACTWAVEFORM TO NOT BLOCK UI
      final target = 1200;

      // initialize placeholder with zeros so it looks neutral (flat line)
      c.normWaveformData = List<double>.filled(target, 0.0, growable: false);

      c.waveformController.extractWaveformData(path: c.file.path, noOfSamples: target).then((raw) {
        // raw is arbitrary scale; normalize to [-1..1]
        // don't normalize, but amplify
        final norm = amplifyAndCapWaveform(raw); //normalizeWaveform(raw);
        setState(() {
          c.normWaveformData = norm;
        });
      }).catchError((e) {
        debugPrint("Waveform extraction failed: $e");
      });
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
        // _stopTicker();
        for (var track in _audioTracks) {
          track.waveformController.dispose();
        }
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

  Widget _buildFloatingTransportBar() {
    final theme = Theme.of(context);

    // stuff for audio-only
    Duration overallDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      overallDuration = _audioTracks.map((track) {
        final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
        final trackDuration = track.trimEnd - track.trimStart;
        return offsetDuration + trackDuration;
      }).reduce((a, b) => a > b ? a : b);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _audioOnlyOverallDuration = overallDuration;
      });
    });

    // return Positioned(
    //   bottom: 24,
    //   left: 16,
    //   right: 16,
    // child: ClipRRect(
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 13, 13, 13).withOpacity(0.75),
            // borderRadius: BorderRadius.circular(35),
            // border: Border.all(
            //   color: const Color.fromARGB(255, 39, 39, 39), // Or adjust to your desired grey
            //   width: 1.5,
            // ),
          ),
          child: Row(
            children: [
              // Play/Pause button
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: _togglePlayPause,
              ),

              // Restart button
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  _restartAudio(_audioEditorStateSetter!);
                },
              ),
            ],
          ),
        ),
      ),
    );
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
                        timeMs: 0.0, // TODO: maybe make this equal to the current playhead Ms instead of start
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

  Future<double?> getVideoDurationSeconds(String path) async {
    final session = await FFprobeKit.execute('-v quiet -print_format json -show_format "$path"');

    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) {
      final output = await session.getOutput();
      if (output != null && output.isNotEmpty) {
        final jsonMap = jsonDecode(output);
        final format = jsonMap['format'];
        if (format != null && format['duration'] != null) {
          return double.tryParse(format['duration']);
        }
      }
    }
    return null;
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

  Widget _buildMasterRackContent() {
    const double volumeContentHeight = 200.0;

    // 💡 Max height for the Effects tab. The content will scroll inside this.
    const double effectsMaxHeight = 400.0;
    return DefaultTabController(
      length: 2,
      child: Builder(
        // <-- Use Builder to access the TabController
        builder: (BuildContext context) {
          final TabController? tabController = DefaultTabController.of(context);
          final double currentHeight = tabController?.index == 0 ? volumeContentHeight : effectsMaxHeight;
          print(currentHeight);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tabs
              Container(
                decoration: BoxDecoration(color: const Color(0xFF252B3A), borderRadius: BorderRadius.circular(12)),
                child: TabBar(
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(text: "Volume"),
                    Tab(text: "Effects"),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Content (scrollable)
              SizedBox(
                height: currentHeight,
                child: TabBarView(children: [_buildMasterVolumePage(), _buildMasterEffectsPage()]),
              ),
            ],
          );
        },
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

                final choice = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF0C1A32),
                    title: const Text("Save project?", style: TextStyle(color: Colors.white)),
                    content: const Text("Do you want to save before leaving?", style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, "cancel"), child: const Text("Cancel")),
                      TextButton(onPressed: () => Navigator.pop(context, "nosave"), child: const Text("Don't Save")),
                      ElevatedButton(onPressed: () => Navigator.pop(context, "save"), child: const Text("Save")),
                    ],
                  ),
                );

                _isDialogOpen = false;

                if (choice == "cancel" || choice == null) return;

                if (choice == "save") {
                  await _saveProject();
                }

                // If new project and user chose don't save and nothing was ever saved -> delete project folder
                if (choice == "nosave" && !_everSaved) {
                  try {
                    await ProjectManager.deleteProject(_projectDir);
                  } catch (_) {}
                }

                if (mounted) {
                  // Dispose resources before navigating
                  _pausePlayback();
                  for (var track in _audioTracks) {
                    track.waveformController.dispose();
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

  Widget _roundIconButton({required IconData icon, String? label, VoidCallback? onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
        ],
      ],
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Text(text),
      );

  Widget _transportBtn(IconData icon, {VoidCallback? onTap, String? label, bool primary = false}) {
    final bg = primary ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.12);
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 40,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ],
    );
    return child;
  }

  void _handleCopyClip(int clipIndex) {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;
    final clip = _audioTracks[clipIndex];

    setState(() {
      _copiedAudioFile = clip.originalFile; // just remember the file for now
      _copiedTrimStart = clip.trimStart;
      _copiedTrimEnd = clip.trimEnd;
    });
  }

  Future<void> _handleDeleteClip(int clipIndex) async {
    if (clipIndex < 0 || clipIndex >= _audioTracks.length) return;

    final clip = _audioTracks[clipIndex];

    // track.audioStartTimer?.cancel();
    // track.waveformController.dispose();

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
          required File file,
          required int row,
          required double timeMs,
          required Duration trimStartRequested,
          required Duration trimEndRequested,
        }) =>
            _addAudioTrackFromFile(
          file,
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
    _undoManager
        .clear(); // NOTE: this means deleting a track deletes all undo history. can delete this if that's not desired

    Future.delayed(Duration(milliseconds: 50), () {
      setState(() {}); // force a repaint
    });
  }

  Future<void> _handlePasteClipAt(int row, double timeMs) async {
    if (_copiedAudioFile == null) return;

    // await _addAudioTrackFromFile(_copiedAudioFile!, row, timeMs,
    //     trimStartRequested: _copiedTrimStart, trimEndRequested: _copiedTrimEnd);
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
          trimStartRequested: _copiedTrimStart,
          trimEndRequested: _copiedTrimEnd,
        ),
        tracks: _audioTracks,
        file: _copiedAudioFile!,
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
                                  // waveform extract now handled on addAudioTrack once
                                  // if (!c.didExtractWaveform) {
                                  //   c.didExtractWaveform = true;

                                  //   final durMs = c.audioDuration.inMilliseconds;
                                  //   final durSec = (durMs / 1000.0).clamp(0.001, double.infinity);
                                  //   final target = (durSec * kWaveformSPS).round().clamp(kMinSamples, kMaxSamples);

                                  //   // initialize placeholder with zeros so it looks neutral (flat line)
                                  //   c.normWaveformData = List<double>.filled(target, 0.0, growable: false);

                                  //   c.waveformController
                                  //       .extractWaveformData(
                                  //     path: c.file.path,
                                  //     noOfSamples: target,
                                  //   )
                                  //       .then((raw) {
                                  //     // raw is arbitrary scale; normalize to [-1..1]
                                  //     final norm = normalizeWaveform(raw);
                                  //     setState(() {
                                  //       c.normWaveformData = norm;
                                  //     });
                                  //   }).catchError((e) {
                                  //     debugPrint("Waveform extraction failed: $e");
                                  //   });
                                  // }
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
                                      oldOffset: oo,
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
                                hasCopiedClip: _copiedAudioFile != null,
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
            if (_isLoadingVideo || _isLoadingAudio || _isLoadingNextScreen)
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

class _CapsuleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final bool filled;
  final double size; // square icon container
  final double radius;

  const _CapsuleButton({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.filled = false,
    this.size = 40,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final base = filled ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.06);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                // soft outer
                BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6)),
                // subtle top highlight
                const BoxShadow(color: Color(0x22FFFFFF), blurRadius: 0, spreadRadius: 1, offset: Offset(0, -1)),
              ],
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label!, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.75), height: 1.0)),
          ],
        ],
      ),
    );
  }
}

class _VerticalDividerThin extends StatelessWidget {
  const _VerticalDividerThin({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.10)],
        ),
      ),
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

class _WaveformSeekLinePainter extends CustomPainter {
  _WaveformSeekLinePainter({
    required this.audioPosition, // ← pass in effectiveAudioPos
    required this.trimStart,
    required this.trimEnd,
    required this.totalAudioDuration,
    required this.lineColor,
  });

  final Duration audioPosition;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration totalAudioDuration;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0;

    // First, compute how far into the trimmed region our audioPosition is,
    // clamped between trimStart and trimEnd:
    if (audioPosition < trimStart || audioPosition > trimEnd) {
      return; // nothing to draw if outside the trimmed range
    }

    // Map [trimStart .. trimEnd] → [0.0 .. 1.0]
    final trimmedDuration = trimEnd - trimStart;
    final normalized = (audioPosition - trimStart).inMilliseconds / trimmedDuration.inMilliseconds;

    // Compute X in the total waveform:
    final trimStartRatio = trimStart.inMilliseconds / totalAudioDuration.inMilliseconds;
    final trimEndRatio = trimEnd.inMilliseconds / totalAudioDuration.inMilliseconds;

    final waveformStartX = size.width * trimStartRatio;
    final waveformEndX = size.width * trimEndRatio;

    final seekX = waveformStartX + (waveformEndX - waveformStartX) * normalized;
    canvas.drawLine(Offset(seekX, 0), Offset(seekX, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformSeekLinePainter old) {
    return old.audioPosition != audioPosition ||
        old.trimStart != trimStart ||
        old.trimEnd != trimEnd ||
        old.totalAudioDuration != totalAudioDuration ||
        old.lineColor != lineColor;
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

class VolumeAutomationWidget extends StatefulWidget {
  final List<AutomationPoint> automationPoints;
  final double currentNormalizedTime; // normalized current playback time (0.0 to 1.0)
  final ValueChanged<List<AutomationPoint>> onAutomationChanged;

  const VolumeAutomationWidget({
    Key? key,
    required this.automationPoints,
    required this.currentNormalizedTime,
    required this.onAutomationChanged,
  }) : super(key: key);

  @override
  _VolumeAutomationWidgetState createState() => _VolumeAutomationWidgetState();
}

class _VolumeAutomationWidgetState extends State<VolumeAutomationWidget> {
  late List<AutomationPoint> _points;
  static const double _autoSnapNorm = 0.02;
  @override
  void initState() {
    super.initState();
    // Create a copy so we can modify it.
    _points = List.from(widget.automationPoints);
  }

  @override
  void didUpdateWidget(covariant VolumeAutomationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.automationPoints != oldWidget.automationPoints) {
      setState(() {
        _points = List.from(widget.automationPoints);
      });
    }
  }

  void _addPoint(Offset localPosition, double width, double height) {
    double x = (localPosition.dx / width).clamp(0.0, 1.0);
    double volume = _interpolateVolume(x);
    setState(() {
      _points.add(AutomationPoint(x: x, volume: volume));
      _points.sort((a, b) => a.x.compareTo(b.x));
    });
    widget.onAutomationChanged(_points);
  }

  double _interpolateVolume(double x) {
    if (_points.isEmpty) return 1.0;
    if (x <= _points.first.x) return _points.first.volume;
    if (x >= _points.last.x) return _points.last.volume;
    for (int i = 0; i < _points.length - 1; i++) {
      if (x >= _points[i].x && x <= _points[i + 1].x) {
        double t = (x - _points[i].x) / (_points[i + 1].x - _points[i].x);
        return _points[i].volume + t * (_points[i + 1].volume - _points[i].volume);
      }
    }
    return 1.0;
  }

  Widget _buildDraggableHandle(AutomationPoint point, double width, double height) {
    const double visibleHandleSize = 24;
    const double hitBoxSize = 48;

    const double edgeExtension = 16; // How much extra space to provide at the edges

    double hitBoxLeft = point.x * width - hitBoxSize / 2;
    double hitBoxTop = (1 - point.volume) * height - hitBoxSize / 2;

    // Adjust positioning for the first (left edge) and last (right edge) points
    if (point == _points.first) {
      hitBoxLeft = -edgeExtension;
    } else if (point == _points.last) {
      hitBoxLeft = width - hitBoxSize + edgeExtension;
    }

    return Positioned(
      left: hitBoxLeft,
      top: hitBoxTop,
      width: hitBoxSize,
      height: hitBoxSize,
      child: Listener(
        // Use Listener instead of RawGestureDetector
        onPointerMove: (PointerMoveEvent event) {
          setState(() {
            double newVolume = point.volume - event.delta.dy / height;
            newVolume = newVolume.clamp(0.0, 1.0);
            point.volume = newVolume;

            // Update horizontal position if needed
            if (point != _points.first && point != _points.last) {
              double newX = point.x + event.delta.dx / width;
              int index = _points.indexOf(point);
              double leftLimit = _points[index - 1].x + 0.01;
              double rightLimit = _points[index + 1].x - 0.01;
              point.x = newX.clamp(leftLimit, rightLimit);
            }

            // snap to seek line
            double seekNorm = widget.currentNormalizedTime;
            if ((point.x - seekNorm).abs() < _autoSnapNorm) {
              point.x = seekNorm;
            }
          });
          widget.onAutomationChanged(_points);
        },
        child: Center(
          child: GestureDetector(
            onLongPress: () {
              if (point != _points.first && point != _points.last) {
                setState(() => _points.remove(point));
                widget.onAutomationChanged(_points);
              }
            },
            child: Container(
              width: visibleHandleSize,
              height: visibleHandleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (point == _points.first || point == _points.last)
                    ? const Color(0xFF888888)
                    : const Color(0xFF2E61A5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        return GestureDetector(
          onLongPressStart: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPos = box.globalToLocal(details.globalPosition);
            _addPoint(localPos, width, height);
          },
          child: Stack(
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: _AutomationPainter(points: _points, currentNormalizedTime: widget.currentNormalizedTime),
              ),
              for (var point in _points) _buildDraggableHandle(point, width, height),
            ],
          ),
        );
      },
    );
  }
}

class _AutomationPainter extends CustomPainter {
  final List<AutomationPoint> points;
  final double currentNormalizedTime;
  _AutomationPainter({required this.points, required this.currentNormalizedTime});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    Paint linePaint = Paint()
      ..color = Color(0xFF888888)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    // Draw the automation curve.
    Path path = Path();
    final first = points.first;
    path.moveTo(first.x * size.width, (1 - first.volume) * size.height);
    for (var point in points.skip(1)) {
      path.lineTo(point.x * size.width, (1 - point.volume) * size.height);
    }
    canvas.drawPath(path, linePaint);

    // Optionally fill under the curve.
    Paint fillPaint = Paint()
      ..color = Color(0x33888888)
      ..style = PaintingStyle.fill;
    Path fillPath = Path.from(path);
    fillPath.lineTo(points.last.x * size.width, size.height);
    fillPath.lineTo(points.first.x * size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw the seek line (non-interactive).
    double seekX = currentNormalizedTime.isFinite ? currentNormalizedTime * size.width : 0.0;
    Paint seekPaint = Paint()
      ..color = Color(0xFF888888)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(seekX, 0), Offset(seekX, size.height), seekPaint);
  }

  @override
  bool shouldRepaint(covariant _AutomationPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.currentNormalizedTime != currentNormalizedTime;
  }
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

// EFFECTS DRAWER START

class EffectsDrawer extends StatefulWidget {
  final int trackIndex;
  final String mode;
  const EffectsDrawer({Key? key, required this.trackIndex, this.mode = "Basic"}) : super(key: key);

  @override
  _EffectsDrawerState createState() => _EffectsDrawerState();
}

class _EffectsDrawerState extends State<EffectsDrawer> {
  List<String> _effects = [];
  List<bool> _bypassed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEffects();
  }

  Future<void> _loadEffects() async {
    final names = await JuceAudioEngine.getTrackEffects(widget.trackIndex);
    final bypassStates = await Future.wait(
      List.generate(names.length, (index) async {
        return await JuceAudioEngine.getPluginBypassState(widget.trackIndex, index);
      }),
    );
    setState(() {
      _effects = List<String>.from(names);
      _bypassed = List<bool>.from(bypassStates);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.primaryColor;

    if (_loading) {
      return SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, ctrl) => NotificationListener<ScrollNotification>(
        onNotification: (_) => true, // prevents bubbling up
        child: SingleChildScrollView(
          controller: ctrl,
          primary: false, // IMPORTANT: prevents gesture hijack
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Grab Handle ---
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),

                Center(
                  child: Text(
                    "${L10n.translate(context, 'Track')} #${widget.trackIndex + 1} ${L10n.translate(context, 'Effects')}",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 24),

                Text(L10n.translate(context, 'Presets'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildPresetChip("Concert Hall"),
                    _buildPresetChip("Echoes"),
                    _buildPresetChip("LoFi Effect"),
                    _buildPresetChip("Heavy Crunch"),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Reorderable List ---
                ReorderableListView(
                  scrollController: ctrl,
                  // buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,

                  children: [for (int i = 0; i < _effects.length; i++) _buildEffectTile(i)],

                  proxyDecorator: (child, index, animation) =>
                      Material(elevation: 6, color: const Color.fromARGB(154, 130, 130, 130), child: child),

                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < 0 || oldIndex >= _effects.length) return;
                    if (newIndex > oldIndex) newIndex--;
                    newIndex = newIndex.clamp(0, _effects.length - 1);

                    await JuceAudioEngine.reorderEffects(widget.trackIndex, oldIndex, newIndex);
                    setState(() {
                      final name = _effects.removeAt(oldIndex);
                      final bypass = _bypassed.removeAt(oldIndex);
                      _effects.insert(newIndex, name);
                      _bypassed.insert(newIndex, bypass);
                    });
                  },
                ),

                if (_effects.length < 5) Padding(padding: const EdgeInsets.only(top: 8), child: _buildAddTile()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = []; //['LoFi Effect', 'Heavy Crunch'];
    final isLocked = widget.mode == 'Basic' && lockedPresets.contains(name);

    return ActionChip(
      backgroundColor: isLocked
          ? const Color.fromARGB(255, 61, 61, 61) // dimmed if locked
          : const Color.fromARGB(255, 122, 122, 122),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.translate(context, name),
            style: TextStyle(
              color: isLocked ? const Color.fromARGB(255, 122, 122, 122) : const Color.fromARGB(255, 255, 255, 255),
            ),
          ),
          if (isLocked)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock, size: 16, color: Color.fromARGB(255, 122, 122, 122)),
            ),
        ],
      ),
      onPressed: isLocked ? () {} : () => handlePresetLoading(context, name),
    );
  }

  void handlePresetLoading(BuildContext context, String presetName) async {
    final description = () {
      switch (presetName) {
        case 'Concert Hall':
          return L10n.translate(context, 'Applies wide reverb and subtle EQ to simulate a live concert space.');
        case 'Echoes':
          return L10n.translate(context, 'Applies reverb and delay to give an echo effect.');
        case 'LoFi Effect':
          return L10n.translate(context, 'Applies filters and soft distortion for a vintage, relaxed vibe.');
        case 'Heavy Crunch':
          return L10n.translate(context, 'Crushes sound with heavy distortion.');
        default:
          return "${L10n.translate(context, 'This will replace your current effects with ')}'$presetName'.";
      }
    }();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.translate(context, presetName)),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.translate(context, 'Cancel'), style: TextStyle(color: Color.fromARGB(255, 218, 218, 218))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, true);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              // 1. Remove all effects (if any) on the current track
              while (_effects.isNotEmpty) {
                await JuceAudioEngine.removeEffect(widget.trackIndex, 0);
                setState(() {
                  _effects.removeAt(0);
                  _bypassed.removeAt(0);
                });
              }

              // 2. have a switch case thing to do "stuff" for each preset name
              switch (presetName) {
                case 'Concert Hall':
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom Reverb');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Room Size', 53);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Mix', 20);
                  break;

                case 'Echoes':
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom Reverb');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Room Size', 40);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Mix', 20);
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom Delay');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Delay Time', 400);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Feedback', 30);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Mix', 30);
                  break;

                case 'LoFi Effect':
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom EQ');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'LPF Frequency', 2600.0);
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom Distortion');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Drive', 50);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Mix', 85);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Anger', 1);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'LPF Frequency', 2800.0);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 1, 'Distortion Type', "Mode 3");
                  break;

                case 'Heavy Crunch':
                  await JuceAudioEngine.insertEffect(widget.trackIndex, 'Mixroom Distortion');
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Drive', 100);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Mix', 100);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Anger', 1);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Volume', 12);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Pre Shape', 3.0);
                  await JuceAudioEngine.setEffect(widget.trackIndex, 0, 'Distortion Type', "Mode 3");
                  break;

                default:
                  print('⚠️ No matching preset logic for: $presetName');
              }
              await _loadEffects();

              // Dismiss loading modal
              Navigator.of(context).pop();
            },
            child: Text(L10n.translate(context, 'Load Preset')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      print('✅ Loaded preset: $presetName');
    }
  }

  Widget _buildEffectTile(int idx) {
    return ReorderableDragStartListener(
      key: ValueKey("effect_$idx"),
      index: idx,
      child: ListTile(
        contentPadding: EdgeInsets.all(0),
        key: ValueKey("effect_$idx"),
        leading: const Icon(Icons.drag_handle),
        title: Text(_effects[idx]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bypass toggle
            Switch(
              value: !_bypassed[idx],
              onChanged: (active) {
                final shouldBypass = !active;
                JuceAudioEngine.bypassPlugin(widget.trackIndex, idx, shouldBypass);
                setState(() => _bypassed[idx] = shouldBypass);
              },
              activeColor: const Color.fromARGB(255, 231, 231, 231), // thumb color when ON
              inactiveThumbColor: const Color.fromARGB(255, 186, 186, 186), // thumb color when OFF
              inactiveTrackColor: const Color.fromARGB(255, 235, 235, 235), // track color when OFF
              activeTrackColor: const Color.fromARGB(255, 54, 54, 54), // track color when ON
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color.fromARGB(255, 255, 164, 164)),
              onPressed: () => _confirmRemove(idx),
            ),
          ],
        ),
        onTap: () => _openPluginParams(idx),
      ),
    );
    // return ListTile(
    //   contentPadding: EdgeInsets.all(0),
    //   key: ValueKey("effect_$idx"),
    //   leading: const Icon(Icons.drag_handle),
    //   title: Text(_effects[idx]),
    //   trailing: Row(
    //     mainAxisSize: MainAxisSize.min,
    //     children: [
    //       // Bypass toggle
    //       Switch(
    //         value: !_bypassed[idx],
    //         onChanged: (active) {
    //           final shouldBypass = !active;
    //           JuceAudioEngine.bypassPlugin(
    //             widget.trackIndex,
    //             idx,
    //             shouldBypass,
    //           );
    //           setState(() => _bypassed[idx] = shouldBypass);
    //         },
    //       ),
    //       // Delete button
    //       IconButton(
    //         icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
    //         onPressed: () => _confirmRemove(idx),
    //       ),
    //     ],
    //   ),
    //   onTap: () => _openPluginParams(idx),
    // );
  }

  Widget _buildAddTile() => ListTile(
        contentPadding: EdgeInsets.all(0),
        key: const ValueKey("add_effect"),
        leading: const Icon(Icons.add_circle_outline),
        title: Text(L10n.translate(context, 'Add Effect')),
        onTap: _showAddEffectModal,
      );

  Future<void> _confirmRemove(int idx) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.translate(context, 'Delete Effect?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.translate(context, 'Cancel'), style: TextStyle(color: Color.fromARGB(255, 218, 218, 218))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete'), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await JuceAudioEngine.removeEffect(widget.trackIndex, idx);
      setState(() {
        _effects.removeAt(idx);
        _bypassed.removeAt(idx);
      });
    }
  }

  // Inside your EffectsDrawer:
  // Future<void> _showAddEffectModal() async {
  //   final plugins = await JuceAudioEngine.scanPlugins();
  //   showDialog(
  //     context: context,
  //     builder: (_) => AlertDialog(
  //       title: Text("Add Effect"),
  //       content: SizedBox(
  //         width: double.maxFinite,
  //         height: 300,
  //         child: ListView(
  //           children: plugins.map((meta) {
  //             final name = meta['name'] ?? meta['id'] ?? '';
  //             final path = meta['id'] ?? '';
  //             return ListTile(
  //               title: Text(name),
  //               onTap: () async {
  //                 Navigator.pop(context); // close dialog
  //                 await JuceAudioEngine.insertEffect(widget.trackIndex, path);
  //                 await _loadEffects();
  //               },
  //             );
  //           }).toList(),
  //         ),
  //       ),
  //     ),
  //   );
  // }
  Future<void> _showAddEffectModal() async {
    final plugins = await JuceAudioEngine.scanPlugins();
    const allowedInBasic = ['Mixroom Reverb', 'Mixroom EQ', 'Mixroom Delay', 'Mixroom Distortion', 'Mixroom De-Esser'];

    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color.fromARGB(255, 79, 79, 79),
            titlePadding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
            contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: TabBar(
              labelColor: Color.fromARGB(255, 255, 255, 255),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Color.fromARGB(255, 255, 255, 255),
              indicatorWeight: 2,
              tabs: [
                Tab(text: 'Mixroom FX'),
                Tab(text: L10n.translate(context, 'On Device')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: TabBarView(
                children: [
                  ListView(
                    children: [
                      'Mixroom Reverb',
                      'Mixroom EQ',
                      'Mixroom Delay',
                      'Mixroom Distortion',
                      'Mixroom De-Esser'
                    ].map((name) {
                      final isAllowed = widget.mode == 'Pro' || allowedInBasic.contains(name);
                      return GestureDetector(
                        onTap: isAllowed
                            ? () async {
                                Navigator.pop(context);
                                await JuceAudioEngine.insertEffect(widget.trackIndex, name);
                                await _loadEffects();
                              }
                            : null,
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            title: Text(name),
                            trailing: isAllowed ? null : const Icon(Icons.lock, size: 18, color: Colors.white70),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  ListView(
                    children: plugins.map((meta) {
                      final name = meta['name'] ?? meta['id'] ?? '';
                      final path = meta['id'] ?? '';
                      return ListTile(
                        title: Text(name),
                        onTap: () async {
                          Navigator.pop(context); // close dialog
                          await JuceAudioEngine.insertEffect(widget.trackIndex, path);
                          await _loadEffects();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPluginParams(int idx) async {
    var params = await JuceAudioEngine.getPluginParameters(widget.trackIndex, idx);

    // Limit what parameters are shown if it's basic mode
    if (widget.mode == "Basic") {
      switch (_effects[idx]) {
        case 'Mixroom Reverb':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Room Size', 'Mix'].contains(name);
          }).toList();
          break;

        case 'Mixroom EQ':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return [
              'HPF Frequency',
              'Band 1 Gain',
              'Band 2 Gain',
              'Band 3 Gain',
              'Band 4 Gain',
              'LPF Frequency',
            ].contains(name); //['HPF Frequency', 'HPF Slope', 'LPF Frequency', 'LPF Slope'].contains(name);
          }).toList();
          break;

        case 'Mixroom Delay':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Delay Time', 'Feedback', 'Mix'].contains(name);
          }).toList();
          break;
      }
    }

    showModalBottomSheet(
      context: context,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8, // Max 70% height
        // minHeight: MediaQuery.of(context).size.height * 0.4, // Min 40% height
      ),
      isScrollControlled: true,
      backgroundColor: const Color.fromARGB(255, 74, 74, 74),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (_effects[idx] == 'Mixroom EQ') {
              // Lookup expected params
              final pHPF = _paramByName(params, 'HPF Frequency');
              final pLPF = _paramByName(params, 'LPF Frequency');
              final pB1 = _paramByName(params, 'Band 1 Gain');
              final pB2 = _paramByName(params, 'Band 2 Gain');
              final pB3 = _paramByName(params, 'Band 3 Gain');
              final pB4 = _paramByName(params, 'Band 4 Gain');

              // Fallback to generic UI if essentials missing
              // if (pHPF == null || pLPF == null) {
              //   return _buildGenericParamsUI(ctx, idx, params);
              // }

              // Values for preview
              final hpfHz = (pHPF!['value'] as num).toDouble();
              final lpfHz = (pLPF!['value'] as num).toDouble();
              final bandGains = [
                (pB1?['value'] as num?)?.toDouble() ?? 0,
                (pB2?['value'] as num?)?.toDouble() ?? 0,
                (pB3?['value'] as num?)?.toDouble() ?? 0,
                (pB4?['value'] as num?)?.toDouble() ?? 0,
              ];
              final bandFreqs = [60.0, 400.0, 2000.0, 8000.0]; // your defaults

              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(height: 16),
                        Text('Mixroom EQ', style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Divider(color: Color.fromARGB(213, 104, 104, 104)),

                        // Preview with bands
                        _EqPreviewFull(hpfHz: hpfHz, lpfHz: lpfHz, bandGains: bandGains, bandFreqs: bandFreqs),
                        const SizedBox(height: 16),

                        // Sliders row
                        SizedBox(
                          height: _eqRowHeight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (pHPF != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'HPF\nFreq',
                                    value: (pHPF['value'] as num).toDouble(),
                                    min: (pHPF['min'] as num).toDouble(),
                                    max: (pHPF['max'] as num).toDouble(),
                                    logarithmic: true,
                                    unit: 'Hz',
                                    onChanged: (v) {
                                      setModalState(() => pHPF['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pHPF['name'] as String, v);
                                    },
                                  ),
                                ),
                              if (pB1 != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'Band1\nGain',
                                    value: (pB1['value'] as num).toDouble(),
                                    min: (pB1['min'] as num).toDouble(),
                                    max: (pB1['max'] as num).toDouble(),
                                    unit: 'dB',
                                    onChanged: (v) {
                                      setModalState(() => pB1['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pB1['name'] as String, v);
                                    },
                                  ),
                                ),
                              if (pB2 != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'Band2\nGain',
                                    value: (pB2['value'] as num).toDouble(),
                                    min: (pB2['min'] as num).toDouble(),
                                    max: (pB2['max'] as num).toDouble(),
                                    unit: 'dB',
                                    onChanged: (v) {
                                      setModalState(() => pB2['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pB2['name'] as String, v);
                                    },
                                  ),
                                ),
                              if (pB3 != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'Band3\nGain',
                                    value: (pB3['value'] as num).toDouble(),
                                    min: (pB3['min'] as num).toDouble(),
                                    max: (pB3['max'] as num).toDouble(),
                                    unit: 'dB',
                                    onChanged: (v) {
                                      setModalState(() => pB3['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pB3['name'] as String, v);
                                    },
                                  ),
                                ),
                              if (pB4 != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'Band4\nGain',
                                    value: (pB4['value'] as num).toDouble(),
                                    min: (pB4['min'] as num).toDouble(),
                                    max: (pB4['max'] as num).toDouble(),
                                    unit: 'dB',
                                    onChanged: (v) {
                                      setModalState(() => pB4['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pB4['name'] as String, v);
                                    },
                                  ),
                                ),
                              if (pLPF != null)
                                Expanded(
                                  child: _verticalFader(
                                    context: ctx,
                                    label: 'LPF\nFreq',
                                    value: (pLPF['value'] as num).toDouble(),
                                    min: (pLPF['min'] as num).toDouble(),
                                    max: (pLPF['max'] as num).toDouble(),
                                    logarithmic: true,
                                    unit: 'Hz',
                                    onChanged: (v) {
                                      setModalState(() => pLPF['value'] = v);
                                      JuceAudioEngine.setEffect(widget.trackIndex, idx, pLPF['name'] as String, v);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const Divider(color: Color.fromARGB(213, 104, 104, 104)),
                        const SizedBox(height: 16),
                        TextButton(
                          child: Text(
                            'Close',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              );
            }

            // END HERE
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    // crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _effects[idx], //L10n.translate(context, 'Parameters'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Color.fromARGB(213, 104, 104, 104)),

                      // Parameter controls
                      for (var param in params) ...[
                        if (param['type'] == 'float') ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(param['name'] as String, style: Theme.of(context).textTheme.bodyLarge),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    // 1) min label
                                    Text(
                                      (param['min'] as num).toDouble().toStringAsFixed(2),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 8),

                                    // 2) the slider with value indicator
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          showValueIndicator: ShowValueIndicator.always,
                                          valueIndicatorTextStyle: TextStyle(
                                            color: const Color.fromARGB(255, 0, 0, 0),
                                            fontSize: 12,
                                          ),
                                        ),
                                        child: Slider(
                                          value: (param['value'] as num).toDouble().clamp(
                                                (param['min'] as num).toDouble(),
                                                (param['max'] as num).toDouble(),
                                              ),
                                          min: (param['min'] as num).toDouble(),
                                          max: (param['max'] as num).toDouble(),
                                          divisions: 100, // or compute a sensible number
                                          label: (param['value'] as num).toDouble().toStringAsFixed(2),
                                          onChanged: (v) {
                                            setModalState(() => param['value'] = v);
                                            // final min = (param['min'] as num).toDouble();
                                            // final max = (param['max'] as num).toDouble();
                                            // final normalized = ((v - min) / (max - min)).clamp(0.0, 1.0);
                                            // print("value: ${v} normalized: ${normalized}");
                                            JuceAudioEngine.setEffect(
                                              widget.trackIndex,
                                              idx,
                                              param['name'] as String,
                                              v, //normalized, //v,
                                            );
                                          },
                                          onChangeEnd: (v) => {}, // originally put JuceAudioEngine.setEffect here
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // 3) max label
                                    Text(
                                      (param['max'] as num).toDouble().toStringAsFixed(2),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ] else if (param['type'] == 'bool') ...[
                          SwitchListTile(
                            title: Text(param['name'] as String),
                            value: param['value'] as bool,
                            onChanged: (v) => setModalState(() {
                              param['value'] = v;
                              JuceAudioEngine.setEffect(widget.trackIndex, idx, param['name'] as String, v);
                            }),
                          ),
                        ] else if (param['type'] == 'choice') ...[
                          (() {
                            final keys = param.keys.where((k) => k.startsWith('choice_')).toList()
                              ..sort((a, b) {
                                final ai = int.parse(a.split('_')[1]);
                                final bi = int.parse(b.split('_')[1]);
                                return ai.compareTo(bi);
                              });
                            // 2) build the labels
                            final choices = keys.map((k) => param[k] as String).toList();
                            // 3) current
                            final current = param['value'] as String;
                            // 4) render a ListTile that pops a dialog
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(param['name'] as String),
                                trailing: Text(current, style: Theme.of(context).textTheme.bodyLarge),
                                onTap: () async {
                                  final picked = await showDialog<String>(
                                    context: context,
                                    useRootNavigator: true,
                                    builder: (ctx) => SimpleDialog(
                                      title: Text("${L10n.translate(context, 'Select ')}${param['name']}"),
                                      children: choices.map((c) {
                                        return SimpleDialogOption(
                                          child: Text(c),
                                          onPressed: () => Navigator.pop(ctx, c),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                  if (picked != null) {
                                    setModalState(() => param['value'] = picked);
                                    JuceAudioEngine.setEffect(widget.trackIndex, idx, param['name'] as String, picked);
                                  }
                                },
                              ),
                            );
                          })(),
                        ] else ...[
                          ListTile(title: Text(param['name'] as String), trailing: Text("${param['value']}")),
                        ],
                      ],

                      const Divider(color: Color.fromARGB(213, 104, 104, 104)),
                      const SizedBox(height: 16),
                      TextButton(
                        child: Text(
                          L10n.translate(context, 'Close'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGenericParamsSheet(BuildContext ctx, StateSetter setModalState, List params, int idx) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(L10n.translate(context, 'Parameters'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Divider(color: Color.fromARGB(213, 104, 104, 104)),
              // 🔁 your existing loop:
              for (var param in params) ...[
                if (param['type'] == 'float') ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(param['name'] as String, style: Theme.of(ctx).textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              (param['min'] as num).toDouble().toStringAsFixed(2),
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(ctx).copyWith(
                                  showValueIndicator: ShowValueIndicator.always,
                                  valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontSize: 12),
                                ),
                                child: Slider(
                                  value: (param['value'] as num).toDouble().clamp(
                                        (param['min'] as num).toDouble(),
                                        (param['max'] as num).toDouble(),
                                      ),
                                  min: (param['min'] as num).toDouble(),
                                  max: (param['max'] as num).toDouble(),
                                  divisions: 100,
                                  label: (param['value'] as num).toDouble().toStringAsFixed(2),
                                  onChanged: (v) {
                                    setModalState(() => param['value'] = v);
                                    JuceAudioEngine.setEffect(widget.trackIndex, idx, param['name'] as String, v);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (param['max'] as num).toDouble().toStringAsFixed(2),
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (param['type'] == 'bool') ...[
                  SwitchListTile(
                    title: Text(param['name'] as String),
                    value: param['value'] as bool,
                    onChanged: (v) {
                      setModalState(() => param['value'] = v);
                      JuceAudioEngine.setEffect(widget.trackIndex, idx, param['name'] as String, v);
                    },
                  ),
                ] else if (param['type'] == 'choice') ...[
                  (() {
                    final keys = param.keys.where((k) => k.startsWith('choice_')).toList()
                      ..sort((a, b) => int.parse(a.split('_')[1]).compareTo(int.parse(b.split('_')[1])));
                    final choices = keys.map((k) => param[k] as String).toList();
                    final current = param['value'] as String;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(param['name'] as String),
                        trailing: Text(current, style: Theme.of(ctx).textTheme.bodyLarge),
                        onTap: () async {
                          final picked = await showDialog<String>(
                            context: ctx,
                            useRootNavigator: true,
                            builder: (dCtx) => SimpleDialog(
                              title: Text("${L10n.translate(context, 'Select ')}${param['name']}"),
                              children: choices.map((c) {
                                return SimpleDialogOption(child: Text(c), onPressed: () => Navigator.pop(dCtx, c));
                              }).toList(),
                            ),
                          );
                          if (picked != null) {
                            setModalState(() => param['value'] = picked);
                            JuceAudioEngine.setEffect(widget.trackIndex, idx, param['name'] as String, picked);
                          }
                        },
                      ),
                    );
                  })(),
                ] else ...[
                  ListTile(title: Text(param['name'] as String), trailing: Text("${param['value']}")),
                ],
              ],
              const Divider(color: Color.fromARGB(213, 104, 104, 104)),
              const SizedBox(height: 16),
              TextButton(
                child: Text(
                  L10n.translate(context, 'Close'),
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Sizes for the vertical faders/rows (tweak to taste) ----
const double _eqFaderHeight = 160;
const double _eqRowHeight = _eqFaderHeight + 60; // space for labels above/below

Map<String, dynamic>? _paramByName(List params, String name) {
  for (final p in params) {
    if ((p['name']?.toString() ?? '') == name) return p as Map<String, dynamic>;
  }
  return null;
}

double _toLogPos(double v, double min, double max) {
  // guard
  final lo = (min <= 0) ? 1.0 : min;
  final hi = (max <= lo) ? lo + 1.0 : max;
  final vv = v.clamp(lo, hi).toDouble();
  final lm = math.log(lo), lM = math.log(hi);
  return (math.log(vv) - lm) / (lM - lm);
}

double _fromLogPos(double t, double min, double max) {
  final lo = (min <= 0) ? 1.0 : min;
  final hi = (max <= lo) ? lo + 1.0 : max;
  final lm = math.log(lo), lM = math.log(hi);
  return math.exp(lm + (lM - lm) * t.clamp(0.0, 1.0));
}

String _fmtHz(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000.0;
    // 1 decimal up to 9.9k, then integer
    return k < 10 ? '${k.toStringAsFixed(1)}k' : '${k.toStringAsFixed(0)}k';
  }
  return hz.toStringAsFixed(hz < 100 ? 1 : 0);
}

Widget _slopePicker({
  required BuildContext ctx,
  required String title,
  required List<String> choices,
  required String current,
  required void Function(String) onPick,
  bool compact = false,
}) {
  if (choices.isEmpty) return const SizedBox.shrink();

  if (compact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 6),
        DropdownButton<String>(
          isExpanded: true,
          value: current.isNotEmpty ? current : choices.first,
          items: choices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) {
            if (v != null) onPick(v);
          },
        ),
      ],
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: Theme.of(ctx).textTheme.bodySmall),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: choices.map((label) {
          final selected = label == current;
          return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onPick(label));
        }).toList(),
      ),
    ],
  );
}

Widget _verticalFader({
  required BuildContext context,
  required String label,
  required double value,
  required double min,
  required double max,
  int? divisions,
  required ValueChanged<double> onChanged,
  String? unit, // e.g. "Hz"
  bool logarithmic = false,
  double width = 56, // 👈 new
}) {
  final pos = logarithmic ? _toLogPos(value, min, max) : ((value.clamp(min, max) - min) / (max - min));

  final labelText = (unit == 'Hz')
      ? '${_fmtHz(value)} Hz'
      : (unit == null ? value.toStringAsFixed(0) : '${value.toStringAsFixed(0)} $unit');

  return SizedBox(
    width: width, // 👈 respect caller width
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(labelText, style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        SizedBox(
          height: _eqFaderHeight,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                showValueIndicator: ShowValueIndicator.never,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: pos,
                min: 0.0,
                max: 1.0,
                divisions: divisions ?? 200,
                onChanged: (p) {
                  final v = logarithmic ? _fromLogPos(p, min, max) : (min + (max - min) * p);
                  onChanged(v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
      ],
    ),
  );
}

/// Simple HPF/LPF curve preview (visual aid; not a DSP analyzer)
class _EqPreview extends StatelessWidget {
  final double hpfHz;
  final double lpfHz;
  final int hpfSlope; // dB/oct (visual hint only)
  final int lpfSlope;

  const _EqPreview({
    super.key,
    required this.hpfHz,
    required this.lpfHz,
    required this.hpfSlope,
    required this.lpfSlope,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0x1A000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33888888)),
      ),
      padding: const EdgeInsets.all(8),
      // Ensure the CustomPaint always has width/height
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _EqPreviewPainter(hpfHz: hpfHz, lpfHz: lpfHz, hpfSlope: hpfSlope, lpfSlope: lpfSlope),
        ),
      ),
    );
  }
}

class _EqPreviewPainter extends CustomPainter {
  final double hpfHz, lpfHz;
  final int hpfSlope, lpfSlope;

  _EqPreviewPainter({required this.hpfHz, required this.lpfHz, required this.hpfSlope, required this.lpfSlope});

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  // If plugin sends normalized 0..1, map to 20..20k perceptually.
  double _normToHz(double v) {
    if (v.isNaN) return _minF;
    if (v >= 0.0 && v <= 1.0) {
      final logMin = math.log(_minF), logMax = math.log(_maxF);
      return math.exp(logMin + (logMax - logMin) * v);
    }
    return v;
  }

  double _log2(num x) => math.log(x) / math.ln2;

  // x-position for a frequency (log scale across the width)
  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF).toDouble();
    final t = (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
    return (t.clamp(0.0, 1.0) as double) * w;
  }

  // Map slope (dB/oct) to transition width in octaves.
  // Steeper slope => smaller width. Tuned for clear visuals.
  double _widthOctavesForSlope(int slopeDbPerOct) {
    if (slopeDbPerOct <= 0) return 1.0;
    final w = 8.0 / slopeDbPerOct; // 6dB→~1.33oct, 12→0.67, 24→0.33, 48→0.17
    return w.clamp(0.15, 1.50);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 1 || h <= 1) return;

    // Baseline axis
    final axis = Paint()
      ..color = const Color(0x55888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);

    // Sanitize / map inputs
    double hpf = _normToHz(hpfHz);
    double lpf = _normToHz(lpfHz);

    // Keep order sensible so passband exists
    if (hpf > lpf) {
      final mid = (hpf + lpf) * 0.5;
      hpf = (mid - 1).clamp(_minF, _maxF);
      lpf = (mid + 1).clamp(_minF, _maxF);
    }
    hpf = hpf.clamp(_minF, _maxF);
    lpf = lpf.clamp(_minF, _maxF);

    // Geometry
    final xHPF = _xForHz(hpf, w);
    final xLPF = _xForHz(lpf, w);

    // Pixels per octave across the canvas
    final totalOct = _log2(_maxF / _minF);
    final pxPerOct = w / totalOct;

    // Transition widths in pixels derived from slopes
    double wHPFpx = pxPerOct * _widthOctavesForSlope(hpfSlope);
    double wLPFpx = pxPerOct * _widthOctavesForSlope(lpfSlope);

    // Ensure transitions fit between HPF and LPF
    final gap = (xLPF - xHPF).clamp(0.0, w);
    final needed = wHPFpx + wLPFpx + 8.0; // +margin
    if (gap < needed && gap > 0) {
      final k = (gap - 8.0) / (wHPFpx + wLPFpx);
      final scale = k.clamp(0.1, 1.0);
      wHPFpx *= scale;
      wLPFpx *= scale;
    }

    // HPF transition start (from floor to passband)
    final xHPF0 = (xHPF - wHPFpx).clamp(0.0, w);
    // LPF transition end (from passband back to floor)
    final xLPF1 = (xLPF + wLPFpx).clamp(0.0, w);

    // Vertical targets
    final floorY = h - 1;
    final passbandY = h * 0.25; // visual "flat" line
    final kneeY = h * 0.20; // slightly above passband for a gentle knee

    // Build a filled polygon for visibility
    final fill = Path()
      ..moveTo(0, floorY)
      ..lineTo(xHPF0, floorY)
      // HPF cubic: floor → knee near cutoff
      ..cubicTo(xHPF0 + (wHPFpx * 0.35), floorY, xHPF - (wHPFpx * 0.15), kneeY, xHPF, passbandY)
      // Flat passband to LPF cutoff
      ..lineTo(xLPF, passbandY)
      // LPF cubic: passband → floor
      ..cubicTo(xLPF + (wLPFpx * 0.15), passbandY, xLPF1 - (wLPFpx * 0.35), floorY, xLPF1, floorY)
      ..lineTo(w, floorY)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0x33B03A2E) // translucent reddish
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(fill, fillPaint);

    // Stroke on top (same geometry but without the bottom edges)
    final stroke = Path()
      ..moveTo(0, floorY)
      ..lineTo(xHPF0, floorY)
      ..cubicTo(xHPF0 + (wHPFpx * 0.35), floorY, xHPF - (wHPFpx * 0.15), kneeY, xHPF, passbandY)
      ..lineTo(xLPF, passbandY)
      ..cubicTo(xLPF + (wLPFpx * 0.15), passbandY, xLPF1 - (wLPFpx * 0.35), floorY, xLPF1, floorY)
      ..lineTo(w, floorY);

    final strokePaint = Paint()
      ..color = const Color(0xFFB03A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(stroke, strokePaint);

    // Markers at exact cutoffs
    final marker = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(xHPF, 0), Offset(xHPF, h), marker);
    canvas.drawLine(Offset(xLPF, 0), Offset(xLPF, h), marker);
  }

  @override
  bool shouldRepaint(covariant _EqPreviewPainter old) {
    return old.hpfHz != hpfHz ||
        old.lpfHz != lpfSlope || // keep repainting on slope change
        old.hpfSlope != hpfSlope ||
        old.lpfSlope != lpfSlope;
  }
}

class _EqPreviewFull extends StatelessWidget {
  final double hpfHz;
  final double lpfHz;
  final List<double> bandGains; // dB values
  final List<double> bandFreqs; // Hz centers

  const _EqPreviewFull({
    super.key,
    required this.hpfHz,
    required this.lpfHz,
    required this.bandGains,
    required this.bandFreqs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0x1A000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33888888)),
      ),
      padding: const EdgeInsets.all(8),
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _EqPreviewFullPainter(hpfHz: hpfHz, lpfHz: lpfHz, bandGains: bandGains, bandFreqs: bandFreqs),
        ),
      ),
    );
  }
}

class _EqPreviewFullPainter extends CustomPainter {
  final double hpfHz, lpfHz;
  final List<double> bandGains;
  final List<double> bandFreqs;

  _EqPreviewFullPainter({required this.hpfHz, required this.lpfHz, required this.bandGains, required this.bandFreqs});

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  double _log2(num x) => math.log(x) / math.ln2;

  // map Hz → log X position
  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF);
    final t = (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
    return (t.clamp(0.0, 1.0)) * w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 1 || h <= 1) return;

    // baseline axis
    final axis = Paint()
      ..color = const Color(0x55888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);

    // clamp hpf/lpf
    double hpf = hpfHz.clamp(_minF, _maxF);
    double lpf = lpfHz.clamp(_minF, _maxF);
    if (hpf >= lpf) {
      final mid = (hpf + lpf) * 0.5;
      hpf = (mid - 1).clamp(_minF, _maxF);
      lpf = (mid + 1).clamp(_minF, _maxF);
    }

    // HPF/LPF markers
    final xHPF = _xForHz(hpf, w);
    final xLPF = _xForHz(lpf, w);
    final marker = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(xHPF, 0), Offset(xHPF, h), marker);
    canvas.drawLine(Offset(xLPF, 0), Offset(xLPF, h), marker);

    // path for overall curve
    final path = Path();
    for (int px = 0; px < w; px++) {
      // frequency at this pixel (log mapped)
      final f = _minF * math.pow(_maxF / _minF, px / w);

      // start flat at 0dB
      double db = 0.0;

      // HPF attenuation
      if (f < hpf) {
        final oct = _log2(hpf / f);
        db -= oct * 12; // 12dB/oct approx
      }

      // LPF attenuation
      if (f > lpf) {
        final oct = _log2(f / lpf);
        db -= oct * 12;
      }

      // Add band gains as bumps
      for (int i = 0; i < bandFreqs.length; i++) {
        final gain = bandGains[i];
        if (gain.abs() < 0.1) continue;

        final fc = bandFreqs[i];
        final q = 1.0; // fixed width for Basic preview
        final bw = fc / q;

        // gaussian-like bump
        final d = (math.log(f / fc) / math.ln2); // distance in octaves
        final shape = math.exp(-(d * d) * 2.0); // narrower = steeper
        db += gain * shape;
      }

      // map dB (-24..+24) to canvas height
      final y = h * 0.5 - (db.clamp(-24.0, 24.0) / 24.0) * (h * 0.4);

      if (px == 0) {
        path.moveTo(px.toDouble(), y);
      } else {
        path.lineTo(px.toDouble(), y);
      }
    }

    // draw fill under curve
    final fillPaint = Paint()
      ..color = const Color(0x33B03A2E)
      ..style = PaintingStyle.fill;
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    // draw stroke curve
    final strokePaint = Paint()
      ..color = const Color(0xFFB03A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _EqPreviewFullPainter old) {
    return old.hpfHz != hpfHz || old.lpfHz != lpfHz || old.bandGains != bandGains;
  }
}

// EFFECTS DRAWER END

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    p.moveTo(size.width / 2, 0);
    p.lineTo(size.width, size.height);
    p.lineTo(0, size.height);
    p.close();

    final paint = Paint()
      ..color = const Color(0xFF1A1F2E)
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(p, paint);
    canvas.drawPath(p, border);
  }

  @override
  bool shouldRepaint(_) => false;
}

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
    track.waveformController.dispose();

    tracks.removeAt(_addedIndex!);
    await JuceAudioEngine.removeTrack(_addedIndex!);
    await JuceAudioEngine.pause();

    _addedTrack = null;
    _addedIndex = null;
  }
}

class DeleteClipAction extends EditorUndoAction {
  final List<AudioTrack> tracks;
  final int originalIndex;

  final Future<void> Function({
    required File file,
    required int row,
    required double timeMs,
    required Duration trimStartRequested,
    required Duration trimEndRequested,
  }) addTrack;

  final VoidCallback onChange;

  // snapshot
  late final File file;
  late final int row;
  late final double timeMs;
  late final Duration trimStart;
  late final Duration trimEnd;

  DeleteClipAction({
    required this.tracks,
    required AudioTrack clip,
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
  String get description => 'Delete clip';

  @override
  Future<void> redo() async {
    final clip = _resolveClip(tracks, originalIndex);
    if (clip == null) return;

    clip.audioStartTimer?.cancel();
    clip.waveformController.dispose();

    tracks.removeAt(originalIndex);
    await JuceAudioEngine.removeTrack(originalIndex);
    await JuceAudioEngine.pause();

    onChange();
  }

  @override
  Future<void> undo() async {
    await addTrack(file: file, row: row, timeMs: timeMs, trimStartRequested: trimStart, trimEndRequested: trimEnd);
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
  String get description => 'Trim clip';

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
  String get description => 'Move clip';

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
    snapshots.add(EffectSnapshot(effects[i], {for (final p in params) p['name']: p['value']}));
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
  }
}

Future<MasterEffectsSnapshot> captureMasterSnapshot() async {
  final effects = await JuceAudioEngine.getMasterEffects();
  final snapshots = <EffectSnapshot>[];

  for (int i = 0; i < effects.length; i++) {
    final params = await JuceAudioEngine.getMasterPluginParameters(i);
    snapshots.add(EffectSnapshot(effects[i], {for (final p in params) p['name']: p['value']}));
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

class _CollapsedChatBar extends StatelessWidget {
  final VoidCallback onTap;
  const _CollapsedChatBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        opacity: 0.10,
        child: Row(
          children: [
            _chatIcon(),
            const SizedBox(width: 10),
            Text('Type...', style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _ExpandedChatBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  const _ExpandedChatBar({super.key, required this.controller, required this.focusNode, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      opacity: 0.14,
      child: Row(
        children: [
          _chatIcon(),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Type...', border: InputBorder.none),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
