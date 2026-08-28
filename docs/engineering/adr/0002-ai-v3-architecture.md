# 0002: AI V3 Uses One Semantic Planner And A Transactional Executor

Status: Accepted; server-owned context-only V3 deployed, Flutter cutover in
release-candidate verification

Date: 2026-07-17

Owner: AI Engineering

Update trigger: Revisit this record when the planner boundary, context model,
PlanV3 schema, command-handler ownership, retrieval limit, execution semantics,
or V3 evaluation gates change.

## Purpose

This is the canonical architecture and delivery plan for Mixroom AI V3. It
separates decisions that are frozen from values that must be measured. If a V3
prototype note, experiment, or implementation comment conflicts with this
record, this record wins unless it is explicitly superseded by another ADR.

V3 exists to improve request understanding and musical reasoning without
repeating either of these failure modes:

- V1: one direct model call, but a very large prompt and ambiguous legacy action
  maps.
- V2: strong safety foundations, but several semantic stages that could narrow,
  reinterpret, or block the same request.

The target remains understandable as:

```text
one semantic planner
-> one transactional executor
```

The planner contract and all semantic guidance live on the backend. Flutter
supplies bounded facts, validates the returned PlanV3, and remains the only
application execution authority.

## Server-owned contract amendment (2026-08-29)

Backend contract v3 is the sole source of truth for V3 system instructions,
command descriptions, canonical provider schema, tool-call policy, model and
reasoning selection, and token/cache/storage policy. It deliberately tracks the
V3 behavior on reverted main and excludes the reverted PR #27 semantic compiler,
goal classification, skipped-capability fields, and retry behavior.

Updated Flutter clients send `mixroom_v3_context_v1` facts and a sorted command
capability subset, accept only `v3_plan_response_server_v1`, and perform no
direct-provider or legacy fallback after a V3 failure. Released clients remain
supported temporarily by the separately controlled legacy backend route.

Adaptive, compact, retrieval, capture, and music-generation planner
experiments were removed from the shipped client. Any successor experiment
must be implemented behind a server-owned contract.

The former adaptive planner specification is retained as historical design
documentation only; it is not an active client architecture.

## Adaptive-planner amendment (2026-07-20)

Input profiling showed that clips, the complete command schema, rows, library
assets, and effect catalogs dominate the current V3 request. Real V3 captures
had a median 13,468 provider input tokens, while the synthetic maximum prototype
envelope exceeded 44,000 estimated tokens. The next V3 implementation therefore
uses:

- one immutable Flutter planning snapshot for the core and all retrieval;
- exactly 13 initial common commands for one-shot everyday editing;
- a compact capability-domain directory instead of all uncommon schemas;
- zero or one batched read-only retrieval round by the same planner;
- fresh live-state preparation after planning;
- a provider-neutral `MusicSpecV3` boundary rather than raw note arrays as the
  assumed production composition path;
- measured latency objectives rather than a fixed architectural timeout.

The current command surface is planned by backend contract v3. There is no
adaptive or shadow planner in the shipped application.

## Goals

V3 must optimize for:

1. Correct understanding of the complete request.
2. Strong musical reasoning.
3. No unintended, wrong-target, or partial project mutations.
4. Low architectural complexity and clear failure ownership.
5. Reasonable latency and cost.
6. Support for large projects, catalogs, and command surfaces.
7. Measured improvement over V1 in actual project state, not only valid JSON.

These goals are ordered constraints, not permission to add layers whenever one
case fails.

## Decision summary

