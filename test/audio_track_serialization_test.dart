import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/models/models.dart';

void main() {
  test('MIDI save preserves a 32-beat boundary at 84 BPM', () async {
    final end = Duration(microseconds: (32 * 60000000 / 84).round());
    final track = await AudioTrack.create(
      file: File('/tmp/precision.mid'), originalFile: File('/tmp/precision.mid'),
      audioDuration: end, trimStart: Duration.zero, trimEnd: end,
      offset: 0, rowIndex: 0, label: 'Precision', clipKind: ClipKind.midi,
    );
    final saved = track.toJson('precision.mid');
    expect(saved['trimEndMs'], 22857.143);
    expect(clipTrimFromMilliseconds(saved['trimEndMs'] as num, isMidi: true), end);
    // The existing numeric fields remain readable by old rounded-ms clients.
    expect((saved['trimEndMs'] as num).round(), 22857);
  });

  test('MIDI trim round trips retain fractional endpoints without snapping', () {
    for (final us in <int>[0, 123456, 17777778, 22857143, 12345001]) {
      final duration = Duration(microseconds: us);
      var value = clipTrimMilliseconds(duration, isMidi: true);
      for (var cycle = 0; cycle < 5; cycle++) {
        final restored = clipTrimFromMilliseconds(value, isMidi: true);
        expect(restored, duration);
        value = clipTrimMilliseconds(restored, isMidi: true);
      }
      expect(clipTrimMilliseconds(duration, isMidi: false), us ~/ 1000);
    }
    // Old whole-ms data is not guessed back to a musical grid.
    expect(clipTrimFromMilliseconds(17777, isMidi: true),
        const Duration(milliseconds: 17777));
    expect(clipTrimFromMilliseconds(17777.8, isMidi: false),
        const Duration(milliseconds: 17778));
    expect(clipTrimMilliseconds(const Duration(seconds: 4), isMidi: true), isA<int>());
  });

  test('AudioTrack JSON preserves clip-level processing state', () async {
    final track = await AudioTrack.create(
      file: File('audio/kick.wav'),
      originalFile: File('audio/kick.wav'),
      audioDuration: const Duration(milliseconds: 2400),
      trimStart: const Duration(milliseconds: 120),
      trimEnd: const Duration(milliseconds: 1800),
      offset: 1.25,
      crossfade: 0.4,
      gain: 1.35,
      normalizeVolume: true,
      normalizeGain: 2.25,
      preNormalizeGain: 1.1,
      pitchSemitones: -2.0,
      isReversed: true,
      sourceTempoBpm: 126.0,
      stretchToProjectTempo: true,
      tempoStretchPreservePitch: true,
      tempoWarpMode: kTempoWarpModeBeats,
      recordingLatencyMs: 18.0,
      alignmentOffsetMs: -7.5,
      audioEnhancementPreset: 'voice_cleanup',
      rowIndex: 2,
      rowId: 42,
      clipId: 'clip_1',
      label: 'Kick',
    );

    final json = track.toJson('kick.wav');

    expect(json['normalizeVolume'], isTrue);
    expect(json['normalizeGain'], 2.25);
    expect(json['preNormalizeGain'], 1.1);
    expect(json['tempoWarpMode'], kTempoWarpModeBeats);
    expect(json['recordingLatencyMs'], 18.0);
    expect(json['alignmentOffsetMs'], -7.5);
    expect(json['audioEnhancementPreset'], 'voice_cleanup');
  });

  test('AudioTrack JSON preserves external MIDI instrument state', () async {
    final track = await AudioTrack.create(
      file: File('audio/vital_render.wav'),
      originalFile: File('audio/vital_render.wav'),
      audioDuration: const Duration(milliseconds: 4800),
      trimStart: Duration.zero,
      trimEnd: const Duration(milliseconds: 4800),
      offset: 2.0,
      rowIndex: 1,
      rowId: 77,
      engineClipId: 4,
      clipId: 'clip_vital_1',
      label: 'Vital Lead',
      clipKind: ClipKind.midi,
      instrumentId: 'hosted:vst3:/Library/Audio/Plug-Ins/VST3/Vital.vst3',
      instrumentName: 'Vital',
      instrumentParams: <String, double>{
        'macro_1': 0.42,
        'macro_2': 0.7,
      },
      midiNotes: <MidiNote>[
        MidiNote(
          id: 'note_1',
          pitch: 60,
          startBeat: 0.0,
          lengthBeats: 1.0,
          velocity: 0.9,
        ),
        MidiNote(
          id: 'note_2',
          pitch: 67,
          startBeat: 1.0,
          lengthBeats: 2.0,
          velocity: 0.75,
        ),
      ],
      hostedInstrumentStateBase64: 'dmVyeV9pbXBvcnRhbnRfc3ludGhfc3RhdGU=',
    );

    final json = track.toJson('vital_render.wav');

    expect(json['clipType'], 'midi');
    expect(json['instrumentId'],
        'hosted:vst3:/Library/Audio/Plug-Ins/VST3/Vital.vst3');
    expect(json['instrumentName'], 'Vital');
    expect((json['instrumentParams'] as Map)['macro_1'], 0.42);
    expect((json['midiNotes'] as List), hasLength(2));
    expect(json['hostedInstrumentStateB64'],
        'dmVyeV9pbXBvcnRhbnRfc3ludGhfc3RhdGU=');
  });

  test('AudioTrack JSON preserves exact zero-time built-in ADSR values',
      () async {
    final track = await AudioTrack.create(
      file: File('audio/basic_synth.mid'),
      originalFile: File('audio/basic_synth.mid'),
      audioDuration: const Duration(milliseconds: 2400),
      trimStart: Duration.zero,
      trimEnd: const Duration(milliseconds: 2400),
      offset: 0.0,
      rowIndex: 0,
      rowId: 3,
      clipId: 'clip_basic_synth',
      label: 'Basic Synth',
      clipKind: ClipKind.midi,
      instrumentId: 'mixroom.basic_synth',
      instrumentName: 'Basic Synth',
      instrumentParams: <String, double>{
        'attackMs': 0.0,
        'decayMs': 0.0,
        'sustainLevel': 0.0,
        'releaseMs': 0.0,
      },
    );

    final json = track.toJson('basic_synth.mid');

    expect(json['instrumentParams'], <String, double>{
      'attackMs': 0.0,
      'decayMs': 0.0,
      'sustainLevel': 0.0,
      'releaseMs': 0.0,
    });
  });
}
