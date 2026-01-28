// import 'dart:async';
// import 'dart:io';
// import 'dart:isolate';
// import 'dart:ui';
// import 'package:audio_waveforms/audio_waveforms.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/log.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
// import 'package:ffmpeg_kit_flutter_full_gpl/session.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/scheduler.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// import 'package:mixroom/l10n/l10n.dart';
// import 'package:mixroom/providers/locale_provider.dart';
// import 'package:mixroom/widgets/side_menu.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:provider/provider.dart';
// import 'package:video_player/video_player.dart';
// import 'dart:typed_data';
// import 'dart:math';
// import 'package:flutter/foundation.dart';
// import 'package:fftea/fftea.dart';
// // import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// // import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// import 'package:better_player/better_player.dart';
// import 'package:share_plus/share_plus.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:juce_audio_engine/juce_audio_engine.dart';
// import 'package:video_thumbnail/video_thumbnail.dart';

// Completer<void> _cancelSignal = Completer();

// // ----------------- //
// // VIDEO EDITOR SCREEN //
// // ----------------- //
// class VideoEditorScreen extends StatefulWidget {
//   final String mode;

//   const VideoEditorScreen({Key? key, required this.mode}) : super(key: key);
//   @override
//   State<VideoEditorScreen> createState() => _VideoEditorScreenState();
// }

// class _VideoEditorScreenState extends State<VideoEditorScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
//   // Video variables
//   bool useBetterPlayer = false;
//   File? _videoFile;
//   VideoPlayerController? _videoController;
//   BetterPlayerController? betterController;
//   Duration _videoDuration = Duration.zero;
//   Duration _videoPosition = Duration.zero;
//   Duration _scrubPosition = Duration.zero;
//   bool _isScrubbing = false;
//   bool _isPlaying = false;

//   // Multi-track support
//   List<AudioTrack> _audioTracks = []; // ONLY NEED TO USE THIS FOR MULTI-TRACK
//   double _universalCrossfade = 0.5;

//   // video audio automation
//   List<AutomationPoint> videoAudioAutomation = [
//     AutomationPoint(x: 0.0, volume: 1.0),
//     AutomationPoint(x: 1.0, volume: 1.0),
//   ];

//   // UI: AI sync progress bar
//   bool _isSyncing = false;
//   double _syncProgress = 0.0;

//   // for bluetooth connection
//   bool _isScanning = false;
//   bool _isConnecting = false;
//   bool _deviceFound = false;
//   double _downloadProgress = 0.0;
//   bool _showProgressDialog = false;
//   String _progressMessage = "";
//   String _currentOperation = "";
//   List<String> _guitarFiles = [];

//   late Ticker _ticker;
//   Duration _lastKnownPosition = Duration.zero;

//   // audio-only mode
//   bool _audioOnly = false;
//   Duration _audioOnlyOverallDuration = Duration.zero;

//   // A timer to update automation and the scrubber in audio-only mode.
//   Timer? _audioAutomationTimer;
//   Duration _globalAudioClock = Duration.zero;

//   // string of export filter to pass to effects screen
//   String filterString = "";

//   // when press play, need to pre-warm audio, but volume should be muted during pre-warm
//   bool _preWarmState = false;

//     // PICK VIDEO
//   bool _isPickingFile = false; // Add this flag to track file picker state
//   bool _isLoadingVideo = false;
//   bool _isLoadingAudio = false;
//   bool _isLoadingNextScreen = false;

//   StateSetter? _audioEditorStateSetter; // Store the StateSetter

//   // for snapping automation points to seek line
//   static const double _trimSnapPx = 8.0;
//   static const double _autoSnapNorm = 0.02; 

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     prewarmFFT(); // so that AI sync first run is not heavy
//     // Initialize the ticker to update every ~16ms (about 60fps)
//     _ticker = createTicker((elapsed) async {
//       // Use the elapsed time to compute an interpolated position.
//       // For instance, add elapsed to _lastKnownPosition and update UI.
//       final interpolatedPosition = _lastKnownPosition + elapsed;
//       _updatePosition(interpolatedPosition);
//     });
//     if (defaultTargetPlatform == TargetPlatform.android) {
//       useBetterPlayer = true;
//     }

//     JuceAudioEngine.initialise();
//     JuceAudioEngine.initialiseEventListeners();
//   }

//   Future<void> _startTicker() async {
//     // Stop any previous ticker.
//     _ticker.stop();
//     // Get the current position from the video controller.
//     _lastKnownPosition = _videoPosition;//_videoController!.value.position;
//     _ticker.start();
//   }

//   Future<void> _stopTicker() async {
//     _ticker.stop();
//   }

//   void _updatePosition(Duration position) async {
//     setState(() {
//       // Update videoPosition and scrubPosition at a high frequency.
//       _videoPosition = position;
//       _scrubPosition = position;
//       if (position.inMilliseconds >
//           _videoDuration.inMilliseconds) {
//         _videoPosition = duration;//position;
//         _scrubPosition = duration;
//         for (var track in _audioTracks) {
//           // track.player.pause();
//           track.audioStarted = false;
//         }
//         JuceAudioEngine.pause();
//         // Optionally update _isPlaying state if needed.
//         setState(() {
//           _isPlaying = false;
//         });
//         _pausePlayback();
//         _stopTicker();
//       }
//     });

//     if (!_isScrubbing && mounted && _isPlaying) {
        
//         if (betterController?.isVideoInitialized() != null || _videoController!.value.isInitialized) {
//           double normalizedTime = position.inMilliseconds / 
//                                   duration.inMilliseconds;
//           // Compute the volume using your video automation curve (which you store in a variable, e.g., videoAudioAutomation)
//           double automationVolume = getVolumeForAutomation(videoAudioAutomation, normalizedTime);
      
//           // Combine the crossfade factor and automation volume.
//           double finalVolume = min(1.0, (1.0 - _universalCrossfade) * 2) * automationVolume;
          
//           // Update video player volume.
//           _updateVideoVolume(finalVolume);
//         }

//         for (int i = 0; i < _audioTracks.length; i++) {
//           final track = _audioTracks[i];
//           final seconds = await JuceAudioEngine.getCurrentPosition(i);
//           track.currentPosition = Duration(microseconds: (seconds * 1e6).round());

//           if(track.currentPosition >= track.trimEnd) {
//             await JuceAudioEngine.bypassTrack(i, true);
//             continue;
//           }
          
//           // NOTE THAT this drift doesn't indicate the true distance between the video
//           // and audio because the ticker is slightly off from the video
//           // print("drift: ${((_videoPosition - track.currentPosition).inMilliseconds/10).round()/100}");
          
//           final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
//           if (position >= offsetDuration) {
//             // Calculate how far the audio has progressed relative to its trim range.
//             final effectiveTime = position - offsetDuration;
//             final effectiveDuration = track.trimEnd - track.trimStart;
//             double normalizedTime = effectiveDuration.inMilliseconds > 0
//                 ? effectiveTime.inMilliseconds / effectiveDuration.inMilliseconds
//                 : 0.0;
//             normalizedTime = normalizedTime.clamp(0.0, 1.0);
            
//             // Compute the new volume from the automation curve.
//             double newVolume = getVolumeForAutomation(track.volumeAutomation, normalizedTime);
            
//             // Optionally, combine this with your universal crossfade if desired.
//             // For example, multiply with _universalCrossfade:
//             newVolume *= min(1.0, _universalCrossfade * 2);

//             // COMMENT OUT BECAUSE WE DO MAKE A NEW MP3 TIME GAIN IS CHANGED
//             newVolume *= track.gain; // adjust for gain // this should not be above 1.0
            
//             // SETVOLUME (1.0>) LEADS TO BUG IN THIS AUDIO PKG
//             // Update the audio track volume.
//             if(!_preWarmState) {
//               // track.player.setVolume(newVolume);
//               JuceAudioEngine.setTrackVolume(i, newVolume);
//             }
            
//             // If the track hasn’t started yet, start it.
//             if (!track.audioStarted) {
//               continue;
//             }
//           }
//         }
//       }
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _ticker.dispose();
//     _videoController?.dispose();
//     betterController?.dispose();
//     for (var track in _audioTracks) {
//       // track.player.dispose();
//       track.waveformController.dispose();
//       track.audioStartTimer?.cancel();
//     }
//     // JuceAudioEngine.shutdown();
//     // print("shutdown called");
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (defaultTargetPlatform == TargetPlatform.android) {
//       if (state == AppLifecycleState.resumed) {
//         debugPrint("App Resumed on Android - Re-initializing video.");
//         _videoController?.dispose();
//         if(_videoFile != null) {
//           _initializeVideo();
//         }
//       } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
//         debugPrint("App Paused or Inactive on Android - Disposing video.");
//         _pausePlayback();
//         _stopTicker();
//         setState(() {
//           _isPlaying = false;
//         });
//         // _videoController?.pause(); // Optionally pause on leaving
//         // _videoController?.dispose();
//         // _videoController = null; // Set to null to ensure re-initialization
//       }
//     }
//   }

//   // Helper: Format Duration as mm:ss:xx (first two digits of ms).
//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     String firstTwoMsDigits(int milliseconds) {
//       final msString = milliseconds.toString().padLeft(3, '0');
//       return msString.substring(0, 2);
//     }

//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     final millisecondsFirstTwo = firstTwoMsDigits(duration.inMilliseconds.remainder(1000));

//     return "$minutes:$seconds:$millisecondsFirstTwo";
//   }

//   void prewarmFFT() async {
//     // Create a small dummy signal
//     List<double> dummySignal = List.filled(1024, 0.0);
//     // Fill it with some dummy data
//     for (int i = 0; i < dummySignal.length; i++) {
//       dummySignal[i] = sin(2 * pi * i / dummySignal.length);
//     }
//     // Get a padded length for the dummy signal (e.g., next power of 2)
//     int paddedLength = _nextPowerOf2(dummySignal.length);
//     final fft = FFT(paddedLength);
//     // Perform a dummy FFT
//     List<double> paddedDummy = List.filled(paddedLength, 0.0);
//     paddedDummy.setAll(0, dummySignal);
//     normalize(paddedDummy);
//     fft.realFft(paddedDummy);
//   }

// Future<void> _pickVideoFile() async {
//   // Prevent multiple simultaneous requests
//   if (_isPickingFile) return;
//   setState(() {
//     _isPickingFile = true;
//   });

//   try {
//     setState(() {
//       _isLoadingVideo = true;
//     });

//     String? filePath;
//     if(Platform.isIOS) {
//       final XFile? pickedFile = await ImagePicker().pickVideo(
//         source: ImageSource.gallery, // Direct Photos app access
//         maxDuration: Duration(minutes: 15), // LIMIT OF VIDEO DURATION
//       );

//       if (pickedFile != null) {
//         filePath = pickedFile.path;
//       }
//     }
//     else {
//       FilePickerResult? result = await FilePicker.platform.pickFiles(
//         type: FileType.video,
//         // allowCompression: true,
//         // withData: false,
//         // allowedExtensions: ['mp4'], // NOTE: if it is .MOV file, it'll be much slower than .mp4 file
//       );

//       // Handle cancellation or no file selected
//       if (result == null || result.files.isEmpty) {
//         print("File picker canceled or no file selected.");
//         return;
//       }

//       // Get the selected file path
//       filePath = result.files.single.path;
//     }

//     if (filePath == null) {
//       print("Selected file path is null.");
//       return;
//     }

//     // Process the selected video file
//     final videoFile = File(filePath);
//     setState(() {
//       _videoFile = videoFile;
//     });
    
//     // Initialize video controller with the new file
//     await _initializeVideo();
    
//   } catch (e) {
//     print("Error picking video file: $e");
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text("Failed to pick video file: ${e.toString()}")),
//     );
//   } finally {
//     // Reset the flag
//     setState(() {
//       _isPickingFile = false;
//       _isLoadingVideo = false;
//     });
//   }
// }
//   Future<void> _initializeVideo() async {
//     _videoController?.dispose();
//     betterController?.dispose();

//     if (useBetterPlayer) {
//       final dataSource = BetterPlayerDataSource(
//         BetterPlayerDataSourceType.file,
//         _videoFile!.path,
//         cacheConfiguration: BetterPlayerCacheConfiguration(
//           useCache: false,
//         ),
//         bufferingConfiguration: BetterPlayerBufferingConfiguration(
//           minBufferMs: 100,
//           maxBufferMs: 500,
//           bufferForPlaybackMs: 50,
//           bufferForPlaybackAfterRebufferMs: 50,
//         ),
//       );
//       betterController = BetterPlayerController(
//         BetterPlayerConfiguration(
//           autoPlay: false,
//           looping: false,
//           handleLifecycle: true,
//           useRootNavigator: true,
//           autoDetectFullscreenDeviceOrientation: true,
//           allowedScreenSleep: false,
//           fit: BoxFit.fitHeight,
//           controlsConfiguration: BetterPlayerControlsConfiguration(
//             showControls: false, // 🔑 hides all controls
//           ),
//           playerVisibilityChangedBehavior: (visibilityFraction) { // so that it doesn't pause on background
            
//           },
//         ),
//         betterPlayerDataSource: dataSource,
//       );
//       betterController!.setMixWithOthers(true);
//     } else {
//       _videoController = VideoPlayerController.file(_videoFile!,videoPlayerOptions: VideoPlayerOptions(
//         mixWithOthers: true,  // Prevents audio ducking
//       ),);
//       await _videoController!.initialize();
//     }

//     if (Platform.isAndroid) {
//       _updateVideoVolume(0.001); // ← Never zero (did this change because android vid play issue) TODO look into this
//     }
    
//     if (!mounted) return;
//     setState(() {
//       _videoDuration = duration;
//       _videoPosition = Duration.zero;//position;
//       _scrubPosition = Duration.zero;//position;
//     });
//     if (_videoDuration == Duration.zero) {
//       await Future.delayed(const Duration(milliseconds: 1000), () {
//         if (mounted) {
//           setState(() {
//             _videoDuration = duration;
//           });
//         }
//       });
//     }
//   }


//   Future<void> play() async {
//     if (useBetterPlayer) {
//       await betterController!.play();
//     } else {
//       await _videoController!.play();
//     }
//   }

//   Future<void> pause() async {
//     if (useBetterPlayer) {
//       await betterController!.pause();
//     } else {
//       await _videoController!.pause();
//     }
//   }

//   Future<void> seekTo(Duration position) async {
//     if (useBetterPlayer) {
//       await betterController!.seekTo(position);
//     } else {
//       await _videoController!.seekTo(position);
//     }
//   }

//   void _updateVideoVolume(double volume) {
//     if (Platform.isAndroid) {
//       betterController?.setVolume(volume);
//     } else {
//       _videoController?.setVolume(volume);
//     }
//   }


//   Duration get position {
//     if (useBetterPlayer) {
//       return betterController!.videoPlayerController!.value.position;
//     } else {
//       return _videoController!.value.position;
//     }
//   }

//   Duration get duration {
//     if (useBetterPlayer) {
//       return betterController!.videoPlayerController!.value.duration ?? Duration.zero;
//     } else {
//       return _videoController!.value.duration;
//     }
//   }

//   double get aspectRatio {
//     if (useBetterPlayer) {
//       return betterController!.videoPlayerController!.value.aspectRatio;
//     } else {
//       return _videoController!.value.aspectRatio;
//     }
//   }

//   bool get isPlaying {
//     if (useBetterPlayer) {
//       return betterController!.videoPlayerController!.value.isPlaying;
//     } else {
//       return _videoController!.value.isPlaying;
//     }
//   }

//   /// Calculate effective audio position for a given track based on video position.
//   Duration _calculateEffectiveAudioPositionForTrack(
//       AudioTrack track, Duration videoPos) {
//     final offsetDuration =
//         Duration(milliseconds: (track.offset * 1000).toInt());
//     if (videoPos < offsetDuration) {
//       return track.trimStart;
//     } else {
//       var effectiveAudioPos = track.trimStart + (videoPos - offsetDuration);
//       if (effectiveAudioPos > track.trimEnd) {
//         effectiveAudioPos = track.trimEnd;
//       }
//       return effectiveAudioPos;
//     }
//   }

//   // PLAY/PAUSE TOGGLE using a global _audioStarted flag.
//   Future<void> _togglePlayPause() async {
//     if (_audioOnly) {
//       await _togglePlayPauseAudio(_audioEditorStateSetter!);
//       return;
//     }
//     if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null)  return;

//     if(_videoPosition.inMilliseconds  >= _videoDuration.inMilliseconds) {
//       await _restartVideo();
//     }

//     setState(() {
//       _isPlaying = !_isPlaying;
//     });

//     if (_isPlaying) {
//       _resumePlayback();
//       _startTicker();
//     } else {
//       await _pausePlayback();
//       _stopTicker();
//     }
//   }

//   // REWIND: reset video and audio to zero and clear _audioStarted.
//   Future<void> _restartVideo() async {
//     if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) return;

//     // Pause video and seek to the start
//     await pause();
//     await seekTo(Duration.zero);
//     _stopTicker();

//     // Reset audio tracks
//     JuceAudioEngine.pause();
//     for (int i = 0; i < _audioTracks.length; i++) {
//       final track = _audioTracks[i];
//       // Cancel any pending timers
//       track.audioStartTimer?.cancel();
//       // Mark the track as not started
//       track.audioStarted = false;
//       final effectivePos = _calculateEffectiveAudioPositionForTrack(track, Duration.zero);
//       JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//       track.currentPosition = Duration.zero;
//     }

//     // Update UI state
//     setState(() {
//       _videoPosition = Duration.zero;
//       _scrubPosition = Duration.zero;
//       _isPlaying = false;
//     });
//   }
  
//   Widget _buildTimeDisplay() {
//     if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) {
//       return Container();
//     }
//     return Column(
//       children: [Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(_formatDuration(_videoPosition)),
//             Text(_formatDuration(duration)),
//           ],
//         )]
//     );
//   }
  
//   // SCRUBBER right under the video (unused because this stuff is located elsewhere now)
//   // Widget _buildCustomScrubber() {
//   //   if ((_videoController == null || !_videoController!.value.isInitialized) && betterController == null) {
//   //     return Container();
//   //   }
//   //   final maxValue = duration.inMilliseconds.toDouble();
//   //   double currentValue = _isScrubbing
//   //       ? _scrubPosition.inMilliseconds.toDouble()
//   //       : _videoPosition.inMilliseconds.toDouble();
//   //   currentValue = currentValue.clamp(0.0, maxValue);
//   //   return Column(
//   //     children: [
//   //       Row(
//   //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//   //         children: [
//   //           Text(_formatDuration(_videoPosition)),
//   //           Text(_formatDuration(duration)),
//   //         ],
//   //       ),
//   //       // Slider(
//   //       //   value: currentValue,
//   //       //   min: 0,
//   //       //   max: maxValue,
//   //       //   onChangeStart: (value) {
//   //       //     for (var track in _audioTracks) {
//   //       //       track.audioStartTimer?.cancel();
//   //       //     }
//   //       //     _pausePlayback();
//   //       //     _stopTicker();
//   //       //     setState(() {
//   //       //       _isScrubbing = true;
//   //       //       _scrubPosition = Duration(milliseconds: value.toInt());
//   //       //     });
//   //       //   },
//   //       //   onChanged: (value) {
//   //       //     setState(() {
//   //       //       _scrubPosition = Duration(milliseconds: value.toInt());
//   //       //     });
//   //       //   },
//   //       //   onChangeEnd: (value) async {
//   //       //     final newPosition = Duration(milliseconds: value.toInt());
//   //       //     setState(() {
//   //       //       _isScrubbing = false;
//   //       //       _videoPosition = newPosition;
//   //       //       _scrubPosition = newPosition;
//   //       //     });