| Area | Selected decision | Rejected direction |
| --- | --- | --- |
| Build location | Isolated V3 path behind flags; reuse selected infrastructure | Rewrite V1 in place or continue V2 orchestration |
| Meaning | One model owns semantic and musical interpretation | Intent model, selector model, specialist chain |
| Request | Preserve the original request verbatim | Lossy intermediate intent representation |
| Context | Immutable compact core; one same-planner retrieval batch when needed | Full unbounded dump, semantic packer, selector LLM |
| Commands | Versioned, operation-specific typed commands | Legacy action maps or generic payload bags |
| Targets | Stable IDs; transaction-local references for new resources | Names/indexes as authority or fuzzy repair |
| Factual checks | Operation-local handlers | Trusting the model or a central semantic validator |
| Execution | Prepare all, confirm by policy, commit one local transaction | Immediate model tool mutations |
| External work | Explicit staged job workflow | Pretending external jobs are locally atomic |
| Verification | Targeted handler readback and receipts | Exception-only success or mandatory full diff in production |
| Failure | Explicit and non-mutating | Silent V1 fallback or an LLM repair chain |
| Evaluation | Verified mutations, invariants, listening, latency, and cost | Contract tests or a small prompt list alone |

## Complete target architecture

```text
Original request
+ fixed authoritative core state
+ small common typed command surface
        |
        v
One GPT planner
        |-- respond
        |-- clarify
        |-- unsupported
        |-- submit PlanV3
        `-- request one batch of read-only facts
                         |
                         v
                  deterministic retrieval
                         |
                         v
                  same planner submits PlanV3
        |
        v
Flutter transactional executor
        |-- operation handlers prepare commands
        |-- deterministic risk/confirmation decision
        |-- atomic local commit or staged external job
        |-- rollback on failure
        `-- targeted verification and receipts
```

The backend authenticates production requests, enforces the V3 model and
reasoning configuration, proxies model calls, and records usage. It must not
independently compile PlanV3 into editor actions or duplicate Flutter execution
semantics. Updated clients use `/v1/llm/v3/responses`; older clients keep the
unchanged `/v1/llm/responses` V1 route. Direct OpenAI V3 is debug-only.

## Frozen architecture rules

The following rules require a new ADR to change:

1. One semantic planner receives the original request unchanged.
2. No mandatory intent LLM, context-selector LLM, critic LLM, or repair LLM is
   placed before execution.
3. PlanV3 uses typed operation-specific commands and stable target IDs.
4. Flutter is the sole authority for command preparation, expansion, local
   execution, undo, rollback, and readback.
5. Factual preparation is operation-local. There is no central component that
   reinterprets user intent or recompiles the plan semantically.
6. Model output never mutates the project while the model is still planning.
7. Local compound work is prepared completely and committed as one transaction.
8. Success messages for mutations come from verified receipts.
9. Active V3 has no silent semantic fallback to V1 and no semantic repair call.
10. Retrieval, when enabled, is read-only, planner-owned, batched, and limited
    to one round.

## Component responsibilities

### 1. CoreContextV3 builder

The application builds context from authoritative current Flutter state. It
does not interpret the wording of the request or pick facts because they seem
musically relevant.

The fixed core includes a documented representation of:

- project ID, state digest, tempo, meter, key, timeline, and playhead;
- current selection and pending confirmation/plan state;
- stable identities and lightweight state for addressable rows and clips;
- essential mixer state, instruments, loaded effects, and capabilities;
- counts and availability summaries for files, plugins, presets, instruments,
  effects, and library assets;
- current folder and selected file identities when a file browser is involved;
- limited recent conversation and stable user preferences, when available.

Names and display indexes are descriptive. Stable IDs are authoritative.

Detailed MIDI notes, analysis, parameter definitions, file metadata, or catalog
entries may be included under a fixed documented envelope. Every bounded list
must expose its total count and whether more items exist. Exceeding a production
envelope must never silently omit an explicitly addressed resource.

The representation must not change based on request keywords. Token counts are
measurements, not a semantic selection algorithm.

### 2. Catalog and large-state access

Large libraries cannot be dumped into every model call. The fixed core provides
factual counts, categories, currently used resources, and bounded deterministic
indexes. Once retrieval is enabled, the planner can request typed searches such
as:

