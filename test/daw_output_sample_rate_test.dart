import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:mixroom/helpers/daw_output_sample_rate.dart';

AudioRouteSnapshotV2 snapshot({
  double? native = 48000,
  double? device = 48000,
  double? graph = 48000,
  bool open = true,
  bool attached = true,
  int outputs = 2,
  int callbacks = 1,
  int endpoints = 1,
  String consistency = 'stable',
  bool? changeable,
  List<Map<String, Object>> ranges = const [],
}) => AudioRouteSnapshotV2.fromMap({
  'captureConsistency': consistency,
  'outputs': [
    for (var i = 0; i < endpoints; i++)
      {
        'direction': 'output',
        'uid': 'interface-$i',
        'sampleRateChangeable': changeable,
        'sampleRateRanges': ranges,
      },
  ],
  'session': {'sampleRateHz': native},
  'juce': {
    'deviceOpen': open,
    'audioCallbackAttached': attached,
    'activeOutputChannels': outputs,
    'realtimeCallbackCount': callbacks,
    'sampleRateHz': device,
    'projectGraphSampleRateHz': graph,
  },
});

void main() {
  test('publishes the admitted output clock', () {
    expect(verifiedDawOutputSampleRate(snapshot()), 48000);
  });
  test('follows rate changes and rates outside the editable presets', () {
    for (final rate in [44100.0, 48000.0, 96000.0, 192000.0]) {
      expect(
        verifiedDawOutputSampleRate(
          snapshot(native: rate, device: rate, graph: rate),
        ),
        rate.round(),
      );
    }
  });
  test('does not publish a stable but mismatched hardware or graph clock', () {
    expect(verifiedDawOutputSampleRate(snapshot(device: 44100)), isNull);
    expect(verifiedDawOutputSampleRate(snapshot(graph: 44100)), isNull);
  });
  test('does not publish closed, detached or transitioning outputs', () {
    for (final state in [
      snapshot(open: false),
      snapshot(attached: false),
      snapshot(outputs: 0),
      snapshot(callbacks: 0),
      snapshot(endpoints: 0),
      snapshot(endpoints: 2),
      snapshot(consistency: 'unavailable'),
      snapshot(consistency: 'routeChangedDuringCapture'),
    ]) {
      expect(verifiedDawOutputSampleRate(state), isNull);
    }
  });
  test('missing and non-finite clocks do not fall back to 44.1 kHz', () {
    for (final rate in [null, 0.0, -48000.0, double.nan, double.infinity]) {
      expect(verifiedDawOutputSampleRate(snapshot(native: rate)), isNull);
      expect(verifiedDawOutputSampleRate(snapshot(device: rate)), isNull);
      expect(verifiedDawOutputSampleRate(snapshot(graph: rate)), isNull);
    }
  });
  test('labels preserve the full detected rate', () {
    expect(formatDawSampleRate(44100), '44.1 kHz');
    expect(formatDawSampleRate(48000), '48 kHz');
    expect(formatDawSampleRate(11025), '11.025 kHz');
  });

  group('selectable output rates', () {
    const presets = [44100, 48000, 88200, 96000];
    Map<String, Object> range(double min, double max) => {
      'minimumHz': min,
      'maximumHz': max,
    };
    List<int> options(AudioRouteSnapshotV2 value) =>
        selectableDawOutputSampleRates(value, commonRates: presets);

    test(
      'uses device rates and includes discrete rates beyond old presets',
      () {
        expect(
          options(
            snapshot(
              changeable: true,
              ranges: [range(48000, 48000), range(192000, 192000)],
            ),
          ),
          [48000, 192000],
        );
      },
    );
    test(
      'read-only, missing capabilities, and a single current rate have no menu',
      () {
        expect(
          options(snapshot(changeable: false, ranges: [range(16000, 48000)])),
          isEmpty,
        );
        expect(options(snapshot()), isEmpty);
        expect(options(snapshot(changeable: true)), isEmpty);
        expect(
          options(snapshot(changeable: true, ranges: [range(48000, 48000)])),
          isEmpty,
        );
      },
    );
    test('continuous ranges offer only valid bounded choices', () {
      expect(
        options(snapshot(changeable: true, ranges: [range(32000, 50000)])),
        [32000, 44100, 48000, 50000],
      );
    });
    test('does not offer stale current rates outside the reported ranges', () {
      expect(
        options(snapshot(changeable: true, ranges: [range(96000, 96000)])),
        [96000],
      );
    });
    test('rejects malformed ranges and deduplicates valid ranges', () {
      expect(
        options(
          snapshot(
            changeable: true,
            ranges: [
              range(double.nan, 48000),
              range(48000, double.infinity),
              range(-1, 96000),
              range(96000, 44100),
              range(44100, 44100),
              range(44100, 44100),
              range(48000, 48000),
            ],
          ),
        ),
        [44100, 48000],
      );
    });
    test('unverified routes do not expose manual controls', () {
      expect(
        options(
          snapshot(
            open: false,
            changeable: true,
            ranges: [range(44100, 96000)],
          ),
        ),
        isEmpty,
      );
    });
    test('capability metadata survives the snapshot wire round trip', () {
      final original = snapshot(
        changeable: true,
        ranges: [range(44100, 96000)],
      );
      final copy = AudioRouteSnapshotV2.fromMap(original.toRawMap());
      expect(copy.outputs.single.sampleRateChangeable, isTrue);
      expect(options(copy), options(original));
    });
  });
}
