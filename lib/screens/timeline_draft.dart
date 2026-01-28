//**
//
//  THIS IS CODE to replace your video editor with a timeline that is closer to a DAW (visual timeline, drag/cut clips, etc.)
//
//
//
// */




// // lib/timeline.dart
// import 'dart:math';
// import 'package:flutter/material.dart';

// /// ---------- Models ----------
// class AudioClip {
//   final String id;
//   final String name;
//   final String path;
//   double startMs;        // position on timeline
//   double durationMs;     // visible duration (after trims)
//   double mediaOffsetMs;  // how far into source (left trim)
//   double fadeInMs;
//   double fadeOutMs;
//   double gain;           // 0.0 - 3.0
//   bool selected;
//   final List<double>? waveform; // normalized [-1..1]

//   AudioClip({
//     required this.id,
//     required this.name,
//     required this.path,
//     required this.startMs,
//     required this.durationMs,
//     this.mediaOffsetMs = 0,
//     this.fadeInMs = 0,
//     this.fadeOutMs = 0,
//     this.gain = 1.0,
//     this.selected = false,
//     this.waveform,
//   });

//   double get endMs => startMs + durationMs;

//   AudioClip copy() => AudioClip(
//     id: id,
//     name: name,
//     path: path,
//     startMs: startMs,
//     durationMs: durationMs,
//     mediaOffsetMs: mediaOffsetMs,
//     fadeInMs: fadeInMs,
//     fadeOutMs: fadeOutMs,
//     gain: gain,
//     selected: selected,
//     waveform: waveform,
//   );
// }

// class TimelineController extends ChangeNotifier {
//   double pixelsPerSecond = 120;     // zoom
//   double playheadMs = 0;
//   double quantizeMs = 0;            // 0 = off, e.g. 125 for 1/8 at 120bpm
//   double contentLengthMs = 60000;   // grows as clips extend
//   double snapPx = 8;                // snap distance in px

//   double msToPx(double ms) => ms / 1000 * pixelsPerSecond;
//   double pxToMs(double px) => px / pixelsPerSecond * 1000;

//   void setZoom(double pps) { pixelsPerSecond = pps; notifyListeners(); }
//   void setPlayhead(double ms) { playheadMs = max(0, ms); notifyListeners(); }
//   void setQuantize(double ms) { quantizeMs = ms; notifyListeners(); }
//   void ensureContentLength(double endMs) {
//     if (endMs > contentLengthMs) { contentLengthMs = endMs + 2000; notifyListeners(); }
//   }
// }

// /// ---------- Demo Screen ----------
// class AudioTimelineDemo extends StatelessWidget {
//   const AudioTimelineDemo({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'BandLab-like Timeline',
//       theme: ThemeData(
//         colorSchemeSeed: const Color(0xffc33c2e), // reddish accent (Mixroom vibe)
//         brightness: Brightness.dark,
//         useMaterial3: true,
//       ),
//       home: const TimelinePage(),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }

// class TimelinePage extends StatefulWidget {
//   const TimelinePage({super.key});
//   @override
//   State<TimelinePage> createState() => _TimelinePageState();
// }

// class _TimelinePageState extends State<TimelinePage> {
//   final controller = TimelineController();
//   final scrollCtrl = ScrollController();

//   // One lane for simplicity. Add lanes: List<List<AudioClip>> if you want multitrack.
//   final clips = <AudioClip>[];

//   @override
//   void initState() {
//     super.initState();
//     // Seed with 3 demo clips
//     clips.addAll([
//       AudioClip(
//         id: 'a', name: 'GuitarVerse', path: 'guitar.wav',
//         startMs: 0, durationMs: 10000, fadeInMs: 300, fadeOutMs: 200,
//         waveform: _fakeWave(400),
//       ),
//       AudioClip(
//         id: 'b', name: 'Beat', path: 'beat.wav',
//         startMs: 11000, durationMs: 9000, fadeInMs: 0, fadeOutMs: 500,
//         waveform: _fakeWave(360),
//       ),
//       AudioClip(
//         id: 'c', name: 'Lead', path: 'lead.wav',
//         startMs: 21000, durationMs: 8000, fadeInMs: 150, fadeOutMs: 300,
//         waveform: _fakeWave(300),
//       ),
//     ]);
//     controller.ensureContentLength(clips.map((c) => c.endMs).fold<double>(0, max));
//   }

