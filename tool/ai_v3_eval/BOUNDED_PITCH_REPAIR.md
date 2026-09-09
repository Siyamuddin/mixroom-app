# Bounded pitch repair — offline prototype

Historical report: the original **offline, inactive prototype** phase. The
subsequent local-only handler integration is described in
`PITCH_REPAIR_LOCAL_INTEGRATION.md`. Production activation remains disabled.
The results and boundaries below describe the original prototype phase only.

## What changed

The existing contract-6 parser now exposes its structural checks separately;
the normal entry point still runs those checks followed by strict semantic
validation. The ordered semantic simulator has an explicit, private analysis
argument for collecting unsupported pitches. No request field can enable it.
No existing handler, bridge, instruction asset, tool schema, client, deadline,
model setting, usage record, or infrastructure file was changed in this phase.

`bounded_pitch_repair.py` is an evaluation-only consumer of that analysis. It:

- Resolves instruments through the existing simulator, including preceding
  instrument selection, new rows, and generated clip references.
- Builds one required integer property per invalid note. Allowed intervals are
  derived from capabilities, with gaps preserved; the model supplies the pitches.
- Sends the request/history, affected commands, timing, and relevant capabilities,
  not the whole project or command catalog.
- Reconstructs a copy, verifies that every non-target field stayed identical,
  and subjects the entire plan to ordinary strict validation again.
- Rejects malformed, oversized, incomplete, refused, duplicate-key, extra-field,
  missing-field, wrong-tool, repeated-tool, and out-of-range patches.
- Never calls a provider, changes stored projects, or logs raw plans/context.

Numeric bounds and nested `anyOf` follow the official
[Structured Outputs schema subset](https://developers.openai.com/api/docs/guides/structured-outputs#supported-schemas).
The upstream conversion retains `strict: true` and the selected repair tool.

## Deliberate eligibility limits

Only explicit note arrays in create, replace, and append are repairable.
Unknown instruments and any other semantic failure are ineligible. An analyzed
plan is **not** executable; only a reconstructed, fully validated plan is accepted.

After the first unsupported pitch, the prototype accepts only subsequent explicit
note operations, row creation/rename, mix goals, and effect configuration/removal/
bypass operations. Other later commands are conservatively ineligible, including
transpose and instrument changes **even on apparently unrelated targets**.
There is no dependency solver and no cumulative/fallback repair loop. This narrow
coverage is intentional for the prototype, not a claim of universal recovery.

Only unsupported pitches may change. This may be insufficient for some musical
voicings; execution validity is not a musical-quality score. A refusal remains a
safe failure. Existing first-pass pitch mistakes and provider timeouts remain possible.

## Deterministic comparison

Five small synthetic fixtures: three accepted mocked patches (create two sections,
replace, append), one rejected note-boundary failure, and one rejected downstream
transpose dependency. These are reconstructed fixtures, **not recovered original
provider plans**. All accepted plans preserve every non-target field.

| Measurement | Full-plan repair | Targeted repair |
| --- | ---: | ---: |
| Two-section canonical request | 57,839 bytes | 3,160 bytes |
| Two-section canonical upstream request | 57,836 bytes | 3,157 bytes |
| Two-section serialized upstream request | 61,333 bytes | 3,239 bytes |
| Two-section output arguments | 796 bytes | 45 bytes |
| Single-command canonical requests | 57,840–57,841 bytes | 2,357–2,358 bytes |
| Single-command output arguments | 440–441 bytes | 23 bytes |

Both report runs were byte-identical; shuffled fixture order is also a test gate.
Reports contain only counts, sizes, preservation results, and failure categories.
Synthetic secret-marker tests verify that request/history/project/plan text does
not appear in the report or prototype stdout.

Informational local timing, 20 two-section iterations on this machine:

- Analysis and repair-body construction: median 5.875 ms; p95 6.702 ms.
- Patch reconstruction and full validation: median 5.194 ms; p95 5.387 ms.

Timing is not a hard gate. **No provider latency, live repair reliability, or
musical quality was measured.** Smaller payloads alone do not establish those gains.

## Verification and reproduction

Backend: 314 tests passing, including 14 new tests with multiple subcases.
Client/editor: 237 selected tests passing, including transaction/rollback checks.
The backend suite includes frozen legacy compatibility and the deterministic
profiler/baseline checks. Existing profile baselines were not updated.

The test-only provider adapter intercepts the real handler's already bounded
repair call. It proves one attempt for valid plans, at most two for repairs,
27→17 and 55→45 second shared-budget behavior after ten simulated seconds,
unchanged timeout/invalid-output responses, and exactly one finalization or
release. Invalid patches return the rejected plan to normal validation in this
adapter; this is **not** production integration or another provider call.

From the worktree root, using the existing backend test environment:

```sh
PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s backend/llm_proxy/tests -p test_bounded_pitch_repair.py -q
PYTHONDONTWRITEBYTECODE=1 python backend/llm_proxy/tests/test_bounded_pitch_repair.py --report
PYTHONDONTWRITEBYTECODE=1 python backend/llm_proxy/tests/test_bounded_pitch_repair.py --timing
```

The full suite needs localhost binding for its existing fake bridge tests. Flutter
tests need SDK-cache write permission. Neither requires live provider access.
No Python bytecode artifacts were generated; `git diff --check` passed. Existing
local edits outside the shared semantic-contract file were verified unchanged.

Next decision: whether to approve a fixed synthetic live comparison of existing
full-plan repair versus this candidate under the same remaining deadline. Do not
activate it, alter first-pass instructions, or claim the timeout problem solved
before that evidence exists.
