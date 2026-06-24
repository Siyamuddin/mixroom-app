import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/helpers/desktop_slider_wheel_sensitivity.dart';

class DesktopScrollableSlider extends StatelessWidget {
  const DesktopScrollableSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.secondaryActiveColor,
    this.thumbColor,
    this.overlayColor,
    this.mouseCursor,
    this.semanticFormatterCallback,
    this.focusNode,
    this.autofocus = false,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? secondaryActiveColor;
  final Color? thumbColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final MouseCursor? mouseCursor;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final FocusNode? focusNode;
  final bool autofocus;

  double get _scrollStep {
    final range = (max - min).abs();
    if (range <= 0) return 0;
    final divided = divisions;
    if (divided != null && divided > 0) return range / divided;
    return range / 100.0;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final callback = onChanged;
    if (callback == null ||
        event is! PointerScrollEvent ||
        !PlatformCapabilities.current.isDesktop) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      _applyScroll(resolved, callback);
    });
  }

  void _applyScroll(
    PointerScrollEvent event,
    ValueChanged<double> callback,
  ) {
    final step = _scrollStep;
    if (step <= 0) return;

    final keyboard = HardwareKeyboard.instance;
    final modifier =
        DesktopSliderWheelSensitivityStore.multiplierForKeyboard(keyboard);
    final notches =
        event.scrollDelta.dy.abs() < 1 ? 0.0 : event.scrollDelta.dy.sign * -1.0;
    if (notches == 0) return;

    final next = (value + notches * step * modifier).clamp(min, max).toDouble();
    if ((next - value).abs() < 0.000001) return;
    onChangeStart?.call(value);
    callback(next);
    onChangeEnd?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handlePointerSignal,
      child: Slider(
        value: value,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        secondaryActiveColor: secondaryActiveColor,
        thumbColor: thumbColor,
        overlayColor: overlayColor,
        mouseCursor: mouseCursor,
        semanticFormatterCallback: semanticFormatterCallback,
        focusNode: focusNode,
        autofocus: autofocus,
      ),
    );
  }
}

class DesktopScrollableRangeSlider extends StatelessWidget {
  const DesktopScrollableRangeSlider({
    super.key,
    required this.values,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.labels,
    this.activeColor,
    this.inactiveColor,
    this.overlayColor,
    this.mouseCursor,
    this.semanticFormatterCallback,
  });

  final RangeValues values;
  final ValueChanged<RangeValues>? onChanged;
  final ValueChanged<RangeValues>? onChangeStart;
  final ValueChanged<RangeValues>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final RangeLabels? labels;
  final Color? activeColor;
  final Color? inactiveColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final WidgetStateProperty<MouseCursor?>? mouseCursor;
  final SemanticFormatterCallback? semanticFormatterCallback;

  double get _scrollStep {
    final range = (max - min).abs();
    if (range <= 0) return 0;
    final divided = divisions;
    if (divided != null && divided > 0) return range / divided;
    return range / 100.0;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final callback = onChanged;
    if (callback == null ||
        event is! PointerScrollEvent ||
        !PlatformCapabilities.current.isDesktop) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      _applyScroll(resolved, callback);
    });
  }

  void _applyScroll(
    PointerScrollEvent event,
    ValueChanged<RangeValues> callback,
  ) {
    final step = _scrollStep;
    if (step <= 0) return;

    final keyboard = HardwareKeyboard.instance;
    final modifier =
        DesktopSliderWheelSensitivityStore.multiplierForKeyboard(keyboard);
    final direction =
        event.scrollDelta.dy.abs() < 1 ? 0.0 : event.scrollDelta.dy.sign * -1.0;
    if (direction == 0) return;

    final span = values.end - values.start;
    final delta = direction * step * modifier;
    var nextStart = values.start + delta;
    var nextEnd = values.end + delta;
    if (nextStart < min) {
      nextStart = min;
      nextEnd = math.min(max, min + span);
    } else if (nextEnd > max) {
      nextEnd = max;
      nextStart = math.max(min, max - span);
    }
    final next = RangeValues(nextStart, nextEnd);
    if ((next.start - values.start).abs() < 0.000001 &&
        (next.end - values.end).abs() < 0.000001) {
      return;
    }
    onChangeStart?.call(values);
    callback(next);
    onChangeEnd?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handlePointerSignal,
      child: RangeSlider(
        values: values,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        divisions: divisions,
        labels: labels,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        overlayColor: overlayColor,
        mouseCursor: mouseCursor,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}
