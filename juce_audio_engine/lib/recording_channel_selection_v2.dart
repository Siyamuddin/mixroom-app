class RecordingChannelSelectionV2 {
  const RecordingChannelSelectionV2({
    required this.channelStart,
    required this.channelCount,
  });

  final int channelStart;
  final int channelCount;

  int get requiredInputChannels => channelStart + channelCount;

  bool get isValid =>
      channelStart >= 0 && (channelCount == 1 || channelCount == 2);

  RecordingChannelSelectionV2 normalizeForCapacity(int availableChannels) {
    if (availableChannels <= 1) {
      return const RecordingChannelSelectionV2(
        channelStart: 0,
        channelCount: 1,
      );
    }
    final normalizedStart = channelStart.clamp(0, availableChannels - 1);
    final normalizedCount = channelCount == 2 &&
            normalizedStart + 2 <= availableChannels &&
            normalizedStart.isEven
        ? 2
        : 1;
    return RecordingChannelSelectionV2(
      channelStart: normalizedStart,
      channelCount: normalizedCount,
    );
  }
}
