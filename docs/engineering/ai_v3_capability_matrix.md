# V1 Capability Inventory and V1→V3 Matrix

Owner: AI Engineering
Status: Complete source audit; execution evidence remains capability-specific
Last reviewed: 2026-07-20

The machine-readable authority is
[`tool/ai_v3_eval/v3_capabilities.yaml`](../../tool/ai_v3_eval/v3_capabilities.yaml).
This page explains its architecture, capability matrix, evidence level, and V3
migration implications. Updating a V1 action, mix engine, model route, V3 command,
or capability claim requires updating both files.

## Audit boundary and evidence rules

This inventory is deliberately scoped to the **DAW project-chat AI and its
deterministic DAW entrypoints**. The standalone Video Editor AI has a separate
prompt, `video_editor_actions` contract, state model, and executor and is not
part of the V1-to-V3 DAW migration audited here.

The inventory traces behavior through:

```text
user request
→ V1 tool/schema or deterministic model entrypoint
→ proxy normalization
→ Dart normalization and routing
→ Flutter model/editor handler
→ execution, undo/rollback, and readback
→ tests and workflow captures
```

The canonical action contract contains 22 families and 87 operations, but it is
not the whole AI product. The audit separately includes top-level response
surfaces, the mix-goal contract, heuristic and learned mixing engines, concrete
mix executor actions, reference-track mixing, audio models, catalogs, context
analysis, and cross-cutting execution behavior.

Status meanings:

- `verified`: real editor execution, undo/rollback, and targeted readback have
  all been demonstrated.
- `implemented_unverified`: the route and handler exist and have some automated
  evidence, but the complete outcome has not been proven.
- `partial`: the capability exists but has a known incomplete boundary such as
  asynchronous files or non-atomic compound execution.
- `broken`: a reproducible defect prevents the intended behavior.
- `non_mutating`: response or UI behavior that intentionally changes no project
  state.
- `context_only`: analysis used by planning/mixing but not directly invoked as
  an edit.
- `unreachable`: declared code cannot be reached through the audited product
  route.
- `test_only`: an intentionally invalid or synthetic test token.

No capability is marked `verified` merely because its schema parses or a mock
test passes. No entry remains `not_audited`.

## V1 architecture

V1 has three GPT-facing response tools:

| Surface | Responsibility | Current evidence | Main limitation |
| --- | --- | --- | --- |
| `daw_assistant_actions` | Concrete project/editor operations, including ordered bundles | Proxy, Dart routing, action-flow tests, captures | Heterogeneous legacy payloads; no universal atomic rollback/readback |
| `mix_model_request` | Subjective sonic goals resolved by Mixroom models | Goal parsing, heuristic/reference tests, local/remote resolver tests | Quality and complete apply safety remain workflow-dependent |
| `informational_response` | Factual, educational, or musical response without mutation | Routing tests and captures | Accuracy depends on supplied context |

Tutorial and clarification behavior can also be represented in the legacy action
envelope. V1 can aggregate multiple concrete actions and can preserve an ordered
concrete-edit call followed by a sonic mix call. That ordering is functional but
is not one universal transaction when handlers or external files differ.

One-Button Mix is a separate user-facing entrypoint over the same V1 and mixing
stack. It sends a fixed professional-release request, uses a dedicated pre-run
confirmation, and then auto-applies the resulting `MixingResult`. Its current UI
contains one profile, and that selected profile is not included in the fixed
prompt sent to V1.

## Direct DAW capability matrix

All operations below are individual machine-readable entries with inputs,
aliases, target/context requirements, implementation route, evidence, status,
gaps, V3 disposition, phase, and dependency.

