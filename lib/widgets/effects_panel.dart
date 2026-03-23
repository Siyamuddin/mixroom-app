import 'dart:async';
import 'package:fftea/fftea.dart';

import 'package:flutter/material.dart';
import 'package:mixroom/helpers/entitlement_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';

import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/helpers/halo.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/entitlement_models.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const int maxNumEffects = 10;

List<String> _buildStableEffectKeys(List<String> effectIds) {
  final counts = <String, int>{};
  final keys = <String>[];
  for (final id in effectIds) {
    final n = (counts[id] ?? 0) + 1;
    counts[id] = n;
    keys.add('$id#$n');
  }
  return keys;
}

String _testKeySlug(String raw) {
  final normalized = raw.trim().toLowerCase();
  final slug = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return slug.replaceAll(RegExp(r'^_+|_+$'), '');
}

bool _isPitchShiftSemitonesParam(
  String effectName,
  Map<String, dynamic> param,
) {
  final name = param['name']?.toString() ?? '';
  final type = param['type']?.toString() ?? '';
  return effectName == 'Pitch Shift' &&
      type == 'float' &&
      name.toLowerCase() == 'semitones';
}

bool _isGainVolumeParam(
  String effectName,
  Map<String, dynamic> param,
) {
  final name = param['name']?.toString() ?? '';
  final type = param['type']?.toString() ?? '';
  return effectName == 'Gain' &&
      type == 'float' &&
      name.toLowerCase() == 'volume';
}

bool _showsDynamicsReductionMeter(String effectName) {
  return effectName == 'Compressor' ||
      effectName == 'Limiter' ||
      effectName == 'Clipper' ||
      effectName == 'Mixroom Clipper';
}

String _dynamicsReductionMeterTitle(String effectName) {
  switch (effectName) {
    case 'Limiter':
      return 'Limiting';
    case 'Clipper':
    case 'Mixroom Clipper':
      return 'Clipping';
    default:
      return 'Gain Reduction';
  }
}

double _gainUiToDb(double sliderValue, {double uiMax = 3.0}) {
  const dbMin = -60.0;
  const dbMax = 6.0;
  const uiUnity = 2.0;

  final clamped = sliderValue.clamp(0.0, uiMax).toDouble();
  final unity = math.min(uiUnity, uiMax);

  if (clamped <= unity) {
    final t = unity <= 0.0 ? 0.0 : (clamped / unity).clamp(0.0, 1.0);
    return dbMin + ((0.0 - dbMin) * t);
  }

  final t = (uiMax <= unity)
      ? 0.0
      : ((clamped - unity) / (uiMax - unity)).clamp(0.0, 1.0);
  return 0.0 + ((dbMax - 0.0) * t);
}

String _formatGainDb(double sliderValue, {double uiMax = 3.0}) {
  final db = _gainUiToDb(sliderValue, uiMax: uiMax);
  return db > 0
      ? "+${db.toStringAsFixed(1)} dB"
      : "${db.toStringAsFixed(1)} dB";
}

class RowEffectsPanel extends StatefulWidget {
  final int rowIndex;
  final String mode;
  final bool? isProEntitled;
  final double minHeight;

  // Callbacks from AudioEditor → JUCE
  final Future<List<String>> Function(int row) getEffectsForRow;
  final Future<List<String>> Function(int row) getEffectIdsForRow;
  final Future<bool> Function(int row, int effectIndex) getBypassStateForRow;
  final Future<void> Function(int row, int effectIndex, bool bypass)
      setBypassForRow;
  final Future<void> Function(int row, int from, int to) reorderEffectsForRow;
  final Future<void> Function(
          int row, int effectIndex, String name, bool applyingPreset)
      removeEffectFromRow;
  final Future<void> Function(int row, String path) insertEffectOnRow;
  final Future<List<Map<String, dynamic>>> Function(int row, int effectIndex)
      getTrackPluginParameters;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final Future<void> Function(
          int row, int effectIndex, String paramId, dynamic value)
      setTrackEffectParam;
  final Future<void> Function(
    int row,
    int effectIndex,
    String effectName,
    String paramId,
    String paramName,
  )? onRequestAutomateParameter;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)?
      onPresetCommit;
  final void Function(int row, int effectIndex, String effectName)?
      onTutorialEffectAdded;
  final void Function(int row, int effectIndex, String effectName)?
      onTutorialEffectOpened;
  final void Function(double height) onHeightChanged;
  final void Function(VoidCallback refresh)? registerRefresh;
  final void Function(VoidCallback refresh)? registerPlaybackRefresh;
  final void Function(
    Future<void> Function(int effectIndex, String paramId) reveal,
  )? registerParameterRevealer;
  final double projectBpm;

  final void Function(int row, int effectIndex, String paramId,
      dynamic oldValue, dynamic newValue)? onPluginParamCommit;

  final MeterBus meters;
  final Future<List<double>> Function(int row, int effectIndex)
      getRowCompressorMeter;
  final Future<List<double>> Function(int row, int effectIndex, int sampleCount)
      getRowEqWaveform;
  final MixChangeHighlighter? tutorialHighlighter;

  const RowEffectsPanel({
    Key? key,
    required this.rowIndex,
    required this.mode,
    this.isProEntitled,
    this.minHeight = 240,
    required this.getEffectsForRow,
    required this.getEffectIdsForRow,
    required this.getBypassStateForRow,
    required this.setBypassForRow,
    required this.reorderEffectsForRow,
    required this.removeEffectFromRow,
    required this.insertEffectOnRow,
    required this.getTrackPluginParameters,
    required this.scanPlugins,
    required this.setTrackEffectParam,
    this.onRequestAutomateParameter,
    required this.onHeightChanged,
    required this.onPluginParamCommit,
    required this.onPresetCommit,
    this.onTutorialEffectAdded,
    this.onTutorialEffectOpened,
    this.registerRefresh,
    this.registerPlaybackRefresh,
    this.registerParameterRevealer,
    required this.projectBpm,
    required this.meters,
    required this.getRowCompressorMeter,
    required this.getRowEqWaveform,
    this.tutorialHighlighter,
  }) : super(key: key);

  @override
  State<RowEffectsPanel> createState() => _RowEffectsPanelState();
}

class _PendingParamOverride {
  final dynamic value;
  final DateTime updatedAt;

  const _PendingParamOverride({
    required this.value,
    required this.updatedAt,
  });
}

class _RowEffectsPanelState extends State<RowEffectsPanel> {
  List<String> _effects = [];
  List<String> _effectKeys = [];
  List<bool> _bypassed = [];
  bool _loading = true;

  int? _selectedEffectIndex;
  List<Map<String, dynamic>> _currentParams = [];
  bool _paramsLoading = false;
  double? _lastReportedHeight; // since height is dynamic

  // for undo state
  double? _paramDragStartValue;
  double? _EQParamStartValue; // have one "before" start value for all EQ faders

  // for Delay Time parameter
  final Map<int, int> _delayDivisionByEffect = {};

  Timer? _compMeterTimer;
  CompressorStripFrame _compFrame = CompressorStripFrame.zero;
  CompressorStripFrame _compFrameSmoothed = CompressorStripFrame.zero;
  bool _compMeterRunning = false;
  Timer? _eqWaveformTimer;
  bool _eqWaveformRunning = false;
  List<double> _eqWaveform = const <double>[];
  List<double> _eqSpectrumDb = const <double>[];
  double _eqAnalyzerSampleRate = 44100.0;
  int _eqParametricTabIndex = 0;
  bool _playbackRefreshBusy = false;
  DateTime _lastPlaybackRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kPlaybackRefreshMinInterval =
      Duration(milliseconds: 90);
  static const Duration _kParamRefreshHold = Duration(milliseconds: 900);
  static const Duration _kPendingParamOverrideTtl = Duration(seconds: 2);
  DateTime _holdParamRefreshUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _deferredParamRefreshTimer;
  bool _deferredParamRefreshPlaybackOnly = true;
  final Map<String, _PendingParamOverride> _pendingParamOverrides =
      <String, _PendingParamOverride>{};

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

  bool get _isKnownSubscriptionMode =>
      widget.isProEntitled != null ||
      widget.mode == 'Basic' ||
      widget.mode == 'Pro';

