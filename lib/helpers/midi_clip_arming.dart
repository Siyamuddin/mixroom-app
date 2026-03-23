import 'package:mixroom/models/models.dart';

AudioTrack? resolveArmedMidiClip({
  required List<AudioTrack> tracks,
  required int? activeMidiClipEngineId,
  required int primarySelectedClipIndex,
}) {
  if (activeMidiClipEngineId != null && activeMidiClipEngineId >= 0) {
    for (final track in tracks) {
      if (track.engineClipId == activeMidiClipEngineId && track.isMidi) {
        return track;
      }
    }
  }

  if (primarySelectedClipIndex >= 0 &&
      primarySelectedClipIndex < tracks.length) {
    final track = tracks[primarySelectedClipIndex];
    if (track.isMidi) {
      return track;
    }
  }

  return null;
}
