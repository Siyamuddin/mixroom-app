import 'ai_v3_contract.dart';

/// Always-on planner layer for production-style / remix / listening-format
/// goals (PRO-18). Request-independent: the original request stays in
/// ORIGINAL_REQUEST_VERBATIM. Flutter never matches genre names.
const String aiV3MusicalDimensionCompilerInstructions = '''
A production-style, remix, version, or listening-format goal is one request.
When the original request names such a goal rather than individual edits,
infer which musical dimensions it implies and emit every Mixroom-supported
implied step in this one plan. Implied steps of a goal are related; they
are not unrelated commands. Do not stop after the nearest single command.
Do not substitute clip.align_tempo_to_project for a style transformation.
Do not clarify speed versus pitch when the goal implies both.

Map implied dimensions to legal commands only:
- Tempo: project.set_tempo. When pitch is a separate step, set
  time_stretch_audio true and preserve_pitch true so tempo does not
  secretly double-pitch. Clamp BPM 20–999. If current project BPM is
  already inside the implied band, skip project.set_tempo and still emit
  the other implied dimensions.
- Pitch: clip.adjust_pitch_semitones on existing audio clips. Use
  midi.transpose only for in-scope MIDI clips. Never pitch MIDI with an
  audio pitch command. Stay within contract ranges. If the 16-command
  budget cannot cover every audio clip, prioritize the longest or main
  clips and say which were skipped.
- Mix / space: mix.apply_goal for subjective tone, width, or energy.
  Spatial or headphone-orbit motion uses automation.set_points on mix:pan
  when that automation target exists in context. Do not also emit a
  mix.apply_goal pan intent or a static pan on the same request.
  mix.apply_goal may still change tone, reverb, or EQ. If mix:pan is
  missing, mix-widen only and say the sweep was skipped. Stereo pan is
  an illusion, not binaural or HRIR 8D.
- Arrangement: do not add drums, bass, risers, or other parts because a
  production style implies them, even when library assets exist.
  sample.place only when the original request explicitly asks to add
  those parts and a real asset_id is already in context. Otherwise skip
  accompaniment and say so. Never invent a library asset.

Style goals target the whole project (every existing audio clip, all_rows
for mix) unless the user names one track. Tempo remains project-wide; say
so if mix or pitch is scoped to one track.
Never invent a row, clip, instrument, effect, parameter, or library asset.
Never import or export. Stay within 16 commands. Moderate defaults from
musical knowledge, not a catalog of named styles.
An empty project with no audio is unsupported or a clarification; do not
invent a song.
Named single edits remain single edits. Questions do not mutate.
A request that only asks for a higher, lower, squeaky, or deeper vocal
or sound is a named pitch edit: clip.adjust_pitch_semitones, or
midi.transpose for MIDI. Do not add tempo or mix unless the request also
names a production-style, remix, version, or listening-format goal.
Pitch-only metaphors stay moderate: a few semitones of lift or drop,
not a full octave, unless the user names an amount.
Explicit do-not-change constraints beat an implied dimension (for example
keep pitch).
For production-style, remix, version, or listening-format mutating plans,
user_message must name what will change and which common DAW steps Mixroom
skipped, such as import, export, generated drums, or true binaural 8D.
Named single edits, questions, and refusals must not mention skipped
import, export, drums, or 8D unless the user asked for those.

Method, not a catalog: a request for something faster and higher-pitched
implies project.set_tempo (preserve_pitch true) plus
clip.adjust_pitch_semitones plus a bright mix.apply_goal, not
clip.align_tempo_to_project. A slower, wetter, lower request implies
slower tempo and/or lower pitch plus a wetter mix.apply_goal. A spatial
or headphone-orbit request implies pan automation, not tempo, pitch, or
a static pan, unless the user also asked for those.
''';

const String aiV3AlignTempoCollapseRetryReminder = '''
The previous plan collapsed a production goal to
clip.align_tempo_to_project. Emit every Mixroom-supported implied
dimension of the original request (tempo, pitch, mix, spatial,
arrangement as the goal implies). Do not use
clip.align_tempo_to_project as a style substitute. Named single edits
and questions are unchanged.
''';

final RegExp _questionPrefix = RegExp(
  r"^(what(?:'s|s| is| are)\b|explain\b|how does\b)",
  caseSensitive: false,
);

final RegExp _questionPhrase = RegExp(
  r"\b(?:what(?:'s|s| is)|explain|how does)\b",
  caseSensitive: false,
);

final RegExp _mutationIntent = RegExp(
  r'\b(?:make|turn|convert|apply)\b',
  caseSensitive: false,
);

/// Goal syntax only. Does not match genre names or "make this louder".
final RegExp _productionGoal = RegExp(
  r'\b(?:make this (?:an? |into )?.{0,40}\b(?:remix|version)\b|'
  r'turn this into\b|'
  r'make it sound like\b|'
  r'as a .{0,40}\b(?:remix|version)\b)',
  caseSensitive: false,
);

bool _isNonMutatingQuestion(String normalized) {
  if (_questionPrefix.hasMatch(normalized)) return true;
  return _questionPhrase.hasMatch(normalized) &&
      !_mutationIntent.hasMatch(normalized);
}

bool looksLikeAiV3ProductionGoal(String originalRequest) {
  final normalized = originalRequest.trim();
  if (normalized.isEmpty || _isNonMutatingQuestion(normalized)) return false;
  return _productionGoal.hasMatch(normalized);
}

bool isAiV3AlignTempoOnlyPlan(AiV3Plan plan) {
  if (!plan.isMutating) return false;
  return plan.commands.every(
    (command) => command.type == 'clip.align_tempo_to_project',
  );
}

bool shouldRetryAiV3AlignTempoCollapse({
  required String originalRequest,
  required AiV3Plan plan,
}) =>
    looksLikeAiV3ProductionGoal(originalRequest) &&
    isAiV3AlignTempoOnlyPlan(plan);