| Family | Operations | V1 assessment | V3 direction |
| --- | --- | --- | --- |
| `tutorial` | No operation token; legacy non-mutating family | Non-mutating | `respond`/tutorial context |
| `clarify` | No operation token; legacy non-mutating family | Non-mutating | `clarify` with stable identities |
| `project_edit` | `set_tempo` | Implemented; stretch outcome needs broader proof | Existing `project.set_tempo` |
| `transport_control` | `play`, `pause`, `stop`, `restart`, `toggle_play_pause`, recording start/stop/toggle, `undo`, `redo`, metronome enable/disable/toggle, loop enable/disable/toggle | Implemented; runtime-state dependent | V3 supports explicit final playback, restart, metronome, and loop state; recording and AI history remain excluded |
| `row_mix` | `set_gain`, `adjust_gain`, `set_pan`, `adjust_pan` | Implemented; legacy units/fields vary | V3 supports semantic dB set/adjust and signed exact/relative pan commands |
| `row_mute` | `mute`, `unmute`, `toggle` | Implemented | `row.set_muted` expresses the final Boolean state, including state-aware toggle requests |
| `row_solo` | `solo`, `unsolo`, `toggle` | Implemented | `row.set_soloed` emits an explicit final state from current context |
| `row_select` | `select` | Implemented UI state | Typed selection command |
| `row_rename` | `rename` | Implemented | Existing `row.rename` |
| `row_delete` | `delete` | Implemented; destructive rollback needs complete row snapshot | Typed lifecycle transaction |
| `row_create` | `create` | Implemented; legacy continuation binding is weaker | Typed create with transaction-local ID |
| `row_color_edit` | `set`, `clear` | Implemented but not separately advertised in the legacy capability field | Typed row metadata |
| `row_group_edit` | `create`, `remove_row`, `toggle_collapsed` | Implemented but not separately advertised in the legacy capability field | V3 uses stable group/row IDs, exact membership and final collapsed state |
| `clip_edit` | `trim`, `auto_trim`, `cut`, `stretch`, `pitch_shift`, `glue`, `move`, `tempo_follow`, `auto_bpm_align`, `align_first_sound`, `tempo_detect_set_project`, `duplicate`, `delete`, four dialogue operations | Local and rendering paths exist; rendering is not uniformly atomic | V3 supports exact move, explicit and automatic silence trim, first-sound alignment, split, single-copy duplication, delete, same-row transactional audio glue, absolute/relative pitch and stretch, explicit tempo-follow, local BPM alignment, and project tempo derivation; dialogue work remains staged |
| `sample_insert` | `insert_audio_clips`, `replace_audio_clips` | Implemented; large-catalog matching can be descriptive | `sample.place` and stable-ID `sample.replace` with adaptive shadow catalog lookup |
| `midi_compose` | `create_clip`, `compose_bassline`, `compose_pattern`, `replace_notes`, `append_notes`, `transpose_notes`, `convert_audio_to_midi`, `chop_notes` | Editing exists; raw composition quality unproven; transcription is model-dependent | V3 supports exact create, replace, bounded append, transpose, deterministic chop, and staged local Basic Pitch transcription |
| `effect_edit` | `add`, `remove`, `bypass`, `unbypass`, `toggle_bypass` | Implemented; hosted-plugin parameters lack one portable contract | Built-in ensure/configure plus exact row-instance remove and bypass; master/group instances remain deferred |
| `automation_edit` | points, ramps, clear, create/duplicate/move/delete/clear clips, clip mute state, unique clips, clip points, templates | Implemented with target-specific units | Existing gain fade with adaptive shadow point lookup, then target/clip IDs and typed parameter values |
| `stem_separate` | `vocal_instrumental` | Partial asynchronous ONNX/file workflow | `clip.separate_stems` with local staged Spleeter execution and atomic rollback |
| `role_override` | `set`, `clear` | Implemented metadata affecting later mixing | Typed analysis metadata |
| `audio_enhance` | `phone_mic_cleanup` | Partial legacy rendered-cache workflow | `row.apply_phone_mic_cleanup` verifies the audible row effect chain and clip metadata atomically; the legacy cache remains best-effort derived output |
| `mix_goal` | `mix_request` | Implemented route; contract alone hides the actual mix stack | Reuse mixing stack behind a typed V3 goal |

The automation template surface includes sidechain pump and kick-driven
sidechain variants, reverb tail, filter sweep, and auto-pan/stereo-motion
variants. The YAML records their accepted template aliases and source-target
requirements.

The YAML also records canonical legacy aliases. Important examples include
audio pitch/transpose aliases, sample replace/swap aliases, MIDI composition and
audio-to-MIDI aliases, automation clip aliases, row grouping aliases, and BPM
aliases. V3 should not inherit that duplicate Python/Dart alias boundary: its
planner should emit canonical typed commands directly.

## Mixing is a separate capability system

`mix_model_request` does not directly return editor actions. GPT returns one or
more `GoalVector` objects. Mixroom then performs:

