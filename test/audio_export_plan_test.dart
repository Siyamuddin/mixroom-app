import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/audio_export_plan.dart';

void main() {
  group('AudioExportPlan sample rates', () {
    test('exposes format-specific UI sample rates', () {
      expect(AudioExportPlan.uiSampleRatesForFormat('wav'), [
        44100,
        48000,
        88200,
        96000,
      ]);
      expect(AudioExportPlan.uiSampleRatesForFormat('mp3'), [44100, 48000]);
    });

    test(
        'normalizes unsupported MP3 sample rates to nearest valid encoder rate',
        () {
      expect(
        AudioExportPlan.normalizeSampleRate(format: 'mp3', sampleRate: 88200),
        48000,
      );
      expect(
        AudioExportPlan.normalizeSampleRate(format: 'mp3', sampleRate: 96000),
        48000,
      );
      expect(
        AudioExportPlan.normalizeSampleRate(format: 'wav', sampleRate: 96000),
        96000,
      );
    });
  });

  group('AudioExportPlan.buildExportFilter', () {
    test('builds WAV filter with mono downmix, resampling, and normalization',
        () {
      final filter = AudioExportPlan.buildExportFilter(
        format: 'wav',
        sampleRate: 48000,
        wavDithering: true,
        channelMode: 'mono',
        normalize: true,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      expect(
        filter,
        'aresample=48000:resampler=soxr:precision=28:dither_method=triangular,'
        'pan=mono|c0=0.5*c0+0.5*c1,'
        'loudnorm=I=-14:LRA=11:TP=-1.0:linear=true',
      );
    });

    test('does not add WAV dithering to MP3 resampling filter', () {
      final filter = AudioExportPlan.buildExportFilter(
        format: 'mp3',
        sampleRate: 44100,
        wavDithering: true,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -0.3,
        resampleQuality: 'good',
      );

      expect(
        filter,
        'aresample=44100:resampler=soxr:precision=20,'
        'aformat=channel_layouts=stereo',
      );
      expect(filter.contains('dither_method'), isFalse);
    });
  });

  group('AudioExportPlan.buildFfmpegArgs', () {
    test('builds WAV command with bit depth codec and channel count', () {
      final args = AudioExportPlan.buildFfmpegArgs(
        inputPath: '/tmp/in.wav',
        outputPath: '/tmp/out.wav',
        format: 'wav',
        sampleRate: 96000,
        wavBitDepth: 24,
        wavDithering: false,
        mp3BitrateKbps: 192,
        mp3Mode: 'cbr',
        mp3VbrQuality: 2,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'draft',
      );

      expect(
        args,
        [
          '-i',
          '"/tmp/in.wav"',
          '-af',
          'aresample=96000:resampler=swr:dither_method=none,aformat=channel_layouts=stereo',
          '-c:a',
          'pcm_s24le',
          '-ac',
          '2',
          '-ar',
          '96000',
          '-y',
          '"/tmp/out.wav"',
        ],
      );
    });

    test('builds MP3 CBR command with bitrate', () {
      final args = AudioExportPlan.buildFfmpegArgs(
        inputPath: '/tmp/in.wav',
        outputPath: '/tmp/out.mp3',
        format: 'mp3',
        sampleRate: 44100,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 320,
        mp3Mode: 'cbr',
        mp3VbrQuality: 0,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      expect(args.contains('libmp3lame'), isTrue);
      expect(args.contains('320k'), isTrue);
      expect(args.contains('-q:a'), isFalse);
    });

    test('normalizes unsupported MP3 sample rates before encoding', () {
      final args = AudioExportPlan.buildFfmpegArgs(
        inputPath: '/tmp/in.wav',
        outputPath: '/tmp/out.mp3',
        format: 'mp3',
        sampleRate: 88200,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 192,
        mp3Mode: 'cbr',
        mp3VbrQuality: 0,
        channelMode: 'stereo',
        normalize: false,
        normalizeTargetDb: -1.0,
        resampleQuality: 'best',
      );

      expect(args.contains('88200'), isFalse);
      expect(args.contains('48000'), isTrue);
    });

    test('builds MP3 VBR command with quality scale', () {
      final args = AudioExportPlan.buildFfmpegArgs(
        inputPath: '/tmp/in.wav',
        outputPath: '/tmp/out.mp3',
        format: 'mp3',
        sampleRate: 44100,
        wavBitDepth: 16,
        wavDithering: true,
        mp3BitrateKbps: 192,
        mp3Mode: 'vbr',
        mp3VbrQuality: 4,
        channelMode: 'mono',
        normalize: true,
        normalizeTargetDb: -0.3,
        resampleQuality: 'good',
      );

      expect(args.contains('-q:a'), isTrue);
      expect(args.contains('4'), isTrue);
      expect(args.contains('-b:a'), isFalse);
      expect(args.contains('1'), isTrue);
    });
  });

  group('AudioExportPlan.canUseNativeWavExport', () {
    test(
        'only allows native direct export for stereo WAV without normalization',
        () {
      expect(
        AudioExportPlan.canUseNativeWavExport(
          format: 'wav',
          channelMode: 'stereo',
          normalize: false,
        ),
        isTrue,
      );
      expect(
        AudioExportPlan.canUseNativeWavExport(
          format: 'mp3',
          channelMode: 'stereo',
          normalize: false,
        ),
        isFalse,
      );
      expect(
        AudioExportPlan.canUseNativeWavExport(
          format: 'wav',
          channelMode: 'mono',
          normalize: false,
        ),
        isFalse,
      );
      expect(
        AudioExportPlan.canUseNativeWavExport(
          format: 'wav',
          channelMode: 'stereo',
          normalize: true,
        ),
        isFalse,
      );
    });
  });

  test('option matrix yields coherent ffmpeg arguments', () {
    const formats = ['wav', 'mp3'];
    const channelModes = ['stereo', 'mono'];
    const resampleQualities = ['draft', 'good', 'best'];
    const mp3Modes = ['cbr', 'vbr'];
    const bitDepths = [16, 24, 32];

    for (final format in formats) {
      for (final channelMode in channelModes) {
        for (final resampleQuality in resampleQualities) {
          for (final mp3Mode in mp3Modes) {
            for (final bitDepth in bitDepths) {
              final args = AudioExportPlan.buildFfmpegArgs(
                inputPath: '/tmp/source.wav',
                outputPath: '/tmp/out.${format == 'wav' ? 'wav' : 'mp3'}',
                format: format,
                sampleRate: 48000,
                wavBitDepth: bitDepth,
                wavDithering: true,
                mp3BitrateKbps: 192,
                mp3Mode: mp3Mode,
                mp3VbrQuality: 2,
                channelMode: channelMode,
                normalize: true,
                normalizeTargetDb: -1.0,
                resampleQuality: resampleQuality,
              );

              expect(args.first, '-i');
              expect(args.contains('-af'), isTrue);
              expect(args.contains('-ac'), isTrue);
              expect(args.contains(channelMode == 'mono' ? '1' : '2'), isTrue);
              expect(args.contains('-ar'), isTrue);
              expect(args.contains('48000'), isTrue);

              if (format == 'wav') {
                expect(args.contains('libmp3lame'), isFalse);
                expect(
                  args.contains(AudioExportPlan.wavCodecForBitDepth(bitDepth)),
                  isTrue,
                );
              } else {
                expect(args.contains('libmp3lame'), isTrue);
                expect(args.contains('pcm_s16le'), isFalse);
                expect(args.contains('pcm_s24le'), isFalse);
                expect(args.contains('pcm_f32le'), isFalse);
                expect(
                    args.contains(mp3Mode == 'cbr' ? '-b:a' : '-q:a'), isTrue);
              }
            }
          }
        }
      }
    }
  });
}
