import 'package:flutter_test/flutter_test.dart';
import 'package:juce_audio_engine/recording_channel_selection_v2.dart';

void main() {
  test('validates mono and stereo channel selections', () {
    expect(
      const RecordingChannelSelectionV2(channelStart: 2, channelCount: 1)
          .isValid,
      isTrue,
    );
    expect(
      const RecordingChannelSelectionV2(channelStart: 0, channelCount: 2)
          .requiredInputChannels,
      2,
    );
    expect(
      const RecordingChannelSelectionV2(channelStart: -1, channelCount: 1)
          .isValid,
      isFalse,
    );
    expect(
      const RecordingChannelSelectionV2(channelStart: 0, channelCount: 3)
          .isValid,
      isFalse,
    );
  });

  test('normalizes single-channel routes to first-channel mono', () {
    final normalized = const RecordingChannelSelectionV2(
      channelStart: 4,
      channelCount: 2,
    ).normalizeForCapacity(1);
    expect(normalized.channelStart, 0);
    expect(normalized.channelCount, 1);
  });

  test('preserves valid later mono and adjacent stereo selections', () {
    final mono = const RecordingChannelSelectionV2(
      channelStart: 3,
      channelCount: 1,
    ).normalizeForCapacity(4);
    final stereo = const RecordingChannelSelectionV2(
      channelStart: 2,
      channelCount: 2,
    ).normalizeForCapacity(4);
    expect((mono.channelStart, mono.channelCount), (3, 1));
    expect((stereo.channelStart, stereo.channelCount), (2, 2));
  });

  test('falls back to mono when a saved stereo pair no longer fits', () {
    final normalized = const RecordingChannelSelectionV2(
      channelStart: 2,
      channelCount: 2,
    ).normalizeForCapacity(3);
    expect((normalized.channelStart, normalized.channelCount), (2, 1));
  });
}