```text
GoalVector
→ LocalMixingModel heuristic actions
→ optional learned apply/magnitude refinement
→ concrete MixActions
→ Flutter mix executor
→ MixApplyReport
```

### GoalVector surface

| Dimension | Supported values/shape |
| --- | --- |
| Intents | Closed kinds: `gain`, `pan`, `eq`, `reverb`, `delay`, `distortion`, `deesser`, `compressor`, `limiter`, `clipper`, `balance` |
| Directions | `up`, `down`, `left`, `right`, `center`, `widen`, `narrow`, `remove`, or `null` |
| EQ descriptors | `mud_cut`, `box_cut`, `boom_cut`, `harsh_cut`, `presence_boost`, `air_boost`, `warmth_boost`, `thin_fix`, `dull_fix`, `low_cut`, `high_cut`, or `null` |
| Target | `auto`, `row`, `group`, or `master`; role/index/group hints and confidence |
| Intensity | `0.0..1.0` |
| Execution profile | `producer_safe`, `creative_bold`, `experimental_extreme` |
| Audibility | `subtle`, `noticeable`, `obvious`, `extreme` |
| Reset policy | `reset_fx` is GPT-facing |
| Downstream-only fields | `style_tags` and `destructive_ok` are normalized downstream but are not declared in the current GPT tool schema |
| Reference | Separate target, mode, closeness, and confidence |
| Request mode | Proposal or execution |

The LLM owns semantic sonic intent. `LocalMixingModel` owns the factual
conversion to concrete gain, pan, effect, and master operations. Learned models
may decide whether to apply an action and refine its magnitude; they do not own
the natural-language interpretation.

### Reference-track mixing

Reference mixing is implemented and must not be reduced to generic EQ or level
requests. The processing and reference targets are resolved independently, and
the reference must not be mutated.

| Dimension | Values/behavior |
| --- | --- |
| Mode | `tone`, `loudness`, `width`, `glue`, `full_mix` |
| Closeness | `loose`, `balanced`, `close` |
| Targeting | Explicit row or selected reference, with confidence |
| Analysis | Uses reference features and whether the source resembles a full mix |
| Safety | Reference row is excluded from the processing target set |
| Remaining proof | Reference suitability and audible quality need audio-level evaluation |

### Mixing engines and routing

| Engine | Role | Selection/fallback |
| --- | --- | --- |
| `LocalMixingModel` | Deterministically derives candidate MixActions from project analysis and GoalVector | Always forms the heuristic base |
| Local ONNX refinement | Apply classifier plus magnitude regressor | Used when learned magnitudes are enabled and remote mode is off |
| Remote `/mix/resolve` refinement | Backend apply classifier plus magnitude regressor | Current default when learned and remote flags are enabled |
| Disabled/no-op refinement | Returns heuristic actions unchanged | Used when learned magnitudes are disabled or intentionally bypassed |
| Model manager | Downloads/refreshes model bundles or prefers bundled assets | Falls back when models are unavailable or invalid |

Source code identifies the learned artifacts as an ONNX apply classifier and an
ONNX magnitude regressor. This document does not call them a regression tree
without model metadata proving that algorithm.

The route records learned-model enabled/ready/bypassed state, model source and
version, fallback reason, heuristic and ONNX timings, action deltas, and apply
results where the relevant debug/capture flags are enabled.

### Concrete MixAction surface

| Target | Actions |
| --- | --- |
| Row | `set_row_gain`, `set_row_pan`, `ensure_effect`, `delete_effect`, `adjust_effect_param_by_name`, `hard_reset_row_fx` |
| Master | `set_master_gain`, `set_master_pan`, `ensure_master_effect`, `delete_master_effect`, `adjust_master_effect_param_by_name`, `hard_reset_master_fx` |
| Non-mutating | `noop` |
| Test-only invalid token | `invent_plugin` |

`hard_reset_row_fx` is supported by the model/executor but omitted from the
commented list in `mixing_result.dart`; the YAML records this discrepancy. The
negative-test `invent_plugin` token is explicitly `test_only`, not a product
capability.

## Other AI, audio, and resource capabilities

