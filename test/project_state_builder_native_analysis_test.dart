import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/ai_file_metadata.dart';
import 'package:mixroom/ai/instrument_classifier.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/models.dart';
import 'package:mixroom/models/project_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juce_audio_engine');
  final nativeCalls = <MethodCall>[];

  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          switch (call.method) {
            case 'getTrackEffectsForRow':
            case 'getTrackEffectIdsForRow':
            case 'getTrackEffectInstanceIdsForRow':
            case 'getTrackPluginParameters':
            case 'getMasterEffects':
            case 'getMasterEffectIds':
            case 'getMasterEffectInstanceIds':
              return <dynamic>[];
            case 'decodeAudioMono16k':
            case 'decodeAudioMono16kForAnalysis':
              return <double>[];
            case 'analyzeAudioStereo16k':
              return <String, double>{
                'phase_corr': 1,
                'side_ratio': 0,
                'stereo_imbalance': 0,
              };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'macOS uses validated combined analysis once per analysis key',
    () async {
      var combinedCalls = 0;
      final builder = ProjectStateBuilder(
        classifier: InstrumentClassifier(enabled: false),
        maxRows: 1,
        targetPlatformOverride: TargetPlatform.macOS,
        combinedPromptAnalysisProvider:
            (path, {trimStartMs = 0, trimEndMs}) async {
              combinedCalls++;
              return _validNativeAnalysis();
            },
      );
      final first = await _track('/tmp/private/combined.wav');
      final repeated = await _track('/tmp/private/combined.wav');
      final trimmed = await _track(
        '/tmp/private/combined.wav',
        trimStart: const Duration(milliseconds: 250),
      );
      final metrics = ProjectStateBuildMetrics();

      final state = await _build(
        builder,
        <AudioTrack>[first, repeated, trimmed],
        _metadata(<AudioTrack>[first, repeated, trimmed]),
        metrics,
      );

      expect(combinedCalls, 2);
      expect(
        nativeCalls.where(
          (call) => call.method.startsWith('decodeAudioMono16k'),
        ),
        isEmpty,
      );
      expect(
        nativeCalls.where((call) => call.method == 'analyzeAudioStereo16k'),
        isEmpty,
      );
      expect(state.rows.single.roleProbs.values.reduce((a, b) => a + b), 1);
      expect(state.estimatedKey, 'C major');
      final observed = metrics.toObservability(totalMs: 0);
      expect(observed['project_combined_native_analysis_call_count'], 2);
      expect(observed['project_combined_native_analysis_failure_count'], 0);
      expect(observed['project_combined_native_analysis_fallback_count'], 0);

      await _build(
        builder,
        <AudioTrack>[first, repeated, trimmed],
        _metadata(<AudioTrack>[first, repeated, trimmed]),
        ProjectStateBuildMetrics(),
      );
      expect(combinedCalls, 2, reason: 'warm build must use the LRU cache');
    },
  );

  test('macOS unavailable source skips all native analysis', () async {
    var combinedCalls = 0;
    final track = await _track('/tmp/private/missing.wav');
    final builder = ProjectStateBuilder(
      classifier: InstrumentClassifier(enabled: false),
      maxRows: 1,
      targetPlatformOverride: TargetPlatform.macOS,
      combinedPromptAnalysisProvider:
          (path, {trimStartMs = 0, trimEndMs}) async {
            combinedCalls++;
            return _validNativeAnalysis();
          },
    );

    final state = await _build(
      builder,
      <AudioTrack>[track],
      _metadata(<AudioTrack>[track], available: false),
      ProjectStateBuildMetrics(),
    );

    expect(combinedCalls, 0);
    expect(
      nativeCalls.where(
        (call) =>
            call.method.startsWith('decodeAudioMono16k') ||
            call.method == 'analyzeAudioStereo16k',
      ),
      isEmpty,
    );
    expect(state.rows.single.audioStats['true_peak_dbfs'], -120);
    expect(state.rows.single.roleProbs['vocals'], closeTo(0.17, 1e-12));
  });

  test(
    'macOS malformed combined result falls back to desktop analysis',
    () async {
      final track = await _track('/tmp/private/malformed.wav');
      final metrics = ProjectStateBuildMetrics();
      final builder = ProjectStateBuilder(
        classifier: InstrumentClassifier(enabled: false),
        maxRows: 1,
        targetPlatformOverride: TargetPlatform.macOS,
        combinedPromptAnalysisProvider:
            (path, {trimStartMs = 0, trimEndMs}) async => <String, dynamic>{
              'roleProbs': <String, double>{'vocals': double.nan},
              'audioStats': const <String, double>{},
            },
      );

      final state = await _build(
        builder,
        <AudioTrack>[track],
        _metadata(<AudioTrack>[track]),
        metrics,
      );

      expect(
        nativeCalls.where(
          (call) => call.method.startsWith('decodeAudioMono16k'),
        ),
        hasLength(1),
      );
      expect(
        nativeCalls.where((call) => call.method == 'analyzeAudioStereo16k'),
        hasLength(1),
      );
      expect(state.rows.single.roleProbs['vocals'], closeTo(0.17, 1e-12));
      final observed = metrics.toObservability(totalMs: 0);
      expect(observed['project_combined_native_analysis_failure_count'], 1);
      expect(observed['project_combined_native_analysis_fallback_count'], 1);
      expect(observed['project_audio_decode_call_count'], 1);
      expect(observed['project_stereo_analysis_call_count'], 1);
    },
  );

  test('macOS caught native failure falls back to desktop analysis', () async {
    final track = await _track('/tmp/private/throwing.wav');
    final metrics = ProjectStateBuildMetrics();
    final builder = ProjectStateBuilder(
      classifier: InstrumentClassifier(enabled: false),
      maxRows: 1,
      targetPlatformOverride: TargetPlatform.macOS,
      combinedPromptAnalysisProvider: (
        path, {
        trimStartMs = 0,
        trimEndMs,
      }) async => throw PlatformException(code: 'native_analysis_failed'),
    );

    final state = await _build(
      builder,
      <AudioTrack>[track],
      _metadata(<AudioTrack>[track]),
      metrics,
    );

    expect(
      nativeCalls.where((call) => call.method.startsWith('decodeAudioMono16k')),
      hasLength(1),
    );
    expect(
      nativeCalls.where((call) => call.method == 'analyzeAudioStereo16k'),
      hasLength(1),
    );
    expect(state.rows.single.roleProbs['vocals'], closeTo(0.17, 1e-12));
    final observed = metrics.toObservability(totalMs: 0);
    expect(observed['project_combined_native_analysis_failure_count'], 1);
    expect(observed['project_combined_native_analysis_fallback_count'], 1);
  });

  test('Windows retains the legacy desktop path', () async {
    var combinedCalls = 0;
    final track = await _track('/tmp/private/windows.wav');
    final builder = ProjectStateBuilder(
      classifier: InstrumentClassifier(enabled: false),
      maxRows: 1,
      targetPlatformOverride: TargetPlatform.windows,
      combinedPromptAnalysisProvider:
          (path, {trimStartMs = 0, trimEndMs}) async {
            combinedCalls++;
            return _validNativeAnalysis();
          },
    );

    await _build(
      builder,
      <AudioTrack>[track],
      _metadata(<AudioTrack>[track]),
      ProjectStateBuildMetrics(),
    );

    expect(combinedCalls, 0);
    expect(
      nativeCalls.where((call) => call.method.startsWith('decodeAudioMono16k')),
      hasLength(1),
    );
  });
}

