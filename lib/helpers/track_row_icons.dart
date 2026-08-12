import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Stable IDs persisted with project rows. Add new options at the end only.
const List<int> kTrackRowIconIds = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
  20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
  38, 39, 40, 41,
];

IconData trackRowIconForId(int iconId) {
  switch (iconId) {
    case 1:
      return Icons.piano;
    case 2:
      return Icons.graphic_eq;
    case 3:
      return Icons.queue_music;
    case 4:
      return Symbols.music_note;
    case 5:
      return Symbols.podcasts;
    case 6:
      return Icons.mic_rounded;
    case 7:
      return Icons.headphones_rounded;
    case 8:
      return Icons.album_rounded;
    case 9:
      return Icons.radio_rounded;
    case 10:
      return Icons.record_voice_over_rounded;
    case 11:
      return Icons.volume_up_rounded;
    case 12:
      return Icons.audiotrack_rounded;
    case 13:
      return Icons.library_music_rounded;
    case 14:
      return Icons.surround_sound_rounded;
    case 15:
      return Icons.speaker_rounded;
    case 16:
      return Icons.keyboard_rounded;
    case 17:
      return Icons.music_video_rounded;
    case 18:
      return Icons.person_rounded;
    case 19:
      return Icons.waves_rounded;
    case 20:
      return Icons.multitrack_audio_rounded;
    case 21:
      return Icons.tune_rounded;
    case 22:
      return Icons.auto_graph_rounded;
    case 23:
      return Icons.bolt_rounded;
    case 24:
      return Icons.star_rounded;
    case 25:
      return Icons.folder_rounded;
    default:
      return Symbols.audio_file;
  }
}

String? trackRowEmojiForId(int iconId) {
  switch (iconId) {
    case 26:
      return '🎤';
    case 27:
      return '🎸';
    case 28:
      return '🥁';
    case 29:
      return '🎷';
    case 30:
      return '🎺';
    case 31:
      return '🎻';
    case 32:
      return '😀';
    case 33:
      return '😎';
    case 34:
      return '🤖';
    case 35:
      return '👾';
    case 36:
      return '👻';
    case 37:
      return '🔥';
    case 38:
      return '✨';
    case 39:
      return '🌙';
    case 40:
      return '💎';
    case 41:
      return '🚀';
  }
  return null;
}

Widget buildTrackRowIcon(
  int iconId, {
  required double size,
  required Color color,
}) {
  final emoji = trackRowEmojiForId(iconId);
  if (emoji != null) {
    return Text(
      emoji,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: size, height: 1),
    );
  }
  return Icon(trackRowIconForId(iconId), size: size, color: color);
}