| Capability | Kind | Current path | V3 disposition |
| --- | --- | --- | --- |
| Spleeter two-stem separation | User-invokable local ONNX + file workflow | `stem_separate.vocal_instrumental` | Staged external/asynchronous workflow |
| Basic Pitch transcription | User-invokable local ONNX | `midi_compose.convert_audio_to_midi` | `clip.convert_to_midi` with staged local inference and atomic rollback |
| Phone-mic cleanup | Chat action or direct Capture Deck entrypoint; inserts a cleanup effect chain, stores preset metadata, and warms a rendered cache | `audio_enhance.phone_mic_cleanup` | `row.apply_phone_mic_cleanup` targets one stable audio row, preserves matching effect instances and parameters, and atomically verifies chain and metadata state |
| YAMNet instrument classification | Context-only local ONNX | Project role/source interpretation | Compact enriched context, not a direct edit command |
| Project mix analysis | Context-only deterministic analysis | Roles, confidence, tone, loudness, width, glue, effects | Stable-ID mix context |
| Sample/file-browser catalog | Context and resource catalog | Indexed assets used by sample insertion | Bounded identity catalog; retrieval only if scale proves necessary |
| Instruments/effects/plugins | Context and resource catalog | Runtime catalogs and project instances | Stable catalog/instance IDs; hosted parameters remain a later boundary |

## Cross-cutting behavior

| Behavior | Current assessment | V3 rule |
| --- | --- | --- |
| Target resolution | V1 supports IDs, indexes, names, roles, and selection; contradictions can drift across layers | Stable ID is authority; preparation rejects contradictions |
| Duplicate names | Resolved through additional hints/selection where possible | Full identity index; clarify only when identity remains ambiguous |
| Capability/platform gating | Proxy, Dart, and runtime all participate | Flutter-owned authoritative capabilities exposed to planner |
| Proposal/Apply/Cancel/Modify | Implemented with heterogeneous per-action policy | Prepared bundle tied to state digest; mutation always previewed in prototype |
| Compound ordering | Implemented, including create-then-insert and edit-then-mix | One local transaction with transaction-local IDs |
| Asynchronous/file work | Handler-specific and only partially atomic | Staged jobs with explicit state and compensating cleanup |
| Undo/rollback/readback | Exists per handler but is not universal in V1 | Required for every local V3 command slice |
| Observability | Captures model/tokens/cost/latency/fallback/actions where enabled | Preserve and add expected-versus-observed receipts |
| Legacy aliases | Duplicated across Python, `CloudLlmService`, `AssistantActionUtils`, and `AudioEditor`; automation `create` has conflicting meanings across layers | Do not reproduce in PlanV3 |

## Capture evidence

The current local corpus contains 34 V1 comparison captures. All three top-level
tool surfaces appear. Fourteen canonical operations appear in captured JSON:

- tempo;
- row relative gain, exact/relative pan, mute, rename, and create;
- clip move;
- effect add;
- automation ramp;
- sample insertion;
- MIDI create, replace notes, and transpose.

Captures are diagnostic evidence of model output and recorded workflow state.
They do not by themselves prove correct editor mutation, rollback, or audible
quality. The remaining 73 canonical operations are not declared broken; they
are simply absent from this capture set.

## V1→V3 migration order

1. Keep the existing typed V3 prototype and its stable-ID preparation,
   preview, local transaction, and readback boundary.
2. Add representative typed core editing slices: transport, row lifecycle/state,
   clip core, MIDI editing, effect instances, and general automation.
3. The `mix.apply_goal` vertical slice now integrates typed GoalVector,
   protected processing/reference IDs, the local heuristic model, optional
   local or remote magnitude refinement, existing MixActions, and apply report.
4. Decide the composition/music-provider boundary through evaluation rather
   than expanding raw note serialization blindly.
5. Add Spleeter, Basic Pitch, cleanup, and rendering as staged jobs rather than
   pretending they are immediate atomic commands.
6. Measure large projects/catalogs before enabling the optional single
   planner-owned retrieval round.

## Adaptive V3 capability placement

The authoritative adaptive-planner specification is
[`ai_v3_adaptive_planner.md`](ai_v3_adaptive_planner.md). It prevents V1 parity
from becoming one flat schema.

### Always-present common commands

These 13 commands form the everyday common-edit surface:

| Area | Commands |
| --- | --- |
| Project | `project.set_tempo` |
| Row | `row.adjust_gain_db`, `row.set_gain_db`, `row.adjust_pan`, `row.set_pan`, `row.set_muted`, `row.set_soloed`, `row.rename` |
| Clip | `clip.move_by_beats`, `clip.trim_to_range`, `clip.split_at`, `clip.duplicate_to`, `clip.delete` |

