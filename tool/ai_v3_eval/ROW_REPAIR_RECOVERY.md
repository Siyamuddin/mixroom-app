# Bounded row-order recovery

> Historical report: the user subsequently chose the earlier 16/20 instruction
> revision. This row-repair experiment's code, handler integration and runner have
> been removed locally. Its results below are retained as evidence, not active
> behavior. The removed implementation is recoverable from
> `/tmp/pro4-row-repair-before-removal.tar.gz`. See `ROW_REBUILD_REVISION.md` for
> the current local decision. No deployment occurred.

## Scope

This local, default-off experiment extends the existing single repair attempt to
two precisely attributed failures: last-row deletion and row-capacity overflow.
It does not change first-pass instructions, command schemas, public errors,
client execution, model settings, deadlines, entitlements or billing logic.
Both earlier instruction candidates remain inactive.

The server validates the original proposal itself and attaches private failure
details. A trusted local context attribute, `_local_v3_row_repair_enabled`, is
required. Request JSON, headers and environment variables cannot opt in. The
manual bridge is not modified or restarted by this experiment.

The existing full-plan tool receives the original request/context, rejected
proposal and precise failure details as untrusted data. The complete repair body
must fit the existing request budget. Unknown bounds and impossible maximum-one-
row replacements are rejected without calling the provider.

Returned command IDs/types, every non-note argument and the relative order of
non-row-lifecycle commands are locked to the original proposal. The model may
reorder row creation/deletion and regenerate explicit notes. Application code
does neither. Full semantic validation is still mandatory. Invalid repairs do
not trigger another pitch or full-plan repair, and no partial result is exposed.
Detailed feedback stays out of final logs, analytics and usage records.

## Evaluation method

`evaluate_row_repair.py` drives the actual handler with a synthetic rejected first
response. It simulates 15 seconds already spent, then uses the real remaining-
deadline calculation for one repair call (normally 89 seconds after integer
rounding). That simulated first-pass time is not measured provider latency.

There are exactly five frozen scenarios and four repetitions each: last-row,
capacity overflow, single-row replacement, mixed ordering/unsupported pitches,
and partial rebuild with protected content. The retained mixed fixture has four
unsupported note entries. Single-row and partial-capacity adaptations are
explicitly synthetic. Runtime first-pass instructions are used, not either
experimental instruction candidate.

An external manifest freezes source request/plan hashes, repair-body hashes,
schedule and gates before calls. Calls are serial to avoid global test mocks
interfering with each other. There are no live first-pass generation calls,
replacement trials or retries. Credentials are retrieved read-only, kept in
memory and not logged. Reports are aggregate; synthetic client-check artifacts
are outside the repository.

The unchanged handler is compared by deterministic replay of the same rejected
proposals. Its safe rejection is not a failed live control call. Recovery success
does not measure first-pass quality or prove production timeout rates.

Adoption requires at least 18/20 valid scope-preserving repairs, no accepted scope
violations or wrong-language replies, and all compatibility/client gates. Even
passing does not enable the manual bridge: local acceptance is a separate step.

## Results — 2026-09-08: do not activate

Exactly 20 approved live repair calls completed. **14/20** produced complete,
valid, scope-preserving plans, below the required 18/20. No replacement trials
or additional retries were made. All request hashes and the schedule match the
pre-call manifest. Every trial made one synthetic first attempt and one live
repair attempt. The unchanged handler rejects all five frozen input proposals
with the existing 502 response; it offers no row-order recovery.

| Scenario | Accepted repairs | Remaining failures |
| --- | ---: | --- |
| Last-row deletion | 3/4 | One duplicated MIDI operation |
| Capacity overflow | 4/4 | None in this sample |
| Single-row replacement | 4/4 | None in this sample |
| Mixed ordering and unsupported pitches | 0/4 | Unsupported pitches in all four |
| Partial rebuild/protected content | 3/4 | One unsupported-pitch plan |
| Total | 14/20 | Six safely rejected |

Exact remaining failures, using zero-based trial/command indices:

- Mixed-pitch repetitions 0–3: command 9, `midi.create_clip`, still includes
  pitches 36 and 38 for the synthetic piano whose inclusive range is 40–84.
  Row ordering was corrected, but playable-note validation still fails.
