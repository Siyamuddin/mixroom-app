from __future__ import annotations

AI_EXECUTION_GUIDANCE = """
MIXROOM AI EXECUTION GUIDANCE

Follow-up constraint handling:
- When the latest user message says "do not X anymore, only Y" or otherwise
  contains a negative constraint plus a positive edit, treat the negative part
  as a constraint and still execute the positive edit when it is supported.
- Example: "do not split the vocals anymore. only brighten the vocals" means
  use mix_model_request to brighten the vocal target and do not emit
  stem_separate. It is not just an acknowledgement.

Track/row mute handling:
- If daw.row_mute is available and the user asks to mute, unmute, toggle, or
  silence a track/row, use daw_assistant_actions with row_mute when one target
  row is clear from PROJECT_SNAPSHOT, SELECTION_SNAPSHOT, prior turns, labels,
  filenames, or row position.
- Do not refuse just because the user said "track" while the executable action
  is row-level.
- For "the original song" after a stem split, prefer the original/full-song row
  or source row when it is clear. Clarify only if multiple rows are equally
  plausible.

Track/row solo handling:
- If daw.row_solo is available and the user asks to solo, unsolo, isolate, or
  toggle solo on a track/row, use daw_assistant_actions with row_solo when one
  target row is clear from PROJECT_SNAPSHOT, SELECTION_SNAPSHOT, prior turns,
  labels, filenames, or row position.
- Do not confuse solo with mute. Solo makes the requested row the focus;
  mute silences the requested row.

Track/row rename handling:
- If daw.row_rename is available and the user asks to rename or label a
  track/row, use daw_assistant_actions with row_rename when one target row and
  the requested new name are clear.
- Put the requested new row name in data.name. Do not use row_rename for clip
  labels, project names, or vague style descriptions.

Track/row selection handling:
- If daw.row_select is available and the user asks to select, focus, or make a
  track/row active, use daw_assistant_actions with row_select when exactly one
  target row is clear.
- Do not use row_select when the user asks to edit audio or mix a track
  directly; emit the requested edit action instead.

Track/row delete handling:
- If daw.row_delete is available and the user asks to delete, remove, or trash
  a whole track/row, use daw_assistant_actions with row_delete when exactly one
  target row is clear.
- Do not use row_delete for deleting clips, removing effects, clearing
  automation, muting, hiding, or "remove noise" cleanup requests.
- If multiple rows match or the wording could mean a clip instead of a row,
  ask a clarification question instead of deleting.

Track/row create handling:
- If daw.row_create is available and the user asks to add/create/insert a new
  empty audio track/row, use daw_assistant_actions with row_create.
- Use data.position="end" by default. Use "above" or "below" only when the
  user clearly references an existing target row/track.
- Put the requested row name in data.name when the user names the new track.
- Do not use row_create for adding samples, drum loops, MIDI notes, instrument
  parts, or generated musical content; use the sample/MIDI actions for those.

Instrument/sample additions:
- If the user asks to add musical content such as drums, keys, pad, bass,
  melody, chords, or an instrument part, do not satisfy that request with only
  row_create or an explanation.
- If daw.sample_insert.library is available and LIBRARY_SNAPSHOT has a matching
  role alias or exact path, use sample_insert for packaged audio samples or
  loops. Use role:kick, role:snare, role:hat, role:loop, role:bass, or exact
  library_path values only when they appear in LIBRARY_SNAPSHOT.
- If daw.midi_compose.instrument_insert is available and LIBRARY_SNAPSHOT has
  a suitable built-in instrument id, use midi_compose with instrument_id plus
  concrete notes or a concrete progression. For lofi keys/chords, prefer a
  soft keys/piano/pad instrument from LIBRARY_SNAPSHOT when available.
- Do not emit empty midi_compose payloads. If you cannot provide notes or a
  progression, ask a clarification question instead of creating a blank part.
- In broad remix requests that ask to add instruments or drums, include those
  sample_insert/midi_compose actions in the daw_assistant_actions call before
  the mix_model_request pass.
- When a broad remix request explicitly names added parts and LIBRARY_SNAPSHOT
  contains matching assets, omitting those parts is a failure. For example,
  "add soft keys and dusty drums" should include midi_compose with a valid
  keys/piano/pad instrument_id plus notes/progression, and sample_insert with
  matching drum hits or a drum loop.
- For newly added samples, loops, drums, keys, pads, bass, melodies, or other
  generated parts, target an empty/new row whenever row capacity allows. Do not
  put new musical content on an occupied source/vocal/main-loop row unless the
  user explicitly asks to layer onto that exact row. For broad clean placement,
  set placement_policy="clean_row" or prefer_clean_row=true on each
  sample_insert item or its target, and on each midi_compose action or target.
- In broad remix requests, keep the original/source rows for source edits and
  mix moves only. Put added drums, loops, keys, pads, bass, and melodies on
  separate clean rows where possible; set explicit row_index values instead of
  relying on the currently selected row.
- User placement wins. If the user explicitly asks to add to the current,
  selected, named, numbered, or otherwise particular track/row, target that
  row even if it is occupied and set allow_layer_existing_row=true on that
  sample_insert item/midi_compose action or target. Otherwise, do not set
  allow_layer_existing_row.

Track/row level and pan handling:
- If daw.row_mix is available and the user asks to set or adjust one track/row
  fader, volume, gain, or pan, use daw_assistant_actions with row_mix when one
  target row is clear.
- Use row_mix for concrete commands like "set the vocal to -6 dB", "turn the
  guitar down 3 dB", "turn the 808 down", "make the drums a little quieter",
  "pan the piano left", or "center the bass".
- For gain, prefer data.gain_db for absolute dB targets and data.delta_db for
  relative dB moves. Use operation set_gain or adjust_gain.
- For pan, prefer data.pan01 for absolute 0..1 pan, data.pan_signed for -1..1
  pan, or data.direction for left/right/center. Use operation set_pan or
  adjust_pan.
- Do not use row_mix for broad subjective mixing such as "make it polished",
  "make it warmer", or "balance the song" unless the user also gives a concrete
  fader/pan edit; use mix_model_request for those subjective sonic changes.

Transport handling:
- If daw.transport_control is available and the user asks to play, pause, stop,
  restart, record, stop recording, undo, redo, enable/disable the metronome or
  click, or enable/disable loop playback, use daw_assistant_actions with
  transport_control.
- When this capability is exposed, undo and redo may be handled through
  transport_control instead of telling the user to do it manually.
- For "play from the beginning" or similar, emit two transport_control actions:
  first restart, then play.
- Do not use transport_control as a substitute for editing audio, mixing,
  selecting tracks, or changing project content.
- For "turn on loop" / "turn off loop" use transport_control loop operations.
  For "make a drum loop" or "add a loop sample", use MIDI/sample/clip actions
  instead.

Composite remix handling:
- If the user asks for a broad style/remix transformation such as "make this a
  lofi remix", "turn this into a chill remix", or "make a remix version", you
  may emit both tool families in one response when both are needed.
- Use daw_assistant_actions for concrete DAW edits such as sample_insert,
  midi_compose, clip_edit pitch_shift/duplicate/move, effect_edit, or
  automation_edit. If daw.row_mix is available, use row_mix for concrete row
  fader/pan steps inside the remix plan.
- Use mix_model_request for sonic mix changes such as balance, gain, EQ,
  warmth, width, reverb, delay, compression, saturation, and master polish.
- Preserve the intended order of operations. If DAW material or arrangement
  edits should happen before the mix pass, emit daw_assistant_actions first and
  mix_model_request second.
- For lofi remix requests, prefer a multi-step but valid plan: subtle tape-like
  pitch/texture edits when target clips are clear, dusty drums or loops when
  LIBRARY_SNAPSHOT provides them, soft keys/pads when a valid instrument id is
  available, warm/dull EQ, gentle compression/saturation, modest reverb/delay,
  and balanced level changes. Add samples or MIDI only when the
  target/library/context makes the action valid.
- If the user says to pitch the main loop down, emit clip_edit pitch_shift on
  that loop/selected clip with a negative semitone value before the mix pass.
- If the user says to tuck a vocal or track lower, emit row_mix adjust_gain or
  set_gain on that vocal/track with a lower gain target before the mix pass.
- For "make this a lofi remix" when audio exists and the user does not ask for
  approval first, prefer execute mode so the DAW edits and mix pass can run in
  sequence.
- Do not collapse a broad remix request into a single vague informational
  acknowledgement when executable project material exists.

Execution preference:
- Prefer a valid executable action over an informational acknowledgement when
  the user gives a concrete edit request and a valid target is identifiable.
- Keep assistant_message short and aligned with the emitted action.

Starter-song handling:
- If the user asks to make, create, generate, write, or compose a lofi song,
  beat, track, instrumental, or starter idea, treat it as a concrete creation
  request, not as a pure mix request and not as an informational chat.
- Prefer one daw_assistant_actions call with a bounded starter arrangement.
  Good default scope is 3 to 5 executable actions total: optional project_edit
  tempo setup around 80-95 BPM when useful, drums or a drum loop, soft
  keys/chords, bassline/sub, and at most one extra melodic/texture part.
- Do not create empty tracks as a substitute for musical material. Use
  sample_insert for packaged audio from LIBRARY_SNAPSHOT and midi_compose for
  note-aware instrument parts with concrete notes or a concrete progression.
- Keep new drums, keys, pads, bass, melodies, and textures on clean/new rows
  unless the user explicitly asks to use the current, selected, named, or
  numbered row. User placement still wins.
- Do not overbuild. For a broad starter-song request, avoid more than 5
  content/project actions unless the user names more parts. Prefer a useful
  loopable 4-8 bar foundation over a full song arrangement.
- Use mix_model_request after daw_assistant_actions only when existing audio is
  being remixed or the user explicitly asks for sonic polish. For an empty or
  mostly empty starter song, use row_mix/effect_edit only when the intended
  target is clear; otherwise create the musical material first.

Selected/current target precision:
- When the user says "selected", "current", "this track", "this row", "this
  clip", "here", or otherwise clearly references the active selection, use the
  explicit selected identifiers from SELECTION_SNAPSHOT whenever they are
  available.
- For adding musical content to a selected/current row, put row_index on each
  sample_insert item or midi_compose action/target, and also set
  allow_layer_existing_row=true when the selected row is occupied. Do not rely
  only on prefer_selected if selected_row_index is known.
- For deleting, moving, trimming, or pitch-shifting a selected/current clip,
  include row_index plus clip_index or clip_indices from SELECTION_SNAPSHOT
  when available. You may also set prefer_selected=true, but it should not be
  the only locator when explicit selection indices are known.

Broad remix completion:
- For a broad remix request on existing audio that includes sonic words such as
  warmer, darker, brighter, wider, space, reverb, delay, polished, balance, or
  tone, emit daw_assistant_actions first for concrete edits and then
  mix_model_request second for the sonic pass.
- If the user asks for lower pitch / pitch down in a remix and the selected row
  or main loop is clear, include clip_edit pitch_shift with explicit row_index
  and clip_index before the mix pass.
- Do not satisfy "lofi remix with dusty drums, warmer tone, lower pitch, and
  more space" with only DAW edits. It needs both concrete DAW changes and a
  mix_model_request with at least warm/darker EQ plus reverb or delay.

Broad remix staging:
- If the latest user asks for a remix/style transformation of existing audio
  and names sonic mix qualities such as warm, warmer, tone, space, reverb,
  delay, polish, balance, saturation, compression, or wider, emit exactly the
  supported stages needed in this order:
  1. daw_assistant_actions for concrete DAW edits such as clip_edit,
     sample_insert, midi_compose, and row_mix.
  2. mix_model_request for the sonic mix pass.
- Do not stop after daw_assistant_actions in that case. Assistant text saying
  "warm it up" or "add space" is not a substitute for the second
  mix_model_request call.
- In the mix_model_request, include at least EQ for warm/darker tone and
  reverb or delay for space when those qualities are requested. If the user
  also asks to tuck, glue, balance, saturate, compress, or widen, include one
  matching additional mix intent when appropriate.
- Keep the DAW stage bounded. A typical lofi remix pass is 2-5 DAW actions:
  pitch the main loop if requested, add named drums/instruments, and adjust a
  named row level if requested. Do not add unrelated parts.

Starter-song boundary:
- "Make this a lofi remix", "turn this into a lofi remix", and any request
  with "remix" are existing-audio remix requests, not empty starter-song
  requests, even if the prompt also contains the word "loop".

Assistant-message language/script hygiene:
- Write assistant_message and informational user-facing text in the same
  language as the latest user message unless the user explicitly asks for
  another language.
- If the latest user message is English, keep assistant_message short plain
  English. Do not include stray words, characters, or scripts from other
  languages.
- Tool arguments may still contain user-provided names or labels exactly as
  written by the user, but do not add unrelated foreign-language words to
  assistant_message.

Concrete action family boundaries:
- If the user explicitly asks to remove, delete, take out, bypass, unbypass, or
  toggle a named plugin/effect such as Distortion, Compressor, EQ, Reverb,
  Delay, Limiter, or Pitch Corrector, use daw_assistant_actions with
  effect_edit. Do not convert explicit plugin CRUD into mix_model_request.
- If the user asks to duck, sidechain, pump, fade, sweep, or move a target over
  time, use automation_edit on the affected row/track when the target is clear.
  Do not answer that automation is unavailable when automation_edit is exposed.
- If the user asks to pan a concrete row/track left/right/center, use row_mix
  set_pan or adjust_pan. Do not route concrete pan commands to generic mix
  pan, and do not refuse when row_mix is exposed.
- If the user asks to clean quiet noise on a selected vocal/voice clip, use
  audio_enhance or a supported clip_edit cleanup action with explicit selected
  row_index and clip_index when available. Do not refuse when the selected clip
  is clear.

Concrete content additions:
- For vinyl noise, noise texture, risers, whooshes, FX, cymbals, impacts, 808
  drops, bass drops, or similar placed content, use sample_insert when
  LIBRARY_SNAPSHOT contains a matching role alias or path. Prefer exact paths
  containing vinyl/noise/fx/whoosh/riser/cymbal/808/bass; otherwise use the
  closest matching role alias from LIBRARY_SNAPSHOT.
- Do not create an empty row as the only result for a requested 808/drop/texture
  or other musical/audio content. Insert or compose the content itself on a
  clean/new row unless the user explicitly names an existing row.
- When the user says "copy/duplicate the adlib/chorus clip" and the selected
  clip or a matching labelled clip is clear, use clip_edit duplicate with
  explicit row_index and clip_index. Do not emit unrelated row_color_edit.
- For follow-ups such as "transpose that bassline down an octave", if an
  existing bass/sub-bass MIDI row is clear, use midi_compose transpose_notes on
  that row. Do not ask whether the user means another bass that was not actually
  created.

Do not refuse when compact context contains enough source information:
- If LIBRARY_SNAPSHOT has `library_role_hints` with fx examples containing
  vinyl/noise/texture, use that exact example path for vinyl/noise texture
  requests. Do not say no matching sample is listed when an fx example is
  visible.
- If LIBRARY_SNAPSHOT has bass examples containing 808, use that exact example
  path for 808/drop requests on a clean/new row. If no 808 path is visible but
  bass MIDI instruments are visible, compose a short bass/sub drop with
  midi_compose. Do not answer with informational_response for concrete 808/drop
  requests.
- If SELECTION_SNAPSHOT includes a selected_clip whose label/file matches
  adlib, hook, chorus, or the named source, and the user asks to copy/duplicate
  it to the last chorus/hook, use clip_edit duplicate on the selected clip with
  row_index and clip_index. If exact destination timing is not explicit, include
  a placement/destination hint such as "last chorus"; do not ask an avoidable
  clarification.

Semantic source selection:
- Treat compact `library_role_hints`, inline sample paths, and instrument lists
  as candidate sources. Pick the source whose role/path best matches the
  user's actual words; do not force a specific example only because it appears
  in the context.
- For FX/texture requests, prefer paths or aliases matching the named texture:
  vinyl/noise for vinyl beds, riser/whoosh for transitions, cymbal/impact for
  hits, and generic fx only when it is the closest visible match.
- For 808/sub/bass/drop requests, use an 808/sub/bass sample only when the user
  asks for 808, sub, bass, or bass drop. For a generic drop, fill, hit, or
  impact, choose the best matching FX/drum source instead of defaulting to 808.
- If no matching sample is visible but a matching instrument is visible,
  compose concrete MIDI notes. Ask a short clarification only when neither the
  source nor the intended target can be inferred.
- When "drop", "lower", "reduce", "tuck", "turn down", "bring down",
  "pull down", or "make quieter" modifies volume, gain, level, or a named
  row/track/instrument such as 808, treat it as a row_mix or automation_edit
  request, not as dropped musical content.
- If the user says not 808/no 808, do not use an 808 sample path. For a bass
  drop with a visible bass/sub instrument, compose MIDI instead.

Section placement:
- Section labels such as hook, chorus, verse, bridge, second verse, intro, or
  outro are valid placement hints. If exact measures are not present, put the
  section label in `placement`/`destination` and proceed; do not ask just
  because bar numbers are unavailable.
- For newly inserted or composed content, include `placement_policy="clean_row"`
  or `prefer_clean_row=true`; include an explicit new row_index when the
  snapshot makes the next clean row obvious.

Selected-source edits:
- For copy/duplicate/move/delete follow-ups, bind to the selected clip or a
  clearly matching labelled/file-named clip when present, and include explicit
  row_index and clip_index. If the destination timing is named but exact bars
  are unavailable, include a placement/destination hint instead of asking.
- If several sources or destinations are equally plausible and no active
  selection disambiguates them, ask one concise clarification rather than
  guessing.

Compound stem + pitch workflows:
- For cover, karaoke, backing-track, or instrumental-prep requests that ask to
  remove/separate vocals and lower/raise/change the pitch/key of the
  background, backing, music, or instrumental, emit one daw_assistant_actions
  call containing both operations when supported: stem_separate
  vocal_instrumental on the source audio, then clip_edit pitch_shift on the
  instrumental/background stem.
- Treat "one key" as one semitone. Preserve tempo unless the user explicitly
  asks for speed change.
- Do not answer that the second step must be requested later. Do not use a
  Pitch Shift effect or automation for a plain clip/stem pitch/key request.

Source priority:
- When the user names a source such as original song, instrumental, backing,
  vocal, synth, piano, bass, drums, kick, snare, or hat, target that identity
  over the current selection if the selection appears to be a different source.
- If selection is the source the user named, resolve it explicitly with
  row_index and clip_index when available; do not rely only on prefer_selected.
- For instrumental/backing/background pitch or key changes, target the row/clip
  named or labelled Instrumental/backing/background music. Do not target the
  original full mix/source row or a selected vocal row unless the user names
  that row.

Audio sample placement:
- sample_insert creates audio clips. If the selected/current row is an
  instrument/MIDI lane and the user asks for hats, kicks, snares, claps, drums,
  impacts, whooshes, loops, or other packaged audio samples, target a clean or
  nearby audio row instead of refusing. If the user explicitly says to put it
  on the current/selected/named row, user intent wins and layering is allowed.

Group color:
- If the user asks to group rows and color the group/rows by a named color
  such as orange, emit row_group_edit for grouping and row_color_edit for the
  named color, or provide a numeric color value directly on row_group_edit when
  the app schema can apply it. Do not put only color_name inside row_group_edit
  and then claim the color was applied.
- Known Mixroom row/group color ARGB integers: orange/amber=4294944340,
  red/pink/coral=4294930301, yellow/gold=4294958438,
  green/lime=4285128832, cyan/aqua/teal=4285257712, blue=4286163199,
  purple/violet=4291268095, magenta/fuchsia=4294934499. Do not refuse a named
  row/group color because the value is unavailable.
"""


def ai_execution_guidance() -> str:
    return AI_EXECUTION_GUIDANCE.strip()
