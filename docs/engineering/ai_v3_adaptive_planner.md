# AI V3 Adaptive Planner Specification

Owner: AI Engineering
Status: Accepted design; adaptive domain capabilities remain shadow-only
Last reviewed: 2026-07-21

This is the decision-complete implementation specification for the scalable V3
planner described by [ADR 0002](adr/0002-ai-v3-architecture.md). The current
45-command one-shot prototype remains the user-visible baseline. Shared
capability slices update both planner surfaces through one canonical contract;
adaptive activation remains gated by the evaluations in this document.

## Objective and evidence

V3 must preserve one model's understanding of the original request without
sending every project detail and DAW operation on every turn. It must retain
Flutter-owned factual preparation, confirmation, atomic execution, rollback,
and readback.

The input profiler measured these current medium-state contributors:

| Contributor | Approximate tokens |
| --- | ---: |
| Clips | 3,825 |
| Historical complete 21-command schema | 3,599 |
| Rows | 1,951 |
| Library assets | 1,490 |
| Effect catalog | 1,297 |

Existing captures measured a V3 median of 13,468 provider input tokens versus
17,486 for V1. The synthetic maximum prototype envelope reached approximately
44,000 tokens. Flat context and command expansion therefore cannot be the
production scaling strategy.

### Decision status

| Item | Status |
| --- | --- |
| One semantic planner, immutable snapshot, all typed commands, one factual retrieval round, Flutter execution | Frozen architecture |
| Initial core and retrieval item limits | Implementation defaults; profile before production freeze |
| MusicSpec/provider boundary | Frozen architecture |
| Production realization provider | Deliberately selected by evaluation, not yet decided |
| Latency figures | Measurement objectives, not hard timeouts |
| Production model and reasoning effort | Selected by matched evaluation |

## Frozen architecture

```text
original request
+ immutable compact planning snapshot
+ every canonical typed command variant
+ compact capability-domain directory
                     |
                     v
               same GPT planner
          / submit final PlanV3               \
         /                                     \
        /          call get_context_domains    \
       /                       |                \
      /             one deterministic batched  \
     /               lookup against the same    \
    /                 immutable snapshot          \
   /                           |                    \
  /          original request + original core      \
 /             + request + typed facts               \
/             + the same command schemas              \
                           |                           /
                    same GPT planner                 /
                           |                         /
                      final PlanV3 <----------------
                           |
              fresh-state factual preparation
                           |
                  confirmation by policy
                           |
             atomic execution, readback, receipts
```

There is one semantic authority. Retrieval is deterministic data access, not
an intent model, selector model, specialist agent, validator, or repair call.

Initial limits are:

- zero or one retrieval round;
- one batched retrieval request containing at most four domain queries;
- at most 16 commands in the final plan;
- no mutation during planning or retrieval;
- no silent V1 fallback;
- no third planner call.

## Immutable planning snapshot

Flutter captures one `PlanningSnapshotV3` before the first planner call. It is
the sole source for the compact core and every retrieval result in that turn.

The snapshot contains:

- `snapshot_id`, project ID, project revision, state digest, and capture time;
- authoritative project, selection, row, group, clip, mixer, automation,
  analysis, catalog, file-browser, plugin, and capability state available at
  capture time;
- immutable indexes by stable resource ID;
- total counts and deterministic ordering for bounded collections.

The snapshot is held in memory for the planning turn and is not exposed as a
mutable editor object. Retrieval cannot read fresh Flutter state. If the user
or another action changes the live project during planning, the completed plan
still refers to the original digest and fails fresh-state preparation as stale.

Snapshots expire after the planner deadline or when the turn is cancelled.
They are excluded from persisted project data. Debug captures may serialize a
sanitized snapshot under existing opt-in capture rules.

## CompactCoreV3

The first call receives a deterministic, request-independent projection of the
snapshot.

### Always-present project fields

- snapshot ID and state digest;
- project ID, tempo, time signature, key, estimated key when available;
- playhead time and beat;
- current row and clip totals;
- current selection using stable IDs;
- row capacity and whether a row can be created;
- request mode and pending-plan identity when modifying a preview;
- latest eight valid conversation turns.