  String _haloSlug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _normalizedParamToken(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  List<String> _effectHaloKeys({
    required int effectIndex,
    required String effectName,
  }) {
    final row = widget.rowIndex;
    final lower = effectName.trim().toLowerCase();
    final slug = _haloSlug(effectName);
    final tokens = slug
        .split('_')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final out = <String>[
      'row:$row:fx_index:$effectIndex',
      if (lower.isNotEmpty) 'row:$row:fx_contains:$lower',
      if (slug.isNotEmpty) 'row:$row:fx_contains:$slug',
    ];
    for (final token in tokens) {
      out.add('row:$row:fx_contains:$token');
    }
    return out;
  }

  List<String> _paramHaloKeys({
    required int effectIndex,
    required String effectName,
    required String paramName,
  }) {
    final row = widget.rowIndex;
    final paramSlug = _haloSlug(paramName);
    final paramLower = paramName.trim().toLowerCase();
    return <String>[
      if (paramName.trim().isNotEmpty)
        'row:$row:fx_index:$effectIndex:param:${paramName.trim()}',
      if (paramSlug.isNotEmpty)
        'row:$row:fx_index:$effectIndex:param:$paramSlug',
      if (paramLower.isNotEmpty)
        'row:$row:fx_index:$effectIndex:param:$paramLower',
    ];
  }

  Widget _wrapWithHalos({
    required Widget child,
    required List<String> haloKeys,
    BorderRadius? borderRadius,
    Key? key,
  }) {
    final highlighter = widget.tutorialHighlighter;
    if (highlighter == null || haloKeys.isEmpty) return child;
    final mapped = haloKeys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .map((k) => HaloKey(k))
        .toList(growable: false);
    if (mapped.isEmpty) return child;
    return MultiHalo(
      key: key,
      highlighter: highlighter,
      haloKeys: mapped,
      borderRadius: borderRadius,
      child: child,
    );
  }

  void _triggerHalos(
    List<String> haloKeys, {
    Duration duration = const Duration(milliseconds: 800),
  }) {
    final highlighter = widget.tutorialHighlighter;
    if (highlighter == null || haloKeys.isEmpty) return;
    final mapped = haloKeys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .map(HaloKey.new)
        .toList(growable: false);
    if (mapped.isEmpty) return;
    highlighter.trigger(mapped, duration: duration);
  }

  Future<void> _showAutomateParameterSheet({
    required int effectIndex,
    required String effectName,
    required String paramId,
    required String paramName,
    required List<String> haloKeys,
    Offset? anchorGlobalPos,
  }) async {
    if (widget.onRequestAutomateParameter == null) return;
    _triggerHalos(
      haloKeys,
      duration: const Duration(milliseconds: 320),
    );
    await AppHaptics.impact(AppHapticImpact.medium);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final fallbackAnchor = (() {
      final box = context.findRenderObject();
      if (box is RenderBox) {
        return box.localToGlobal(
          Offset(box.size.width / 2, box.size.height / 2),
        );
      }
      return const Offset(120, 120);
    })();
    final anchor = anchorGlobalPos ?? fallbackAnchor;
    String? action;
    if (overlay != null) {
      final left = anchor.dx.clamp(0.0, overlay.size.width).toDouble();
      final top = (anchor.dy - 40.0).clamp(0.0, overlay.size.height).toDouble();
      final right = (overlay.size.width - anchor.dx)
          .clamp(0.0, overlay.size.width)
          .toDouble();
      final bottom = (overlay.size.height - anchor.dy)
          .clamp(0.0, overlay.size.height)
          .toDouble();
      action = await showMenu<String>(
        context: context,
        color: const Color(0xFF1B2233),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        position: RelativeRect.fromLTRB(left, top, right, bottom),
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'automate',
            height: 34,
            child: Text('Automate'),
          ),
        ],
      );
    }
    if (action != 'automate') return;
    _triggerHalos(haloKeys);
    await widget.onRequestAutomateParameter!(
      widget.rowIndex,
      effectIndex,
      effectName,
      paramId,
      paramName,
    );
  }

  Future<void> _revealParameter(int effectIndex, String paramId) async {
    if (effectIndex < 0) return;
    if (effectIndex >= _effects.length) {
      await _loadEffects();
      if (effectIndex < 0 || effectIndex >= _effects.length) return;
    }
    await _openPluginParams(effectIndex);
    if (!mounted) return;
    final effectName = _effects[effectIndex];
    final params = _currentParams;
    final targetRaw = paramId.trim();
    final target = targetRaw.toLowerCase();
    final targetToken = _normalizedParamToken(targetRaw);
    final match = params.cast<Map<String, dynamic>?>().firstWhere(
      (param) {
        if (param == null) return false;
        final candidateId =
            (param['id'] ?? param['name'] ?? '').toString().trim();
        final candidateName = (param['name'] ?? candidateId).toString().trim();
        if (target.isEmpty) return false;
        final idLower = candidateId.toLowerCase();
        final nameLower = candidateName.toLowerCase();
        if (idLower == target || nameLower == target) return true;
        if (targetToken.isEmpty) return false;
        return _normalizedParamToken(candidateId) == targetToken ||
            _normalizedParamToken(candidateName) == targetToken;
      },
      orElse: () => null,
    );
    final matchedParamName =
        (match?['name'] ?? match?['id'] ?? targetRaw).toString().trim();
    final matchedParamId =
        (match?['id'] ?? match?['name'] ?? targetRaw).toString().trim();
    final haloKeys = <String>[];
    final seen = <String>{};
    void addHaloKeys(List<String> keys) {
      for (final key in keys) {
        final trimmed = key.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) continue;
        haloKeys.add(trimmed);
      }
    }

    addHaloKeys(
      _paramHaloKeys(
        effectIndex: effectIndex,
        effectName: effectName,
        paramName: matchedParamName,
      ),
    );
    if (matchedParamId.isNotEmpty &&
        matchedParamId.toLowerCase() != matchedParamName.toLowerCase()) {
      addHaloKeys(
        _paramHaloKeys(
          effectIndex: effectIndex,
          effectName: effectName,
          paramName: matchedParamId,
        ),
      );
    }
    if (targetRaw.isNotEmpty &&
        targetRaw.toLowerCase() != matchedParamName.toLowerCase() &&
        targetRaw.toLowerCase() != matchedParamId.toLowerCase()) {
      addHaloKeys(
        _paramHaloKeys(
          effectIndex: effectIndex,
          effectName: effectName,
          paramName: targetRaw,
        ),
      );
    }
    final matchedSlug = _haloSlug(matchedParamName);
    final targetSlug = _haloSlug(targetRaw);
    if (matchedParamName.isNotEmpty) {
      addHaloKeys(<String>['row:${widget.rowIndex}:param:$matchedParamName']);
    }
    if (matchedSlug.isNotEmpty) {
      addHaloKeys(<String>['row:${widget.rowIndex}:param:$matchedSlug']);
    }
    if (targetRaw.isNotEmpty) {
      addHaloKeys(<String>['row:${widget.rowIndex}:param:$targetRaw']);
    }
    if (targetSlug.isNotEmpty) {
      addHaloKeys(<String>['row:${widget.rowIndex}:param:$targetSlug']);
    }
    if (haloKeys.isEmpty) return;
    // Trigger after paint so the target param halo node is definitely mounted.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _triggerHalos(haloKeys);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _triggerHalos(haloKeys);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    _triggerHalos(haloKeys);
  }

  Widget _wrapAutomatableParam({
    required int effectIndex,
    required String effectName,
    required Map<String, dynamic> param,
    required Widget child,
    BorderRadius? borderRadius,
  }) {
    final paramName =
        (param['name'] ?? param['id'] ?? 'Parameter').toString().trim();
    final paramId = (param['id'] ?? param['name'] ?? '').toString().trim();
    final haloKeys = _paramHaloKeys(
      effectIndex: effectIndex,
      effectName: effectName,
      paramName: paramName,
    );
    return KeyedSubtree(
      key: ValueKey(
        'row_param_${widget.rowIndex}_${_testKeySlug(effectName)}_${_testKeySlug(paramName)}',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) => _showAutomateParameterSheet(
          effectIndex: effectIndex,
          effectName: effectName,
          paramId: paramId,
          paramName: paramName,
          haloKeys: haloKeys,
          anchorGlobalPos: details.globalPosition,
        ),
        child: _wrapWithHalos(
          haloKeys: haloKeys,
          borderRadius: borderRadius,
          child: child,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadEffects();
    // widget.registerRefresh?.call = _refetchAll;
    widget.registerRefresh?.call(_refetchAll);
    widget.registerPlaybackRefresh?.call(_refetchParamsForPlayback);
    widget.registerParameterRevealer?.call(_revealParameter);
  }

  @override
  void didUpdateWidget(covariant RowEffectsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rowIndex != widget.rowIndex) {
      _pendingParamOverrides.clear();
      _refetchAll();
    }
  }

  @override
  void dispose() {
    _deferredParamRefreshTimer?.cancel();
    _pendingParamOverrides.clear();
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    super.dispose();
  }

  String _pendingParamOverrideKey(int effectIndex, String paramId) {
    final trimmedParamId = paramId.trim();
    final effectKey = (effectIndex >= 0 && effectIndex < _effectKeys.length)
        ? _effectKeys[effectIndex]
        : 'idx:$effectIndex';
    return '$effectKey\u0000$trimmedParamId';
  }

  void _rememberPendingParamOverride(
    int effectIndex,
    String paramId,
    dynamic value,
  ) {
    final trimmedParamId = paramId.trim();
    if (trimmedParamId.isEmpty) return;
    _pendingParamOverrides[
            _pendingParamOverrideKey(effectIndex, trimmedParamId)] =
        _PendingParamOverride(
      value: value,
      updatedAt: DateTime.now(),
    );
  }

  List<Map<String, dynamic>> _mergePendingParamOverrides(
    int effectIndex,
    List<Map<String, dynamic>> params,
  ) {
    if (_pendingParamOverrides.isEmpty || params.isEmpty) {
      return params;
    }

    final now = DateTime.now();
    final merged = <Map<String, dynamic>>[];
    final keysToRemove = <String>{};

    for (final original in params) {
      final param = Map<String, dynamic>.from(original);
      final rawName = (param['name'] ?? '').toString().trim();
      final rawId = (param['id'] ?? '').toString().trim();
      _PendingParamOverride? override;
      String? overrideKey;

      for (final candidate in <String>[
        if (rawId.isNotEmpty) rawId,
        if (rawName.isNotEmpty) rawName,
      ]) {
        final key = _pendingParamOverrideKey(effectIndex, candidate);
        final pending = _pendingParamOverrides[key];
        if (pending == null) continue;
        override = pending;
        overrideKey = key;
        break;
      }

      if (override != null && overrideKey != null) {
        if (now.difference(override.updatedAt) > _kPendingParamOverrideTtl ||
            _paramValuesEqual(param['value'], override.value)) {
          keysToRemove.add(overrideKey);
        } else {
          param['value'] = override.value;
        }
      }

      merged.add(param);
    }

    if (keysToRemove.isNotEmpty) {
      for (final key in keysToRemove) {
        _pendingParamOverrides.remove(key);
      }
    }

    return merged;
  }

  bool _isParamRefreshHeld() {
    return DateTime.now().isBefore(_holdParamRefreshUntil);
  }

  void _extendParamRefreshHold([
    Duration duration = _kParamRefreshHold,
  ]) {
    final until = DateTime.now().add(duration);
    if (until.isAfter(_holdParamRefreshUntil)) {
      _holdParamRefreshUntil = until;
    }
  }

  void _scheduleDeferredParamRefresh({required bool playbackOnly}) {
    _deferredParamRefreshPlaybackOnly = _deferredParamRefreshTimer == null
        ? playbackOnly
        : (_deferredParamRefreshPlaybackOnly && playbackOnly);
    _deferredParamRefreshTimer?.cancel();
    final delay = _holdParamRefreshUntil.difference(DateTime.now());
    _deferredParamRefreshTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _deferredParamRefreshTimer = null;
        final playbackRefresh = _deferredParamRefreshPlaybackOnly;
        _deferredParamRefreshPlaybackOnly = true;
        if (!mounted) return;
        if (playbackRefresh) {
          unawaited(_refetchParamsForPlayback());
          return;
        }
        unawaited(_refetchAll());
      },
    );
  }

  Future<void> _setTrackEffectParam(
    int row,
    int effectIndex,
    String paramId,
    dynamic value,
  ) async {
    _rememberPendingParamOverride(effectIndex, paramId, value);
    _extendParamRefreshHold();
    await widget.setTrackEffectParam(row, effectIndex, paramId, value);
  }

  void _commitTrackEffectParam(
    int row,
    int effectIndex,
    String paramId,
    dynamic oldValue,
    dynamic newValue,
  ) {
    _extendParamRefreshHold();
    widget.onPluginParamCommit?.call(
      row,
      effectIndex,
      paramId,
      oldValue,
      newValue,
    );
    _scheduleDeferredParamRefresh(playbackOnly: false);
  }

  Future<void> _loadEffects(
      {bool forceCloseParams = false, bool showLoading = true}) async {
    final hadSelection = _selectedEffectIndex != null;
    if (forceCloseParams) {
      setState(() {
        _loading = showLoading;
        _selectedEffectIndex = null;
        _currentParams = [];
      });
      _stopEqWaveformPolling();
    } else if (!hadSelection) {
      if (showLoading) {
        setState(() {
          _loading = true;
        });
      }
      _stopEqWaveformPolling();
    }
    final names = await widget.getEffectsForRow(widget.rowIndex);
    var ids = await widget.getEffectIdsForRow(widget.rowIndex);
    if (ids.length != names.length) {
      ids = List<String>.from(names);
    }
    final keys = _buildStableEffectKeys(ids);
    final bypassStates = <bool>[];

    for (int i = 0; i < names.length; i++) {
      final b = await widget.getBypassStateForRow(widget.rowIndex, i);
      bypassStates.add(b);
    }

    if (!mounted) return;
    setState(() {
      _effects = List<String>.from(names);
      _effectKeys = List<String>.from(keys);
      _bypassed = List<bool>.from(bypassStates);
      _loading = false;
      if (_selectedEffectIndex != null &&
          _selectedEffectIndex! >= _effects.length) {
        _selectedEffectIndex = null;
        _currentParams = [];
        _stopEqWaveformPolling();
      }
    });
  }

  void _moveDelayDivisionState(int from, int to) {
    if (from == to) return;

    final moved = _delayDivisionByEffect.remove(from);
    final next = <int, int>{};

    _delayDivisionByEffect.forEach((key, value) {
      var newKey = key;
      if (from < to) {
        if (key > from && key <= to) newKey = key - 1;
      } else {
        if (key >= to && key < from) newKey = key + 1;
      }
      next[newKey] = value;
    });

    if (moved != null) next[to] = moved;

    _delayDivisionByEffect
      ..clear()
      ..addAll(next);
  }

  void _applyLocalReorder(int oldIndex, int newIndex) {
    final movedName = _effects.removeAt(oldIndex);
    final movedKey = _effectKeys.removeAt(oldIndex);
    final movedBypass = _bypassed.removeAt(oldIndex);
    _effects.insert(newIndex, movedName);
    _effectKeys.insert(newIndex, movedKey);
    _bypassed.insert(newIndex, movedBypass);

    final selected = _selectedEffectIndex;
    if (selected != null) {
      if (selected == oldIndex) {
        _selectedEffectIndex = newIndex;
      } else if (oldIndex < newIndex &&
          selected > oldIndex &&
          selected <= newIndex) {
        _selectedEffectIndex = selected - 1;
      } else if (newIndex < oldIndex &&
          selected >= newIndex &&
          selected < oldIndex) {
        _selectedEffectIndex = selected + 1;
      }
    }

    _moveDelayDivisionState(oldIndex, newIndex);
  }

  Future<int> _resolveLiveEffectIndex(int uiIndex) async {
    if (uiIndex < 0 || uiIndex >= _effects.length) return -1;

    final liveNames = await widget.getEffectsForRow(widget.rowIndex);
    if (uiIndex >= 0 && uiIndex < liveNames.length) return uiIndex;

    await _loadEffects(showLoading: false);
    if (uiIndex < 0 || uiIndex >= _effects.length) return -1;
    return uiIndex;
  }

  int _delayDivisionIndex(int effectIndex) {
    return _delayDivisionByEffect[effectIndex] ?? 2; // default = 1/4
  }

  int? _detectDelayDivision(double ms, double bpm) {
    const toleranceMs = 1.5;

    for (int i = 0; i < kDelayDivisions.length; i++) {
      final targetMs = beatsToMs(kDelayDivisions[i].beats, bpm);
      if ((ms - targetMs).abs() <= toleranceMs) {
        return i;
      }
    }
    return null; // Custom
  }

  Widget _buildDelayTimeParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
    required double bpm,
  }) {
    final msValue = (param['value'] as num).toDouble();
    final detectedIdx = _detectDelayDivision(msValue, bpm);
    final presetLabel =
        detectedIdx == null ? 'Custom' : kDelayDivisions[detectedIdx].label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header row ----
          Row(
            children: [
              Text(param['name'] as String,
                  style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),

              // ---- PRESET DROPDOWN ----
              DropdownButton<String>(
                value: presetLabel,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(
                    value: 'Custom',
                    child: Text(L10n.translate(context, 'Custom')),
                  ),
                  ...kDelayDivisions.map((d) =>
                      DropdownMenuItem(value: d.label, child: Text(d.label))),
                ],
                onChanged: (label) {
                  if (label == null || label == 'Custom') return;

                  final division =
                      kDelayDivisions.firstWhere((d) => d.label == label);
                  final newMs = beatsToMs(division.beats, bpm);

                  _paramDragStartValue = msValue;

                  setState(() {
                    param['value'] = newMs;
                  });

                  _setTrackEffectParam(widget.rowIndex, effectIndex,
                      param['name'] as String, newMs);

                  _commitTrackEffectParam(
                    widget.rowIndex,
                    effectIndex,
                    param['name'] as String,
                    _paramDragStartValue!,
                    newMs,
                  );

                  _paramDragStartValue = null;
                },
              ),
            ],
          ),

          // ---- MS SLIDER (ALWAYS SHOWN) ----
          Row(
            children: [
              Text((param['min'] as num).toDouble().toStringAsFixed(0),
                  style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final defaultValue = _paramDefaultAsDouble(param);
                    if (defaultValue == null) return;
                    final oldValue = (param['value'] as num).toDouble();
                    if ((oldValue - defaultValue).abs() < 1.0e-6) return;
                    setState(() => param['value'] = defaultValue);
                    _setTrackEffectParam(widget.rowIndex, effectIndex,
                        param['name'] as String, defaultValue);
                    _commitTrackEffectParam(
                      widget.rowIndex,
                      effectIndex,
                      param['name'] as String,
                      oldValue,
                      defaultValue,
                    );
                  },
                  child: Slider(
                    value: msValue.clamp((param['min'] as num).toDouble(),
                        (param['max'] as num).toDouble()),
                    min: (param['min'] as num).toDouble(),
                    max: (param['max'] as num).toDouble(),
                    divisions: 200,
                    label: '${msValue.toStringAsFixed(0)} ms',
                    onChangeStart: (_) {
                      _paramDragStartValue = msValue;
                    },
                    onChanged: (v) {
                      setState(() => param['value'] = v);
                      _setTrackEffectParam(widget.rowIndex, effectIndex,
                          param['name'] as String, v);
                    },
                    onChangeEnd: (v) {
                      if (_paramDragStartValue == null) return;

                      _commitTrackEffectParam(
                        widget.rowIndex,
                        effectIndex,
                        param['name'] as String,
                        _paramDragStartValue!,
                        v,
                      );
                      _paramDragStartValue = null;
                    },
                  ),
                ),
              ),
              Text((param['max'] as num).toDouble().toStringAsFixed(0),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitchShiftSemitonesParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
  }) {
    final paramName = param['name'] as String;
    final minV = ((param['min'] as num?)?.toDouble() ?? -12.0);
    final maxV = ((param['max'] as num?)?.toDouble() ?? 12.0);
    final rawV =
        ((param['value'] as num?)?.toDouble() ?? 0.0).clamp(minV, maxV);
    final defaultValue = _paramDefaultAsDouble(param);
    final divisions = math.max(1, (maxV - minV).round());

    void commitImmediate(double nextValue) {
      final oldValue = (param['value'] as num).toDouble();
      final clamped = nextValue.clamp(minV, maxV).toDouble();
      if ((oldValue - clamped).abs() < 1.0e-6) return;

      setState(() => param['value'] = clamped);
      _setTrackEffectParam(widget.rowIndex, effectIndex, paramName, clamped);
      _commitTrackEffectParam(
        widget.rowIndex,
        effectIndex,
        paramName,
        oldValue,
        clamped,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(paramName, style: Theme.of(context).textTheme.bodyLarge),
          Row(
            children: [
              Text(
                minV.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    if (defaultValue == null) return;
                    commitImmediate(defaultValue);
                  },
                  child: Slider(
                    value: rawV,
                    min: minV,
                    max: maxV,
                    divisions: divisions,
                    label: '${rawV.toStringAsFixed(0)} st',
                    onChangeStart: (_) {
                      _paramDragStartValue = rawV;
                    },
                    onChanged: (v) {
                      final snapped = v.roundToDouble().clamp(minV, maxV);
                      setState(() => param['value'] = snapped);
                      _setTrackEffectParam(
                          widget.rowIndex, effectIndex, paramName, snapped);
                    },
                    onChangeEnd: (v) {
                      if (_paramDragStartValue == null) return;
                      final snapped = v.roundToDouble().clamp(minV, maxV);
                      _commitTrackEffectParam(
                        widget.rowIndex,
                        effectIndex,
                        paramName,
                        _paramDragStartValue!,
                        snapped,
                      );
                      _paramDragStartValue = null;
                    },
                  ),
                ),
              ),
              Text(
                maxV.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = rawV.roundToDouble() - 1.0;
                  commitImmediate(next);
                },
                icon: const Icon(Icons.remove, size: 18),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                    'pitch_row_${widget.rowIndex}_${effectIndex}_${rawV.toStringAsFixed(2)}',
                  ),
                  initialValue: rawV.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    suffixText: 'st',
                  ),
                  onFieldSubmitted: (text) {
                    final parsed = double.tryParse(text.trim());
                    if (parsed == null) return;
                    commitImmediate(parsed);
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = rawV.roundToDouble() + 1.0;
                  commitImmediate(next);
                },
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGainVolumeParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
  }) {
    final paramName = param['name'] as String;
    final minV = ((param['min'] as num?)?.toDouble() ?? 0.0);
    final maxV = ((param['max'] as num?)?.toDouble() ?? 3.0);
    final rawV =
        ((param['value'] as num?)?.toDouble() ?? 2.0).clamp(minV, maxV);
    final defaultValue = _paramDefaultAsDouble(param);
    final unity = 2.0.clamp(minV, maxV).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(paramName, style: Theme.of(context).textTheme.bodyLarge),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final target =
                        (defaultValue ?? unity).clamp(minV, maxV).toDouble();
                    final oldValue = (param['value'] as num).toDouble();
                    if ((oldValue - target).abs() < 1.0e-6) return;
                    setState(() => param['value'] = target);
                    _setTrackEffectParam(
                        widget.rowIndex, effectIndex, paramName, target);
                    _commitTrackEffectParam(
                      widget.rowIndex,
                      effectIndex,
                      paramName,
                      oldValue,
                      target,
                    );
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 11),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: rawV,
                      min: minV,
                      max: maxV,
                      onChangeStart: (_) {
                        _paramDragStartValue = rawV;
                      },
                      onChanged: (v) {
                        setState(() => param['value'] = v);
                        _setTrackEffectParam(
                            widget.rowIndex, effectIndex, paramName, v);
                      },
                      onChangeEnd: (v) {
                        if (_paramDragStartValue == null) return;
                        _commitTrackEffectParam(
                          widget.rowIndex,
                          effectIndex,
                          paramName,
                          _paramDragStartValue!,
                          v,
                        );
                        _paramDragStartValue = null;
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  _formatGainDb(rawV, uiMax: maxV),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startCompressorMetering({required int effectIndex}) {
    _stopCompressorMetering();
    _compMeterRunning = true;

    // ~30fps is plenty; 60fps if you want (16ms)
    _compMeterTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!mounted || !_compMeterRunning) return;

      try {
        final arr =
            await widget.getRowCompressorMeter(widget.rowIndex, effectIndex);
        if (!mounted || !_compMeterRunning) return;
        // arr = [inL, inR, grDb, outL, outR]
        final next = CompressorStripFrame(
          inL: (arr.isNotEmpty ? arr[0] : 0).toDouble(),
          inR: (arr.length > 1 ? arr[1] : 0).toDouble(),
          grDb: (arr.length > 2 ? arr[2] : 0).toDouble(),
          outL: (arr.length > 3 ? arr[3] : 0).toDouble(),
          outR: (arr.length > 4 ? arr[4] : 0).toDouble(),
        ).clamp();

        // smoothing (simple EMA-ish via lerp)
        // increase t for snappier response (0.35), decrease for smoother (0.18)
        const t = 0.25;
        setState(() {
          _compFrame = next;
          _compFrameSmoothed =
              CompressorStripFrame.lerp(_compFrameSmoothed, next, t);
        });
      } catch (_) {
        // ignore polling errors (plugin might not be ready)
      }
    });
  }

  void _stopCompressorMetering() {
    _compMeterRunning = false;
    _compMeterTimer?.cancel();
    _compMeterTimer = null;
    _compFrame = CompressorStripFrame.zero;
    _compFrameSmoothed = CompressorStripFrame.zero;
  }

  void _startEqWaveformPolling({required int effectIndex}) {
    _stopEqWaveformPolling();
    _eqWaveformRunning = true;
    _refreshEqAnalyzerSampleRate();

    _eqWaveformTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!mounted || !_eqWaveformRunning) return;

      try {
        final arr =
            await widget.getRowEqWaveform(widget.rowIndex, effectIndex, 1024);
        if (!mounted || !_eqWaveformRunning) return;
        final spectrum = _EqSpectrumAnalyzer.computeSpectrumDb(arr);
        setState(() {
          _eqWaveform = arr;
          _eqSpectrumDb = spectrum;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      }
    });
  }

  void _stopEqWaveformPolling() {
    _eqWaveformRunning = false;
    _eqWaveformTimer?.cancel();
    _eqWaveformTimer = null;
    _eqWaveform = const <double>[];
    _eqSpectrumDb = const <double>[];
  }

  Future<void> _refreshEqAnalyzerSampleRate() async {
    try {
      final sr = await JuceAudioEngine.getHostSampleRate();
      if (!mounted || !_eqWaveformRunning) return;
      if ((sr - _eqAnalyzerSampleRate).abs() > 1.0) {
        setState(() {
          _eqAnalyzerSampleRate = sr;
        });
      }
    } catch (_) {
      // keep default if host SR is unavailable on this platform
    }
  }

  bool _sameDisplayedParams(
    List<Map<String, dynamic>> next,
  ) {
    final current = _currentParams;
    if (current.length != next.length) return false;
    for (int i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if ((a['name']?.toString() ?? '') != (b['name']?.toString() ?? '')) {
        return false;
      }
      if (!_paramValuesEqual(a['value'], b['value'])) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _filterParamsForEffect(
    String effectName,
    List<Map<String, dynamic>> params,
  ) {
    if (!_isKnownSubscriptionMode) {
      return params;
    }
    switch (effectName) {
      case 'Reverb':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Room Size', 'Mix', 'Predelay'].contains(n);
        }).toList();

      case 'Compressor':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Threshold', 'Attack', 'Release', 'Ratio', 'Makeup', 'Mix']
              .contains(n);
        }).toList();

      case 'Limiter':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Threshold', 'Release', 'Ceiling'].contains(n);
        }).toList();

      case 'Clipper':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Threshold', 'Ceiling'].contains(n);
        }).toList();

      case 'EQ Parametric':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return [
            'HPF Frequency',
            'HPF Slope',
            'Band 1 Frequency',
            'Band 1 Gain',
            'Band 1 Q',
            'Band 2 Frequency',
            'Band 2 Gain',
            'Band 2 Q',
            'Band 3 Frequency',
            'Band 3 Gain',
            'Band 3 Q',
            'Band 4 Frequency',
            'Band 4 Gain',
            'Band 4 Q',
            'LPF Slope',
            'LPF Frequency',
          ].contains(n);
        }).toList();

      case 'EQ 3-Band':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Low Gain', 'Mid Gain', 'High Gain'].contains(n);
        }).toList();

      case 'Delay':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Delay Time', 'Feedback', 'Mix'].contains(n);
        }).toList();

      case 'Gain':
        return params.where((p) {
          final n = p['name']?.toString() ?? '';
          return ['Volume'].contains(n);
        }).toList();
    }
    return params;
  }

  Future<void> _refetchParamsForPlayback() async {
    if (!mounted || _selectedEffectIndex == null || _paramsLoading) return;
    if (_paramDragStartValue != null || _EQParamStartValue != null) return;
    if (_playbackRefreshBusy) return;
    if (_isParamRefreshHeld()) {
      _scheduleDeferredParamRefresh(playbackOnly: true);
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastPlaybackRefreshAt) < _kPlaybackRefreshMinInterval) {
      return;
    }
    _lastPlaybackRefreshAt = now;
    _playbackRefreshBusy = true;

    try {
      final uiIdx = _selectedEffectIndex!;
      final liveIdx = await _resolveLiveEffectIndex(uiIdx);
      if (liveIdx < 0) return;

      final effectName = (liveIdx >= 0 && liveIdx < _effects.length)
          ? _effects[liveIdx]
          : (uiIdx >= 0 && uiIdx < _effects.length ? _effects[uiIdx] : '');

      var params =
          await widget.getTrackPluginParameters(widget.rowIndex, liveIdx);
      params = _filterParamsForEffect(effectName, params);
      params = _mergePendingParamOverrides(liveIdx, params);

      if (!mounted || _selectedEffectIndex == null) return;
      final hasChanges =
          !_sameDisplayedParams(params) || _selectedEffectIndex != liveIdx;
      if (!hasChanges) return;
      setState(() {
        _currentParams = params;
        _selectedEffectIndex = liveIdx;
      });
    } catch (_) {
      // swallow playback refresh errors and recover next tick
    } finally {
      _playbackRefreshBusy = false;
    }
  }

  // used from above when the UI needs to be updated after JUCE state changed from above (undo actions, AI mixer)
  Future<void> _refetchAll() async {
    if (!mounted) return;
    if (_isParamRefreshHeld()) {
      _scheduleDeferredParamRefresh(playbackOnly: false);
      return;
    }

    // Case 1: effect list page
    if (_selectedEffectIndex == null) {
      // Keep list page stable during external refreshes (undo/AI/etc).
      await _loadEffects(showLoading: false);
      return;
    }

    // Case 2: parameter page
    final idx = _selectedEffectIndex!;
    final liveIdx = await _resolveLiveEffectIndex(idx);
    if (liveIdx < 0) {
      await _loadEffects(showLoading: false);
      return;
    }

    var params =
        await widget.getTrackPluginParameters(widget.rowIndex, liveIdx);

    final effectName = (liveIdx >= 0 && liveIdx < _effects.length)
        ? _effects[liveIdx]
        : (idx >= 0 && idx < _effects.length ? _effects[idx] : '');

    params = _filterParamsForEffect(effectName, params);
    params = _mergePendingParamOverrides(liveIdx, params);

    if (!mounted) return;
    if (_selectedEffectIndex == null) return;

    setState(() {
      _currentParams = params;
      // Keep parameter page invariant during external refreshes.
      // If index shifted due live reorder, stay on the same effect slot.
      _selectedEffectIndex = liveIdx;
    });
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 160,
        child: Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor)),
      );
    }

    // If an effect is selected → show parameter page (no inner scroll)
    if (_selectedEffectIndex != null) {
      return _buildEffectParamsPage(context, _selectedEffectIndex!);
    }

    // Otherwise: presets + FX list + Add FX
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Presets Section ---
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetChip("Concert Hall"),
                  const SizedBox(width: 6),
                  _buildPresetChip("Echoes"),
                  const SizedBox(width: 6),
                  _buildPresetChip("LoFi Effect"),
                  // const SizedBox(width: 6),
                  // _buildPresetChip("Heavy Crunch"), // TODO: TEMP
                ],
              ),
            ),
          ),

          const SizedBox(height: 2),

          // --- Effects List ---
          if (_effects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 0.0, right: 0.0),
              child: _wrapWithHalos(
                haloKeys: <String>[
                  'row:${widget.rowIndex}:fx_list',
                  'row:${widget.rowIndex}:effects_panel',
                ],
                borderRadius: BorderRadius.circular(10),
                child: ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (int i = 0; i < _effects.length; i++)
                      _buildEffectTile(i)
                  ],
                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < 0 || oldIndex >= _effects.length) return;
                    if (newIndex > oldIndex) newIndex--;
                    newIndex = newIndex.clamp(0, _effects.length - 1);
                    if (oldIndex == newIndex) return;

                    setState(() {
                      _applyLocalReorder(oldIndex, newIndex);
                    });

                    try {
                      await widget.reorderEffectsForRow(
                          widget.rowIndex, oldIndex, newIndex);
                    } catch (_) {
                      await _loadEffects(showLoading: false);
                    }
                  },
                ),
              ),
            ),

          // --- Add FX Button ---
          if (_effects.length < maxNumEffects)
            Padding(
                padding: const EdgeInsets.only(top: 0.0, left: 0.0),
                child: _buildAddTile()),
        ],
      ),
    );
  }

  // =========================
  // UI BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;

      if (box != null) {
        final h = box.size.height;

        // Only notify if height changed by a meaningful amount
        if (_lastReportedHeight == null ||
            (h - _lastReportedHeight!).abs() > 0.5) {
          _lastReportedHeight = h;
          widget.onHeightChanged(h);
        }
      }
    });

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: _buildContent(context),
    );
  }

  // =========================
  // PRESETS
  // =========================

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = <String>[]; // you can re-lock LoFi / Heavy later
    final isLocked = _isBasicTier && lockedPresets.contains(name);

    return ActionChip(
      materialTapTargetSize:
          MaterialTapTargetSize.shrinkWrap, // ← smaller hitbox
      padding: const EdgeInsets.symmetric(
          horizontal: 4, vertical: 4), // ← shrink chip
      visualDensity:
          const VisualDensity(horizontal: -2, vertical: -2), // ← reduce height
      backgroundColor: isLocked
          ? const Color.fromARGB(255, 61, 61, 61)
          : const Color.fromARGB(255, 88, 107, 200),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.translate(context, name),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
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
      onPressed: isLocked ? null : () => _handlePresetLoading(context, name),
    );
  }

  Future<void> _handlePresetLoading(
      BuildContext context, String presetName) async {
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
            child: Text(
              L10n.translate(context, 'Cancel'),
              style: const TextStyle(color: Color.fromARGB(255, 218, 218, 218)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Load Preset')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // BUILD 'BEFORE' SNAPSHOT
    final beforeSnapshots = <EffectSnapshot>[];
    for (int i = 0; i < _effects.length; i++) {
      final params = await widget.getTrackPluginParameters(widget.rowIndex, i);
      final isBypassed = await widget.getBypassStateForRow(widget.rowIndex, i);
      beforeSnapshots.add(EffectSnapshot(_effects[i], isBypassed,
          {for (final p in params) p['name']: p['value']}));
    }
    final before = RowEffectsSnapshot(widget.rowIndex, beforeSnapshots);

    // Remove all current effects on this row
    while (_effects.isNotEmpty) {
      await widget.removeEffectFromRow(widget.rowIndex, 0, _effects[0], true);
      setState(() {
        _effects.removeAt(0);
        _bypassed.removeAt(0);
      });
    }

    // Apply preset chain using callbacks
    switch (presetName) {
      case 'Concert Hall':
        await widget.insertEffectOnRow(widget.rowIndex, 'Reverb');
        await _setTrackEffectParam(widget.rowIndex, 0, 'Room Size', 53);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Mix', 20);
        break;

      case 'Echoes':
        await widget.insertEffectOnRow(widget.rowIndex, 'Reverb');
        await _setTrackEffectParam(widget.rowIndex, 0, 'Room Size', 40);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Mix', 20);
        await widget.insertEffectOnRow(widget.rowIndex, 'Delay');
        await _setTrackEffectParam(widget.rowIndex, 1, 'Delay Time', 400);
        await _setTrackEffectParam(widget.rowIndex, 1, 'Feedback', 30);
        await _setTrackEffectParam(widget.rowIndex, 1, 'Mix', 30);
        break;

      case 'LoFi Effect':
        await widget.insertEffectOnRow(widget.rowIndex, 'EQ Parametric');
        await _setTrackEffectParam(widget.rowIndex, 0, 'LPF Frequency', 2600.0);
        await widget.insertEffectOnRow(widget.rowIndex, 'Distortion');
        await _setTrackEffectParam(widget.rowIndex, 1, 'Drive', 50);
        await _setTrackEffectParam(widget.rowIndex, 1, 'Mix', 85);
        await _setTrackEffectParam(widget.rowIndex, 1, 'Anger', 1);
        await _setTrackEffectParam(widget.rowIndex, 1, 'LPF Frequency', 2800.0);
        await _setTrackEffectParam(
            widget.rowIndex, 1, 'Distortion Type', "Mode 3");
        break;

      case 'Heavy Crunch':
        await widget.insertEffectOnRow(widget.rowIndex, 'Distortion');
        await _setTrackEffectParam(widget.rowIndex, 0, 'Drive', 100);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Mix', 100);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Anger', 1);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Volume', 12);
        await _setTrackEffectParam(widget.rowIndex, 0, 'Pre Shape', 3.0);
        await _setTrackEffectParam(
            widget.rowIndex, 0, 'Distortion Type', "Mode 3");
        break;

      default:
        debugPrint('⚠️ No matching preset logic for: $presetName');
    }

    await _loadEffects();

    // BUILD 'AFTER' SNAPSHOT
    final afterSnapshots = <EffectSnapshot>[];
    for (int i = 0; i < _effects.length; i++) {
      final params = await widget.getTrackPluginParameters(widget.rowIndex, i);
      final isBypassed = await widget.getBypassStateForRow(widget.rowIndex, i);
      afterSnapshots.add(EffectSnapshot(_effects[i], isBypassed,
          {for (final p in params) p['name']: p['value']}));
    }
    final after = RowEffectsSnapshot(widget.rowIndex, afterSnapshots);
    widget.onPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildEffectTile(int idx) {
    final tile = ListTile(
      key: ValueKey("effect_${_effectKeys[idx]}"),
      contentPadding: EdgeInsets.zero,

      // only this area starts the reorder gesture
      leading: ReorderableDragStartListener(
        index: idx,
        child: const Padding(
          padding: EdgeInsets.only(left: 6.0, right: 6.0),
          child: Icon(Icons.drag_handle),
        ),
      ),

      title: Text(
        _effects[idx],
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15),
      ),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: !_bypassed[idx],
            onChanged: (active) async {
              final shouldBypass = !active;
              final previous = _bypassed[idx];

              setState(() => _bypassed[idx] = shouldBypass);
              try {
                await widget.setBypassForRow(
                    widget.rowIndex, idx, shouldBypass);
              } catch (_) {
                if (!mounted) return;
                setState(() => _bypassed[idx] = previous);
              }
            },
            activeColor: const Color.fromARGB(255, 231, 231, 231),
            inactiveThumbColor: const Color.fromARGB(255, 186, 186, 186),
            inactiveTrackColor: const Color.fromARGB(255, 235, 235, 235),
            activeTrackColor: const Color.fromARGB(255, 54, 54, 54),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color.fromARGB(255, 255, 164, 164)),
            onPressed: () => _confirmRemove(idx),
          ),
        ],
      ),

      onTap: () async {
        final liveIdx = await _resolveLiveEffectIndex(idx);
        final targetIdx = liveIdx >= 0 ? liveIdx : idx;
        await _openPluginParams(targetIdx);
      },
    );

    return _wrapWithHalos(
      key: ValueKey("effect_${_effectKeys[idx]}"),
      child: tile,
      haloKeys: <String>[
        ..._effectHaloKeys(effectIndex: idx, effectName: _effects[idx]),
      ],
      borderRadius: BorderRadius.circular(10),
    );
  }

  Widget _buildAddTile() {
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      key: const ValueKey("add_effect"),
      leading: const Icon(Icons.add_circle_outline),
      title: Text(
        L10n.translate(context, 'Add Effect'),
        style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15),
      ),
      onTap: _showAddEffectModal,
    );
    return _wrapWithHalos(
      child: tile,
      haloKeys: <String>[
        'row:${widget.rowIndex}:add_effect',
        'row:${widget.rowIndex}:fx_add',
      ],
      borderRadius: BorderRadius.circular(10),
    );
  }

  Future<void> _confirmRemove(int idx) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.translate(context, 'Delete Effect?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              L10n.translate(context, 'Cancel'),
              style: const TextStyle(color: Color.fromARGB(255, 218, 218, 218)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (yes == true) {
      final liveIdx = await _resolveLiveEffectIndex(idx);
      final targetIdx = liveIdx >= 0 ? liveIdx : idx;
      await widget.removeEffectFromRow(
          widget.rowIndex, targetIdx, _effects[idx], false);
      _delayDivisionByEffect.remove(targetIdx);
      await _loadEffects();
    }
  }

  // =========================
  // ADD EFFECT MODAL (dialog, can scroll internally)
  // =========================

  Future<void> _showAddEffectModal() async {
    final plugins = await widget.scanPlugins();
    // const allowedInBasic = ['Reverb', 'EQ Parametric', 'EQ 3-Band', 'Delay', 'Distortion', 'De-Esser', 'Compressor'];
    const allowedInBasic = [
      "Gain",
      "EQ 3-Band",
      "Compressor",
      "Limiter",
      "Clipper",
      "De-Esser",
      "Distortion",
      "Delay",
      "Reverb",
      "EQ Parametric",
      "Pitch Shift",
      "Chorus",
      "Vibrato",
    ];
    const fxChoices = [
      "Gain",
      "EQ 3-Band",
      "Compressor",
      "Limiter",
      "Clipper",
      "De-Esser",
      "Distortion",
      "Delay",
      "Reverb",
      "EQ Parametric",
      "Pitch Shift",
      "Chorus",
      "Vibrato",
    ];

    // Dialog can use scrolling; this is outside the row panel layout.
    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A2233),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: Container(
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFF121927),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.zero,
                indicator: BoxDecoration(
                  color: const Color(0xFF2D3F5D),
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  const Tab(text: 'FX'),
                  Tab(text: L10n.translate(context, 'On Device')),
                ],
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 390,
              child: TabBarView(
                children: [
                  ListView.separated(
                    itemCount: fxChoices.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      final name = fxChoices[i];
                      final isAllowed =
                          _isProEntitled || allowedInBasic.contains(name);
                      return GestureDetector(
                        onTap: isAllowed
                            ? () async {
                                Navigator.pop(context);
                                await widget.insertEffectOnRow(
                                    widget.rowIndex, name);
                                await _loadEffects();
                                final addedIndex = _effects.length - 1;
                                if (addedIndex >= 0 &&
                                    addedIndex < _effects.length) {
                                  widget.onTutorialEffectAdded?.call(
                                    widget.rowIndex,
                                    addedIndex,
                                    _effects[addedIndex],
                                  );
                                }
                              }
                            : null,
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            title: Text(
                              name,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.2),
                            ),
                            trailing: isAllowed
                                ? null
                                : const Icon(Icons.lock,
                                    size: 18, color: Colors.white70),
                          ),
                        ),
                      );
                    },
                  ),
                  ListView.separated(
                    itemCount: plugins.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      final meta = plugins[i];
                      final path = (meta['id'] ?? '').toString();
                      if (path.isEmpty) return const SizedBox.shrink();
                      final name = (meta['name'] ?? path).toString();
                      final format = (meta['format'] ?? '').toString();
                      final manufacturer =
                          (meta['manufacturer'] ?? '').toString();
                      final details = <String>[
                        if (format.isNotEmpty) format,
                        if (manufacturer.isNotEmpty) manufacturer,
                      ];
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        title: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13.2),
                        ),
                        subtitle: details.isEmpty
                            ? null
                            : Text(
                                details.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.62),
                                  fontSize: 11.0,
                                ),
                              ),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.insertEffectOnRow(widget.rowIndex, path);
                          await _loadEffects();
                          final addedIndex = _effects.length - 1;
                          if (addedIndex >= 0 && addedIndex < _effects.length) {
                            widget.onTutorialEffectAdded?.call(
                              widget.rowIndex,
                              addedIndex,
                              _effects[addedIndex],
                            );
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================
  // PARAMETERS PAGE (inline, no internal scroll)
  // =========================

  Future<void> _openPluginParams(int idx) async {
    if (idx < 0 || idx >= _effects.length) {
      await _loadEffects();
      if (idx < 0 || idx >= _effects.length) return;
    }

    widget.onTutorialEffectOpened?.call(
      widget.rowIndex,
      idx,
      idx >= 0 && idx < _effects.length ? _effects[idx] : 'Effect',
    );

    setState(() {
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
    });

    // Turn on dynamics reduction metering if it is about to be opened
    if (_showsDynamicsReductionMeter(_effects[idx])) {
      _startCompressorMetering(effectIndex: idx);
    } else {
      _stopCompressorMetering();
    }
    if (_effects[idx] == 'EQ Parametric' || _effects[idx] == 'EQ 3-Band') {
      _startEqWaveformPolling(effectIndex: idx);
    } else {
      _stopEqWaveformPolling();
    }

    var params = await widget.getTrackPluginParameters(widget.rowIndex, idx);
    if (params.isEmpty) {
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        params = await widget.getTrackPluginParameters(widget.rowIndex, idx);
        if (params.isNotEmpty) break;
      }
    }

    // Keep effect parameter subsets consistent with external/poll refresh.
    params = _filterParamsForEffect(_effects[idx], params);
    params = _mergePendingParamOverrides(idx, params);
    final effectName = _effects[idx];
    final estimatedHeight = (effectName == 'EQ Parametric')
        ? 760.0
        : (effectName == 'EQ 3-Band')
            ? 560.0
            : (220.0 + (math.max(0, params.length) * 74.0))
                .clamp(widget.minHeight, 1200.0)
                .toDouble();

    if (!mounted) return;
    setState(() {
      _currentParams = params;
      _paramsLoading = false;
    });
    widget.onHeightChanged(math.max(widget.minHeight, estimatedHeight));
  }

  Widget _buildEffectParamsPage(BuildContext context, int idx) {
    if (_paramsLoading) {
      return SizedBox(
        height: 180,
        child: Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor)),
      );
    }

    final effectName = _effects[idx];
    final effectPageHaloKeys = <String>[
      ..._effectHaloKeys(effectIndex: idx, effectName: effectName),
      'row:${widget.rowIndex}:fx_list',
      'row:${widget.rowIndex}:fx_params',
    ];

    // Special layout for EQ Parametric
    if (effectName == 'EQ Parametric' && _currentParams.isNotEmpty) {
      final pHPF = _paramByName(_currentParams, 'HPF Frequency');
      final pHPFSlope = _paramByName(_currentParams, 'HPF Slope');
      final pLPF = _paramByName(_currentParams, 'LPF Frequency');
      final pLPFSlope = _paramByName(_currentParams, 'LPF Slope');
      final pB1Freq = _paramByName(_currentParams, 'Band 1 Frequency');
      final pB1 = _paramByName(_currentParams, 'Band 1 Gain');
      final pB1Q = _paramByName(_currentParams, 'Band 1 Q');
      final pB2Freq = _paramByName(_currentParams, 'Band 2 Frequency');
      final pB2 = _paramByName(_currentParams, 'Band 2 Gain');
      final pB2Q = _paramByName(_currentParams, 'Band 2 Q');
      final pB3Freq = _paramByName(_currentParams, 'Band 3 Frequency');
      final pB3 = _paramByName(_currentParams, 'Band 3 Gain');
      final pB3Q = _paramByName(_currentParams, 'Band 3 Q');
      final pB4Freq = _paramByName(_currentParams, 'Band 4 Frequency');
      final pB4 = _paramByName(_currentParams, 'Band 4 Gain');
      final pB4Q = _paramByName(_currentParams, 'Band 4 Q');

      final hpfHz = (pHPF?['value'] as num?)?.toDouble() ?? 80.0;
      final lpfHz = (pLPF?['value'] as num?)?.toDouble() ?? 12000.0;
      final hpfSlopeDbOct = _parseSlopeDbPerOct(pHPFSlope?['value']);
      final lpfSlopeDbOct = _parseSlopeDbPerOct(pLPFSlope?['value']);

      final bandGains = [
        (pB1?['value'] as num?)?.toDouble() ?? 0,
        (pB2?['value'] as num?)?.toDouble() ?? 0,
        (pB3?['value'] as num?)?.toDouble() ?? 0,
        (pB4?['value'] as num?)?.toDouble() ?? 0,
      ];
      final bandFreqs = [
        (pB1Freq?['value'] as num?)?.toDouble() ?? 60.0,
        (pB2Freq?['value'] as num?)?.toDouble() ?? 400.0,
        (pB3Freq?['value'] as num?)?.toDouble() ?? 2000.0,
        (pB4Freq?['value'] as num?)?.toDouble() ?? 8000.0,
      ];
      final bandQs = [
        (pB1Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB2Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB3Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB4Q?['value'] as num?)?.toDouble() ?? 1.0,
      ];

      _EqFaderSpec? buildEqFader(
        Map<String, dynamic>? param, {
        required String label,
        required String unit,
        bool logarithmic = false,
      }) {
        if (param == null) return null;
        final name = param['name'] as String;
        return _EqFaderSpec(
          label: label,
          value: (param['value'] as num).toDouble(),
          min: (param['min'] as num).toDouble(),
          max: (param['max'] as num).toDouble(),
          defaultValue: _paramDefaultAsDouble(param),
          logarithmic: logarithmic,
          unit: unit,
          onChangeStart: (_) {
            _EQParamStartValue = (param['value'] as num).toDouble();
          },
          onChanged: (v) {
            setState(() => param['value'] = v);
            _setTrackEffectParam(widget.rowIndex, idx, name, v);
          },
          onChangeEnd: (v) {
            final startValue = _EQParamStartValue;
            if (startValue == null) return;
            _commitTrackEffectParam(
              widget.rowIndex,
              idx,
              name,
              startValue,
              v,
            );
            _EQParamStartValue = null;
          },
          onReset: () {
            final defaultValue = _paramDefaultAsDouble(param);
            if (defaultValue == null) return;
            final oldValue = (param['value'] as num).toDouble();
            if ((oldValue - defaultValue).abs() < 1.0e-6) return;
            setState(() => param['value'] = defaultValue);
            _setTrackEffectParam(widget.rowIndex, idx, name, defaultValue);
            _commitTrackEffectParam(
              widget.rowIndex,
              idx,
              name,
              oldValue,
              defaultValue,
            );
          },
        );
      }

      final gainFaders = <_EqFaderSpec>[
        if (pB1 != null) buildEqFader(pB1, label: 'Band 1', unit: 'dB')!,
        if (pB2 != null) buildEqFader(pB2, label: 'Band 2', unit: 'dB')!,
        if (pB3 != null) buildEqFader(pB3, label: 'Band 3', unit: 'dB')!,
        if (pB4 != null) buildEqFader(pB4, label: 'Band 4', unit: 'dB')!,
      ];
      final frequencyFaders = <_EqFaderSpec>[
        if (pB1Freq != null)
          buildEqFader(
            pB1Freq,
            label: 'Band 1',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB2Freq != null)
          buildEqFader(
            pB2Freq,
            label: 'Band 2',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB3Freq != null)
          buildEqFader(
            pB3Freq,
            label: 'Band 3',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB4Freq != null)
          buildEqFader(
            pB4Freq,
            label: 'Band 4',
            unit: 'Hz',
            logarithmic: true,
          )!,
      ];
      final qFaders = <_EqFaderSpec>[
        if (pB1Q != null) buildEqFader(pB1Q, label: 'Band 1', unit: 'Q')!,
        if (pB2Q != null) buildEqFader(pB2Q, label: 'Band 2', unit: 'Q')!,
        if (pB3Q != null) buildEqFader(pB3Q, label: 'Band 3', unit: 'Q')!,
        if (pB4Q != null) buildEqFader(pB4Q, label: 'Band 4', unit: 'Q')!,
      ];
      final hpfSlopeChoices =
          (pHPFSlope != null && pHPFSlope['type'] == 'choice')
              ? _extractChoiceValues(pHPFSlope)
              : const <String>[];
      final lpfSlopeChoices =
          (pLPFSlope != null && pLPFSlope['type'] == 'choice')
              ? _extractChoiceValues(pLPFSlope)
              : const <String>[];
      final hpfSlopeCurrent = hpfSlopeChoices.isEmpty
          ? null
          : (hpfSlopeChoices.contains(pHPFSlope?['value']?.toString())
              ? pHPFSlope!['value'].toString()
              : hpfSlopeChoices.first);
      final lpfSlopeCurrent = lpfSlopeChoices.isEmpty
          ? null
          : (lpfSlopeChoices.contains(pLPFSlope?['value']?.toString())
              ? pLPFSlope!['value'].toString()
              : lpfSlopeChoices.first);
      final frequencyExtraControls = <Widget>[
        if (pHPF != null)
          _buildEqFilterControlRow(
            context: context,
            label: 'HPF',
            value: (pHPF['value'] as num).toDouble(),
            min: (pHPF['min'] as num).toDouble(),
            max: (pHPF['max'] as num).toDouble(),
            logarithmic: true,
            onChangeStart: (_) {
              _EQParamStartValue = (pHPF['value'] as num).toDouble();
            },
            onChanged: (v) {
              setState(() => pHPF['value'] = v);
              _setTrackEffectParam(
                  widget.rowIndex, idx, pHPF['name'] as String, v);
            },
            onChangeEnd: (v) {
              final startValue = _EQParamStartValue;
              if (startValue == null) return;
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pHPF['name'] as String,
                startValue,
                v,
              );
              _EQParamStartValue = null;
            },
            onDoubleTapReset: () {
              final defaultValue = _paramDefaultAsDouble(pHPF);
              if (defaultValue == null) return;
              final oldValue = (pHPF['value'] as num).toDouble();
              if ((oldValue - defaultValue).abs() < 1.0e-6) return;
              setState(() => pHPF['value'] = defaultValue);
              _setTrackEffectParam(
                  widget.rowIndex, idx, pHPF['name'] as String, defaultValue);
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pHPF['name'] as String,
                oldValue,
                defaultValue,
              );
            },
            slopeChoices: hpfSlopeChoices,
            selectedSlope: hpfSlopeCurrent,
            onSlopeChanged: (picked) {
              if (pHPFSlope == null) return;
              final oldVal = pHPFSlope['value'];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => pHPFSlope['value'] = picked);
              });
              _setTrackEffectParam(
                  widget.rowIndex, idx, pHPFSlope['name'] as String, picked);
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pHPFSlope['name'] as String,
                oldVal,
                picked,
              );
            },
          ),
        if (pHPF != null && pLPF != null) const SizedBox(height: 6),
        if (pLPF != null)
          _buildEqFilterControlRow(
            context: context,
            label: 'LPF',
            value: (pLPF['value'] as num).toDouble(),
            min: (pLPF['min'] as num).toDouble(),
            max: (pLPF['max'] as num).toDouble(),
            logarithmic: true,
            onChangeStart: (_) {
              _EQParamStartValue = (pLPF['value'] as num).toDouble();
            },
            onChanged: (v) {
              setState(() => pLPF['value'] = v);
              _setTrackEffectParam(
                  widget.rowIndex, idx, pLPF['name'] as String, v);
            },
            onChangeEnd: (v) {
              final startValue = _EQParamStartValue;
              if (startValue == null) return;
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pLPF['name'] as String,
                startValue,
                v,
              );
              _EQParamStartValue = null;
            },
            onDoubleTapReset: () {
              final defaultValue = _paramDefaultAsDouble(pLPF);
              if (defaultValue == null) return;
              final oldValue = (pLPF['value'] as num).toDouble();
              if ((oldValue - defaultValue).abs() < 1.0e-6) return;
              setState(() => pLPF['value'] = defaultValue);
              _setTrackEffectParam(
                  widget.rowIndex, idx, pLPF['name'] as String, defaultValue);
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pLPF['name'] as String,
                oldValue,
                defaultValue,
              );
            },
            slopeChoices: lpfSlopeChoices,
            selectedSlope: lpfSlopeCurrent,
            onSlopeChanged: (picked) {
              if (pLPFSlope == null) return;
              final oldVal = pLPFSlope['value'];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => pLPFSlope['value'] = picked);
              });
              _setTrackEffectParam(
                  widget.rowIndex, idx, pLPFSlope['name'] as String, picked);
              _commitTrackEffectParam(
                widget.rowIndex,
                idx,
                pLPFSlope['name'] as String,
                oldVal,
                picked,
              );
            },
          ),
      ];

      return _wrapWithHalos(
          haloKeys: effectPageHaloKeys,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row with back button
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 26, height: 26),
                      splashRadius: 14,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () {
                        _stopEqWaveformPolling();
                        setState(() {
                          _selectedEffectIndex = null;
                          _currentParams = [];
                        });
                        widget.onHeightChanged(widget.minHeight);
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        effectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(1.00),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final changes = <Map<String, dynamic>>[];
                        for (final p in _currentParams) {
                          final next = _paramDefaultValue(p);
                          if (next == null) continue;
                          final old = p['value'];
                          if (_paramValuesEqual(old, next)) continue;
                          changes.add({
                            'param': p,
                            'old': old,
                            'next': next,
                          });
                        }
                        if (changes.isEmpty) return;

                        setState(() {
                          for (final c in changes) {
                            (c['param'] as Map<String, dynamic>)['value'] =
                                c['next'];
                          }
                        });

                        for (final c in changes) {
                          final p = c['param'] as Map<String, dynamic>;
                          final oldVal = c['old'];
                          final newVal = c['next'];
                          final name = p['name'] as String;
                          await _setTrackEffectParam(
                              widget.rowIndex, idx, name, newVal);
                          _commitTrackEffectParam(
                            widget.rowIndex,
                            idx,
                            name,
                            oldVal,
                            newVal,
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 28),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label:
                          const Text('Reset', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(
                  height: 1,
                  thickness: 0.9,
                  color: Color.fromARGB(213, 104, 104, 104),
                ),
                const SizedBox(height: 6),

                LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth, // EQ shrinks inside row
                      ),
                      child: Column(
                        children: [
                          // EQ Preview
                          _EqPreviewFull(
                              hpfHz: hpfHz,
                              lpfHz: lpfHz,
                              hpfSlopeDbOct: hpfSlopeDbOct,
                              lpfSlopeDbOct: lpfSlopeDbOct,
                              bandGains: bandGains,
                              bandFreqs: bandFreqs,
                              bandQs: bandQs,
                              waveformSamples: _eqWaveform,
                              spectrumDb: _eqSpectrumDb,
                              analyzerSampleRate: _eqAnalyzerSampleRate),
                          const SizedBox(height: 16),
                          _buildEqParametricTabs(
                            context: context,
                            gainFaders: gainFaders,
                            frequencyFaders: frequencyFaders,
                            qFaders: qFaders,
                            frequencyExtraControls: frequencyExtraControls,
                            selectedTabIndex: _eqParametricTabIndex,
                            onTabChanged: (index) {
                              if (_eqParametricTabIndex == index) return;
                              setState(() => _eqParametricTabIndex = index);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ));
    }

    if (effectName == 'EQ 3-Band' && _currentParams.isNotEmpty) {
      final pLow = _paramByName(_currentParams, 'Low Gain');
      final pMid = _paramByName(_currentParams, 'Mid Gain');
      final pHigh = _paramByName(_currentParams, 'High Gain');

      final gains = [
        (pLow?['value'] as num?)?.toDouble() ?? 0.0,
        (pMid?['value'] as num?)?.toDouble() ?? 0.0,
        (pHigh?['value'] as num?)?.toDouble() ?? 0.0,
      ];

      // Must match JUCE fixed centers for accurate preview
      final freqs = [140.0, 1200.0, 8000.0];

      return _wrapWithHalos(
          haloKeys: effectPageHaloKeys,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 26, height: 26),
                      splashRadius: 14,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () {
                        _stopEqWaveformPolling();
                        setState(() {
                          _selectedEffectIndex = null;
                          _currentParams = [];
                        });
                        widget.onHeightChanged(widget.minHeight);
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        effectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withOpacity(1.00),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(
                  height: 1,
                  thickness: 0.9,
                  color: Color.fromARGB(213, 104, 104, 104),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Column(
                        children: [
                          _Eq3Preview(
                            bandGains: gains,
                            bandFreqs: freqs,
                            waveformSamples: _eqWaveform,
                            spectrumDb: _eqSpectrumDb,
                            analyzerSampleRate: _eqAnalyzerSampleRate,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: _eqRowHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (pLow != null)
                                    _verticalFader(
                                      context: context,
                                      label: 'Low',
                                      onLongPressStart: (globalPos) =>
                                          _showAutomateParameterSheet(
                                        effectIndex: idx,
                                        effectName: effectName,
                                        paramId:
                                            (pLow['id'] ?? pLow['name'] ?? '')
                                                .toString()
                                                .trim(),
                                        paramName: (pLow['name'] ?? 'Low')
                                            .toString()
                                            .trim(),
                                        haloKeys: _paramHaloKeys(
                                          effectIndex: idx,
                                          effectName: effectName,
                                          paramName: (pLow['name'] ?? 'Low')
                                              .toString(),
                                        ),
                                        anchorGlobalPos: globalPos,
                                      ),
                                      value: (pLow['value'] as num).toDouble(),
                                      min: (pLow['min'] as num).toDouble(),
                                      max: (pLow['max'] as num).toDouble(),
                                      defaultValue: _paramDefaultAsDouble(pLow),
                                      unit: 'dB',
                                      onDoubleTapReset: () {
                                        final defaultValue =
                                            _paramDefaultAsDouble(pLow);
                                        if (defaultValue == null) return;
                                        final oldValue =
                                            (pLow['value'] as num).toDouble();
                                        if ((oldValue - defaultValue).abs() <
                                            1.0e-6) {
                                          return;
                                        }
                                        setState(
                                            () => pLow['value'] = defaultValue);
                                        _setTrackEffectParam(
                                            widget.rowIndex,
                                            idx,
                                            pLow['name'] as String,
                                            defaultValue);
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pLow['name'] as String,
                                          oldValue,
                                          defaultValue,
                                        );
                                      },
                                      onChangeStart: (v) {
                                        _EQParamStartValue =
                                            (pLow['value'] as num).toDouble();
                                      },
                                      onChangeEnd: (v) {
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pLow['name'] as String,
                                          _EQParamStartValue!,
                                          v,
                                        );
                                        _EQParamStartValue = null;
                                      },
                                      onChanged: (v) {
                                        setState(() => pLow['value'] = v);
                                        _setTrackEffectParam(widget.rowIndex,
                                            idx, pLow['name'] as String, v);
                                      },
                                    ),
                                  if (pMid != null)
                                    _verticalFader(
                                      context: context,
                                      label: 'Mid',
                                      onLongPressStart: (globalPos) =>
                                          _showAutomateParameterSheet(
                                        effectIndex: idx,
                                        effectName: effectName,
                                        paramId:
                                            (pMid['id'] ?? pMid['name'] ?? '')
                                                .toString()
                                                .trim(),
                                        paramName: (pMid['name'] ?? 'Mid')
                                            .toString()
                                            .trim(),
                                        haloKeys: _paramHaloKeys(
                                          effectIndex: idx,
                                          effectName: effectName,
                                          paramName: (pMid['name'] ?? 'Mid')
                                              .toString(),
                                        ),
                                        anchorGlobalPos: globalPos,
                                      ),
                                      value: (pMid['value'] as num).toDouble(),
                                      min: (pMid['min'] as num).toDouble(),
                                      max: (pMid['max'] as num).toDouble(),
                                      defaultValue: _paramDefaultAsDouble(pMid),
                                      unit: 'dB',
                                      onDoubleTapReset: () {
                                        final defaultValue =
                                            _paramDefaultAsDouble(pMid);
                                        if (defaultValue == null) return;
                                        final oldValue =
                                            (pMid['value'] as num).toDouble();
                                        if ((oldValue - defaultValue).abs() <
                                            1.0e-6) {
                                          return;
                                        }
                                        setState(
                                            () => pMid['value'] = defaultValue);
                                        _setTrackEffectParam(
                                            widget.rowIndex,
                                            idx,
                                            pMid['name'] as String,
                                            defaultValue);
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pMid['name'] as String,
                                          oldValue,
                                          defaultValue,
                                        );
                                      },
                                      onChangeStart: (v) {
                                        _EQParamStartValue =
                                            (pMid['value'] as num).toDouble();
                                      },
                                      onChangeEnd: (v) {
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pMid['name'] as String,
                                          _EQParamStartValue!,
                                          v,
                                        );
                                        _EQParamStartValue = null;
                                      },
                                      onChanged: (v) {
                                        setState(() => pMid['value'] = v);
                                        _setTrackEffectParam(widget.rowIndex,
                                            idx, pMid['name'] as String, v);
                                      },
                                    ),
                                  if (pHigh != null)
                                    _verticalFader(
                                      context: context,
                                      label: 'High',
                                      onLongPressStart: (globalPos) =>
                                          _showAutomateParameterSheet(
                                        effectIndex: idx,
                                        effectName: effectName,
                                        paramId:
                                            (pHigh['id'] ?? pHigh['name'] ?? '')
                                                .toString()
                                                .trim(),
                                        paramName: (pHigh['name'] ?? 'High')
                                            .toString()
                                            .trim(),
                                        haloKeys: _paramHaloKeys(
                                          effectIndex: idx,
                                          effectName: effectName,
                                          paramName: (pHigh['name'] ?? 'High')
                                              .toString(),
                                        ),
                                        anchorGlobalPos: globalPos,
                                      ),
                                      value: (pHigh['value'] as num).toDouble(),
                                      min: (pHigh['min'] as num).toDouble(),
                                      max: (pHigh['max'] as num).toDouble(),
                                      defaultValue:
                                          _paramDefaultAsDouble(pHigh),
                                      unit: 'dB',
                                      onDoubleTapReset: () {
                                        final defaultValue =
                                            _paramDefaultAsDouble(pHigh);
                                        if (defaultValue == null) return;
                                        final oldValue =
                                            (pHigh['value'] as num).toDouble();
                                        if ((oldValue - defaultValue).abs() <
                                            1.0e-6) {
                                          return;
                                        }
                                        setState(() =>
                                            pHigh['value'] = defaultValue);
                                        _setTrackEffectParam(
                                            widget.rowIndex,
                                            idx,
                                            pHigh['name'] as String,
                                            defaultValue);
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pHigh['name'] as String,
                                          oldValue,
                                          defaultValue,
                                        );
                                      },
                                      onChangeStart: (v) {
                                        _EQParamStartValue =
                                            (pHigh['value'] as num).toDouble();
                                      },
                                      onChangeEnd: (v) {
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pHigh['name'] as String,
                                          _EQParamStartValue!,
                                          v,
                                        );
                                        _EQParamStartValue = null;
                                      },
                                      onChanged: (v) {
                                        setState(() => pHigh['value'] = v);
                                        _setTrackEffectParam(widget.rowIndex,
                                            idx, pHigh['name'] as String, v);
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ));
    }

    // Generic parameter page (no scroll, full height in row)
    return _wrapWithHalos(
        haloKeys: effectPageHaloKeys,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    splashRadius: 14,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: () {
                      _stopCompressorMetering();
                      _stopEqWaveformPolling();
                      setState(() {
                        _selectedEffectIndex = null;
                        _currentParams = [];
                      });
                      widget.onHeightChanged(widget.minHeight);
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      effectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(1.00),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(
                height: 1,
                thickness: 0.9,
                color: Color.fromARGB(213, 104, 104, 104),
              ),
              const SizedBox(height: 6),

              if (_showsDynamicsReductionMeter(effectName)) ...[
                // _buildCompressorMeterStrip(),
                const SizedBox(height: 10),
                GainReductionSliderMeterHorizontal(
                  grDb: _compFrameSmoothed.grDb,
                  maxDb: 24,
                  title: _dynamicsReductionMeterTitle(effectName),
                ),
                const SizedBox(height: 10),
              ],

              // Params straight in Column
              for (var param in _currentParams) ...[
                if (_effects[idx] == 'Delay' &&
                    param['name'] == 'Delay Time') ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: _buildDelayTimeParam(
                        context: context,
                        param: param,
                        effectIndex: idx,
                        bpm: widget.projectBpm),
                  ),
                ] else if (_isGainVolumeParam(effectName, param)) ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: _buildGainVolumeParam(
                      context: context,
                      param: param,
                      effectIndex: idx,
                    ),
                  ),
                ] else if (_isPitchShiftSemitonesParam(effectName, param)) ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: _buildPitchShiftSemitonesParam(
                      context: context,
                      param: param,
                      effectIndex: idx,
                    ),
                  ),
                ] else if (param['type'] == 'float') ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(param['name'] as String,
                              style: Theme.of(context).textTheme.bodyLarge),
                          // const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                (param['min'] as num)
                                    .toDouble()
                                    .toStringAsFixed(2),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              // const SizedBox(width: 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    showValueIndicator:
                                        ShowValueIndicator.always,
                                    valueIndicatorTextStyle: const TextStyle(
                                      color: Color.fromARGB(255, 0, 0, 0),
                                      fontSize: 12,
                                    ),
                                  ),
                                  child: (() {
                                    final effectName = _effects[idx];
                                    final paramName = param['name'] as String;

                                    final minV =
                                        (param['min'] as num).toDouble();
                                    final maxV =
                                        (param['max'] as num).toDouble();
                                    final rawV = (param['value'] as num)
                                        .toDouble()
                                        .clamp(minV, maxV);

                                    final skew = _getParamSkew(
                                        effectName, paramName); // null = linear

                                    // value -> 0..1
                                    double toNorm(double v) =>
                                        ((v - minV) / (maxV - minV))
                                            .clamp(0.0, 1.0);

                                    // 0..1 -> value
                                    double fromNorm(double t) =>
                                        minV +
                                        (maxV - minV) * t.clamp(0.0, 1.0);

                                    // if skew exists: position uses norm^skew, and inverse uses ^(1/skew)
                                    final norm = toNorm(rawV);
                                    final sliderPos = (skew == null)
                                        ? norm
                                        : math.pow(norm, skew).toDouble();

                                    return GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onDoubleTap: () {
                                        final defaultValue =
                                            _paramDefaultAsDouble(param);
                                        if (defaultValue == null) return;
                                        final clampedDefault = defaultValue
                                            .clamp(minV, maxV)
                                            .toDouble();
                                        final oldValue =
                                            (param['value'] as num).toDouble();
                                        if ((oldValue - clampedDefault).abs() <
                                            1.0e-6) {
                                          return;
                                        }
                                        setState(() =>
                                            param['value'] = clampedDefault);
                                        _setTrackEffectParam(widget.rowIndex,
                                            idx, paramName, clampedDefault);
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          paramName,
                                          oldValue,
                                          clampedDefault,
                                        );
                                      },
                                      child: Slider(
                                        value: sliderPos,
                                        min: 0.0,
                                        max: 1.0,
                                        divisions: 200,
                                        label: rawV.toStringAsFixed(2),
                                        onChangeStart: (_) {
                                          _paramDragStartValue = rawV;
                                        },
                                        onChanged: (p) {
                                          final t = p.clamp(0.0, 1.0);
                                          final newNorm = (skew == null)
                                              ? t
                                              : math
                                                  .pow(t, 1.0 / skew!)
                                                  .toDouble();
                                          final v = fromNorm(newNorm);

                                          setState(() => param['value'] = v);
                                          _setTrackEffectParam(widget.rowIndex,
                                              idx, paramName, v);
                                        },
                                        onChangeEnd: (p) {
                                          if (_paramDragStartValue == null)
                                            return;

                                          final t = p.clamp(0.0, 1.0);
                                          final newNorm = (skew == null)
                                              ? t
                                              : math
                                                  .pow(t, 1.0 / skew!)
                                                  .toDouble();
                                          final v = fromNorm(newNorm);

                                          _commitTrackEffectParam(
                                            widget.rowIndex,
                                            idx,
                                            paramName,
                                            _paramDragStartValue!,
                                            v,
                                          );

                                          _paramDragStartValue = null;
                                        },
                                      ),
                                    );
                                  })(),
                                ),
                              ),
                              // const SizedBox(width: 8),
                              Text(
                                (param['max'] as num)
                                    .toDouble()
                                    .toStringAsFixed(2),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (param['type'] == 'bool') ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(param['name'] as String),
                      value: param['value'] as bool,
                      onChanged: (v) {
                        setState(() => param['value'] = v);
                        _setTrackEffectParam(
                            widget.rowIndex, idx, param['name'] as String, v);
                        _commitTrackEffectParam(widget.rowIndex, idx,
                            param['name'] as String, !v, v);
                      },
                    ),
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
                    final choices =
                        keys.map((k) => param[k] as String).toList();
                    final current = param['value'] as String;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4.0, horizontal: 4),
                      child: _wrapAutomatableParam(
                        effectIndex: idx,
                        effectName: effectName,
                        param: param,
                        borderRadius: BorderRadius.circular(10),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(param['name'] as String),
                          trailing: Text(current,
                              style: Theme.of(context).textTheme.bodyLarge),
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
                                      onPressed: () => Navigator.pop(ctx, c));
                                }).toList(),
                              ),
                            );
                            if (picked != null) {
                              final oldVal = param['value'];
                              setState(() => param['value'] = picked);
                              _setTrackEffectParam(widget.rowIndex, idx,
                                  param['name'] as String, picked);
                              _commitTrackEffectParam(widget.rowIndex, idx,
                                  param['name'] as String, oldVal, picked);
                            }
                          },
                        ),
                      ),
                    );
                  })(),
                ] else ...[
                  _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4.0, horizontal: 4),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(param['name'] as String),
                        trailing: Text("${param['value']}"),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ));
  }
}