//   @override
//   void dispose() {
//     controller.dispose();
//     scrollCtrl.dispose();
//     super.dispose();
//   }

//   void _cutAtPlayhead() {
//     final ms = controller.playheadMs;
//     for (int i = 0; i < clips.length; i++) {
//       final c = clips[i];
//       if (ms > c.startMs && ms < c.endMs) {
//         final leftDur = ms - c.startMs;
//         final rightDur = c.endMs - ms;
//         final left = c.copy()..durationMs = leftDur;
//         final right = c.copy()
//           ..id = '${c.id}_r${DateTime.now().microsecondsSinceEpoch}'
//           ..startMs = ms
//           ..durationMs = rightDur
//           ..mediaOffsetMs = c.mediaOffsetMs + leftDur
//           ..fadeInMs = 0
//           ..fadeOutMs = 0
//           ..selected = false;
//         clips[i] = left;
//         clips.insert(i + 1, right);
//         controller.ensureContentLength(right.endMs);
//         setState(() {});
//         return;
//       }
//     }
//   }

//   void _deleteSelection() {
//     clips.removeWhere((c) => c.selected);
//     setState(() {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     final height = 220.0;

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('BandLab-like Audio Timeline (Flutter)'),
//         actions: [
//           IconButton(
//             tooltip: 'Cut at Playhead',
//             icon: const Icon(Icons.content_cut),
//             onPressed: _cutAtPlayhead,
//           ),
//           IconButton(
//             tooltip: 'Delete Selected',
//             icon: const Icon(Icons.delete_outline),
//             onPressed: _deleteSelection,
//           ),
//           const SizedBox(width: 8),
//         ],
//       ),
//       body: Column(
//         children: [
//           // Ruler + Zoom + Quantize
//           _TopBar(controller: controller),
//           // Timeline
//           Expanded(
//             child: AnimatedBuilder(
//               animation: controller,
//               builder: (_, __) {
//                 final contentW = controller.msToPx(controller.contentLengthMs);
//                 return Stack(
//                   children: [
//                     // Scrollable lane
//                     SingleChildScrollView(
//                       controller: scrollCtrl,
//                       scrollDirection: Axis.horizontal,
//                       child: SizedBox(
//                         width: max(contentW, MediaQuery.sizeOf(context).width),
//                         child: Column(
//                           children: [
//                             _Ruler(height: 28, controller: controller),
//                             _Lane(
//                               height: height,
//                               controller: controller,
//                               clips: clips,
//                               onChange: () {
//                                 controller.ensureContentLength(
//                                   clips.map((c) => c.endMs).fold<double>(0, max),
//                                 );
//                                 setState(() {});
//                               },
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                     // Playhead (stays put while content scrolls)
//                     IgnorePointer(
//                       child: Align(
//                         alignment: Alignment.topLeft,
//                         child: Padding(
//                           padding: const EdgeInsets.only(top: 28.0),
//                           child: _Playhead(height: height, controller: controller),
//                         ),
//                       ),
//                     ),
//                   ],
//                 );
//               },
//             ),
//           ),
//           // Transport
//           _TransportBar(
//             controller: controller,
//             onRecenter: () {
//               // center scroll to playhead
//               final x = controller.msToPx(controller.playheadMs) - MediaQuery.sizeOf(context).width/2;
//               scrollCtrl.animateTo(max(0, x), duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
//             },
//           ),
//           const SizedBox(height: 8),
//         ],
//       ),
//       backgroundColor: cs.surface,
//     );
//   }
// }

// /// ---------- Widgets ----------
// class _TopBar extends StatelessWidget {
//   final TimelineController controller;
//   const _TopBar({required this.controller});

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//       decoration: BoxDecoration(color: cs.surfaceVariant.withOpacity(0.35)),
//       child: Row(
//         children: [
//           const Text('Zoom'),
//           Expanded(
//             child: Slider(
//               min: 40, max: 320, value: controller.pixelsPerSecond,
//               onChanged: (v) => controller.setZoom(v),
//             ),
//           ),
//           const SizedBox(width: 12),
//           const Text('Quantize'),
//           const SizedBox(width: 8),
//           DropdownButton<double>(
//             value: controller.quantizeMs == 0 ? 0 : controller.quantizeMs,
//             items: const [
//               DropdownMenuItem(value: 0, child: Text('Off')),
//               DropdownMenuItem(value: 62.5, child: Text('1/16')),
//               DropdownMenuItem(value: 125, child: Text('1/8')),
//               DropdownMenuItem(value: 250, child: Text('1/4')),
//             ],
//             onChanged: (v) => controller.setQuantize(v ?? 0),
//           ),
//           const SizedBox(width: 12),
//         ],
//       ),
//     );
//   }
// }

