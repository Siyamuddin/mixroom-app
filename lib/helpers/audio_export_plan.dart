class AudioExportPlan {
  const AudioExportPlan._();

  static const List<int> _wavUiSampleRates = [44100, 48000];
  static const List<int> _mp3UiSampleRates = [44100, 48000];
  static const List<int> _flacUiSampleRates = [44100, 48000];
  static const List<int> _mp3SupportedSampleRates = [
    8000,
    11025,
    12000,
    16000,
    22050,
    24000,
    32000,
    44100,
    48000,
  ];

  static List<int> uiSampleRatesForFormat(String format) {
    if (format == 'mp3') return _mp3UiSampleRates;
    if (format == 'flac') return _flacUiSampleRates;
    return _wavUiSampleRates;
  }

  static int normalizeSampleRate({
    required String format,
    required int sampleRate,
  }) {
    if (format != 'mp3') return sampleRate;
    if (_mp3SupportedSampleRates.contains(sampleRate)) return sampleRate;

    var best = _mp3SupportedSampleRates.first;
    var bestDistance = (sampleRate - best).abs();
    for (final candidate in _mp3SupportedSampleRates.skip(1)) {
      final distance = (sampleRate - candidate).abs();
      if (distance < bestDistance ||
          (distance == bestDistance && candidate > best)) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  static String wavCodecForBitDepth(int bitDepth) {
    switch (bitDepth) {
      case 24:
        return 'pcm_s24le';
      case 32:
        return 'pcm_f32le';
      case 16:
      default:
        return 'pcm_s16le';
    }
  }

  static String buildResampleFilter({
    required String format,
    required int sampleRate,
    required bool wavDithering,
    required String resampleQuality,
  }) {
    final effectiveSampleRate = normalizeSampleRate(
      format: format,
      sampleRate: sampleRate,
    );
    final isWav = format == 'wav';
    final ditherMethod = wavDithering ? 'triangular' : 'none';
    switch (resampleQuality) {
      case 'draft':
        return isWav
            ? 'aresample=$effectiveSampleRate:resampler=swr:dither_method=$ditherMethod'
            : 'aresample=$effectiveSampleRate:resampler=swr';
      case 'good':
        return isWav
            ? 'aresample=$effectiveSampleRate:resampler=soxr:precision=20:dither_method=$ditherMethod'
            : 'aresample=$effectiveSampleRate:resampler=soxr:precision=20';
      case 'best':
      default:
        return isWav
            ? 'aresample=$effectiveSampleRate:resampler=soxr:precision=28:dither_method=$ditherMethod'
            : 'aresample=$effectiveSampleRate:resampler=soxr:precision=28';
    }
  }

  static String buildExportFilter({
    required String format,
    required int sampleRate,
    required bool wavDithering,
    required String channelMode,
    required bool normalize,
    required double normalizeTargetDb,
    required String resampleQuality,
  }) {
    final filters = <String>[
      buildResampleFilter(
        format: format,
        sampleRate: sampleRate,
        wavDithering: wavDithering,
        resampleQuality: resampleQuality,
      ),
      channelMode == 'mono'
          ? 'pan=mono|c0=0.5*c0+0.5*c1'
          : 'aformat=channel_layouts=stereo',
    ];

    if (normalize) {
      filters.add(
        'loudnorm=I=-14:LRA=11:TP=${normalizeTargetDb.toStringAsFixed(1)}:linear=true',
      );
    }

    return filters.join(',');
  }

  static List<String> buildFfmpegArgs({
    required String inputPath,
    required String outputPath,
    required String format,
    required int sampleRate,
    required int wavBitDepth,
    required bool wavDithering,
    required int mp3BitrateKbps,
    required String mp3Mode,
    required int mp3VbrQuality,
    required String channelMode,
    required bool normalize,
    required double normalizeTargetDb,
    required String resampleQuality,
  }) {
    final effectiveSampleRate = normalizeSampleRate(
      format: format,
      sampleRate: sampleRate,
    );
    final filter = buildExportFilter(
      format: format,
      sampleRate: effectiveSampleRate,
      wavDithering: wavDithering,
      channelMode: channelMode,
      normalize: normalize,
      normalizeTargetDb: normalizeTargetDb,
      resampleQuality: resampleQuality,
    );
    final channelCount = channelMode == 'mono' ? '1' : '2';

    if (format == 'wav') {
      return [
        '-i',
        '"$inputPath"',
        if (filter.isNotEmpty) ...['-af', filter],
        '-c:a',
        wavCodecForBitDepth(wavBitDepth),
        '-ac',
        channelCount,
        '-ar',
        '$effectiveSampleRate',
        '-y',
        '"$outputPath"',
      ];
    }

    if (format == 'flac') {
      return [
        '-i',
        '"$inputPath"',
        if (filter.isNotEmpty) ...['-af', filter],
        '-c:a',
        'flac',
        '-compression_level',
        '8',
        '-sample_fmt',
        wavBitDepth >= 24 ? 's32' : 's16',
        '-ac',
        channelCount,
        '-ar',
        '$effectiveSampleRate',
        '-y',
        '"$outputPath"',
      ];
    }

    return [
      '-i',
      '"$inputPath"',
      if (filter.isNotEmpty) ...['-af', filter],
      '-c:a',
      'libmp3lame',
      if (mp3Mode == 'cbr') ...[
        '-b:a',
        '${mp3BitrateKbps}k',
      ] else ...[
        '-q:a',
        '$mp3VbrQuality',
      ],
      '-ac',
      channelCount,
      '-ar',
      '$effectiveSampleRate',
      '-y',
      '"$outputPath"',
    ];
  }

  static bool canUseNativeWavExport({
    required String format,
    required String channelMode,
    required bool normalize,
  }) {
    return format == 'wav' && channelMode == 'stereo' && !normalize;
  }
}