class MasterEffectsPanel extends StatefulWidget {
  final String mode;
  final bool? isProEntitled;

  // Master FX callbacks (to be wired in audio_editor)
  final Future<List<String>> Function() getMasterEffects;
  final Future<List<String>> Function() getMasterEffectIds;
  final Future<bool> Function(int effectIndex) getMasterEffectBypassState;
  final Future<void> Function(int effectIndex, bool bypass) bypassMasterEffect;
  final Future<void> Function(int from, int to) reorderMasterEffects;
  final Future<void> Function(int effectIndex, String name, bool applyingPreset)
      removeMasterEffect;
  final Future<void> Function(String effectNameOrPath) insertMasterEffect;
  final Future<List<Map<String, dynamic>>> Function(int effectIndex)
      getMasterPluginParameters;
  final Future<void> Function(int effectIndex, String paramId, dynamic value)
      setMasterEffectParam;
  final Future<void> Function(
    int effectIndex,
    String effectName,
    String paramId,
    String paramName,
  )? onRequestAutomateParameter;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final void Function(
          int effectIndex, String paramId, dynamic oldValue, dynamic newValue)?
      onMasterPluginParamCommit;
  final void Function(
          MasterEffectsSnapshot before, MasterEffectsSnapshot after)?
      onMasterPresetCommit;

