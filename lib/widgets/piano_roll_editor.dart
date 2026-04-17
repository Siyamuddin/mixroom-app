import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mixroom/helpers/instrument_picker_categories.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/models.dart';

typedef MidiCommitCallback = Future<void> Function({
  required List<MidiNote> notes,
  required Map<String, double> instrumentParams,
  required String instrumentId,
  required String instrumentName,
});

const Color _kPianoShellText = Color(0xFFF4F4F4);
const Color _kPianoShellMutedText = Color(0xB8F4F4F4);
const Color _kPianoShellBorder = Color.fromRGBO(255, 255, 255, 0.12);
const Color _kPianoShellFill = Color.fromRGBO(244, 244, 244, 0.08);
const Color _kPianoShellFillStrong = Color.fromRGBO(244, 244, 244, 0.14);
const Color _kPianoWarmStart = Color(0xFF9D6833);
const Color _kPianoWarmEnd = Color(0xFF704821);
const Color _kPianoWarmBorder = Color(0xFFE0B27F);

BoxDecoration _mixroomPianoSurfaceDecoration({
  double radius = 24,
}) {
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
    border: Border.all(color: _kPianoShellBorder),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.30),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
    ],
  );
}

BoxDecoration _mixroomPianoInsetDecoration({
  double radius = 18,
  bool selected = false,
}) {
  return BoxDecoration(
    color: selected ? _kPianoShellFillStrong : _kPianoShellFill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.white.withValues(alpha: selected ? 0.18 : 0.12),
    ),
  );
}

class PianoRollEditor extends StatefulWidget {
  const PianoRollEditor({
    super.key,
    required this.clip,
    required this.availableInstruments,
    required this.bpm,
    required this.beatsPerBar,
    required this.projectPlayheadMs,
    required this.isPlaying,
    required this.magnetEnabled,
    required this.quantizeDivisionsPerBar,
    required this.fullscreen,
    required this.onFullscreenChanged,
    required this.onClose,
    required this.onCommit,
    this.onPreviewNote,
  });

  final AudioTrack clip;
  final List<Map<String, dynamic>> availableInstruments;
  final double bpm;
  final int beatsPerBar;
  final double projectPlayheadMs;
  final bool isPlaying;
  final bool magnetEnabled;
  final int quantizeDivisionsPerBar;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onClose;
  final MidiCommitCallback onCommit;
  final Future<void> Function(int pitch, double velocity)? onPreviewNote;

  @override
  State<PianoRollEditor> createState() => _PianoRollEditorState();
}