### Complete lightweight row index

For every row within the current application limit, include:

- stable row ID, display index, name, lane kind, and group ID;
- instrument identity when loaded;
- gain in dB, signed pan, mute, and solo;
- clip count and whether audio or MIDI content exists;
- loaded effect count, not parameter definitions;
- whether usable analysis is available.

The current application limit is 32 rows, so every row is represented. Raising
that product limit requires a new scale profile before changing this rule.

### Bounded lightweight clip index

Include at most 64 clip summaries, ordered deterministically:

1. selected clips;
2. primary selected clip;
3. remaining clips by start beat, row display order, and stable ID.

Each summary contains stable clip ID, parent row ID, type, name, start beat,
length, and source or instrument identity. The envelope also contains
`total_count`, `returned_count`, and `has_more`.

No MIDI notes, audio analysis arrays, trim/render internals, or detailed source
metadata are included in the core. Missing clip summaries are discoverable
through the clip or MIDI domain.

### Compact resource availability

The core contains counts, availability, and `has_more` for:

- instruments and hosted plugins;
- built-in effects and presets;
- indexed library assets;
- analysis results;
- automation targets;
- external audio services.

It includes stable identities only for resources currently loaded or selected,
within an envelope of 32 identities per resource category. It does not include
effect parameter definitions, the full asset catalog, plugin descriptions, raw
analysis features, or file-system paths.

### Explicitly excluded from the core

- complete MIDI note arrays;
- complete sample, plugin, preset, or effect catalogs;
- exposed effect parameter schemas;
- detailed automation points and clips;
- reference-track analysis features;
- raw audio-analysis vectors;
- external job payloads;
- uncommon command schemas;
- duplicated prose versions of structured facts.

Every bounded collection exposes counts and `has_more`. Nothing is silently
presented as complete when it has been truncated.

## Capability-transparent command surface

All canonical PlanV3 command schemas are supplied on both adaptive planner
turns. The following 13 remain the everyday/common subset used for reporting
and evaluation:

1. `project.set_tempo`
2. `row.adjust_gain_db`
3. `row.set_gain_db`
4. `row.adjust_pan`
5. `row.set_pan`
6. `row.set_muted`
7. `row.set_soloed`
8. `row.rename`
9. `clip.move_by_beats`
10. `clip.trim_to_range`
11. `clip.split_at`
12. `clip.duplicate_to`
13. `clip.delete`

“Common” no longer controls schema visibility. It describes operations that
normally need only CompactCore and should therefore finish in one call. It does
not mean low risk or automatic execution. Tempo, trim, split, and delete retain
factual preparation, confirmation, undo, rollback, and readback.

This list is changed only from measured usage and schema-cost evidence. A new
capability is not added merely because it is easy to expose.

## Capability-domain directory

The first call receives only the domain ID, one-sentence purpose, factual
availability, retrieval support, and resource counts. It does not duplicate
capability IDs, command names, command schemas, or detailed facts. The canonical
tool schema already makes every supported operation visible. Retrieval supplies
only missing immutable facts. `available` describes the current project;
`retrieval_enabled` describes implemented factual lookup. These meanings must
not be combined.

| Domain | Purpose | Current or planned capability |
| --- | --- | --- |
| `project_structure` | Transport, selection, row lifecycle, metadata, and grouping | V1 parity work |
| `clip_advanced` | Exact audio pitch plus later rendered, analysis-driven, tempo, dialogue, and multi-clip editing | Existing set/adjust pitch plus V1 parity |
| `midi` | MIDI notes, transcription results, and typed MIDI editing | Existing create/transpose plus V1 parity |
| `samples` | Bounded asset search, insertion, and replacement | Existing placement plus V1 parity |
| `effects` | Instances, catalogs, parameters, presets, and bypass/configuration | Existing three effect commands plus expansion |
| `automation` | Targets, points, ramps, clips, templates, and state | Existing gain fade plus expansion |
| `mix` | Mix analysis, groups, master state, reference state, and Mixroom engines | Existing `mix.apply_goal` |
| `music_generation` | Provider-neutral musical brief and realization capabilities | New evaluated boundary |
| `files_plugins` | File-browser entries, instruments, hosted plugins, and presets | Retrieval and later typed commands |
| `external_audio` | Stem separation, audio-to-MIDI, cleanup, rendering, and jobs | Staged workflows |
| `tutorial_ui` | Platform and UI capability facts for non-mutating help | V1 informational parity |

