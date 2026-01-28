// import 'dart:async';
// import 'dart:io';
// import 'dart:isolate';
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

// // START OF EFFECTS SCREEN

// class EffectsEditorScreen extends StatefulWidget {
//   final String originalPath;
//   final bool isVideo;
//   final List<AudioTrack> audioTracks;
//   final String originalFilterChain;
//   final double universalCrossfade;
//   final List<AutomationPoint> videoAudioAutomation;
//   final String videoFilePath;

//   const EffectsEditorScreen({
//     super.key,
//     required this.originalPath,
//     required this.isVideo,
//     required this.audioTracks,
//     required this.originalFilterChain,
//     required this.universalCrossfade,
//     required this.videoAudioAutomation,
//     required this.videoFilePath,
//   });

//   @override
//   State<EffectsEditorScreen> createState() => _EffectsEditorScreenState();
// }

// class _EffectsEditorScreenState extends State<EffectsEditorScreen> with WidgetsBindingObserver {
//   late VideoPlayerController _videoController;
//   late AudioPlayer _audioPlayer;
//   String _currentFilePath = '';
//   bool _isProcessing = false;
//   bool _isPlayerInitialized = false;
//   bool isLoading = false;
//   bool _isPlaying = false;

//   ValueNotifier<Duration> _currentPosition = ValueNotifier(Duration.zero);
//   ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);


//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _currentFilePath = widget.originalPath;
//     _initPlayer();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (defaultTargetPlatform == TargetPlatform.android) {
//       if (state == AppLifecycleState.resumed) {
//         debugPrint("App Resumed on Android - Re-initializing video.");
//         _initPlayer();
//       } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
//         debugPrint("App Paused or Inactive on Android - Disposing video.");
//         // _videoController?.pause(); // Optionally pause on leaving
//         // _videoController?.dispose();
//         // _videoController = null; // Set to null to ensure re-initialization
//       }
//     }
//   }

//   Future<void> _initPlayer() async {
//     if (widget.isVideo) {
//       _videoController = VideoPlayerController.file(File(_currentFilePath))
//         ..addListener(_updateVideoPosition);
//       await _videoController.initialize();
//       _duration.value = _videoController.value.duration;
//     } else {
//       _audioPlayer = AudioPlayer()
//         ..onPositionChanged.listen((p) => _currentPosition.value = p)
//         ..onDurationChanged.listen((d) => _duration.value = d);
//       await _audioPlayer.setSourceDeviceFile(_currentFilePath);

//       _audioPlayer.onPlayerComplete.listen((_) {
//         setState(() {
//           _isPlaying = true;
//           _currentPosition.value = Duration.zero;
//           _audioPlayer.seek(Duration.zero);
//         });
//       });
//     }
//     setState(() => _isPlayerInitialized = true);
//   }

//   void _updateVideoPosition() {
//     _currentPosition.value = _videoController.value.position;
//   }


//   Future<String> copyIrFileToTemp() async {
//     final tempDir = await getTemporaryDirectory();
//     final irFile = File('${tempDir.path}/reverb_ir2.wav');
//     if (!await irFile.exists()) {
//       try {
//         final byteData = await DefaultAssetBundle.of(context).load(
//             'assets/impulse/large-dark-plate-trim.wav');
//         await irFile.writeAsBytes(byteData.buffer.asUint8List());
//         await logToFile("IR file copied to: ${irFile.path}", 'ffmpeg_log.txt');
//       } catch (e) {
//         await logToFile("Failed to copy IR file: $e", 'ffmpeg_log.txt');
//         throw Exception("Failed to copy IR file: $e");
//       }
//     }
//     return irFile.path;
//   }

// Future<void> logToFile(String message, String fileName) async {
//   final directory = await getTemporaryDirectory();
//   final file = File('${directory.path}/$fileName');
//   await file.writeAsString('$message\n', mode: FileMode.append);
//   print("Log written to: ${file.path}");
// }

// // START OF CHANGES NOW
// Future<String> getFilterChain() async {
//   if(widget.isVideo) {
//     final List<String> inputArgs = ['-i "${widget.videoFilePath}"'];
//   for (final track in widget.audioTracks) {
//     inputArgs.add('-i "${track.file.path}"');
//   }

