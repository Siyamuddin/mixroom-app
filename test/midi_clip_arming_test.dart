import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/midi_clip_arming.dart';
import 'package:mixroom/models/models.dart';

Future<AudioTrack> _buildTrack({
  required int engineClipId,
  required ClipKind kind,
  required String label,
}) {
  final file = File('/tmp/$label.wav');
  return AudioTrack.create(
    file: file,
    originalFile: file,
    audioDuration: const Duration(seconds: 1),
    trimEnd: const Duration(seconds: 1),
    engineClipId: engineClipId,
    label: label,
    clipKind: kind,
  );
}

void main() {
  test('prefers active midi editor clip when available', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.midi,
        label: 'piano',
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.audio,
        label: 'audio',
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: 11,
      primarySelectedClipIndex: 1,
    );

    expect(armed?.engineClipId, 11);
  });

  test('falls back to the selected midi clip when editor clip is absent',
      () async {
    final tracks = <AudioTrack>[
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.audio,
        label: 'audio',
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.midi,
        label: 'strings',
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: null,
      primarySelectedClipIndex: 1,
    );

    expect(armed?.engineClipId, 22);
  });

  test('does not arm a non-midi primary selection', () async {
    final tracks = <AudioTrack>[
      await _buildTrack(
        engineClipId: 11,
        kind: ClipKind.audio,
        label: 'audio',
      ),
      await _buildTrack(
        engineClipId: 22,
        kind: ClipKind.midi,
        label: 'bass',
      ),
    ];

    final armed = resolveArmedMidiClip(
      tracks: tracks,
      activeMidiClipEngineId: null,
      primarySelectedClipIndex: 0,
    );

    expect(armed, isNull);
  });
}
