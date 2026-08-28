import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juce_audio_engine/audio_route_v2.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';
import 'package:mixroom/helpers/audio_test_signal.dart';
import 'package:path/path.dart' as p;

const _pianoId =
    'sfz_asset:assets/instruments/VSCO-2-CE-1.1.0/UprightPiano.sfz';
const _acousticId =
    'sfz_asset:assets/instruments/FreePats-Spanish-Classical-Guitar-2019-06-18/AcousticGuitar.sfz';
const _electricId =
    'sfz_asset:assets/instruments/Karoryfer-Black-And-Green-Guitars-1.000/ElectricGuitar.sfz';

class _DecodedWav {
  const _DecodedWav(this.sampleRate, this.mono);

  final int sampleRate;
  final Float64List mono;
}

class _InstrumentPitchCase {
  const _InstrumentPitchCase({
    required this.id,
    required this.name,
    required this.pitches,
    this.params = const <String, double>{},
  });

  final String id;
  final String name;
  final List<int> pitches;
  final Map<String, double> params;
}

int _findChunk(Uint8List bytes, String name) {
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final chunkName = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(
      bytes,
      offset + 4,
      offset + 8,
    ).getUint32(0, Endian.little);
    if (chunkName == name) return offset;
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return -1;
}

_DecodedWav _decodePcm16Wav(Uint8List bytes) {
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  final fmtOffset = _findChunk(bytes, 'fmt ');
  final dataOffset = _findChunk(bytes, 'data');
  expect(fmtOffset, greaterThanOrEqualTo(0));
  expect(dataOffset, greaterThanOrEqualTo(0));

  final fmtSize = ByteData.sublistView(
    bytes,
    fmtOffset + 4,
    fmtOffset + 8,
  ).getUint32(0, Endian.little);
  final fmt = ByteData.sublistView(
    bytes,
    fmtOffset + 8,
    fmtOffset + 8 + fmtSize,
  );
  expect(fmt.getUint16(0, Endian.little), 1, reason: 'Expected PCM WAV');
  final channels = fmt.getUint16(2, Endian.little);
  final sampleRate = fmt.getUint32(4, Endian.little);
  final bitsPerSample = fmt.getUint16(14, Endian.little);
  expect(bitsPerSample, 16);
  expect(channels, anyOf(1, 2));

  final dataSize = ByteData.sublistView(
    bytes,
    dataOffset + 4,
    dataOffset + 8,
  ).getUint32(0, Endian.little);
  final sampleBytes = bitsPerSample ~/ 8;
  final frameBytes = channels * sampleBytes;
  final frames = dataSize ~/ frameBytes;
  final mono = Float64List(frames);
  var cursor = dataOffset + 8;
  final data = ByteData.sublistView(bytes);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      sum += data.getInt16(cursor, Endian.little) / 32768.0;
      cursor += sampleBytes;
    }
    mono[frame] = sum / channels;
  }
  return _DecodedWav(sampleRate, mono);
}

double _segmentRms(_DecodedWav wav, double startSec, double durationSec) {
  final start = (startSec * wav.sampleRate).round().clamp(0, wav.mono.length);
  final end = ((startSec + durationSec) * wav.sampleRate).round().clamp(
    start,
    wav.mono.length,
  );
  if (end <= start) return 0.0;
  var energy = 0.0;
  for (var i = start; i < end; i++) {
    energy += wav.mono[i] * wav.mono[i];
  }
  return math.sqrt(energy / (end - start));
}

double _estimateFrequency(_DecodedWav wav, {required double startSec}) {
  // The fixture is a pure sine, so interpolated rising zero crossings are
  // deterministic and substantially cheaper than an autocorrelation pass in
  // a debug integration-test VM.
  final durationSec = 0.45;
  final start = (startSec * wav.sampleRate).round();
  final end = math.min(
    wav.mono.length,
    start + (durationSec * wav.sampleRate).round(),
  );
  final crossings = <double>[];
  for (var i = start + 1; i < end; i++) {
    final previous = wav.mono[i - 1];
    final current = wav.mono[i];
    if (previous <= 0.0 && current > 0.0) {
      final denominator = current - previous;
      final fraction = denominator.abs() < 1e-12
          ? 0.0
          : -previous / denominator;
      crossings.add((i - 1) + fraction);
    }
  }
  expect(crossings.length, greaterThan(20), reason: 'No stable pitched signal');
  return (crossings.length - 1) *
      wav.sampleRate /
      (crossings.last - crossings.first);
}

double _midiFrequency(int pitch) => 440.0 * math.pow(2.0, (pitch - 69) / 12.0);

double _centsBetween(double actualHz, double expectedHz) =>
    1200.0 * math.log(actualHz / expectedHz) / math.ln2;

