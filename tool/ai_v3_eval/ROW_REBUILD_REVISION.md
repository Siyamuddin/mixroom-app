# Rebuild ordering and playable-note revision — 2026-09-08

## Current local status: adopted by explicit user decision

After reviewing the results, the user approved adopting the exact 16/20 revision
locally and removing the later row-order repair experiment. Both contract-6
instruction assets now contain precisely the tested capacity and pitch paragraphs.
No thresholds or historical scores were changed: this is a user-approved exception
to the original adoption gate, not a claim that the gate passed or that production
success is 80%. The four observed failures below remain limitations.

The experimental row-repair handler path, private row-error details, module and
runner were removed. Existing pitch repair, strict validation, tiny-boundary and
512-note support, deadlines, legacy behavior and unrelated local work remain.
Historical eval helpers reconstruct the pre-adoption instruction wording so old
comparisons retain their original request bodies. No new live trials were run.
No app/bridge restart, commit, push, PR update or deployment was performed.

Local adoption verification: **358 backend tests and 218 client/editor tests
passed**. All five constructed provider bodies exactly match the earlier tested
revision, and historical comparison request hashes remain unchanged. Both
profiler runs are deterministic. Only instruction/request sizes and hashes
changed (+839 instruction bytes); schemas, counts and other provider fields
remain unchanged. The two instruction-asset golden hashes were updated; legacy
snapshots were not changed. `git diff --check` passes and no Python bytecode was
generated. A regression verifies the removed row-repair opt-in cannot trigger a
provider retry. The running manual bridge may retain previously cached wording
until a separately requested restart.

