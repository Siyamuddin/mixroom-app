import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'dart:math' as math;

import 'package:mixroom/models/models.dart';

class RowEffectsPanel extends StatefulWidget {
  final int rowIndex;
  final String mode;

  // Callbacks from AudioEditor → JUCE
  final Future<List<String>> Function(int row) getEffectsForRow;
  final Future<bool> Function(int row, int effectIndex) getBypassStateForRow;
  final Future<void> Function(int row, int effectIndex, bool bypass) setBypassForRow;
  final Future<void> Function(int row, int from, int to) reorderEffectsForRow;
  final Future<void> Function(int row, int effectIndex, String name, bool applyingPreset) removeEffectFromRow;
  final Future<void> Function(int row, String path) insertEffectOnRow;
  final Future<List<Map<String, dynamic>>> Function(int row, int effectIndex) getTrackPluginParameters;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final Future<void> Function(int row, int effectIndex, String paramId, dynamic value) setTrackEffectParam;
  final void Function(RowEffectsSnapshot before, RowEffectsSnapshot after)? onPresetCommit;
  final void Function(double height) onHeightChanged;
  final void Function(VoidCallback refresh)? registerRefresh;
  final double projectBpm;

  final void Function(int row, int effectIndex, String paramId, dynamic oldValue, dynamic newValue)?
  onPluginParamCommit;

  const RowEffectsPanel({
    Key? key,
    required this.rowIndex,
    required this.mode,
    required this.getEffectsForRow,
    required this.getBypassStateForRow,
    required this.setBypassForRow,
    required this.reorderEffectsForRow,
    required this.removeEffectFromRow,
    required this.insertEffectOnRow,
    required this.getTrackPluginParameters,
    required this.scanPlugins,
    required this.setTrackEffectParam,
    required this.onHeightChanged,
    required this.onPluginParamCommit,
    required this.onPresetCommit,
    this.registerRefresh,
    required this.projectBpm,
  }) : super(key: key);

  @override
  State<RowEffectsPanel> createState() => _RowEffectsPanelState();
}

class _RowEffectsPanelState extends State<RowEffectsPanel> {
  List<String> _effects = [];
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

  @override
  void initState() {
    super.initState();
    _loadEffects();
    // widget.registerRefresh?.call = _refetchAll;
    widget.registerRefresh?.call(_refetchAll);
  }

  Future<void> _loadEffects() async {
    setState(() {
      _loading = true;
      _selectedEffectIndex = null;
      _currentParams = [];
    });
    final names = await widget.getEffectsForRow(widget.rowIndex);
    final bypassStates = <bool>[];

    for (int i = 0; i < names.length; i++) {
      final b = await widget.getBypassStateForRow(widget.rowIndex, i);
      bypassStates.add(b);
    }

    if (!mounted) return;
    setState(() {
      _effects = List<String>.from(names);
      _bypassed = List<bool>.from(bypassStates);
      _loading = false;
    });
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
    final presetLabel = detectedIdx == null ? 'Custom' : kDelayDivisions[detectedIdx].label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header row ----
          Row(
            children: [
              Text(param['name'] as String, style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),

              // ---- PRESET DROPDOWN ----
              DropdownButton<String>(
                value: presetLabel,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                  ...kDelayDivisions.map((d) => DropdownMenuItem(value: d.label, child: Text(d.label))),
                ],
                onChanged: (label) {
                  if (label == null || label == 'Custom') return;

                  final division = kDelayDivisions.firstWhere((d) => d.label == label);
                  final newMs = beatsToMs(division.beats, bpm);

                  _paramDragStartValue = msValue;

                  setState(() {
                    param['value'] = newMs;
                  });

                  widget.setTrackEffectParam(widget.rowIndex, effectIndex, param['name'] as String, newMs);

                  widget.onPluginParamCommit?.call(
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
              Text((param['min'] as num).toDouble().toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: Slider(
                  value: msValue.clamp((param['min'] as num).toDouble(), (param['max'] as num).toDouble()),
                  min: (param['min'] as num).toDouble(),
                  max: (param['max'] as num).toDouble(),
                  divisions: 200,
                  label: '${msValue.toStringAsFixed(0)} ms',
                  onChangeStart: (_) {
                    _paramDragStartValue = msValue;
                  },
                  onChanged: (v) {
                    setState(() => param['value'] = v);
                    widget.setTrackEffectParam(widget.rowIndex, effectIndex, param['name'] as String, v);
                  },
                  onChangeEnd: (v) {
                    if (_paramDragStartValue == null) return;

                    widget.onPluginParamCommit?.call(
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
              Text((param['max'] as num).toDouble().toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  // used from above when the UI needs to be updated after JUCE state changed from above (undo actions, AI mixer)
  Future<void> _refetchAll() async {
    if (!mounted) return;

    // Case 1: effect list page
    if (_selectedEffectIndex == null) {
      await _loadEffects();
      return;
    }

    // Case 2: parameter page
    final idx = _selectedEffectIndex!;
    setState(() {
      _paramsLoading = true;
    });

    var params = await widget.getTrackPluginParameters(widget.rowIndex, idx);

    // Re-apply the same filtering logic used in _openPluginParams
    if (widget.mode == "Basic" || widget.mode == "Pro") {
      final effectName = _effects[idx];
      switch (effectName) {
        case 'Reverb':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return ['Room Size', 'Mix', 'Predelay'].contains(n);
          }).toList();
          break;

        case 'Compressor':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return ['Threshold', 'Attack', 'Release', 'Ratio', 'Makeup', 'Mix'].contains(n);
          }).toList();
          break;

        case 'EQ Parametric':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return [
              'HPF Frequency',
              'Band 1 Gain',
              'Band 2 Gain',
              'Band 3 Gain',
              'Band 4 Gain',
              'LPF Frequency',
            ].contains(n);
          }).toList();
          break;

        case 'EQ 3-Band':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return ['Low Gain', 'Mid Gain', 'High Gain'].contains(n);
          }).toList();
          break;

        case 'Delay':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return ['Delay Time', 'Feedback', 'Mix'].contains(n);
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

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
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
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetChip("Concert Hall"),
                _buildPresetChip("Echoes"),
                _buildPresetChip("LoFi Effect"),
                // _buildPresetChip("Heavy Crunch"), // TODO: TEMP
              ],
            ),
          ),

          const SizedBox(height: 2),

          // --- Effects List ---
          if (_effects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 0.0, right: 0.0),
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [for (int i = 0; i < _effects.length; i++) _buildEffectTile(i)],
                onReorder: (oldIndex, newIndex) async {
                  if (oldIndex < 0 || oldIndex >= _effects.length) return;
                  if (newIndex > oldIndex) newIndex--;
                  newIndex = newIndex.clamp(0, _effects.length - 1);

                  await widget.reorderEffectsForRow(widget.rowIndex, oldIndex, newIndex);

                  setState(() {
                    final name = _effects.removeAt(oldIndex);
                    final bypass = _bypassed.removeAt(oldIndex);
                    _effects.insert(newIndex, name);
                    _bypassed.insert(newIndex, bypass);
                  });
                },
              ),
            ),