//   // Add IR file if reverb is enabled
//   bool hasReverb = widget.audioTracks.any((track) => track.reverb > 0);
//   String? irInputLabel;
//   if (hasReverb) {
//     final irFilePath = await copyIrFileToTemp();
//     inputArgs.add('-i "$irFilePath"');
//     irInputLabel = '[${inputArgs.length - 1}:a]'; // index of IR file in full ffmpeg cmd
//     await logToFile("IR input added: $irFilePath, label: $irInputLabel", 'ffmpeg_log.txt');
//   }

//   // Get video duration
//   double videoDurationSec = _videoController!.value.duration.inSeconds.toDouble();

//   // Generate video audio automation filter
//   final String videoAudioFilter = generateVolumeAutomationFilterForVideo(
//       widget.videoAudioAutomation, videoDurationSec, 0, widget.universalCrossfade);

//   // Build filter complex lines
//   final List<String> filterLines = [
//     // Video audio
//     '[0:a]atrim=start=0,asetpts=PTS-STARTPTS,volume=eval=frame:volume=$videoAudioFilter[vid];'
//   ];

//   final List<String> trackLabels = [];
//   for (int i = 0; i < widget.audioTracks.length; i++) {
//     final track = widget.audioTracks[i];
//     final int offsetMs = (track.offset * 1000).round();
//     final double startSec = track.trimStart.inMilliseconds / 1000.0;
//     final double endSec = track.trimEnd.inMilliseconds / 1000.0;
//     String currentAudioLabel = 'proc_audio${i}_prefx';
//     final String finalTrackLabel = 't${i + 1}';

//     final String volumeAutomation = generateVolumeAutomationFilter(
//         track, offsetMs, widget.universalCrossfade);

//     // Initial processing (trim, delay, volume)
//     String trackFilters =
//         '[${i + 1}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
//         'adelay=$offsetMs|$offsetMs,asetpts=PTS-STARTPTS,'
//         'volume=eval=frame:volume=($volumeAutomation)*(1.0)[$currentAudioLabel];';

//     if (track.reverb > 0 && irInputLabel != null) {
//       // First split the original audio
//       trackFilters += '[$currentAudioLabel]asplit=2[split${i}_dry][split${i}_wet];';
      
//       // Process dry signal
//       trackFilters += '[split${i}_dry]volume=${1.0 - track.reverb}[dry_adjusted${i}];';
      
//       // Process wet signal with reverb
//       trackFilters += '[split${i}_wet]${irInputLabel}'
//           'afir=wet=${track.reverb},'
//           'dynaudnorm=f=150:g=17,'
//           'volume=5'
//           '[wet_adjusted${i}];';

//       String dryLabel = '[dry_adjusted${i}]';
//       String wetLabel = '[wet_adjusted${i}]';

//       if (track.echo > 0) {
//         trackFilters += '${dryLabel}aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[dry_echoed${i}];';
//         dryLabel = '[dry_echoed${i}]';
//         trackFilters += '${wetLabel}aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[wet_echoed${i}];';
//         wetLabel = '[wet_echoed${i}]';
//       }

//       trackLabels.add(dryLabel);
//       trackLabels.add(wetLabel);
//     } else {
//       if (track.echo > 0) {
//         trackFilters += '[$currentAudioLabel]aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[$finalTrackLabel];';
//         trackLabels.add('[$finalTrackLabel]');
//       } else {
//         trackLabels.add('[$currentAudioLabel]');
//       }
//     }

//     filterLines.add(trackFilters);
//   }

//   // Mix all audio streams
//   final String amixInputs =
//       '[vid]${trackLabels.join('')}amix=inputs=${1 + trackLabels.length}:duration=first:normalize=0[aout]';
//   filterLines.add(amixInputs);

//   // Log for debugging
//   await logToFile("FFmpeg Input Args:\n${inputArgs.join('\n')}", 'ffmpeg_log.txt');
//   await logToFile("FFmpeg Filter Complex:\n${filterLines.join('\n')}", 'ffmpeg_log.txt');
//   await logToFile(
//       "FFmpeg Output Options:\n-map \"[aout]\" -map 0:v -c:v copy -c:a aac -b:a 192k outputFilePath",
//       'ffmpeg_log.txt');

//   print("🔹 FFmpeg Input Args:");
//   for (var arg in inputArgs) {
//     print("  $arg");
//   }
//   print("🔹 FFmpeg Filter Complex:");
//   for (var line in filterLines) {
//     print("  $line");
//   }
//   print("🔹 FFmpeg Output Options:");
//   print("  -map \"[aout]\" -map 0:v -c:v copy -c:a aac -b:a 192k outputFilePath");

