import 'package:juce_audio_engine/juce_audio_engine.dart';

class AudioInputDevicePolicy {
  const AudioInputDevicePolicy();

  Map<String, String> displayLabelsByUid(
    Iterable<AudioInputDeviceInfo> devices,
  ) {
    final devicesByUid = <String, AudioInputDeviceInfo>{};
    for (final device in devices) {
      final uid = device.uid.trim();
      final name = device.name.trim();
      if (uid.isEmpty || name.isEmpty) continue;
      devicesByUid.putIfAbsent(uid, () => device);
    }

    final groups = <String, List<AudioInputDeviceInfo>>{};
    for (final device in devicesByUid.values) {
      groups.putIfAbsent(_displayNameKey(device.name), () => []).add(device);
    }

    final labels = <String, String>{};
    for (final group in groups.values) {
      if (group.length == 1) {
        final device = group.single;
        labels[device.uid.trim()] = device.name.trim();
        continue;
      }
      final ordered = [...group]
        ..sort((left, right) => left.uid.trim().compareTo(right.uid.trim()));
      for (var index = 0; index < ordered.length; index++) {
        final device = ordered[index];
        labels[device.uid.trim()] =
            '${device.name.trim()} · ${_transportLabel(device.transport)} ${index + 1}';
      }
    }
    return labels;
  }

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

  String _displayNameKey(String value) => value.trim().toLowerCase();

  String _transportLabel(String transport) {
    return switch (transport.trim().toLowerCase()) {
      'builtin' => 'Built-in',
      'bluetooth' => 'Bluetooth',
      'usb' => 'USB',
      'firewire' => 'FireWire',
      'pci' => 'PCI',
      'aggregate' => 'Aggregate',
      'virtual' => 'Virtual',
      _ => 'External',
    };
  }
}
