import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/helpers/mac_input_channel_policy.dart';

AudioInputDeviceInfo device(
  String uid,
  int channels, {
  bool isDefault = false,
}) => AudioInputDeviceInfo(
  uid: uid,
  name: 'Same name',
  channelCount: channels,
  isBluetoothInput: false,
  isBuiltIn: false,
  isDefault: isDefault,
  transport: 'external',
);
void main() {
  test(
    'lists only physical mono channels and complete nonoverlapping pairs',
    () {
      for (final count in [0, 1, 2, 3, 8, 257]) {
        final options = macInputChannelOptions(count);
        expect(options.length, count + count ~/ 2);
        expect(
          options.every(
            (o) => macInputChannelSelectionIsValid(count, o.start, o.count),
          ),
          isTrue,
        );
        expect(
          options.where((o) => o.count == 1).map((o) => o.start),
          List.generate(count, (i) => i),
        );
      }
    },
  );
  test(
    'saved selections cannot manufacture capacity or silently become mono',
    () {
      expect(macInputChannelSelectionIsValid(1, 0, 2), isFalse);
      expect(macInputChannelSelectionIsValid(2, 255, 1), isFalse);
      expect(macInputChannelSelectionIsValid(4, 1, 2), isFalse);
      expect(macInputChannelSelectionIsValid(4, 0, 3), isFalse);
      expect(macInputChannelSelectionIsValid(4, -1, 1), isFalse);
      expect(macInputChannelSelectionIsValid(0, 0, 1), isFalse);
      const saved = MacInputChannelOption(6, 2);
      expect(macInputChannelOptions(2).contains(saved), isFalse);
      expect(macInputChannelOptions(8).contains(saved), isTrue);
    },
  );
  test(
    'device identity and System Default resolve independently of output',
    () {
      final a = device('a', 8, isDefault: true);
      final b = device('b', 1);
      expect(resolveMacInputDevice([a, b], 'b'), b);
      expect(resolveMacInputDevice([a, b], null), a);
      expect(resolveMacInputDevice([b], 'a'), isNull);
      expect(resolveMacInputDevice([a, b], 'a'), a);
      expect(
        resolveMacInputDevice([a, device('b', 1, isDefault: true)], null),
        isNull,
      );
    },
  );
  test('channel names are optional and labels retain physical numbering', () {
    expect(const MacInputChannelOption(0, 1).label([]), 'Input 1');
    expect(
      const MacInputChannelOption(0, 2).label(['Mic', 'Line']),
      'Inputs 1–2 — Mic / Line',
    );
    expect(const MacInputChannelOption(2, 1).label(['Mic']), 'Input 3');
    final info = AudioInputDeviceInfo.fromMap({
      'name': 'Interface',
      'channelCount': 3,
      'channelNames': [' Mic ', null, ''],
    });
    expect(info.channelNames, [' Mic ', '', '']);
    expect(
      AudioInputDeviceInfo.fromMap({'name': 'Legacy'}).channelNames,
      isEmpty,
    );
  });
}
