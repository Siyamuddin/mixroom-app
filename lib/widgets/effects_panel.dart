import 'dart:async';
import 'dart:ui' as ui;
import 'package:fftea/fftea.dart';

import 'package:flutter/material.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'dart:math' as math;

import 'package:mixroom/helpers/app_haptics.dart';
import 'package:mixroom/helpers/effect_parameter_exposure.dart';
import 'package:mixroom/helpers/halo.dart';
import 'package:mixroom/helpers/mix_change_highlighter.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/subscription_limits.dart';
import 'package:mixroom/models/models.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

const int maxNumEffects = 10;

void _showPluginUpgradeDialog(
  BuildContext context, {
  VoidCallback? onUpgradeRequested,
}) {
  unawaited(
    showAppUpgradeDialog(
      context: context,
      title: 'Upgrade to use this plugin',
      message:
          'All plugins and external plugin hosting are available on Starter and higher plans.',
      icon: Icons.extension_outlined,
      onUpgrade: onUpgradeRequested,
    ),
  );
}

const Color _kFxPanelText = Color(0xFFF4F4F4);
const Color _kFxPanelMutedText = Color(0xB8F4F4F4);
const Color _kFxPanelBorder = Color.fromRGBO(255, 255, 255, 0.12);
const Color _kFxPanelFill = Color.fromRGBO(244, 244, 244, 0.08);
const Color _kFxPanelFillStrong = Color.fromRGBO(244, 244, 244, 0.14);
const Color _kFxWarmAccent = Color(0xFFC89762);
const Color _kFxWarmAccentBorder = Color(0xFFE0B27F);
const Color _kFxCoolAccent = Color(0xFFBBD3E4);
const Color _kFxCoolAccentSoft = Color(0xFFA7C4D9);
const Duration _kShaperPreviewPollInterval = Duration(milliseconds: 16);
const Duration _kDynamicSoftenerPollInterval = Duration(milliseconds: 40);

bool _previewFramesChanged(
  List<double> previous,
  List<double> next, {
  double tolerance = 0.001,
}) {
  if (identical(previous, next)) return false;
  if (previous.length != next.length) return true;

  for (int i = 0; i < next.length; i++) {
    if ((previous[i] - next[i]).abs() > tolerance) return true;
  }
  return false;
}

BoxDecoration _mixroomFxSurfaceDecoration({
  double radius = 24,
  bool active = false,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: active
          ? const <Color>[
              Color(0xFF727982),
              Color(0xFF474F58),
            ]
          : const <Color>[
              Color.fromRGBO(87, 96, 106, 0.94),
              Color.fromRGBO(49, 58, 68, 0.94),
            ],
    ),
    border: Border.all(
      color: Colors.white.withValues(alpha: active ? 0.16 : 0.10),
    ),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.26),
        blurRadius: 18,
        spreadRadius: 2,
      ),
    ],
  );
}

BoxDecoration _mixroomFxInsetDecoration({
  double radius = 18,
  bool selected = false,
}) {
  return BoxDecoration(
    color: selected ? _kFxPanelFillStrong : _kFxPanelFill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Colors.white.withValues(alpha: selected ? 0.20 : 0.12),
    ),
  );
}

BoxDecoration _mixroomFxReturnHighlightDecoration({
  double radius = 14,
}) {
  return BoxDecoration(
    color: const Color(0xFF9FD9FF).withValues(alpha: 0.028),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: const Color(0xFFD9F1FF).withValues(alpha: 0.18),
      width: 0.9,
    ),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF8DD6FF).withValues(alpha: 0.075),
        blurRadius: 10,
        spreadRadius: 0.4,
      ),
    ],
  );
}

ButtonStyle _mixroomFxGhostButtonStyle({
  bool emphasized = false,
}) {
  return TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    minimumSize: const Size(0, 34),
    backgroundColor:
        emphasized ? _kFxPanelFillStrong : Colors.white.withValues(alpha: 0.08),
    foregroundColor: _kFxPanelText,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
      side: BorderSide(
        color: Colors.white.withValues(alpha: emphasized ? 0.18 : 0.12),
      ),
    ),
  );
}

Future<String?> _showMixroomChoiceDialog({
  required BuildContext context,
  required String title,
  required List<String> choices,
  String? currentChoice,
}) {
  if (choices.isEmpty) return Future<String?>.value(null);

  unawaited(AppHaptics.impact(AppHapticImpact.medium));

  final maxHeight = math.min(choices.length * 58.0 + 24.0, 360.0);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _mixroomFxInsetDecoration(radius: 18, selected: true),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kFxPanelText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: _kFxPanelText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: choices.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.07),
              ),
              itemBuilder: (ctx, index) {
                final choice = choices[index];
                final isSelected = choice == currentChoice;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, choice),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              choice,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.4,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: _kFxCoolAccentSoft,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            style: _mixroomFxGhostButtonStyle(),
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.translate(context, 'Cancel')),
          ),
        ],
      );
    },
  );
}

double _numericParamStep(Map<String, dynamic> param, double currentValue) {
  final minV = (param['min'] as num?)?.toDouble() ?? 0.0;
  final maxV = (param['max'] as num?)?.toDouble() ?? 1.0;
  final range = (maxV - minV).abs();
  final unit = _normalizeParamUnit(param['unit']);
  final name = (param['name'] ?? '').toString().toLowerCase();

  if (unit == 'Hz') {
    if (currentValue.abs() >= 2000.0) return 100.0;
    if (currentValue.abs() >= 200.0) return 10.0;
    return 1.0;
  }
  if (unit == 'dB') return 0.5;
  if (unit == '%' || name.contains('mix') || name.contains('amount')) {
    return range <= 1.0 ? 0.01 : 1.0;
  }
  if (unit == 'ms') return currentValue.abs() >= 100.0 ? 10.0 : 1.0;
  if (unit == '°') return 1.0;
  if (range <= 2.0) return 0.01;
  if (range <= 20.0) return 0.1;
  return math.max(0.1, range / 100.0);
}

String _numericParamInputSeed(Map<String, dynamic> param, double value) {
  final unit = _normalizeParamUnit(param['unit']);
  if (unit == 'Hz' || unit == '%' || unit == '°') {
    return value.toStringAsFixed(0);
  }
  if (unit == 'dB' || unit == 'ms') return value.toStringAsFixed(1);
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 1.0e-6) return rounded.toInt().toString();
  return value.toStringAsFixed(2);
}

double? _parseNumericParamInput(String raw, Map<String, dynamic> param) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final unit = _normalizeParamUnit(param['unit']);
  final lower = trimmed.toLowerCase();
  final kiloHz = unit == 'Hz' && RegExp(r'\bk(?:hz)?\b').hasMatch(lower);
  final cleaned =
      lower.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9eE+\-.]'), '');
  if (cleaned.isEmpty || cleaned == '-' || cleaned == '+') return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return kiloHz ? parsed * 1000.0 : parsed;
}

Future<double?> _showNumericParamEntryDialog({
  required BuildContext context,
  required Map<String, dynamic> param,
  required double currentValue,
}) async {
  return showDialog<double>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _NumericParamEntryDialog(
      param: param,
      currentValue: currentValue,
    ),
  );
}

class _NumericParamEntryDialog extends StatefulWidget {
  const _NumericParamEntryDialog({
    required this.param,
    required this.currentValue,
  });

  final Map<String, dynamic> param;
  final double currentValue;

  @override
  State<_NumericParamEntryDialog> createState() =>
      _NumericParamEntryDialogState();
}

class _NumericParamEntryDialogState extends State<_NumericParamEntryDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final double _minValue;
  late final double _maxValue;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _minValue = (widget.param['min'] as num?)?.toDouble() ?? 0.0;
    _maxValue = (widget.param['max'] as num?)?.toDouble() ?? 1.0;
    _controller = TextEditingController(
      text: _numericParamInputSeed(widget.param, widget.currentValue),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = _parseNumericParamInput(_controller.text, widget.param);
    if (parsed == null) {
      setState(() => _errorText = 'Enter a number');
      return;
    }
    _focusNode.unfocus();
    Navigator.of(context).pop(parsed.clamp(_minValue, _maxValue).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF5F666D),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      title: Text(
        (widget.param['name'] ?? 'Value').toString(),
        style: const TextStyle(
          color: _kFxPanelText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: const TextStyle(color: _kFxPanelText),
        decoration: InputDecoration(
          errorText: _errorText,
          suffixText: _normalizeParamUnit(widget.param['unit']),
          suffixStyle: const TextStyle(color: _kFxPanelMutedText),
          helperText:
              '${_formatParamValueForDisplay(widget.param, _minValue)} - ${_formatParamValueForDisplay(widget.param, _maxValue)}',
          helperStyle: const TextStyle(color: _kFxPanelMutedText),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kFxCoolAccent),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Set'),
        ),
      ],
    );
  }
}

Widget _buildParamStepButton({
  required IconData icon,
  required VoidCallback onPressed,
  required String tooltip,
}) {
  return Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      color: _kFxPanelText,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
    ),
  );
}