The original evidence and failure categories remain explicit, consistent with
[OpenAI's task-specific evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices).

The following section records the original evaluation decision at the time.

## Historical evaluation decision: do not adopt

Exactly 40 approved live first-pass calls completed: 20 previous-candidate
controls and 20 revisions. The control is the earlier **inactive 14/20
candidate**, not the runtime instructions or the historical 3/20 baseline.

| Outcome | Previous candidate | Revision |
|---|---:|---:|
| Complete first-pass success, including English | 14/20 | 16/20 |
| Backend-valid executable plans | 14 | 17 |
| Last-row deletion rejected | 2 | 0 |
| Capacity overflow rejected | 0 | 1 |
| Unsupported pitches rejected | 3 | 1 |
| Other invalid output: unavailable row reference | 1 | 0 |
| Unnecessary clarification | 0 | 1 |
| Wrong-language reply | 0 | 1 |
| Provider timeout/upstream failure | 0 | 0 |

The revision gained two complete successes but missed **18/20**, and observed
capacity and language failures increased. Runtime instructions remain unchanged.
No additional calls, prompt revisions, threshold changes or automatic adoption.
Both candidates remain inactive; this is not a release-ready improvement.

| Scenario successes | Previous candidate | Revision |
|---|---:|---:|
| Exact jazz restart | 3/4 | 2/4 |
| Spare-capacity rebuild | 1/4 | 4/4 |
| Full-capacity rebuild | 3/4 | 2/4 |
| Single-row replacement | 4/4 | 4/4 |
| Partial rebuild/protected content | 3/4 | 4/4 |

## Exact remaining revision failures

1. Jazz restart, repetition 0: three row creations occurred before any deletion;
   command index 2 would increase six original rows to nine with max_rows eight.
2. Full-capacity rebuild, repetition 0: unnecessary clarification claiming no
   capacity to create rows, although authorized deletions could free capacity.
3. Full-capacity rebuild, repetition 1: command index 10 (`midi.create_clip`)
   generated pitch 36 for `free-piano`, advertising inclusive range 40–84.
4. Jazz restart, repetition 3: valid musical plan, but the reply was German.

All 40 replies were read directly: the other 39 were English. No model grader or
runtime writing-system detector was introduced. Protected content was preserved
in all partial-rebuild outputs. One already-invalid control also left an old row
behind; that overlap is not counted as a separate failed trial.

Two scorer review flags were resolved by inspecting the actual commands, without
changing the frozen scorer: control jazz repetition 1 adds mix goals only to its
new piano/guitar rows (within rebuild scope); revision jazz repetition 3 sets
tempo to 82 for the complete relaxed-jazz rebuild (within scope, but still fails
language). These reviews do not substitute for native execution.

## Implementation and deterministic checks

- Retained the six original synthetic failed plans and the earlier incomplete
  baseline plan, with exact contexts and provenance, in a regression fixture.
  These are retained evaluation outputs, not reconstructed historical app plans.
- Added the exact approved two-paragraph revision as pure, separately testable
  capacity/pitch substitutions. Both contract-6 instruction variants are covered.
  No runtime handler imports it; command schemas and public interfaces are unchanged.
- Reused the original five scenario requests and provider adapter. The previous
  candidate body is byte-equivalent under canonical serialization to its original
  construction. Only the two instruction paragraphs differ for the revision.
- Locked scope, schedule, request hashes, source hashes and adoption gates in an
  external manifest before calls. Verified the frozen manifest and all 40 output
  request hashes afterward. Two workers, alternating variant order, one provider
  attempt each, no repair/retry calls.
- Scope scoring requires all five requested partial-rebuild rows to be replaced
  and supplied with notes; an empty replacement row does not pass. Position
  anchors to protected rows remain read-only references, not protected edits.
- Replayed both original pitch failures through the existing repair implementation:
  four invalid note entries each; explicit mocked pitches reconstruct valid plans
  and preserve every non-target field. Actual handler tests use one repair with
  shared 105/95-second remaining budgets and correct finalization/release behavior.
  No repair redesign was needed or made. Mocked recovery is not live recovery evidence.

Verification:

- Complete backend suite: **357 passed**, including frozen legacy, failure,
  settlement, pitch/boundary, policy budget and compatibility regressions.
- Focused row rebuild/revision checks after the final scorer change: **17 passed**.
- Relevant client/editor/persistence/transaction regressions: **218 passed**.
- Existing isolated native rebuild test: passed with `all_checks_completed`,
  covering real execution/readback, undo/redo and injected-failure rollback.
- Every backend-valid generated executable plan: **31/31 pass the actual client
  parser/preparer**. These newly generated plans were not executed in the app.
- Two profiler runs pass approved baselines; all four scenarios have identical
  deterministic sizes/counts/hashes after excluding informational timings.
- `git diff --check` passes; no Python bytecode artifacts were generated.

Native acceptance uses private synthetic storage. The manual app, project #132,
and running bridge were not restarted or changed. Runtime/deployed behavior,
schemas, timeouts, model, billing, legacy paths and existing work are preserved.
The existing AWS credential was retrieved read-only under the user's approval,
kept in memory, and not printed or written to reports. No commit, push, PR update
or deployment occurred.

## Evidence and limitations

Provider-call-plus-validation median/max: control **15.411s / 21.705s**, revision
**20.209s / 30.563s**. No latency improvement was established. Small synthetic
catalogs and twenty observations per variant do not establish production rates
or subjective musical quality. Earlier semantic failures can mask later ones;
observed category changes do not establish why the model made them. The combined
trial does not isolate the effects of the two paragraphs.

Evidence outside the repository:

- `/tmp/pro4-rebuild-revision-results.jsonl`
- `/tmp/pro4-rebuild-revision-results.manifest.json`
- `/tmp/pro4-rebuild-revision-progress.log`
- `/tmp/pro4-rebuild-revision-backend.log`
- `/tmp/pro4-rebuild-revision-client.log`
- `/tmp/pro4-rebuild-revision-native.log`
- `/tmp/pro4-rebuild-revision-live-client.log`
- `/tmp/pro4-rebuild-revision-profile{1,2}.json`

The demonstrated conclusion is limited: stronger instructions improved this
sample but did not satisfy reliability/non-regression gates. Retain the proven
local identity/memory corrections and existing strict validation. Do not stack
further reminders or treat this experiment as justification to widen limits,
auto-reorder commands, clamp notes, or add retries.
