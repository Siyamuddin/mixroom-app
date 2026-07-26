import 'dart:io';
import 'dart:typed_data';

import 'package:mixroom/helpers/project_manager.dart';
import 'package:path/path.dart' as p;

class DevelopmentEvalFixture {
  const DevelopmentEvalFixture({
    required this.directory,
    required this.rowCount,
    required this.clipCount,
  });
  final Directory directory;
  final int rowCount;
  final int clipCount;
}

Future<DevelopmentEvalFixture> createDevelopmentEvalFixture(
  String fixtureId,
) async {
  final directory = await ProjectManager.createNewProjectDir(
    name: 'AI Eval $fixtureId',
  );
  final audioDirectory = ProjectManager.audioDir(directory);
  await audioDirectory.create(recursive: true);

  Future<void> audio(
    String name, {
    bool withSignal = false,
    bool rhythmic = false,
    bool withBoundarySilence = false,
    int durationMs = 1200,
  }) async {
    await File(p.join(audioDirectory.path, name)).writeAsBytes(
      rhythmic
          ? _rhythmicWavBytes(durationMs: durationMs)
          : withBoundarySilence
              ? _boundedToneWavBytes(durationMs: durationMs)
              : withSignal
                  ? _toneWavBytes(durationMs: durationMs)
                  : _silentWavBytes(durationMs: durationMs),
      flush: true,
    );
  }

  final rows = <Map<String, dynamic>>[];
  final tracks = <Map<String, dynamic>>[];

  void addRow(
    String name, {
    String kind = 'audio',
    String instrumentId = '',
    String instrumentName = '',
  }) {
    rows.add(<String, dynamic>{
      'rowId': -1,
      'name': name,
      'iconId': kind == 'instrument' ? 1 : 0,
      'kind': kind,
      if (instrumentId.isNotEmpty) 'instrumentId': instrumentId,
      if (instrumentName.isNotEmpty) 'instrumentName': instrumentName,
      if (instrumentId.isNotEmpty) 'instrumentParams': <String, double>{},
      'inputChannelStart': 0,
      'inputChannelCount': 1,
    });
  }

  Future<void> addAudioClip({
    required String id,
    required String label,
    required int row,
    double offset = 0,
    bool withSignal = false,
    double sourceTempoBpm = 120,
    bool stretchToProjectTempo = false,
    bool preservePitch = false,
    String warpMode = 'complex',
    bool rhythmic = false,
    bool withBoundarySilence = false,
    int durationMs = 1200,
  }) async {
    final fileName = '$id.wav';
    await audio(
      fileName,
      withSignal: withSignal,
      rhythmic: rhythmic,
      withBoundarySilence: withBoundarySilence,
      durationMs: durationMs,
    );
    tracks.add(_track(
      clipId: id,
      label: label,
      row: row,
      fileName: fileName,
      offset: offset,
      sourceTempoBpm: sourceTempoBpm,
      stretchToProjectTempo: stretchToProjectTempo,
      preservePitch: preservePitch,
      warpMode: warpMode,
      durationMs: durationMs,
    ));
  }

  Future<void> addBundledAudioClip({
    required String id,
    required String label,
    required int row,
    required String assetPath,
    int durationMs = 1200,
  }) async {
    final extension = p.extension(assetPath);
    final fileName = '$id$extension';
    final source = File(assetPath);
    if (!await source.exists()) {
      throw StateError('Missing bundled audio fixture: $assetPath');
    }
    await source.copy(p.join(audioDirectory.path, fileName));
    tracks.add(_track(
      clipId: id,
      label: label,
      row: row,
      fileName: fileName,
      durationMs: durationMs,
    ));
  }

  void addMidiClip({
    required String id,
    required String label,
    required int row,
    required String instrumentId,
    required String instrumentName,
    required List<Map<String, dynamic>> notes,
    double offset = 0,
    int durationMs = 1200,
  }) {
    tracks.add(_track(
      clipId: id,
      label: label,
      row: row,
      fileName: '$id.midiclip',
      clipType: 'midi',
      offset: offset,
      instrumentId: instrumentId,
      instrumentName: instrumentName,
      notes: notes,
      durationMs: durationMs,
    ));
  }

  switch (fixtureId) {
    case 'empty_one_row':
      addRow('Track 1');
      break;
    case 'mixed_small_selected_row':
      addRow('Lead Vocal');
      addRow('Upright Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      await addAudioClip(id: 'lead_clip', label: 'Lead Vocal', row: 0);
      addMidiClip(
        id: 'lead_piano',
        label: 'Upright Piano',
        row: 1,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'mixed_duplicate_names':
      addRow('Percussion');
      addRow('Percussion');
      await addAudioClip(id: 'perc_a', label: 'Percussion A', row: 0);
      await addAudioClip(id: 'perc_b', label: 'Percussion B', row: 1);
      break;
    case 'audio_small':
      addRow('Guide Vocal');
      addRow('Synth');
      await addAudioClip(id: 'guide_vocal', label: 'Guide Vocal', row: 0);
      await addAudioClip(id: 'synth_audio', label: 'Synth', row: 1);
      break;
    case 'audio_phone_cleanup':
      addRow('Voice');
      addRow('Unrelated');
      await addAudioClip(
        id: 'voice_phrase_a',
        label: 'Voice Phrase A',
        row: 0,
        withSignal: true,
      );
      await addAudioClip(
        id: 'voice_phrase_b',
        label: 'Voice Phrase B',
        row: 0,
        offset: 1.4,
        withSignal: true,
      );
      await addAudioClip(
        id: 'unrelated_audio',
        label: 'Unrelated',
        row: 1,
        withSignal: true,
      );
      break;
    case 'audio_replace_lengths':
      addRow('Target');
      addRow('Short Replacement');
      addRow('Long Replacement');
      await addAudioClip(
        id: 'replace_target',
        label: 'Target',
        row: 0,
        durationMs: 2400,
      );
      await addAudioClip(
        id: 'replace_short',
        label: 'Short Replacement',
        row: 1,
        durationMs: 800,
      );
      await addAudioClip(
        id: 'replace_long',
        label: 'Long Replacement',
        row: 2,
        durationMs: 4000,
      );
      break;
    case 'audio_non_neutral':
      addRow('Guide');
      addRow('Unchanged');
      await addAudioClip(id: 'guide_audio', label: 'Guide', row: 0);
      await addAudioClip(id: 'unchanged_audio', label: 'Unchanged', row: 1);
      break;
    case 'audio_stretched':
      addRow('Stretched Vocal');
      addRow('Unchanged');
      await addAudioClip(
        id: 'stretched_vocal',
        label: 'Stretched Vocal',
        row: 0,
        sourceTempoBpm: 240,
        stretchToProjectTempo: true,
        preservePitch: false,
        warpMode: 'repitch',
      );
      await addAudioClip(id: 'unchanged_audio', label: 'Unchanged', row: 1);
      break;
    case 'audio_reference_valid':
      addRow('Target');
      addRow('Reference');
      await addAudioClip(
        id: 'target_audio',
        label: 'Target',
        row: 0,
        withSignal: true,
      );
      await addAudioClip(
        id: 'reference_audio',
        label: 'Reference',
        row: 1,
        withSignal: true,
      );
      break;
    case 'audio_tempo_rhythmic':
      addRow('Drums');
      addRow('Unchanged');
      await addAudioClip(
        id: 'rhythmic_drums',
        label: 'Rhythmic Drums',
        row: 0,
        rhythmic: true,
        durationMs: 8000,
      );
      await addAudioClip(
        id: 'unchanged_audio',
        label: 'Unchanged',
        row: 1,
      );
      break;
    case 'audio_tempo_duplicate_names':
      addRow('Percussion');
      addRow('Percussion');
      await addAudioClip(
        id: 'tempo_perc_a',
        label: 'Percussion A',
        row: 0,
        rhythmic: true,
        durationMs: 8000,
      );
      await addAudioClip(
        id: 'tempo_perc_b',
        label: 'Percussion B',
        row: 1,
        rhythmic: true,
        durationMs: 8000,
      );
      break;
    case 'audio_boundary_signal':
      addRow('Voice');
      addRow('Unchanged');
      await addAudioClip(
        id: 'voice_with_silence',
        label: 'Voice With Silence',
        row: 0,
        withBoundarySilence: true,
        durationMs: 4000,
      );
      await addAudioClip(
        id: 'unchanged_audio',
        label: 'Unchanged',
        row: 1,
        withSignal: true,
        durationMs: 4000,
      );
      break;
    case 'audio_boundary_duplicate_names':
      addRow('Voice');
      addRow('Voice');
      await addAudioClip(
        id: 'voice_boundary_a',
        label: 'Voice',
        row: 0,
        withBoundarySilence: true,
        durationMs: 4000,
      );
      await addAudioClip(
        id: 'voice_boundary_b',
        label: 'Voice',
        row: 1,
        withBoundarySilence: true,
        durationMs: 4000,
      );
      break;
    case 'midi_small':
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addMidiClip(
        id: 'midi_piano',
        label: 'Piano',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'midi_append_live':
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addRow('Unrelated');
      addMidiClip(
        id: 'append_midi',
        label: 'Piano',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
        durationMs: 4000,
      );
      await addBundledAudioClip(
        id: 'append_unrelated',
        label: 'Unrelated Audio',
        row: 1,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bass loop 140bpm.mp3',
      );
      break;
    case 'mixed_medium':
      addRow('Harmony',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addRow('Drums');
      addRow('Bass');
      addMidiClip(
        id: 'harmony_clip',
        label: 'Harmony',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      await addAudioClip(id: 'drums_clip', label: 'Drums', row: 1);
      await addAudioClip(id: 'bass_clip', label: 'Bass', row: 2);
      break;
    case 'automation_mixed_live':
      addRow('Track 1');
      addRow('Track 2');
      addRow('Track 3');
      await addAudioClip(
        id: 'automation_track_1',
        label: 'Track 1 Audio',
        row: 0,
        withSignal: true,
        durationMs: 8000,
      );
      await addAudioClip(
        id: 'automation_track_2',
        label: 'Track 2 Audio',
        row: 1,
        rhythmic: true,
        durationMs: 8000,
      );
      await addAudioClip(
        id: 'automation_track_3',
        label: 'Track 3 Audio',
        row: 2,
        withSignal: true,
        durationMs: 8000,
      );
      break;
    case 'audio_glue_live':
      addRow('Drums');
      addRow('Textures');
      addRow('Vocals');
      addRow(
        'Keys',
        kind: 'instrument',
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      );
      await addAudioClip(
        id: 'drums_intro_a',
        label: 'Drums Intro A',
        row: 0,
        offset: 0,
        rhythmic: true,
        durationMs: 1200,
      );
      await addAudioClip(
        id: 'drums_intro_b',
        label: 'Drums Intro B',
        row: 0,
        offset: 1.2,
        rhythmic: true,
        durationMs: 1200,
      );
      await addAudioClip(
        id: 'drums_gap_a',
        label: 'Drums Gap A',
        row: 0,
        offset: 3.0,
        rhythmic: true,
        durationMs: 1000,
      );
      await addAudioClip(
        id: 'drums_gap_b',
        label: 'Drums Gap B',
        row: 0,
        offset: 5.0,
        rhythmic: true,
        durationMs: 1000,
      );
      await addAudioClip(
        id: 'texture_overlap_a',
        label: 'Texture Layer',
        row: 1,
        offset: 0,
        withSignal: true,
        durationMs: 1800,
      );
      await addAudioClip(
        id: 'texture_overlap_b',
        label: 'Texture Layer',
        row: 1,
        offset: 1.0,
        withSignal: true,
        durationMs: 1800,
      );
      await addAudioClip(
        id: 'texture_tail_a',
        label: 'Texture Tail A',
        row: 1,
        offset: 4.0,
        withSignal: true,
        durationMs: 1200,
      );
      await addAudioClip(
        id: 'texture_tail_b',
        label: 'Texture Tail B',
        row: 1,
        offset: 4.6,
        withSignal: true,
        durationMs: 1200,
      );
      await addAudioClip(
        id: 'vocal_phrase_a',
        label: 'Vocal Phrase A',
        row: 2,
        offset: 0,
        withSignal: true,
        durationMs: 1400,
      );
      await addAudioClip(
        id: 'vocal_phrase_b',
        label: 'Vocal Phrase B',
        row: 2,
        offset: 1.4,
        withSignal: true,
        durationMs: 1400,
      );
      await addAudioClip(
        id: 'vocal_phrase_c',
        label: 'Vocal Phrase C',
        row: 2,
        offset: 2.8,
        withSignal: true,
        durationMs: 1400,
      );
      await addAudioClip(
        id: 'vocal_unrelated',
        label: 'Vocal Unrelated',
        row: 2,
        offset: 6.0,
        withSignal: true,
        durationMs: 1200,
      );
      addMidiClip(
        id: 'glue_keys',
        label: 'Keys',
        row: 3,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'audio_stem_live':
      addRow('Main Mix');
      addRow('Alternate Mix');
      addRow('Alternate Mix');
      addRow('Unrelated Audio');
      addRow(
        'Keys',
        kind: 'instrument',
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      );
      await addBundledAudioClip(
        id: 'stem_main_mix',
        label: 'Main Mix',
        row: 0,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/Trap Drum Loop-12(130).mp3',
      );
      await addBundledAudioClip(
        id: 'stem_alt_a',
        label: 'Alternate Mix',
        row: 1,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bell synth loop 140bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'stem_alt_b',
        label: 'Alternate Mix',
        row: 2,
        assetPath: 'assets/sample_packs/starter_kit_v1/Loops/key loop 135.mp3',
      );
      await addBundledAudioClip(
        id: 'stem_unrelated',
        label: 'Unrelated Audio',
        row: 3,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bass loop 140bpm.mp3',
      );
      addMidiClip(
        id: 'stem_keys',
        label: 'Keys',
        row: 4,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'audio_to_midi_live':
      addRow('Melody');
      addRow('Bass');
      addRow('Phrase');
      addRow('Phrase');
      addRow('Processed Lead');
      addRow('Spanish Lead');
      addRow(
        'Existing MIDI',
        kind: 'instrument',
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      );
      await addBundledAudioClip(
        id: 'audio_melody',
        label: 'Melody Loop',
        row: 0,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa flute 120bpm_1.mp3',
      );
      await addBundledAudioClip(
        id: 'audio_bass',
        label: 'Bass Loop',
        row: 1,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa bass 120bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'audio_phrase_a',
        label: 'Musical Phrase',
        row: 2,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bell synth loop 140bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'audio_phrase_b',
        label: 'Musical Phrase',
        row: 3,
        assetPath: 'assets/sample_packs/starter_kit_v1/Loops/key loop 135.mp3',
      );
      await addBundledAudioClip(
        id: 'audio_processed_lead',
        label: 'Processed Lead',
        row: 4,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa lead 120bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'audio_spanish_lead',
        label: 'Spanish Lead',
        row: 5,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/key arp  loop 135.mp3',
      );
      addMidiClip(
        id: 'existing_midi',
        label: 'Existing MIDI',
        row: 6,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'v3_reliability_checkpoint':
      addRow('Processed Melody');
      addRow('Automation Lead');
      addRow('Glue Bus');
      addRow('Mixed Song');
      addRow('Pitched Lead');
      addRow('Pitched Bass');
      addRow('Compound Source');
      addRow('Spanish Source');
      addRow('Unrelated');
      addRow(
        'Existing MIDI',
        kind: 'instrument',
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
      );
      await addBundledAudioClip(
        id: 'checkpoint_processed',
        label: 'Processed Melody',
        row: 0,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa lead 120bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_automation',
        label: 'Automation Lead',
        row: 1,
        assetPath: 'assets/sample_packs/starter_kit_v1/Loops/key loop 135.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_glue_a',
        label: 'Glue A',
        row: 2,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bell synth loop 140bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_glue_b',
        label: 'Glue B',
        row: 2,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/key arp  loop 135.mp3',
      );
      tracks.last['offset'] = 1.4;
      await addBundledAudioClip(
        id: 'checkpoint_mix',
        label: 'Mixed Song',
        row: 3,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/Trap Drum Loop-12(130).mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_pitched_lead',
        label: 'Pitched Lead',
        row: 4,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa flute 120bpm_1.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_pitched_bass',
        label: 'Pitched Bass',
        row: 5,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/doa bass 120bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_compound',
        label: 'Compound Source',
        row: 6,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/sample rising pad 146bpm_1.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_spanish',
        label: 'Spanish Source',
        row: 7,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/sample organ bass 146bpm.mp3',
      );
      await addBundledAudioClip(
        id: 'checkpoint_unrelated',
        label: 'Unrelated Audio',
        row: 8,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/bass loop 140bpm.mp3',
      );
      addMidiClip(
        id: 'checkpoint_existing_midi',
        label: 'Existing MIDI',
        row: 9,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'v3_reliability_capacity':
      for (var index = 0; index < 32; index++) {
        addRow(index == 0 ? 'Capacity Source' : 'Capacity ${index + 1}');
      }
      await addBundledAudioClip(
        id: 'checkpoint_capacity_source',
        label: 'Capacity Source',
        row: 0,
        assetPath:
            'assets/sample_packs/starter_kit_v1/Loops/Trap Drum Loop-12(130).mp3',
      );
      break;
    case 'mixed_small_catalog':
      addRow('Guide');
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      await addAudioClip(id: 'guide_clip', label: 'Guide', row: 0);
      addMidiClip(
        id: 'catalog_piano',
        label: 'Piano',
        row: 1,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      await audio('kick_sample_120.wav');
      break;
    case 'midi_medium':
      addRow('Harmony',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addRow('Strings',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.violin_ens_sus',
          instrumentName: 'Violin Ensemble Sustain');
      addMidiClip(
        id: 'medium_harmony',
        label: 'Minor Harmony',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(bars: 4),
      );
      break;
    case 'midi_two_clips':
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addMidiClip(
        id: 'piano_intro',
        label: 'Piano Intro',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      addMidiClip(
        id: 'piano_outro',
        label: 'Piano Outro',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
        offset: 8,
      );
      break;
    case 'midi_duplicate_names':
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addRow('Piano',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addMidiClip(
        id: 'first_piano',
        label: 'First Piano',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      addMidiClip(
        id: 'second_piano',
        label: 'Second Piano',
        row: 1,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: _minorHarmonyNotes(),
      );
      break;
    case 'midi_dense':
      addRow('Dense Keys',
          kind: 'instrument',
          instrumentId: 'sfz.vsco.upright_piano',
          instrumentName: 'Upright Piano');
      addMidiClip(
        id: 'dense_keys',
        label: 'Dense Keys',
        row: 0,
        instrumentId: 'sfz.vsco.upright_piano',
        instrumentName: 'Upright Piano',
        notes: List<Map<String, dynamic>>.generate(
          500,
          (index) => <String, dynamic>{
            'id': 'dense_note_$index',
            'pitch': 48 + (index % 24),
            'startBeat': index * 0.125,
            'lengthBeats': 0.125,
            'velocity': 0.7,
          },
        ),
      );
      break;
    case 'audio_duplicate_names':
      addRow('Vocal');
      addRow('Vocal');
      await addAudioClip(id: 'vocal_a', label: 'Lead Vocal', row: 0);
      await addAudioClip(id: 'vocal_b', label: 'Backing Vocal', row: 1);
      break;
    case 'rows_32':
      for (var index = 0; index < 32; index++) {
        addRow('Utility ${index + 1}');
      }
      break;
    case 'clips_64':
    case 'clips_65':
      addRow('Clip Lane');
      final count = fixtureId == 'clips_64' ? 64 : 65;
      for (var index = 0; index < count; index++) {
        await addAudioClip(
          id: 'clip_${index.toString().padLeft(3, '0')}',
          label: 'Clip ${index + 1}',
          row: 0,
          offset: index * 0.75,
        );
      }
      break;
    default:
      throw ArgumentError.value(fixtureId, 'fixtureId', 'Unknown fixture');
  }

  final rowStates = List<Map<String, dynamic>>.generate(
    rows.length,
    (index) => <String, dynamic>{
      'row': index,
      'rowId': -1,
      'gain': fixtureId == 'audio_non_neutral' && index == 0 ? 2.5 : 2.0,
      'pan': fixtureId == 'audio_non_neutral' && index == 0 ? 0.7 : 0.5,
      'muted': false,
      'soloed': false,
      'volumeAutomation': <Map<String, dynamic>>[
        <String, dynamic>{'x': 0.0, 'volume': 1.0},
        <String, dynamic>{'x': 8000.0, 'volume': 1.0},
      ],
      'automationLanes': const <Map<String, dynamic>>[],
      'automationClips': const <Map<String, dynamic>>[],
      'selectedAutomationTargetId': 'volume',
      'inputChannelStart': 0,
      'inputChannelCount': 1,
    },
  );
  if (fixtureId == 'automation_mixed_live') {
    rowStates[0]['volumeAutomation'] = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'volume': 0.65},
      <String, dynamic>{'x': 4000.0, 'volume': 0.85},
      <String, dynamic>{'x': 8000.0, 'volume': 0.65},
    ];
  }
  if (fixtureId == 'audio_glue_live') {
    rowStates[0]['gain'] = 1.8;
    rowStates[0]['pan'] = 0.4;
    rowStates[1]['volumeAutomation'] = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'volume': 0.6},
      <String, dynamic>{'x': 3000.0, 'volume': 0.9},
      <String, dynamic>{'x': 7000.0, 'volume': 0.7},
    ];
    final processed =
        tracks.firstWhere((track) => track['clipId'] == 'texture_overlap_a');
    processed['gain'] = 1.6;
    processed['pitchSemitones'] = 2.0;
    processed['isReversed'] = true;
    processed['crossfade'] = 0.25;
    final processedTail =
        tracks.firstWhere((track) => track['clipId'] == 'texture_tail_a');
    processedTail['gain'] = 1.7;
    processedTail['pitchSemitones'] = -2.0;
    processedTail['crossfade'] = 0.2;
  }
  if (fixtureId == 'audio_to_midi_live') {
    rowStates[0]['gain'] = 1.7;
    rowStates[1]['pan'] = 0.35;
    rowStates[5]['volumeAutomation'] = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'volume': 0.7},
      <String, dynamic>{'x': 1200.0, 'volume': 0.9},
    ];
    final processed = tracks.firstWhere(
      (track) => track['clipId'] == 'audio_processed_lead',
    );
    processed['gain'] = 1.65;
    processed['pitchSemitones'] = 2.0;
    processed['isReversed'] = true;
    processed['crossfade'] = 0.2;
  }
  if (fixtureId == 'v3_reliability_checkpoint') {
    rowStates[0]['gain'] = 1.72;
    rowStates[1]['pan'] = 0.65;
    rowStates[1]['volumeAutomation'] = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'volume': 0.55},
      <String, dynamic>{'x': 1200.0, 'volume': 0.85},
    ];
    rowStates[8]['volumeAutomation'] = <Map<String, dynamic>>[
      <String, dynamic>{'x': 0.0, 'volume': 0.8},
      <String, dynamic>{'x': 1200.0, 'volume': 0.7},
    ];
    final processed = tracks.firstWhere(
      (track) => track['clipId'] == 'checkpoint_processed',
    );
    processed['gain'] = 1.62;
    processed['pitchSemitones'] = 2.0;
    processed['isReversed'] = true;
    processed['crossfade'] = 0.2;
  }
  final rowEffects = List<Map<String, dynamic>>.generate(
    rows.length,
    (index) => <String, dynamic>{
      'row': index,
      'rowId': -1,
      'effects': const <Map<String, dynamic>>[],
    },
  );
  final project = await ProjectManager.readProjectJson(directory);
  project.addAll(<String, dynamic>{
    'version': 6,
    'nameConfirmed': true,
    'tempoBpm': 120.0,
    'tempoStretchEnabled': fixtureId == 'audio_stretched',
    'tempoStretchPreservePitchDefault': false,
    'projectKey': 'C minor',
    'timeSignature': <String, int>{'numerator': 4, 'denominator': 4},
    'rows': rows,
    'tracks': tracks,
    'rowStates': rowStates,
    'rowEffects': rowEffects,
    'master': <String, dynamic>{
      'gain': 2.0,
      'pan': 0.5,
      'effects': <String, dynamic>{'effects': const <Map<String, dynamic>>[]},
    },
    'ui': <String, dynamic>{
      'showProducerCaptureUi': false,
      'desktopKeyboardMidiEnabled': false,
      'desktopSpacebarStopReturnsToStart': false,
      'allowMultipleExpandedRows': true,
      'expandRowsOnTrackSelect': true,
      'crossfadeMode': 'equal_power',
      'metronomeEnabled': false,
      'metronomeVolume': 0.5,
      'sampleRate': 48000,
      'bufferSize': 512,
      'midiInputChannel': 0,
      'loopEnabled': false,
      'loopStartMs': 0,
      'loopEndMs': 0,
    },
  });
  await ProjectManager.writeProjectJson(directory, project);
  return DevelopmentEvalFixture(
    directory: directory,
    rowCount: rows.length,
    clipCount: tracks.length,
  );
}

Map<String, dynamic> _track({
  required String clipId,
  required String label,
  required int row,
  required String fileName,
  String clipType = 'audio',
  double offset = 0,
  String instrumentId = '',
  String instrumentName = '',
  List<Map<String, dynamic>> notes = const <Map<String, dynamic>>[],
  double sourceTempoBpm = 120,
  bool stretchToProjectTempo = false,
  bool preservePitch = false,
  String warpMode = 'complex',
  int durationMs = 1200,
}) {
  return <String, dynamic>{
    'fileName': fileName,
    'label': label,
    'clipType': clipType,
    'trimStartMs': 0,
    'trimEndMs': durationMs,
    'offset': offset,
    'crossfade': 0.0,
    'gain': 2.0,
    'normalizeVolume': false,
    'normalizeGain': 1.0,
    'preNormalizeGain': 2.0,
    'pitchSemitones': 0.0,
    'isReversed': false,
    'sourceTempoBpm': sourceTempoBpm,
    'stretchToProjectTempo': clipType == 'midi' || stretchToProjectTempo,
    'tempoStretchPreservePitch': clipType == 'midi' || preservePitch,
    'tempoWarpMode': clipType == 'midi' ? 'complex' : warpMode,
    'rowIndex': row,
    'rowId': -1,
    'clipId': clipId,
    'automation': const <Map<String, dynamic>>[],
    'instrumentId': instrumentId,
    'instrumentName': instrumentName,
    'instrumentParams': const <String, double>{},
    'midiNotes': notes,
  };
}

List<Map<String, dynamic>> _minorHarmonyNotes({int bars = 2}) {
  final notes = <Map<String, dynamic>>[];
  const chords = <List<int>>[
    <int>[48, 51, 55],
    <int>[46, 50, 53],
    <int>[44, 48, 51],
    <int>[43, 47, 50],
  ];
  var index = 0;
  for (var bar = 0; bar < bars; bar++) {
    final chord = chords[bar % chords.length];
    for (final pitch in chord) {
      notes.add(<String, dynamic>{
        'id': 'note_${index++}',
        'pitch': pitch,
        'startBeat': bar * 4.0,
        'lengthBeats': 3.5,
        'velocity': 0.72,
      });
    }
  }
  return notes;
}

Uint8List _silentWavBytes({
  int sampleRate = 48000,
  int durationMs = 1200,
}) {
  const channels = 1;
  const bitsPerSample = 16;
  final samples = ((sampleRate * durationMs) / 1000).round();
  const bytesPerSample = bitsPerSample ~/ 8;
  const blockAlign = channels * bytesPerSample;
  final dataSize = samples * blockAlign;
  final buffer = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(buffer);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      buffer[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * blockAlign, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  return buffer;
}

Uint8List _toneWavBytes({
  int sampleRate = 48000,
  int durationMs = 1200,
}) {
  final buffer = _silentWavBytes(
    sampleRate: sampleRate,
    durationMs: durationMs,
  );
  final data = ByteData.sublistView(buffer);
  final samples = ((sampleRate * durationMs) / 1000).round();
  for (var index = 0; index < samples; index++) {
    final sample = ((index ~/ 48).isEven ? 6000 : -6000);
    data.setInt16(44 + (index * 2), sample, Endian.little);
  }
  return buffer;
}

Uint8List _rhythmicWavBytes({
  int sampleRate = 48000,
  int durationMs = 8000,
}) {
  final buffer = _silentWavBytes(
    sampleRate: sampleRate,
    durationMs: durationMs,
  );
  final data = ByteData.sublistView(buffer);
  final samples = ((sampleRate * durationMs) / 1000).round();
  final beatSamples = sampleRate ~/ 2;
  final pulseSamples = sampleRate ~/ 25;
  for (var index = 0; index < samples; index++) {
    final withinBeat = index % beatSamples;
    if (withinBeat >= pulseSamples) continue;
    final envelope = 1.0 - (withinBeat / pulseSamples);
    final carrier = (index ~/ 12).isEven ? 1.0 : -1.0;
    data.setInt16(
      44 + (index * 2),
      (12000 * envelope * carrier).round(),
      Endian.little,
    );
  }
  return buffer;
}

Uint8List _boundedToneWavBytes({
  int sampleRate = 48000,
  int durationMs = 4000,
  int leadingSilenceMs = 300,
  int trailingSilenceMs = 400,
}) {
  final buffer = _silentWavBytes(
    sampleRate: sampleRate,
    durationMs: durationMs,
  );
  final data = ByteData.sublistView(buffer);
  final firstSample = ((sampleRate * leadingSilenceMs) / 1000).round();
  final lastSample =
      ((sampleRate * (durationMs - trailingSilenceMs)) / 1000).round();
  for (var index = firstSample; index < lastSample; index++) {
    final sample = ((index ~/ 48).isEven ? 6000 : -6000);
    data.setInt16(44 + (index * 2), sample, Endian.little);
  }
  return buffer;
}
