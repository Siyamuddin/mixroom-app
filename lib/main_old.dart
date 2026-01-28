// import 'dart:async';
// import 'dart:io';
// import 'package:audio_waveforms/audio_waveforms.dart';
// import 'package:audioplayers/audioplayers.dart';
// import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:video_player/video_player.dart';

// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(
//     MaterialApp(
//       title: 'Flutter Video Editor App',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         primarySwatch: Colors.grey,
//         brightness: Brightness.dark,
//         dividerColor: Colors.white,
//       ),
//       home: const LoginScreen(),
//     ),
//   );
// }

// // ----------------- //
// // LOGIN SCREEN //
// // ----------------- //
// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});
//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }
// class _LoginScreenState extends State<LoginScreen> {
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();
//   void _login() async {
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(builder: (context) => const VideoEditorScreen()),
//     );
//   }
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Welcome to Mixroom')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             TextField(
//               controller: _emailController,
//               decoration: const InputDecoration(labelText: 'Email'),
//             ),
//             TextField(
//               controller: _passwordController,
//               decoration: const InputDecoration(labelText: 'Password'),
//               obscureText: true,
//             ),
//             const SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: _login,
//               child: const Text('Login / Register'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ----------------- //
// // VIDEO EDITOR SCREEN //
// // ----------------- //
// class VideoEditorScreen extends StatefulWidget {
//   const VideoEditorScreen({Key? key}) : super(key: key);
//   @override
//   State<VideoEditorScreen> createState() => _VideoEditorScreenState();
// }
// class _VideoEditorScreenState extends State<VideoEditorScreen> {
//   // Video variables
//   File? _videoFile;
//   VideoPlayerController? _videoController;
//   Duration _videoDuration = Duration.zero;
//   Duration _videoPosition = Duration.zero;
//   Duration _scrubPosition = Duration.zero;
//   bool _isScrubbing = false;

//   // Audio variables
//   File? _audioFile; // DEPRECATE THIS (IT'S SINGLE TRACK)
//   AudioPlayer? _audioPlayer; // DEPRECATE THIS (IT'S SINGLE TRACK)
//   Duration _audioDuration = Duration.zero; // DEPRECATE THIS (IT'S SINGLE TRACK)
//   Duration _audioTrimStart = Duration.zero; // DEPRECATE THIS (IT'S SINGLE TRACK)
//   Duration _audioTrimEnd = Duration.zero; // DEPRECATE THIS (IT'S SINGLE TRACK)

//   // Audio editing controls
//   double _audioOffset = 0.0; // seconds of silence to insert before external audio starts // DEPRECATE THIS (IT'S SINGLE TRACK)
//   double _crossfade = 0.5;   // 0: only video audio, 1: only external audio // DEPRECATE THIS (IT'S SINGLE TRACK)

//   bool _isPlaying = false;
//   bool _audioStarted = false;
//   Timer? _audioStartTimer; // DEPRECATE THIS (IT'S SINGLE TRACK)

//   // For scrubbing state
//   bool _wasPlayingBeforeScrub = false;

//   // Controller for the audio waveform
//   final PlayerController _playerController = PlayerController(); // DEPRECATE THIS (IT'S SINGLE TRACK)

//   // Multi-track support
//   List<AudioTrack> _audioTracks = []; // ONLY NEED TO USE THIS FOR MULTI-TRACK
//   double _universalCrossfade = 0.5;

//   @override
//   void dispose() {
//     _videoController?.dispose();
//     _audioPlayer?.dispose();
//     _audioStartTimer?.cancel();
//     _playerController.dispose();
//     super.dispose();
//   }

//   // Helper: Format Duration as mm:ss.
//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     return "$minutes:$seconds";
//   }

//   // PICK VIDEO
//   Future<void> _pickVideoFile() async {
//     FilePickerResult? result =
//         await FilePicker.platform.pickFiles(type: FileType.video);
//     if (result != null && result.files.single.path != null) {
//       _videoFile = File(result.files.single.path!);
//       await _initializeVideo();
//     }
//   }
//   Future<void> _initializeVideo() async {
//     _videoController = VideoPlayerController.file(_videoFile!);
//     await _videoController!.initialize();
//     if (!mounted) return;
//     setState(() {
//       _videoDuration = _videoController!.value.duration;
//       _videoPosition = _videoController!.value.position;
//       _scrubPosition = _videoController!.value.position;
//     });
//     if (_videoDuration == Duration.zero) {
//       Future.delayed(const Duration(milliseconds: 500), () {
//         if (mounted) {
//           setState(() {
//             _videoDuration = _videoController!.value.duration;
//           });
//         }
//       });
//     }
//     _videoController!.addListener(() async {
//       if (!_isScrubbing && mounted) {
//         setState(() {
//           _videoPosition = _videoController!.value.position;
//           _scrubPosition = _videoController!.value.position;
//           if (_videoController!.value.duration.inMilliseconds >
//               _videoDuration.inMilliseconds) {
//             _videoDuration = _videoController!.value.duration;
//           }
//         });
//         final offsetDuration =
//             Duration(milliseconds: (_audioOffset * 1000).toInt());
//         if (_isPlaying && !_audioStarted && _audioPlayer != null && _audioFile != null) {
//           if (_videoPosition >= offsetDuration) {
//             await _audioPlayer!.seek(_audioTrimStart);
//             _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
//             _audioPlayer!.setVolume(_crossfade);
//             _audioStarted = true;
//           }
//         }
//       }
//     });
//   }

//   // PICK AUDIO
//   Future<void> _pickAudioFile() async {
//     FilePickerResult? result =
//         await FilePicker.platform.pickFiles(type: FileType.any);
//     if (result != null && result.files.single.path != null) {
//       _audioFile = File(result.files.single.path!);
//       await _initializeAudio();
//       _playerController.preparePlayer(path: _audioFile!.path);
//     }
//   }
//   Future<void> _initializeAudio() async {
//     _audioPlayer = AudioPlayer();
//     await _audioPlayer!.setSourceDeviceFile(_audioFile!.path);
//     final dur = await _audioPlayer!.getDuration();
//     if (dur != null && dur > Duration.zero) {
//       setState(() {
//         _audioDuration = dur;
//         if (_audioTrimEnd == Duration.zero) {
//           _audioTrimStart = Duration.zero;
//           _audioTrimEnd = dur;
//         }
//       });
//     }
//     _audioPlayer!.onDurationChanged.listen((duration) {
//       if (!mounted) return;
//       setState(() {
//         _audioDuration = duration;
//         if (_audioTrimEnd == Duration.zero) {
//           _audioTrimStart = Duration.zero;
//           _audioTrimEnd = duration;
//         }
//       });
//     });
//     _audioPlayer!.onPositionChanged.listen((position) {
//       if (position >= _audioTrimEnd && _isPlaying) {
//         _audioPlayer!.pause();
//       }
//     });
//   }

