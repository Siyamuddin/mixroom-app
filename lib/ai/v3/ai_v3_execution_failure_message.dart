const String _fallbackMessage =
    'Something went wrong while applying the changes, so I restored the project to its previous state. Please try again.';

const String _recordingMessage =
    'Playback controls cannot be changed while recording. Stop recording first, then try again. Nothing was changed.';

const String _audioToMidiNotesMessage =
    'I could not detect usable notes in that audio. The project was unchanged. Try a clearer pitched clip or convert a different clip.';

const String _audioToMidiUnreadableMessage =
    'I could not read that audio clip for transcription. The project was unchanged. Try another readable audio clip.';

const String _trackOrClipMessage =
    'I couldn’t finish a requested track or clip change, so I restored the project. Check that the target is still available and try again.';

const String _mixMessage =
    'I couldn’t apply the mix to all requested tracks, so I restored the project. Check the target tracks and try again.';

const String _soundChangeMessage =
    'I couldn’t apply one of the requested sound changes, so I restored the project. Try again or choose another available effect or instrument.';

const String _groupMessage =
    'I couldn’t apply the requested track grouping, so I restored the project. Check that those tracks still exist and try again.';

const String _transportMessage =
    'I couldn’t apply the requested playback change, so I restored the project. Check the transport state and try again.';

/// Returns user-facing copy for a V3 execution failure after a complete
/// rollback. Exception text is classified only; it is never displayed.
String aiV3RolledBackFailureMessage(Object cause) {
  String description;
  try {
    description = cause.toString();
  } catch (_) {
    return _fallbackMessage;
  }
  if (description.length > 4096) {
    description = description.substring(0, 4096);
  }
  final codes = RegExp(
    r'v3_[a-z0-9_]{1,80}',
  ).allMatches(description).map((match) => match.group(0)!).toSet();

  bool hasCode(String code) => codes.contains(code);
  bool hasPrefix(String prefix) => codes.any((code) => code.startsWith(prefix));

  if (hasCode('v3_transport_recording_active')) return _recordingMessage;
  if (hasCode('v3_audio_to_midi_source_unreadable')) {
    return _audioToMidiUnreadableMessage;
  }
  if (hasCode('v3_audio_to_midi_source_silent') ||
      hasCode('v3_audio_to_midi_no_stable_notes') ||
      hasCode('v3_audio_to_midi_render_unreadable') ||
      hasCode('v3_audio_to_midi_transcription_failed')) {
    return _audioToMidiNotesMessage;
  }
  if (hasPrefix('v3_audio_to_midi_instrument_') ||
      hasPrefix('v3_midi_instrument_')) {
    return _soundChangeMessage;
  }
  if (hasPrefix('v3_resource_') ||
      hasPrefix('v3_clip_') ||
      hasPrefix('v3_sample_replace_') ||
      hasPrefix('v3_generated_') ||
      hasPrefix('v3_audio_to_midi_') ||
      hasPrefix('v3_row_role_')) {
    return _trackOrClipMessage;
  }
  if (hasPrefix('v3_mix_') || hasPrefix('v3_row_mix_')) return _mixMessage;
  if (hasPrefix('v3_effect_') ||
      hasPrefix('v3_row_instrument_') ||
      hasPrefix('v3_phone_cleanup_')) {
    return _soundChangeMessage;
  }
  if (hasPrefix('v3_group_')) return _groupMessage;
  if (hasPrefix('v3_transport_')) return _transportMessage;
  return _fallbackMessage;
}
