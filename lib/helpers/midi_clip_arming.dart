import 'package:mixroom/models/models.dart';

AudioTrack? resolveArmedMidiClip({
  required List<AudioTrack> tracks,
  required int? activeMidiClipEngineId,
  required int primarySelectedClipIndex,
  int? requiredRowIndex,
}) {
  bool isEligible(AudioTrack track) =>
      track.isMidi &&
      (requiredRowIndex == null || track.rowIndex == requiredRowIndex);

  if (activeMidiClipEngineId != null && activeMidiClipEngineId >= 0) {
    for (final track in tracks) {
      if (track.engineClipId == activeMidiClipEngineId && isEligible(track)) {
        return track;
      }
    }
  }

  if (primarySelectedClipIndex >= 0 &&
      primarySelectedClipIndex < tracks.length) {
    final track = tracks[primarySelectedClipIndex];
    if (isEligible(track)) {
      return track;
    }
  }

  return null;
}

int? resolveSelectedInstrumentLaneRecordingRow({
  required List<TimelineRow> rows,
  required int selectedRow,
}) {
  if (selectedRow < 0 || selectedRow >= rows.length) return null;
  return rows[selectedRow].isInstrumentLane ? selectedRow : null;
}
