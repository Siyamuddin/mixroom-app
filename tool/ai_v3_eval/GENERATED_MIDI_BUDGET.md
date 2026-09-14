# PRO-4 generated MIDI budget

Local implementation and isolated native acceptance; no deployment, live provider
calls, or commits. The native test launches a test app with a new temporary project.

## Contract

Updated clients emit `project.generated_midi_policy = "notes_512_v1"` in core context.
The backend resolves server-owned budgets; arbitrary numeric client budgets are not used.

| Effective capability | Aggregate and per-command explicit notes | Canonical accepted plan bytes | Output-token ceiling |
|---|---:|---:|---:|
| Missing or unknown | 256 | 24,000 | 8,192 |
| `notes_512_v1` | 512 | 64,000 | 16,384 |

All explicit entries in create/replace/append count, including repeated replacements.
No truncation, deduplication, pitch clamping, or timing changes are introduced.
Current contract-6 generation instructions state the shared ceiling, not a target.
Frozen legacy contracts and schema assets are unchanged. Runtime contract-6 schemas
derive their per-command note limits from the effective capability, including references.
Fingerprinting includes the budgeted instructions and effective budgets.

## Verification

- Shared JSON fixture: `backend/llm_proxy/tests/fixtures/generated_midi_budget_v1.json`.
- Backend and Dart boundaries: 256, 257, 512, 513; repeated commands and aggregate validation.
- Backend mixed create/replace/append, ordered instrument selection, generated references,
  byte ceilings, missing/unknown markers, schema limits, fingerprints, and operational caps.
- Mocked handler accepts 512 in one attempt for capable clients and rejects oversized plans;
  full-plan repair remains at most one additional attempt, retaining budget and settlement.
- Targeted pitch reconstruction of a 512-note plan preserves all non-target fields;
  repeated invalid pitches and mixed boundary failures remain rejected.
- Client parsing/preparation, exact 512-note editor-action readback, undo/redo,
  serialized MIDI-note save/reopen, and simulated native-sync failure rollback pass.
- AI backend regression suite and relevant client/editor suites include existing deadline,
  language, boundary, frozen legacy, and failure/settlement tests. Profiler tests run twice
  and compare deterministic baselines; timing is not a gate.

The AI backend suite passed all 336 tests. The client suite passed 370 tests with one
existing skip. `git diff --check` passed and no Python bytecode artifacts were generated.
The separate application API
suite ran 409 tests with one billing failure and two collaboration errors. These also
reproduce in the corresponding isolated suites; `backend/app_api` has no worktree diff.
They are outside this implementation, so the entire repository is not claimed green.

## Operational limits and remaining acceptance

### Native acceptance — passed on 2026-09-08

`integration_test/ai_v3_generated_midi_budget_local_test.dart` ran against
`generated_midi_local_fixture.py`, a two-request fake provider using the real local
REST adapter and backend handler. Its provider asserts the effective 16,384-token
budget; the test process explicitly sets `LLM_MAX_OUTPUT_TOKENS=16384` without
changing the manual bridge or infrastructure configuration.

- All 512 notes crossed the backend/client/editor boundary with exact pitches,
  starts, lengths, velocities, instrument, and clip placement.
- Native offline WAV export from the actual engine graph was silent before the
  planned start and contained signal near both the beginning and end of the clip.
  The same assertions passed after save/dispose/reopen. This is audio/timing
  coverage, not subjective musical-quality grading or proof of every audible note.
- Undo/redo preserved the exact clip snapshot. The 513-note plan was rejected
  without changing clips, rows, or undo depth.
- Two requests, one provider attempt each; one usage finalization and one release.
  No repair, model call, or provider-latency claim.
- Native integration test passed in 11 seconds after build. Nine focused backend
  budget/fixture tests and static analysis of the native test also passed.
- No dependency-lock changes remained; `git diff --check` passed. The dedicated
  fake bridge was stopped; the existing manual bridge was not changed.

Run from the worktree root, with the normal app closed:

```sh
PYTHONDONTWRITEBYTECODE=1 LLM_MAX_OUTPUT_TOKENS=16384 python tool/ai_v3_eval/generated_midi_local_fixture.py --port 8769
```

In another terminal:

```sh
flutter test integration_test/ai_v3_generated_midi_budget_local_test.dart -d macos --no-pub \
  --dart-define=AI_V3_GENERATED_MIDI_LOCAL_TEST=true \
  --dart-define=AI_V3_PRIMARY_ENABLED=true \
  --dart-define=AI_V3_RESOURCE_REFS_ENABLED=true \
  --dart-define=AI_V3_LONG_PATH_ENABLED=true \
  --dart-define=AI_V3_LONG_API_BASE_URL=http://127.0.0.1:8769 \
  --dart-define=LLM_PROXY_API_BASE_URL=http://127.0.0.1:8765 \
  --dart-define=APP_API_BASE_URL=http://127.0.0.1:8769 \
  --dart-define=SUBSCRIPTION_API_BASE_URL=http://127.0.0.1:8769
```

Restart the test bridge before each run. Project and WAV artifacts are under the
unique temporary directory printed by `LOCAL_512_NATIVE`; no existing project is used.

### Remaining operational considerations

An explicit `LLM_MAX_OUTPUT_TOKENS` remains an administrative upper bound. The existing
SAM template defaults it to 8,192; this work does not change the template or deployed
configuration. Without an explicit cap the capable contract defaults to 16,384. A future
rollout must separately review configuration if 16,384 is desired. Malformed caps retain
the previous conservative 8,192 fallback. Token reservation uses the effective request
budget, and existing accounting rules are unchanged.

Command count (16), generated clip length (eight bars), timeouts, model/reasoning, input
counts, and entitlements remain unchanged. In particular, input context still accepts
only 512 existing notes total: creating more project content can make a later request
exceed that separate limit. The acceptance fixtures stay within it.

512 is an allowed maximum, not a guaranteed output size: byte/token budgets and the
shared deadline still apply. Higher permitted output may increase provider usage.
No live latency, musical quality, or production readiness is inferred from these
deterministic tests. Live model acceptance requires separate approval.