Future<ProjectState> _build(
  ProjectStateBuilder builder,
  List<AudioTrack> tracks,
  AiFileMetadataResolution metadata,
  ProjectStateBuildMetrics metrics,
) => builder.build(
  audioTracks: tracks,
  bpmFallback: 120,
  rowGain: const <double>[1],
  rowPan: const <double>[0.5],
  rowAutomation: const <List<AutomationPoint>>[<AutomationPoint>[]],
  timelineRows: <TimelineRow>[TimelineRow(rowId: 1, name: 'Audio', iconId: 0)],
  fileMetadata: metadata,
  buildMetrics: metrics,
);

Future<AudioTrack> _track(String path, {Duration trimStart = Duration.zero}) =>
    AudioTrack.create(
      file: File(path),
      originalFile: File(path),
      audioDuration: const Duration(seconds: 4),
      trimStart: trimStart,
      trimEnd: const Duration(seconds: 4),
      offset: 0,
      rowIndex: 0,
      rowId: 1,
      label: 'Fixture',
    );

AiFileMetadataResolution _metadata(
  Iterable<AudioTrack> tracks, {
  bool available = true,
}) {
  final byPath = <String, AiFileMetadata>{};
  for (final track in tracks) {
    final normalized = normalizeAiFilePath(track.file.path);
    byPath[normalized] = AiFileMetadata(
      normalizedPath: normalized,
      available: available,
      sizeBytes: available ? 4096 : 0,
      modifiedMilliseconds: available ? 118 : 0,
    );
  }
  return AiFileMetadataResolution(
    byNormalizedPath: byPath,
    elapsedMilliseconds: 0,
  );
}

Map<String, dynamic> _validNativeAnalysis() => <String, dynamic>{
  'roleProbs': <String, double>{
    'vocals': 0.5,
    'guitar': 0.1,
    'bass': 0.1,
    'drums': 0.1,
    'synth': 0.1,
    'other': 0.1,
  },
  'audioStats': <String, double>{
    'centroid_hz': 1000,
    'zcr': 0.1,
    'hf_rms': 0.1,
    'st_rms_mean': 0.1,
    'st_rms_p95': 0.2,
    'st_rms_std': 0.01,
    'transient_density': 0.1,
    'true_peak_dbfs': -3,
    'integrated_lufs_est': -16,
    'short_lufs_mean': -16,
    'short_lufs_p95': -12,
    'lra_est': 4,
    'clip_ratio': 0,
    'spectral_flatness': 0.2,
    'spectral_rolloff_hz': 4000,
    'spectral_slope': 0,
    'spectral_flux': 0.1,
    'spectral_bandwidth_hz': 2000,
    'silence_ratio': 0.1,
    'activity_ratio': 0.9,
    'onset_rate_hz': 2,
    'noise_floor_dbfs': -60,
    'phase_corr': 0.9,
    'side_ratio': 0.1,
    'stereo_imbalance': 0.05,
    'low': 0.1,
    'lowmid': 0.1,
    'mid': 0.1,
    'high': 0.1,
    'sibilance': 0.2,
    'bassiness': 0.2,
    for (var index = 0; index < 12; index++)
      'key_pc_$index': index == 0 ? 1 : 0,
  },
};
