# AI Mixing Overview

This is a plain-English overview of how Mixroom's AI works today, what it can
cover, and where it is likely going next.

## The short version

Mixroom does not use one model to do everything.

Instead, it uses a layered system:

1. A language model understands the user's prompt.
2. The app builds a snapshot of the project.
3. Mixroom proposes candidate actions inside the DAW.
4. Learned models can filter and refine those actions.
5. The app applies the final result.

This makes the system safer and more controllable than letting one model guess
all audio changes directly.

## What each model does

### `yamnet.onnx`

File:

- [yamnet.onnx](../assets/models/yamnet.onnx)

Purpose:

- helps the app understand what kind of audio is in the project
- supports role/content understanding such as vocals, drums, bass, and similar
  categories

Simple description:

`yamnet` helps Mixroom understand the audio.

### `mix_apply_classifier.onnx`

File:

- [mix_apply_classifier.onnx](../assets/models/mix_apply_classifier.onnx)

Purpose:

- looks at a proposed mixing action
- decides whether that action should be kept or suppressed

Simple description:

this is the "should we do this?" model.

### `mix_magnitude_regressor.onnx`

File:

- [mix_magnitude_regressor.onnx](../assets/models/mix_magnitude_regressor.onnx)

Purpose:

- looks at a proposed action that survived the previous step
- decides how strong that action should be

Simple description:

this is the "how much should we do it?" model.

## How the current system works

The current design is a hybrid:

- the LLM understands user intent
- Mixroom logic proposes actions
- learned models refine those actions

For interpretive mixing prompts, the flow is:

1. The user asks for a change.
2. The LLM turns that into structured intent.
3. Mixroom analyzes the project and proposes candidate moves.
4. `mix_apply_classifier.onnx` removes weak or risky moves.
5. `mix_magnitude_regressor.onnx` adjusts the strength of the remaining moves.
6. The app applies the final actions.
7. The assistant explains what happened.

So:

- `yamnet` is for understanding audio
- the `mix_*` models are for refining mixing decisions

Right now, the learned mixing layer is mainly a corrective refinement layer:
it decides which proposed mix moves to keep and how strong they should be.
The overall architecture already supports broader stylistic behavior too, and
the next step is to train that behavior with clearer style-oriented data rather
than relying only on generic "good mix" examples.

## What data is sent to the cloud

This matters because some users and companies are sensitive about what leaves
the device.

Today, Mixroom's cloud LLM path sends a structured text payload to the backend
LLM proxy. It does not send raw audio media through this chat path.

Data sent in the cloud request:

- recent chat history, limited to a short rolling window
- the current user prompt
- a text `project_snapshot` built from project state, including:
  - BPM
  - per-track empty/non-empty status
  - clip file names
  - track gain and pan
  - top role probabilities such as vocals, drums, bass, guitar, synth
  - lightweight audio summary stats such as RMS, crest, spectral centroid,
    sibilance, bassiness, zero-crossing rate, high-frequency RMS, and transient
    density
  - track overlap relationships
  - effect names on each track
  - automation target names and ids
- a text `selection_snapshot`, when relevant, including:
  - selected row index
  - selected clip indices
  - primary selected clip index
  - selected clip timing, file name, row, clip kind, and label
  - selected row automation targets
- a pending proposed mix, if one exists, including summary, notes, and
  structured actions
- optional request metadata such as `project_id` and `ai_feature`
- optional analytics client context when analytics is enabled:
  - device id
  - distinct id
  - session id
  - app version
  - platform
  - environment
  - locale

Data not sent in this cloud chat path:

- raw audio files
- rendered stems
- waveform/sample buffers
- the full project file
- plugin state blobs
- full automation point data for the whole project
- local learned-model weights or internal inference state

Important architecture note:

- the cloud LLM is used for intent/tool selection
- the local mixing model still turns that intent into actual mix actions
- the local learned models still refine whether actions should be kept and how
  strong they should be

So the cloud sees a summarized project description, not direct audio content,
for the current chat-driven mixing flow.

## What kinds of prompts it can cover

The system is not only for one type of prompt.
In the broad sense, Mixroom aims to support:

- informational prompts
- mixing prompts
- DAW action prompts
- guided editing prompts

Examples:

- "What is wrong with my mix?"
- "Make the vocals clearer."
- "Tighten the low end."
- "Where is the export button?"
- "Show me how to edit MIDI notes."
- "Split vocals from instrumental."

Today, the system is strongest on:

- corrective mixing prompts
- DAW/tutorial prompts that map to known actions
- project-aware explanations

## Supported actions today

This is the current supported action space in the AI system.

### 1. Informational actions

The assistant can:

- explain mix problems
- explain plugin concepts
- explain what changed after an edit
- summarize previous actions
- answer DAW "how does this work?" questions
- analyze a mix without changing anything