  final void Function(double height)? onHeightChanged;
  final double projectBpm;

  final MeterBus meters;
  final Future<List<double>> Function(int effectIndex) getMasterCompressorMeter;
  final Future<List<double>> Function(int effectIndex, int sampleCount)
      getMasterEqWaveform;
  final MixChangeHighlighter? highlighter;
  final void Function(
    Future<void> Function(int effectIndex, String paramId) reveal,
  )? registerParameterRevealer;

  const MasterEffectsPanel({
    Key? key,
    required this.mode,
    this.isProEntitled,
    required this.getMasterEffects,
    required this.getMasterEffectIds,
    required this.getMasterEffectBypassState,
    required this.bypassMasterEffect,
    required this.reorderMasterEffects,
    required this.removeMasterEffect,
    required this.insertMasterEffect,
    required this.getMasterPluginParameters,
    required this.setMasterEffectParam,
    this.onRequestAutomateParameter,
    required this.scanPlugins,
    this.onHeightChanged,
    this.onMasterPluginParamCommit,
    this.onMasterPresetCommit,
    required this.projectBpm,
    required this.meters,
    required this.getMasterCompressorMeter,
    required this.getMasterEqWaveform,
    this.highlighter,
    this.registerParameterRevealer,
  }) : super(key: key);

  @override
  State<MasterEffectsPanel> createState() => _MasterEffectsPanelState();
}

class _MasterEffectsPanelState extends State<MasterEffectsPanel> {
  List<String> _effects = [];
  List<String> _effectKeys = [];
  List<bool> _bypassed = [];
  double _panelHeight = 220;

  int? _selectedEffectIndex;
  List<Map<String, dynamic>> _currentParams = [];
  bool _paramsLoading = false;

  // for undo state
  double? _paramDragStartValue;
  double? _EQParamStartValue;

  // for Delay Time parameter
  final Map<int, int> _delayDivisionByEffect = {};

  Timer? _compMeterTimer;
  CompressorStripFrame _compFrame = CompressorStripFrame.zero;
  CompressorStripFrame _compFrameSmoothed = CompressorStripFrame.zero;
  bool _compMeterRunning = false;
  Timer? _eqWaveformTimer;
  bool _eqWaveformRunning = false;
  List<double> _eqWaveform = const <double>[];
  List<double> _eqSpectrumDb = const <double>[];
  double _eqAnalyzerSampleRate = 44100.0;
  int _eqParametricTabIndex = 0;

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

  bool get _isKnownSubscriptionMode =>
      widget.isProEntitled != null ||
      widget.mode == 'Basic' ||
      widget.mode == 'Pro';

