import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/models.dart';

const Color _kPitchLabText = Color(0xFFF4F4F4);
const Color _kPitchLabMutedText = Color(0xB8F4F4F4);
const Color _kPitchLabBorder = Color.fromRGBO(255, 255, 255, 0.12);
const Color _kPitchLabAccent = Color(0xFFE0B27F);

BoxDecoration _mixroomPitchLabSurfaceDecoration({double radius = 24}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.fromRGBO(87, 96, 106, 0.96),
        Color.fromRGBO(49, 58, 68, 0.96),
      ],
    ),
    border: Border.all(color: _kPitchLabBorder),
  );
}

class PitchBlobEditor extends StatefulWidget {
  const PitchBlobEditor({
    super.key,
    required this.clip,
    required this.bpm,
    required this.projectPlayheadMs,
    required this.isPlaying,
    required this.fullscreen,
    required this.onFullscreenChanged,
    required this.onClose,
    required this.onCommit,
    this.draftNotes,
    this.audioCorrectionMode = false,
    this.headerTitle,
    this.headerSubtitle,
    this.primaryActionLabel,
    this.onDraftChanged,
    this.onApplyAudio,
    this.onPreviewAudio,
    this.onStopPreviewAudio,
    this.onPausePreviewAudio,
    this.onResumePreviewAudio,
    this.onPreviewSingleNote,
    this.onPreviewNote,
    this.onScrubRequested,
    this.audioPreviewPositionStream,
    this.audioPreviewDurationStream,
    this.audioPreviewReady = false,
    this.audioPreviewInFlight = false,
    this.audioPreviewPlaying = false,
    this.allowCreateNotes = true,
    this.allowHarmony = true,
    this.allowSplit = true,
    this.waveformPeaks = const <double>[],
  });

  final AudioTrack clip;
  final double bpm;
  final double projectPlayheadMs;
  final bool isPlaying;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onClose;
  final Future<void> Function({
    required List<MidiNote> notes,
    required Map<String, double> instrumentParams,
    required String instrumentId,
    required String instrumentName,
  }) onCommit;
  final List<MidiNote>? draftNotes;
  final bool audioCorrectionMode;
  final String? headerTitle;
  final String? headerSubtitle;
  final String? primaryActionLabel;
  final ValueChanged<List<MidiNote>>? onDraftChanged;
  final Future<void> Function(List<MidiNote> notes)? onApplyAudio;
  final Future<void> Function(List<MidiNote> notes)? onPreviewAudio;
  final Future<void> Function()? onStopPreviewAudio;
  final Future<void> Function()? onPausePreviewAudio;
  final Future<void> Function()? onResumePreviewAudio;
  final Future<void> Function(MidiNote note)? onPreviewSingleNote;
  final Future<void> Function(int pitch, double velocity)? onPreviewNote;
  final void Function(double ms)? onScrubRequested;
  final Stream<Duration>? audioPreviewPositionStream;
  final Stream<Duration?>? audioPreviewDurationStream;
  final bool audioPreviewReady;
  final bool audioPreviewInFlight;
  final bool audioPreviewPlaying;
  final bool allowCreateNotes;
  final bool allowHarmony;
  final bool allowSplit;
  final List<double> waveformPeaks;

  @override
  State<PitchBlobEditor> createState() => _PitchBlobEditorState();
}

enum _PitchBlobTool { select, pitch, time, split }

enum _PitchBlobDragMode { move, trimStart, trimEnd }

enum _PitchBlobViewportGesture { idle, pan, zoom }

class _PitchBlobEditorState extends State<PitchBlobEditor> {
  static const double _keyboardWidth = 62.0;
  static const double _baseRowHeight = 26.0;
  static const double _basePixelsPerBeat = 92.0;
  static const double _blobHitInset = 9.0;
  static const double _blobTrimHitWidth = 18.0;
  static const int _defaultMinPitch = 36;
  static const int _defaultMaxPitch = 84;
  static const int _pitchHeadroom = 7;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final Set<String> _selectedIds = <String>{};

  late List<MidiNote> _notes;
  late List<MidiNote> _syncedClipNotes;
  _PitchBlobTool _tool = _PitchBlobTool.select;
  int _gridDivisionsPerBar = 16;
  bool _commitInFlight = false;
  bool _dirty = false;
  double _horizontalZoom = 1.0;
  double _verticalZoom = 1.0;
  double _scaleStartHorizontalZoom = 1.0;
  double _scaleStartVerticalZoom = 1.0;
  double _scaleStartHorizontalOffset = 0.0;
  double _scaleStartVerticalOffset = 0.0;
  Offset _scaleStartContentFocal = Offset.zero;
  Offset _scaleStartViewportFocal = Offset.zero;
  Size _editorViewportSize = Size.zero;
  _PitchBlobViewportGesture _viewportGesture = _PitchBlobViewportGesture.idle;

  String? _dragAnchorId;
  String? _notePreviewActionId;
  Offset? _notePreviewActionAnchor;
  _PitchBlobDragMode _dragMode = _PitchBlobDragMode.move;
  Offset? _dragStartLocal;
  Map<String, MidiNote>? _dragStartNotesById;
  OverlayEntry? _helpPopoverEntry;
  String? _pendingVerticalCenterSignature;
  int? _middlePanPointer;
  Offset? _middlePanPosition;

  double get _rowHeight => _baseRowHeight * _verticalZoom;
  double get _pixelsPerBeat => _basePixelsPerBeat * _horizontalZoom;

  String _t(String key) => L10n.translate(context, key);

  @override
  void initState() {
    super.initState();
    _syncFromClip();
  }

  @override
  void didUpdateWidget(covariant PitchBlobEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipChanged = oldWidget.clip.engineClipId != widget.clip.engineClipId;
    final notesChanged = _noteListsDiffer(_syncedClipNotes, _externalNotes);
    if (clipChanged || (!_dirty && notesChanged)) {
      _syncFromClip();
    }
  }