// class _Ruler extends StatelessWidget {
//   final double height;
//   final TimelineController controller;
//   const _Ruler({required this.height, required this.controller});

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return SizedBox(
//       height: height,
//       child: CustomPaint(
//         painter: _RulerPainter(
//           pixelsPerSecond: controller.pixelsPerSecond,
//           color: cs.onSurface.withOpacity(0.35),
//           textColor: cs.onSurface.withOpacity(0.8),
//         ),
//         size: Size(controller.msToPx(controller.contentLengthMs), height),
//       ),
//     );
//   }
// }

// class _RulerPainter extends CustomPainter {
//   final double pixelsPerSecond;
//   final Color color;
//   final Color textColor;
//   _RulerPainter({required this.pixelsPerSecond, required this.color, required this.textColor});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final p = Paint()..color = color..strokeWidth = 1;
//     final tp = TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);
//     final major = pixelsPerSecond;        // 1 sec
//     final minor = pixelsPerSecond / 4;    // 250ms
//     for (double x = 0; x <= size.width; x += minor) {
//       final isMajor = (x / major - (x/major).round()).abs() < 0.001;
//       final h = isMajor ? 14.0 : 8.0;
//       canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), p);
//       if (isMajor) {
//         final sec = (x / pixelsPerSecond).round();
//         tp.text = TextSpan(text: '${sec}s', style: TextStyle(fontSize: 10, color: textColor));
//         tp.layout();
//         tp.paint(canvas, Offset(x + 3, size.height - 18));
//       }
//     }
//   }
//   @override
//   bool shouldRepaint(c) => true;
// }

// class _Lane extends StatefulWidget {
//   final double height;
//   final TimelineController controller;
//   final List<AudioClip> clips;
//   final VoidCallback onChange;
//   const _Lane({required this.height, required this.controller, required this.clips, required this.onChange});

//   @override
//   State<_Lane> createState() => _LaneState();
// }

// class _LaneState extends State<_Lane> {
//   String? _activeId;
//   _DragMode _mode = _DragMode.move;
//   double _dragStartMs = 0;
//   double _origStartMs = 0;
//   double _origDurMs = 0;
//   double _origOffMs = 0;
//   double _origFadeIn = 0;
//   double _origFadeOut = 0;

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Container(
//       height: widget.height,
//       color: cs.surfaceVariant.withOpacity(0.18),
//       child: Stack(
//         children: [
//           // Clips
//           for (final c in widget.clips)
//             Positioned(
//               left: widget.controller.msToPx(c.startMs),
//               top: 18,
//               width: max(1, widget.controller.msToPx(c.durationMs)),
//               height: widget.height - 36,
//               child: _ClipBox(
//                 clip: c,
//                 controller: widget.controller,
//                 selected: c.selected,
//                 onTap: () {
//                   setState(() { for (final x in widget.clips) x.selected = x == c; });
//                 },
//                 onPanStart: (localPos) {
//                   _activeId = c.id;
//                   _dragStartMs = _xToMs(localPos.dx);
//                   _origStartMs = c.startMs;
//                   _origDurMs = c.durationMs;
//                   _origOffMs = c.mediaOffsetMs;
//                   _origFadeIn = c.fadeInMs;
//                   _origFadeOut = c.fadeOutMs;
//                   _mode = _hitTest(localPos, c);
//                 },
//                 onPanUpdate: (localPos, deltaDx) {
//                   if (_activeId != c.id) return;
//                   final currMs = _xToMs(localPos.dx);
//                   final dxMs = currMs - _dragStartMs;

//                   switch (_mode) {
//                     case _DragMode.move:
//                       c.startMs = _snap(_origStartMs + dxMs, c);
//                       break;
//                     case _DragMode.trimL:
//                       final d = max(50.0, _origDurMs - dxMs);
//                       final delta = _origDurMs - d;
//                       c.durationMs = d;
//                       c.startMs = _snap(_origStartMs + delta, c);
//                       c.mediaOffsetMs = max(0, _origOffMs + delta);
//                       c.fadeInMs = min(c.fadeInMs, c.durationMs - 1);
//                       break;
//                     case _DragMode.trimR:
//                       c.durationMs = max(50.0, _origDurMs + dxMs);
//                       c.fadeOutMs = min(c.fadeOutMs, c.durationMs - 1);
//                       break;
//                     case _DragMode.fadeIn:
//                       c.fadeInMs = min(max(0, _origFadeIn + dxMs), c.durationMs - 1);
//                       break;
//                     case _DragMode.fadeOut:
//                       c.fadeOutMs = min(max(0, _origFadeOut - dxMs), c.durationMs - 1);
//                       break;
//                   }
//                   widget.controller.ensureContentLength(c.endMs);
//                   setState(() {});
//                   widget.onChange();
//                 },
//                 onPanEnd: () => _activeId = null,
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   double _xToMs(double dx) => widget.controller.pxToMs(dx);
//   double _snap(double ms, AudioClip me) {
//     final q = widget.controller.quantizeMs;
//     final snapPx = widget.controller.snapPx;

//     double bestMs = ms;
//     double bestDiffPx = double.infinity;

//     // Grid
//     if (q > 0) {
//       final qMs = (ms / q).round() * q;
//       final diffPx = (widget.controller.msToPx(ms) - widget.controller.msToPx(qMs)).abs();
//       if (diffPx < bestDiffPx && diffPx <= snapPx) {
//         bestMs = qMs; bestDiffPx = diffPx;
//       }
//     }
//     // Playhead
//     final phMs = widget.controller.playheadMs;
//     final diffPh = (widget.controller.msToPx(ms) - widget.controller.msToPx(phMs)).abs();
//     if (diffPh < bestDiffPx && diffPh <= snapPx) {
//       bestMs = phMs; bestDiffPx = diffPh;
//     }
//     // Other clip boundaries
//     for (final c in widget.clips) {
//       if (c == me) continue;
//       for (final target in [c.startMs, c.endMs]) {
//         final d = (widget.controller.msToPx(ms) - widget.controller.msToPx(target)).abs();
//         if (d < bestDiffPx && d <= snapPx) { bestMs = target; bestDiffPx = d; }
//       }
//     }
//     return max(0, bestMs);
//   }

//   _DragMode _hitTest(Offset pos, AudioClip c) {
//     const edge = 12.0;
//     final w = widget.controller.msToPx(c.durationMs);
//     // Fade handles near top corners (priority)
//     if (pos.dy < 18 && pos.dx < 22) return _DragMode.fadeIn;
//     if (pos.dy < 18 && pos.dx > w - 22) return _DragMode.fadeOut;
//     // Trim handles at bottom corners
//     if (pos.dy > 28 && pos.dx < edge) return _DragMode.trimL;
//     if (pos.dy > 28 && pos.dx > w - edge) return _DragMode.trimR;
//     return _DragMode.move;
//   }
// }

// enum _DragMode { move, trimL, trimR, fadeIn, fadeOut }

// class _ClipBox extends StatelessWidget {
//   final AudioClip clip;
//   final TimelineController controller;
//   final bool selected;
//   final VoidCallback onTap;
//   final void Function(Offset localPos) onPanStart;
//   final void Function(Offset localPos, double deltaDx) onPanUpdate;
//   final VoidCallback onPanEnd;

//   const _ClipBox({
//     required this.clip,
//     required this.controller,
//     required this.selected,
//     required this.onTap,
//     required this.onPanStart,
//     required this.onPanUpdate,
//     required this.onPanEnd,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     final w = max(1, controller.msToPx(clip.durationMs));
//     final h = (MediaQuery.sizeOf(context).height).clamp(100.0, 220.0) - 36;

//     return RepaintBoundary(
//       child: GestureDetector(
//         behavior: HitTestBehavior.opaque,
//         onTap: onTap,
//         onPanStart: (d) => onPanStart(d.localPosition),
//         onPanUpdate: (d) => onPanUpdate(d.localPosition, d.delta.dx),
//         onPanEnd: (_) => onPanEnd(),
//         child: Container(
//           width: w,
//           height: h,
//           decoration: BoxDecoration(
//             color: selected ? cs.primary.withOpacity(0.20) : cs.primary.withOpacity(0.12),
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(
//               color: selected ? cs.primary : cs.outlineVariant.withOpacity(0.5),
//               width: selected ? 2 : 1,
//             ),
//           ),
//           child: Stack(
//             children: [
//               // Waveform
//               Positioned.fill(
//                 child: CustomPaint(
//                   painter: _WavePainter(
//                     clip.waveform ?? _placeholderWave(w ~/ 4),
//                     color: cs.onSurface.withOpacity(0.7),
//                   ),
//                 ),
//               ),
//               // Trim ends shading (CapCut-ish)
//               _trimCaps(h, cs),
//               // Top labels
//               Positioned(
//                 left: 8, top: 6,
//                 child: Text(clip.name, style: TextStyle(fontSize: 12, color: cs.onSurface)),
//               ),
//               Positioned(
//                 right: 8, top: 6,
//                 child: Text('${(clip.durationMs/1000).toStringAsFixed(2)}s',
//                   style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.8))),
//               ),
//               // Fade overlays
//               Positioned.fill(child: _fadeOverlay(controller, clip, cs)),
//               // Handles
//               _handles(w, h, cs),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _trimCaps(double h, ColorScheme cs) {
//     return Positioned.fill(
//       child: Row(
//         children: [
//           Container(width: 6, decoration: BoxDecoration(
//             color: cs.primary.withOpacity(0.35),
//             borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
//           )),
//           Expanded(child: Container()),
//           Container(width: 6, decoration: BoxDecoration(
//             color: cs.primary.withOpacity(0.35),
//             borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
//           )),
//         ],
//       ),
//     );
//   }

//   Widget _fadeOverlay(TimelineController ctl, AudioClip c, ColorScheme cs) {
//     final w = ctl.msToPx(c.durationMs);
//     return Stack(children: [
//       // Fade-in gradient
//       Positioned(
//         left: 0, top: 0, bottom: 0, width: ctl.msToPx(c.fadeInMs),
//         child: IgnorePointer(child: DecoratedBox(
//           decoration: BoxDecoration(
//             gradient: LinearGradient(
//               begin: Alignment.centerLeft, end: Alignment.centerRight,
//               colors: [cs.surface, Colors.transparent],
//             ),
//           ),
//         )),
//       ),
//       // Fade-out gradient
//       Positioned(
//         right: 0, top: 0, bottom: 0, width: ctl.msToPx(c.fadeOutMs),
//         child: IgnorePointer(child: DecoratedBox(
//           decoration: BoxDecoration(
//             gradient: LinearGradient(
//               begin: Alignment.centerRight, end: Alignment.centerLeft,
//               colors: [cs.surface, Colors.transparent],
//             ),
//           ),
//         )),
//       ),
//       // Tiny diamonds for fade handles (visual cue)
//       Positioned(left: max(0, ctl.msToPx(c.fadeInMs) - 6), top: 6,
//         child: _diamond(cs.primary)),
//       Positioned(left: w - max(0, ctl.msToPx(c.fadeOutMs)) - 6, top: 6,
//         child: _diamond(cs.primary)),
//     ]);
//   }

//   Widget _diamond(Color color) => Transform.rotate(
//     angle: pi/4,
//     child: Container(width: 12, height: 12,
//       decoration: BoxDecoration(color: color.withOpacity(0.9), borderRadius: BorderRadius.circular(2)),
//     ),
//   );
// }

// class _WavePainter extends CustomPainter {
//   final List<double> samples; // [-1..1]
//   final Color color;
//   _WavePainter(this.samples, {required this.color});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final p = Paint()..color = color..strokeWidth = 1;
//     if (samples.isEmpty) return;
//     final step = max(1, (samples.length / size.width).floor());
//     final mid = size.height / 2;
//     for (int x = 0; x < size.width; x++) {
//       final idx = min(samples.length - 1, x * step);
//       final v = samples[idx].clamp(-1.0, 1.0);
//       final h = (v.abs() * (size.height * 0.9));
//       canvas.drawLine(Offset(x.toDouble(), mid - h/2), Offset(x.toDouble(), mid + h/2), p);
//     }
//   }
//   @override
//   bool shouldRepaint(covariant _WavePainter old) => old.samples != samples || old.color != color;
// }

// class _Playhead extends StatelessWidget {
//   final double height;
//   final TimelineController controller;
//   const _Playhead({required this.height, required this.controller});

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return AnimatedBuilder(
//       animation: controller,
//       builder: (_, __) {
//         final x = controller.msToPx(controller.playheadMs);
//         return Transform.translate(
//           offset: Offset(x, 0),
//           child: Container(
//             width: 2,
//             height: height,
//             color: cs.secondary,
//             child: Align(
//               alignment: Alignment.topCenter,
//               child: Container(
//                 width: 14, height: 12,
//                 decoration: BoxDecoration(
//                   color: cs.secondary, borderRadius: BorderRadius.circular(2),
//                 ),
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// class _TransportBar extends StatefulWidget {
//   final TimelineController controller;
//   final VoidCallback onRecenter;
//   const _TransportBar({required this.controller, required this.onRecenter});
//   @override
//   State<_TransportBar> createState() => _TransportBarState();
// }

// class _TransportBarState extends State<_TransportBar> with SingleTickerProviderStateMixin {
//   Ticker? _ticker;
//   bool _playing = false;
//   Duration _startWall = Duration.zero;
//   double _startMs = 0;

//   void _play() {
//     if (_playing) return;
//     _playing = true;
//     _startMs = widget.controller.playheadMs;
//     _startWall = Duration.zero;
//     _ticker = createTicker((elapsed) {
//       final ms = _startMs + (elapsed - _startWall).inMilliseconds.toDouble();
//       widget.controller.setPlayhead(ms);
//     })..start();
//     setState(() {});
//   }
//   void _pause() {
//     _ticker?.stop(); _ticker?.dispose(); _ticker = null;
//     _playing = false;
//     setState(() {});
//   }
//   void _stop() { _pause(); widget.controller.setPlayhead(0); }

//   @override
//   void dispose() { _ticker?.dispose(); super.dispose(); }

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Container(
//       padding: const EdgeInsets.all(10),
//       decoration: BoxDecoration(color: cs.surfaceVariant.withOpacity(0.3)),
//       child: Row(
//         children: [
//           IconButton(icon: const Icon(Icons.stop), onPressed: _stop),
//           IconButton(icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
//             onPressed: _playing ? _pause : _play),
//           const SizedBox(width: 12),
//           IconButton(icon: const Icon(Icons.center_focus_strong), onPressed: widget.onRecenter),
//           const SizedBox(width: 12),
//           AnimatedBuilder(
//             animation: widget.controller,
//             builder: (_, __) => Text(
//               _fmtMs(widget.controller.playheadMs),
//               style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
//             ),
//           ),
//           const Spacer(),
//           const Text('Click ruler to set playhead • Drag clip, edges = trim • Top diamonds = fades'),
//         ],
//       ),
//     );
//   }

//   String _fmtMs(double ms) {
//     final s = (ms / 1000).floor();
//     final r = (ms % 1000).round();
//     return '${s.toString().padLeft(2,'0')}:${(r/10).floor().toString().padLeft(2,'0')}';
//   }
// }

// /// ---------- Helpers ----------
// List<double> _fakeWave(int n) {
//   final r = Random(3);
//   return List<double>.generate(n, (i) {
//     final base = sin(i / 8) * 0.7 + sin(i / 17) * 0.3;
//     final noise = (r.nextDouble() - 0.5) * 0.2;
//     return (base + noise).clamp(-1.0, 1.0);
//   });
// }
// List<double> _placeholderWave(int n) => List<double>.generate(n, (i) => sin(i/7) * 0.6);


// Upgrades you can add quickly

// Multiple lanes: just render several _Lanes stacked, each with its own clips subset.

// Waveforms from files: precompute 512–2048 samples/clip in an isolate and drop into waveform.

// Crossfades: when two clips overlap, draw a cross-fade zone + schedule inverse fades in the engine.

// Snap strength toggle (tight/loose/off).

// Clip selection rectangle drag.