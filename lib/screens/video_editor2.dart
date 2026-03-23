import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../helpers/youtube_upload.dart';

import 'package:mixroom/ffmpeg/ffmpeg.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/helpers/audio_export_plan.dart';
import 'package:mixroom/helpers/export_save_dialog.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:mixroom/widgets/side_menu.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:fftea/fftea.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:better_player/better_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:mixroom/screens/home.dart';
import 'package:mixroom/screens/mini_timeline_pro.dart';
import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:mixroom/widgets/export_success_preview_player.dart';

Completer<void> _cancelSignal = Completer();

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

// ----------------- //
// VIDEO EDITOR SCREEN //
// ----------------- //
class VideoEditorScreen2 extends StatefulWidget {
  final String mode;
  final bool? isProEntitled;

  const VideoEditorScreen2({
    Key? key,
    required this.mode,
    this.isProEntitled,
  }) : super(key: key);
  @override
  State<VideoEditorScreen2> createState() => _VideoEditorScreenState2();
}

class _VideoEditorScreenState2 extends State<VideoEditorScreen2>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _subscriptionCapabilityOrLegacy(String capability) {
    try {
      return context.read<EntitlementService>().canUseCapability(capability);
    } catch (_) {
      return widget.mode == 'Pro';
    }
  }

  bool get _isProEntitled {
    final explicit = widget.isProEntitled;
    if (explicit != null) return explicit;
    return _subscriptionCapabilityOrLegacy(SubscriptionCapability.proEditor);
  }

  bool get _isBasicTier => !_isProEntitled;

  String get _resolvedMode => _isProEntitled ? 'Pro' : 'Basic';

  // Video variables
  bool useBetterPlayer = false;
  File? _videoFile;
  VideoPlayerController? _videoController;
  BetterPlayerController? betterController;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;
  Duration _scrubPosition = Duration.zero;
  bool _isScrubbing = false;
  bool _isPlaying = false;

  // Multi-track support
  List<AudioTrack> _audioTracks = []; // ONLY NEED TO USE THIS FOR MULTI-TRACK
  double _universalCrossfade = 0.5;

  // video audio automation
  List<AutomationPoint> videoAudioAutomation = [
    AutomationPoint(x: 0.0, volume: 1.0),
    AutomationPoint(x: 1.0, volume: 1.0),
  ];

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

  late Ticker _ticker;
  Duration _lastKnownPosition = Duration.zero;

  // A timer to update automation and the scrubber in audio-only mode.
  Timer? _audioAutomationTimer;
  Duration _globalAudioClock = Duration.zero;

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

  List<VideoSegment> _segments = [];
  Set<int> _expandedSegments = {};
  bool _isExporting = false;

  bool _showAutomationSection = false;

  bool _audioOnly = true; // initially true as there is no video loaded
  Duration _audioOnlyOverallDuration = Duration.zero;

  static const List<int> _kExportSampleRates = [44100, 48000, 88200, 96000];
  static const List<int> _kExportWavBitDepths = [16, 24, 32];
  static const List<int> _kExportMp3Bitrates = [128, 192, 256, 320];
  static const List<int> _kExportMp3VbrQualities = [0, 2, 4, 6];
  static const List<double> _kExportNormalizeTargetsDb = [-0.3, -1.0, -2.0];

  _AudioExportSettings _audioExportSettings = const _AudioExportSettings(
    format: _ExportAudioFormat.mp3,
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

  final _timelineScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prewarmFFT(); // so that AI sync first run is not heavy
    // Initialize the ticker to update every ~16ms (about 60fps)
    _ticker = createTicker((elapsed) async {
      // Use the elapsed time to compute an interpolated position.
      // For instance, add elapsed to _lastKnownPosition and update UI.
      final interpolatedPosition = _lastKnownPosition + elapsed;
      _updatePosition(interpolatedPosition);
    });
    if (defaultTargetPlatform == TargetPlatform.android) {
      useBetterPlayer =
          false; //TODO: testing, maybe android doesn't need to use this anymore
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _isLoadingNextScreen = true);
      JuceAudioEngine.initialise(); // heavy blocking native call
      JuceAudioEngine.initialiseEventListeners();
      await Future.delayed(const Duration(
          milliseconds: 300)); // so that juce.init doesn't block UI load
      setState(() => _isLoadingNextScreen = false);
    });
  }

  Future<void> _startTicker() async {
    // Stop any previous ticker.
    _ticker.stop();
    // Get the current position from the video controller.
    _lastKnownPosition = _videoPosition; //_videoController!.value.position;
    _ticker.start();
  }

  Future<void> _stopTicker() async {
    _ticker.stop();
  }

  void _updatePosition(Duration position) async {
    // setState(() {
    // Update videoPosition and scrubPosition at a high frequency.
    _videoPosition = position;
    _scrubPosition = position;
    if (position.inMilliseconds > _videoDuration.inMilliseconds) {
      _videoPosition = duration; //position;
      _scrubPosition = duration;
      for (var track in _audioTracks) {
        // track.player.pause();
        track.audioStarted = false;
      }
      JuceAudioEngine.pause();
      // Optionally update _isPlaying state if needed.
      setState(() {
        _isPlaying = false;
      });
      _pausePlayback();
      _stopTicker();
    }
    // });

    if (!_isScrubbing && mounted && _isPlaying) {
      if (betterController?.isVideoInitialized() != null ||
          _videoController!.value.isInitialized) {
        double normalizedTime =
            position.inMilliseconds / duration.inMilliseconds;
        // Compute the volume using your video automation curve (which you store in a variable, e.g., videoAudioAutomation)
        double automationVolume =
            getVolumeForAutomation(videoAudioAutomation, normalizedTime);

        // Combine the crossfade factor and automation volume.
        double finalVolume =
            min(1.0, (1.0 - _universalCrossfade) * 2) * automationVolume;

        // Update video player volume.
        _updateVideoVolume(
          0.0,
        ); // SINCE WE ARE PUTTING VIDEO AUDIO INTO JUCE (MAKE SURE TO EXPORT VIDEO WITH JUCE'S STORED GAIN CORRECTLY on ffmpeg)

        // THIS IS A TEMPORARY MEASURE, WE ASSUME THAT THERE WILL BE ONLY ONE VIDEO (SO PRO MODE WON'T WORK WITH THIS OF COURSE)
        if (_segments.isEmpty) {
          print("ERROR: _segments is empty");
          return;
        }
        JuceAudioEngine.setVideoAudioGain(finalVolume * _segments[0].gain);

        // _updateVideoVolume(finalVolume);
      }

      for (int i = 0; i < _audioTracks.length; i++) {
        final track = _audioTracks[i];
        final seconds = await JuceAudioEngine.getCurrentPosition(i);
        track.currentPosition = Duration(microseconds: (seconds * 1e6).round());

        if (track.currentPosition >= track.trimEnd) {
          await JuceAudioEngine.bypassTrack(i, true);
          continue;
        }

        // NOTE THAT this drift doesn't indicate the true distance between the video
        // and audio because the ticker is slightly off from the video
        // print("drift: ${((_videoPosition - track.currentPosition).inMilliseconds/10).round()/100}");

        final offsetDuration =
            Duration(milliseconds: (track.offset * 1000).toInt());
        if (position >= offsetDuration) {
          // Calculate how far the audio has progressed relative to its trim range.
          final effectiveTime = position - offsetDuration;
          final effectiveDuration = track.trimEnd - track.trimStart;
          double normalizedTime = effectiveDuration.inMilliseconds > 0
              ? effectiveTime.inMilliseconds / effectiveDuration.inMilliseconds
              : 0.0;
          normalizedTime = normalizedTime.clamp(0.0, 1.0);

          // Compute the new volume from the automation curve.
          double newVolume =
              getVolumeForAutomation(track.volumeAutomation, normalizedTime);

          // Optionally, combine this with your universal crossfade if desired.
          // For example, multiply with _universalCrossfade:
          newVolume *= min(1.0, _universalCrossfade * 2);

          // COMMENT OUT BECAUSE WE DO MAKE A NEW MP3 TIME GAIN IS CHANGED
          newVolume *=
              track.gain; // adjust for gain // this should not be above 1.0

          // SETVOLUME (1.0>) LEADS TO BUG IN THIS AUDIO PKG
          // Update the audio track volume.
          if (!_preWarmState) {
            // track.player.setVolume(newVolume);
            JuceAudioEngine.setTrackVolume(i, newVolume);
            //KIND OF BUG WHERE IF YOU SET A TRACK VOLUME BUT YOU DON'T PLAY IT BEFORE EXPORTING, IT WON'T APPLY
          }

          // If the track hasn’t started yet, start it.
          if (!track.audioStarted) {
            continue;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _videoController?.dispose();
    betterController?.dispose();
    for (var track in _audioTracks) {
      // track.player.dispose();
      track.waveformController.dispose();
      track.audioStartTimer?.cancel();
    }
    // JuceAudioEngine.shutdown();
    // print("shutdown called");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (state == AppLifecycleState.resumed) {
        debugPrint("App Resumed on Android - Re-initializing video.");
        _videoController?.dispose();
        if (_videoFile != null) {
          _initializeVideo();
        }
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        debugPrint("App Paused or Inactive on Android - Disposing video.");
        _pausePlayback();
        _stopTicker();
        setState(() {
          _isPlaying = false;
        });
        // _videoController?.pause(); // Optionally pause on leaving
        // _videoController?.dispose();
        // _videoController = null; // Set to null to ensure re-initialization
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (state == AppLifecycleState.paused) {
        _pausePlayback();
        _stopTicker();
        setState(() {
          _isPlaying = false;
        });
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

  // using easy_video_editor package
  Future<Duration?> getVideoDuration(String filePath) async {
    try {
      final metadata =
          await VideoEditorBuilder(videoPath: filePath).getVideoMetadata();
      return Duration(milliseconds: metadata.duration);
    } catch (e) {
      print('Failed to get duration: $e');
      return null;
    }
  }

  Future<void> _pickVideoFile() async {
    // Prevent multiple simultaneous requests
    if (_isPickingFile) return;
    setState(() {
      _isPickingFile = true;
    });

    try {
      setState(() {
        _isLoadingVideo = true;
      });

      String? filePath;
      if (Platform.isIOS) {
        final XFile? pickedFile = await ImagePicker().pickVideo(
          source: ImageSource.gallery, // Direct Photos app access
          maxDuration: Duration(minutes: 15), // LIMIT OF VIDEO DURATION
        );

        if (pickedFile != null) {
          filePath = pickedFile.path;
        }
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          // allowCompression: true,
          // withData: false,
          // allowedExtensions: ['mp4'], // NOTE: if it is .MOV file, it'll be much slower than .mp4 file
        );

        // Handle cancellation or no file selected
        if (result == null || result.files.isEmpty) {
          print("File picker canceled or no file selected.");
          return;
        }

        // Get the selected file path
        filePath = result.files.single.path;
      }

      if (filePath == null) {
        print("Selected file path is null.");
        return;
      }

      // START OF EASY_VIDEO_EDITOR CODE
      // ...
      final fileDuration = await getVideoDuration(filePath);
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/thumb_${filePath.hashCode}.jpg';
      final thumbnailPath = await VideoEditorBuilder(
        videoPath: filePath,
      ).generateThumbnail(
          positionMs: 0,
          quality: 80,
          width: 640,
          height: 360,
          outputPath: outputPath);
      _segments.add(
        VideoSegment(
          path: filePath,
          start: Duration.zero,
          end: fileDuration ?? Duration.zero,
          totalDuration: fileDuration ?? Duration.zero,
          thumbnailPath: thumbnailPath!,
        ),
      );
      setState(() => _isExporting = true);

      File mergedFile;

      final trimmedPaths = <String>[];

      for (int i = 0; i < _segments.length; i++) {
        final tempDir = await getTemporaryDirectory();
        final trimmedOutputPath = '${tempDir.path}/trimmed_$i.mp4';

        final trimmed = await VideoEditorBuilder(videoPath: _segments[i].path)
            .trim(
                startTimeMs: _segments[i].start.inMilliseconds,
                endTimeMs: _segments[i].end.inMilliseconds)
            .export(outputPath: trimmedOutputPath);

        trimmedPaths.add(trimmed!);
      }

      // Build merge editor with the trimmed clips
      final builder = VideoEditorBuilder(videoPath: trimmedPaths.first);
      if (trimmedPaths.length > 1) {
        builder.merge(otherVideoPaths: trimmedPaths.sublist(1));
      }

      var mergedFilePath = await builder.export(onProgress: (_) {});
      mergedFile = File(mergedFilePath!);

      setState(() => _isExporting = false);
      // ...
      // END OF EASY_VIDEO_EDITOR CODE

      // Process the selected video file
      final videoFile = mergedFile; //filePath);
      setState(() {
        _videoFile = videoFile;
      });

      // Initialize video controller with the new file
      await _initializeVideo();
    } catch (e) {
      print("Error picking video file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "${L10n.translate(context, 'Failed to pick video file')}: ${e.toString()}")),
      );
    } finally {
      // Reset the flag
      setState(() {
        _isPickingFile = false;
        _isLoadingVideo = false;
      });
    }
  }

  Future<void> _initializeVideo() async {
    _videoController?.dispose();
    betterController?.dispose();

    if (useBetterPlayer) {
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.file,
        _videoFile!.path,
        cacheConfiguration: BetterPlayerCacheConfiguration(useCache: false),
        // bufferingConfiguration: BetterPlayerBufferingConfiguration(
        //   minBufferMs: 100,
        //   maxBufferMs: 500,
        //   bufferForPlaybackMs: 50,
        //   bufferForPlaybackAfterRebufferMs: 50,
        // ),
      );
      betterController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: false,
          looping: false,
          handleLifecycle: true,
          useRootNavigator: true,
          autoDetectFullscreenDeviceOrientation: true,
          allowedScreenSleep: false,
          fit: BoxFit.fitHeight,
          controlsConfiguration: BetterPlayerControlsConfiguration(
            showControls: false, // 🔑 hides all controls
          ),
          playerVisibilityChangedBehavior: (visibilityFraction) {
            // so that it doesn't pause on background
          },
        ),
        betterPlayerDataSource: dataSource,
      );
      betterController!.setMixWithOthers(true);
    } else {
      _videoController = VideoPlayerController.file(
        _videoFile!,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true, // Prevents audio ducking
        ),
      );
      await _videoController!.initialize();
    }

    // make it always 48k sample rate
    final tmpDir = await getTemporaryDirectory();
    final baseName = _videoFile!.path.split('/').last;
    // final resampledPath = '${tmpDir.path}/$baseName';

    final baseNameNoExt = baseName.contains('.')
        ? baseName.substring(0, baseName.lastIndexOf('.'))
        : baseName;
    final resampledPath = '${tmpDir.path}/$baseNameNoExt.wav';

    // 1) Transcode to 48 kHz PCM WAV (fast, one‐time cost):
    await FFmpegKit.execute(
      '-i "${_videoFile!.path}" -ar 48000 -y "$resampledPath"', // DO .WAV
    );
    final newFile_48 = File(resampledPath);
    await JuceAudioEngine.loadVideoAudio(
      newFile_48.path,
    ); // maybe put in mp3 instead of raw video, but should still work

    if (Platform.isAndroid) {
      _updateVideoVolume(
          0.001); // ← Never zero (did this change because android vid play issue) TODO look into this
    }

    setState(() {
      _audioOnly = false;
    });

    if (!mounted) return;
    setState(() {
      _videoDuration = duration;
      _videoPosition = Duration.zero; //position;
      _scrubPosition = Duration.zero; //position;
    });
    if (_videoDuration == Duration.zero) {
      await Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _videoDuration = duration;
          });
        }
      });
    }
  }

  Future<void> play() async {
    if (useBetterPlayer) {
      await betterController!.play();
    } else {
      await _videoController!.play();
    }
  }

  Future<void> pause() async {
    if (useBetterPlayer) {
      await betterController!.pause();
    } else {
      await _videoController!.pause();
    }
  }

  Future<void> seekTo(Duration position) async {
    if (useBetterPlayer) {
      await betterController!.seekTo(position);
    } else {
      await _videoController!.seekTo(position);
    }
  }

  void _updateVideoVolume(double volume) {
    if (useBetterPlayer) {
      //Platform.isAndroid) {
      betterController?.setVolume(volume);
    } else {
      _videoController?.setVolume(volume);
    }
  }

  Duration get position {
    if (useBetterPlayer) {
      return betterController!.videoPlayerController!.value.position;
    } else {
      return _videoController!.value.position;
    }
  }

  Duration get duration {
    if (useBetterPlayer) {
      return betterController!.videoPlayerController!.value.duration ??
          Duration.zero;
    } else {
      return _videoController!.value.duration;
    }
  }

  double get aspectRatio {
    if (useBetterPlayer) {
      return betterController!.videoPlayerController!.value.aspectRatio;
    } else {
      return _videoController!.value.aspectRatio;
    }
  }

  bool get isPlaying {
    if (useBetterPlayer) {
      return betterController!.videoPlayerController!.value.isPlaying;
    } else {
      return _videoController!.value.isPlaying;
    }
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
    if (_audioOnly) {
      await _togglePlayPauseAudio(_audioEditorStateSetter!);
      return;
    }
    if ((_videoController == null || !_videoController!.value.isInitialized) &&
        betterController == null) return;

    if (_videoPosition.inMilliseconds >= _videoDuration.inMilliseconds) {
      await _restartVideo();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      //TODO: this should work for ios too, but just to be safe. test later on ios with await _resumeplayback to check
      if (Platform.isAndroid) {
        //PRE-WARM TEST (THIS WORKS LOL)
        // await _resumePlayback();
        // _startTicker();

        // await _pausePlayback();
        // _stopTicker();
        await _resumePlayback();
        _startTicker();
      } else {
        _resumePlayback();
        _startTicker();
      }
    } else {
      await _pausePlayback();
      _stopTicker();
    }
  }

  Future<void> _togglePlayPauseAudio(StateSetter setLocalState) async {
    if (_audioTracks.isEmpty) {
      return;
    }

    setLocalState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      JuceAudioEngine.play();
      // Resume playback: do not reset the global clock.
      // For each track, if its offset has been reached, start (or resume) playback.
      for (int i = 0; i < _audioTracks.length; i++) {
        final track = _audioTracks[i];
        final offsetDuration =
            Duration(milliseconds: (track.offset * 1000).round());
        if (_globalAudioClock >= offsetDuration) {
          final effectivePos = _calculateEffectiveAudioPositionForTrack(
              track, _globalAudioClock);
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
      _audioAutomationTimer?.cancel();
      _audioAutomationTimer =
          Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        setLocalState(() {
          _globalAudioClock += const Duration(milliseconds: 50);
        });
        if (_globalAudioClock >= _audioOnlyOverallDuration) {
          await _restartAudio(setLocalState);
          // setLocalState(() {
          //   _isPlaying = true;
          // });
          await _togglePlayPauseAudio(setLocalState);
          return;
        }
        _updateAudioAutomation(_globalAudioClock);
      });
    } else {
      // On pause, cancel the timer, pause each track, and importantly, reset audioStarted.
      _audioAutomationTimer?.cancel();
      for (var track in _audioTracks) {
        // await track.player.pause();
        track.audioStarted =
            false; // Reset flag on pause so that resume triggers play.
      }
      JuceAudioEngine.pause();
    }
  }

  Future<void> _restartAudio(StateSetter setLocalState) async {
    // Pause all tracks and seek them to their trimStart.
    _audioAutomationTimer?.cancel();
    for (int i = 0; i < _audioTracks.length; i++) {
      // await track.player.pause();
      // await track.player.seek(track.trimStart);
      final track = _audioTracks[i];
      track.audioStarted = false;
      track.audioStartTimer?.cancel();
      final effectivePos =
          _calculateEffectiveAudioPositionForTrack(track, Duration.zero);
      JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
      track.currentPosition = Duration.zero;
    }
    JuceAudioEngine.pause();

    // Reset the global audio clock.
    setLocalState(() {
      _globalAudioClock = Duration.zero;
      _isPlaying = false;
    });
  }

  void _updateAudioAutomation(Duration globalClock) {
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      // Convert track.offset (in seconds) to a Duration.
      final offsetDuration =
          Duration(milliseconds: (track.offset * 1000).round());
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

      // Calculate the effective duration of the trimmed portion.
      final effectiveDuration = track.trimEnd - track.trimStart;
      double normalizedTime = effectiveDuration.inMilliseconds > 0
          ? (effectiveAudioPos.inMilliseconds -
                  track.trimStart.inMilliseconds) /
              effectiveDuration.inMilliseconds
          : 0.0;
      normalizedTime = normalizedTime.clamp(0.0, 1.0);

      // Compute the volume from the automation curve.
      final automationVolume =
          getVolumeForAutomation(track.volumeAutomation, normalizedTime);
      final finalVolume =
          automationVolume * min(1.0, _universalCrossfade * 2) * track.gain;
      // track.player.setVolume(finalVolume);
      JuceAudioEngine.setTrackVolume(i, finalVolume);

      // Start the track if the offset has been reached and it hasn't started yet.
      if (globalClock >= offsetDuration && !track.audioStarted) {
        // track.player.seek(effectiveAudioPos);
        JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6);
        // track.player.play(DeviceFileSource(track.file.path));
        JuceAudioEngine.bypassTrack(
            i, false); // TODO: verify that this resumes the track playback
        track.audioStarted = true;
      }
      track.currentPosition = effectiveAudioPos;
    }
  }

  // REWIND: reset video and audio to zero and clear _audioStarted.
  Future<void> _restartVideo() async {
    if ((_videoController == null || !_videoController!.value.isInitialized) &&
        betterController == null) return;

    // Pause video and seek to the start
    await pause();
    await seekTo(Duration.zero);
    await JuceAudioEngine.seekVideoAudio(0.0);
    _stopTicker();

    // Reset audio tracks
    JuceAudioEngine.pause();
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      // Cancel any pending timers
      track.audioStartTimer?.cancel();
      // Mark the track as not started
      track.audioStarted = false;
      final effectivePos =
          _calculateEffectiveAudioPositionForTrack(track, Duration.zero);
      JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
      track.currentPosition = Duration.zero;
    }

    // Update UI state
    setState(() {
      _videoPosition = Duration.zero;
      _scrubPosition = Duration.zero;
      _isPlaying = false;
    });
  }

  Widget _buildTimeDisplay() {
    // if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) {
    //   return const SizedBox.shrink();
    // }

    //stuff for audio-only
    Duration overallDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      overallDuration = _audioTracks.map((track) {
        final offsetDuration =
            Duration(milliseconds: (track.offset * 1000).round());
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
              _formatDuration(_audioOnly ? _globalAudioClock : _videoPosition),
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
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.normal),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDuration(_audioOnly ? overallDuration : duration),
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }

  // SCRUBBER right under the video (unused because this stuff is located elsewhere now)
  // Widget _buildCustomScrubber() {
  //   if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) {
  //     return Container();
  //   }
  //   final maxValue = duration.inMilliseconds.toDouble();
  //   double currentValue = _isScrubbing
  //       ? _scrubPosition.inMilliseconds.toDouble()
  //       : _videoPosition.inMilliseconds.toDouble();
  //   currentValue = currentValue.clamp(0.0, maxValue);
  //   return Column(
  //     children: [
  //       Row(
  //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //         children: [
  //           Text(_formatDuration(_videoPosition)),
  //           Text(_formatDuration(duration)),
  //         ],
  //       ),
  //       // Slider(
  //       //   value: currentValue,
  //       //   min: 0,
  //       //   max: maxValue,
  //       //   onChangeStart: (value) {
  //       //     for (var track in _audioTracks) {
  //       //       track.audioStartTimer?.cancel();
  //       //     }
  //       //     _pausePlayback();
  //       //     _stopTicker();
  //       //     setState(() {
  //       //       _isScrubbing = true;
  //       //       _scrubPosition = Duration(milliseconds: value.toInt());
  //       //     });
  //       //   },
  //       //   onChanged: (value) {
  //       //     setState(() {
  //       //       _scrubPosition = Duration(milliseconds: value.toInt());
  //       //     });
  //       //   },
  //       //   onChangeEnd: (value) async {
  //       //     final newPosition = Duration(milliseconds: value.toInt());
  //       //     setState(() {
  //       //       _isScrubbing = false;
  //       //       _videoPosition = newPosition;
  //       //       _scrubPosition = newPosition;
  //       //     });

  //       //     await seekTo(newPosition);

  //       //     for (int i = 0; i < _audioTracks.length; i++) {
  //       //       final track = _audioTracks[i];
  //       //       final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);

  //       //       await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
  //       //       setState(() {
  //       //         track.currentPosition = effectivePos;
  //       //       });
  //       //     }

  //       //     if(_isPlaying) {
  //       //       _resumePlayback();
  //       //       _startTicker();
  //       //     }
  //       //   },
  //       // ),
  //     ],
  //   );
  // }

  // Pause helper
  Future<void> _pausePlayback() async {
    // Pause video first
    await pause();

    // Pause all audio tracks at precise position
    for (var track in _audioTracks) {
      track.audioStartTimer
          ?.cancel(); // NEED THIS IN CASE THERE WAS A TIMER STARTED
    }
    await JuceAudioEngine.pause();
  }

  // START OF PLAYBACK SYNC FIXES

  // Future<void> waitForBetterPlayerToStart(BetterPlayerController controller) async {
  //   final video = controller.videoPlayerController!;
  //   final Duration startPos = video.value.position;
  //   const int maxWaitMs = 1000;
  //   int waited = 0;

  //   while (waited < maxWaitMs) {
  //     await Future.delayed(const Duration(milliseconds: 10));
  //     waited += 10;

  //     if ((video.value.position - startPos).inMilliseconds > 5) {
  //       return; // Confirmed playback started
  //     }
  //   }
  // }
  Future<void> waitForBetterPlayerToStart(
      BetterPlayerController controller) async {
    final video = controller.videoPlayerController!;
    final Duration startPos = video.value.position;

    while (video.value.position == startPos) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  // Resume helper: resumes video and all audio tracks in unison.
  // Future<void> _resumePlayback() async {
  //   // var videoPosition = _videoPosition;//_videoController!.value.position;
  //   // await seekTo(videoPosition);

  //   // testing to see if doing seek/scrub logic before resume fixes drift
  //   // await seekTo(_videoPosition);

  //   // for (int i = 0; i < _audioTracks.length; i++) {
  //   //   final track = _audioTracks[i];
  //   //   final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _videoPosition);

  //   //   await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
  //   //   track.currentPosition = effectivePos;
  //   // }

  //   // await Future.delayed(const Duration(milliseconds: 100));

  //   await play();
  //   var adjustedVideoPos = _videoPosition; // this is crucial

  //   // HARD-CODED ADJUSTMENT FOR AUDIBLE LAG
  //   // EVEN IF VIDEOPOS AND JUCE GETPOSITION SAYS OTHERWISE, NEEDS THIS TO SOUND IN SYNC
  //   // await Future.delayed(const Duration(milliseconds: 50));

  //   // JuceAudioEngine.play(); redundant since I just bypass tracks below anyways
  //   // Play and sync all audio tracks
  //   for (int i = 0; i < _audioTracks.length; i++) {
  //     final track = _audioTracks[i];
  //     final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
  //     if (adjustedVideoPos >= offsetDuration) {
  //       // Precision seek with compensation
  //       // final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(track, adjustedVideoPos); // GETTING NEW VID POS

  //       if(useBetterPlayer) {
  //         JuceAudioEngine.bypassTrack(i, false);
  //         // JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0
  //         //   ? effectiveAudioPos.inMicroseconds / 1e6
  //         //   : 0.0);
  //         // track.currentPosition = effectiveAudioPos;
  //       }
  //       else {
  //         JuceAudioEngine.bypassTrack(i, false);
  //         // JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0
  //         //   ? effectiveAudioPos.inMicroseconds / 1e6
  //         //   : 0.0);
  //         // track.currentPosition = effectiveAudioPos;
  //       }
  //       track.audioStarted = true;
  //     } else {
  //       JuceAudioEngine.bypassTrack(i, true); // to prevent track from playback when it shouldn't be
  //       final delay = offsetDuration - adjustedVideoPos;
  //       final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(track, adjustedVideoPos);

  //       track.audioStarted = false;
  //       track.audioStartTimer = Timer(delay, () async {

  //         if(useBetterPlayer) {
  //           JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
  //           JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0
  //           ? effectiveAudioPos.inMicroseconds / 1e6
  //           : 0.0);
  //           track.currentPosition = effectiveAudioPos;
  //         }
  //         else {
  //           JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0
  //           ? effectiveAudioPos.inMicroseconds / 1e6
  //           : 0.0);
  //           track.currentPosition = effectiveAudioPos;
  //           JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
  //         }
  //         track.audioStarted = true;
  //       });
  //     }
  //   }
  // }

  Future<void> _resumePlaybackAndroid() async {
    // 0) Clean up: cancel any pending delayed starts from the last run (Android drift culprit)
    for (final t in _audioTracks) {
      t.audioStartTimer?.cancel();
      t.audioStartTimer = null;
      t.audioStarted = false;
    }

    // 1) Seek video to the requested point
    await seekTo(_videoPosition);

    // // 2) Start video and (Android only) wait until position actually advances
    await play();

    // await _waitForVideoToAdvance(); // ~1–2 frames; no logic change, just certainty

    // if(!isPlaying) {
    //   return;
    // }

    // 3) Read the real current video time AFTER start
    final currentVideoPos = await position;

    // 4) Start audio transport; measure monotonic latency (replaces DateTime.now jitter)
    final sw = Stopwatch()..start();
    await JuceAudioEngine.play();
    final latencyCompensation = sw.elapsed;

    // 5) Sync all audio tracks (same logic; tiny timing/ordering fixes only)
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      final offsetDuration =
          Duration(milliseconds: (track.offset * 1000).toInt());

      if (currentVideoPos >= offsetDuration) {
        // Start now
        final effectivePos = _calculateEffectiveAudioPositionForTrack(
          track,
          // your logic: base on current video minus measured start latency
          currentVideoPos - latencyCompensation,
        );

        if (effectivePos >= track.trimEnd) {
          continue; // track is already over
        }

        // Order fix (timing-safe): seek first, then unbypass
        await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
        JuceAudioEngine.bypassTrack(i, false);
        track.audioStarted = true;
      } else {
        // Start later
        JuceAudioEngine.bypassTrack(i, true); // keep muted until offset hits
        final delay = offsetDuration - currentVideoPos;

        track.audioStarted = false;
        track.audioStartTimer = Timer(delay, () async {
          // Re-read video time at the exact fire moment to neutralize Timer jitter
          final vNow = await position;

          // Compute effective position *now* (was computed too early before)
          final eff = _calculateEffectiveAudioPositionForTrack(track, vNow);

          if (eff >= track.trimEnd) {
            // nothing to play
            JuceAudioEngine.bypassTrack(i, true);
            return;
          }

          // Order fix: seek first, then unbypass (same intended behavior)
          await JuceAudioEngine.seek(
              i, eff.inMicroseconds > 0 ? eff.inMicroseconds / 1e6 : 0.0);
          JuceAudioEngine.bypassTrack(i, false);
          track.audioStarted = true;
        });
      }
    }

    _startTicker();
  }

  Future<void> _waitForVideoStart() async {
    // Wait until the video position actually moves a few ms (bounded)
    final start = position;
    const minAdvanceMs = 5; // detect "real start"
    const timeoutMs = 400; // don't block forever
    var waited = 0;
    while (waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 5));
      waited += 10;
      if ((position - start).inMilliseconds > minAdvanceMs) return;
    }
    // If we time out, continue anyway; we'll still re-sync using current position
  }

  Future<void> _resumePlayback() async {
    //PRE-WARM FOR ANDROID
    if (Platform.isAndroid) {}
    // NEW: Seek video to current position to reset its internal clock
    if (Platform.isIOS) {
      await seekTo(_videoPosition);
      await JuceAudioEngine.seekVideoAudio(_videoPosition.inMicroseconds / 1e6);
    }

    // // Get current video position AFTER seek to ensure accuracy
    // final currentVideoPos = position;

    // Play video and wait for it to actually start
    await play();

    // HARD-CODED ADJUSTMENT for iOS
    if (Platform.isIOS) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (Platform.isAndroid) {
      await _waitForVideoStart();
      // think about adding a return if user press pause
      if (!isPlaying) {
        return;
      }
    }

    final currentVideoPos = position;

    await JuceAudioEngine.seekVideoAudio(currentVideoPos.inMicroseconds / 1e6);
    // NEW: Calculate precise time difference between audio and video
    final audioStartTime = DateTime.now();
    await JuceAudioEngine.play(); // Start audio immediately after video

    // Sync all audio tracks
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      final offsetDuration =
          Duration(milliseconds: (track.offset * 1000).toInt());

      if (currentVideoPos >= offsetDuration) {
        // NEW: Calculate precise compensation for playback latency
        final latencyCompensation = Duration
            .zero; //Platform.isAndroid ? Duration(milliseconds: 40) : Duration.zero; //DateTime.now().difference(audioStartTime);
        final effectivePos = _calculateEffectiveAudioPositionForTrack(
          track,
          currentVideoPos + latencyCompensation, //TODO: UNCOMMENT THIS FOR IOS
        );

        // don't do anything if track is over
        if (effectivePos >= track.trimEnd) {
          continue;
        }

        await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
        JuceAudioEngine.bypassTrack(i, false);
        track.audioStarted = true;
      } else {
        JuceAudioEngine.bypassTrack(
            i, true); // to prevent track from playback when it shouldn't be
        final delay = offsetDuration - currentVideoPos;
        final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(
          track,
          currentVideoPos,
        ); // + (Platform.isAndroid ? Duration(milliseconds: 100) : Duration.zero);

        track.audioStarted = false;
        track.audioStartTimer = Timer(delay, () async {
          if (useBetterPlayer) {
            JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
            JuceAudioEngine.seek(
              i,
              effectiveAudioPos.inMicroseconds / 1e6 > 0.0
                  ? effectiveAudioPos.inMicroseconds / 1e6
                  : 0.0,
            );
            track.currentPosition = effectiveAudioPos;
          } else {
            JuceAudioEngine.seek(
              i,
              effectiveAudioPos.inMicroseconds / 1e6 > 0.0
                  ? effectiveAudioPos.inMicroseconds / 1e6
                  : 0.0,
            );
            track.currentPosition = effectiveAudioPos;
            JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
          }
          track.audioStarted = true;
        });
      }
    }

    _startTicker();
  }

  // END OF PLAYBACK SYNC FIXES

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
    if (!_ExportChannelMode.values.contains(selectedChannelMode)) {
      selectedChannelMode = _ExportChannelMode.stereo;
    }
    if (!_ExportResampleQuality.values.contains(selectedResampleQuality)) {
      selectedResampleQuality = _ExportResampleQuality.best;
    }
    if (!_ExportMp3Mode.values.contains(selectedMp3Mode)) {
      selectedMp3Mode = _ExportMp3Mode.cbr;
    }

    return showDialog<_AudioExportSettings>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget buildFormatOption({
              required _ExportAudioFormat format,
              required String label,
              required bool isLeft,
            }) {
              final bool isSelected = selectedFormat == format;
              return Expanded(
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: isLeft ? const Radius.circular(12) : Radius.zero,
                    right: isLeft ? Radius.zero : const Radius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.horizontal(
                      left: isLeft ? const Radius.circular(12) : Radius.zero,
                      right: isLeft ? Radius.zero : const Radius.circular(12),
                    ),
                    onTap: () {
                      setSheetState(() {
                        selectedFormat = format;
                      });
                    },
                    child: SizedBox(
                      height: 50,
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            Widget buildDropdownField<T>({
              required String label,
              required T value,
              required List<T> options,
              required ValueChanged<T?> onChanged,
              required String Function(T) textBuilder,
            }) {
              return DropdownButtonFormField<T>(
                value: value,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem<T>(
                        value: option,
                        child: Text(textBuilder(option)),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Export',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  theme.colorScheme.outline.withOpacity(0.35),
                            ),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.22),
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
                                height: 50,
                                color:
                                    theme.colorScheme.outline.withOpacity(0.25),
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
                            setSheetState(() {
                              showAdvanced = !showAdvanced;
                            });
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
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Icon(showAdvanced
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down),
                              ],
                            ),
                          ),
                        ),
                        if (showAdvanced) ...[
                          const SizedBox(height: 10),
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
                            label: L10n.translate(context, 'Resample quality'),
                            value: selectedResampleQuality,
                            options: _ExportResampleQuality.values,
                            textBuilder: (value) {
                              switch (value) {
                                case _ExportResampleQuality.draft:
                                  return L10n.translate(
                                      context, 'Draft (fast)');
                                case _ExportResampleQuality.good:
                                  return L10n.translate(context, 'Good');
                                case _ExportResampleQuality.best:
                                  return L10n.translate(context, 'Best');
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
                              L10n.translate(context, 'Normalize loudness'),
                            ),
                            value: selectedNormalize,
                            onChanged: (value) {
                              setSheetState(() {
                                selectedNormalize = value;
                              });
                            },
                          ),
                          if (selectedNormalize) ...[
                            const SizedBox(height: 4),
                            buildDropdownField(
                              label: L10n.translate(
                                  context, 'Limiter ceiling (dBTP)'),
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
                          if (selectedFormat == _ExportAudioFormat.wav) ...[
                            buildDropdownField(
                              label: L10n.translate(context, 'Bit depth'),
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
                                L10n.translate(context, 'Enable dithering'),
                              ),
                              value: selectedWavDithering,
                              onChanged: (value) {
                                setSheetState(() {
                                  selectedWavDithering = value;
                                });
                              },
                            ),
                          ] else ...[
                            buildDropdownField(
                              label: L10n.translate(context, 'Encoding mode'),
                              value: selectedMp3Mode,
                              options: _ExportMp3Mode.values,
                              textBuilder: (value) =>
                                  value == _ExportMp3Mode.cbr ? 'CBR' : 'VBR',
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
                                label: L10n.translate(context, 'Bit rate'),
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
                                label: L10n.translate(context, 'VBR quality'),
                                value: selectedMp3VbrQuality,
                                options: _kExportMp3VbrQualities,
                                textBuilder: (value) =>
                                    'V$value (${L10n.translate(context, value == 0 ? "highest" : "smaller file")})',
                                onChanged: (value) {
                                  if (value == null) return;
                                  setSheetState(() {
                                    selectedMp3VbrQuality = value;
                                  });
                                },
                              ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 44,
                          child: FilledButton(
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
                                  normalizeTargetDb: selectedNormalizeTargetDb,
                                  resampleQuality: selectedResampleQuality,
                                ),
                              );
                            },
                            child:
                                Text(L10n.translate(context, 'Start export')),
                          ),
                        ),
                      ],
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

  Future<String> _convertMixWithExportSettings({
    required String inputPath,
    required _AudioExportSettings settings,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.${settings.fileExtension}';

    final ffmpegCmd = AudioExportPlan.buildFfmpegArgs(
      inputPath: inputPath,
      outputPath: outPath,
      format: settings.format.name,
      sampleRate: settings.sampleRate,
      wavBitDepth: settings.wavBitDepth,
      wavDithering: settings.wavDithering,
      mp3BitrateKbps: settings.mp3BitrateKbps,
      mp3Mode: settings.mp3Mode.name,
      mp3VbrQuality: settings.mp3VbrQuality,
      channelMode: settings.channelMode.name,
      normalize: settings.normalize,
      normalizeTargetDb: settings.normalizeTargetDb,
      resampleQuality: settings.resampleQuality.name,
    );

    try {
      final Session session = await FFmpegKit.execute(ffmpegCmd.join(' '));
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogs() ?? [];
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

    // Build input arguments
    List<String> inputArgs = [];
    // for (final track in _audioTracks) {
    //   inputArgs.add('-i "${track.file.path}"');
    // }

    for (int i = 0; i < _audioTracks.length; i++) {
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/juce_track${i}_export.wav';
      final outDir = await JuceAudioEngine.exportTrack(
        i,
        outPath,
        format: 'wav',
        sampleRate: settings.sampleRate,
        wavBitDepth: 32,
        wavDithering: false,
        mp3BitrateKbps: settings.mp3BitrateKbps,
      );
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
        final String volumeAutomationExpression =
            generateVolumeAutomationFilter(
                track, offsetMs, _universalCrossfade);
        volumeFilter =
            'volume=eval=frame:volume="${volumeAutomationExpression}"'; //*${track.gain}"';
      } else {
        volumeFilter =
            'volume=${min(1.0, _universalCrossfade * 2).toStringAsFixed(2)}'; //*${track.gain}';
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
    final String amixInputs = trackLabels.join('') +
        'amix=inputs=${_audioTracks.length}:duration=longest:normalize=0[aout]';
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
      'pcm_f32le',
      '-ar',
      '${settings.sampleRate}',
      '-loglevel',
      'verbose',
      '-y',
    ];

    final tempDir = await getTemporaryDirectory();
    final mixedWavPath =
        '${tempDir.path}/audio_export_mix_${DateTime.now().millisecondsSinceEpoch}.wav';
    ffmpegCmd.add('"$mixedWavPath"');

    // print("FFmpeg command: ${ffmpegCmd.join(' ')}");

    try {
      final session = await FFmpegKit.execute(ffmpegCmd.join(' '));
      final returnCode = await session.getReturnCode();
      final errorLogs = await session.getLogs() ?? [];

      String getLogMessages(List<Log> logs) {
        return logs.map((log) => log.getMessage() ?? "null").join('\n');
      }

      final lastErrorCount = min(10, errorLogs.length);
      final lastErrors =
          errorLogs.sublist(max(0, errorLogs.length - lastErrorCount));
      final lastErrorMessages = getLogMessages(lastErrors);

      print("═════════ LAST ERRORS ═════════");
      print(lastErrorMessages);

      if (ReturnCode.isSuccess(returnCode)) {
        final outFile = File(mixedWavPath);
        int retries = 0;
        while (!await outFile.exists() && retries < 20) {
          await Future.delayed(const Duration(milliseconds: 250));
          retries++;
        }

        if (!await outFile.exists() || (await outFile.length()) < 1000) {
          print("❌ ERROR: Output file is missing or too small!");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(L10n.translate(context,
                    'Export failed: Output file missing or too small.'))),
          );
          return "";
        }

        print("✅ File found: $mixedWavPath");
        onProgress(0.75);
        final convertedPath = await _convertMixWithExportSettings(
          inputPath: mixedWavPath,
          settings: settings,
        );
        onProgress(1.0);
        return convertedPath;
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
          content: Text(
              '${L10n.translate(context, "Export error")}: ${e.toString().split('\n').first}'),
          duration: Duration(seconds: 5),
        ),
      );
    }
    return "";
  }

  Future<String> _exportVideo(ValueChanged<double> onProgress) async {
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L10n.translate(context, 'No video selected'))));
      return "";
    }
    // if (_audioTracks.isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text(L10n.translate(context, 'No audio tracks selected'))),
    //   );
    //   return "";
    // }

    onProgress(0.0);
    if (_cancelSignal.isCompleted) return "";

    // Build FFmpeg input arguments.
    // Use the video file as input 0.

    // final List<String> inputArgs = ['-i "${_videoFile!.path}"'];

    // TODO: change this later to support multiple VIDEO SEGMENT GAINS (diff volumes throughout)
    final tempDir = await getTemporaryDirectory();
    final extractedAudioPath = '${tempDir.path}/video_audio.wav';

    final gain = (_segments.isNotEmpty ? _segments[0].gain : 1.0);
    final double perceptual = (gain * gain).clamp(0.0, 9.0);

    await FFmpegKit.execute(
      '-i "${_videoFile!.path}" -vn -af volume=$perceptual -c:a pcm_f32le -ar 48000 -ac 2 -y "$extractedAudioPath"',
    );

    final List<String> inputArgs = [
      '-i "${_videoFile!.path}"', // input 0 = video only
      '-i "$extractedAudioPath"', // input 1 = clean extracted audio
    ];

    for (int i = 0; i < _audioTracks.length; i++) {
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/juce_track${i}_export.wav';
      final outDir = await JuceAudioEngine.exportTrack(i, outPath);
      print("_exportVideo: track ${i} exported at ${outDir}");
      inputArgs.add('-i "${outDir}"');

      onProgress(((i + 1).toDouble() / _audioTracks.length) * 0.5);
      if (_cancelSignal.isCompleted) return "";
    }
    if (_cancelSignal.isCompleted) return "";

    onProgress(0.6);
    // Get video duration in seconds (for volume automation).
    double videoDurationSec = duration.inSeconds.toDouble();

    // Generate video audio automation filter for input 0.
    // (Assumes you have a variable `videoAudioAutomation` of type List<AutomationPoint>.)
    final String videoAudioFilter = generateVolumeAutomationFilterForVideo(
      videoAudioAutomation,
      videoDurationSec,
      0,
      _universalCrossfade,
    );
    onProgress(0.7);
    // Build filter complex lines.
    final List<String> filterLines = [
      // For video audio (input 0), apply trim and automation filter.
      // '[0:a]atrim=start=0,asetpts=PTS-STARTPTS,volume=eval=frame:volume=${videoAudioFilter}[vid];'
      '[1:a]volume=eval=frame:volume=${videoAudioFilter}[vid];',
    ];

    if (_cancelSignal.isCompleted) return "";

    final List<String> trackLabels = [];
    for (int i = 0; i < _audioTracks.length; i++) {
      final track = _audioTracks[i];
      final int offsetMs = (track.offset * 1000).round();
      final double startSec =
          track.trimStart.inMilliseconds / 1000.0; //track.trimStart.inSeconds;
      final double endSec =
          track.trimEnd.inMilliseconds / 1000.0; //track.trimEnd.inSeconds;
      final String label = 't${i + 2}'; //1}';

      final String volumeAutomation =
          generateVolumeAutomationFilter(track, offsetMs, _universalCrossfade);

      filterLines.add(
        '[${i + 2}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
        'adelay=${offsetMs}|${offsetMs},asetpts=PTS-STARTPTS,'
        'volume=eval=frame:volume=(${volumeAutomation})*(1.0)[$label];', // 1.0 = track.gain
      );

      trackLabels.add('[$label]');
    }
    onProgress(0.8);
    if (_cancelSignal.isCompleted) return "";

    // Mix video audio and additional audio tracks.
    final int totalInputs = 1 + _audioTracks.length; //1 + _audioTracks.length;
    final String amixInputs = '[vid]' +
        trackLabels.join('') +
        'amix=inputs=$totalInputs:duration=first[aout]';
    filterLines.add(amixInputs);

    // print("🔹 FFmpeg Filter Complex:\n${filterLines.join('\n')}");

    final String filterComplex = filterLines.join('');

    setState(() {
      filterString = filterComplex;
    });

    final List<String> ffmpegCmd = [
      ...inputArgs,
      '-filter_complex', '"$filterComplex"',
      '-map', '0:v:0', // Map only the primary video stream
      '-map', '[aout]', // Map the mixed audio output
      '-c:v',
      'copy', // Copy video (no re-encoding) //NOTE: THIS SHOULD BE SAFE I HOPE IT DIDN'T BREAK ANYTHING CUZ IT MAKES IT FAST
      // '-c:v', 'libx264',          // ✅ safe re-encode
      '-c:a', 'aac', // Force AAC for audio
      '-b:a', '128k', // Set audio bitrate
      '-ar', '48000', // Set sample rate to 48000 Hz
      '-movflags', '+faststart',
      '-f', 'mp4',
      '-loglevel', 'verbose',
      '-y',
    ];

    //TODO: TRY THIS TO MAKE IT FASTER
    // final ffmpegCmd = [
    //   ...inputArgs,
    //   '-filter_complex', filterComplex,
    //   '-map', '0:v:0',
    //   '-map', '[aout]',
    //   '-c:v', 'copy',             // 🚀 fastest (no re-encode)
    //   '-c:a', 'aac',
    //   '-b:a', '128k',
    //   '-ar', '48000',
    //   '-movflags', '+faststart',
    //   '-f', 'mp4',
    //   '-loglevel', 'verbose',
    //   '-y',
    // ];
    if (_cancelSignal.isCompleted) return "";

    final tempDir2 = await getTemporaryDirectory();
    final outPath =
        '${tempDir2.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';
    ffmpegCmd.add('"$outPath"');

    // print("🔹 Running FFmpeg command:\n${ffmpegCmd.join(' ')}");

    Session session = await FFmpegKit.execute(ffmpegCmd.join(' '));
    if (_cancelSignal.isCompleted) return "";
    onProgress(1.0);
    final returnCode = await session.getReturnCode();
    final logs = (await session.getAllLogsAsString()) ?? "No logs available.";
    final errorLogs = (await session.getLogsAsString()) ?? "No error logs.";

    // print("🔹 FFmpeg FULL Output Log:\n$logs");
    // print("🔴 FFmpeg ERROR Log:\n$errorLogs");

    if (!ReturnCode.isSuccess(returnCode)) {
      print("❌ FFmpeg export failed.");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
          content:
              Text(L10n.translate(context, 'Export failed! Check logs.'))));
      return "";
    }

    print("✅ FFmpeg export completed successfully.");
    final outFile = File(outPath);
    int retries = 0;
    while (!await outFile.exists() && retries < 20) {
      await Future.delayed(const Duration(milliseconds: 250));
      retries++;
    }

    if (!await outFile.exists() || (await outFile.length()) < 1000) {
      print("❌ ERROR: Output file is missing or too small!");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(
          content: Text('Export failed: Output file missing or too small.')));
      return "";
    }

    print("✅ File found: $outPath");

    return outPath;
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

  // In place of old single-audio UI:
  Widget _buildMultiTrackAudioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "Add Track" button
        // ElevatedButton(
        //   onPressed: _showAudioSourceOptions,
        //   child: Text(L10n.translate(context, 'Add Audio Track')),
        // ),
        // const SizedBox(height: 10),

        // A scrollable list of all tracks
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _audioTracks.length,
          itemBuilder: (context, index) {
            return _buildSingleTrackUI(index);
          },
          padding: EdgeInsets.fromLTRB(0, 0, 0, 20),
        ),
      ],
    );
  }

  bool _expandedIndexMatches(int index) => _expandedTrackIndex == index;
  bool _selectedIndexMatches(int index) => _selectedTrackIndex == index;

  Widget _buildSingleTrackUI(int index) {
    final track = _audioTracks[index];
    final Duration audioPos = track.currentPosition < track.trimStart
        ? track.trimStart
        : (track.currentPosition > track.trimEnd
            ? track.trimEnd
            : track.currentPosition);
    final Duration effectiveDuration = track.trimEnd - track.trimStart;
    final double normalizedTime = effectiveDuration.inMilliseconds > 0
        ? ((audioPos.inMilliseconds - track.trimStart.inMilliseconds) /
                effectiveDuration.inMilliseconds)
            .clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: Colors.grey.shade400,
            width: _selectedTrackIndex == index ? 4 : 1.5),
      ),
      color: const Color.fromARGB(255, 134, 135, 173),
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GestureDetector(
          onTap: () {
            if (!_expandedIndexMatches(index)) {
              setState(() {
                _selectedTrackIndex = _selectedIndexMatches(index) ? -1 : index;
              });
            } else {
              _selectedTrackIndex = index;
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: filename
              GestureDetector(
                onTap: () {
                  if (!_expandedIndexMatches(index)) {
                    _selectedTrackIndex =
                        _selectedIndexMatches(index) ? -1 : index;
                  } else {
                    _selectedTrackIndex = index;
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.music_note,
                        color: Color.fromARGB(255, 230, 230, 230)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${L10n.translate(context, 'Audio')}: ${track.originalFile.path.split('/').last.split('.').first}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_expandedIndexMatches(index)) {
                            // should close
                            _expandedTrackIndex = -1;
                            _selectedTrackIndex = -1;
                          } else {
                            // should open
                            _expandedTrackIndex = index;
                            _selectedTrackIndex = index;
                          }
                        });
                      },
                      child: Icon(
                        _expandedIndexMatches(index)
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Waveform only (no shading or trim handles)
              // ClipRRect(
              //   borderRadius: BorderRadius.circular(6),
              //   child: SizedBox(
              //     height: 80,
              //     child: AudioFileWaveforms(
              //       size: const Size(double.infinity, 80),
              //       waveformData: track.normWaveformData,
              //       playerController: track.waveformController,
              //       enableSeekGesture: false,
              //       waveformType: WaveformType.fitWidth,
              //       playerWaveStyle: const PlayerWaveStyle(
              //         showSeekLine: true,
              //         seekLineColor: Colors.grey,
              //       ),
              //     ),
              //   ),
              // ),
              _buildWaveformWithTrim(index, track, track.audioDuration),
              if (_expandedIndexMatches(index)) ...[
                const SizedBox(height: 10),
                Text(
                  '${L10n.translate(context, 'Trim')}: ${_formatDuration(track.trimStart)} - ${_formatDuration(track.trimEnd)}',
                ),
              ],
              if (_expandedIndexMatches(index)) ...[
                const Divider(
                    height: 20, color: Color.fromARGB(255, 221, 221, 221)),
                // Offset
                // Text('${L10n.translate(context, 'Offset')}: ${track.offset.toStringAsFixed(2)} s'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${L10n.translate(context, 'Offset')}: ${track.offset.toStringAsFixed(2)} s'),
                    TextButton.icon(
                      onPressed: () {
                        final seconds = (_audioOnly
                                ? _globalAudioClock.inMilliseconds
                                : _videoPosition.inMilliseconds) ~/
                            10 *
                            0.01;
                        if (seconds > 180) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(L10n.translate(context,
                                    'Offset cannot exceed 180 seconds.'))),
                          );
                          return;
                        }

                        setState(() {
                          track.offset = seconds;
                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        });
                      },
                      icon: const Icon(Icons.flash_on, size: 16),
                      label: Text(L10n.translate(context, 'Start from Now')),
                      style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: "-0.10s",
                      icon: const Icon(Icons.keyboard_double_arrow_left,
                          size: 18),
                      onPressed: () {
                        setState(() {
                          track.offset =
                              (track.offset - 0.10).clamp(0.0, 180.0);
                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: "-0.01s",
                      icon: const Icon(Icons.keyboard_arrow_left, size: 18),
                      onPressed: () {
                        setState(() {
                          track.offset =
                              (track.offset - 0.01).clamp(0.0, 180.0);
                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: "+0.01s",
                      icon: const Icon(Icons.keyboard_arrow_right, size: 18),
                      onPressed: () {
                        setState(() {
                          track.offset =
                              (track.offset + 0.01).clamp(0.0, 180.0);
                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: "+0.10s",
                      icon: const Icon(Icons.keyboard_double_arrow_right,
                          size: 18),
                      onPressed: () {
                        setState(() {
                          track.offset =
                              (track.offset + 0.10).clamp(0.0, 180.0);
                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        });
                      },
                    ),
                  ],
                ),
                Slider(
                  value: track.offset,
                  min: 0,
                  max: 180,
                  divisions: 18000,
                  label: track.offset.toStringAsFixed(2),
                  onChanged: (value) {
                    setState(() {
                      track.offset = value;
                      final effectivePos =
                          _calculateEffectiveAudioPositionForTrack(
                        track,
                        _audioOnly ? _globalAudioClock : _videoPosition,
                      );
                      JuceAudioEngine.seek(
                          index, effectivePos.inMicroseconds / 1e6);
                      track.currentPosition = effectivePos;
                    });
                  },
                ),

                // Trim info
                // Text(
                //   '${L10n.translate(context, 'Trim')}: ${_formatDuration(track.trimStart)} - ${_formatDuration(track.trimEnd)}'
                // ),
                // const SizedBox(height: 10),
                // _buildWaveformWithTrim(index, track, track.audioDuration),
                const SizedBox(height: 10),
                Text(L10n.translate(context, 'Volume Automation')),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragDown: (_) {}, // Claim the vertical gesture
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 100,
                        width: double.infinity,
                        color: Colors.grey[200],
                        child: VolumeAutomationWidget(
                          automationPoints: track.volumeAutomation,
                          currentNormalizedTime: normalizedTime,
                          onAutomationChanged: (points) {
                            setState(() {
                              track.volumeAutomation = points;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                    "${L10n.translate(context, 'Gain')}: ${track.gain.toStringAsFixed(2)}x"),
                Slider(
                  value: track.gain,
                  min: 0.0,
                  max: 3.0,
                  divisions: 60,
                  label: track.gain.toStringAsFixed(2),
                  onChanged: (value) {
                    setState(() {
                      track.gain = value;
                    });
                  },
                  onChangeEnd: (value) async {
                    setState(() => _isLoadingAudio = true);
                    await amplifyAndPlay(value, index);
                    setState(() => _isLoadingAudio = false);
                  },
                ),

                // EFFECTS BUTTON
                // Padding(
                //   padding: const EdgeInsets.symmetric(vertical: 8),
                //   child: SizedBox(
                //      width: double.infinity,
                //       child: ElevatedButton.icon(
                //         style: ElevatedButton.styleFrom(
                //           backgroundColor: HSLColor.fromColor(Theme.of(context).primaryColor)
                //   .withLightness((HSLColor.fromColor(Theme.of(context).primaryColor).lightness - 0.2).clamp(0.0, 1.0)).toColor(),
                //           padding: const EdgeInsets.symmetric(vertical: 16),
                //           shape: RoundedRectangleBorder(
                //             borderRadius: BorderRadius.circular(8),
                //           ),
                //         ),
                //         icon: const Icon(Icons.tune, color: Colors.white),
                //         label: FutureBuilder<List<String>>(
                //           future: JuceAudioEngine.getTrackEffects(index), // TODO: maybe this is being called too often when playing??
                //           builder: (ctx, snap) {
                //             final count = snap.hasData ? snap.data!.length : 0;
                //             return Text("Effects ($count/5)",
                //                 style: const TextStyle(color: Colors.white));
                //           },
                //         ),
                //         onPressed: () => _openEffectsDrawer(context, index),
                //       ),
                //   ),
                // ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor:
                            const Color.fromARGB(170, 44, 44, 44),
                        backgroundColor: const Color.fromARGB(
                          255,
                          79,
                          79,
                          98,
                        ), //HSLColor.fromColor(Theme.of(context).primaryColor)
                        // .withLightness(
                        //   (HSLColor.fromColor(Theme.of(context).primaryColor).lightness - 0.2)
                        //       .clamp(0.0, 1.0),
                        // )
                        // .toColor(),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.tune, color: Colors.white),
                      label: Text(
                        L10n.translate(context, 'Audio Track Effects'),
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () =>
                          _openEffectsDrawer(context, _selectedTrackIndex),
                    ),
                  ),
                ),

                // Delete Button
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(
                                  L10n.translate(context, 'Delete track?')),
                              content: Text(
                                L10n.translate(context,
                                    'Are you sure you want to delete this audio track?'),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(
                                    L10n.translate(context, 'Cancel'),
                                    style: TextStyle(
                                        color:
                                            Color.fromARGB(255, 218, 218, 218)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(L10n.translate(context, 'Delete'),
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ) ??
                          false;

                      // 2) Only delete if they confirmed
                      if (!confirm) return;
                      _expandedTrackIndex = -1;
                      _selectedTrackIndex = -1;
                      // Stop the audio track if it's playing.
                      final track = _audioTracks[index];
                      track.audioStartTimer?.cancel();
                      // await track.player.pause();
                      // track.player.dispose();
                      track.waveformController.dispose();

                      setState(() {
                        _audioTracks.removeAt(index);
                      });
                      await JuceAudioEngine.removeTrack(index);
                      await JuceAudioEngine.pause();
                      Future.delayed(Duration(milliseconds: 50), () {
                        setState(() {}); // force a repaint
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openEffectsDrawer(BuildContext context, int trackIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color.fromARGB(
          116, 199, 199, 199), //const Color.fromARGB(255, 39, 46, 97),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      barrierColor: Colors.black.withOpacity(0.3),
      // builder: (_) => EffectsDrawer(trackIndex: trackIndex),
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 10.0, sigmaY: 10.0), // adjust for more/less blur
          child: Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(
                82,
                122,
                122,
                122,
              ), //const Color.fromARGB(255, 124, 124, 124), // your semi-translucent color
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: EffectsDrawer(
              trackIndex: trackIndex,
              mode: _resolvedMode,
              isProEntitled: _isProEntitled,
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      // schedule the rebuild on the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    });
  }

  // this will be deprecated cuz we'll use JUCE instead of this ffmpeg thing
  Future<void> amplifyAndPlay(double gain, int trackInd) async {
    //   final track = _audioTracks[trackInd];
    //   // Get a temporary directory
    //   final tempDir = await getTemporaryDirectory();
    //   final outputPath = '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}${track.originalFile.path.split('/').last}';
    //   // FFmpeg command: amplify audio by {gain}x (e.g., 2.0 = 200%)
    //   final command = '-i "${track.originalFile.path}" -af "volume=$gain" -y "$outputPath"';

    //   // Execute FFmpeg
    //   final session = await FFmpegKit.execute(command);
    //   final returnCode = await session.getReturnCode();
    //   final errors = await session.getLogsAsString();
    //   if (!ReturnCode.isSuccess(returnCode)) {
    //     throw Exception('FFmpeg failed with rc=${returnCode}. ${errors}');
    //   }

    //  _isPlaying = false;
    //  await _pausePlayback();
    //  _stopTicker();

    //   // Play the new file
    //   track.file = File(outputPath); // mandatory for this to work since we use play(track.file.path)
    //   await track.player.stop();
    //   await track.player.setSource(DeviceFileSource(outputPath));
    // await track.player.resume();
  }

  Future<void> createWaveformData(AudioTrack track, double width) async {
    final sampleCount = PlayerWaveStyle().getSamplesForWidth(width);
    // TEMP TODO: deprecating waveformController
    List<double> rawData =
        []; // await track.waveformController.extractWaveformData(path: track.file.path, noOfSamples: sampleCount);
    setState(() {
      track.normWaveformData = normalizeWaveform(rawData);
    });
  }

  List<double> normalizeWaveform(List<double> data) {
    if (data.isEmpty) return [];

    final maxAmplitude =
        data.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

    if (maxAmplitude == 0) return List.filled(data.length, 0.0);

    return data.map((v) => v / maxAmplitude).toList();
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

  Widget _buildWaveformWithTrim(
      int index, AudioTrack track, Duration fullDuration) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double boxWidth = constraints.maxWidth;
        final double paddingH = 10.0;
        final double effectiveWidth = boxWidth - (2 * paddingH);
        final double totalMs = fullDuration.inMilliseconds.toDouble();

        if (totalMs <= 0) {
          return SizedBox(width: boxWidth, height: 80.0);
        }

        final ValueNotifier<double> trimStartNotifier =
            ValueNotifier(track.trimStart.inMilliseconds.toDouble());
        final ValueNotifier<double> trimEndNotifier =
            ValueNotifier(track.trimEnd.inMilliseconds.toDouble());

        // if(track.normWaveformData.isEmpty) {
        //   createWaveformData(track, boxWidth);
        // }
        if (!track.didExtractWaveform) {
          track.didExtractWaveform = true; // guard so we only ever do it once
          final samples = PlayerWaveStyle().getSamplesForWidth(boxWidth);
          // initialize it cuz on android it takes a long time to extract waveformdata
          track.normWaveformData =
              List<double>.filled(samples, 1.0, growable: false);

          // TEMP TODO: DEPRECATING waveformController
          // track.waveformController.extractWaveformData(path: track.file.path, noOfSamples: samples).then((raw) {
          //   setState(() {
          //     if (Platform.isAndroid) {
          //       final shaped = resampleLinear(raw, samples);
          //       track.normWaveformData = normalizeWaveform(shaped);
          //     } else {
          //       track.normWaveformData = normalizeWaveform(raw);
          //     }
          //   });
          // }).catchError((e) {
          //   print("Waveform extraction failed: $e");
          // });
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
                          key: ValueKey(
                              '${track.file.path}_${track.normWaveformData.hashCode}'),
                          size: Size(effectiveWidth, 80),
                          waveformData: track.normWaveformData, // NEW CHANGE
                          playerController: track.waveformController,
                          continuousWaveform: false,
                          enableSeekGesture: false,
                          waveformType: WaveformType.fitWidth,
                          playerWaveStyle: const PlayerWaveStyle(
                              seekLineColor: Color(0xFF888888),
                              showSeekLine: false),
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
                        left: paddingH +
                            (effectiveWidth * (trimStartMs / totalMs)),
                        onDragUpdate: (dx) {
                          double newTrimStart =
                              trimStartMs + (dx / effectiveWidth) * totalMs;
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
                          track.trimStart =
                              Duration(milliseconds: newTrimStart.round());

                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
                          track.currentPosition = effectivePos;
                        },
                      ),

                      // ✅ Trim End Handle
                      _buildTrimHandle(
                        left:
                            paddingH + (effectiveWidth * (trimEndMs / totalMs)),
                        onDragUpdate: (dx) {
                          double newTrimEnd =
                              trimEndMs + (dx / effectiveWidth) * totalMs;
                          newTrimEnd =
                              newTrimEnd.clamp(trimStartMs + 100, totalMs);

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
                          track.trimEnd =
                              Duration(milliseconds: newTrimEnd.round());

                          final effectivePos =
                              _calculateEffectiveAudioPositionForTrack(
                            track,
                            _audioOnly ? _globalAudioClock : _videoPosition,
                          );
                          JuceAudioEngine.seek(
                              index, effectivePos.inMicroseconds / 1e6);
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

  Widget _buildTrimHandle(
      {required double left, required Function(double) onDragUpdate}) {
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

  void _showAudioSourceOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          L10n.translate(context, 'Add Audio Track'),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.audiotrack),
              title: Text(L10n.translate(context, 'Pick from Device')),
              onTap: () {
                Navigator.pop(context);
                _addAudioTrack();
              },
            ),
            // Uncomment if needed later
            // ListTile(
            //   leading: Icon(Icons.bluetooth_audio),
            //   title: Text("Connect to Mixroom Guitar"),
            //   onTap: () {
            //     Navigator.pop(context);
            //     _connectToGuitarViaBluetooth();
            //   },
            // ),
          ],
        ),
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
        _progressMessage =
            "Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%";
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
      ).showSnackBar(SnackBar(
          content: Text(message), duration: const Duration(seconds: 3)));
    }
    print("Error: $message");
  }

  void _showOpenSettingsPrompt() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Bluetooth Required"),
        content:
            Text("Please enable Bluetooth to connect to your Mixroom guitar"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L10n.translate(context, 'Cancel'))),
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

  // 3. The complete Bluetooth file picker implementation
  // final flutterReactiveBle = FlutterReactiveBle();

  // Future<void> _connectToGuitarViaBluetooth() async {
  //   try {
  //     // A. Initialize Bluetooth
  //     _showProgress("Initializing Bluetooth...");

  //     // Check and request permissions
  //     await _requestBlePermissions();

  //     // B. Scan for Mixroom Guitar
  //     _showProgress("Searching for Mixroom Guitar...");
  //     setState(() => _isScanning = true);

  //     BluetoothDevice? guitarDevice;

  //     // Start classic Bluetooth scan
  //     await FlutterBluePlus.startScan(timeout: Duration(seconds: 10), androidScanMode: AndroidScanMode.lowLatency, oneByOne: true);

  //     // Listen for results
  //     var subscription = FlutterBluePlus.scanResults.listen((results) {
  //       for (var result in results) {
  //         print('Classic BT Device: ${result.device.platformName}');
  //         if (result.device.platformName?.toLowerCase().contains('mixroom') ?? false) {
  //           guitarDevice = result.device;
  //           FlutterBluePlus.stopScan();
  //           break;
  //         }
  //       }
  //     });

  //     // Timeout handling
  //     await Future.delayed(Duration(seconds: 10), () {

  //     });

  //     if (guitarDevice == null) {
  //       FlutterBluePlus.stopScan();
  //       subscription.cancel();
  //       print('Classic BT scan timeout');
  //       _showError("Mixroom Guitar not found");
  //       return;
  //     }

  //     // C. Connect to Guitar
  //     _showProgress("Connecting to guitar...");
  //     setState(() => _isConnecting = true);

  //     // final connection = flutterReactiveBle.connectToDevice(
  //     //   id: guitarDevice!.id,
  //     //   connectionTimeout: const Duration(seconds: 10),
  //     // );

  //     // final connectionSubscription = connection.listen((state) {
  //     //   if (state.connectionState == DeviceConnectionState.connected) {
  //     //     print("✅ Connected to Mixroom Guitar");
  //     //   }
  //     // });

  //     // // Wait for connection
  //     // await connection.firstWhere(
  //     //   (state) => state.connectionState == DeviceConnectionState.connected,
  //     // ).timeout(const Duration(seconds: 10));

  //     // // D. Discover Services
  //     // _showProgress("Discovering services...");
  //     // final services = await flutterReactiveBle.discoverServices(guitarDevice!.id);

  //     // // E. Find File Transfer Characteristics
  //     // QualifiedCharacteristic? fileListChar;
  //     // QualifiedCharacteristic? fileDataChar;

  //     // for (final service in services) {
  //     //   for (final characteristic in service.characteristics) {
  //     //     // Check if characteristic supports both read and notify
  //     //     if (characteristic.isReadable && characteristic.isNotifiable) {
  //     //       fileListChar = QualifiedCharacteristic(
  //     //         serviceId: service.serviceId,
  //     //         characteristicId: characteristic.characteristicId,
  //     //         deviceId: guitarDevice!.id,
  //     //       );
  //     //     }

  //     //     // Check if characteristic supports both write and read
  //     //     if (characteristic.isWritableWithResponse && characteristic.isReadable) {
  //     //       fileDataChar = QualifiedCharacteristic(
  //     //         serviceId: service.serviceId,
  //     //         characteristicId: characteristic.characteristicId,
  //     //         deviceId: guitarDevice!.id,
  //     //       );
  //     //     }
  //     //   }
  //     // }

  //     // if (fileListChar == null || fileDataChar == null) {
  //     //   _showError("Could not find required guitar services");
  //     //   return;
  //     // }

  //     // // F. Get File List
  //     // _showProgress("Fetching available files...");
  //     // final fileListData = await flutterReactiveBle.readCharacteristic(fileListChar);
  //     // final fileList = utf8.decode(fileListData).split('\n').where((f) => f.isNotEmpty).toList();

  //     // setState(() {
  //     //   _guitarFiles = fileList;
  //     //   _isConnecting = false;
  //     // });
  //     // _hideProgress();

  //     // // G. Show File Picker Dialog
  //     // final selectedFile = await showDialog<String>(
  //     //   context: context,
  //     //   builder: (context) => AlertDialog(
  //     //     title: const Text("Select Audio File"),
  //     //     content: SizedBox(
  //     //       width: double.maxFinite,
  //     //       child: ListView.builder(
  //     //         shrinkWrap: true,
  //     //         itemCount: _guitarFiles.length,
  //     //         itemBuilder: (context, index) => ListTile(
  //     //           title: Text(_guitarFiles[index]),
  //     //           onTap: () => Navigator.pop(context, _guitarFiles[index]),
  //     //         ),
  //     //       ),
  //     //     ),
  //     //   ),
  //     // );

  //     // if (selectedFile != null) {
  //     //   // H. Download File
  //     //   _showProgress("Downloading $selectedFile...");
  //     //   await flutterReactiveBle.writeCharacteristicWithResponse(
  //     //     fileDataChar,
  //     //     value: utf8.encode("DL:$selectedFile"),
  //     //   );

  //     //   List<int> fileData = [];
  //     //   final sub = flutterReactiveBle.subscribeToCharacteristic(fileDataChar).listen((value) {
  //     //     fileData.addAll(value);
  //     //     _updateDownloadProgress(fileData.length);
  //     //   });

  //     //   // Wait for complete (adjust timeout as needed)
  //     //   await Future.delayed(const Duration(seconds: 2));
  //     //   await sub.cancel();

  //     //   // I. Create Audio Track
  //     //   final tempDir = await getTemporaryDirectory();
  //     //   final filePath = '${tempDir.path}/${selectedFile.replaceAll('/', '_')}';
  //     //   final file = File(filePath);
  //     //   await file.writeAsBytes(fileData);

  //     //   final newPlayer = AudioPlayer();
  //     //   await newPlayer.setSourceDeviceFile(filePath);
  //     //   final dur = await newPlayer.getDuration() ?? Duration.zero;

  //     //   final newController = PlayerController();
  //     //   newController.preparePlayer(path: filePath);

  //     //   final newTrack = AudioTrack(
  //     //     file: file,
  //     //     player: newPlayer,
  //     //     waveformController: newController,
  //     //     audioDuration: dur,
  //     //     trimStart: Duration.zero,
  //     //     trimEnd: dur,
  //     //     offset: 0.0,
  //     //     crossfade: 1.0,
  //     //     currentPosition: Duration.zero,
  //     //   );

  //     //   newPlayer.onPositionChanged.listen((position) {
  //     //     if (mounted) setState(() => newTrack.currentPosition = position);
  //     //     if (_isPlaying && position >= newTrack.trimEnd) newPlayer.pause();
  //     //   });

  //     //   if (mounted) {
  //     //     setState(() => _audioTracks.add(newTrack));
  //     //   }

  //     //   _hideProgress();
  //     //   _showError("Download complete!");
  //     // }

  //     // // Clean up connection
  //     // await connectionSubscription.cancel();

  //   } catch (e) {
  //     _hideProgress();
  //     _showError("Error: ${e.toString()}");
  //     if (mounted) setState(() {
  //       _isScanning = false;
  //       _isConnecting = false;
  //     });
  //   }
  // }

  // Future<void> _requestBlePermissions() async {
  //   if (Platform.isAndroid) {
  //     await Permission.locationWhenInUse.request();
  //   }

  //   if (Platform.isIOS) {
  //     await Permission.bluetooth.request();
  //     await Permission.bluetoothConnect.request();
  //     await Permission.bluetoothScan.request();
  //   }

  //   // Wait for Bluetooth to be ready
  //   // await flutterReactiveBle.statusStream.firstWhere(
  //   //   (status) => status == BleStatus.ready,
  //   // ).timeout(const Duration(seconds: 10));
  // }

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

  // Instead of the deprecated single-audio _pickAudioFile, use _addAudioTrack.
  Future<void> _addAudioTrack() async {
    _pausePlayback();
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.path != null) {
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

      final baseNameNoExt = baseName.contains('.')
          ? baseName.substring(0, baseName.lastIndexOf('.'))
          : baseName;
      final resampledPath = '${tmpDir.path}/$baseNameNoExt.wav';

      // 1) Transcode to 48 kHz PCM WAV (fast, one‐time cost):
      await FFmpegKit.execute(
        '-i "${newFile.path}" -ar 48000 -y "$resampledPath"', // DO .WAV
      );
      final newFile_48 = File(resampledPath);

      // await newPlayer.setSourceDeviceFile(newFile.path);
      // final dur = await newPlayer.getDuration() ?? Duration.zero;
      await JuceAudioEngine.loadTrack(_audioTracks.length, newFile_48.path);
      // final dur = await JuceAudioEngine.getTrackDuration(0);
      final durSeconds =
          await JuceAudioEngine.getTrackDuration(_audioTracks.length);
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
      );

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
        //TODO: take out the async
        _audioTracks.add(newTrack);
        if (!_audioOnly) {
          _initializeVideo(); // maybe too excessive (consider doing it for android only)
        }
        _isLoadingAudio = false;
      });
    }
  }

  Widget _buildVideoAudioAutomationSection() {
    // Assume currentNormalizedTime is computed from video audio playback progress.
    double videoAudioNormalizedTime =
        _videoPosition.inMilliseconds / duration.inMilliseconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Text("Video Audio Volume Automation"),
        Text(
          L10n.translate(context, 'Video Audio Volume Automation'),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w400),
        ),
        Container(
          height: 100,
          color: Colors.grey[200],
          child: VideoAudioAutomationWidget(
            automationPoints: videoAudioAutomation,
            currentNormalizedTime: videoAudioNormalizedTime,
            onAutomationChanged: (points) {
              setState(() {
                videoAudioAutomation = points;
              });
            },
          ),
        ),
      ],
    );
  }

  Future<void> _exportAndNavigate() async {
    if (_audioOnly) {
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
            format: _ExportAudioFormat.mp3,
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
            SnackBar(
              content: Text(
                L10n.translate(context, 'Could not open export options.'),
              ),
            ),
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
      });
    }

    setState(() {
      _isLoadingNextScreen = true;
    });
    if (_isPlaying) {
      _audioOnly
          ? await _togglePlayPauseAudio(_audioEditorStateSetter!)
          : await _togglePlayPause();
    }
    // final exportPath = _audioOnly ? await _exportAudioOnly() : await _exportVideo();
    final exportPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ExportProgressPage(
          exportFn: _audioOnly ? _exportAudioOnly : _exportVideo,
          videoFile: _audioOnly ? "" : _videoFile!.path,
        ),
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

    final exportExt = exportPath.split('.').last;
    final exportBaseName = _videoFile != null
        ? p.basenameWithoutExtension(_videoFile!.path)
        : (_audioOnly ? 'Mixroom Export' : 'Mixroom Video');
    final suggestedFileName = ExportSaveDialog.buildSuggestedFileName(
      baseName: exportBaseName,
      extension: exportExt,
    );
    final savedPath = await ExportSaveDialog.saveExportedFile(
      sourceFilePath: exportPath,
      suggestedFileName: suggestedFileName,
      desktopDialogTitle: L10n.translate(context, 'Save export'),
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
            filePath: exportPath,
            savedFilePath: savedPath,
            savedFileName: suggestedFileName,
            isVideo: !_audioOnly,
          ),
        ),
      );

      try {
        final tempExport = File(exportPath);
        if (await tempExport.exists()) {
          await tempExport.delete();
        }
      } catch (_) {}

      if (done == true) {
        //****TEMPORARY: REMOVE return LINE FOR Mixroom FULL RELEASE****
        return;

        _pausePlayback();
        _stopTicker();
        for (var track in _audioTracks) {
          track.waveformController.dispose();
        }
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

  Widget _buildFloatingTransportBar() {
    final theme = Theme.of(context);

    final maxValue =
        _videoFile == null ? 0.0 : duration.inMilliseconds.toDouble();
    double currentValue = _isScrubbing
        ? _scrubPosition.inMilliseconds.toDouble()
        : _videoPosition.inMilliseconds.toDouble();
    currentValue = currentValue.clamp(0.0, maxValue);

    // stuff for audio-only
    Duration overallDuration = Duration.zero;
    if (_audioTracks.isNotEmpty) {
      overallDuration = _audioTracks.map((track) {
        final offsetDuration =
            Duration(milliseconds: (track.offset * 1000).round());
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
            color: const Color.fromARGB(255, 32, 32, 32).withOpacity(0.75),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(
              color: const Color.fromARGB(
                  255, 80, 80, 80), // Or adjust to your desired grey
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Play/Pause button
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
                onPressed: _togglePlayPause,
              ),

              // Restart button
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white),
                onPressed: () {
                  if (_audioOnly) {
                    _restartAudio(_audioEditorStateSetter!);
                  } else {
                    _restartVideo();
                  }
                },
              ),

              // Scrubber
              Expanded(
                child: _audioOnly
                    ? Slider(
                        value:
                            _globalAudioClock.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  overallDuration.inMilliseconds.toDouble(),
                                ),
                        min: 0,
                        max: overallDuration.inMilliseconds.toDouble(),
                        onChangeStart: (value) async {
                          _audioAutomationTimer?.cancel();
                          for (var track in _audioTracks) {
                            // await track.player.pause();
                            track.audioStarted =
                                false; // Reset flag on pause so that resume triggers play.
                          }
                          JuceAudioEngine.pause();
                          _audioEditorStateSetter!(() {
                            _isPlaying = false;
                          });
                        },
                        onChanged: (value) {
                          final newPos = Duration(milliseconds: value.toInt());
                          // Update the UI immediately:
                          _audioEditorStateSetter!(() {
                            _globalAudioClock = newPos;
                          });
                          // For each track, calculate the effective seek position:
                          for (int i = 0; i < _audioTracks.length; i++) {
                            final track = _audioTracks[i];
                            final offsetDuration = Duration(
                                milliseconds: (track.offset * 1000).round());
                            Duration effectivePos;
                            if (newPos < offsetDuration) {
                              effectivePos = track.trimStart;
                            } else {
                              effectivePos =
                                  track.trimStart + (newPos - offsetDuration);
                              if (effectivePos > track.trimEnd) {
                                effectivePos = track.trimEnd;
                              }
                            }
                            // Kick off the seek without awaiting:
                            // track.player.seek(effectivePos);
                            JuceAudioEngine.seek(
                                i, effectivePos.inMicroseconds / 1e6);
                          }
                          // Update automation (you can call this synchronously or asynchronously).
                          _updateAudioAutomation(newPos);
                        },
                        onChangeEnd: (value) async {
                          _audioAutomationTimer?.cancel();
                          for (var track in _audioTracks) {
                            // await track.player.pause();
                            track.audioStarted =
                                false; // Reset flag on pause so that resume triggers play.
                          }
                          JuceAudioEngine.pause();
                          _audioEditorStateSetter!(() {
                            _isPlaying = false;
                          });
                        },
                      )
                    : Slider(
                        value: currentValue,
                        min: 0,
                        max: maxValue,
                        onChangeStart: (value) {
                          for (var track in _audioTracks) {
                            track.audioStartTimer?.cancel();
                          }
                          _pausePlayback();
                          _stopTicker();
                          setState(() {
                            _isScrubbing = true;
                            _scrubPosition =
                                Duration(milliseconds: value.toInt());
                          });
                        },
                        onChanged: (value) {
                          setState(() {
                            _scrubPosition =
                                Duration(milliseconds: value.toInt());
                          });
                        },
                        onChangeEnd: (value) async {
                          final newPosition =
                              Duration(milliseconds: value.toInt());
                          setState(() {
                            _isScrubbing = false;
                            _videoPosition = newPosition;
                            _scrubPosition = newPosition;
                          });

                          await seekTo(newPosition);
                          await JuceAudioEngine.seekVideoAudio(
                              newPosition.inMicroseconds / 1e6);

                          for (int i = 0; i < _audioTracks.length; i++) {
                            final track = _audioTracks[i];
                            final effectivePos =
                                _calculateEffectiveAudioPositionForTrack(
                                    track, newPosition);

                            await JuceAudioEngine.seek(
                                i, effectivePos.inMicroseconds / 1e6);
                            setState(() {
                              track.currentPosition = effectivePos;
                            });
                          }

                          if (_isPlaying) {
                            _resumePlayback();
                            _startTicker();
                          }
                        },
                      ),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(L10n.translate(context, 'Add Video Clip')),
                onTap: () {
                  Navigator.pop(context);

                  if (_isBasicTier && _segments.length == 1) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Text(L10n.translate(context, 'Pro Mode Feature'),
                            style: TextStyle(color: Colors.white)),
                        content: Text(
                          L10n.translate(context,
                              'Upgrade to Pro mode to import more than 1 video.'),
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

                  _pickVideoFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(L10n.translate(context, 'Add Audio Track')),
                onTap: () {
                  Navigator.pop(context);

                  if (_isBasicTier && _audioTracks.length == 3) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF2C2C2C),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: Text(L10n.translate(context, 'Pro Mode Feature'),
                            style: TextStyle(color: Colors.white)),
                        content: Text(
                          L10n.translate(context,
                              'Upgrade to Pro mode to import more than 3 audio tracks.'),
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

                  _addAudioTrack();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Future<void> _exportMergedVideo() async {
  //   setState(() => _isExporting = true);
  //   final builder = VideoEditorBuilder(videoPath: _segments[0].path)
  //     .trim(startTimeMs: _segments[0].start.inMilliseconds,
  //           endTimeMs: _segments[0].end.inMilliseconds);

  //   for (int i = 1; i < _segments.length; i++) {
  //     builder
  //       .merge(otherVideoPaths: [_segments[i].path])
  //       .trim(startTimeMs: _segments[i].start.inMilliseconds,
  //             endTimeMs: _segments[i].end.inMilliseconds);
  //   }

  //   final out = await builder.export(onProgress: (_) {});
  //   setState(() => _isExporting = false);

  //   // print("here: ${out}");

  //   final videoFile = File(out!);
  //   setState(() {
  //     _videoFile = videoFile;
  //   });

  //   // Initialize video controller with the new file
  //   await _initializeVideo();
  //   // _pickVideoFile(out);
  // }

  Future<void> _exportMergedVideo() async {
    setState(() => _isExporting = true);

    final trimmedPaths = <String>[];

    if (_segments.isEmpty) {
      setState(() {
        _audioOnly = true;
        _isExporting = false;
      });
      _videoFile = null;
      return;
    }

    for (int i = 0; i < _segments.length; i++) {
      final tempDir = await getTemporaryDirectory();
      final trimmedOutputPath =
          '${tempDir.path}/trimmed_${i}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final builder = VideoEditorBuilder(videoPath: _segments[i].path).trim(
        startTimeMs: _segments[i].start.inMilliseconds,
        endTimeMs: _segments[i]
            .end
            .inMilliseconds, // made a fix where _segments[i].end is clamped to total duration if end > duration
      );
      await builder.export(outputPath: trimmedOutputPath);

      trimmedPaths.add(trimmedOutputPath);
    }

    String? finalOutput;
    if (trimmedPaths.length == 1) {
      finalOutput = trimmedPaths.first;
    } else {
      final mergeEditor = VideoEditorBuilder(videoPath: trimmedPaths.first);
      mergeEditor.merge(otherVideoPaths: trimmedPaths.sublist(1));

      final outputDir = await getTemporaryDirectory();
      final mergedOutputPath = '${outputDir.path}/final_merged.mp4';

      finalOutput = await mergeEditor.export(
        outputPath: mergedOutputPath,
      ); // POTENTIALLY A BUG (finalOutput = null, answer is in mergedOutputPath)
    }

    setState(() {
      _isExporting = false;
      _videoFile = File(finalOutput!);
    });

    await _initializeVideo();
  }

  Future<double?> getVideoDurationSeconds(String path) async {
    final session = await FFprobeKit.execute(
        '-v quiet -print_format json -show_format "$path"');

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

  Future<Map<String, int>> getVideoDimensions(String videoPath) async {
    final session = await FFprobeKit.getMediaInformation(videoPath);
    final information = session.getMediaInformation();
    final allProperties = information!.getAllProperties();

    final streams = allProperties!['streams'] as List<dynamic>;
    for (final stream in streams) {
      if (stream['codec_type'] == 'video') {
        return {
          'width': stream['width'] as int,
          'height': stream['height'] as int
        };
      }
    }
    return {'width': 1920, 'height': 1080}; // fallback
  }

  Future<void> applyGreenScreen({
    required int i,
    required BuildContext context,
    required String foregroundPath,
    required String bgPath,
    double bgStart = 0.0,
  }) async {
    setState(() => _isExporting = true);
    try {
      final duration = await getVideoDurationSeconds(bgPath);
      final segStartSec = _segments[i].start.inMilliseconds / 1000.0;
      final hasSegDelay = segStartSec > 0.0;
      final bgDelay = hasSegDelay ? ',setpts=PTS+${segStartSec}/TB' : '';

      // 2) Compose output path
      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/gs_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // Tweak these if your greens aren’t pure #00FF00:
      //   keyColor:   0x00FF00 (pure green)
      //   similarity: 0.15–0.25 usually
      //   blend:      0.05–0.15 (edge softness)

      // 0: foreground (green screen), 1: background
      const keyColor = '0x00FF00';
      const similarity = '0.20';
      const blend = '0.15';

      // OLDER FILTERGRAPH (because scale2ref is deprecated for ios I think)
      final filterGraph = [
        '[0:v]colorkey=$keyColor:$similarity:$blend[fg]', // Use colorkey instead
        '[1:v]setsar=1$bgDelay[bg]',
        '[fg][bg]scale2ref=flags=lanczos[fgs][bgs]',
        '[bgs][fgs]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2:format=yuv420[v]',
      ].join(';');

      final dimensions = await getVideoDimensions(bgPath);
      final bgWidth = dimensions['width']!;
      final bgHeight = dimensions['height']!;

      final filterGraph2 = [
        '[0:v]chromakey=$keyColor:$similarity:$blend,scale=$bgWidth:$bgHeight:flags=lanczos[fg]',
        '[1:v]setsar=1$bgDelay[bg]',
        '[bg][fg]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2,format=yuv420p[v]',
      ].join(';');
      // final minimalFilter = '[1:v][0:v]overlay=10:10[v]';

      String cmdX264 = [
        '-y',
        '-i', '"$foregroundPath"',
        if (bgStart != 0.0) ...['-ss', bgStart.toString()],
        '-i', '"$bgPath"',
        '-filter_complex', '"$filterGraph2"',
        '-map', '[v]',
        '-map', '"0:a?"',
        // '-c:v', 'h264_mediacodec',
        // '-c:v', 'libx264',
        '-c:v',
        Platform.isAndroid
            ? 'h264_mediacodec'
            : 'mpeg4', // DIFF ENCODER AND STUFF FOR NEW FFMPEG LIBRARY (not using GPL)
        //  '-c:v', 'mpeg4',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-shortest',
        outPath,
      ].join(' ');

      print('FFmpeg command: $cmdX264');

      final session = await FFmpegKit.execute(cmdX264);
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        // setState(() {
        //   _segments[i].path = outPath;
        // });

        final original = _segments[i];
        final newDuration = await getVideoDuration(outPath);
        setState(() {
          _segments[i] = VideoSegment(
            path: outPath,
            start: original.start, // Duration.zero,
            end: original.end > newDuration!
                ? newDuration
                : original.end, //original.totalDuration,
            totalDuration: newDuration, //original.totalDuration,
            thumbnailPath:
                original.thumbnailPath, // optional: regenerate if needed

            gain: original.gain,
            original: foregroundPath,
            greenScreen: bgPath,
            greenScreenDuration: duration!,
            greenScreenStart: bgStart, //original.greenScreenStart,
          );
        });

        await _exportMergedVideo();
      } else {
        final logs = await session.getAllLogsAsString();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Green screen compose failed.\n$logs')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildClipList() {
    return Column(
      children: [
        if (_isExporting) const LinearProgressIndicator(),
        for (int i = 0; i < _segments.length; i++)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade400, width: 1.5),
            ),
            color: const Color.fromARGB(255, 192, 104, 63),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(_segments[i].thumbnailPath),
                              height: 60, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(_expandedSegments.contains(i)
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down),
                        onPressed: () {
                          setState(() {
                            if (_expandedSegments.contains(i)) {
                              _expandedSegments.remove(i);
                            } else {
                              _expandedSegments.add(i);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_expandedSegments.contains(i)) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: VideoTrimSlider(
                        key: ValueKey(_segments[i].path),
                        initialStart: _segments[i].start,
                        initialEnd: _segments[i].end,
                        totalDuration: _segments[i].totalDuration,
                        onChangeStart: (start) async {
                          setState(() => _segments[i].start = start);
                          // await _exportMergedVideo();
                        },
                        onChangeEnd: (end) async {
                          setState(() => _segments[i].end = end);

                          if (_segments[i].greenScreen != '') {
                            await applyGreenScreen(
                              i: i,
                              context: context,
                              foregroundPath: _segments[i].original,
                              bgPath: _segments[i].greenScreen,
                              bgStart: _segments[i].greenScreenStart,
                            );
                            // internally it will also do _exportMergedVideo()
                          } else {
                            await _exportMergedVideo();
                          }
                        },
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            "${L10n.translate(context, 'Gain')}: ${_segments[i].gain.toStringAsFixed(2)}x"),
                        Slider(
                          value: _segments[i].gain,
                          min: 0.0,
                          max: 3.0,
                          divisions: 60,
                          label: _segments[i].gain.toStringAsFixed(2),
                          onChanged: (value) async {
                            setState(() {
                              _segments[i].gain = value;
                            });
                            // await JuceAudioEngine.setVideoAudioGain(value);
                          },
                          onChangeEnd: (value) async {
                            setState(() {
                              _segments[i].gain = value;
                            });
                            // await _exportMergedVideo();
                            // await JuceAudioEngine.setVideoAudioGain(value);
                          },
                        ),
                      ],
                    ),
                    if (_segments[i].greenScreen != '') ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Background Start: ${_segments[i].greenScreenStart.toStringAsFixed(2)}s",
                          ), //${L10n.translate(context, 'Background start')}: ${_segments[i].greenScreenStart.toStringAsFixed(2)}s"),
                          Slider(
                            value: _segments[i].greenScreenStart,
                            min: 0.0,
                            max: _segments[i].greenScreenDuration,
                            divisions: 500,
                            label: _segments[i]
                                .greenScreenStart
                                .toStringAsFixed(2),
                            onChanged: (value) async {
                              setState(() {
                                _segments[i].greenScreenStart = value;
                              });
                            },
                            onChangeEnd: (value) async {
                              setState(() {
                                _segments[i].greenScreenStart = value;
                              });

                              await applyGreenScreen(
                                i: i,
                                context: context,
                                foregroundPath: _segments[i].original,
                                bgPath: _segments[i].greenScreen,
                                bgStart: _segments[i].greenScreenStart,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i > 0
                              ? () async {
                                  setState(() {
                                    final temp = _segments[i - 1];
                                    _segments[i - 1] = _segments[i];
                                    _segments[i] = temp;
                                  });
                                  await _exportMergedVideo();
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: i < _segments.length - 1
                              ? () async {
                                  setState(() {
                                    final temp = _segments[i + 1];
                                    _segments[i + 1] = _segments[i];
                                    _segments[i] = temp;
                                  });
                                  await _exportMergedVideo();
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.crop_rotate_sharp),
                          tooltip: 'Rotate 90°',
                          onPressed: () async {
                            setState(() => _isExporting = true);
                            final original = _segments[i];
                            final tempDir = await getTemporaryDirectory();
                            final rotatedPath =
                                '${tempDir.path}/rotated_${DateTime.now().millisecondsSinceEpoch}.mp4';

                            String? output;

                            if (Platform.isAndroid) {
                              // final cmd = [
                              //   '-y',
                              //   '-i', '"${original.path}}"',
                              //   // '-vf', 'transpose=1',  // 90° clockwise
                              //   // '-c:v', 'libx264',
                              //   // '-preset', 'ultrafast',
                              //   // '-movflags', '+faststart',
                              //   // '-c:a', 'copy',        // copy audio without re-encode
                              //   '"$rotatedPath"',
                              // ].join(' ');

                              final cmd =
                                  '-y -i "${original.path}" -vf "transpose=1" -c:a copy -preset ultrafast -movflags +faststart "$rotatedPath"';

                              final session = await FFmpegKit.execute(cmd);
                              final rc = await session.getReturnCode();

                              if (ReturnCode.isSuccess(rc)) {
                                print(
                                    '✅ Video rotated successfully -> $rotatedPath');
                              } else {
                                print(
                                    '❌ Failed to rotate video. Return code: $rc');
                              }
                              output = rotatedPath;
                            } else {
                              // Rotate original path (or current if previously rotated)
                              output = await VideoEditorBuilder(
                                videoPath: original.path,
                              )
                                  .rotate(degree: RotationDegree.degree90)
                                  .export(outputPath: rotatedPath);
                            }

                            final newDuration = await getVideoDuration(output!);

                            setState(() {
                              _segments[i] = VideoSegment(
                                path: output!,
                                start: original.start, //Duration.zero,
                                end: original.end > newDuration!
                                    ? newDuration
                                    : original.end, //original.totalDuration,
                                totalDuration:
                                    newDuration, //original.totalDuration,
                                thumbnailPath: original
                                    .thumbnailPath, // optional: regenerate if needed

                                gain: original.gain,
                                original: original.original,
                                greenScreen: original.greenScreen,
                                greenScreenStart: original.greenScreenStart,
                                greenScreenDuration:
                                    original.greenScreenDuration,
                              );
                            });
                            await _exportMergedVideo();
                            setState(() => _isExporting = false);
                          },
                        ),

                        // ADD ICONBUTTON HERE FOR ADD GREENSCREEN VIDEO
                        IconButton(
                          tooltip: 'Add Green Screen Background',
                          icon:
                              const Icon(Icons.image), // or Icons.video_library
                          onPressed: () async {
                            // 0) Guard: segment must exist
                            if (i < 0 || i >= _segments.length) return;

                            final foregroundPath = _segments[i].original != ''
                                ? _segments[i].original
                                : _segments[i]
                                    .path; // this is the clip that has green screen
                            if (foregroundPath.isEmpty) return;

                            // 1) Pick a background video
                            String? bgPath;
                            if (Platform.isIOS) {
                              final XFile? pickedFile =
                                  await ImagePicker().pickVideo(
                                source: ImageSource
                                    .gallery, // Direct Photos app access
                                maxDuration: Duration(
                                    minutes: 15), // LIMIT OF VIDEO DURATION
                              );

                              if (pickedFile == null) return;

                              bgPath = pickedFile.path;
                            } else {
                              final picked =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.video,
                                allowMultiple: false,
                              );
                              if (picked == null || picked.files.isEmpty)
                                return;

                              bgPath = picked.files.single.path;
                              if (bgPath == null) return;
                            }

                            await applyGreenScreen(
                              i: i,
                              context: context,
                              foregroundPath: foregroundPath,
                              bgPath: bgPath,
                            );
                          },
                        ),

                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(L10n.translate(
                                        context, 'Delete clip?')),
                                    content: Text(
                                      L10n.translate(
                                        context,
                                        'Are you sure you want to remove this video clip from your timeline?',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: Text(
                                          L10n.translate(context, 'Cancel'),
                                          style: TextStyle(
                                              color: Color.fromARGB(
                                                  255, 218, 218, 218)),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text(
                                          L10n.translate(context, 'Delete'),
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;

                            if (!confirm) return;

                            setState(() => _segments.removeAt(i));

                            // (Optional) dispose controllers or clean up here

                            if (_segments.isEmpty) {
                              setState(() => _audioOnly = true);
                            }

                            await _exportMergedVideo();
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // If no video is selected
    // offer the choice.
    // if (_videoFile == null) {
    //   return _buildIntroScreen();
    // }

    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return Stack(
          children: [
            Scaffold(
              extendBody: true,
              body: Stack(
                children: [
                  SafeArea(
                    child: StatefulBuilder(
                      builder:
                          (BuildContext context, StateSetter setLocalState) {
                        _audioEditorStateSetter = setLocalState;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
                          child: Column(
                            children: [
                              // TOP ROW OF BUTTONS
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // LEFT SIDE: Home + Help
                                    Row(
                                      children: [
                                        // ****TEMPORARY: UNCOMMENT ENTIRE children BLOCK FOR FULL Mixroom RELEASE****
                                        // IconButton(
                                        //   icon: const Icon(Icons.home),
                                        //   onPressed: () async {
                                        //     final shouldProceed = await showDialog<bool>(
                                        //       context: context,
                                        //       builder: (context) => AlertDialog(
                                        //         backgroundColor: const Color(0xFF2C2C2C),
                                        //         shape: RoundedRectangleBorder(
                                        //           borderRadius: BorderRadius.circular(16),
                                        //         ),
                                        //         title: Text(
                                        //           L10n.translate(context, 'Exit project?'),
                                        //           style: TextStyle(color: Colors.white),
                                        //         ),
                                        //         content: Text(
                                        //           L10n.translate(context, 'All progress will be lost.'),
                                        //           style: TextStyle(color: Colors.white70),
                                        //         ),
                                        //         actions: [
                                        //           TextButton(
                                        //             onPressed: () => Navigator.pop(context, false),
                                        //             child: Text(L10n.translate(context, 'Cancel'), style: TextStyle(color: Color.fromARGB(255, 218, 218, 218))),
                                        //           ),
                                        //           TextButton(
                                        //             onPressed: () => Navigator.pop(context, true),
                                        //             child: Text(L10n.translate(context, 'Confirm')),//, style: TextStyle(color: Color(0xFF2F44FF))),
                                        //           ),
                                        //         ],
                                        //       ),
                                        //     );

                                        //     if (shouldProceed != true) {
                                        //       return;
                                        //     }

                                        //     // Dispose resources before navigating
                                        //     _pausePlayback();
                                        //     _stopTicker();
                                        //     for (var track in _audioTracks) {
                                        //       // track.player.dispose();
                                        //       track.waveformController.dispose();
                                        //     }
                                        //     // _videoController?.dispose();
                                        //     // betterController?.dispose();
                                        //     JuceAudioEngine.shutdown(); //TODO: not sure if this necessary
                                        //     // Navigator.of(context).pushAndRemoveUntil(
                                        //     //   MaterialPageRoute(builder: (_) => const HomeScreen()),
                                        //     //   (route) => false,
                                        //     // );
                                        //     Navigator.of(context).pop();
                                        //   },
                                        // ),
                                        // // IconButton(
                                        // //   icon: const Icon(Icons.help_outline),
                                        // //   onPressed: () {
                                        // //     showDialog(
                                        // //       context: context,
                                        // //       builder: (context) => AlertDialog(
                                        // //         title: Text(L10n.translate(context, 'Help')),
                                        // //         content: Text(L10n.translate(context, 'Coming soon')),
                                        // //       ),
                                        // //     );
                                        // //   },
                                        // // ),
                                      ],
                                    ),

                                    // RIGHT SIDE: Sync + Export
                                    Row(
                                      children: [
                                        // Now AI Sync will work for Audio-Only mode too. The reference track will be the first audio track. So there should be at least 2 audio tracks.
                                        // _audioOnly ? SizedBox.shrink() :
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            final shouldSync = await showDialog<
                                                    bool>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                    title: Text(L10n.translate(
                                                        context, 'AI Sync')),
                                                    content: Text(
                                                      L10n.translate(
                                                        context,
                                                        'Automatically synchronizes all audio tracks to the video. Audio offset/trim may be adjusted.',
                                                      ),
                                                      // style: Theme.of(context).textTheme.bodyLarge,
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                                    context)
                                                                .pop(false),
                                                        child: Text(
                                                          L10n.translate(
                                                              context,
                                                              'Cancel'),
                                                          style: TextStyle(
                                                              color: Color
                                                                  .fromARGB(
                                                                      255,
                                                                      218,
                                                                      218,
                                                                      218)),
                                                        ),
                                                      ),
                                                      // ElevatedButton(
                                                      //   onPressed: () => Navigator.of(context).pop(true),
                                                      //   child: const Text("Sync"),
                                                      // ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child: Text(
                                                          L10n.translate(
                                                              context, 'Sync'),
                                                        ), //, style: TextStyle(color: Color(0xFF2F44FF))),
                                                      ),
                                                    ],
                                                  ),
                                                ) ??
                                                false;

                                            if (shouldSync == false) {
                                              return;
                                            }

                                            if (_audioOnly) {
                                              if (_audioTracks.length < 2)
                                                return;
                                              if (_isPlaying) {
                                                await _togglePlayPauseAudio(
                                                    _audioEditorStateSetter!);
                                              }

                                              setState(() {
                                                _isSyncing = true;
                                                _syncProgress = 0.0;
                                              });

                                              var firstTrack =
                                                  _audioTracks.first;
                                              for (var i = 1;
                                                  i < _audioTracks.length;
                                                  i++) {
                                                await applyBestSyncOffset(
                                                    _audioTracks[i],
                                                    firstTrack.file.path);
                                              }

                                              setState(() {
                                                _isSyncing = false;
                                                _syncProgress = 0.0;
                                              });

                                              _restartAudio(
                                                  _audioEditorStateSetter!);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    L10n.translate(context,
                                                        'AI Sync applied successfully!'),
                                                  ),
                                                ),
                                              );
                                              _restartAudio(
                                                  _audioEditorStateSetter!);

                                              return;
                                            }

                                            // Ensure both video and at least one audio track are available.
                                            if (_videoFile == null ||
                                                _audioTracks.isEmpty) return;

                                            setState(() {
                                              _isPlaying = false;
                                            });
                                            _pausePlayback();
                                            _stopTicker();

                                            setState(() {
                                              _isSyncing = true;
                                              _syncProgress = 0.0;
                                            });

                                            for (var track in _audioTracks) {
                                              await applyBestSyncOffset(
                                                  track, _videoFile!.path);
                                            }
                                            setState(() {
                                              _isSyncing = false;
                                              _syncProgress = 0.0;
                                            });

                                            _restartVideo();

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(L10n.translate(
                                                    context,
                                                    'AI Sync applied successfully!')),
                                              ),
                                            );
                                            _restartVideo();
                                          },
                                          icon: const Icon(Icons.sync),
                                          label: Text(
                                              L10n.translate(context, 'SYNC'),
                                              style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(
                                                  24), // makes it more pill-like
                                            ),
                                            elevation: 2,
                                            backgroundColor:
                                                const Color.fromARGB(
                                                    255, 230, 230, 230),
                                            foregroundColor:
                                                const Color.fromARGB(
                                                    255, 0, 0, 0),
                                            iconColor: const Color.fromARGB(
                                                255, 0, 0, 0),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // ElevatedButton.icon(
                                        //   onPressed: _exportAndNavigate,
                                        //   icon: const Icon(Icons.ios_share_sharp, size: 18),
                                        //   label: Text(L10n.translate(context, 'EXPORT'), style: TextStyle(fontSize: 12)),
                                        //   style: ElevatedButton.styleFrom(
                                        //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        //     shape: RoundedRectangleBorder(
                                        //       borderRadius: BorderRadius.circular(24), // makes it more pill-like
                                        //     ),
                                        //     elevation: 2,
                                        //     backgroundColor: const Color.fromARGB(255, 230, 230, 230),
                                        //     foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                                        //     iconColor: const Color.fromARGB(255, 0, 0, 0),
                                        //   ),
                                        // ),
                                        IconButton(
                                          onPressed: _exportAndNavigate,
                                          icon: const Icon(
                                              Icons.ios_share_sharp,
                                              size: 18),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(
                                                  24), // makes it more pill-like
                                            ),
                                            elevation: 2,
                                            backgroundColor:
                                                const Color.fromARGB(
                                                    255, 230, 230, 230),
                                            foregroundColor:
                                                const Color.fromARGB(
                                                    255, 0, 0, 0),
                                            iconColor: const Color.fromARGB(
                                                255, 0, 0, 0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // VIDEO SECTION
                              // _videoController == null && betterController == null
                              //     ? CustomSelectVideoWidget(onTap: _pickVideoFile)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (_isBasicTier &&
                                          _segments.length == 1) {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor:
                                                const Color(0xFF2C2C2C),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            title: Text(
                                              L10n.translate(
                                                  context, 'Pro Mode Feature'),
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                            content: Text(
                                              L10n.translate(
                                                context,
                                                'Upgrade to Pro mode to import more than 1 video.',
                                              ),
                                              style: TextStyle(
                                                  color: Colors.white70),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
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
                                      _pickVideoFile();
                                    },
                                    key: const ValueKey('video_player'),
                                    child: _audioOnly ||
                                            (_videoController == null &&
                                                betterController == null)
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                                12), // Adjust radius as needed
                                            child: AspectRatio(
                                              aspectRatio: 16 / 9,
                                              child: Container(
                                                color: Colors.black87,
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  Icons.video_camera_back_sharp,
                                                  size: 64,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ),
                                          )
                                        :
                                        // useBetterPlayer ? BetterPlayer(controller: betterController!) : AspectRatio(
                                        //   aspectRatio: aspectRatio,
                                        //   child:VideoPlayer(_videoController!)
                                        // ),
                                        ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: useBetterPlayer
                                                ? BetterPlayer(
                                                    controller:
                                                        betterController!)
                                                : AspectRatio(
                                                    aspectRatio: aspectRatio,
                                                    child: VideoPlayer(
                                                        _videoController!),
                                                  ),
                                          ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _audioOnly
                                          ? SizedBox.shrink()
                                          : IconButton(
                                              icon: Icon(
                                                Icons
                                                    .video_settings, // speaker with lines icon
                                                color: _showAutomationSection
                                                    ? Colors.white
                                                    : const Color.fromARGB(
                                                        255, 230, 230, 230),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _showAutomationSection =
                                                      !_showAutomationSection;
                                                });
                                              },
                                            ),
                                      _audioOnly
                                          ? Container()
                                          : const SizedBox(width: 8),
                                      Expanded(child: _buildTimeDisplay()),
                                      _audioOnly
                                          ? Container()
                                          : const SizedBox(
                                              width:
                                                  48), // balance space taken by IconButton
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // TESTING
                                  // --- Timeline (visualization only) ---
                                  MiniTimelinePro<VideoSegment, AudioTrack>(
                                    // your data
                                    video: _segments, // List<VideoSegment>
                                    audio: _audioTracks
                                        .map((t) => [t])
                                        .toList(), // List<List<AudioTrack>>
                                    // map fields from YOUR models (adjust names if needed)
                                    getVideoStartMs: (v) =>
                                        v.start.inMilliseconds.toDouble(),
                                    getVideoDurationMs: (v) => (v.end - v.start)
                                        .inMilliseconds
                                        .toDouble(),
                                    getVideoThumbPath: (v) => v
                                        .thumbnailPath, // tiled across the block
                                    getVideoLabel: (v) =>
                                        v.path.split('/').last,

                                    getAudioStartMs: (a) =>
                                        a.offset * 1000.0, // seconds → ms
                                    getAudioDurationMs: (a) =>
                                        (a.trimEnd - a.trimStart)
                                            .inMilliseconds
                                            .toDouble(),
                                    getAudioPeaks: (a) => a
                                        .normWaveformData, // List<double> [-1..1]
                                    // playhead binding (keeps the red line in sync)
                                    playheadMs: _audioOnly
                                        ? _globalAudioClock.inMilliseconds
                                            .toDouble()
                                        : _videoPosition.inMilliseconds
                                            .toDouble(),

                                    // scrub anywhere on the ruler or timeline to seek
                                    onScrubRequested: (ms) {
                                      final t =
                                          Duration(milliseconds: ms.round());
                                      // Replace these with your actual seek calls:
                                      _videoController?.seekTo(
                                          t); // or better_player on Android
                                      setState(() => _videoPosition =
                                          t); // keep your state in sync
                                      // If you sync audio tracks too, call your JUCE/engine seek here.
                                    },

                                    scrollController: _timelineScroll,
                                    autoFollow:
                                        true, // edge follow while playing/scrubbing
                                    followEdgePadding: 60,
                                    fixedPlayhead:
                                        true, // set true to pin the line in the viewport
                                    playheadAnchorFraction: 0.5,

                                    // optional tuning
                                    initialPixelsPerSecond: 140, // zoom
                                    minPixelsPerSecond: 10,
                                    maxPixelsPerSecond: 480,
                                    height: 280,
                                    // scrollController: myHorizCtrl, // pass one if you want external sync
                                  ),

                                  // END OF TESTING
                                  if (_showAutomationSection) ...[
                                    GestureDetector(
                                      onVerticalDragDown: (_) {},
                                      behavior: HitTestBehavior.translucent,
                                      child:
                                          _buildVideoAudioAutomationSection(),
                                    ),
                                    const SizedBox(height: 10),
                                  ],

                                  _buildClipList(),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // AUDIO SECTION
                              // _videoFile != null
                              //   ? (_audioTracks.isEmpty
                              //       ? Container()
                              //       : _buildMultiTrackAudioSection())
                              //   : Container(),//_buildAudioControls(),
                              _audioTracks.isEmpty
                                  ? Container()
                                  : _buildMultiTrackAudioSection(),
                              //_buildAudioControls(),
                              // const SizedBox(height: 10),
                              // const SizedBox(height: 60),

                              // Padding(
                              //   padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                              //   child: SizedBox(
                              //     width: double.infinity,
                              //     child: ElevatedButton.icon(
                              //       style: ElevatedButton.styleFrom(
                              //         disabledBackgroundColor: const Color.fromARGB(170, 44, 44, 44),
                              //         backgroundColor: _selectedTrackIndex == -1
                              //             ? Colors.grey.shade600
                              //             : HSLColor.fromColor(Theme.of(context).primaryColor)
                              //                 .withLightness(
                              //                   (HSLColor.fromColor(Theme.of(context).primaryColor).lightness - 0.2)
                              //                       .clamp(0.0, 1.0),
                              //                 )
                              //                 .toColor(),
                              //         padding: const EdgeInsets.symmetric(vertical: 16),
                              //         shape: RoundedRectangleBorder(
                              //           borderRadius: BorderRadius.circular(8),
                              //         ),
                              //       ),
                              //       icon: Icon(Icons.tune, color: _selectedTrackIndex == -1 ? Colors.grey : Colors.white),
                              //       label: Text(
                              //         L10n.translate(context, 'Audio Track Effects'),
                              //         style: TextStyle(color: _selectedTrackIndex == -1 ? Colors.grey : Colors.white),
                              //       ),
                              //       onPressed: _selectedTrackIndex == -1 ? null : () => _openEffectsDrawer(context, _selectedTrackIndex),
                              //     ),
                              //   ),
                              // ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // END OF SINGLECHILDSCROLLVIEW
                  // BELOW IS UI ANIMATIONS
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
                ],
              ),
              bottomNavigationBar: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 0, 16, Platform.isAndroid ? 54 : 36),
                child: SizedBox(
                  height: 64, // or any height you want for the floating bar
                  child: _buildFloatingTransportBar(),
                ),
              ),
              floatingActionButton: Padding(
                padding: const EdgeInsets.only(
                    bottom: 0.0, right: 0.0), // above bottom nav
                child: FloatingActionButton(
                  onPressed: () => _showAddMediaOptions(),
                  backgroundColor: const Color.fromARGB(255, 230, 230, 230),
                  child: const Icon(Icons.add, color: Colors.black),
                  shape: const CircleBorder(),
                  elevation: 4,
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
          ],
        );
      },
    );
  }
}

class VideoSegment {
  String path;
  Duration start, end, totalDuration;
  String thumbnailPath;
  double gain; // 0.0..3.0, default 1.0
  String original,
      greenScreen; // original stores the path in case path gets overwritten with green-screen replacement and we need copy of original path, green screen stores the bg
  double greenScreenStart, greenScreenDuration;
  VideoSegment({
    required this.path,
    required this.start,
    required this.end,
    required this.totalDuration,
    required this.thumbnailPath,
    this.gain = 1.0,
    this.original = '',
    this.greenScreen = '',
    this.greenScreenStart = 0.0,
    this.greenScreenDuration = 0.0,
  });
}

class VideoTrimSlider extends StatefulWidget {
  final Duration initialStart;
  final Duration initialEnd;
  final Duration totalDuration;
  final ValueChanged<Duration> onChangeStart;
  final ValueChanged<Duration> onChangeEnd;

  const VideoTrimSlider({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.totalDuration,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  @override
  State<VideoTrimSlider> createState() => _VideoTrimSliderState();
}

class _VideoTrimSliderState extends State<VideoTrimSlider> {
  late RangeValues _range;

  static const double _minGapMs = 100;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(widget.initialStart.inMilliseconds.toDouble(),
        widget.initialEnd.inMilliseconds.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.totalDuration.inMilliseconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   'Trim: ${_format(_range.start)} → ${_format(_range.end)}',
        //   style: const TextStyle(fontSize: 14),
        // ),
        Text(
          '${L10n.translate(context, 'Trim')}: ${_formatDuration(Duration(milliseconds: _range.start.toInt()))} - ${_formatDuration(Duration(milliseconds: _range.end.toInt()))}',
          style: const TextStyle(fontSize: 14),
        ),
        // const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: RangeSlider(
            activeColor: const Color.fromARGB(255, 255, 255, 255),
            min: 0,
            max: maxMs,
            divisions: 2000, //maxMs ~/ 500,
            values: _range,
            onChanged: (values) {
              double start = values.start;
              double end = values.end;

              // Prevent crossing and ensure minimum trim duration
              if (end - start < _minGapMs) {
                if (_range.start != start) {
                  start = end - _minGapMs;
                } else {
                  end = start + _minGapMs;
                }
              }

              setState(() {
                _range =
                    RangeValues(start.clamp(0, maxMs), end.clamp(0, maxMs));
              });
            },
            onChangeEnd: (values) {
              widget
                  .onChangeStart(Duration(milliseconds: _range.start.toInt()));
              widget.onChangeEnd(Duration(milliseconds: _range.end.toInt()));
            },
          ),
        ),
      ],
    );
  }

  String _format(double ms) {
    final d = Duration(milliseconds: ms.toInt());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

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
}

class CustomSelectVideoWidget extends StatelessWidget {
  final VoidCallback onTap;
  const CustomSelectVideoWidget({Key? key, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam,
                          size: 48, color: const Color(0xFF2E61A5)),
                      const SizedBox(height: 8),
                      Text(
                        L10n.translate(context, 'Select Video'),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF2E61A5)),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: CornerPainter(
                      cornerLength: 20,
                      strokeWidth: 3,
                      color: const Color(0xFF2E61A5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomSelectModeWidget extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String text;

  const CustomSelectModeWidget(
      {Key? key, required this.onTap, required this.icon, required this.text})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 48, color: const Color(0xFF2E61A5)),
                      const SizedBox(height: 8),
                      Text(
                        text,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF2E61A5)),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: CornerPainter(
                      cornerLength: 20,
                      strokeWidth: 3,
                      color: const Color(0xFF2E61A5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CornerPainter extends CustomPainter {
  final double cornerLength;
  final double strokeWidth;
  final Color color;

  CornerPainter({
    this.cornerLength = 20.0,
    this.strokeWidth = 3.0,
    this.color = const Color(0xFF2E61A5), // your red-ish color
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // Top left corner
    canvas.drawLine(Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(0, cornerLength), paint);

    // Top right corner
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // Bottom left corner
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - cornerLength), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(cornerLength, size.height), paint);

    // Bottom right corner
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
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
    final normalized = (audioPosition - trimStart).inMilliseconds /
        trimmedDuration.inMilliseconds;

    // Compute X in the total waveform:
    final trimStartRatio =
        trimStart.inMilliseconds / totalAudioDuration.inMilliseconds;
    final trimEndRatio =
        trimEnd.inMilliseconds / totalAudioDuration.inMilliseconds;

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
  })  : currentPosition = currentPosition ?? Duration.zero,
        volumeAutomation = volumeAutomation ??
            [
              AutomationPoint(x: 0.0, volume: 1.0),
              AutomationPoint(x: 1.0, volume: 1.0)
            ];

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

class AutomationPoint {
  double x; // normalized x (0.0 = left, 1.0 = right)
  double volume; // normalized volume (0.0 = silent, 1.0 = full)
  AutomationPoint({required this.x, required this.volume});
}

class VolumeAutomationWidget extends StatefulWidget {
  final List<AutomationPoint> automationPoints;
  final double
      currentNormalizedTime; // normalized current playback time (0.0 to 1.0)
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
        return _points[i].volume +
            t * (_points[i + 1].volume - _points[i].volume);
      }
    }
    return 1.0;
  }

  Widget _buildDraggableHandle(
      AutomationPoint point, double width, double height) {
    const double visibleHandleSize = 24;
    const double hitBoxSize = 48;

    const double edgeExtension =
        16; // How much extra space to provide at the edges

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
                painter: _AutomationPainter(
                    points: _points,
                    currentNormalizedTime: widget.currentNormalizedTime),
              ),
              for (var point in _points)
                _buildDraggableHandle(point, width, height),
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
  _AutomationPainter(
      {required this.points, required this.currentNormalizedTime});

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
    double seekX = currentNormalizedTime.isFinite
        ? currentNormalizedTime * size.width
        : 0.0;
    Paint seekPaint = Paint()
      ..color = Color(0xFF888888)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(seekX, 0), Offset(seekX, size.height), seekPaint);
  }

  @override
  bool shouldRepaint(covariant _AutomationPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.currentNormalizedTime != currentNormalizedTime;
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

// VIDEO AUDIO AUTOMATION CURVE
class VideoAudioAutomationWidget extends StatefulWidget {
  final List<AutomationPoint> automationPoints;
  final double currentNormalizedTime; // normalized (0.0 to 1.0)
  final ValueChanged<List<AutomationPoint>> onAutomationChanged;

  const VideoAudioAutomationWidget({
    Key? key,
    required this.automationPoints,
    required this.currentNormalizedTime,
    required this.onAutomationChanged,
  }) : super(key: key);

  @override
  _VideoAudioAutomationWidgetState createState() =>
      _VideoAudioAutomationWidgetState();
}

class _VideoAudioAutomationWidgetState
    extends State<VideoAudioAutomationWidget> {
  late List<AutomationPoint> _points;
  static const double _autoSnapNorm = 0.02;
  @override
  void initState() {
    super.initState();
    // Create a mutable copy of the automation points.
    _points = List.from(widget.automationPoints);
  }

  @override
  void didUpdateWidget(covariant VideoAudioAutomationWidget oldWidget) {
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
        return _points[i].volume +
            t * (_points[i + 1].volume - _points[i].volume);
      }
    }
    return 1.0;
  }

  Widget _buildDraggableHandle(
      AutomationPoint point, double width, double height) {
    const double visibleHandleSize = 24;
    const double hitBoxSize = 48;

    const double edgeExtension =
        16; // How much extra space to provide at the edges

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
                // TODO: Offset argument contained a NaN value.
                size: Size(width, height),
                painter: _AutomationPainter(
                    points: _points,
                    currentNormalizedTime: widget.currentNormalizedTime),
              ),
              for (var point in _points)
                _buildDraggableHandle(point, width, height),
            ],
          ),
        );
      },
    );
  }
}
// VIDEO AUDIO AUTOMATION CURVE END

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