  String _haloSlug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _normalizedParamToken(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  List<String> _effectHaloKeys({
    required int effectIndex,
    required String effectName,
  }) {
    final lower = effectName.trim().toLowerCase();
    final slug = _haloSlug(effectName);
    final tokens = slug
        .split('_')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    final out = <String>[
      'master:fx_index:$effectIndex',
      if (lower.isNotEmpty) 'master:fx_contains:$lower',
      if (slug.isNotEmpty) 'master:fx_contains:$slug',
    ];
    for (final token in tokens) {
      out.add('master:fx_contains:$token');
    }
    return out;
  }

  List<String> _paramHaloKeys({
    required int effectIndex,
    required String effectName,
    required String paramName,
  }) {
    final paramSlug = _haloSlug(paramName);
    final paramLower = paramName.trim().toLowerCase();
    return <String>[
      if (paramName.trim().isNotEmpty)
        'master:fx_index:$effectIndex:param:${paramName.trim()}',
      if (paramSlug.isNotEmpty) 'master:fx_index:$effectIndex:param:$paramSlug',
      if (paramLower.isNotEmpty)
        'master:fx_index:$effectIndex:param:$paramLower',
    ];
  }

  Widget _wrapWithHalos({
    required Widget child,
    required List<String> haloKeys,
    BorderRadius? borderRadius,
  }) {
    final highlighter = widget.highlighter;
    if (highlighter == null || haloKeys.isEmpty) return child;
    final mapped = haloKeys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .map(HaloKey.new)
        .toList(growable: false);
    if (mapped.isEmpty) return child;
    return MultiHalo(
      highlighter: highlighter,
      haloKeys: mapped,
      borderRadius: borderRadius,
      child: child,
    );
  }

  void _triggerHalos(
    List<String> haloKeys, {
    Duration duration = const Duration(milliseconds: 800),
  }) {
    final highlighter = widget.highlighter;
    if (highlighter == null || haloKeys.isEmpty) return;
    final mapped = haloKeys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .map(HaloKey.new)
        .toList(growable: false);
    if (mapped.isEmpty) return;
    highlighter.trigger(mapped, duration: duration);
  }

  Future<void> _showAutomateParameterSheet({
    required int effectIndex,
    required String effectName,
    required String paramId,
    required String paramName,
    required List<String> haloKeys,
    Offset? anchorGlobalPos,
  }) async {
    if (widget.onRequestAutomateParameter == null) return;
    _triggerHalos(
      haloKeys,
      duration: const Duration(milliseconds: 320),
    );
    await AppHaptics.impact(AppHapticImpact.medium);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final fallbackAnchor = (() {
      final box = context.findRenderObject();
      if (box is RenderBox) {
        return box.localToGlobal(
          Offset(box.size.width / 2, box.size.height / 2),
        );
      }
      return const Offset(120, 120);
    })();
    final anchor = anchorGlobalPos ?? fallbackAnchor;
    String? action;
    if (overlay != null) {
      final left = anchor.dx.clamp(0.0, overlay.size.width).toDouble();
      final top = (anchor.dy - 40.0).clamp(0.0, overlay.size.height).toDouble();
      final right = (overlay.size.width - anchor.dx)
          .clamp(0.0, overlay.size.width)
          .toDouble();
      final bottom = (overlay.size.height - anchor.dy)
          .clamp(0.0, overlay.size.height)
          .toDouble();
      action = await showMenu<String>(
        context: context,
        color: const Color(0xFF1B2233),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        position: RelativeRect.fromLTRB(left, top, right, bottom),
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'automate',
            height: 34,
            child: Text('Automate'),
          ),
        ],
      );
    }
    if (action != 'automate') return;
    _triggerHalos(haloKeys);
    await widget.onRequestAutomateParameter!(
      effectIndex,
      effectName,
      paramId,
      paramName,
    );
  }

  Future<void> _revealParameter(int effectIndex, String paramId) async {
    if (effectIndex < 0) return;
    if (effectIndex >= _effects.length) {
      await _loadEffects();
      if (effectIndex < 0 || effectIndex >= _effects.length) return;
    }
    await _openPluginParams(effectIndex);
    if (!mounted) return;
    final effectName = _effects[effectIndex];
    final targetRaw = paramId.trim();
    final target = targetRaw.toLowerCase();
    final targetToken = _normalizedParamToken(targetRaw);
    final match = _currentParams.cast<Map<String, dynamic>?>().firstWhere(
      (param) {
        if (param == null) return false;
        final candidateId =
            (param['id'] ?? param['name'] ?? '').toString().trim();
        final candidateName = (param['name'] ?? candidateId).toString().trim();
        if (target.isEmpty) return false;
        final idLower = candidateId.toLowerCase();
        final nameLower = candidateName.toLowerCase();
        if (idLower == target || nameLower == target) return true;
        if (targetToken.isEmpty) return false;
        return _normalizedParamToken(candidateId) == targetToken ||
            _normalizedParamToken(candidateName) == targetToken;
      },
      orElse: () => null,
    );
    final matchedParamName =
        (match?['name'] ?? match?['id'] ?? targetRaw).toString().trim();
    final matchedParamId =
        (match?['id'] ?? match?['name'] ?? targetRaw).toString().trim();
    final haloKeys = <String>[];
    final seen = <String>{};
    void addHaloKeys(List<String> keys) {
      for (final key in keys) {
        final trimmed = key.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) continue;
        haloKeys.add(trimmed);
      }
    }

    addHaloKeys(
      _paramHaloKeys(
        effectIndex: effectIndex,
        effectName: effectName,
        paramName: matchedParamName,
      ),
    );
    if (matchedParamId.isNotEmpty &&
        matchedParamId.toLowerCase() != matchedParamName.toLowerCase()) {
      addHaloKeys(
        _paramHaloKeys(
          effectIndex: effectIndex,
          effectName: effectName,
          paramName: matchedParamId,
        ),
      );
    }
    if (targetRaw.isNotEmpty &&
        targetRaw.toLowerCase() != matchedParamName.toLowerCase() &&
        targetRaw.toLowerCase() != matchedParamId.toLowerCase()) {
      addHaloKeys(
        _paramHaloKeys(
          effectIndex: effectIndex,
          effectName: effectName,
          paramName: targetRaw,
        ),
      );
    }
    if (haloKeys.isEmpty) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _triggerHalos(haloKeys);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _triggerHalos(haloKeys);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    _triggerHalos(haloKeys);
  }

  Widget _wrapAutomatableParam({
    required int effectIndex,
    required String effectName,
    required Map<String, dynamic> param,
    required Widget child,
    BorderRadius? borderRadius,
  }) {
    final paramName =
        (param['name'] ?? param['id'] ?? 'Parameter').toString().trim();
    final paramId = (param['id'] ?? param['name'] ?? '').toString().trim();
    final haloKeys = _paramHaloKeys(
      effectIndex: effectIndex,
      effectName: effectName,
      paramName: paramName,
    );
    return KeyedSubtree(
      key: ValueKey(
        'master_param_${effectIndex}_${_testKeySlug(effectName)}_${_testKeySlug(paramName)}',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) => _showAutomateParameterSheet(
          effectIndex: effectIndex,
          effectName: effectName,
          paramId: paramId,
          paramName: paramName,
          haloKeys: haloKeys,
          anchorGlobalPos: details.globalPosition,
        ),
        child: _wrapWithHalos(
          haloKeys: haloKeys,
          borderRadius: borderRadius,
          child: child,
        ),
      ),
    );
  }

  Widget _buildGainVolumeParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
  }) {
    final paramName = param['name'] as String;
    final minV = ((param['min'] as num?)?.toDouble() ?? 0.0);
    final maxV = ((param['max'] as num?)?.toDouble() ?? 3.0);
    final rawV =
        ((param['value'] as num?)?.toDouble() ?? 2.0).clamp(minV, maxV);
    final defaultValue = _paramDefaultAsDouble(param);
    final unity = 2.0.clamp(minV, maxV).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(paramName, style: Theme.of(context).textTheme.bodyLarge),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final target =
                        (defaultValue ?? unity).clamp(minV, maxV).toDouble();
                    final oldValue = (param['value'] as num).toDouble();
                    if ((oldValue - target).abs() < 1.0e-6) return;
                    setState(() => param['value'] = target);
                    widget.setMasterEffectParam(effectIndex, paramName, target);
                    widget.onMasterPluginParamCommit?.call(
                      effectIndex,
                      paramName,
                      oldValue,
                      target,
                    );
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 11),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: rawV,
                      min: minV,
                      max: maxV,
                      onChangeStart: (_) {
                        _paramDragStartValue = rawV;
                      },
                      onChanged: (v) {
                        setState(() => param['value'] = v);
                        widget.setMasterEffectParam(effectIndex, paramName, v);
                      },
                      onChangeEnd: (v) {
                        if (_paramDragStartValue == null) return;
                        widget.onMasterPluginParamCommit?.call(
                          effectIndex,
                          paramName,
                          _paramDragStartValue!,
                          v,
                        );
                        _paramDragStartValue = null;
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  _formatGainDb(rawV, uiMax: maxV),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadEffects();
    widget.registerParameterRevealer?.call(_revealParameter);
  }

  @override
  void dispose() {
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    super.dispose();
  }

  Future<void> _loadEffects() async {
    _stopEqWaveformPolling();
    final names = await widget.getMasterEffects();
    var ids = await widget.getMasterEffectIds();
    if (ids.length != names.length) {
      ids = List<String>.from(names);
    }
    final keys = _buildStableEffectKeys(ids);
    final bypass = <bool>[];

    for (int i = 0; i < names.length; i++) {
      bypass.add(await widget.getMasterEffectBypassState(i));
    }

    setState(() {
      _effects = List<String>.from(names);
      _effectKeys = List<String>.from(keys);
      _bypassed = List<bool>.from(bypass);
    });
    widget.onHeightChanged?.call(_panelHeight);
  }

  void _moveDelayDivisionState(int from, int to) {
    if (from == to) return;

    final moved = _delayDivisionByEffect.remove(from);
    final next = <int, int>{};

    _delayDivisionByEffect.forEach((key, value) {
      var newKey = key;
      if (from < to) {
        if (key > from && key <= to) newKey = key - 1;
      } else {
        if (key >= to && key < from) newKey = key + 1;
      }
      next[newKey] = value;
    });

    if (moved != null) next[to] = moved;

    _delayDivisionByEffect
      ..clear()
      ..addAll(next);
  }

  void _applyLocalReorder(int oldIndex, int newIndex) {
    final movedName = _effects.removeAt(oldIndex);
    final movedKey = _effectKeys.removeAt(oldIndex);
    final movedBypass = _bypassed.removeAt(oldIndex);
    _effects.insert(newIndex, movedName);
    _effectKeys.insert(newIndex, movedKey);
    _bypassed.insert(newIndex, movedBypass);

    final selected = _selectedEffectIndex;
    if (selected != null) {
      if (selected == oldIndex) {
        _selectedEffectIndex = newIndex;
      } else if (oldIndex < newIndex &&
          selected > oldIndex &&
          selected <= newIndex) {
        _selectedEffectIndex = selected - 1;
      } else if (newIndex < oldIndex &&
          selected >= newIndex &&
          selected < oldIndex) {
        _selectedEffectIndex = selected + 1;
      }
    }

    _moveDelayDivisionState(oldIndex, newIndex);
  }

  int? _detectDelayDivision(double ms, double bpm) {
    const toleranceMs = 1.5;

    for (int i = 0; i < kDelayDivisions.length; i++) {
      final targetMs = beatsToMs(kDelayDivisions[i].beats, bpm);
      if ((ms - targetMs).abs() <= toleranceMs) {
        return i;
      }
    }
    return null; // Custom / free ms
  }

  Widget _buildDelayTimeParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
    required double bpm,
  }) {
    final msValue = (param['value'] as num).toDouble();
    final detectedIdx = _detectDelayDivision(msValue, bpm);
    final presetLabel =
        detectedIdx == null ? 'Custom' : kDelayDivisions[detectedIdx].label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header row ----
          Row(
            children: [
              Text(param['name'] as String,
                  style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),

              // ---- PRESET DROPDOWN ----
              DropdownButton<String>(
                value: presetLabel,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(
                    value: 'Custom',
                    child: Text(L10n.translate(context, 'Custom')),
                  ),
                  ...kDelayDivisions.map((d) =>
                      DropdownMenuItem(value: d.label, child: Text(d.label))),
                ],
                onChanged: (label) {
                  if (label == null || label == 'Custom') return;

                  final division =
                      kDelayDivisions.firstWhere((d) => d.label == label);
                  final newMs = beatsToMs(division.beats, bpm);

                  _paramDragStartValue = msValue;

                  setState(() {
                    param['value'] = newMs;
                  });

                  widget.setMasterEffectParam(
                      effectIndex, param['name'] as String, newMs);

                  widget.onMasterPluginParamCommit?.call(
                    effectIndex,
                    param['name'] as String,
                    _paramDragStartValue!,
                    newMs,
                  );

                  _paramDragStartValue = null;
                },
              ),
            ],
          ),

          // ---- MS SLIDER (ALWAYS SHOWN) ----
          Row(
            children: [
              Text((param['min'] as num).toDouble().toStringAsFixed(0),
                  style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final defaultValue = _paramDefaultAsDouble(param);
                    if (defaultValue == null) return;
                    final oldValue = (param['value'] as num).toDouble();
                    if ((oldValue - defaultValue).abs() < 1.0e-6) return;
                    setState(() => param['value'] = defaultValue);
                    widget.setMasterEffectParam(
                        effectIndex, param['name'] as String, defaultValue);
                    widget.onMasterPluginParamCommit?.call(
                      effectIndex,
                      param['name'] as String,
                      oldValue,
                      defaultValue,
                    );
                  },
                  child: Slider(
                    value: msValue.clamp((param['min'] as num).toDouble(),
                        (param['max'] as num).toDouble()),
                    min: (param['min'] as num).toDouble(),
                    max: (param['max'] as num).toDouble(),
                    divisions: 200,
                    label: '${msValue.toStringAsFixed(0)} ms',
                    onChangeStart: (_) {
                      _paramDragStartValue = msValue;
                    },
                    onChanged: (v) {
                      setState(() => param['value'] = v);
                      widget.setMasterEffectParam(
                          effectIndex, param['name'] as String, v);
                    },
                    onChangeEnd: (v) {
                      if (_paramDragStartValue == null) return;

                      widget.onMasterPluginParamCommit?.call(
                        effectIndex,
                        param['name'] as String,
                        _paramDragStartValue!,
                        v,
                      );
                      _paramDragStartValue = null;
                    },
                  ),
                ),
              ),
              Text((param['max'] as num).toDouble().toStringAsFixed(0),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitchShiftSemitonesParam({
    required BuildContext context,
    required Map<String, dynamic> param,
    required int effectIndex,
  }) {
    final paramName = param['name'] as String;
    final minV = ((param['min'] as num?)?.toDouble() ?? -12.0);
    final maxV = ((param['max'] as num?)?.toDouble() ?? 12.0);
    final rawV =
        ((param['value'] as num?)?.toDouble() ?? 0.0).clamp(minV, maxV);
    final defaultValue = _paramDefaultAsDouble(param);
    final divisions = math.max(1, (maxV - minV).round());

    void commitImmediate(double nextValue) {
      final oldValue = (param['value'] as num).toDouble();
      final clamped = nextValue.clamp(minV, maxV).toDouble();
      if ((oldValue - clamped).abs() < 1.0e-6) return;

      setState(() => param['value'] = clamped);
      widget.setMasterEffectParam(effectIndex, paramName, clamped);
      widget.onMasterPluginParamCommit?.call(
        effectIndex,
        paramName,
        oldValue,
        clamped,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(paramName, style: Theme.of(context).textTheme.bodyLarge),
          Row(
            children: [
              Text(
                minV.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    if (defaultValue == null) return;
                    commitImmediate(defaultValue);
                  },
                  child: Slider(
                    value: rawV,
                    min: minV,
                    max: maxV,
                    divisions: divisions,
                    label: '${rawV.toStringAsFixed(0)} st',
                    onChangeStart: (_) {
                      _paramDragStartValue = rawV;
                    },
                    onChanged: (v) {
                      final snapped = v.roundToDouble().clamp(minV, maxV);
                      setState(() => param['value'] = snapped);
                      widget.setMasterEffectParam(
                          effectIndex, paramName, snapped);
                    },
                    onChangeEnd: (v) {
                      if (_paramDragStartValue == null) return;
                      final snapped = v.roundToDouble().clamp(minV, maxV);
                      widget.onMasterPluginParamCommit?.call(
                        effectIndex,
                        paramName,
                        _paramDragStartValue!,
                        snapped,
                      );
                      _paramDragStartValue = null;
                    },
                  ),
                ),
              ),
              Text(
                maxV.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = rawV.roundToDouble() - 1.0;
                  commitImmediate(next);
                },
                icon: const Icon(Icons.remove, size: 18),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                    'pitch_master_${effectIndex}_${rawV.toStringAsFixed(2)}',
                  ),
                  initialValue: rawV.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    suffixText: 'st',
                  ),
                  onFieldSubmitted: (text) {
                    final parsed = double.tryParse(text.trim());
                    if (parsed == null) return;
                    commitImmediate(parsed);
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = rawV.roundToDouble() + 1.0;
                  commitImmediate(next);
                },
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startCompressorMetering({required int effectIndex}) {
    _stopCompressorMetering();
    _compMeterRunning = true;

    _compMeterTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!mounted || !_compMeterRunning) return;

      try {
        final arr = await widget.getMasterCompressorMeter(effectIndex);
        if (!mounted || !_compMeterRunning) return;

        // arr = [inL, inR, grDb, outL, outR]
        final next = CompressorStripFrame(
          inL: (arr.isNotEmpty ? arr[0] : 0).toDouble(),
          inR: (arr.length > 1 ? arr[1] : 0).toDouble(),
          grDb: (arr.length > 2 ? arr[2] : 0).toDouble(),
          outL: (arr.length > 3 ? arr[3] : 0).toDouble(),
          outR: (arr.length > 4 ? arr[4] : 0).toDouble(),
        ).clamp();

        // smoothing (tweak: 0.18 smoother, 0.35 snappier)
        const t = 0.25;

        setState(() {
          _compFrame = next;
          _compFrameSmoothed =
              CompressorStripFrame.lerp(_compFrameSmoothed, next, t);
        });
      } catch (_) {
        // swallow polling errors
      }
    });
  }

  void _stopCompressorMetering() {
    _compMeterRunning = false;
    _compMeterTimer?.cancel();
    _compMeterTimer = null;

    _compFrame = CompressorStripFrame.zero;
    _compFrameSmoothed = CompressorStripFrame.zero;
  }

  void _startEqWaveformPolling({required int effectIndex}) {
    _stopEqWaveformPolling();
    _eqWaveformRunning = true;
    _refreshEqAnalyzerSampleRate();

    _eqWaveformTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (!mounted || !_eqWaveformRunning) return;

      try {
        final arr = await widget.getMasterEqWaveform(effectIndex, 1024);
        if (!mounted || !_eqWaveformRunning) return;
        final spectrum = _EqSpectrumAnalyzer.computeSpectrumDb(arr);
        setState(() {
          _eqWaveform = arr;
          _eqSpectrumDb = spectrum;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      }
    });
  }

  void _stopEqWaveformPolling() {
    _eqWaveformRunning = false;
    _eqWaveformTimer?.cancel();
    _eqWaveformTimer = null;
    _eqWaveform = const <double>[];
    _eqSpectrumDb = const <double>[];
  }

  Future<void> _refreshEqAnalyzerSampleRate() async {
    try {
      final sr = await JuceAudioEngine.getHostSampleRate();
      if (!mounted || !_eqWaveformRunning) return;
      if ((sr - _eqAnalyzerSampleRate).abs() > 1.0) {
        setState(() {
          _eqAnalyzerSampleRate = sr;
        });
      }
    } catch (_) {
      // keep default if host SR is unavailable on this platform
    }
  }

  @override
  Widget build(BuildContext context) {
    // If an effect is selected → show parameter page (no inner scroll)
    if (_selectedEffectIndex != null) {
      return _buildEffectParamsPage(context, _selectedEffectIndex!);
    }
    return Container(
      // color: const Color(0xFF151A26).withOpacity(0.9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetChip("Concert Hall"),
                  const SizedBox(width: 6),
                  _buildPresetChip("Echoes"),
                  const SizedBox(width: 6),
                  _buildPresetChip("LoFi Effect"),
                  // const SizedBox(width: 6),
                  // _buildPresetChip("Heavy Crunch"), // TODO: TEMP
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          const SizedBox(height: 12),
          Flexible(
            fit: FlexFit.loose,
            child: ReorderableListView(
              // shrinkWrap: true,
              // physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (int i = 0; i < _effects.length; i++)
                  _buildMasterEffectTile(i)
              ],
              onReorder: (oldIndex, newIndex) async {
                if (oldIndex < 0 || oldIndex >= _effects.length) return;
                if (newIndex > oldIndex) newIndex--;
                newIndex = newIndex.clamp(0, _effects.length - 1);
                if (oldIndex == newIndex) return;

                setState(() {
                  _applyLocalReorder(oldIndex, newIndex);
                });

                try {
                  await widget.reorderMasterEffects(oldIndex, newIndex);
                } catch (_) {
                  await _loadEffects();
                }
              },
            ),
          ),
          if (_effects.length < maxNumEffects)
            Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: _buildAddTile()),
        ],
      ),
    );
  }

  // === SAME UI HELPERS AS RowEffectsPanel (presets, effect tile, add tile, params UI) ===
  // You can copy your existing _buildPresetChip, _buildEffectTile, etc.

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = <String>[]; // you can re-lock LoFi / Heavy later
    final isLocked = _isBasicTier && lockedPresets.contains(name);

    return ActionChip(
      materialTapTargetSize:
          MaterialTapTargetSize.shrinkWrap, // ← smaller hitbox
      padding: const EdgeInsets.symmetric(
          horizontal: 4, vertical: 4), // ← shrink chip
      visualDensity:
          const VisualDensity(horizontal: -2, vertical: -2), // ← reduce height
      backgroundColor: isLocked
          ? const Color.fromARGB(255, 61, 61, 61)
          : const Color.fromARGB(255, 88, 107, 200),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.translate(context, name),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
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
      onPressed: isLocked ? null : () => _handlePresetLoading(context, name),
    );
  }

  Future<void> _handlePresetLoading(
      BuildContext context, String presetName) async {
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
            child: Text(
              L10n.translate(context, 'Cancel'),
              style: const TextStyle(color: Color.fromARGB(255, 218, 218, 218)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Load Preset')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // BUILD 'BEFORE' SNAPSHOT
    final beforeSnapshots = <EffectSnapshot>[];
    for (int i = 0; i < _effects.length; i++) {
      final params = await widget.getMasterPluginParameters(i);
      final isBypassed = await widget.getMasterEffectBypassState(i);
      beforeSnapshots.add(EffectSnapshot(_effects[i], isBypassed,
          {for (final p in params) p['name']: p['value']}));
    }
    final before = MasterEffectsSnapshot(beforeSnapshots);

    // Remove all current effects on this row
    // while (_effects.isNotEmpty) {
    //   await widget.removeMasterEffect(0);
    //   _effects.removeAt(0);
    //   _bypassed.removeAt(0);
    // }

    for (int i = 0; i < _effects.length; i++) {
      await widget.removeMasterEffect(0, _effects[0], true);
    }
    await _loadEffects();

    // Apply preset chain using callbacks
    switch (presetName) {
      case 'Concert Hall':
        await widget.insertMasterEffect('Reverb');
        await widget.setMasterEffectParam(0, 'Room Size', 53);
        await widget.setMasterEffectParam(0, 'Mix', 20);
        break;

      case 'Echoes':
        await widget.insertMasterEffect('Reverb');
        await widget.setMasterEffectParam(0, 'Room Size', 40);
        await widget.setMasterEffectParam(0, 'Mix', 20);
        await widget.insertMasterEffect('Delay');
        await widget.setMasterEffectParam(1, 'Delay Time', 400);
        await widget.setMasterEffectParam(1, 'Feedback', 30);
        await widget.setMasterEffectParam(1, 'Mix', 30);
        break;

      case 'LoFi Effect':
        await widget.insertMasterEffect('EQ Parametric');
        await widget.setMasterEffectParam(0, 'LPF Frequency', 2600.0);
        await widget.insertMasterEffect('Distortion');
        await widget.setMasterEffectParam(1, 'Drive', 50);
        await widget.setMasterEffectParam(1, 'Mix', 85);
        await widget.setMasterEffectParam(1, 'Anger', 1);
        await widget.setMasterEffectParam(1, 'LPF Frequency', 2800.0);
        await widget.setMasterEffectParam(1, 'Distortion Type', "Mode 3");
        break;

      case 'Heavy Crunch':
        await widget.insertMasterEffect('Distortion');
        await widget.setMasterEffectParam(0, 'Drive', 100);
        await widget.setMasterEffectParam(0, 'Mix', 100);
        await widget.setMasterEffectParam(0, 'Anger', 1);
        await widget.setMasterEffectParam(0, 'Volume', 12);
        await widget.setMasterEffectParam(0, 'Pre Shape', 3.0);
        await widget.setMasterEffectParam(0, 'Distortion Type', "Mode 3");
        break;

      default:
        debugPrint('⚠️ No matching preset logic for: $presetName');
    }

    await _loadEffects();

    // BUILD 'AFTER' SNAPSHOT
    final afterSnapshots = <EffectSnapshot>[];
    for (int i = 0; i < _effects.length; i++) {
      final params = await widget.getMasterPluginParameters(i);
      final isBypassed = await widget.getMasterEffectBypassState(i);
      afterSnapshots.add(EffectSnapshot(_effects[i], isBypassed,
          {for (final p in params) p['name']: p['value']}));
    }
    final after = MasterEffectsSnapshot(afterSnapshots);
    widget.onMasterPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildMasterEffectTile(int idx) {
    return ListTile(
      key: ValueKey("master_effect_${_effectKeys[idx]}"),
      contentPadding: EdgeInsets.zero,

      // only this handle starts reorder drag
      leading: ReorderableDragStartListener(
        index: idx,
        child: const Padding(
          padding: EdgeInsets.only(left: 6.0, right: 6.0),
          child: Icon(Icons.drag_handle),
        ),
      ),

      title: Text(
        _effects[idx],
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15),
      ),

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: !_bypassed[idx],
            onChanged: (active) async {
              final shouldBypass = !active;
              final previous = _bypassed[idx];

              setState(() => _bypassed[idx] = shouldBypass);
              try {
                await widget.bypassMasterEffect(idx, shouldBypass);
              } catch (_) {
                if (!mounted) return;
                setState(() => _bypassed[idx] = previous);
              }
            },
            activeColor: const Color.fromARGB(255, 231, 231, 231),
            inactiveThumbColor: const Color.fromARGB(255, 186, 186, 186),
            inactiveTrackColor: const Color.fromARGB(255, 235, 235, 235),
            activeTrackColor: const Color.fromARGB(255, 54, 54, 54),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color.fromARGB(255, 255, 164, 164)),
            onPressed: () => _confirmRemove(idx),
          ),
        ],
      ),

      onTap: () => _openPluginParams(idx),
    );
  }

  Widget _buildAddTile() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      key: const ValueKey("add_effect"),
      leading: const Icon(Icons.add_circle_outline),
      title: Text(
        L10n.translate(context, 'Add Effect'),
        style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15),
      ),
      onTap: _showAddEffectModal,
    );
  }

  Future<void> _confirmRemove(int idx) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.translate(context, 'Delete Effect?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              L10n.translate(context, 'Cancel'),
              style: const TextStyle(color: Color.fromARGB(255, 218, 218, 218)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete'),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (yes == true) {
      await widget.removeMasterEffect(idx, _effects[idx], false);
      _delayDivisionByEffect.remove(idx);
      await _loadEffects();
    }
  }

  // =========================
  // ADD EFFECT MODAL (dialog, can scroll internally)
  // =========================

  Future<void> _showAddEffectModal() async {
    final plugins = await widget.scanPlugins();
    const allowedInBasic = [
      "Gain",
      "EQ 3-Band",
      "Compressor",
      "Limiter",
      "Clipper",
      "De-Esser",
      "Distortion",
      "Delay",
      "Reverb",
      "EQ Parametric",
      "Pitch Shift",
      "Chorus",
      "Vibrato",
    ];
    const fxChoices = [
      "Gain",
      "EQ 3-Band",
      "Compressor",
      "Limiter",
      "Clipper",
      "De-Esser",
      "Distortion",
      "Delay",
      "Reverb",
      "EQ Parametric",
      "Pitch Shift",
      "Chorus",
      "Vibrato",
    ];

    // Dialog can use scrolling; this is outside the row panel layout.
    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A2233),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: Container(
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0xFF121927),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.zero,
                indicator: BoxDecoration(
                  color: const Color(0xFF2D3F5D),
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  const Tab(text: 'FX'),
                  Tab(text: L10n.translate(context, 'On Device')),
                ],
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 390,
              child: TabBarView(
                children: [
                  ListView.separated(
                    itemCount: fxChoices.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      final name = fxChoices[i];
                      final isAllowed =
                          _isProEntitled || allowedInBasic.contains(name);
                      return GestureDetector(
                        onTap: isAllowed
                            ? () async {
                                Navigator.pop(context);
                                await widget.insertMasterEffect(name);
                                await _loadEffects();
                              }
                            : null,
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            title: Text(
                              name,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.2),
                            ),
                            trailing: isAllowed
                                ? null
                                : const Icon(Icons.lock,
                                    size: 18, color: Colors.white70),
                          ),
                        ),
                      );
                    },
                  ),
                  ListView.separated(
                    itemCount: plugins.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      final meta = plugins[i];
                      final path = (meta['id'] ?? '').toString();
                      if (path.isEmpty) return const SizedBox.shrink();
                      final name = (meta['name'] ?? path).toString();
                      final format = (meta['format'] ?? '').toString();
                      final manufacturer =
                          (meta['manufacturer'] ?? '').toString();
                      final details = <String>[
                        if (format.isNotEmpty) format,
                        if (manufacturer.isNotEmpty) manufacturer,
                      ];
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        title: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13.2),
                        ),
                        subtitle: details.isEmpty
                            ? null
                            : Text(
                                details.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.62),
                                  fontSize: 11.0,
                                ),
                              ),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.insertMasterEffect(path);
                          await _loadEffects();
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================
  // PARAMETERS PAGE (inline, no internal scroll)
  // =========================

  Future<void> _openPluginParams(int idx) async {
    setState(() {
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
    });

    if (_showsDynamicsReductionMeter(_effects[idx])) {
      _startCompressorMetering(effectIndex: idx);
    } else {
      _stopCompressorMetering();
    }
    if (_effects[idx] == 'EQ Parametric' || _effects[idx] == 'EQ 3-Band') {
      _startEqWaveformPolling(effectIndex: idx);
    } else {
      _stopEqWaveformPolling();
    }

    var params = await widget.getMasterPluginParameters(idx);
    if (params.isEmpty) {
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        params = await widget.getMasterPluginParameters(idx);
        if (params.isNotEmpty) break;
      }
    }

    // Basic-mode param filtering
    //TODO: TEMP limit plugin parameters no matter what "mode"
    if (_isKnownSubscriptionMode) {
      switch (_effects[idx]) {
        case 'Reverb':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Room Size', 'Mix', 'Predelay'].contains(name);
          }).toList();
          break;

        case 'Limiter':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Threshold', 'Release', 'Ceiling'].contains(name);
          }).toList();
          break;

        case 'Clipper':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Threshold', 'Ceiling'].contains(name);
          }).toList();
          break;

        case 'EQ Parametric':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return [
              'HPF Frequency',
              'HPF Slope',
              'Band 1 Frequency',
              'Band 1 Gain',
              'Band 1 Q',
              'Band 2 Frequency',
              'Band 2 Gain',
              'Band 2 Q',
              'Band 3 Frequency',
              'Band 3 Gain',
              'Band 3 Q',
              'Band 4 Frequency',
              'Band 4 Gain',
              'Band 4 Q',
              'LPF Slope',
              'LPF Frequency',
            ].contains(name);
          }).toList();
          break;

        case 'EQ 3-Band':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Low Gain', 'Mid Gain', 'High Gain'].contains(name);
          }).toList();
          break;

        case 'Delay':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Delay Time', 'Feedback', 'Mix'].contains(name);
          }).toList();
          break;
      }
    }

    if (!mounted) return;
    setState(() {
      _currentParams = params;
      _paramsLoading = false;
    });
  }

  Widget _buildEffectParamsPage(BuildContext context, int idx) {
    if (_paramsLoading) {
      return SizedBox(
        height: 180,
        child: Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).primaryColor)),
      );
    }

    final effectName = _effects[idx];

    // Special layout for EQ Parametric
    if (effectName == 'EQ Parametric' && _currentParams.isNotEmpty) {
      final pHPF = _paramByName(_currentParams, 'HPF Frequency');
      final pHPFSlope = _paramByName(_currentParams, 'HPF Slope');
      final pLPF = _paramByName(_currentParams, 'LPF Frequency');
      final pLPFSlope = _paramByName(_currentParams, 'LPF Slope');
      final pB1Freq = _paramByName(_currentParams, 'Band 1 Frequency');
      final pB1 = _paramByName(_currentParams, 'Band 1 Gain');
      final pB1Q = _paramByName(_currentParams, 'Band 1 Q');
      final pB2Freq = _paramByName(_currentParams, 'Band 2 Frequency');
      final pB2 = _paramByName(_currentParams, 'Band 2 Gain');
      final pB2Q = _paramByName(_currentParams, 'Band 2 Q');
      final pB3Freq = _paramByName(_currentParams, 'Band 3 Frequency');
      final pB3 = _paramByName(_currentParams, 'Band 3 Gain');
      final pB3Q = _paramByName(_currentParams, 'Band 3 Q');
      final pB4Freq = _paramByName(_currentParams, 'Band 4 Frequency');
      final pB4 = _paramByName(_currentParams, 'Band 4 Gain');
      final pB4Q = _paramByName(_currentParams, 'Band 4 Q');

      final hpfHz = (pHPF?['value'] as num?)?.toDouble() ?? 80.0;
      final lpfHz = (pLPF?['value'] as num?)?.toDouble() ?? 12000.0;
      final hpfSlopeDbOct = _parseSlopeDbPerOct(pHPFSlope?['value']);
      final lpfSlopeDbOct = _parseSlopeDbPerOct(pLPFSlope?['value']);

      final bandGains = [
        (pB1?['value'] as num?)?.toDouble() ?? 0,
        (pB2?['value'] as num?)?.toDouble() ?? 0,
        (pB3?['value'] as num?)?.toDouble() ?? 0,
        (pB4?['value'] as num?)?.toDouble() ?? 0,
      ];
      final bandFreqs = [
        (pB1Freq?['value'] as num?)?.toDouble() ?? 60.0,
        (pB2Freq?['value'] as num?)?.toDouble() ?? 400.0,
        (pB3Freq?['value'] as num?)?.toDouble() ?? 2000.0,
        (pB4Freq?['value'] as num?)?.toDouble() ?? 8000.0,
      ];
      final bandQs = [
        (pB1Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB2Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB3Q?['value'] as num?)?.toDouble() ?? 1.0,
        (pB4Q?['value'] as num?)?.toDouble() ?? 1.0,
      ];

      _EqFaderSpec? buildEqFader(
        Map<String, dynamic>? param, {
        required String label,
        required String unit,
        bool logarithmic = false,
      }) {
        if (param == null) return null;
        final name = param['name'] as String;
        return _EqFaderSpec(
          label: label,
          value: (param['value'] as num).toDouble(),
          min: (param['min'] as num).toDouble(),
          max: (param['max'] as num).toDouble(),
          defaultValue: _paramDefaultAsDouble(param),
          logarithmic: logarithmic,
          unit: unit,
          onChangeStart: (_) {
            _EQParamStartValue = (param['value'] as num).toDouble();
          },
          onChanged: (v) {
            setState(() => param['value'] = v);
            widget.setMasterEffectParam(idx, name, v);
          },
          onChangeEnd: (v) {
            final startValue = _EQParamStartValue;
            if (startValue == null) return;
            widget.onMasterPluginParamCommit?.call(
              idx,
              name,
              startValue,
              v,
            );
            _EQParamStartValue = null;
          },
          onReset: () {
            final defaultValue = _paramDefaultAsDouble(param);
            if (defaultValue == null) return;
            final oldValue = (param['value'] as num).toDouble();
            if ((oldValue - defaultValue).abs() < 1.0e-6) return;
            setState(() => param['value'] = defaultValue);
            widget.setMasterEffectParam(idx, name, defaultValue);
            widget.onMasterPluginParamCommit?.call(
              idx,
              name,
              oldValue,
              defaultValue,
            );
          },
        );
      }

      final gainFaders = <_EqFaderSpec>[
        if (pB1 != null) buildEqFader(pB1, label: 'Band 1', unit: 'dB')!,
        if (pB2 != null) buildEqFader(pB2, label: 'Band 2', unit: 'dB')!,
        if (pB3 != null) buildEqFader(pB3, label: 'Band 3', unit: 'dB')!,
        if (pB4 != null) buildEqFader(pB4, label: 'Band 4', unit: 'dB')!,
      ];
      final frequencyFaders = <_EqFaderSpec>[
        if (pB1Freq != null)
          buildEqFader(
            pB1Freq,
            label: 'Band 1',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB2Freq != null)
          buildEqFader(
            pB2Freq,
            label: 'Band 2',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB3Freq != null)
          buildEqFader(
            pB3Freq,
            label: 'Band 3',
            unit: 'Hz',
            logarithmic: true,
          )!,
        if (pB4Freq != null)
          buildEqFader(
            pB4Freq,
            label: 'Band 4',
            unit: 'Hz',
            logarithmic: true,
          )!,
      ];
      final qFaders = <_EqFaderSpec>[
        if (pB1Q != null) buildEqFader(pB1Q, label: 'Band 1', unit: 'Q')!,
        if (pB2Q != null) buildEqFader(pB2Q, label: 'Band 2', unit: 'Q')!,
        if (pB3Q != null) buildEqFader(pB3Q, label: 'Band 3', unit: 'Q')!,
        if (pB4Q != null) buildEqFader(pB4Q, label: 'Band 4', unit: 'Q')!,
      ];
      final hpfSlopeChoices =
          (pHPFSlope != null && pHPFSlope['type'] == 'choice')
              ? _extractChoiceValues(pHPFSlope)
              : const <String>[];
      final lpfSlopeChoices =
          (pLPFSlope != null && pLPFSlope['type'] == 'choice')
              ? _extractChoiceValues(pLPFSlope)
              : const <String>[];
      final hpfSlopeCurrent = hpfSlopeChoices.isEmpty
          ? null
          : (hpfSlopeChoices.contains(pHPFSlope?['value']?.toString())
              ? pHPFSlope!['value'].toString()
              : hpfSlopeChoices.first);
      final lpfSlopeCurrent = lpfSlopeChoices.isEmpty
          ? null
          : (lpfSlopeChoices.contains(pLPFSlope?['value']?.toString())
              ? pLPFSlope!['value'].toString()
              : lpfSlopeChoices.first);
      final frequencyExtraControls = <Widget>[
        if (pHPF != null)
          _buildEqFilterControlRow(
            context: context,
            label: 'HPF',
            value: (pHPF['value'] as num).toDouble(),
            min: (pHPF['min'] as num).toDouble(),
            max: (pHPF['max'] as num).toDouble(),
            logarithmic: true,
            onChangeStart: (_) {
              _EQParamStartValue = (pHPF['value'] as num).toDouble();
            },
            onChanged: (v) {
              setState(() => pHPF['value'] = v);
              widget.setMasterEffectParam(idx, pHPF['name'] as String, v);
            },
            onChangeEnd: (v) {
              final startValue = _EQParamStartValue;
              if (startValue == null) return;
              widget.onMasterPluginParamCommit?.call(
                idx,
                pHPF['name'] as String,
                startValue,
                v,
              );
              _EQParamStartValue = null;
            },
            onDoubleTapReset: () {
              final defaultValue = _paramDefaultAsDouble(pHPF);
              if (defaultValue == null) return;
              final oldValue = (pHPF['value'] as num).toDouble();
              if ((oldValue - defaultValue).abs() < 1.0e-6) return;
              setState(() => pHPF['value'] = defaultValue);
              widget.setMasterEffectParam(
                  idx, pHPF['name'] as String, defaultValue);
              widget.onMasterPluginParamCommit?.call(
                idx,
                pHPF['name'] as String,
                oldValue,
                defaultValue,
              );
            },
            slopeChoices: hpfSlopeChoices,
            selectedSlope: hpfSlopeCurrent,
            onSlopeChanged: (picked) {
              if (pHPFSlope == null) return;
              final oldVal = pHPFSlope['value'];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => pHPFSlope['value'] = picked);
              });
              widget.setMasterEffectParam(
                  idx, pHPFSlope['name'] as String, picked);
              widget.onMasterPluginParamCommit?.call(
                idx,
                pHPFSlope['name'] as String,
                oldVal,
                picked,
              );
            },
          ),
        if (pHPF != null && pLPF != null) const SizedBox(height: 6),
        if (pLPF != null)
          _buildEqFilterControlRow(
            context: context,
            label: 'LPF',
            value: (pLPF['value'] as num).toDouble(),
            min: (pLPF['min'] as num).toDouble(),
            max: (pLPF['max'] as num).toDouble(),
            logarithmic: true,
            onChangeStart: (_) {
              _EQParamStartValue = (pLPF['value'] as num).toDouble();
            },
            onChanged: (v) {
              setState(() => pLPF['value'] = v);
              widget.setMasterEffectParam(idx, pLPF['name'] as String, v);
            },
            onChangeEnd: (v) {
              final startValue = _EQParamStartValue;
              if (startValue == null) return;
              widget.onMasterPluginParamCommit?.call(
                idx,
                pLPF['name'] as String,
                startValue,
                v,
              );
              _EQParamStartValue = null;
            },
            onDoubleTapReset: () {
              final defaultValue = _paramDefaultAsDouble(pLPF);
              if (defaultValue == null) return;
              final oldValue = (pLPF['value'] as num).toDouble();
              if ((oldValue - defaultValue).abs() < 1.0e-6) return;
              setState(() => pLPF['value'] = defaultValue);
              widget.setMasterEffectParam(
                  idx, pLPF['name'] as String, defaultValue);
              widget.onMasterPluginParamCommit?.call(
                idx,
                pLPF['name'] as String,
                oldValue,
                defaultValue,
              );
            },
            slopeChoices: lpfSlopeChoices,
            selectedSlope: lpfSlopeCurrent,
            onSlopeChanged: (picked) {
              if (pLPFSlope == null) return;
              final oldVal = pLPFSlope['value'];
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => pLPFSlope['value'] = picked);
              });
              widget.setMasterEffectParam(
                  idx, pLPFSlope['name'] as String, picked);
              widget.onMasterPluginParamCommit?.call(
                idx,
                pLPFSlope['name'] as String,
                oldVal,
                picked,
              );
            },
          ),
      ];

      return SingleChildScrollView(
        // You may want to add padding here if not already handled by internal widgets
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with back button
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints.tightFor(width: 26, height: 26),
                  splashRadius: 14,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: () {
                    _stopEqWaveformPolling();
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    effectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(1.00),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    final changes = <Map<String, dynamic>>[];
                    for (final p in _currentParams) {
                      final next = _paramDefaultValue(p);
                      if (next == null) continue;
                      final old = p['value'];
                      if (_paramValuesEqual(old, next)) continue;
                      changes.add({
                        'param': p,
                        'old': old,
                        'next': next,
                      });
                    }
                    if (changes.isEmpty) return;

                    setState(() {
                      for (final c in changes) {
                        (c['param'] as Map<String, dynamic>)['value'] =
                            c['next'];
                      }
                    });

                    for (final c in changes) {
                      final p = c['param'] as Map<String, dynamic>;
                      final oldVal = c['old'];
                      final newVal = c['next'];
                      final name = p['name'] as String;
                      await widget.setMasterEffectParam(idx, name, newVal);
                      widget.onMasterPluginParamCommit?.call(
                        idx,
                        name,
                        oldVal,
                        newVal,
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 28),
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(
              height: 1,
              thickness: 0.9,
              color: Color.fromARGB(213, 104, 104, 104),
            ),
            const SizedBox(height: 6),

            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth, // EQ shrinks inside row
                  ),
                  child: Column(
                    children: [
                      // EQ Preview
                      _EqPreviewFull(
                          hpfHz: hpfHz,
                          lpfHz: lpfHz,
                          hpfSlopeDbOct: hpfSlopeDbOct,
                          lpfSlopeDbOct: lpfSlopeDbOct,
                          bandGains: bandGains,
                          bandFreqs: bandFreqs,
                          bandQs: bandQs,
                          waveformSamples: _eqWaveform,
                          spectrumDb: _eqSpectrumDb,
                          analyzerSampleRate: _eqAnalyzerSampleRate),
                      const SizedBox(height: 16),
                      _buildEqParametricTabs(
                        context: context,
                        gainFaders: gainFaders,
                        frequencyFaders: frequencyFaders,
                        qFaders: qFaders,
                        frequencyExtraControls: frequencyExtraControls,
                        selectedTabIndex: _eqParametricTabIndex,
                        onTabChanged: (index) {
                          if (_eqParametricTabIndex == index) return;
                          setState(() => _eqParametricTabIndex = index);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    if (effectName == 'EQ 3-Band' && _currentParams.isNotEmpty) {
      final pLow = _paramByName(_currentParams, 'Low Gain');
      final pMid = _paramByName(_currentParams, 'Mid Gain');
      final pHigh = _paramByName(_currentParams, 'High Gain');

      final gains = [
        (pLow?['value'] as num?)?.toDouble() ?? 0.0,
        (pMid?['value'] as num?)?.toDouble() ?? 0.0,
        (pHigh?['value'] as num?)?.toDouble() ?? 0.0,
      ];

      // Must match JUCE fixed centers for accurate preview
      final freqs = [140.0, 1200.0, 8000.0];

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints.tightFor(width: 26, height: 26),
                  splashRadius: 14,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: () {
                    _stopEqWaveformPolling();
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    effectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(1.00),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(
              height: 1,
              thickness: 0.9,
              color: Color.fromARGB(213, 104, 104, 104),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    children: [
                      _Eq3Preview(
                        bandGains: gains,
                        bandFreqs: freqs,
                        waveformSamples: _eqWaveform,
                        spectrumDb: _eqSpectrumDb,
                        analyzerSampleRate: _eqAnalyzerSampleRate,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: _eqRowHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (pLow != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Low',
                                  onLongPressStart: (globalPos) =>
                                      _showAutomateParameterSheet(
                                    effectIndex: idx,
                                    effectName: effectName,
                                    paramId: (pLow['id'] ?? pLow['name'] ?? '')
                                        .toString()
                                        .trim(),
                                    paramName: (pLow['name'] ?? 'Low')
                                        .toString()
                                        .trim(),
                                    haloKeys: _paramHaloKeys(
                                      effectIndex: idx,
                                      effectName: effectName,
                                      paramName:
                                          (pLow['name'] ?? 'Low').toString(),
                                    ),
                                    anchorGlobalPos: globalPos,
                                  ),
                                  value: (pLow['value'] as num).toDouble(),
                                  min: (pLow['min'] as num).toDouble(),
                                  max: (pLow['max'] as num).toDouble(),
                                  defaultValue: _paramDefaultAsDouble(pLow),
                                  unit: 'dB',
                                  onDoubleTapReset: () {
                                    final defaultValue =
                                        _paramDefaultAsDouble(pLow);
                                    if (defaultValue == null) return;
                                    final oldValue =
                                        (pLow['value'] as num).toDouble();
                                    if ((oldValue - defaultValue).abs() <
                                        1.0e-6) {
                                      return;
                                    }
                                    setState(
                                        () => pLow['value'] = defaultValue);
                                    widget.setMasterEffectParam(idx,
                                        pLow['name'] as String, defaultValue);
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pLow['name'] as String,
                                      oldValue,
                                      defaultValue,
                                    );
                                  },
                                  onChangeStart: (v) {
                                    _EQParamStartValue =
                                        (pLow['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pLow['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pLow['value'] = v);
                                    widget.setMasterEffectParam(
                                        idx, pLow['name'] as String, v);
                                  },
                                ),
                              if (pMid != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Mid',
                                  onLongPressStart: (globalPos) =>
                                      _showAutomateParameterSheet(
                                    effectIndex: idx,
                                    effectName: effectName,
                                    paramId: (pMid['id'] ?? pMid['name'] ?? '')
                                        .toString()
                                        .trim(),
                                    paramName: (pMid['name'] ?? 'Mid')
                                        .toString()
                                        .trim(),
                                    haloKeys: _paramHaloKeys(
                                      effectIndex: idx,
                                      effectName: effectName,
                                      paramName:
                                          (pMid['name'] ?? 'Mid').toString(),
                                    ),
                                    anchorGlobalPos: globalPos,
                                  ),
                                  value: (pMid['value'] as num).toDouble(),
                                  min: (pMid['min'] as num).toDouble(),
                                  max: (pMid['max'] as num).toDouble(),
                                  defaultValue: _paramDefaultAsDouble(pMid),
                                  unit: 'dB',
                                  onDoubleTapReset: () {
                                    final defaultValue =
                                        _paramDefaultAsDouble(pMid);
                                    if (defaultValue == null) return;
                                    final oldValue =
                                        (pMid['value'] as num).toDouble();
                                    if ((oldValue - defaultValue).abs() <
                                        1.0e-6) {
                                      return;
                                    }
                                    setState(
                                        () => pMid['value'] = defaultValue);
                                    widget.setMasterEffectParam(idx,
                                        pMid['name'] as String, defaultValue);
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pMid['name'] as String,
                                      oldValue,
                                      defaultValue,
                                    );
                                  },
                                  onChangeStart: (v) {
                                    _EQParamStartValue =
                                        (pMid['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pMid['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pMid['value'] = v);
                                    widget.setMasterEffectParam(
                                        idx, pMid['name'] as String, v);
                                  },
                                ),
                              if (pHigh != null)
                                _verticalFader(
                                  context: context,
                                  label: 'High',
                                  onLongPressStart: (globalPos) =>
                                      _showAutomateParameterSheet(
                                    effectIndex: idx,
                                    effectName: effectName,
                                    paramId:
                                        (pHigh['id'] ?? pHigh['name'] ?? '')
                                            .toString()
                                            .trim(),
                                    paramName: (pHigh['name'] ?? 'High')
                                        .toString()
                                        .trim(),
                                    haloKeys: _paramHaloKeys(
                                      effectIndex: idx,
                                      effectName: effectName,
                                      paramName:
                                          (pHigh['name'] ?? 'High').toString(),
                                    ),
                                    anchorGlobalPos: globalPos,
                                  ),
                                  value: (pHigh['value'] as num).toDouble(),
                                  min: (pHigh['min'] as num).toDouble(),
                                  max: (pHigh['max'] as num).toDouble(),
                                  defaultValue: _paramDefaultAsDouble(pHigh),
                                  unit: 'dB',
                                  onDoubleTapReset: () {
                                    final defaultValue =
                                        _paramDefaultAsDouble(pHigh);
                                    if (defaultValue == null) return;
                                    final oldValue =
                                        (pHigh['value'] as num).toDouble();
                                    if ((oldValue - defaultValue).abs() <
                                        1.0e-6) {
                                      return;
                                    }
                                    setState(
                                        () => pHigh['value'] = defaultValue);
                                    widget.setMasterEffectParam(idx,
                                        pHigh['name'] as String, defaultValue);
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pHigh['name'] as String,
                                      oldValue,
                                      defaultValue,
                                    );
                                  },
                                  onChangeStart: (v) {
                                    _EQParamStartValue =
                                        (pHigh['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pHigh['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pHigh['value'] = v);
                                    widget.setMasterEffectParam(
                                        idx, pHigh['name'] as String, v);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    // Generic parameter page (no scroll, full height in row)
    return SingleChildScrollView(
      // You may want to add padding here if not already handled by internal widgets
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 26, height: 26),
                splashRadius: 14,
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () {
                  _stopCompressorMetering();
                  _stopEqWaveformPolling();
                  setState(() {
                    _selectedEffectIndex = null;
                    _currentParams = [];
                  });
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  effectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(1.00),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(
            height: 1,
            thickness: 0.9,
            color: Color.fromARGB(213, 104, 104, 104),
          ),
          const SizedBox(height: 6),

          if (_showsDynamicsReductionMeter(effectName)) ...[
            // _buildCompressorMeterStrip(),
            const SizedBox(height: 10),
            GainReductionSliderMeterHorizontal(
              grDb: _compFrameSmoothed.grDb,
              maxDb: 24,
              title: _dynamicsReductionMeterTitle(effectName),
            ),
            const SizedBox(height: 10),
          ],

          // Params straight in Column
          for (var param in _currentParams) ...[
            if (_effects[idx] == 'Delay' && param['name'] == 'Delay Time') ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: _buildDelayTimeParam(
                    context: context,
                    param: param,
                    effectIndex: idx,
                    bpm: widget.projectBpm),
              ),
            ] else if (_isGainVolumeParam(effectName, param)) ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: _buildGainVolumeParam(
                  context: context,
                  param: param,
                  effectIndex: idx,
                ),
              ),
            ] else if (_isPitchShiftSemitonesParam(effectName, param)) ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: _buildPitchShiftSemitonesParam(
                  context: context,
                  param: param,
                  effectIndex: idx,
                ),
              ),
            ] else if (param['type'] == 'float') ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(param['name'] as String,
                          style: Theme.of(context).textTheme.bodyLarge),
                      Row(
                        children: [
                          Text(
                            (param['min'] as num).toDouble().toStringAsFixed(2),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                showValueIndicator: ShowValueIndicator.always,
                                valueIndicatorTextStyle: const TextStyle(
                                  color: Color.fromARGB(255, 0, 0, 0),
                                  fontSize: 12,
                                ),
                              ),
                              child: (() {
                                final effectName = _effects[idx];
                                final paramName = param['name'] as String;

                                final minV = (param['min'] as num).toDouble();
                                final maxV = (param['max'] as num).toDouble();
                                final rawV = (param['value'] as num)
                                    .toDouble()
                                    .clamp(minV, maxV);

                                final skew =
                                    _getParamSkew(effectName, paramName);

                                double toNorm(double v) =>
                                    ((v - minV) / (maxV - minV))
                                        .clamp(0.0, 1.0);

                                double fromNorm(double t) =>
                                    minV + (maxV - minV) * t.clamp(0.0, 1.0);

                                final norm = toNorm(rawV);
                                final sliderPos = (skew == null)
                                    ? norm
                                    : math.pow(norm, skew).toDouble();

                                return GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onDoubleTap: () {
                                    final defaultValue =
                                        _paramDefaultAsDouble(param);
                                    if (defaultValue == null) return;
                                    final clampedDefault = defaultValue
                                        .clamp(minV, maxV)
                                        .toDouble();
                                    final oldValue =
                                        (param['value'] as num).toDouble();
                                    if ((oldValue - clampedDefault).abs() <
                                        1.0e-6) {
                                      return;
                                    }
                                    setState(
                                        () => param['value'] = clampedDefault);
                                    widget.setMasterEffectParam(
                                        idx, paramName, clampedDefault);
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      paramName,
                                      oldValue,
                                      clampedDefault,
                                    );
                                  },
                                  child: Slider(
                                    value: sliderPos,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 200,
                                    label: rawV.toStringAsFixed(2),
                                    onChangeStart: (_) {
                                      _paramDragStartValue = rawV;
                                    },
                                    onChanged: (p) {
                                      final t = p.clamp(0.0, 1.0);
                                      final newNorm = (skew == null)
                                          ? t
                                          : math.pow(t, 1.0 / skew!).toDouble();
                                      final v = fromNorm(newNorm);

                                      setState(() => param['value'] = v);
                                      widget.setMasterEffectParam(
                                          idx, paramName, v);
                                    },
                                    onChangeEnd: (p) {
                                      if (_paramDragStartValue == null) return;

                                      final t = p.clamp(0.0, 1.0);
                                      final newNorm = (skew == null)
                                          ? t
                                          : math.pow(t, 1.0 / skew!).toDouble();
                                      final v = fromNorm(newNorm);

                                      widget.onMasterPluginParamCommit?.call(
                                        idx,
                                        paramName,
                                        _paramDragStartValue!,
                                        v,
                                      );

                                      _paramDragStartValue = null;
                                    },
                                  ),
                                );
                              })(),
                            ),
                          ),
                          Text(
                            (param['max'] as num).toDouble().toStringAsFixed(2),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (param['type'] == 'bool') ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(param['name'] as String),
                  value: param['value'] as bool,
                  onChanged: (v) {
                    setState(() => param['value'] = v);
                    widget.setMasterEffectParam(
                        idx, param['name'] as String, v);
                    widget.onMasterPluginParamCommit
                        ?.call(idx, param['name'] as String, !v, v);
                  },
                ),
              ),
            ] else if (param['type'] == 'choice') ...[
              (() {
                final keys =
                    param.keys.where((k) => k.startsWith('choice_')).toList()
                      ..sort((a, b) {
                        final ai = int.parse(a.split('_')[1]);
                        final bi = int.parse(b.split('_')[1]);
                        return ai.compareTo(bi);
                      });
                final choices = keys.map((k) => param[k] as String).toList();
                final current = param['value'] as String;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
                  child: _wrapAutomatableParam(
                    effectIndex: idx,
                    effectName: effectName,
                    param: param,
                    borderRadius: BorderRadius.circular(10),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(param['name'] as String),
                      trailing: Text(current,
                          style: Theme.of(context).textTheme.bodyLarge),
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
                                  onPressed: () => Navigator.pop(ctx, c));
                            }).toList(),
                          ),
                        );
                        if (picked != null) {
                          final oldVal = param['value'];
                          setState(() => param['value'] = picked);
                          widget.setMasterEffectParam(
                              idx, param['name'] as String, picked);
                          widget.onMasterPluginParamCommit?.call(
                              idx, param['name'] as String, oldVal, picked);
                        }
                      },
                    ),
                  ),
                );
              })(),
            ] else ...[
              _wrapAutomatableParam(
                effectIndex: idx,
                effectName: effectName,
                param: param,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(param['name'] as String),
                    trailing: Text("${param['value']}"),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---- Sizes for the vertical faders/rows (tweak to taste) ----
const double _eqFaderHeight = 156;
const double _eqRowHeight = _eqFaderHeight + 60; // space for labels above/below

class _EqFaderSpec {
  final String label;
  final double value;
  final double min;
  final double max;
  final double? defaultValue;
  final String unit;
  final bool logarithmic;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onReset;

  const _EqFaderSpec({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.unit,
    required this.logarithmic,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });
}

Widget _buildEqParametricTabs({
  required BuildContext context,
  required List<_EqFaderSpec> gainFaders,
  required List<_EqFaderSpec> frequencyFaders,
  required List<_EqFaderSpec> qFaders,
  required int selectedTabIndex,
  required ValueChanged<int> onTabChanged,
  List<Widget> frequencyExtraControls = const [],
}) {
  return _EqParametricTabsWidget(
    gainFaders: gainFaders,
    frequencyFaders: frequencyFaders,
    qFaders: qFaders,
    selectedTabIndex: selectedTabIndex,
    onTabChanged: onTabChanged,
    frequencyExtraControls: frequencyExtraControls,
  );
}

class _EqParametricTabsWidget extends StatefulWidget {
  final List<_EqFaderSpec> gainFaders;
  final List<_EqFaderSpec> frequencyFaders;
  final List<_EqFaderSpec> qFaders;
  final int selectedTabIndex;
  final ValueChanged<int> onTabChanged;
  final List<Widget> frequencyExtraControls;

  const _EqParametricTabsWidget({
    required this.gainFaders,
    required this.frequencyFaders,
    required this.qFaders,
    required this.selectedTabIndex,
    required this.onTabChanged,
    required this.frequencyExtraControls,
  });

  @override
  State<_EqParametricTabsWidget> createState() =>
      _EqParametricTabsWidgetState();
}

class _EqParametricTabsWidgetState extends State<_EqParametricTabsWidget>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 3, vsync: this, initialIndex: widget.selectedTabIndex);
  }

  @override
  void didUpdateWidget(covariant _EqParametricTabsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabController.index != widget.selectedTabIndex) {
      _tabController.animateTo(widget.selectedTabIndex,
          duration: Duration.zero);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frequencyExtraHeight =
            widget.frequencyExtraControls.isEmpty ? 0.0 : 94.0;
        final tabBodyHeight = _eqRowHeight +
            (widget.selectedTabIndex == 1 ? frequencyExtraHeight : 0.0);

        return Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0x22000000),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33888888)),
              ),
              child: TabBar(
                controller: _tabController,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: const Color(0x335C94D9),
                  borderRadius: BorderRadius.circular(7),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFFB9B9B9),
                onTap: widget.onTabChanged,
                tabs: const [
                  Tab(height: 30, text: 'Gain'),
                  Tab(height: 30, text: 'Frequency'),
                  Tab(height: 30, text: 'Q'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: tabBodyHeight,
              child: KeyedSubtree(
                key: ValueKey<int>(widget.selectedTabIndex),
                child: widget.selectedTabIndex == 0
                    ? _buildEqTabPage(
                        context: context,
                        faders: widget.gainFaders,
                      )
                    : widget.selectedTabIndex == 1
                        ? _buildEqTabPage(
                            context: context,
                            faders: widget.frequencyFaders,
                            extraControls: widget.frequencyExtraControls,
                          )
                        : _buildEqTabPage(
                            context: context,
                            faders: widget.qFaders,
                          ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _buildEqTabPage({
  required BuildContext context,
  required List<_EqFaderSpec> faders,
  List<Widget> extraControls = const [],
}) {
  return Column(
    children: [
      _buildEqFaderRow(context: context, faders: faders),
      if (extraControls.isNotEmpty) const SizedBox(height: 2),
      ...extraControls,
    ],
  );
}

Widget _buildEqFaderRow({
  required BuildContext context,
  required List<_EqFaderSpec> faders,
}) {
  if (faders.isEmpty) {
    return SizedBox(
      height: _eqRowHeight,
      child: Center(
        child: Text(
          'No controls',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  return SizedBox(
    height: _eqRowHeight,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final f in faders)
            _verticalFader(
              context: context,
              label: f.label,
              value: f.value,
              min: f.min,
              max: f.max,
              defaultValue: f.defaultValue,
              logarithmic: f.logarithmic,
              unit: f.unit,
              onChangeStart: f.onChangeStart,
              onChanged: f.onChanged,
              onChangeEnd: f.onChangeEnd,
              onDoubleTapReset: f.onReset,
            ),
        ],
      ),
    ),
  );
}

Widget _buildEqChoiceSelector({
  required BuildContext context,
  required String label,
  required List<String> choices,
  required String currentChoice,
  required ValueChanged<String> onChanged,
}) {
  final compactLabel = label
      .replaceAll(' Frequency', '')
      .replaceAll(' Slope', '')
      .replaceAll('Band ', 'B');

  return Container(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0x15000000),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x33888888)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            compactLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Flexible(
          child: PopupMenuButton<String>(
            initialValue: currentChoice,
            tooltip: '',
            padding: EdgeInsets.zero,
            onSelected: onChanged,
            itemBuilder: (_) => choices
                .map((choice) => PopupMenuItem<String>(
                      value: choice,
                      child: Text(choice),
                    ))
                .toList(growable: false),
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x1F000000),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x33888888)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      currentChoice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildEqFilterControlRow({
  required BuildContext context,
  required String label,
  required double value,
  required double min,
  required double max,
  required bool logarithmic,
  required ValueChanged<double> onChangeStart,
  required ValueChanged<double> onChanged,
  required ValueChanged<double> onChangeEnd,
  VoidCallback? onDoubleTapReset,
  List<String> slopeChoices = const [],
  String? selectedSlope,
  ValueChanged<String>? onSlopeChanged,
}) {
  final clampedValue = value.clamp(min, max).toDouble();
  final sliderValue = logarithmic
      ? _toLogPos(clampedValue, min, max)
      : ((clampedValue - min) / (max - min)).clamp(0.0, 1.0);

  return Container(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0x15000000),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x33888888)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          flex: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: onDoubleTapReset,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                showValueIndicator: ShowValueIndicator.onDrag,
                trackHeight: 4,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                valueIndicatorTextStyle: const TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 11,
                ),
              ),
              child: Slider(
                min: 0.0,
                max: 1.0,
                divisions: 220,
                value: sliderValue,
                label: '${_fmtHz(clampedValue)} Hz',
                onChangeStart: (p) {
                  final v = logarithmic
                      ? _fromLogPos(p, min, max)
                      : (min + (max - min) * p.clamp(0.0, 1.0));
                  onChangeStart(v);
                },
                onChanged: (p) {
                  final v = logarithmic
                      ? _fromLogPos(p, min, max)
                      : (min + (max - min) * p.clamp(0.0, 1.0));
                  onChanged(v);
                },
                onChangeEnd: (p) {
                  final v = logarithmic
                      ? _fromLogPos(p, min, max)
                      : (min + (max - min) * p.clamp(0.0, 1.0));
                  onChangeEnd(v);
                },
              ),
            ),
          ),
        ),
        if (slopeChoices.isNotEmpty &&
            selectedSlope != null &&
            onSlopeChanged != null) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 84,
            child: PopupMenuButton<String>(
              initialValue: selectedSlope,
              tooltip: '',
              padding: EdgeInsets.zero,
              onSelected: onSlopeChanged,
              itemBuilder: (_) => slopeChoices
                  .map((choice) =>
                      PopupMenuItem<String>(value: choice, child: Text(choice)))
                  .toList(growable: false),
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x1F000000),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x33888888)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedSlope,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _buildEqSlopeControlsRow({
  Widget? left,
  Widget? right,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 360;
      if (isNarrow) {
        return Column(
          children: [
            if (left != null) left,
            if (left != null && right != null) const SizedBox(height: 6),
            if (right != null) right,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: left ?? const SizedBox.shrink()),
          const SizedBox(width: 8),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      );
    },
  );
}