          // --- Add FX Button ---
          if (_effects.length < 5) Padding(padding: const EdgeInsets.only(top: 0.0, left: 0.0), child: _buildAddTile()),
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
        if (_lastReportedHeight == null || (h - _lastReportedHeight!).abs() > 0.5) {
          _lastReportedHeight = h;
          widget.onHeightChanged(h);
        }
      }
    });

    return ConstrainedBox(
      // NOTE: this is meant to equal kExpandedRowHeight which is currently equal to kRowHeight (80.0) * 3. defined in audio_timeline_pro.dart
      constraints: const BoxConstraints(minHeight: 240),
      child: _buildContent(context),
    );
  }

  // =========================
  // PRESETS
  // =========================

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = <String>[]; // you can re-lock LoFi / Heavy later
    final isLocked = widget.mode == 'Basic' && lockedPresets.contains(name);

    return ActionChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // ← smaller hitbox
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), // ← shrink chip
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2), // ← reduce height
      backgroundColor: isLocked ? const Color.fromARGB(255, 61, 61, 61) : const Color.fromARGB(255, 88, 107, 200),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.translate(context, name),
            style: TextStyle(
              fontSize: 12,
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
      onPressed: isLocked ? null : () => _handlePresetLoading(context, name),
    );
  }

  Future<void> _handlePresetLoading(BuildContext context, String presetName) async {
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
      beforeSnapshots.add(EffectSnapshot(_effects[i], {for (final p in params) p['name']: p['value']}));
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
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Room Size', 53);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Mix', 20);
        break;

      case 'Echoes':
        await widget.insertEffectOnRow(widget.rowIndex, 'Reverb');
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Room Size', 40);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Mix', 20);
        await widget.insertEffectOnRow(widget.rowIndex, 'Delay');
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Delay Time', 400);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Feedback', 30);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Mix', 30);
        break;

      case 'LoFi Effect':
        await widget.insertEffectOnRow(widget.rowIndex, 'EQ Parametric');
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'LPF Frequency', 2600.0);
        await widget.insertEffectOnRow(widget.rowIndex, 'Distortion');
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Drive', 50);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Mix', 85);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Anger', 1);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'LPF Frequency', 2800.0);
        await widget.setTrackEffectParam(widget.rowIndex, 1, 'Distortion Type', "Mode 3");
        break;

      case 'Heavy Crunch':
        await widget.insertEffectOnRow(widget.rowIndex, 'Distortion');
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Drive', 100);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Mix', 100);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Anger', 1);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Volume', 12);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Pre Shape', 3.0);
        await widget.setTrackEffectParam(widget.rowIndex, 0, 'Distortion Type', "Mode 3");
        break;

      default:
        debugPrint('⚠️ No matching preset logic for: $presetName');
    }

    await _loadEffects();

    // BUILD 'AFTER' SNAPSHOT
    final afterSnapshots = <EffectSnapshot>[];
    for (int i = 0; i < _effects.length; i++) {
      final params = await widget.getTrackPluginParameters(widget.rowIndex, i);
      afterSnapshots.add(EffectSnapshot(_effects[i], {for (final p in params) p['name']: p['value']}));
    }
    final after = RowEffectsSnapshot(widget.rowIndex, afterSnapshots);
    widget.onPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildEffectTile(int idx) {
    return ReorderableDragStartListener(
      key: ValueKey("effect_$idx"),
      index: idx,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        key: ValueKey("effect_tile_$idx"),
        leading: const Icon(Icons.drag_handle),
        title: Text(_effects[idx], style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bypass toggle
            Switch(
              value: !_bypassed[idx],
              onChanged: (active) async {
                final shouldBypass = !active;
                await widget.setBypassForRow(widget.rowIndex, idx, shouldBypass);
                setState(() => _bypassed[idx] = shouldBypass);
              },
              activeColor: const Color.fromARGB(255, 231, 231, 231),
              inactiveThumbColor: const Color.fromARGB(255, 186, 186, 186),
              inactiveTrackColor: const Color.fromARGB(255, 235, 235, 235),
              activeTrackColor: const Color.fromARGB(255, 54, 54, 54),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color.fromARGB(255, 255, 164, 164)),
              onPressed: () => _confirmRemove(idx),
            ),
          ],
        ),
        onTap: () => _openPluginParams(idx),
      ),
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
            child: Text(L10n.translate(context, 'Delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (yes == true) {
      await widget.removeEffectFromRow(widget.rowIndex, idx, _effects[idx], false);
      _delayDivisionByEffect.remove(idx);

      setState(() {
        _effects.removeAt(idx);
        _bypassed.removeAt(idx);
      });
    }
  }

  // =========================
  // ADD EFFECT MODAL (dialog, can scroll internally)
  // =========================

  Future<void> _showAddEffectModal() async {
    final plugins = await widget.scanPlugins();
    // const allowedInBasic = ['Reverb', 'EQ Parametric', 'EQ 3-Band', 'Delay', 'Distortion', 'De-Esser', 'Compressor'];
    const allowedInBasic = ["EQ 3-Band", "Compressor", "De-Esser", "Distortion", "Delay", "Reverb", "EQ Parametric"];

    // Dialog can use scrolling; this is outside the row panel layout.
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
              labelColor: const Color.fromARGB(255, 255, 255, 255),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color.fromARGB(255, 255, 255, 255),
              indicatorWeight: 2,
              tabs: [
                const Tab(text: 'FX'),
                Tab(text: L10n.translate(context, 'On Device')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: TabBarView(
                children: [
                  ListView(
                    children: ["EQ 3-Band", "Compressor", "De-Esser", "Distortion", "Delay", "Reverb", "EQ Parametric"]
                        .map((name) {
                          final isAllowed = widget.mode == 'Pro' || allowedInBasic.contains(name);
                          return GestureDetector(
                            onTap: isAllowed
                                ? () async {
                                    Navigator.pop(context);
                                    await widget.insertEffectOnRow(widget.rowIndex, name);
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
                        })
                        .toList(),
                  ),
                  ListView(
                    children: plugins.map((meta) {
                      final name = meta['name'] ?? meta['id'] ?? '';
                      final path = meta['id'] ?? '';
                      return ListTile(
                        title: Text(name),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.insertEffectOnRow(widget.rowIndex, path);
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

  // =========================
  // PARAMETERS PAGE (inline, no internal scroll)
  // =========================

  Future<void> _openPluginParams(int idx) async {
    setState(() {
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
    });

    var params = await widget.getTrackPluginParameters(widget.rowIndex, idx);

    // Basic-mode param filtering
    //TODO: TEMP limit plugin parameters no matter what "mode"
    if (widget.mode == "Basic" || widget.mode == "Pro") {
      switch (_effects[idx]) {
        case 'Reverb':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Room Size', 'Mix', 'Predelay'].contains(name);
          }).toList();
          break;

        case 'Compressor':
          params = params.where((p) {
            final n = p['name']?.toString() ?? '';
            return ['Threshold', 'Attack', 'Release', 'Ratio', 'Makeup', 'Mix'].contains(n);
          }).toList();
          break;

        case 'EQ Parametric':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return [
              'HPF Frequency',
              'Band 1 Gain',
              'Band 2 Gain',
              'Band 3 Gain',
              'Band 4 Gain',
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
        child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
      );
    }

    final effectName = _effects[idx];

    // Special layout for EQ Parametric
    if (effectName == 'EQ Parametric' && _currentParams.isNotEmpty) {
      final pHPF = _paramByName(_currentParams, 'HPF Frequency');
      final pLPF = _paramByName(_currentParams, 'LPF Frequency');
      final pB1 = _paramByName(_currentParams, 'Band 1 Gain');
      final pB2 = _paramByName(_currentParams, 'Band 2 Gain');
      final pB3 = _paramByName(_currentParams, 'Band 3 Gain');
      final pB4 = _paramByName(_currentParams, 'Band 4 Gain');

      final hpfHz = (pHPF?['value'] as num?)?.toDouble() ?? 80.0;
      final lpfHz = (pLPF?['value'] as num?)?.toDouble() ?? 12000.0;

      final bandGains = [
        (pB1?['value'] as num?)?.toDouble() ?? 0,
        (pB2?['value'] as num?)?.toDouble() ?? 0,
        (pB3?['value'] as num?)?.toDouble() ?? 0,
        (pB4?['value'] as num?)?.toDouble() ?? 0,
      ];
      final bandFreqs = [60.0, 400.0, 2000.0, 8000.0];

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with back button
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  effectName,
                  style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            // const SizedBox(height: 8),
            const Divider(color: Color.fromARGB(213, 104, 104, 104)),
            const SizedBox(height: 8),

            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth, // EQ shrinks inside row
                  ),
                  child: Column(
                    children: [
                      // EQ Preview
                      _EqPreviewFull(hpfHz: hpfHz, lpfHz: lpfHz, bandGains: bandGains, bandFreqs: bandFreqs),
                      const SizedBox(height: 16),

                      // Vertical faders row
                      SizedBox(
                        height: _eqRowHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown, // solves horizontal overflow
                          alignment: Alignment.topCenter,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (pHPF != null)
                                _verticalFader(
                                  context: context,
                                  label: 'HPF\nFreq',
                                  value: (pHPF['value'] as num).toDouble(),
                                  min: (pHPF['min'] as num).toDouble(),
                                  max: (pHPF['max'] as num).toDouble(),
                                  logarithmic: true,
                                  unit: 'Hz',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pHPF['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pHPF['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pHPF['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pHPF['name'] as String, v);
                                  },
                                ),
                              if (pB1 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band1\nGain',
                                  value: (pB1['value'] as num).toDouble(),
                                  min: (pB1['min'] as num).toDouble(),
                                  max: (pB1['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB1['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pB1['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB1['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pB1['name'] as String, v);
                                  },
                                ),
                              if (pB2 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band2\nGain',
                                  value: (pB2['value'] as num).toDouble(),
                                  min: (pB2['min'] as num).toDouble(),
                                  max: (pB2['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB2['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pB2['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB2['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pB2['name'] as String, v);
                                  },
                                ),
                              if (pB3 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band3\nGain',
                                  value: (pB3['value'] as num).toDouble(),
                                  min: (pB3['min'] as num).toDouble(),
                                  max: (pB3['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB3['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pB3['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB3['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pB3['name'] as String, v);
                                  },
                                ),
                              if (pB4 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band4\nGain',
                                  value: (pB4['value'] as num).toDouble(),
                                  min: (pB4['min'] as num).toDouble(),
                                  max: (pB4['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB4['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pB4['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB4['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pB4['name'] as String, v);
                                  },
                                ),
                              if (pLPF != null)
                                _verticalFader(
                                  context: context,
                                  label: 'LPF\nFreq',
                                  value: (pLPF['value'] as num).toDouble(),
                                  min: (pLPF['min'] as num).toDouble(),
                                  max: (pLPF['max'] as num).toDouble(),
                                  logarithmic: true,
                                  unit: 'Hz',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pLPF['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
                                      widget.rowIndex,
                                      idx,
                                      pLPF['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pLPF['value'] = v);
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pLPF['name'] as String, v);
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

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  effectName,
                  style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(color: Color.fromARGB(213, 104, 104, 104)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    children: [
                      _Eq3Preview(bandGains: gains, bandFreqs: freqs),
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
                                  label: 'Low\nGain',
                                  value: (pLow['value'] as num).toDouble(),
                                  min: (pLow['min'] as num).toDouble(),
                                  max: (pLow['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pLow['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
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
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pLow['name'] as String, v);
                                  },
                                ),
                              if (pMid != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Mid\nGain',
                                  value: (pMid['value'] as num).toDouble(),
                                  min: (pMid['min'] as num).toDouble(),
                                  max: (pMid['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pMid['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
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
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pMid['name'] as String, v);
                                  },
                                ),
                              if (pHigh != null)
                                _verticalFader(
                                  context: context,
                                  label: 'High\nGain',
                                  value: (pHigh['value'] as num).toDouble(),
                                  min: (pHigh['min'] as num).toDouble(),
                                  max: (pHigh['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pHigh['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onPluginParamCommit?.call(
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
                                    widget.setTrackEffectParam(widget.rowIndex, idx, pHigh['name'] as String, v);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedEffectIndex = null;
                    _currentParams = [];
                  });
                },
              ),
              const SizedBox(width: 4),
              Text(
                effectName,
                style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          // const SizedBox(height: 8),
          const Divider(color: Color.fromARGB(213, 104, 104, 104)),
          // const SizedBox(height: 8),

          // Params straight in Column
          for (var param in _currentParams) ...[
            if (_effects[idx] == 'Delay' && param['name'] == 'Delay Time') ...[
              _buildDelayTimeParam(context: context, param: param, effectIndex: idx, bpm: widget.projectBpm),
            ] else if (param['type'] == 'float') ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(param['name'] as String, style: Theme.of(context).textTheme.bodyLarge),
                    // const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          (param['min'] as num).toDouble().toStringAsFixed(2),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        // const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              showValueIndicator: ShowValueIndicator.always,
                              valueIndicatorTextStyle: const TextStyle(
                                color: Color.fromARGB(255, 0, 0, 0),
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
                              divisions: 100,
                              label: (param['value'] as num).toDouble().toStringAsFixed(2),
                              // onChanged: (v) {
                              //   setState(() => param['value'] = v);
                              //   widget.setTrackEffectParam(
                              //     widget.rowIndex,
                              //     idx,
                              //     param['name'] as String,
                              //     v,
                              //   );
                              // },
                              onChangeStart: (v) {
                                _paramDragStartValue = (param['value'] as num).toDouble();
                              },
                              onChanged: (v) {
                                setState(() => param['value'] = v);
                                widget.setTrackEffectParam(widget.rowIndex, idx, param['name'] as String, v);
                              },
                              onChangeEnd: (v) {
                                if (_paramDragStartValue == null) return;

                                widget.onPluginParamCommit?.call(
                                  widget.rowIndex,
                                  idx,
                                  param['name'] as String,
                                  _paramDragStartValue!,
                                  v,
                                );

                                _paramDragStartValue = null;
                              },
                            ),
                          ),
                        ),
                        // const SizedBox(width: 8),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(param['name'] as String),
                value: param['value'] as bool,
                onChanged: (v) {
                  setState(() => param['value'] = v);
                  widget.setTrackEffectParam(widget.rowIndex, idx, param['name'] as String, v);
                  widget.onPluginParamCommit?.call(widget.rowIndex, idx, param['name'] as String, !v, v);
                },
              ),
            ] else if (param['type'] == 'choice') ...[
              (() {
                final keys = param.keys.where((k) => k.startsWith('choice_')).toList()
                  ..sort((a, b) {
                    final ai = int.parse(a.split('_')[1]);
                    final bi = int.parse(b.split('_')[1]);
                    return ai.compareTo(bi);
                  });
                final choices = keys.map((k) => param[k] as String).toList();
                final current = param['value'] as String;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
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
                            return SimpleDialogOption(child: Text(c), onPressed: () => Navigator.pop(ctx, c));
                          }).toList(),
                        ),
                      );
                      if (picked != null) {
                        final oldVal = param['value'];
                        setState(() => param['value'] = picked);
                        widget.setTrackEffectParam(widget.rowIndex, idx, param['name'] as String, picked);
                        widget.onPluginParamCommit?.call(widget.rowIndex, idx, param['name'] as String, oldVal, picked);
                      }
                    },
                  ),
                );
              })(),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(param['name'] as String),
                  trailing: Text("${param['value']}"),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class MasterEffectsPanel extends StatefulWidget {
  final String mode;

  // Master FX callbacks (to be wired in audio_editor)
  final Future<List<String>> Function() getMasterEffects;
  final Future<bool> Function(int effectIndex) getMasterEffectBypassState;
  final Future<void> Function(int effectIndex, bool bypass) bypassMasterEffect;
  final Future<void> Function(int from, int to) reorderMasterEffects;
  final Future<void> Function(int effectIndex, String name, bool applyingPreset) removeMasterEffect;
  final Future<void> Function(String effectNameOrPath) insertMasterEffect;
  final Future<List<Map<String, dynamic>>> Function(int effectIndex) getMasterPluginParameters;
  final Future<void> Function(int effectIndex, String paramId, dynamic value) setMasterEffectParam;
  final Future<List<Map<String, dynamic>>> Function() scanPlugins;
  final void Function(int effectIndex, String paramId, dynamic oldValue, dynamic newValue)? onMasterPluginParamCommit;
  final void Function(MasterEffectsSnapshot before, MasterEffectsSnapshot after)? onMasterPresetCommit;

  final void Function(double height)? onHeightChanged;
  final double projectBpm;

  const MasterEffectsPanel({
    Key? key,
    required this.mode,
    required this.getMasterEffects,
    required this.getMasterEffectBypassState,
    required this.bypassMasterEffect,
    required this.reorderMasterEffects,
    required this.removeMasterEffect,
    required this.insertMasterEffect,
    required this.getMasterPluginParameters,
    required this.setMasterEffectParam,
    required this.scanPlugins,
    this.onHeightChanged,
    this.onMasterPluginParamCommit,
    this.onMasterPresetCommit,
    required this.projectBpm,
  }) : super(key: key);

  @override
  State<MasterEffectsPanel> createState() => _MasterEffectsPanelState();
}

class _MasterEffectsPanelState extends State<MasterEffectsPanel> {
  List<String> _effects = [];
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

  @override
  void initState() {
    super.initState();
    _loadEffects();
  }

  Future<void> _loadEffects() async {
    final names = await widget.getMasterEffects();
    final bypass = <bool>[];

    for (int i = 0; i < names.length; i++) {
      bypass.add(await widget.getMasterEffectBypassState(i));
    }

    setState(() {
      _effects = names;
      _bypassed = bypass;
    });
    widget.onHeightChanged?.call(_panelHeight);
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
    final presetLabel = detectedIdx == null ? 'Custom' : kDelayDivisions[detectedIdx].label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header row ----
          Row(
            children: [
              Text(param['name'] as String, style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),

              // ---- PRESET DROPDOWN ----
              DropdownButton<String>(
                value: presetLabel,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                  ...kDelayDivisions.map((d) => DropdownMenuItem(value: d.label, child: Text(d.label))),
                ],
                onChanged: (label) {
                  if (label == null || label == 'Custom') return;

                  final division = kDelayDivisions.firstWhere((d) => d.label == label);
                  final newMs = beatsToMs(division.beats, bpm);

                  _paramDragStartValue = msValue;

                  setState(() {
                    param['value'] = newMs;
                  });

                  widget.setMasterEffectParam(effectIndex, param['name'] as String, newMs);

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
              Text((param['min'] as num).toDouble().toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
              Expanded(
                child: Slider(
                  value: msValue.clamp((param['min'] as num).toDouble(), (param['max'] as num).toDouble()),
                  min: (param['min'] as num).toDouble(),
                  max: (param['max'] as num).toDouble(),
                  divisions: 200,
                  label: '${msValue.toStringAsFixed(0)} ms',
                  onChangeStart: (_) {
                    _paramDragStartValue = msValue;
                  },
                  onChanged: (v) {
                    setState(() => param['value'] = v);
                    widget.setMasterEffectParam(effectIndex, param['name'] as String, v);
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
              Text((param['max'] as num).toDouble().toStringAsFixed(0), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
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
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetChip("Concert Hall"),
                _buildPresetChip("Echoes"),
                _buildPresetChip("LoFi Effect"),
                // _buildPresetChip("Heavy Crunch"), // TODO: TEMP
              ],
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
              children: [for (int i = 0; i < _effects.length; i++) _buildMasterEffectTile(i)],
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex--;
                await widget.reorderMasterEffects(oldIndex, newIndex);
                await _loadEffects();

                setState(() {
                  final name = _effects.removeAt(oldIndex);
                  final bp = _bypassed.removeAt(oldIndex);
                  _effects.insert(newIndex, name);
                  _bypassed.insert(newIndex, bp);
                });
              },
            ),
          ),
          if (_effects.length < 5) Padding(padding: const EdgeInsets.only(top: 8.0), child: _buildAddTile()),
        ],
      ),
    );
  }

  // === SAME UI HELPERS AS RowEffectsPanel (presets, effect tile, add tile, params UI) ===
  // You can copy your existing _buildPresetChip, _buildEffectTile, etc.

  ActionChip _buildPresetChip(String name) {
    const lockedPresets = <String>[]; // you can re-lock LoFi / Heavy later
    final isLocked = widget.mode == 'Basic' && lockedPresets.contains(name);

    return ActionChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // ← smaller hitbox
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), // ← shrink chip
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2), // ← reduce height
      backgroundColor: isLocked ? const Color.fromARGB(255, 61, 61, 61) : const Color.fromARGB(255, 88, 107, 200),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            L10n.translate(context, name),
            style: TextStyle(
              fontSize: 12,
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
      onPressed: isLocked ? null : () => _handlePresetLoading(context, name),
    );
  }

  Future<void> _handlePresetLoading(BuildContext context, String presetName) async {
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
      beforeSnapshots.add(EffectSnapshot(_effects[i], {for (final p in params) p['name']: p['value']}));
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
      afterSnapshots.add(EffectSnapshot(_effects[i], {for (final p in params) p['name']: p['value']}));
    }
    final after = MasterEffectsSnapshot(afterSnapshots);
    widget.onMasterPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildMasterEffectTile(int idx) {
    return ReorderableDragStartListener(
      key: ValueKey("master_effect_$idx"),
      index: idx,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        key: ValueKey("master_effect_tile_$idx"),
        leading: const Icon(Icons.drag_handle),
        title: Text(_effects[idx], style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 15)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bypass toggle
            Switch(
              value: !_bypassed[idx],
              onChanged: (active) async {
                final shouldBypass = !active;
                await widget.bypassMasterEffect(idx, shouldBypass);
                setState(() => _bypassed[idx] = shouldBypass);
              },
              activeColor: const Color.fromARGB(255, 231, 231, 231),
              inactiveThumbColor: const Color.fromARGB(255, 186, 186, 186),
              inactiveTrackColor: const Color.fromARGB(255, 235, 235, 235),
              activeTrackColor: const Color.fromARGB(255, 54, 54, 54),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color.fromARGB(255, 255, 164, 164)),
              onPressed: () => _confirmRemove(idx),
            ),
          ],
        ),
        onTap: () => _openPluginParams(idx),
      ),
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
            child: Text(L10n.translate(context, 'Delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (yes == true) {
      await widget.removeMasterEffect(idx, _effects[idx], false);
      _delayDivisionByEffect.remove(idx);
      await _loadEffects();
      setState(() {
        _effects.removeAt(idx);
        _bypassed.removeAt(idx);
      });
    }
  }

  // =========================
  // ADD EFFECT MODAL (dialog, can scroll internally)
  // =========================

  Future<void> _showAddEffectModal() async {
    final plugins = await widget.scanPlugins();
    const allowedInBasic = ["EQ 3-Band", "Compressor", "De-Esser", "Distortion", "Delay", "Reverb", "EQ Parametric"];

    // Dialog can use scrolling; this is outside the row panel layout.
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
              labelColor: const Color.fromARGB(255, 255, 255, 255),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color.fromARGB(255, 255, 255, 255),
              indicatorWeight: 2,
              tabs: [
                const Tab(text: 'FX'),
                Tab(text: L10n.translate(context, 'On Device')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: TabBarView(
                children: [
                  ListView(
                    children: ["EQ 3-Band", "Compressor", "De-Esser", "Distortion", "Delay", "Reverb", "EQ Parametric"]
                        .map((name) {
                          final isAllowed = widget.mode == 'Pro' || allowedInBasic.contains(name);
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
                                title: Text(name),
                                trailing: isAllowed ? null : const Icon(Icons.lock, size: 18, color: Colors.white70),
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                  ListView(
                    children: plugins.map((meta) {
                      final name = meta['name'] ?? meta['id'] ?? '';
                      final path = meta['id'] ?? '';
                      return ListTile(
                        title: Text(name),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.insertMasterEffect(path);
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

  // =========================
  // PARAMETERS PAGE (inline, no internal scroll)
  // =========================

  Future<void> _openPluginParams(int idx) async {
    setState(() {
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
    });

    var params = await widget.getMasterPluginParameters(idx);

    // Basic-mode param filtering
    //TODO: TEMP limit plugin parameters no matter what "mode"
    if (widget.mode == "Basic" || widget.mode == "Pro") {
      switch (_effects[idx]) {
        case 'Reverb':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return ['Room Size', 'Mix', 'Predelay'].contains(name);
          }).toList();
          break;

        case 'EQ Parametric':
          params = params.where((param) {
            final name = param['name']?.toString() ?? '';
            return [
              'HPF Frequency',
              'Band 1 Gain',
              'Band 2 Gain',
              'Band 3 Gain',
              'Band 4 Gain',
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
        child: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
      );
    }

    final effectName = _effects[idx];

    // Special layout for EQ Parametric
    if (effectName == 'EQ Parametric' && _currentParams.isNotEmpty) {
      final pHPF = _paramByName(_currentParams, 'HPF Frequency');
      final pLPF = _paramByName(_currentParams, 'LPF Frequency');
      final pB1 = _paramByName(_currentParams, 'Band 1 Gain');
      final pB2 = _paramByName(_currentParams, 'Band 2 Gain');
      final pB3 = _paramByName(_currentParams, 'Band 3 Gain');
      final pB4 = _paramByName(_currentParams, 'Band 4 Gain');

      final hpfHz = (pHPF?['value'] as num?)?.toDouble() ?? 80.0;
      final lpfHz = (pLPF?['value'] as num?)?.toDouble() ?? 12000.0;

      final bandGains = [
        (pB1?['value'] as num?)?.toDouble() ?? 0,
        (pB2?['value'] as num?)?.toDouble() ?? 0,
        (pB3?['value'] as num?)?.toDouble() ?? 0,
        (pB4?['value'] as num?)?.toDouble() ?? 0,
      ];
      final bandFreqs = [60.0, 400.0, 2000.0, 8000.0];

      return SingleChildScrollView(
        // You may want to add padding here if not already handled by internal widgets
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with back button
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  effectName,
                  style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            // const SizedBox(height: 8),
            const Divider(color: Color.fromARGB(213, 104, 104, 104)),
            const SizedBox(height: 8),

            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth, // EQ shrinks inside row
                  ),
                  child: Column(
                    children: [
                      // EQ Preview
                      _EqPreviewFull(hpfHz: hpfHz, lpfHz: lpfHz, bandGains: bandGains, bandFreqs: bandFreqs),
                      const SizedBox(height: 16),

                      // Vertical faders row
                      SizedBox(
                        height: _eqRowHeight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown, // solves horizontal overflow
                          alignment: Alignment.topCenter,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (pHPF != null)
                                _verticalFader(
                                  context: context,
                                  label: 'HPF\nFreq',
                                  value: (pHPF['value'] as num).toDouble(),
                                  min: (pHPF['min'] as num).toDouble(),
                                  max: (pHPF['max'] as num).toDouble(),
                                  logarithmic: true,
                                  unit: 'Hz',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pHPF['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pHPF['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pHPF['value'] = v);
                                    widget.setMasterEffectParam(idx, pHPF['name'] as String, v);
                                  },
                                ),
                              if (pB1 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band1\nGain',
                                  value: (pB1['value'] as num).toDouble(),
                                  min: (pB1['min'] as num).toDouble(),
                                  max: (pB1['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB1['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pB1['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB1['value'] = v);
                                    widget.setMasterEffectParam(idx, pB1['name'] as String, v);
                                  },
                                ),
                              if (pB2 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band2\nGain',
                                  value: (pB2['value'] as num).toDouble(),
                                  min: (pB2['min'] as num).toDouble(),
                                  max: (pB2['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB2['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pB2['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB2['value'] = v);
                                    widget.setMasterEffectParam(idx, pB2['name'] as String, v);
                                  },
                                ),
                              if (pB3 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band3\nGain',
                                  value: (pB3['value'] as num).toDouble(),
                                  min: (pB3['min'] as num).toDouble(),
                                  max: (pB3['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB3['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pB3['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB3['value'] = v);
                                    widget.setMasterEffectParam(idx, pB3['name'] as String, v);
                                  },
                                ),
                              if (pB4 != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Band4\nGain',
                                  value: (pB4['value'] as num).toDouble(),
                                  min: (pB4['min'] as num).toDouble(),
                                  max: (pB4['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pB4['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pB4['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pB4['value'] = v);
                                    widget.setMasterEffectParam(idx, pB4['name'] as String, v);
                                  },
                                ),
                              if (pLPF != null)
                                _verticalFader(
                                  context: context,
                                  label: 'LPF\nFreq',
                                  value: (pLPF['value'] as num).toDouble(),
                                  min: (pLPF['min'] as num).toDouble(),
                                  max: (pLPF['max'] as num).toDouble(),
                                  logarithmic: true,
                                  unit: 'Hz',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pLPF['value'] as num).toDouble();
                                  },
                                  onChangeEnd: (v) {
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pLPF['name'] as String,
                                      _EQParamStartValue!,
                                      v,
                                    );
                                    _EQParamStartValue = null;
                                  },
                                  onChanged: (v) {
                                    setState(() => pLPF['value'] = v);
                                    widget.setMasterEffectParam(idx, pLPF['name'] as String, v);
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

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedEffectIndex = null;
                      _currentParams = [];
                    });
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  effectName,
                  style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(color: Color.fromARGB(213, 104, 104, 104)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Column(
                    children: [
                      _Eq3Preview(bandGains: gains, bandFreqs: freqs),
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
                                  label: 'Low\nGain',
                                  value: (pLow['value'] as num).toDouble(),
                                  min: (pLow['min'] as num).toDouble(),
                                  max: (pLow['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pLow['value'] as num).toDouble();
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
                                    widget.setMasterEffectParam(idx, pLow['name'] as String, v);
                                  },
                                ),
                              if (pMid != null)
                                _verticalFader(
                                  context: context,
                                  label: 'Mid\nGain',
                                  value: (pMid['value'] as num).toDouble(),
                                  min: (pMid['min'] as num).toDouble(),
                                  max: (pMid['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pMid['value'] as num).toDouble();
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
                                    widget.setMasterEffectParam(idx, pMid['name'] as String, v);
                                  },
                                ),
                              if (pHigh != null)
                                _verticalFader(
                                  context: context,
                                  label: 'High\nGain',
                                  value: (pHigh['value'] as num).toDouble(),
                                  min: (pHigh['min'] as num).toDouble(),
                                  max: (pHigh['max'] as num).toDouble(),
                                  unit: 'dB',
                                  onChangeStart: (v) {
                                    _EQParamStartValue = (pHigh['value'] as num).toDouble();
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
                                    widget.setMasterEffectParam(idx, pHigh['name'] as String, v);
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
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedEffectIndex = null;
                    _currentParams = [];
                  });
                },
              ),
              const SizedBox(width: 4),
              Text(
                effectName,
                style: TextStyle(color: Colors.white.withOpacity(1.00), fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          // const SizedBox(height: 8),
          const Divider(color: Color.fromARGB(213, 104, 104, 104)),
          // const SizedBox(height: 8),

          // Params straight in Column
          for (var param in _currentParams) ...[
            if (_effects[idx] == 'Delay' && param['name'] == 'Delay Time') ...[
              _buildDelayTimeParam(context: context, param: param, effectIndex: idx, bpm: widget.projectBpm),
            ] else if (param['type'] == 'float') ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(param['name'] as String, style: Theme.of(context).textTheme.bodyLarge),
                    // const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          (param['min'] as num).toDouble().toStringAsFixed(2),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        // const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              showValueIndicator: ShowValueIndicator.always,
                              valueIndicatorTextStyle: const TextStyle(
                                color: Color.fromARGB(255, 0, 0, 0),
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
                              divisions: 100,
                              label: (param['value'] as num).toDouble().toStringAsFixed(2),
                              // onChanged: (v) {
                              //   setState(() => param['value'] = v);
                              //   widget.setMasterEffectParam(
                              //     idx,
                              //     param['name'] as String,
                              //     v,
                              //   );
                              // },
                              onChangeStart: (v) {
                                _paramDragStartValue = (param['value'] as num).toDouble();
                              },
                              onChanged: (v) {
                                setState(() => param['value'] = v);
                                widget.setMasterEffectParam(idx, param['name'] as String, v);
                              },
                              onChangeEnd: (v) {
                                if (_paramDragStartValue == null) return;

                                widget.onMasterPluginParamCommit?.call(
                                  idx,
                                  param['name'] as String,
                                  _paramDragStartValue!,
                                  v,
                                );

                                _paramDragStartValue = null;
                              },
                            ),
                          ),
                        ),
                        // const SizedBox(width: 8),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(param['name'] as String),
                value: param['value'] as bool,
                onChanged: (v) {
                  setState(() => param['value'] = v);
                  widget.setMasterEffectParam(idx, param['name'] as String, v);
                  widget.onMasterPluginParamCommit?.call(idx, param['name'] as String, !v, v);
                },
              ),
            ] else if (param['type'] == 'choice') ...[
              (() {
                final keys = param.keys.where((k) => k.startsWith('choice_')).toList()
                  ..sort((a, b) {
                    final ai = int.parse(a.split('_')[1]);
                    final bi = int.parse(b.split('_')[1]);
                    return ai.compareTo(bi);
                  });
                final choices = keys.map((k) => param[k] as String).toList();
                final current = param['value'] as String;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
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
                            return SimpleDialogOption(child: Text(c), onPressed: () => Navigator.pop(ctx, c));
                          }).toList(),
                        ),
                      );
                      if (picked != null) {
                        final oldVal = param['value'];
                        setState(() => param['value'] = picked);
                        widget.setMasterEffectParam(idx, param['name'] as String, picked);
                        widget.onMasterPluginParamCommit?.call(idx, param['name'] as String, oldVal, picked);
                      }
                    },
                  ),
                );
              })(),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(param['name'] as String),
                  trailing: Text("${param['value']}"),
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

class _Eq3Preview extends StatelessWidget {
  final List<double> bandGains; // [low, mid, high] dB
  final List<double> bandFreqs; // [lowFc, midFc, highFc] Hz

  const _Eq3Preview({super.key, required this.bandGains, required this.bandFreqs});

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
          ),
        ),
      ),
    );
  }
}

class _Eq3PreviewPainter extends CustomPainter {
  final double lowGainDb, midGainDb, highGainDb;
  final double lowFc, midFc, highFc;

  _Eq3PreviewPainter({
    required this.lowGainDb,
    required this.midGainDb,
    required this.highGainDb,
    required this.lowFc,
    required this.midFc,
    required this.highFc,
  });

  static const double _minF = 20.0;
  static const double _maxF = 20000.0;

  double _xForHz(double hz, double w) {
    final f = hz.clamp(_minF, _maxF);
    final t = (math.log(f) - math.log(_minF)) / (math.log(_maxF) - math.log(_minF));
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
  double _bellContributionDb({required double f, required double fc, required double gainDb}) {
    if (gainDb.abs() < 0.01) return 0.0;

    final d = _log2(f / fc); // octaves away
    final width = 1.1; // larger = wider bell (broad)
    final shape = math.exp(-(d * d) / (2 * width * width));
    return gainDb * shape;
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
    canvas.drawLine(Offset(_xForHz(lowFc, w), 0), Offset(_xForHz(lowFc, w), h), marker);
    canvas.drawLine(Offset(_xForHz(midFc, w), 0), Offset(_xForHz(midFc, w), h), marker);
    canvas.drawLine(Offset(_xForHz(highFc, w), 0), Offset(_xForHz(highFc, w), h), marker);

    final path = Path();
    for (int px = 0; px < w; px++) {
      final f = _minF * math.pow(_maxF / _minF, px / w);

      double db = 0.0;
      db += _shelfContributionDb(f: f, fc: lowFc, gainDb: lowGainDb, isLowShelf: true);
      db += _bellContributionDb(f: f, fc: midFc, gainDb: midGainDb);
      db += _shelfContributionDb(f: f, fc: highFc, gainDb: highGainDb, isLowShelf: false);

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
        old.highFc != highFc;
  }
}

Widget _verticalFader({
  required BuildContext context,
  required String label,
  required double value,
  required double min,
  required double max,
  int? divisions,
  required ValueChanged<double> onChangeStart,
  onChanged,
  onChangeEnd,
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
                onChangeStart: (v) {
                  onChangeStart(v);
                },
                onChanged: (p) {
                  final v = logarithmic ? _fromLogPos(p, min, max) : (min + (max - min) * p);
                  onChanged(v);
                },
                onChangeEnd: (p) {
                  final v = logarithmic ? _fromLogPos(p, min, max) : (min + (max - min) * p);
                  onChangeEnd(v);
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