String generateVolumeAutomationFilterForVideo(
  List<AutomationPoint> points,
  double durationSec,
  int offsetMs,
  double universalCrossfade,
) {
  // If no automation points are defined, default to the crossfaded volume.
  if (points.isEmpty) return "(${min(1.0, (1.0 - universalCrossfade) * 2)})";

  // Choose a small epsilon (in seconds) to smooth boundaries.
  double epsilon = 0.01;
  List<String> conditions = [];

  // For each pair of automation points, create a condition with epsilon margins.
  for (int i = 0; i < points.length - 1; i++) {
    AutomationPoint startPoint = points[i];
    AutomationPoint endPoint = points[i + 1];
    // Scale normalized positions by duration.
    double startTime = startPoint.x * durationSec;
    double endTime = endPoint.x * durationSec;
    // Build a condition with an epsilon margin.
    conditions.add(
      "if(between(t,${(startTime - epsilon).toStringAsFixed(3)},${(endTime + epsilon).toStringAsFixed(3)}),"
      "${startPoint.volume}+(${endPoint.volume}-${startPoint.volume})*((t-${startTime.toStringAsFixed(3)})/(${(endTime - startTime).toStringAsFixed(3)})),",
    );
  }
  // Close all nested ifs.
  String closing = ")" * (points.length - 1);
  // Default value if none of the conditions match.
  String automationExpr = "${conditions.join("")}1.0$closing";

  // Multiply the whole expression by (1 - universalCrossfade)
  return "'($automationExpr)*(${(min(1.0, (1.0 - universalCrossfade) * 2)).toStringAsFixed(2)})'";
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
    if (widget.videoFile.isNotEmpty) {
      _loadThumbnail();
    }
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

  Future<void> _loadThumbnail() async {
    final thumb = await VideoThumbnail.thumbnailData(
      video: widget.videoFile,
      imageFormat: ImageFormat.JPEG,
      quality: 75,
    );
    setState(() => _thumbnail = thumb);
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
              // Stack(
              //   alignment: Alignment.center,
              //   children: [
              //     ClipRRect(
              //       borderRadius: BorderRadius.circular(8),
              //       child: Image.memory(_thumbnail!, height: 160),
              //     ),
              //     Text(
              //       "${(_progress * 100).toStringAsFixed(0)}%",
              //       style: const TextStyle(
              //         color: Colors.white,
              //         fontSize: 24,
              //         fontWeight: FontWeight.bold,
              //         shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              //       ),
              //     ),
              //   ],
              // ),
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
  final String? savedFilePath;
  final String? savedFileName;
  final bool isVideo;

  const ExportSuccessScreen(
      {super.key,
      required this.filePath,
      required this.isVideo,
      this.savedFilePath,
      this.savedFileName});

  String _resolvedFileName() {
    final explicit = savedFileName?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final saved = savedFilePath?.trim();
    if (saved != null && saved.isNotEmpty) {
      return p.basename(saved);
    }

    return p.basename(filePath);
  }

  String _openSavedLabel(BuildContext context) {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      return L10n.translate(context, 'Open in Files');
    }
    return L10n.translate(context, 'Open saved file');
  }

  bool _isUriLikePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.contains('://');
  }

  String _normalizedCandidatePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!_isUriLikePath(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return trimmed;
  }

  String _resolvedActionPath() {
    final saved = savedFilePath?.trim();
    if (saved != null && saved.isNotEmpty) {
      return _normalizedCandidatePath(saved);
    }
    return _normalizedCandidatePath(filePath);
  }

  String _resolvedPreviewPath() {
    final saved = savedFilePath?.trim();
    if (saved == null || saved.isEmpty) {
      return filePath;
    }
    final normalizedSaved = _normalizedCandidatePath(saved);
    if (!_isUriLikePath(normalizedSaved) &&
        File(normalizedSaved).existsSync()) {
      return normalizedSaved;
    }
    return filePath;
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      await Share.shareXFiles([
        XFile(
          _resolvedActionPath(),
          name: _resolvedFileName(),
        )
      ]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share.')), // ${e.toString()}')),
      );
    }
  }

  Future<void> _openSavedFile(BuildContext context) async {
    final candidates = <String>[
      if ((savedFilePath ?? '').trim().isNotEmpty)
        _normalizedCandidatePath(savedFilePath!),
      _normalizedCandidatePath(filePath),
    ];

    for (final candidate in candidates) {
      try {
        if (_isUriLikePath(candidate)) {
          final launched = await launchUrl(Uri.parse(candidate));
          if (launched) {
            return;
          }
        }
        final result = await OpenFile.open(candidate);
        if (result.type == ResultType.done) {
          return;
        }
      } catch (_) {
        // Try the next candidate before surfacing a failure.
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.translate(context, 'Could not open the saved export.'),
        ),
      ),
    );
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
      SnackBar(
        content: Text(
          L10n.translate(context, 'Platform upload coming soon'),
        ),
      ),
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
          title: Text(L10n.translate(context, 'Upload to YouTube')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: L10n.translate(context, 'Title'),
                ),
              ),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: L10n.translate(context, 'Description'),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(L10n.translate(context, 'Cancel'))),
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
              child: Text(L10n.translate(context, 'Upload')),
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
          title: Text(L10n.translate(context, 'Video Uploaded')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L10n.translate(context, 'Your video is live!')),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(qrImage,
                    width: 280, height: 158, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text(L10n.translate(context, 'Save Image')),
                onPressed: () async {
                  final result = await ImageGallerySaver.saveFile(qrImage.path);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(result['isSuccess'] == true
                            ? L10n.translate(context, 'Saved to gallery!')
                            : L10n.translate(context, 'Failed to save'))),
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
                        filePath: _resolvedPreviewPath(),
                        displayName: _resolvedFileName(),
                        isVideo: isVideo,
                      ),
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
                              onPressed: () => _openSavedFile(context),
                              icon: const Icon(Icons.folder_open_rounded,
                                  size: 20),
                              label: Text(_openSavedLabel(context)),
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showUploadComingSoon(context),
                          icon:
                              const Icon(Icons.cloud_upload_rounded, size: 20),
                          label: Text(
                            L10n.translate(context, 'Upload to platform'),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: Colors.white70,
                            side: const BorderSide(
                              color: Color(0xFF4F5A73),
                            ),
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('${L10n.translate(context, 'Thumbnail saved to ')}${file.path}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.translate(context, 'YouTube QR Thumbnail')),
      ),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(L10n.translate(context, 'Your video has been uploaded!')),
            const SizedBox(height: 20),
            QrImageView(data: videoUrl, size: 200),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => _saveThumbnailWithQR(context),
                child: Text(
                  L10n.translate(context, 'Download QR Thumbnail'),
                )),
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

