import 'package:juce_audio_engine/juce_audio_engine.dart';

/// Physical input ranges, independent of saved routing and opened channel masks.
class MacInputChannelOption {
  const MacInputChannelOption(this.start, this.count);
  final int start;
  final int count;

  String label(List<String> names) {
    final numbered = count == 1
        ? 'Input ${start + 1}'
        : 'Inputs ${start + 1}–${start + count}';
    final labels = <String>[];
    for (var i = start; i < start + count; i++) {
      if (i >= 0 && i < names.length && names[i].trim().isNotEmpty) {
        labels.add(names[i].trim());
      }
    }
    return labels.isEmpty ? numbered : '$numbered — ${labels.join(' / ')}';
  }

  @override
  bool operator ==(Object other) =>
      other is MacInputChannelOption &&
      start == other.start &&
      count == other.count;
  @override
  int get hashCode => Object.hash(start, count);
}

List<MacInputChannelOption> macInputChannelOptions(int capacity) => [
  for (var i = 0; i < capacity; i++) MacInputChannelOption(i, 1),
  for (var i = 0; i + 1 < capacity; i += 2) MacInputChannelOption(i, 2),
];

bool macInputChannelSelectionIsValid(int capacity, int start, int count) =>
    capacity > 0 &&
    start >= 0 &&
    (count == 1 || (count == 2 && start.isEven)) &&
    start + count <= capacity;

AudioInputDeviceInfo? resolveMacInputDevice(
  List<AudioInputDeviceInfo> devices,
  String? selectedUID,
) {
  final matches = devices
      .where(
        (device) =>
            selectedUID == null ? device.isDefault : device.uid == selectedUID,
      )
      .toList();
  return matches.length == 1 ? matches.single : null;
}