//   //       //     await seekTo(newPosition);

//   //       //     for (int i = 0; i < _audioTracks.length; i++) {
//   //       //       final track = _audioTracks[i];
//   //       //       final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);

//   //       //       await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//   //       //       setState(() {
//   //       //         track.currentPosition = effectivePos;
//   //       //       });
//   //       //     }


//   //       //     if(_isPlaying) {
//   //       //       _resumePlayback();
//   //       //       _startTicker();
//   //       //     }
//   //       //   },
//   //       // ),
//   //     ],
//   //   );
//   // }


//   // Pause helper
//   Future<void> _pausePlayback() async {
//     // Pause video first
//     await pause();
    
//     // Pause all audio tracks at precise position
//     for (var track in _audioTracks) {
//       track.audioStartTimer?.cancel(); // NEED THIS IN CASE THERE WAS A TIMER STARTED
//     }
//     await JuceAudioEngine.pause();
//   }











// // START OF PLAYBACK SYNC FIXES


// // Future<void> waitForBetterPlayerToStart(BetterPlayerController controller) async {
// //   final video = controller.videoPlayerController!;
// //   final Duration startPos = video.value.position;
// //   const int maxWaitMs = 1000;
// //   int waited = 0;

// //   while (waited < maxWaitMs) {
// //     await Future.delayed(const Duration(milliseconds: 10));
// //     waited += 10;

// //     if ((video.value.position - startPos).inMilliseconds > 5) {
// //       return; // Confirmed playback started
// //     }
// //   }
// // }
// Future<void> waitForBetterPlayerToStart(BetterPlayerController controller) async {
//   final video = controller.videoPlayerController!;
//   final Duration startPos = video.value.position;
  
//   while (video.value.position == startPos) {
//     await Future.delayed(const Duration(milliseconds: 10));
//   }
// }


//   // Resume helper: resumes video and all audio tracks in unison.
// // Future<void> _resumePlayback() async {
// //   // var videoPosition = _videoPosition;//_videoController!.value.position;
// //   // await seekTo(videoPosition);


// //   // testing to see if doing seek/scrub logic before resume fixes drift
// //   // await seekTo(_videoPosition);

// //   // for (int i = 0; i < _audioTracks.length; i++) {
// //   //   final track = _audioTracks[i];
// //   //   final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _videoPosition);

// //   //   await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
// //   //   track.currentPosition = effectivePos;
// //   // }


// //   // await Future.delayed(const Duration(milliseconds: 100));

  


// //   await play();
// //   var adjustedVideoPos = _videoPosition; // this is crucial

// //   // HARD-CODED ADJUSTMENT FOR AUDIBLE LAG
// //   // EVEN IF VIDEOPOS AND JUCE GETPOSITION SAYS OTHERWISE, NEEDS THIS TO SOUND IN SYNC
// //   // await Future.delayed(const Duration(milliseconds: 50));
  
// //   // JuceAudioEngine.play(); redundant since I just bypass tracks below anyways
// //   // Play and sync all audio tracks
// //   for (int i = 0; i < _audioTracks.length; i++) {
// //     final track = _audioTracks[i];
// //     final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
// //     if (adjustedVideoPos >= offsetDuration) {
// //       // Precision seek with compensation
// //       // final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(track, adjustedVideoPos); // GETTING NEW VID POS

// //       if(useBetterPlayer) {
// //         JuceAudioEngine.bypassTrack(i, false);
// //         // JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0 
// //         //   ? effectiveAudioPos.inMicroseconds / 1e6 
// //         //   : 0.0);
// //         // track.currentPosition = effectiveAudioPos;
// //       }
// //       else {
// //         JuceAudioEngine.bypassTrack(i, false);
// //         // JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0 
// //         //   ? effectiveAudioPos.inMicroseconds / 1e6 
// //         //   : 0.0);
// //         // track.currentPosition = effectiveAudioPos;
// //       }
// //       track.audioStarted = true;
// //     } else {
// //       JuceAudioEngine.bypassTrack(i, true); // to prevent track from playback when it shouldn't be
// //       final delay = offsetDuration - adjustedVideoPos;
// //       final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(track, adjustedVideoPos);
  
// //       track.audioStarted = false;
// //       track.audioStartTimer = Timer(delay, () async {

// //         if(useBetterPlayer) {
// //           JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
// //           JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0 
// //           ? effectiveAudioPos.inMicroseconds / 1e6 
// //           : 0.0);
// //           track.currentPosition = effectiveAudioPos;
// //         }
// //         else {
// //           JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6 > 0.0 
// //           ? effectiveAudioPos.inMicroseconds / 1e6 
// //           : 0.0);
// //           track.currentPosition = effectiveAudioPos;
// //           JuceAudioEngine.bypassTrack(i, false); // SHOULD RESUME PLAYBACK
// //         }
// //         track.audioStarted = true;
// //       });
// //     }
// //   }
// // }

// Future<void> _resumePlayback() async {
//   // NEW: Seek video to current position to reset its internal clock
//   await seekTo(_videoPosition);
  
//   // Get current video position AFTER seek to ensure accuracy
//   final currentVideoPos = position;

//   // Play video and wait for it to actually start
//   await play();
  
//   // HARD-CODED ADJUSTMENT for iOS
//   await Future.delayed(const Duration(milliseconds: 50));
  
//   if (useBetterPlayer) {
//     await waitForBetterPlayerToStart(betterController!);
//   }

//   // NEW: Calculate precise time difference between audio and video
//   final audioStartTime = DateTime.now();
//   await JuceAudioEngine.play(); // Start audio immediately after video


//   // Sync all audio tracks
//   for (int i = 0; i < _audioTracks.length; i++) {
//     final track = _audioTracks[i];
//     final offsetDuration = Duration(milliseconds: (track.offset * 1000).toInt());
    
//     if (currentVideoPos >= offsetDuration) {
//       // NEW: Calculate precise compensation for playback latency
//       final latencyCompensation = DateTime.now().difference(audioStartTime);
//       final effectivePos = _calculateEffectiveAudioPositionForTrack(
//         track, 
//         currentVideoPos - latencyCompensation
//       );

//       // don't do anything if track is over
//       if(effectivePos >= track.trimEnd) {
//         continue;
//       }
      
//       await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//       JuceAudioEngine.bypassTrack(i, false);
//       track.audioStarted = true;
//     } else {
//       JuceAudioEngine.bypassTrack(i, true); // to prevent track from playback when it shouldn't be
//       final delay = offsetDuration - currentVideoPos;
//       final effectiveAudioPos = _calculateEffectiveAudioPositionForTrack(track, currentVideoPos);
  
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

//   _startTicker();
// }


// // END OF PLAYBACK SYNC FIXES




// Future<String> _exportVideo(ValueChanged<double> onProgress) async {
//   if (_videoFile == null) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('No video selected')),
//     );
//     return "";
//   }
//   if (_audioTracks.isEmpty) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('No audio tracks selected')),
//     );
//     return "";
//   }

//   onProgress(0.0);
//   if (_cancelSignal.isCompleted) return "";

//   // Build FFmpeg input arguments.
//   // Use the video file as input 0.
//   final List<String> inputArgs = ['-i "${_videoFile!.path}"'];
//   for (int i = 0; i < _audioTracks.length; i++) {
//     final tempDir = await getTemporaryDirectory();
//     final outPath = '${tempDir.path}/juce_track${i}_export.wav';
//     final outDir = await JuceAudioEngine.exportTrack(i, outPath);
//     print("_exportVideo: track ${i} exported at ${outDir}");
//     inputArgs.add('-i "${outDir}"');

//     onProgress(((i+1).toDouble()/_audioTracks.length) * 0.5);
//     if (_cancelSignal.isCompleted) return "";
//   }
//   if (_cancelSignal.isCompleted) return "";

//   onProgress(0.6);
//   // Get video duration in seconds (for volume automation).
//   double videoDurationSec = duration.inSeconds.toDouble();

//   // Generate video audio automation filter for input 0.
//   // (Assumes you have a variable `videoAudioAutomation` of type List<AutomationPoint>.)
//   final String videoAudioFilter = generateVolumeAutomationFilterForVideo(videoAudioAutomation, videoDurationSec, 0, _universalCrossfade);
//   onProgress(0.7);
//   // Build filter complex lines.
//   final List<String> filterLines = [
//     // For video audio (input 0), apply trim and automation filter.
//     '[0:a]atrim=start=0,asetpts=PTS-STARTPTS,volume=eval=frame:volume=${videoAudioFilter}[vid];'
//   ];

//   if (_cancelSignal.isCompleted) return "";

//   final List<String> trackLabels = [];
//   for (int i = 0; i < _audioTracks.length; i++) {
//     final track = _audioTracks[i];
//     final int offsetMs = (track.offset * 1000).round();
//     final double startSec = track.trimStart.inMilliseconds / 1000.0;//track.trimStart.inSeconds;
//     final double endSec = track.trimEnd.inMilliseconds / 1000.0;//track.trimEnd.inSeconds;
//     final String label = 't${i+1}';

//     final String volumeAutomation = generateVolumeAutomationFilter(track, offsetMs, _universalCrossfade);

//     filterLines.add(
//       '[${i+1}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
//       'adelay=${offsetMs}|${offsetMs},asetpts=PTS-STARTPTS,'
//       'volume=eval=frame:volume=(${volumeAutomation})*(1.0)[$label];'  // 1.0 = track.gain
//     );

//     trackLabels.add('[$label]');
//   }
//   onProgress(0.8);
//   if (_cancelSignal.isCompleted) return "";

//   // Mix video audio and additional audio tracks.
//   final int totalInputs = 1 + _audioTracks.length;
//   final String amixInputs = '[vid]' + trackLabels.join('') + 'amix=inputs=$totalInputs:duration=first:normalize=0[aout]';
//   filterLines.add(amixInputs);

//   // print("🔹 FFmpeg Filter Complex:\n${filterLines.join('\n')}");

//   final String filterComplex = filterLines.join('');

//   setState(() {
//     filterString = filterComplex;
//   });

//   final List<String> ffmpegCmd = [
//     ...inputArgs,
//     '-filter_complex', '"$filterComplex"',
//     '-map', '0:v:0',         // Map only the primary video stream
//     '-map', '[aout]',        // Map the mixed audio output
//     '-c:v', 'copy',          // Copy video (no re-encoding)
//     '-c:a', 'aac',           // Force AAC for audio
//     '-b:a', '128k',          // Set audio bitrate
//     '-ar', '48000',          // Set sample rate to 48000 Hz
//     '-movflags', '+faststart',
//     '-f', 'mp4',
//     '-loglevel', 'verbose',
//     '-y'
//   ];
//   if (_cancelSignal.isCompleted) return "";

//   final tempDir = await getTemporaryDirectory();
//   final outPath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';
//   ffmpegCmd.add('"$outPath"');

//   // print("🔹 Running FFmpeg command:\n${ffmpegCmd.join(' ')}");

//   Session session = await FFmpegKit.execute(ffmpegCmd.join(' '));
//   if (_cancelSignal.isCompleted) return "";
//   onProgress(1.0);
//   final returnCode = await session.getReturnCode();
//   final logs = (await session.getAllLogsAsString()) ?? "No logs available.";
//   final errorLogs = (await session.getLogsAsString()) ?? "No error logs.";

//   // print("🔹 FFmpeg FULL Output Log:\n$logs");
//   // print("🔴 FFmpeg ERROR Log:\n$errorLogs");

//   if (!ReturnCode.isSuccess(returnCode)) {
//     print("❌ FFmpeg export failed.");
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Export failed! Check logs.')),
//     );
//     return "";
//   }

//   print("✅ FFmpeg export completed successfully.");
//   final outFile = File(outPath);
//   int retries = 0;
//   while (!await outFile.exists() && retries < 20) {
//     await Future.delayed(const Duration(milliseconds: 250));
//     retries++;
//   }

//   if (!await outFile.exists() || (await outFile.length()) < 1000) {
//     print("❌ ERROR: Output file is missing or too small!");
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Export failed: Output file missing or too small.')),
//     );
//     return "";
//   }

//   print("✅ File found: $outPath");

//   return outPath;
// }

// // THINGS FOR AI SYNC---------

// // Extract PCM samples from raw bytes
// List<double> extractPcmSamples(Uint8List audioBytes) {
//   List<double> samples = [];

//   // Ensure we read in **pairs** of bytes (16-bit PCM)
//   for (int i = 0; i < audioBytes.length - 1; i += 2) {
//     int sample = audioBytes[i] | (audioBytes[i + 1] << 8);

//     // Convert to signed 16-bit integer
//     if (sample >= 0x8000) sample -= 0x10000;

//     // Normalize to range -1.0 to 1.0
//     samples.add(sample / 32768.0);
//   }

//   print("✅ Extracted ${samples.length} PCM samples.");

//   return samples;
// }


// double computeCorrelation(List<double> signalA, List<double> signalB) {
//   double sum = 0;
//   int len = min(signalA.length, signalB.length);

//   for (int i = 0; i < len; i++) {
//     sum += signalA[i] * signalB[i]; 
//   }

//   return sum;
// }


// Future<int> findBestSyncOffset(String videoAudioPath, String trackAudioPath) async {
//   final ReceivePort receivePort = ReceivePort();
//   final ReceivePort progressPort = ReceivePort(); // for reporting UI progress

//   // ✅ Extract Audio Before Processing
//   String extractedVideoAudio = await extractAudioFromVideo(videoAudioPath);
//   String convertedTrackAudio = await convertAudioToWav(trackAudioPath);

//   double videoSampleRate = await getSampleRate(extractedVideoAudio);
//   double trackSampleRate = await getSampleRate(convertedTrackAudio);

//   // Listen for progress updates
//   progressPort.listen((message) {
//     if (message is double) {
//       setState(() {
//         _syncProgress = message;
//       });
//     }
//   });

//   await Isolate.spawn(
//     _findSyncOffsetInBackground,
//     [receivePort.sendPort, extractedVideoAudio, convertedTrackAudio, trackSampleRate, progressPort.sendPort],
//   );

//   final result = await receivePort.first as int;
//   progressPort.close();
//   return result;
// }


// Future<void> applyBestSyncOffset(AudioTrack track, String videoAudioPath) async {
//   int syncOffset = await findBestSyncOffset(videoAudioPath, track.file.path);
//   final int audioLengthMs = track.audioDuration.inMilliseconds;
//   final int offsetLimit = 10000; // 10 seconds

//   if (syncOffset >= 0 && syncOffset > offsetLimit) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//           content: Text('AI Sync failed: Computed offset exceeds audio length.')),
//     );
//     return;
//   } else if (syncOffset < 0 && syncOffset.abs() > audioLengthMs) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//           content: Text('AI Sync failed: Computed trim exceeds audio length.')),
//     );
//     return;
//   }
  
//   setState(() {
//     // Adjust track offset or trim start based on offset direction
//     if (syncOffset >= 0) {
//       // Delay the track (shift right)
//       track.offset = syncOffset / 1000.0;
//       track.trimStart = Duration(seconds: 0);
//     } else {
//       // Trim the track (shift left)
//       // double trimAdjustment = syncOffset.abs() / 1000.0;
//       track.trimStart = Duration(milliseconds: syncOffset.abs());//trimAdjustment.toInt());
//       track.offset = 0.0;
//     }
//   });

//   // Refresh UI
//   setState(() {});
//   print("✅ AI Sync applied. Adjusted Offset: ${track.offset}, Trim Start: ${track.trimStart}");
// }

// // THINGS FOR AI SYNC END-----

//   // In place of old single-audio UI:
//   Widget _buildMultiTrackAudioSection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         // One crossfade slider for entire mix
//         _audioOnly ? SizedBox.shrink() : 
//           // Text('${L10n.translate(context, 'Crossfade (Video vs. All Audio)')}: ${(_universalCrossfade * 100).toStringAsFixed(0)}%',
//           //       style: Theme.of(context).textTheme.titleMedium?.copyWith(
//           //   fontWeight: FontWeight.w400,
//           // )),
//           Text(L10n.translate(context, 'Volume Balance'),
//                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
//             fontWeight: FontWeight.w500,
//           )),
//         _audioOnly ? SizedBox.shrink() : 
//         // Slider(
//         //   value: _universalCrossfade,
//         //   min: 0,
//         //   max: 1,
//         //   onChanged: (value) {
//         //     setState(() {
//         //       _universalCrossfade = value;
//         //     });
//         //   },
//         // ),
//           Stack(
//             alignment: Alignment.center,
//             children: [
//               // The slider itself
//               Row(
//                 children: [
//                   const Icon(Icons.videocam_sharp, color: Colors.grey),
//                   Expanded(
//                     child: 
//                       Slider(
//                         value: _universalCrossfade,
//                         min: 0,
//                         max: 1,
//                         onChanged: (value) {
//                           setState(() {
//                             // _universalCrossfade = value;
//                             const double snapThreshold = 0.05; // ±5% from center
//                             if ((value - 0.5).abs() < snapThreshold) {
//                               _universalCrossfade = 0.5;
//                             } else {
//                               _universalCrossfade = value;
//                             }
//                           });
//                         },
//                       ),
//                   ),
//                   const Icon(Icons.music_video_sharp, color: Colors.grey),
//                 ]
//               ),

//               // Center line using Align (not Positioned)
//               IgnorePointer( // Prevents this overlay from blocking slider interaction
//                 child: Align(
//                   alignment: Alignment.center,
//                   child: Container(
//                     width: 2,
//                     height: 24, // Adjust to your preference
//                     color: const Color.fromARGB(255, 134, 134, 134).withOpacity(0.8),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         const SizedBox(height: 10),

//         // "Add Track" button
//         ElevatedButton(
//           onPressed: _showAudioSourceOptions,
//           child: Text(L10n.translate(context, 'Add Audio Track')),
//         ),
//         const SizedBox(height: 10),

//         // A scrollable list of all tracks
//         ListView.builder(
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),
//           itemCount: _audioTracks.length,
//           itemBuilder: (context, index) {
//             return _buildSingleTrackUI(index);
//           },
//           padding: EdgeInsets.fromLTRB(0, 0, 0, 20),
//         ),
//       ],
//     );
//   }

//   Widget _buildSingleTrackUI(int index) {
//     final track = _audioTracks[index];

//     // For the seeker
//     final Duration audioPos = track.currentPosition < track.trimStart
//         ? track.trimStart
//         : (track.currentPosition > track.trimEnd ? track.trimEnd : track.currentPosition);  
//     final Duration effectiveDuration = track.trimEnd - track.trimStart;
//     final double normalizedTime = effectiveDuration.inMilliseconds > 0
//         ? ((audioPos.inMilliseconds - track.trimStart.inMilliseconds) /
//             effectiveDuration.inMilliseconds)
//             .clamp(0.0, 1.0)
//         : 0.0;