//   // Construct full command
//   final fullCommand =
//       '${inputArgs.join(' ')} -filter_complex "${filterLines.join('')}" '
//       '-map "[aout]" -map 0:v -c:v copy -c:a aac -b:a 192k outputFilePath';

//   await logToFile("Full FFmpeg Command:\n$fullCommand", 'ffmpeg_log.txt');

//     return filterLines.join('');
//   }
//   else {
//     // Build input arguments
//     List<String> inputArgs = [];
//     for (final track in widget.audioTracks) {
//       inputArgs.add('-i "${track.file.path}"');
//     }

//     String irInputLabel = '[${inputArgs.length}:a]'; // index of IR file in full ffmpeg cmd

//     // Build filter complex
//     List<String> filterLines = [];
//     List<String> trackLabels = [];

//     for (int i = 0; i < widget.audioTracks.length; i++) {
//       final track = widget.audioTracks[i];
//       final offsetMs = (track.offset * 1000).round();
//       final startSec = track.trimStart.inMilliseconds / 1000.0;
//       final endSec = track.trimEnd.inMilliseconds / 1000.0;
//       final String label = 'a${i}';
      
//       String currentAudioLabel = 'proc_audio${i}_prefx';
//       final String finalTrackLabel = 't${i + 1}';

//       String volumeFilter;
//       if (track.volumeAutomation.isNotEmpty) {
//         final String volumeAutomationExpression = generateVolumeAutomationFilter(
//           track,
//           offsetMs,
//           widget.universalCrossfade,
//         );
//         volumeFilter = 'volume=eval=frame:volume="${volumeAutomationExpression}"';//*${track.gain}"';
//       } else {
//         volumeFilter = 'volume=${min(1.0, widget.universalCrossfade * 2).toStringAsFixed(2)}';//*${track.gain}';
//       }

//       String currentTrackFilters = 
//         '[${i}:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS,'
//         'adelay=${offsetMs}|${offsetMs},asetpts=PTS-STARTPTS,'
//         '${volumeFilter}[$currentAudioLabel];'
//       ;

//       if (track.reverb > 0 && irInputLabel != null) {
//         // First split the original audio
//         currentTrackFilters += '[$currentAudioLabel]asplit=2[split${i}_dry][split${i}_wet];';
        
//         // Process dry signal
//         currentTrackFilters += '[split${i}_dry]volume=${1.0 - track.reverb}[dry_adjusted${i}];';
        
//         // Process wet signal with reverb
//         currentTrackFilters += '[split${i}_wet]${irInputLabel}'
//             'afir=wet=${track.reverb},'
//             'dynaudnorm=f=150:g=17,'
//             'volume=5'
//             '[wet_adjusted${i}];';

//         String dryLabel = '[dry_adjusted${i}]';
//         String wetLabel = '[wet_adjusted${i}]';

//         if (track.echo > 0) {
//           currentTrackFilters += '${dryLabel}aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[dry_echoed${i}];';
//           dryLabel = '[dry_echoed${i}]';
//           currentTrackFilters += '${wetLabel}aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[wet_echoed${i}];';
//           wetLabel = '[wet_echoed${i}]';
//         }

//         trackLabels.add(dryLabel);
//         trackLabels.add(wetLabel);
//       } else {
//         if (track.echo > 0) {
//           currentTrackFilters += '[$currentAudioLabel]aecho=0.8:0.9:${track.echo}|${track.echo * 2.0}:0.9|0.45[$finalTrackLabel];';
//           trackLabels.add('[$finalTrackLabel]');
//         } else {
//           trackLabels.add('[$currentAudioLabel]');
//         }
//       }

//       filterLines.add(currentTrackFilters);
//     }

//     // Mix all tracks (matches video export's amix approach)
//     final String amixInputs = trackLabels.join('') +
//         'amix=inputs=${trackLabels.length}:duration=longest:normalize=0[aout]';
//     filterLines.add(amixInputs);

//     return filterLines.join('');
  
//   }
// }

//   Future<void> _updateEffects() async {
//   if (_isProcessing) return;
//   _isProcessing = true;
//   setState(() {});

//   final tempDir = await getTemporaryDirectory();
//   final newPath = '${tempDir.path}/editedfx_${DateTime.now().millisecondsSinceEpoch}.${widget.isVideo ? 'mp4' : 'mp3'}';

