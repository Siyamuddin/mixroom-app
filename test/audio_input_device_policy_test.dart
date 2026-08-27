import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/helpers/audio_input_device_policy.dart';

void main() {
  const policy = AudioInputDevicePolicy();

  const builtIn = AudioInputDeviceInfo(
    name: 'MacBook Pro Microphone',
    isBluetoothInput: false,
    isBuiltIn: true,
    isDefault: false,
    transport: 'builtIn',
  );
  const interface = AudioInputDeviceInfo(
    name: 'Scarlett 2i2',
    isBluetoothInput: false,
    isBuiltIn: false,
    isDefault: true,
    transport: 'usb',
  );
  const airPods = AudioInputDeviceInfo(
    name: 'AirPods Pro',
    isBluetoothInput: true,
    isBuiltIn: false,
    isDefault: false,
    transport: 'bluetooth',
  );

  test('keeps selected non-Bluetooth input before other fallbacks', () {
    final fallback = policy.safeFallbackName(
      devices: const [builtIn, interface, airPods],
      selectedName: 'Scarlett 2i2',
      currentName: 'AirPods Pro',
    );

    expect(fallback, 'Scarlett 2i2');
  });

  test('can prefer built-in input over another selected non-Bluetooth input',
      () {
    final fallback = policy.safeFallbackName(
      devices: const [interface, builtIn, airPods],
      selectedName: 'Scarlett 2i2',
      currentName: 'Scarlett 2i2',
      preferBuiltIn: true,
    );

    expect(fallback, 'MacBook Pro Microphone');
  });

  test('preserves selectable name when it fuzzy-matches metadata', () {
    const metadataName = AudioInputDeviceInfo(
      name: 'MacBook Pro Microphone',
      isBluetoothInput: false,
      isBuiltIn: true,
      isDefault: true,
      transport: 'builtIn',
    );

    final fallback = policy.safeFallbackName(
      devices: const [metadataName, airPods],
      selectedName: 'MacBook Pro Mic',
      currentName: 'AirPods Pro',
    );

    expect(fallback, 'MacBook Pro Mic');
  });

  test('uses built-in mic when selected and current inputs are Bluetooth', () {
    final fallback = policy.safeFallbackName(
      devices: const [airPods, interface, builtIn],
      selectedName: 'AirPods Pro',
      currentName: 'AirPods Pro',
    );

    expect(fallback, 'MacBook Pro Microphone');
  });

  test('falls back to interface when no built-in mic is available', () {
    final fallback = policy.safeFallbackName(
      devices: const [airPods, interface],
      selectedName: 'AirPods Pro',
      currentName: 'AirPods Pro',
    );

    expect(fallback, 'Scarlett 2i2');
  });

  test('returns null when every available input is Bluetooth', () {
    final fallback = policy.safeFallbackName(
      devices: const [airPods],
      selectedName: 'AirPods Pro',
      currentName: 'AirPods Pro',
    );

    expect(fallback, isNull);
  });

  test(
    'keeps unique labels and distinguishes duplicate names by stable UID',
    () {
      const duplicateB = AudioInputDeviceInfo(
        uid: 'input-b',
        name: 'Studio Interface',
        isBluetoothInput: false,
        isBuiltIn: false,
        isDefault: false,
        transport: 'usb',
      );
      const duplicateA = AudioInputDeviceInfo(
        uid: 'input-a',
        name: 'Studio Interface',
        isBluetoothInput: false,
        isBuiltIn: false,
        isDefault: false,
        transport: 'usb',
      );
      const unique = AudioInputDeviceInfo(
        uid: 'built-in-input',
        name: 'MacBook Microphone',
        isBluetoothInput: false,
        isBuiltIn: true,
        isDefault: true,
        transport: 'builtIn',
      );

      final labels = policy.displayLabelsByUid(const [
        duplicateB,
        unique,
        duplicateA,
      ]);

      expect(labels['built-in-input'], 'MacBook Microphone');
      expect(labels['input-a'], 'Studio Interface · USB 1');
      expect(labels['input-b'], 'Studio Interface · USB 2');
      expect(labels.values.where((label) => label.contains('input-')), isEmpty);
    },
  );

  test(
    'duplicate labels retain distinct transports and ignore invalid IDs',
    () {
      const aggregate = AudioInputDeviceInfo(
        uid: 'device-a',
        name: 'Shared Name',
        isBluetoothInput: false,
        isBuiltIn: false,
        isDefault: false,
        transport: 'aggregate',
      );
      const virtualDevice = AudioInputDeviceInfo(
        uid: 'device-b',
        name: 'Shared Name',
        isBluetoothInput: false,
        isBuiltIn: false,
        isDefault: false,
        transport: 'virtual',
      );
      const missingUid = AudioInputDeviceInfo(
        name: 'Shared Name',
        isBluetoothInput: false,
        isBuiltIn: false,
        isDefault: false,
        transport: 'usb',
      );

      final labels = policy.displayLabelsByUid(const [
        virtualDevice,
        missingUid,
        aggregate,
      ]);

      expect(labels, hasLength(2));
      expect(labels['device-a'], 'Shared Name · Aggregate 1');
      expect(labels['device-b'], 'Shared Name · Virtual 2');
    },
  );
}