//     // print("Track #${index}: ${track.currentPosition}");

//     return Card(
//       margin: const EdgeInsets.symmetric(vertical: 8),
//       shape: RoundedRectangleBorder(
//       borderRadius: BorderRadius.circular(8),
//       side: BorderSide(
//         color: HSLColor.fromColor(Theme.of(context).primaryColor)
//           .withLightness((HSLColor.fromColor(Theme.of(context).primaryColor).lightness - 0.2).clamp(0.0, 1.0)).toColor(),
//         width: 3.0,
//       ),
//     ),
//       child: Padding(
//         padding: const EdgeInsets.all(12.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Row with file name and a delete button.
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Expanded(
//                   child: Text(
//                     '${L10n.translate(context, 'Audio')}: ${track.originalFile.path.split('/').last}',
//                     style: const TextStyle(fontWeight: FontWeight.bold),
//                     maxLines: 2, // ✅ Allow wrapping up to 2 lines
//                     overflow: TextOverflow.ellipsis, // ✅ Use ellipsis if still too long
//                     softWrap: true,
//                   ),
//                 ),
//                 IconButton(
//                   icon: const Icon(Icons.delete),
//                   onPressed: () async {
//                     final confirm = await showDialog<bool>(
//                     context: context,
//                     builder: (ctx) => AlertDialog(
//                       title: const Text("Delete track?"),
//                       content: const Text("Are you sure you want to delete this audio track?"),
//                       actions: [
//                         TextButton(
//                           onPressed: () => Navigator.of(ctx).pop(false),
//                           child: const Text("Cancel"),
//                         ),
//                         TextButton(
//                           onPressed: () => Navigator.of(ctx).pop(true),
//                           child: const Text("Delete", style: TextStyle(color: Colors.red)),
//                         ),
//                       ],
//                     ),
//                   ) ?? false;

//                   // 2) Only delete if they confirmed
//                   if (!confirm) return;
//                     // Stop the audio track if it's playing.
//                     final track = _audioTracks[index];
//                     track.audioStartTimer?.cancel();
//                     // await track.player.pause();
//                     // track.player.dispose();
//                     track.waveformController.dispose();
                    
//                     setState(() {
//                       _audioTracks.removeAt(index);
//                     });
//                     await JuceAudioEngine.removeTrack(index);
//                     await JuceAudioEngine.pause();
//                     Future.delayed(Duration(milliseconds: 50), () {
//                       setState(() {}); // force a repaint
//                     });

//                   },
//                 ),
//               ],
//             ),
//             const SizedBox(height: 10),
//             // Offset slider for this track.
//             Text('${L10n.translate(context, 'Offset')}: ${track.offset.toStringAsFixed(2)} s'),
//             Row(
//               children: [
//                 SizedBox(
//                   width: 40, // Adjust width as needed
//                   height: 30, // Adjust height as needed
//                   child: ElevatedButton(
//                     onPressed: () {
//                       setState(() {
//                         track.offset = (track.offset - 0.01).clamp(0, 10);
//                       });
//                     },
//                     style: ElevatedButton.styleFrom(
//                       padding: EdgeInsets.zero, // Remove default padding
//                       minimumSize: Size.zero, // Allow precise sizing
//                     ),
//                     child: const Text('-'),
//                   ),
//                 ),
//                 Expanded(
//                   child: Padding( // Add some padding around the text and slider
//                     padding: const EdgeInsets.symmetric(horizontal: 0.0),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Slider(
//                           value: track.offset,
//                           min: 0,
//                           max: 10,
//                           divisions: 1000,
//                           label: track.offset.toStringAsFixed(2),
//                           onChanged: (value) {
//                             setState(() {
//                               track.offset = value;
//                               final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _videoPosition);
//                               JuceAudioEngine.seek(index, effectivePos.inMicroseconds / 1e6);
//                               track.currentPosition = effectivePos;
//                             });
//                           },
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 SizedBox(
//                   width: 40, // Adjust width as needed
//                   height: 30, // Adjust height as needed
//                   child: ElevatedButton(
//                     onPressed: () {
//                       setState(() {
//                         track.offset = (track.offset + 0.01).clamp(0, 10);
//                       });
//                     },
//                     style: ElevatedButton.styleFrom(
//                       padding: EdgeInsets.zero, // Remove default padding
//                       minimumSize: Size.zero, // Allow precise sizing
//                     ),
//                     child: const Text('+'),
//                   ),
//                 ),
//               ],
//             ),
//             Text(
//               '${L10n.translate(context, 'Trim')}: ${_formatDuration(track.trimStart)} - ${_formatDuration(track.trimEnd)}'
//             ),
//             const SizedBox(height: 10),
//             _buildWaveformWithTrim(index, track, track.audioDuration),//_audioDuration), // TODO: LOOK INTO THIS
//             const SizedBox(height: 10),
//             // Display current trim range text.
//             // Volume Automation UI
//             // Text('Volume Automation'),
//             Text(L10n.translate(context, 'Volume Automation')),
//             GestureDetector(
//               behavior: HitTestBehavior.translucent,
//               onVerticalDragDown: (_) {}, // Claim the vertical gesture
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Container(
//                     height: 100,
//                     width: double.infinity,
//                     color: Colors.grey[200],
//                     child: VolumeAutomationWidget(
//                       automationPoints: track.volumeAutomation,
//                       currentNormalizedTime: normalizedTime,
//                       onAutomationChanged: (points) {
//                         setState(() {
//                           track.volumeAutomation = points;
//                         });
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             // NEW: Gain control slider for this track.
//             const SizedBox(height: 10),

//             // EFFECTS BUTTON
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 8),
//               child: SizedBox(
//                  width: double.infinity,
//                   child: ElevatedButton.icon(
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: HSLColor.fromColor(Theme.of(context).primaryColor)
//               .withLightness((HSLColor.fromColor(Theme.of(context).primaryColor).lightness - 0.2).clamp(0.0, 1.0)).toColor(),
//                       padding: const EdgeInsets.symmetric(vertical: 16),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                     ),
//                     icon: const Icon(Icons.tune, color: Colors.white),
//                     label: FutureBuilder<List<String>>(
//                       future: JuceAudioEngine.getTrackEffects(index), // TODO: maybe this is being called too often when playing??
//                       builder: (ctx, snap) {
//                         final count = snap.hasData ? snap.data!.length : 0;
//                         return Text("Effects ($count/5)",
//                             style: const TextStyle(color: Colors.white));
//                       },
//                     ),
//                     onPressed: () => _openEffectsDrawer(context, index),
//                   ),
//               ),
//             ),

//             const SizedBox(height: 10),
//             Text("${L10n.translate(context, 'Gain')}: ${track.gain.toStringAsFixed(2)}x"),
//             Slider(
//               value: track.gain,
//               min: 0.0,
//               max: 3.0,
//               divisions: 60, // increments of 0.05 roughly
//               label: track.gain.toStringAsFixed(2),
//               onChanged: (value) {
//                 setState(() {
//                   track.gain = value;
//                 });
//                 // Optionally, update volume immediately if needed.
//               },
//               onChangeEnd: (value) async {
//                 setState(() {
//                   _isLoadingAudio = true;
//                 });
//                 await amplifyAndPlay(value, index); // TODO: should be one-line, but use JUCE instead for this
//                 setState(() {
//                   _isLoadingAudio = false;
//                 });
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _openEffectsDrawer(BuildContext context, int trackIndex) {
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: const Color.fromARGB(255, 39, 46, 97),
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       builder: (_) => EffectsDrawer(trackIndex: trackIndex),
//     ).whenComplete(() {
//       // schedule the rebuild on the next frame
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (mounted) setState(() {});
//       });
//     });
//   }

//   // this will be deprecated cuz we'll use JUCE instead of this ffmpeg thing
//   Future<void> amplifyAndPlay(double gain, int trackInd) async {
//   //   final track = _audioTracks[trackInd];
//   //   // Get a temporary directory
//   //   final tempDir = await getTemporaryDirectory();
//   //   final outputPath = '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}${track.originalFile.path.split('/').last}';
//   //   // FFmpeg command: amplify audio by {gain}x (e.g., 2.0 = 200%)
//   //   final command = '-i "${track.originalFile.path}" -af "volume=$gain" -y "$outputPath"';

//   //   // Execute FFmpeg
//   //   final session = await FFmpegKit.execute(command);
//   //   final returnCode = await session.getReturnCode();
//   //   final errors = await session.getLogsAsString();
//   //   if (!ReturnCode.isSuccess(returnCode)) {
//   //     throw Exception('FFmpeg failed with rc=${returnCode}. ${errors}');
//   //   }

//   //  _isPlaying = false;
//   //  await _pausePlayback();
//   //  _stopTicker();

//   //   // Play the new file
//   //   track.file = File(outputPath); // mandatory for this to work since we use play(track.file.path)
//   //   await track.player.stop();
//   //   await track.player.setSource(DeviceFileSource(outputPath));
//     // await track.player.resume();
//   }

//   Future<void> createWaveformData(AudioTrack track, double width) async {
//     final sampleCount = PlayerWaveStyle().getSamplesForWidth(width);
//     final rawData = await track.waveformController.extractWaveformData(
//       path: track.file.path,
//       noOfSamples: sampleCount,
//     );
//     setState(() {
//       track.normWaveformData = normalizeWaveform(rawData);
//     });
//   }

//   List<double> normalizeWaveform(List<double> data) {
//     if (data.isEmpty) return [];

//     final maxAmplitude = data.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);

//     if (maxAmplitude == 0) return List.filled(data.length, 0.0);

//     return data.map((v) => v / maxAmplitude).toList();
//   }



//   Widget _buildWaveformWithTrim(int index, AudioTrack track, Duration fullDuration) {
//   return LayoutBuilder(
//     builder: (context, constraints) {
//       final double boxWidth = constraints.maxWidth;
//       final double paddingH = 10.0;
//       final double effectiveWidth = boxWidth - (2 * paddingH);
//       final double totalMs = fullDuration.inMilliseconds.toDouble();

//       if (totalMs <= 0) {
//         return SizedBox(width: boxWidth, height: 80.0);
//       }

//       final ValueNotifier<double> trimStartNotifier =
//           ValueNotifier(track.trimStart.inMilliseconds.toDouble());
//       final ValueNotifier<double> trimEndNotifier =
//           ValueNotifier(track.trimEnd.inMilliseconds.toDouble());

//       if(track.normWaveformData.isEmpty) {
//         createWaveformData(track, boxWidth);
//       }

//       return ValueListenableBuilder<double>(
//         valueListenable: trimStartNotifier,
//         builder: (context, trimStartMs, child) {
//           return ValueListenableBuilder<double>(
//             valueListenable: trimEndNotifier,
//             builder: (context, trimEndMs, child) {
//               final double trimmedDurationMs = trimEndMs - trimStartMs;
//               return SizedBox(
//                 height: 80,
//                 width: boxWidth,
//                 child: Stack(
//                   children: [
//                     // ✅ Waveform
//                     Positioned.fill(
//                       // left: 0,//paddingH,
//                       // top: 0,
//                       // width: effectiveWidth,
//                       // height: 80,
//                       child: AudioFileWaveforms(
//                         // key: ValueKey(track.file.path + String(track.normWaveformData.hashCode)),
//                         key: ValueKey('${track.file.path}_${track.normWaveformData.hashCode}'),
//                         size: Size(effectiveWidth, 80),
//                         waveformData: track.normWaveformData, // NEW CHANGE
//                         playerController: track.waveformController,
//                         continuousWaveform: false,
//                         enableSeekGesture: false,
//                         waveformType: WaveformType.fitWidth,
//                         playerWaveStyle: const PlayerWaveStyle(
//                           seekLineColor: Color(0xFF888888),
//                           showSeekLine: false,
//                         ),
//                       ),
//                     ),
//                     // seek line for waveform
//                     Positioned.fill(
//                       child: CustomPaint(
//                         painter: _WaveformSeekLinePainter(
//                           // videoPosition: _audioOnly ? _globalAudioClock : _videoPosition, // big change
//                           audioPosition: track.currentPosition, 
//                           trimStart: track.trimStart,
//                           trimEnd: track.trimEnd,
//                           totalAudioDuration: fullDuration,
//                           lineColor: Color(0xFF888888),
//                         ),
//                       ),
//                     ),
//                     // ✅ Left shading (Before Trim Start)
//                     Positioned(
//                       left: 0,//paddingH,
//                       top: 0,
//                       bottom: 0,
//                       width: effectiveWidth * (trimStartMs / totalMs),
//                       child: Container(color: Colors.black.withOpacity(0.3)),
//                     ),

//                     // ✅ Right shading (After Trim End)
//                     Positioned(
//                       left: paddingH + effectiveWidth * (trimEndMs / totalMs),
//                       top: 0,
//                       bottom: 0,
//                       right: 0,//paddingH,
//                       child: Container(color: Colors.black.withOpacity(0.3)),
//                     ),

//                     // ✅ Trim Start Handle
//                     _buildTrimHandle(
//                       left: paddingH + (effectiveWidth * (trimStartMs / totalMs)),
//                       onDragUpdate: (dx) {
//                         double newTrimStart = trimStartMs + (dx / effectiveWidth) * totalMs;
//                         newTrimStart = newTrimStart.clamp(0, trimEndMs - 100);

//                         // // --- SNAP LOGIC START ---
//                         // // Compute current seek‐line X within this trimmed waveform
//                         // final effectiveTimeMs = (_videoPosition.inMilliseconds - (track.offset * 1000)).clamp(0, trimmedDurationMs);
//                         // final double seekX = paddingH + effectiveWidth * ((trimStartMs + effectiveTimeMs) / totalMs);
//                         // final double handleX = paddingH + effectiveWidth * (newTrimStart / totalMs);
//                         // if ((handleX - seekX).abs() < _trimSnapPx) {
//                         //   newTrimStart = ((seekX - paddingH) / effectiveWidth) * totalMs;
//                         // }
//                         // // --- SNAP LOGIC END ---

//                         trimStartNotifier.value = newTrimStart;
//                         track.trimStart = Duration(milliseconds: newTrimStart.round());

//                         final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _videoPosition);
//                         JuceAudioEngine.seek(index, effectivePos.inMicroseconds / 1e6);
//                         track.currentPosition = effectivePos;
//                       },
//                     ),

//                     // ✅ Trim End Handle
//                     _buildTrimHandle(
//                       left: paddingH + (effectiveWidth * (trimEndMs / totalMs)),
//                       onDragUpdate: (dx) {
//                         double newTrimEnd = trimEndMs + (dx / effectiveWidth) * totalMs;
//                         newTrimEnd = newTrimEnd.clamp(trimStartMs + 100, totalMs);

//                         // // --- SNAP LOGIC START ---
//                         // final effectiveTimeMs = (_videoPosition.inMilliseconds - (track.offset * 1000)).clamp(0, trimmedDurationMs);
//                         // final double seekX = paddingH
//                         //   + effectiveWidth * ((trimStartMs + effectiveTimeMs) / totalMs);
//                         // final double handleX = paddingH + effectiveWidth * (newTrimEnd / totalMs);
//                         // if ((handleX - seekX).abs() < _trimSnapPx) {
//                         //   newTrimEnd = ((seekX - paddingH) / effectiveWidth) * totalMs;
//                         // }
//                         // // --- SNAP LOGIC END ---

//                         trimEndNotifier.value = newTrimEnd;
//                         track.trimEnd = Duration(milliseconds: newTrimEnd.round());

//                         final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _videoPosition);
//                         JuceAudioEngine.seek(index, effectivePos.inMicroseconds / 1e6);
//                         track.currentPosition = effectivePos;
//                       },
//                     ),
//                   ],
//                 ),
//               );
//             },
//           );
//         },
//       );
//     },
//   );
// }

// Widget _buildTrimHandle({required double left, required Function(double) onDragUpdate}) {
//   return Positioned(
//     left: left - 10,
//     top: 0,
//     bottom: 0,
//     child: GestureDetector(
//       onHorizontalDragUpdate: (details) {
//         onDragUpdate(details.delta.dx);
//       },
//       onHorizontalDragEnd: (details) {
//         // ✅ Immediately refresh UI when user stops dragging
//         setState(() {});
//       },
//       child: Container(
//         width: 20,
//         height: 80,
//         color: Color(0x80B03A2E),
//       ),
//     ),
//   );
// }

// void _showAudioSourceOptions() {
//   showDialog(
//     context: context,
//     builder: (context) => AlertDialog(
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       title: Text(
//         L10n.translate(context, 'Add Audio Track'),
//         style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
//       ),
//       content: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           ListTile(
//             leading: Icon(Icons.audiotrack),
//             title: Text(L10n.translate(context, 'Pick from Device')),
//             onTap: () {
//               Navigator.pop(context);
//               _addAudioTrack();
//             },
//           ),
//           // Uncomment if needed later
//           // ListTile(
//           //   leading: Icon(Icons.bluetooth_audio),
//           //   title: Text("Connect to Mixroom Guitar"),
//           //   onTap: () {
//           //     Navigator.pop(context);
//           //     _connectToGuitarViaBluetooth();
//           //   },
//           // ),
//         ],
//       ),
//     ),
//   );
// }


// // 2. Progress and error handling methods
// void _showProgress(String message) {
//   if (mounted) {
//     setState(() {
//       _progressMessage = message;
//       _showProgressDialog = true;
//       _downloadProgress = 0.0;
//     });
//   }
// }

// void _updateDownloadProgress(int bytesReceived, [int? totalBytes]) {
//   if (mounted) {
//     setState(() {
//       if (totalBytes != null) {
//         _downloadProgress = bytesReceived / totalBytes;
//       }
//       _progressMessage = "Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%";
//     });
//   }
// }

// void _hideProgress() {
//   if (mounted) {
//     setState(() {
//       _showProgressDialog = false;
//       _downloadProgress = 0.0;
//     });
//   }
// }

// void _showError(String message) {
//   _hideProgress();
//   if (mounted) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         duration: const Duration(seconds: 3),
//       )
//     );
//   }
//   print("Error: $message");
// }

// void _showOpenSettingsPrompt() {
//   if (!mounted) return;
  
//   showDialog(
//     context: context,
//     builder: (context) => AlertDialog(
//       title: Text("Bluetooth Required"),
//       content: Text("Please enable Bluetooth to connect to your Mixroom guitar"),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: Text("Cancel"),
//         ),
//         // TextButton(
//         //   onPressed: () {
//         //     Navigator.pop(context);
//         //     FlutterBluePlus.openBluetoothSettings();
//         //   },
//         //   child: Text("Open Settings"),
//         // ),
//       ],
//     ),
//   );
// }

// // 3. The complete Bluetooth file picker implementation
// // final flutterReactiveBle = FlutterReactiveBle();

// // Future<void> _connectToGuitarViaBluetooth() async {
// //   try {
// //     // A. Initialize Bluetooth
// //     _showProgress("Initializing Bluetooth...");
    
// //     // Check and request permissions
// //     await _requestBlePermissions();
    
// //     // B. Scan for Mixroom Guitar
// //     _showProgress("Searching for Mixroom Guitar...");
// //     setState(() => _isScanning = true);

// //     BluetoothDevice? guitarDevice;

// //     // Start classic Bluetooth scan
// //     await FlutterBluePlus.startScan(timeout: Duration(seconds: 10), androidScanMode: AndroidScanMode.lowLatency, oneByOne: true);

// //     // Listen for results
// //     var subscription = FlutterBluePlus.scanResults.listen((results) {
// //       for (var result in results) {
// //         print('Classic BT Device: ${result.device.platformName}');
// //         if (result.device.platformName?.toLowerCase().contains('mixroom') ?? false) {
// //           guitarDevice = result.device;
// //           FlutterBluePlus.stopScan();
// //           break;
// //         }
// //       }
// //     });

// //     // Timeout handling
// //     await Future.delayed(Duration(seconds: 10), () {
      
// //     });

// //     if (guitarDevice == null) {
// //       FlutterBluePlus.stopScan();
// //       subscription.cancel();
// //       print('Classic BT scan timeout');
// //       _showError("Mixroom Guitar not found");
// //       return;
// //     }

// //     // C. Connect to Guitar
// //     _showProgress("Connecting to guitar...");
// //     setState(() => _isConnecting = true);
    
// //     // final connection = flutterReactiveBle.connectToDevice(
// //     //   id: guitarDevice!.id,
// //     //   connectionTimeout: const Duration(seconds: 10),
// //     // );
    
// //     // final connectionSubscription = connection.listen((state) {
// //     //   if (state.connectionState == DeviceConnectionState.connected) {
// //     //     print("✅ Connected to Mixroom Guitar");
// //     //   }
// //     // });

// //     // // Wait for connection
// //     // await connection.firstWhere(
// //     //   (state) => state.connectionState == DeviceConnectionState.connected,
// //     // ).timeout(const Duration(seconds: 10));

// //     // // D. Discover Services
// //     // _showProgress("Discovering services...");
// //     // final services = await flutterReactiveBle.discoverServices(guitarDevice!.id);
    
// //     // // E. Find File Transfer Characteristics
// //     // QualifiedCharacteristic? fileListChar;
// //     // QualifiedCharacteristic? fileDataChar;

// //     // for (final service in services) {
// //     //   for (final characteristic in service.characteristics) {
// //     //     // Check if characteristic supports both read and notify
// //     //     if (characteristic.isReadable && characteristic.isNotifiable) {
// //     //       fileListChar = QualifiedCharacteristic(
// //     //         serviceId: service.serviceId,
// //     //         characteristicId: characteristic.characteristicId,
// //     //         deviceId: guitarDevice!.id,
// //     //       );
// //     //     }
        
// //     //     // Check if characteristic supports both write and read
// //     //     if (characteristic.isWritableWithResponse && characteristic.isReadable) {
// //     //       fileDataChar = QualifiedCharacteristic(
// //     //         serviceId: service.serviceId,
// //     //         characteristicId: characteristic.characteristicId,
// //     //         deviceId: guitarDevice!.id,
// //     //       );
// //     //     }
// //     //   }
// //     // }

// //     // if (fileListChar == null || fileDataChar == null) {
// //     //   _showError("Could not find required guitar services");
// //     //   return;
// //     // }

// //     // // F. Get File List
// //     // _showProgress("Fetching available files...");
// //     // final fileListData = await flutterReactiveBle.readCharacteristic(fileListChar);
// //     // final fileList = utf8.decode(fileListData).split('\n').where((f) => f.isNotEmpty).toList();
    
// //     // setState(() {
// //     //   _guitarFiles = fileList;
// //     //   _isConnecting = false;
// //     // });
// //     // _hideProgress();

// //     // // G. Show File Picker Dialog
// //     // final selectedFile = await showDialog<String>(
// //     //   context: context,
// //     //   builder: (context) => AlertDialog(
// //     //     title: const Text("Select Audio File"),
// //     //     content: SizedBox(
// //     //       width: double.maxFinite,
// //     //       child: ListView.builder(
// //     //         shrinkWrap: true,
// //     //         itemCount: _guitarFiles.length,
// //     //         itemBuilder: (context, index) => ListTile(
// //     //           title: Text(_guitarFiles[index]),
// //     //           onTap: () => Navigator.pop(context, _guitarFiles[index]),
// //     //         ),
// //     //       ),
// //     //     ),
// //     //   ),
// //     // );

// //     // if (selectedFile != null) {
// //     //   // H. Download File
// //     //   _showProgress("Downloading $selectedFile...");
// //     //   await flutterReactiveBle.writeCharacteristicWithResponse(
// //     //     fileDataChar,
// //     //     value: utf8.encode("DL:$selectedFile"),
// //     //   );
      
// //     //   List<int> fileData = [];
// //     //   final sub = flutterReactiveBle.subscribeToCharacteristic(fileDataChar).listen((value) {
// //     //     fileData.addAll(value);
// //     //     _updateDownloadProgress(fileData.length);
// //     //   });

// //     //   // Wait for complete (adjust timeout as needed)
// //     //   await Future.delayed(const Duration(seconds: 2));
// //     //   await sub.cancel();
      
// //     //   // I. Create Audio Track
// //     //   final tempDir = await getTemporaryDirectory();
// //     //   final filePath = '${tempDir.path}/${selectedFile.replaceAll('/', '_')}';
// //     //   final file = File(filePath);
// //     //   await file.writeAsBytes(fileData);
      
// //     //   final newPlayer = AudioPlayer();
// //     //   await newPlayer.setSourceDeviceFile(filePath);
// //     //   final dur = await newPlayer.getDuration() ?? Duration.zero;

// //     //   final newController = PlayerController();
// //     //   newController.preparePlayer(path: filePath);

// //     //   final newTrack = AudioTrack(
// //     //     file: file,
// //     //     player: newPlayer,
// //     //     waveformController: newController,
// //     //     audioDuration: dur,
// //     //     trimStart: Duration.zero,
// //     //     trimEnd: dur,
// //     //     offset: 0.0,
// //     //     crossfade: 1.0,
// //     //     currentPosition: Duration.zero,
// //     //   );

// //     //   newPlayer.onPositionChanged.listen((position) {
// //     //     if (mounted) setState(() => newTrack.currentPosition = position);
// //     //     if (_isPlaying && position >= newTrack.trimEnd) newPlayer.pause();
// //     //   });

// //     //   if (mounted) {
// //     //     setState(() => _audioTracks.add(newTrack));
// //     //   }

// //     //   _hideProgress();
// //     //   _showError("Download complete!");
// //     // }

// //     // // Clean up connection
// //     // await connectionSubscription.cancel();
    
// //   } catch (e) {
// //     _hideProgress();
// //     _showError("Error: ${e.toString()}");
// //     if (mounted) setState(() {
// //       _isScanning = false;
// //       _isConnecting = false;
// //     });
// //   }
// // }

// // Future<void> _requestBlePermissions() async {
// //   if (Platform.isAndroid) {
// //     await Permission.locationWhenInUse.request();
// //   }
  
// //   if (Platform.isIOS) {
// //     await Permission.bluetooth.request();
// //     await Permission.bluetoothConnect.request();
// //     await Permission.bluetoothScan.request();
// //   }

// //   // Wait for Bluetooth to be ready
// //   // await flutterReactiveBle.statusStream.firstWhere(
// //   //   (status) => status == BleStatus.ready,
// //   // ).timeout(const Duration(seconds: 10));
// // }

// // 4. Progress Indicator Widget (add to your build method)
// Widget _buildProgressIndicator() {
//   if (!_showProgressDialog) return const SizedBox.shrink();

//   return AlertDialog(
//     title: Text(_currentOperation),
//     content: Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Text(_progressMessage),
//         const SizedBox(height: 16),
//         LinearProgressIndicator(
//           value: _downloadProgress,
//           backgroundColor: Colors.grey[200],
//           valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
//         ),
//       ],
//     ),
//   );
// }

//   // Instead of the deprecated single-audio _pickAudioFile, use _addAudioTrack.
//   Future<void> _addAudioTrack() async {
//     _pausePlayback();
//     FilePickerResult? result =
//         await FilePicker.platform.pickFiles(type: FileType.any);
//     if (result != null && result.files.isNotEmpty && result.files.single.path != null) {

//       setState(() {
//         _isLoadingAudio = true;
//       });

//       final newFile = File(result.files.single.path!);
//       // final newPlayer = AudioPlayer();
//       // NEW

//       // TODO: figure out if there's setup required for juce like below
//       // await newPlayer.setAudioContext(AudioContext(
//       //   android: AudioContextAndroid(
//       //     usageType: AndroidUsageType.media,
//       //     contentType: AndroidContentType.music,
//       //     audioFocus: AndroidAudioFocus.none, // because of android vid play issue
//       //     isSpeakerphoneOn: true, // because of android vid play issue
//       //   ),
//       // ));

//       // make it always 48k sample rate
//       final tmpDir = await getTemporaryDirectory();
//       final baseName = newFile.path.split('/').last;
//       final resampledPath = '${tmpDir.path}/$baseName';

//       // 1) Transcode to 48 kHz PCM WAV (fast, one‐time cost):
//       await FFmpegKit.execute(
//         '-i "${newFile.path}" -ar 48000 -y "$resampledPath"'
//       );
//       final newFile_48 = File(resampledPath);


//       // await newPlayer.setSourceDeviceFile(newFile.path);
//       // final dur = await newPlayer.getDuration() ?? Duration.zero;
//       await JuceAudioEngine.loadTrack(_audioTracks.length, newFile_48.path);
//       // final dur = await JuceAudioEngine.getTrackDuration(0);
//       final durSeconds = await JuceAudioEngine.getTrackDuration(_audioTracks.length);
//       final dur = Duration(milliseconds: (durSeconds * 1000).round());


//       final newController = PlayerController();
//       newController.preparePlayer(path: newFile_48.path);

//       // Create a new AudioTrack instance with a fixed audioDuration.
//       final newTrack = await AudioTrack.create(
//         file: newFile_48,
//         originalFile: newFile_48,
//         // player: newPlayer,
//         waveformController: newController,
//         audioDuration: dur, // Fixed duration for this track.
//         trimStart: Duration.zero,
//         trimEnd: dur,
//         offset: 0.0,
//         crossfade: 1.0,
//       );

//       // Listen to the player's position to pause it when trimEnd is reached.
//       // NOTE: THIS WAS INTENDED TO UPDATE CURRENTPOS SO THAT SEEK LINES PROGRESS BASED ON THIS VAL
//       // newPlayer.onPositionChanged.listen((position) {
//       //   setState(() {
//       //     newTrack.currentPosition = position;
//       //   });
//       //   if (_isPlaying && position >= newTrack.trimEnd) {
//       //     newPlayer.pause();
//       //   }
//       // });

//       setState(() {  //TODO: take out the async
//         _audioTracks.add(newTrack);
//         if(!_audioOnly) {
//           // _videoController?.dispose(); // not sure if this is needed
//           _initializeVideo(); // maybe too excessive (consider doing it for android only)
//         }
//         _isLoadingAudio = false;
//       });
//     }
//   }

//   Widget _buildVideoAudioAutomationSection() {
//     // Assume currentNormalizedTime is computed from video audio playback progress.
//     double videoAudioNormalizedTime = _videoPosition.inMilliseconds / duration.inMilliseconds;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         // Text("Video Audio Volume Automation"),
//         Text(L10n.translate(context, 'Video Audio Volume Automation'),
//               style: Theme.of(context).textTheme.titleMedium?.copyWith(
//           fontWeight: FontWeight.w400,
//         )),
//         Container(
//           height: 100,
//           color: Colors.grey[200],
//           child: VideoAudioAutomationWidget(
//             automationPoints: videoAudioAutomation,
//             currentNormalizedTime: videoAudioNormalizedTime,
//             onAutomationChanged: (points) {
//               setState(() {
//                 videoAudioAutomation = points;
//               });
//             },
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildAudioEditor() {
//     return StatefulBuilder(
//     builder: (BuildContext context, StateSetter setLocalState) {
//       _audioEditorStateSetter = setLocalState;
//       return SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Audio scrubber at the top.
//             _buildAudioScrubber(),
//             const SizedBox(height: 20),
//             // Row with play/pause and restart buttons.
//             Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 IconButton(
//                   onPressed: () {_togglePlayPauseAudio(setLocalState);},
//                   icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 32),
//                 ),
//                 const SizedBox(width: 20),
//                 IconButton(
//                   onPressed: () {_restartAudio(setLocalState);},
//                   icon: const Icon(Icons.replay, size: 32),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 20),
//             // Multi-track audio section (your list of tracks).
//             _buildMultiTrackAudioSection(),
//             const SizedBox(height: 20),
//             // Export Audio button placed at the bottom of the scroll view.
//             _audioTracks.isEmpty ? Container() : 
//               ElevatedButton.icon(
//                 onPressed: _exportAndNavigate,//_exportAudioOnly,
//                 icon: const Icon(Icons.upload_file),
//                 label: Text(L10n.translate(context, 'Next')),//Export Audio"),
//               ),
//             const SizedBox(height: 30),
//           ],
//         ),
//       );
//     }
//     );
// }


// Future<void> _restartAudio(StateSetter setLocalState) async {
//   // Pause all tracks and seek them to their trimStart.
//   for (var track in _audioTracks) {
//     // await track.player.pause();
//     // await track.player.seek(track.trimStart);
//     track.audioStarted = false;
//   }
//   JuceAudioEngine.pause();
//   // Reset the global audio clock.
//   setLocalState(() {
//     _globalAudioClock = Duration.zero;
//     _isPlaying = false;
//   });
// }


// Widget _buildAudioScrubber() {
//   // Compute overall duration as the maximum (offset + trimmed duration) among tracks.
//   Duration overallDuration = Duration.zero;
//   if (_audioTracks.isNotEmpty) {
//     overallDuration = _audioTracks.map((track) {
//       final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
//       final trackDuration = track.trimEnd - track.trimStart;
//       return offsetDuration + trackDuration;
//     }).reduce((a, b) => a > b ? a : b);
//   }
//   // setState(() {
//   //   _audioOnlyOverallDuration = overallDuration;
//   // });

//   WidgetsBinding.instance.addPostFrameCallback((_) {
//     setState(() {
//       _audioOnlyOverallDuration = overallDuration;
//     });
//   });
//   return Column(
//     children: [
//       Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(_formatDuration(_globalAudioClock)),
//           Text(_formatDuration(overallDuration)),
//         ],
//       ),
//       Slider(
//         value: _globalAudioClock.inMilliseconds.toDouble().clamp(0.0, overallDuration.inMilliseconds.toDouble()),
//         min: 0,
//         max: overallDuration.inMilliseconds.toDouble(),
//         onChangeStart: (value) async {
//            _audioAutomationTimer?.cancel();
//             for (var track in _audioTracks) {
//               // await track.player.pause();
//               track.audioStarted = false; // Reset flag on pause so that resume triggers play.
//             }
//             JuceAudioEngine.pause();
//             _audioEditorStateSetter!(() {
//               _isPlaying = false;
//             });
//         },
//         onChanged: (value) {
//           final newPos = Duration(milliseconds: value.toInt());
//           // Update the UI immediately:
//           _audioEditorStateSetter!(() {
//             _globalAudioClock = newPos;
//           });
//           // For each track, calculate the effective seek position:
//           for (int i = 0; i < _audioTracks.length; i++) {
//             final track = _audioTracks[i];
//             final offsetDuration =
//                 Duration(milliseconds: (track.offset * 1000).round());
//             Duration effectivePos;
//             if (newPos < offsetDuration) {
//               effectivePos = track.trimStart;
//             } else {
//               effectivePos = track.trimStart + (newPos - offsetDuration);
//               if (effectivePos > track.trimEnd) {
//                 effectivePos = track.trimEnd;
//               }
//             }
//             // Kick off the seek without awaiting:
//             // track.player.seek(effectivePos);
//             JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//           }
//           // Update automation (you can call this synchronously or asynchronously).
//           _updateAudioAutomation(newPos);
//         },
//         onChangeEnd: (value) async {
//            _audioAutomationTimer?.cancel();
//             for (var track in _audioTracks) {
//               // await track.player.pause();
//               track.audioStarted = false; // Reset flag on pause so that resume triggers play.
//             }
//             JuceAudioEngine.pause();
//             _audioEditorStateSetter!(() {
//               _isPlaying = false;
//             });
//         },
//       ),
//     ],
//   );
// }


// Future<void> _togglePlayPauseAudio(StateSetter setLocalState) async {
//   setLocalState(() {
//     _isPlaying = !_isPlaying;
//   });
  
//   if (_isPlaying) {
//     JuceAudioEngine.play();
//     // Resume playback: do not reset the global clock.
//     // For each track, if its offset has been reached, start (or resume) playback.
//     for (int i = 0; i < _audioTracks.length; i++) {
//       final track = _audioTracks[i];
//       final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
//       if (_globalAudioClock >= offsetDuration) {
//         final effectivePos = _calculateEffectiveAudioPositionForTrack(track, _globalAudioClock);
//         // await track.player.play(DeviceFileSource(track.file.path));
//         // await track.player.seek(effectivePos);
//         JuceAudioEngine.bypassTrack(i, false);
//         JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//         track.audioStarted = true;
//         track.currentPosition = effectivePos;
//       }
//       else {
//         JuceAudioEngine.bypassTrack(i, true);
//         track.audioStarted = false;
//       }
//     }
//     // Restart the automation timer
//     _audioAutomationTimer?.cancel();
//     _audioAutomationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
//       setLocalState(() {
//         _globalAudioClock += const Duration(milliseconds: 50);
//       });
//       if (_globalAudioClock >= _audioOnlyOverallDuration) {
//         await _restartAudio(setLocalState);
//         return;
//       }
//       _updateAudioAutomation(_globalAudioClock);
//     });
//   } else {
//     // On pause, cancel the timer, pause each track, and importantly, reset audioStarted.
//     _audioAutomationTimer?.cancel();
//     for (var track in _audioTracks) {
//       // await track.player.pause();
//       track.audioStarted = false; // Reset flag on pause so that resume triggers play.
//     }
//     JuceAudioEngine.pause();
//   }
// }



// void _updateAudioAutomation(Duration globalClock) {
//   for (int i = 0; i < _audioTracks.length; i++) {
//     final track = _audioTracks[i];
//     // Convert track.offset (in seconds) to a Duration.
//     final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
//     Duration effectiveAudioPos;
//     if (globalClock < offsetDuration) {
//       // Global clock hasn’t reached the track's offset: use trimStart.
//       effectiveAudioPos = track.trimStart;
//     } else {
//       // Once past offset, effective position is trimStart + (globalClock - offset).
//       effectiveAudioPos = track.trimStart + (globalClock - offsetDuration);
//       if (effectiveAudioPos > track.trimEnd) {
//         effectiveAudioPos = track.trimEnd;
//       }
//     }
    
//     // Calculate the effective duration of the trimmed portion.
//     final effectiveDuration = track.trimEnd - track.trimStart;
//     double normalizedTime = effectiveDuration.inMilliseconds > 0
//         ? (effectiveAudioPos.inMilliseconds - track.trimStart.inMilliseconds) / effectiveDuration.inMilliseconds
//         : 0.0;
//     normalizedTime = normalizedTime.clamp(0.0, 1.0);
    
//     // Compute the volume from the automation curve.
//     final automationVolume = getVolumeForAutomation(track.volumeAutomation, normalizedTime);
//     final finalVolume = automationVolume * min(1.0, _universalCrossfade * 2) * track.gain;
//     // track.player.setVolume(finalVolume);
//     JuceAudioEngine.setTrackVolume(i, finalVolume);
    
//     // Start the track if the offset has been reached and it hasn't started yet.
//     if (globalClock >= offsetDuration && !track.audioStarted) {
//       // track.player.seek(effectiveAudioPos);
//       JuceAudioEngine.seek(i, effectiveAudioPos.inMicroseconds / 1e6);
//       // track.player.play(DeviceFileSource(track.file.path));
//       JuceAudioEngine.bypassTrack(i, false); // TODO: verify that this resumes the track playback
//       track.audioStarted = true;
//     }
//     track.currentPosition = effectiveAudioPos;
//   }
// }

// Future<String> _exportAudioOnly(ValueChanged<double> onProgress) async {
//   if (_audioTracks.isEmpty) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text("No audio tracks selected")),
//     );
//     return "";
//   }

//   onProgress(0.0);

//   final overallDuration = _audioTracks.map((track) {
//     final offsetDuration = Duration(milliseconds: (track.offset * 1000).round());
//     final trackDuration = track.trimEnd - track.trimStart;
//     return offsetDuration + trackDuration;
//   }).reduce((a, b) => a > b ? a : b);

//   // Build input arguments
//   List<String> inputArgs = [];
//   // for (final track in _audioTracks) {
//   //   inputArgs.add('-i "${track.file.path}"');
//   // }

//   for (int i = 0; i < _audioTracks.length; i++) {
//     final tempDir = await getTemporaryDirectory();
//     final outPath = '${tempDir.path}/juce_track${i}_export.wav';
//     final outDir = await JuceAudioEngine.exportTrack(i, outPath);
//     print("_exportAudioOnly: track ${i} exported at ${outDir}");
//     inputArgs.add('-i "${outDir}"');
//   }

//   // Build filter complex
//   List<String> filterLines = [];
//   List<String> trackLabels = [];

//   for (int i = 0; i < _audioTracks.length; i++) {
//     final track = _audioTracks[i];
//     final offsetMs = (track.offset * 1000).round();
//     final startSec = track.trimStart.inMilliseconds / 1000.0;
//     final endSec = track.trimEnd.inMilliseconds / 1000.0;
//     final String label = 'a${i}';

//     String volumeFilter;
//     if (track.volumeAutomation.isNotEmpty) {
//       final String volumeAutomationExpression = generateVolumeAutomationFilter(
//         track,
//         offsetMs,
//         _universalCrossfade,
//       );
//       volumeFilter = 'volume=eval=frame:volume="${volumeAutomationExpression}"';//*${track.gain}"';
//     } else {
//       volumeFilter = 'volume=${min(1.0, _universalCrossfade * 2).toStringAsFixed(2)}';//*${track.gain}';
//     }

//     filterLines.add(
//       '[${i}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
//       'adelay=${offsetMs}|${offsetMs},asetpts=PTS-STARTPTS,'
//       '$volumeFilter[$label];'
//     );

//     trackLabels.add('[$label]');
//     onProgress(((i+1).toDouble()/_audioTracks.length) * 0.5);
//   }
//   onProgress(0.6);

//   // Mix all tracks (matches video export's amix approach)
//   final String amixInputs = trackLabels.join('') +
//       'amix=inputs=${_audioTracks.length}:duration=longest:normalize=0[aout]';
//   filterLines.add(amixInputs);

//   final String filterComplex = filterLines.join('');
  
//   setState(() {
//     filterString = filterComplex;
//   });

//   // Build FFmpeg command (matches video export structure)
//   List<String> ffmpegCmd = [
//     ...inputArgs,
//     '-filter_complex', filterComplex,
//     '-map', '[aout]',
//     '-c:a', 'libmp3lame',
//     '-b:a', '192k',
//     '-ar', '44100',
//     '-loglevel', 'verbose',
//     '-y',
//   ];

//   final tempDir = await getTemporaryDirectory();
//   final outPath = '${tempDir.path}/audio_export_${DateTime.now().millisecondsSinceEpoch}.mp3';
//   ffmpegCmd.add('"$outPath"');

//   // print("FFmpeg command: ${ffmpegCmd.join(' ')}");

//   try {
//     final session = await FFmpegKit.execute(ffmpegCmd.join(' '));
//     onProgress(1.0);
//     final returnCode = await session.getReturnCode();

//     final allLogs = await session.getAllLogs() ?? [];
//     final errorLogs = await session.getLogs() ?? [];

//     String getLogMessages(List<Log> logs) {
//       return logs.map((log) => log.getMessage() ?? "null").join('\n');
//     }

//     final lastErrorCount = min(10, errorLogs.length);
//     final lastErrors = errorLogs.sublist(max(0, errorLogs.length - lastErrorCount));
//     final lastErrorMessages = getLogMessages(lastErrors);

//     print("═════════ LAST ERRORS ═════════");
//     print(lastErrorMessages);

//     if (ReturnCode.isSuccess(returnCode)) {
//       final outFile = File(outPath);
//       int retries = 0;
//       while (!await outFile.exists() && retries < 20) {
//         await Future.delayed(const Duration(milliseconds: 250));
//         retries++;
//       }

//       if (!await outFile.exists() || (await outFile.length()) < 1000) {
//         print("❌ ERROR: Output file is missing or too small!");
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Export failed: Output file missing or too small.')),
//         );
//         return "";
//       }

//       print("✅ File found: $outPath");

//       return outPath;
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Export failed:\n${lastErrorMessages.isNotEmpty
//               ? lastErrorMessages
//               : "Unknown error (RC: $returnCode)"}'),
//           duration: Duration(seconds: 10),
//         ),
//       );
//     }
//   } catch (e) {
//     print("Full export error: $e");
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text('Export error: ${e.toString().split('\n').first}'),
//         duration: Duration(seconds: 5),
//       ),
//     );
//   }
//   return "";
// }

// Widget _buildIntroScreen() {
//   return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//         return Scaffold(
//           appBar: AppBar(title: Text(L10n.translate(context, 'Editor'))),
//           drawer: const SideMenu(),
//           backgroundColor: const Color(0xFF1A1A1A), // your app's background color
//           body: Padding(
//             padding: const EdgeInsets.all(16.0),
//             child: Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   CustomSelectModeWidget(
//                     onTap: () {
//                       // Clear audio-only flag and trigger video selection.
//                       setState(() {
//                         _audioOnly = false;
//                       });
//                       _pickVideoFile();
//                     },
//                     icon: Icons.videocam,
//                     text: L10n.translate(context, 'Video Editing'),
//                   ),
//                   const SizedBox(height: 30),
//                   CustomSelectModeWidget(
//                     onTap: () {
//                       // Switch to audio-only mode.
//                       setState(() {
//                         _audioOnly = true;
//                       });
//                     },
//                     icon: Icons.audiotrack,
//                     text: '${L10n.translate(context, 'Audio-Only Mode')}',
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//     }
//   );
// }

// Future<void> _exportAndNavigate() async {
//   setState(() {
//     _isLoadingNextScreen = true;
//   });
//   if(_isPlaying) {
//     _audioOnly ? await _togglePlayPauseAudio(_audioEditorStateSetter!) : await _togglePlayPause();
//   }
//   // final exportPath = _audioOnly ? await _exportAudioOnly() : await _exportVideo();
//   final exportPath = await Navigator.push<String>(
//     context,
//     MaterialPageRoute(
//       builder: (_) => ExportProgressPage(exportFn: _audioOnly ? _exportAudioOnly : _exportVideo, videoFile: _audioOnly ? "" : _videoFile!.path),
//     ),
//   );
//   if (!mounted) return;

//   setState(() {
//     _isLoadingNextScreen = false;
//   });

//   final params = SaveFileDialogParams(
//     sourceFilePath: exportPath,
//     fileName: 'export_file.${!_audioOnly ? 'mp4' : 'mp3'}',
//   );
//   final savedPath = await FlutterFileDialog.saveFile(params: params);

//   if (savedPath != null) {
//     final success_str = L10n.translate(context, 'Exported file saved!');
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(success_str)),// at: $savedPath')),
//     );
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => ExportSuccessScreen(
//           filePath: savedPath,
//           isVideo: !_audioOnly,
//         ),
//       ),
//     );
//   } else {
//     final fail_str = L10n.translate(context, 'Export canceled or failed.');
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(fail_str)),
//     );
//   }
// }

// Widget _buildFloatingTransportBar() {
//   final theme = Theme.of(context);

//   final maxValue = duration.inMilliseconds.toDouble();
//   double currentValue = _isScrubbing
//       ? _scrubPosition.inMilliseconds.toDouble()
//       : _videoPosition.inMilliseconds.toDouble();
//   currentValue = currentValue.clamp(0.0, maxValue);
//   // return Positioned(
//   //   bottom: 24,
//   //   left: 16,
//   //   right: 16,
//     // child: ClipRRect(
//     return ClipRRect(
//       borderRadius: BorderRadius.circular(35),
//       child: BackdropFilter(
//         filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//           decoration: BoxDecoration(
//             color: const Color.fromARGB(255, 32, 32, 32).withOpacity(0.75),
//             borderRadius: BorderRadius.circular(35),
//             border: Border.all(
//               color: const Color.fromARGB(255, 80, 80, 80), // Or adjust to your desired grey
//               width: 1.5,
//             ),
//           ),
//           child: Row(
//             children: [
//               // Play/Pause button
//               IconButton(
//                 icon: Icon(
//                   _isPlaying ? Icons.pause : Icons.play_arrow,
//                   color: Colors.white,
//                 ),
//                 onPressed: _togglePlayPause,
//               ),

//               // Restart button
//               IconButton(
//                 icon: const Icon(Icons.replay, color: Colors.white),
//                 onPressed: _restartVideo,
//               ),

//               // Scrubber
//               Expanded(
//                 child: Slider(
//                   value: currentValue,
//                   min: 0,
//                   max: maxValue,
//                   onChangeStart: (value) {
//                     for (var track in _audioTracks) {
//                       track.audioStartTimer?.cancel();
//                     }
//                     _pausePlayback();
//                     _stopTicker();
//                     setState(() {
//                       _isScrubbing = true;
//                       _scrubPosition = Duration(milliseconds: value.toInt());
//                     });
//                   },
//                   onChanged: (value) {
//                     setState(() {
//                       _scrubPosition = Duration(milliseconds: value.toInt());
//                     });
//                   },
//                   onChangeEnd: (value) async {
//                     final newPosition = Duration(milliseconds: value.toInt());
//                     setState(() {
//                       _isScrubbing = false;
//                       _videoPosition = newPosition;
//                       _scrubPosition = newPosition;
//                     });

//                     await seekTo(newPosition);

//                     for (int i = 0; i < _audioTracks.length; i++) {
//                       final track = _audioTracks[i];
//                       final effectivePos = _calculateEffectiveAudioPositionForTrack(track, newPosition);

//                       await JuceAudioEngine.seek(i, effectivePos.inMicroseconds / 1e6);
//                       setState(() {
//                         track.currentPosition = effectivePos;
//                       });
//                     }


//                     if(_isPlaying) {
//                       _resumePlayback();
//                       _startTicker();
//                     }
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
// }


//   @override
//   Widget build(BuildContext context) {
//     // If no video is selected and we're not in audio-only mode,
//     // offer the choice.
//     if (_videoFile == null && !_audioOnly) {
//       return _buildIntroScreen();
//     }

//     if (_audioOnly) {
//       return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Scaffold(
//             appBar: AppBar(title: Text(L10n.translate(context, 'Audio Editor'))),
//             drawer: const SideMenu(),
//             body: _buildAudioEditor(),
//           );
//         }
//       );
//     } else {
//       return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Stack(
//         children: [
//           Scaffold(
//             extendBody: true,
//             appBar: AppBar(title: Text(L10n.translate(context, 'Video Editor'))),
//             drawer: const SideMenu(),
//             body: Stack(
//               children: [
//                 SingleChildScrollView(
//                   padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
//                   child: Column(
//                     children: [
//                       // VIDEO SECTION
//                       _videoController == null && betterController == null
//                           ? CustomSelectVideoWidget(onTap: _pickVideoFile)
//                           : Column(
//                               crossAxisAlignment: CrossAxisAlignment.stretch,
//                               children: [
//                                 GestureDetector(
//                                   onTap: _pickVideoFile,
//                                   key: const ValueKey('video_player'),
//                                   child: useBetterPlayer ? BetterPlayer(controller: betterController!) : AspectRatio(
//                                       aspectRatio: aspectRatio,
//                                       child:VideoPlayer(_videoController!)
//                                     ),
//                                 ),
//                                 const SizedBox(height: 8),
//                                 _buildTimeDisplay(),
//                                 // _buildCustomScrubber(),
//                                 // Row(
//                                 //   mainAxisAlignment: MainAxisAlignment.center,
//                                 //   children: [
//                                 //     IconButton(
//                                 //       icon: Icon(
//                                 //         _isPlaying ? Icons.pause : Icons.play_arrow,
//                                 //         size: 32,
//                                 //       ),
//                                 //       onPressed: _togglePlayPause,
//                                 //     ),
//                                 //     const SizedBox(width: 20),
//                                 //     IconButton(
//                                 //       icon: const Icon(Icons.replay, size: 32),
//                                 //       onPressed: _restartVideo,
//                                 //     ),
//                                 //   ],
//                                 // ),
//                                 const SizedBox(height: 10),
//                                 GestureDetector(
//                                   onVerticalDragDown: (_) {}, // just to claim the gesture
//                                   behavior: HitTestBehavior.translucent,
//                                   child: _buildVideoAudioAutomationSection(),
//                                 ),
//                               ],
//                             ),
//                       const SizedBox(height: 20),
//                       // AUDIO SECTION
//                       _videoFile != null
//                         ? (_audioTracks.isEmpty
//                             ? ElevatedButton.icon(
//                                 onPressed: _showAudioSourceOptions,
//                                 icon: const Icon(Icons.audiotrack),
//                                 label: Text(L10n.translate(context, 'Select Audio')),
//                               )
//                             : _buildMultiTrackAudioSection())
//                         : Container(),//_buildAudioControls(),
//                       // const SizedBox(height: 10),
//                       // AI SYNC + EXPORT BUTTON
//                       _videoFile != null && _audioTracks.isNotEmpty
//                         ? Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                             children: [
//                               ElevatedButton.icon(
//                                 onPressed: () async {
//                                   final shouldSync = await showDialog<bool>(
//                                     context: context,
//                                     builder: (context) => AlertDialog(
//                                       title: const Text("AI Sync"),
//                                       content: Text(
//                                         "Automatically syncs video and audio tracks.\nAudio offset/trim may be adjusted.",
//                                         style: Theme.of(context).textTheme.bodyLarge
//                                       ),
//                                       actions: [
//                                         TextButton(
//                                           onPressed: () => Navigator.of(context).pop(false),
//                                           child: const Text("Cancel"),
//                                         ),
//                                         ElevatedButton(
//                                           onPressed: () => Navigator.of(context).pop(true),
//                                           child: const Text("Sync"),
//                                         ),
//                                       ],
//                                     ),
//                                   ) ?? false;

//                                   if (shouldSync == false) {
//                                     return;
//                                   }
//                                   // Ensure both video and at least one audio track are available.
//                                   if (_videoFile == null || _audioTracks.isEmpty) return;

//                                   setState(() {
//                                     _isPlaying = false;
//                                   });
//                                   _pausePlayback();
//                                   _stopTicker();

//                                   setState(() {
//                                     _isSyncing = true;
//                                     _syncProgress = 0.0;
//                                   });

//                                   for (var track in _audioTracks) {
//                                     await applyBestSyncOffset(track, _videoFile!.path);
//                                   }
//                                   setState(() {
//                                     _isSyncing = false;
//                                     _syncProgress = 0.0;
//                                   });

//                                   _restartVideo();

//                                   ScaffoldMessenger.of(context).showSnackBar(
//                                     SnackBar(content: Text(L10n.translate(context, 'AI Sync applied successfully!'))),
//                                   );
//                                   _restartVideo();
//                                 },
//                                 icon: const Icon(Icons.sync),
//                                 label: Text(L10n.translate(context, 'AI Sync')),
//                               ),
//                               ElevatedButton.icon(
//                                 onPressed: _exportAndNavigate,//_exportVideo,
//                                 icon: const Icon(Icons.upload_file),
//                                 label: Text(L10n.translate(context, 'Export')),
//                               ),
//                             ],
//                           )
//                         : Container(),
//                       const SizedBox(height: 60),
//                     ],
//                   ),
//             ),
//             // PLAY/PAUSE/RESTART/SEEK CONTROL
//             // _buildFloatingTransportBar(),
//             // END OF SINGLECHILDSCROLLVIEW
//             // BELOW IS UI ANIMATIONS
//                 if (_isSyncing)
//                   Positioned.fill(
//                   child: Container(
//                     color: Colors.black.withOpacity(0.75),
//                     child: Center(
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           const DotsLoader(),
//                           const SizedBox(height: 16),
//                           SizedBox(
//                             width: 250,
//                             child: LinearProgressIndicator(
//                               value: _syncProgress,
//                               backgroundColor: Colors.white30,
//                               valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
//                             ),
//                           ),
//                           const SizedBox(height: 8),
//                           Text(
//                             '${(_syncProgress * 100).toStringAsFixed(1)}%',
//                             style: const TextStyle(color: Colors.white70),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//             ]
//           ),
//           bottomNavigationBar: Padding(
//             padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
//             child: SizedBox(
//               height: 64, // or any height you want for the floating bar
//               child: _buildFloatingTransportBar(),
//             ),
//           ),
//         ),
//         if (_isLoadingVideo || _isLoadingAudio || _isLoadingNextScreen)
//           Positioned.fill(
//             child: Container(
//               color: Colors.black.withOpacity(0.5),
//               child: const Center(
//                 child: CircularProgressIndicator(),
//               ),
//             ),
//           ),
//         _buildProgressIndicator(),
//           // Positioned(
//           //   left: 16,
//           //   right: 16,
//           //   bottom: 24,
//           //   child: Material(
//           //     type: MaterialType.transparency, // Ensures background doesn't block clicks
//           //     child: SizedBox(
//           //       height: 64,
//           //       child: _buildFloatingTransportBar(),
//           //     ),
//           //   ),
//           // ),
//         ],
//       );
//         }
//       );
//     }
//   }
// }

// class CustomSelectVideoWidget extends StatelessWidget {
//   final VoidCallback onTap;
//   const CustomSelectVideoWidget({Key? key, required this.onTap}) : super(key: key);
  
//   @override
//   Widget build(BuildContext context) {
//     return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return GestureDetector(
//       onTap: onTap,
//       child: Stack(
//         alignment: Alignment.center,
//         children: [
//           Container(
//             width: double.infinity,
//             height: 250,
//             decoration: BoxDecoration(
//               color: Colors.transparent,
//             ),
//             child: Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Icon(
//                     Icons.videocam,
//                     size: 48,
//                     color: const Color(0xFF2E61A5),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(L10n.translate(context, 'Select Video'),style: TextStyle(
//                       fontSize: 24,
//                       fontWeight: FontWeight.w400,
//                       color: Color(0xFF2E61A5),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           Positioned.fill(
//             child: CustomPaint(
//               painter: CornerPainter(
//                 cornerLength: 20,
//                 strokeWidth: 3,
//                 color: const Color(0xFF2E61A5),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//         }
//     );
//   }
// }

// class CustomSelectModeWidget extends StatelessWidget {
//   final VoidCallback onTap;
//   final IconData icon;
//   final String text;
  
//   const CustomSelectModeWidget({
//     Key? key,
//     required this.onTap,
//     required this.icon,
//     required this.text,
//   }) : super(key: key);
  
//   @override
//   Widget build(BuildContext context) {
//     return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return GestureDetector(
//       onTap: onTap,
//       child: Stack(
//         alignment: Alignment.center,
//         children: [
//           Container(
//             width: double.infinity,
//             height: 250,
//             decoration: BoxDecoration(
//               color: Colors.transparent,
//             ),
//             child: Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Icon(
//                     icon,
//                     size: 48,
//                     color: const Color(0xFF2E61A5),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     text,
//                     style: const TextStyle(
//                       fontSize: 24,
//                       fontWeight: FontWeight.w400,
//                       color: Color(0xFF2E61A5),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           Positioned.fill(
//             child: CustomPaint(
//               painter: CornerPainter(
//                 cornerLength: 20,
//                 strokeWidth: 3,
//                 color: const Color(0xFF2E61A5),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//         }
//     );
//   }
// }

// class CornerPainter extends CustomPainter {
//   final double cornerLength;
//   final double strokeWidth;
//   final Color color;
  
//   CornerPainter({
//     this.cornerLength = 20.0,
//     this.strokeWidth = 3.0,
//     this.color = const Color(0xFF2E61A5), // your red-ish color
//   });
  
//   @override
//   void paint(Canvas canvas, Size size) {
//     final Paint paint = Paint()
//       ..color = color
//       ..strokeWidth = strokeWidth
//       ..style = PaintingStyle.stroke;
    
//     // Top left corner
//     canvas.drawLine(Offset(0, 0), Offset(cornerLength, 0), paint);
//     canvas.drawLine(Offset(0, 0), Offset(0, cornerLength), paint);
    
//     // Top right corner
//     canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
//     canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);
    
//     // Bottom left corner
//     canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);
//     canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);
    
//     // Bottom right corner
//     canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
//     canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
//   }
  
//   @override
//   bool shouldRepaint(CustomPainter oldDelegate) => false;
// }

// class DotsLoader extends StatefulWidget {
//   const DotsLoader({Key? key}) : super(key: key);

//   @override
//   State<DotsLoader> createState() => _DotsLoaderState();
// }

// class _DotsLoaderState extends State<DotsLoader> with SingleTickerProviderStateMixin {
//   late AnimationController _controller;
//   late Animation<int> _dotCount;

//   @override
//   void initState() {
//     super.initState();
//     _controller = AnimationController(duration: const Duration(seconds: 1), vsync: this)
//       ..repeat();
//     _dotCount = StepTween(begin: 0, end: 4).animate(_controller);
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     const maxDots = 4;
//     const dotWidth = 6.0; // each dot ~6px
//     final totalDotSpace = maxDots * dotWidth;

//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Text(
//           '${L10n.translate(context, 'Syncing Audio')}',
//           style: TextStyle(color: Colors.white, fontSize: 20),
//         ),
//         const SizedBox(width: 2),
//         SizedBox(
//           width: totalDotSpace,
//           child: AnimatedBuilder(
//             animation: _dotCount,
//             builder: (context, _) {
//               return Text(
//                 '.' * _dotCount.value,
//                 style: const TextStyle(color: Colors.white, fontSize: 20),
//               );
//             },
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _WaveformSeekLinePainter extends CustomPainter {
//   _WaveformSeekLinePainter({
//     required this.audioPosition,   // ← pass in effectiveAudioPos
//     required this.trimStart,
//     required this.trimEnd,
//     required this.totalAudioDuration,
//     required this.lineColor,
//   });

//   final Duration audioPosition;
//   final Duration trimStart;
//   final Duration trimEnd;
//   final Duration totalAudioDuration;
//   final Color   lineColor;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final Paint paint = Paint()
//       ..color = lineColor
//       ..strokeWidth = 2.0;

//     // First, compute how far into the trimmed region our audioPosition is,
//     // clamped between trimStart and trimEnd:
//     if (audioPosition < trimStart || audioPosition > trimEnd) {
//       return; // nothing to draw if outside the trimmed range
//     }

//     // Map [trimStart .. trimEnd] → [0.0 .. 1.0]
//     final trimmedDuration = trimEnd - trimStart;
//     final normalized = (audioPosition - trimStart).inMilliseconds 
//                      / trimmedDuration.inMilliseconds;

//     // Compute X in the total waveform:
//     final trimStartRatio = trimStart.inMilliseconds 
//                          / totalAudioDuration.inMilliseconds;
//     final trimEndRatio   = trimEnd.inMilliseconds 
//                          / totalAudioDuration.inMilliseconds;

//     final waveformStartX = size.width * trimStartRatio;
//     final waveformEndX   = size.width * trimEndRatio;

//     final seekX = waveformStartX + (waveformEndX - waveformStartX) * normalized;
//     canvas.drawLine(
//       Offset(seekX, 0),
//       Offset(seekX, size.height),
//       paint,
//     );
//   }

//   @override
//   bool shouldRepaint(covariant _WaveformSeekLinePainter old) {
//     return old.audioPosition != audioPosition
//         || old.trimStart     != trimStart
//         || old.trimEnd       != trimEnd
//         || old.totalAudioDuration != totalAudioDuration
//         || old.lineColor     != lineColor;
//   }
// }



// class AudioTrack {
//   File file;
//   File originalFile; // for gain
//   // final AudioPlayer player;
//   final PlayerController waveformController;
//   final Duration audioDuration;
//   Duration trimStart;
//   Duration trimEnd;
//   double offset;
//   double crossfade;
//   Timer? audioStartTimer;
//   bool audioStarted;
//   List<AutomationPoint> volumeAutomation; // NEW property
//   Duration currentPosition; 
//   late List<double> normWaveformData;
//   double gain;
//   // consider moving the below FX into a separate class
//   double reverb;
//   double echo;

//   AudioTrack._({
//     required this.file,
//     required this.originalFile,
//     // required this.player,
//     required this.waveformController,
//     required this.audioDuration,
//     required this.trimStart,
//     required this.trimEnd,
//     required this.offset,
//     required this.crossfade,
//     this.audioStartTimer,
//     this.audioStarted = false,
//     List<AutomationPoint>? volumeAutomation,
//     Duration? currentPosition,
//     this.normWaveformData = const [],
//     this.gain = 1.0,
//     this.reverb = 0.0,
//     this.echo = 0.0,
//   }) : currentPosition = currentPosition ?? Duration.zero,
//       volumeAutomation = volumeAutomation ??
//          [
//            AutomationPoint(x: 0.0, volume: 1.0),
//            AutomationPoint(x: 1.0, volume: 1.0)
//          ];

//   static Future<AudioTrack> create({
//       required File file,
//       required File originalFile,
//       // required AudioPlayer player,
//       required PlayerController waveformController,
//       required Duration audioDuration,
//       Duration trimStart = Duration.zero,
//       Duration trimEnd = Duration.zero,
//       double offset = 0.0,
//       double crossfade = 0.0,
//       Timer? audioStartTimer,
//       bool audioStarted = false,
//       List<AutomationPoint>? volumeAutomation,
//       Duration? currentPosition,
//       double gain = 1.0,
//       double reverb = 0.0,
//       double echo = 0.0,
//     }) async {

//       // Then create instance
//       return AudioTrack._(
//         file: file,
//         originalFile: originalFile,
//         // player: player,
//         waveformController: waveformController,
//         audioDuration: audioDuration,
//         trimStart: trimStart,
//         trimEnd: trimEnd,
//         offset: offset,
//         crossfade: crossfade,
//         audioStartTimer: audioStartTimer,
//         audioStarted: audioStarted,
//         volumeAutomation: volumeAutomation,
//         currentPosition: currentPosition,
//         normWaveformData: const [],
//         gain: gain,
//         reverb: reverb,
//         echo: echo,
//       );
//     }
// }

// double getVolumeForAutomation(List<AutomationPoint> points, double normalizedTime) {
//   if (points.isEmpty) return 1.0;
//   if (normalizedTime <= points.first.x) return points.first.volume;
//   if (normalizedTime >= points.last.x) return points.last.volume;
//   for (int i = 0; i < points.length - 1; i++) {
//     if (normalizedTime >= points[i].x && normalizedTime <= points[i + 1].x) {
//       double t = (normalizedTime - points[i].x) / (points[i + 1].x - points[i].x);
//       return points[i].volume + t * (points[i + 1].volume - points[i].volume);
//     }
//   }
//   return 1.0;
// }

// class AutomationPoint {
//   double x;      // normalized x (0.0 = left, 1.0 = right)
//   double volume; // normalized volume (0.0 = silent, 1.0 = full)
//   AutomationPoint({required this.x, required this.volume});
// }

// class VolumeAutomationWidget extends StatefulWidget {
//   final List<AutomationPoint> automationPoints;
//   final double currentNormalizedTime; // normalized current playback time (0.0 to 1.0)
//   final ValueChanged<List<AutomationPoint>> onAutomationChanged;

//   const VolumeAutomationWidget({
//     Key? key,
//     required this.automationPoints,
//     required this.currentNormalizedTime,
//     required this.onAutomationChanged,
//   }) : super(key: key);

//   @override
//   _VolumeAutomationWidgetState createState() => _VolumeAutomationWidgetState();
// }

// class _VolumeAutomationWidgetState extends State<VolumeAutomationWidget> {
//   late List<AutomationPoint> _points;
//   static const double _autoSnapNorm = 0.02;
//   @override
//   void initState() {
//     super.initState();
//     // Create a copy so we can modify it.
//     _points = List.from(widget.automationPoints);
//   }

//   @override
//   void didUpdateWidget(covariant VolumeAutomationWidget oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (widget.automationPoints != oldWidget.automationPoints) {
//       setState(() {
//         _points = List.from(widget.automationPoints);
//       });
//     }
//   }

//   void _addPoint(Offset localPosition, double width, double height) {
//     double x = (localPosition.dx / width).clamp(0.0, 1.0);
//     double volume = _interpolateVolume(x);
//     setState(() {
//       _points.add(AutomationPoint(x: x, volume: volume));
//       _points.sort((a, b) => a.x.compareTo(b.x));
//     });
//     widget.onAutomationChanged(_points);
//   }

//   double _interpolateVolume(double x) {
//     if (_points.isEmpty) return 1.0;
//     if (x <= _points.first.x) return _points.first.volume;
//     if (x >= _points.last.x) return _points.last.volume;
//     for (int i = 0; i < _points.length - 1; i++) {
//       if (x >= _points[i].x && x <= _points[i + 1].x) {
//         double t = (x - _points[i].x) / (_points[i + 1].x - _points[i].x);
//         return _points[i].volume + t * (_points[i + 1].volume - _points[i].volume);
//       }
//     }
//     return 1.0;
//   }
  
// Widget _buildDraggableHandle(AutomationPoint point, double width, double height) {
//   const double visibleHandleSize = 24;
//   const double hitBoxSize = 48;

//   const double edgeExtension = 16; // How much extra space to provide at the edges

//   double hitBoxLeft = point.x * width - hitBoxSize / 2;
//   double hitBoxTop = (1 - point.volume) * height - hitBoxSize / 2;

//   // Adjust positioning for the first (left edge) and last (right edge) points
//   if (point == _points.first) {
//     hitBoxLeft = -edgeExtension;
//   } else if (point == _points.last) {
//     hitBoxLeft = width - hitBoxSize + edgeExtension;
//   }

//   return Positioned(
//     left: hitBoxLeft,
//     top: hitBoxTop,
//     width: hitBoxSize,
//     height: hitBoxSize,
//     child: Listener( // Use Listener instead of RawGestureDetector
//       onPointerMove: (PointerMoveEvent event) {
//         setState(() {
//           double newVolume = point.volume - event.delta.dy / height;
//           newVolume = newVolume.clamp(0.0, 1.0);
//           point.volume = newVolume;

//           // Update horizontal position if needed
//           if (point != _points.first && point != _points.last) {
//             double newX = point.x + event.delta.dx / width;
//             int index = _points.indexOf(point);
//             double leftLimit = _points[index - 1].x + 0.01;
//             double rightLimit = _points[index + 1].x - 0.01;
//             point.x = newX.clamp(leftLimit, rightLimit);
//           }

//           // snap to seek line
//           double seekNorm = widget.currentNormalizedTime;
//           if ((point.x - seekNorm).abs() < _autoSnapNorm) {
//             point.x = seekNorm;
//           }
//         });
//         widget.onAutomationChanged(_points);
//       },
//       child: Center(
//         child: GestureDetector(
//           onLongPress: () {
//             if (point != _points.first && point != _points.last) {
//               setState(() => _points.remove(point));
//               widget.onAutomationChanged(_points);
//             }
//           },
//           child: Container(
//             width: visibleHandleSize,
//             height: visibleHandleSize,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               color: (point == _points.first || point == _points.last)
//                   ? const Color(0xFF888888)
//                   : const Color(0xFF2E61A5),
//             ),
//           ),
//         ),
//       ),
//     ),
//   );
// }


//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(builder: (context, constraints) {
//       final double width = constraints.maxWidth;
//       final double height = constraints.maxHeight;
//       return GestureDetector(
//         onLongPressStart: (details) {
//           final RenderBox box = context.findRenderObject() as RenderBox;
//           final localPos = box.globalToLocal(details.globalPosition);
//           _addPoint(localPos, width, height);
//         },
//         child: Stack(
//           children: [
//             CustomPaint(
//               size: Size(width, height),
//               painter: _AutomationPainter(
//                 points: _points,
//                 currentNormalizedTime: widget.currentNormalizedTime,
//               ),
//             ),
//             for (var point in _points)
//               _buildDraggableHandle(point, width, height),
//           ],
//         ),
//       );
//     });
//   }
// }

// class _AutomationPainter extends CustomPainter {
//   final List<AutomationPoint> points;
//   final double currentNormalizedTime;
//   _AutomationPainter({
//     required this.points,
//     required this.currentNormalizedTime,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     if (points.isEmpty) return;
//     Paint linePaint = Paint()
//       ..color = Color(0xFF888888)
//       ..strokeWidth = 2.0
//       ..style = PaintingStyle.stroke;
//     // Draw the automation curve.
//     Path path = Path();
//     final first = points.first;
//     path.moveTo(first.x * size.width, (1 - first.volume) * size.height);
//     for (var point in points.skip(1)) {
//       path.lineTo(point.x * size.width, (1 - point.volume) * size.height);
//     }
//     canvas.drawPath(path, linePaint);

//     // Optionally fill under the curve.
//     Paint fillPaint = Paint()
//       ..color = Color(0x33888888)
//       ..style = PaintingStyle.fill;
//     Path fillPath = Path.from(path);
//     fillPath.lineTo(points.last.x * size.width, size.height);
//     fillPath.lineTo(points.first.x * size.width, size.height);
//     fillPath.close();
//     canvas.drawPath(fillPath, fillPaint);

//     // Draw the seek line (non-interactive).
//     double seekX = currentNormalizedTime.isFinite ? currentNormalizedTime * size.width : 0.0;
//     Paint seekPaint = Paint()
//       ..color = Color(0xFF888888)
//       ..strokeWidth = 2;
//     canvas.drawLine(Offset(seekX, 0), Offset(seekX, size.height), seekPaint);
//   }

//   @override
//   bool shouldRepaint(covariant _AutomationPainter oldDelegate) {
//     return oldDelegate.points != points ||
//         oldDelegate.currentNormalizedTime != currentNormalizedTime;
//   }
// }

// void _findSyncOffsetInBackground(List<Object?> args) {
//   final SendPort sendPort = args[0] as SendPort;
//   final String videoAudioPath = args[1] as String;
//   final String convertedTrackPath = args[2] as String;
//   final double sampleRate = args[3] as double;
//   final SendPort progressPort = args[4] as SendPort;

//   void run() async {
//     List<double> videoSamples = await loadAudioSamplesAsync(videoAudioPath);
//     List<double> trackSamples = await loadAudioSamplesAsync(convertedTrackPath);

//     int bestOffset = findOffsetFFT(videoSamples, trackSamples, sampleRate, progressPort);
//     sendPort.send(bestOffset);
//   }

//   run();
// }

// // Synchronous function to load audio samples
// List<double> loadAudioSamples(String filePath, {int numChannels = 2}) {
//   final file = File(filePath);
//   final bytes = file.readAsBytesSync(); 

//   final Uint8List audioBytes = Uint8List.fromList(bytes);
//   List<double> samples = [];

//   for (int i = 0; i < audioBytes.length - 1; i += 2 * numChannels) { 
//     int sample = audioBytes[i] | (audioBytes[i + 1] << 8);
//     if (sample >= 0x8000) sample -= 0x10000;
//     samples.add(sample / 32768.0);
//   }

//   return samples;
// }


// Future<List<double>> loadAudioSamplesAsync(String filePath, {int numChannels = 2}) async {
//   final file = File(filePath);
//   final bytes = await file.readAsBytes(); 

//   final Uint8List audioBytes = Uint8List.fromList(bytes);
//   List<double> samples = [];

//   for (int i = 0; i < audioBytes.length - 1; i += 2 * numChannels) { 
//     int sample = audioBytes[i] | (audioBytes[i + 1] << 8);
//     if (sample >= 0x8000) sample -= 0x10000;
//     samples.add(sample / 32768.0);
//   }

//   return samples;
// }

// int findOffsetFFT(List<double> videoSamples, List<double> trackSamples, double sampleRate, SendPort progressPort) {
//   // 1. Downsample first (Key optimization)
//   const int targetSampleRate = 8000; // Adequate for sync
//   final double ratio = sampleRate / targetSampleRate;
  
//   final videoDown = _downsample(videoSamples, ratio);
//   final trackDown = _downsample(trackSamples, ratio);
//   final effectiveRate = sampleRate / ratio;

//   // 2. Calculate optimal FFT size
//   final minLength = videoDown.length + trackDown.length - 1;
//   final fftSize = _nextPowerOf2(minLength);
//   final fft = FFT(fftSize);

//   progressPort.send(0.1);

//   // 3. Memory-efficient windowing
//   final windowedVideo = _applyWindow(videoDown, fftSize);
//   final windowedTrack = _applyWindow(trackDown, fftSize);
  
//   progressPort.send(0.3);

//   // 4. Compute FFTs (using your original FFT calls)
//   final videoFFT = fft.realFft(windowedVideo);
//   progressPort.send(0.5);
//   final trackFFT = fft.realFft(windowedTrack);
//   progressPort.send(0.6);

//   // 5. Frequency-domain multiplication (fixed type)
//   final productFFT = List<Float64x2>.generate(videoFFT.length, (i) {
//     final v = videoFFT[i], t = trackFFT[i];
//     return Float64x2(
//       v.x * t.x + v.y * t.y, // real
//       v.y * t.x - v.x * t.y  // imag
//     );
//   });
//   progressPort.send(0.7);

//   // 6. Inverse FFT and peak finding
//   final productFFTList = Float64x2List.fromList(productFFT);
//   final correlation = fft.realInverseFft(productFFTList);
//   // final correlation = fft.realInverseFft(productFFT);
//   progressPort.send(0.8);
  
//   final peakIndex = _findPeakIndex(correlation);
//   final refinedLag = _refinePeak(correlation, peakIndex, fftSize);
//   final offsetMs = (refinedLag / effectiveRate * 1000).round();

//   progressPort.send(1.0);
//   return offsetMs;
// }

// // ---- Helper Functions ---- //

// List<double> _downsample(List<double> input, double ratio) {
//   final newLength = (input.length / ratio).floor();
//   return List.generate(newLength, (i) => input[(i * ratio).floor()]);
// }

// List<double> _applyWindow(List<double> input, int fftSize) {
//   final output = List<double>.filled(fftSize, 0.0);
//   final length = min(input.length, fftSize);
  
//   for (int i = 0; i < length; i++) {
//     final hann = 0.5 * (1 - cos(2 * pi * i / (length - 1)));
//     output[i] = input[i] * hann;
//   }
//   return output;
// }

// int _findPeakIndex(List<double> data) {
//   int maxIndex = 0;
//   for (int i = 1; i < data.length; i++) {
//     if (data[i] > data[maxIndex]) maxIndex = i;
//   }
//   return maxIndex;
// }

// double _refinePeak(List<double> data, int index, int fftSize) {
//   if (index <= 0 || index >= data.length - 1) return index.toDouble();
  
//   final double delta = 0.5 * (data[index-1] - data[index+1]) / 
//                      (data[index-1] - 2*data[index] + data[index+1]);
  
//   final refined = index + delta;
//   return refined < fftSize/2 ? refined : refined - fftSize;
// }

// // int _nextPowerOf2(int n) => 1 << (n.bitLength + (n & (n - 1) == 0 ? 0 : 1));




// // int findOffsetFFT(List<double> videoSamples, List<double> trackSamples, double sampleRate, SendPort progressPort) {
// //   final int videoLength = videoSamples.length;
// //   final int trackLength = trackSamples.length;
  
// //   // Compute minimum padded length, then optionally choose a higher power of 2 for more resolution.
// //   final int minPaddedLength = videoLength + trackSamples.length - 1;
// //   final int paddedLength = _nextPowerOf2(minPaddedLength);
// //   final fft = FFT(paddedLength);

// //   progressPort.send(0.05);

// //   // Zero-pad both signals.
// //   // Optionally, apply a Hann window to improve accuracy.
// //   List<double> windowedVideo = applyHannWindow(videoSamples);
// //   List<double> windowedTrack = applyHannWindow(trackSamples);

// //   List<double> paddedVideo = List.filled(paddedLength, 0.0);
// //   List<double> paddedTrack = List.filled(paddedLength, 0.0);
// //   paddedVideo.setAll(0, windowedVideo);
// //   paddedTrack.setAll(0, windowedTrack);

// //   progressPort.send(0.25);

// //   normalize(paddedVideo);
// //   normalize(paddedTrack);
// //   progressPort.send(0.35);

// //   // Compute FFTs.
// //   final videoFFT = fft.realFft(paddedVideo);
// //   progressPort.send(0.45);
// //   final trackFFT = fft.realFft(paddedTrack);
// //   progressPort.send(0.55);

// //   // Multiply in frequency domain.
// //   for (int i = 0; i < videoFFT.length; i++) {
// //     final double real1 = videoFFT[i].x;
// //     final double imag1 = videoFFT[i].y;
// //     final double real2 = trackFFT[i].x;
// //     final double imag2 = trackFFT[i].y;
// //     trackFFT[i] = Float64x2(
// //       real1 * real2 + imag1 * imag2, // Real
// //       imag1 * real2 - real1 * imag2  // Imaginary
// //     );
// //   }
// //   progressPort.send(0.65);

// //   // Inverse FFT to compute correlation.
// //   final correlation = fft.realInverseFft(trackFFT);
// //   progressPort.send(0.75);

// //   // Find maximum correlation index.
// //   int bestIndex = 0;
// //   double maxCorrValue = double.negativeInfinity;
// //   for (int i = 0; i < correlation.length; i++) {
// //     if (correlation[i] > maxCorrValue) {
// //       maxCorrValue = correlation[i];
// //       bestIndex = i;
// //     }
// //   }
// //   progressPort.send(0.85);

// //   // Quadratic interpolation to refine the peak.
// //   double refinedIndexDouble = bestIndex.toDouble();
// //   if (bestIndex > 0 && bestIndex < correlation.length - 1) {
// //     double prevVal = correlation[bestIndex - 1];
// //     double centerVal = correlation[bestIndex];
// //     double nextVal = correlation[bestIndex + 1];
// //     double denominator = prevVal - 2 * centerVal + nextVal;
// //     if (denominator != 0) {
// //       double shift = 0.5 * (prevVal - nextVal) / denominator;
// //       refinedIndexDouble = bestIndex + shift;
// //     }
// //   }

// //   // Convert index to lag.
// //   int refinedLag;
// //   if (refinedIndexDouble < paddedLength / 2) {
// //     refinedLag = refinedIndexDouble.round();
// //   } else {
// //     refinedLag = (refinedIndexDouble - paddedLength).round();
// //   }
// //   progressPort.send(0.95);

// //   int finalOffsetMs = (refinedLag / sampleRate * 1000).round();

// //   print("""
// // ======== SYNC DEBUG ========
// //   Video Samples: $videoLength
// //   Track Samples: $trackLength
// //   Best Peak Index: $bestIndex
// //   Refined Index (fractional): $refinedIndexDouble
// //   Refined Lag (samples): $refinedLag
// //   Final Offset: $finalOffsetMs ms
// // ======== END DEBUG ========
// // """);

// //   progressPort.send(1.0);
// //   return finalOffsetMs;
// // }

// List<double> applyHannWindow(List<double> samples) {
//   final int N = samples.length;
//   List<double> windowed = List.filled(N, 0.0);
//   for (int n = 0; n < N; n++) {
//     double w = 0.5 * (1 - cos(2 * pi * n / (N - 1)));
//     windowed[n] = samples[n] * w;
//   }
//   return windowed;
// }


// Future<String> extractAudioFromVideo(String videoPath) async {
//   final tempDir = await getTemporaryDirectory();
//   final audioPath = '${tempDir.path}/video_audio.wav';

//   final command = '-i "$videoPath" -ar 44100 -y "$audioPath"';
//   await FFmpegKit.execute(command);

//   return audioPath;
// }

// Future<String> convertAudioToWav(String inputPath) async {
//   final tempDir = await getTemporaryDirectory();
//   final outputPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

//   final command = '-i "$inputPath" -ar 44100 -y "$outputPath"';
//   await FFmpegKit.execute(command);

//   return outputPath;
// }

// int _nextPowerOf2(int n) {
//   int power = 1;
//   while (power < n) {
//     power *= 2;
//   }
//   return power;
// }

// void normalize(List<double> samples) {
//   double maxVal = samples.reduce((a, b) => a.abs() > b.abs() ? a : b);
//   if (maxVal > 0) {
//     for (int i = 0; i < samples.length; i++) {
//       samples[i] /= maxVal; // Scale values between -1 and 1
//     }
//   }
// }

// Future<double> getSampleRate(String filePath) async {
//   final session = await FFmpegKit.execute('-i "$filePath" -hide_banner');
//   final logs = await session.getLogsAsString() ?? "";

//   final sampleRateRegex = RegExp(r'(\d+) Hz');
//   final match = sampleRateRegex.firstMatch(logs);

//   if (match != null) {
//     return double.parse(match.group(1)!);
//   } else {
//     print("⚠️ Could not detect sample rate. Defaulting to 44100 Hz.");
//     return 44100.0; // Fallback to 44.1kHz only if detection fails
//   }
// }


// // VIDEO AUDIO AUTOMATION CURVE
// class VideoAudioAutomationWidget extends StatefulWidget {
//   final List<AutomationPoint> automationPoints;
//   final double currentNormalizedTime; // normalized (0.0 to 1.0)
//   final ValueChanged<List<AutomationPoint>> onAutomationChanged;

//   const VideoAudioAutomationWidget({
//     Key? key,
//     required this.automationPoints,
//     required this.currentNormalizedTime,
//     required this.onAutomationChanged,
//   }) : super(key: key);

//   @override
//   _VideoAudioAutomationWidgetState createState() => _VideoAudioAutomationWidgetState();
// }

// class _VideoAudioAutomationWidgetState extends State<VideoAudioAutomationWidget> {
//   late List<AutomationPoint> _points;
//   static const double _autoSnapNorm = 0.02;   
//   @override
//   void initState() {
//     super.initState();
//     // Create a mutable copy of the automation points.
//     _points = List.from(widget.automationPoints);
//   }

//   @override
//   void didUpdateWidget(covariant VideoAudioAutomationWidget oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (widget.automationPoints != oldWidget.automationPoints) {
//       setState(() {
//         _points = List.from(widget.automationPoints);
//       });
//     }
//   }

//   void _addPoint(Offset localPosition, double width, double height) {
//     double x = (localPosition.dx / width).clamp(0.0, 1.0);
//     double volume = _interpolateVolume(x);
//     setState(() {
//       _points.add(AutomationPoint(x: x, volume: volume));
//       _points.sort((a, b) => a.x.compareTo(b.x));
//     });
//     widget.onAutomationChanged(_points);
//   }

//   double _interpolateVolume(double x) {
//     if (_points.isEmpty) return 1.0;
//     if (x <= _points.first.x) return _points.first.volume;
//     if (x >= _points.last.x) return _points.last.volume;
//     for (int i = 0; i < _points.length - 1; i++) {
//       if (x >= _points[i].x && x <= _points[i + 1].x) {
//         double t = (x - _points[i].x) / (_points[i + 1].x - _points[i].x);
//         return _points[i].volume + t * (_points[i + 1].volume - _points[i].volume);
//       }
//     }
//     return 1.0;
//   }

// Widget _buildDraggableHandle(AutomationPoint point, double width, double height) {
//   const double visibleHandleSize = 24;
//   const double hitBoxSize = 48;

//   const double edgeExtension = 16; // How much extra space to provide at the edges

//   double hitBoxLeft = point.x * width - hitBoxSize / 2;
//   double hitBoxTop = (1 - point.volume) * height - hitBoxSize / 2;

//   // Adjust positioning for the first (left edge) and last (right edge) points
//   if (point == _points.first) {
//     hitBoxLeft = -edgeExtension;
//   } else if (point == _points.last) {
//     hitBoxLeft = width - hitBoxSize + edgeExtension;
//   }

//   return Positioned(
//     left: hitBoxLeft,
//     top: hitBoxTop,
//     width: hitBoxSize,
//     height: hitBoxSize,
//     child: Listener( // Use Listener instead of RawGestureDetector
//       onPointerMove: (PointerMoveEvent event) {
//         setState(() {
//           double newVolume = point.volume - event.delta.dy / height;
//           newVolume = newVolume.clamp(0.0, 1.0);
//           point.volume = newVolume;

//           // Update horizontal position if needed
//           if (point != _points.first && point != _points.last) {
//             double newX = point.x + event.delta.dx / width;
//             int index = _points.indexOf(point);
//             double leftLimit = _points[index - 1].x + 0.01;
//             double rightLimit = _points[index + 1].x - 0.01;
//             point.x = newX.clamp(leftLimit, rightLimit);
//           }

//           // snap to seek line
//           double seekNorm = widget.currentNormalizedTime;
//           if ((point.x - seekNorm).abs() < _autoSnapNorm) {
//             point.x = seekNorm;
//           }
//         });
//         widget.onAutomationChanged(_points);
//       },
//       child: Center(
//         child: GestureDetector(
//           onLongPress: () {
//             if (point != _points.first && point != _points.last) {
//               setState(() => _points.remove(point));
//               widget.onAutomationChanged(_points);
//             }
//           },
//           child: Container(
//             width: visibleHandleSize,
//             height: visibleHandleSize,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               color: (point == _points.first || point == _points.last)
//                   ? const Color(0xFF888888)
//                   : const Color(0xFF2E61A5),
//             ),
//           ),
//         ),
//       ),
//     ),
//   );
// }


//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(builder: (context, constraints) {
//       final double width = constraints.maxWidth;
//       final double height = constraints.maxHeight;
//       return GestureDetector(
//         onLongPressStart: (details) {
//           final RenderBox box = context.findRenderObject() as RenderBox;
//           final localPos = box.globalToLocal(details.globalPosition);
//           _addPoint(localPos, width, height);
//         },
//         child: Stack(
//           children: [
//             CustomPaint( // TODO: Offset argument contained a NaN value.
//               size: Size(width, height),
//               painter: _AutomationPainter(
//                 points: _points,
//                 currentNormalizedTime: widget.currentNormalizedTime,
//               ),
//             ),
//             for (var point in _points)
//               _buildDraggableHandle(point, width, height),
//           ],
//         ),
//       );
//     });
//   }
// }
// // VIDEO AUDIO AUTOMATION CURVE END

// String generateVolumeAutomationFilter(AudioTrack track, int offsetMs, double universalCrossfade) {
//   // If no automation points, default to universal crossfade value.
//   if (track.volumeAutomation.isEmpty) return min(1.0, universalCrossfade * 2).toStringAsFixed(2);

//   List<String> conditions = [];
//   double trackOffsetSec = offsetMs / 1000.0;
//   double trackStartSec = track.trimStart.inSeconds.toDouble();
//   double trackEndSec = track.trimEnd.inSeconds.toDouble();
//   double trackDuration = trackEndSec - trackStartSec;

//   for (int i = 0; i < track.volumeAutomation.length - 1; i++) {
//     AutomationPoint startPoint = track.volumeAutomation[i];
//     AutomationPoint endPoint = track.volumeAutomation[i + 1];

//     // Adjust the time positions by the track offset.
//     double pointStart = (startPoint.x * trackDuration) + trackOffsetSec;
//     double pointEnd = (endPoint.x * trackDuration) + trackOffsetSec;
//     double volumeStart = startPoint.volume;
//     double volumeEnd = endPoint.volume;

//     // Use linear interpolation for smooth volume transition.
//     conditions.add(
//       "if(between(t,max($pointStart,0),max($pointEnd,0)),"
//       "$volumeStart+($volumeEnd-$volumeStart)*(t-$pointStart)/($pointEnd-$pointStart),"
//     );
//   }

//   // Close all nested ifs.
//   String closingBrackets = List.filled(conditions.length, ")").join("");
//   // Build the automation expression.
//   String automationExpr = "${conditions.join("")}1.0$closingBrackets";
//   // Multiply the automation by the universal crossfade factor.
//   return "'($automationExpr)*(${min(1.0, universalCrossfade * 2).toStringAsFixed(2)})'";
// }


// String generateVolumeAutomationFilterForVideo(
//     List<AutomationPoint> points, double durationSec, int offsetMs, double universalCrossfade) {
//   // If no automation points are defined, default to the crossfaded volume.
//   if (points.isEmpty) return "(${min(1.0, (1.0 - universalCrossfade) * 2)})";

//   // Choose a small epsilon (in seconds) to smooth boundaries.
//   double epsilon = 0.01;
//   List<String> conditions = [];
  
//   // For each pair of automation points, create a condition with epsilon margins.
//   for (int i = 0; i < points.length - 1; i++) {
//     AutomationPoint startPoint = points[i];
//     AutomationPoint endPoint = points[i + 1];
//     // Scale normalized positions by duration.
//     double startTime = startPoint.x * durationSec;
//     double endTime = endPoint.x * durationSec;
//     // Build a condition with an epsilon margin.
//     conditions.add(
//       "if(between(t,${(startTime - epsilon).toStringAsFixed(3)},${(endTime + epsilon).toStringAsFixed(3)}),"
//       "${startPoint.volume}+(${endPoint.volume}-${startPoint.volume})*((t-${startTime.toStringAsFixed(3)})/(${(endTime - startTime).toStringAsFixed(3)})),"
//     );
//   }
//   // Close all nested ifs.
//   String closing = ")" * (points.length - 1);
//   // Default value if none of the conditions match.
//   String automationExpr = "${conditions.join("")}1.0$closing";
  
//   // Multiply the whole expression by (1 - universalCrossfade)
//   return "'($automationExpr)*(${(min(1.0, (1.0 - universalCrossfade) * 2)).toStringAsFixed(2)})'";
// }


// // EXPORT PROGRESS SCREEN

// class ExportProgressPage extends StatefulWidget {
//   final Future<String> Function(ValueChanged<double>) exportFn;
//   final String videoFile;

//   const ExportProgressPage({required this.exportFn, required this.videoFile, super.key});

//   @override
//   State<ExportProgressPage> createState() => _ExportProgressPageState();
// }

// class _ExportProgressPageState extends State<ExportProgressPage> {
//   double _progress = 0.0;
//   Uint8List? _thumbnail;
//   bool _cancelled = false;

//   @override
//   void initState() {
//     super.initState();
//     if (widget.videoFile.isNotEmpty) {
//       _loadThumbnail();
//     }
//     _cancelSignal = Completer();
//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       await Future.delayed(const Duration(milliseconds: 400));
//       _startExport();
//     });
//   }

//   @override
//   void dispose() {
//     super.dispose();
//   }

//   Future<void> _loadThumbnail() async {
//     final thumb = await VideoThumbnail.thumbnailData(
//       video: widget.videoFile,
//       imageFormat: ImageFormat.JPEG,
//       quality: 75,
//     );
//     setState(() => _thumbnail = thumb);
//   }

//   Future<void> _startExport() async {
//     final path = await widget.exportFn((value) {
//       if (!_cancelled) setState(() => _progress = value.clamp(0.0, 1.0));
//     });
//     if (!_cancelled && mounted) Navigator.of(context).pop(path); // return path
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Cancel button
//             IconButton(
//               icon: const Icon(Icons.close, color: Colors.white),
//               onPressed: () {
//                 setState(() => _cancelled = true);
//                 _cancelSignal.complete();
//                 print("cancelling export progress");
//                 Navigator.of(context).pop("");
//               },
//             ),
//             const SizedBox(height: 24),
//             const Text("Exporting...",
//                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
//             const SizedBox(height: 8),
//             const Text("Please don’t close the app or lock your screen.",
//                 style: TextStyle(color: Colors.white70)),
//             const SizedBox(height: 24),
//             LinearProgressIndicator(
//               value: _progress,
//               minHeight: 4,
//               backgroundColor: Colors.white24,
//               valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
//             ),
//             const SizedBox(height: 24),
//             if (_thumbnail != null)
//               // Stack(
//               //   alignment: Alignment.center,
//               //   children: [
//               //     ClipRRect(
//               //       borderRadius: BorderRadius.circular(8),
//               //       child: Image.memory(_thumbnail!, height: 160),
//               //     ),
//               //     Text(
//               //       "${(_progress * 100).toStringAsFixed(0)}%",
//               //       style: const TextStyle(
//               //         color: Colors.white,
//               //         fontSize: 24,
//               //         fontWeight: FontWeight.bold,
//               //         shadows: [Shadow(blurRadius: 4, color: Colors.black)],
//               //       ),
//               //     ),
//               //   ],
//               // ),
//               SizedBox(
//                 height: 160,
//                 child: Stack(
//                   alignment: Alignment.center,
//                   children: [
//                     Center(
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(8),
//                         child: Image.memory(
//                           _thumbnail!,
//                           height: 160,
//                           fit: BoxFit.contain, // or omit fit entirely
//                         ),
//                       ),
//                     ),
//                     Text(
//                       "${(_progress * 100).toStringAsFixed(0)}%",
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 24,
//                         fontWeight: FontWeight.bold,
//                         shadows: [Shadow(blurRadius: 4, color: Colors.black)],
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                   ],
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // EXPORT PROGRESS SCREEN END

// // EXPORT SUCCESS SCREEN

// class ExportSuccessScreen extends StatelessWidget {
//   final String filePath;
//   final bool isVideo;

//   const ExportSuccessScreen({
//     super.key,
//     required this.filePath,
//     required this.isVideo,
//   });

//   Future<void> _shareFile(BuildContext context) async {
//     try {
//       await Share.shareXFiles([XFile(filePath)]); // doesn't work on android (only iOS)
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Failed to share.')),// ${e.toString()}')),
//       );
//     }
//   }

//   Future<void> _openSocialMedia(String deepLink, String fallbackUrl) async {
//     try {
//       if (await canLaunchUrl(Uri.parse(deepLink))) {
//         await launchUrl(Uri.parse(deepLink));
//       } else {
//         await launchUrl(Uri.parse(fallbackUrl));
//       }
//     } catch (e) {
//       debugPrint('Error launching social media.');// $e');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Scaffold(
//       appBar: AppBar(title: Text(L10n.translate(context, 'Export Successful'))),
//       body: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(
//               Icons.check_circle,
//               color: Colors.green,
//               size: 100,
//             ),
//             const SizedBox(height: 20),
//             // Text(
//             //   'Your ${isVideo ? 'video' : 'audio'} was exported successfully!',
//             //   style: Theme.of(context).textTheme.headlineSmall,
//             //   textAlign: TextAlign.center,
//             // ),
//             isVideo ? Text(L10n.translate(context, 'Your video was exported successfully!'),style: Theme.of(context).textTheme.headlineSmall,
//               textAlign: TextAlign.center,) : Text(L10n.translate(context, 'Your audio was exported successfully!'),style: Theme.of(context).textTheme.headlineSmall,
//               textAlign: TextAlign.center,),
//             const SizedBox(height: 40),
//             // ElevatedButton(
//             //   onPressed: () => _shareFile(context),
//             //   child: const Text('Share File'),
//             // ),
//             // const SizedBox(height: 20),
//             Text(L10n.translate(context, 'Share directly to:')),
//             const SizedBox(height: 20),
//             Wrap(
//               spacing: 10,
//               runSpacing: 10,
//               children: [
//                 _SocialButton(
//                   icon: Icons.play_arrow,
//                   label: '${L10n.translate(context, 'YouTube')}',
//                   onTap: () => _openSocialMedia(
//                     'vnd.youtube://upload',
//                     'https://www.youtube.com/upload',
//                   ),
//                 ),
//                 _SocialButton(
//                   icon: Icons.camera_alt,
//                   label: '${L10n.translate(context, 'Instagram')}',
//                   onTap: () => _openSocialMedia(
//                     'instagram://library',
//                     'https://www.instagram.com/',
//                   ),
//                 ),
//                 _SocialButton(
//                   icon: Icons.music_note,
//                   label: '${L10n.translate(context, 'TikTok')}',
//                   onTap: () => _openSocialMedia(
//                     'snssdk1233://upload',
//                     'https://www.tiktok.com/upload',
//                   ),
//                 ),
//                 if (!isVideo) // Audio-specific platforms
//                   _SocialButton(
//                     icon: Icons.headset,
//                     label: '${L10n.translate(context, 'SoundCloud')}',
//                     onTap: () => _openSocialMedia(
//                       'soundcloud://upload',
//                       'https://soundcloud.com/upload',
//                     ),
//                   ),
//               ],
//             ),
//             const SizedBox(height: 40),
//             OutlinedButton(
//               onPressed: () => Navigator.popUntil(
//                   context, (route) => route.isFirst),
//               child: Text(L10n.translate(context, 'Back to Editor')),
//             ),
//           ],
//         ),
//       ),
//     );
//         }
//     );
//   }
// }

// class _SocialButton extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final VoidCallback onTap;

//   const _SocialButton({
//     required this.icon,
//     required this.label,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return ElevatedButton.icon(
//       style: ElevatedButton.styleFrom(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       ),
//       onPressed: onTap,
//       icon: Icon(icon),
//       label: Text(label),
//     );
//   }
// }

// // EXPORT SUCCESS SCREEN END



// // EFFECTS DRAWER START

// class EffectsDrawer extends StatefulWidget {
//   final int trackIndex;
//   const EffectsDrawer({Key? key, required this.trackIndex}) : super(key: key);

//   @override
//   _EffectsDrawerState createState() => _EffectsDrawerState();
// }

// class _EffectsDrawerState extends State<EffectsDrawer> {
//   List<String> _effects = [];
//   List<bool> _bypassed = [];
//   bool _loading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadEffects();
//   }

//   Future<void> _loadEffects() async {
//     final names =
//         await JuceAudioEngine.getTrackEffects(widget.trackIndex);
//     final bypassStates = await Future.wait(
//       List.generate(names.length, (index) async {
//         return await JuceAudioEngine.getPluginBypassState(widget.trackIndex, index);
//       })
//     );
//     setState(() {
//       _effects = List<String>.from(names);
//       _bypassed = List<bool>.from(bypassStates);
//       _loading = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final accent = theme.primaryColor;

//     if (_loading) {
//       return SizedBox(
//         height: 200,
//         child: Center(child: CircularProgressIndicator(color: accent)),
//       );
//     }

//     return DraggableScrollableSheet(
//       expand: false,
//       initialChildSize: 0.6,
//       minChildSize: 0.3,
//       maxChildSize: 0.9,
//       builder: (_, ctrl) => Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//                 Center(
//                   key: const ValueKey('handle'),
//                   child: Container(
//                     width: 40,
//                     height: 4,
//                     decoration: BoxDecoration(
//                       color: Colors.grey[300],
//                       borderRadius: BorderRadius.circular(2),
//                     ),
//                   ),
//                 ),

//                 const SizedBox(key: ValueKey('spacer1'), height: 12),

//                 // — presets header —
//                 Text("Presets",
//                     key: const ValueKey('presetsTitle'),
//                     style: theme.textTheme.titleMedium),
//                 const SizedBox(key: ValueKey('spacer2'), height: 8),
//                 Wrap(
//                   key: const ValueKey('presetsWrap'),
//                   spacing: 8,
//                   children: [
//                     _buildPresetChip("ASMR Chain"),
//                     _buildPresetChip("Jazz Chain"),
//                     _buildPresetChip("LoFi Chain"),
//                     _buildPresetChip("Guitar Chain"),
//                   ],
//                 ),

//                 const Divider(key: ValueKey('divider'), height: 24),

//                 Flexible(
//                   fit: FlexFit.loose,
//                   child: ReorderableListView(
//                     scrollController: ctrl,
//                     // buildDefaultDragHandles: false,
//                     shrinkWrap: true,
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     padding: EdgeInsets.zero,

//                     children: [
//                       for (int i = 0; i < _effects.length; i++)
//                         _buildEffectTile(i),
//                     ],

//                     proxyDecorator: (child, index, animation) => Material(
//                       elevation: 6,
//                       color: const Color.fromARGB(154, 182, 182, 182),
//                       child: child,
//                     ),

//                     onReorder: (oldIndex, newIndex) async {
//                       if (oldIndex < 0 || oldIndex >= _effects.length) return;
//                       if (newIndex > oldIndex) newIndex--;
//                       newIndex = newIndex.clamp(0, _effects.length - 1);

//                       await JuceAudioEngine.reorderEffects(
//                         widget.trackIndex, oldIndex, newIndex);
//                       setState(() {
//                         final name   = _effects.removeAt(oldIndex);
//                         final bypass = _bypassed.removeAt(oldIndex);
//                         _effects.insert(newIndex, name);
//                         _bypassed.insert(newIndex, bypass);
//                       });
//                     },
//                   ),
//                 ),
//                 if (_effects.length < 5) 
//                   Padding(
//                     padding: const EdgeInsets.only(top: 0),
//                     child: _buildAddTile(),
//                   ),
//           ],
//         ),
//       ),
//     );
//   }

//   ActionChip _buildPresetChip(String name) => ActionChip(
//         backgroundColor: const Color.fromARGB(255, 87, 92, 148),
//         label: Text(name),
//         onPressed: () {
//           Navigator.of(context).pop();
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: Text("Preset “$name” applied (placeholder)")),
//           );
//         },
//       );

//   Widget _buildEffectTile(int idx) {
//     return ReorderableDragStartListener(
//       key: ValueKey("effect_$idx"),
//       index: idx,
//       child: ListTile(
//         contentPadding: EdgeInsets.all(0),
//         key: ValueKey("effect_$idx"),
//         leading: const Icon(Icons.drag_handle),
//         title: Text(_effects[idx]),
//         trailing: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Bypass toggle
//             Switch(
//               value: !_bypassed[idx],
//               onChanged: (active) {
//                 final shouldBypass = !active;
//                 JuceAudioEngine.bypassPlugin(
//                   widget.trackIndex,
//                   idx,
//                   shouldBypass,
//                 );
//                 setState(() => _bypassed[idx] = shouldBypass);
//               },
//             ),
//             // Delete button
//             IconButton(
//               icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
//               onPressed: () => _confirmRemove(idx),
//             ),
//           ],
//         ),
//         onTap: () => _openPluginParams(idx),
//       )
//     );
//     // return ListTile(
//     //   contentPadding: EdgeInsets.all(0),
//     //   key: ValueKey("effect_$idx"),
//     //   leading: const Icon(Icons.drag_handle),
//     //   title: Text(_effects[idx]),
//     //   trailing: Row(
//     //     mainAxisSize: MainAxisSize.min,
//     //     children: [
//     //       // Bypass toggle
//     //       Switch(
//     //         value: !_bypassed[idx],
//     //         onChanged: (active) {
//     //           final shouldBypass = !active;
//     //           JuceAudioEngine.bypassPlugin(
//     //             widget.trackIndex,
//     //             idx,
//     //             shouldBypass,
//     //           );
//     //           setState(() => _bypassed[idx] = shouldBypass);
//     //         },
//     //       ),
//     //       // Delete button
//     //       IconButton(
//     //         icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
//     //         onPressed: () => _confirmRemove(idx),
//     //       ),
//     //     ],
//     //   ),
//     //   onTap: () => _openPluginParams(idx),
//     // );
//   }

//   Widget _buildAddTile() => ListTile(
//         contentPadding: EdgeInsets.all(0),
//         key: const ValueKey("add_effect"),
//         leading: const Icon(Icons.add_circle_outline),
//         title: const Text("Add Effect"),
//         onTap: _showAddEffectModal,
//       );

//   Future<void> _confirmRemove(int idx) async {
//     final yes = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         title: const Text("Delete Effect?"),
//         actions: [
//           TextButton(
//               onPressed: () => Navigator.pop(context, false),
//               child: const Text("Cancel")),
//           TextButton(
//             onPressed: () => Navigator.pop(context, true),
//             child:
//                 const Text("Delete", style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//     if (yes == true) {
//       await JuceAudioEngine.removeEffect(widget.trackIndex, idx);
//       setState(() {
//         _effects.removeAt(idx);
//         _bypassed.removeAt(idx);
//       });
//     }
//   }

//   // Inside your EffectsDrawer:
//   Future<void> _showAddEffectModal() async {
//     final plugins = await JuceAudioEngine.scanPlugins();
//     showDialog(
//       context: context,
//       builder: (_) => AlertDialog(
//         title: Text("Add Effect"),
//         content: SizedBox(
//           width: double.maxFinite,
//           height: 300,
//           child: ListView(
//             children: plugins.map((meta) {
//               final name = meta['name'] ?? meta['id'] ?? '';
//               final path = meta['id'] ?? '';
//               return ListTile(
//                 title: Text(name),
//                 onTap: () async {
//                   Navigator.pop(context); // close dialog
//                   await JuceAudioEngine.insertEffect(widget.trackIndex, path);
//                   await _loadEffects();
//                 },
//               );
//             }).toList(),
//           ),
//         ),
//       ),
//     );
//   }


//   Future<void> _openPluginParams(int idx) async {
//     final params = await JuceAudioEngine.getPluginParameters(
//       widget.trackIndex,
//       idx,
//     );

//     showModalBottomSheet(
//       context: context,
//       constraints: BoxConstraints(
//         maxHeight: MediaQuery.of(context).size.height * 0.8, // Max 70% height
//         // minHeight: MediaQuery.of(context).size.height * 0.4, // Min 40% height
//       ),
//       isScrollControlled: true,
//       backgroundColor: const Color.fromARGB(255, 35, 32, 78),
//       shape: const RoundedRectangleBorder(
//           borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
//       builder: (ctx) {
//         return StatefulBuilder(
//           builder: (ctx, setModalState) {
//             return Padding(
//               padding: EdgeInsets.only(
//                   bottom: MediaQuery.of(ctx).viewInsets.bottom),
//               child: SingleChildScrollView(
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
//                     child: Column(
//                       // crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const SizedBox(height: 8),
//                         Container(
//                           width: 40,
//                           height: 4,
//                           decoration: BoxDecoration(
//                             color: Colors.grey[300],
//                             borderRadius: BorderRadius.circular(2),
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         Text("Parameters",
//                             style: Theme.of(context).textTheme.titleLarge),
//                         const SizedBox(height: 8),

//                         // Parameter controls
//                         for (var param in params) ...[
//                           if (param['type'] == 'float') ...[
//                             Padding(
//                               padding: const EdgeInsets.symmetric(vertical: 8),
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     param['name'] as String,
//                                     style: Theme.of(context).textTheme.bodyLarge,
//                                   ),
//                                   const SizedBox(height: 4),
//                                   Row(
//                                     children: [
//                                       // 1) min label
//                                       Text(
//                                         (param['min'] as num).toDouble().toStringAsFixed(2),
//                                         style: Theme.of(context).textTheme.bodySmall,
//                                       ),
//                                       const SizedBox(width: 8),

//                                       // 2) the slider with value indicator
//                                       Expanded(
//                                         child: SliderTheme(
//                                           data: SliderTheme.of(context).copyWith(
//                                             showValueIndicator: ShowValueIndicator.always,
//                                             valueIndicatorTextStyle: TextStyle(
//                                               color: const Color.fromARGB(255, 0, 0, 0),
//                                               fontSize: 12,
//                                             ),
//                                           ),
//                                           child: Slider(
//                                             value: (param['value'] as num)
//                                                 .toDouble()
//                                                 .clamp(
//                                                   (param['min'] as num).toDouble(),
//                                                   (param['max'] as num).toDouble(),
//                                                 ),
//                                             min: (param['min'] as num).toDouble(),
//                                             max: (param['max'] as num).toDouble(),
//                                             divisions: 100, // or compute a sensible number
//                                             label: (param['value'] as num)
//                                                 .toDouble()
//                                                 .toStringAsFixed(2),
//                                             onChanged: (v) => {
//                                               setModalState(() => param['value'] = v),
//                                               JuceAudioEngine.setEffect(
//                                                 widget.trackIndex,
//                                                 idx,
//                                                 param['name'] as String,
//                                                 v,
//                                               )
//                                             },
//                                             onChangeEnd: (v) => {}, // originally put JuceAudioEngine.setEffect here
//                                           ),
//                                         ),
//                                       ),
//                                       const SizedBox(width: 8),

//                                       // 3) max label
//                                       Text(
//                                         (param['max'] as num).toDouble().toStringAsFixed(2),
//                                         style: Theme.of(context).textTheme.bodySmall,
//                                       ),
//                                     ],
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ] else if (param['type'] == 'bool') ...[
//                             SwitchListTile(
//                               title: Text(param['name'] as String),
//                               value: param['value'] as bool,
//                               onChanged: (v) => setModalState(() {
//                                 param['value'] = v;
//                                 JuceAudioEngine.setEffect(
//                                   widget.trackIndex,
//                                   idx,
//                                   param['name'] as String,
//                                   v,
//                                 );
//                               }),
//                             ),
//                           ] else if (param['type'] == 'choice') ...[
//                               (() {
//                                 final keys = param.keys
//                                     .where((k) => k.startsWith('choice_'))
//                                     .toList()
//                                   ..sort((a, b) {
//                                     final ai = int.parse(a.split('_')[1]);
//                                     final bi = int.parse(b.split('_')[1]);
//                                     return ai.compareTo(bi);
//                                   });
//                                 // 2) build the labels
//                                 final choices = keys.map((k) => param[k] as String).toList();
//                                 // 3) current
//                                 final current = param['value'] as String;
//                                 // 4) render a ListTile that pops a dialog
//                                 return Padding(
//                                   padding: const EdgeInsets.symmetric(vertical: 8.0),
//                                   child: ListTile(
//                                     contentPadding: EdgeInsets.zero,
//                                     title: Text(param['name'] as String),
//                                     trailing: Text(current, style: Theme.of(context).textTheme.bodyLarge),
//                                     onTap: () async {
//                                       final picked = await showDialog<String>(
//                                         context: context,
//                                         useRootNavigator: true,
//                                         builder: (ctx) => SimpleDialog(
//                                           title: Text("Select ${param['name']}"),
//                                           children: choices.map((c) {
//                                             return SimpleDialogOption(
//                                               child: Text(c),
//                                               onPressed: () => Navigator.pop(ctx, c),
//                                             );
//                                           }).toList(),
//                                         ),
//                                       );
//                                       if (picked != null) {
//                                         setModalState(() => param['value'] = picked);
//                                         JuceAudioEngine.setEffect(
//                                           widget.trackIndex,
//                                           idx,
//                                           param['name'] as String,
//                                           picked,
//                                         );
//                                       }
//                                     },
//                                   ),
//                                 );
//                               })(),
//                           ] else ...[
//                             ListTile(
//                               title: Text(param['name'] as String),
//                               trailing: Text("${param['value']}"),
//                             ),
//                           ]
//                         ],

//                         const SizedBox(height: 16),
//                         TextButton(
//                           child: Text("Close", style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                                   fontWeight: FontWeight.w500,
//                           )),
//                           onPressed: () => Navigator.pop(ctx),
//                         ),
//                         const SizedBox(height: 16),
//                       ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }

// // EFFECTS DRAWER END