The remaining thirty-eight current commands are also visible to both planners, while
adaptive retrieval supplies their detailed domain facts only when needed:

| Domain | Current commands |
| --- | --- |
| Transport | `transport.set_playing`, `transport.restart`, `transport.set_metronome_enabled`, `transport.set_loop_enabled` |
| Project structure | `row.select`, `row.set_color`, `row.set_role_override`, `row.create`, `row.delete`, `group.create`, `group.remove_row`, `group.set_collapsed` |
| MIDI | `midi.transpose`, `midi.create_clip`, `midi.replace_notes`, `midi.append_notes`, `midi.chop_notes` |
| Samples | `sample.place`, `sample.replace` |
| Effects | `effect.ensure_configured`, `effect.remove`, `effect.set_bypassed` |
| Automation | `automation.gain_fade`, `automation.set_points`, `automation.clear` |
| Mix | `mix.apply_goal` |
| Advanced clips | `clip.set_pitch_semitones`, `clip.adjust_pitch_semitones`, `clip.set_timeline_length_beats`, `clip.scale_timeline_length`, `clip.set_source_tempo_bpm`, `clip.set_tempo_follow_mode`, `clip.align_tempo_to_project`, `project.set_tempo_from_clip`, `clip.trim_silence`, `clip.align_first_sound`, `clip.glue`, `clip.separate_stems`, `clip.convert_to_midi` |
| External audio | `row.apply_phone_mic_cleanup` |

The adaptive shadow exposes all fifty-three prototype commands from its first
call, including `mix.apply_goal`. Mixing retrieval supplies only bounded factual
row/group/master/reference information; the existing Mixroom heuristic and
learned refinement stack remains the sole producer of concrete MixActions.

### Complete capability-domain mapping

| Domain | V1/V3 capability groups |
| --- | --- |
| `project_structure` | Transport, history, recording, metronome, loop, selection, row creation/deletion/color/grouping, and role metadata |
| `clip_advanced` | Exact audio pitch, non-destructive timeline stretching, source-tempo metadata, explicit tempo-follow modes, automatic tempo/onset analysis, and same-row audio glue; later dialogue cleanup and broader multi-clip workflows |
| `midi` | Exact MIDI inspection/editing, append/replace/chop/transpose, and transcription results |
| `samples` | Catalog search, insertion, replacement, and transaction-local destinations |
| `effects` | Built-in and hosted instances, parameters, presets, add/remove/bypass/configure, row/group/master targets |
| `automation` | Points, ramps, targets, clips, templates, mute state, duplication, movement, and deletion |
| `mix` | GoalVector, groups/master, project analysis, LocalMixingModel, local/remote learned refinement, MixActions, and protected reference matching |
| `music_generation` | Provider-neutral briefs, arrangement, patterns, harmony, roles, and generated bundles |
| `files_plugins` | File-browser results, instruments, hosted plugins, and presets |
| `external_audio` | Stem separation, audio-to-MIDI, cleanup, rendering, and other staged jobs |
| `tutorial_ui` | Informational responses, tutorials, platform state, and UI guidance |

Every inventory entry must map to one of the common commands, one of these
domains, a staged external job, `respond`/`clarify`, or an explicit intentional
unsupported decision. Retrieval supplies immutable facts and domain schemas; it
does not execute or reinterpret the request.

## Gap report

- The canonical 87-operation contract does not describe the full mixing or
  audio-model architecture.
- V1 lacks universal atomicity and readback across heterogeneous and
  asynchronous compound work.
- Python and Dart both normalize legacy aliases and payloads, allowing drift.
- Automation `create` currently normalizes to `set_points` before routing but to
  `create_clip` in the final editor normalizer.
- Phone-mic cleanup undo covers inserted effects but does not explicitly restore
  enhancement metadata or remove its asynchronously rendered cache.
- Current captures cover only 14 canonical operations.
- Hosted plugin discovery and arbitrary parameters are broader than V3's current
  built-in effect command.
- Reference mixing is structurally implemented, but its audible quality still
  requires evaluation against real audio.
- Model presence and mock tests are not sufficient to mark capabilities
  verified.

The inventory is therefore complete as a map of current source behavior, while
remaining deliberately conservative about production verification.