```json
{
  "requests": [
    {
      "type": "library.search",
      "role": "kick",
      "pack": "Trap Essentials",
      "tags": ["dark", "short"],
      "limit": 12
    },
    {
      "type": "midi_clip.notes",
      "clip_id": "clip_42"
    },
    {
      "type": "effect.parameters",
      "effect_id": "effect_9"
    }
  ]
}
```

GPT chooses musical search terms. The application only performs factual
filtering over indexed metadata. It must not create a hidden semantic candidate
selector.

The same protocol covers off-screen state, file-browser entries, plugins,
presets, instruments, effect definitions, and deferred command namespaces.

### 3. Planner

The planner receives:

- the original request verbatim;
- fixed CoreContextV3;
- limited recent conversation;
- a small common typed command surface;
- the pending PlanV3 and explicit modification request when modifying a preview.

It returns one strict tool result. It owns all semantic and musical decisions:
target choice, operation choice, musical content, arrangement, and whether a
real ambiguity requires clarification.

The system prompt stays principle-focused. Operation facts live in schemas and
handler-owned metadata, not a growing list of prompt patches. Request-specific
regex repairs and case-specific prompt rules are forbidden.

For complex composition, the planner may return exact notes and placements or
use future typed pattern commands. Repeated structures should gain compact,
typed pattern representations rather than hundreds of copied events. This is a
command-contract expansion, not a second planner.

### 4. PlanV3

PlanV3 is a versioned discriminated contract. Product outcomes are:

- `plan`
- `respond`
- `clarify`
- `unsupported`

Retrieval is a separate strict `get_context_domains` tool available only on the
first planner call. It is not a PlanV3 outcome. The first call returns exactly
one `submit_plan_v3` or `get_context_domains` tool call; the continuation exposes
only `submit_plan_v3`.

A plan contains an ordered command list and a preview-oriented message. Typed
commands use operation-specific fields; generic `value`, `amount`, or legacy
action maps are not allowed.

Existing resources use stable IDs. Resources created in the same plan use
transaction-local references so later commands can target them without knowing
a runtime ID in advance. The executor binds the real ID within the transaction.

Strict structured output prevents malformed shapes. It does not establish that
the plan is factually executable; handlers do that.

### 5. Explicit preservation constraints

The production contract must be able to represent explicit constraints at the
resource-and-field level, for example:

```json
{
  "resource_id": "row_vocal",
  "fields": ["gain_db"]
}
```

Each command handler declares its write set. Preparation rejects a command only
when its concrete target and write set conflict with an explicit preservation
assertion.

This mechanism must obey all of these rules:

- no global operation-family bans;
- no language-specific regex extraction;
- no inferred preservation for every unmentioned resource;
- no target substitution or command deletion to make a conflict disappear;
- no second LLM validator.

The current prototype deliberately omits model-authored preservation because an
earlier version produced self-contradictory assertions and false blocks. It may
be reintroduced only after the core executor is reliable and dedicated tests
show that explicit constraints are represented without increasing false blocks.

### 6. Operation handlers

Each command variant has one Flutter handler that owns:

```text
schema facts
prepare
apply
undo
targeted readback
write set
risk metadata
```

Preparation may:

- resolve an exact stable ID;
- check resource existence, type, state, capacity, and capability;
- check numeric and enum ranges;
- convert units mechanically;
- expand a typed command into concrete existing editor operations;
- bind transaction-local references;
- compute expected readback.

Preparation may not:

- reinterpret the request;
- fuzzy-match or replace a target;
- drop, add, or reorder creative commands;
- choose a different sample, effect, note, or musical strategy;
- repair a semantically questionable plan.

A tiny transaction coordinator orchestrates handlers. It must not grow into a
universal semantic validator.

### 7. Confirmation and risk

Risk is deterministic metadata owned by command handlers and aggregated across
the transaction. The model does not assign risk.

Examples include reversible/local, destructive/local, and
asynchronous/external. User and product policy decide which categories require
confirmation. Exact thresholds are empirical product choices.

