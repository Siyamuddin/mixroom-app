import 'package:juce_audio_engine/juce_audio_engine.dart';

class AudioInputDevicePolicy {
  const AudioInputDevicePolicy();

  bool isBluetoothInput(AudioInputDeviceInfo info) => info.isBluetoothInput;

  String? builtInInputName(Iterable<AudioInputDeviceInfo> devices) {
    for (final device in devices) {
      if (device.name.trim().isNotEmpty &&
          device.isBuiltIn &&
          !device.isBluetoothInput) {
        return device.name;
      }
    }
    return null;
  }

  AudioInputDeviceInfo? findByName(
    Iterable<AudioInputDeviceInfo> devices,
    String? name,
  ) {
    final normalized = _normalizeName(name ?? '');
    if (normalized.isEmpty) return null;
    for (final device in devices) {
      final candidate = _normalizeName(device.name);
      if (candidate.isEmpty) continue;
      if (candidate == normalized ||
          candidate.contains(normalized) ||
          normalized.contains(candidate)) {
        return device;
      }
    }
    return null;
  }

  String? safeFallbackName({
    required Iterable<AudioInputDeviceInfo> devices,
    String? selectedName,
    String? currentName,
    bool preferBuiltIn = false,
  }) {
    final list = devices
        .where((device) => device.name.trim().isNotEmpty)
        .toList(growable: false);

    if (preferBuiltIn) {
      for (final device in list) {
        if (device.isBuiltIn && !device.isBluetoothInput) return device.name;
      }
    }

    final selected = findByName(list, selectedName);
    if (selected != null && !selected.isBluetoothInput) {
      return selectedName?.trim();
    }

    final current = findByName(list, currentName);
    if (current != null && !current.isBluetoothInput) {
      return currentName?.trim();
    }

    for (final device in list) {
      if (device.isBuiltIn && !device.isBluetoothInput) return device.name;
    }

    for (final device in list) {
      if (!device.isBluetoothInput &&
          (device.transport == 'usb' ||
              device.transport == 'firewire' ||
              device.transport == 'pci' ||
              device.transport == 'aggregate' ||
              device.transport == 'virtual')) {
        return device.name;
      }
    }

    for (final device in list) {
      if (!device.isBluetoothInput) return device.name;
    }

    return null;
  }

  String _normalizeName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