Several domain queries may be batched in the one allowed retrieval round. The
application does not infer or preselect a domain from the user's wording.

The adaptive planner instructions are capability-independent. They contain no
domain IDs, operation names, requested fields, or domain examples. New
capabilities extend the canonical command union once for both one-shot and
adaptive planning. Fact-heavy capabilities also extend the internal registry,
compact directory, strict query schema, and snapshot retriever without expanding
the prose prompt. Operation-specific semantics live in the relevant typed
command or query schema, never in the general instructions.

The permanent rule is: every implemented typed command remains visible, while
heavy factual state is retrieved only when needed. Retrieval never unlocks a
command and the domain directory never substitutes capability hints for the
actual strict command schemas.

The closed initial `requested_fields` registry is:

| Domain | Allowed requested fields |
| --- | --- |
| `project_structure` | `transport`, `history`, `row_details`, `groups`, `role_overrides`, `capabilities` |
| `clip_advanced` | `clip_details`, `transform_capabilities` |
| `midi` | `clip_notes`, `clip_instruments`, `edit_capabilities`, `transcription_status` |
| `samples` | `search_results`, `asset_metadata`, `placement_capabilities`, `replacement_capabilities` |
| `effects` | `instances`, `catalog`, `parameter_definitions`, `presets`, `target_capabilities` |
| `automation` | `targets`, `points`, `clips`, `templates`, `state` |
| `mix` | `row_analysis`, `group_state`, `master_state`, `reference_analysis`, `engine_capabilities` |
| `music_generation` | `provider_capabilities`, `roles`, `styles`, `destination_capabilities` |
| `files_plugins` | `file_results`, `instrument_catalog`, `plugin_catalog`, `preset_results`, `parameter_definitions` |
| `external_audio` | `job_capabilities`, `source_requirements`, `service_status` |
| `tutorial_ui` | `topics`, `visible_controls`, `platform_capabilities` |

Adding a field requires a typed result shape, an immutable-snapshot source, a
consumer, a result limit, and a size measurement.

## Retrieval contract

The first planner exposes two strict, mutually exclusive tools:

- `submit_plan_v3`, for a final `plan`, `respond`, `clarify`, or `unsupported`;
- `get_context_domains`, for the single batched read-only lookup.

Parallel tool calls are disabled and exactly one tool call is accepted. A
retrieval call uses this argument shape:

```json
{
  "schema_version": "context_request_v3_1",
  "requests": [
    {
      "request_id": "effects_for_vocal",
      "domain": "effects",
      "target_ids": ["row_vocal"],
      "time_range": null,
      "query_terms": [],
      "requested_fields": ["instances", "parameter_definitions"],
      "limit": 32
    }
  ]
}
```

Rules:

- one to four requests;
- every domain and requested field comes from a closed registry;
- target IDs must exist in the immutable snapshot;
- beat ranges must be finite and ordered;
- query terms are model-authored musical or factual search terms, never paths;
- the application clamps limits to each domain maximum;
- results return stable IDs, totals, returned counts, `has_more`, and sanitized
  typed facts;
- no arbitrary file access, network access, mutation, or executable plugin call;
- invalid retrieval requests fail explicitly and do not receive a repair call.

The retrieval tool uses a typed union of domain queries. It performs one batched
lookup and returns `ContextDomainResultV3` entries in request order. Retrieval
is a planner-turn outcome, not a PlanV3 outcome; PlanV3 remains exclusively a
final response or executable plan.

### Initial domain result limits