Every command must have an explicit deterministic execution policy. The
current reversible command surface is classified `auto_apply`; `confirm` is
reserved for future irreversible or external side effects. An unclassified
command fails safely, and a compound plan uses its strictest contained policy.

### 8. Local execution

Execution follows this order:

1. Strictly parse PlanV3.
2. Prepare every command against one state digest.
3. Reject the complete plan if any command cannot be prepared.
4. Auto-apply the current reversible commands, or show the deterministic
   preview when an explicit future `confirm` policy requires it.
5. Recheck the state digest immediately before execution.
6. Apply the complete bundle through one undo transaction.
7. Read back every affected property.
8. Compare expected and observed state.
9. Commit one undo entry and generate receipts only after verification.
10. Roll back all captured changes in reverse order after any failure.

No compound request may leave a created row, inserted clip, changed setting, or
other partial result behind after failure. Idempotent commands may produce no
mutation when readback proves that the requested state already exists.

### 9. External and asynchronous work

Stem separation, uploads, remote rendering, analysis jobs, and similar work
cannot honestly share local atomicity. They use an explicit staged workflow:

```text
plan job
-> confirm
-> start job
-> receive result
-> revalidate current project
-> apply result in a new local transaction
```

Failures must identify which stage failed. Starting an external job is itself a
receipt-bearing event; applying its result is a separate transaction.

### 10. Verification and messages

Each handler performs targeted readback and returns factual before/after data.
The transaction verifies all affected properties and emits receipts.

Use full project diffing in automated tests and debug/evaluation captures to
detect unintended mutations. Do not require a full project diff for every
production action unless measurement justifies it.

User-facing ownership is hybrid:

- plan previews are generated from typed commands;
- mutation success is generated from verified receipts;
- factual, tutorial, and creative explanations may come from GPT;
- failures come from specific context, preparation, execution, or job errors.

GPT must never claim that an unexecuted plan was applied.

### 11. Failure behavior

V3 fails explicitly and without mutation for stale state, unknown IDs,
unsupported commands, unavailable resources, invalid parameters, timeouts, and
verification mismatches.

Transport calls may use bounded transport retries. The system must not silently
send a rejected semantic plan to V1 or another model for reinterpretation.
While V3 is shadow-only, V1 may remain the visible system, but the two results
must stay independent in captures.

### 12. Conversation

Current project state is authoritative. Include only a bounded recent history,
the pending plan/confirmation, and stable preferences required for follow-ups.
Do not add an LLM conversation summarizer until long-session evidence proves it
is needed.

Modify sends the original pending plan, fresh current state, and an explicit
modification request to the same planner. The result is a complete replacement
plan, not a partial patch.

### 13. Model choice

V3 is model-independent. Default model and reasoning effort are selected by
matched evaluation of verified correctness, musical quality, latency, cost,
and repeated-run stability. Do not add adaptive per-request model routing during
the prototype; it creates another decision layer before the base path is proven.

### 14. Optional audio review

Symbolic state verification proves that commands executed, not that a creative
result sounds good. Creative quality therefore requires human listening in the
evaluation gate.

A future rendered-audio critic may be tested for subjective composition or mix
work. It is not part of the mandatory V3 mutation path and must not become a
general semantic veto over precise edits. Adding it requires separate evidence
and an ADR update.

## Current prototype versus complete architecture

The debug prototype is a vertical slice, not the full V3 product.