### 2. Mixing actions

Inside mixing mode, the assistant can work through these action families:

- gain
- pan
- balance
- EQ
- compressor
- limiter
- clipper
- reverb
- delay
- distortion
- de-esser

`Clipper` is included as a mixing action because it is part of loudness and
transient control. `Pitch Shift` and similar creative processors are not in the
core mixing lane; they belong in editing or sound-design actions instead of the
main mixing model.

For EQ-style requests, it also supports common descriptors such as:

- muddy
- boxy
- boomy
- harsh
- bright
- thin
- dull
- sibilant
- warmth
- presence
- air
- low cut
- high cut

It can apply those actions at:

- track level
- multi-track level
- master level

It also supports:

- direct commands
- interpretive mixing prompts
- broad polish prompts
- reset/remix-from-scratch style requests

### 3. DAW assistant actions

The assistant can also drive non-mixing actions through the DAW assistant path.

Supported DAW assistant action types:

- tutorial
- clarify
- clip_edit
- automation_edit
- midi_compose
- stem_separate
- role_override

### 4. Tutorial and UI highlight actions

The assistant can guide the user to:

- chatbar
- toolbar
- play
- record
- restart
- mute
- solo
- export
- project settings
- plugins
- timeline
- piano roll

It also supports more specific drill-down guidance such as:

- row header
- row mute/solo
- row effects tab
- row volume tab
- row automation tab
- FX list
- add effect
- specific effect slot
- specific plugin parameter

### 5. Clip edit actions

Supported clip edit operations:

- trim
- auto_trim
- cut
- stretch
- move
- tempo_follow
- auto_bpm_align
- tempo_detect_set_project
- duplicate
- delete
- dialog_cleanup
- dialog_remove_range
- dialog_tighten_pauses
- dialog_lift_quiet

### 6. Automation actions

Supported automation operations:

- set_points
- add_ramp
- clear
- create_clip
- duplicate_clip
- move_clip
- delete_clip
- clear_clips
- mute_clip
- unmute_clip
- toggle_clip_mute
- set_clip_points
- apply_template

Supported automation templates:

- sidechain_pump
- reverb_tail
- filter_sweep
- sidechain_from_kick

### 7. MIDI actions

Supported MIDI operations:

- compose_bassline
- compose_pattern
- replace_notes
- append_notes
- chop_notes

### 8. Stem separation actions

Supported stem-separation operation:

- vocal_instrumental

### 9. Role actions

Supported role override operations:

- set
- clear

Supported role values:

- vocals
- drums
- bass
- guitar
- synth
- other

This supported action list is the reason Mixroom can cover a broad range of
prompts without forcing everything through one mixing model.

## What it cannot fully do yet

It still has real limits.

- It is not a perfect human mixer.
- It does not support every possible DAW operation yet.
- It is only as good as the app's current action set and audio engine support.
- The learned mixing stage is a refinement layer, not a full black-box
  "mix-from-scratch" system.

So even if a prompt is reasonable, the app may not yet support the exact action
behind it.

## Current beta reality

For beta, the safest interpretation is:

- prompt routing is broader than learned mixing
- the learned mixing model is only one part of the overall assistant

That means Mixroom can support many prompt types overall, even before one
single learned model covers all of them.

## Where this is likely going

The long-term goal is to support a very wide range of user prompts.

That does **not** mean one model should do everything.
The direction is:

- one assistant system
- multiple prompt types
- multiple internal stages
- broader learned conditioning over time

For mixing specifically, Mixroom will train one shared learned model that
covers both:

- corrective behavior
- artistic or stylistic behavior

But that only works well if training data clearly encodes the difference
between them.

In practice, the model needs conditioning such as:

- intensity
- corrective vs artistic intent
- style target
- genre or aesthetic direction

Without that, a single model can average conflicting tastes and become too
generic.

## Why training data matters

The learned system improves when it sees:

- what the AI proposed
- what a producer changed afterward
- which actions should have been kept
- which actions should have been removed
- which actions should have been weaker or stronger

Mixroom also trains for artistic behavior, with clear context.

For example, the data should distinguish between:

- "fix this problem"
- "make this more polished"
- "make this more aggressive"
- "make this warmer, bigger, dirtier, more vintage, more modern, etc."

## The most important limitation

The main limitation is not just model quality.
It is coverage.

To support all types of user prompts well, Mixroom needs:

- strong prompt routing
- a broad supported action set in the app
- good training data for both technical and artistic mixing
- clear conditioning so the learned model knows what kind of result the user wants

## One-sentence summary

Mixroom's AI is a layered assistant system: it understands the user's prompt,
understands the project, proposes actions, and uses learned models to refine
which mixing moves should happen and how strong they should be.