//   // Calculate effective external audio position.
//   Duration _calculateEffectiveAudioPosition(Duration videoPos) {
//     final offsetDuration =
//         Duration(milliseconds: (_audioOffset * 1000).toInt());
//     if (videoPos < offsetDuration) {
//       return _audioTrimStart;
//     } else {
//       var effectiveAudioPos = _audioTrimStart + (videoPos - offsetDuration);
//       if (effectiveAudioPos > _audioTrimEnd) {
//         effectiveAudioPos = _audioTrimEnd;
//       }
//       return effectiveAudioPos;
//     }
//   }

//   // PLAY/PAUSE TOGGLE
//   void _togglePlayPause() async {
//     if (_videoController == null || !_videoController!.value.isInitialized) return;
//     setState(() {
//       _isPlaying = !_isPlaying;
//       _audioStarted = false;
//     });
//     _audioStartTimer?.cancel();
//     if (_isPlaying) {
//       _videoController!.play();
//       _videoController!.setVolume(1 - _crossfade);
//       if (_audioPlayer != null && _audioFile != null) {
//         final offsetDuration =
//             Duration(milliseconds: (_audioOffset * 1000).toInt());
//         if (_videoPosition < offsetDuration) {
//           _audioStartTimer =
//               Timer.periodic(const Duration(milliseconds: 100), (timer) async {
//             if (!_isPlaying) {
//               timer.cancel();
//               return;
//             }
//             if (_videoController!.value.position >= offsetDuration) {
//               await _audioPlayer!.seek(_audioTrimStart);
//               _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
//               _audioPlayer!.setVolume(_crossfade);
//               _audioStarted = true;
//               timer.cancel();
//             }
//           });
//         } else {
//           final effectiveAudioPos =
//               _calculateEffectiveAudioPosition(_videoPosition);
//           await _audioPlayer!.seek(effectiveAudioPos);
//           _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
//           _audioPlayer!.setVolume(_crossfade);
//           _audioStarted = true;
//         }
//       }
//     } else {
//       _videoController!.pause();
//       _audioPlayer?.pause();
//     }
//   }

//   // REWIND
//   void _restartVideo() async {
//     if (_videoController == null || !_videoController!.value.isInitialized) return;
//     _audioStartTimer?.cancel();
//     await Future.wait([
//       _videoController!.pause(),
//       if (_audioPlayer != null) _audioPlayer!.pause(),
//     ]);
//     await Future.wait([
//       _videoController!.seekTo(Duration.zero),
//       if (_audioPlayer != null)
//           _audioPlayer!.seek(_calculateEffectiveAudioPosition(Duration.zero)),
//     ]);
//     setState(() {
//       _videoPosition = Duration.zero;
//       _scrubPosition = Duration.zero;
//       _audioStarted = false;
//     });
//     if (_isPlaying) {
//       _videoController!.play();
//       final offsetDuration =
//           Duration(milliseconds: (_audioOffset * 1000).toInt());
//       if (_videoController!.value.position < offsetDuration) {
//         // Wait until offset reached.
//       } else {
//         await _audioPlayer!.seek(_calculateEffectiveAudioPosition(Duration.zero));
//         _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
//         _audioPlayer!.setVolume(_crossfade);
//         _audioStarted = true;
//       }
//     }
//   }

//   // SCRUBBER
//   Widget _buildCustomScrubber() {
//     if (_videoController == null || !_videoController!.value.isInitialized) {
//       return Container();
//     }
//     final maxValue = _videoController!.value.duration.inMilliseconds.toDouble();
//     return Column(
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(_formatDuration(_videoPosition)),
//             Text(_formatDuration(_videoController!.value.duration)),
//           ],
//         ),
//         Slider(
//           value: _isScrubbing
//               ? _scrubPosition.inMilliseconds.toDouble()
//               : _videoPosition.inMilliseconds.toDouble(),
//           min: 0,
//           max: maxValue > 0 ? maxValue : 1,
//           onChangeStart: (value) {
//             _wasPlayingBeforeScrub = _isPlaying;
//             _pausePlayback();
//             setState(() {
//               _isScrubbing = true;
//               _scrubPosition = Duration(milliseconds: value.toInt());
//               _audioStarted = false;
//             });
//           },
//           onChanged: (value) {
//             setState(() {
//               _scrubPosition = Duration(milliseconds: value.toInt());
//             });
//           },
//           onChangeEnd: (value) async {
//             final newPosition = Duration(milliseconds: value.toInt());
//             await _videoController!.seekTo(newPosition);
//             setState(() {
//               _isScrubbing = false;
//               _videoPosition = newPosition;
//               _scrubPosition = newPosition;
//             });
//             if (_wasPlayingBeforeScrub) {
//               _resumePlayback();
//             }
//           },
//         ),
//       ],
//     );
//   }

//   // Pause helper
//   void _pausePlayback() {
//     _videoController?.pause();
//     _audioPlayer?.pause();
//   }

//   // Resume helper
//   Future<void> _resumePlayback() async {
//     _videoController?.play();
//     final offsetDuration =
//         Duration(milliseconds: (_audioOffset * 1000).toInt());
//     if (_videoController != null &&
//         _videoController!.value.position >= offsetDuration) {
//       final effectiveAudioPos =
//           _calculateEffectiveAudioPosition(_videoController!.value.position);
//       await _audioPlayer?.seek(effectiveAudioPos);
//       _audioPlayer?.resume();
//       _audioStarted = true;
//     }
//   }

//   // EXPORT (SINGLE TRACK)
//   // Future<void> _exportVideo() async {
//   //   if (_videoFile == null || _audioFile == null) {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(content: Text('Please select both video and audio files.')),
//   //     );
//   //     return;
//   //   }
//   //   final videoPath = _videoFile!.path;
//   //   final audioPath = _audioFile!.path;
//   //   final offsetMs = (_audioOffset * 1000).toInt();
//   //   final videoVolume = 1.0 - _crossfade;
//   //   final extAudioVolume = _crossfade;
//   //   // Use atrim to apply external audio trim.
//   //   final ffmpegCommand =
//   //       '-i "$videoPath" -i "$audioPath" '
//   //       '-filter_complex "[0:a]volume=$videoVolume[a0]; '
//   //       '[1:a]atrim=start=${_audioTrimStart.inSeconds}:end=${_audioTrimEnd.inSeconds},adelay=${offsetMs}|${offsetMs},volume=$extAudioVolume[a1]; '
//   //       '[a0][a1]amix=inputs=2:duration=first[aout]" '
//   //       '-map 0:v -map "[aout]" -c:v copy -shortest ';
//   //   final tempDir = await getTemporaryDirectory();
//   //   final tempOutputPath =
//   //       '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';
//   //   final fullCommand = '$ffmpegCommand"$tempOutputPath"';
//   //   await FFmpegKit.execute(fullCommand);
//   //   final params = SaveFileDialogParams(
//   //     sourceFilePath: tempOutputPath,
//   //     fileName: 'exported_video.mp4',
//   //   );
//   //   final savedPath = await FlutterFileDialog.saveFile(params: params);
//   //   if (savedPath != null) {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       SnackBar(content: Text('Exported file saved at: $savedPath')),
//   //     );
//   //   } else {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(content: Text('Export canceled or failed.')),
//   //     );
//   //   }
//   // }