//   String filterComplex = await getFilterChain();

//   List<String> cmd = [];
  
//   if(widget.isVideo) {
//     final List<String> inputArgs = ['-i "${widget.videoFilePath}"'];
//     for (final track in widget.audioTracks) {
//       inputArgs.add('-i "${track.file.path}"');
//     }

//     bool hasReverb = widget.audioTracks.any((track) => track.reverb > 0);
//     if (hasReverb) {
//       final irFilePath = await copyIrFileToTemp();
//       inputArgs.add('-i "$irFilePath"');
//     }


//     cmd = [
//     ...inputArgs,
//     '-filter_complex', '"$filterComplex"',
//     '-map', '0:v:0',         // Map only the primary video stream
//     '-map', '"[aout]"',        // Map the mixed audio output
//     '-c:v', 'copy',          // Copy video (no re-encoding)
//     '-c:a', 'aac',           // Force AAC for audio
//     '-b:a', '128k',          // Set audio bitrate
//     '-ar', '48000',          // Set sample rate to 48000 Hz
//     '-movflags', '+faststart',
//     '-f', 'mp4',
//     '-loglevel', 'verbose',
//     '-y', newPath
//   ];
//   }
//   else {
//     List<String> inputArgs = [];
//     for (final track in widget.audioTracks) {
//       inputArgs.add('-i "${track.file.path}"');
//     }
//     bool hasReverb = widget.audioTracks.any((track) => track.reverb > 0);
//     if (hasReverb) {
//       final irFilePath = await copyIrFileToTemp();
//       inputArgs.add('-i "$irFilePath"');
//     }
//     cmd = [
//       ...inputArgs,
//       '-filter_complex', filterComplex,
//       '-map', '"[aout]"',
//       '-c:a', 'libmp3lame',
//       '-b:a', '192k',
//       '-ar', '44100',
//       '-loglevel', 'verbose',
//       '-y', newPath
//     ];
//   }


//   print('hey FFmpeg command: ${cmd.join(' ')}');
//   await logToFile("Full FFmpeg Command2:\n${cmd.join(' ')}", 'ffmpeg_log.txt');


//   // await FFmpegKit.execute(cmd.join(' '));

//    try {
//     final session = await FFmpegKit.execute(cmd.join(' '));
//     final returnCode = await session.getReturnCode();

//     if (ReturnCode.isSuccess(returnCode)) {
//       print("FFmpeg processing successful. Output at: $newPath");
//       final logs = await session.getAllLogsAsString();
//       print("FFmpeg logs on success:\n$logs"); // Print logs on success
//       if (!widget.isVideo) {
//         try {
//           await _audioPlayer.stop();
//           await _audioPlayer.setSourceDeviceFile(newPath);
//           await _audioPlayer.seek(_currentPosition.value);
//           await _audioPlayer.pause();
//           print("Audio player source set successfully.");
//         } catch (e) {
//           debugPrint('Audio player setSource error: $e');
//         }
//       }
//     } else {
//       final logs = await session.getAllLogsAsString();
//       debugPrint('FFmpeg processing failed with code $returnCode:\n$logs');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('FFmpeg processing failed. See debug console.')),
//       );
//     }
//   } catch (e) {
//     debugPrint('FFmpeg execution error: $e');
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('FFmpeg execution error.')),
//     );
//   } finally {
//     _isProcessing = false;
//     setState(() {});
//   }

//   // Update player
//   if (widget.isVideo) {
//     await _videoController.dispose();
//     _videoController = VideoPlayerController.file(File(newPath))
//       ..addListener(_updateVideoPosition);
//     await _videoController.initialize();
//     await _videoController.seekTo(_videoController.value.position);
//     await _videoController.pause();
//   } else {
//     try {
//       await _audioPlayer.stop();
//       await _audioPlayer.setSourceDeviceFile(newPath);
//       await _audioPlayer.seek(_currentPosition as Duration); // Restore previous position
//       await _audioPlayer.pause();
//     } catch (e) {
//       debugPrint('Player update error: $e');
//       // Add retry logic or fallback here
//     }
//   }

//   // Cleanup old file
//   if (_currentFilePath != widget.originalPath) {
//     try { File(_currentFilePath).delete(); } catch (e) { /* ignore */ }
//   }

//   _currentFilePath = newPath;
//   _isProcessing = false;
//   setState(() {});
// }

