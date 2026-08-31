import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/instrument_picker_categories.dart';
import 'package:mixroom/helpers/piano_roll_playhead.dart';
import 'package:mixroom/helpers/timeline_grid_policy.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/widgets/desktop_scrollable_slider.dart';

typedef MidiCommitCallback = Future<void> Function({
  required List<MidiNote> notes,
  required Map<String, double> instrumentParams,
  required String instrumentId,
  required String instrumentName,
});

typedef PianoKeyDownCallback = Future<void> Function(
  AudioTrack clip,
  int pitch,
  double velocity, {
  double? startBeat,
});
typedef PianoKeyUpCallback = Future<void> Function(
  AudioTrack clip,
  int pitch,
);
typedef PlayableMidiPitchesResolver = Future<Set<int>> Function(
  String instrumentId,
  Map<String, double> instrumentParams,
);
typedef PianoRollGridResolutionChanged = void Function(
  String clipId,
  int divisionsPerBar,
);

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

class _PianoRollGridOption {
  const _PianoRollGridOption({
    required this.label,
    required this.divisionsPerBar,
  });

  final String label;
  final int divisionsPerBar;
}

class _StepSequencerLane {
  const _StepSequencerLane({
    required this.pitch,
    required this.label,
  });

  final int pitch;
  final String label;
}

class PianoRollEditor extends StatefulWidget {
  const PianoRollEditor({
    super.key,
    required this.clip,
    required this.availableInstruments,
    required this.bpm,
    required this.beatsPerBar,
    this.beatUnit = 4,
    required this.projectPlayheadMs,
    required this.isPlaying,
    required this.magnetEnabled,
    required this.gridMode,
    required this.fixedQuantizeDivisionsPerBar,
    required this.fullscreen,
    required this.isRecording,
    required this.onFullscreenChanged,
    required this.onClose,
    required this.onCommit,
    required this.onScrubRequested,
    this.onPreviewNote,
    this.onKeyboardNoteDown,
    this.onKeyboardNoteUp,
    this.resolvePlayablePitches,
    this.highlightedPitches = const <int>{},
    this.onOpenCurrentInstrumentUi,
    this.canReplaceSamplerSource = false,
    this.onReplaceSamplerSource,
    this.onEffectiveGridResolutionChanged,
    this.initialTab = 0,
    this.tabRequestRevision = 0,
  });

  final AudioTrack clip;
  final List<Map<String, dynamic>> availableInstruments;
  final double bpm;
  final int beatsPerBar;
  final int beatUnit;
  final double projectPlayheadMs;
  final bool isPlaying;
  final bool magnetEnabled;
  final TimelineGridMode gridMode;
  final int fixedQuantizeDivisionsPerBar;
  final bool fullscreen;
  final bool isRecording;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onClose;
  final MidiCommitCallback onCommit;
  final ValueChanged<double> onScrubRequested;
  final Future<void> Function(int pitch, double velocity)? onPreviewNote;
  final PianoKeyDownCallback? onKeyboardNoteDown;
  final PianoKeyUpCallback? onKeyboardNoteUp;
  final PlayableMidiPitchesResolver? resolvePlayablePitches;
  final Set<int> highlightedPitches;
  final Future<bool> Function()? onOpenCurrentInstrumentUi;
  final bool canReplaceSamplerSource;
  final Future<void> Function()? onReplaceSamplerSource;
  final PianoRollGridResolutionChanged? onEffectiveGridResolutionChanged;
  final int initialTab;
  final int tabRequestRevision;

  @override
  State<PianoRollEditor> createState() => _PianoRollEditorState();
}

