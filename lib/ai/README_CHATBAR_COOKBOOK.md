# AI Chatbar Cookbook (Exhaustive Prompt Examples)

Last updated: February 26, 2026

This is a practical prompt cookbook for the single chatbar UI, with one-sentence examples for every supported action family and operation.

## 1) Informational Mode (no edits)

- "What can you do in this DAW?"
- "Explain what a de-esser does in plain language."
- "Why does my mix feel muddy?"
- "Explain what changed in my mix after your last action."
- "Summarize all edits you made in the last request."
- "What does attack and release do on a compressor?"
- "How do EQ low-cut and high-cut differ?"
- "Analyze why my vocal sounds harsh without changing anything."

## 2) Mixing Mode (`mix_model_request`)

### 2.1 Direct command and interpretive prompts

- "Turn the vocals up a bit."
- "Pan track 3 to the right."
- "Make the mix sound wider and cleaner."
- "Make this chorus sound bigger and more polished."
- "Give me two mix approaches for this verse before applying."

### 2.2 Core mix intent kinds

- `gain`: "Raise the bass level slightly."
- `pan`: "Pan the rhythm guitar left."
- `eq`: "Cut muddiness on the piano."
- `reverb`: "Add more reverb to the lead vocal."
- `delay`: "Add a subtle delay throw on the vocal."
- `distortion`: "Add light saturation to the snare."
- `deesser`: "Tame sibilance on the vocal."
- `compressor`: "Compress the drums a little more."
- `limiter`: "Put a limiter on the master and keep peaks controlled."
- `clipper`: "Add a clipper on the master for a little more loudness and edge."
- `balance`: "Rebalance the track levels so vocals stay in front."

### 2.3 EQ descriptor-style requests

- `mud_cut`: "Remove mud from the low mids."
- `box_cut`: "Make the guitar less boxy."
- `boom_cut`: "Tighten boomy low end."
- `harsh_cut`: "Soften harsh upper mids."
- `presence_boost`: "Bring out vocal presence."
- `air_boost`: "Add more air on top."
- `warmth_boost`: "Add some warmth to this piano."
- `thin_fix`: "Make this thin vocal fuller."
- `dull_fix`: "Make this dull synth brighter and clearer."
- `low_cut`: "Roll off unnecessary low rumble."
- `high_cut`: "Reduce overly bright high-end fizz."

### 2.4 Scope and reset examples

- "Only mix track 2."
- "Mix the vocal track."
- "Balance all active tracks together."
- "Polish the whole master bus."
- "Start fresh and remix this section from scratch."

## 3) DAW Assistant Mode (`daw_assistant_actions`)

### 3.1 Tutorial highlight prompts

- `chatbar`: "Show me where to type commands."
- `toolbar`: "Show me the main toolbar controls."
- `transport:play`: "Show me where play is."
- `transport:record`: "Show me where to start recording."
- `transport:restart`: "Show me the restart/rewind button."
- `mute`: "Show me how to mute a track."
- `solo`: "Show me how to solo a track."
- `export`: "Show me where export is."
- `project_settings`: "Show me where project settings are."
- `plugins`: "Show me where to add plugins."
- `timeline`: "Show me where to edit clips on the timeline."
- `piano_roll`: "Show me where to edit MIDI notes."

### 3.2 Clarification-triggering prompts (when ambiguous)

- "Trim the clip."
- "Automate the filter."
- "Move it to the right."

### 3.3 Clip edit operations

- `trim`: "Trim the start of the selected clip."
- `auto_trim`: "Auto-trim silence from this podcast clip."
- `cut`: "Split this clip at the playhead."
- `stretch`: "Stretch this clip to double its length."
- `move`: "Move this clip one bar later."
- `tempo_follow`: "Make this loop follow project tempo."
- `auto_bpm_align`: "Auto-align all selected loops to BPM."
- `tempo_detect_set_project`: "Detect this clip tempo and set project BPM to it."
- `duplicate`: "Duplicate this clip after itself."
- `delete`: "Delete the selected clip."

### 3.4 Smart non-generative dialog/mistake editing

- `dialog_cleanup`: "Remove coughs and mouth noise from this spoken clip."
- `dialog_remove_range`: "Delete the sentence around 12.4 seconds."
- `dialog_tighten_pauses`: "Tighten long pauses in this podcast take."
- `dialog_lift_quiet`: "Lift the quiet spoken phrases so they are more even."

### 3.5 Automation lane and clip operations

- `set_points`: "Set volume automation points from 0s to 8s."
- `add_ramp`: "Add a fade-down ramp over the next 2 bars."
- `clear`: "Clear automation on this lane."
- `create_clip`: "Create an automation clip for this section."
- `duplicate_clip`: "Clone that automation clip to the next phrase."
- `move_clip`: "Move that automation clip 1 bar right."
- `delete_clip`: "Delete that automation clip."
- `clear_clips`: "Clear all automation clips on this lane."
- `mute_clip`: "Mute that automation clip."
- `unmute_clip`: "Unmute that automation clip."
- `toggle_clip_mute`: "Toggle mute for the selected automation clip."
- `set_clip_points`: "Replace points inside that automation clip with a new curve."
- `make_unique_clip`: "Make just this automation clone unique so I can change it separately."
- `apply_template`: "Apply a sidechain pump automation template here."

### 3.6 Automation templates

- `sidechain_pump`: "Create a pump curve over this buildup."
- `reverb_tail`: "Create a reverb tail rise and decay."
- `filter_sweep`: "Create a filter sweep into the drop."
- `sidechain_from_kick`: "Duck this pad everywhere the kick hits."

### 3.7 MIDI composition and editing

- `compose_bassline`: "Write a bassline for C-D-G-C."
- `compose_pattern`: "Generate a simple MIDI arp pattern for this chord loop."
- `replace_notes`: "Replace notes in the selected MIDI clip with this new phrase."
- `append_notes`: "Append a second phrase to the end of this MIDI clip."
- `chop_notes`: "Chop these MIDI notes into 16th notes."
- `chop_notes` with stutter controls: "Make 16th stutters with velocity decay and slight humanized jitter."

### 3.8 Stem separation

- `vocal_instrumental`: "Separate this audio clip into vocals and instrumental."

### 3.9 Role override actions

- `set`: "Set track 1 role to vocals."
- `clear`: "Clear role override for track 1."

## 4) Multi-action single-prompt examples

- "Trim silence on this vocal, then add a sidechain-style volume envelope from the kick."
- "Show me how to mute a track, then mute track 2."
- "Write a bassline for C-D-G-C and then chop it into 16th-note stutters."
- "Remove coughs from this spoken clip and tighten long pauses."
- "Detect tempo from this loop, set project BPM, and align the selected clips."