  @override
  void dispose() {
    _hideHelpPopover();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _syncFromClip() {
    _notes = _externalNotes.map((note) => note.copy()).toList();
    _notes.sort(_compareNotes);
    _syncedClipNotes = _externalNotes.map((note) => note.copy()).toList();
    _selectedIds.removeWhere((id) => !_notes.any((note) => note.id == id));
    if (_notePreviewActionId != null &&
        !_notes.any((note) => note.id == _notePreviewActionId)) {
      _notePreviewActionId = null;
      _notePreviewActionAnchor = null;
    }
    _dirty = false;
    _queueInitialVerticalCenter();
  }

  List<MidiNote> get _externalNotes =>
      widget.draftNotes ?? widget.clip.midiNotes;

  int _compareNotes(MidiNote a, MidiNote b) {
    final byStart = a.startBeat.compareTo(b.startBeat);
    if (byStart != 0) return byStart;
    final byPitch = b.pitch.compareTo(a.pitch);
    if (byPitch != 0) return byPitch;
    return a.id.compareTo(b.id);
  }

  bool _noteListsDiffer(List<MidiNote> previous, List<MidiNote> next) {
    if (previous.length != next.length) return true;
    for (int i = 0; i < previous.length; i++) {
      final a = previous[i];
      final b = next[i];
      if (a.id != b.id ||
          a.pitch != b.pitch ||
          (a.startBeat - b.startBeat).abs() > 0.00001 ||
          (a.lengthBeats - b.lengthBeats).abs() > 0.00001 ||
          (a.velocity - b.velocity).abs() > 0.00001) {
        return true;
      }
    }
    return false;
  }

  ({int min, int max}) get _pitchRange {
    if (_notes.isEmpty) return (min: _defaultMinPitch, max: _defaultMaxPitch);
    var minPitch = _notes.first.pitch;
    var maxPitch = _notes.first.pitch;
    for (final note in _notes) {
      minPitch = math.min(minPitch, note.pitch);
      maxPitch = math.max(maxPitch, note.pitch);
    }
    return (
      min: math.max(0, math.min(_defaultMinPitch, minPitch - _pitchHeadroom)),
      max: math.min(127, math.max(_defaultMaxPitch, maxPitch + _pitchHeadroom)),
    );
  }

  int get _pitchCount {
    final range = _pitchRange;
    return (range.max - range.min) + 1;
  }

  double get _durationBeats {
    var endBeat = 8.0;
    for (final note in _notes) {
      endBeat = math.max(endBeat, note.startBeat + note.lengthBeats + 1.0);
    }
    final clipBeats = _durationBeatsForClip(widget.clip);
    return math.max(endBeat, clipBeats + 1.0);
  }

  double _durationBeatsForClip(AudioTrack clip) {
    final tempo = _safeTempo;
    final msPerBeat = 60000.0 / tempo;
    final durationMs = math.max(
      0,
      (clip.trimEnd - clip.trimStart).inMilliseconds,
    );
    return durationMs / msPerBeat;
  }

  double get _safeTempo {
    final bpm = widget.bpm;
    if (!bpm.isFinite || bpm <= 0) return 120.0;
    return bpm.clamp(20.0, 320.0).toDouble();
  }

  double get _gridStepBeats => 4.0 / _gridDivisionsPerBar;

  Rect _rectForNote(MidiNote note) {
    final range = _pitchRange;
    final x = _keyboardWidth + note.startBeat * _pixelsPerBeat;
    final y = (range.max - note.pitch) * _rowHeight + 4.0;
    final w = math.max(26.0, note.lengthBeats * _pixelsPerBeat);
    final h = math.max(12.0, _rowHeight - 8.0);
    return Rect.fromLTWH(x, y, w, h);
  }

  int _pitchForY(double y) {
    final range = _pitchRange;
    final row = (y / _rowHeight).floor();
    return (range.max - row).clamp(range.min, range.max).toInt();
  }

  double _beatForX(double x) {
    return math.max(0.0, (x - _keyboardWidth) / _pixelsPerBeat);
  }

  double _quantizeBeat(double beat) {
    final step = _gridStepBeats;
    if (step <= 0) return beat;
    return (beat / step).roundToDouble() * step;
  }

  void _selectNote(String id, {bool additive = false}) {
    setState(() {
      if (!additive) _selectedIds.clear();
      if (additive && _selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _showNotePreviewAction(String id, {Offset? anchor}) {
    if (!_canPreviewSingleNote) return;
    setState(() {
      _notePreviewActionId = id;
      _notePreviewActionAnchor = anchor;
    });
  }

  bool get _canPreviewSingleNote =>
      widget.onPreviewSingleNote != null || widget.onPreviewNote != null;

  Future<void> _previewSingleNote(MidiNote note) async {
    final previewSingleNote = widget.onPreviewSingleNote;
    if (previewSingleNote != null) {
      await previewSingleNote(note.copy());
      return;
    }
    await widget.onPreviewNote?.call(note.pitch, note.velocity);
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_notes.map((note) => note.id));
    });
  }

  List<MidiNote> _targetNotes() {
    if (_selectedIds.isEmpty) return _notes;
    return _notes.where((note) => _selectedIds.contains(note.id)).toList();
  }

  void _markDirty() {
    _dirty = true;
    _notes.sort(_compareNotes);
  }

  Future<void> _commit({bool applyAudio = false}) async {
    final notes = _notes.map((note) => note.copy()).toList()
      ..sort(_compareNotes);
    widget.onDraftChanged?.call(notes.map((note) => note.copy()).toList());

    if (widget.audioCorrectionMode) {
      if (!applyAudio) return;
      if (_commitInFlight) return;
      _commitInFlight = true;
      if (mounted) setState(() {});
      try {
        await widget.onApplyAudio
            ?.call(notes.map((note) => note.copy()).toList());
        if (!mounted) return;
        setState(() {
          _syncedClipNotes = notes.map((note) => note.copy()).toList();
          _dirty = false;
        });
      } finally {
        _commitInFlight = false;
        if (mounted) setState(() {});
      }
      return;
    }

    if (_commitInFlight) return;
    _commitInFlight = true;
    try {
      await widget.onCommit(
        notes: notes,
        instrumentParams:
            Map<String, double>.from(widget.clip.instrumentParams),
        instrumentId: widget.clip.instrumentId,
        instrumentName: widget.clip.instrumentName,
      );
      if (!mounted) return;
      setState(() {
        _syncedClipNotes = notes.map((note) => note.copy()).toList();
        _dirty = false;
      });
    } finally {
      _commitInFlight = false;
    }
  }

  Future<void> _previewAudio() async {
    if (!widget.audioCorrectionMode || widget.onPreviewAudio == null) return;
    if (widget.audioPreviewInFlight) return;
    final notes = _notes.map((note) => note.copy()).toList()
      ..sort(_compareNotes);
    widget.onDraftChanged?.call(notes.map((note) => note.copy()).toList());
    await widget.onPreviewAudio!(notes);
  }

  Future<void> _stopPreviewAudio() async {
    await widget.onStopPreviewAudio?.call();
  }

  Future<void> _pausePreviewAudio() async {
    await widget.onPausePreviewAudio?.call();
  }

  Future<void> _resumePreviewAudio() async {
    await widget.onResumePreviewAudio?.call();
  }

  void _toggleHelpPopover() {
    if (_helpPopoverEntry != null) {
      _hideHelpPopover();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlayBox == null || !renderBox.hasSize) return;

    final panelTopLeft =
        renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final panelSize = renderBox.size;
    final body = _t(
      widget.audioCorrectionMode
          ? 'Drag notes to tune pitch or timing. Drag empty space to move around. Pinch to zoom. Preview before rendering audio.'
          : 'Drag notes to change pitch or timing. Drag empty space to move around. Pinch to zoom. Save when the melody feels right.',
    );

    _helpPopoverEntry = OverlayEntry(
      builder: (context) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideHelpPopover,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: panelTopLeft.dy + 42,
            right: math.max(
              12.0,
              overlayBox.size.width - panelTopLeft.dx - panelSize.width + 10.0,
            ),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 292),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A444E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.36),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _kPitchLabAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: _kPitchLabAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _t('Pitch Lab'),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: _kPitchLabText,
                                  fontSize: 12.25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 24,
                                height: 24,
                              ),
                              splashRadius: 13,
                              onPressed: _hideHelpPopover,
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.58),
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            body,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              color: Colors.white.withValues(alpha: 0.76),
                              fontSize: 11.8,
                              fontWeight: FontWeight.w600,
                              height: 1.36,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_helpPopoverEntry!);
  }

  void _hideHelpPopover() {
    _helpPopoverEntry?.remove();
    _helpPopoverEntry = null;
  }

  void _startViewportScale(ScaleStartDetails details) {
    _scaleStartHorizontalZoom = _horizontalZoom;
    _scaleStartVerticalZoom = _verticalZoom;
    _scaleStartHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    _scaleStartVerticalOffset =
        _verticalController.hasClients ? _verticalController.offset : 0.0;
    _scaleStartContentFocal = details.localFocalPoint;
    _scaleStartViewportFocal = Offset(
      details.localFocalPoint.dx - _scaleStartHorizontalOffset,
      details.localFocalPoint.dy - _scaleStartVerticalOffset,
    );
    _viewportGesture = details.pointerCount >= 2
        ? _PitchBlobViewportGesture.zoom
        : _PitchBlobViewportGesture.pan;
  }

  void _updateViewportScale(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      if (_viewportGesture == _PitchBlobViewportGesture.zoom) return;
      _viewportGesture = _PitchBlobViewportGesture.pan;
      _panViewport(details.focalPointDelta);
      return;
    }

    _viewportGesture = _PitchBlobViewportGesture.zoom;
    final scale = details.scale;
    if (!scale.isFinite || (scale - 1.0).abs() < 0.01) return;

    final startBeatPx = _basePixelsPerBeat * _scaleStartHorizontalZoom;
    final startRowPx = _baseRowHeight * _scaleStartVerticalZoom;

    final nextHorizontal =
        (_scaleStartHorizontalZoom * scale).clamp(0.55, 3.4).toDouble();
    final nextVertical =
        (_scaleStartVerticalZoom * scale).clamp(0.72, 2.3).toDouble();
    if ((nextHorizontal - _horizontalZoom).abs() < 0.001 &&
        (nextVertical - _verticalZoom).abs() < 0.001) {
      return;
    }

    final nextBeatPx = _basePixelsPerBeat * nextHorizontal;
    final nextRowPx = _baseRowHeight * nextVertical;
    double? nextHorizontalOffset;
    double? nextVerticalOffset;
    if (_horizontalController.hasClients && startBeatPx > 0.0) {
      final startBeat =
          (_scaleStartContentFocal.dx - _keyboardWidth) / startBeatPx;
      final nextContentX = _keyboardWidth + startBeat * nextBeatPx;
      nextHorizontalOffset = nextContentX - _scaleStartViewportFocal.dx;
    }
    if (_verticalController.hasClients && startRowPx > 0.0) {
      final startRow = _scaleStartContentFocal.dy / startRowPx;
      final nextContentY = startRow * nextRowPx;
      nextVerticalOffset = nextContentY - _scaleStartViewportFocal.dy;
    }

    setState(() {
      _horizontalZoom = nextHorizontal;
      _verticalZoom = nextVertical;
    });

    final viewport = _editorViewportSize;
    _jumpViewportTo(
      horizontal: nextHorizontalOffset,
      horizontalMax: viewport.width > 0
          ? math.max(
              0.0,
              _contentWidthForZoom(nextHorizontal, viewport.width) -
                  viewport.width,
            )
          : null,
      vertical: nextVerticalOffset,
      verticalMax: viewport.height > 0
          ? math.max(
              0.0,
              _contentHeightForZoom(nextVertical, viewport.height) -
                  viewport.height,
            )
          : null,
    );
  }

  void _endViewportScale() {
    _viewportGesture = _PitchBlobViewportGesture.idle;
  }

  void _panViewport(Offset focalDelta) {
    if (focalDelta == Offset.zero) return;
    _jumpViewportTo(
      horizontal: (_horizontalController.hasClients
              ? _horizontalController.offset
              : 0.0) -
          focalDelta.dx,
      vertical:
          (_verticalController.hasClients ? _verticalController.offset : 0.0) -
              focalDelta.dy,
    );
  }

  void _scrollViewportBy({double horizontal = 0.0, double vertical = 0.0}) {
    if (horizontal == 0.0 && vertical == 0.0) return;
    _jumpViewportTo(
      horizontal: _horizontalController.hasClients
          ? _horizontalController.offset + horizontal
          : null,
      vertical: _verticalController.hasClients
          ? _verticalController.offset + vertical
          : null,
    );
  }

  void _handleViewportPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final shiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    final delta = event.scrollDelta;
    if (shiftPressed) {
      _scrollViewportBy(horizontal: delta.dx + delta.dy);
      return;
    }
    _scrollViewportBy(horizontal: delta.dx, vertical: delta.dy);
  }

  void _handleViewportPointerDown(PointerDownEvent event) {
    if ((event.buttons & kMiddleMouseButton) == 0) return;
    _middlePanPointer = event.pointer;
    _middlePanPosition = event.position;
  }

  void _handleViewportPointerMove(PointerMoveEvent event) {
    if (_middlePanPointer != event.pointer || _middlePanPosition == null) return;
    final delta = event.position - _middlePanPosition!;
    _middlePanPosition = event.position;
    _panViewport(delta);
  }

  void _endMiddleViewportPan(PointerEvent event) {
    if (_middlePanPointer != event.pointer) return;
    _middlePanPointer = null;
    _middlePanPosition = null;
  }

  double _contentWidthForZoom(double horizontalZoom, double viewportWidth) {
    return math.max(
      viewportWidth,
      _keyboardWidth +
          _durationBeats * _basePixelsPerBeat * horizontalZoom +
          180.0,
    );
  }

  double _contentHeightForZoom(double verticalZoom, double viewportHeight) {
    return math.max(
      viewportHeight,
      _pitchCount * _baseRowHeight * verticalZoom,
    );
  }

  void _queueInitialVerticalCenter() {
    if (_notes.isEmpty) return;
    final signature = widget.clip.engineClipId >= 0
        ? 'engine:${widget.clip.engineClipId}:${_notes.length}:${_notes.first.id}:${_notes.last.id}'
        : 'clip:${widget.clip.clipId}:${_notes.length}:${_notes.first.id}:${_notes.last.id}';
    _pendingVerticalCenterSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingVerticalCenterSignature != signature) return;
      _centerVerticalScrollOnNotes();
      if (_pendingVerticalCenterSignature == signature) {
        _pendingVerticalCenterSignature = null;
      }
    });
  }

  void _centerVerticalScrollOnNotes() {
    if (_notes.isEmpty || !_verticalController.hasClients) return;
    final position = _verticalController.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;

    var top = double.infinity;
    var bottom = -double.infinity;
    for (final note in _notes) {
      final rect = _rectForNote(note);
      top = math.min(top, rect.top);
      bottom = math.max(bottom, rect.bottom);
    }
    if (!top.isFinite || !bottom.isFinite) return;

    final noteCenter = (top + bottom) / 2.0;
    final nextOffset = noteCenter - (position.viewportDimension / 2.0);
    position.jumpTo(
      nextOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _jumpViewportTo({
    double? horizontal,
    double? vertical,
    double? horizontalMax,
    double? verticalMax,
  }) {
    if (horizontal != null && _horizontalController.hasClients) {
      final max =
          horizontalMax ?? _horizontalController.position.maxScrollExtent;
      _horizontalController.jumpTo(
        horizontal.clamp(
          _horizontalController.position.minScrollExtent,
          max,
        ),
      );
    }
    if (vertical != null && _verticalController.hasClients) {
      final max = verticalMax ?? _verticalController.position.maxScrollExtent;
      _verticalController.jumpTo(
        vertical.clamp(
          _verticalController.position.minScrollExtent,
          max,
        ),
      );
    }
  }

  void _zoomViewport(double factor) {
    if (!factor.isFinite || factor <= 0.0) return;
    setState(() {
      _horizontalZoom = (_horizontalZoom * factor).clamp(0.55, 3.4).toDouble();
      _verticalZoom = (_verticalZoom * factor).clamp(0.72, 2.3).toDouble();
    });
  }

  void _startNoteDrag(
    MidiNote note,
    DragStartDetails details, {
    double hitInset = 0.0,
  }) {
    final rect = _rectForNote(note);
    final localX = (details.localPosition.dx - hitInset).clamp(0.0, rect.width);
    final nearStart = localX <= _blobTrimHitWidth;
    final nearEnd = rect.width - localX <= _blobTrimHitWidth;
    _dragMode = nearStart
        ? _PitchBlobDragMode.trimStart
        : nearEnd
            ? _PitchBlobDragMode.trimEnd
            : _PitchBlobDragMode.move;
    _notePreviewActionId = null;
    _notePreviewActionAnchor = null;
    _dragAnchorId = note.id;
    _dragStartLocal = details.globalPosition;
    if (!_selectedIds.contains(note.id)) {
      _selectedIds
        ..clear()
        ..add(note.id);
    }
    _dragStartNotesById = <String, MidiNote>{
      for (final item in _notes.where((n) => _selectedIds.contains(n.id)))
        item.id: item.copy(),
    };
  }

  void _updateNoteDrag(DragUpdateDetails details) {
    final start = _dragStartLocal;
    final starts = _dragStartNotesById;
    if (start == null || starts == null || starts.isEmpty) return;
    final delta = details.globalPosition - start;
    final beatDelta = delta.dx / _pixelsPerBeat;
    final pitchDelta = (delta.dy / _rowHeight).round();
    setState(() {
      for (final note in _notes) {
        final base = starts[note.id];
        if (base == null) continue;
        switch (_dragMode) {
          case _PitchBlobDragMode.move:
            if (_tool != _PitchBlobTool.pitch) {
              note.startBeat = math.max(0.0, base.startBeat + beatDelta);
            }
            if (_tool != _PitchBlobTool.time) {
              note.pitch = (base.pitch - pitchDelta).clamp(0, 127).toInt();
            }
            break;
          case _PitchBlobDragMode.trimStart:
            final endBeat = base.startBeat + base.lengthBeats;
            final nextStart = math.max(0.0, base.startBeat + beatDelta);
            note.startBeat = math.min(nextStart, endBeat - 0.0625);
            note.lengthBeats = math.max(0.0625, endBeat - note.startBeat);
            break;
          case _PitchBlobDragMode.trimEnd:
            note.lengthBeats = math.max(0.0625, base.lengthBeats + beatDelta);
            break;
        }
      }
      _markDirty();
    });
  }

  Future<void> _endNoteDrag() async {
    final anchorId = _dragAnchorId;
    _dragAnchorId = null;
    _dragStartLocal = null;
    _dragStartNotesById = null;
    MidiNote? note;
    if (anchorId != null) {
      for (final item in _notes) {
        if (item.id == anchorId) {
          note = item;
          break;
        }
      }
    }
    if (note != null) {
      unawaited(widget.onPreviewNote?.call(note.pitch, note.velocity));
    }
    await _commit();
  }

  void _addNoteAt(Offset localPosition) {
    if (!widget.allowCreateNotes) return;
    if (localPosition.dx < _keyboardWidth) return;
    final startBeat = _quantizeBeat(_beatForX(localPosition.dx));
    final pitch = _pitchForY(localPosition.dy);
    final note = MidiNote(
      id: 'pitch_lab_${DateTime.now().microsecondsSinceEpoch}_${_notes.length}',
      pitch: pitch,
      startBeat: startBeat,
      lengthBeats: math.max(_gridStepBeats * 2.0, 0.25),
      velocity: 0.82,
    );
    setState(() {
      _notes.add(note);
      _selectedIds
        ..clear()
        ..add(note.id);
      _markDirty();
    });
    unawaited(widget.onPreviewNote?.call(note.pitch, note.velocity));
    unawaited(_commit());
  }

  Future<void> _quantizeTiming() async {
    setState(() {
      for (final note in _targetNotes()) {
        note.startBeat = _quantizeBeat(note.startBeat);
        note.lengthBeats = math.max(0.0625, _quantizeBeat(note.lengthBeats));
      }
      _markDirty();
    });
    await _commit();
  }

  Future<void> _fitSelectedToScale() async {
    const scale = <int>{0, 2, 4, 5, 7, 9, 11};
    int nearestScalePitch(int pitch) {
      var best = pitch;
      var bestDistance = 128;
      for (int candidate = math.max(0, pitch - 6);
          candidate <= math.min(127, pitch + 6);
          candidate++) {
        if (!scale.contains(candidate % 12)) continue;
        final distance = (candidate - pitch).abs();
        if (distance < bestDistance) {
          best = candidate;
          bestDistance = distance;
        }
      }
      return best;
    }

    setState(() {
      for (final note in _targetNotes()) {
        note.pitch = nearestScalePitch(note.pitch);
      }
      _markDirty();
    });
    await _commit();
  }

  Future<void> _transposeSelected(int semitones) async {
    setState(() {
      for (final note in _targetNotes()) {
        note.pitch = (note.pitch + semitones).clamp(0, 127).toInt();
      }
      _markDirty();
    });
    if (_targetNotes().isNotEmpty) {
      final note = _targetNotes().first;
      unawaited(widget.onPreviewNote?.call(note.pitch, note.velocity));
    }
    await _commit();
  }

  Future<void> _addHarmony(int semitones) async {
    final source = _targetNotes();
    if (source.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final additions = <MidiNote>[];
    for (int i = 0; i < source.length; i++) {
      final note = source[i];
      additions.add(
        MidiNote(
          id: 'pitch_lab_harmony_${now}_$i',
          pitch: (note.pitch + semitones).clamp(0, 127).toInt(),
          startBeat: note.startBeat,
          lengthBeats: note.lengthBeats,
          velocity: (note.velocity * 0.76).clamp(0.1, 1.0).toDouble(),
        ),
      );
    }
    setState(() {
      _notes.addAll(additions);
      _selectedIds
        ..clear()
        ..addAll(additions.map((note) => note.id));
      _markDirty();
    });
    await _commit();
  }

  Future<void> _splitSelected() async {
    final targets =
        _targetNotes().where((note) => note.lengthBeats >= 0.25).toList();
    if (targets.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final additions = <MidiNote>[];
    setState(() {
      for (int i = 0; i < targets.length; i++) {
        final note = targets[i];
        final half = note.lengthBeats / 2.0;
        note.lengthBeats = half;
        additions.add(
          MidiNote(
            id: 'pitch_lab_split_${now}_$i',
            pitch: note.pitch,
            startBeat: note.startBeat + half,
            lengthBeats: half,
            velocity: note.velocity,
          ),
        );
      }
      _notes.addAll(additions);
      _selectedIds
        ..clear()
        ..addAll(additions.map((note) => note.id));
      _markDirty();
    });
    await _commit();
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    setState(() {
      _notes.removeWhere((note) => _selectedIds.contains(note.id));
      _selectedIds.clear();
      _markDirty();
    });
    await _commit();
  }

  void _scrubToBeat(double beat) {
    final msPerBeat = 60000.0 / _safeTempo;
    final timelineMs = widget.clip.offset * 1000.0 + beat * msPerBeat;
    widget.onScrubRequested?.call(math.max(0.0, timelineMs));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: _mixroomPitchLabSurfaceDecoration(),
        child: Column(
          children: <Widget>[
            _buildHeader(),
            _buildToolbars(),
            Expanded(child: _buildEditor()),
            if (widget.audioCorrectionMode) _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = widget.headerTitle ??
        (widget.clip.label.trim().isEmpty
            ? _t('Pitch Lab')
            : widget.clip.label.trim());
    final subtitle = widget.headerSubtitle ??
        '${_notes.length} ${_t(_notes.length == 1 ? 'note' : 'notes')}';
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _kPitchLabAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: _kPitchLabAccent.withValues(alpha: 0.20),
              ),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: _kPitchLabAccent,
              size: 15,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kPitchLabText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kPitchLabMutedText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          _buildIconAction(
            icon: Icons.info_outline_rounded,
            tooltip: _t('Pitch Lab help'),
            onTap: _toggleHelpPopover,
          ),
          _buildIconAction(
            icon: widget.fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip:
                widget.fullscreen ? _t('Exit fullscreen') : _t('Fullscreen'),
            onTap: () => widget.onFullscreenChanged(!widget.fullscreen),
          ),
          _buildIconAction(
            icon: Icons.close_rounded,
            tooltip: _t('Close'),
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbars() {
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.065),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _buildToolGroup(<Widget>[
            _buildToolButton(
              tool: _PitchBlobTool.select,
              icon: Icons.ads_click_rounded,
              label: _t('Move'),
              tooltip: _t('Move notes in pitch and time'),
            ),
            _buildToolButton(
              tool: _PitchBlobTool.pitch,
              icon: Icons.height_rounded,
              label: _t('Pitch Only'),
              tooltip: _t('Drag notes vertically only'),
            ),
            _buildToolButton(
              tool: _PitchBlobTool.time,
              icon: Icons.keyboard_tab_rounded,
              label: _t('Time Only'),
              tooltip: _t('Drag notes horizontally only'),
            ),
            if (widget.allowSplit)
              _buildToolButton(
                tool: _PitchBlobTool.split,
                icon: Icons.call_split_rounded,
                label: _t('Split'),
                onTap: () => unawaited(_splitSelected()),
              ),
          ]),
          const SizedBox(width: 7),
          _buildCommandButton(
            icon: Icons.select_all_rounded,
            label: _t('All'),
            onTap: _selectAll,
          ),
          _buildCommandButton(
            icon: Icons.grid_4x4_rounded,
            label: _t('Quantize'),
            onTap: () => unawaited(_quantizeTiming()),
          ),
          _buildCommandButton(
            icon: Icons.check_rounded,
            label: _t('C Major'),
            tooltip: _t('Snap selected notes to C major'),
            onTap: () => unawaited(_fitSelectedToScale()),
          ),
          _buildCommandButton(
            icon: Icons.arrow_downward_rounded,
            label: '-1',
            tooltip: _t('Transpose selected notes down one semitone'),
            onTap: () => unawaited(_transposeSelected(-1)),
          ),
          _buildCommandButton(
            icon: Icons.arrow_upward_rounded,
            label: '+1',
            tooltip: _t('Transpose selected notes up one semitone'),
            onTap: () => unawaited(_transposeSelected(1)),
          ),
          _buildCommandButton(
            icon: Icons.zoom_in_rounded,
            label: '',
            tooltip: _t('Zoom in'),
            onTap: () => _zoomViewport(1.18),
          ),
          _buildCommandButton(
            icon: Icons.zoom_out_rounded,
            label: '',
            tooltip: _t('Zoom out'),
            onTap: () => _zoomViewport(1 / 1.18),
          ),
          if (widget.allowHarmony)
            _buildCommandButton(
              icon: Icons.library_music_rounded,
              label: _t('+3rd'),
              onTap: () => unawaited(_addHarmony(3)),
            ),
          if (widget.allowHarmony)
            _buildCommandButton(
              icon: Icons.library_music_rounded,
              label: _t('+5th'),
              onTap: () => unawaited(_addHarmony(7)),
            ),
          if (!widget.audioCorrectionMode)
            _buildCommandButton(
              icon: Icons.delete_outline_rounded,
              label: _t('Delete'),
              danger: true,
              onTap: () => unawaited(_deleteSelected()),
            ),
          _buildGridControl(),
          if (!widget.audioCorrectionMode) _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildToolGroup(List<Widget> children) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _buildToolButton({
    required _PitchBlobTool tool,
    required IconData icon,
    required String label,
    String? tooltip,
    VoidCallback? onTap,
  }) {
    final selected = _tool == tool;
    return _PitchLabButton(
      icon: icon,
      label: label,
      tooltip: tooltip,
      selected: selected,
      onTap: onTap ??
          () {
            setState(() => _tool = tool);
          },
    );
  }

  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    String? tooltip,
    required VoidCallback? onTap,
    bool selected = false,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: _PitchLabButton(
        icon: icon,
        label: label,
        tooltip: tooltip,
        selected: selected,
        danger: danger,
        onTap: onTap,
      ),
    );
  }

  Widget _buildGridControl() {
    return Container(
      height: 28,
      margin: const EdgeInsets.only(right: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _gridDivisionsPerBar,
          isDense: true,
          dropdownColor: const Color(0xFF3A444E),
          iconEnabledColor: _kPitchLabMutedText,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            color: _kPitchLabText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem<int>(value: 4, child: Text('1/4')),
            DropdownMenuItem<int>(value: 8, child: Text('1/8')),
            DropdownMenuItem<int>(value: 16, child: Text('1/16')),
            DropdownMenuItem<int>(value: 32, child: Text('1/32')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _gridDivisionsPerBar = value);
          },
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _dirty ? 1.0 : 0.62,
      child: _PitchLabButton(
        icon:
            _commitInFlight ? Icons.hourglass_top_rounded : Icons.save_rounded,
        label: _commitInFlight
            ? (widget.audioCorrectionMode ? _t('Rendering') : _t('Saving'))
            : (widget.primaryActionLabel ??
                (widget.audioCorrectionMode ? _t('Render') : _t('Save'))),
        selected: _dirty,
        onTap: () => unawaited(_commit(applyAudio: true)),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.065),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildPreviewTransportButton(),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildSaveButton()),
        ],
      ),
    );
  }

  Widget _buildPreviewTransportButton() {
    final durationStream = widget.audioPreviewDurationStream;
    final positionStream = widget.audioPreviewPositionStream;
    return StreamBuilder<Duration?>(
      stream: durationStream,
      builder: (context, durationSnapshot) {
        return StreamBuilder<Duration>(
          stream: positionStream,
          builder: (context, positionSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final position = positionSnapshot.data ?? Duration.zero;
            final durationMs = duration.inMilliseconds;
            final progress = durationMs <= 0
                ? 0.0
                : (position.inMilliseconds / durationMs)
                    .clamp(0.0, 1.0)
                    .toDouble();
            final playing = widget.audioPreviewPlaying;
            final ready = widget.audioPreviewReady || playing;
            if (ready) {
              return Row(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: _buildCompactTransportButton(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      label: playing ? _t('Pause') : _t('Resume'),
                      tooltip:
                          playing ? _t('Pause preview') : _t('Resume preview'),
                      selected: playing,
                      progress: progress,
                      onTap: playing
                          ? () => unawaited(_pausePreviewAudio())
                          : () => unawaited(_resumePreviewAudio()),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    flex: 4,
                    child: _buildCompactTransportButton(
                      icon: Icons.stop_rounded,
                      label: _t('Stop'),
                      tooltip: _t('Stop preview'),
                      selected: true,
                      onTap: () => unawaited(_stopPreviewAudio()),
                    ),
                  ),
                ],
              );
            }
            return _PitchLabButton(
              icon: widget.audioPreviewInFlight
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
              label:
                  widget.audioPreviewInFlight ? _t('Preparing') : _t('Preview'),
              tooltip: _t('Preview tuned audio'),
              selected: false,
              onTap: widget.audioPreviewInFlight
                  ? null
                  : () => unawaited(_previewAudio()),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactTransportButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool selected,
    required VoidCallback? onTap,
    double? progress,
  }) {
    return _PitchLabButton(
      icon: icon,
      label: label,
      tooltip: tooltip,
      selected: selected,
      progress: progress,
      compact: true,
      onTap: onTap,
    );
  }

  Widget _buildIconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        splashRadius: 18,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white.withValues(alpha: 0.78), size: 19),
      ),
    );
  }

  Widget _buildEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _editorViewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final contentWidth =
            _contentWidthForZoom(_horizontalZoom, constraints.maxWidth);
        final contentHeight =
            _contentHeightForZoom(_verticalZoom, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _handleViewportPointerSignal,
          onPointerDown: _handleViewportPointerDown,
          onPointerMove: _handleViewportPointerMove,
          onPointerUp: _endMiddleViewportPan,
          onPointerCancel: _endMiddleViewportPan,
          onPointerPanZoomUpdate: (event) => _panViewport(event.panDelta),
          child: Stack(
            children: <Widget>[
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.right,
                  thickness: 5,
                  radius: const Radius.circular(999),
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    physics: const NeverScrollableScrollPhysics(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _startViewportScale,
                      onScaleUpdate: _updateViewportScale,
                      onScaleEnd: (_) => _endViewportScale(),
                      onDoubleTapDown: (details) =>
                          _addNoteAt(details.localPosition),
                      onTapDown: (details) {
                        if (details.localPosition.dx > _keyboardWidth) {
                          _scrubToBeat(_beatForX(details.localPosition.dx));
                        }
                      },
                      child: SizedBox(
                        width: contentWidth,
                        height: contentHeight,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(child: _buildGridPaint()),
                            for (final note in _notes) _buildBlob(note),
                            _buildNotePreviewAction(
                                contentWidth, contentHeight),
                            if (_notes.isEmpty)
                              Positioned.fill(
                                child: Center(
                                  child: Text(
                                    widget.allowCreateNotes
                                        ? _t(
                                            'Double-tap to place the first note',
                                          )
                                        : _t('No editable notes detected'),
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      color:
                                          Colors.white.withValues(alpha: 0.42),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
            Positioned(
              left: _keyboardWidth + 10,
              right: 16,
              bottom: 3,
              child: _PitchLabHorizontalScrollIndicator(
                controller: _horizontalController,
              ),
            ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGridPaint() {
    final previewPositionStream =
        widget.audioPreviewPlaying ? widget.audioPreviewPositionStream : null;
    if (previewPositionStream == null) {
      return _buildGridPaintForPosition(null);
    }
    return StreamBuilder<Duration>(
      stream: previewPositionStream,
      builder: (context, snapshot) =>
          _buildGridPaintForPosition(snapshot.data ?? Duration.zero),
    );
  }

  Widget _buildGridPaintForPosition(Duration? previewPosition) {
    return CustomPaint(
      painter: _PitchBlobGridPainter(
        pitchRange: _pitchRange,
        pitchCount: _pitchCount,
        rowHeight: _rowHeight,
        keyboardWidth: _keyboardWidth,
        pixelsPerBeat: _pixelsPerBeat,
        durationBeats: _durationBeats,
        gridStepBeats: _gridStepBeats,
        playheadBeat: _playheadBeatForPreviewPosition(previewPosition),
        isPlaying: widget.isPlaying || widget.audioPreviewPlaying,
        waveformPeaks: widget.waveformPeaks,
        waveformWidthBeats: _durationBeatsForClip(widget.clip),
        waveformTrimStartMs: widget.clip.trimStart.inMilliseconds.toDouble(),
        waveformTrimEndMs: widget.clip.trimEnd.inMilliseconds.toDouble(),
        waveformFullDurationMs:
            widget.clip.audioDuration.inMilliseconds.toDouble(),
      ),
    );
  }

  double? _playheadBeatForPreviewPosition(Duration? previewPosition) {
    if (widget.audioCorrectionMode &&
        widget.audioPreviewPlaying &&
        previewPosition != null) {
      return previewPosition.inMilliseconds / (60000.0 / _safeTempo);
    }
    return _playheadBeat;
  }

  double? get _playheadBeat {
    final localMs = widget.projectPlayheadMs - widget.clip.offset * 1000.0;
    if (!localMs.isFinite || localMs < 0) return null;
    return localMs / (60000.0 / _safeTempo);
  }

  Widget _buildBlob(MidiNote note) {
    final rect = _rectForNote(note);
    final selected = _selectedIds.contains(note.id);
    final color = _colorForPitch(note.pitch);
    final hitLeftInset = rect.left <= _keyboardWidth + _blobHitInset
        ? math.max(0.0, rect.left - _keyboardWidth)
        : _blobHitInset;
    final hitTopInset =
        rect.top <= _blobHitInset ? math.max(0.0, rect.top) : _blobHitInset;
    final hitLeft = math.max(_keyboardWidth, rect.left - _blobHitInset);
    final hitTop = math.max(0.0, rect.top - _blobHitInset);
    return Positioned(
      left: hitLeft,
      top: hitTop,
      width: rect.width + hitLeftInset + _blobHitInset,
      height: rect.height + hitTopInset + _blobHitInset,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final contentPoint = hitLeft + details.localPosition.dx;
          final contentY = hitTop + details.localPosition.dy;
          _notePreviewActionAnchor = Offset(
            contentPoint.clamp(rect.left, rect.right).toDouble(),
            contentY.clamp(rect.top, rect.bottom).toDouble(),
          );
        },
        onTap: () {
          _selectNote(note.id);
          _showNotePreviewAction(note.id, anchor: _notePreviewActionAnchor);
        },
        onLongPress: () => _selectNote(note.id, additive: true),
        onPanStart: (details) => _startNoteDrag(
          note,
          details,
          hitInset: hitLeftInset,
        ),
        onPanUpdate: _updateNoteDrag,
        onPanEnd: (_) => unawaited(_endNoteDrag()),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            hitLeftInset,
            hitTopInset,
            _blobHitInset,
            _blobHitInset,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 90),
            scale: selected ? 1.03 : 1.0,
            child: CustomPaint(
              painter: _PitchBlobPainter(
                color: color,
                selected: selected,
                velocity: note.velocity,
                label: _noteNameForPitch(note.pitch),
                showHandles: selected,
                tool: _tool,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotePreviewAction(double contentWidth, double contentHeight) {
    if (!_canPreviewSingleNote || _notePreviewActionId == null) {
      return const SizedBox.shrink();
    }
    MidiNote? note;
    for (final item in _notes) {
      if (item.id == _notePreviewActionId) {
        note = item;
        break;
      }
    }
    if (note == null) return const SizedBox.shrink();

    final rect = _rectForNote(note);
    const size = 30.0;
    final canPlaceAbove = rect.top >= size + 8.0;
    final top = (canPlaceAbove ? rect.top - size - 6.0 : rect.bottom + 6.0)
        .clamp(0.0, math.max(0.0, contentHeight - size))
        .toDouble();
    final anchorX = (_notePreviewActionAnchor?.dx ?? rect.left + 12.0)
        .clamp(rect.left, rect.right)
        .toDouble();
    final left = (anchorX - (size / 2.0))
        .clamp(
          _keyboardWidth + 2.0,
          math.max(_keyboardWidth + 2.0, contentWidth - size),
        )
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Tooltip(
        message: _t('Preview note'),
        child: Semantics(
          button: true,
          label: _t('Preview note'),
          onTap: () => unawaited(_previewSingleNote(note!)),
          child: Listener(
            key: const ValueKey<String>('pitch-lab-note-preview-action'),
            behavior: HitTestBehavior.opaque,
            onPointerUp: (_) => unawaited(_previewSingleNote(note!)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF3A444E).withValues(alpha: 0.98),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _kPitchLabAccent.withValues(alpha: 0.62),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _kPitchLabAccent.withValues(alpha: 0.22),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.volume_up_rounded,
                  size: 16,
                  color: _kPitchLabAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorForPitch(int pitch) {
    const colors = <Color>[
      Color(0xFF5CD8FF),
      Color(0xFF56E6B5),
      Color(0xFFFFCE5C),
      Color(0xFFFF8F67),
      Color(0xFFE78AFF),
      Color(0xFF9FA8FF),
    ];
    return colors[pitch.abs() % colors.length];
  }

  String _noteNameForPitch(int pitch) {
    const names = <String>[
      'C',
      'C#',
      'D',
      'Eb',
      'E',
      'F',
      'F#',
      'G',
      'Ab',
      'A',
      'Bb',
      'B',
    ];
    final clamped = pitch.clamp(0, 127).toInt();
    final octave = (clamped ~/ 12) - 1;
    return '${names[clamped % 12]}$octave';
  }
}

class _PitchLabButton extends StatelessWidget {
  const _PitchLabButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.selected = false,
    this.danger = false,
    this.progress,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool selected;
  final bool danger;
  final double? progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = danger
        ? const Color(0xFFFF837A)
        : selected
            ? _kPitchLabAccent
            : _kPitchLabMutedText;
    final progressValue = progress?.clamp(0.0, 1.0).toDouble();
    final contentPadding = EdgeInsets.symmetric(
      horizontal: label.isEmpty
          ? 8
          : compact
              ? 7
              : 9,
    );
    final body = Opacity(
      opacity: enabled ? 1.0 : 0.48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 28,
            decoration: BoxDecoration(
              color: selected
                  ? _kPitchLabAccent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? _kPitchLabAccent.withValues(alpha: 0.40)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: compact ? StackFit.expand : StackFit.passthrough,
                children: <Widget>[
                  if (progressValue != null)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progressValue,
                        child: ColoredBox(
                          color: _kPitchLabAccent.withValues(alpha: 0.20),
                        ),
                      ),
                    ),
                  Padding(
                    padding: contentPadding,
                    child: Row(
                      mainAxisSize:
                          compact ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(icon, color: accent, size: compact ? 13 : 14),
                        if (label.isNotEmpty) ...<Widget>[
                          SizedBox(width: compact ? 4 : 5),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: danger
                                    ? accent
                                    : _kPitchLabText,
                                fontSize: compact ? 10.5 : 11,
                                fontWeight: FontWeight.w700,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (progressValue != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _kPitchLabAccent.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final message = tooltip ?? (label.isEmpty ? null : label);
    if (message == null || message.trim().isEmpty) return body;
    return Tooltip(message: message, child: body);
  }
}

class _PitchLabHorizontalScrollIndicator extends StatefulWidget {
  const _PitchLabHorizontalScrollIndicator({required this.controller});

  final ScrollController controller;

  @override
  State<_PitchLabHorizontalScrollIndicator> createState() =>
      _PitchLabHorizontalScrollIndicatorState();
}

class _PitchLabHorizontalScrollIndicatorState
    extends State<_PitchLabHorizontalScrollIndicator> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          if (!trackWidth.isFinite || trackWidth <= 0) {
            return const SizedBox.shrink();
          }
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              if (!widget.controller.hasClients) return const SizedBox.shrink();
              final position = widget.controller.position;
              final maxScroll = position.maxScrollExtent;
              if (maxScroll <= 0) return const SizedBox.shrink();

              final viewport = position.viewportDimension;
              final content = viewport + maxScroll;
              final thumbWidth =
                  (trackWidth * (viewport / content)).clamp(38.0, trackWidth);
              final travel = math.max(0.0, trackWidth - thumbWidth);
              final offsetRatio =
                  (position.pixels / maxScroll).clamp(0.0, 1.0).toDouble();
              final thumbLeft = travel * offsetRatio;

              void moveBy(double delta) {
                if (travel <= 0) return;
                final next = position.pixels + (delta / travel) * maxScroll;
                widget.controller.jumpTo(
                  next.clamp(position.minScrollExtent, maxScroll),
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragDown: (_) => _setDragging(true),
                onHorizontalDragStart: (_) => _setDragging(true),
                onHorizontalDragUpdate: (details) =>
                    moveBy(details.primaryDelta ?? 0.0),
                onHorizontalDragEnd: (_) => _setDragging(false),
                onHorizontalDragCancel: () => _setDragging(false),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      width: thumbWidth,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        height: _dragging ? 14 : 8,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _dragging
                              ? _kPitchLabAccent.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: _dragging
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: _kPitchLabAccent.withValues(
                                      alpha: 0.34,
                                    ),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : const <BoxShadow>[],
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          height: _dragging ? 7 : 5,
                          decoration: BoxDecoration(
                            color: _kPitchLabAccent.withValues(
                              alpha: _dragging ? 0.95 : 0.72,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _kPitchLabAccent.withValues(
                                  alpha: _dragging ? 0.42 : 0.18,
                                ),
                                blurRadius: _dragging ? 12 : 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PitchBlobGridPainter extends CustomPainter {
  const _PitchBlobGridPainter({
    required this.pitchRange,
    required this.pitchCount,
    required this.rowHeight,
    required this.keyboardWidth,
    required this.pixelsPerBeat,
    required this.durationBeats,
    required this.gridStepBeats,
    required this.playheadBeat,
    required this.isPlaying,
    required this.waveformPeaks,
    required this.waveformWidthBeats,
    required this.waveformTrimStartMs,
    required this.waveformTrimEndMs,
    required this.waveformFullDurationMs,
  });

  final ({int min, int max}) pitchRange;
  final int pitchCount;
  final double rowHeight;
  final double keyboardWidth;
  final double pixelsPerBeat;
  final double durationBeats;
  final double gridStepBeats;
  final double? playheadBeat;
  final bool isPlaying;
  final List<double> waveformPeaks;
  final double waveformWidthBeats;
  final double waveformTrimStartMs;
  final double waveformTrimEndMs;
  final double waveformFullDurationMs;

  @override
  void paint(Canvas canvas, Size size) {
    final keyboardPaint = Paint()..color = const Color(0xFF0F141C);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, keyboardWidth, size.height), keyboardPaint);

    final whiteKeyPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.024);
    final blackKeyPaint = Paint()..color = Colors.black.withValues(alpha: 0.22);
    final rowLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    final beatPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final barPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 1;

    for (int row = 0; row < pitchCount; row++) {
      final y = row * rowHeight;
      final pitch = pitchRange.max - row;
      final isBlack = _isBlackKey(pitch);
      canvas.drawRect(
        Rect.fromLTWH(
          keyboardWidth,
          y,
          size.width - keyboardWidth,
          rowHeight,
        ),
        isBlack ? blackKeyPaint : whiteKeyPaint,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowLinePaint);
      if (pitch % 12 == 0 || row == 0) {
        _paintText(
          canvas,
          _noteNameForPitch(pitch),
          Offset(10, y + 6),
          Colors.white.withValues(alpha: 0.58),
          10.5,
          FontWeight.w700,
        );
      }
    }

    _paintWaveform(canvas, size);

    final steps = math.max(1, (durationBeats / gridStepBeats).ceil());
    for (int i = 0; i <= steps; i++) {
      final beat = i * gridStepBeats;
      final x = keyboardWidth + beat * pixelsPerBeat;
      final isBar = (beat % 4.0).abs() < 0.0001;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isBar ? barPaint : beatPaint,
      );
      if (isBar) {
        _paintText(
          canvas,
          '${(beat ~/ 4) + 1}',
          Offset(x + 5, 7),
          Colors.white.withValues(alpha: 0.48),
          10,
          FontWeight.w800,
        );
      }
    }

    final ph = playheadBeat;
    if (ph != null && ph >= 0 && ph <= durationBeats) {
      final x = keyboardWidth + ph * pixelsPerBeat;
      final paint = Paint()
        ..color =
            (isPlaying ? _kPitchLabAccent : const Color(0xFFFFCE5C))
                .withValues(alpha: 0.88)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final peaks = waveformPeaks;
    if (peaks.length < 2) return;
    final width = waveformWidthBeats * pixelsPerBeat;
    if (!width.isFinite || width <= 2.0) return;
    final fullMs = waveformFullDurationMs.clamp(1.0, double.infinity);
    final trimStart = waveformTrimStartMs.clamp(0.0, fullMs).toDouble();
    final trimEnd = waveformTrimEndMs.clamp(trimStart, fullMs).toDouble();
    final sourceWindowMs = math.max(1.0, trimEnd - trimStart);
    final drawWidth =
        math.min(width, math.max(0.0, size.width - keyboardWidth));
    if (drawWidth <= 2.0) return;

    final rect = Rect.fromLTWH(keyboardWidth, 0, drawWidth, size.height);
    canvas.save();
    canvas.clipRect(rect);

    final centerY = rect.center.dy;
    final maxHeight = math.max(8.0, rect.height * 0.34);
    final baselinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(rect.left, centerY),
      Offset(rect.right, centerY),
      baselinePaint,
    );

    final paint = Paint()
      ..color = const Color(0xFF9CB8C7).withValues(alpha: 0.18)
      ..strokeWidth = 1.0
      ..isAntiAlias = false;
    final peakScale = (peaks.length - 1) / fullMs;
    final pixelStep = math.max(1, (drawWidth / 2200.0).ceil()).toInt();
    for (int col = 0; col <= drawWidth; col += pixelStep) {
      final x = rect.left + col.toDouble();
      final sourceMs = trimStart + (col / drawWidth) * sourceWindowMs;
      final peakIndex =
          (sourceMs * peakScale).round().clamp(0, peaks.length - 1).toInt();
      final amp = peaks[peakIndex].abs().clamp(0.0, 1.0).toDouble();
      if (amp <= 0.002) continue;
      final h = math.pow(amp, 0.72).toDouble() * maxHeight;
      canvas.drawLine(Offset(x, centerY - h), Offset(x, centerY + h), paint);
    }

    canvas.restore();
  }

  bool _isBlackKey(int pitch) {
    switch (pitch % 12) {
      case 1:
      case 3:
      case 6:
      case 8:
      case 10:
        return true;
      default:
        return false;
    }
  }

  static String _noteNameForPitch(int pitch) {
    const names = <String>[
      'C',
      'C#',
      'D',
      'Eb',
      'E',
      'F',
      'F#',
      'G',
      'Ab',
      'A',
      'Bb',
      'B',
    ];
    final clamped = pitch.clamp(0, 127).toInt();
    final octave = (clamped ~/ 12) - 1;
    return '${names[clamped % 12]}$octave';
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
    FontWeight fontWeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: 'Pretendard',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: keyboardWidth - 14);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _PitchBlobGridPainter oldDelegate) {
    return oldDelegate.pitchRange != pitchRange ||
        oldDelegate.pitchCount != pitchCount ||
        oldDelegate.durationBeats != durationBeats ||
        oldDelegate.gridStepBeats != gridStepBeats ||
        oldDelegate.playheadBeat != playheadBeat ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.waveformPeaks != waveformPeaks ||
        oldDelegate.waveformWidthBeats != waveformWidthBeats ||
        oldDelegate.waveformTrimStartMs != waveformTrimStartMs ||
        oldDelegate.waveformTrimEndMs != waveformTrimEndMs ||
        oldDelegate.waveformFullDurationMs != waveformFullDurationMs;
  }
}

class _PitchBlobPainter extends CustomPainter {
  const _PitchBlobPainter({
    required this.color,
    required this.selected,
    required this.velocity,
    required this.label,
    required this.showHandles,
    required this.tool,
  });

  final Color color;
  final bool selected;
  final double velocity;
  final String label;
  final bool showHandles;
  final _PitchBlobTool tool;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(math.min(12, size.height / 2));
    final fill = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          color.withValues(alpha: selected ? 0.92 : 0.76),
          color.withValues(alpha: selected ? 0.66 : 0.48),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.6 : 1.0
      ..color = selected
          ? Colors.white.withValues(alpha: 0.72)
          : color.withValues(alpha: 0.68);
    final rrect = RRect.fromRectAndRadius(rect.deflate(1.0), radius);
    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, border);

    final centerY = size.height * 0.52;
    final vibratoPaint = Paint()
      ..color = Colors.white.withValues(alpha: selected ? 0.44 : 0.28)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final wave = Path();
    final amplitude = math.max(1.0, 2.2 + velocity * 2.4);
    for (double x = 8; x <= size.width - 8; x += 4) {
      final y = centerY + math.sin(x / 5.8) * amplitude;
      if (x == 8) {
        wave.moveTo(x, y);
      } else {
        wave.lineTo(x, y);
      }
    }
    canvas.drawPath(wave, vibratoPaint);

    if (showHandles) {
      final handlePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.64)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(8, 5),
        Offset(8, size.height - 5),
        handlePaint,
      );
      canvas.drawLine(
        Offset(size.width - 8, 5),
        Offset(size.width - 8, size.height - 5),
        handlePaint,
      );
    }

    if (size.width >= 44) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.62),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'Pretendard',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(0.0, size.width - 14));
      textPainter.paint(
          canvas, Offset(10, (size.height - textPainter.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PitchBlobPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.selected != selected ||
        oldDelegate.velocity != velocity ||
        oldDelegate.label != label ||
        oldDelegate.showHandles != showHandles ||
        oldDelegate.tool != tool;
  }
}