List<String> _extractChoiceValues(Map<String, dynamic> param) {
  final keys = param.keys.where((k) => k.startsWith('choice_')).toList()
    ..sort((a, b) {
      final ai = int.tryParse(a.split('_').last) ?? 0;
      final bi = int.tryParse(b.split('_').last) ?? 0;
      return ai.compareTo(bi);
    });

  return keys.map((k) => param[k].toString()).toList();
}

double? _paramDefaultAsDouble(Map<String, dynamic> param) {
  final raw = param['defaultValue'];
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+\-\.]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed != null) return parsed;
  }

  final name = (param['name']?.toString() ?? '').trim();
  const knownDefaults = <String, double>{
    'HPF Frequency': 80.0,
    'LPF Frequency': 12000.0,
    'Band 1 Frequency': 60.0,
    'Band 2 Frequency': 400.0,
    'Band 3 Frequency': 2000.0,
    'Band 4 Frequency': 8000.0,
    'Band 1 Gain': 0.0,
    'Band 2 Gain': 0.0,
    'Band 3 Gain': 0.0,
    'Band 4 Gain': 0.0,
    'Band 1 Q': 1.0,
    'Band 2 Q': 1.0,
    'Band 3 Q': 1.0,
    'Band 4 Q': 1.0,
    'Low Gain': 0.0,
    'Mid Gain': 0.0,
    'High Gain': 0.0,
  };
  final fallback = knownDefaults[name];
  if (fallback != null) {
    final min = (param['min'] as num?)?.toDouble();
    final max = (param['max'] as num?)?.toDouble();
    if (min != null && max != null) {
      return fallback.clamp(min, max).toDouble();
    }
    return fallback;
  }

  final min = (param['min'] as num?)?.toDouble();
  final max = (param['max'] as num?)?.toDouble();
  if (min != null && max != null) {
    return (min + max) * 0.5;
  }
  return null;
}