// EFFECTS DRAWER START

class EffectsDrawer extends StatefulWidget {
  final int trackIndex;
  final String mode;
  final bool? isProEntitled;
  const EffectsDrawer({
    Key? key,
    required this.trackIndex,
    this.mode = "Basic",
    this.isProEntitled,
  }) : super(key: key);

  @override
  _EffectsDrawerState createState() => _EffectsDrawerState();
}

class _EffectsDrawerState extends State<EffectsDrawer> {
  List<String> _effects = [];
  List<bool> _bypassed = [];
  bool _loading = true;

  bool _subscriptionCapabilityOrLegacy(String capability) {
    try {
      return context.read<EntitlementService>().canUseCapability(capability);
    } catch (_) {
      return widget.mode == 'Pro';
    }
  }

  bool get _isProEntitled {
    final explicit = widget.isProEntitled;
    if (explicit != null) return explicit;
    return _subscriptionCapabilityOrLegacy(SubscriptionCapability.proEditor);
  }

  bool get _isBasicTier => !_isProEntitled;

  @override
  void initState() {
    super.initState();
    _loadEffects();
  }

  Future<void> _loadEffects() async {
    final names = await JuceAudioEngine.getTrackEffects(widget.trackIndex);
    final bypassStates = await Future.wait(
      List.generate(names.length, (index) async {
        return await JuceAudioEngine.getPluginBypassState(
            widget.trackIndex, index);
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
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
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

                Text(L10n.translate(context, 'Presets'),
                    style: Theme.of(context).textTheme.headlineSmall),
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

                  children: [
                    for (int i = 0; i < _effects.length; i++)
                      _buildEffectTile(i)
                  ],

                  proxyDecorator: (child, index, animation) => Material(
                      elevation: 6,
                      color: const Color.fromARGB(154, 130, 130, 130),
                      child: child),

                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < 0 || oldIndex >= _effects.length) return;
                    if (newIndex > oldIndex) newIndex--;
                    newIndex = newIndex.clamp(0, _effects.length - 1);

                    await JuceAudioEngine.reorderEffects(
                        widget.trackIndex, oldIndex, newIndex);
                    setState(() {
                      final name = _effects.removeAt(oldIndex);
                      final bypass = _bypassed.removeAt(oldIndex);
                      _effects.insert(newIndex, name);
                      _bypassed.insert(newIndex, bypass);
                    });
                  },
                ),

                if (_effects.length < 5)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildAddTile()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = []; //['LoFi Effect', 'Heavy Crunch'];
    final isLocked = _isBasicTier && lockedPresets.contains(name);

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
              color: isLocked
                  ? const Color.fromARGB(255, 122, 122, 122)
                  : const Color.fromARGB(255, 255, 255, 255),
            ),
          ),
          if (isLocked)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock,
                  size: 16, color: Color.fromARGB(255, 122, 122, 122)),
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
          return L10n.translate(context,
              'Applies wide reverb and subtle EQ to simulate a live concert space.');
        case 'Echoes':
          return L10n.translate(
              context, 'Applies reverb and delay to give an echo effect.');
        case 'LoFi Effect':
          return L10n.translate(context,
              'Applies filters and soft distortion for a vintage, relaxed vibe.');
        case 'Heavy Crunch':
          return L10n.translate(
              context, 'Crushes sound with heavy distortion.');
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
            child: Text(L10n.translate(context, 'Cancel'),
                style: TextStyle(color: Color.fromARGB(255, 218, 218, 218))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, true);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
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
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom Reverb');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Room Size', 53);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Mix', 20);
                  break;

                case 'Echoes':
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom Reverb');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Room Size', 40);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Mix', 20);
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom Delay');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Delay Time', 400);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Feedback', 30);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Mix', 30);
                  break;

                case 'LoFi Effect':
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom EQ');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'LPF Frequency', 2600.0);
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom Distortion');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Drive', 50);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Mix', 85);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Anger', 1);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'LPF Frequency', 2800.0);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 1, 'Distortion Type', "Mode 3");
                  break;

                case 'Heavy Crunch':
                  await JuceAudioEngine.insertEffect(
                      widget.trackIndex, 'Mixroom Distortion');
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Drive', 100);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Mix', 100);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Anger', 1);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Volume', 12);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Pre Shape', 3.0);
                  await JuceAudioEngine.setEffect(
                      widget.trackIndex, 0, 'Distortion Type', "Mode 3");
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
                JuceAudioEngine.bypassPlugin(
                    widget.trackIndex, idx, shouldBypass);
                setState(() => _bypassed[idx] = shouldBypass);
              },
              activeColor: const Color.fromARGB(
                  255, 231, 231, 231), // thumb color when ON
              inactiveThumbColor: const Color.fromARGB(
                  255, 186, 186, 186), // thumb color when OFF
              inactiveTrackColor: const Color.fromARGB(
                  255, 235, 235, 235), // track color when OFF
              activeTrackColor:
                  const Color.fromARGB(255, 54, 54, 54), // track color when ON
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color.fromARGB(255, 255, 164, 164)),
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
            child: Text(L10n.translate(context, 'Cancel'),
                style: TextStyle(color: Color.fromARGB(255, 218, 218, 218))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete'),
                style: TextStyle(color: Colors.red)),
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
    const allowedInBasic = [
      'Mixroom Reverb',
      'Mixroom EQ',
      'Mixroom Delay',
      'Mixroom Distortion',
      'Mixroom De-Esser',
      'Mixroom Clipper'
    ];

    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color.fromARGB(255, 79, 79, 79),
            titlePadding:
                const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
            contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      'Mixroom De-Esser',
                      'Mixroom Clipper'
                    ].map((name) {
                      final isAllowed =
                          _isProEntitled || allowedInBasic.contains(name);
                      return GestureDetector(
                        onTap: isAllowed
                            ? () async {
                                Navigator.pop(context);
                                await JuceAudioEngine.insertEffect(
                                    widget.trackIndex, name);
                                await _loadEffects();
                              }
                            : null,
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            title: Text(name),
                            trailing: isAllowed
                                ? null
                                : const Icon(Icons.lock,
                                    size: 18, color: Colors.white70),
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
                          await JuceAudioEngine.insertEffect(
                              widget.trackIndex, path);
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
    var params =
        await JuceAudioEngine.getPluginParameters(widget.trackIndex, idx);

    // Limit what parameters are shown if it's basic mode
    if (_isBasicTier) {
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
            ].contains(
                name); //['HPF Frequency', 'HPF Slope', 'LPF Frequency', 'LPF Slope'].contains(name);
          }).toList();
          break;

        case 'Mixroom Delay':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Delay Time', 'Feedback', 'Mix'].contains(name);
          }).toList();
          break;

        case 'Mixroom Clipper':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Threshold', 'Ceiling'].contains(name);
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(height: 16),
                        Text('Mixroom EQ',
                            style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Divider(
                            color: Color.fromARGB(213, 104, 104, 104)),

                        // Preview with bands
                        _EqPreviewFull(
                            hpfHz: hpfHz,
                            lpfHz: lpfHz,
                            bandGains: bandGains,
                            bandFreqs: bandFreqs),
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pHPF['name'] as String,
                                          v);
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pB1['name'] as String,
                                          v);
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pB2['name'] as String,
                                          v);
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pB3['name'] as String,
                                          v);
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pB4['name'] as String,
                                          v);
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
                                      JuceAudioEngine.setEffect(
                                          widget.trackIndex,
                                          idx,
                                          pLPF['name'] as String,
                                          v);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const Divider(
                            color: Color.fromARGB(213, 104, 104, 104)),
                        const SizedBox(height: 16),
                        TextButton(
                          child: Text(
                            'Close',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
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
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    // crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)),
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
                                Text(param['name'] as String,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    // 1) min label
                                    Text(
                                      (param['min'] as num)
                                          .toDouble()
                                          .toStringAsFixed(2),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 8),

                                    // 2) the slider with value indicator
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          showValueIndicator:
                                              ShowValueIndicator.always,
                                          valueIndicatorTextStyle: TextStyle(
                                            color: const Color.fromARGB(
                                                255, 0, 0, 0),
                                            fontSize: 12,
                                          ),
                                        ),
                                        child: Slider(
                                          value: (param['value'] as num)
                                              .toDouble()
                                              .clamp(
                                                (param['min'] as num)
                                                    .toDouble(),
                                                (param['max'] as num)
                                                    .toDouble(),
                                              ),
                                          min: (param['min'] as num).toDouble(),
                                          max: (param['max'] as num).toDouble(),
                                          divisions:
                                              100, // or compute a sensible number
                                          label: (param['value'] as num)
                                              .toDouble()
                                              .toStringAsFixed(2),
                                          onChanged: (v) {
                                            setModalState(
                                                () => param['value'] = v);
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
                                          onChangeEnd: (v) =>
                                              {}, // originally put JuceAudioEngine.setEffect here
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // 3) max label
                                    Text(
                                      (param['max'] as num)
                                          .toDouble()
                                          .toStringAsFixed(2),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
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
                              JuceAudioEngine.setEffect(widget.trackIndex, idx,
                                  param['name'] as String, v);
                            }),
                          ),
                        ] else if (param['type'] == 'choice') ...[
                          (() {
                            final keys = param.keys
                                .where((k) => k.startsWith('choice_'))
                                .toList()
                              ..sort((a, b) {
                                final ai = int.parse(a.split('_')[1]);
                                final bi = int.parse(b.split('_')[1]);
                                return ai.compareTo(bi);
                              });
                            // 2) build the labels
                            final choices =
                                keys.map((k) => param[k] as String).toList();
                            // 3) current
                            final current = param['value'] as String;
                            // 4) render a ListTile that pops a dialog
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(param['name'] as String),
                                trailing: Text(current,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge),
                                onTap: () async {
                                  final picked = await showDialog<String>(
                                    context: context,
                                    useRootNavigator: true,
                                    builder: (ctx) => SimpleDialog(
                                      title: Text(
                                          "${L10n.translate(context, 'Select ')}${param['name']}"),
                                      children: choices.map((c) {
                                        return SimpleDialogOption(
                                          child: Text(c),
                                          onPressed: () =>
                                              Navigator.pop(ctx, c),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                  if (picked != null) {
                                    setModalState(
                                        () => param['value'] = picked);
                                    JuceAudioEngine.setEffect(widget.trackIndex,
                                        idx, param['name'] as String, picked);
                                  }
                                },
                              ),
                            );
                          })(),
                        ] else ...[
                          ListTile(
                              title: Text(param['name'] as String),
                              trailing: Text("${param['value']}")),
                        ],
                      ],

                      const Divider(color: Color.fromARGB(213, 104, 104, 104)),
                      const SizedBox(height: 16),
                      TextButton(
                        child: Text(
                          L10n.translate(context, 'Close'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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

  Widget _buildGenericParamsSheet(
      BuildContext ctx, StateSetter setModalState, List params, int idx) {
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
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(L10n.translate(context, 'Parameters'),
                  style: Theme.of(ctx).textTheme.titleLarge),
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
                        Text(param['name'] as String,
                            style: Theme.of(ctx).textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              (param['min'] as num)
                                  .toDouble()
                                  .toStringAsFixed(2),
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(ctx).copyWith(
                                  showValueIndicator: ShowValueIndicator.always,
                                  valueIndicatorTextStyle: const TextStyle(
                                      color: Colors.black, fontSize: 12),
                                ),
                                child: Slider(
                                  value:
                                      (param['value'] as num).toDouble().clamp(
                                            (param['min'] as num).toDouble(),
                                            (param['max'] as num).toDouble(),
                                          ),
                                  min: (param['min'] as num).toDouble(),
                                  max: (param['max'] as num).toDouble(),
                                  divisions: 100,
                                  label: (param['value'] as num)
                                      .toDouble()
                                      .toStringAsFixed(2),
                                  onChanged: (v) {
                                    setModalState(() => param['value'] = v);
                                    JuceAudioEngine.setEffect(widget.trackIndex,
                                        idx, param['name'] as String, v);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (param['max'] as num)
                                  .toDouble()
                                  .toStringAsFixed(2),
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
                      JuceAudioEngine.setEffect(
                          widget.trackIndex, idx, param['name'] as String, v);
                    },
                  ),
                ] else if (param['type'] == 'choice') ...[
                  (() {
                    final keys = param.keys
                        .where((k) => k.startsWith('choice_'))
                        .toList()
                      ..sort((a, b) => int.parse(a.split('_')[1])
                          .compareTo(int.parse(b.split('_')[1])));
                    final choices =
                        keys.map((k) => param[k] as String).toList();
                    final current = param['value'] as String;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(param['name'] as String),
                        trailing: Text(current,
                            style: Theme.of(ctx).textTheme.bodyLarge),
                        onTap: () async {
                          final picked = await showDialog<String>(
                            context: ctx,
                            useRootNavigator: true,
                            builder: (dCtx) => SimpleDialog(
                              title: Text(
                                  "${L10n.translate(context, 'Select ')}${param['name']}"),
                              children: choices.map((c) {
                                return SimpleDialogOption(
                                    child: Text(c),
                                    onPressed: () => Navigator.pop(dCtx, c));
                              }).toList(),
                            ),
                          );
                          if (picked != null) {
                            setModalState(() => param['value'] = picked);
                            JuceAudioEngine.setEffect(widget.trackIndex, idx,
                                param['name'] as String, picked);
                          }
                        },
                      ),
                    );
                  })(),
                ] else ...[
                  ListTile(
                      title: Text(param['name'] as String),
                      trailing: Text("${param['value']}")),
                ],
              ],
              const Divider(color: Color.fromARGB(213, 104, 104, 104)),
              const SizedBox(height: 16),
              TextButton(
                child: Text(
                  L10n.translate(context, 'Close'),
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
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
          items: choices
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
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
          return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => onPick(label));
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
  final pos = logarithmic
      ? _toLogPos(value, min, max)
      : ((value.clamp(min, max) - min) / (max - min));

  final labelText = (unit == 'Hz')
      ? '${_fmtHz(value)} Hz'
      : (unit == null
          ? value.toStringAsFixed(0)
          : '${value.toStringAsFixed(0)} $unit');

  return SizedBox(
    width: width, // 👈 respect caller width
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(labelText,
            style: Theme.of(context).textTheme.labelMedium,
            overflow: TextOverflow.ellipsis),
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
                  final v = logarithmic
                      ? _fromLogPos(p, min, max)
                      : (min + (max - min) * p);
                  onChanged(v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2),
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
          painter: _EqPreviewPainter(
              hpfHz: hpfHz,
              lpfHz: lpfHz,
              hpfSlope: hpfSlope,
              lpfSlope: lpfSlope),
        ),
      ),
    );
  }
}

class _EqPreviewPainter extends CustomPainter {
  final double hpfHz, lpfHz;
  final int hpfSlope, lpfSlope;

  _EqPreviewPainter(
      {required this.hpfHz,
      required this.lpfHz,
      required this.hpfSlope,
      required this.lpfSlope});

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
    final t =
        (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
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
      ..cubicTo(xHPF0 + (wHPFpx * 0.35), floorY, xHPF - (wHPFpx * 0.15), kneeY,
          xHPF, passbandY)
      // Flat passband to LPF cutoff
      ..lineTo(xLPF, passbandY)
      // LPF cubic: passband → floor
      ..cubicTo(xLPF + (wLPFpx * 0.15), passbandY, xLPF1 - (wLPFpx * 0.35),
          floorY, xLPF1, floorY)
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
      ..cubicTo(xHPF0 + (wHPFpx * 0.35), floorY, xHPF - (wHPFpx * 0.15), kneeY,
          xHPF, passbandY)
      ..lineTo(xLPF, passbandY)
      ..cubicTo(xLPF + (wLPFpx * 0.15), passbandY, xLPF1 - (wLPFpx * 0.35),
          floorY, xLPF1, floorY)
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
          painter: _EqPreviewFullPainter(
              hpfHz: hpfHz,
              lpfHz: lpfHz,
              bandGains: bandGains,
              bandFreqs: bandFreqs),
        ),
      ),
    );
  }
}

class _EqPreviewFullPainter extends CustomPainter {
  final double hpfHz, lpfHz;
  final List<double> bandGains;
  final List<double> bandFreqs;

  _EqPreviewFullPainter(
      {required this.hpfHz,
      required this.lpfHz,
      required this.bandGains,
      required this.bandFreqs});

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  double _log2(num x) => math.log(x) / math.ln2;

  // map Hz → log X position
  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF);
    final t =
        (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
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
    return old.hpfHz != hpfHz ||
        old.lpfHz != lpfHz ||
        old.bandGains != bandGains;
  }
}

// EFFECTS DRAWER END