Widget _buildGenericFloatParamEditor({
  required BuildContext context,
  required String effectName,
  required Map<String, dynamic> param,
  required ValueChanged<double> setLocalValue,
  required FutureOr<void> Function(double value) setRemoteValue,
  required void Function(double oldValue, double newValue) commitValue,
  required ValueChanged<double?> setDragStartValue,
  required double? Function() getDragStartValue,
}) {
  final paramName = param['name'] as String;
  final minV = (param['min'] as num).toDouble();
  final maxV = (param['max'] as num).toDouble();
  final rawV = (param['value'] as num).toDouble().clamp(minV, maxV).toDouble();
  final valueText = _formatParamValueForDisplay(param, rawV);
  final skew = _getParamSkew(effectName, paramName);

  void sendValue(double value) {
    final result = setRemoteValue(value);
    if (result is Future<void>) unawaited(result);
  }

  void applyDiscreteValue(double nextValue) {
    final oldValue = (param['value'] as num).toDouble();
    final clamped = nextValue.clamp(minV, maxV).toDouble();
    if ((oldValue - clamped).abs() < 1.0e-6) return;
    setLocalValue(clamped);
    sendValue(clamped);
    commitValue(oldValue, clamped);
  }

  double toNorm(double v) => ((v - minV) / (maxV - minV)).clamp(0.0, 1.0);
  double fromNorm(double t) => minV + (maxV - minV) * t.clamp(0.0, 1.0);

  final norm = toNorm(rawV);
  final sliderPos = (skew == null) ? norm : math.pow(norm, skew).toDouble();
  final step = _numericParamStep(param, rawV);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                paramName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            _buildParamStepButton(
              icon: Icons.remove_rounded,
              tooltip: 'Decrease',
              onPressed: () => applyDiscreteValue(rawV - step),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Enter value',
              child: TextButton(
                onPressed: () async {
                  final picked = await _showNumericParamEntryDialog(
                    context: context,
                    param: param,
                    currentValue: rawV,
                  );
                  if (picked == null) return;
                  applyDiscreteValue(picked);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(66, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  foregroundColor: _kFxPanelText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                child: Text(
                  valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _buildParamStepButton(
              icon: Icons.add_rounded,
              tooltip: 'Increase',
              onPressed: () => applyDiscreteValue(rawV + step),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              _formatParamValueForDisplay(param, minV),
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
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final defaultValue = _paramDefaultAsDouble(param);
                    if (defaultValue == null) return;
                    applyDiscreteValue(defaultValue);
                  },
                  child: Slider(
                    value: sliderPos,
                    min: 0.0,
                    max: 1.0,
                    divisions: 200,
                    label: valueText,
                    onChangeStart: (_) {
                      setDragStartValue(rawV);
                    },
                    onChanged: (p) {
                      final t = p.clamp(0.0, 1.0);
                      final newNorm = (skew == null)
                          ? t
                          : math.pow(t, 1.0 / skew).toDouble();
                      final v = fromNorm(newNorm);
                      setLocalValue(v);
                      sendValue(v);
                    },
                    onChangeEnd: (p) {
                      final startValue = getDragStartValue();
                      if (startValue == null) return;
                      final t = p.clamp(0.0, 1.0);
                      final newNorm = (skew == null)
                          ? t
                          : math.pow(t, 1.0 / skew).toDouble();
                      final v = fromNorm(newNorm);
                      commitValue(startValue, v);
                      setDragStartValue(null);
                    },
                  ),
                ),
              ),
            ),
            Text(
              _formatParamValueForDisplay(param, maxV),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildMixroomChoiceField({
  required BuildContext context,
  required String value,
  required VoidCallback onTap,
  bool compact = false,
}) {
  final horizontal = compact ? 10.0 : 12.0;
  final vertical = compact ? 7.0 : 10.0;
  final radius = compact ? 12.0 : 14.0;

  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.94),
                  fontSize: compact ? 12.0 : 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              size: compact ? 18 : 20,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildMixroomChoiceSettingTile({
  required BuildContext context,
  required String label,
  required String value,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _kFxPanelText,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildDegradeModeSelectorTile({
  required BuildContext context,
  required String label,
  required String value,
  required List<String> choices,
  required ValueChanged<String> onSelected,
  bool oneRow = false,
}) {
  Widget buildChoice(String choice, {bool compact = false}) {
    final isSelected = choice == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onSelected(choice),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 8 : 9,
          ),
          decoration: _mixroomFxInsetDecoration(
            radius: 999,
            selected: isSelected,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              choice,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: compact ? 12.5 : null,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.82),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: oneRow
        ? Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _kFxPanelText,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    for (int i = 0; i < choices.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: buildChoice(choices[i], compact: true)),
                    ],
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _kFxPanelText,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: choices.map(buildChoice).toList(),
              ),
            ],
          ),
  );
}

Widget _buildFxParamsHeader({
  required BuildContext context,
  required String title,
  required VoidCallback onBack,
  VoidCallback? onReset,
  Widget? trailing,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: _mixroomFxInsetDecoration(radius: 18, selected: true),
    child: Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onBack,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child:
                  const Icon(Icons.arrow_back, size: 18, color: _kFxPanelText),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            L10n.translate(context, title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: _kFxPanelText,
              fontSize: 14.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            style: _mixroomFxGhostButtonStyle(),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(
              L10n.translate(context, 'Reset'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (trailing != null) ...[
          if (onReset != null) const SizedBox(width: 8),
          trailing,
        ],
      ],
    ),
  );
}

class _EffectInfoCopy {
  const _EffectInfoCopy({
    required this.summary,
    required this.parameters,
  });

  final String summary;
  final List<String> parameters;
}

List<String> _parameterNameSummary(List<Map<String, dynamic>> params) {
  final names = <String>[];
  for (final param in params) {
    final name = (param['name'] ?? '').toString().trim();
    if (name.isEmpty || names.contains(name)) continue;
    names.add(name);
  }
  if (names.isEmpty) return const <String>['Controls depend on the plugin.'];
  return names.take(6).map((name) => '$name: Plugin control.').toList();
}

_EffectInfoCopy _effectInfoCopy(
  String effectName,
  List<Map<String, dynamic>> params,
) {
  switch (effectName.trim()) {
    case 'Reverb':
      return const _EffectInfoCopy(
        summary: 'Adds room or space around the sound.',
        parameters: <String>[
          'Room Size: space size.',
          'Predelay: time before the room sound starts.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Compressor':
      return const _EffectInfoCopy(
        summary: 'Evens out loud and quiet parts.',
        parameters: <String>[
          'Threshold: level where compression starts.',
          'Ratio: compression strength.',
          'Attack: how fast it grabs peaks.',
          'Release: how fast it lets go.',
          'Makeup: output level after compression.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Dynamic Softener':
      return const _EffectInfoCopy(
        summary: 'Reduces harsh moments without dulling everything.',
        parameters: <String>[
          'Mode: softening style.',
          'Depth: amount of softening.',
          'Focus: detail sensitivity.',
          'Attack: how fast it reacts.',
          'Release: how fast it recovers.',
          'Cut Limit: max reduction.',
        ],
      );
    case 'Transient Shaper':
      return const _EffectInfoCopy(
        summary: 'Changes the punch and tail of hits.',
        parameters: <String>[
          'Attack: front-edge punch.',
          'Sustain: tail length and body.',
          'Pump: movement after the hit.',
          'Speed: response speed.',
          'Clip: catches sharp peaks.',
        ],
      );
    case 'Limiter':
      return const _EffectInfoCopy(
        summary: 'Stops peaks from getting too loud.',
        parameters: <String>[
          'Threshold: level where limiting starts.',
          'Release: recovery speed.',
          'Ceiling: max output level.',
        ],
      );
    case 'Clipper':
    case 'Mixroom Clipper':
      return const _EffectInfoCopy(
        summary: 'Trims peaks for a louder, harder sound.',
        parameters: <String>[
          'Threshold: level where clipping starts.',
          'Ceiling: max output level.',
        ],
      );
    case 'EQ 3-Band':
      return const _EffectInfoCopy(
        summary: 'Quick tone control for lows, mids, and highs.',
        parameters: <String>[
          'Low Gain: bass cut or boost.',
          'Mid Gain: body and presence cut or boost.',
          'High Gain: brightness cut or boost.',
        ],
      );
    case 'Degrade':
      return const _EffectInfoCopy(
        summary: 'Adds digital wear and texture.',
        parameters: <String>[
          'Mode: texture style.',
          'Tone: brightness.',
          'Depth: amount of degradation.',
          'Spread: stereo width.',
        ],
      );
    case 'Delay':
      return const _EffectInfoCopy(
        summary: 'Repeats the sound like an echo.',
        parameters: <String>[
          'Delay Time: spacing between echoes.',
          'Feedback: number of repeats.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'De-Esser':
      return const _EffectInfoCopy(
        summary: 'Reduces sharp S sounds and vocal harshness.',
        parameters: <String>[
          'Frequency: harsh range to target.',
          'Threshold: level where reduction starts.',
          'Amount: reduction strength.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Distortion':
      return const _EffectInfoCopy(
        summary: 'Adds grit, drive, and harmonic color.',
        parameters: <String>[
          'Drive: distortion amount.',
          'Tone: brightness.',
          'Output: level after distortion.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Stereo':
      return const _EffectInfoCopy(
        summary: 'Controls stereo width.',
        parameters: <String>[
          'Width: wider or narrower stereo image.',
          'Low Bypass: keeps bass centered.',
          'Mono: folds the signal to center.',
        ],
      );
    case 'Stereo Pro':
      return const _EffectInfoCopy(
        summary: 'Shapes the stereo image more precisely.',
        parameters: <String>[
          'Gain: output level.',
          'Width: stereo spread.',
          'Asymmetry: left/right balance shape.',
          'Rotation: image angle.',
        ],
      );
    case 'Volume Shaper':
      return const _EffectInfoCopy(
        summary: 'Creates rhythmic volume movement.',
        parameters: <String>[
          'Shape: volume curve.',
          'Rate: movement speed.',
          'Phase: timing offset.',
          'Depth: movement amount.',
          'Smooth: softer edges.',
          'Swing: groove feel.',
        ],
      );
    case 'Time Shaper':
      return const _EffectInfoCopy(
        summary: 'Creates rhythmic timing changes.',
        parameters: <String>[
          'Pattern: timing movement.',
          'Rate: movement speed.',
          'Phase: timing offset.',
          'Amount: effect strength.',
          'Smooth: softer edges.',
          'Swing: groove feel.',
        ],
      );
    case 'Chorus':
      return const _EffectInfoCopy(
        summary: 'Adds a wider, doubled sound.',
        parameters: <String>[
          'Rate: movement speed.',
          'Depth: movement amount.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Vibrato':
      return const _EffectInfoCopy(
        summary: 'Adds pitch movement.',
        parameters: <String>[
          'Rate: movement speed.',
          'Depth: pitch movement amount.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Gain':
      return const _EffectInfoCopy(
        summary: 'Changes overall level.',
        parameters: <String>['Volume: output level.'],
      );
    case 'Pitch Shift':
      return const _EffectInfoCopy(
        summary: 'Moves pitch up or down.',
        parameters: <String>[
          'Semitones: pitch shift amount.',
          'Mix: dry/wet balance.',
        ],
      );
    case 'Pitch Corrector':
      return const _EffectInfoCopy(
        summary: 'Pulls notes toward a key.',
        parameters: <String>[
          'Key: target key.',
          'Scale: allowed notes.',
          'Correction: tuning strength.',
          'Retune Speed: how fast notes move.',
          'Mix: dry/wet balance.',
        ],
      );
    default:
      return _EffectInfoCopy(
        summary: 'Changes this sound.',
        parameters: _parameterNameSummary(params),
      );
  }
}

String _effectInfoBulletText(BuildContext context, String parameter) {
  const fallbackSuffix = ': Plugin control.';
  if (parameter.endsWith(fallbackSuffix)) {
    final name =
        parameter.substring(0, parameter.length - fallbackSuffix.length);
    return '$name: ${L10n.translate(context, 'Plugin control.')}';
  }
  return L10n.translate(context, parameter);
}

Widget _buildEffectInfoButton({
  required BuildContext context,
  required String effectName,
  required List<Map<String, dynamic>> params,
}) {
  final copy = _effectInfoCopy(effectName, params);
  return IconButton(
    tooltip: L10n.translate(context, 'Plugin info'),
    onPressed: () => _showEffectInfoDialog(
      context: context,
      effectName: effectName,
      copy: copy,
    ),
    icon: const Icon(Icons.info_outline_rounded, size: 17),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    color: _kFxPanelText,
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    ),
  );
}

void _showEffectInfoDialog({
  required BuildContext context,
  required String effectName,
  required _EffectInfoCopy copy,
}) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF3B434B),
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  L10n.translate(context, effectName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kFxPanelText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: L10n.translate(context, 'Close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _kFxPanelMutedText,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.translate(context, copy.summary),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kFxPanelText,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  L10n.translate(context, 'Parameters'),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: _kFxPanelMutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final parameter in copy.parameters) ...[
                  _EffectInfoBullet(
                    text: _effectInfoBulletText(context, parameter),
                  ),
                  const SizedBox(height: 7),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L10n.translate(context, 'Close')),
            ),
          ],
        );
      },
    ),
  );
}

class _EffectInfoBullet extends StatelessWidget {
  const _EffectInfoBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(top: 7, right: 9),
          decoration: BoxDecoration(
            color: _kFxCoolAccent.withValues(alpha: 0.86),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: _kFxPanelText,
              fontSize: 12.6,
              height: 1.32,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

enum _RowEffectsMenuAction {
  copy,
  paste,
  clear,
}

enum _MasterEffectsMenuAction {
  copy,
  paste,
  clear,
}

const double _kRowEffectsMenuButtonWidth = 34;
const double _kRowEffectsPresetFadeWidth = 34;
const double _kRowEffectsMenuPanelWidth = 220;
const double _kRowEffectsMenuCloseButtonSize = 28;
const double _kRowEffectsMenuRightOffset = -7;
const double _kRowEffectsMenuTopOffset = -7;
const double _kMasterEffectsMenuRightOffset = 0;
const double _kMasterEffectsMenuTopOffset = -3;
const double _kMasterEffectsMenuInnerRightInset = 3;
const double _kRowEffectsMenuClosedWidthFactor =
    _kRowEffectsMenuButtonWidth / _kRowEffectsMenuPanelWidth;
const double _kRowEffectsMenuClosedHeightFactor = 0.22;

bool _shouldShowDefaultReorderHandles(BuildContext context) {
  return Theme.of(context).platform != TargetPlatform.macOS;
}

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

bool _showsStereoScope(String effectName) {
  return effectName == 'Stereo Pro';
}

bool _showsSpectrumPreview(String effectName) {
  return effectName == 'EQ Parametric' ||
      effectName == 'EQ 3-Band' ||
      effectName == 'Degrade';
}

bool _showsShaperPreview(String effectName) {
  return effectName == 'Volume Shaper' || effectName == 'Time Shaper';
}

bool _showsDynamicSoftenerPreview(String effectName) {
  return effectName == 'Dynamic Softener';
}

bool _showsTransientShaperVisualizer(String effectName) {
  return effectName == 'Transient Shaper';
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

double _gainUiToPercent(double sliderValue, {double uiMax = 3.0}) {
  final db = _gainUiToDb(sliderValue, uiMax: uiMax);
  return (math.pow(10.0, db / 20.0) * 100.0).toDouble();
}

double _gainPercentToUi(
  double percent, {
  required double minValue,
  required double maxValue,
}) {
  const dbMin = -60.0;
  const dbMax = 6.0;
  const uiUnity = 2.0;

  final clampedPercent = percent.clamp(0.1, 200.0).toDouble();
  final db = (20.0 * math.log(clampedPercent / 100.0) / math.ln10)
      .clamp(dbMin, dbMax)
      .toDouble();
  final unity = math.min(uiUnity, maxValue);
  final ui = db <= 0.0
      ? unity * ((db - dbMin) / (0.0 - dbMin)).clamp(0.0, 1.0)
      : unity + ((maxValue - unity) * (db / dbMax).clamp(0.0, 1.0)).toDouble();
  return ui.clamp(minValue, maxValue).toDouble();
}

Future<double?> _showGainPercentDialog({
  required BuildContext context,
  required double value,
  required double minValue,
  required double maxValue,
}) async {
  var percent = _gainUiToPercent(value, uiMax: maxValue);
  final controller = TextEditingController(
    text: percent.toStringAsFixed(1),
  );
  final nextPercent = await showDialog<double>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        title: const Text(
          'Set volume',
          style: TextStyle(color: _kFxPanelText),
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            void setPercent(double next) {
              percent = next.clamp(0.1, 200.0).toDouble();
              controller.text = percent.toStringAsFixed(1);
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
              setDialogState(() {});
            }

            final nextUi = _gainPercentToUi(
              percent,
              minValue: minValue,
              maxValue: maxValue,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Lower volume',
                      onPressed: () => setPercent(percent - 5.0),
                      icon: const Icon(Icons.remove, color: _kFxPanelText),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _kFxPanelText),
                        decoration: InputDecoration(
                          suffixText: '%',
                          suffixStyle: TextStyle(
                            color: _kFxPanelText.withValues(alpha: 0.72),
                          ),
                          helperText: '100% = 0 dB',
                          helperStyle: TextStyle(
                            color: _kFxPanelText.withValues(alpha: 0.62),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                          isDense: true,
                        ),
                        onChanged: (text) {
                          final parsed = double.tryParse(text.trim());
                          if (parsed == null || !parsed.isFinite) {
                            return;
                          }
                          percent = parsed.clamp(0.1, 200.0).toDouble();
                          setDialogState(() {});
                        },
                        onSubmitted: (text) {
                          final parsed = double.tryParse(text.trim());
                          if (parsed != null) {
                            Navigator.pop(dialogContext, parsed);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Raise volume',
                      onPressed: () => setPercent(percent + 5.0),
                      icon: const Icon(Icons.add, color: _kFxPanelText),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _formatGainDb(nextUi, uiMax: maxValue),
                  style: TextStyle(
                    color: _kFxPanelText.withValues(alpha: 0.76),
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Set'),
          ),
        ],
      );
    },
  );
  if (nextPercent == null || !nextPercent.isFinite) return null;
  return _gainPercentToUi(
    nextPercent,
    minValue: minValue,
    maxValue: maxValue,
  );
}

class RowEffectsPanel extends StatefulWidget {
  final int rowIndex;
  final String mode;
  final bool? isProEntitled;
  final VoidCallback? onUpgradeRequested;
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
  final Future<bool> Function(int row, int effectIndex)? openTrackPluginEditor;
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
  final VoidCallback? onCopyRowEffects;
  final Future<void> Function()? onPasteRowEffects;
  final Future<void> Function()? onClearRowEffects;
  final bool hasCopiedRowEffects;

  final MeterBus meters;
  final Future<List<double>> Function(int row, int effectIndex)
      getRowCompressorMeter;
  final Future<List<double>> Function(int row, int effectIndex, int sampleCount)
      getRowEqWaveform;
  final Future<List<double>> Function(int row, int effectIndex, int pointCount)
      getRowStereoScope;
  final MixChangeHighlighter? tutorialHighlighter;

  const RowEffectsPanel({
    Key? key,
    required this.rowIndex,
    required this.mode,
    this.isProEntitled,
    this.onUpgradeRequested,
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
    this.openTrackPluginEditor,
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
    required this.getRowStereoScope,
    this.tutorialHighlighter,
    this.onCopyRowEffects,
    this.onPasteRowEffects,
    this.onClearRowEffects,
    this.hasCopiedRowEffects = false,
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
  int? _draggingEffectIndex;
  bool _rowEffectsMenuOpen = false;

  int? _selectedEffectIndex;
  List<Map<String, dynamic>> _currentParams = [];
  bool _paramsLoading = false;
  int? _returnHighlightedEffectIndex;
  Timer? _returnHighlightTimer;
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
  Timer? _stereoScopeTimer;
  bool _stereoScopeRunning = false;
  List<double> _stereoScope = const <double>[];
  Timer? _shaperPreviewTimer;
  bool _shaperPreviewRunning = false;
  bool _shaperPreviewRequestInFlight = false;
  List<double> _shaperPreview = const <double>[];
  Timer? _softenerPreviewTimer;
  bool _softenerPreviewRunning = false;
  bool _softenerPreviewRequestInFlight = false;
  List<double> _softenerFrame = const <double>[];
  Timer? _transientShaperVisualTimer;
  bool _transientShaperVisualRunning = false;
  bool _transientShaperVisualRequestInFlight = false;
  List<double> _transientShaperVisual = const <double>[];
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

  bool get _isProEntitled => widget.isProEntitled == true;

  bool get _isBasicTier => !_isProEntitled;

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

  void _setReturnHighlight(int? effectIndex) {
    _returnHighlightTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _returnHighlightedEffectIndex = effectIndex;
    });
    if (effectIndex == null) return;
    _returnHighlightTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted || _returnHighlightedEffectIndex != effectIndex) return;
      setState(() {
        _returnHighlightedEffectIndex = null;
      });
    });
  }

  Future<void> _returnToEffectsList({required int effectIndex}) async {
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    _stopStereoScopePolling();
    _stopShaperPreviewPolling();
    _stopTransientShaperVisualPolling();
    _stopDynamicSoftenerPolling();
    setState(() {
      _selectedEffectIndex = null;
      _currentParams = [];
    });
    widget.onHeightChanged(widget.minHeight);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _selectedEffectIndex != null) return;
    _setReturnHighlight(effectIndex);
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
        items: <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'automate',
            height: 34,
            child: Text(L10n.translate(context, 'Automate')),
          ),
        ],
      );
    }
    if (action != 'automate') return;
    _triggerHalos(haloKeys);
    final requestAutomateParameter = widget.onRequestAutomateParameter;
    if (requestAutomateParameter == null) return;
    await requestAutomateParameter(
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
    void showAutomationSheet(Offset globalPosition) {
      _showAutomateParameterSheet(
        effectIndex: effectIndex,
        effectName: effectName,
        paramId: paramId,
        paramName: paramName,
        haloKeys: haloKeys,
        anchorGlobalPos: globalPosition,
      );
    }

    return KeyedSubtree(
      key: ValueKey(
        'row_param_${widget.rowIndex}_${_testKeySlug(effectName)}_${_testKeySlug(paramName)}',
      ),
      child: Builder(
        builder: (gestureContext) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: PlatformCapabilities.current.isDesktop
              ? (details) => showAutomationSheet(details.globalPosition)
              : null,
          onLongPressStart: PlatformCapabilities.current.isDesktop
              ? null
              : (details) {
                  final box = gestureContext.findRenderObject() as RenderBox?;
                  if (box != null &&
                      _isLikelyNumericSliderPress(
                        param: param,
                        localPosition:
                            box.globalToLocal(details.globalPosition),
                        size: box.size,
                      )) {
                    return;
                  }
                  showAutomationSheet(details.globalPosition);
                },
          child: _wrapWithHalos(
            haloKeys: haloKeys,
            borderRadius: borderRadius,
            child: child,
          ),
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
    _returnHighlightTimer?.cancel();
    _deferredParamRefreshTimer?.cancel();
    _pendingParamOverrides.clear();
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    _stopStereoScopePolling();
    _stopShaperPreviewPolling();
    _stopTransientShaperVisualPolling();
    _stopDynamicSoftenerPolling();
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
      _stopStereoScopePolling();
      _stopShaperPreviewPolling();
      _stopDynamicSoftenerPolling();
      _stopTransientShaperVisualPolling();
    } else if (!hadSelection) {
      if (showLoading) {
        setState(() {
          _loading = true;
        });
      }
      _stopEqWaveformPolling();
      _stopStereoScopePolling();
      _stopShaperPreviewPolling();
      _stopDynamicSoftenerPolling();
      _stopTransientShaperVisualPolling();
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
        _stopStereoScopePolling();
        _stopShaperPreviewPolling();
        _stopDynamicSoftenerPolling();
        _stopTransientShaperVisualPolling();
      }
    });
  }

  String _rawEffectIdAt(int idx) {
    if (idx < 0 || idx >= _effectKeys.length) return '';
    final stableKey = _effectKeys[idx];
    final hashIndex = stableKey.lastIndexOf('#');
    if (hashIndex <= 0) return stableKey;
    return stableKey.substring(0, hashIndex);
  }

  bool _isLikelyExternalEffectSlot(int idx) {
    final rawId = _rawEffectIdAt(idx).trim();
    if (rawId.isEmpty) return false;
    final effectName =
        (idx >= 0 && idx < _effects.length) ? _effects[idx].trim() : '';
    return rawId != effectName;
  }

  Future<void> _tryOpenTrackPluginEditor(int idx) async {
    final opener = widget.openTrackPluginEditor;
    if (opener == null || !_isLikelyExternalEffectSlot(idx)) return;
    await opener(widget.rowIndex, idx);
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
    final customLabel = L10n.translate(context, 'Custom');
    final presetLabel =
        detectedIdx == null ? customLabel : kDelayDivisions[detectedIdx].label;

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
              SizedBox(
                width: 136,
                child: _buildMixroomChoiceField(
                  context: context,
                  value: presetLabel,
                  compact: true,
                  onTap: () async {
                    final labels = <String>[
                      customLabel,
                      ...kDelayDivisions.map((d) => d.label),
                    ];
                    final picked = await _showMixroomChoiceDialog(
                      context: context,
                      title:
                          '${L10n.translate(context, 'Select ')}${param['name']}',
                      choices: labels,
                      currentChoice: presetLabel,
                    );
                    if (picked == null || picked == customLabel) {
                      return;
                    }

                    final division =
                        kDelayDivisions.firstWhere((d) => d.label == picked);
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
    void commitImmediate(double nextValue) {
      final target = nextValue.clamp(minV, maxV).toDouble();
      final oldValue = ((param['value'] as num?)?.toDouble() ?? rawV)
          .clamp(minV, maxV)
          .toDouble();
      if ((oldValue - target).abs() < 1.0e-6) return;
      setState(() => param['value'] = target);
      _setTrackEffectParam(widget.rowIndex, effectIndex, paramName, target);
      _commitTrackEffectParam(
        widget.rowIndex,
        effectIndex,
        paramName,
        oldValue,
        target,
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
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final target =
                        (defaultValue ?? unity).clamp(minV, maxV).toDouble();
                    commitImmediate(target);
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
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (!mounted) return;
                      final next = await _showGainPercentDialog(
                        context: context,
                        value: rawV,
                        minValue: minV,
                        maxValue: maxV,
                      );
                      if (next == null || !mounted) return;
                      commitImmediate(next);
                    });
                  },
                  child: Center(
                    child: Text(
                      _formatGainDb(rawV, uiMax: maxV),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
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
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
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

  void _startStereoScopePolling({required int effectIndex}) {
    _stopStereoScopePolling();
    _stereoScopeRunning = true;

    _stereoScopeTimer =
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
      if (!mounted || !_stereoScopeRunning) return;

      try {
        final arr =
            await widget.getRowStereoScope(widget.rowIndex, effectIndex, 256);
        if (!mounted || !_stereoScopeRunning) return;
        setState(() {
          _stereoScope = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      }
    });
  }

  void _stopStereoScopePolling() {
    _stereoScopeRunning = false;
    _stereoScopeTimer?.cancel();
    _stereoScopeTimer = null;
    _stereoScope = const <double>[];
  }

  void _startShaperPreviewPolling({required int effectIndex}) {
    _stopShaperPreviewPolling();
    _shaperPreviewRunning = true;
    _shaperPreviewRequestInFlight = false;

    _shaperPreviewTimer =
        Timer.periodic(_kShaperPreviewPollInterval, (_) async {
      if (!mounted || !_shaperPreviewRunning || _shaperPreviewRequestInFlight) {
        return;
      }
      _shaperPreviewRequestInFlight = true;

      try {
        final arr = await JuceAudioEngine.getRowShaperPreview(
          widget.rowIndex,
          effectIndex,
          pointCount: 192,
        );
        if (!mounted || !_shaperPreviewRunning) return;
        if (!_previewFramesChanged(_shaperPreview, arr)) return;
        setState(() {
          _shaperPreview = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _shaperPreviewRequestInFlight = false;
      }
    });
  }

  void _stopShaperPreviewPolling() {
    _shaperPreviewRunning = false;
    _shaperPreviewRequestInFlight = false;
    _shaperPreviewTimer?.cancel();
    _shaperPreviewTimer = null;
    _shaperPreview = const <double>[];
  }

  void _startDynamicSoftenerPolling({required int effectIndex}) {
    _stopDynamicSoftenerPolling();
    _softenerPreviewRunning = true;
    _softenerPreviewRequestInFlight = false;

    Future<void> fetchFrame() async {
      if (!mounted ||
          !_softenerPreviewRunning ||
          _softenerPreviewRequestInFlight) {
        return;
      }
      _softenerPreviewRequestInFlight = true;

      try {
        final arr = await JuceAudioEngine.getRowDynamicSoftenerFrame(
          widget.rowIndex,
          effectIndex,
        );
        if (!mounted || !_softenerPreviewRunning) return;
        if (!_previewFramesChanged(_softenerFrame, arr, tolerance: 0.0005)) {
          return;
        }
        setState(() {
          _softenerFrame = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _softenerPreviewRequestInFlight = false;
      }
    }

    unawaited(fetchFrame());
    _softenerPreviewTimer =
        Timer.periodic(_kDynamicSoftenerPollInterval, (_) => fetchFrame());
  }

  void _stopDynamicSoftenerPolling() {
    _softenerPreviewRunning = false;
    _softenerPreviewRequestInFlight = false;
    _softenerPreviewTimer?.cancel();
    _softenerPreviewTimer = null;
    _softenerFrame = const <double>[];
  }

  void _startTransientShaperVisualPolling({required int effectIndex}) {
    _stopTransientShaperVisualPolling();
    _transientShaperVisualRunning = true;
    _transientShaperVisualRequestInFlight = false;

    _transientShaperVisualTimer =
        Timer.periodic(_kShaperPreviewPollInterval, (_) async {
      if (!mounted ||
          !_transientShaperVisualRunning ||
          _transientShaperVisualRequestInFlight) {
        return;
      }
      _transientShaperVisualRequestInFlight = true;

      try {
        final arr = await JuceAudioEngine.getRowTransientShaperVisual(
          widget.rowIndex,
          effectIndex,
          pointCount: 192,
        );
        if (!mounted || !_transientShaperVisualRunning) return;
        if (!_previewFramesChanged(_transientShaperVisual, arr)) return;
        setState(() {
          _transientShaperVisual = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _transientShaperVisualRequestInFlight = false;
      }
    });
  }

  void _stopTransientShaperVisualPolling() {
    _transientShaperVisualRunning = false;
    _transientShaperVisualRequestInFlight = false;
    _transientShaperVisualTimer?.cancel();
    _transientShaperVisualTimer = null;
    _transientShaperVisual = const <double>[];
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
    return exposedEffectParameters(effectName, params);
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

  Future<void> _handleRowEffectsMenuAction(_RowEffectsMenuAction action) async {
    if (mounted) {
      setState(() {
        _rowEffectsMenuOpen = false;
      });
    }
    switch (action) {
      case _RowEffectsMenuAction.copy:
        widget.onCopyRowEffects?.call();
        break;
      case _RowEffectsMenuAction.paste:
        await widget.onPasteRowEffects?.call();
        break;
      case _RowEffectsMenuAction.clear:
        await widget.onClearRowEffects?.call();
        break;
    }
    if (!mounted) return;
    if (action != _RowEffectsMenuAction.copy) {
      await _loadEffects(showLoading: false);
    } else {
      setState(() {});
    }
  }

  Widget _buildRowEffectsMenuButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('row_effects_menu_${widget.rowIndex}'),
          onTap: () {
            setState(() {
              _rowEffectsMenuOpen = !_rowEffectsMenuOpen;
            });
          },
          borderRadius: BorderRadius.circular(999),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.06);
              }
              return null;
            },
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            width: _kRowEffectsMenuButtonWidth,
            height: 34,
            decoration: _mixroomFxInsetDecoration(
              radius: 999,
              selected: _rowEffectsMenuOpen,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Spacer(),
                Icon(Icons.more_horiz, size: 18, color: _kFxPanelText),
                Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowEffectsMenuPanel(BuildContext context) {
    Widget actionTile({
      required String title,
      required _RowEffectsMenuAction action,
      required bool enabled,
    }) {
      final actionSlug = switch (action) {
        _RowEffectsMenuAction.copy => 'copy',
        _RowEffectsMenuAction.paste => 'paste',
        _RowEffectsMenuAction.clear => 'clear',
      };
      return Opacity(
        opacity: enabled ? 1.0 : 0.46,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(
                'row_effects_menu_action_${widget.rowIndex}_$actionSlug'),
            onTap: enabled
                ? () => unawaited(_handleRowEffectsMenuAction(action))
                : null,
            borderRadius: BorderRadius.circular(14),
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.05);
                }
                return null;
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: _mixroomFxInsetDecoration(radius: 14),
              child: Text(
                L10n.translate(context, title),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kFxPanelText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('row_effects_menu_panel_${widget.rowIndex}'),
      padding: const EdgeInsets.all(10),
      decoration: _mixroomFxSurfaceDecoration(radius: 18, active: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                L10n.translate(context, 'Row effects'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kFxPanelText,
                  fontSize: 13.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('row_effects_menu_close_${widget.rowIndex}'),
                  onTap: () {
                    setState(() {
                      _rowEffectsMenuOpen = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(WidgetState.pressed)) {
                        return Colors.white.withValues(alpha: 0.12);
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return Colors.white.withValues(alpha: 0.05);
                      }
                      return null;
                    },
                  ),
                  child: Container(
                    width: _kRowEffectsMenuCloseButtonSize,
                    height: _kRowEffectsMenuCloseButtonSize,
                    decoration: _mixroomFxInsetDecoration(radius: 999),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: _kFxPanelText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          actionTile(
            title: 'Copy effects',
            action: _RowEffectsMenuAction.copy,
            enabled: widget.onCopyRowEffects != null,
          ),
          const SizedBox(height: 8),
          actionTile(
            title: 'Paste effects',
            action: _RowEffectsMenuAction.paste,
            enabled:
                widget.hasCopiedRowEffects && widget.onPasteRowEffects != null,
          ),
          const SizedBox(height: 8),
          actionTile(
            title: 'Clear effects',
            action: _RowEffectsMenuAction.clear,
            enabled: widget.onClearRowEffects != null,
          ),
        ],
      ),
    );
  }

  Widget _buildPresetStrip(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 34,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: <double>[0.0, 0.82, 0.93, 1.0],
                ).createShader(bounds);
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                  right: _kRowEffectsPresetFadeWidth + 6,
                ),
                child: Row(
                  children: [
                    _buildPresetChip("Concert Hall"),
                    const SizedBox(width: 6),
                    _buildPresetChip("Echoes"),
                    const SizedBox(width: 6),
                    _buildPresetChip("LoFi Effect"),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildRowEffectsMenuButton(context),
      ],
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: _buildPresetStrip(context),
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
                      buildDefaultDragHandles:
                          _shouldShowDefaultReorderHandles(context),
                      padding: EdgeInsets.zero,
                      onReorderStart: (index) {
                        setState(() {
                          _draggingEffectIndex = index;
                        });
                      },
                      onReorderEnd: (_) {
                        if (_draggingEffectIndex == null) return;
                        setState(() {
                          _draggingEffectIndex = null;
                        });
                      },
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
                    padding: const EdgeInsets.only(top: 4.0, left: 0.0),
                    child: _buildAddTile()),
            ],
          ),
          Positioned(
            top: _kRowEffectsMenuTopOffset,
            right: _kRowEffectsMenuRightOffset,
            child: IgnorePointer(
              ignoring: !_rowEffectsMenuOpen,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: _rowEffectsMenuOpen ? 1.0 : 0.0,
                ),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  if (t <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  final widthFactor = _kRowEffectsMenuClosedWidthFactor +
                      ((1.0 - _kRowEffectsMenuClosedWidthFactor) * t);
                  final heightFactor = _kRowEffectsMenuClosedHeightFactor +
                      ((1.0 - _kRowEffectsMenuClosedHeightFactor) * t);
                  return Opacity(
                    opacity: t,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Align(
                        alignment: Alignment.topRight,
                        widthFactor: widthFactor,
                        heightFactor: heightFactor,
                        child: Transform.translate(
                          offset: Offset((1.0 - t) * 8, (1.0 - t) * -4),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kRowEffectsMenuPanelWidth,
                  ),
                  child: _buildRowEffectsMenuPanel(context),
                ),
              ),
            ),
          ),
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
        final h = math.max(box.size.height, widget.minHeight);

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
          : const Color.fromRGBO(244, 244, 244, 0.16),
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
                  : _kFxPanelText,
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
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
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
          exposedEffectParameterValues(_effects[i], params)));
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
        await widget.insertEffectOnRow(widget.rowIndex, 'EQ 3-Band');
        await _setTrackEffectParam(widget.rowIndex, 1, 'Low Gain', -1.0);
        await _setTrackEffectParam(widget.rowIndex, 1, 'Mid Gain', 0.6);
        await _setTrackEffectParam(widget.rowIndex, 1, 'High Gain', 1.2);
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
          exposedEffectParameterValues(_effects[i], params)));
    }
    final after = RowEffectsSnapshot(widget.rowIndex, afterSnapshots);
    widget.onPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildEffectTile(int idx) {
    final isDragging = _draggingEffectIndex == idx;
    final showReturnHighlight = _returnHighlightedEffectIndex == idx;
    final tile = AnimatedContainer(
      key: ValueKey("effect_${_effectKeys[idx]}"),
      duration: const Duration(milliseconds: 170),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: isDragging
          ? _mixroomFxInsetDecoration(radius: 14, selected: true)
          : showReturnHighlight
              ? _mixroomFxReturnHighlightDecoration(radius: 14)
              : const BoxDecoration(color: Colors.transparent),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          minLeadingWidth: 22,
          horizontalTitleGap: 4,
          contentPadding: const EdgeInsets.symmetric(horizontal: 2),

          // only this area starts the reorder gesture
          leading: ReorderableDragStartListener(
            index: idx,
            child: const Padding(
              padding: EdgeInsets.only(left: 2.0, right: 2.0),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 18,
                color: Color(0xCCF4F4F4),
              ),
            ),
          ),

          title: Text(
            L10n.translate(context, _effects[idx]),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kFxPanelText,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Switch(
                    value: !_bypassed[idx],
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    activeColor: const Color(0xFFF4F4F4),
                    inactiveThumbColor: const Color(0xFFB8BDC3),
                    inactiveTrackColor: const Color(0xFFDFE2E5),
                    activeTrackColor: const Color(0xFF545A60),
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Color.fromARGB(255, 255, 164, 164),
                ),
                onPressed: () => _confirmRemove(idx),
              ),
            ],
          ),

          onTap: () async {
            final liveIdx = await _resolveLiveEffectIndex(idx);
            final targetIdx = liveIdx >= 0 ? liveIdx : idx;
            await _openPluginParams(targetIdx);
          },
        ),
      ),
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
    final tile = Container(
      key: const ValueKey("add_effect"),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          minLeadingWidth: 26,
          horizontalTitleGap: 6,
          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
          leading: const Icon(
            Icons.add_circle_outline,
            color: _kFxPanelText,
            size: 19,
          ),
          title: Text(
            L10n.translate(context, 'Add Effect'),
            style: const TextStyle(
              color: _kFxPanelText,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          onTap: _showAddEffectModal,
        ),
      ),
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
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
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
    List<Map<String, dynamic>> plugins;
    try {
      plugins = await widget.scanPlugins();
    } catch (_) {
      plugins = const <Map<String, dynamic>>[];
    }
    final externalEffects = plugins.where((plugin) {
      final category =
          (plugin['category'] ?? '').toString().trim().toLowerCase();
      final isInstrument = plugin['isInstrument'] == true;
      return !isInstrument && category != 'instrument';
    }).toList(growable: false);
    const allFxChoices = [
      "Gain",
      "Reverb",
      "EQ 3-Band",
      "EQ Parametric",
      "Delay",
      "Compressor",
      "Dynamic Softener",
      "Transient Shaper",
      "Clipper",
      "Limiter",
      "Distortion",
      "Degrade",
      "Pitch Shift",
      "Pitch Corrector",
      "De-Esser",
      "Stereo",
      "Stereo Pro",
      "Volume Shaper",
      "Time Shaper",
      "Chorus",
      "Vibrato",
    ];
    const fxChoices = allFxChoices;

    // Dialog can use scrolling; this is outside the row panel layout.
    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color(0xFF5F666D),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            title: Container(
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: _mixroomFxInsetDecoration(radius: 18),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.zero,
                indicator: BoxDecoration(
                  color: _kFxPanelFillStrong,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
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
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    itemBuilder: (context, i) {
                      final name = fxChoices[i];
                      final isAllowed = !_isBasicTier ||
                          SubscriptionLimits.freeBuiltInEffects.contains(name);
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
                            : () => _showPluginUpgradeDialog(
                                  context,
                                  onUpgradeRequested: widget.onUpgradeRequested,
                                ),
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            title: Text(
                              L10n.translate(context, name),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.2),
                            ),
                            trailing: isAllowed
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        L10n.translate(context, 'Starter'),
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.72),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                  ListView.separated(
                    itemCount:
                        externalEffects.isEmpty ? 1 : externalEffects.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      if (externalEffects.isEmpty) {
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          title: Text(
                            L10n.translate(
                              context,
                              'No external plugins found',
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13.0,
                            ),
                          ),
                        );
                      }
                      final meta = externalEffects[i];
                      final path = (meta['id'] ?? '').toString();
                      if (path.isEmpty) return const SizedBox.shrink();
                      final name = (meta['name'] ?? path).toString();
                      final format = (meta['format'] ?? '').toString();
                      final manufacturer =
                          (meta['manufacturer'] ?? '').toString();
                      final isAllowed = !_isBasicTier;
                      final details = <String>[
                        if (format.isNotEmpty) format,
                        if (manufacturer.isNotEmpty) manufacturer,
                      ];
                      return Opacity(
                        opacity: isAllowed ? 1.0 : 0.45,
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
                          trailing: isAllowed
                              ? null
                              : const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: Colors.white70,
                                ),
                          onTap: isAllowed
                              ? () async {
                                  Navigator.pop(context);
                                  await widget.insertEffectOnRow(
                                      widget.rowIndex, path);
                                  await _loadEffects();
                                  final addedIndex = _effects.length - 1;
                                  if (addedIndex >= 0 &&
                                      addedIndex < _effects.length) {
                                    await _tryOpenTrackPluginEditor(addedIndex);
                                    widget.onTutorialEffectAdded?.call(
                                      widget.rowIndex,
                                      addedIndex,
                                      _effects[addedIndex],
                                    );
                                  }
                                }
                              : () => _showPluginUpgradeDialog(
                                    context,
                                    onUpgradeRequested:
                                        widget.onUpgradeRequested,
                                  ),
                        ),
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

    if (_isLikelyExternalEffectSlot(idx)) {
      _stopCompressorMetering();
      _stopEqWaveformPolling();
      _stopStereoScopePolling();
      _stopShaperPreviewPolling();
      _stopDynamicSoftenerPolling();
      _stopTransientShaperVisualPolling();
      setState(() {
        _rowEffectsMenuOpen = false;
        _selectedEffectIndex = null;
        _paramsLoading = false;
        _currentParams = [];
        _returnHighlightedEffectIndex = null;
      });
      await _tryOpenTrackPluginEditor(idx);
      return;
    }

    widget.onTutorialEffectOpened?.call(
      widget.rowIndex,
      idx,
      idx >= 0 && idx < _effects.length ? _effects[idx] : 'Effect',
    );

    setState(() {
      _rowEffectsMenuOpen = false;
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
      _returnHighlightedEffectIndex = null;
    });
    unawaited(_tryOpenTrackPluginEditor(idx));

    // Turn on dynamics reduction metering if it is about to be opened
    if (_showsDynamicsReductionMeter(_effects[idx])) {
      _startCompressorMetering(effectIndex: idx);
    } else {
      _stopCompressorMetering();
    }
    if (_showsSpectrumPreview(_effects[idx])) {
      _startEqWaveformPolling(effectIndex: idx);
    } else {
      _stopEqWaveformPolling();
    }
    if (_showsStereoScope(_effects[idx])) {
      _startStereoScopePolling(effectIndex: idx);
    } else {
      _stopStereoScopePolling();
    }
    if (_showsShaperPreview(_effects[idx])) {
      _startShaperPreviewPolling(effectIndex: idx);
    } else {
      _stopShaperPreviewPolling();
    }
    if (_showsTransientShaperVisualizer(_effects[idx])) {
      _startTransientShaperVisualPolling(effectIndex: idx);
    } else {
      _stopTransientShaperVisualPolling();
    }
    if (_showsDynamicSoftenerPreview(_effects[idx])) {
      _startDynamicSoftenerPolling(effectIndex: idx);
    } else {
      _stopDynamicSoftenerPolling();
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

      _EqFaderSpec buildEqFader(
        Map<String, dynamic> param, {
        required String label,
        required String unit,
        bool logarithmic = false,
      }) {
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
            final startValue =
                _EQParamStartValue ?? (param['value'] as num).toDouble();
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
          onValueTap: () async {
            final oldValue = (param['value'] as num).toDouble();
            final picked = await _showNumericParamEntryDialog(
              context: context,
              param: param,
              currentValue: oldValue,
            );
            if (!mounted || picked == null) return;
            final nextValue = picked
                .clamp(
                  (param['min'] as num).toDouble(),
                  (param['max'] as num).toDouble(),
                )
                .toDouble();
            if ((oldValue - nextValue).abs() < 1.0e-6) return;
            setState(() => param['value'] = nextValue);
            _setTrackEffectParam(widget.rowIndex, idx, name, nextValue);
            _commitTrackEffectParam(
              widget.rowIndex,
              idx,
              name,
              oldValue,
              nextValue,
            );
          },
        );
      }

      final gainFaders = <_EqFaderSpec>[
        if (pB1 != null) buildEqFader(pB1, label: 'Band 1', unit: 'dB'),
        if (pB2 != null) buildEqFader(pB2, label: 'Band 2', unit: 'dB'),
        if (pB3 != null) buildEqFader(pB3, label: 'Band 3', unit: 'dB'),
        if (pB4 != null) buildEqFader(pB4, label: 'Band 4', unit: 'dB'),
      ];
      final frequencyFaders = <_EqFaderSpec>[
        if (pB1Freq != null)
          buildEqFader(
            pB1Freq,
            label: 'Band 1',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB2Freq != null)
          buildEqFader(
            pB2Freq,
            label: 'Band 2',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB3Freq != null)
          buildEqFader(
            pB3Freq,
            label: 'Band 3',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB4Freq != null)
          buildEqFader(
            pB4Freq,
            label: 'Band 4',
            unit: 'Hz',
            logarithmic: true,
          ),
      ];
      final qFaders = <_EqFaderSpec>[
        if (pB1Q != null) buildEqFader(pB1Q, label: 'Band 1', unit: 'Q'),
        if (pB2Q != null) buildEqFader(pB2Q, label: 'Band 2', unit: 'Q'),
        if (pB3Q != null) buildEqFader(pB3Q, label: 'Band 3', unit: 'Q'),
        if (pB4Q != null) buildEqFader(pB4Q, label: 'Band 4', unit: 'Q'),
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
              final startValue =
                  _EQParamStartValue ?? (pHPF['value'] as num).toDouble();
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
              final startValue =
                  _EQParamStartValue ?? (pLPF['value'] as num).toDouble();
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
                _buildFxParamsHeader(
                  context: context,
                  title: effectName,
                  onBack: () => _returnToEffectsList(effectIndex: idx),
                  onReset: () async {
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
                ),
                const SizedBox(height: 10),
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

      Future<void> typeEq3BandValue(Map<String, dynamic> param) async {
        final name = param['name'] as String;
        final oldValue = (param['value'] as num).toDouble();
        final picked = await _showNumericParamEntryDialog(
          context: context,
          param: param,
          currentValue: oldValue,
        );
        if (!mounted || picked == null) return;
        final nextValue = picked
            .clamp(
              (param['min'] as num).toDouble(),
              (param['max'] as num).toDouble(),
            )
            .toDouble();
        if ((oldValue - nextValue).abs() < 1.0e-6) return;
        setState(() => param['value'] = nextValue);
        _setTrackEffectParam(widget.rowIndex, idx, name, nextValue);
        _commitTrackEffectParam(
          widget.rowIndex,
          idx,
          name,
          oldValue,
          nextValue,
        );
      }

      return _wrapWithHalos(
          haloKeys: effectPageHaloKeys,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFxParamsHeader(
                  context: context,
                  title: effectName,
                  onBack: () => _returnToEffectsList(effectIndex: idx),
                  trailing: _buildEffectInfoButton(
                    context: context,
                    effectName: effectName,
                    params: _currentParams,
                  ),
                ),
                const SizedBox(height: 10),
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
                                      onValueTap: () =>
                                          unawaited(typeEq3BandValue(pLow)),
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
                                        final startValue = _EQParamStartValue ??
                                            (pLow['value'] as num).toDouble();
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pLow['name'] as String,
                                          startValue,
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
                                      onValueTap: () =>
                                          unawaited(typeEq3BandValue(pMid)),
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
                                        final startValue = _EQParamStartValue ??
                                            (pMid['value'] as num).toDouble();
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pMid['name'] as String,
                                          startValue,
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
                                      onValueTap: () =>
                                          unawaited(typeEq3BandValue(pHigh)),
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
                                        final startValue = _EQParamStartValue ??
                                            (pHigh['value'] as num).toDouble();
                                        _commitTrackEffectParam(
                                          widget.rowIndex,
                                          idx,
                                          pHigh['name'] as String,
                                          startValue,
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

    // Generic parameter page
    return _wrapWithHalos(
        haloKeys: effectPageHaloKeys,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFxParamsHeader(
                context: context,
                title: effectName,
                onBack: () => _returnToEffectsList(effectIndex: idx),
                trailing: _buildEffectInfoButton(
                  context: context,
                  effectName: effectName,
                  params: _currentParams,
                ),
              ),
              const SizedBox(height: 10),

              if (effectName == 'Stereo Pro' && _currentParams.isNotEmpty) ...[
                _StereoProPreview(
                  scopeFrames: _stereoScope,
                  gainDb:
                      (_paramByName(_currentParams, 'Gain')?['value'] as num?)
                              ?.toDouble() ??
                          0.0,
                  widthPercent:
                      (_paramByName(_currentParams, 'Width')?['value'] as num?)
                              ?.toDouble() ??
                          100.0,
                  asymmetryPercent:
                      (_paramByName(_currentParams, 'Asymmetry')?['value']
                                  as num?)
                              ?.toDouble() ??
                          0.0,
                  rotationDegrees:
                      (_paramByName(_currentParams, 'Rotation')?['value']
                                  as num?)
                              ?.toDouble() ??
                          0.0,
                ),
                const SizedBox(height: 12),
              ],

              if (effectName == 'Degrade' && _currentParams.isNotEmpty) ...[
                _DegradePreview(
                  spectrumDb: _eqSpectrumDb,
                  analyzerSampleRate: _eqAnalyzerSampleRate,
                  mode: (_paramByName(_currentParams, 'Mode')?['value']
                              ?.toString() ??
                          'Noise')
                      .trim(),
                  toneHz:
                      (_paramByName(_currentParams, 'Tone')?['value'] as num?)
                              ?.toDouble() ??
                          6000.0,
                  depthPercent:
                      (_paramByName(_currentParams, 'Depth')?['value'] as num?)
                              ?.toDouble() ??
                          35.0,
                  spreadPercent:
                      (_paramByName(_currentParams, 'Spread')?['value'] as num?)
                              ?.toDouble() ??
                          40.0,
                ),
                const SizedBox(height: 12),
              ],

              if (_showsTransientShaperVisualizer(effectName) &&
                  _currentParams.isNotEmpty) ...[
                _TransientShaperVisualizerCard(
                  frames: _transientShaperVisual,
                  attackPercent:
                      (_paramByName(_currentParams, 'Attack')?['value'] as num?)
                              ?.toDouble() ??
                          0.0,
                  pumpPercent:
                      (_paramByName(_currentParams, 'Pump')?['value'] as num?)
                              ?.toDouble() ??
                          0.0,
                  sustainPercent:
                      (_paramByName(_currentParams, 'Sustain')?['value']
                                  as num?)
                              ?.toDouble() ??
                          0.0,
                  speedPercent:
                      (_paramByName(_currentParams, 'Speed')?['value'] as num?)
                              ?.toDouble() ??
                          65.0,
                  clip: (_paramByName(_currentParams, 'Clip')?['value']
                          as bool?) ??
                      false,
                ),
                const SizedBox(height: 12),
              ],

              if (_showsDynamicSoftenerPreview(effectName)) ...[
                _DynamicSoftenerPreview(
                  frame: _softenerFrame,
                  mode: (_paramByName(_currentParams, 'Mode')?['value'] ??
                          'Gentle')
                      .toString(),
                  depthPercent:
                      (_paramByName(_currentParams, 'Depth')?['value'] as num?)
                              ?.toDouble() ??
                          55.0,
                  detailPercent:
                      (_paramByName(_currentParams, 'Focus')?['value'] as num?)
                              ?.toDouble() ??
                          55.0,
                  maxCutDb: (_paramByName(_currentParams, 'Cut Limit')?['value']
                              as num?)
                          ?.toDouble() ??
                      18.0,
                  lowRangeHz:
                      (_paramByName(_currentParams, 'Low Range')?['value']
                                  as num?)
                              ?.toDouble() ??
                          20.0,
                  highRangeHz:
                      (_paramByName(_currentParams, 'High Range')?['value']
                                  as num?)
                              ?.toDouble() ??
                          20000.0,
                ),
                const SizedBox(height: 12),
              ],

              if (_showsShaperPreview(effectName) &&
                  _currentParams.isNotEmpty) ...[
                _ShaperPreviewCard(
                  kind: effectName == 'Time Shaper'
                      ? _ShaperPreviewKind.time
                      : _ShaperPreviewKind.volume,
                  previewFrames: _shaperPreview,
                  title: ((_paramByName(
                            _currentParams,
                            effectName == 'Time Shaper' ? 'Pattern' : 'Shape',
                          )?['value']) ??
                          (effectName == 'Time Shaper' ? 'Pattern' : 'Shape'))
                      .toString(),
                  detail: ((_paramByName(_currentParams, 'Rate')?['value']) ??
                          'Rate')
                      .toString(),
                ),
                const SizedBox(height: 12),
              ],

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
                    child: _buildGenericFloatParamEditor(
                      context: context,
                      effectName: _effects[idx],
                      param: param,
                      setLocalValue: (value) =>
                          setState(() => param['value'] = value),
                      setRemoteValue: (value) => _setTrackEffectParam(
                        widget.rowIndex,
                        idx,
                        param['name'] as String,
                        value,
                      ),
                      commitValue: (oldValue, newValue) =>
                          _commitTrackEffectParam(
                        widget.rowIndex,
                        idx,
                        param['name'] as String,
                        oldValue,
                        newValue,
                      ),
                      setDragStartValue: (value) =>
                          _paramDragStartValue = value,
                      getDragStartValue: () => _paramDragStartValue,
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
                        child: (effectName == 'Degrade' ||
                                    effectName == 'Dynamic Softener') &&
                                param['name'] == 'Mode'
                            ? _buildDegradeModeSelectorTile(
                                context: context,
                                label: param['name'] as String,
                                value: current,
                                choices: choices,
                                oneRow: effectName == 'Dynamic Softener',
                                onSelected: (picked) {
                                  if (picked == current) return;
                                  final oldVal = param['value'];
                                  setState(() => param['value'] = picked);
                                  _setTrackEffectParam(widget.rowIndex, idx,
                                      param['name'] as String, picked);
                                  _commitTrackEffectParam(widget.rowIndex, idx,
                                      param['name'] as String, oldVal, picked);
                                },
                              )
                            : _buildMixroomChoiceSettingTile(
                                context: context,
                                label: param['name'] as String,
                                value: current,
                                onTap: () async {
                                  final picked = await _showMixroomChoiceDialog(
                                    context: context,
                                    title:
                                        '${L10n.translate(context, 'Select ')}${param['name']}',
                                    choices: choices,
                                    currentChoice: current,
                                  );
                                  if (picked != null) {
                                    final oldVal = param['value'];
                                    setState(() => param['value'] = picked);
                                    _setTrackEffectParam(widget.rowIndex, idx,
                                        param['name'] as String, picked);
                                    _commitTrackEffectParam(
                                        widget.rowIndex,
                                        idx,
                                        param['name'] as String,
                                        oldVal,
                                        picked);
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
  final VoidCallback? onUpgradeRequested;

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
  final Future<bool> Function(int effectIndex)? openMasterPluginEditor;
  final void Function(
          int effectIndex, String paramId, dynamic oldValue, dynamic newValue)?
      onMasterPluginParamCommit;
  final void Function(
          MasterEffectsSnapshot before, MasterEffectsSnapshot after)?
      onMasterPresetCommit;
  final VoidCallback? onCopyMasterEffects;
  final Future<void> Function()? onPasteMasterEffects;
  final Future<void> Function()? onClearMasterEffects;
  final bool hasCopiedMasterEffects;

  final void Function(double height)? onHeightChanged;
  final double projectBpm;

  final MeterBus meters;
  final Future<List<double>> Function(int effectIndex) getMasterCompressorMeter;
  final Future<List<double>> Function(int effectIndex, int sampleCount)
      getMasterEqWaveform;
  final Future<List<double>> Function(int effectIndex, int pointCount)
      getMasterStereoScope;
  final MixChangeHighlighter? highlighter;
  final void Function(
    Future<void> Function(int effectIndex, String paramId) reveal,
  )? registerParameterRevealer;

  const MasterEffectsPanel({
    Key? key,
    required this.mode,
    this.isProEntitled,
    this.onUpgradeRequested,
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
    this.openMasterPluginEditor,
    this.onHeightChanged,
    this.onMasterPluginParamCommit,
    this.onMasterPresetCommit,
    this.onCopyMasterEffects,
    this.onPasteMasterEffects,
    this.onClearMasterEffects,
    this.hasCopiedMasterEffects = false,
    required this.projectBpm,
    required this.meters,
    required this.getMasterCompressorMeter,
    required this.getMasterEqWaveform,
    required this.getMasterStereoScope,
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
  bool _masterEffectsMenuOpen = false;

  int? _selectedEffectIndex;
  List<Map<String, dynamic>> _currentParams = [];
  bool _paramsLoading = false;
  int? _returnHighlightedEffectIndex;
  Timer? _returnHighlightTimer;

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
  Timer? _stereoScopeTimer;
  bool _stereoScopeRunning = false;
  List<double> _stereoScope = const <double>[];
  Timer? _shaperPreviewTimer;
  bool _shaperPreviewRunning = false;
  bool _shaperPreviewRequestInFlight = false;
  List<double> _shaperPreview = const <double>[];
  Timer? _softenerPreviewTimer;
  bool _softenerPreviewRunning = false;
  bool _softenerPreviewRequestInFlight = false;
  List<double> _softenerFrame = const <double>[];
  Timer? _transientShaperVisualTimer;
  bool _transientShaperVisualRunning = false;
  bool _transientShaperVisualRequestInFlight = false;
  List<double> _transientShaperVisual = const <double>[];
  double _eqAnalyzerSampleRate = 44100.0;
  int _eqParametricTabIndex = 0;

  bool get _isProEntitled => widget.isProEntitled == true;

  bool get _isBasicTier => !_isProEntitled;

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
    Key? key,
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

  void _setReturnHighlight(int? effectIndex) {
    _returnHighlightTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _returnHighlightedEffectIndex = effectIndex;
    });
    if (effectIndex == null) return;
    _returnHighlightTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted || _returnHighlightedEffectIndex != effectIndex) return;
      setState(() {
        _returnHighlightedEffectIndex = null;
      });
    });
  }

  Future<void> _returnToEffectsList({required int effectIndex}) async {
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    _stopStereoScopePolling();
    _stopShaperPreviewPolling();
    _stopTransientShaperVisualPolling();
    _stopDynamicSoftenerPolling();
    setState(() {
      _selectedEffectIndex = null;
      _currentParams = [];
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _selectedEffectIndex != null) return;
    _setReturnHighlight(effectIndex);
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
        items: <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'automate',
            height: 34,
            child: Text(L10n.translate(context, 'Automate')),
          ),
        ],
      );
    }
    if (action != 'automate') return;
    _triggerHalos(haloKeys);
    final requestAutomateParameter = widget.onRequestAutomateParameter;
    if (requestAutomateParameter == null) return;
    await requestAutomateParameter(
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
    void showAutomationSheet(Offset globalPosition) {
      _showAutomateParameterSheet(
        effectIndex: effectIndex,
        effectName: effectName,
        paramId: paramId,
        paramName: paramName,
        haloKeys: haloKeys,
        anchorGlobalPos: globalPosition,
      );
    }

    return KeyedSubtree(
      key: ValueKey(
        'master_param_${effectIndex}_${_testKeySlug(effectName)}_${_testKeySlug(paramName)}',
      ),
      child: Builder(
        builder: (gestureContext) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: PlatformCapabilities.current.isDesktop
              ? (details) => showAutomationSheet(details.globalPosition)
              : null,
          onLongPressStart: PlatformCapabilities.current.isDesktop
              ? null
              : (details) {
                  final box = gestureContext.findRenderObject() as RenderBox?;
                  if (box != null &&
                      _isLikelyNumericSliderPress(
                        param: param,
                        localPosition:
                            box.globalToLocal(details.globalPosition),
                        size: box.size,
                      )) {
                    return;
                  }
                  showAutomationSheet(details.globalPosition);
                },
          child: _wrapWithHalos(
            haloKeys: haloKeys,
            borderRadius: borderRadius,
            child: child,
          ),
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
    void commitImmediate(double nextValue) {
      final target = nextValue.clamp(minV, maxV).toDouble();
      final oldValue = ((param['value'] as num?)?.toDouble() ?? rawV)
          .clamp(minV, maxV)
          .toDouble();
      if ((oldValue - target).abs() < 1.0e-6) return;
      setState(() => param['value'] = target);
      widget.setMasterEffectParam(effectIndex, paramName, target);
      widget.onMasterPluginParamCommit?.call(
        effectIndex,
        paramName,
        oldValue,
        target,
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
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () {
                    final target =
                        (defaultValue ?? unity).clamp(minV, maxV).toDouble();
                    commitImmediate(target);
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
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (!mounted) return;
                      final next = await _showGainPercentDialog(
                        context: context,
                        value: rawV,
                        minValue: minV,
                        maxValue: maxV,
                      );
                      if (next == null || !mounted) return;
                      commitImmediate(next);
                    });
                  },
                  child: Center(
                    child: Text(
                      _formatGainDb(rawV, uiMax: maxV),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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
    _returnHighlightTimer?.cancel();
    _stopCompressorMetering();
    _stopEqWaveformPolling();
    _stopStereoScopePolling();
    _stopShaperPreviewPolling();
    _stopTransientShaperVisualPolling();
    _stopDynamicSoftenerPolling();
    super.dispose();
  }

  Future<void> _loadEffects() async {
    _stopEqWaveformPolling();
    _stopStereoScopePolling();
    _stopShaperPreviewPolling();
    _stopTransientShaperVisualPolling();
    _stopDynamicSoftenerPolling();
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

  String _rawEffectIdAt(int idx) {
    if (idx < 0 || idx >= _effectKeys.length) return '';
    final stableKey = _effectKeys[idx];
    final hashIndex = stableKey.lastIndexOf('#');
    if (hashIndex <= 0) return stableKey;
    return stableKey.substring(0, hashIndex);
  }

  bool _isLikelyExternalEffectSlot(int idx) {
    final rawId = _rawEffectIdAt(idx).trim();
    if (rawId.isEmpty) return false;
    final effectName =
        (idx >= 0 && idx < _effects.length) ? _effects[idx].trim() : '';
    return rawId != effectName;
  }

  Future<void> _tryOpenMasterPluginEditor(int idx) async {
    final opener = widget.openMasterPluginEditor;
    if (opener == null || !_isLikelyExternalEffectSlot(idx)) return;
    await opener(idx);
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
    final customLabel = L10n.translate(context, 'Custom');
    final presetLabel =
        detectedIdx == null ? customLabel : kDelayDivisions[detectedIdx].label;

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
              SizedBox(
                width: 136,
                child: _buildMixroomChoiceField(
                  context: context,
                  value: presetLabel,
                  compact: true,
                  onTap: () async {
                    final labels = <String>[
                      customLabel,
                      ...kDelayDivisions.map((d) => d.label),
                    ];
                    final picked = await _showMixroomChoiceDialog(
                      context: context,
                      title:
                          '${L10n.translate(context, 'Select ')}${param['name']}',
                      choices: labels,
                      currentChoice: presetLabel,
                    );
                    if (picked == null || picked == customLabel) return;

                    final division =
                        kDelayDivisions.firstWhere((d) => d.label == picked);
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
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
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
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
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

  void _startStereoScopePolling({required int effectIndex}) {
    _stopStereoScopePolling();
    _stereoScopeRunning = true;

    _stereoScopeTimer =
        Timer.periodic(const Duration(milliseconds: 40), (_) async {
      if (!mounted || !_stereoScopeRunning) return;

      try {
        final arr = await widget.getMasterStereoScope(effectIndex, 256);
        if (!mounted || !_stereoScopeRunning) return;
        setState(() {
          _stereoScope = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      }
    });
  }

  void _stopStereoScopePolling() {
    _stereoScopeRunning = false;
    _stereoScopeTimer?.cancel();
    _stereoScopeTimer = null;
    _stereoScope = const <double>[];
  }

  void _startShaperPreviewPolling({required int effectIndex}) {
    _stopShaperPreviewPolling();
    _shaperPreviewRunning = true;
    _shaperPreviewRequestInFlight = false;

    _shaperPreviewTimer =
        Timer.periodic(_kShaperPreviewPollInterval, (_) async {
      if (!mounted || !_shaperPreviewRunning || _shaperPreviewRequestInFlight) {
        return;
      }
      _shaperPreviewRequestInFlight = true;

      try {
        final arr = await JuceAudioEngine.getMasterShaperPreview(
          effectIndex,
          pointCount: 192,
        );
        if (!mounted || !_shaperPreviewRunning) return;
        if (!_previewFramesChanged(_shaperPreview, arr)) return;
        setState(() {
          _shaperPreview = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _shaperPreviewRequestInFlight = false;
      }
    });
  }

  void _stopShaperPreviewPolling() {
    _shaperPreviewRunning = false;
    _shaperPreviewRequestInFlight = false;
    _shaperPreviewTimer?.cancel();
    _shaperPreviewTimer = null;
    _shaperPreview = const <double>[];
  }

  void _startDynamicSoftenerPolling({required int effectIndex}) {
    _stopDynamicSoftenerPolling();
    _softenerPreviewRunning = true;
    _softenerPreviewRequestInFlight = false;

    Future<void> fetchFrame() async {
      if (!mounted ||
          !_softenerPreviewRunning ||
          _softenerPreviewRequestInFlight) {
        return;
      }
      _softenerPreviewRequestInFlight = true;

      try {
        final arr =
            await JuceAudioEngine.getMasterDynamicSoftenerFrame(effectIndex);
        if (!mounted || !_softenerPreviewRunning) return;
        if (!_previewFramesChanged(_softenerFrame, arr, tolerance: 0.0005)) {
          return;
        }
        setState(() {
          _softenerFrame = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _softenerPreviewRequestInFlight = false;
      }
    }

    unawaited(fetchFrame());
    _softenerPreviewTimer =
        Timer.periodic(_kDynamicSoftenerPollInterval, (_) => fetchFrame());
  }

  void _stopDynamicSoftenerPolling() {
    _softenerPreviewRunning = false;
    _softenerPreviewRequestInFlight = false;
    _softenerPreviewTimer?.cancel();
    _softenerPreviewTimer = null;
    _softenerFrame = const <double>[];
  }

  void _startTransientShaperVisualPolling({required int effectIndex}) {
    _stopTransientShaperVisualPolling();
    _transientShaperVisualRunning = true;
    _transientShaperVisualRequestInFlight = false;

    _transientShaperVisualTimer =
        Timer.periodic(_kShaperPreviewPollInterval, (_) async {
      if (!mounted ||
          !_transientShaperVisualRunning ||
          _transientShaperVisualRequestInFlight) {
        return;
      }
      _transientShaperVisualRequestInFlight = true;

      try {
        final arr = await JuceAudioEngine.getMasterTransientShaperVisual(
          effectIndex,
          pointCount: 192,
        );
        if (!mounted || !_transientShaperVisualRunning) return;
        if (!_previewFramesChanged(_transientShaperVisual, arr)) return;
        setState(() {
          _transientShaperVisual = arr;
        });
      } catch (_) {
        // ignore transient bridge errors while polling
      } finally {
        _transientShaperVisualRequestInFlight = false;
      }
    });
  }

  void _stopTransientShaperVisualPolling() {
    _transientShaperVisualRunning = false;
    _transientShaperVisualRequestInFlight = false;
    _transientShaperVisualTimer?.cancel();
    _transientShaperVisualTimer = null;
    _transientShaperVisual = const <double>[];
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

  Future<void> _handleMasterEffectsMenuAction(
      _MasterEffectsMenuAction action) async {
    if (mounted) {
      setState(() {
        _masterEffectsMenuOpen = false;
      });
    }
    switch (action) {
      case _MasterEffectsMenuAction.copy:
        widget.onCopyMasterEffects?.call();
        break;
      case _MasterEffectsMenuAction.paste:
        await widget.onPasteMasterEffects?.call();
        break;
      case _MasterEffectsMenuAction.clear:
        await widget.onClearMasterEffects?.call();
        break;
    }
    if (!mounted) return;
    if (action != _MasterEffectsMenuAction.copy) {
      await _loadEffects();
    } else {
      setState(() {});
    }
  }

  Widget _buildMasterEffectsMenuButton(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('master_effects_menu'),
          onTap: () {
            setState(() {
              _masterEffectsMenuOpen = !_masterEffectsMenuOpen;
            });
          },
          borderRadius: BorderRadius.circular(999),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: 0.06);
              }
              return null;
            },
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            width: _kRowEffectsMenuButtonWidth,
            height: 34,
            decoration: _mixroomFxInsetDecoration(
              radius: 999,
              selected: _masterEffectsMenuOpen,
            ),
            child: const Row(
              children: [
                Spacer(),
                Icon(Icons.more_horiz, size: 18, color: _kFxPanelText),
                Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterEffectsMenuPanel(BuildContext context) {
    Widget actionTile({
      required String title,
      required _MasterEffectsMenuAction action,
      required bool enabled,
    }) {
      final actionSlug = switch (action) {
        _MasterEffectsMenuAction.copy => 'copy',
        _MasterEffectsMenuAction.paste => 'paste',
        _MasterEffectsMenuAction.clear => 'clear',
      };
      return Opacity(
        opacity: enabled ? 1.0 : 0.46,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('master_effects_menu_action_$actionSlug'),
            onTap: enabled
                ? () => unawaited(_handleMasterEffectsMenuAction(action))
                : null,
            borderRadius: BorderRadius.circular(14),
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.05);
                }
                return null;
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: _mixroomFxInsetDecoration(radius: 14),
              child: Text(
                L10n.translate(context, title),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kFxPanelText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('master_effects_menu_panel'),
      padding: const EdgeInsets.all(10),
      decoration: _mixroomFxSurfaceDecoration(radius: 18, active: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                L10n.translate(context, 'Master effects'),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: _kFxPanelText,
                  fontSize: 13.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('master_effects_menu_close'),
                  onTap: () {
                    setState(() {
                      _masterEffectsMenuOpen = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(WidgetState.pressed)) {
                        return Colors.white.withValues(alpha: 0.12);
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return Colors.white.withValues(alpha: 0.05);
                      }
                      return null;
                    },
                  ),
                  child: Container(
                    width: _kRowEffectsMenuCloseButtonSize,
                    height: _kRowEffectsMenuCloseButtonSize,
                    decoration: _mixroomFxInsetDecoration(radius: 999),
                    child:
                        const Icon(Icons.close, size: 16, color: _kFxPanelText),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          actionTile(
            title: 'Copy effects',
            action: _MasterEffectsMenuAction.copy,
            enabled: widget.onCopyMasterEffects != null,
          ),
          const SizedBox(height: 8),
          actionTile(
            title: 'Paste effects',
            action: _MasterEffectsMenuAction.paste,
            enabled: widget.hasCopiedMasterEffects &&
                widget.onPasteMasterEffects != null,
          ),
          const SizedBox(height: 8),
          actionTile(
            title: 'Clear effects',
            action: _MasterEffectsMenuAction.clear,
            enabled: widget.onClearMasterEffects != null,
          ),
        ],
      ),
    );
  }

  Widget _buildMasterPresetStrip(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 34,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Colors.white,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: <double>[0.0, 0.82, 0.93, 1.0],
                ).createShader(bounds);
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                  right: _kRowEffectsPresetFadeWidth + 6,
                ),
                child: Row(
                  children: [
                    _buildPresetChip("Concert Hall"),
                    const SizedBox(width: 6),
                    _buildPresetChip("Echoes"),
                    const SizedBox(width: 6),
                    _buildPresetChip("LoFi Effect"),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildMasterEffectsMenuButton(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // If an effect is selected → show parameter page (no inner scroll)
    if (_selectedEffectIndex != null) {
      return _buildEffectParamsPage(context, _selectedEffectIndex!);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: _buildMasterPresetStrip(context),
              ),
              const SizedBox(height: 2),
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: ReorderableListView(
                  buildDefaultDragHandles:
                      _shouldShowDefaultReorderHandles(context),
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
          Positioned(
            top: _kMasterEffectsMenuTopOffset,
            right: _kMasterEffectsMenuRightOffset,
            child: IgnorePointer(
              ignoring: !_masterEffectsMenuOpen,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: _masterEffectsMenuOpen ? 1.0 : 0.0,
                ),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  if (t <= 0.001) return const SizedBox.shrink();
                  final widthFactor = _kRowEffectsMenuClosedWidthFactor +
                      ((1.0 - _kRowEffectsMenuClosedWidthFactor) * t);
                  final heightFactor = _kRowEffectsMenuClosedHeightFactor +
                      ((1.0 - _kRowEffectsMenuClosedHeightFactor) * t);
                  return Opacity(
                    opacity: t,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Align(
                        alignment: Alignment.topRight,
                        widthFactor: widthFactor,
                        heightFactor: heightFactor,
                        child: Transform.translate(
                          offset: Offset((1.0 - t) * 8, (1.0 - t) * -4),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kRowEffectsMenuPanelWidth +
                        _kMasterEffectsMenuInnerRightInset,
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _buildMasterEffectsMenuPanel(context),
                  ),
                ),
              ),
            ),
          ),
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
          : const Color.fromRGBO(244, 244, 244, 0.16),
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
                  : _kFxPanelText,
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
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
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
          exposedEffectParameterValues(_effects[i], params)));
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
        await widget.insertMasterEffect('EQ 3-Band');
        await widget.setMasterEffectParam(1, 'Low Gain', -1.0);
        await widget.setMasterEffectParam(1, 'Mid Gain', 0.6);
        await widget.setMasterEffectParam(1, 'High Gain', 1.2);
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
          exposedEffectParameterValues(_effects[i], params)));
    }
    final after = MasterEffectsSnapshot(afterSnapshots);
    widget.onMasterPresetCommit?.call(before, after);
    Navigator.of(context).pop(); // dismiss loading
  }

  // =========================
  // FX LIST
  // =========================

  Widget _buildMasterEffectTile(int idx) {
    final showReturnHighlight = _returnHighlightedEffectIndex == idx;
    final tile = AnimatedContainer(
      key: ValueKey("master_effect_${_effectKeys[idx]}"),
      duration: const Duration(milliseconds: 170),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: showReturnHighlight
          ? _mixroomFxReturnHighlightDecoration(radius: 14)
          : const BoxDecoration(color: Colors.transparent),
      child: ListTile(
        dense: true,
        minLeadingWidth: 22,
        horizontalTitleGap: 4,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),

        // only this handle starts reorder drag
        leading: ReorderableDragStartListener(
          index: idx,
          child: const Padding(
            padding: EdgeInsets.only(left: 2.0, right: 2.0),
            child: Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: Color(0xCCF4F4F4),
            ),
          ),
        ),

        title: Text(
          L10n.translate(context, _effects[idx]),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _kFxPanelText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 42,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Switch(
                  value: !_bypassed[idx],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  activeColor: const Color(0xFFF4F4F4),
                  inactiveThumbColor: const Color(0xFFB8BDC3),
                  inactiveTrackColor: const Color(0xFFDFE2E5),
                  activeTrackColor: const Color(0xFF545A60),
                ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Color.fromARGB(255, 255, 164, 164),
              ),
              onPressed: () => _confirmRemove(idx),
            ),
          ],
        ),

        onTap: () => _openPluginParams(idx),
      ),
    );
    return _wrapWithHalos(
      key: ValueKey("master_effect_${_effectKeys[idx]}"),
      child: tile,
      haloKeys: <String>[
        ..._effectHaloKeys(effectIndex: idx, effectName: _effects[idx]),
      ],
      borderRadius: BorderRadius.circular(10),
    );
  }

  Widget _buildAddTile() {
    return Container(
      key: const ValueKey("add_effect"),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: ListTile(
        dense: true,
        minLeadingWidth: 26,
        horizontalTitleGap: 6,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),
        leading: const Icon(
          Icons.add_circle_outline,
          color: _kFxPanelText,
          size: 19,
        ),
        title: Text(
          L10n.translate(context, 'Add Effect'),
          style: const TextStyle(
            color: _kFxPanelText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        onTap: _showAddEffectModal,
      ),
    );
  }

  Future<void> _confirmRemove(int idx) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
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
    List<Map<String, dynamic>> plugins;
    try {
      plugins = await widget.scanPlugins();
    } catch (_) {
      plugins = const <Map<String, dynamic>>[];
    }
    final externalEffects = plugins.where((plugin) {
      final category =
          (plugin['category'] ?? '').toString().trim().toLowerCase();
      final isInstrument = plugin['isInstrument'] == true;
      return !isInstrument && category != 'instrument';
    }).toList(growable: false);
    const allFxChoices = [
      "Gain",
      "Reverb",
      "EQ 3-Band",
      "EQ Parametric",
      "Delay",
      "Compressor",
      "Dynamic Softener",
      "Transient Shaper",
      "Clipper",
      "Limiter",
      "Distortion",
      "Degrade",
      "Pitch Shift",
      "Pitch Corrector",
      "De-Esser",
      "Stereo",
      "Stereo Pro",
      "Volume Shaper",
      "Time Shaper",
      "Chorus",
      "Vibrato",
    ];
    const fxChoices = allFxChoices;

    // Dialog can use scrolling; this is outside the row panel layout.
    showDialog(
      context: context,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            backgroundColor: const Color(0xFF5F666D),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            title: Container(
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: _mixroomFxInsetDecoration(radius: 18),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: EdgeInsets.zero,
                indicator: BoxDecoration(
                  color: _kFxPanelFillStrong,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
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
                      final isAllowed = !_isBasicTier ||
                          SubscriptionLimits.freeBuiltInEffects.contains(name);
                      return GestureDetector(
                        onTap: isAllowed
                            ? () async {
                                Navigator.pop(context);
                                await widget.insertMasterEffect(name);
                                await _loadEffects();
                              }
                            : () => _showPluginUpgradeDialog(
                                  context,
                                  onUpgradeRequested: widget.onUpgradeRequested,
                                ),
                        child: Opacity(
                          opacity: isAllowed ? 1.0 : 0.4,
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            title: Text(
                              L10n.translate(context, name),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.2),
                            ),
                            trailing: isAllowed
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        L10n.translate(context, 'Starter'),
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.72),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                  ListView.separated(
                    itemCount:
                        externalEffects.isEmpty ? 1 : externalEffects.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                    itemBuilder: (context, i) {
                      if (externalEffects.isEmpty) {
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          title: Text(
                            L10n.translate(
                              context,
                              'No external plugins found',
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13.0,
                            ),
                          ),
                        );
                      }
                      final meta = externalEffects[i];
                      final path = (meta['id'] ?? '').toString();
                      if (path.isEmpty) return const SizedBox.shrink();
                      final name = (meta['name'] ?? path).toString();
                      final format = (meta['format'] ?? '').toString();
                      final manufacturer =
                          (meta['manufacturer'] ?? '').toString();
                      final isAllowed = !_isBasicTier;
                      final details = <String>[
                        if (format.isNotEmpty) format,
                        if (manufacturer.isNotEmpty) manufacturer,
                      ];
                      return Opacity(
                        opacity: isAllowed ? 1.0 : 0.45,
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
                          trailing: isAllowed
                              ? null
                              : const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: Colors.white70,
                                ),
                          onTap: isAllowed
                              ? () async {
                                  Navigator.pop(context);
                                  await widget.insertMasterEffect(path);
                                  await _loadEffects();
                                  final addedIndex = _effects.length - 1;
                                  if (addedIndex >= 0 &&
                                      addedIndex < _effects.length) {
                                    await _tryOpenMasterPluginEditor(
                                        addedIndex);
                                  }
                                }
                              : () => _showPluginUpgradeDialog(
                                    context,
                                    onUpgradeRequested:
                                        widget.onUpgradeRequested,
                                  ),
                        ),
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

    if (_isLikelyExternalEffectSlot(idx)) {
      setState(() {
        _masterEffectsMenuOpen = false;
        _selectedEffectIndex = null;
        _paramsLoading = false;
        _currentParams = [];
        _returnHighlightedEffectIndex = null;
      });
      await _tryOpenMasterPluginEditor(idx);
      return;
    }

    setState(() {
      _masterEffectsMenuOpen = false;
      _selectedEffectIndex = idx;
      _paramsLoading = true;
      _currentParams = [];
      _returnHighlightedEffectIndex = null;
    });
    unawaited(_tryOpenMasterPluginEditor(idx));

    if (_showsDynamicsReductionMeter(_effects[idx])) {
      _startCompressorMetering(effectIndex: idx);
    } else {
      _stopCompressorMetering();
    }
    if (_showsSpectrumPreview(_effects[idx])) {
      _startEqWaveformPolling(effectIndex: idx);
    } else {
      _stopEqWaveformPolling();
    }
    if (_showsStereoScope(_effects[idx])) {
      _startStereoScopePolling(effectIndex: idx);
    } else {
      _stopStereoScopePolling();
    }
    if (_showsShaperPreview(_effects[idx])) {
      _startShaperPreviewPolling(effectIndex: idx);
    } else {
      _stopShaperPreviewPolling();
    }
    if (_showsTransientShaperVisualizer(_effects[idx])) {
      _startTransientShaperVisualPolling(effectIndex: idx);
    } else {
      _stopTransientShaperVisualPolling();
    }
    if (_showsDynamicSoftenerPreview(_effects[idx])) {
      _startDynamicSoftenerPolling(effectIndex: idx);
    } else {
      _stopDynamicSoftenerPolling();
    }

    var params = await widget.getMasterPluginParameters(idx);
    if (params.isEmpty) {
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        params = await widget.getMasterPluginParameters(idx);
        if (params.isNotEmpty) break;
      }
    }

    params = exposedEffectParameters(_effects[idx], params);

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

      _EqFaderSpec buildEqFader(
        Map<String, dynamic> param, {
        required String label,
        required String unit,
        bool logarithmic = false,
      }) {
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
            final startValue =
                _EQParamStartValue ?? (param['value'] as num).toDouble();
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
          onValueTap: () async {
            final oldValue = (param['value'] as num).toDouble();
            final picked = await _showNumericParamEntryDialog(
              context: context,
              param: param,
              currentValue: oldValue,
            );
            if (!mounted || picked == null) return;
            final nextValue = picked
                .clamp(
                  (param['min'] as num).toDouble(),
                  (param['max'] as num).toDouble(),
                )
                .toDouble();
            if ((oldValue - nextValue).abs() < 1.0e-6) return;
            setState(() => param['value'] = nextValue);
            widget.setMasterEffectParam(idx, name, nextValue);
            widget.onMasterPluginParamCommit?.call(
              idx,
              name,
              oldValue,
              nextValue,
            );
          },
        );
      }

      final gainFaders = <_EqFaderSpec>[
        if (pB1 != null) buildEqFader(pB1, label: 'Band 1', unit: 'dB'),
        if (pB2 != null) buildEqFader(pB2, label: 'Band 2', unit: 'dB'),
        if (pB3 != null) buildEqFader(pB3, label: 'Band 3', unit: 'dB'),
        if (pB4 != null) buildEqFader(pB4, label: 'Band 4', unit: 'dB'),
      ];
      final frequencyFaders = <_EqFaderSpec>[
        if (pB1Freq != null)
          buildEqFader(
            pB1Freq,
            label: 'Band 1',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB2Freq != null)
          buildEqFader(
            pB2Freq,
            label: 'Band 2',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB3Freq != null)
          buildEqFader(
            pB3Freq,
            label: 'Band 3',
            unit: 'Hz',
            logarithmic: true,
          ),
        if (pB4Freq != null)
          buildEqFader(
            pB4Freq,
            label: 'Band 4',
            unit: 'Hz',
            logarithmic: true,
          ),
      ];
      final qFaders = <_EqFaderSpec>[
        if (pB1Q != null) buildEqFader(pB1Q, label: 'Band 1', unit: 'Q'),
        if (pB2Q != null) buildEqFader(pB2Q, label: 'Band 2', unit: 'Q'),
        if (pB3Q != null) buildEqFader(pB3Q, label: 'Band 3', unit: 'Q'),
        if (pB4Q != null) buildEqFader(pB4Q, label: 'Band 4', unit: 'Q'),
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
              final startValue =
                  _EQParamStartValue ?? (pHPF['value'] as num).toDouble();
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
              final startValue =
                  _EQParamStartValue ?? (pLPF['value'] as num).toDouble();
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
            _buildFxParamsHeader(
              context: context,
              title: effectName,
              onBack: () => _returnToEffectsList(effectIndex: idx),
              onReset: () async {
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
                    (c['param'] as Map<String, dynamic>)['value'] = c['next'];
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
            ),
            const SizedBox(height: 10),
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

      Future<void> typeEq3BandValue(Map<String, dynamic> param) async {
        final name = param['name'] as String;
        final oldValue = (param['value'] as num).toDouble();
        final picked = await _showNumericParamEntryDialog(
          context: context,
          param: param,
          currentValue: oldValue,
        );
        if (!mounted || picked == null) return;
        final nextValue = picked
            .clamp(
              (param['min'] as num).toDouble(),
              (param['max'] as num).toDouble(),
            )
            .toDouble();
        if ((oldValue - nextValue).abs() < 1.0e-6) return;
        setState(() => param['value'] = nextValue);
        widget.setMasterEffectParam(idx, name, nextValue);
        widget.onMasterPluginParamCommit?.call(
          idx,
          name,
          oldValue,
          nextValue,
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFxParamsHeader(
              context: context,
              title: effectName,
              onBack: () => _returnToEffectsList(effectIndex: idx),
              trailing: _buildEffectInfoButton(
                context: context,
                effectName: effectName,
                params: _currentParams,
              ),
            ),
            const SizedBox(height: 10),
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
                                  onValueTap: () =>
                                      unawaited(typeEq3BandValue(pLow)),
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
                                    final startValue = _EQParamStartValue ??
                                        (pLow['value'] as num).toDouble();
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pLow['name'] as String,
                                      startValue,
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
                                  onValueTap: () =>
                                      unawaited(typeEq3BandValue(pMid)),
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
                                    final startValue = _EQParamStartValue ??
                                        (pMid['value'] as num).toDouble();
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pMid['name'] as String,
                                      startValue,
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
                                  onValueTap: () =>
                                      unawaited(typeEq3BandValue(pHigh)),
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
                                    final startValue = _EQParamStartValue ??
                                        (pHigh['value'] as num).toDouble();
                                    widget.onMasterPluginParamCommit?.call(
                                      idx,
                                      pHigh['name'] as String,
                                      startValue,
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
          _buildFxParamsHeader(
            context: context,
            title: effectName,
            onBack: () => _returnToEffectsList(effectIndex: idx),
            trailing: _buildEffectInfoButton(
              context: context,
              effectName: effectName,
              params: _currentParams,
            ),
          ),
          const SizedBox(height: 10),

          if (effectName == 'Stereo Pro' && _currentParams.isNotEmpty) ...[
            _StereoProPreview(
              scopeFrames: _stereoScope,
              gainDb: (_paramByName(_currentParams, 'Gain')?['value'] as num?)
                      ?.toDouble() ??
                  0.0,
              widthPercent:
                  (_paramByName(_currentParams, 'Width')?['value'] as num?)
                          ?.toDouble() ??
                      100.0,
              asymmetryPercent:
                  (_paramByName(_currentParams, 'Asymmetry')?['value'] as num?)
                          ?.toDouble() ??
                      0.0,
              rotationDegrees:
                  (_paramByName(_currentParams, 'Rotation')?['value'] as num?)
                          ?.toDouble() ??
                      0.0,
            ),
            const SizedBox(height: 12),
          ],

          if (effectName == 'Degrade' && _currentParams.isNotEmpty) ...[
            _DegradePreview(
              spectrumDb: _eqSpectrumDb,
              analyzerSampleRate: _eqAnalyzerSampleRate,
              mode:
                  (_paramByName(_currentParams, 'Mode')?['value']?.toString() ??
                          'Noise')
                      .trim(),
              toneHz: (_paramByName(_currentParams, 'Tone')?['value'] as num?)
                      ?.toDouble() ??
                  6000.0,
              depthPercent:
                  (_paramByName(_currentParams, 'Depth')?['value'] as num?)
                          ?.toDouble() ??
                      35.0,
              spreadPercent:
                  (_paramByName(_currentParams, 'Spread')?['value'] as num?)
                          ?.toDouble() ??
                      40.0,
            ),
            const SizedBox(height: 12),
          ],

          if (_showsDynamicSoftenerPreview(effectName)) ...[
            _DynamicSoftenerPreview(
              frame: _softenerFrame,
              mode: (_paramByName(_currentParams, 'Mode')?['value'] ?? 'Gentle')
                  .toString(),
              depthPercent:
                  (_paramByName(_currentParams, 'Depth')?['value'] as num?)
                          ?.toDouble() ??
                      55.0,
              detailPercent:
                  (_paramByName(_currentParams, 'Focus')?['value'] as num?)
                          ?.toDouble() ??
                      55.0,
              maxCutDb:
                  (_paramByName(_currentParams, 'Cut Limit')?['value'] as num?)
                          ?.toDouble() ??
                      18.0,
              lowRangeHz:
                  (_paramByName(_currentParams, 'Low Range')?['value'] as num?)
                          ?.toDouble() ??
                      20.0,
              highRangeHz:
                  (_paramByName(_currentParams, 'High Range')?['value'] as num?)
                          ?.toDouble() ??
                      20000.0,
            ),
            const SizedBox(height: 12),
          ],

          if (_showsTransientShaperVisualizer(effectName) &&
              _currentParams.isNotEmpty) ...[
            _TransientShaperVisualizerCard(
              frames: _transientShaperVisual,
              attackPercent:
                  (_paramByName(_currentParams, 'Attack')?['value'] as num?)
                          ?.toDouble() ??
                      0.0,
              pumpPercent:
                  (_paramByName(_currentParams, 'Pump')?['value'] as num?)
                          ?.toDouble() ??
                      0.0,
              sustainPercent:
                  (_paramByName(_currentParams, 'Sustain')?['value'] as num?)
                          ?.toDouble() ??
                      0.0,
              speedPercent:
                  (_paramByName(_currentParams, 'Speed')?['value'] as num?)
                          ?.toDouble() ??
                      65.0,
              clip: (_paramByName(_currentParams, 'Clip')?['value'] as bool?) ??
                  false,
            ),
            const SizedBox(height: 12),
          ],

          if (_showsShaperPreview(effectName) && _currentParams.isNotEmpty) ...[
            _ShaperPreviewCard(
              kind: effectName == 'Time Shaper'
                  ? _ShaperPreviewKind.time
                  : _ShaperPreviewKind.volume,
              previewFrames: _shaperPreview,
              title: ((_paramByName(
                        _currentParams,
                        effectName == 'Time Shaper' ? 'Pattern' : 'Shape',
                      )?['value']) ??
                      (effectName == 'Time Shaper' ? 'Pattern' : 'Shape'))
                  .toString(),
              detail:
                  ((_paramByName(_currentParams, 'Rate')?['value']) ?? 'Rate')
                      .toString(),
            ),
            const SizedBox(height: 12),
          ],

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
                child: _buildGenericFloatParamEditor(
                  context: context,
                  effectName: _effects[idx],
                  param: param,
                  setLocalValue: (value) =>
                      setState(() => param['value'] = value),
                  setRemoteValue: (value) => widget.setMasterEffectParam(
                    idx,
                    param['name'] as String,
                    value,
                  ),
                  commitValue: (oldValue, newValue) =>
                      widget.onMasterPluginParamCommit?.call(
                    idx,
                    param['name'] as String,
                    oldValue,
                    newValue,
                  ),
                  setDragStartValue: (value) => _paramDragStartValue = value,
                  getDragStartValue: () => _paramDragStartValue,
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
                    child: (effectName == 'Degrade' ||
                                effectName == 'Dynamic Softener') &&
                            param['name'] == 'Mode'
                        ? _buildDegradeModeSelectorTile(
                            context: context,
                            label: param['name'] as String,
                            value: current,
                            choices: choices,
                            oneRow: effectName == 'Dynamic Softener',
                            onSelected: (picked) {
                              if (picked == current) return;
                              final oldVal = param['value'];
                              setState(() => param['value'] = picked);
                              widget.setMasterEffectParam(
                                  idx, param['name'] as String, picked);
                              widget.onMasterPluginParamCommit?.call(
                                  idx, param['name'] as String, oldVal, picked);
                            },
                          )
                        : _buildMixroomChoiceSettingTile(
                            context: context,
                            label: param['name'] as String,
                            value: current,
                            onTap: () async {
                              final picked = await _showMixroomChoiceDialog(
                                context: context,
                                title:
                                    '${L10n.translate(context, 'Select ')}${param['name']}',
                                choices: choices,
                                currentChoice: current,
                              );
                              if (picked != null) {
                                final oldVal = param['value'];
                                setState(() => param['value'] = picked);
                                widget.setMasterEffectParam(
                                    idx, param['name'] as String, picked);
                                widget.onMasterPluginParamCommit?.call(idx,
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
const double _eqParametricFaderSlotWidth = 72;

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
  final VoidCallback? onValueTap;

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
    required this.onValueTap,
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
              onValueTap: f.onValueTap,
              width: _eqParametricFaderSlotWidth,
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
          child: _buildMixroomChoiceField(
            context: context,
            value: currentChoice,
            compact: true,
            onTap: () async {
              final picked = await _showMixroomChoiceDialog(
                context: context,
                title: '${L10n.translate(context, 'Select ')}$label',
                choices: choices,
                currentChoice: currentChoice,
              );
              if (picked != null) onChanged(picked);
            },
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
            child: _buildMixroomChoiceField(
              context: context,
              value: selectedSlope,
              compact: true,
              onTap: () async {
                final picked = await _showMixroomChoiceDialog(
                  context: context,
                  title: '${L10n.translate(context, 'Select ')}$label Slope',
                  choices: slopeChoices,
                  currentChoice: selectedSlope,
                );
                if (picked != null) onSlopeChanged(picked);
              },
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

bool _isLikelyNumericSliderPress({
  required Map<String, dynamic> param,
  required Offset localPosition,
  required Size size,
}) {
  final type = (param['type']?.toString() ?? '').toLowerCase();
  final hasNumericRange =
      param['min'] is num && param['max'] is num && param['value'] is num;
  if (!hasNumericRange &&
      type != 'float' &&
      type != 'double' &&
      type != 'int') {
    return false;
  }
  if (size.height <= 0 || size.width <= 0) return false;

  // Numeric parameter cards put the readable label/value area above the slider.
  // Long-pressing that header still opens automation; long-pressing the lower
  // slider/knob area is treated as a value edit gesture and does nothing here.
  final sliderZoneTop = math.min(42.0, size.height * 0.45);
  return localPosition.dy >= sliderZoneTop;
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
  "Degrade": {
    "Tone": 0.25,
  },
  "Delay": {
    "HPF Frequency": 0.35,
  },
  "Stereo": {
    "Low Bypass": 0.35,
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

String _normalizeParamUnit(dynamic rawUnit) {
  final unit = (rawUnit?.toString() ?? '').trim();
  if (unit.isEmpty) return '';
  if (unit == 'deg') return '°';
  return unit;
}

String _formatParamValueForDisplay(Map<String, dynamic> param, double value) {
  final unit = _normalizeParamUnit(param['unit']);
  if (unit == 'Hz') return '${_fmtHz(value)} Hz';
  if (unit == 'dB') return '${value.toStringAsFixed(1)} dB';
  if (unit == '%') return '${value.toStringAsFixed(0)}%';
  if (unit == '°') return '${value.toStringAsFixed(0)}°';
  if (unit == 'ms') return '${value.toStringAsFixed(1)} ms';
  if (unit.isNotEmpty) return '${value.toStringAsFixed(2)} $unit';
  return value.toStringAsFixed(2);
}

class _StereoStageMarker {
  final String label;
  final double xNorm;
  final double yNorm;
  final double emphasis;
  final Color color;

  const _StereoStageMarker({
    required this.label,
    required this.xNorm,
    required this.yNorm,
    required this.emphasis,
    required this.color,
  });
}

const double _kStereoProPreviewCeiling = 1.25;

double _tanhApprox(double x) {
  final ex = math.exp(x);
  final inv = math.exp(-x);
  return (ex - inv) / (ex + inv);
}

double _softLimitStereoProPreviewSample(double sample) {
  if (!sample.isFinite) return 0.0;
  return _kStereoProPreviewCeiling *
      _tanhApprox(sample / _kStereoProPreviewCeiling);
}

(double, double) _transformStereoProPreviewFrame({
  required double gainDb,
  required double widthPercent,
  required double asymmetryPercent,
  required double rotationDegrees,
  required double inputL,
  required double inputR,
}) {
  final gain = math.pow(10.0, gainDb / 20.0).toDouble();
  final width = (widthPercent / 100.0).clamp(0.0, 3.0);
  final asymmetry = (asymmetryPercent / 100.0).clamp(-0.95, 0.95);
  final rotation = (rotationDegrees / 90.0).clamp(-1.0, 1.0);
  final angle = (rotation + 1.0) * math.pi * 0.25;
  final midGainL = math.sqrt(2.0) * math.cos(angle);
  final midGainR = math.sqrt(2.0) * math.sin(angle);
  final sideGainL = width * (1.0 + asymmetry);
  final sideGainR = width * (1.0 - asymmetry);
  final matrixPeak = math.max(
    1.0,
    math.max(
        midGainL.abs() + sideGainL.abs(), midGainR.abs() + sideGainR.abs()),
  );
  final matrixNormalise = 1.0 / matrixPeak;

  final mid = 0.5 * (inputL + inputR);
  final side = 0.5 * (inputL - inputR);
  final outL = _softLimitStereoProPreviewSample(
    gain * (((mid * midGainL) + (side * sideGainL)) * matrixNormalise),
  );
  final outR = _softLimitStereoProPreviewSample(
    gain * (((mid * midGainR) - (side * sideGainR)) * matrixNormalise),
  );
  return (outL, outR);
}

List<_StereoStageMarker> _buildStereoProStageMarkers({
  required double gainDb,
  required double widthPercent,
  required double asymmetryPercent,
  required double rotationDegrees,
}) {
  _StereoStageMarker marker(
    String label,
    Color color,
    double inputL,
    double inputR,
  ) {
    final (outL, outR) = _transformStereoProPreviewFrame(
      gainDb: gainDb,
      widthPercent: widthPercent,
      asymmetryPercent: asymmetryPercent,
      rotationDegrees: rotationDegrees,
      inputL: inputL,
      inputR: inputR,
    );
    final xNorm =
        ((((outR - outL) * 0.5) / _kStereoProPreviewCeiling).clamp(-1.0, 1.0))
            .toDouble();
    final yNorm =
        ((((outL + outR) * 0.5) / _kStereoProPreviewCeiling).clamp(-1.0, 1.0))
            .toDouble();
    final emphasis =
        (math.max(outL.abs(), outR.abs()) / _kStereoProPreviewCeiling)
            .clamp(0.35, 1.0);
    return _StereoStageMarker(
      label: label,
      xNorm: xNorm,
      yNorm: yNorm,
      emphasis: emphasis,
      color: color,
    );
  }

  return <_StereoStageMarker>[
    marker('L', const Color(0xFF78BFFF), 1.0, 0.0),
    marker('C', const Color(0xFFAEDAFF), 1.0, 1.0),
    marker('R', const Color(0xFF4E9FFF), 0.0, 1.0),
  ];
}

class _StereoProPreview extends StatelessWidget {
  final List<double> scopeFrames;
  final double gainDb;
  final double widthPercent;
  final double asymmetryPercent;
  final double rotationDegrees;

  const _StereoProPreview({
    required this.scopeFrames,
    required this.gainDb,
    required this.widthPercent,
    required this.asymmetryPercent,
    required this.rotationDegrees,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        height: 156,
        decoration: BoxDecoration(
          color: _kFxPanelFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kFxPanelBorder),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: CustomPaint(
          painter: _StereoProPreviewPainter(
            scopeFrames: scopeFrames,
            markers: _buildStereoProStageMarkers(
              gainDb: gainDb,
              widthPercent: widthPercent,
              asymmetryPercent: asymmetryPercent,
              rotationDegrees: rotationDegrees,
            ),
          ),
        ),
      ),
    );
  }
}

class _StereoProPreviewPainter extends CustomPainter {
  final List<double> scopeFrames;
  final List<_StereoStageMarker> markers;

  const _StereoProPreviewPainter({
    required this.scopeFrames,
    required this.markers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = Rect.fromLTWH(
      4.0,
      6.0,
      math.max(0.0, size.width - 8.0),
      math.max(0.0, size.height - 18.0),
    );
    final center = plotRect.center;
    final xExtent = plotRect.width * 0.46;
    final yExtent = plotRect.height * 0.42;
    final grid = Paint()
      ..color = _kFxCoolAccent.withValues(alpha: 0.14)
      ..strokeWidth = 1.0;
    final border = Paint()
      ..color = _kFxCoolAccentSoft.withValues(alpha: 0.22)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..shader = ui.Gradient.linear(
        plotRect.topCenter,
        plotRect.bottomCenter,
        [
          _kFxCoolAccent.withValues(alpha: 0.05),
          _kFxCoolAccentSoft.withValues(alpha: 0.02),
        ],
        const [0.0, 1.0],
      );

    canvas.drawRRect(
      RRect.fromRectAndRadius(plotRect, const Radius.circular(16)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plotRect, const Radius.circular(16)),
      border,
    );

    canvas.drawLine(
      Offset(plotRect.left, center.dy),
      Offset(plotRect.right, center.dy),
      grid,
    );
    canvas.drawLine(
      Offset(center.dx, plotRect.top),
      Offset(center.dx, plotRect.bottom),
      grid,
    );
    canvas.drawLine(plotRect.topLeft, plotRect.bottomRight, grid);
    canvas.drawLine(plotRect.bottomLeft, plotRect.topRight, grid);

    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: xExtent * 1.7,
        height: yExtent * 1.7,
      ),
      Paint()
        ..color = _kFxCoolAccent.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: xExtent * 0.9,
        height: yExtent * 0.9,
      ),
      Paint()
        ..color = _kFxCoolAccentSoft.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final scopeVectors = <Offset>[];
    var scopePeak = 0.0;
    for (int i = 0; i + 1 < scopeFrames.length; i += 2) {
      final leftSample = scopeFrames[i]
          .clamp(-_kStereoProPreviewCeiling, _kStereoProPreviewCeiling)
          .toDouble();
      final rightSample = scopeFrames[i + 1]
          .clamp(-_kStereoProPreviewCeiling, _kStereoProPreviewCeiling)
          .toDouble();
      final xComponent = (rightSample - leftSample) * 0.5;
      final yComponent = (leftSample + rightSample) * 0.5;
      scopePeak = math.max(
        scopePeak,
        math.max(xComponent.abs(), yComponent.abs()),
      );
      scopeVectors.add(Offset(xComponent, yComponent));
    }

    final displayCeiling = (scopePeak * 1.08).clamp(
      0.18,
      _kStereoProPreviewCeiling,
    );
    final scopePoints = <Offset>[];
    for (final vector in scopeVectors) {
      final xNorm = (vector.dx / displayCeiling).clamp(-1.0, 1.0);
      final yNorm = (vector.dy / displayCeiling).clamp(-1.0, 1.0);
      final x = center.dx + (xNorm * xExtent * 0.94);
      final y = center.dy - (yNorm * yExtent * 0.94);
      scopePoints.add(Offset(x, y));
    }

    if (scopePoints.length > 1) {
      final scopePaint = Paint()
        ..color = _kFxCoolAccentSoft.withValues(alpha: 0.38)
        ..strokeWidth = 1.55
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final scopePath = Path()
        ..moveTo(scopePoints.first.dx, scopePoints.first.dy);
      for (int i = 1; i < scopePoints.length; i++) {
        scopePath.lineTo(scopePoints[i].dx, scopePoints[i].dy);
      }
      canvas.drawPath(scopePath, scopePaint);
      canvas.drawPoints(
        ui.PointMode.points,
        scopePoints,
        Paint()
          ..color = _kFxCoolAccent.withValues(alpha: 0.12)
          ..strokeWidth = 1.25
          ..strokeCap = StrokeCap.round,
      );
      final lastPoint = scopePoints.last;
      canvas.drawCircle(
        lastPoint,
        3.6,
        Paint()..color = _kFxCoolAccentSoft.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        lastPoint,
        6.8,
        Paint()..color = _kFxCoolAccentSoft.withValues(alpha: 0.16),
      );
    }

    for (final marker in markers) {
      final x = center.dx + (marker.xNorm * xExtent * 0.82);
      final y = center.dy - (marker.yNorm * yExtent * 0.82);
      final radius = 5.0 + (marker.emphasis * 3.2);
      final fill = Paint()..color = marker.color;
      final glow = Paint()..color = marker.color.withValues(alpha: 0.16);
      canvas.drawCircle(Offset(x, y), radius * 1.9, glow);
      canvas.drawCircle(Offset(x, y), radius, fill);
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width * 0.5, y + radius + 5),
      );
    }

    void drawEdgeLabel(String text, Offset offset,
        {TextAlign align = TextAlign.center}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      tp.paint(canvas, offset);
    }

    drawEdgeLabel(
      'MONO',
      Offset(center.dx - 18, plotRect.top - 2),
    );
    drawEdgeLabel(
      'WIDE',
      Offset(center.dx - 14, plotRect.bottom - 12),
    );
    drawEdgeLabel(
      'L',
      Offset(plotRect.left + 4, center.dy - 8),
    );
    drawEdgeLabel(
      'R',
      Offset(plotRect.right - 10, center.dy - 8),
    );
  }

  @override
  bool shouldRepaint(covariant _StereoProPreviewPainter oldDelegate) {
    return oldDelegate.scopeFrames != scopeFrames ||
        oldDelegate.markers != markers;
  }
}

double _degradeSpreadPercentToOctaves(double spreadPercent) {
  final norm = ((spreadPercent / 100.0).clamp(0.0, 1.0)).toDouble();
  return 0.15 + (7.85 * norm * norm);
}

(double, double) _degradeBandEdgesHz({
  required double toneHz,
  required double spreadPercent,
  required double nyquistHz,
}) {
  final centre = toneHz.clamp(20.0, nyquistHz).toDouble();
  final octaves = _degradeSpreadPercentToOctaves(spreadPercent);
  final halfRatio = math.pow(2.0, octaves * 0.5).toDouble();
  final low = (centre / halfRatio).clamp(20.0, nyquistHz).toDouble();
  final high = (centre * halfRatio).clamp(20.0, nyquistHz).toDouble();
  return (low, math.max(low, high).toDouble());
}

double _degradeLogFrequencyX({
  required double hz,
  required Rect plotRect,
  required double maxHz,
}) {
  const minHz = 20.0;
  final safeMax = maxHz <= minHz ? 20000.0 : maxHz;
  final clampedHz = hz.clamp(minHz, safeMax).toDouble();
  final minLog = math.log(minHz);
  final maxLog = math.log(safeMax);
  final t = (math.log(clampedHz) - minLog) / (maxLog - minLog);
  return plotRect.left + (plotRect.width * t);
}

double _degradeSampleSpectrumAtHz({
  required List<double> spectrumDb,
  required double hz,
  required double binHz,
  required double nyquist,
}) {
  if (spectrumDb.length < 2 || hz <= 0.0 || binHz <= 0.0 || hz > nyquist) {
    return -120.0;
  }

  final idx = hz / binHz;
  final maxIdx = spectrumDb.length - 1;
  if (idx <= 1.0) return spectrumDb[1];
  if (idx >= maxIdx) return spectrumDb[maxIdx];

  final i0 = idx.floor();
  final i1 = math.min(maxIdx, i0 + 1);
  final t = idx - i0;
  return spectrumDb[i0] * (1.0 - t) + spectrumDb[i1] * t;
}

double _degradeFocusProfileLevel({
  required String mode,
  required double hz,
  required double toneHz,
  required double spreadPercent,
  required double maxHz,
}) {
  final safeHz = hz.clamp(20.0, maxHz).toDouble();
  final centreHz = toneHz.clamp(20.0, maxHz).toDouble();

  double octaveDistanceFrom(double edgeHz) {
    return (math.log(safeHz / edgeHz) / math.ln2).abs();
  }

  if (mode == 'Sine') {
    const sigmaOctaves = 0.12;
    final distanceOctaves =
        (math.log(safeHz / centreHz) / math.ln2).abs().toDouble();
    return math.exp(
      -0.5 * math.pow(distanceOctaves / sigmaOctaves, 2.0).toDouble(),
    );
  }

  final (lowHz, highHz) = _degradeBandEdgesHz(
    toneHz: toneHz,
    spreadPercent: spreadPercent,
    nyquistHz: maxHz,
  );

  if (safeHz >= lowHz && safeHz <= highHz) {
    return 1.0;
  }

  final edgeHz = safeHz < lowHz ? lowHz : highHz;
  final featherOctaves = mode == 'Wide Noise' ? 0.55 : 0.28;
  final distanceOctaves = octaveDistanceFrom(edgeHz);
  return math.exp(
    -0.5 * math.pow(distanceOctaves / featherOctaves, 2.0).toDouble(),
  );
}

class _DegradePreview extends StatelessWidget {
  final List<double> spectrumDb;
  final double analyzerSampleRate;
  final String mode;
  final double toneHz;
  final double depthPercent;
  final double spreadPercent;

  const _DegradePreview({
    required this.spectrumDb,
    required this.analyzerSampleRate,
    required this.mode,
    required this.toneHz,
    required this.depthPercent,
    required this.spreadPercent,
  });

  Widget _chip(String label) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nyquist =
        analyzerSampleRate > 1000.0 ? analyzerSampleRate * 0.5 : 22050.0;
    final bandText = mode == 'Sine'
        ? 'Tone ${_fmtHz(toneHz)}'
        : (() {
            final (low, high) = _degradeBandEdgesHz(
              toneHz: toneHz,
              spreadPercent: spreadPercent,
              nyquistHz: nyquist,
            );
            return '${_fmtHz(low)}-${_fmtHz(high)} focus';
          })();

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: _kFxPanelFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kFxPanelBorder),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _chip(mode)),
                const SizedBox(width: 8),
                Expanded(child: _chip('${depthPercent.round()}% depth')),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _chip(bandText)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 146,
              child: CustomPaint(
                painter: _DegradePreviewPainter(
                  spectrumDb: spectrumDb,
                  analyzerSampleRate: analyzerSampleRate,
                  mode: mode,
                  toneHz: toneHz,
                  depthPercent: depthPercent,
                  spreadPercent: spreadPercent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DegradePreviewPainter extends CustomPainter {
  final List<double> spectrumDb;
  final double analyzerSampleRate;
  final String mode;
  final double toneHz;
  final double depthPercent;
  final double spreadPercent;

  const _DegradePreviewPainter({
    required this.spectrumDb,
    required this.analyzerSampleRate,
    required this.mode,
    required this.toneHz,
    required this.depthPercent,
    required this.spreadPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = Rect.fromLTWH(
      4.0,
      4.0,
      math.max(0.0, size.width - 8.0),
      math.max(0.0, size.height - 12.0),
    );
    final rrect = RRect.fromRectAndRadius(plotRect, const Radius.circular(16));
    final maxHz = math
        .min(
          20000.0,
          analyzerSampleRate > 1000.0 ? analyzerSampleRate * 0.5 : 22050.0,
        )
        .toDouble();
    final depthNorm = ((depthPercent / 100.0).clamp(0.0, 1.0)).toDouble();

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          plotRect.topCenter,
          plotRect.bottomCenter,
          [
            _kFxCoolAccent.withValues(alpha: 0.05),
            _kFxCoolAccentSoft.withValues(alpha: 0.02),
          ],
          const [0.0, 1.0],
        ),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _kFxCoolAccent.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    double yForNorm(double norm) {
      return plotRect.bottom - (plotRect.height * norm.clamp(0.0, 1.0));
    }

    for (final hz in <double>[40, 100, 250, 500, 1000, 2500, 5000, 10000]) {
      if (hz >= maxHz) break;
      final x = _degradeLogFrequencyX(hz: hz, plotRect: plotRect, maxHz: maxHz);
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 1.0,
      );
    }

    for (final norm in <double>[0.2, 0.4, 0.6, 0.8]) {
      final y = yForNorm(norm);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..strokeWidth = 1.0,
      );
    }

    final centreX = _degradeLogFrequencyX(
      hz: toneHz,
      plotRect: plotRect,
      maxHz: maxHz,
    );
    final focusColor =
        mode == 'Wide Noise' ? _kFxCoolAccentSoft : _kFxCoolAccent;
    final responseSamples = math.max(96, plotRect.width.floor());
    final responsePath = Path();
    for (int px = 0; px < responseSamples; px++) {
      final t = responseSamples <= 1 ? 0.0 : px / (responseSamples - 1);
      final hz = 20.0 * math.pow(maxHz / 20.0, t).toDouble();
      final response = _degradeFocusProfileLevel(
        mode: mode,
        hz: hz,
        toneHz: toneHz,
        spreadPercent: spreadPercent,
        maxHz: maxHz,
      ).clamp(0.0, 1.0);
      final lift = 0.10 + ((0.22 + (0.46 * depthNorm)) * response);
      final x = plotRect.left + (plotRect.width * t);
      final y = yForNorm(lift);
      if (px == 0) {
        responsePath.moveTo(x, y);
      } else {
        responsePath.lineTo(x, y);
      }
    }

    final responseFill = Path.from(responsePath)
      ..lineTo(plotRect.right, plotRect.bottom)
      ..lineTo(plotRect.left, plotRect.bottom)
      ..close();
    canvas.drawPath(
      responseFill,
      Paint()
        ..shader = ui.Gradient.linear(
          plotRect.topCenter,
          plotRect.bottomCenter,
          [
            focusColor.withValues(alpha: 0.24 + (0.10 * depthNorm)),
            focusColor.withValues(alpha: 0.03),
          ],
          const [0.0, 1.0],
        ),
    );
    canvas.drawPath(
      responsePath,
      Paint()
        ..color = focusColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (mode == 'Sine') {
      canvas.drawLine(
        Offset(centreX, plotRect.top),
        Offset(centreX, plotRect.bottom),
        Paint()
          ..color = focusColor.withValues(alpha: 0.12 + (0.10 * depthNorm))
          ..strokeWidth = 4.0 + (2.0 * depthNorm),
      );
      canvas.drawLine(
        Offset(centreX, plotRect.top),
        Offset(centreX, plotRect.bottom),
        Paint()
          ..color = focusColor.withValues(alpha: 0.78)
          ..strokeWidth = 1.2 + (1.0 * depthNorm),
      );
    } else {
      final (lowHz, highHz) = _degradeBandEdgesHz(
        toneHz: toneHz,
        spreadPercent: spreadPercent,
        nyquistHz: maxHz,
      );
      final leftX = _degradeLogFrequencyX(
        hz: lowHz,
        plotRect: plotRect,
        maxHz: maxHz,
      );
      final rightX = _degradeLogFrequencyX(
        hz: highHz,
        plotRect: plotRect,
        maxHz: maxHz,
      );
      final bandRect =
          Rect.fromLTRB(leftX, plotRect.top, rightX, plotRect.bottom);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bandRect, const Radius.circular(12)),
        Paint()
          ..shader = ui.Gradient.linear(
            bandRect.topLeft,
            bandRect.topRight,
            [
              focusColor.withValues(alpha: 0.04 + (0.10 * depthNorm)),
              focusColor.withValues(alpha: 0.14 + (0.16 * depthNorm)),
              focusColor.withValues(alpha: 0.04 + (0.10 * depthNorm)),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.drawLine(
        Offset(leftX, plotRect.top),
        Offset(leftX, plotRect.bottom),
        Paint()
          ..color = focusColor.withValues(alpha: 0.32)
          ..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(rightX, plotRect.top),
        Offset(rightX, plotRect.bottom),
        Paint()
          ..color = focusColor.withValues(alpha: 0.32)
          ..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(centreX, plotRect.top),
        Offset(centreX, plotRect.bottom),
        Paint()
          ..color = focusColor.withValues(alpha: 0.65)
          ..strokeWidth = 1.2 + (1.2 * depthNorm),
      );
    }

    if (spectrumDb.length > 2) {
      final fftSize = (spectrumDb.length - 1) * 2;
      final sr = analyzerSampleRate > 1000.0 ? analyzerSampleRate : 44100.0;
      final nyquist = sr * 0.5;
      final binHz = fftSize > 0 ? sr / fftSize : 0.0;
      if (fftSize > 0 && binHz > 0.0) {
        var peakDb = -120.0;
        for (int i = 1; i < spectrumDb.length; i++) {
          peakDb = math.max(peakDb, spectrumDb[i]);
        }

        if (peakDb > -110.0) {
          final floorDb = math.max(-110.0, peakDb - 72.0);
          final ceilDb = math.max(floorDb + 8.0, peakDb + 2.0);

          double yForSpectrumDb(double db) {
            final norm = ((db - floorDb) / (ceilDb - floorDb)).clamp(0.0, 1.0);
            return yForNorm(0.06 + (0.80 * norm));
          }

          final spectrumPath = Path();
          final spectrumSamples = math.max(96, plotRect.width.floor());
          for (int px = 0; px < spectrumSamples; px++) {
            final t = spectrumSamples <= 1 ? 0.0 : px / (spectrumSamples - 1);
            final hz = 20.0 * math.pow(maxHz / 20.0, t).toDouble();
            final db = _degradeSampleSpectrumAtHz(
              spectrumDb: spectrumDb,
              hz: hz,
              binHz: binHz,
              nyquist: nyquist,
            );
            final x = plotRect.left + (plotRect.width * t);
            final y = yForSpectrumDb(db);
            if (px == 0) {
              spectrumPath.moveTo(x, y);
            } else {
              spectrumPath.lineTo(x, y);
            }
          }

          final fillPath = Path.from(spectrumPath)
            ..lineTo(plotRect.right, plotRect.bottom)
            ..lineTo(plotRect.left, plotRect.bottom)
            ..close();
          canvas.drawPath(
            fillPath,
            Paint()
              ..shader = ui.Gradient.linear(
                plotRect.topCenter,
                plotRect.bottomCenter,
                [
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.02),
                ],
                const [0.0, 1.0],
              ),
          );
          canvas.drawPath(
            spectrumPath,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.92)
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      }
    }

    final depthBarRect = Rect.fromLTWH(
      plotRect.left + 10,
      plotRect.bottom - 10,
      plotRect.width - 20,
      4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(depthBarRect, const Radius.circular(999)),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          depthBarRect.left,
          depthBarRect.top,
          depthBarRect.width * depthNorm,
          depthBarRect.height,
        ),
        const Radius.circular(999),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          depthBarRect.centerLeft,
          depthBarRect.centerRight,
          [
            focusColor.withValues(alpha: 0.58),
            focusColor.withValues(alpha: 0.92),
          ],
          const [0.0, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _DegradePreviewPainter oldDelegate) {
    return oldDelegate.spectrumDb != spectrumDb ||
        oldDelegate.analyzerSampleRate != analyzerSampleRate ||
        oldDelegate.mode != mode ||
        oldDelegate.toneHz != toneHz ||
        oldDelegate.depthPercent != depthPercent ||
        oldDelegate.spreadPercent != spreadPercent;
  }
}

class _DynamicSoftenerPreview extends StatelessWidget {
  final List<double> frame;
  final String mode;
  final double depthPercent;
  final double detailPercent;
  final double maxCutDb;
  final double lowRangeHz;
  final double highRangeHz;

  const _DynamicSoftenerPreview({
    required this.frame,
    required this.mode,
    required this.depthPercent,
    required this.detailPercent,
    required this.maxCutDb,
    required this.lowRangeHz,
    required this.highRangeHz,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: _kFxPanelFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFxPanelBorder),
      ),
      padding: const EdgeInsets.all(8),
      child: SizedBox.expand(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: _DynamicSoftenerPreviewPainter(
              frame: frame,
              mode: mode,
              depthPercent: depthPercent,
              detailPercent: detailPercent,
              maxCutDb: maxCutDb,
              lowRangeHz: lowRangeHz,
              highRangeHz: highRangeHz,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _DynamicSoftenerPreviewPainter extends CustomPainter {
  final List<double> frame;
  final String mode;
  final double depthPercent;
  final double detailPercent;
  final double maxCutDb;
  final double lowRangeHz;
  final double highRangeHz;

  const _DynamicSoftenerPreviewPainter({
    required this.frame,
    required this.mode,
    required this.depthPercent,
    required this.detailPercent,
    required this.maxCutDb,
    required this.lowRangeHz,
    required this.highRangeHz,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 1.0 || h <= 1.0) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, h),
          <Color>[
            Colors.white.withValues(alpha: 0.04),
            _kFxCoolAccent.withValues(alpha: 0.06),
          ],
          const <double>[0.0, 1.0],
        ),
    );

    double xForHz(double hz) {
      final clampedHz = hz.clamp(20.0, 20000.0).toDouble();
      final t = (math.log(clampedHz / 20.0) / math.log(20000.0 / 20.0))
          .clamp(0.0, 1.0)
          .toDouble();
      return w * t;
    }

    double smoothStep(double edge0, double edge1, double value) {
      if (edge0 == edge1) return value >= edge1 ? 1.0 : 0.0;
      final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
      return t * t * (3.0 - 2.0 * t);
    }

    double rangeWeightForHz(double hz) {
      final logFreq = math.log(hz.clamp(20.0, 20000.0).toDouble());
      final low = math.log(lowRangeHz.clamp(20.0, 20000.0).toDouble());
      final high = math.log(
        math
            .max(lowRangeHz + 20.0, highRangeHz)
            .clamp(20.0, 20000.0)
            .toDouble(),
      );
      final edge = math.log(2.0) * 0.44;
      final lowFade = smoothStep(low - edge, low + edge, logFreq);
      final highFade = 1.0 - smoothStep(high - edge, high + edge, logFreq);
      return (lowFade * highFade).clamp(0.0, 1.0).toDouble();
    }

    const labelLaneHeight = 18.0;
    final graphBottom = math.max(36.0, h - labelLaneHeight);
    final graphHeight = math.max(1.0, graphBottom);

    double yForInputDb(double db) {
      final t = ((db + 86.0) / 96.0).clamp(0.0, 1.0).toDouble();
      return (graphBottom - 2.0) - (graphHeight * 0.86 * t);
    }

    final depthNorm = (depthPercent / 100.0).clamp(0.0, 1.0).toDouble();
    final detailNorm = (detailPercent / 100.0).clamp(0.0, 1.0).toDouble();
    final maxCut = math.max(1.0, maxCutDb);
    const visibleCutDb = 24.0;
    final zeroY = graphBottom * 0.50;

    double yForCutDb(double db) {
      final t = (db / visibleCutDb).clamp(0.0, 1.0).toDouble();
      return zeroY + (graphHeight * 0.38 * t);
    }

    void drawEqFrequencyRegions() {
      const regionEdgesHz = [20.0, 80.0, 300.0, 1200.0, 5000.0, 20000.0];
      const markerHz = [80.0, 300.0, 1200.0, 5000.0, 12000.0];

      final divider = Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1.0;

      for (int i = 0; i < regionEdgesHz.length - 1; i++) {
        final f0 = regionEdgesHz[i];
        final f1 = regionEdgesHz[i + 1];
        final x0 = xForHz(f0);
        final x1 = xForHz(f1);
        final shade = Paint()
          ..color = i.isEven
              ? Colors.white.withValues(alpha: 0.035)
              : Colors.black.withValues(alpha: 0.03);
        canvas.drawRect(Rect.fromLTRB(x0, 0, x1, graphBottom), shade);
        canvas.drawLine(Offset(x0, 0), Offset(x0, graphBottom), divider);
      }
      final lastEdgeX = xForHz(regionEdgesHz.last);
      canvas.drawLine(
          Offset(lastEdgeX, 0), Offset(lastEdgeX, graphBottom), divider);

      for (final hz in markerHz) {
        final x = xForHz(hz);
        canvas.drawLine(Offset(x, 0), Offset(x, graphBottom), divider);
        final tp = TextPainter(
          text: TextSpan(
            text: _fmtHz(hz),
            style: const TextStyle(
              color: _kFxPanelMutedText,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final textX = (x - tp.width * 0.5).clamp(0.0, w - tp.width);
        tp.paint(canvas, Offset(textX, graphBottom + 4.0));
      }
    }

    drawEqFrequencyRegions();

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(w, zeroY), gridPaint);

    final rangeLeft = xForHz(lowRangeHz);
    final rangeRight = xForHz(highRangeHz);
    final rangeRect = Rect.fromLTRB(
      math.min(rangeLeft, rangeRight),
      0,
      math.max(rangeLeft, rangeRight),
      graphBottom,
    );
    canvas.drawRect(
      rangeRect,
      Paint()
        ..color = _kFxCoolAccent.withValues(alpha: 0.055)
        ..style = PaintingStyle.fill,
    );
    final edgePaint = Paint()
      ..color = _kFxCoolAccentSoft.withValues(alpha: 0.42)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(rangeRect.left, 0),
        Offset(rangeRect.left, graphBottom), edgePaint);
    canvas.drawLine(Offset(rangeRect.right, 0),
        Offset(rangeRect.right, graphBottom), edgePaint);

    final frequencies = <double>[];
    final inputDb = <double>[];
    final reductionDb = <double>[];
    for (int i = 0; i + 2 < frame.length; i += 3) {
      final hz = frame[i];
      if (hz <= 0.0) continue;
      frequencies.add(hz);
      inputDb.add(frame[i + 1].clamp(-90.0, 10.0).toDouble());
      reductionDb
          .add(frame[i + 2].clamp(0.0, math.max(1.0, maxCutDb)).toDouble());
    }

    if (frequencies.isEmpty) {
      const idleBands = 48;
      for (int i = 0; i < idleBands; i++) {
        final t = i / (idleBands - 1);
        final hz = 20.0 * math.pow(20000.0 / 20.0, t).toDouble();
        frequencies.add(hz);
        inputDb.add(-82.0 + math.sin(t * math.pi * 4.0) * 2.0);
        reductionDb.add(0.0);
      }
    }

    var peakDb = -90.0;
    for (final db in inputDb) {
      peakDb = math.max(peakDb, db);
    }
    final hasSignal = peakDb > -84.0;

    final spectrumPath = Path();
    double? lastSpectrumY;
    for (int i = 0; i < frequencies.length; i++) {
      final x = xForHz(frequencies[i]);
      final y = yForInputDb(inputDb[i]);
      if (i == 0) {
        spectrumPath.moveTo(0, y);
        if (x > 0.0) spectrumPath.lineTo(x, y);
      } else {
        spectrumPath.lineTo(x, y);
      }
      lastSpectrumY = y;
    }
    if (lastSpectrumY != null) {
      spectrumPath.lineTo(w, lastSpectrumY);
    }
    final spectrumFill = Path.from(spectrumPath)
      ..lineTo(w, graphBottom)
      ..lineTo(0, graphBottom)
      ..close();
    canvas.drawPath(
      spectrumFill,
      Paint()
        ..color = _kFxCoolAccent.withValues(alpha: hasSignal ? 0.18 : 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      spectrumPath,
      Paint()
        ..color = _kFxCoolAccentSoft.withValues(alpha: hasSignal ? 0.82 : 0.46)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );

    final depthCeilingPath = Path();
    const curveSteps = 128;
    for (int i = 0; i <= curveSteps; i++) {
      final t = i / curveSteps;
      final hz = 20.0 * math.pow(20000.0 / 20.0, t).toDouble();
      final allowedCutDb = maxCut * depthNorm * rangeWeightForHz(hz);
      final x = xForHz(hz);
      final y = yForCutDb(allowedCutDb);
      if (i == 0) {
        depthCeilingPath.moveTo(x, y);
      } else {
        depthCeilingPath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      depthCeilingPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );

    final actualReductionPath = Path();
    final reductionFill = Path();
    var hasReductionPath = false;
    var lastReductionY = zeroY;

    for (int i = 0; i < frequencies.length; i++) {
      final measured = (reductionDb[i] / maxCut).clamp(0.0, 1.0).toDouble();
      final actualCutDb = maxCut * measured * rangeWeightForHz(frequencies[i]);
      final x = xForHz(frequencies[i]);
      final y = yForCutDb(actualCutDb);
      if (!hasReductionPath) {
        actualReductionPath.moveTo(0, y);
        if (x > 0.0) actualReductionPath.lineTo(x, y);
        reductionFill.moveTo(0, zeroY);
        reductionFill.lineTo(0, y);
        if (x > 0.0) reductionFill.lineTo(x, y);
        hasReductionPath = true;
      } else {
        actualReductionPath.lineTo(x, y);
        reductionFill.lineTo(x, y);
      }
      lastReductionY = y;

      if (actualCutDb > 0.18) {
        final halfWidth = ui.lerpDouble(9.0, 3.4, detailNorm)!;
        final blobRect = Rect.fromLTRB(
          x - halfWidth,
          zeroY,
          x + halfWidth,
          y,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(blobRect, Radius.circular(halfWidth)),
          Paint()
            ..shader = ui.Gradient.linear(
              blobRect.topCenter,
              blobRect.bottomCenter,
              <Color>[
                _kFxWarmAccentBorder.withValues(alpha: 0.34),
                _kFxWarmAccent.withValues(alpha: 0.035),
              ],
              const <double>[0.0, 1.0],
            ),
        );
      }
    }

    if (hasReductionPath) {
      reductionFill
        ..lineTo(w, lastReductionY)
        ..lineTo(w, zeroY)
        ..lineTo(0, zeroY)
        ..close();
      actualReductionPath.lineTo(w, lastReductionY);
      canvas.drawPath(
        reductionFill,
        Paint()
          ..color = _kFxWarmAccent.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        actualReductionPath,
        Paint()
          ..color = _kFxWarmAccentBorder
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicSoftenerPreviewPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.mode != mode ||
        oldDelegate.depthPercent != depthPercent ||
        oldDelegate.detailPercent != detailPercent ||
        oldDelegate.maxCutDb != maxCutDb ||
        oldDelegate.lowRangeHz != lowRangeHz ||
        oldDelegate.highRangeHz != highRangeHz;
  }
}

enum _ShaperPreviewKind {
  volume,
  time,
}

class _TransientShaperVisualStats {
  final double transient;
  final double body;
  final double pump;
  final double gainNorm;

  const _TransientShaperVisualStats({
    required this.transient,
    required this.body,
    required this.pump,
    required this.gainNorm,
  });

  static _TransientShaperVisualStats fromFrames(List<double> frames) {
    const stride = 6;
    final count = frames.length ~/ stride;
    if (count <= 0) {
      return const _TransientShaperVisualStats(
        transient: 0,
        body: 0,
        pump: 0,
        gainNorm: 0,
      );
    }

    final start = math.max(0, count - 18);
    double transient = 0;
    double body = 0;
    double pump = 0;
    double gain = 0;
    int n = 0;
    for (int i = start; i < count; i++) {
      final o = i * stride;
      transient = math.max(transient, frames[o + 2].clamp(0.0, 1.0).toDouble());
      body = math.max(body, frames[o + 3].clamp(0.0, 1.0).toDouble());
      pump = math.max(pump, frames[o + 4].clamp(0.0, 1.0).toDouble());
      gain += frames[o + 5].clamp(-1.0, 1.0).toDouble();
      n++;
    }

    return _TransientShaperVisualStats(
      transient: transient,
      body: body,
      pump: pump,
      gainNorm: n <= 0 ? 0 : gain / n,
    );
  }
}

class _TransientShaperVisualizerCard extends StatelessWidget {
  final List<double> frames;
  final double attackPercent;
  final double pumpPercent;
  final double sustainPercent;
  final double speedPercent;
  final bool clip;

  const _TransientShaperVisualizerCard({
    required this.frames,
    required this.attackPercent,
    required this.pumpPercent,
    required this.sustainPercent,
    required this.speedPercent,
    required this.clip,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _TransientShaperVisualStats.fromFrames(frames);
    final gainDb = stats.gainNorm * 24.0;
    final gainLabel = gainDb >= 0
        ? '+${gainDb.toStringAsFixed(1)} dB'
        : '${gainDb.toStringAsFixed(1)} dB';

    return Container(
      height: 142,
      decoration: BoxDecoration(
        color: _kFxPanelFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFxPanelBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 34),
              child: CustomPaint(
                painter: _TransientShaperVisualizerPainter(
                  frames: frames,
                  attackPercent: attackPercent,
                  sustainPercent: sustainPercent,
                  pumpPercent: pumpPercent,
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Row(
                children: [
                  Expanded(
                    child: _TransientActivityPill(
                      label: 'Attack',
                      value: stats.transient,
                      setting: attackPercent,
                      color: const Color(0xFFF2A85B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _TransientActivityPill(
                      label: 'Body',
                      value: stats.body,
                      setting: sustainPercent,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _TransientActivityPill(
                      label: clip ? 'Clip' : 'Gain',
                      value: clip
                          ? 1.0
                          : stats.gainNorm.abs().clamp(0.0, 1.0).toDouble(),
                      setting: speedPercent,
                      color: clip
                          ? const Color(0xFFF87171)
                          : (gainDb >= 0
                              ? const Color(0xFFA7F3D0)
                              : const Color(0xFFFCA5A5)),
                      valueText: clip ? 'On' : gainLabel,
                    ),
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

class _TransientActivityPill extends StatelessWidget {
  final String label;
  final double value;
  final double setting;
  final Color color;
  final String? valueText;

  const _TransientActivityPill({
    required this.label,
    required this.value,
    required this.setting,
    required this.color,
    this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueText ??
        (setting >= 0 ? '+${setting.round()}' : '${setting.round()}');
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.30 + value * 0.62),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              display,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransientShaperVisualizerPainter extends CustomPainter {
  final List<double> frames;
  final double attackPercent;
  final double sustainPercent;
  final double pumpPercent;

  const _TransientShaperVisualizerPainter({
    required this.frames,
    required this.attackPercent,
    required this.sustainPercent,
    required this.pumpPercent,
  });

  static const int _stride = 6;

  double _frameValue(int index, int offset) {
    final i = index * _stride + offset;
    if (i < 0 || i >= frames.length) return 0.0;
    return frames[i].clamp(-1.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.0);
    final centerY = rect.center.dy;
    final count = frames.length ~/ _stride;
    final radius = Radius.circular(math.min(12.0, rect.height * 0.18));

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawLine(
      Offset(rect.left + 8, centerY),
      Offset(rect.right - 8, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );

    if (count <= 1) {
      final idle = Path()
        ..moveTo(rect.left + 10, centerY)
        ..cubicTo(
            rect.left + rect.width * 0.30,
            centerY - 8,
            rect.left + rect.width * 0.56,
            centerY + 8,
            rect.right - 10,
            centerY);
      canvas.drawPath(
        idle,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final inputPath = Path();
    final outputPath = Path();
    final attackPath = Path();
    final sustainPath = Path();
    final attackNorm = (attackPercent.abs() / 100.0).clamp(0.0, 1.0).toDouble();
    final sustainNorm =
        (sustainPercent.abs() / 100.0).clamp(0.0, 1.0).toDouble();
    final pumpNorm = (pumpPercent.abs() / 100.0).clamp(0.0, 1.0).toDouble();

    for (int i = 0; i < count; i++) {
      final t = count == 1 ? 0.0 : i / (count - 1);
      final x = rect.left + rect.width * t;
      final input = math.sqrt(_frameValue(i, 0).clamp(0.0, 1.0));
      final output = math.sqrt(_frameValue(i, 1).clamp(0.0, 1.0));
      final inputY = centerY - input * rect.height * 0.34;
      final outputY = centerY - output * rect.height * 0.36;
      final attackY =
          centerY - (input * (0.24 + attackNorm * 0.30)) * rect.height;
      final sustainY =
          centerY + (output * (0.18 + sustainNorm * 0.24)) * rect.height;

      if (i == 0) {
        inputPath.moveTo(x, inputY);
        outputPath.moveTo(x, outputY);
        attackPath.moveTo(x, centerY);
        attackPath.lineTo(x, attackY);
        sustainPath.moveTo(x, centerY);
        sustainPath.lineTo(x, sustainY);
      } else {
        inputPath.lineTo(x, inputY);
        outputPath.lineTo(x, outputY);
        attackPath.lineTo(x, attackY);
        sustainPath.lineTo(x, sustainY);
      }
    }
    attackPath
      ..lineTo(rect.right, centerY)
      ..close();
    sustainPath
      ..lineTo(rect.right, centerY)
      ..close();

    canvas.drawPath(
      attackPath,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          Offset(rect.center.dx, centerY),
          [
            const Color(0xFFF2A85B).withValues(alpha: 0.28),
            const Color(0xFFF2A85B).withValues(alpha: 0.02),
          ],
        ),
    );
    canvas.drawPath(
      sustainPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(rect.center.dx, centerY),
          rect.bottomCenter,
          [
            const Color(0xFF7DD3FC).withValues(alpha: 0.02),
            const Color(0xFF7DD3FC).withValues(alpha: 0.22),
          ],
        ),
    );

    canvas.drawPath(
      inputPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      outputPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pumpY = centerY + rect.height * (0.34 - pumpNorm * 0.30);
    canvas.drawLine(
      Offset(rect.left + 10, pumpY),
      Offset(rect.right - 10, pumpY),
      Paint()
        ..color =
            const Color(0xFFF87171).withValues(alpha: 0.16 + pumpNorm * 0.20)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TransientShaperVisualizerPainter oldDelegate) {
    return oldDelegate.frames != frames ||
        oldDelegate.attackPercent != attackPercent ||
        oldDelegate.sustainPercent != sustainPercent ||
        oldDelegate.pumpPercent != pumpPercent;
  }
}

class _ShaperPreviewCard extends StatelessWidget {
  final _ShaperPreviewKind kind;
  final List<double> previewFrames;
  final String title;
  final String detail;

  const _ShaperPreviewCard({
    required this.kind,
    required this.previewFrames,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final accent = kind == _ShaperPreviewKind.volume
        ? const Color(0xFFFB923C)
        : const Color(0xFF38BDF8);
    final icon = kind == _ShaperPreviewKind.volume
        ? Icons.show_chart_rounded
        : Icons.timeline_rounded;

    return Container(
      height: 156,
      decoration: BoxDecoration(
        color: _kFxPanelFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFxPanelBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: CustomPaint(
                painter: _ShaperPreviewPainter(
                  kind: kind,
                  previewFrames: previewFrames,
                  accent: accent,
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _ShaperPreviewChip(
                accent: accent,
                icon: icon,
                label: title,
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: _ShaperPreviewChip(
                accent: accent,
                label: detail,
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShaperPreviewChip extends StatelessWidget {
  final Color accent;
  final IconData? icon;
  final String label;
  final bool compact;

  const _ShaperPreviewChip({
    required this.accent,
    required this.label,
    this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: compact ? 112 : 164,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 11,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1722).withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: compact ? 0.80 : 0.92),
                  fontSize: compact ? 11.0 : 11.6,
                  fontWeight: compact ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShaperPreviewPainter extends CustomPainter {
  final _ShaperPreviewKind kind;
  final List<double> previewFrames;
  final Color accent;

  const _ShaperPreviewPainter({
    required this.kind,
    required this.previewFrames,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = 6.0;
    final plotTop = 12.0;
    final plotRight = size.width - 6.0;
    final plotBottom = size.height - 22.0;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;
    final plotRect = Rect.fromLTRB(plotLeft, plotTop, plotRight, plotBottom);

    canvas.drawRRect(
      RRect.fromRectAndRadius(plotRect, const Radius.circular(16)),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(plotLeft, plotTop),
          Offset(plotRight, plotBottom),
          <Color>[
            Colors.white.withValues(alpha: 0.04),
            accent.withValues(alpha: 0.08),
          ],
          const [0.0, 1.0],
        ),
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    for (final yStep in const <double>[0.0, 0.5, 1.0]) {
      final y = plotTop + ((1.0 - yStep) * plotHeight);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
    }
    for (final xStep in const <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
      final x = plotLeft + (xStep * plotWidth);
      canvas.drawLine(
        Offset(x, plotTop),
        Offset(x, plotBottom),
        Paint()
          ..color = Colors.white
              .withValues(alpha: xStep == 0.0 || xStep == 1.0 ? 0.08 : 0.04)
          ..strokeWidth = 1.0,
      );
    }

    final phase = previewFrames.isNotEmpty
        ? previewFrames.first.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final curve = previewFrames.length > 1
        ? previewFrames
            .skip(1)
            .map((e) => e.clamp(0.0, 1.0).toDouble())
            .toList(growable: false)
        : const <double>[1.0, 1.0];

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < curve.length; i++) {
      final t = curve.length <= 1 ? 0.0 : i / (curve.length - 1);
      final x = plotLeft + (t * plotWidth);
      final y = plotTop + ((1.0 - curve[i]) * plotHeight);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath
          ..moveTo(x, plotBottom)
          ..lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(plotRight, plotBottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(plotLeft, plotTop),
          Offset(plotRight, plotBottom),
          <Color>[
            accent.withValues(alpha: 0.26),
            accent.withValues(alpha: 0.08),
          ],
          const [0.0, 1.0],
        )
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    final playheadX = plotLeft + (phase * plotWidth);
    canvas.drawLine(
      Offset(playheadX, plotTop - 2),
      Offset(playheadX, plotBottom + 2),
      Paint()
        ..color = accent.withValues(alpha: 0.88)
        ..strokeWidth = 1.5,
    );
    final playheadIndex = curve.isEmpty
        ? 0
        : ((curve.length - 1) * phase).round().clamp(0, curve.length - 1);
    final playheadY = plotTop + ((1.0 - curve[playheadIndex]) * plotHeight);
    canvas.drawCircle(
      Offset(playheadX, playheadY),
      4.5,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(playheadX, playheadY),
      4.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final footerLabelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.66),
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
    );
    final leftLabelPainter = TextPainter(
      text: TextSpan(
        text: kind == _ShaperPreviewKind.volume ? 'Start' : 'Now',
        style: footerLabelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rightLabelPainter = TextPainter(
      text: TextSpan(
        text: kind == _ShaperPreviewKind.volume ? 'End' : 'Ahead',
        style: footerLabelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelY = plotBottom + 2.0;
    leftLabelPainter.paint(canvas, Offset(plotLeft, labelY));
    final rightLabelX = plotRight - rightLabelPainter.width;
    rightLabelPainter.paint(
      canvas,
      Offset(rightLabelX, labelY),
    );

    final directionPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final labelHeight = math.max(
      leftLabelPainter.height,
      rightLabelPainter.height,
    );
    final directionY = labelY + (labelHeight * 0.5);
    final directionStartX = plotLeft + leftLabelPainter.width + 14.0;
    final directionEndX = rightLabelX - 10.0;
    if (directionEndX > directionStartX + 8.0) {
      final directionStart = Offset(directionStartX, directionY);
      final arrowTip = Offset(directionEndX, directionY);
      final arrowBaseX = arrowTip.dx - 6.0;
      canvas.drawLine(
        directionStart,
        Offset(arrowBaseX - 0.5, directionY),
        directionPaint,
      );
      final arrowHead = Path()
        ..moveTo(arrowBaseX, directionY - 4.0)
        ..lineTo(arrowTip.dx, arrowTip.dy)
        ..lineTo(arrowBaseX, directionY + 4.0);
      canvas.drawPath(arrowHead, directionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShaperPreviewPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.previewFrames != previewFrames ||
        oldDelegate.accent != accent;
  }
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
        color: _kFxPanelFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFxPanelBorder),
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
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    for (int i = 0; i < regionEdgesHz.length - 1; i++) {
      final f0 = regionEdgesHz[i];
      final f1 = regionEdgesHz[i + 1];
      final x0 = _xForHz(f0, w);
      final x1 = _xForHz(f1, w);
      final shade = Paint()
        ..color = i.isEven
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.black.withValues(alpha: 0.03);
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
            color: _kFxPanelMutedText,
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
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);
    final zeroLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
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
    // At boundary settings (HPF min / LPF max), treat filters as neutral so
    // the default visualizer edges stay straight instead of showing a -3 dB knee.
    const cutoffNeutralToleranceHz = 1.0;
    final hpfIsNeutral = (hpf - _minF).abs() <= cutoffNeutralToleranceHz;
    final lpfIsNeutral = (lpf - _maxF).abs() <= cutoffNeutralToleranceHz;

    // HPF/LPF markers
    final xHPF = _xForHz(hpf, w);
    final xLPF = _xForHz(lpf, w);
    final marker = Paint()
      ..color = _kFxCoolAccentSoft.withValues(alpha: 0.55)
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

      if (!hpfIsNeutral) {
        db += _butterworthHighpassDb(
          f: f.toDouble(),
          fc: hpf,
          slopeDbOct: hpfSlopeDbOct,
        );
      }
      if (!lpfIsNeutral) {
        db += _butterworthLowpassDb(
          f: f.toDouble(),
          fc: lpf,
          slopeDbOct: lpfSlopeDbOct,
        );
      }

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
      ..color = _kFxWarmAccent.withValues(alpha: 0.20)
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
          ..color = _kFxCoolAccent.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        spectrumPath,
        Paint()
          ..color = _kFxCoolAccentSoft.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..isAntiAlias = true,
      );
    }

    // draw stroke curve
    final strokePaint = Paint()
      ..color = _kFxWarmAccentBorder
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
        color: _kFxPanelFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFxPanelBorder),
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
          color: _kFxPanelMutedText,
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
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), axis);

    // faint center line (0 dB)
    final midLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), midLine);

    // band markers (optional but helps “visual accuracy”)
    final marker = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
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
      ..color = _kFxWarmAccent.withValues(alpha: 0.20)
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
          ..color = _kFxCoolAccent.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        spectrumPath,
        Paint()
          ..color = _kFxCoolAccentSoft.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..isAntiAlias = true,
      );
    }

    final strokePaint = Paint()
      ..color = _kFxWarmAccentBorder
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
  VoidCallback? onValueTap,
  ValueChanged<Offset>? onLongPressStart,
  String? unit, // e.g. "Hz"
  bool logarithmic = false,
  double? width,
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

  final faderWidth = width ??
      switch (unit) {
        'Hz' => 72.0,
        'dB' => 68.0,
        _ => 56.0,
      };

  return _EqVerticalFader(
    width: faderWidth,
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
    onValueTap: onValueTap,
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
  final VoidCallback? onValueTap;
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
    required this.onValueTap,
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
            Tooltip(
              message: 'Enter value',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.onValueTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: SizedBox(
                    width: widget.width - 8,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.labelText,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
    final displayDb = grDb.clamp(0.0, 120.0);
    final t = (clamped / maxDb).clamp(0.0, 1.0); // 0..1 (0 = no GR)

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _kFxPanelMutedText,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        );

    final readoutStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _kFxPanelText,
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
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "-${displayDb.toStringAsFixed(1)} dB",
                    style: readoutStyle,
                  ),
                ),
              ),
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
    final bg = Paint()..color = const Color(0xFF545B62);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _kFxPanelBorder;

    final outer =
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h / 2));
    c.drawRRect(outer, bg);
    c.drawRRect(outer, border);

    // Inner track
    const pad = 3.0;
    final track = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);

    final trackPaint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    c.drawRRect(
        RRect.fromRectAndRadius(track, Radius.circular(track.height / 2)),
        trackPaint);

    // Fill (left -> right)
    final fillW = (track.width * t).clamp(0.0, track.width);
    final fillRect = Rect.fromLTWH(track.left, track.top, fillW, track.height);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[_kFxCoolAccent, _kFxWarmAccent],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(fillRect);
    c.drawRRect(
        RRect.fromRectAndRadius(fillRect, Radius.circular(track.height / 2)),
        fillPaint);

    // Thumb (slider handle look)
    // Thumb sits at end of fill
    final thumbX = (track.left + fillW).clamp(track.left, track.right);
    final thumbW = 6.0;
    final thumbRect = Rect.fromLTWH(
        thumbX - thumbW / 2, track.top - 1, thumbW, track.height + 2);

    final thumbPaint = Paint()..color = _kFxPanelText;
    c.drawRRect(RRect.fromRectAndRadius(thumbRect, const Radius.circular(6)),
        thumbPaint);

    // Simple tick marks (optional, subtle)
    final tick = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
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