//   @override
//   Widget build(BuildContext context) {
//     return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Scaffold(
//       appBar: AppBar(
//         title: Text(L10n.translate(context, 'Audio Effects')),
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back),
//           onPressed: () => Navigator.pop(context),
//         ),
//       ),
//       body: 
//       Stack(
//         children: [
//           Column(
//               children: [
//               // Preview
//               if (_isPlayerInitialized) ...[
//                 if (widget.isVideo)
//                   AspectRatio(
//                     aspectRatio: _videoController.value.aspectRatio,
//                     child: VideoPlayer(_videoController),
//                   )
//                 else
//                   const Icon(Icons.audiotrack, size: 100),

//                 _buildPlaybackControls(),
//               ],

//               // Track effects
//               Expanded(
//                 child: ListView.builder(
//                   itemCount: widget.audioTracks.length,
//                   itemBuilder: (context, index) => _buildTrackControls(index),
//                 ),
//               ),

//               // Export button
//               Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     // Back Button
//                     ElevatedButton(
//                       onPressed: () => Navigator.pop(context),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.grey[300],
//                         foregroundColor: Colors.black,
//                       ),
//                       child: Text(L10n.translate(context, 'Back')),
//                     ),

//                     // Export Button
//                     ElevatedButton(
//                       onPressed: _isProcessing ? null : _saveFinalExport,
//                       child: Text(L10n.translate(context, 'Export')),
//                     ),
//                   ],
//                 ),
//               ),
              
//             ],
//             ),
//             if(_isProcessing)
//             Positioned.fill(
//               child: Container(
//                 color: Colors.black.withOpacity(0.5),
//                 child: const Center(
//                   child: CircularProgressIndicator(),
//                 ),
//               ),
//             ),
//         ]
//       ),
//     );
//         }
//     );
//   }

// Widget _buildPlaybackControls() {
//   return Row(
//     mainAxisAlignment: MainAxisAlignment.center,
//     children: [
//       IconButton(
//         icon: Icon(
//           _isPlaying ? Icons.pause : Icons.play_arrow,
//           size: 32,
//         ),
//         onPressed: () async {
//           if (widget.isVideo) {
//             if (_isPlaying) {
//               await _videoController.pause();
//             } else {
//               await _videoController.play();
//             }
//           } else {
//             if (_isPlaying) {
//               await _audioPlayer.pause();
//             } else {
//               // Check if we're at the end and need to restart
//               if (_currentPosition.value >= _duration.value) {
//                 await _audioPlayer.seek(Duration.zero);
//               }
//               await _audioPlayer.setSourceDeviceFile(_currentFilePath);
//               await _audioPlayer.play(_audioPlayer.source!);
//             }
//           }
//           setState(() {
//             _isPlaying = !_isPlaying;
//           });
//         },
//       ),
//       // Restart button
//       IconButton(
//         icon: const Icon(Icons.replay, size: 32),
//         onPressed: () async {
//           if (widget.isVideo) {
//             await _videoController.seekTo(Duration.zero);
//             if (!_isPlaying) {
//               await _videoController.play();
//             }
//           } else {
//             await _audioPlayer.seek(Duration.zero);
//             if (!_isPlaying) {
//               await _audioPlayer.setSourceDeviceFile(_currentFilePath);
//               await _audioPlayer.play(_audioPlayer.source!);
//             }
//           }
//           setState(() {
//             _isPlaying = true;
//           });
//         },
//       ),
//       SizedBox(
//         width: 200,
//         child: ValueListenableBuilder<Duration>(
//           valueListenable: _currentPosition,
//           builder: (context, position, _) {
//             return ValueListenableBuilder<Duration>(
//               valueListenable: _duration,
//               builder: (context, duration, _) {
//                 return Slider(
//                   value: position.inMilliseconds.toDouble().clamp(
//                     0, 
//                     duration.inMilliseconds.toDouble()
//                   ),
//                   min: 0,
//                   max: duration.inMilliseconds.toDouble(),
//                   onChanged: (value) {
//                     final newPosition = Duration(milliseconds: value.toInt());
//                     if (widget.isVideo) {
//                       _videoController.seekTo(newPosition);
//                     } else {
//                       _audioPlayer.seek(newPosition);
//                     }
//                   },
//                 );
//               },
//             );
//           },
//         ),
//       ),
//     ],
//   );
// }