//   // supports multi-track
//   Future<void> _exportVideo() async {
//     if (_videoFile == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('No video selected')),
//       );
//       return;
//     }
//     if (_audioTracks.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('No audio tracks selected')),
//       );
//       return;
//     }

//     // Build the input arguments for ffmpeg.
//     // The first input is the video file, subsequent inputs are each track.
//     final List<String> inputArgs = [];
//     inputArgs.add('-i "${_videoFile!.path}"'); // input #0
//     for (final track in _audioTracks) {
//       inputArgs.add('-i "${track.file.path}"'); // input #1..N
//     }

//     // We'll build the filter_complex step by step.
//     // Start with the video’s audio volume = (1 - crossfade).
//     final double vidVolume = 1.0 - _universalCrossfade;

//     // We’ll store lines for each input in a buffer, then join them.
//     final List<String> filterLines = [];

//     // 1) Video audio (index 0)
//     // Tag it [v0], for example. We'll rename it to [vid].
//     filterLines.add('[0:a]volume=$vidVolume[vid];');

//     // 2) For each audio track i => input #(i+1)
//     // offset => adelay, trim => atrim, volume => _universalCrossfade / (# of tracks) or just _universalCrossfade
//     // For a single “pool” volume, you can do trackVolume = _universalCrossfade / _audioTracks.length to avoid loudness issues,
//     // or just use trackVolume = _universalCrossfade if you want them possibly summing above 1.0.
//     final double trackVolume = _universalCrossfade / _audioTracks.length; 
//     // (If you want them each at _universalCrossfade, that’s also fine, but can be loud.)

//     for (int i = 0; i < _audioTracks.length; i++) {
//       final track = _audioTracks[i];
//       final offsetMs = (track.offset * 1000).round();
//       final startSec = track.trimStart.inSeconds;
//       final endSec   = track.trimEnd.inSeconds;

//       // We'll label them [t1], [t2], etc.
//       final label = 't${i+1}';

//       // Example line:
//       // [i+1:a]atrim=start=START:end=END,adelay=ms|ms,volume=TRACK_VOL[label];
//       filterLines.add(
//         '[${i+1}:a]'
//         'atrim=start=$startSec:end=$endSec,'
//         'adelay=${offsetMs}|${offsetMs},'
//         'volume=$trackVolume'
//         '[$label];'
//       );
//     }

//     // 3) Now we have 1 + _audioTracks.length streams: [vid], [t1], [t2], ...
//     // We amix them all. The total # of inputs = 1 + _audioTracks.length.
//     // Example: amix=inputs=3:duration=first => [mixout]
//     final int totalInputs = 1 + _audioTracks.length;
//     // We’ll build something like: [vid][t1][t2]...amix=inputs=N:duration=first[aout]
//     final String amixInputs = 
//       '[vid]' + 
//       List.generate(_audioTracks.length, (i) => '[t${i+1}]').join() +
//       'amix=inputs=$totalInputs:duration=first[aout]';

//     filterLines.add('$amixInputs;');

//     // Join the lines with no newline needed (or use newlines if you prefer).
//     final String filterComplex = filterLines.join('');

//     // Build the final ffmpeg command
//     final ffmpegCmd = [
//       ...inputArgs,
//       '-filter_complex',
//       '"$filterComplex"', 
//       '-map 0:v',        // keep original video
//       '-map "[aout]"',   // use the mixed audio
//       '-c:v copy',       // don’t re-encode video
//       '-shortest',
//     ];

//     // We'll save the output to a temporary mp4, then open a save dialog.
//     final tempDir = await getTemporaryDirectory();
//     final outPath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';
//     ffmpegCmd.add('"$outPath"');

//     // Build final string
//     final String finalCommand = ffmpegCmd.join(' ');

//     // Execute with ffmpeg_kit
//     await FFmpegKit.execute(finalCommand);

//     // Let user pick location to save
//     final params = SaveFileDialogParams(
//       sourceFilePath: outPath,
//       fileName: 'exported_video.mp4',
//     );
//     final savedPath = await FlutterFileDialog.saveFile(params: params);

//     if (savedPath != null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Exported file saved at: $savedPath')),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Export canceled or failed.')),
//       );
//     }
//   }



//   Widget _buildAudioControls() {
//   return Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       Text('Audio File: ${_audioFile!.path.split('/').last}'),
//       const SizedBox(height: 10),
//       Text('Audio Offset (seconds): ${_audioOffset.toStringAsFixed(2)}'),
//       // Audio offset slider: max 10 seconds, 0.1-sec increments.
//       Slider(
//         value: _audioOffset,
//         min: 0,
//         max: 10,
//         divisions: 1000,
//         label: _audioOffset.toStringAsFixed(2),
//         onChanged: (value) {
//           setState(() {
//             _audioOffset = value;
//           });
//         },
//       ),
//       const SizedBox(height: 10),
//       // Integrated waveform with trim handles.
//       if (_audioFile != null)
//         GestureDetector(
//           onTap: _pickAudioFile,
//           child: WaveformTrimSelector(
//             audioPath: _audioFile!.path,
//             audioDuration: _audioDuration,
//             trimStart: _audioTrimStart,
//             trimEnd: _audioTrimEnd,
//             onTrimChanged: (newTrim) {
//               setState(() {
//                 _audioTrimStart = Duration(seconds: newTrim.start.toInt());
//                 _audioTrimEnd = Duration(seconds: newTrim.end.toInt());
//               });
//             },
//             playerController: _playerController,
//           ),
//         ),
//       const SizedBox(height: 10),
//       Text(
//         'Audio Trim: ${_formatDuration(_audioTrimStart)} - ${_formatDuration(_audioTrimEnd)} (Trim Duration: ${_formatDuration(_audioTrimEnd - _audioTrimStart)})',
//       ),
//       const SizedBox(height: 10),
//       Text('Audio Crossfade: ${(_crossfade * 100).toInt()}%'),
//       Slider(
//         value: _crossfade,
//         min: 0,
//         max: 1,
//         onChanged: (value) {
//           setState(() {
//             _crossfade = value;
//             if (_videoController != null) {
//               _videoController!.setVolume(1 - _crossfade);
//             }
//             if (_audioPlayer != null) {
//               _audioPlayer!.setVolume(_crossfade);
//             }
//           });
//         },
//       ),
//     ],
//   );
// }

