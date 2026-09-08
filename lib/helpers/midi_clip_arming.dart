import 'package:mixroom/models/models.dart';

AudioTrack? resolveArmedMidiClip({
  required List<AudioTrack> tracks,
  required int? activeMidiClipEngineId,
  required int primarySelectedClipIndex,
  int? requiredRowIndex,
  int? preferredRowIndex,
}) {
  bool isEligible(AudioTrack track) =>
      track.isMidi &&
      (requiredRowIndex == null || track.rowIndex == requiredRowIndex);

  AudioTrack? activeEditorClip() {
    if (activeMidiClipEngineId == null || activeMidiClipEngineId < 0) {
      return null;
    }
    for (final track in tracks) {
      if (track.engineClipId == activeMidiClipEngineId && isEligible(track)) {
        return track;
      }
    }
    return null;
  }

  AudioTrack? firstClipOnRow(int rowIndex) {
    for (final track in tracks) {
      if (isEligible(track) && track.rowIndex == rowIndex) {
        return track;
      }
    }
    return null;
  }

  AudioTrack? primarySelectedClip() {
    if (primarySelectedClipIndex >= 0 &&
        primarySelectedClipIndex < tracks.length) {
      final track = tracks[primarySelectedClipIndex];
      if (isEligible(track)) {
        return track;
      }
    }
    return null;
  }

  final active = activeEditorClip();
  if (preferredRowIndex != null) {
    if (active != null && active.rowIndex == preferredRowIndex) {
      return active;
    }
    final preferred = firstClipOnRow(preferredRowIndex);
    if (preferred != null) {
      return preferred;
    }
    return primarySelectedClip();
  }

  return active ?? primarySelectedClip();
}

int? resolveSelectedInstrumentLaneRecordingRow({
  required List<TimelineRow> rows,
  required int selectedRow,
}) {
  if (selectedRow < 0 || selectedRow >= rows.length) return null;
  return rows[selectedRow].isInstrumentLane ? selectedRow : null;
}