| Result | Limit |
| --- | ---: |
| Domain queries per round | 4 |
| Clip summaries | 64 |
| MIDI notes | 512 |
| Library search results | 32 per query, 64 total |
| Effect instances | 64 |
| Parameter definitions | 128 |
| Automation points | 512 |
| File/plugin/preset results | 32 per query, 64 total |
| Mix/reference targets | 32 rows plus master and groups |

Limits are safety envelopes, not claims that every maximum should be requested
together. Payload bytes and provider tokens remain recorded per domain.

## Planner continuation

The second and final planner call receives only:

- the original request verbatim;
- the original CompactCoreV3 and snapshot digest;
- the exact typed retrieval request;
- the returned typed factual results;
- command schemas for the common surface and requested domains;
- the pending plan and explicit modification request when applicable.

It does not receive hidden reasoning, a separately generated intent frame, a
selector summary, live state, or another model's interpretation. The second
call exposes only `submit_plan_v3`; `get_context_domains` is unavailable.

## Planner prompt

The prompt remains short and principle-focused. Its required meaning is:

```text
You are Mixroom's sole semantic and musical planner. Preserve the user's full
request. Use supplied stable IDs for project targets and treat supplied project
state as factual authority. Use general musical knowledge for interpretation
and planning, but never invent project resources or project state. Use only
commands supplied in this turn.
Respect explicit do-not-change constraints by limiting command targets and
write effects. Prefer a complete executable plan when the request is clear;
clarify only ambiguity that changes the result. Never invent resources.

On the first call, return a final response/plan when the compact context has the
facts needed to use the supplied commands. Otherwise request one bounded batch
of factual domains. On the continuation, use the original request, original
snapshot, and returned facts to produce the final result; no further retrieval
is available.

Own musical and semantic decisions. The application owns factual preparation,
confirmation, execution, and verification. Never claim an unexecuted plan was
applied. Match the language of the latest user request.
```

Operation descriptions stay in typed schemas and domain metadata. Do not add
request examples, language-specific regexes, case-specific prompt rules, or a
growing operation manual to the system prompt.

## Music generation boundary

Production music generation uses a provider-neutral typed `MusicSpecV3` rather
than requiring GPT to emit hundreds of raw notes.

GPT owns:

- style traits without copying a protected composition;
- mood, energy, density, and arrangement sections;
- key, scale, meter, tempo relationship, and harmonic plan;
- roles, instrumentation constraints, register, groove, and interaction with
  existing material;
- preservation constraints and desired variation.

`MusicSpecV3` contains bounded structured fields for those decisions plus
length, target destinations, provider capabilities, and a deterministic seed
when reproducibility is requested.

A realization provider returns a `GeneratedMusicBundleV3` containing exact
MIDI notes, drum/sample events, provenance, provider version, seed, and preview
metadata. The first evaluated providers are:

1. GPT-authored compact pattern specifications with deterministic expansion;
2. curated/deterministic pattern realization;
3. a hybrid GPT brief with provider-owned realization.

The provider interface is stable while the implementation is selected through
blind musical evaluation. Raw GPT note-by-note composition remains experimental
and preview-only until it proves competitive. Exact user-requested MIDI editing
is not routed through the music provider.

The provider-neutral boundary requires these fields without prescribing one
provider's internal representation:

| `MusicSpecV3` field | Meaning |
| --- | --- |
| `schema_version`, `spec_id` | Versioned stable request identity |
| `project_digest` | Snapshot against which the music was planned |
| `length_bars`, `start_beat` | Bounded placement requested from advertised provider limits |
| `key`, `scale`, `meter`, `tempo_bpm` | Tonal and metric facts; nullable only when intentionally atonal/free-time |
| `style_tags`, `mood_tags` | At most eight compact tags each |
| `sections` | At most 16 ordered section IDs, beat ranges, functions, energy, and density |
| `roles` | At most 16 provider-advertised musical roles with destination and instrument constraints |
| `harmony` | Ordered harmonic rhythm and chord/degree plan when applicable |
| `groove` | Swing, syncopation, humanization, and rhythmic-density targets |
| `relationships` | How generated roles support or avoid existing stable clip/row IDs |
| `seed` | Optional deterministic realization seed |

