import 'package:flutter/material.dart';
import 'package:juce_audio_engine/android_recording_input_v2.dart';
import 'package:mixroom/widgets/system_default_mono_input_channel_selector.dart';

class AndroidInputChannelSelector extends StatelessWidget {
  const AndroidInputChannelSelector({
    super.key,
    required this.configuration,
    required this.start,
    required this.count,
    required this.enabled,
    required this.decoration,
    required this.onUseSupportedInput,
  });
  final AndroidRecordingInputV2? configuration;
  final int start;
  final int count;
  final bool enabled;
  final InputDecoration decoration;
  final VoidCallback onUseSupportedInput;

  @override
  Widget build(BuildContext context) {
    final config = configuration;
    return SystemDefaultMonoInputChannelSelector(
      configurationKnown: config != null,
      inputAvailable: config?.inputAvailable,
      supportedStart: config?.channelStart ?? 0,
      supportedCount: config?.channelCount ?? 1,
      start: start,
      count: count,
      enabled: enabled,
      decoration: decoration,
      onUseSupportedInput: onUseSupportedInput,
    );
  }
}