| Area | Current prototype | Complete target |
| --- | --- | --- |
| Planner | One strict one-shot call | Same planner; optional one retrieval continuation |
| Outcomes | `plan`, `respond`, `clarify`, `unsupported` | Same final outcomes; first call may instead use the dedicated retrieval tool |
| Commands | 21 typed variants, including exact row effect-instance controls | Expand through audited capability slices |
| Context | Full bounded identities/state/catalog under hard limits | Fixed scalable core with counts/`has_more` and retrieval |
| Targets | Existing stable IDs; new row embedded in destination | Stable IDs plus general transaction-local references |
| Preservation | Original request and narrow command effects; no assertion field | Explicit resource-field assertions checked against write sets |
| Confirmation | Every mutation | Deterministic handler risk plus product policy |
| Execution | Flutter preparation and existing editor actions | Handler-owned prepare/apply/undo/readback for each command |
| Async work | Unsupported | Explicit staged jobs |
| Evaluation | Development captures | Sealed gate, unseen holdout, scale tests, human listening |

The current command list is recorded in
[`../ai_v3_capability_matrix.md`](../ai_v3_capability_matrix.md). Its limits must
not be mistaken for a prompt-specific test implementation or a final product
surface.

## Known prototype findings that must remain visible

Exploratory testing has shown that the one-planner direction is promising on a
small typed surface, but it is not production evidence. Known risks include:

- context grows quickly when every clip, note, and asset is serialized;
- literal repeated drum placements are inefficient and motivate typed patterns;
- creative one-shot plans can exceed practical latency limits;
- editor unit conversions must be shared and tested, especially dB/fader state;
- compound rollback must capture every mutation, including row state changes;
- state digests and debug diffs must include every mutable domain, including
  effects;
- targeted verification must also detect missing or unexpectedly changed
  resources;
- symbolic execution cannot judge whether a creative layer sounds appropriate.

These are capability, executor, scale, and evaluation work. They are not reasons
to add another semantic planner or a broad central validator.

## Capability expansion rule

Before expanding prompts or schemas, maintain the capability inventory in:

- `docs/engineering/ai_v3_capability_matrix.md`
- `tool/ai_v3_eval/v3_capabilities.yaml`

For each user capability, establish separately:

- V1 advertised behavior;
- V1 model output shape;
- actual editor support;
- target semantics and required state;
- V3 typed command or staged workflow;
- prepare/apply/undo/readback ownership;
- unit, transaction, scale, and end-to-end evidence.

Do not promise “all V1 functionality” from a prompt audit alone. A capability is
ported only when its actual mutation and undo/readback behavior are proven.

Add capabilities in representative vertical slices, rerunning evaluation after
each slice. Prefer domain namespaces that can later be loaded on demand rather
than one permanently enormous tool schema.

## Delivery phases

### Phase 1: Executor foundation without GPT

- Define PlanV3, initial typed commands, stable IDs, and local references.
- Implement operation handlers, transaction coordination, receipts, and
  handwritten-plan tests.
- Prove compound rollback and readback through the real editor.

### Phase 2: One-shot planner

- Send fixed CoreContextV3 to one planner.
- Keep retrieval disabled.
- Run planner shadow-only first; activate only after non-mutating output review.
- Measure context profiles instead of inventing a permanent token target.

### Phase 3: Matched shadow evaluation

- Keep V1 visible and V3 detached/non-mutating.
- Compare matched models where possible.
- Score expected and observed project mutations, not just output JSON.

### Phase 4: Bounded retrieval

- Add the dedicated `get_context_domains` tool and one batched read-only round.
- The continuation receives only the original request, fixed core context,
  typed retrieval request, and retrieved factual results.
- Do not preserve or depend on hidden model reasoning.
- Cover libraries, off-screen entities, MIDI details, effect parameters, files,
  plugins, presets, and deferred command namespaces.

### Phase 5: Controlled capability expansion

- Complete the V1/editor capability audit.
- Add one command domain at a time.
- Add compact typed musical patterns where scale evidence requires them.
- Add staged external jobs separately from local transactions.
- Rerun the holdout and scale suite after each slice.

### Phase 6: Gradual activation

```text
shadow
-> internal opt-in
-> limited rollout
-> continued V1 comparison
-> broader rollout
```