`GeneratedMusicBundleV3` contains the originating spec ID and digest, exact
bounded events, destination bindings, provider ID/version, seed, warnings, and
preview duration. It cannot mutate the project; its result is prepared and
previewed like any other generated resource.

Local synchronous realization may join the final local transaction. Slow,
remote, or audio-generating providers use the staged-job workflow.

## Preparation, execution, and safety

The existing V3 boundary remains authoritative:

1. Strictly parse the final PlanV3.
2. Recheck the original snapshot digest against fresh Flutter state.
3. Prepare every command using operation-local factual handlers.
4. Reject the whole local bundle if any command cannot prepare.
5. Apply the deterministic command policy: the current reversible commands
   execute immediately, while an explicit future `confirm` command uses the
   pending confirmation path.
6. Execute local work as one transaction.
7. Read back every affected property and compare expected state.
8. Roll back the complete bundle after any failure or mismatch.
9. Generate mutation success messages from receipts.

Preparation may resolve IDs, check capabilities, convert units, bind local
references, and materialize existing Mixroom model output. It may not reinterpret
text, replace targets, drop commands, rewrite musical intent, or repair plans.

External work is always staged:

```text
plan and confirm job
-> start with progress and cancellation
-> receive result
-> revalidate project
-> preview result
-> apply in a separate local transaction
```

## Failure behavior

Failures are explicit, non-mutating, and attributable:

- `planning_snapshot_unavailable`
- `planning_snapshot_expired`
- `context_request_invalid`
- `context_domain_unavailable`
- `context_result_limit`
- `planner_timeout`
- `planner_contract_invalid`
- `plan_stale`
- existing preparation, execution, rollback, and verification codes

Missing factual information may produce a targeted clarification. Unavailable
product capability produces `unsupported`. Transport retries remain bounded and
must not become semantic replanning.

## Performance and complexity budgets

Latency is an evaluation target, not a rigid architecture constant:

- common one-shot planning: target median under 5 seconds and p95 under 10;
- one-round planning: target median under 15 seconds and measure p95 around 20;
- record first call, retrieval, second call, preparation, and total separately;
- show progress and allow cancellation when interaction exceeds the normal
  one-shot window;
- set the production deadline only after matched real-device measurement;
- external jobs are excluded from interactive planner latency.

Every call records serialized bytes, provider input/output/reasoning tokens,
cost, cache usage, and latency. No fixed token percentage versus V1 is a release
requirement; verified success and practical latency/cost are the gate.

Complexity rules:

- no selector, intent, critic, or repair model in the mutation path;
- no more than one retrieval continuation initially;
- no semantic central validator;
- no request-dependent deterministic context packing;
- no generic legacy action map;
- no domain field or command without an owner and measured consumer;
- no common-schema expansion without usage and token evidence;
- no provider-specific composition contract exposed to GPT;
- no silent fallback.

## Implementation sequence

### A. Freeze and characterization

- Keep the current 45-command one-shot prototype operational behind its flag.
- Add golden serialization tests for its request and verified workflow captures.
- Freeze this specification and the machine-readable adaptive boundary.

### B. Immutable snapshot and compact core

- Capture `PlanningSnapshotV3` from authoritative Flutter state.
- Implement CompactCoreV3 exactly as specified.
- Compare it with current context in shadow without changing planner routing.
- Prove deterministic serialization, bounds, stable identities, and stale-state
  behavior on small, medium, and maximum fixtures.

### C. Common one-shot planner

- Expose only the exact 17 common commands and compact domain directory.
- Run shadow comparisons against the current V3 planner on common edits.
- Require no targeting, preservation, execution, undo, or readback regression.

Corrected shadow result (2026-07-20): after waiting for complete fixture state
and comparing actual editor state rather than selection-sensitive fingerprints,
the unchanged 18-case run passed 18/18 for both current and compact V3. Compact
requests were smaller in every case, averaging 2,871 provider input tokens
versus 11,510. No project mutation occurred and activation was not performed.

