# AI V3 one-shot planner

> Implementation snapshot only. The canonical complete architecture and
> delivery plan is [ADR 0002](engineering/adr/0002-ai-v3-architecture.md). The
> capability inventory is
> [AI V3 Capability Matrix](engineering/ai_v3_capability_matrix.md). If this
> prototype note conflicts with the ADR, the ADR wins.

V3 uses the same compact one-planner architecture in local evaluation and
updated production clients:

```text
original request + deterministic CoreContextV3
                    -> one GPT planner
                    -> strict PlanV3
                    -> Flutter preparation, confirmation, transaction, readback
```

The active one-shot path has no Intent LLM, selector, semantic validator,
repair call, Python compiler, or silent V1 fallback. Flutter is the only
preparation and execution authority. Updated clients use authenticated one-shot
V3; released older clients continue using the unchanged V1 endpoint.

The initial `PlanV3` deliberately has no model-authored preservation or
negative-policy map. The original request remains authoritative, and each typed
command changes only its operation-specific target and state. Flutter rejects
unknown targets, unavailable resources, stale state, malformed payloads, and
failed readback, but it does not reinterpret the request or add semantic vetoes.

## Production and compatibility routing

Updated clients default to one-shot V3 through the authenticated
`/v1/llm/v3/responses` proxy route. The backend owns the Luna model, low
reasoning effort, output ceiling, usage accounting, and server kill switch.
OpenAI credentials never ship in the app.

Set `AI_V3_PRIMARY_ENABLED=false` at build time to produce a V1-compatible
client. This is an explicit route selection, not a silent per-request fallback.
Older released clients remain unchanged because they continue calling
`/v1/llm/responses`.

Direct OpenAI V3 remains available only for explicit local debug evaluation:

```text
AI_V3_PROTOTYPE_ENABLED=true
AI_V3_MODEL=gpt-5.6-luna
AI_V3_REASONING_EFFORT=low
AI_V3_CONTEXT_PROFILE=essential
AI_V3_CAPTURE_ENABLED=true
AI_V3_CAPTURE_DIR=tool/ai_v3_captures.local
```

Production backend settings are:

```text
AI_V3_ENABLED=true
AI_V3_MODEL=gpt-5.6-luna
AI_V3_REASONING_EFFORT=low
```

Use `enriched` and `rich` for the deterministic context-profile experiment.
Projects above 32 rows, 128 clips, 512 MIDI notes, or 250 indexed assets return
specific `prototype_context_*_limit` errors instead of truncating or falling
back.

Every mutating plan is previewed. Apply and Cancel are local; Modify sends the
fresh state, pending plan, original modification request, and fixed context to
the same one-shot planner, which must return a complete replacement plan. The
planner receives current and maximum row capacity, and preparation rejects row
creation beyond that limit. Apply rejects a changed state digest. Local actions
run in one undo transaction and are read back; any failed action or mismatch is
rolled back in reverse order.

Detached comparison planners run only when their explicit debug flags are
enabled and a local capture is active. Those are additional paid API calls and
must remain off outside an intentional evaluation session.

## Development evaluation

Deterministic unit and integration suites are the committed verification
surface. Live provider comparisons are deliberately not included in this clean
branch. Local captures may be enabled explicitly for manual evaluation, remain
ignored, and must never be committed.

## Prototype boundaries

- Fifty-three typed commands covering 65 of 87 canonical V1 operations; at
  most 16 commands per plan.
- Transport playback, restart, metronome, and loop state roll back with a
  failed V3 bundle but never enter normal user Undo/Redo history. Mixed-plan
  Undo reverses persistent edits without rewinding successful transport state.
- At most 96 serialized MIDI notes per plan and eight bars per generated clip;
  existing-clip MIDI edits may result in at most 512 notes.
- Built-in effect configuration uses exposed parameter IDs; existing row
  effect removal and bypass use exact native instance IDs.
- No external jobs, fuzzy target matching, or repair. Local staged Spleeter
  and Basic Pitch operations complete before their editor mutations. Adaptive
  V3 supports one bounded factual retrieval round in detached shadow mode;
  active one-shot V3 remains a single planner call.
- Captures are observational and never affect the visible result.