Map<String, dynamic> _note(int index, int pitch) => <String, dynamic>{
  'id': index + 1,
  'pitch': pitch,
  'startBeat': 1.0 + (index * 2.0),
  'lengthBeats': 0.8,
  'velocity': 0.84,
};

Future<_DecodedWav> _renderPitchCase(
  Directory directory,
  _InstrumentPitchCase pitchCase,
  int caseIndex,
) async {
  final clipId = caseIndex;
  final rowId = await JuceAudioEngine.addRow('PRO-61 ${pitchCase.name}');
  expect(rowId, greaterThanOrEqualTo(0));
  try {
    final notes = <Map<String, dynamic>>[
      for (var i = 0; i < pitchCase.pitches.length; i++)
        _note(i, pitchCase.pitches[i]),
    ];
    await JuceAudioEngine.beginProjectClipLoad();
    var loaded = false;
    try {
      loaded = await JuceAudioEngine.loadMidiClip(
        clipId,
        rowId,
        instrumentId: pitchCase.id,
        instrumentName: pitchCase.name,
        notes: notes,
        params: <String, double>{
          'rootNote': 60.0,
          'outputGain': 0.8,
          'attackMs': 2.0,
          'releaseMs': 250.0,
          ...pitchCase.params,
        },
        sourceTempoBpm: 60.0,
        lengthSec: 2.0 + (pitchCase.pitches.length * 2.0),
        loadRequestId: 61000 + caseIndex,
      );
    } finally {
      await JuceAudioEngine.endProjectClipLoad();
    }
    expect(loaded, isTrue);

    final output = p.join(directory.path, 'case_$caseIndex.wav');
    final exported = await JuceAudioEngine.exportMix(
      output,
      format: 'wav',
      sampleRate: 44100,
      wavBitDepth: 16,
      wavDithering: false,
      audibleClipIds: <int>[clipId],
      dryClipRender: true,
      bypassMasterProcessing: true,
      bypassGroupProcessing: true,
    );
    expect(exported, isNotEmpty);
    return _decodePcm16Wav(await File(exported).readAsBytes());
  } finally {
    await JuceAudioEngine.unloadClip(clipId);
    await JuceAudioEngine.removeRow(rowId);
  }
}

List<double> _expectRequestedPitches(
  _DecodedWav wav,
  List<int> pitches, {
  double toleranceCents = 35.0,
}) {
  final measuredFrequencies = <double>[];
  for (var i = 0; i < pitches.length; i++) {
    final pitch = pitches[i];
    final startSec = 1.14 + (i * 2.0);
    expect(
      _segmentRms(wav, startSec, 0.35),
      greaterThan(0.0005),
      reason: 'MIDI $pitch rendered silence',
    );
    final expectedHz = _midiFrequency(pitch);
    final actualHz = _estimateFrequency(wav, startSec: startSec);
    measuredFrequencies.add(actualHz);
    expect(
      _centsBetween(actualHz, expectedHz).abs(),
      lessThan(toleranceCents),
      reason: 'MIDI $pitch rendered at ${actualHz.toStringAsFixed(2)} Hz',
    );
  }
  return measuredFrequencies;
}