### D. One-round retrieval

- Add the `get_context_domains` first-call tool, snapshot-backed retrievers, and
  the final continuation.
- Keep every canonical command visible on both calls; domains provide facts,
  not command authorization.
- Prove zero live-state reads and zero third calls.

Capability-transparent revision (2026-07-21): adaptive surface revision
`full_commands_fact_retrieval_v1` exposes all 23 canonical commands on both
turns. CompactCore no longer repeats executable capability IDs or command names.
Domain retrieval remains typed, bounded, immutable, and limited to one batch;
returned-result provenance is enforced only for domains actually requested.
The active one-shot planner and shared factual preparation/execution path remain
unchanged.

Fresh 10-case gate (2026-07-21): the initial report scored one-shot 6/10 and
adaptive 4/10. Inspection found two evaluator defects: it expected `name`
instead of the canonical `new_name`, and it required a CompactCore-visible
sample to have been retrieved even though no samples query occurred. After
correcting only the evaluator, the evidence is one-shot 7/10 and adaptive 6/10.
Adaptive first calls used 49,916 provider input tokens versus one-shot's
109,363; adaptive total input including two continuations was 62,648. Aggregate
model latency was 46.7 seconds versus 32.1 seconds. Both systems shared misses
on relative-versus-absolute pan and unusable reference handling; adaptive alone
used absolute rather than relative gain in one case. The boundary therefore
remains shadow-only and does not pass activation. A separate fresh multilingual
automation regression passed for both planners in one call, confirming that
always-visible commands removed that earlier false-unsupported failure without
requiring retrieval.

MIDI slice result (2026-07-20): the first snapshot-backed retrieval slice is
implemented behind `AI_V3_ADAPTIVE_SHADOW_ENABLED` and remains detached.
The frozen 12-case run passed 12/12 for adaptive MIDI versus 11/12 for the
then-current 21-command planner, with four one-call common cases and eight two-call
MIDI cases. No project mutation, third call, invented target, or preparation
failure occurred. Activation was not performed.

Production routing does not change this boundary. Updated clients may use the
authenticated one-shot V3 endpoint, but adaptive V3 remains explicitly
disabled, detached, and incapable of supplying or executing the visible plan.

Phase E1 shared audio-pitch slice (2026-07-21): one-shot and adaptive V3 now
share `clip.set_pitch_semitones` and `clip.adjust_pitch_semitones`. Adaptive
loads them through immutable `clip_advanced` retrieval; preparation converts
both forms to the same absolute editor operation, with exact readback and
transactional rollback. The general adaptive prompts remain unchanged.

Phase E2 shared audio-stretch slice (2026-07-21): both planner surfaces now
share `clip.set_timeline_length_beats` and `clip.scale_timeline_length`.
Adaptive reuses immutable `clip_advanced` facts; factual preparation converts
both forms to one absolute non-destructive stretch operation. Execution,
rollback, Undo/Redo, and exact readback remain Flutter-owned, and neither
general planner prompt changed.

Phase E4 shared clip-boundary slice (2026-07-22): one-shot and adaptive V3
share `clip.trim_silence` and `clip.align_first_sound`. A single request-local
waveform analysis is materialized into exact existing trim or move actions
before confirmation. CompactCore and both general planner prompts remain
unchanged; adaptive reuses the existing `clip_advanced` domain.

The six-case E2 shadow smoke produced the intended prepared final state in
five cases for each planner. Both planners made the same isolated error on an
already-stretched clip: they halved its raw length instead of its visible
timeline length. The legacy command-form scorer reported one-shot 4/6 and
adaptive 3/6 because it rejected equivalent absolute commands where a relative
command was expected; factual review gives both 5/6. Adaptive completed every
case in one call and used 31,672 provider input tokens versus one-shot's 66,824,
with 25.1 seconds aggregate model latency versus 20.9 seconds. No prompt rule,
repair, or activation change was added for the shared model miss.