//   Widget _buildTrackControls(int index) {
//     final track = widget.audioTracks[index];
//     return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(8.0),
//         child: Column(
//           children: [
//             Padding( // Added Padding widget here
//               padding: const EdgeInsets.only(bottom: 8.0), // Adjust the bottom padding as needed
//               child: Text(track.originalFile.path.split('/').last),
//             ),
//             _buildSlider('${L10n.translate(context, 'Echo')}', track.echo, (v) {
//               setState(() => track.echo = v);
//             }),
//             _buildSlider('${L10n.translate(context, 'Reverb')}', track.reverb, (v) {
//               setState(() => track.reverb = v);
//             }),
//           ],
//         ),
//       ),
//     );
//         }
//     );
//   }

//   Widget _buildSlider(String effectType, double value, Function(double) onChanged) {
//   // Default values for unknown effect types
//   String leftLabel = 'Min';
//   String rightLabel = 'Max';
//   String valueLabel = value.toStringAsFixed(1);
//   int divisions = 10;
//   double max = 1.0;
  
//   // Configure based on effect type
//   if (effectType == '${L10n.translate(context, 'Echo')}') {
//     leftLabel = '0ms';
//     rightLabel = '100ms';
//     valueLabel = '${value.round()}ms';
//     max = 100.0;
//   } 
//   else if (effectType == '${L10n.translate(context, 'Reverb')}') {
//     leftLabel = '0%';
//     rightLabel = '100%';
//     valueLabel = '${(value * 100).round()}%';
//   }
//   else if (effectType == '${L10n.translate(context, 'Delay')}') {
//     leftLabel = '0ms';
//     rightLabel = '500ms';
//     valueLabel = '${value.round()}ms';
//     max = 500.0;
//     divisions = 20;
//   }
//   // Add more effects here as needed
//   else if (effectType == '${L10n.translate(context, 'Distortion')}') {
//     leftLabel = 'Clean';
//     rightLabel = 'Heavy';
//     valueLabel = value < 0.3 ? 'Light' : 
//                 value < 0.7 ? 'Medium' : 'Heavy';
//   }

//   return Consumer<LocaleProvider>( // Wrap SideMenu with Consumer
//         builder: (context, localeProvider, child) {
//           return Column(
//     crossAxisAlignment: CrossAxisAlignment.stretch,
//     children: [
//       Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 16.0),
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(leftLabel, style: TextStyle(fontSize: 12)),
//             Text(effectType, style: TextStyle(fontWeight: FontWeight.bold)),
//             Text(rightLabel, style: TextStyle(fontSize: 12)),
//           ],
//         ),
//       ),
//       Slider(
//         value: value,
//         min: 0,
//         max: max,
//         divisions: divisions,
//         label: valueLabel,
//         onChanged: onChanged,
//         onChangeEnd: (newValue) {
//           // Only trigger export when slider is released
//           onChanged(newValue);
//           _updateEffects(); // Your existing effects update function
//           if (widget.isVideo) {
//             _videoController.pause();
//           } else {
//             _audioPlayer.pause();
//           }
//           setState(() {
//             _isPlaying = false;
//           });
//         },
//       ),
//     ],
//   );
//         }
//   );
// }

//   Future<void> _saveFinalExport() async {
//     if (!mounted) return;

//     widget.isVideo ? _videoController.pause() : _audioPlayer.pause();

//     final params = SaveFileDialogParams(
//       sourceFilePath: _currentFilePath,
//       fileName: 'export_file.${widget.isVideo ? 'mp4' : 'mp3'}',
//     );
//     final savedPath = await FlutterFileDialog.saveFile(params: params);

//     if (savedPath != null) {
//       final success_str = L10n.translate(context, 'Exported file saved!');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(success_str)),// at: $savedPath')),
//       );
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => ExportSuccessScreen(
//             filePath: savedPath,
//             isVideo: widget.isVideo,
//           ),
//         ),
//       );
//     } else {
//       final fail_str = L10n.translate(context, 'Export canceled or failed.');
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(fail_str)),
//       );
//     }
//   }

//   @override
//   void dispose() {
//     widget.isVideo ? _videoController.dispose() : _audioPlayer.dispose();
//     WidgetsBinding.instance.removeObserver(this);
//     _currentPosition.dispose();
//     _duration.dispose();
//     super.dispose();
//   }
// }


// // END OF EFFECTS SCREEN