Future<void> _expectPreviewAvailability({
  required int clipId,
  required List<int> available,
  required List<int> unavailable,
}) async {
  expect(await JuceAudioEngine.setLiveMidiInputTargetClip(clipId), isTrue);
  for (final pitch in available) {
    expect(
      await JuceAudioEngine.playPreviewMidiNote(
        clipId,
        pitch: pitch,
        velocity: 0.8,
        durationMs: 80,
      ),
      isTrue,
      reason: 'MIDI $pitch should be playable',
    );
  }
  for (final pitch in unavailable) {
    expect(
      await JuceAudioEngine.playPreviewMidiNote(
        clipId,
        pitch: pitch,
        velocity: 0.8,
        durationMs: 80,
      ),
      isFalse,
      reason: 'MIDI $pitch should be unmapped',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native SFZ playback preserves chromatic pitches and sampler roots',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'mixroom_pro61_pitch_',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      expect(
        await JuceAudioEngine.initialiseForImplementation(
          BluetoothImplementationV2.legacy,
        ),
        isTrue,
      );
      try {
        final fixtureFiles = <int, File>{};
        for (final pitch in const <int>[60, 61, 62, 63]) {
          fixtureFiles[pitch] = await AudioTestSignal.writePcm16WavFile(
            File(p.join(directory.path, 'fixture_$pitch.wav')),
            AudioTestSignalSpec(
              sampleRate: 44100,
              channels: 1,
              duration: const Duration(seconds: 2),
              frequencyHz: _midiFrequency(pitch),
              amplitude: 0.6,
            ),
          );
        }
        final keyedSfz = File(p.join(directory.path, 'keyed.sfz'));
        await keyedSfz.writeAsString(
          [
            for (final pitch in const <int>[60, 61, 62])
              '<region> key=$pitch sample=${p.basename(fixtureFiles[pitch]!.path)}',
            '',
          ].join('\n'),
        );
        final keyedFixture = await _renderPitchCase(
          directory,
          _InstrumentPitchCase(
            id: 'sfz_asset:${keyedSfz.path}',
            name: 'Key Opcode Fixture',
            pitches: const <int>[60, 61, 62],
          ),
          0,
        );
        final keyedFrequencies = _expectRequestedPitches(
          keyedFixture,
          const <int>[60, 61, 62],
        );
        final expectedSemitoneRatio = math.pow(2.0, 1.0 / 12.0);
        for (var i = 1; i < keyedFrequencies.length; i++) {
          expect(
            keyedFrequencies[i] / keyedFrequencies[i - 1],
            closeTo(expectedSemitoneRatio, 0.001),
            reason: 'Consecutive MIDI notes must differ by one semitone',
          );
        }

        final precedenceSfz = File(p.join(directory.path, 'precedence.sfz'));
        await precedenceSfz.writeAsString(
          '<group> key=C4\n'
          '<region> sample=${p.basename(fixtureFiles[60]!.path)}\n'
          '<region> key=C4 lokey=C#4 hikey=D4 pitch_keycenter=C#4 '
          'sample=${p.basename(fixtureFiles[61]!.path)}\n'
          '<region> key=invalid lokey=D#4 hikey=D#4 '
          'pitch_keycenter=invalid '
          'sample=${p.basename(fixtureFiles[63]!.path)}\n',
        );
        final precedenceFixture = await _renderPitchCase(
          directory,
          _InstrumentPitchCase(
            id: 'sfz_asset:${precedenceSfz.path}',
            name: 'SFZ Precedence Fixture',
            pitches: const <int>[60, 61, 62, 63],
          ),
          1,
        );
        _expectRequestedPitches(precedenceFixture, const <int>[60, 61, 62, 63]);

        final samplerSfz = File(p.join(directory.path, 'sampler.sfz'));
        await samplerSfz.writeAsString(
          '<region> sample=${p.basename(fixtureFiles[60]!.path)} '
          'lokey=0 hikey=127 pitch_keycenter=60\n',
        );
        final shiftedSampler = await _renderPitchCase(
          directory,
          _InstrumentPitchCase(
            id: 'sfz_asset:${samplerSfz.path}',
            name: 'Pitch Fixture Sampler',
            pitches: const <int>[62, 63],
            params: const <String, double>{'rootNote': 62.0},
          ),
          2,
        );
        _expectRequestedPitches(shiftedSampler, const <int>[60, 61]);

        final productionCases =
            <
              ({
                String id,
                String name,
                List<int> available,
                List<int> unavailable,
              })
            >[
              (
                id: _pianoId,
                name: 'Upright Piano',
                available: <int>[
                  for (var pitch = 60; pitch <= 72; pitch++) pitch,
                  21,
                  108,
                ],
                unavailable: const <int>[20, 109],
              ),
              (
                id: _acousticId,
                name: 'Acoustic Guitar',
                available: const <int>[40, 41, 42, 43, 60, 61, 62, 83, 84],
                unavailable: const <int>[39, 85],
              ),
              (
                id: _electricId,
                name: 'Electric Guitar',
                available: const <int>[40, 41, 42, 59, 60, 61, 84, 85, 86],
                unavailable: const <int>[39, 87],
              ),
            ];
        for (var index = 0; index < productionCases.length; index++) {
          final pitchCase = productionCases[index];
          final clipId = index + 3;
          final rowId = await JuceAudioEngine.addRow(
            'PRO-61 ${pitchCase.name} range',
          );
          try {
            await JuceAudioEngine.beginProjectClipLoad();
            var loaded = false;
            try {
              loaded = await JuceAudioEngine.loadMidiClip(
                clipId,
                rowId,
                instrumentId: pitchCase.id,
                instrumentName: pitchCase.name,
                notes: const <Map<String, dynamic>>[],
                params: const <String, double>{'rootNote': 60.0},
                sourceTempoBpm: 60.0,
                lengthSec: 2.0,
                loadRequestId: 61100 + index,
              );
            } finally {
              await JuceAudioEngine.endProjectClipLoad();
            }
            expect(loaded, isTrue);
            await _expectPreviewAvailability(
              clipId: clipId,
              available: pitchCase.available,
              unavailable: pitchCase.unavailable,
            );
          } finally {
            await JuceAudioEngine.unloadClip(clipId);
            await JuceAudioEngine.removeRow(rowId);
          }
        }
      } finally {
        await JuceAudioEngine.shutdown();
      }
    },
    skip: !(Platform.isMacOS || Platform.isAndroid || Platform.isIOS),
  );
}