//   // In place of old single-audio UI:
//   Widget _buildMultiTrackAudioSection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: [
//         // One crossfade slider for entire mix
//         Text('Crossfade (Video vs. All Audio): ${(_universalCrossfade * 100).toStringAsFixed(0)}%'),
//         Slider(
//           value: _universalCrossfade,
//           min: 0,
//           max: 1,
//           onChanged: (value) {
//             setState(() {
//               _universalCrossfade = value;
//               // e.g. set video volume = (1 - crossfade), etc. if you want live playback changes
//               _videoController?.setVolume(1 - _universalCrossfade);
//               // For each track, you can also set track.player.setVolume(_universalCrossfade) if you want live mixing.
//             });
//           },
//         ),
//         const SizedBox(height: 10),

//         // "Add Track" button
//         ElevatedButton(
//           onPressed: _addAudioTrack,
//           child: const Text('Add Audio Track'),
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
//         ),
//       ],
//     );
//   }

//   Widget _buildSingleTrackUI(int index) {
//     final track = _audioTracks[index];
//     return Card(
//       margin: const EdgeInsets.symmetric(vertical: 8),
//       child: Padding(
//         padding: const EdgeInsets.all(12.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Row with file name and a delete button.
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text('Audio: ${track.file.path.split('/').last}',
//                     style: const TextStyle(fontWeight: FontWeight.bold)),
//                 IconButton(
//                   icon: const Icon(Icons.delete),
//                   onPressed: () {
//                     setState(() {
//                       _audioTracks.removeAt(index);
//                     });
//                   },
//                 ),
//               ],
//             ),
//             const SizedBox(height: 10),
//             // Offset slider for this track.
//             Text('Offset: ${track.offset.toStringAsFixed(2)} s'),
//             Slider(
//               value: track.offset,
//               min: 0,
//               max: 10,
//               divisions: 1000,
//               label: track.offset.toStringAsFixed(2),
//               onChanged: (value) {
//                 setState(() {
//                   track.offset = value;
//                 });
//               },
//             ),
//             const SizedBox(height: 10),
//             // Use the custom WaveformTrimSelector widget for the trim functionality.
//             _buildWaveformWithTrim(track, _audioDuration),
//             const SizedBox(height: 10),
//             // Display current trim range text.
//             Text(
//               'Trim: ${_formatDuration(track.trimStart)} - ${_formatDuration(track.trimEnd)}'
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildWaveformWithTrim(AudioTrack track, Duration fullDuration) {
//   return LayoutBuilder(
//     builder: (context, constraints) {
//       final double boxWidth = constraints.maxWidth;
//       final double paddingH = 10.0; // horizontal padding around waveform
//       final double effectiveWidth = boxWidth - (2 * paddingH);
//       final double totalSec = fullDuration.inSeconds.toDouble();
//       final double handleWidth = 20.0;
//       final double handleHalf = handleWidth / 2.0;
      
//       // Use track.trimStart and track.trimEnd for handle positions (in seconds)
//       final double localTrimStart = track.trimStart.inSeconds.toDouble();
//       final double localTrimEnd   = track.trimEnd.inSeconds.toDouble();
      
//       return SizedBox(
//         height: 80,
//         width: boxWidth,
//         child: Stack(
//           children: [
//             // 1) Waveform: drawn within the effective area.
//             Positioned(
//               left: paddingH,
//               top: 0,
//               width: effectiveWidth,
//               height: 80,
//               child: AudioFileWaveforms(
//                 size: Size(effectiveWidth, 80),
//                 playerController: track.waveformController,
//                 continuousWaveform: false,
//                 enableSeekGesture: false,
//                 waveformType: WaveformType.fitWidth,
//                 playerWaveStyle: const PlayerWaveStyle(
//                   seekLineColor: Colors.blue,
//                   showSeekLine: false,
//                 ),
//               ),
//             ),
//             // 2) Left shading: covers from left edge to trim start.
//             Positioned(
//               left: paddingH,
//               top: 0,
//               bottom: 0,
//               width: effectiveWidth * (localTrimStart / totalSec),
//               child: Container(color: Colors.black.withOpacity(0.3)),
//             ),
//             // 3) Right shading: covers from trim end to right edge.
//             Positioned(
//               left: paddingH + effectiveWidth * (localTrimEnd / totalSec),
//               top: 0,
//               bottom: 0,
//               right: paddingH,
//               child: Container(color: Colors.black.withOpacity(0.3)),
//             ),
//             // 4) Draggable handle for trim start.
//             Positioned(
//               left: paddingH + (effectiveWidth * (localTrimStart / totalSec)) - handleHalf,
//               top: 0,
//               bottom: 0,
//               child: GestureDetector(
//                 behavior: HitTestBehavior.translucent,
//                 onHorizontalDragUpdate: (details) {
//                   setState(() {
//                     final double currentPos = effectiveWidth * (localTrimStart / totalSec);
//                     double newPos = currentPos + details.delta.dx;
//                     // Clamp so the start handle doesn't cross the end handle minus a gap (10px).
//                     final double maxPos = (effectiveWidth * (localTrimEnd / totalSec)) - 10;
//                     newPos = newPos.clamp(0.0, maxPos);
//                     double newTrimStart = newPos / effectiveWidth * totalSec;
//                     track.trimStart = Duration(seconds: newTrimStart.toInt());
//                   });
//                 },
//                 child: Container(
//                   width: handleWidth,
//                   height: 80,
//                   color: Colors.red.withOpacity(0.5),
//                 ),
//               ),
//             ),
//             // 5) Draggable handle for trim end.
//             Positioned(
//               left: paddingH + (effectiveWidth * (localTrimEnd / totalSec)) - handleHalf,
//               top: 0,
//               bottom: 0,
//               child: GestureDetector(
//                 behavior: HitTestBehavior.translucent,
//                 onHorizontalDragUpdate: (details) {
//                   setState(() {
//                     final double currentPos = effectiveWidth * (localTrimEnd / totalSec);
//                     double newPos = currentPos + details.delta.dx;
//                     // Clamp newPos between (start handle + 10px) and the full effective width.
//                     final double minPos = (effectiveWidth * (localTrimStart / totalSec)) + 10;
//                     newPos = newPos.clamp(minPos, effectiveWidth);
//                     double newTrimEnd = newPos / effectiveWidth * totalSec;
//                     track.trimEnd = Duration(seconds: newTrimEnd.toInt());
//                   });
//                 },
//                 child: Container(
//                   width: handleWidth,
//                   height: 80,
//                   color: Colors.red.withOpacity(0.5),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       );
//     },
//   );
// }




//   Future<void> _addAudioTrack() async {
//     FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
//     if (result != null && result.files != null && result.files.single.path != null) {
//       final newFile = File(result.files.single.path!);
//       final newPlayer = AudioPlayer();
//       await newPlayer.setSourceDeviceFile(newFile.path);
//       final dur = await newPlayer.getDuration() ?? Duration.zero;

//       final newController = PlayerController();
//       newController.preparePlayer(path: newFile.path);

//       setState(() {
//         _audioTracks.add(
//           AudioTrack(
//             file: newFile,
//             player: newPlayer,
//             waveformController: newController,
//             trimStart: Duration.zero,
//             trimEnd: dur,
//             offset: 0.0,
//             crossfade: 1.0,
//           ),
//         );
//       });
//     }
//   }


//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Video Editor')),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             // VIDEO SECTION
//             _videoController == null
//                 ? ElevatedButton(
//                     onPressed: _pickVideoFile,
//                     child: const Text('Select Video'),
//                   )
//                 : Column(
//                     crossAxisAlignment: CrossAxisAlignment.stretch,
//                     children: [
//                       GestureDetector(
//                         onTap: _pickVideoFile,
//                         child: AspectRatio(
//                           aspectRatio: _videoController!.value.aspectRatio,
//                           child: VideoPlayer(_videoController!),
//                         ),
//                       ),
//                       _buildCustomScrubber(),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           IconButton(
//                             icon: Icon(
//                               _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
//                               size: 32,
//                             ),
//                             onPressed: _togglePlayPause,
//                           ),
//                           const SizedBox(width: 20),
//                           IconButton(
//                             icon: const Icon(Icons.replay, size: 32),
//                             onPressed: _restartVideo,
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//             const SizedBox(height: 20),
//             // AUDIO SECTION
//             // _buildMultiTrackAudioSection(),
//             _audioFile == null
//                 ? ElevatedButton(
//                     onPressed: _pickAudioFile,
//                     child: const Text('Select Audio'),
//                   )
//                 : _buildMultiTrackAudioSection(),//_buildAudioControls(),
//             const SizedBox(height: 20),
//             // EXPORT BUTTON
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 ElevatedButton(
//                   onPressed: () {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       const SnackBar(content: Text('AI Sync not implemented yet')),
//                     );
//                   },
//                   child: const Text('AI Sync'),
//                 ),
//                 ElevatedButton(
//                   onPressed: _exportVideo,
//                   child: const Text('Export'),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class WaveformTrimSelector extends StatefulWidget {
//   final String audioPath;
//   final Duration audioDuration;
//   final Duration trimStart;
//   final Duration trimEnd;
//   final ValueChanged<RangeValues> onTrimChanged;
//   final PlayerController playerController;
  
//   const WaveformTrimSelector({
//     Key? key,
//     required this.audioPath,
//     required this.audioDuration,
//     required this.trimStart,
//     required this.trimEnd,
//     required this.onTrimChanged,
//     required this.playerController,
//   }) : super(key: key);
  
//   @override
//   State<WaveformTrimSelector> createState() => _WaveformTrimSelectorState();
// }

// class _WaveformTrimSelectorState extends State<WaveformTrimSelector> {
//   late double _localTrimStart;
//   late double _localTrimEnd;
  
//   @override
//   void initState() {
//     super.initState();
//     _localTrimStart = widget.trimStart.inSeconds.toDouble();
//     _localTrimEnd = widget.trimEnd.inSeconds.toDouble();
//   }
  
//   @override
//   void didUpdateWidget(covariant WaveformTrimSelector oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     _localTrimStart = widget.trimStart.inSeconds.toDouble();
//     _localTrimEnd = widget.trimEnd.inSeconds.toDouble();
//   }
  
//   @override
//   Widget build(BuildContext context) {
//     final totalSec = widget.audioDuration.inSeconds.toDouble();
//     final width = MediaQuery.of(context).size.width;
    
//     final double paddingH = 45.0;
//     final double effectiveWidth = MediaQuery.of(context).size.width - 2 * paddingH;
    
//     return SizedBox(
//       height: 80,
//       width: width,
//       child: Stack(
//         children: [
//           // Full-width, non-scrollable waveform.
//           AudioFileWaveforms(
//             size: Size(width, 80),
//             playerController: widget.playerController,
//             continuousWaveform: false,
//             enableSeekGesture: false,
//             waveformType: WaveformType.fitWidth,
//             playerWaveStyle: const PlayerWaveStyle(
//               seekLineColor: Colors.blue,
//               showSeekLine: false,
//             ),
//           ),
//           // Shaded overlay for regions outside the trim.
//           Positioned(
//             left: 0,
//             top: 0,
//             bottom: 0,
//             width: width * (_localTrimStart / totalSec),
//             child: Container(color: Colors.black.withOpacity(0.3)),
//           ),
//           Positioned(
//             left: (width * (_localTrimEnd / totalSec)).clamp(0.0, width),
//             top: 0,
//             bottom: 0,
//             right: 0,
//             child: Container(color: Colors.black.withOpacity(0.3)),
//           ),
//           // Draggable handle for trim start.
//           Positioned(
//             left: width * (_localTrimStart / totalSec) - 10,
//             top: 0,
//             bottom: 0,
//             child: GestureDetector(
//               behavior: HitTestBehavior.translucent,
//               onHorizontalDragUpdate: (details) {
//                 setState(() {
//                   // Current pixel position of start bar
//                   final currentPos = width * (_localTrimStart / totalSec);
//                   // Attempt to move by delta
//                   double newPos = currentPos + details.delta.dx;
//                   // Maximum allowed is just before the end bar minus 20 px
//                   final maxPos = (width * (_localTrimEnd / totalSec)) - 20;
//                   newPos = newPos.clamp(0.0, maxPos);

//                   // Convert back to seconds
//                   _localTrimStart = (newPos / width * totalSec).clamp(0.0, _localTrimEnd);
//                 });
//                 widget.onTrimChanged(RangeValues(_localTrimStart, _localTrimEnd));
//               },
//               child: Container(
//                 width: 20,
//                 color: Colors.red.withOpacity(0.5),
//               ),
//             ),
//           ),
//           // Draggable handle for trim end (RED)
//           Positioned(
//             left: paddingH + ((effectiveWidth * (_localTrimEnd / totalSec)) - 10).clamp(0.0, effectiveWidth - 20),
//             top: 0,
//             bottom: 0,
//             child: GestureDetector(
//               behavior: HitTestBehavior.translucent,
//               onHorizontalDragUpdate: (details) {
//                 setState(() {
//                   double currentPos = effectiveWidth * (_localTrimEnd / totalSec);
//                   double newPos = currentPos + details.delta.dx;
//                   // Ensure newPos is at least 20 px to the right of the left bar's position
//                   final double minPos = effectiveWidth * (_localTrimStart / totalSec) + 20;
//                   newPos = newPos.clamp(minPos, effectiveWidth);
//                   _localTrimEnd = (newPos / effectiveWidth * totalSec).clamp(_localTrimStart, totalSec);
//                 });
//                 widget.onTrimChanged(RangeValues(_localTrimStart, _localTrimEnd));
//               },
//               child: Container(
//                 width: 20,
//                 height: 80,
//                 color: Colors.red.withOpacity(0.5),
//               ),
//             ),
//           ),

//         ],
//       ),
//     );
//   }
// }

// class AudioTrack {
//   File file;                    // The chosen audio file
//   AudioPlayer player;           // The AudioPlayer instance
//   PlayerController waveformController;  // For audio_waveforms
//   Duration trimStart;
//   Duration trimEnd;
//   double offset;                // in seconds
//   double crossfade;             // 0..1
//   // ...any other fields
//   AudioTrack({
//     required this.file,
//     required this.player,
//     required this.waveformController,
//     required this.trimStart,
//     required this.trimEnd,
//     required this.offset,
//     required this.crossfade,
//   });
// }
// // class VideoEditorScreen extends StatefulWidget {
// //   const VideoEditorScreen({Key? key}) : super(key: key);

// //   @override
// //   State<VideoEditorScreen> createState() => _VideoEditorScreenState();
// // }

// // class _VideoEditorScreenState extends State<VideoEditorScreen> {
// //   // Video variables
// //   File? _videoFile;
// //   VideoPlayerController? _videoController;
// //   Duration _videoDuration = Duration.zero;
// //   Duration _videoPosition = Duration.zero;
// //   Duration _scrubPosition = Duration.zero;
// //   bool _isScrubbing = false;

// //   // Audio variables
// //   File? _audioFile;
// //   AudioPlayer? _audioPlayer;
// //   Duration _audioDuration = Duration.zero;
// //   Duration _audioTrimStart = Duration.zero;
// //   Duration _audioTrimEnd = Duration.zero;

// //   // Audio editing controls
// //   double _audioOffset = 0.0; // seconds of silence to insert before external audio starts (max 10 sec)
// //   double _crossfade = 0.5;   // 0: only video audio, 1: only external audio

// //   bool _isPlaying = false;
// //   bool _audioStarted = false;
// //   Timer? _audioStartTimer;

// //   // Scrubbing state flag
// //   bool _wasPlayingBeforeScrub = false;

// //   // Required controller for audio_waveforms version 1.3.0
// //   final PlayerController _playerController = PlayerController();

// //   @override
// //   void dispose() {
// //     _videoController?.dispose();
// //     _audioPlayer?.dispose();
// //     _audioStartTimer?.cancel();
// //     _playerController.dispose();
// //     super.dispose();
// //   }

// //   // Helper: Format Duration as mm:ss.
// //   String _formatDuration(Duration duration) {
// //     String twoDigits(int n) => n.toString().padLeft(2, '0');
// //     final minutes = twoDigits(duration.inMinutes.remainder(60));
// //     final seconds = twoDigits(duration.inSeconds.remainder(60));
// //     return "$minutes:$seconds";
// //   }

// //   // PICK VIDEO
// //   Future<void> _pickVideoFile() async {
// //     FilePickerResult? result =
// //         await FilePicker.platform.pickFiles(type: FileType.video);
// //     if (result != null && result.files.single.path != null) {
// //       _videoFile = File(result.files.single.path!);
// //       await _initializeVideo();
// //     }
// //   }

// //   Future<void> _initializeVideo() async {
// //     _videoController = VideoPlayerController.file(_videoFile!);
// //     await _videoController!.initialize();
// //     if (!mounted) return;
// //     setState(() {
// //       _videoDuration = _videoController!.value.duration;
// //       _videoPosition = _videoController!.value.position;
// //       _scrubPosition = _videoController!.value.position;
// //     });
// //     if (_videoDuration == Duration.zero) {
// //       Future.delayed(const Duration(milliseconds: 500), () {
// //         if (mounted) {
// //           setState(() {
// //             _videoDuration = _videoController!.value.duration;
// //           });
// //         }
// //       });
// //     }
// //     _videoController!.addListener(() async {
// //       if (!_isScrubbing && mounted) {
// //         setState(() {
// //           _videoPosition = _videoController!.value.position;
// //           _scrubPosition = _videoController!.value.position;
// //           if (_videoController!.value.duration.inMilliseconds >
// //               _videoDuration.inMilliseconds) {
// //             _videoDuration = _videoController!.value.duration;
// //           }
// //         });
// //         // If playing and external audio hasn't started, check if video reached offset.
// //         Duration offsetDuration =
// //             Duration(milliseconds: (_audioOffset * 1000).toInt());
// //         if (_isPlaying && !_audioStarted && _audioPlayer != null && _audioFile != null) {
// //           if (_videoPosition >= offsetDuration) {
// //             // When video reaches offset, start external audio from the trim start.
// //             await _audioPlayer!.seek(_audioTrimStart);
// //             _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
// //             _audioPlayer!.setVolume(_crossfade);
// //             _audioStarted = true;
// //           }
// //         }
// //       }
// //     });
// //   }

// //   // PICK AUDIO
// //   Future<void> _pickAudioFile() async {
// //     FilePickerResult? result =
// //         await FilePicker.platform.pickFiles(type: FileType.any);
// //     if (result != null && result.files.single.path != null) {
// //       _audioFile = File(result.files.single.path!);
// //       await _initializeAudio();
// //       // Load waveform data into the player controller.
// //       // _playerController.loadDataFromPath(_audioFile!.path);
// //       _playerController.preparePlayer(path: _audioFile!.path);

// //     }
// //   }

// //   Future<void> _initializeAudio() async {
// //     _audioPlayer = AudioPlayer();
// //     await _audioPlayer!.setSourceDeviceFile(_audioFile!.path);
// //     Duration? dur = await _audioPlayer!.getDuration();
// //     if (dur != null && dur > Duration.zero) {
// //       setState(() {
// //         _audioDuration = dur;
// //         if (_audioTrimEnd == Duration.zero) {
// //           _audioTrimStart = Duration.zero;
// //           _audioTrimEnd = dur;
// //         }
// //       });
// //     }
// //     _audioPlayer!.onDurationChanged.listen((duration) {
// //       if (!mounted) return;
// //       setState(() {
// //         _audioDuration = duration;
// //         if (_audioTrimEnd == Duration.zero) {
// //           _audioTrimStart = Duration.zero;
// //           _audioTrimEnd = duration;
// //         }
// //       });
// //     });
// //     _audioPlayer!.onPositionChanged.listen((position) {
// //       if (position.inMilliseconds >= _audioTrimEnd.inMilliseconds && _isPlaying) {
// //         _audioPlayer!.pause();
// //       }
// //     });
// //   }

// //   // Calculate effective external audio position.
// //   // If videoPos is less than the offset, external audio remains silent (stays at _audioTrimStart).
// //   // Otherwise, effectiveAudioPos = _audioTrimStart + (videoPos - offset).
// //   Duration _calculateEffectiveAudioPosition(Duration videoPos) {
// //     Duration offsetDuration =
// //         Duration(milliseconds: (_audioOffset * 1000).toInt());
// //     if (videoPos < offsetDuration) {
// //       return _audioTrimStart;
// //     } else {
// //       Duration effectiveAudioPos = _audioTrimStart + (videoPos - offsetDuration);
// //       if (effectiveAudioPos > _audioTrimEnd) effectiveAudioPos = _audioTrimEnd;
// //       return effectiveAudioPos;
// //     }
// //   }

// //   // PLAY/PAUSE TOGGLE
// //   void _togglePlayPause() async {
// //     if (_videoController == null || !_videoController!.value.isInitialized) return;
// //     setState(() {
// //       _isPlaying = !_isPlaying;
// //       _audioStarted = false;
// //     });
// //     _audioStartTimer?.cancel();
// //     if (_isPlaying) {
// //       _videoController!.play();
// //       _videoController!.setVolume(1 - _crossfade);
// //       if (_audioPlayer != null && _audioFile != null) {
// //         Duration offsetDuration =
// //             Duration(milliseconds: (_audioOffset * 1000).toInt());
// //         if (_videoPosition < offsetDuration) {
// //           // Video is before offset; audio will be started by the listener.
// //         } else {
// //           Duration effectiveAudioPos = _calculateEffectiveAudioPosition(_videoPosition);
// //           await _audioPlayer!.seek(effectiveAudioPos);
// //           _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
// //           _audioPlayer!.setVolume(_crossfade);
// //           _audioStarted = true;
// //         }
// //       }
// //     } else {
// //       _videoController!.pause();
// //       _audioPlayer?.pause();
// //     }
// //   }

// //   // REWIND (RESTART) LOGIC: Pause, seek both to 0, then resume if needed.
// //   void _restartVideo() async {
// //     if (_videoController != null && _videoController!.value.isInitialized) {
// //       _audioStartTimer?.cancel();
// //       await Future.wait([
// //         _videoController!.pause(),
// //         if (_audioPlayer != null) _audioPlayer!.pause(),
// //       ]);
// //       await Future.wait([
// //         _videoController!.seekTo(Duration.zero),
// //         if (_audioPlayer != null)
// //           _audioPlayer!.seek(_calculateEffectiveAudioPosition(Duration.zero)),
// //       ]);
// //       setState(() {
// //         _videoPosition = Duration.zero;
// //         _scrubPosition = Duration.zero;
// //         _audioStarted = false;
// //       });
// //       if (_isPlaying) {
// //         _videoController!.play();
// //         Duration offsetDuration =
// //             Duration(milliseconds: (_audioOffset * 1000).toInt());
// //         if (_videoController!.value.position < offsetDuration) {
// //           // Audio remains silent until video reaches offset.
// //         } else {
// //           await _audioPlayer!.seek(_calculateEffectiveAudioPosition(Duration.zero));
// //           _audioPlayer!.play(DeviceFileSource(_audioFile!.path));
// //           _audioPlayer!.setVolume(_crossfade);
// //           _audioStarted = true;
// //         }
// //       }
// //     }
// //   }

// //   // SCRUBBER (SYNC VIDEO & AUDIO)
// //   // When scrubbing while playing, we pause playback, update the position, then resume based on previous state.
// //   Widget _buildCustomScrubber() {
// //     if (_videoController == null || !_videoController!.value.isInitialized) return Container();
// //     final maxValue = _videoController!.value.duration.inMilliseconds.toDouble();
// //     return Column(
// //       children: [
// //         Row(
// //           mainAxisAlignment: MainAxisAlignment.spaceBetween,
// //           children: [
// //             Text(_formatDuration(_videoPosition)),
// //             Text(_formatDuration(_videoController!.value.duration)),
// //           ],
// //         ),
// //         Slider(
// //           value: _isScrubbing
// //               ? _scrubPosition.inMilliseconds.toDouble()
// //               : _videoPosition.inMilliseconds.toDouble(),
// //           min: 0,
// //           max: maxValue > 0 ? maxValue : 1,
// //           onChangeStart: (value) {
// //             _wasPlayingBeforeScrub = _isPlaying;
// //             _pausePlayback();
// //             setState(() {
// //               _isScrubbing = true;
// //               _scrubPosition = Duration(milliseconds: value.toInt());
// //               _audioStarted = false;
// //             });
// //           },
// //           onChanged: (value) {
// //             setState(() {
// //               _scrubPosition = Duration(milliseconds: value.toInt());
// //             });
// //           },
// //           onChangeEnd: (value) async {
// //             final newPosition = Duration(milliseconds: value.toInt());
// //             await _videoController!.seekTo(newPosition);
// //             setState(() {
// //               _isScrubbing = false;
// //               _videoPosition = newPosition;
// //               _scrubPosition = newPosition;
// //             });
// //             if (_wasPlayingBeforeScrub) {
// //               _resumePlayback();
// //             }
// //           },
// //         ),
// //       ],
// //     );
// //   }

// //   // Helper to pause both video and audio.
// //   void _pausePlayback() {
// //     _videoController?.pause();
// //     _audioPlayer?.pause();
// //   }

// //   // Helper to resume playback.
// //   Future<void> _resumePlayback() async {
// //     _videoController?.play();
// //     Duration offsetDuration =
// //         Duration(milliseconds: (_audioOffset * 1000).toInt());
// //     if (_videoController != null && _videoController!.value.position >= offsetDuration) {
// //       Duration effectiveAudioPos = _calculateEffectiveAudioPosition(_videoController!.value.position);
// //       await _audioPlayer?.seek(effectiveAudioPos);
// //       _audioPlayer?.resume();
// //       _audioStarted = true;
// //     }
// //   }

// //   // EXPORT FUNCTION: Mix video and external audio with applied trim, offset, and crossfade.
// //   Future<void> _exportVideo() async {
// //     if (_videoFile == null || _audioFile == null) {
// //       ScaffoldMessenger.of(context).showSnackBar(
// //         const SnackBar(content: Text('Please select both video and audio files.')),
// //       );
// //       return;
// //     }

// //     final String videoPath = _videoFile!.path;
// //     final String audioPath = _audioFile!.path;
// //     final int offsetMs = (_audioOffset * 1000).toInt();
// //     final double videoVolume = 1.0 - _crossfade;
// //     final double extAudioVolume = _crossfade;

// //     // Use atrim to apply audio trim.
// //     String ffmpegCommand =
// //         '-i "$videoPath" -i "$audioPath" '
// //         '-filter_complex "[0:a]volume=$videoVolume[a0]; '
// //         '[1:a]atrim=start=${_audioTrimStart.inSeconds}:end=${_audioTrimEnd.inSeconds},adelay=${offsetMs}|${offsetMs},volume=$extAudioVolume[a1]; '
// //         '[a0][a1]amix=inputs=2:duration=first[aout]" '
// //         '-map 0:v -map "[aout]" -c:v copy -shortest ';

// //     Directory tempDir = await getTemporaryDirectory();
// //     final String tempOutputPath = '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.mp4';
// //     ffmpegCommand += '"$tempOutputPath"';

// //     await FFmpegKit.execute(ffmpegCommand);

// //     final params = SaveFileDialogParams(
// //       sourceFilePath: tempOutputPath,
// //       fileName: 'exported_video.mp4',
// //     );
// //     final savedPath = await FlutterFileDialog.saveFile(params: params);

// //     if (savedPath != null) {
// //       ScaffoldMessenger.of(context).showSnackBar(
// //         SnackBar(content: Text('Exported file saved at: $savedPath')),
// //       );
// //     } else {
// //       ScaffoldMessenger.of(context).showSnackBar(
// //         const SnackBar(content: Text('Export canceled or failed.')),
// //       );
// //     }
// //   }

// //   // AUDIO CONTROLS (ALWAYS VISIBLE AFTER SELECTING AUDIO)
// //   Widget _buildAudioControls() {
// //     return Column(
// //       crossAxisAlignment: CrossAxisAlignment.start,
// //       children: [
// //         Text('Audio File: ${_audioFile!.path.split('/').last}'),
// //         const SizedBox(height: 10),
// //         Text('Audio Offset (seconds): ${_audioOffset.toStringAsFixed(1)}'),
// //         // Maximum is fixed at 10 seconds.
// //         Slider(
// //           value: _audioOffset,
// //           min: 0,
// //           max: 10,
// //           divisions: 10,
// //           label: _audioOffset.toStringAsFixed(1),
// //           onChanged: (value) {
// //             setState(() {
// //               _audioOffset = value;
// //             });
// //           },
// //         ),
// //         const SizedBox(height: 10),
// //         // Display a waveform for the external audio file.
// //         if (_audioFile != null)
// //           Container(
// //             height: 70,
// //             width: double.infinity,
// //             child: AudioFileWaveforms(
// //               size: Size(MediaQuery.of(context).size.width, 70),
// //               playerController: _playerController,
// //               continuousWaveform: true,
// //               playerWaveStyle: const PlayerWaveStyle(
// //                   seekLineColor: Colors.blue,
// //                   showSeekLine: true,
// //                 ),
// //                 enableSeekGesture: true,
// //               ),
// //           ),
// //         const SizedBox(height: 10),
// //         if (_audioDuration > Duration.zero)
// //           Column(
// //             crossAxisAlignment: CrossAxisAlignment.start,
// //             children: [
// //               Text(
// //                 'Audio Trim: ${_formatDuration(_audioTrimStart)} - ${_formatDuration(_audioTrimEnd)} (Trim Duration: ${_formatDuration(_audioTrimEnd - _audioTrimStart)})',
// //               ),
// //               RangeSlider(
// //                 values: RangeValues(
// //                   _audioTrimStart.inSeconds.toDouble(),
// //                   _audioTrimEnd.inSeconds.toDouble(),
// //                 ),
// //                 min: 0,
// //                 max: _audioDuration.inSeconds.toDouble(),
// //                 divisions: _audioDuration.inSeconds > 0 ? _audioDuration.inSeconds : 1,
// //                 labels: RangeLabels(
// //                   _formatDuration(_audioTrimStart),
// //                   _formatDuration(_audioTrimEnd),
// //                 ),
// //                 onChanged: (values) {
// //                   setState(() {
// //                     _audioTrimStart = Duration(seconds: values.start.toInt());
// //                     _audioTrimEnd = Duration(seconds: values.end.toInt());
// //                   });
// //                 },
// //               ),
// //             ],
// //           ),
// //         const SizedBox(height: 10),
// //         Text('Audio Crossfade: ${(_crossfade * 100).toInt()}%'),
// //         Slider(
// //           value: _crossfade,
// //           min: 0,
// //           max: 1,
// //           onChanged: (value) {
// //             setState(() {
// //               _crossfade = value;
// //               if (_videoController != null) {
// //                 _videoController!.setVolume(1 - _crossfade);
// //               }
// //               if (_audioPlayer != null) {
// //                 _audioPlayer!.setVolume(_crossfade);
// //               }
// //             });
// //           },
// //         ),
// //       ],
// //     );
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(title: const Text('Video Editor')),
// //       body: SingleChildScrollView(
// //         padding: const EdgeInsets.all(16),
// //         child: Column(
// //           children: [
// //             // VIDEO SECTION
// //             _videoController == null
// //                 ? ElevatedButton(
// //                     onPressed: _pickVideoFile,
// //                     child: const Text('Select Video'),
// //                   )
// //                 : Column(
// //                     crossAxisAlignment: CrossAxisAlignment.stretch,
// //                     children: [
// //                       AspectRatio(
// //                         aspectRatio: _videoController!.value.aspectRatio,
// //                         child: VideoPlayer(_videoController!),
// //                       ),
// //                       _buildCustomScrubber(),
// //                       Row(
// //                         mainAxisAlignment: MainAxisAlignment.center,
// //                         children: [
// //                           IconButton(
// //                             icon: Icon(
// //                               _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
// //                               size: 32,
// //                             ),
// //                             onPressed: _togglePlayPause,
// //                           ),
// //                           const SizedBox(width: 20),
// //                           IconButton(
// //                             icon: const Icon(Icons.replay, size: 32),
// //                             onPressed: _restartVideo,
// //                           ),
// //                         ],
// //                       ),
// //                     ],
// //                   ),
// //             const SizedBox(height: 20),
// //             // AUDIO SECTION
// //             _audioFile == null
// //                 ? ElevatedButton(
// //                     onPressed: _pickAudioFile,
// //                     child: const Text('Select Audio'),
// //                   )
// //                 : _buildAudioControls(),
// //             const SizedBox(height: 20),
// //             // EXPORT BUTTONS
// //             Row(
// //               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
// //               children: [
// //                 ElevatedButton(
// //                   onPressed: () {
// //                     ScaffoldMessenger.of(context).showSnackBar(
// //                       const SnackBar(content: Text('AI Sync not implemented yet')),
// //                     );
// //                   },
// //                   child: const Text('AI Sync'),
// //                 ),
// //                 ElevatedButton(
// //                   onPressed: _exportVideo,
// //                   child: const Text('Export'),
// //                 ),
// //               ],
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }
 