dynamic _paramDefaultValue(Map<String, dynamic> param) {
  final type = (param['type']?.toString() ?? '').toLowerCase();
  final raw = param['defaultValue'];
  final hasChoices = param.keys.any((k) => k.startsWith('choice_'));
  final hasNumericRange =
      param['min'] is num && param['max'] is num && param['value'] is num;

  if (type == 'choice' || hasChoices) {
    final choices = _extractChoiceValues(param);
    if (choices.isEmpty) return null;
    if (raw is String) {
      if (choices.contains(raw)) return raw;
      final idx = int.tryParse(raw);
      if (idx != null && idx >= 0 && idx < choices.length) return choices[idx];
    }
    if (raw is num) {
      final idx = raw.toInt();
      if (idx >= 0 && idx < choices.length) return choices[idx];
    }
    return choices.first;
  }

  if (type == 'bool') {
    if (raw is bool) return raw;
    if (raw is num) return raw.toInt() != 0;
    if (raw is String) {
      final lower = raw.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return false;
  }

  if (type == 'float' ||
      type == 'double' ||
      type == 'int' ||
      hasNumericRange ||
      raw is num ||
      raw is String) {
    return _paramDefaultAsDouble(param);
  }

  return raw;
}

bool _paramValuesEqual(dynamic a, dynamic b) {
  if (a is num && b is num) {
    return (a.toDouble() - b.toDouble()).abs() < 1.0e-6;
  }
  return a == b;
}

double _parseSlopeDbPerOct(dynamic slopeValue) {
  if (slopeValue is num) {
    final idx = slopeValue.toInt().clamp(0, 3);
    return 12.0 * (idx + 1);
  }
  if (slopeValue is String) {
    final match = RegExp(r'(\d+)').firstMatch(slopeValue);
    if (match != null) {
      final parsed = double.tryParse(match.group(1)!);
      if (parsed != null) return parsed;
    }
  }
  return 12.0;
}

Widget _buildEqAuxSlider({
  required BuildContext context,
  required String label,
  required double value,
  required double min,
  required double max,
  required bool logarithmic,
  required String unit,
  required ValueChanged<double> onChangeStart,
  required ValueChanged<double> onChanged,
  required ValueChanged<double> onChangeEnd,
}) {
  final clampedValue = value.clamp(min, max).toDouble();
  final sliderValue = logarithmic
      ? _toLogPos(clampedValue, min, max)
      : ((clampedValue - min) / (max - min)).clamp(0.0, 1.0);

  String prettyValue(double v) {
    if (unit == 'Hz') return _fmtHz(v);
    if (unit == 'Q') return v.toStringAsFixed(2);
    if (unit == 'dB') return '${v.toStringAsFixed(1)} dB';
    return v.toStringAsFixed(2);
  }

  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              prettyValue(clampedValue),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          min: 0.0,
          max: 1.0,
          divisions: 220,
          value: sliderValue,
          onChangeStart: (p) {
            final v = logarithmic
                ? _fromLogPos(p, min, max)
                : (min + (max - min) * p.clamp(0.0, 1.0));
            onChangeStart(v);
          },
          onChanged: (p) {
            final v = logarithmic
                ? _fromLogPos(p, min, max)
                : (min + (max - min) * p.clamp(0.0, 1.0));
            onChanged(v);
          },
          onChangeEnd: (p) {
            final v = logarithmic
                ? _fromLogPos(p, min, max)
                : (min + (max - min) * p.clamp(0.0, 1.0));
            onChangeEnd(v);
          },
        ),
      ],
    ),
  );
}

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

double _toQuadPos(double v, double min, double max) {
  final t = ((v - min) / (max - min)).clamp(0.0, 1.0);
  return math.sqrt(t); // inverse curve
}

double _fromQuadPos(double t, double min, double max) {
  final curved = t * t;
  return min + (max - min) * curved;
}

double _toSkewPos(double value, double min, double max, double skew) {
  final t = ((value - min) / (max - min)).clamp(0.0, 1.0);

  // inverse mapping: slider position
  return math.pow(t, 1.0 / skew).toDouble();
}

double _fromSkewPos(double t, double min, double max, double skew) {
  final curved = math.pow(t.clamp(0.0, 1.0), skew).toDouble();

  return min + (max - min) * curved;
}

// Some of these values come from JUCE/NativeEffects.cpp
// effectName → (paramName → skewFactor)
const Map<String, Map<String, double>> kEffectParamSkew = {
  "Distortion": {
    "HPF Frequency": 0.25,
    "LPF Frequency": 0.25,
  },
  "Delay": {
    "HPF Frequency": 0.35,
  },
};

double? _getParamSkew(String effectName, String paramName) {
  return kEffectParamSkew[effectName]?[paramName];
}

String _fmtHz(double hz) {
  if (hz >= 1000) {
    final k = hz / 1000.0;
    final kRounded = k.roundToDouble();
    if ((k - kRounded).abs() < 0.05) {
      return '${kRounded.toInt()}k';
    }
    // 1 decimal up to 9.9k, then integer
    return k < 10 ? '${k.toStringAsFixed(1)}k' : '${k.toStringAsFixed(0)}k';
  }
  return hz.round().toString();
}

class _EqSpectrumAnalyzer {
  static final Map<int, FFT> _fftCache = <int, FFT>{};

  static FFT _fftForSize(int size) =>
      _fftCache.putIfAbsent(size, () => FFT(size));

  static int _nextPowerOfTwo(int v) {
    var n = 1;
    while (n < v) {
      n <<= 1;
    }
    return n;
  }

  static double _log10(num x) => math.log(x) / math.ln10;

  static List<double> computeSpectrumDb(List<double> samples) {
    if (samples.length < 64) return const <double>[];

    var fftSize = _nextPowerOfTwo(samples.length);
    fftSize = fftSize.clamp(128, 2048);

    final input = List<double>.filled(fftSize, 0.0, growable: false);
    final srcStart = (samples.length - fftSize).clamp(0, samples.length);
    final copyLen = math.min(fftSize, samples.length);
    final readOffset = srcStart + (samples.length - srcStart - copyLen);
    for (int i = 0; i < copyLen; i++) {
      final window =
          0.5 - 0.5 * math.cos((2.0 * math.pi * i) / (copyLen - 1).toDouble());
      input[i] = samples[readOffset + i] * window;
    }

    final fft = _fftForSize(fftSize);
    final freqDomain = fft.realFft(input);
    final bins = freqDomain.length;
    if (bins <= 1) return const <double>[];

    final out = List<double>.filled(bins, -120.0, growable: false);
    for (int i = 1; i < bins; i++) {
      final c = freqDomain[i];
      final mag = math.sqrt(c.x * c.x + c.y * c.y) / (fftSize * 0.5);
      out[i] = 20.0 * _log10(mag + 1.0e-12);
    }

    for (int i = 1; i < bins - 1; i++) {
      out[i] = (out[i - 1] + out[i] + out[i + 1]) / 3.0;
    }

    return out;
  }
}

class _EqPreviewFull extends StatelessWidget {
  final double hpfHz;
  final double lpfHz;
  final double hpfSlopeDbOct;
  final double lpfSlopeDbOct;
  final List<double> bandGains; // dB values
  final List<double> bandFreqs; // Hz centers
  final List<double> bandQs; // Q values
  final List<double> waveformSamples; // post-EQ waveform
  final List<double> spectrumDb; // precomputed analyzer spectrum
  final double analyzerSampleRate;

  const _EqPreviewFull({
    super.key,
    required this.hpfHz,
    required this.lpfHz,
    required this.hpfSlopeDbOct,
    required this.lpfSlopeDbOct,
    required this.bandGains,
    required this.bandFreqs,
    required this.bandQs,
    required this.waveformSamples,
    required this.spectrumDb,
    required this.analyzerSampleRate,
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
              hpfSlopeDbOct: hpfSlopeDbOct,
              lpfSlopeDbOct: lpfSlopeDbOct,
              bandGains: bandGains,
              bandFreqs: bandFreqs,
              bandQs: bandQs,
              waveformSamples: waveformSamples,
              spectrumDb: spectrumDb,
              analyzerSampleRate: analyzerSampleRate),
        ),
      ),
    );
  }
}

class _EqPreviewFullPainter extends CustomPainter {
  final double hpfHz, lpfHz;
  final double hpfSlopeDbOct, lpfSlopeDbOct;
  final List<double> bandGains;
  final List<double> bandFreqs;
  final List<double> bandQs;
  final List<double> waveformSamples;
  final List<double> spectrumDb;
  final double analyzerSampleRate;

  _EqPreviewFullPainter(
      {required this.hpfHz,
      required this.lpfHz,
      required this.hpfSlopeDbOct,
      required this.lpfSlopeDbOct,
      required this.bandGains,
      required this.bandFreqs,
      required this.bandQs,
      required this.waveformSamples,
      required this.spectrumDb,
      required this.analyzerSampleRate});

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  double _log10(num x) => math.log(x) / math.ln10;