The clean V3 branch selects authenticated one-shot V3 for updated clients.
Older released clients retain V1, and a build-time V3 switch can produce a V1
client without removing either implementation. There is no silent per-request
V3-to-V1 retry. Adaptive V3 remains detached shadow-only.

## Evaluation plan

### Development work

Use a small development set only for plumbing, schema debugging, broad prompt
corrections, and deterministic context-profile experiments. Do not add
request-specific rules. Old demonstration prompts are regression examples, not
the architecture target.

Test fixed deterministic context envelopes across:

- small, medium, and large projects;
- audio-only, MIDI-only, and mixed projects;
- few and many plugins/effects;
- small and large libraries;
- duplicate names and different selection states;
- long conversations and pending-plan modifications.

Freeze the smallest representation that preserves factual success. Record
input/output tokens, latency, cost, missing-context failures, and verified
outcomes.

### Prototype gate

After freezing the prompt, context profile, PlanV3 schema, and preparation code,
run a sealed 30-case set covering precise edits, compound work, ambiguity,
multilingual requests, explicit preservation, unsupported work, and bounded
creative tasks.

Primary binary success requires all of:

- correct intent, target, and values;
- every requested operation completed;
- explicit preservation maintained;
- no unintended mutation;
- successful execution and readback.

Also report false clarification/block rate, wrong-target rate, invalid plans,
preparation and execution failures, rollback failures, latency, tokens, cost,
and blinded creative-quality scores.

The initial prototype continuation criterion is:

- V3 Mini exceeds matched V1 Mini by at least three verified successes;
- V3 beats frozen V2 overall and has fewer false blocks;
- zero wrong-target or protected-state mutations;
- no partial compound commits;
- no more than two combined invalid-plan, preparation, and execution failures;
- creative quality is not worse than the best baseline;
- latency and cost are practically usable.

If it narrowly misses, allow one broad architecture-consistent prompt/context
correction and use a newly generated sealed set. Do not add another semantic
stage or case-specific repair.

### Production claim gate

Passing 30 cases is not enough to claim V3 is better. Freeze the implementation
and run a separate unseen 75-case holdout from identical disposable project
states against matched V1 and frozen V2. Require zero critical wrong-target or
preservation violations, report confidence intervals and failure categories,
and require a meaningful verified-success improvement over V1.

Evaluation also includes:

1. command-handler unit tests;
2. synthetic project and catalog scale tests;
3. malformed, stale, contradictory, and timeout cases;
4. actual editor mutation, undo, rollback, and duplicate-Apply tests;
5. full before/after debug diffs;
6. human listening for creative output;
7. latency and cost measurements.

## Complexity budget

V3 must not repeat the V1 or V2 growth patterns. Apply these rules during review:

- A planner failure is not automatically a new stage.
- A factual handler failure is not automatically a prompt rule.
- No language-specific parsing or request-specific regex safeguard is added.
- No central validator accumulates operation-specific policy.
- No command is added without handler and end-to-end evidence.
- No context field is added without a named consumer and scale measurement.
- No retrieval type is added unless deterministic and read-only.
- No second model call is mandatory for requests that can be solved one-shot.
- Repeated event arrays should become typed compact structures when measured
  scale justifies it.
- Architecture changes must be evaluated on fresh cases, not only the failure
  that motivated them.

## Consequences

V3 should be easier to reason about than V2 because semantic interpretation has
one owner and factual failures have operation-local owners. Typed commands,
stable IDs, atomic transactions, and readback retain the useful V2 safety work.

The tradeoffs are a growing typed command catalog, the need for reliable stable
IDs and editor handlers, and a possible second planner call for genuinely large
state. The bounded retrieval seam addresses scale without making every request
multi-stage.

This architecture cannot guarantee musical taste. It creates a clearer path to
measure and improve musical planning while keeping execution factual and safe.

## Supersession rule

Do not revise this ADR by quietly adding exceptions to implementation code. A
change to a frozen rule requires an explicit ADR amendment or a superseding ADR
with evidence and migration impact.
