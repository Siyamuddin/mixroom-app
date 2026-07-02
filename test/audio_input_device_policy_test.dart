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
}