  // map Hz → log X position
  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF);
    final t =
        (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
    return (t.clamp(0.0, 1.0)) * w;
  }

  double _butterworthHighpassDb({
    required double f,
    required double fc,
    required double slopeDbOct,
  }) {
    final ff = f.clamp(1.0, 96000.0);
    final fcc = fc.clamp(1.0, 96000.0);
    final order = (slopeDbOct / 6.0).round().clamp(1, 16);
    final ratio = fcc / ff;
    final denom = 1.0 + math.pow(ratio, 2 * order);
    return -10.0 * _log10(denom);
  }

  double _butterworthLowpassDb({
    required double f,
    required double fc,
    required double slopeDbOct,
  }) {
    final ff = f.clamp(1.0, 96000.0);
    final fcc = fc.clamp(1.0, 96000.0);
    final order = (slopeDbOct / 6.0).round().clamp(1, 16);
    final ratio = ff / fcc;
    final denom = 1.0 + math.pow(ratio, 2 * order);
    return -10.0 * _log10(denom);
  }

  double _sampleSpectrumAtHz({
    required List<double> spectrumDb,
    required double hz,
    required double binHz,
    required double nyquist,
  }) {
    if (spectrumDb.isEmpty || hz <= 0 || binHz <= 0 || hz > nyquist) {
      return -120.0;
    }

    final idx = hz / binHz;
    final maxIdx = spectrumDb.length - 1;
    if (idx <= 1) return spectrumDb[1];
    if (idx >= maxIdx) return spectrumDb[maxIdx];

    final i0 = idx.floor();
    final i1 = math.min(maxIdx, i0 + 1);
    final t = idx - i0;
    return spectrumDb[i0] * (1.0 - t) + spectrumDb[i1] * t;
  }

  void _drawFrequencyRegions(Canvas canvas, double w, double h) {
    const regionEdgesHz = [20.0, 80.0, 300.0, 1200.0, 5000.0, 20000.0];
    const markerHz = [80.0, 300.0, 1200.0, 5000.0, 12000.0];

    final divider = Paint()
      ..color = const Color(0x2A8F8F8F)
      ..strokeWidth = 1.0;

    for (int i = 0; i < regionEdgesHz.length - 1; i++) {
      final f0 = regionEdgesHz[i];
      final f1 = regionEdgesHz[i + 1];
      final x0 = _xForHz(f0, w);
      final x1 = _xForHz(f1, w);
      final shade = Paint()
        ..color =
            (i.isEven ? const Color(0x0DFFFFFF) : const Color(0x05000000));
      canvas.drawRect(Rect.fromLTRB(x0, 0, x1, h), shade);
      canvas.drawLine(Offset(x0, 0), Offset(x0, h), divider);
    }
    final lastEdgeX = _xForHz(regionEdgesHz.last, w);
    canvas.drawLine(Offset(lastEdgeX, 0), Offset(lastEdgeX, h), divider);

    for (final hz in markerHz) {
      final x = _xForHz(hz, w);
      canvas.drawLine(Offset(x, 0), Offset(x, h), divider);
      final tp = TextPainter(
        text: TextSpan(
          text: _fmtHz(hz),
          style: const TextStyle(
            color: Color(0x88D8D8D8),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final textX = (x - tp.width * 0.5).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(textX, h - tp.height - 2));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 1 || h <= 1) return;

    _drawFrequencyRegions(canvas, w, h);

    // baseline axis
    final axis = Paint()
      ..color = const Color(0x55888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);
    final zeroLine = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), zeroLine);

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

      db += _butterworthHighpassDb(
        f: f.toDouble(),
        fc: hpf,
        slopeDbOct: hpfSlopeDbOct,
      );
      db += _butterworthLowpassDb(
        f: f.toDouble(),
        fc: lpf,
        slopeDbOct: lpfSlopeDbOct,
      );

      // Add band gains as bumps
      for (int i = 0; i < bandFreqs.length; i++) {
        final gain = bandGains[i];
        if (gain.abs() < 0.1) continue;

        final fc = bandFreqs[i];
        final q =
            (i < bandQs.length ? bandQs[i] : 1.0).clamp(0.1, 20.0).toDouble();
        final widthOctaves = (1.6 / q).clamp(0.12, 2.5);

        // gaussian-like bump
        final d = (math.log(f / fc) / math.ln2); // distance in octaves
        final shape = math.exp(-(d * d) / (2.0 * widthOctaves * widthOctaves));
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

    if (spectrumDb.length > 2) {
      final spectrumPath = Path();
      final fftSize = (spectrumDb.length - 1) * 2;
      final sr = analyzerSampleRate > 1000.0 ? analyzerSampleRate : 44100.0;
      final nyquist = sr * 0.5;
      final binHz = sr / fftSize;

      var peakDb = -120.0;
      for (int i = 1; i < spectrumDb.length; i++) {
        peakDb = math.max(peakDb, spectrumDb[i]);
      }
      final floorDb = math.max(-110.0, peakDb - 70.0);
      final ceilDb = math.max(floorDb + 6.0, peakDb);

      for (int px = 0; px < w; px++) {
        final t = px / (w - 1);
        final hz = _minF * math.pow(_maxF / _minF, t).toDouble();
        final db = _sampleSpectrumAtHz(
          spectrumDb: spectrumDb,
          hz: hz,
          binHz: binHz,
          nyquist: nyquist,
        );
        final n = ((db - floorDb) / (ceilDb - floorDb)).clamp(0.0, 1.0);
        final y = (h - 2) - (h * 0.86 * n);
        if (px == 0) {
          spectrumPath.moveTo(px.toDouble(), y);
        } else {
          spectrumPath.lineTo(px.toDouble(), y);
        }
      }

      final spectrumFill = Path.from(spectrumPath)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        spectrumFill,
        Paint()
          ..color = const Color(0x223DADEB)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        spectrumPath,
        Paint()
          ..color = const Color(0xAA72C8F2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..isAntiAlias = true,
      );
    }

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
        old.hpfSlopeDbOct != hpfSlopeDbOct ||
        old.lpfSlopeDbOct != lpfSlopeDbOct ||
        old.bandGains != bandGains ||
        old.bandFreqs != bandFreqs ||
        old.bandQs != bandQs ||
        old.waveformSamples != waveformSamples ||
        old.spectrumDb != spectrumDb ||
        old.analyzerSampleRate != analyzerSampleRate;
  }
}

class _Eq3Preview extends StatelessWidget {
  final List<double> bandGains; // [low, mid, high] dB
  final List<double> bandFreqs; // [lowFc, midFc, highFc] Hz
  final List<double> waveformSamples; // post-EQ waveform
  final List<double> spectrumDb; // precomputed analyzer spectrum
  final double analyzerSampleRate;

  const _Eq3Preview({
    super.key,
    required this.bandGains,
    required this.bandFreqs,
    required this.waveformSamples,
    required this.spectrumDb,
    required this.analyzerSampleRate,
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
          painter: _Eq3PreviewPainter(
            lowGainDb: bandGains[0],
            midGainDb: bandGains[1],
            highGainDb: bandGains[2],
            lowFc: bandFreqs[0],
            midFc: bandFreqs[1],
            highFc: bandFreqs[2],
            waveformSamples: waveformSamples,
            spectrumDb: spectrumDb,
            analyzerSampleRate: analyzerSampleRate,
          ),
        ),
      ),
    );
  }
}

class _Eq3PreviewPainter extends CustomPainter {
  final double lowGainDb, midGainDb, highGainDb;
  final double lowFc, midFc, highFc;
  final List<double> waveformSamples;
  final List<double> spectrumDb;
  final double analyzerSampleRate;

  _Eq3PreviewPainter({
    required this.lowGainDb,
    required this.midGainDb,
    required this.highGainDb,
    required this.lowFc,
    required this.midFc,
    required this.highFc,
    required this.waveformSamples,
    required this.spectrumDb,
    required this.analyzerSampleRate,
  });

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF);
    final t =
        (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
    return (t.clamp(0.0, 1.0)) * w;
  }

  double _log2(double x) => math.log(x) / math.ln2;

  // Smooth shelf transition across ~1 octave around Fc
  double _shelfContributionDb({
    required double f,
    required double fc,
    required double gainDb,
    required bool isLowShelf,
  }) {
    if (gainDb.abs() < 0.01) return 0.0;

    // distance in octaves from Fc
    final d = _log2(f / fc);

    // sigmoid-ish curve in octave domain
    // low shelf: below Fc -> near full gain, above -> 0
    // high shelf: above Fc -> near full gain, below -> 0
    final x = isLowShelf ? (-d) : (d);
    final t = 1.0 / (1.0 + math.exp(-x * 3.0)); // 3.0 = slope softness
    return gainDb * t;
  }

  // Broad bell (gaussian in octave domain)
  double _bellContributionDb(
      {required double f, required double fc, required double gainDb}) {
    if (gainDb.abs() < 0.01) return 0.0;

    final d = _log2(f / fc); // octaves away
    final width = 1.1; // larger = wider bell (broad)
    final shape = math.exp(-(d * d) / (2 * width * width));
    return gainDb * shape;
  }

  void _drawHzLabel(Canvas canvas, double x, double hz, double h) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: "${_fmtHz(hz)}",
        style: const TextStyle(
          color: Color.fromARGB(134, 187, 187, 187),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // ✅ Bottom aligned label
    final offset = Offset(
      x - textPainter.width / 2,
      h - textPainter.height - 2, // bottom padding
    );

    textPainter.paint(canvas, offset);
  }

  double _sampleSpectrumAtHz({
    required List<double> spectrumDb,
    required double hz,
    required double binHz,
    required double nyquist,
  }) {
    if (spectrumDb.isEmpty || hz <= 0 || binHz <= 0 || hz > nyquist) {
      return -120.0;
    }

    final idx = hz / binHz;
    final maxIdx = spectrumDb.length - 1;
    if (idx <= 1) return spectrumDb[1];
    if (idx >= maxIdx) return spectrumDb[maxIdx];

    final i0 = idx.floor();
    final i1 = math.min(maxIdx, i0 + 1);
    final t = idx - i0;
    return spectrumDb[i0] * (1.0 - t) + spectrumDb[i1] * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 1 || h <= 1) return;

    final axis = Paint()
      ..color = const Color(0x55888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);

    // faint center line (0 dB)
    final midLine = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), midLine);

    // band markers (optional but helps “visual accuracy”)
    final marker = Paint()
      ..color = const Color(0x33888888)
      ..strokeWidth = 1;
    // canvas.drawLine(Offset(_xForHz(lowFc, w), 0), Offset(_xForHz(lowFc, w), h), marker);
    // canvas.drawLine(Offset(_xForHz(midFc, w), 0), Offset(_xForHz(midFc, w), h), marker);
    // canvas.drawLine(Offset(_xForHz(highFc, w), 0), Offset(_xForHz(highFc, w), h), marker);
    final xLow = _xForHz(lowFc, w);
    final xMid = _xForHz(midFc, w);
    final xHigh = _xForHz(highFc, w);

    // Marker lines
    canvas.drawLine(Offset(xLow, 0), Offset(xLow, h), marker);
    canvas.drawLine(Offset(xMid, 0), Offset(xMid, h), marker);
    canvas.drawLine(Offset(xHigh, 0), Offset(xHigh, h), marker);

    // Frequency labels
    _drawHzLabel(canvas, xLow, lowFc, h);
    _drawHzLabel(canvas, xMid, midFc, h);
    _drawHzLabel(canvas, xHigh, highFc, h);

    final path = Path();
    for (int px = 0; px < w; px++) {
      final f = _minF * math.pow(_maxF / _minF, px / w);

      double db = 0.0;
      db += _shelfContributionDb(
          f: f, fc: lowFc, gainDb: lowGainDb, isLowShelf: true);
      db += _bellContributionDb(f: f, fc: midFc, gainDb: midGainDb);
      db += _shelfContributionDb(
          f: f, fc: highFc, gainDb: highGainDb, isLowShelf: false);

      // map dB (-24..+24) to canvas height
      final y = h * 0.5 - (db.clamp(-24.0, 24.0) / 24.0) * (h * 0.4);

      if (px == 0) {
        path.moveTo(px.toDouble(), y);
      } else {
        path.lineTo(px.toDouble(), y);
      }
    }

    final fillPaint = Paint()
      ..color = const Color(0x33B03A2E)
      ..style = PaintingStyle.fill;
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    if (spectrumDb.length > 2) {
      final spectrumPath = Path();
      final fftSize = (spectrumDb.length - 1) * 2;
      final sr = analyzerSampleRate > 1000.0 ? analyzerSampleRate : 44100.0;
      final nyquist = sr * 0.5;
      final binHz = sr / fftSize;

      var peakDb = -120.0;
      for (int i = 1; i < spectrumDb.length; i++) {
        peakDb = math.max(peakDb, spectrumDb[i]);
      }
      final floorDb = math.max(-110.0, peakDb - 70.0);
      final ceilDb = math.max(floorDb + 6.0, peakDb);

      for (int px = 0; px < w; px++) {
        final t = px / (w - 1);
        final hz = _minF * math.pow(_maxF / _minF, t).toDouble();
        final db = _sampleSpectrumAtHz(
          spectrumDb: spectrumDb,
          hz: hz,
          binHz: binHz,
          nyquist: nyquist,
        );
        final n = ((db - floorDb) / (ceilDb - floorDb)).clamp(0.0, 1.0);
        final y = (h - 2) - (h * 0.86 * n);
        if (px == 0) {
          spectrumPath.moveTo(px.toDouble(), y);
        } else {
          spectrumPath.lineTo(px.toDouble(), y);
        }
      }

      final spectrumFill = Path.from(spectrumPath)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        spectrumFill,
        Paint()
          ..color = const Color(0x223DADEB)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        spectrumPath,
        Paint()
          ..color = const Color(0xAA72C8F2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..isAntiAlias = true,
      );
    }

    final strokePaint = Paint()
      ..color = const Color(0xFFB03A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _Eq3PreviewPainter old) {
    return old.lowGainDb != lowGainDb ||
        old.midGainDb != midGainDb ||
        old.highGainDb != highGainDb ||
        old.lowFc != lowFc ||
        old.midFc != midFc ||
        old.highFc != highFc ||
        old.waveformSamples != waveformSamples ||
        old.spectrumDb != spectrumDb ||
        old.analyzerSampleRate != analyzerSampleRate;
  }
}

Widget _verticalFader({
  required BuildContext context,
  required String label,
  required double value,
  required double min,
  required double max,
  double? defaultValue,
  int? divisions,
  required ValueChanged<double> onChangeStart,
  onChanged,
  onChangeEnd,
  VoidCallback? onDoubleTapReset,
  ValueChanged<Offset>? onLongPressStart,
  String? unit, // e.g. "Hz"
  bool logarithmic = false,
  double width = 56, // 👈 new
}) {
  final pos = logarithmic
      ? _toLogPos(value, min, max)
      : ((value.clamp(min, max) - min) / (max - min));

  final labelText = (unit == 'Hz')
      ? '${_fmtHz(value)} Hz'
      : (unit == 'Q')
          ? '${value.toStringAsFixed(2)} Q'
          : (unit == 'dB')
              ? '${value.toStringAsFixed(1)} dB'
              : (unit == null
                  ? value.toStringAsFixed(0)
                  : '${value.toStringAsFixed(0)} $unit');

  return _EqVerticalFader(
    width: width,
    label: label,
    labelText: labelText,
    pos: pos,
    min: min,
    max: max,
    logarithmic: logarithmic,
    divisions: divisions ?? 200,
    onChangeStart: onChangeStart,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    onDoubleTapReset: (defaultValue != null && onDoubleTapReset != null)
        ? onDoubleTapReset
        : null,
    onLongPressStart: onLongPressStart,
  );
}

class _EqVerticalFader extends StatefulWidget {
  final double width;
  final String label;
  final String labelText;
  final double pos;
  final double min;
  final double max;
  final bool logarithmic;
  final int divisions;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onDoubleTapReset;
  final ValueChanged<Offset>? onLongPressStart;

  const _EqVerticalFader({
    required this.width,
    required this.label,
    required this.labelText,
    required this.pos,
    required this.min,
    required this.max,
    required this.logarithmic,
    required this.divisions,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onDoubleTapReset,
    required this.onLongPressStart,
  });

  @override
  State<_EqVerticalFader> createState() => _EqVerticalFaderState();
}

class _EqVerticalFaderState extends State<_EqVerticalFader> {
  static const double _valueToFaderGap = 7.0;
  static const double _faderToNameGap = 7.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        setState(() {
          widget.onDoubleTapReset?.call();
        });
      },
      onLongPressStart: (details) {
        widget.onLongPressStart?.call(details.globalPosition);
      },
      child: SizedBox(
        width: widget.width, // 👈 respect caller width
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.labelText,
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: _valueToFaderGap),
            SizedBox(
              height: _eqFaderHeight,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    showValueIndicator: ShowValueIndicator.never,
                    trackHeight: 4,
                    trackShape: const _TightSliderTrackShape(),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: widget.pos,
                    min: 0.0,
                    max: 1.0,
                    divisions: widget.divisions,
                    onChangeStart: (v) {
                      widget.onChangeStart(v);
                    },
                    onChanged: (p) {
                      final v = widget.logarithmic
                          ? _fromLogPos(p, widget.min, widget.max)
                          : (widget.min + (widget.max - widget.min) * p);
                      widget.onChanged(v);
                    },
                    onChangeEnd: (p) {
                      final v = widget.logarithmic
                          ? _fromLogPos(p, widget.min, widget.max)
                          : (widget.min + (widget.max - widget.min) * p);
                      widget.onChangeEnd(v);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: _faderToNameGap),
            Text(widget.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _TightSliderTrackShape extends RoundedRectSliderTrackShape {
  const _TightSliderTrackShape();
  static const double _edgeInset = 4.0;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4.0;
    final trackLeft = offset.dx + _edgeInset;
    final trackWidth = (parentBox.size.width - (_edgeInset * 2)).clamp(
      0.0,
      parentBox.size.width,
    );
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

double beatsToMs(double beats, double bpm) {
  return (60000.0 / bpm) * beats;
}

class DelayDivision {
  final String label; // e.g. "1/4", "1/8T", "1/4."
  final double beats; // how many beats this represents

  const DelayDivision(this.label, this.beats);
}

const List<DelayDivision> kDelayDivisions = [
  DelayDivision('1/1', 4.0),
  DelayDivision('1/2', 2.0),
  DelayDivision('1/4.', 1.5), // dotted
  DelayDivision('1/4', 1.0),
  DelayDivision('1/8.', 0.75),
  DelayDivision('1/4T', 2 / 3), // triplet
  DelayDivision('1/8', 0.5),
  DelayDivision('1/8T', 1 / 3),
  DelayDivision('1/16', 0.25),
];

class CompressorStripFrame {
  final double inL, inR; // 0..1
  final double outL, outR; // 0..1
  final double grDb; // negative or 0 (ex: -6.2)

  const CompressorStripFrame({
    required this.inL,
    required this.inR,
    required this.grDb,
    required this.outL,
    required this.outR,
  });

  static const zero =
      CompressorStripFrame(inL: 0, inR: 0, grDb: 0, outL: 0, outR: 0);

  CompressorStripFrame clamp() {
    double c01(double v) => v.clamp(0.0, 1.0).toDouble();
    double cgr(double v) => v.clamp(0.0, 60.0).toDouble();
    return CompressorStripFrame(
      inL: c01(inL),
      inR: c01(inR),
      grDb: cgr(grDb),
      outL: c01(outL),
      outR: c01(outR),
    );
  }

  static CompressorStripFrame lerp(
      CompressorStripFrame a, CompressorStripFrame b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return CompressorStripFrame(
      inL: l(a.inL, b.inL),
      inR: l(a.inR, b.inR),
      grDb: l(a.grDb, b.grDb),
      outL: l(a.outL, b.outL),
      outR: l(a.outR, b.outR),
    );
  }
}

class GainReductionSliderMeterHorizontal extends StatelessWidget {
  /// Positive GR in dB. Example: 0..60 (your engine returns positive now)
  final double grDb;

  /// Most plugins display 24–30 dB range for readability
  final double maxDb;
  final String title;

  final double height;
  final double width;

  /// Smooth UI motion
  final Duration anim;

  /// Optional peak-hold feel
  final bool peakHold;

  const GainReductionSliderMeterHorizontal({
    super.key,
    required this.grDb,
    this.maxDb = 24.0,
    this.title = 'Gain Reduction',
    this.height = 18,
    this.width = 220,
    this.anim = const Duration(milliseconds: 90),
    this.peakHold = true,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = grDb.clamp(0.0, maxDb);
    final t = (clamped / maxDb).clamp(0.0, 1.0); // 0..1 (0 = no GR)

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white.withOpacity(0.55),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        );

    final readoutStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white.withOpacity(0.80),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );

    // Display as negative numbers (plugin convention)
    final leftLabel = "0";
    final midLabel = "-${(maxDb / 2).round()}";
    final rightLabel = "-${maxDb.round()}";

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: title + live value
          Row(
            children: [
              Text(title, style: readoutStyle),
              const SizedBox(width: 8),
              // Expanded(
              //   child: Opacity(
              //     opacity: 0.0, // keeps right text aligned without extra layout jitter
              //     child: Text("GR", style: readoutStyle),
              //   ),
              // ),
              // Text("${clamped.toStringAsFixed(1)} dB", style: readoutStyle),
            ],
          ),
          const SizedBox(height: 6),

          // Meter bar
          _PeakHold01Wrapper(
            enabled: peakHold,
            value01: t,
            child: (displayT) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: displayT),
                duration: anim,
                curve: Curves.easeOutCubic,
                builder: (_, v, __) {
                  return CustomPaint(
                    size: Size(width, height),
                    painter: _GRSliderHorizontalPainter(
                      t: v,
                      labelDb: clamped,
                      maxDb: maxDb,
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 6),

          // Bottom labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("$leftLabel dB", style: labelStyle),
              Text("$midLabel dB", style: labelStyle),
              Text("$rightLabel dB", style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeakHold01Wrapper extends StatefulWidget {
  final bool enabled;
  final double value01;
  final Widget Function(double displayT) child;

  const _PeakHold01Wrapper({
    required this.enabled,
    required this.value01,
    required this.child,
  });

  @override
  State<_PeakHold01Wrapper> createState() => _PeakHold01WrapperState();
}

class _PeakHold01WrapperState extends State<_PeakHold01Wrapper> {
  double _hold = 0.0;
  DateTime _last = DateTime.now();

  @override
  void didUpdateWidget(covariant _PeakHold01Wrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) return;

    final now = DateTime.now();
    final dt = now.difference(_last).inMilliseconds / 1000.0;
    _last = now;

    final incoming = widget.value01;

    // rise: follow instantly
    if (incoming > _hold) {
      _hold = incoming;
      return;
    }

    // fall: decay
    final decayPerSec = 1.4; // tweak feel
    _hold = (_hold - decayPerSec * dt).clamp(0.0, 1.0);

    if (_hold < incoming) _hold = incoming;
  }

  @override
  Widget build(BuildContext context) {
    final displayT = widget.enabled ? _hold : widget.value01;
    return widget.child(displayT);
  }
}

class _GRSliderHorizontalPainter extends CustomPainter {
  final double t; // 0..1 fill amount
  final double labelDb;
  final double maxDb;

  _GRSliderHorizontalPainter({
    required this.t,
    required this.labelDb,
    required this.maxDb,
  });

  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;

    // Background "pill"
    final bg = Paint()..color = const Color(0xFF111827).withOpacity(0.95);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.12);

    final outer =
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h / 2));
    c.drawRRect(outer, bg);
    c.drawRRect(outer, border);

    // Inner track
    const pad = 3.0;
    final track = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);

    final trackPaint = Paint()..color = Colors.white.withOpacity(0.08);
    c.drawRRect(
        RRect.fromRectAndRadius(track, Radius.circular(track.height / 2)),
        trackPaint);

    // Fill (left -> right)
    final fillW = (track.width * t).clamp(0.0, track.width);
    final fillRect = Rect.fromLTWH(track.left, track.top, fillW, track.height);

    final fillPaint = Paint()..color = Colors.white.withOpacity(0.70);
    c.drawRRect(
        RRect.fromRectAndRadius(fillRect, Radius.circular(track.height / 2)),
        fillPaint);

    // Thumb (slider handle look)
    // Thumb sits at end of fill
    final thumbX = (track.left + fillW).clamp(track.left, track.right);
    final thumbW = 6.0;
    final thumbRect = Rect.fromLTWH(
        thumbX - thumbW / 2, track.top - 1, thumbW, track.height + 2);

    final thumbPaint = Paint()..color = Colors.white.withOpacity(0.95);
    c.drawRRect(RRect.fromRectAndRadius(thumbRect, const Radius.circular(6)),
        thumbPaint);

    // Simple tick marks (optional, subtle)
    final tick = Paint()
      ..color = Colors.black.withOpacity(0.20)
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final x = track.left + track.width * (i / 5.0);
      c.drawLine(Offset(x, track.top + 2), Offset(x, track.bottom - 2), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _GRSliderHorizontalPainter old) {
    return old.t != t || old.labelDb != labelDb || old.maxDb != maxDb;
  }
}