Step 2.5 genuine-project gate (2026-07-20): a separate 12-case run across the
saved duplicate-name, MIDI-heavy, and mixed projects scored adaptive MIDI 10/12
versus current one-shot V3 8/12. Adaptive used 74,432 input tokens versus
148,906, with zero wrong targets, invented resources, preparation failures, or
third calls. The gate did not pass: two of three relational music requests used
`limit: 1`, received incomplete source notes, and safely clarified. This is one
repeated retrieval-contract ambiguity—the field is bounded but does not state
that it limits returned notes rather than matched clips. Keep adaptive detached;
make only that field-semantics correction and rerun new relational cases before
domain expansion or activation.

Post-correction smoke (2026-07-20): the retrieval schema now states that `limit`
is the maximum number of MIDI notes returned. In three new relational cases, all
note-bearing requests used sufficient limits (`256` or `512`) and returned every
matched note. Adaptive and one-shot each passed 1/3. One adaptive miss omitted
the needed note field entirely, and one request caused both systems to clarify
unnecessarily. No prompt rule or repair was added. Keep adaptive detached: the
specific limit ambiguity is resolved, but this result does not justify activation
or retrieval-domain expansion by itself.

Historical built-in effects slice (2026-07-21): the adaptive boundary then
accepted one
batched request containing MIDI and/or built-in-effect queries. Effects lookup
is deterministic and reads only the immutable planning snapshot. It can return
existing row instances, the built-in catalog, normalized parameter definitions,
and target capabilities; its continuation exposed only the command schemas for
the domains actually requested. The later capability-transparent revision
supersedes that visibility rule. The active one-shot route, effect preparation,
and executor are unchanged. Hosted-plugin discovery, presets, activation, and
live evaluation remain deferred.

Genuine-project smoke (2026-07-21): seven requests were run against the saved
mixed audio/MIDI project without applying any plan. Current one-shot and
adaptive each passed 6/7 strictly. Adaptive correctly prepared add/configure,
bypass, remove, and combined MIDI/effect plans; common edits remained one call.
Its completed calls plus the failed first call used 40,523 provider input tokens
versus 89,577 for one-shot. The run exposed two general contract defects: loaded
effect values were returned in native units while labelled normalized, and an
unscoped catalog/capability query was rejected despite not requiring an instance
lookup. Both received narrow deterministic corrections and focused tests. A
fresh live rerun is still required before declaring the effects slice passed;
the attempted hot reload was invalidated by an unrelated Flutter semantics
assertion. No request-specific planner rule was added.

Sample retrieval slice (2026-07-21): the same general adaptive boundary now
supports bounded sample-library lookup from the immutable snapshot and exposes
the existing `sample.place` command only on the continuation. Search is
deterministic and lexical over factual filename, role, and BPM metadata; paths
are never returned to the model. Replacement, semantic audio search, file
browser access, prompt changes, execution changes, activation, and live-model
evaluation remain deferred.

Gain-automation slice (2026-07-21): adaptive retrieval now exposes exact
row-volume automation points and factual gain-fade capabilities from the
immutable snapshot. The continuation can use the existing
`automation.gain_fade` command only for rows returned by that retrieval. The
general prompts, active one-shot route, preparation, executor, and broader
automation surface remain unchanged. In the six-case live shadow run, one-shot
passed 6/6 and the first adaptive run passed 3/6 because the model sometimes
treated an absent first-call command as unsupported instead of retrieving its
advertised domain. The retrieval tool contract was clarified once, in
domain-neutral language, to state that requested domains expose their typed
commands on the final call. Focused fresh reruns raised the composite adaptive
result to 5/6. The remaining miss was a harmless false clarification between
row-volume and mix-gain automation in a compound request; there were no wrong
targets, invented resources, preparation failures, mutations, or third calls.
Across the composite run, adaptive used 32,056 provider input tokens versus
65,061 for one-shot, but took 38.9 seconds of aggregate model time versus 18.7
seconds. The slice remains shadow-only and is not yet marked as matching the
one-shot reliability gate. No request-specific rule or semantic repair was
added. A later domain-neutral clarification made the retrieval contract state
that a continuation may combine requested-domain commands with common commands
in one complete plan. Three fresh real-app compound checks (gain + fade, pan +
fade, and rename + fade) then passed 3/3 for both adaptive and one-shot. All
adaptive plans used one automation retrieval round, preserved command order,
and prepared successfully. Adaptive used 20,723 provider input tokens versus
33,302 for one-shot, with higher aggregate model latency (20.9 seconds versus
12.1 seconds). No preview was applied.