class _PianoRollEditorState extends State<PianoRollEditor>
    with TickerProviderStateMixin {
  static const String _preferredPianoInstrumentId = 'sfz.vsco.upright_piano';
  static const int _absoluteMinPitch = 0;
  static const int _absoluteMaxPitch = 127;
  static final Set<int> _allMidiPitches = Set<int>.unmodifiable(
    <int>{for (var pitch = 0; pitch <= 127; pitch++) pitch},
  );
  static const Duration _gestureTapBlockDuration = Duration(milliseconds: 150);
  static const double _minRowHeight = 14.0;
  static const double _maxRowHeight = 40.0;
  static const double _minPxPerBeat = 24.0;
  static const double _maxPxPerBeat = 3840.0;
  static const double _touchPinchScaleExponent = 0.65;
  static const double _minTouchPinchStartDistance = 12.0;
  static const double _followPlayheadViewportAnchor = 0.42;
  static const double _rollExtensionChunkBeats = 16.0;
  static const double _rulerHeight = 28.0;
  static const double _pianoKeyBlackWidth = 46.0;
  static const double _visualPlayheadDriftSnapMs = 640.0;
  static const int _sequencerStepsPerBar = 16;
  static const double _minSequencerStepScale = 0.62;
  static const double _maxSequencerStepScale = 1.9;
  static const List<int> _sequencerFillIntervals = <int>[1, 2, 4, 8];
  static const List<_StepSequencerLane> _defaultSequencerLanes =
      <_StepSequencerLane>[
    _StepSequencerLane(pitch: 36, label: 'Kick'),
    _StepSequencerLane(pitch: 38, label: 'Snare'),
    _StepSequencerLane(pitch: 39, label: 'Clap'),
    _StepSequencerLane(pitch: 42, label: 'Hat'),
    _StepSequencerLane(pitch: 46, label: 'Open Hat'),
    _StepSequencerLane(pitch: 48, label: '808'),
    _StepSequencerLane(pitch: 50, label: 'Tom'),
    _StepSequencerLane(pitch: 52, label: 'Perc'),
  ];
  static const List<_PianoRollGridOption> _gridOptions = <_PianoRollGridOption>[
    _PianoRollGridOption(label: '1/4', divisionsPerBar: 4),
    _PianoRollGridOption(label: '1/8', divisionsPerBar: 8),
    _PianoRollGridOption(label: '1/16', divisionsPerBar: 16),
    _PianoRollGridOption(label: '1/32', divisionsPerBar: 32),
  ];

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _gridVerticalController = ScrollController();
  final ScrollController _keysVerticalController = ScrollController();
  final ScrollController _sequencerHorizontalController = ScrollController();
  final GlobalKey _rollViewportKey = GlobalKey();
  final GlobalKey _gridViewportKey = GlobalKey();

  late final TabController _tabController;
  late final Ticker _followViewportTicker;
  late final Ticker _playheadVisualTicker;
  late final Listenable _playheadAndHorizontalScroll;
  final ValueNotifier<double> _visualPlayheadBeat = ValueNotifier<double>(0.0);
  double _visualSampleProjectPlayheadMs = 0.0;
  Duration _visualSampleElapsed = Duration.zero;
  Duration _visualTickerElapsed = Duration.zero;
  int _lastTabIndex = 0;

  double _rowHeight = 22.0;
  double _pxPerBeat = 56.0;
  bool _syncingVerticalScroll = false;

  String? _activeDragNoteId;
  bool _activeDragIsResize = false;
  bool _didMoveDuringDrag = false;
  bool _suppressNextGridTap = false;
  final Map<int, int> _pressedPreviewCounts = <int, int>{};
  final Set<int> _pressedKeyboardPitches = <int>{};
  final Map<int, int> _pianoKeyPitchByPointer = <int, int>{};
  Set<int> _playablePitches = _allMidiPitches;
  int _playablePitchesRequestToken = 0;
  bool _pinchZoomActive = false;
  bool _lockGridScroll = false;
  bool _followPlayhead = false;
  bool _suppressFollowScrollScrub = false;
  bool _initialNoteViewportSyncPending = false;
  int _initialNoteViewportSyncAttempts = 0;
  double _rollViewportWidth = 0.0;
  bool _followScrubUserActive = false;

  late List<MidiNote> _notes;
  late List<MidiNote> _syncedClipNotes;
  late Map<String, double> _params;
  late Map<String, double> _syncedClipParams;
  late String _instrumentId;
  late String _syncedInstrumentId;
  late String _instrumentName;
  late String _syncedInstrumentName;
  late ({int min, int max}) _pinnedPitchRange;
  String _instrumentBrowserCategory = 'All';
  String? _samplerWaveformInstrumentId;
  Future<List<double>>? _samplerWaveformFuture;
  int _activeSequencerPitch = 36;
  int _sequencerVisibleBars = 4;
  double _sequencerStepScale = 1.0;

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
  double? _lastEditedNoteLengthBeats;

  Offset? _boxSelectStartLocal;
  Offset? _boxSelectCurrentLocal;
  int? _desktopBoxSelectPointer;
  int? _desktopErasePointer;
  Offset? _desktopEraseLastLocal;
  bool _desktopEraseChanged = false;
  DateTime _ignoreGridTapUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, Offset> _activeGridPointers = <int, Offset>{};
  final Map<int, Offset> _activeGridGlobalPointers = <int, Offset>{};
  bool _manualPinchActive = false;
  bool _manualPinchUpdateScheduled = false;
  int _manualPinchUpdateToken = 0;
  bool _nativeTrackpadPinchActive = false;
  bool _desktopWheelZoomModifierPressed = false;
  Offset _pinchStartPointA = Offset.zero;
  Offset _pinchStartPointB = Offset.zero;
  double _pinchStartPxPerBeat = 56.0;
  double _pinchStartRowHeight = 22.0;
  double _pinchStartHorizontalOffset = 0.0;
  double _pinchStartVerticalOffset = 0.0;
  double _pinchStartFocalBeat = 0.0;
  double _pinchStartFocalRow = 0.0;
  Offset _pinchStartFocalViewport = Offset.zero;
  double _nativeTrackpadStartPxPerBeat = 56.0;
  double _nativeTrackpadStartRowHeight = 22.0;
  double _nativeTrackpadStartHorizontalOffset = 0.0;
  double _nativeTrackpadStartVerticalOffset = 0.0;
  double _nativeTrackpadFocalDx = 0.0;
  double _nativeTrackpadFocalDy = 0.0;
  double _nativeTrackpadFocalBeat = 0.0;
  double _nativeTrackpadFocalRow = 0.0;
  int? _lastPublishedEffectiveGridDivisions;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2).toInt(),
      vsync: this,
    );
    _tabController.addListener(_handleTabChanged);
    _followViewportTicker = createTicker((_) {
      if (!mounted || !_followPlayhead) {
        _followViewportTicker.stop();
        return;
      }
      if (_followScrubUserActive) return;
      _syncPlayheadViewport();
    });
    _playheadAndHorizontalScroll = Listenable.merge(
      <Listenable>[_visualPlayheadBeat, _horizontalController],
    );
    _playheadVisualTicker = createTicker(_tickVisualPlayhead);
    _loadFromClip(resetPitchRange: true);
    _refreshPlayablePitches();
    _syncVisualPlayheadSample(snap: true);
    _gridVerticalController.addListener(_syncKeysWithGridScroll);
    _sequencerHorizontalController.addListener(_extendSequencerWhenNeeded);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _scheduleInitialNoteViewportSync();
    _publishEffectiveGridResolutionIfChanged();
  }

  @override
  void didUpdateWidget(covariant PianoRollEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabRequestRevision != widget.tabRequestRevision) {
      final requestedTab = widget.initialTab.clamp(0, 2).toInt();
      if (_tabController.index != requestedTab) {
        _lastTabIndex = requestedTab;
        _tabController.animateTo(
          requestedTab,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    }
    if (!oldWidget.isRecording && widget.isRecording) {
      _commitDebounce?.cancel();
      _commitQueued = false;
      _activeDragNoteId = null;
      _activeDragIsResize = false;
      _dragStartNotesById = null;
      _dragAccumDxBeat = 0.0;
      _dragAccumDyRows = 0.0;
      _didMoveDuringDrag = false;
      _boxSelectStartLocal = null;
      _boxSelectCurrentLocal = null;
      _lockGridScroll = false;
      _suppressNextGridTap = false;
      _clearSelection();
    }
    final clipIdentityChanged =
        oldWidget.clip.engineClipId != widget.clip.engineClipId;
    final playablePitchInputsChanged = clipIdentityChanged ||
        _syncedInstrumentId != widget.clip.instrumentId ||
        _instrumentParamsDiffer(
          _syncedClipParams,
          widget.clip.instrumentParams,
        );
    final clipContentChanged = _clipDataDiffersFromSyncedClip(widget.clip);
    if (clipIdentityChanged || clipContentChanged) {
      if (clipIdentityChanged) {
        _releaseAllPianoKeys();
      }
      _loadFromClip(resetPitchRange: clipIdentityChanged);
      if (playablePitchInputsChanged) {
        _refreshPlayablePitches();
      }
      if (clipIdentityChanged) {
        _clearSelection();
        _scheduleInitialNoteViewportSync();
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
    if (oldWidget.resolvePlayablePitches != widget.resolvePlayablePitches &&
        !clipIdentityChanged &&
        !clipContentChanged) {
      _refreshPlayablePitches();
    }
    if (clipIdentityChanged ||
        oldWidget.beatsPerBar != widget.beatsPerBar ||
        oldWidget.beatUnit != widget.beatUnit ||
        oldWidget.gridMode != widget.gridMode ||
        oldWidget.fixedQuantizeDivisionsPerBar !=
            widget.fixedQuantizeDivisionsPerBar ||
        oldWidget.onEffectiveGridResolutionChanged !=
            widget.onEffectiveGridResolutionChanged) {
      if (clipIdentityChanged ||
          oldWidget.onEffectiveGridResolutionChanged !=
              widget.onEffectiveGridResolutionChanged) {
        _lastPublishedEffectiveGridDivisions = null;
      }
      _publishEffectiveGridResolutionIfChanged();
    }
    final playheadDeltaMs =
        (oldWidget.projectPlayheadMs - widget.projectPlayheadMs).abs();
    final visualMsDelta = (_projectMsForBeat(_visualPlayheadBeat.value) -
            widget.projectPlayheadMs)
        .abs();
    final shouldSnapVisualPlayhead = clipIdentityChanged ||
        oldWidget.isPlaying != widget.isPlaying ||
        !widget.isPlaying ||
        playheadDeltaMs > _visualPlayheadDriftSnapMs ||
        visualMsDelta > _visualPlayheadDriftSnapMs;
    if (shouldSnapVisualPlayhead) {
      _syncVisualPlayheadSample(snap: true);
    } else if (widget.isPlaying && !_playheadVisualTicker.isActive) {
      _syncVisualPlayheadSample(snap: false);
    }
    if (_followPlayhead &&
        (oldWidget.fullscreen != widget.fullscreen ||
            (!widget.isPlaying &&
                (oldWidget.projectPlayheadMs - widget.projectPlayheadMs).abs() >
                    0.1))) {
      _schedulePlayheadViewportSync(force: true);
    }
  }

  @override
  void dispose() {
    _playablePitchesRequestToken++;
    _releaseAllPianoKeys();
    _commitDebounce?.cancel();
    _activeGridPointers.clear();
    _activeGridGlobalPointers.clear();
    _manualPinchActive = false;
    _nativeTrackpadPinchActive = false;
    _manualPinchUpdateToken++;
    _playheadVisualTicker.dispose();
    _visualPlayheadBeat.dispose();
    _followViewportTicker.dispose();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _horizontalController.dispose();
    _gridVerticalController.removeListener(_syncKeysWithGridScroll);
    _gridVerticalController.dispose();
    _keysVerticalController.dispose();
    _sequencerHorizontalController.removeListener(_extendSequencerWhenNeeded);
    _sequencerHorizontalController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _releaseAllPianoKeys() {
    if (_pressedKeyboardPitches.isEmpty && _pressedPreviewCounts.isEmpty) {
      _pianoKeyPitchByPointer.clear();
      return;
    }
    final keyboardPitches = _pressedKeyboardPitches.toList(growable: false);
    _pianoKeyPitchByPointer.clear();
    _pressedPreviewCounts.clear();
    _pressedKeyboardPitches.clear();
    final recordCallback = widget.onKeyboardNoteUp;
    if (recordCallback == null) return;
    for (final pitch in keyboardPitches) {
      unawaited(recordCallback(widget.clip, pitch));
    }
  }

  bool _isPitchPlayable(int pitch) => _playablePitches.contains(pitch);

  void _refreshPlayablePitches() {
    final requestToken = ++_playablePitchesRequestToken;
    final resolver = widget.resolvePlayablePitches;
    if (!identical(_playablePitches, _allMidiPitches)) {
      setState(() => _playablePitches = _allMidiPitches);
    }
    if (resolver == null) {
      return;
    }
    final instrumentId = _instrumentId;
    final params = Map<String, double>.from(_params);
    unawaited(() async {
      Set<int> resolved;
      try {
        resolved = await resolver(instrumentId, params);
      } catch (_) {
        resolved = _allMidiPitches;
      }
      if (!mounted || requestToken != _playablePitchesRequestToken) return;
      final normalized = Set<int>.unmodifiable(
        resolved.where((pitch) => pitch >= 0 && pitch <= 127),
      );
      final unavailableHeld = _pressedKeyboardPitches
          .where((pitch) => !normalized.contains(pitch))
          .toList(growable: false);
      _pianoKeyPitchByPointer.removeWhere(
        (_, pitch) => !normalized.contains(pitch),
      );
      for (final pitch in unavailableHeld) {
        _releasePianoKey(pitch, keyboardSource: true);
      }
      if (!mounted || requestToken != _playablePitchesRequestToken) return;
      setState(() => _playablePitches = normalized);
    }());
  }

  void _loadFromClip({required bool resetPitchRange}) {
    _notes = widget.clip.midiNotes.map((n) => n.copy()).toList();
    _syncedClipNotes = widget.clip.midiNotes.map((n) => n.copy()).toList();
    _params = Map<String, double>.from(widget.clip.instrumentParams);
    _syncedClipParams = Map<String, double>.from(widget.clip.instrumentParams);
    _instrumentId = widget.clip.instrumentId;
    _syncedInstrumentId = widget.clip.instrumentId;
    _instrumentName = widget.clip.instrumentName;
    _syncedInstrumentName = widget.clip.instrumentName;
    _ensureDefaultParams();
    _refreshSamplerWaveformFuture();
    final match = widget.availableInstruments.where((spec) {
      return (spec['id'] as String?) == _instrumentId;
    });
    final category =
        match.isEmpty ? 'All' : _instrumentCategoryForSpec(match.first);
    final categories = _instrumentBrowserCategories();
    _instrumentBrowserCategory =
        categories.contains(category) ? category : 'All';
    if (resetPitchRange) {
      _pinnedPitchRange = _pitchRangeForNotes(_notes);
      _lastEditedNoteLengthBeats = null;
      if (_notes.isNotEmpty) {
        _activeSequencerPitch = _notes.first.pitch.clamp(0, 127).toInt();
      } else if (!_currentInstrumentUsesDrumSequencer) {
        _activeSequencerPitch = _defaultSingleSequencerPitch;
      }
      _sequencerVisibleBars =
          math.max(_sequencerVisibleBars, _sequencerBarCount);
    }
  }

  void _ensureDefaultParams() {
    final spec =
        widget.availableInstruments.cast<Map<String, dynamic>?>().firstWhere(
              (candidate) => (candidate?['id'] as String?) == _instrumentId,
              orElse: () => null,
            );
    if (spec != null && _isExternalPluginInstrumentSpec(spec)) {
      return;
    }
    if (_isSampledInstrumentId(_instrumentId)) {
      _params.putIfAbsent('outputGain', () => 0.72);
      _params.putIfAbsent('attackMs', () => 6.0);
      _params.putIfAbsent('decayMs', () => 120.0);
      _params.putIfAbsent('sustainLevel', () => 0.86);
      _params.putIfAbsent('releaseMs', () => 520.0);
      _params.putIfAbsent('sampleStartNorm', () => 0.0);
      _params.putIfAbsent('sampleEndNorm', () => 1.0);
      _params.putIfAbsent('reverseSample', () => 0.0);
      _params.putIfAbsent('normalizeSample', () => 0.0);
      _params.putIfAbsent('samplePlayMode', () => 0.0);
      _params.putIfAbsent('rootNote', () => 60.0);
      _params.putIfAbsent('sampleLowKey', () => 0.0);
      _params.putIfAbsent('sampleHighKey', () => 127.0);
      _params.putIfAbsent('sliceMode', () => 0.0);
      _params.putIfAbsent('sliceCount', () => 8.0);
      _params.putIfAbsent('timeStretchMode', () => 0.0);
      _params.putIfAbsent('sampleFilterCutoffHz', () => 20000.0);
      _params.putIfAbsent('granularMode', () => 0.0);
      _params.putIfAbsent('grainAttackMs', () => 18.0);
      _params.putIfAbsent('grainHoldMs', () => 42.0);
      _params.putIfAbsent('grainSpacingPct', () => 100.0);
      _params.putIfAbsent('waveSpacingPct', () => 100.0);
      _params.putIfAbsent(
          'grainPan', () => _isGranularizerParams() ? 0.34 : 0.0);
      _params.putIfAbsent('grainLfoDepthPct', () => 0.0);
      _params.putIfAbsent('grainLfoSpeedHz', () => 0.8);
      _params.putIfAbsent('grainRandomPct', () => 0.0);
      _params.putIfAbsent('grainTransientMode', () => 0.0);
      _params.putIfAbsent('grainTransientHoldMs', () => 80.0);
      _params.putIfAbsent('grainLoop', () => 1.0);
      _params.putIfAbsent('grainPositionHold', () => 0.0);
      _params.putIfAbsent('grainKeyMode', () => 0.0);
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
    final normalized = id.trim().toLowerCase();
    return normalized.startsWith('sfz.') || normalized.startsWith('sfz_asset:');
  }

  bool _isGranularizerParams() {
    final name = widget.clip.instrumentName.trim().toLowerCase();
    return (_params['granularMode'] ?? 0.0) >= 0.5 ||
        name.endsWith('granularizer');
  }

  void _refreshSamplerWaveformFuture() {
    if (!_isSampledInstrumentId(_instrumentId)) {
      _samplerWaveformInstrumentId = null;
      _samplerWaveformFuture = null;
      return;
    }
    if (_samplerWaveformInstrumentId == _instrumentId &&
        _samplerWaveformFuture != null) {
      return;
    }
    _samplerWaveformInstrumentId = _instrumentId;
    _samplerWaveformFuture = _loadSamplerWaveformPeaks(_instrumentId);
  }

  Future<List<double>> _loadSamplerWaveformPeaks(String instrumentId) async {
    final sfzPath = _sfzPathForInstrumentId(instrumentId);
    if (sfzPath == null) return const <double>[];
    try {
      final sfzFile = File(sfzPath);
      if (!sfzFile.existsSync()) return const <double>[];
      final sfz = await sfzFile.readAsString();
      final sampleMatch = RegExp(r'(?:^|\s)sample=([^\s]+)').firstMatch(sfz);
      if (sampleMatch == null) return const <double>[];
      final sampleToken = sampleMatch.group(1)?.trim() ?? '';
      if (sampleToken.isEmpty) return const <double>[];
      final samplePath = _pJoinPortable(
        sfzFile.parent.path,
        sampleToken.replaceAll('\\', '/'),
      );
      final sampleFile = File(samplePath);
      if (!sampleFile.existsSync()) return const <double>[];
      final bytes = await sampleFile.readAsBytes();
      return _wavPeaks(bytes, 96);
    } catch (_) {
      return const <double>[];
    }
  }

  String? _sfzPathForInstrumentId(String instrumentId) {
    final trimmed = instrumentId.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('sfz_asset:')) {
      final path = trimmed.substring('sfz_asset:'.length).trim();
      return path.isEmpty ? null : path;
    }
    final spec = _instrumentSpecForId(trimmed);
    final path = (spec?['sfzAssetPath'] as String?)?.trim() ?? '';
    return path.isEmpty ? null : path;
  }

  String _pJoinPortable(String parent, String child) {
    if (child.startsWith('/')) return child;
    final cleanParent =
        parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent;
    return '$cleanParent/$child';
  }

  int _findWavChunk(Uint8List bytes, String chunkId) {
    for (int i = 12; i + 8 <= bytes.length;) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size =
          ByteData.sublistView(bytes, i + 4, i + 8).getUint32(0, Endian.little);
      if (id == chunkId) return i;
      i += 8 + size + (size.isOdd ? 1 : 0);
    }
    return -1;
  }

  List<double> _wavPeaks(Uint8List bytes, int bins) {
    if (bytes.length < 44) return const <double>[];
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return const <double>[];
    }
    final fmtStart = _findWavChunk(bytes, 'fmt ');
    final dataStart = _findWavChunk(bytes, 'data');
    if (fmtStart < 0 || dataStart < 0) return const <double>[];
    final fmtSize = ByteData.sublistView(bytes, fmtStart + 4, fmtStart + 8)
        .getUint32(0, Endian.little);
    if (fmtSize < 16) return const <double>[];
    final fmt =
        ByteData.sublistView(bytes, fmtStart + 8, fmtStart + 8 + fmtSize);
    final audioFormat = fmt.getUint16(0, Endian.little);
    final channels = fmt.getUint16(2, Endian.little);
    final bitsPerSample = fmt.getUint16(14, Endian.little);
    if (audioFormat != 1 || channels < 1 || channels > 2) {
      return const <double>[];
    }
    if (bitsPerSample != 16 && bitsPerSample != 24) return const <double>[];
    final dataSize = ByteData.sublistView(bytes, dataStart + 4, dataStart + 8)
        .getUint32(0, Endian.little);
    final dataOffset = dataStart + 8;
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = bytesPerSample * channels;
    final frameCount = dataSize ~/ frameSize;
    if (frameCount <= 0 || dataOffset + dataSize > bytes.length) {
      return const <double>[];
    }

    final peaks = List<double>.filled(bins, 0.0);
    int ptr = dataOffset;
    for (int frame = 0; frame < frameCount; frame++) {
      double framePeak = 0.0;
      for (int ch = 0; ch < channels; ch++) {
        int signed;
        if (bitsPerSample == 16) {
          final v = bytes[ptr] | (bytes[ptr + 1] << 8);
          signed = (v & 0x8000) != 0 ? v - 0x10000 : v;
          ptr += 2;
          framePeak = math.max(framePeak, (signed / 32768.0).abs());
        } else {
          final v = bytes[ptr] | (bytes[ptr + 1] << 8) | (bytes[ptr + 2] << 16);
          signed = (v & 0x800000) != 0 ? v - 0x1000000 : v;
          ptr += 3;
          framePeak = math.max(framePeak, (signed / 8388608.0).abs());
        }
      }
      final bin = ((frame / math.max(1, frameCount)) * bins)
          .floor()
          .clamp(0, bins - 1)
          .toInt();
      peaks[bin] = math.max(peaks[bin], framePeak);
    }
    final maxPeak = peaks.fold<double>(0.0, math.max);
    if (maxPeak <= 0.0) return peaks;
    return peaks.map((peak) => (peak / maxPeak).clamp(0.0, 1.0)).toList();
  }

  Map<String, dynamic>? _instrumentSpecForId(String id) {
    for (final spec in widget.availableInstruments) {
      if ((spec['id'] as String?) == id) {
        return spec;
      }
    }
    return null;
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
    if (_isExternalPluginInstrumentSpec(spec)) {
      return params;
    }
    if (sampled) {
      params.putIfAbsent('outputGain', () => 0.72);
      params.putIfAbsent('attackMs', () => 6.0);
      params.putIfAbsent('decayMs', () => 120.0);
      params.putIfAbsent('sustainLevel', () => 0.86);
      params.putIfAbsent('releaseMs', () => 520.0);
      params.putIfAbsent('sampleStartNorm', () => 0.0);
      params.putIfAbsent('sampleEndNorm', () => 1.0);
      params.putIfAbsent('reverseSample', () => 0.0);
      params.putIfAbsent('normalizeSample', () => 0.0);
      params.putIfAbsent('samplePlayMode', () => 0.0);
      params.putIfAbsent('rootNote', () => 60.0);
      params.putIfAbsent('sampleLowKey', () => 0.0);
      params.putIfAbsent('sampleHighKey', () => 127.0);
      params.putIfAbsent('sliceMode', () => 0.0);
      params.putIfAbsent('sliceCount', () => 8.0);
      params.putIfAbsent('timeStretchMode', () => 0.0);
      params.putIfAbsent('sampleFilterCutoffHz', () => 20000.0);
      params.putIfAbsent('stereoWidth', () => 0.0);
      params.putIfAbsent('granularMode', () => 0.0);
      params.putIfAbsent('grainAttackMs', () => 18.0);
      params.putIfAbsent('grainHoldMs', () => 42.0);
      params.putIfAbsent('grainSpacingPct', () => 100.0);
      params.putIfAbsent('waveSpacingPct', () => 100.0);
      params.putIfAbsent('grainPan', () => 0.0);
      params.putIfAbsent('grainLfoDepthPct', () => 0.0);
      params.putIfAbsent('grainLfoSpeedHz', () => 0.8);
      params.putIfAbsent('grainRandomPct', () => 0.0);
      params.putIfAbsent('grainTransientMode', () => 0.0);
      params.putIfAbsent('grainTransientHoldMs', () => 80.0);
      params.putIfAbsent('grainLoop', () => 1.0);
      params.putIfAbsent('grainPositionHold', () => 0.0);
      params.putIfAbsent('grainKeyMode', () => 0.0);
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

  bool _isExternalPluginInstrumentSpec(Map<String, dynamic> spec) {
    return spec['isExternalPlugin'] == true;
  }

  bool get _currentInstrumentIsExternalPlugin {
    final spec = _instrumentSpecForId(_instrumentId);
    if (spec == null) return false;
    return _isExternalPluginInstrumentSpec(spec);
  }

  void _setInstrumentFromSpec(Map<String, dynamic> spec) {
    final id = (spec['id'] as String?)?.trim();
    if (id == null || id.isEmpty) return;
    final name = (spec['name'] as String?)?.trim();
    setState(() {
      _instrumentId = id;
      _instrumentName = (name == null || name.isEmpty) ? id : name;
      _params = _instrumentParamsFromSpec(spec);
      if (_notes.isEmpty && !_currentInstrumentUsesDrumSequencer) {
        _activeSequencerPitch = _defaultSingleSequencerPitch;
      }
      _refreshSamplerWaveformFuture();
    });
    _refreshPlayablePitches();
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

  void _jumpBothVerticalControllers(
    double targetOffset, {
    double? contentHeight,
  }) {
    _syncingVerticalScroll = true;
    if (_gridVerticalController.hasClients) {
      final viewport = _gridVerticalController.position.viewportDimension;
      final maxExtent = contentHeight == null
          ? _gridVerticalController.position.maxScrollExtent
          : math.max(0.0, contentHeight - viewport);
      final gridTarget = targetOffset.clamp(
        _gridVerticalController.position.minScrollExtent,
        maxExtent,
      );
      _gridVerticalController.jumpTo(gridTarget);
    }
    if (_keysVerticalController.hasClients) {
      final viewport = _keysVerticalController.position.viewportDimension;
      final maxExtent = contentHeight == null
          ? _keysVerticalController.position.maxScrollExtent
          : math.max(0.0, contentHeight - viewport);
      final keysTarget = targetOffset.clamp(
        _keysVerticalController.position.minScrollExtent,
        maxExtent,
      );
      _keysVerticalController.jumpTo(keysTarget);
    }
    _syncingVerticalScroll = false;
  }

  double get _msPerBeat => 60000.0 / widget.bpm.clamp(1.0, 400.0);

  ({int min, int max}) _pitchRangeForNotes(List<MidiNote> _) =>
      (min: _absoluteMinPitch, max: _absoluteMaxPitch);

  ({int min, int max}) get _visiblePitchRange => _pinnedPitchRange;

  int get _pitchCount {
    final pitchRange = _visiblePitchRange;
    return (pitchRange.max - pitchRange.min) + 1;
  }

  List<MidiNote> get _displayNotes =>
      widget.isRecording ? widget.clip.midiNotes : _notes;

  double get _contentHeight => _pitchCount * _rowHeight;

  double get _followLeadingPaddingPx => _followPlayhead
      ? _rollViewportWidth * _followPlayheadViewportAnchor
      : 0.0;

  double get _clipSpanBeat {
    final spanMs = (widget.clip.trimEnd - widget.clip.trimStart).inMilliseconds;
    if (spanMs <= 0) return 0.0;
    return spanMs / _msPerBeat;
  }

  double get _maxBeat {
    var beat = pianoRollContentEndBeat(
      clipSpanBeat: _clipSpanBeat,
      playheadBeat: math.max(_playheadBeat, _visualClipPlayheadBeat),
    );
    for (final n in _displayNotes) {
      beat = math.max(beat, n.startBeat + n.lengthBeats + 1.0);
    }
    if (_horizontalController.hasClients) {
      final visibleEndBeat = (_horizontalController.offset +
              _horizontalController.position.viewportDimension) /
          _pxPerBeat;
      final extendedVisibleEndBeat =
          ((visibleEndBeat + 16.0) / _rollExtensionChunkBeats).ceil() *
              _rollExtensionChunkBeats;
      beat = math.max(beat, extendedVisibleEndBeat);
    }
    return beat;
  }

  double get _contentWidth => _followLeadingPaddingPx + (_maxBeat * _pxPerBeat);

  double _xForBeat(double beat) =>
      _followLeadingPaddingPx + (beat * _pxPerBeat);

  double _beatForProjectPlayheadMs(double projectPlayheadMs) {
    return ((projectPlayheadMs -
                (widget.clip.offset * 1000.0) +
                widget.clip.trimStart.inMilliseconds) /
            _msPerBeat)
        .toDouble();
  }

  double _visibleBeatForProjectPlayheadMs(double projectPlayheadMs) =>
      visiblePianoRollPlayheadBeat(
        _beatForProjectPlayheadMs(projectPlayheadMs),
      );

  double get _visualClipPlayheadBeat => _visualPlayheadBeat.value;

  void _setVisualPlayheadBeat(double beat) {
    final next = visiblePianoRollPlayheadBeat(beat);
    if ((_visualPlayheadBeat.value - next).abs() < 0.0001) return;
    _visualPlayheadBeat.value = next;
  }

  void _syncVisualPlayheadSample({required bool snap}) {
    final sampleMs = widget.projectPlayheadMs.isFinite
        ? math.max(0.0, widget.projectPlayheadMs)
        : 0.0;
    _visualSampleProjectPlayheadMs = sampleMs;
    _visualSampleElapsed =
        _playheadVisualTicker.isActive ? _visualTickerElapsed : Duration.zero;
    if (snap || !widget.isPlaying) {
      _setVisualPlayheadBeat(_visibleBeatForProjectPlayheadMs(sampleMs));
    }
    if (widget.isPlaying) {
      if (!_playheadVisualTicker.isActive) {
        _visualTickerElapsed = Duration.zero;
        _visualSampleElapsed = Duration.zero;
        _playheadVisualTicker.start();
      }
    } else {
      _playheadVisualTicker.stop();
      _visualTickerElapsed = Duration.zero;
      _visualSampleElapsed = Duration.zero;
    }
  }

  void _tickVisualPlayhead(Duration elapsed) {
    _visualTickerElapsed = elapsed;
    if (!mounted || !widget.isPlaying) {
      _playheadVisualTicker.stop();
      return;
    }
    final elapsedSinceSample = elapsed >= _visualSampleElapsed
        ? elapsed - _visualSampleElapsed
        : Duration.zero;
    final visualMs = _visualSampleProjectPlayheadMs +
        (elapsedSinceSample.inMicroseconds / 1000.0);
    _setVisualPlayheadBeat(_visibleBeatForProjectPlayheadMs(visualMs));
  }

  double get _barLengthBeats {
    final numerator = math.max(1, widget.beatsPerBar);
    final denominator = math.max(1, widget.beatUnit);
    return numerator * 4.0 / denominator;
  }

  double get _quantizeBeat {
    final safeDivisions = math.max(1, _effectiveQuantizeDivisionsPerBar);
    return _barLengthBeats / safeDivisions;
  }

  int get _effectiveQuantizeDivisionsPerBar {
    final pixelsPerBar = TimelineGridPolicy.pianoRollPixelsPerBar(
      beatsPerBar: widget.beatsPerBar,
      beatUnit: widget.beatUnit,
      pixelsPerBeat: _pxPerBeat,
    );
    return TimelineGridPolicy.resolveDivisionsPerBar(
      mode: widget.gridMode,
      fixedDivisionsPerBar: widget.fixedQuantizeDivisionsPerBar,
      pixelsPerBar: pixelsPerBar,
    );
  }

  void _publishEffectiveGridResolutionIfChanged() {
    if (widget.onEffectiveGridResolutionChanged == null) return;
    final divisions = _effectiveQuantizeDivisionsPerBar;
    if (_lastPublishedEffectiveGridDivisions == divisions) return;
    _lastPublishedEffectiveGridDivisions = divisions;
    final clipId = widget.clip.clipId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.clip.clipId != clipId) return;
      if (_effectiveQuantizeDivisionsPerBar != divisions) return;
      widget.onEffectiveGridResolutionChanged?.call(clipId, divisions);
    });
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
    for (final n in _displayNotes) {
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

  double get _sequencerStepLengthBeat =>
      _barLengthBeats / _sequencerStepsPerBar;

  int get _sequencerBarCount {
    final barLength = _barLengthBeats;
    var spanBeat = math.max(barLength, _clipSpanBeat);
    for (final note in _displayNotes) {
      spanBeat = math.max(spanBeat, note.startBeat + note.lengthBeats);
    }
    return math.max(1, (spanBeat / barLength).ceil());
  }

  int get _sequencerPatternBars =>
      math.max(_sequencerVisibleBars, math.max(4, _sequencerBarCount));

  int get _sequencerTotalSteps => _sequencerPatternBars * _sequencerStepsPerBar;

  double get _sequencerPatternLengthBeat =>
      _sequencerTotalSteps * _sequencerStepLengthBeat;

  List<_StepSequencerLane> get _sequencerLanes {
    final seen = <int>{};
    final lanes = <_StepSequencerLane>[];
    for (final lane in _defaultSequencerLanes) {
      seen.add(lane.pitch);
      lanes.add(lane);
    }

    final extraPitches = _displayNotes
        .map((note) => note.pitch.clamp(0, 127).toInt())
        .where((pitch) => !seen.contains(pitch))
        .toSet()
        .toList()
      ..sort();
    for (final pitch in extraPitches) {
      lanes.add(_StepSequencerLane(
        pitch: pitch,
        label: _noteNameForPitch(pitch),
      ));
    }

    return lanes;
  }

  int get _effectiveSequencerPitch {
    final lanes = _sequencerLanes;
    if (lanes.any((lane) => lane.pitch == _activeSequencerPitch)) {
      return _activeSequencerPitch;
    }
    return lanes.isEmpty ? 36 : lanes.first.pitch;
  }

  bool get _currentInstrumentUsesDrumSequencer {
    final spec = _instrumentSpecForId(_instrumentId);
    final id = _instrumentId.trim().toLowerCase();
    final name = _instrumentName.trim().toLowerCase();
    final category = (spec?['category'] as String? ?? '').trim().toLowerCase();
    final picker =
        (spec?['pickerCategory'] as String? ?? '').trim().toLowerCase();
    final sfzPath =
        (spec?['sfzAssetPath'] as String? ?? '').trim().toLowerCase();
    final text = '$id $name $sfzPath';
    final drumLike = category == 'drum' ||
        picker == 'drums' ||
        text.contains('drum') ||
        text.contains('808');
    final kitLike = id.startsWith('mixroom.drum_') ||
        text.contains('drum kit') ||
        text.contains('drum_kit') ||
        text.contains('drumstarter') ||
        text.contains('kit') ||
        text.contains('breakbeat') ||
        text.contains('dnb starter') ||
        text.contains('trap starter') ||
        text.contains('808 starter') ||
        text.contains('beat kit');
    return drumLike && kitLike;
  }

  bool get _currentInstrumentIsSingleDrum {
    final spec = _instrumentSpecForId(_instrumentId);
    final id = _instrumentId.trim().toLowerCase();
    final name = _instrumentName.trim().toLowerCase();
    final category = (spec?['category'] as String? ?? '').trim().toLowerCase();
    final picker =
        (spec?['pickerCategory'] as String? ?? '').trim().toLowerCase();
    return !_currentInstrumentUsesDrumSequencer &&
        (category == 'drum' ||
            picker == 'drums' ||
            id.contains('kick') ||
            name.contains('kick') ||
            name.contains('snare') ||
            name.contains('hat') ||
            name.contains('clap'));
  }

  int get _defaultSingleSequencerPitch {
    final root = _params['rootNote'];
    if (root != null && root.isFinite) {
      return root.round().clamp(0, 127).toInt();
    }
    return _currentInstrumentIsSingleDrum ? 36 : 60;
  }

  int get _effectiveSingleSequencerPitch {
    if (_notes.isEmpty &&
        _activeSequencerPitch == 36 &&
        !_currentInstrumentIsSingleDrum) {
      return _defaultSingleSequencerPitch;
    }
    return _activeSequencerPitch.clamp(0, 127).toInt();
  }

  int get _effectiveSequencerEditPitch {
    return _currentInstrumentUsesDrumSequencer
        ? _effectiveSequencerPitch
        : _effectiveSingleSequencerPitch;
  }

  double _sequencerStartBeatForStep(int step) {
    final safeStep =
        step.clamp(0, math.max(0, _sequencerTotalSteps - 1)).toInt();
    return safeStep * _sequencerStepLengthBeat;
  }

  bool _noteStartsInSequencerStep(MidiNote note, int step) {
    final start = _sequencerStartBeatForStep(step);
    final end = start + _sequencerStepLengthBeat;
    const epsilon = 0.0001;
    return note.startBeat >= start - epsilon && note.startBeat < end - epsilon;
  }

  int _sequencerNoteIndexAt({
    required int pitch,
    required int step,
  }) {
    return _notes.indexWhere(
      (note) => note.pitch == pitch && _noteStartsInSequencerStep(note, step),
    );
  }

  List<int> _sequencerNoteIndexesInPattern(int pitch) {
    final patternEnd = _sequencerPatternLengthBeat;
    const epsilon = 0.0001;
    final indexes = <int>[];
    for (int i = 0; i < _notes.length; i++) {
      final note = _notes[i];
      if (note.pitch != pitch) continue;
      if (note.startBeat >= -epsilon && note.startBeat < patternEnd - epsilon) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  MidiNote _newSequencerNote({
    required int pitch,
    required int step,
    double? velocity,
  }) {
    return MidiNote(
      id: 'seq_${DateTime.now().microsecondsSinceEpoch}_${pitch}_$step',
      pitch: pitch.clamp(0, 127).toInt(),
      startBeat: _sequencerStartBeatForStep(step),
      lengthBeats: _sequencerStepLengthBeat,
      velocity:
          (velocity ?? _velocityForSequencerPitch(pitch)).clamp(0.05, 1.0),
    );
  }

  double _velocityForSequencerPitch(int pitch) {
    final notes = _notes.where((note) => note.pitch == pitch).toList();
    if (notes.isEmpty) return _selectedAverageVelocity;
    final total = notes.fold<double>(0.0, (sum, note) => sum + note.velocity);
    return (total / notes.length).clamp(0.05, 1.0);
  }

  int _sequencerHitCountForPitch(int pitch) {
    return _sequencerNoteIndexesInPattern(pitch).length;
  }

  void _toggleSequencerStep({
    required int pitch,
    required int step,
  }) {
    if (widget.isRecording) return;
    final existingIndex = _sequencerNoteIndexAt(pitch: pitch, step: step);
    setState(() {
      _activeSequencerPitch = pitch.clamp(0, 127).toInt();
      if (existingIndex >= 0) {
        _notes.removeAt(existingIndex);
        _clearSelection();
      } else {
        final note = _newSequencerNote(pitch: pitch, step: step);
        _notes.add(note);
        _sortNotesInPlace();
        _selectSingle(note.id);
        _lastEditedNoteLengthBeats = note.lengthBeats;
        _previewPianoKey(note.pitch, velocity: note.velocity);
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          _releasePianoKey(note.pitch);
        });
      }
    });
    _queueCommit(immediate: true);
  }

  void _fillSequencerEvery(int intervalSteps) {
    if (widget.isRecording) return;
    final safeInterval = intervalSteps.clamp(1, _sequencerStepsPerBar).toInt();
    final pitch = _effectiveSequencerEditPitch;
    setState(() {
      final removeIndexes = _sequencerNoteIndexesInPattern(pitch).reversed;
      for (final index in removeIndexes) {
        _notes.removeAt(index);
      }
      final velocity = _velocityForSequencerPitch(pitch);
      for (int step = 0; step < _sequencerTotalSteps; step += safeInterval) {
        _notes.add(_newSequencerNote(
          pitch: pitch,
          step: step,
          velocity: velocity,
        ));
      }
      _activeSequencerPitch = pitch;
      _clearSelection();
      _sortNotesInPlace();
    });
    _queueCommit(immediate: true);
  }

  void _clearSequencerLane() {
    if (widget.isRecording) return;
    final pitch = _effectiveSequencerEditPitch;
    final indexes = _sequencerNoteIndexesInPattern(pitch);
    if (indexes.isEmpty) return;
    setState(() {
      for (final index in indexes.reversed) {
        _notes.removeAt(index);
      }
      _clearSelection();
    });
    _queueCommit(immediate: true);
  }

  void _setSequencerStepScale(double value) {
    final next =
        value.clamp(_minSequencerStepScale, _maxSequencerStepScale).toDouble();
    if ((next - _sequencerStepScale).abs() < 0.001) return;
    setState(() {
      _sequencerStepScale = next;
    });
  }

  void _setSequencerVisibleBars(int bars) {
    final minBars = math.max(4, _sequencerBarCount);
    final next = bars.clamp(minBars, 64).toInt();
    if (next == _sequencerVisibleBars) return;
    setState(() {
      _sequencerVisibleBars = next;
    });
  }

  void _setSingleSequencerPitch(int pitch) {
    if (widget.isRecording) return;
    final next = pitch.clamp(0, 127).toInt();
    if (next == _effectiveSingleSequencerPitch) return;
    setState(() {
      _activeSequencerPitch = next;
    });
    _previewPianoKey(next);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _releasePianoKey(next);
    });
  }

  void _extendSequencerWhenNeeded() {
    if (!_sequencerHorizontalController.hasClients) return;
    final position = _sequencerHorizontalController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels < position.maxScrollExtent - 280) return;
    if (!mounted) return;
    if (_sequencerVisibleBars >= 64) return;
    setState(() {
      _sequencerVisibleBars = math.min(_sequencerVisibleBars + 2, 64);
    });
  }

  double get _playheadBeat =>
      _beatForProjectPlayheadMs(widget.projectPlayheadMs);

  double get _transportPlayheadBeat =>
      visiblePianoRollPlayheadBeat(_playheadBeat);

  double get _followScrubBeat => _visualClipPlayheadBeat;

  double get _visiblePlayheadBeat =>
      _followPlayhead ? _followScrubBeat : _transportPlayheadBeat;

  double _projectMsForBeat(double beat) {
    return math.max(
      0.0,
      (widget.clip.offset * 1000.0) -
          widget.clip.trimStart.inMilliseconds +
          (beat * _msPerBeat),
    );
  }

  bool get _desktopSelectionModifierActive {
    final keyboard = HardwareKeyboard.instance;
    return PlatformCapabilities.current.isDesktop &&
        (Platform.isMacOS ? keyboard.isMetaPressed : keyboard.isControlPressed);
  }

  bool get _desktopWheelZoomAvailable {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  bool get _desktopWheelZoomModifierActive {
    if (!_desktopWheelZoomAvailable) return false;
    final keyboard = HardwareKeyboard.instance;
    return Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    _syncDesktopWheelZoomModifierState();
    return false;
  }

  void _syncDesktopWheelZoomModifierState() {
    final next = _desktopWheelZoomModifierActive;
    if (_desktopWheelZoomModifierPressed == next) return;
    if (!mounted) {
      _desktopWheelZoomModifierPressed = next;
      return;
    }
    setState(() {
      _desktopWheelZoomModifierPressed = next;
    });
  }

  Widget _hideDesktopScrollbars(Widget child) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }

  void _schedulePlayheadViewportSync({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPlayheadViewport(force: force);
    });
  }

  void _setFollowPlayhead(bool enabled) {
    if (_followPlayhead == enabled) return;
    setState(() {
      _followPlayhead = enabled;
    });
    if (enabled) {
      if (!_followViewportTicker.isActive) {
        _followViewportTicker.start();
      }
      _schedulePlayheadViewportSync(force: true);
    } else {
      _followViewportTicker.stop();
    }
  }

  void _syncPlayheadViewport({bool force = false}) {
    if (!_followPlayhead || !_horizontalController.hasClients) return;
    if (_pinchZoomActive) return;
    if (_followScrubUserActive) return;
    if (!_followScrubBeat.isFinite) return;
    final targetOffset = _followScrubBeat * _pxPerBeat;
    final currentOffset = _horizontalController.offset;
    final viewport = _horizontalController.position.viewportDimension;
    final rebaseThreshold = math.max(240.0, viewport * 0.42);
    if (!force && (targetOffset - currentOffset).abs() < rebaseThreshold) {
      return;
    }
    _jumpHorizontalTo(targetOffset, suppressFollowScrub: true);
  }

  void _jumpHorizontalTo(
    double offset, {
    bool suppressFollowScrub = false,
    double? contentWidth,
  }) {
    if (!_horizontalController.hasClients) return;
    final viewport = _horizontalController.position.viewportDimension;
    final maxExtent = contentWidth == null
        ? _horizontalController.position.maxScrollExtent
        : math.max(0.0, contentWidth - viewport);
    final clampedOffset = offset.clamp(
      _horizontalController.position.minScrollExtent,
      maxExtent,
    );
    if ((clampedOffset - _horizontalController.offset).abs() < 0.5) return;
    _suppressFollowScrollScrub = suppressFollowScrub;
    _horizontalController.jumpTo(clampedOffset);
    _suppressFollowScrollScrub = false;
  }

  void _scheduleInitialNoteViewportSync() {
    _initialNoteViewportSyncAttempts = 0;
    if (_initialNoteViewportSyncPending) return;
    _initialNoteViewportSyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncInitialNoteViewport();
    });
  }

  void _syncInitialNoteViewport() {
    if (!mounted) {
      _initialNoteViewportSyncPending = false;
      return;
    }
    final verticalReady = _gridVerticalController.hasClients &&
        _keysVerticalController.hasClients &&
        _gridVerticalController.position.viewportDimension > 0.0;
    final horizontalReady = _notes.isEmpty ||
        (_horizontalController.hasClients &&
            _horizontalController.position.viewportDimension > 0.0);
    if (!verticalReady || !horizontalReady) {
      if (_initialNoteViewportSyncAttempts++ < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncInitialNoteViewport();
        });
      } else {
        _initialNoteViewportSyncPending = false;
      }
      return;
    }

    final pitchStats = _notePitchStats();
    final beatStats = _noteBeatStats();
    final verticalViewport = _gridVerticalController.position.viewportDimension;
    final horizontalViewport = _horizontalController.position.viewportDimension;
    final desiredRows = math.min(
      _pitchCount.toDouble(),
      math.max(12.0, pitchStats.span + 8.0),
    );
    final desiredRowHeight =
        (verticalViewport / desiredRows).clamp(_minRowHeight, _maxRowHeight);
    final desiredBeats = math.max(4.0, beatStats.span + 2.0);
    final desiredPxPerBeat =
        (horizontalViewport / desiredBeats).clamp(_minPxPerBeat, _maxPxPerBeat);
    final nextRowHeight = math.min(_rowHeight, desiredRowHeight).toDouble();
    final nextPxPerBeat = math.min(_pxPerBeat, desiredPxPerBeat).toDouble();
    final zoomChanged = (nextRowHeight - _rowHeight).abs() > 0.2 ||
        (nextPxPerBeat - _pxPerBeat).abs() > 0.2;
    if (zoomChanged) {
      setState(() {
        _rowHeight = nextRowHeight;
        _pxPerBeat = nextPxPerBeat;
      });
      _publishEffectiveGridResolutionIfChanged();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerInitialNoteViewport();
      _initialNoteViewportSyncPending = false;
    });
  }

  ({double average, double span}) _notePitchStats() {
    if (_notes.isEmpty) return (average: 60.0, span: 1.0);
    var minPitch = _notes.first.pitch;
    var maxPitch = _notes.first.pitch;
    var sum = 0.0;
    for (final note in _notes) {
      minPitch = math.min(minPitch, note.pitch);
      maxPitch = math.max(maxPitch, note.pitch);
      sum += note.pitch;
    }
    return (
      average: sum / _notes.length,
      span: (maxPitch - minPitch + 1).toDouble(),
    );
  }

  ({double center, double span}) _noteBeatStats() {
    if (_notes.isEmpty) return (center: 0.0, span: 4.0);
    var minBeat = _notes.first.startBeat;
    var maxBeat = _notes.first.startBeat + _notes.first.lengthBeats;
    var centerSum = 0.0;
    for (final note in _notes) {
      minBeat = math.min(minBeat, note.startBeat);
      maxBeat = math.max(maxBeat, note.startBeat + note.lengthBeats);
      centerSum += note.startBeat + (note.lengthBeats * 0.5);
    }
    return (
      center: centerSum / _notes.length,
      span: math.max(0.0, maxBeat - minBeat),
    );
  }

  void _centerInitialNoteViewport() {
    if (!_gridVerticalController.hasClients ||
        !_keysVerticalController.hasClients ||
        (_notes.isNotEmpty && !_horizontalController.hasClients)) {
      return;
    }
    final pitchStats = _notePitchStats();
    final verticalViewport = _gridVerticalController.position.viewportDimension;
    final targetRow = _visiblePitchRange.max - pitchStats.average + 0.5;
    final targetV = (targetRow * _rowHeight) - (verticalViewport * 0.5);
    _jumpBothVerticalControllers(targetV);

    final horizontalViewport = _horizontalController.position.viewportDimension;
    final targetH =
        _xForBeat(_transportPlayheadBeat) - (horizontalViewport * 0.5);
    _jumpHorizontalTo(targetH);
  }

  bool _handleFollowModeScrollNotification(ScrollNotification notification) {
    if (!_followPlayhead) return false;
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _followScrubUserActive = true;
      return false;
    }
    if (notification is ScrollEndNotification) {
      _followScrubUserActive = false;
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      _followScrubUserActive = false;
      return false;
    }
    if (notification is! ScrollUpdateNotification ||
        _suppressFollowScrollScrub) {
      return false;
    }
    if (notification.dragDetails != null) {
      _followScrubUserActive = true;
    }
    final beat = (notification.metrics.pixels / _pxPerBeat).clamp(0.0, 9999.0);
    final targetMs = math.max(
      0.0,
      (widget.clip.offset * 1000.0) -
          widget.clip.trimStart.inMilliseconds +
          (beat * _msPerBeat),
    );
    _visualSampleProjectPlayheadMs = targetMs;
    _visualSampleElapsed = _visualTickerElapsed;
    _setVisualPlayheadBeat(beat);
    widget.onScrubRequested(targetMs);
    return false;
  }

  void _setPlayheadFromBeat(double beat) {
    final safeBeat = beat.clamp(0.0, 9999.0).toDouble();
    final projectMs = _projectMsForBeat(safeBeat);
    _visualSampleProjectPlayheadMs = projectMs;
    _visualSampleElapsed = _visualTickerElapsed;
    _setVisualPlayheadBeat(safeBeat);
    widget.onScrubRequested(projectMs);
  }

  void _queueCommit({bool immediate = false}) {
    _commitDebounce?.cancel();
    if (widget.isRecording) {
      _commitQueued = false;
      return;
    }
    if (immediate) {
      unawaited(_commitNow());
      return;
    }
    _commitDebounce = Timer(const Duration(milliseconds: 160), _commitNow);
  }

  Future<void> _commitNow() async {
    if (widget.isRecording) return;
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

  double _newNoteLengthBeat() {
    final remembered = _lastEditedNoteLengthBeats;
    if (remembered != null) {
      return remembered.clamp(_minimumLengthBeat, 64.0).toDouble();
    }
    return widget.magnetEnabled ? _quantizeBeat : 1.0;
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
        _lockGridScroll = false;
      });
      return;
    }

    final hits = <String>{};
    for (final note in _notes) {
      final noteRect = Rect.fromLTWH(
        _xForBeat(note.startBeat),
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
      _lockGridScroll = false;
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
    return _snapBeat(
      ((x - _followLeadingPaddingPx) / _pxPerBeat).clamp(0.0, 9999.0),
    );
  }

  double _unsnappedBeatForViewportX(
    double scrollOffset,
    double localDx,
    double pxPerBeat,
  ) {
    return ((scrollOffset + localDx - _followLeadingPaddingPx) / pxPerBeat)
        .clamp(0.0, 9999.0)
        .toDouble();
  }

  double _scrollOffsetForBeatAtViewportX(double beat, double localDx) {
    return _followLeadingPaddingPx + (beat * _pxPerBeat) - localDx;
  }

  double _unsnappedBeatForContentX(double contentDx, double pxPerBeat) {
    return ((contentDx - _followLeadingPaddingPx) / pxPerBeat)
        .clamp(0.0, 9999.0)
        .toDouble();
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
      final rect = _noteRect(note);
      if (rect.contains(local)) return note.id;
    }
    return null;
  }

  Rect _noteRect(MidiNote note) {
    return Rect.fromLTWH(
      _xForBeat(note.startBeat),
      _yForPitch(note.pitch) + 1.0,
      math.max(10.0, note.lengthBeats * _pxPerBeat),
      _rowHeight - 2.0,
    );
  }

  bool _isPreviewPitchActive(int pitch) =>
      (_pressedPreviewCounts[pitch] ?? 0) > 0 ||
      widget.highlightedPitches.contains(pitch);

  Set<int> _playbackPitchesForBeat(double beat) {
    if (!widget.isPlaying || !beat.isFinite) return const <int>{};
    final active = <int>{};
    for (final note in _displayNotes) {
      final start = note.startBeat;
      final end = start + math.max(note.lengthBeats, 0.0001);
      if (beat >= start && beat < end) {
        active.add(
          note.pitch.clamp(_absoluteMinPitch, _absoluteMaxPitch).toInt(),
        );
      }
    }
    return active;
  }

  void _incrementPreviewPitch(int pitch) {
    _pressedPreviewCounts.update(pitch, (value) => value + 1,
        ifAbsent: () => 1);
  }

  void _decrementPreviewPitch(int pitch) {
    final current = _pressedPreviewCounts[pitch];
    if (current == null) return;
    if (current <= 1) {
      _pressedPreviewCounts.remove(pitch);
      return;
    }
    _pressedPreviewCounts[pitch] = current - 1;
  }

  void _previewPianoKey(
    int pitch, {
    double velocity = 0.9,
    bool keyboardSource = false,
  }) {
    if (keyboardSource && _pressedKeyboardPitches.contains(pitch)) {
      return;
    }
    final safeVelocity = velocity.clamp(0.0, 1.0);
    setState(() {
      _incrementPreviewPitch(pitch);
      if (keyboardSource) {
        _pressedKeyboardPitches.add(pitch);
      }
    });
    final useHeldKeyboardPreview =
        keyboardSource && widget.onKeyboardNoteDown != null;
    final callback = widget.onPreviewNote;
    if (callback != null && !useHeldKeyboardPreview) {
      unawaited(callback(pitch, safeVelocity));
    }
    if (keyboardSource) {
      final recordCallback = widget.onKeyboardNoteDown;
      if (recordCallback != null) {
        unawaited(
          recordCallback(
            widget.clip,
            pitch,
            safeVelocity,
            startBeat: _visiblePlayheadBeat,
          ),
        );
      }
    }
  }

  void _releasePianoKey(
    int pitch, {
    bool keyboardSource = false,
  }) {
    final hadPreview = _isPreviewPitchActive(pitch);
    final hadKeyboardPress =
        keyboardSource && _pressedKeyboardPitches.contains(pitch);
    if (!hadPreview && !hadKeyboardPress) return;
    setState(() {
      _decrementPreviewPitch(pitch);
      if (keyboardSource) {
        _pressedKeyboardPitches.remove(pitch);
      }
    });
    if (hadKeyboardPress) {
      final recordCallback = widget.onKeyboardNoteUp;
      if (recordCallback != null) {
        unawaited(recordCallback(widget.clip, pitch));
      }
    }
  }

  void _handlePianoKeyPointerDown(PointerDownEvent event, int pitch) {
    if ((event.buttons & kPrimaryButton) == 0) return;
    if (!_isPitchPlayable(pitch)) return;
    final previousPitch = _pianoKeyPitchByPointer[event.pointer];
    if (previousPitch != null) {
      _releasePianoKey(previousPitch, keyboardSource: true);
    }
    if (_pressedKeyboardPitches.contains(pitch)) {
      _releasePianoKey(pitch, keyboardSource: true);
    }
    _pianoKeyPitchByPointer[event.pointer] = pitch;
    _previewPianoKey(pitch, keyboardSource: true);
  }

  int? _pianoKeyPitchForLocalPosition(Offset localPosition) {
    if (_rowHeight <= 0.0 || _pitchCount <= 0) return null;
    final offset = _keysVerticalController.hasClients
        ? _keysVerticalController.offset
        : 0.0;
    final contentY = localPosition.dy + offset;
    if (contentY < 0.0 || contentY >= _contentHeight) return null;
    final rowIndex = (contentY / _rowHeight).floor();
    final safeRowIndex = rowIndex.clamp(0, _pitchCount - 1);
    return _visiblePitchRange.max - safeRowIndex;
  }

  void _handlePianoKeyPointerMove(PointerMoveEvent event) {
    if ((event.kind != PointerDeviceKind.mouse &&
            !PlatformCapabilities.current.isDesktop) ||
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    final previousPitch = _pianoKeyPitchByPointer[event.pointer];
    final nextPitch = _pianoKeyPitchForLocalPosition(event.localPosition);
    if (previousPitch == nextPitch) return;
    if (previousPitch != null) {
      _pianoKeyPitchByPointer.remove(event.pointer);
      _releasePianoKey(previousPitch, keyboardSource: true);
    }
    if (nextPitch == null) return;
    if (!_isPitchPlayable(nextPitch)) return;
    if (_pressedKeyboardPitches.contains(nextPitch)) {
      _releasePianoKey(nextPitch, keyboardSource: true);
    }
    _pianoKeyPitchByPointer[event.pointer] = nextPitch;
    _previewPianoKey(nextPitch, keyboardSource: true);
  }

  void _handlePianoKeyPointerRelease(PointerEvent event) {
    final pitch = _pianoKeyPitchByPointer.remove(event.pointer);
    if (pitch == null) return;
    _releasePianoKey(pitch, keyboardSource: true);
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
    final focalBeat = _unsnappedBeatForViewportX(
      currentHorizontalOffset,
      focalDx,
      startX,
    );
    final focalRow = (currentVerticalOffset + focalDy) / startY;

    setState(() {
      _followPlayhead = false;
      _pxPerBeat = nextX;
      _rowHeight = nextY;
    });
    _publishEffectiveGridResolutionIfChanged();

    final nextContentWidth = _contentWidth;
    final nextContentHeight = _contentHeight;
    if (_horizontalController.hasClients) {
      final targetH = _scrollOffsetForBeatAtViewportX(focalBeat, focalDx);
      _jumpHorizontalTo(
        targetH,
        suppressFollowScrub: true,
        contentWidth: nextContentWidth,
      );
    }
    final targetV = (focalRow * _rowHeight) - focalDy;
    _jumpBothVerticalControllers(targetV, contentHeight: nextContentHeight);
  }

  double _distance(Offset a, Offset b) => (a - b).distance;

  void _maybeStartManualPinch() {
    if (_manualPinchActive || _activeGridGlobalPointers.length < 2) return;
    final globalPts = _activeGridGlobalPointers.values.toList(growable: false);
    final localPts = _activeGridPointers.values.toList(growable: false);
    if (_distance(globalPts[0], globalPts[1]) <
        _minTouchPinchStartDistance) {
      return;
    }
    _pinchStartPointA = globalPts[0];
    _pinchStartPointB = globalPts[1];
    _pinchStartPxPerBeat = _pxPerBeat;
    _pinchStartRowHeight = _rowHeight;
    _pinchStartHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    _pinchStartVerticalOffset = _gridVerticalController.hasClients
        ? _gridVerticalController.offset
        : 0.0;
    final focalContent = (localPts[0] + localPts[1]) / 2.0;
    _pinchStartFocalViewport = Offset(
      focalContent.dx - _pinchStartHorizontalOffset,
      focalContent.dy - _pinchStartVerticalOffset,
    );
    _pinchStartFocalBeat =
        _unsnappedBeatForContentX(focalContent.dx, _pinchStartPxPerBeat);
    _pinchStartFocalRow = focalContent.dy / _pinchStartRowHeight;
    setState(() {
      _manualPinchActive = true;
      _pinchZoomActive = true;
      _lockGridScroll = true;
    });
    _suppressGridTapFor(const Duration(milliseconds: 220));
  }

  void _scheduleManualPinchUpdate() {
    if (_manualPinchUpdateScheduled) return;
    _manualPinchUpdateScheduled = true;
    final token = _manualPinchUpdateToken;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _manualPinchUpdateScheduled = false;
      if (!mounted || token != _manualPinchUpdateToken) return;
      _applyManualPinchUpdate();
    });
  }

  void _applyManualPinchUpdate() {
    if (!_manualPinchActive || _activeGridGlobalPointers.length < 2) return;
    final pts = _activeGridGlobalPointers.values.toList(growable: false);
    final p1 = pts[0];
    final p2 = pts[1];

    final startDistance = _distance(_pinchStartPointA, _pinchStartPointB);
    final currentDistance = _distance(p1, p2);
    if (startDistance <= 0.5 || currentDistance <= 0.5) return;

    final rawScale = (currentDistance / startDistance).clamp(0.25, 4.0);
    final scale = math.pow(rawScale, _touchPinchScaleExponent).toDouble();
    final nextPxPerBeat =
        (_pinchStartPxPerBeat * scale).clamp(_minPxPerBeat, _maxPxPerBeat);
    final nextRowHeight =
        (_pinchStartRowHeight * scale).clamp(_minRowHeight, _maxRowHeight);

    if ((_pxPerBeat - nextPxPerBeat).abs() < 0.001 &&
        (_rowHeight - nextRowHeight).abs() < 0.001) {
      return;
    }

    setState(() {
      _pxPerBeat = nextPxPerBeat;
      _rowHeight = nextRowHeight;
    });
    _publishEffectiveGridResolutionIfChanged();

    final nextContentWidth = _contentWidth;
    final nextContentHeight = _contentHeight;
    if (_horizontalController.hasClients) {
      final targetH = _scrollOffsetForBeatAtViewportX(
        _pinchStartFocalBeat,
        _pinchStartFocalViewport.dx,
      );
      _jumpHorizontalTo(
        targetH,
        suppressFollowScrub: true,
        contentWidth: nextContentWidth,
      );
    }
    final targetV =
        (_pinchStartFocalRow * _rowHeight) - _pinchStartFocalViewport.dy;
    _jumpBothVerticalControllers(targetV, contentHeight: nextContentHeight);
  }

  void _endManualPinch() {
    if (!_manualPinchActive) return;
    _manualPinchActive = false;
    _manualPinchUpdateToken++;
    _pinchZoomActive = false;
    _setGridScrollLocked(false);
    _suppressGridTapFor();
  }

  void _handleDesktopWheelZoom(PointerScrollEvent event) {
    _handleDesktopZoomDelta(
      event.scrollDelta.dy,
      focalDx: _desktopZoomFocalDx(event.position),
    );
  }

  void _handleDesktopZoomDelta(
    double rawDelta, {
    required double focalDx,
  }) {
    if (rawDelta == 0) return;

    final startX = _pxPerBeat;
    final zoomFactor = math.exp(-rawDelta * 0.0025);
    final nextX = (startX * zoomFactor).clamp(_minPxPerBeat, _maxPxPerBeat);
    if ((nextX - startX).abs() < 0.001) {
      return;
    }

    final currentHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    final focalBeat = _unsnappedBeatForViewportX(
      currentHorizontalOffset,
      focalDx,
      startX,
    );

    setState(() {
      _followPlayhead = false;
      _pxPerBeat = nextX;
    });
    _publishEffectiveGridResolutionIfChanged();

    if (_horizontalController.hasClients) {
      final targetHorizontalOffset = _scrollOffsetForBeatAtViewportX(
        focalBeat,
        focalDx,
      );
      _jumpHorizontalTo(
        targetHorizontalOffset,
        suppressFollowScrub: true,
        contentWidth: _contentWidth,
      );
    }
  }

  double _desktopZoomFocalDx(Offset globalPosition) {
    final renderObject = _rollViewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final local = renderObject.globalToLocal(globalPosition);
      return local.dx.clamp(0.0, renderObject.size.width).toDouble();
    }
    return 0.0;
  }

  double _desktopZoomFocalDy(Offset globalPosition) {
    final renderObject = _gridViewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final local = renderObject.globalToLocal(globalPosition);
      return local.dy.clamp(0.0, renderObject.size.height).toDouble();
    }
    return 0.0;
  }

  void _onGridPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!_desktopWheelZoomAvailable) return;
    _nativeTrackpadPinchActive = false;
    _nativeTrackpadStartPxPerBeat = _pxPerBeat;
    _nativeTrackpadStartRowHeight = _rowHeight;
    _nativeTrackpadStartHorizontalOffset =
        _horizontalController.hasClients ? _horizontalController.offset : 0.0;
    _nativeTrackpadStartVerticalOffset = _gridVerticalController.hasClients
        ? _gridVerticalController.offset
        : 0.0;
    _nativeTrackpadFocalDx = _desktopZoomFocalDx(event.position);
    _nativeTrackpadFocalDy = _desktopZoomFocalDy(event.position);
    _nativeTrackpadFocalBeat = _unsnappedBeatForViewportX(
      _nativeTrackpadStartHorizontalOffset,
      _nativeTrackpadFocalDx,
      _nativeTrackpadStartPxPerBeat,
    );
    _nativeTrackpadFocalRow =
        (_nativeTrackpadStartVerticalOffset + _nativeTrackpadFocalDy) /
            _nativeTrackpadStartRowHeight;
  }

  void _onGridPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_desktopWheelZoomAvailable) return;

    if (_desktopWheelZoomModifierActive) {
      _syncDesktopWheelZoomModifierState();
      _handleDesktopZoomDelta(
        event.localPanDelta.dy,
        focalDx: _desktopZoomFocalDx(event.position),
      );
      return;
    }

    final scale = event.scale;
    if (!scale.isFinite || (scale - 1.0).abs() < 0.001) return;
    final nextX = (_nativeTrackpadStartPxPerBeat * scale)
        .clamp(_minPxPerBeat, _maxPxPerBeat);
    final nextY = (_nativeTrackpadStartRowHeight * scale)
        .clamp(_minRowHeight, _maxRowHeight);
    if ((nextX - _pxPerBeat).abs() < 0.001 &&
        (nextY - _rowHeight).abs() < 0.001) {
      return;
    }

    if (!_nativeTrackpadPinchActive) {
      _nativeTrackpadPinchActive = true;
      _pinchZoomActive = true;
      _lockGridScroll = true;
    }
    setState(() {
      _followPlayhead = false;
      _pxPerBeat = nextX;
      _rowHeight = nextY;
    });
    _publishEffectiveGridResolutionIfChanged();

    if (_horizontalController.hasClients) {
      _jumpHorizontalTo(
        _scrollOffsetForBeatAtViewportX(
          _nativeTrackpadFocalBeat,
          _nativeTrackpadFocalDx,
        ),
        suppressFollowScrub: true,
        contentWidth: _contentWidth,
      );
    }
    _jumpBothVerticalControllers(
      (_nativeTrackpadFocalRow * _rowHeight) - _nativeTrackpadFocalDy,
      contentHeight: _contentHeight,
    );
  }

  void _onGridPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_nativeTrackpadPinchActive) return;
    _nativeTrackpadPinchActive = false;
    _pinchZoomActive = false;
    _setGridScrollLocked(false);
    _suppressGridTapFor();
  }

  void _onGridPointerSignal(PointerSignalEvent event) {
    if (!_desktopWheelZoomAvailable) return;
    if (event is! PointerScrollEvent) return;

    final modifierPressed = _desktopWheelZoomModifierActive;
    if (_desktopWheelZoomModifierPressed != modifierPressed) {
      setState(() {
        _desktopWheelZoomModifierPressed = modifierPressed;
      });
    }
    if (!modifierPressed) return;

    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (PointerSignalEvent resolved) {
        if (resolved is! PointerScrollEvent) return;
        _handleDesktopWheelZoom(resolved);
      },
    );
  }

  void _onGridPointerDown(PointerDownEvent event) {
    _activeGridPointers[event.pointer] = event.localPosition;
    _activeGridGlobalPointers[event.pointer] = event.position;
    final desktopErase = event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0;
    if (desktopErase) {
      _startDesktopErase(event.pointer, event.localPosition);
      return;
    }
    final desktopBoxSelect = PlatformCapabilities.current.isDesktop &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        _desktopSelectionModifierActive;
    if (desktopBoxSelect) {
      _setGridScrollLocked(true);
      _desktopBoxSelectPointer = event.pointer;
      _startBoxSelectionAt(
        event.localPosition,
        skipIfNoteHit: false,
      );
      _suppressGridTapFor(const Duration(milliseconds: 220));
      return;
    }
    _maybeStartManualPinch();
  }

  void _onGridPointerMove(PointerMoveEvent event) {
    if (!_activeGridPointers.containsKey(event.pointer)) return;
    _activeGridPointers[event.pointer] = event.localPosition;
    _activeGridGlobalPointers[event.pointer] = event.position;
    if (_desktopErasePointer == event.pointer) {
      if ((event.buttons & kSecondaryMouseButton) == 0) {
        _finishDesktopErase();
        return;
      }
      _eraseNotesThrough(event.localPosition);
      return;
    }
    if (_desktopBoxSelectPointer == event.pointer &&
        _boxSelectStartLocal != null) {
      _updateBoxSelectionAt(event.localPosition);
      return;
    }
    _maybeStartManualPinch();
    if (_manualPinchActive) {
      _scheduleManualPinchUpdate();
    }
  }

  void _onGridPointerUp(PointerEvent event) {
    _activeGridPointers.remove(event.pointer);
    _activeGridGlobalPointers.remove(event.pointer);
    if (_desktopErasePointer == event.pointer) {
      _finishDesktopErase();
      return;
    }
    if (_desktopBoxSelectPointer == event.pointer) {
      _desktopBoxSelectPointer = null;
      _finishBoxSelection();
      return;
    }
    if (_activeGridPointers.length < 2) {
      _endManualPinch();
    }
  }

  void _startDesktopErase(int pointer, Offset localPosition) {
    if (widget.isRecording) return;
    _desktopErasePointer = pointer;
    _desktopEraseLastLocal = localPosition;
    _desktopEraseChanged = false;
    _suppressGridTapFor(const Duration(milliseconds: 220));
    _setGridScrollLocked(true);
    _eraseNotesThrough(localPosition);
  }

  void _eraseNotesThrough(Offset localPosition) {
    if (widget.isRecording) return;
    final previous = _desktopEraseLastLocal ?? localPosition;
    final sweepRect = Rect.fromPoints(previous, localPosition).inflate(5.0);
    final idsToRemove = <String>{};
    for (final note in _notes) {
      final noteRect = _noteRect(note);
      if (noteRect.contains(localPosition) ||
          noteRect.contains(previous) ||
          sweepRect.overlaps(noteRect)) {
        idsToRemove.add(note.id);
      }
    }
    _desktopEraseLastLocal = localPosition;
    if (idsToRemove.isEmpty) return;
    setState(() {
      _notes.removeWhere((note) => idsToRemove.contains(note.id));
      _selectedNoteIds.removeWhere(idsToRemove.contains);
      if (_selectedNoteId != null && idsToRemove.contains(_selectedNoteId)) {
        _selectedNoteId = null;
      }
      _normalizeSelectionState();
      _desktopEraseChanged = true;
    });
  }

  void _finishDesktopErase() {
    final shouldCommit = _desktopEraseChanged;
    _desktopErasePointer = null;
    _desktopEraseLastLocal = null;
    _desktopEraseChanged = false;
    _setGridScrollLocked(false);
    _suppressGridTapFor();
    if (shouldCommit) {
      _queueCommit(immediate: true);
    }
  }

  void _startBoxSelectionAt(
    Offset localPosition, {
    bool skipIfNoteHit = true,
  }) {
    if (_pinchZoomActive) return;
    if (skipIfNoteHit && _hitNoteIdAt(localPosition) != null) return;
    setState(() {
      _boxSelectStartLocal = localPosition;
      _boxSelectCurrentLocal = localPosition;
      _suppressNextGridTap = true;
    });
  }

  void _updateBoxSelectionAt(Offset localPosition) {
    if (_boxSelectStartLocal == null) return;
    setState(() {
      _boxSelectCurrentLocal = localPosition;
    });
  }

  void _startBoxSelection(LongPressStartDetails details) {
    _startBoxSelectionAt(details.localPosition);
  }

  void _updateBoxSelection(LongPressMoveUpdateDetails details) {
    _updateBoxSelectionAt(details.localPosition);
  }

  void _cancelBoxSelection() {
    if (_boxSelectStartLocal == null && _boxSelectCurrentLocal == null) return;
    setState(() {
      _boxSelectStartLocal = null;
      _boxSelectCurrentLocal = null;
      _desktopBoxSelectPointer = null;
      _lockGridScroll = false;
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
    if (widget.isRecording) return;
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
    if (widget.isRecording) return;
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
    if (shouldCommit && _activeDragIsResize && _activeDragNoteId != null) {
      final resized = _noteById(_activeDragNoteId!);
      if (resized != null) {
        _lastEditedNoteLengthBeats =
            resized.lengthBeats.clamp(_minimumLengthBeat, 64.0).toDouble();
      }
    }
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
    if (widget.isRecording) return;
    if (DateTime.now().isBefore(_ignoreGridTapUntil)) return;
    if (_pinchZoomActive) return;
    if (_boxSelectStartLocal != null || _boxSelectCurrentLocal != null) return;
    if (_suppressNextGridTap) {
      _suppressNextGridTap = false;
      return;
    }
    if (_hitNoteIdAt(local) != null) return;
    if (_followPlayhead && local.dx < _followLeadingPaddingPx) return;

    final beat = _beatForX(local.dx);
    final pitch = _pitchForY(local.dy);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_notes.length}';
    final note = MidiNote(
      id: id,
      pitch: pitch,
      startBeat: beat,
      lengthBeats: _newNoteLengthBeat(),
      velocity: _selectedAverageVelocity,
    );

    setState(() {
      _notes.add(note);
      _lastEditedNoteLengthBeats = note.lengthBeats;
      _selectSingle(id);
    });
    _queueCommit();
  }

  void _deleteSelectedNotes() {
    final selected = _effectiveSelectedIds;
    if (selected.isEmpty) return;
    setState(() {
      _notes.removeWhere((n) => selected.contains(n.id));
      _clearSelection();
    });
    _queueCommit();
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

  void _pasteNotes({double? insertionBeatOverride}) {
    if (_copiedNotes == null || _copiedNotes!.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final minCopiedBeat =
        _copiedNotes!.map((n) => n.startBeat).reduce((a, b) => math.min(a, b));
    final insertionBeat = insertionBeatOverride != null
        ? _snapBeat(insertionBeatOverride)
        : _snapBeat(_visiblePlayheadBeat);

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
    final selected = _selectedNotes;
    final duplicateBeat = selected.isNotEmpty
        ? _snapBeat(
            selected.map((n) => n.startBeat + n.lengthBeats).reduce(math.max),
          )
        : _snapBeat(_visiblePlayheadBeat);
    _pasteNotes(insertionBeatOverride: duplicateBeat);
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

  void _sortNotesInPlace() {
    _notes.sort((a, b) {
      final beatCompare = a.startBeat.compareTo(b.startBeat);
      if (beatCompare != 0) return beatCompare;
      final pitchCompare = a.pitch.compareTo(b.pitch);
      if (pitchCompare != 0) return pitchCompare;
      return a.id.compareTo(b.id);
    });
  }

  Set<String> _targetNoteIds({required bool selectedOnly}) {
    if (!selectedOnly) {
      return _notes.map((note) => note.id).toSet();
    }
    return _effectiveSelectedIds;
  }

  void _showPianoRollNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(L10n.translate(context, message))),
    );
  }

  bool _quantizeNotes({
    required int divisionsPerBar,
    bool selectedOnly = false,
  }) {
    final targetIds = _targetNoteIds(selectedOnly: selectedOnly);
    if (targetIds.isEmpty) return false;
    final stepBeats = _barLengthBeats / math.max(1, divisionsPerBar).toDouble();
    bool changed = false;
    setState(() {
      for (final note in _notes) {
        if (!targetIds.contains(note.id)) continue;
        final nextStart =
            ((note.startBeat / stepBeats).round() * stepBeats).clamp(
          0.0,
          9999.0,
        );
        if ((nextStart - note.startBeat).abs() > 0.00001) {
          note.startBeat = nextStart;
          changed = true;
        }
      }
      if (changed) {
        _sortNotesInPlace();
      }
    });
    if (changed) {
      _queueCommit(immediate: true);
    }
    return changed;
  }

  bool _chopNotes({
    required int divisionsPerBar,
    bool selectedOnly = false,
  }) {
    final targetIds = _targetNoteIds(selectedOnly: selectedOnly);
    if (targetIds.isEmpty) return false;
    final targetNotes = _notes
        .where((note) => targetIds.contains(note.id))
        .map((note) => note.copy())
        .toList(growable: false);
    if (targetNotes.isEmpty) return false;

    final stepBeats = _barLengthBeats / math.max(1, divisionsPerBar).toDouble();
    final chopped = AssistantActionUtils.chopMidiNotes(
      notes: targetNotes,
      subdivision: divisionsPerBar,
      stepBeats: stepBeats,
      sustainRatio: 1.0,
      minLengthBeats: math.min(stepBeats, _minimumLengthBeat),
      noteIdPrefix: 'piano_roll_chop',
    );
    if (!_noteListsDiffer(targetNotes, chopped)) {
      return false;
    }

    setState(() {
      final untouched = _notes
          .where((note) => !targetIds.contains(note.id))
          .map((note) => note.copy())
          .toList();
      _notes = <MidiNote>[
        ...untouched,
        ...chopped.map((note) => note.copy()),
      ];
      _sortNotesInPlace();
      if (selectedOnly) {
        _selectedNoteIds
          ..clear()
          ..addAll(chopped.map((note) => note.id));
      } else {
        _selectedNoteIds.removeWhere(
          (id) => !_notes.any((note) => note.id == id),
        );
      }
      _normalizeSelectionState();
    });
    _queueCommit(immediate: true);
    return true;
  }

  bool _humanizeVelocity({
    bool selectedOnly = false,
    double amount = 0.12,
  }) {
    final targetIds = _targetNoteIds(selectedOnly: selectedOnly);
    if (targetIds.isEmpty) return false;
    final random = math.Random(DateTime.now().microsecondsSinceEpoch);
    bool changed = false;
    setState(() {
      for (final note in _notes) {
        if (!targetIds.contains(note.id)) continue;
        final jitter = ((random.nextDouble() * 2.0) - 1.0) * amount;
        final nextVelocity = (note.velocity + jitter).clamp(0.05, 1.0);
        if ((nextVelocity - note.velocity).abs() > 0.00001) {
          note.velocity = nextVelocity;
          changed = true;
        }
      }
    });
    if (changed) {
      _queueCommit(immediate: true);
    }
    return changed;
  }

  bool _transposeNotes(
    int semitones, {
    bool selectedOnly = true,
  }) {
    final targetIds = _targetNoteIds(selectedOnly: selectedOnly);
    if (targetIds.isEmpty) return false;
    bool changed = false;
    setState(() {
      for (final note in _notes) {
        if (!targetIds.contains(note.id)) continue;
        final nextPitch = (note.pitch + semitones).clamp(
          _absoluteMinPitch,
          _absoluteMaxPitch,
        );
        if (nextPitch != note.pitch) {
          note.pitch = nextPitch;
          changed = true;
        }
      }
      if (changed) {
        _sortNotesInPlace();
      }
    });
    if (changed) {
      _queueCommit(immediate: true);
    }
    return changed;
  }

  void _selectAllNotes() {
    if (_notes.isEmpty) return;
    setState(() {
      _selectedNoteIds
        ..clear()
        ..addAll(_notes.map((note) => note.id));
      _normalizeSelectionState();
    });
  }

  Future<void> _showPianoRollPopup({
    required Widget Function(BuildContext popupContext) builder,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (dialogContext) => Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 54, 16, 16),
              child: builder(dialogContext),
            ),
          ),
        ),
      ),
    );
  }

  Widget _advancedPopupPanel({
    required String title,
    String? subtitle,
    required Widget child,
    double width = 274,
    VoidCallback? onClose,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: _mixroomPianoSurfaceDecoration(radius: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _kPianoShellText,
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: _kPianoShellText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _kPianoShellMutedText,
                      fontFamily: 'Pretendard',
                      fontSize: 11.8,
                      fontWeight: FontWeight.w500,
                      height: 1.34,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _advancedMenuAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool danger = false,
    bool showsChevron = false,
  }) {
    final enabled = onTap != null;
    final accent = danger ? const Color(0xFFFF9C9C) : _kPianoWarmBorder;
    return Opacity(
      opacity: enabled ? 1.0 : 0.42,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.20),
                  ),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _kPianoShellText,
                        fontFamily: 'Pretendard',
                        fontSize: 12.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _kPianoShellMutedText,
                        fontFamily: 'Pretendard',
                        fontSize: 11.2,
                        fontWeight: FontWeight.w500,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
              if (showsChevron)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _kPianoShellMutedText,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _advancedMenuDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  Future<void> _showGridActionDialog({
    required String title,
    required String subtitle,
    required bool selectedOnly,
    required bool Function(int divisionsPerBar) onApply,
  }) async {
    await _showPianoRollPopup(
      builder: (popupContext) => _advancedPopupPanel(
        title: title,
        subtitle: subtitle,
        width: 230,
        onClose: () => Navigator.of(popupContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _gridOptions.length; i++) ...[
              _advancedMenuAction(
                icon: Icons.grid_view_rounded,
                title: _gridOptions[i].label,
                subtitle: _gridOptions[i].divisionsPerBar ==
                        _effectiveQuantizeDivisionsPerBar
                    ? L10n.translate(
                        context,
                        'Matches the current piano roll grid.',
                      )
                    : L10n.translate(
                        context,
                        selectedOnly
                            ? 'Apply to selected notes.'
                            : 'Apply to all notes.',
                      ),
                onTap: widget.isRecording
                    ? null
                    : () {
                        Navigator.of(popupContext).pop();
                        final changed =
                            onApply(_gridOptions[i].divisionsPerBar);
                        if (!changed) {
                          _showPianoRollNotice(
                            L10n.translate(
                              context,
                              selectedOnly
                                  ? 'Selected notes already match that grid.'
                                  : 'Notes already match that grid.',
                            ),
                          );
                        }
                      },
              ),
              if (i < _gridOptions.length - 1) _advancedMenuDivider(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAdvancedToolsDialog() async {
    final hasNotes = _notes.isNotEmpty;
    final hasSelection = _effectiveSelectedIds.isNotEmpty;

    await _showPianoRollPopup(
      builder: (popupContext) => _advancedPopupPanel(
        title: L10n.translate(context, 'Piano Roll Tools'),
        subtitle: widget.isRecording
            ? L10n.translate(
                context,
                'Recording is active. Finish the take before running edit tools.',
              )
            : L10n.translate(
                context,
                'Fast cleanup tools for timing, rhythm, and pitch.',
              ),
        onClose: () => Navigator.of(popupContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _advancedMenuAction(
              icon: Icons.checklist_rtl_rounded,
              title: L10n.translate(context, 'Select All'),
              subtitle: L10n.translate(
                context,
                'Grab every note in the current clip.',
              ),
              onTap: hasNotes
                  ? () {
                      Navigator.of(popupContext).pop();
                      _selectAllNotes();
                    }
                  : null,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.grid_on_rounded,
              title: L10n.translate(context, 'Quantize All Notes'),
              subtitle: L10n.translate(
                context,
                'Snap note starts to a timing grid.',
              ),
              onTap: hasNotes && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      unawaited(_showGridActionDialog(
                        title: L10n.translate(context, 'Quantize All Notes'),
                        subtitle: L10n.translate(
                          context,
                          'Choose the grid to snap note starts to.',
                        ),
                        selectedOnly: false,
                        onApply: (divisionsPerBar) => _quantizeNotes(
                          divisionsPerBar: divisionsPerBar,
                        ),
                      ));
                    }
                  : null,
              showsChevron: true,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.fit_screen_rounded,
              title: L10n.translate(context, 'Quantize Selected'),
              subtitle: L10n.translate(
                context,
                'Tighten only the notes you have selected.',
              ),
              onTap: hasSelection && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      unawaited(_showGridActionDialog(
                        title: L10n.translate(context, 'Quantize Selected'),
                        subtitle: L10n.translate(
                          context,
                          'Choose the grid for the selected notes.',
                        ),
                        selectedOnly: true,
                        onApply: (divisionsPerBar) => _quantizeNotes(
                          divisionsPerBar: divisionsPerBar,
                          selectedOnly: true,
                        ),
                      ));
                    }
                  : null,
              showsChevron: true,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.content_cut_rounded,
              title: L10n.translate(context, 'Chop All Notes'),
              subtitle: L10n.translate(
                context,
                'Split notes into repeated rhythmic slices.',
              ),
              onTap: hasNotes && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      unawaited(_showGridActionDialog(
                        title: L10n.translate(context, 'Chop All Notes'),
                        subtitle: L10n.translate(
                          context,
                          'Choose the slice grid for the whole clip.',
                        ),
                        selectedOnly: false,
                        onApply: (divisionsPerBar) => _chopNotes(
                          divisionsPerBar: divisionsPerBar,
                        ),
                      ));
                    }
                  : null,
              showsChevron: true,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.cut_rounded,
              title: L10n.translate(context, 'Chop Selected'),
              subtitle: L10n.translate(
                context,
                'Slice only the notes you selected.',
              ),
              onTap: hasSelection && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      unawaited(_showGridActionDialog(
                        title: L10n.translate(context, 'Chop Selected'),
                        subtitle: L10n.translate(
                          context,
                          'Choose the slice grid for the selection.',
                        ),
                        selectedOnly: true,
                        onApply: (divisionsPerBar) => _chopNotes(
                          divisionsPerBar: divisionsPerBar,
                          selectedOnly: true,
                        ),
                      ));
                    }
                  : null,
              showsChevron: true,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.tune_rounded,
              title: L10n.translate(context, 'Humanize Velocity'),
              subtitle: hasSelection
                  ? L10n.translate(
                      context,
                      'Add slight dynamics to the selected notes.',
                    )
                  : L10n.translate(
                      context,
                      'Add slight dynamics across the whole clip.',
                    ),
              onTap: hasNotes && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      final changed = _humanizeVelocity(
                        selectedOnly: hasSelection,
                      );
                      if (!changed) {
                        _showPianoRollNotice(
                          L10n.translate(context, 'No notes changed.'),
                        );
                      }
                    }
                  : null,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.keyboard_double_arrow_up_rounded,
              title: L10n.translate(context, 'Octave Up'),
              subtitle: L10n.translate(
                context,
                'Move the selected notes up by 12 semitones.',
              ),
              onTap: hasSelection && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      final changed = _transposeNotes(12);
                      if (!changed) {
                        _showPianoRollNotice(
                          L10n.translate(
                            context,
                            'Selected notes are already at the top range.',
                          ),
                        );
                      }
                    }
                  : null,
            ),
            _advancedMenuDivider(),
            _advancedMenuAction(
              icon: Icons.keyboard_double_arrow_down_rounded,
              title: L10n.translate(context, 'Octave Down'),
              subtitle: L10n.translate(
                context,
                'Move the selected notes down by 12 semitones.',
              ),
              onTap: hasSelection && !widget.isRecording
                  ? () {
                      Navigator.of(popupContext).pop();
                      final changed = _transposeNotes(-12);
                      if (!changed) {
                        _showPianoRollNotice(
                          L10n.translate(
                            context,
                            'Selected notes are already at the bottom range.',
                          ),
                        );
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
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
    Widget tipRow({
      required IconData icon,
      required Color accent,
      required String title,
      required String body,
      bool showDivider = true,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(icon, color: accent, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _kPianoShellText,
                            fontFamily: 'Pretendard',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: TextStyle(
                            color: _kPianoShellMutedText,
                            fontFamily: 'Pretendard',
                            fontSize: 12.2,
                            fontWeight: FontWeight.w500,
                            height: 1.34,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: _mixroomPianoSurfaceDecoration(radius: 24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _kPianoWarmBorder.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color:
                                    _kPianoWarmBorder.withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Icon(
                              Icons.help_outline_rounded,
                              size: 18,
                              color: _kPianoWarmBorder,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              L10n.translate(ctx, 'Piano Roll Quick Guide'),
                              style: const TextStyle(
                                color: _kPianoShellText,
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.translate(
                          ctx,
                          'A few gestures that make editing faster.',
                        ),
                        style: TextStyle(
                          color: _kPianoShellMutedText,
                          fontFamily: 'Pretendard',
                          fontSize: 12.2,
                          fontWeight: FontWeight.w500,
                          height: 1.32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      tipRow(
                        icon: Icons.touch_app_rounded,
                        accent: const Color(0xFF7DB4FF),
                        title: L10n.translate(ctx, 'Create + shape notes'),
                        body: L10n.translate(
                          ctx,
                          'Tap empty grid to add. Drag to move. Pull right edge to resize.',
                        ),
                      ),
                      tipRow(
                        icon: Icons.select_all_rounded,
                        accent: const Color(0xFF83D4B9),
                        title: L10n.translate(ctx, 'Select groups quickly'),
                        body: L10n.translate(
                          ctx,
                          'Hold empty space and drag a box to multi-select notes.',
                        ),
                      ),
                      tipRow(
                        icon: Icons.pinch_rounded,
                        accent: const Color(0xFFF7C56D),
                        title: L10n.translate(ctx, 'Zoom + edit faster'),
                        body: L10n.translate(
                          ctx,
                          'Pinch with two fingers or use +/- buttons to zoom in time and pitch.',
                        ),
                      ),
                      tipRow(
                        icon: Icons.tune_rounded,
                        accent: const Color(0xFFE78CF3),
                        title: L10n.translate(ctx, 'Use the bottom tray'),
                        body: L10n.translate(
                          ctx,
                          'Duplicate, delete, and adjust length/velocity for selected notes.',
                        ),
                        showDivider: false,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            foregroundColor: _kPianoShellText,
                            backgroundColor: _kPianoShellFillStrong,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                          ),
                          child: Text(
                            L10n.translate(ctx, 'Got it'),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTabIndex = _tabController.index.clamp(0, 2).toInt();

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
                child: IndexedStack(
                  index: activeTabIndex,
                  children: [
                    _buildMidiTab(),
                    ValueListenableBuilder<double>(
                      valueListenable: _visualPlayheadBeat,
                      builder: (context, playheadBeat, _) {
                        return _buildSequencerTab(playheadBeat);
                      },
                    ),
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
    final onMidiLayerTab =
        _tabController.index == 0 || _tabController.index == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _instrumentName.isEmpty
                  ? L10n.translate(context, 'Instrument')
                  : _instrumentName,
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
          if (onMidiLayerTab) ...[
            if (_currentInstrumentIsExternalPlugin &&
                widget.onOpenCurrentInstrumentUi != null) ...[
              _toolbarIconButton(
                icon: Icons.open_in_new_rounded,
                tooltip: L10n.translate(context, 'Open instrument UI'),
                onTap: () {
                  unawaited(widget.onOpenCurrentInstrumentUi!.call());
                },
              ),
              const SizedBox(width: 5),
            ],
            _toolbarIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: widget.isRecording
                  ? L10n.translate(
                      context,
                      'Finish recording to use piano roll tools',
                    )
                  : L10n.translate(context, 'Piano roll tools'),
              onTap: _showAdvancedToolsDialog,
            ),
            const SizedBox(width: 5),
            _toolbarIconButton(
              icon: _followPlayhead
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              tooltip: _followPlayhead
                  ? L10n.translate(context, 'Unlock piano roll from playhead')
                  : L10n.translate(context, 'Lock piano roll to playhead'),
              active: _followPlayhead,
              onTap: () => _setFollowPlayhead(!_followPlayhead),
            ),
            const SizedBox(width: 5),
            _toolbarIconButton(
              icon: Icons.zoom_out_rounded,
              tooltip: L10n.translate(context, 'Zoom out'),
              onTap: () => _adjustZoom(xFactor: 0.76, yFactor: 0.82),
            ),
            const SizedBox(width: 5),
            _toolbarIconButton(
              icon: Icons.zoom_in_rounded,
              tooltip: L10n.translate(context, 'Zoom in'),
              onTap: () => _adjustZoom(xFactor: 1.32, yFactor: 1.24),
            ),
            const SizedBox(width: 5),
          ],
          _toolbarIconButton(
            icon: Icons.help_outline,
            tooltip: L10n.translate(context, 'Piano roll help'),
            onTap: _showMidiHelpDialog,
          ),
          const SizedBox(width: 5),
          _toolbarIconButton(
            icon: widget.fullscreen
                ? Icons.fullscreen_exit_outlined
                : Icons.fullscreen_outlined,
            tooltip: L10n.translate(context, 'Toggle fullscreen'),
            onTap: () => widget.onFullscreenChanged(!widget.fullscreen),
          ),
          const SizedBox(width: 5),
          _toolbarIconButton(
            icon: Icons.close,
            tooltip: L10n.translate(context, 'Close'),
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabHeight = PlatformCapabilities.current.isDesktop ? 36.0 : 34.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: _mixroomPianoInsetDecoration(radius: 18),
        child: SizedBox(
          height: tabHeight,
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
            onTap: (index) {
              if (_lastTabIndex == index) return;
              _lastTabIndex = index;
              setState(() {});
            },
            tabs: [
              Tab(height: tabHeight, text: 'MIDI'),
              Tab(
                height: tabHeight,
                text: L10n.translate(context, 'Sequencer'),
              ),
              Tab(
                height: tabHeight,
                text: L10n.translate(context, 'Instrument'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMidiTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: _mixroomPianoInsetDecoration(radius: 18),
          child: Row(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: _onGridPointerSignal,
                onPointerPanZoomStart: _onGridPointerPanZoomStart,
                onPointerPanZoomUpdate: _onGridPointerPanZoomUpdate,
                onPointerPanZoomEnd: _onGridPointerPanZoomEnd,
                child: SizedBox(
                  width: 74,
                  child: Column(
                    children: [
                      if (PlatformCapabilities.current.isDesktop)
                        const SizedBox(height: _rulerHeight),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _visualPlayheadBeat,
                          builder: (context, playheadBeat, _) {
                            return _hideDesktopScrollbars(
                              _buildPianoKeys(
                                playbackPitches:
                                    _playbackPitchesForBeat(playheadBeat),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _rollViewportWidth = constraints.maxWidth;
                    return _buildRollGrid();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSequencerTab(double playheadBeat) {
    if (!_currentInstrumentUsesDrumSequencer) {
      return _buildSingleSequencerTab(playheadBeat);
    }
    return _buildDrumSequencerTab(playheadBeat);
  }

  Widget _buildDrumSequencerTab(double playheadBeat) {
    final lanes = _sequencerLanes;
    final activePitch = _effectiveSequencerPitch;
    final rowHeight = PlatformCapabilities.current.isDesktop ? 48.0 : 52.0;
    final labelWidth = PlatformCapabilities.current.isDesktop ? 126.0 : 112.0;
    const stepGap = 5.0;
    const headerHeight = 30.0;
    final playheadStep =
        playheadBeat >= 0.0 && playheadBeat < _sequencerPatternLengthBeat
            ? (playheadBeat / _sequencerStepLengthBeat)
                .floor()
                .clamp(0, math.max(0, _sequencerTotalSteps - 1))
                .toInt()
            : -1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: _mixroomPianoInsetDecoration(radius: 18),
          child: Column(
            children: [
              _buildSequencerToolbar(
                activePitch: activePitch,
                drumMode: true,
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0x1FFFFFFF),
              ),
              Expanded(
                child: _hideDesktopScrollbars(
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Column(
                            children: [
                              Container(
                                height: headerHeight,
                                padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Sound',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _kPianoShellMutedText,
                                    fontFamily: 'Pretendard',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              for (final lane in lanes)
                                SizedBox(
                                  height: rowHeight,
                                  child: _buildSequencerLaneLabel(
                                    lane: lane,
                                    selected: lane.pitch == activePitch,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final minStepWidth =
                                  PlatformCapabilities.current.isDesktop
                                      ? 26.0
                                      : 30.0;
                              final scaledMinStepWidth =
                                  minStepWidth * _sequencerStepScale;
                              final fittedWidth = ((constraints.maxWidth -
                                          (stepGap *
                                              (_sequencerTotalSteps - 1))) /
                                      _sequencerTotalSteps)
                                  .floorToDouble();
                              final stepWidth = math.max(
                                scaledMinStepWidth,
                                fittedWidth,
                              );
                              final contentWidth =
                                  (stepWidth * _sequencerTotalSteps) +
                                      (stepGap * (_sequencerTotalSteps - 1));

                              return RawScrollbar(
                                controller: _sequencerHorizontalController,
                                thumbVisibility: true,
                                interactive: true,
                                scrollbarOrientation:
                                    ScrollbarOrientation.bottom,
                                thickness: 3.5,
                                radius: const Radius.circular(999),
                                thumbColor:
                                    _kPianoWarmBorder.withValues(alpha: 0.70),
                                child: _hideDesktopScrollbars(
                                  SingleChildScrollView(
                                    key: const ValueKey<String>(
                                      'sequencer_grid_scroll',
                                    ),
                                    controller: _sequencerHorizontalController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const ClampingScrollPhysics(),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SizedBox(
                                      width: contentWidth,
                                      child: Column(
                                        children: [
                                          _buildSequencerStepHeader(
                                            stepWidth: stepWidth,
                                            stepGap: stepGap,
                                            playheadStep: playheadStep,
                                            totalSteps: _sequencerTotalSteps,
                                            height: headerHeight,
                                          ),
                                          for (final lane in lanes)
                                            SizedBox(
                                              height: rowHeight,
                                              child: _buildSequencerLaneSteps(
                                                lane: lane,
                                                stepWidth: stepWidth,
                                                stepGap: stepGap,
                                                playheadStep: playheadStep,
                                                totalSteps:
                                                    _sequencerTotalSteps,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleSequencerTab(double playheadBeat) {
    final activePitch = _effectiveSingleSequencerPitch;
    final lane = _StepSequencerLane(
      pitch: activePitch,
      label: _noteNameForPitch(activePitch),
    );
    final rowHeight = PlatformCapabilities.current.isDesktop ? 58.0 : 62.0;
    final labelWidth = PlatformCapabilities.current.isDesktop ? 92.0 : 84.0;
    const stepGap = 5.0;
    const headerHeight = 30.0;
    final playheadStep =
        playheadBeat >= 0.0 && playheadBeat < _sequencerPatternLengthBeat
            ? (playheadBeat / _sequencerStepLengthBeat)
                .floor()
                .clamp(0, math.max(0, _sequencerTotalSteps - 1))
                .toInt()
            : -1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: _mixroomPianoInsetDecoration(radius: 18),
          child: Column(
            children: [
              _buildSequencerToolbar(
                activePitch: activePitch,
                drumMode: false,
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0x1FFFFFFF),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Column(
                            children: [
                              Container(
                                height: headerHeight,
                                padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Note',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _kPianoShellMutedText,
                                    fontFamily: 'Pretendard',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: rowHeight,
                                child: _buildSingleSequencerLaneLabel(
                                  pitch: activePitch,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final minStepWidth =
                                  PlatformCapabilities.current.isDesktop
                                      ? 28.0
                                      : 32.0;
                              final scaledMinStepWidth =
                                  minStepWidth * _sequencerStepScale;
                              final fittedWidth = ((constraints.maxWidth -
                                          (stepGap *
                                              (_sequencerTotalSteps - 1))) /
                                      _sequencerTotalSteps)
                                  .floorToDouble();
                              final stepWidth = math.max(
                                scaledMinStepWidth,
                                fittedWidth,
                              );
                              final contentWidth =
                                  (stepWidth * _sequencerTotalSteps) +
                                      (stepGap * (_sequencerTotalSteps - 1));

                              return RawScrollbar(
                                controller: _sequencerHorizontalController,
                                thumbVisibility: true,
                                interactive: true,
                                scrollbarOrientation:
                                    ScrollbarOrientation.bottom,
                                thickness: 3.5,
                                radius: const Radius.circular(999),
                                thumbColor:
                                    _kPianoWarmBorder.withValues(alpha: 0.70),
                                child: _hideDesktopScrollbars(
                                  SingleChildScrollView(
                                    key: const ValueKey<String>(
                                      'single_sequencer_grid_scroll',
                                    ),
                                    controller: _sequencerHorizontalController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const ClampingScrollPhysics(),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SizedBox(
                                      width: contentWidth,
                                      child: Column(
                                        children: [
                                          _buildSequencerStepHeader(
                                            stepWidth: stepWidth,
                                            stepGap: stepGap,
                                            playheadStep: playheadStep,
                                            totalSteps: _sequencerTotalSteps,
                                            height: headerHeight,
                                          ),
                                          SizedBox(
                                            height: rowHeight,
                                            child: _buildSequencerLaneSteps(
                                              lane: lane,
                                              stepWidth: stepWidth,
                                              stepGap: stepGap,
                                              playheadStep: playheadStep,
                                              totalSteps: _sequencerTotalSteps,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSequencerToolbar({
    required int activePitch,
    required bool drumMode,
  }) {
    final activeLane = drumMode
        ? _sequencerLanes.firstWhere(
            (lane) => lane.pitch == activePitch,
            orElse: () => _StepSequencerLane(
              pitch: activePitch,
              label: _noteNameForPitch(activePitch),
            ),
          )
        : _StepSequencerLane(
            pitch: activePitch,
            label: _instrumentName.isEmpty ? 'Instrument' : _instrumentName,
          );
    final activeNoteName = _noteNameForPitch(activePitch);
    final activeHitCount = _sequencerHitCountForPitch(activePitch);
    final subtitle = drumMode
        ? '$activeNoteName  |  $activeHitCount hits'
        : 'Step note $activeNoteName  |  $activeHitCount hits';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeLane.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kPianoShellText,
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kPianoShellMutedText,
                    fontFamily: 'Pretendard',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!drumMode) ...[
                    _compactIconButton(
                      key: const ValueKey<String>('sequencer_pitch_down'),
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: L10n.translate(context, 'Lower note'),
                      enabled: !widget.isRecording && activePitch > 0,
                      onTap: () => _setSingleSequencerPitch(activePitch - 1),
                    ),
                    const SizedBox(width: 5),
                    _sequencerInfoPill(activeNoteName),
                    const SizedBox(width: 5),
                    _compactIconButton(
                      key: const ValueKey<String>('sequencer_pitch_up'),
                      icon: Icons.keyboard_arrow_up_rounded,
                      tooltip: L10n.translate(context, 'Higher note'),
                      enabled: !widget.isRecording && activePitch < 127,
                      onTap: () => _setSingleSequencerPitch(activePitch + 1),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _compactIconButton(
                    key: const ValueKey<String>('sequencer_zoom_out'),
                    icon: Icons.remove_rounded,
                    tooltip: L10n.translate(context, 'Zoom out'),
                    enabled: _sequencerStepScale > _minSequencerStepScale,
                    onTap: () => _setSequencerStepScale(
                      _sequencerStepScale - 0.16,
                    ),
                  ),
                  const SizedBox(width: 5),
                  _sequencerInfoPill(
                    '${(_sequencerStepScale * 100).round()}%',
                  ),
                  const SizedBox(width: 5),
                  _compactIconButton(
                    key: const ValueKey<String>('sequencer_zoom_in'),
                    icon: Icons.add_rounded,
                    tooltip: L10n.translate(context, 'Zoom in'),
                    enabled: _sequencerStepScale < _maxSequencerStepScale,
                    onTap: () => _setSequencerStepScale(
                      _sequencerStepScale + 0.16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _compactIconButton(
                    key: const ValueKey<String>('sequencer_bars_less'),
                    icon: Icons.keyboard_arrow_left_rounded,
                    tooltip: L10n.translate(context, 'Shorter pattern'),
                    enabled:
                        _sequencerPatternBars > math.max(4, _sequencerBarCount),
                    onTap: () => _setSequencerVisibleBars(
                      _sequencerPatternBars - 1,
                    ),
                  ),
                  const SizedBox(width: 5),
                  _sequencerInfoPill('$_sequencerPatternBars bars'),
                  const SizedBox(width: 5),
                  _compactIconButton(
                    key: const ValueKey<String>('sequencer_bars_more'),
                    icon: Icons.keyboard_arrow_right_rounded,
                    tooltip: L10n.translate(context, 'Longer pattern'),
                    enabled: _sequencerPatternBars < 64,
                    onTap: () => _setSequencerVisibleBars(
                      _sequencerPatternBars + 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSequencerRepeatShortcuts(),
                  const SizedBox(width: 5),
                  _compactIconButton(
                    key: const ValueKey<String>('sequencer_clear_lane'),
                    icon: Icons.backspace_outlined,
                    tooltip: L10n.translate(context, 'Clear lane'),
                    enabled: !widget.isRecording,
                    onTap: _clearSequencerLane,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSequencerRepeatShortcuts() {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final interval in _sequencerFillIntervals) ...[
            _sequencerMacroButton(
              key: ValueKey<String>('sequencer_fill_$interval'),
              label: '${interval}x',
              tooltip: L10n.translate(
                context,
                interval == 1
                    ? 'Fill every step'
                    : 'Fill every $interval steps',
              ),
              enabled: !widget.isRecording,
              onTap: () => _fillSequencerEvery(interval),
            ),
            if (interval != _sequencerFillIntervals.last)
              const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildSequencerLaneLabel({
    required _StepSequencerLane lane,
    required bool selected,
  }) {
    final noteName = _noteNameForPitch(lane.pitch);
    final hitCount = _sequencerHitCountForPitch(lane.pitch);
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 4, 4, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('sequencer_lane_${lane.pitch}'),
          borderRadius: BorderRadius.circular(8),
          onTap: widget.isRecording
              ? null
              : () {
                  setState(() {
                    _activeSequencerPitch = lane.pitch;
                  });
                  _previewPianoKey(lane.pitch);
                  Future<void>.delayed(const Duration(milliseconds: 80), () {
                    if (!mounted) return;
                    _releasePianoKey(lane.pitch);
                  });
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? _kPianoWarmBorder.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? _kPianoWarmBorder
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lane.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _kPianoShellText : _kPianoShellMutedText,
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        noteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: selected ? 0.72 : 0.50,
                          ),
                          fontFamily: 'Pretendard',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (hitCount > 0)
                      Text(
                        '$hitCount',
                        style: TextStyle(
                          color: selected
                              ? _kPianoWarmBorder
                              : Colors.white.withValues(alpha: 0.52),
                          fontFamily: 'Pretendard',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleSequencerLaneLabel({
    required int pitch,
  }) {
    final noteName = _noteNameForPitch(pitch);
    final hitCount = _sequencerHitCountForPitch(pitch);
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 4, 4, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _kPianoWarmBorder.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kPianoWarmBorder.withValues(alpha: 0.72)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              noteName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kPianoShellText,
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '$hitCount hits',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontFamily: 'Pretendard',
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSequencerStepHeader({
    required double stepWidth,
    required double stepGap,
    required int playheadStep,
    required int totalSteps,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (int step = 0; step < totalSteps; step++) ...[
            SizedBox(
              width: stepWidth,
              child: Center(
                child: step == playheadStep
                    ? Container(
                        width: math.max(18.0, stepWidth * 0.58),
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD45A),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x66FFD45A),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: step % _sequencerStepsPerBar == 0
                              ? Text(
                                  '${(step ~/ _sequencerStepsPerBar) + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFF271800),
                                    fontFamily: 'Pretendard',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : Container(
                                  width: step % 4 == 0 ? 9 : 4,
                                  height: step % 4 == 0 ? 3 : 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF271800),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                        ),
                      )
                    : step % _sequencerStepsPerBar == 0
                        ? Text(
                            '${(step ~/ _sequencerStepsPerBar) + 1}',
                            style: const TextStyle(
                              color: _kPianoShellMutedText,
                              fontFamily: 'Pretendard',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Container(
                            width: step % 4 == 0 ? 18 : 4,
                            height: step % 4 == 0 ? 3 : 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: step % 4 == 0 ? 0.48 : 0.18,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
              ),
            ),
            if (step != totalSteps - 1) SizedBox(width: stepGap),
          ],
        ],
      ),
    );
  }

  Widget _buildSequencerLaneSteps({
    required _StepSequencerLane lane,
    required double stepWidth,
    required double stepGap,
    required int playheadStep,
    required int totalSteps,
  }) {
    final selectedPitch = _effectiveSequencerEditPitch;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: lane.pitch == selectedPitch
              ? Colors.white.withValues(alpha: 0.035)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            for (int step = 0; step < totalSteps; step++) ...[
              _buildSequencerStepButton(
                lane: lane,
                step: step,
                width: stepWidth,
                playheadActive: step == playheadStep,
              ),
              if (step != totalSteps - 1) SizedBox(width: stepGap),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSequencerStepButton({
    required _StepSequencerLane lane,
    required int step,
    required double width,
    required bool playheadActive,
  }) {
    final enabled = _sequencerNoteIndexAt(pitch: lane.pitch, step: step) >= 0;
    final selectedLane = lane.pitch == _effectiveSequencerEditPitch;
    final strongBeat = step % 4 == 0;
    final barStart = step % _sequencerStepsPerBar == 0;
    final activeColor =
        strongBeat ? const Color(0xFFFFC66E) : const Color(0xFF79DCA7);
    final inactiveAlpha = barStart ? 0.16 : (strongBeat ? 0.115 : 0.070);
    final baseColor = enabled
        ? activeColor.withValues(alpha: selectedLane ? 0.92 : 0.72)
        : Colors.white.withValues(alpha: inactiveAlpha);
    final playheadColor = enabled
        ? Color.alphaBlend(
            const Color(0xFFFFD45A).withValues(alpha: 0.34),
            baseColor,
          )
        : const Color(0xFFFFD45A).withValues(alpha: 0.24);

    return Semantics(
      button: true,
      selected: enabled,
      label: '${lane.label} step ${step + 1}',
      child: GestureDetector(
        key: ValueKey<String>('sequencer_step_${lane.pitch}_$step'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.isRecording
            ? null
            : () => _toggleSequencerStep(pitch: lane.pitch, step: step),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 95),
          curve: Curves.easeOutCubic,
          width: width,
          height: double.infinity,
          decoration: BoxDecoration(
            color: playheadActive ? playheadColor : baseColor,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: playheadActive
                  ? const Color(0xFFFFD45A)
                  : (enabled
                      ? Colors.white.withValues(alpha: 0.44)
                      : Colors.white.withValues(alpha: 0.10)),
              width: playheadActive ? 2.0 : 1.0,
            ),
            boxShadow: enabled && selectedLane
                ? <BoxShadow>[
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.24),
                      blurRadius: 8,
                      offset: const Offset(0, 0),
                    ),
                    if (playheadActive)
                      const BoxShadow(
                        color: Color(0x66FFD45A),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                  ]
                : playheadActive
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x44FFD45A),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
          ),
          child: enabled
              ? Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 95),
                    curve: Curves.easeOutCubic,
                    width: selectedLane ? 8 : 6,
                    height: selectedLane ? 8 : 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: selectedLane ? 0.88 : 0.62,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : barStart
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 12,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    )
                  : null,
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
                              child: DesktopScrollableSlider(
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
                      tooltip: L10n.translate(context, 'Copy'),
                      enabled: true,
                      onTap: _copySelectedNotes,
                    ),
                    _trayAction(
                      icon: Icons.content_paste_rounded,
                      tooltip: L10n.translate(context, 'Paste'),
                      enabled: hasCopiedNotes,
                      onTap: _pasteNotes,
                    ),
                    _trayAction(
                      icon: Icons.control_point_duplicate_rounded,
                      tooltip: L10n.translate(context, 'Duplicate'),
                      enabled: true,
                      onTap: _duplicateSelectedNotes,
                    ),
                    _trayAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: L10n.translate(context, 'Delete'),
                      enabled: true,
                      onTap: _deleteSelectedNotes,
                      danger: true,
                    ),
                    _selectionTextActionRow(
                      velocityActive: _velocityPanelOpen,
                    ),
                    _trayAction(
                      icon: Icons.close_rounded,
                      tooltip: L10n.translate(context, 'Close'),
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
      case 'On Device':
        return const Color(0xFF7CCBFF);
      case 'Guitars':
        return const Color(0xFF67A6FF);
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
      case 'On Device':
        return Icons.developer_board_rounded;
      case 'Guitars':
        return CupertinoIcons.guitars;
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

  String _instrumentCategoryLabel(String category) {
    return L10n.translate(context, category);
  }

  Widget _buildInstrumentTab() {
    final category = _instrumentVisualCategory();
    final accent = _instrumentVisualAccent(category);
    final sampled = _isSampledInstrumentId(_instrumentId);
    final externalPlugin = _currentInstrumentIsExternalPlugin;
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
                        L10n.translate(context, 'Instrument'),
                        style: TextStyle(
                          color: _kPianoShellMutedText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      Text(
                        _instrumentName.isEmpty
                            ? L10n.translate(context, 'Instrument')
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
                if (externalPlugin && widget.onOpenCurrentInstrumentUi != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        unawaited(widget.onOpenCurrentInstrumentUi!.call());
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _kPianoShellFillStrong,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: accent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              L10n.translate(context, 'Open UI'),
                              style: TextStyle(
                                color: _kPianoShellText,
                                fontFamily: 'Pretendard',
                                fontSize: 10.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (widget.canReplaceSamplerSource &&
                    widget.onReplaceSamplerSource != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        unawaited(widget.onReplaceSamplerSource!.call());
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _kPianoShellFillStrong,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.find_replace_rounded,
                              size: 13,
                              color: accent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              L10n.translate(context, 'Replace source'),
                              style: TextStyle(
                                color: _kPianoShellText,
                                fontFamily: 'Pretendard',
                                fontSize: 10.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    _instrumentCategoryLabel(category),
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
                            _instrumentCategoryLabel(c),
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
                      L10n.translate(
                          context, 'No instruments in this category.'),
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
            _buildSamplerEnvelopePanel(accent: accent),
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

  Widget _buildSamplerEnvelopePanel({required Color accent}) {
    final attack = (_params['attackMs'] ?? 6.0).clamp(0.0, 600.0).toDouble();
    final decay = (_params['decayMs'] ?? 120.0).clamp(0.0, 900.0).toDouble();
    final sustain =
        (_params['sustainLevel'] ?? 0.86).clamp(0.05, 1.0).toDouble();
    final release =
        (_params['releaseMs'] ?? 520.0).clamp(20.0, 1800.0).toDouble();
    final output = (_params['outputGain'] ?? 0.72).clamp(0.2, 2.0).toDouble();
    final filterCutoff = (_params['sampleFilterCutoffHz'] ?? 20000.0)
        .clamp(80.0, 20000.0)
        .toDouble();
    final granular = _isGranularizerParams();

    void setParam(String key, double value) {
      setState(() => _params[key] = value);
      if (key == 'sampleLowKey' || key == 'sampleHighKey') {
        _refreshPlayablePitches();
      }
      _queueCommit();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: _kPianoShellFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  granular ? 'Granularizer' : 'Sampler envelope',
                  style: const TextStyle(
                    color: _kPianoShellText,
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${(output * 100).round()}%',
                style: TextStyle(
                  color: _kPianoShellMutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Pretendard',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSamplerWaveformEditor(accent: accent, setParam: setParam),
          const SizedBox(height: 11),
          _buildSamplerModeStrip(accent: accent, setParam: setParam),
          if (granular) ...[
            const SizedBox(height: 11),
            _buildGranularizerControls(accent: accent, setParam: setParam),
          ],
          const SizedBox(height: 11),
          SizedBox(
            height: granular ? 76 : 106,
            width: double.infinity,
            child: CustomPaint(
              painter: _SamplerEnvelopePainter(
                attackMs: attack,
                decayMs: decay,
                sustainLevel: sustain,
                releaseMs: release,
                accent: accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _samplerEnvelopeRow(
            label: 'A',
            name: 'Attack',
            value: attack,
            min: 0.0,
            max: 600.0,
            accent: accent,
            valueLabelBuilder: _formatEnvelopeMs,
            onChanged: (value) => setParam('attackMs', value),
          ),
          _samplerEnvelopeRow(
            label: 'D',
            name: 'Decay',
            value: decay,
            min: 0.0,
            max: 900.0,
            accent: accent,
            valueLabelBuilder: _formatEnvelopeMs,
            onChanged: (value) => setParam('decayMs', value),
          ),
          _samplerEnvelopeRow(
            label: 'S',
            name: 'Sustain',
            value: sustain,
            min: 0.05,
            max: 1.0,
            accent: accent,
            valueLabelBuilder: (value) => '${(value * 100).round()}%',
            onChanged: (value) => setParam('sustainLevel', value),
          ),
          _samplerEnvelopeRow(
            label: 'R',
            name: 'Release',
            value: release,
            min: 20.0,
            max: 1800.0,
            accent: accent,
            valueLabelBuilder: _formatEnvelopeMs,
            onChanged: (value) => setParam('releaseMs', value),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 7),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          _samplerEnvelopeRow(
            label: 'G',
            name: 'Gain',
            value: output,
            min: 0.2,
            max: 2.0,
            accent: accent,
            valueLabelBuilder: (value) => '${(value * 100).round()}%',
            onChanged: (value) => setParam('outputGain', value),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 7),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          _samplerEnvelopeRow(
            label: 'F',
            name: 'Filter',
            value: filterCutoff,
            min: 80.0,
            max: 20000.0,
            accent: accent,
            valueLabelBuilder: _formatFrequency,
            onChanged: (value) => setParam('sampleFilterCutoffHz', value),
          ),
          const SizedBox(height: 8),
          _buildSamplerMappingEditor(accent: accent, setParam: setParam),
        ],
      ),
    );
  }

  Widget _buildSamplerWaveformEditor({
    required Color accent,
    required void Function(String key, double value) setParam,
  }) {
    final start =
        (_params['sampleStartNorm'] ?? 0.0).clamp(0.0, 0.98).toDouble();
    final end = (_params['sampleEndNorm'] ?? 1.0).clamp(0.02, 1.0).toDouble();
    final safeStart = math.min(start, end - 0.02);
    final safeEnd = math.max(end, safeStart + 0.02);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 118,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<List<double>>(
              future: _samplerWaveformFuture,
              builder: (context, snapshot) {
                return CustomPaint(
                  painter: _SamplerWaveformPainter(
                    accent: accent,
                    peaks: snapshot.data ?? const <double>[],
                    startNorm: safeStart,
                    endNorm: safeEnd,
                    reverse: (_params['reverseSample'] ?? 0.0) >= 0.5,
                    sliceMode: (_params['sliceMode'] ?? 0.0) >= 0.5,
                    sliceCount:
                        (_params['sliceCount'] ?? 8.0).round().clamp(2, 32),
                  ),
                );
              },
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 2,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent.withValues(alpha: 0.34),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
                  rangeThumbShape:
                      const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbColor: _kPianoShellText,
                  overlayColor: accent.withValues(alpha: 0.14),
                  trackHeight: 2.5,
                ),
                child: DesktopScrollableRangeSlider(
                  values: RangeValues(safeStart, safeEnd),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (values) {
                    final nextStart = math.min(values.start, values.end - 0.02);
                    final nextEnd = math.max(values.end, nextStart + 0.02);
                    setParam('sampleStartNorm', nextStart);
                    setParam('sampleEndNorm', nextEnd);
                  },
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 9,
              child: _samplerBadge('Start ${(safeStart * 100).round()}%'),
            ),
            Positioned(
              right: 12,
              top: 9,
              child: _samplerBadge('End ${(safeEnd * 100).round()}%'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGranularizerControls({
    required Color accent,
    required void Function(String key, double value) setParam,
  }) {
    final transientMode =
        (_params['grainTransientMode'] ?? 0.0).round().clamp(0, 2);
    final keyMode = (_params['grainKeyMode'] ?? 0.0).round().clamp(0, 3);
    return Column(
      children: [
        _samplerEnvelopeRow(
          label: 'AT',
          name: 'Attack',
          value:
              (_params['grainAttackMs'] ?? 18.0).clamp(0.0, 250.0).toDouble(),
          min: 0.0,
          max: 250.0,
          accent: accent,
          valueLabelBuilder: _formatEnvelopeMs,
          onChanged: (value) => setParam('grainAttackMs', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'HD',
          name: 'Hold',
          value: (_params['grainHoldMs'] ?? 42.0).clamp(2.0, 500.0).toDouble(),
          min: 2.0,
          max: 500.0,
          accent: accent,
          valueLabelBuilder: _formatEnvelopeMs,
          onChanged: (value) => setParam('grainHoldMs', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'GS',
          name: 'Grain',
          value: (_params['grainSpacingPct'] ?? 100.0)
              .clamp(1.0, 400.0)
              .toDouble(),
          min: 1.0,
          max: 400.0,
          accent: accent,
          valueLabelBuilder: (value) => '${value.round()}%',
          onChanged: (value) => setParam('grainSpacingPct', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'WS',
          name: 'Wave',
          value: (_params['waveSpacingPct'] ?? 100.0)
              .clamp(-400.0, 400.0)
              .toDouble(),
          min: -400.0,
          max: 400.0,
          accent: accent,
          valueLabelBuilder: (value) => '${value.round()}%',
          onChanged: (value) => setParam('waveSpacingPct', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'PN',
          name: 'Pan',
          value: (_params['grainPan'] ?? 0.34).clamp(-1.0, 1.0).toDouble(),
          min: -1.0,
          max: 1.0,
          accent: accent,
          valueLabelBuilder: (value) => value.abs() < 0.01
              ? 'C'
              : value < 0.0
                  ? 'L ${(value.abs() * 100).round()}'
                  : 'R ${(value * 100).round()}',
          onChanged: (value) => setParam('grainPan', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'DP',
          name: 'Depth',
          value:
              (_params['grainLfoDepthPct'] ?? 0.0).clamp(0.0, 100.0).toDouble(),
          min: 0.0,
          max: 100.0,
          accent: accent,
          valueLabelBuilder: (value) => '${value.round()}%',
          onChanged: (value) => setParam('grainLfoDepthPct', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'SP',
          name: 'Speed',
          value:
              (_params['grainLfoSpeedHz'] ?? 0.8).clamp(0.0, 20.0).toDouble(),
          min: 0.0,
          max: 20.0,
          accent: accent,
          valueLabelBuilder: (value) =>
              value <= 0.0 ? 'Off' : '${value.toStringAsFixed(1)} Hz',
          onChanged: (value) => setParam('grainLfoSpeedHz', value),
          compact: true,
        ),
        _samplerEnvelopeRow(
          label: 'RD',
          name: 'Rand',
          value:
              (_params['grainRandomPct'] ?? 0.0).clamp(0.0, 100.0).toDouble(),
          min: 0.0,
          max: 100.0,
          accent: accent,
          valueLabelBuilder: (value) => '${value.round()}%',
          onChanged: (value) => setParam('grainRandomPct', value),
          compact: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _samplerSegment(
                labels: const ['Off', 'Tran', 'Gate'],
                selectedIndex: transientMode,
                accent: accent,
                onSelected: (index) =>
                    setParam('grainTransientMode', index.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 116,
              child: _samplerStepper(
                label: 'Hold',
                value: (_params['grainTransientHoldMs'] ?? 80.0)
                    .round()
                    .clamp(2, 500),
                accent: accent,
                valueLabelBuilder: (value) => '$value ms',
                onChanged: (value) =>
                    setParam('grainTransientHoldMs', value.toDouble()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _samplerSegment(
          labels: const ['Pitch', 'Start', 'Step', 'Trans'],
          selectedIndex: keyMode,
          accent: accent,
          onSelected: (index) => setParam('grainKeyMode', index.toDouble()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _samplerToggleButton(
                label: 'Loop',
                icon: Icons.loop_rounded,
                selected: (_params['grainLoop'] ?? 1.0) >= 0.5,
                accent: accent,
                onTap: () => setParam(
                  'grainLoop',
                  (_params['grainLoop'] ?? 1.0) >= 0.5 ? 0.0 : 1.0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _samplerToggleButton(
                label: 'Hold',
                icon: Icons.pause_circle_outline_rounded,
                selected: (_params['grainPositionHold'] ?? 0.0) >= 0.5,
                accent: accent,
                onTap: () => setParam(
                  'grainPositionHold',
                  (_params['grainPositionHold'] ?? 0.0) >= 0.5 ? 0.0 : 1.0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSamplerModeStrip({
    required Color accent,
    required void Function(String key, double value) setParam,
  }) {
    final playMode = (_params['samplePlayMode'] ?? 0.0).round();
    final stretchMode = (_params['timeStretchMode'] ?? 0.0).round();
    final sliceMode = (_params['sliceMode'] ?? 0.0).round();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _samplerToggleButton(
                label: 'Reverse',
                icon: Icons.swap_horiz_rounded,
                selected: (_params['reverseSample'] ?? 0.0) >= 0.5,
                accent: accent,
                onTap: () => setParam(
                  'reverseSample',
                  (_params['reverseSample'] ?? 0.0) >= 0.5 ? 0.0 : 1.0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _samplerToggleButton(
                label: 'Normalize',
                icon: Icons.vertical_align_top_rounded,
                selected: (_params['normalizeSample'] ?? 0.0) >= 0.5,
                accent: accent,
                onTap: () => setParam(
                  'normalizeSample',
                  (_params['normalizeSample'] ?? 0.0) >= 0.5 ? 0.0 : 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _samplerSegment(
                labels: const ['Gate', 'One-shot'],
                selectedIndex: playMode.clamp(0, 1),
                accent: accent,
                onSelected: (index) =>
                    setParam('samplePlayMode', index.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _samplerSegment(
                labels: const ['Repitch', 'Stretch'],
                selectedIndex: stretchMode.clamp(0, 1),
                accent: accent,
                onSelected: (index) =>
                    setParam('timeStretchMode', index.toDouble()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _samplerSegment(
                labels: const ['Keys', 'Slice'],
                selectedIndex: sliceMode.clamp(0, 1),
                accent: accent,
                onSelected: (index) => setParam('sliceMode', index.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              child: _samplerStepper(
                label: 'Slices',
                value: (_params['sliceCount'] ?? 8.0).round().clamp(2, 32),
                accent: accent,
                onChanged: (value) => setParam('sliceCount', value.toDouble()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSamplerMappingEditor({
    required Color accent,
    required void Function(String key, double value) setParam,
  }) {
    final root = (_params['rootNote'] ?? 60.0).round().clamp(0, 127);
    final low = (_params['sampleLowKey'] ?? 0.0).clamp(0.0, 127.0).toDouble();
    final high =
        (_params['sampleHighKey'] ?? 127.0).clamp(0.0, 127.0).toDouble();
    final safeLow = math.min(low, high - 1.0).clamp(0.0, 126.0).toDouble();
    final safeHigh = math.max(high, safeLow + 1.0).clamp(1.0, 127.0).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _samplerStepper(
                label: 'Root',
                value: root,
                accent: accent,
                valueLabelBuilder: _noteNameForMidi,
                onChanged: (value) => setParam('rootNote', value.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _samplerBadge(
                '${_noteNameForMidi(safeLow.round())} - ${_noteNameForMidi(safeHigh.round())}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            trackHeight: 2.8,
          ),
          child: DesktopScrollableRangeSlider(
            values: RangeValues(safeLow, safeHigh),
            min: 0,
            max: 127,
            divisions: 127,
            onChanged: (values) {
              setParam('sampleLowKey', values.start.roundToDouble());
              setParam('sampleHighKey', values.end.roundToDouble());
            },
          ),
        ),
      ],
    );
  }

  Widget _samplerToggleButton({
    required String label,
    required IconData icon,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.36)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15, color: selected ? accent : _kPianoShellMutedText),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _kPianoShellText : _kPianoShellMutedText,
                    fontFamily: 'Pretendard',
                    fontSize: 10.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _samplerSegment({
    required List<String> labels,
    required int selectedIndex,
    required Color accent,
    required ValueChanged<int> onSelected,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedIndex == i
                        ? accent.withValues(alpha: 0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[i],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedIndex == i
                          ? _kPianoShellText
                          : _kPianoShellMutedText,
                      fontFamily: 'Pretendard',
                      fontSize: 10.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _samplerStepper({
    required String label,
    required int value,
    required Color accent,
    required ValueChanged<int> onChanged,
    String Function(int value)? valueLabelBuilder,
  }) {
    final displayValue = valueLabelBuilder?.call(value) ?? '$value';
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kPianoShellMutedText,
                fontFamily: 'Pretendard',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _samplerStepperButton(
            icon: Icons.remove_rounded,
            onTap: () => onChanged((value - 1).clamp(0, 127)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(
              displayValue,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontFamily: 'Pretendard',
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _samplerStepperButton(
            icon: Icons.add_rounded,
            onTap: () => onChanged((value + 1).clamp(0, 127)),
          ),
        ],
      ),
    );
  }

  Widget _samplerStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: icon == Icons.add_rounded ? 'Increase' : 'Decrease',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 19,
          height: 26,
          child: Icon(icon, size: 15, color: _kPianoShellMutedText),
        ),
      ),
    );
  }

  Widget _samplerBadge(String label) {
    return Container(
      height: 26,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _kPianoShellMutedText,
          fontFamily: 'Pretendard',
          fontSize: 10.3,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _formatEnvelopeMs(double value) {
    if (value >= 1000.0) {
      return '${(value / 1000.0).toStringAsFixed(1)} s';
    }
    return '${value.round()} ms';
  }

  String _formatFrequency(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)} kHz';
    }
    return '${value.round()} Hz';
  }

  String _noteNameForMidi(int midi) {
    const names = [
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
      'B'
    ];
    final clamped = midi.clamp(0, 127);
    final octave = (clamped ~/ 12) - 1;
    return '${names[clamped % 12]}$octave';
  }

  Widget _samplerEnvelopeRow({
    required String label,
    required String name,
    required double value,
    required double min,
    required double max,
    required Color accent,
    required String Function(double value) valueLabelBuilder,
    required ValueChanged<double> onChanged,
    bool compact = false,
  }) {
    final labelWidth = compact ? 22.0 : 24.0;
    final nameWidth = compact ? 50.0 : 58.0;
    final valueWidth = compact ? 46.0 : 52.0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                color: accent,
                fontFamily: 'Pretendard',
                fontSize: compact ? 10.7 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: nameWidth,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _kPianoShellText,
                fontFamily: 'Pretendard',
                fontSize: compact ? 10.7 : 11.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: compact ? 36 : 46,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  thumbColor: _kPianoShellText,
                  overlayColor: accent.withValues(alpha: 0.18),
                  trackHeight: compact ? 3.2 : 2.8,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: compact ? 6 : 5,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: compact ? 18 : 14,
                  ),
                ),
                child: DesktopScrollableSlider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
          SizedBox(
            width: valueWidth,
            child: Text(
              valueLabelBuilder(value),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _kPianoShellMutedText,
                fontSize: compact ? 10.1 : 10.6,
                fontWeight: FontWeight.w800,
                fontFamily: 'Pretendard',
              ),
            ),
          ),
        ],
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
            child: DesktopScrollableSlider(
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

  Widget _buildPianoKeys({
    Set<int> playbackPitches = const <int>{},
  }) {
    const blackKeyWidth = _pianoKeyBlackWidth;
    final pitchRange = _visiblePitchRange;
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
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          final pitch = _pianoKeyPitchForLocalPosition(event.localPosition);
          if (pitch != null) {
            _handlePianoKeyPointerDown(event, pitch);
          }
        },
        onPointerMove: _handlePianoKeyPointerMove,
        onPointerUp: _handlePianoKeyPointerRelease,
        onPointerCancel: _handlePianoKeyPointerRelease,
        onPointerSignal: _onGridPointerSignal,
        child: _hideDesktopScrollbars(
          SingleChildScrollView(
            controller: _keysVerticalController,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: _contentHeight,
              child: Column(
                children: List<Widget>.generate(_pitchCount, (i) {
                  final pitch = maxPitch - i;
                  final isBlack = _isBlackKey(pitch);
                  final isPlayable = _isPitchPlayable(pitch);
                  final noteName = _noteNameForPitch(pitch);
                  final isPressed = _isPreviewPitchActive(pitch) ||
                      playbackPitches.contains(pitch);
                  final showLabel = pitch % 12 == 0 ||
                      pitch == _absoluteMaxPitch ||
                      isPressed;
                  final blackTop = isPressed
                      ? const Color(0xFF737D86)
                      : const Color(0xFF525A62);
                  final blackBottom = isPressed
                      ? const Color(0xFF626B74)
                      : const Color(0xFF454C54);
                  final rowFill = isBlack
                      ? const Color(0xFFF6F8FA)
                      : (isPressed
                          ? const Color(0xFFE0EAF7)
                          : const Color(0xFFF8F9FA));
                  final keyOverlayColor = (isBlack
                          ? const Color(0xFF79B5FF)
                          : const Color(0xFF5FA8FF))
                      .withValues(alpha: isBlack ? 0.18 : 0.14);
                  return SizedBox(
                    key: ValueKey<String>('piano_key_$pitch'),
                    height: _rowHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(color: rowFill),
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
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 0.7,
                              color: const Color(0xFFD8DDE1),
                            ),
                          ),
                        if (isPressed)
                          Positioned(
                            key: ValueKey<String>(
                              'piano_key_active_shape_$pitch',
                            ),
                            left: 0,
                            right: isBlack ? null : 0,
                            top: 0,
                            bottom: 0,
                            width: isBlack ? blackKeyWidth : null,
                            child: IgnorePointer(
                              child: Container(
                                key: ValueKey<String>(
                                  'piano_key_active_overlay_$pitch',
                                ),
                                decoration: BoxDecoration(
                                  color: keyOverlayColor,
                                  borderRadius: isBlack
                                      ? const BorderRadius.horizontal(
                                          right: Radius.circular(1.2),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        if (!isPlayable)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                key: ValueKey<String>(
                                  'piano_key_disabled_$pitch',
                                ),
                                color: const Color(0xFF8C949B)
                                    .withValues(alpha: 0.58),
                              ),
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
                                color: !isPlayable
                                    ? const Color(0xFF6E747A)
                                    : isBlack
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
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRollGrid() {
    final physics = (_lockGridScroll || _desktopWheelZoomModifierPressed)
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();
    final pitchRange = _visiblePitchRange;
    final showDesktopRuler = PlatformCapabilities.current.isDesktop;
    return Container(
      key: _rollViewportKey,
      color: const Color(0xFF41474E),
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleFollowModeScrollNotification,
              child: _hideDesktopScrollbars(
                SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  physics: physics,
                  child: SizedBox(
                    width: _contentWidth,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: _onGridPointerSignal,
                      onPointerPanZoomStart: _onGridPointerPanZoomStart,
                      onPointerPanZoomUpdate: _onGridPointerPanZoomUpdate,
                      onPointerPanZoomEnd: _onGridPointerPanZoomEnd,
                      child: SizedBox(
                        height: _contentHeight +
                            (showDesktopRuler ? _rulerHeight : 0.0),
                        child: Column(
                          children: [
                            if (showDesktopRuler) _buildRollRuler(),
                            Expanded(
                              child: _hideDesktopScrollbars(
                                SingleChildScrollView(
                                  key: _gridViewportKey,
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
                                      onPointerSignal: _onGridPointerSignal,
                                      child: _buildFollowTranslatedContent(
                                        GestureDetector(
                                          key: const ValueKey<String>(
                                            'piano_roll_grid_canvas',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          dragStartBehavior:
                                              DragStartBehavior.down,
                                          onTapUp: (details) => _addNoteAt(
                                            details.localPosition,
                                          ),
                                          onLongPressStart: PlatformCapabilities
                                                  .current.isDesktop
                                              ? null
                                              : _startBoxSelection,
                                          onLongPressMoveUpdate:
                                              PlatformCapabilities
                                                      .current.isDesktop
                                                  ? null
                                                  : _updateBoxSelection,
                                          onLongPressEnd: PlatformCapabilities
                                                  .current.isDesktop
                                              ? null
                                              : (_) => _finishBoxSelection(),
                                          onLongPressCancel:
                                              PlatformCapabilities
                                                      .current.isDesktop
                                                  ? null
                                                  : _cancelBoxSelection,
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  key: ValueKey<String>(
                                                    'piano_roll_grid_divisions_$_effectiveQuantizeDivisionsPerBar',
                                                  ),
                                                  painter: _PianoGridPainter(
                                                    rowHeight: _rowHeight,
                                                    pxPerBeat: _pxPerBeat,
                                                    leadingBeatPadPx:
                                                        _followLeadingPaddingPx,
                                                    maxPitch: pitchRange.max,
                                                    minPitch: pitchRange.min,
                                                    maxBeat: _maxBeat,
                                                    beatsPerBar:
                                                        widget.beatsPerBar,
                                                    beatUnit: widget.beatUnit,
                                                    quantizeDivisionsPerBar:
                                                        _effectiveQuantizeDivisionsPerBar,
                                                    magnetEnabled:
                                                        widget.magnetEnabled,
                                                    playablePitches:
                                                        _playablePitches,
                                                  ),
                                                ),
                                              ),
                                              for (final pitch in <int>{
                                                ..._pressedPreviewCounts.keys,
                                                ...widget.highlightedPitches,
                                              })
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  top: _yForPitch(pitch),
                                                  height: _rowHeight,
                                                  child: IgnorePointer(
                                                    child: Container(
                                                      color: _kPianoWarmBorder
                                                          .withValues(
                                                        alpha: 0.18,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              for (final note in _displayNotes)
                                                _buildNoteWidget(note),
                                              if (_currentSelectionRect != null)
                                                Positioned.fromRect(
                                                  rect: _currentSelectionRect!,
                                                  child: IgnorePointer(
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0x2B78A7FF,
                                                        ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xFF8CB6FF,
                                                          ),
                                                          width: 1.2,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: ValueListenableBuilder<
                                                      double>(
                                                    valueListenable:
                                                        _visualPlayheadBeat,
                                                    builder: (
                                                      context,
                                                      visualBeat,
                                                      _,
                                                    ) {
                                                      return CustomPaint(
                                                        painter:
                                                            _PianoRollPlayheadLinePainter(
                                                          x: _xForBeat(
                                                            visualBeat,
                                                          ),
                                                        ),
                                                      );
                                                    },
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_selectedNotes.isNotEmpty && !widget.isRecording)
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

  Widget _buildFollowTranslatedContent(Widget child) {
    if (!_followPlayhead) return child;
    return AnimatedBuilder(
      animation: _playheadAndHorizontalScroll,
      child: child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_followVisualShift, 0),
          child: child,
        );
      },
    );
  }

  double get _followVisualShift {
    if (!_followPlayhead || !_horizontalController.hasClients) return 0.0;
    return _horizontalController.offset -
        (_visualClipPlayheadBeat * _pxPerBeat);
  }

  Widget _buildRollRuler() {
    return SizedBox(
      height: _rulerHeight,
      child: _buildFollowTranslatedContent(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: PlatformCapabilities.current.isDesktop
              ? (details) {
                  _setPlayheadFromBeat(_beatForX(details.localPosition.dx));
                }
              : null,
          onHorizontalDragStart: PlatformCapabilities.current.isDesktop
              ? (details) {
                  _setPlayheadFromBeat(_beatForX(details.localPosition.dx));
                }
              : null,
          onHorizontalDragUpdate: PlatformCapabilities.current.isDesktop
              ? (details) {
                  _setPlayheadFromBeat(_beatForX(details.localPosition.dx));
                }
              : null,
          child: SizedBox(
            width: _contentWidth,
            height: _rulerHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PianoRollRulerPainter(
                      pxPerBeat: _pxPerBeat,
                      leadingBeatPadPx: _followLeadingPaddingPx,
                      maxBeat: _maxBeat,
                      beatsPerBar: widget.beatsPerBar,
                      beatUnit: widget.beatUnit,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _visualPlayheadBeat,
                      builder: (context, visualBeat, _) {
                        return CustomPaint(
                          painter: _PianoRollRulerPlayheadPainter(
                            x: _xForBeat(visualBeat),
                          ),
                        );
                      },
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

  Widget _buildNoteWidget(MidiNote note) {
    final selected = _effectiveSelectedIds.contains(note.id);
    final paddedLeft = _xForBeat(note.startBeat);
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
      left: paddedLeft,
      top: top + 1,
      width: width,
      height: _rowHeight - 2,
      child: Listener(
        onPointerDown: (_) {
          if (widget.isRecording) return;
          _setGridScrollLocked(true);
          _suppressGridTapFor();
        },
        onPointerUp: (_) {
          if (!widget.isRecording) {
            _setGridScrollLocked(false);
          }
        },
        onPointerCancel: (_) {
          if (!widget.isRecording) {
            _setGridScrollLocked(false);
          }
        },
        child: GestureDetector(
          key: ValueKey<String>('piano_note_${note.id}'),
          behavior: HitTestBehavior.translucent,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (_) {
            if (widget.isRecording) return;
            if (_desktopSelectionModifierActive) return;
            setState(() {
              _focusNoteSelection(note.id);
            });
          },
          onTapUp: (_) {
            if (widget.isRecording) {
              _setGridScrollLocked(false);
              return;
            }
            if (_desktopSelectionModifierActive) {
              _setGridScrollLocked(false);
              return;
            }
            _previewPianoKey(note.pitch, velocity: note.velocity);
            _suppressGridTapFor();
            Future<void>.delayed(const Duration(milliseconds: 90), () {
              if (!mounted) return;
              _releasePianoKey(note.pitch);
            });
            _setGridScrollLocked(false);
          },
          onTapCancel: () {
            if (widget.isRecording) return;
            _releasePianoKey(note.pitch);
            _setGridScrollLocked(false);
          },
          onPanStart: (details) => setState(() {
            if (widget.isRecording) {
              _setGridScrollLocked(false);
              return;
            }
            if (_desktopSelectionModifierActive) {
              _setGridScrollLocked(false);
              return;
            }
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
    bool active = false,
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
              color: active
                  ? _kPianoShellFillStrong
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? _kPianoWarmBorder
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              color: active ? _kPianoWarmBorder : Colors.white,
              size: 17,
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactIconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: _kPianoShellText, size: 17),
          ),
        ),
      ),
    );
  }

  Widget _sequencerInfoPill(String label) {
    return Container(
      height: 30,
      constraints: const BoxConstraints(minWidth: 54),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            color: _kPianoShellText,
            fontFamily: 'Pretendard',
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _sequencerMacroButton({
    Key? key,
    required String label,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: Container(
            height: 26,
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: _kPianoWarmBorder.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _kPianoWarmBorder.withValues(alpha: 0.45),
              ),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: _kPianoShellText,
                  fontFamily: 'Pretendard',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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
              child: DesktopScrollableSlider(
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

class _SamplerEnvelopePainter extends CustomPainter {
  _SamplerEnvelopePainter({
    required this.attackMs,
    required this.decayMs,
    required this.sustainLevel,
    required this.releaseMs,
    required this.accent,
  });

  final double attackMs;
  final double decayMs;
  final double sustainLevel;
  final double releaseMs;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.075),
          Colors.white.withValues(alpha: 0.025),
        ],
      ).createShader(rect);
    final radius = BorderRadius.circular(12).toRRect(rect);
    canvas.drawRRect(radius, bgPaint);
    canvas.drawRRect(
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final plot = rect.deflate(13);
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.055);
    for (var i = 1; i <= 3; i++) {
      final y = plot.top + (plot.height * i / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final attackW = _phaseWidth(attackMs, 600.0, 0.08, 0.24);
    final decayW = _phaseWidth(decayMs, 900.0, 0.09, 0.24);
    final releaseW = _phaseWidth(releaseMs, 1800.0, 0.13, 0.30);
    final sustainW = math.max(0.20, 1.0 - attackW - decayW - releaseW);
    final total = attackW + decayW + sustainW + releaseW;

    final x0 = plot.left;
    final xA = plot.left + plot.width * attackW / total;
    final xD = xA + plot.width * decayW / total;
    final xS = xD + plot.width * sustainW / total;
    final xR = plot.right;
    final yBase = plot.bottom - 4;
    final yPeak = plot.top + 5;
    final safeSustain = sustainLevel.clamp(0.05, 1.0).toDouble();
    final ySustain = yBase - ((yBase - yPeak) * safeSustain);

    final curve = Path()
      ..moveTo(x0, yBase)
      ..lineTo(xA, yPeak)
      ..quadraticBezierTo((xA + xD) * 0.5, ySustain, xD, ySustain)
      ..lineTo(xS, ySustain)
      ..quadraticBezierTo((xS + xR) * 0.58, yBase, xR, yBase);

    final fill = Path.from(curve)
      ..lineTo(xR, yBase)
      ..lineTo(x0, yBase)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(plot),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );

    final guidePaint = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.10);
    for (final x in [xA, xD, xS]) {
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), guidePaint);
    }

    _drawPhaseLabel(canvas, 'A', Offset((x0 + xA) * 0.5, plot.bottom - 13));
    _drawPhaseLabel(canvas, 'D', Offset((xA + xD) * 0.5, plot.bottom - 13));
    _drawPhaseLabel(canvas, 'S', Offset((xD + xS) * 0.5, plot.bottom - 13));
    _drawPhaseLabel(canvas, 'R', Offset((xS + xR) * 0.5, plot.bottom - 13));
  }

  double _phaseWidth(
    double value,
    double max,
    double minWidth,
    double maxWidth,
  ) {
    final t = (value / max).clamp(0.0, 1.0).toDouble();
    return minWidth + (maxWidth - minWidth) * math.sqrt(t);
  }

  void _drawPhaseLabel(Canvas canvas, String label, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.62),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: 'Pretendard',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SamplerEnvelopePainter oldDelegate) {
    return attackMs != oldDelegate.attackMs ||
        decayMs != oldDelegate.decayMs ||
        sustainLevel != oldDelegate.sustainLevel ||
        releaseMs != oldDelegate.releaseMs ||
        accent != oldDelegate.accent;
  }
}

class _SamplerWaveformPainter extends CustomPainter {
  _SamplerWaveformPainter({
    required this.accent,
    required this.peaks,
    required this.startNorm,
    required this.endNorm,
    required this.reverse,
    required this.sliceMode,
    required this.sliceCount,
  });

  final Color accent;
  final List<double> peaks;
  final double startNorm;
  final double endNorm;
  final bool reverse;
  final bool sliceMode;
  final int sliceCount;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.055),
          Colors.white.withValues(alpha: 0.018),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final centerY = size.height * 0.52;
    final halfHeight = size.height * 0.32;
    final inactive = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = accent.withValues(alpha: 0.86)
      ..strokeWidth = 1.45
      ..strokeCap = StrokeCap.round;

    final startX = size.width * startNorm.clamp(0.0, 1.0);
    final endX = size.width * endNorm.clamp(0.0, 1.0);
    final sourcePeaks = peaks.isEmpty ? null : peaks;

    for (int x = 0; x < size.width.round(); x += 3) {
      final t = x / math.max(1.0, size.width);
      final amp = _ampFor(t, sourcePeaks) * halfHeight;
      final paint = x >= startX && x <= endX ? active : inactive;
      canvas.drawLine(
        Offset(x.toDouble(), centerY - amp),
        Offset(x.toDouble(), centerY + amp),
        paint,
      );
    }

    final selectedRect = Rect.fromLTRB(startX, 0, endX, size.height);
    canvas.drawRect(
      selectedRect,
      Paint()..color = accent.withValues(alpha: 0.055),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, 0, startX, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );
    canvas.drawRect(
      Rect.fromLTRB(endX, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );

    final handlePaint = Paint()..color = _kPianoShellText;
    for (final x in [startX, endX]) {
      final handle = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 4,
          height: size.height - 28,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(handle, handlePaint);
    }

    if (sliceMode) {
      final count = sliceCount.clamp(2, 32);
      final slicePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.17)
        ..strokeWidth = 1;
      for (int i = 1; i < count; i++) {
        final x = startX + ((endX - startX) * i / count);
        canvas.drawLine(Offset(x, 28), Offset(x, size.height - 30), slicePaint);
      }
    }

    if (reverse) {
      final arrowPaint = Paint()
        ..color = accent.withValues(alpha: 0.72)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final y = size.height - 22;
      canvas.drawLine(Offset(endX - 12, y), Offset(startX + 12, y), arrowPaint);
      canvas.drawLine(
          Offset(startX + 12, y), Offset(startX + 20, y - 5), arrowPaint);
      canvas.drawLine(
          Offset(startX + 12, y), Offset(startX + 20, y + 5), arrowPaint);
    }
  }

  double _ampFor(double t, List<double>? sourcePeaks) {
    if (sourcePeaks != null && sourcePeaks.isNotEmpty) {
      final sampleT = reverse ? 1.0 - t : t;
      final index = (sampleT.clamp(0.0, 1.0) * (sourcePeaks.length - 1))
          .round()
          .clamp(0, sourcePeaks.length - 1)
          .toInt();
      return sourcePeaks[index].clamp(0.04, 1.0);
    }
    final env = math.sin(math.pi * t).abs();
    final transient = math.exp(-9.0 * t);
    final body = 0.35 +
        0.32 * math.sin(t * math.pi * 10.0).abs() +
        0.20 * math.sin(t * math.pi * 23.0 + 0.7).abs();
    return (0.10 + env * body + transient * 0.42).clamp(0.08, 1.0);
  }

  @override
  bool shouldRepaint(covariant _SamplerWaveformPainter oldDelegate) {
    return accent != oldDelegate.accent ||
        peaks != oldDelegate.peaks ||
        startNorm != oldDelegate.startNorm ||
        endNorm != oldDelegate.endNorm ||
        reverse != oldDelegate.reverse ||
        sliceMode != oldDelegate.sliceMode ||
        sliceCount != oldDelegate.sliceCount;
  }
}

Rect _visiblePianoRollPaintBounds(Canvas canvas, Size size) {
  final fullBounds = Offset.zero & size;
  final localClip = canvas.getLocalClipBounds();
  if (!localClip.left.isFinite ||
      !localClip.top.isFinite ||
      !localClip.right.isFinite ||
      !localClip.bottom.isFinite) {
    return fullBounds;
  }
  final visible = localClip.intersect(fullBounds);
  return visible.isEmpty ? fullBounds : visible;
}

({int start, int end}) _visiblePianoRollBarRange({
  required Rect paintBounds,
  required double leadingBeatPadPx,
  required double pxPerBeat,
  required double barLengthBeats,
  required int maxBars,
}) {
  if (!pxPerBeat.isFinite ||
      pxPerBeat <= 0.0 ||
      !barLengthBeats.isFinite ||
      barLengthBeats <= 0.0 ||
      maxBars <= 0) {
    return (start: 0, end: math.max(0, maxBars));
  }
  final startBeat = math.max(
    0.0,
    (paintBounds.left - leadingBeatPadPx) / pxPerBeat,
  );
  final endBeat = math.max(
    startBeat,
    (paintBounds.right - leadingBeatPadPx) / pxPerBeat,
  );
  final firstVisibleBar = (startBeat / barLengthBeats).floor();
  final lastVisibleBar = (endBeat / barLengthBeats).ceil();
  return (
    start: math.max(0, firstVisibleBar - 1),
    end: math.min(maxBars, lastVisibleBar + 1),
  );
}

class _PianoGridPainter extends CustomPainter {
  _PianoGridPainter({
    required this.rowHeight,
    required this.pxPerBeat,
    required this.leadingBeatPadPx,
    required this.maxPitch,
    required this.minPitch,
    required this.maxBeat,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.quantizeDivisionsPerBar,
    required this.magnetEnabled,
    required this.playablePitches,
  });

  final double rowHeight;
  final double pxPerBeat;
  final double leadingBeatPadPx;
  final int maxPitch;
  final int minPitch;
  final double maxBeat;
  final int beatsPerBar;
  final int beatUnit;
  final int quantizeDivisionsPerBar;
  final bool magnetEnabled;
  final Set<int> playablePitches;

  static bool _isBlackPitch(int pitch) {
    const black = <int>{1, 3, 6, 8, 10};
    return black.contains(pitch % 12);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paintBounds = _visiblePianoRollPaintBounds(canvas, size);
    final rowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.7;
    final whiteRowFill = Paint()
      ..color = const Color(0xFF585F66).withValues(alpha: 0.32);
    final blackRowFill = Paint()
      ..color = const Color(0xFF454C53).withValues(alpha: 0.82);
    final unavailableRowFill = Paint()
      ..color = const Color(0xFF252A2F).withValues(alpha: 0.62);
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
          Rect.fromLTWH(paintBounds.left, y, paintBounds.width, rowHeight),
          blackRowFill,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(paintBounds.left, y, paintBounds.width, rowHeight),
          whiteRowFill,
        );
      }
      if (!playablePitches.contains(pitch)) {
        canvas.drawRect(
          Rect.fromLTWH(paintBounds.left, y, paintBounds.width, rowHeight),
          unavailableRowFill,
        );
      }
      canvas.drawLine(
        Offset(paintBounds.left, y),
        Offset(paintBounds.right, y),
        rowPaint,
      );
    }
    canvas.drawLine(
      Offset(paintBounds.left, pitchCount * rowHeight),
      Offset(paintBounds.right, pitchCount * rowHeight),
      rowPaint,
    );

    final safeBeatsPerBar = math.max(1, beatsPerBar);
    final safeBeatUnit = math.max(1, beatUnit);
    final barLengthBeats = safeBeatsPerBar * 4.0 / safeBeatUnit;
    final beatStep = barLengthBeats / safeBeatsPerBar;
    final safeDivisions = math.max(1, quantizeDivisionsPerBar);
    final divisionBeat = barLengthBeats / safeDivisions;
    final maxBars = (maxBeat / barLengthBeats).ceil() + 1;
    final visibleBars = _visiblePianoRollBarRange(
      paintBounds: paintBounds,
      leadingBeatPadPx: leadingBeatPadPx,
      pxPerBeat: pxPerBeat,
      barLengthBeats: barLengthBeats,
      maxBars: maxBars,
    );

    for (int bar = visibleBars.start; bar <= visibleBars.end; bar++) {
      final barBeat = bar * barLengthBeats;
      final barX = leadingBeatPadPx + (barBeat * pxPerBeat);
      canvas.drawLine(
        Offset(barX, 0),
        Offset(barX, size.height),
        majorPaint,
      );

      for (int d = 1; d < safeDivisions; d++) {
        final beat = barBeat + (d * divisionBeat);
        if (beat > maxBeat) break;
        final x = leadingBeatPadPx + (beat * pxPerBeat);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          minorPaint,
        );
      }

      for (int beat = 1; beat < safeBeatsPerBar; beat++) {
        final beatValue = barBeat + (beat * beatStep);
        if (beatValue > maxBeat) break;
        final x = leadingBeatPadPx + (beatValue * pxPerBeat);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          beatPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PianoGridPainter oldDelegate) {
    return rowHeight != oldDelegate.rowHeight ||
        pxPerBeat != oldDelegate.pxPerBeat ||
        leadingBeatPadPx != oldDelegate.leadingBeatPadPx ||
        maxPitch != oldDelegate.maxPitch ||
        minPitch != oldDelegate.minPitch ||
        maxBeat != oldDelegate.maxBeat ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        beatUnit != oldDelegate.beatUnit ||
        quantizeDivisionsPerBar != oldDelegate.quantizeDivisionsPerBar ||
        magnetEnabled != oldDelegate.magnetEnabled ||
        !setEquals(playablePitches, oldDelegate.playablePitches);
  }
}

class _PianoRollPlayheadLinePainter extends CustomPainter {
  const _PianoRollPlayheadLinePainter({
    required this.x,
  });

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (!x.isFinite || x < -2.0 || x > size.width + 2.0) return;
    final glowPaint = Paint()
      ..color = const Color.fromRGBO(255, 212, 90, 0.22)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square;
    final paint = Paint()
      ..color = const Color(0xFFFFD45A)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _PianoRollPlayheadLinePainter oldDelegate) {
    return x != oldDelegate.x;
  }
}

class _PianoRollRulerPlayheadPainter extends CustomPainter {
  const _PianoRollRulerPlayheadPainter({
    required this.x,
  });

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (!x.isFinite || x < -14.0 || x > size.width + 14.0) return;

    final paint = Paint()..color = const Color(0xFFFFD45A);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    final triangle = Path()
      ..moveTo(x - 7.0, 5.0)
      ..lineTo(x + 7.0, 5.0)
      ..lineTo(x, 16.0)
      ..close();
    canvas.drawPath(triangle.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawPath(triangle, paint);

    final stem = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, 22.5),
        width: 2.0,
        height: 7.0,
      ),
      const Radius.circular(2.0),
    );
    canvas.drawRRect(stem.shift(const Offset(0, 1)), shadowPaint);
    canvas.drawRRect(stem, paint);
  }

  @override
  bool shouldRepaint(covariant _PianoRollRulerPlayheadPainter oldDelegate) {
    return x != oldDelegate.x;
  }
}

class _PianoRollRulerPainter extends CustomPainter {
  _PianoRollRulerPainter({
    required this.pxPerBeat,
    required this.leadingBeatPadPx,
    required this.maxBeat,
    required this.beatsPerBar,
    required this.beatUnit,
  });

  final double pxPerBeat;
  final double leadingBeatPadPx;
  final double maxBeat;
  final int beatsPerBar;
  final int beatUnit;

  @override
  void paint(Canvas canvas, Size size) {
    final paintBounds = _visiblePianoRollPaintBounds(canvas, size);
    final backgroundPaint = Paint()
      ..color = const Color(0xFF3A4047).withValues(alpha: 0.92);
    final dividerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    final majorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.2;
    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 0.9;
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.74),
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFamily: 'Pretendard',
    );

    canvas.drawRect(paintBounds, backgroundPaint);
    canvas.drawLine(
      Offset(paintBounds.left, size.height - 0.5),
      Offset(paintBounds.right, size.height - 0.5),
      dividerPaint,
    );

    final safeBeatsPerBar = math.max(1, beatsPerBar);
    final safeBeatUnit = math.max(1, beatUnit);
    final barLengthBeats = safeBeatsPerBar * 4.0 / safeBeatUnit;
    final beatStep = barLengthBeats / safeBeatsPerBar;
    final maxBars = (maxBeat / barLengthBeats).ceil() + 1;
    final visibleBars = _visiblePianoRollBarRange(
      paintBounds: paintBounds,
      leadingBeatPadPx: leadingBeatPadPx,
      pxPerBeat: pxPerBeat,
      barLengthBeats: barLengthBeats,
      maxBars: maxBars,
    );
    for (int bar = visibleBars.start; bar <= visibleBars.end; bar++) {
      final barBeat = bar * barLengthBeats;
      final barX = leadingBeatPadPx + (barBeat * pxPerBeat);
      canvas.drawLine(
        Offset(barX, 0),
        Offset(barX, size.height),
        majorPaint,
      );

      if (barBeat <= maxBeat) {
        final labelPainter = TextPainter(
          text: TextSpan(text: '${bar + 1}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(canvas, Offset(barX + 4, 4));
      }

      for (int beat = 1; beat < safeBeatsPerBar; beat++) {
        final beatValue = barBeat + (beat * beatStep);
        final beatX = leadingBeatPadPx + (beatValue * pxPerBeat);
        if (beatValue > maxBeat) break;
        canvas.drawLine(
          Offset(beatX, size.height * 0.46),
          Offset(beatX, size.height),
          minorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PianoRollRulerPainter oldDelegate) {
    return pxPerBeat != oldDelegate.pxPerBeat ||
        leadingBeatPadPx != oldDelegate.leadingBeatPadPx ||
        maxBeat != oldDelegate.maxBeat ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        beatUnit != oldDelegate.beatUnit;
  }
}