class _PianoRollEditorState extends State<PianoRollEditor>
    with TickerProviderStateMixin {
  static const String _preferredPianoInstrumentId = 'sfz.vsco.upright_piano';
  static const int _defaultMinPitch = 36;
  static const int _defaultMaxPitch = 84;
  static const int _pitchHeadroom = 12;
  static const int _absoluteMinPitch = 0;
  static const int _absoluteMaxPitch = 127;
  static const Duration _gestureTapBlockDuration = Duration(milliseconds: 150);
  static const double _minRowHeight = 14.0;
  static const double _maxRowHeight = 40.0;
  static const double _minPxPerBeat = 24.0;
  static const double _maxPxPerBeat = 220.0;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _gridVerticalController = ScrollController();
  final ScrollController _keysVerticalController = ScrollController();

  late final TabController _tabController;
  int _lastTabIndex = 0;

  double _rowHeight = 22.0;
  double _pxPerBeat = 56.0;
  bool _syncingVerticalScroll = false;

  String? _activeDragNoteId;
  bool _activeDragIsResize = false;
  bool _didMoveDuringDrag = false;
  bool _suppressNextGridTap = false;
  int? _pressedPreviewPitch;
  late final Ticker _playheadTicker;
  double _smoothedPlayheadMs = 0.0;
  bool _pinchZoomActive = false;
  bool _lockGridScroll = false;

  late List<MidiNote> _notes;
  late List<MidiNote> _syncedClipNotes;
  late Map<String, double> _params;
  late Map<String, double> _syncedClipParams;
  late String _instrumentId;
  late String _syncedInstrumentId;
  late String _instrumentName;
  late String _syncedInstrumentName;
  String _instrumentBrowserCategory = 'All';

  String? _selectedNoteId;
  final Set<String> _selectedNoteIds = <String>{};
  List<MidiNote>? _copiedNotes;
  Timer? _commitDebounce;
  bool _commitInFlight = false;
  bool _commitQueued = false;
  bool _velocityPanelOpen = false;

  Map<String, MidiNote>? _dragStartNotesById;
  double _dragAccumDxBeat = 0.0;
  double _dragAccumDyRows = 0.0;

  Offset? _boxSelectStartLocal;
  Offset? _boxSelectCurrentLocal;
  DateTime _ignoreGridTapUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, Offset> _activeGridPointers = <int, Offset>{};
  bool _manualPinchActive = false;
  Offset _pinchStartPointA = Offset.zero;
  Offset _pinchStartPointB = Offset.zero;
  double _pinchStartPxPerBeat = 56.0;
  double _pinchStartRowHeight = 22.0;
  double _pinchStartHorizontalOffset = 0.0;
  double _pinchStartVerticalOffset = 0.0;
  double _pinchStartFocalBeat = 0.0;
  double _pinchStartFocalRow = 0.0;
  Offset _pinchStartFocalLocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadFromClip();
    _gridVerticalController.addListener(_syncKeysWithGridScroll);
    _smoothedPlayheadMs = widget.projectPlayheadMs;
    _playheadTicker = createTicker((_) {
      if (!mounted) return;
      final target = widget.projectPlayheadMs;
      final next =
          _smoothedPlayheadMs + ((target - _smoothedPlayheadMs) * 0.24);
      if ((next - _smoothedPlayheadMs).abs() >= 0.01) {
        setState(() => _smoothedPlayheadMs = next);
      }
    });
    if (widget.isPlaying) {
      _playheadTicker.start();
    }
  }

  @override
  void didUpdateWidget(covariant PianoRollEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipIdentityChanged =
        oldWidget.clip.engineClipId != widget.clip.engineClipId;
    final clipContentChanged = _clipDataDiffersFromSyncedClip(widget.clip);
    if (clipIdentityChanged || clipContentChanged) {
      _loadFromClip();
      if (clipIdentityChanged) {
        _clearSelection();
      } else {
        _selectedNoteIds.removeWhere(
          (id) => !_notes.any((n) => n.id == id),
        );
        if (_selectedNoteId != null &&
            !_notes.any((n) => n.id == _selectedNoteId)) {
          _selectedNoteId = null;
        }
        if (_selectedNoteIds.isEmpty && _selectedNoteId == null) {
          _velocityPanelOpen = false;
        }
      }
    }
    if (widget.isPlaying && !_playheadTicker.isActive) {
      _playheadTicker.start();
    } else if (!widget.isPlaying && _playheadTicker.isActive) {
      _playheadTicker.stop();
      _smoothedPlayheadMs = widget.projectPlayheadMs;
      if (mounted) setState(() {});
    } else if (!widget.isPlaying &&
        (widget.projectPlayheadMs - _smoothedPlayheadMs).abs() > 0.1 &&
        mounted) {
      setState(() => _smoothedPlayheadMs = widget.projectPlayheadMs);
    }
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _activeGridPointers.clear();
    _manualPinchActive = false;
    _playheadTicker.dispose();
    _horizontalController.dispose();
    _gridVerticalController.removeListener(_syncKeysWithGridScroll);
    _gridVerticalController.dispose();
    _keysVerticalController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _loadFromClip() {
    _notes = widget.clip.midiNotes.map((n) => n.copy()).toList();
    _syncedClipNotes = widget.clip.midiNotes.map((n) => n.copy()).toList();
    _params = Map<String, double>.from(widget.clip.instrumentParams);
    _syncedClipParams = Map<String, double>.from(widget.clip.instrumentParams);
    _instrumentId = widget.clip.instrumentId;
    _syncedInstrumentId = widget.clip.instrumentId;
    _instrumentName = widget.clip.instrumentName;
    _syncedInstrumentName = widget.clip.instrumentName;
    _ensureDefaultParams();
    final match = widget.availableInstruments.where((spec) {
      return (spec['id'] as String?) == _instrumentId;
    });
    final category =
        match.isEmpty ? 'All' : _instrumentCategoryForSpec(match.first);
    final categories = _instrumentBrowserCategories();
    _instrumentBrowserCategory =
        categories.contains(category) ? category : 'All';
  }

  void _ensureDefaultParams() {
    if (_isSampledInstrumentId(_instrumentId)) {
      _params.putIfAbsent('outputGain', () => 0.72);
      _params.putIfAbsent('attackMs', () => 6.0);
      _params.putIfAbsent('releaseMs', () => 520.0);
      _params['drive'] = 0.0;
      return;
    }
    _params.putIfAbsent('oscillator', () => 1.0);
    _params.putIfAbsent('cutoffHz', () => 3200.0);
    _params.putIfAbsent('attackMs', () => 18.0);
    _params.putIfAbsent('releaseMs', () => 180.0);
    _params.putIfAbsent('drive', () => 0.08);
  }

  bool _isSampledInstrumentId(String id) {
    return id.trim().toLowerCase().startsWith('sfz.');
  }

  String _instrumentCategoryForSpec(Map<String, dynamic> spec) {
    return instrumentPickerCategoryForSpec(spec);
  }

  List<String> _instrumentBrowserCategories() {
    final available = widget.availableInstruments
        .map(_instrumentCategoryForSpec)
        .toSet()
        .toList(growable: false);
    return <String>[
      'All',
      ...kInstrumentPickerOrderedCategories.where(available.contains),
    ];
  }

  List<Map<String, dynamic>> _visibleInstrumentSpecs() {
    final category = _instrumentBrowserCategory;
    final list = widget.availableInstruments.where((spec) {
      if (category == 'All') return true;
      return _instrumentCategoryForSpec(spec) == category;
    }).toList(growable: false);
    list.sort((a, b) {
      final aId = (a['id'] as String? ?? '').trim();
      final bId = (b['id'] as String? ?? '').trim();
      if (aId == _preferredPianoInstrumentId &&
          bId != _preferredPianoInstrumentId) {
        return -1;
      }
      if (bId == _preferredPianoInstrumentId &&
          aId != _preferredPianoInstrumentId) {
        return 1;
      }
      final an = (a['name'] as String?) ?? '';
      final bn = (b['name'] as String?) ?? '';
      return an.compareTo(bn);
    });
    return list;
  }

  Map<String, double> _instrumentParamsFromSpec(Map<String, dynamic> spec) {
    final id = (spec['id'] as String?)?.trim() ?? '';
    final sampled = _isSampledInstrumentId(id);
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

  void _setInstrumentFromSpec(Map<String, dynamic> spec) {
    final id = (spec['id'] as String?)?.trim();
    if (id == null || id.isEmpty) return;
    final name = (spec['name'] as String?)?.trim();
    setState(() {
      _instrumentId = id;
      _instrumentName = (name == null || name.isEmpty) ? id : name;
      _params = _instrumentParamsFromSpec(spec);
    });
    _queueCommit(immediate: true);
  }

  bool _clipDataDiffersFromSyncedClip(AudioTrack next) {
    if (_syncedInstrumentId != next.instrumentId ||
        _syncedInstrumentName != next.instrumentName) {
      return true;
    }
    if (_instrumentParamsDiffer(_syncedClipParams, next.instrumentParams)) {
      return true;
    }
    return _noteListsDiffer(_syncedClipNotes, next.midiNotes);
  }

  bool _instrumentParamsDiffer(
    Map<String, double> previous,
    Map<String, double> next,
  ) {
    if (previous.length != next.length) return true;
    for (final entry in previous.entries) {
      final current = next[entry.key];
      if (current == null || (current - entry.value).abs() > 0.00001) {
        return true;
      }
    }
    return false;
  }

  bool _noteListsDiffer(List<MidiNote> previous, List<MidiNote> next) {
    if (previous.length != next.length) return true;
    for (int i = 0; i < previous.length; i++) {
      final a = previous[i];
      final b = next[i];
      if (a.id != b.id) return true;
      if (a.pitch != b.pitch) return true;
      if ((a.startBeat - b.startBeat).abs() > 0.00001) return true;
      if ((a.lengthBeats - b.lengthBeats).abs() > 0.00001) return true;
      if ((a.velocity - b.velocity).abs() > 0.00001) return true;
    }
    return false;
  }

  void _handleTabChanged() {
    final idx = _tabController.index;
    if (idx == _lastTabIndex) return;
    _lastTabIndex = idx;
    if (!mounted) return;
    setState(() {});
  }

  void _syncKeysWithGridScroll() {
    if (_syncingVerticalScroll || !_gridVerticalController.hasClients) {
      return;
    }
    if (!_keysVerticalController.hasClients) {
      return;
    }
    _syncingVerticalScroll = true;
    final target = _gridVerticalController.offset.clamp(
      _keysVerticalController.position.minScrollExtent,
      _keysVerticalController.position.maxScrollExtent,
    );
    _keysVerticalController.jumpTo(target);
    _syncingVerticalScroll = false;
  }

  void _jumpBothVerticalControllers(double targetOffset) {
    _syncingVerticalScroll = true;
    if (_gridVerticalController.hasClients) {
      final gridTarget = targetOffset.clamp(
        _gridVerticalController.position.minScrollExtent,
        _gridVerticalController.position.maxScrollExtent,
      );
      _gridVerticalController.jumpTo(gridTarget);
    }
    if (_keysVerticalController.hasClients) {
      final keysTarget = targetOffset.clamp(
        _keysVerticalController.position.minScrollExtent,
        _keysVerticalController.position.maxScrollExtent,
      );
      _keysVerticalController.jumpTo(keysTarget);
    }
    _syncingVerticalScroll = false;
  }

  double get _msPerBeat => 60000.0 / widget.bpm.clamp(1.0, 400.0);

  ({int min, int max}) get _visiblePitchRange {
    if (_notes.isEmpty) {
      return (min: _defaultMinPitch, max: _defaultMaxPitch);
    }

    var minNotePitch = _notes.first.pitch;
    var maxNotePitch = _notes.first.pitch;
    for (final note in _notes.skip(1)) {
      minNotePitch = math.min(minNotePitch, note.pitch);
      maxNotePitch = math.max(maxNotePitch, note.pitch);
    }

    final minPitch = math.max(
      _absoluteMinPitch,
      math.min(_defaultMinPitch, minNotePitch - _pitchHeadroom),
    );
    final maxPitch = math.min(
      _absoluteMaxPitch,
      math.max(_defaultMaxPitch, maxNotePitch + _pitchHeadroom),
    );
    return (min: minPitch, max: maxPitch);
  }

  int get _pitchCount {
    final pitchRange = _visiblePitchRange;
    return (pitchRange.max - pitchRange.min) + 1;
  }

  double get _contentHeight => _pitchCount * _rowHeight;

  double get _clipSpanBeat {
    final spanMs = (widget.clip.trimEnd - widget.clip.trimStart).inMilliseconds;
    if (spanMs <= 0) return 0.0;
    return spanMs / _msPerBeat;
  }

  double get _maxBeat {
    var beat = math.max(32.0, _clipSpanBeat + 8.0);
    for (final n in _notes) {
      beat = math.max(beat, n.startBeat + n.lengthBeats + 1.0);
    }
    if (_horizontalController.hasClients) {
      final visibleEndBeat = (_horizontalController.offset +
              _horizontalController.position.viewportDimension) /
          _pxPerBeat;
      beat = math.max(beat, visibleEndBeat + 16.0);
    }
    return beat;
  }

  double get _contentWidth => _maxBeat * _pxPerBeat;

  double get _quantizeBeat {
    final safeDivisions = math.max(1, widget.quantizeDivisionsPerBar);
    final safeBeatsPerBar = math.max(1, widget.beatsPerBar);
    return safeBeatsPerBar / safeDivisions;
  }

  double get _minimumLengthBeat =>
      widget.magnetEnabled ? _quantizeBeat : 0.0625;

  Set<String> get _effectiveSelectedIds {
    if (_selectedNoteIds.isNotEmpty) {
      return Set<String>.from(_selectedNoteIds);
    }
    if (_selectedNoteId != null) {
      return <String>{_selectedNoteId!};
    }
    return <String>{};
  }

  List<MidiNote> get _selectedNotes {
    final ids = _effectiveSelectedIds;
    if (ids.isEmpty) return const <MidiNote>[];
    final out = <MidiNote>[];
    for (final n in _notes) {
      if (ids.contains(n.id)) out.add(n);
    }
    return out;
  }

  double get _selectedAverageVelocity {
    final notes = _selectedNotes;
    if (notes.isEmpty) return 0.8;
    final total = notes.fold<double>(0.0, (sum, n) => sum + n.velocity);
    return (total / notes.length).clamp(0.0, 1.0);
  }

  void _queueCommit({bool immediate = false}) {
    _commitDebounce?.cancel();
    if (immediate) {
      unawaited(_commitNow());
      return;
    }
    _commitDebounce = Timer(const Duration(milliseconds: 160), _commitNow);
  }

  Future<void> _commitNow() async {
    if (_commitInFlight) {
      _commitQueued = true;
      return;
    }

    _commitInFlight = true;
    try {
      do {
        _commitQueued = false;
        await widget.onCommit(
          notes: _notes.map((n) => n.copy()).toList(),
          instrumentParams: Map<String, double>.from(_params),
          instrumentId: _instrumentId,
          instrumentName: _instrumentName,
        );
      } while (_commitQueued);
    } finally {
      _commitInFlight = false;
    }
  }

  double _snapBeat(double beat) {
    if (!widget.magnetEnabled) {
      return beat.clamp(0.0, 9999.0);
    }
    final q = (beat / _quantizeBeat).round() * _quantizeBeat;
    return q.clamp(0.0, 9999.0);
  }

  double _snapLengthBeat(double length) {
    final base = length.clamp(_minimumLengthBeat, 64.0);
    if (!widget.magnetEnabled) return base;
    final q = (base / _quantizeBeat).round() * _quantizeBeat;
    return q.clamp(_minimumLengthBeat, 64.0);
  }

  void _selectSingle(String id) {
    _selectedNoteIds
      ..clear()
      ..add(id);
    _selectedNoteId = id;
  }

  void _focusNoteSelection(String id) {
    if (_effectiveSelectedIds.contains(id)) {
      _selectedNoteId = id;
      return;
    }
    _selectSingle(id);
  }

  void _clearSelection() {
    _selectedNoteIds.clear();
    _selectedNoteId = null;
    _velocityPanelOpen = false;
  }

  void _normalizeSelectionState() {
    if (_selectedNoteIds.isEmpty) {
      _selectedNoteId = null;
      return;
    }
    if (_selectedNoteId == null ||
        !_selectedNoteIds.contains(_selectedNoteId)) {
      _selectedNoteId = _selectedNoteIds.first;
    }
  }

  Rect? get _currentSelectionRect {
    if (_boxSelectStartLocal == null || _boxSelectCurrentLocal == null) {
      return null;
    }
    return Rect.fromPoints(_boxSelectStartLocal!, _boxSelectCurrentLocal!);
  }

  void _finishBoxSelection() {
    final rect = _currentSelectionRect;
    if (rect == null) {
      setState(() {
        _boxSelectStartLocal = null;
        _boxSelectCurrentLocal = null;
      });
      return;
    }

    final hits = <String>{};
    for (final note in _notes) {
      final noteRect = Rect.fromLTWH(
        note.startBeat * _pxPerBeat,
        _yForPitch(note.pitch) + 1.0,
        math.max(10.0, note.lengthBeats * _pxPerBeat),
        _rowHeight - 2.0,
      );
      if (rect.overlaps(noteRect)) {
        hits.add(note.id);
      }
    }

    setState(() {
      _selectedNoteIds
        ..clear()
        ..addAll(hits);
      _normalizeSelectionState();
      _boxSelectStartLocal = null;
      _boxSelectCurrentLocal = null;
    });
  }

  int _clampPitch(int pitch) {
    final pitchRange = _visiblePitchRange;
    return pitch.clamp(pitchRange.min, pitchRange.max);
  }

  int _pitchForY(double y) {
    final pitchRange = _visiblePitchRange;
    final row = (y / _rowHeight).floor();
    final pitch = pitchRange.max - row;
    return _clampPitch(pitch);
  }

  double _beatForX(double x) {
    return _snapBeat(x / _pxPerBeat);
  }

  double _yForPitch(int pitch) {
    final row = (_visiblePitchRange.max - pitch).toDouble();
    return row * _rowHeight;
  }

  MidiNote? _noteById(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  String? _hitNoteIdAt(Offset local) {
    for (int i = _notes.length - 1; i >= 0; i--) {
      final note = _notes[i];
      final rect = Rect.fromLTWH(
        note.startBeat * _pxPerBeat,
        _yForPitch(note.pitch) + 1.0,
        math.max(10.0, note.lengthBeats * _pxPerBeat),
        _rowHeight - 2.0,
      );
      if (rect.contains(local)) return note.id;
    }
    return null;
  }

  void _previewPianoKey(int pitch, {double velocity = 0.9}) {
    setState(() => _pressedPreviewPitch = pitch);
    final callback = widget.onPreviewNote;
    if (callback != null) {
      unawaited(callback(pitch, velocity.clamp(0.0, 1.0)));
    }
  }

  void _releasePianoKey(int pitch) {
    if (_pressedPreviewPitch != pitch) return;
    setState(() => _pressedPreviewPitch = null);
  }

  void _adjustZoom({
    required double xFactor,
    required double yFactor,
  }) {
    final startX = _pxPerBeat;
    final startY = _rowHeight;
    final nextX = (startX * xFactor).clamp(_minPxPerBeat, _maxPxPerBeat);
    final nextY = (startY * yFactor).clamp(_minRowHeight, _maxRowHeight);
    if ((nextX - startX).abs() < 0.001 && (nextY - startY).abs() < 0.001) {
      return;
    }

    final currentHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    final currentVerticalOffset = _gridVerticalController.hasClients
        ? _gridVerticalController.offset
        : 0.0;
    final focalDx = _horizontalController.hasClients
        ? _horizontalController.position.viewportDimension * 0.5
        : 0.0;
    final focalDy = _gridVerticalController.hasClients
        ? _gridVerticalController.position.viewportDimension * 0.5
        : 0.0;
    final focalBeat = (currentHorizontalOffset + focalDx) / startX;
    final focalRow = (currentVerticalOffset + focalDy) / startY;

    setState(() {
      _pxPerBeat = nextX;
      _rowHeight = nextY;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontalController.hasClients) {
        final targetH = (focalBeat * _pxPerBeat) - focalDx;
        _horizontalController.jumpTo(
          targetH.clamp(
            _horizontalController.position.minScrollExtent,
            _horizontalController.position.maxScrollExtent,
          ),
        );
      }
      final targetV = (focalRow * _rowHeight) - focalDy;
      _jumpBothVerticalControllers(targetV);
    });
  }

  double _distance(Offset a, Offset b) => (a - b).distance;

  void _maybeStartManualPinch() {
    if (_manualPinchActive || _activeGridPointers.length < 2) return;
    final pts = _activeGridPointers.values.toList(growable: false);
    _pinchStartPointA = pts[0];
    _pinchStartPointB = pts[1];
    _pinchStartPxPerBeat = _pxPerBeat;
    _pinchStartRowHeight = _rowHeight;
    _pinchStartHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    _pinchStartVerticalOffset = _gridVerticalController.hasClients
        ? _gridVerticalController.offset
        : 0.0;
    final focal = (_pinchStartPointA + _pinchStartPointB) / 2.0;
    _pinchStartFocalLocal = focal;
    _pinchStartFocalBeat =
        (_pinchStartHorizontalOffset + focal.dx) / _pinchStartPxPerBeat;
    _pinchStartFocalRow =
        (_pinchStartVerticalOffset + focal.dy) / _pinchStartRowHeight;
    _manualPinchActive = true;
    _pinchZoomActive = true;
    _setGridScrollLocked(true);
    _suppressGridTapFor(const Duration(milliseconds: 220));
  }

  void _updateManualPinch() {
    if (!_manualPinchActive || _activeGridPointers.length < 2) return;
    final pts = _activeGridPointers.values.toList(growable: false);
    final p1 = pts[0];
    final p2 = pts[1];

    final startDistance = _distance(_pinchStartPointA, _pinchStartPointB);
    final currentDistance = _distance(p1, p2);
    if (startDistance <= 0.5 || currentDistance <= 0.5) return;

    final scale = (currentDistance / startDistance).clamp(0.25, 4.0);
    final nextPxPerBeat =
        (_pinchStartPxPerBeat * scale).clamp(_minPxPerBeat, _maxPxPerBeat);
    final nextRowHeight =
        (_pinchStartRowHeight * scale).clamp(_minRowHeight, _maxRowHeight);
    final focal = (p1 + p2) / 2.0;

    if ((_pxPerBeat - nextPxPerBeat).abs() < 0.001 &&
        (_rowHeight - nextRowHeight).abs() < 0.001) {
      return;
    }

    setState(() {
      _pxPerBeat = nextPxPerBeat;
      _rowHeight = nextRowHeight;
    });

    if (_horizontalController.hasClients) {
      final targetH = (_pinchStartFocalBeat * _pxPerBeat) - focal.dx;
      _horizontalController.jumpTo(
        targetH.clamp(
          _horizontalController.position.minScrollExtent,
          _horizontalController.position.maxScrollExtent,
        ),
      );
    }
    // Keep vertical zoom anchored to where the pinch began to avoid
    // accidental upward/downward drift while users change scale.
    final targetV =
        (_pinchStartFocalRow * _rowHeight) - _pinchStartFocalLocal.dy;
    _jumpBothVerticalControllers(targetV);
  }

  void _endManualPinch() {
    if (!_manualPinchActive) return;
    _manualPinchActive = false;
    _pinchZoomActive = false;
    _setGridScrollLocked(false);
    _suppressGridTapFor();
  }

  void _onGridPointerDown(PointerDownEvent event) {
    _activeGridPointers[event.pointer] = event.localPosition;
    _maybeStartManualPinch();
  }

  void _onGridPointerMove(PointerMoveEvent event) {
    if (!_activeGridPointers.containsKey(event.pointer)) return;
    _activeGridPointers[event.pointer] = event.localPosition;
    _updateManualPinch();
  }

  void _onGridPointerUp(PointerEvent event) {
    _activeGridPointers.remove(event.pointer);
    if (_activeGridPointers.length < 2) {
      _endManualPinch();
    }
  }

  void _startBoxSelection(LongPressStartDetails details) {
    if (_pinchZoomActive) return;
    if (_hitNoteIdAt(details.localPosition) != null) return;
    setState(() {
      _boxSelectStartLocal = details.localPosition;
      _boxSelectCurrentLocal = details.localPosition;
      _suppressNextGridTap = true;
    });
  }

  void _updateBoxSelection(LongPressMoveUpdateDetails details) {
    if (_boxSelectStartLocal == null) return;
    setState(() {
      _boxSelectCurrentLocal = details.localPosition;
    });
  }

  void _cancelBoxSelection() {
    if (_boxSelectStartLocal == null && _boxSelectCurrentLocal == null) return;
    setState(() {
      _boxSelectStartLocal = null;
      _boxSelectCurrentLocal = null;
    });
  }

  void _setGridScrollLocked(bool locked) {
    if (_lockGridScroll == locked) return;
    setState(() {
      _lockGridScroll = locked;
    });
  }

  void _suppressGridTapFor([Duration duration = _gestureTapBlockDuration]) {
    final until = DateTime.now().add(duration);
    if (until.isAfter(_ignoreGridTapUntil)) {
      _ignoreGridTapUntil = until;
    }
  }

  void _beginNoteDrag(
    MidiNote note,
    DragStartDetails details, {
    required double width,
    required double handleWidth,
  }) {
    final selectedIds = _effectiveSelectedIds;
    if (!selectedIds.contains(note.id)) {
      _selectSingle(note.id);
    } else {
      _selectedNoteId = note.id;
    }

    final dragIds = _effectiveSelectedIds;
    _dragStartNotesById = <String, MidiNote>{};
    for (final n in _notes) {
      if (dragIds.contains(n.id)) {
        _dragStartNotesById![n.id] = n.copy();
      }
    }

    _activeDragNoteId = note.id;
    _activeDragIsResize = details.localPosition.dx >= (width - handleWidth);
    _dragAccumDxBeat = 0.0;
    _dragAccumDyRows = 0.0;
    _didMoveDuringDrag = false;
    _suppressNextGridTap = true;
    _lockGridScroll = true;
    _suppressGridTapFor();
  }

  void _updateNoteDrag(MidiNote anchor, DragUpdateDetails details) {
    if (_activeDragNoteId != anchor.id) return;
    if (_dragStartNotesById == null || _dragStartNotesById!.isEmpty) return;

    _dragAccumDxBeat += details.delta.dx / _pxPerBeat;
    _dragAccumDyRows += details.delta.dy / _rowHeight;
    if (!_didMoveDuringDrag &&
        (_dragAccumDxBeat.abs() > 0.01 || _dragAccumDyRows.abs() > 0.01)) {
      _didMoveDuringDrag = true;
    }

    if (_activeDragIsResize) {
      for (final entry in _dragStartNotesById!.entries) {
        final base = entry.value;
        final live = _noteById(entry.key);
        if (live == null) continue;
        final proposed = base.lengthBeats + _dragAccumDxBeat;
        live.lengthBeats = _snapLengthBeat(proposed);
      }
      return;
    }
    final rowShift = _dragAccumDyRows.round();

    for (final entry in _dragStartNotesById!.entries) {
      final base = entry.value;
      final live = _noteById(entry.key);
      if (live == null) continue;
      final unsnappedStart = base.startBeat + _dragAccumDxBeat;
      live.startBeat = widget.magnetEnabled
          ? _snapBeat(unsnappedStart)
          : unsnappedStart.clamp(0.0, 9999.0);
      live.pitch = _clampPitch(base.pitch - rowShift);
    }
  }

  void _endNoteDrag({required bool commit}) {
    final shouldCommit = commit && _didMoveDuringDrag;
    _activeDragNoteId = null;
    _activeDragIsResize = false;
    _dragStartNotesById = null;
    _dragAccumDxBeat = 0.0;
    _dragAccumDyRows = 0.0;
    _didMoveDuringDrag = false;
    _lockGridScroll = false;
    _suppressNextGridTap = false;
    _suppressGridTapFor();
    if (shouldCommit) {
      _queueCommit(immediate: true);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _addNoteAt(Offset local) {
    if (DateTime.now().isBefore(_ignoreGridTapUntil)) return;
    if (_pinchZoomActive) return;
    if (_boxSelectStartLocal != null || _boxSelectCurrentLocal != null) return;
    if (_suppressNextGridTap) {
      _suppressNextGridTap = false;
      return;
    }
    if (_hitNoteIdAt(local) != null) return;

    final beat = _beatForX(local.dx);
    final pitch = _pitchForY(local.dy);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_notes.length}';
    final note = MidiNote(
      id: id,
      pitch: pitch,
      startBeat: beat,
      lengthBeats: widget.magnetEnabled ? math.max(_quantizeBeat, 0.25) : 1.0,
      velocity: _selectedAverageVelocity,
    );

    setState(() {
      _notes.add(note);
      _selectSingle(id);
    });
    _queueCommit(immediate: true);
  }

  void _deleteSelectedNotes() {
    final selected = _effectiveSelectedIds;
    if (selected.isEmpty) return;
    setState(() {
      _notes.removeWhere((n) => selected.contains(n.id));
      _clearSelection();
    });
    _queueCommit(immediate: true);
  }

  void _copySelectedNotes() {
    final selectedIds = _effectiveSelectedIds;
    if (selectedIds.isEmpty) return;
    final copied = _notes
        .where((n) => selectedIds.contains(n.id))
        .map((n) => n.copy())
        .toList();
    copied.sort((a, b) {
      final byBeat = a.startBeat.compareTo(b.startBeat);
      if (byBeat != 0) return byBeat;
      return a.pitch.compareTo(b.pitch);
    });
    if (copied.isEmpty) return;
    _copiedNotes = copied;
  }

  void _pasteNotes() {
    if (_copiedNotes == null || _copiedNotes!.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final minCopiedBeat =
        _copiedNotes!.map((n) => n.startBeat).reduce((a, b) => math.min(a, b));
    final selected = _selectedNotes;
    final insertionBeat = selected.isNotEmpty
        ? _snapBeat(
            selected.map((n) => n.startBeat + n.lengthBeats).reduce(math.max),
          )
        : (_notes.isEmpty
            ? 0.0
            : _snapBeat(_notes.map((n) => n.startBeat).reduce(math.max) + 1.0));

    final pastedIds = <String>{};
    setState(() {
      for (int i = 0; i < _copiedNotes!.length; i++) {
        final src = _copiedNotes![i];
        final id = '${now}_$i';
        _notes.add(MidiNote(
          id: id,
          pitch: _clampPitch(src.pitch),
          startBeat: _snapBeat(insertionBeat + (src.startBeat - minCopiedBeat)),
          lengthBeats: _snapLengthBeat(src.lengthBeats),
          velocity: src.velocity,
        ));
        pastedIds.add(id);
      }
      _selectedNoteIds
        ..clear()
        ..addAll(pastedIds);
      _normalizeSelectionState();
    });
    _queueCommit(immediate: true);
  }

  void _duplicateSelectedNotes() {
    _copySelectedNotes();
    _pasteNotes();
  }

  void _setSelectedVelocity(double velocity) {
    final selected = _effectiveSelectedIds;
    if (selected.isEmpty) return;
    final safe = velocity.clamp(0.05, 1.0);
    setState(() {
      for (final note in _notes) {
        if (selected.contains(note.id)) {
          note.velocity = safe;
        }
      }
    });
    _queueCommit();
  }

  void _scaleSelectedLength(double factor) {
    final selected = _effectiveSelectedIds;
    if (selected.isEmpty) return;
    setState(() {
      for (final note in _notes) {
        if (selected.contains(note.id)) {
          note.lengthBeats = _snapLengthBeat(note.lengthBeats * factor);
        }
      }
    });
    _queueCommit(immediate: true);
  }

  int _oscillatorIndex() {
    final raw = (_params['oscillator'] ?? 1.0).round();
    return raw.clamp(0, 3);
  }

  String _oscillatorLabel(int idx) {
    switch (idx) {
      case 0:
        return 'Sine';
      case 1:
        return 'Saw';
      case 2:
        return 'Square';
      case 3:
        return 'Triangle';
      default:
        return 'Saw';
    }
  }

  Future<void> _showMidiHelpDialog() async {
    Widget tipCard({
      required IconData icon,
      required Color accent,
      required String title,
      required String body,
    }) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accent, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2333),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          L10n.translate(ctx, 'Piano Roll Quick Guide'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tipCard(
              icon: Icons.touch_app_rounded,
              accent: const Color(0xFF7DB4FF),
              title: L10n.translate(ctx, 'Create + shape notes'),
              body: L10n.translate(
                ctx,
                'Tap empty grid to add. Drag to move. Pull right edge to resize.',
              ),
            ),
            const SizedBox(height: 8),
            tipCard(
              icon: Icons.select_all_rounded,
              accent: const Color(0xFF83D4B9),
              title: L10n.translate(ctx, 'Select groups quickly'),
              body: L10n.translate(
                ctx,
                'Hold empty space and drag a box to multi-select notes.',
              ),
            ),
            const SizedBox(height: 8),
            tipCard(
              icon: Icons.pinch_rounded,
              accent: const Color(0xFFF7C56D),
              title: L10n.translate(ctx, 'Zoom + edit faster'),
              body: L10n.translate(
                ctx,
                'Pinch with two fingers or use +/- buttons to zoom in time and pitch.',
              ),
            ),
            const SizedBox(height: 8),
            tipCard(
              icon: Icons.tune_rounded,
              accent: const Color(0xFFE78CF3),
              title: L10n.translate(ctx, 'Use the bottom tray'),
              body: L10n.translate(
                ctx,
                'Duplicate, delete, and adjust length/velocity for selected notes.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.translate(ctx, 'Got it')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playheadBeat = ((_smoothedPlayheadMs -
                (widget.clip.offset * 1000.0) +
                widget.clip.trimStart.inMilliseconds) /
            _msPerBeat)
        .toDouble();

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: _mixroomPianoSurfaceDecoration(radius: 24),
        child: SafeArea(
          top: widget.fullscreen,
          bottom: false,
          child: Column(
            children: [
              _buildHeaderBar(),
              _buildTabBar(),
              const Divider(height: 1, thickness: 1, color: Color(0x28FFFFFF)),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildMidiTab(playheadBeat),
                    _buildInstrumentTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    final onMidiTab = _tabController.index == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _instrumentName.isEmpty ? 'Instrument' : _instrumentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kPianoShellText,
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w700,
                fontSize: 13.0,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (onMidiTab) ...[
            _toolbarIconButton(
              icon: Icons.zoom_out_rounded,
              tooltip: 'Zoom out',
              onTap: () => _adjustZoom(xFactor: 0.86, yFactor: 0.90),
            ),
            const SizedBox(width: 5),
            _toolbarIconButton(
              icon: Icons.zoom_in_rounded,
              tooltip: 'Zoom in',
              onTap: () => _adjustZoom(xFactor: 1.16, yFactor: 1.12),
            ),
            const SizedBox(width: 5),
          ],
          _toolbarIconButton(
            icon: Icons.help_outline,
            tooltip: 'Piano roll help',
            onTap: _showMidiHelpDialog,
          ),
          const SizedBox(width: 5),
          _toolbarIconButton(
            icon: widget.fullscreen
                ? Icons.fullscreen_exit_outlined
                : Icons.fullscreen_outlined,
            tooltip: 'Toggle fullscreen',
            onTap: () => widget.onFullscreenChanged(!widget.fullscreen),
          ),
          const SizedBox(width: 5),
          _toolbarIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: _mixroomPianoInsetDecoration(radius: 18),
        child: SizedBox(
          height: 34,
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[_kPianoWarmStart, _kPianoWarmEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kPianoWarmBorder),
            ),
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 2,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: _kPianoShellText,
            labelStyle: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.6,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelColor: _kPianoShellMutedText,
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(18),
            tabs: const [
              Tab(height: 34, text: 'MIDI'),
              Tab(height: 34, text: 'Instrument'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMidiTab(double playheadBeat) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: _mixroomPianoInsetDecoration(radius: 18),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: _buildPianoKeys(),
              ),
              Expanded(
                child: _buildRollGrid(playheadBeat),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    final selected = _selectedNotes;
    if (selected.isEmpty) return const SizedBox.shrink();
    final velocity = _selectedAverageVelocity;
    final hasCopiedNotes = _copiedNotes != null && _copiedNotes!.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxOverlayWidth = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - 12.0)
            : double.infinity;
        final velocityPanelWidth =
            maxOverlayWidth.isFinite ? math.min(286.0, maxOverlayWidth) : 286.0;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxOverlayWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_velocityPanelOpen)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(244, 244, 244, 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: SizedBox(
                    width: velocityPanelWidth,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4.6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 9,
                                ),
                              ),
                              child: Slider(
                                min: 0.05,
                                max: 1.0,
                                value: velocity,
                                onChanged: _setSelectedVelocity,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            child: Text(
                              velocity.toStringAsFixed(2),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'Pretendard',
                                fontSize: 8.8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(244, 244, 244, 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    _trayAction(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copy',
                      enabled: true,
                      onTap: _copySelectedNotes,
                    ),
                    _trayAction(
                      icon: Icons.content_paste_rounded,
                      tooltip: 'Paste',
                      enabled: hasCopiedNotes,
                      onTap: _pasteNotes,
                    ),
                    _trayAction(
                      icon: Icons.control_point_duplicate_rounded,
                      tooltip: 'Duplicate',
                      enabled: true,
                      onTap: _duplicateSelectedNotes,
                    ),
                    _trayAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      enabled: true,
                      onTap: _deleteSelectedNotes,
                      danger: true,
                    ),
                    _selectionTextActionRow(
                      velocityActive: _velocityPanelOpen,
                    ),
                    _trayAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      enabled: true,
                      onTap: () => setState(_clearSelection),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _selectionTextActionRow({
    required bool velocityActive,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _lengthAction('Len-', () => _scaleSelectedLength(0.8)),
        const SizedBox(width: 3),
        _lengthAction('Len+', () => _scaleSelectedLength(1.25)),
        const SizedBox(width: 3),
        _lengthAction(
          'Vel',
          () => setState(
            () => _velocityPanelOpen = !_velocityPanelOpen,
          ),
          active: velocityActive,
        ),
      ],
    );
  }

  Widget _lengthAction(
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _trayAction({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: danger
                  ? const Color(0x40CF4B4B)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: danger
                    ? const Color(0x66E56F6F)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              color: danger ? const Color(0xFFFFB4B4) : Colors.white,
              size: 13,
            ),
          ),
        ),
      ),
    );
  }

  String _instrumentVisualCategory() {
    return instrumentPickerCategoryForValues(
      instrumentId: _instrumentId,
      instrumentName: _instrumentName,
    );
  }

  Color _instrumentVisualAccent(String category) {
    switch (category) {
      case 'Strings':
        return const Color(0xFF6AA9FF);
      case 'Woodwinds':
        return const Color(0xFF4BC6A8);
      case 'Percussion':
        return const Color(0xFFF8B55E);
      case 'Drums':
        return const Color(0xFFFF6E6E);
      case 'Bass':
        return const Color(0xFF5FD36A);
      case 'Pads':
        return const Color(0xFF4BC9B6);
      case 'Plucks':
        return const Color(0xFFD77EFF);
      case 'Synths':
        return const Color(0xFF7FA5FF);
      case 'Brass':
        return const Color(0xFFF1C24D);
      case 'Keys':
        return const Color(0xFF53A8FF);
      case 'Leads':
        return const Color(0xFFFFA749);
      default:
        return const Color(0xFF7FA5FF);
    }
  }

  IconData _instrumentVisualIcon(String category) {
    switch (category) {
      case 'Strings':
        return Icons.multitrack_audio_rounded;
      case 'Woodwinds':
        return Icons.air_rounded;
      case 'Percussion':
        return Icons.music_note_outlined;
      case 'Drums':
        return Icons.album_rounded;
      case 'Bass':
        return Icons.graphic_eq_rounded;
      case 'Pads':
        return Icons.waves_rounded;
      case 'Plucks':
        return Icons.auto_awesome_rounded;
      case 'Synths':
        return Icons.music_note_rounded;
      case 'Brass':
        return Icons.campaign_outlined;
      case 'Keys':
        return Icons.piano_rounded;
      case 'Leads':
        return Icons.bolt_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  Widget _buildInstrumentTab() {
    final category = _instrumentVisualCategory();
    final accent = _instrumentVisualAccent(category);
    final sampled = _isSampledInstrumentId(_instrumentId);
    final categories = _instrumentBrowserCategories();
    final instruments = _visibleInstrumentSpecs();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration:
                _mixroomPianoInsetDecoration(radius: 18, selected: true),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _instrumentVisualIcon(category),
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instrument',
                        style: TextStyle(
                          color: _kPianoShellMutedText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      Text(
                        _instrumentName.isEmpty
                            ? 'Instrument'
                            : _instrumentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kPianoShellText,
                          fontFamily: 'Pretendard',
                          fontSize: 13.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kPianoShellFillStrong,
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) {
                final c = categories[i];
                final selected = c == _instrumentBrowserCategory;
                final chipAccent =
                    _instrumentVisualAccent(c == 'All' ? category : c);
                return InkWell(
                  onTap: () => setState(() => _instrumentBrowserCategory = c),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    constraints: const BoxConstraints(
                      minHeight: 30,
                      minWidth: 72,
                    ),
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          selected ? _kPianoShellFillStrong : _kPianoShellFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? _kPianoWarmBorder
                            : Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _instrumentVisualIcon(c == 'All' ? category : c),
                            size: 12.2,
                            color: selected ? chipAccent : Colors.white70,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            c,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? _kPianoShellText
                                  : _kPianoShellMutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                              fontFamily: 'Pretendard',
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
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: _mixroomPianoInsetDecoration(radius: 18),
            child: instruments.isEmpty
                ? Center(
                    child: Text(
                      'No instruments in this category.',
                      style: TextStyle(
                        color: _kPianoShellMutedText,
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: instruments.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (_, i) {
                      final spec = instruments[i];
                      final id = (spec['id'] as String?) ?? '';
                      final selected = id == _instrumentId;
                      final name = (spec['name'] as String?) ?? id;
                      final rowAccent = _instrumentVisualAccent(
                        _instrumentCategoryForSpec(spec),
                      );
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _setInstrumentFromSpec(spec),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _kPianoShellFillStrong
                                  : Colors.transparent,
                              border: selected
                                  ? Border(
                                      left: BorderSide(
                                        color: _kPianoWarmBorder,
                                        width: 2.0,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _instrumentVisualIcon(
                                    _instrumentCategoryForSpec(spec),
                                  ),
                                  size: 14,
                                  color: selected ? rowAccent : Colors.white54,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Pretendard',
                                      fontSize: 12.2,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 15,
                                    color: _kPianoWarmBorder,
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
          if (sampled) ...[
            Row(
              children: [
                Expanded(
                  child: _macroSliderCard(
                    label: 'Output',
                    accent: accent,
                    value: (_params['outputGain'] ?? 0.72).clamp(0.2, 2.0),
                    min: 0.2,
                    max: 2.0,
                    valueLabelBuilder: (v) => '${(v * 100).round()}%',
                    onChanged: (v) {
                      setState(() => _params['outputGain'] = v);
                      _queueCommit();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _macroSliderCard(
                    label: 'Release',
                    accent: accent,
                    value: (_params['releaseMs'] ?? 520.0).clamp(20.0, 1400.0),
                    min: 20.0,
                    max: 1400.0,
                    valueLabelBuilder: (v) => '${v.round()} ms',
                    onChanged: (v) {
                      setState(() => _params['releaseMs'] = v);
                      _queueCommit();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _instrumentCard(
              title: 'Attack',
              subtitle: 'Sample fade-in to avoid clicks',
              child: _labeledSlider(
                label: 'Attack',
                value: (_params['attackMs'] ?? 6.0).clamp(0.0, 180.0),
                min: 0.0,
                max: 180.0,
                onChanged: (v) {
                  setState(() => _params['attackMs'] = v);
                  _queueCommit();
                },
              ),
            ),
          ] else ...[
            _instrumentCard(
              title: 'Oscillator',
              subtitle: 'Pick the source waveform',
              child: Row(
                children: [
                  Expanded(
                    child: _waveformButton(
                      index: 0,
                      icon: Icons.radio_button_checked_rounded,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _waveformButton(
                      index: 1,
                      icon: Icons.show_chart_rounded,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _waveformButton(
                      index: 2,
                      icon: Icons.crop_square_rounded,
                      accent: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _waveformButton(
                      index: 3,
                      icon: Icons.change_history_rounded,
                      accent: accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _macroSliderCard(
                    label: 'Drive',
                    accent: accent,
                    value: (_params['drive'] ?? 0.08).clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    valueLabelBuilder: (v) => '${(v * 100).round()}%',
                    onChanged: (v) {
                      setState(() => _params['drive'] = v);
                      _queueCommit();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _macroSliderCard(
                    label: 'Cutoff',
                    accent: accent,
                    value:
                        (_params['cutoffHz'] ?? 3200.0).clamp(200.0, 12000.0),
                    min: 200.0,
                    max: 12000.0,
                    valueLabelBuilder: (v) => '${v.round()} Hz',
                    onChanged: (v) {
                      setState(() => _params['cutoffHz'] = v);
                      _queueCommit();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _instrumentCard(
              title: 'Envelope',
              subtitle: 'Shape note attack and tail',
              child: Column(
                children: [
                  _labeledSlider(
                    label: 'Attack',
                    value: (_params['attackMs'] ?? 18.0).clamp(0.0, 300.0),
                    min: 0.0,
                    max: 300.0,
                    onChanged: (v) {
                      setState(() => _params['attackMs'] = v);
                      _queueCommit();
                    },
                  ),
                  _labeledSlider(
                    label: 'Release',
                    value: (_params['releaseMs'] ?? 180.0).clamp(20.0, 1200.0),
                    min: 20.0,
                    max: 1200.0,
                    onChanged: (v) {
                      setState(() => _params['releaseMs'] = v);
                      _queueCommit();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _waveformButton({
    required int index,
    required IconData icon,
    required Color accent,
  }) {
    final selected = _oscillatorIndex() == index;
    return InkWell(
      onTap: () {
        setState(() => _params['oscillator'] = index.toDouble());
        _queueCommit();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kPianoShellFillStrong : _kPianoShellFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _kPianoWarmBorder
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? _kPianoShellText : _kPianoShellMutedText,
                size: 16),
            const SizedBox(height: 2),
            Text(
              _oscillatorLabel(index),
              style: TextStyle(
                color: selected ? _kPianoShellText : _kPianoShellMutedText,
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
                fontFamily: 'Pretendard',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroSliderCard({
    required String label,
    required Color accent,
    required double value,
    required double min,
    required double max,
    required String Function(double value) valueLabelBuilder,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: _kPianoShellFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _kPianoShellText,
                  fontFamily: 'Pretendard',
                  fontSize: 11.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                valueLabelBuilder(value),
                style: TextStyle(
                  color: _kPianoShellMutedText,
                  fontSize: 10.6,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
              thumbColor: _kPianoShellText,
              overlayColor: Colors.white.withValues(alpha: 0.20),
              trackHeight: 3.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _instrumentCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: _kPianoShellFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _kPianoShellText,
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: _kPianoShellMutedText,
              fontSize: 10.4,
              fontWeight: FontWeight.w500,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildPianoKeys() {
    const blackKeyWidth = 46.0;
    final pitchRange = _visiblePitchRange;
    final minPitch = pitchRange.min;
    final maxPitch = pitchRange.max;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE7EAED),
        border: Border(
          right: BorderSide(
              color: const Color(0xFFB5BDC4).withValues(alpha: 0.95),
              width: 1.0),
        ),
      ),
      child: SingleChildScrollView(
        controller: _keysVerticalController,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          height: _contentHeight,
          child: Column(
            children: List<Widget>.generate(_pitchCount, (i) {
              final pitch = maxPitch - i;
              final isBlack = _isBlackKey(pitch);
              final belowPitch = pitch - 1;
              final belowIsBlack =
                  belowPitch >= minPitch && _isBlackKey(belowPitch);
              final abovePitch = pitch + 1;
              final noteName = _noteNameForPitch(pitch);
              final isPressed = _pressedPreviewPitch == pitch;
              final showLabel = pitch % 12 == 0 || isPressed;
              final topHalfPressed = isBlack &&
                  abovePitch <= maxPitch &&
                  !_isBlackKey(abovePitch) &&
                  _pressedPreviewPitch == abovePitch;
              final bottomHalfPressed = isBlack &&
                  belowPitch >= minPitch &&
                  !_isBlackKey(belowPitch) &&
                  _pressedPreviewPitch == belowPitch;
              final blackTop =
                  isPressed ? const Color(0xFF737D86) : const Color(0xFF525A62);
              final blackBottom =
                  isPressed ? const Color(0xFF626B74) : const Color(0xFF454C54);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _previewPianoKey(pitch),
                onPointerUp: (_) => _releasePianoKey(pitch),
                onPointerCancel: (_) => _releasePianoKey(pitch),
                child: SizedBox(
                  height: _rowHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: isBlack
                              ? (isPressed
                                  ? const Color(0xFF6A747D)
                                  : const Color(0xFF50575F))
                              : (isPressed
                                  ? const Color(0xFFF3F5F6)
                                  : const Color(0xFFF8F9FA)),
                        ),
                      ),
                      if (isBlack)
                        Positioned(
                          left: blackKeyWidth,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  color: topHalfPressed
                                      ? const Color(0xFFDCE7FB)
                                      : const Color(0xFFF9FAFB),
                                ),
                              ),
                              Container(
                                height: 0.7,
                                color: const Color(0xFFD6DADF),
                              ),
                              Expanded(
                                child: Container(
                                  color: bottomHalfPressed
                                      ? const Color(0xFFDCE7FB)
                                      : const Color(0xFFF3F5F7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isBlack)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: blackKeyWidth,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [blackTop, blackBottom],
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(1.2),
                              ),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.22),
                                width: 0.6,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!isBlack)
                        Positioned(
                          left: 0,
                          right: belowIsBlack ? null : 0,
                          bottom: 0,
                          width: belowIsBlack ? blackKeyWidth : null,
                          child: Container(
                            height: 0.7,
                            color: const Color(0xFFD8DDE1),
                          ),
                        ),
                      Positioned(
                        left: isBlack ? 9 : 7,
                        right: 4,
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            showLabel ? noteName : '',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: isBlack
                                  ? Colors.white.withValues(alpha: 0.84)
                                  : const Color(0xFF535B64),
                              fontSize: showLabel ? 10.2 : 0.1,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Pretendard',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildRollGrid(double playheadBeat) {
    final physics = _lockGridScroll
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();
    final pitchRange = _visiblePitchRange;
    return Container(
      color: const Color(0xFF41474E),
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              physics: physics,
              child: SizedBox(
                width: _contentWidth,
                child: SingleChildScrollView(
                  controller: _gridVerticalController,
                  physics: physics,
                  child: SizedBox(
                    width: _contentWidth,
                    height: _contentHeight,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onGridPointerDown,
                      onPointerMove: _onGridPointerMove,
                      onPointerUp: _onGridPointerUp,
                      onPointerCancel: _onGridPointerUp,
                      child: GestureDetector(
                        key: const ValueKey<String>('piano_roll_grid_canvas'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: (details) => _addNoteAt(details.localPosition),
                        onLongPressStart: _startBoxSelection,
                        onLongPressMoveUpdate: _updateBoxSelection,
                        onLongPressEnd: (_) => _finishBoxSelection(),
                        onLongPressCancel: _cancelBoxSelection,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _PianoGridPainter(
                                  rowHeight: _rowHeight,
                                  pxPerBeat: _pxPerBeat,
                                  maxPitch: pitchRange.max,
                                  minPitch: pitchRange.min,
                                  maxBeat: _maxBeat,
                                  beatsPerBar: widget.beatsPerBar,
                                  quantizeDivisionsPerBar:
                                      widget.quantizeDivisionsPerBar,
                                  magnetEnabled: widget.magnetEnabled,
                                ),
                              ),
                            ),
                            if (_pressedPreviewPitch != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: _yForPitch(_pressedPreviewPitch!),
                                height: _rowHeight,
                                child: IgnorePointer(
                                  child: Container(
                                    color: _kPianoWarmBorder.withValues(
                                        alpha: 0.18),
                                  ),
                                ),
                              ),
                            for (final note in _notes) _buildNoteWidget(note),
                            if (_currentSelectionRect != null)
                              Positioned.fromRect(
                                rect: _currentSelectionRect!,
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0x2B78A7FF),
                                      border: Border.all(
                                        color: const Color(0xFF8CB6FF),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (playheadBeat >= 0.0)
                              Positioned(
                                left: playheadBeat * _pxPerBeat,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 2.0,
                                    color: const Color(0xFFFFD45A),
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
          ),
          if (_selectedNotes.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.bottomRight,
                child: _buildSelectionOverlay(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoteWidget(MidiNote note) {
    final selected = _effectiveSelectedIds.contains(note.id);
    final left = note.startBeat * _pxPerBeat;
    final width = math.max(10.0, note.lengthBeats * _pxPerBeat);
    final top = _yForPitch(note.pitch);
    final alpha = (118 + (note.velocity * 108).round()).clamp(90, 235);
    final resizeHitWidth = math.min(24.0, math.max(14.0, width * 0.34));
    final handleWidth = selected ? math.max(18.0, resizeHitWidth) : 0.0;
    final dragging = _activeDragNoteId == note.id;
    final dragAccent = const Color(0xFF79DCA7);
    final labelUsableWidth = width - handleWidth - 10.0;
    final showNoteLabel =
        selected && !dragging && labelUsableWidth >= 24.0 && _rowHeight >= 15;

    return Positioned(
      left: left,
      top: top + 1,
      width: width,
      height: _rowHeight - 2,
      child: Listener(
        onPointerDown: (_) {
          _setGridScrollLocked(true);
          _suppressGridTapFor();
        },
        onPointerUp: (_) => _setGridScrollLocked(false),
        onPointerCancel: (_) => _setGridScrollLocked(false),
        child: GestureDetector(
          key: ValueKey<String>('piano_note_${note.id}'),
          behavior: HitTestBehavior.translucent,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (_) {
            setState(() {
              _focusNoteSelection(note.id);
            });
          },
          onTapUp: (_) {
            _previewPianoKey(note.pitch, velocity: note.velocity);
            _suppressGridTapFor();
            Future<void>.delayed(const Duration(milliseconds: 90), () {
              if (!mounted) return;
              _releasePianoKey(note.pitch);
            });
            _setGridScrollLocked(false);
          },
          onTapCancel: () {
            _releasePianoKey(note.pitch);
            _setGridScrollLocked(false);
          },
          onPanStart: (details) => setState(() {
            _releasePianoKey(note.pitch);
            _beginNoteDrag(
              note,
              details,
              width: width,
              handleWidth: resizeHitWidth,
            );
          }),
          onPanUpdate: (details) {
            if (_activeDragNoteId != note.id) return;
            setState(() {
              _updateNoteDrag(note, details);
            });
          },
          onPanEnd: (_) => _endNoteDrag(commit: true),
          onPanCancel: () => _endNoteDrag(commit: false),
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: dragging
                  ? dragAccent.withValues(alpha: 0.92)
                  : Color.fromARGB(alpha, 72, 185, 123),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: dragging
                    ? const Color(0xFFE9FFE7)
                    : (selected
                        ? const Color(0xFFE9FF98)
                        : const Color(0x66000000)),
                width: dragging ? 2.2 : (selected ? 2.0 : 1.0),
              ),
              boxShadow: dragging
                  ? [
                      BoxShadow(
                        color: const Color(0x66A4F4C8).withValues(alpha: 0.75),
                        blurRadius: 8,
                        offset: const Offset(0, 0),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                if (showNoteLabel)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 6,
                        right: handleWidth + 3,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _noteNameForPitch(note.pitch),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: handleWidth,
                    child: MouseRegion(
                      key: ValueKey<String>('piano_note_handle_${note.id}'),
                      cursor: SystemMouseCursors.resizeColumn,
                      child: Container(
                        decoration: BoxDecoration(
                          color: dragging
                              ? dragAccent.withValues(alpha: 0.85)
                              : const Color(0x99FFE17A),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(3),
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
      ),
    );
  }

  bool _isBlackKey(int pitch) {
    const black = <int>{1, 3, 6, 8, 10};
    return black.contains(pitch % 12);
  }

  String _noteNameForPitch(int pitch) {
    const names = <String>[
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = (pitch ~/ 12) - 1;
    return '${names[pitch % 12]}$octave';
  }

  Widget _toolbarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1.0,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
        ),
      ),
    );
  }

  Widget _labeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              value.toStringAsFixed(label == 'Velocity' ? 2 : 0),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PianoGridPainter extends CustomPainter {
  _PianoGridPainter({
    required this.rowHeight,
    required this.pxPerBeat,
    required this.maxPitch,
    required this.minPitch,
    required this.maxBeat,
    required this.beatsPerBar,
    required this.quantizeDivisionsPerBar,
    required this.magnetEnabled,
  });

  final double rowHeight;
  final double pxPerBeat;
  final int maxPitch;
  final int minPitch;
  final double maxBeat;
  final int beatsPerBar;
  final int quantizeDivisionsPerBar;
  final bool magnetEnabled;

  static bool _isBlackPitch(int pitch) {
    const black = <int>{1, 3, 6, 8, 10};
    return black.contains(pitch % 12);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.7;
    final whiteRowFill = Paint()
      ..color = const Color(0xFF585F66).withValues(alpha: 0.32);
    final blackRowFill = Paint()
      ..color = const Color(0xFF454C53).withValues(alpha: 0.82);
    final majorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.5;
    final beatPaint = Paint()
      ..color = Colors.white.withValues(alpha: magnetEnabled ? 0.10 : 0.07)
      ..strokeWidth = magnetEnabled ? 1.25 : 1.1;
    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: magnetEnabled ? 0.08 : 0.05)
      ..strokeWidth = magnetEnabled ? 1.05 : 1.0;

    final pitchCount = (maxPitch - minPitch) + 1;
    for (int r = 0; r < pitchCount; r++) {
      final pitch = maxPitch - r;
      final y = r * rowHeight;
      if (_isBlackPitch(pitch)) {
        canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, rowHeight), blackRowFill);
      } else {
        canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, rowHeight), whiteRowFill);
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }
    canvas.drawLine(
      Offset(0, pitchCount * rowHeight),
      Offset(size.width, pitchCount * rowHeight),
      rowPaint,
    );

    final safeBeatsPerBar = math.max(1, beatsPerBar);
    final safeDivisions = math.max(1, quantizeDivisionsPerBar);
    final divisionBeat = safeBeatsPerBar / safeDivisions;
    final maxBars = (maxBeat / safeBeatsPerBar).ceil() + 1;

    for (int bar = 0; bar <= maxBars; bar++) {
      final barBeat = bar * safeBeatsPerBar;
      final barX = barBeat * pxPerBeat;
      canvas.drawLine(
        Offset(barX, 0),
        Offset(barX, size.height),
        majorPaint,
      );

      for (int d = 1; d < safeDivisions; d++) {
        final beat = barBeat + (d * divisionBeat);
        if (beat > maxBeat) break;
        final x = beat * pxPerBeat;
        final isBeatBoundary = (d * safeBeatsPerBar) % safeDivisions == 0;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          isBeatBoundary ? beatPaint : minorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PianoGridPainter oldDelegate) {
    return rowHeight != oldDelegate.rowHeight ||
        pxPerBeat != oldDelegate.pxPerBeat ||
        maxPitch != oldDelegate.maxPitch ||
        minPitch != oldDelegate.minPitch ||
        maxBeat != oldDelegate.maxBeat ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        quantizeDivisionsPerBar != oldDelegate.quantizeDivisionsPerBar ||
        magnetEnabled != oldDelegate.magnetEnabled;
  }
}