Mix retrieval slice (2026-07-21): the registry-backed adaptive boundary now
exposes the existing `mix.apply_goal` command after one immutable lookup of
bounded row, group, master, reference, and engine facts. GPT still receives no
raw analysis vectors or concrete `MixAction`s; the existing Flutter
materializer continues to own LocalMixingModel and optional local/remote
refinement. Shared audio facts now distinguish clip presence, usable signal,
available analysis, and reference suitability, so silent or unanalyzed material
cannot qualify as a reference. Focused deterministic coverage passed.

Genuine-project mix gate (2026-07-21): disposable saved projects with real
imported audio covered common, row, all-row, master, group, compound,
reference, and unusable-reference requests without applying a preview. The
initial run exposed two general retrieval-contract gaps: target-free master
facts were rejected when the model also requested empty reference facts, and
the compact directory did not distinguish the supported mix scopes clearly
enough. These received schema/directory corrections without changing either
general planner prompt. Focused tests remained green. In the three targeted
post-correction categories, adaptive correctly prepared group mixing and exact
gain plus row mixing on their first attempts. The effect-plus-mix case chose
direct Reverb plus EQ once, then used effects plus `mix.apply_goal` when
repeated unchanged. All successful mix goals reached the existing Mixroom
materializer and packaged learned refinement route. There were no wrong
targets, invented IDs, preparation failures, mutations, or third calls.
Adaptive used 25,842 provider input tokens for the three passing targeted
captures versus 33,933 for one-shot, with the expected additional latency from
its second model call. Keep the slice shadow-only: the single direct-EQ model
choice is recorded as stochastic evidence and does not justify a prompt rule,
but the run is not a claim of production activation.

### E. Domain expansion

- Port remaining V1 capabilities by domain from the capability inventory.
- Keep exact local edits typed and transactional.
- Integrate existing local/ONNX/remote mixing and reference protection through
  the mix domain rather than recreating them.
- Add external audio capabilities only as staged jobs.

### F. Music generation evaluation

- Implement `MusicSpecV3` and provider interface.
- Compare the three initial realization approaches on identical projects.
- Score structure automatically and musical usefulness through blind listening.
- Select a production default only after evidence.

### G. Activation

- Freeze schemas and prompts for a sealed evaluation.
- Compare adaptive V3 with matched V1 and frozen V2 on verified project state,
  musical quality, tokens, cost, latency, and repeated-run stability.
- Progress from shadow to internal opt-in and limited rollout only after zero
  critical wrong-target, preservation, or partial-commit failures.

## Acceptance criteria

- Common edits normally complete in one planner call.
- Detailed work uses at most one batched retrieval round.
- Retrieval reads only the immutable snapshot.
- Every final plan is tied to the original digest and checked against live state.
- No common or domain command uses fuzzy authoritative targets.
- No retrieval or preparation component changes musical intent.
- The complete V1 capability inventory has a common, domain, staged-job,
  respond-only, or intentionally unsupported disposition.
- Compact-core and schema sizes remain measured in CI fixtures and local
  captures.
- V3 beats matched V1 on verified outcomes before replacing it.
- Creative generation is judged by listening, not structural JSON alone.

## Explicit non-goals

- Multiple semantic agents or LangGraph orchestration.
- An open-ended tool loop.
- Automatic per-request model routing.
- A second LLM that selects context.
- A general semantic validator or LLM repair path.
- Direct GPT mutation tools.
- Claiming all external work is atomic.
- Achieving V1 parity by placing all 87 legacy operations in one schema.
