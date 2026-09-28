import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/project_state_builder.dart';
import 'package:mixroom/models/models.dart';

void main() {
  test('project-state build metrics are zero-safe and privacy-safe', () {
    final metrics = ProjectStateBuildMetrics();
    final observability = metrics.toObservability(totalMs: 7);

    expect(observability['project_stats_ms'], 7);
    expect(observability['project_clip_count'], 0);
    expect(observability['project_analysis_cache_hit_count'], 0);
    expect(observability['project_audio_decode_call_count'], 0);
    expect(
      observability.keys.every((key) => key.startsWith('project_')),
      isTrue,
    );
  });

  test('project-state build metrics count distinct analysis work', () async {
    final first = await _track('/tmp/private/source.wav');
    final repeated = await _track('/tmp/private/source.wav');
    final trimmed = await _track(
      '/tmp/private/source.wav',
      trimStart: const Duration(milliseconds: 250),
    );
    final midi = await _track('/tmp/private/midi.wav', clipKind: ClipKind.midi);
    final metrics = ProjectStateBuildMetrics()
      ..recordInventory(<AudioTrack>[first, repeated, trimmed, midi])
      ..recordCacheLookup(elapsedMs: 2, hit: true)
      ..recordCacheLookup(elapsedMs: 3, hit: false)
      ..recordDecode(elapsedMs: 4, failed: false)
      ..recordDecode(elapsedMs: 5, failed: true)
      ..recordClassification(elapsedMs: 6, failed: false)
      ..recordStereoAnalysis(elapsedMs: 7, failed: true)
      ..recordCombinedNativeAnalysis(elapsedMs: 8, failed: true)
      ..recordCombinedNativeFallback(elapsedMs: 9);

    final observability = metrics.toObservability(totalMs: 40);
    expect(observability['project_clip_count'], 4);
    expect(observability['project_audio_clip_count'], 3);
    expect(observability['project_midi_clip_count'], 1);
    expect(observability['project_unique_source_path_count'], 2);
    expect(observability['project_unique_analysis_key_count'], 3);
    expect(observability['project_analysis_cache_hit_count'], 1);
    expect(observability['project_analysis_cache_miss_count'], 1);
    expect(observability['project_audio_decode_call_count'], 2);
    expect(observability['project_audio_decode_failure_count'], 1);
    expect(observability['project_role_classification_call_count'], 1);
    expect(observability['project_stereo_analysis_failure_count'], 1);
    expect(observability['project_combined_native_analysis_ms'], 8);
    expect(observability['project_combined_native_analysis_call_count'], 1);
    expect(observability['project_combined_native_analysis_failure_count'], 1);
    expect(observability['project_combined_native_analysis_fallback_ms'], 9);
    expect(observability['project_combined_native_analysis_fallback_count'], 1);
    expect(observability['project_mobile_native_analysis_ms'], 8);
    expect(observability['project_mobile_native_analysis_failure_count'], 1);
    expect(observability.toString(), isNot(contains('/tmp/private')));
  });
}

Future<AudioTrack> _track(
  String path, {
  Duration trimStart = Duration.zero,
  ClipKind clipKind = ClipKind.audio,
}) => AudioTrack.create(
  file: File(path),
  originalFile: File(path),
  audioDuration: const Duration(seconds: 4),
  trimStart: trimStart,
  trimEnd: const Duration(seconds: 4),
  offset: 0,
  rowIndex: 0,
  rowId: 1,
  label: 'Fixture',
  clipKind: clipKind,
  instrumentId: clipKind == ClipKind.midi ? 'mixroom.sub_bass' : '',
  instrumentName: clipKind == ClipKind.midi ? 'Sub Bass' : '',
);