- Partial-rebuild repetition 1: command 10 generates pitches 36 and 38 for the
  same range-limited synthetic piano. This fixture's original notes were valid;
  full-plan recomposition introduced a pitch failure.
- Last-row repetition 3: the model duplicated its final MIDI-create command.
  The scope guard rejected the extra operation; normal semantics also rejects
  the duplicate command ID.

No scope-changing result was accepted. All 20 available replies were inspected
directly and were English. No runtime language detector or model grader was
added. There were no refusals, clarifications or provider timeouts in these 20
repair calls. This is not evidence that language consistency or unnecessary
clarification is solved generally.

All **14 accepted plans pass the actual client parser/preparer**. These live
outputs were not executed in the manual app. Separately, the existing isolated
native rebuild fixture passed execution/readback, undo/redo and injected-failure
rollback with `REBUILD_CHECKPOINT all_checks_completed`. It uses private
synthetic storage and is not native acceptance of all 14 generated plans.

### Latency and provider usage

Measured repair-call-plus-local-handler latency: median **15.470 seconds**, p95
**17.179 seconds** (nearest-rank), minimum **6.045 seconds**, maximum **18.365
seconds**. These exclude the simulated 15-second first pass. All repair calls
received an 89-second remaining budget. No end-to-end production latency or
timeout improvement is claimed.

Reported usage across the 20 live repair calls:

- Input: **234,244 tokens**, including **201,693 cached input tokens**.
- Output: **31,975 tokens**, including **2,395 reasoning tokens**.
- Total: **266,219 tokens**. The synthetic first passes have no provider usage.

Normal provider charges apply even to rejected repairs. Mocked application
settlement finalized 14 successful trials and released six failed trials; no
production usage store or billing record was accessed or changed.

### Compatibility and deterministic verification

- Complete backend suite: **370 passed**, including 13 row-repair tests,
  frozen legacy/provider-body, handler failure/settlement, pitch, boundary and
  generated-note-budget regressions.
- Client/editor/persistence/transaction regressions: **218 passed**.
- All five mocked repairs pass the real handler and client parser/preparer.
- First-pass provider bodies are identical with the local flag enabled/disabled.
  Contract 3 remains unaffected. Missing opt-in retains existing behavior.
- Tests reject missing/duplicate/changed commands and every changed non-note
  argument, altered non-lifecycle order, unresolved resources, unknown bounds,
  impossible capacity, over-budget repair requests and malformed results.
- Expired budgets skip repair; invalid pitches after ordering repair cannot
  trigger a third attempt. Failure responses contain no partial plan.
- Final logs, analytics and usage records exclude the new private repair data.
- Both profiler runs pass existing baselines and have identical sizes, counts
  and hashes for all four profiles. `git diff --check` passes. No Python bytecode
  artifacts were generated.

### Decision and limits

Keep this implementation **local and default-off**. Do not activate it in the
manual bridge or move to a local acceptance run: the adoption gate failed.
The experiment demonstrates useful ordering recovery but insufficient combined
reliability. Full-plan repair can retain invalid pitches or introduce new ones,
and can duplicate an operation; validation and scope checks prevented acceptance.
Do not add a second repair, weaken validation, alter notes in application code,
or retune against these outputs automatically.

The existing 180,000-byte repair preflight can safely skip larger requests; these
small synthetic catalogs do not establish recovery rates for large real
projects. The repair details describe the first detected row error, not an
exhaustive inventory of later semantic failures.

No first-pass instruction, public contract, schema, client capability,
persistence, timeout (105/115/120/130), model, quota or billing-logic change was
made in this phase. AI repair remains backend-only. The manual bridge and project
#132 were untouched. No commit, push, PR update, deployment or production mutation
occurred. Language consistency and unnecessary clarification remain open.

Evidence outside the repository:

- `/tmp/pro4-row-repair-live.jsonl` and its `.manifest.json` sibling.
- `/tmp/pro4-row-repair-live-progress.log` and `-live-client.log`.
- `/tmp/pro4-row-repair-backend-final.log`, `-client.log`, and `-native.log`.
- `/tmp/pro4-row-repair-offline-plans.jsonl` and `-offline-preparer.log`.
- `/tmp/pro4-row-repair-profile1.json` and `-profile2.json`.
