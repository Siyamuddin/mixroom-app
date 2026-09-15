# Safe row rebuild — deterministic gate findings

Follow-up completed: the paired previous-candidate/revision comparison produced
**14/20 versus 16/20** complete first-pass successes. The revision is **not
adopted**: it missed 18/20 and had an observed language failure. See
[the full revision report](ROW_REBUILD_REVISION.md). Historical results below
refer to the earlier runtime-baseline/first-candidate comparison.

## Completed comparison (2026-09-08): do not adopt

Exactly **20 baseline and 20 candidate** first-pass calls completed, using the
same synthetic states, model/settings, current 105-second deadline and runtime
schemas. Calls were interleaved with two workers. No repair was invoked. The
existing credential was retrieved read-only with explicit user approval; no
production configuration, bridge, app project or deployed code was changed.

| First-pass result | Baseline | Candidate |
|---|---:|---:|
| Executable plan satisfying scored scope | 3/20 | 14/20 |
| Last-row deletion rejected | 13 | 2 |
| Capacity exceeded | 0 | 2 |
| Unsupported pitch | 0 | 2 |
| Unnecessary clarification | 3 | 0 |
| Valid but incomplete replacement scope | 1 | 0 |
| Non-English replies (overlapping category) | 1 | 0 |
| Provider timeout/upstream failure | 0 | 0 |

Baseline's one scope failure created five replacement rows but supplied notes
for only one; its receipt incorrectly described five completed parts. All
partial-rebuild outputs preserved the protected row/clip. Language review of
all retained replies found one Spanish baseline clarification and otherwise
English. Language review was direct inspection, not a model grader or a new
runtime writing-system rule.

| Scenario | Baseline successes | Candidate successes |
|---|---:|---:|
| Exact jazz restart | 0/4 | 4/4 |
| Rebuild with spare capacity | 0/4 | 0/4 |
| Rebuild at full capacity | 0/4 | 3/4 |
| Single-row replacement | 0/4 | 4/4 |
| Partial rebuild/protected row | 3/4 | 3/4 |

The candidate improves observed planning but **fails the 18/20 adoption gate**
and has two observed pitch failures versus none detected in baseline. Earlier
last-row failures may mask other errors, so that comparison does not prove the
candidate caused more unsupported pitches. Neither ambiguity changes the
failed adoption decision. Both instruction assets remain unchanged by this
evaluation; the candidate remains inactive. No additional trials or prompt
revisions were added after seeing results.

All **18 backend-valid executable plans** also pass the actual Dart parser and
preparer, including the scope-incomplete baseline plan (preparation validity
does not certify fulfillment). These generated outputs were not executed in
the native app. The earlier synthetic native execution/undo/rollback gates
remain separate evidence. Post-adoption app acceptance was not triggered
because the candidate was not adopted.

Provider median/max: baseline **15.045s / 21.341s**, candidate
**15.499s / 23.258s**. These constrained synthetic scenarios do not establish
production latency or subjective musical quality. Fixture catalogs are small
and synthetic; the exact jazz prompt is preserved but the original full plan
was not retained.

Verification: complete backend suite **351 passed**, then all **10 focused eval
tests passed** after adding the position-anchor scoring regression; relevant
client regressions **203 passed**; all 18 generated valid-plan client checks
passed; `git diff --check` passed. No Python bytecode artifacts were generated.

Evidence stays outside the repository:

- `/tmp/pro4-row-rebuild-comparison.jsonl` (synthetic context/plans)
- `/tmp/pro4-row-rebuild-comparison-progress.log`
- `/tmp/pro4-row-rebuild-eval-final-backend.log`
- `/tmp/pro4-row-rebuild-eval-client-regressions.log`
- `/tmp/pro4-row-rebuild-live-client-check.log`

Recommended next decision: retain the proven local identity/memory corrections
and focus any separately approved planning iteration on ordered capacity during
complete rebuilds. Do not loosen validation, auto-reorder plans, increase
timeouts, or claim the current instruction candidate is production-ready.

## Evaluation setup

`evaluate_row_rebuild.py` now prepares the five approved synthetic scenarios
and a fixed, alternating 20-baseline/20-candidate first-pass schedule. All
requests pass current contract validation. Upstream bodies differ only in the
capacity instruction paragraph; model, reasoning, 16,384-token ceiling,
105-second deadline and all 54 commands are held constant. Six offline runner
tests pass, including no retries on timeout and deterministic request bodies.
The complete backend suite passes **348 tests** with loopback sockets enabled
(`/tmp/pro4-row-rebuild-eval-backend-local.log`). The first sandboxed run was
blocked on 11 local socket-bind tests; the permitted rerun passed unchanged.
`git diff --check` passes; no Python bytecode artifacts were generated.

The runner itself accepts only local environment credentials. The approved
launch wrapper loaded the pre-existing AWS credential without printing it and
supplied it in memory. The earlier missing-shell-key blocker was resolved.

Reproduction command (not authorization for additional calls; never paste a key
in chat):

```sh
PYTHONDONTWRITEBYTECODE=1 /tmp/pro4-v6-venv/bin/python \
  tool/ai_v3_eval/evaluate_row_rebuild.py --execute-live \
  --output /tmp/pro4-row-rebuild-comparison.jsonl
```

The runner refuses to overwrite existing evidence. Generated synthetic plans
remain outside the repository for actual client preparation, scope/protected
content checks and English-language review. Backend validity alone is not
reported as overall success. Those acceptance checks and the original adoption
gates remain mandatory; no runtime code imports this evaluation runner.

## Current result: native memory defect identified and corrected locally

This section supersedes the historical blocked/unknown-root-cause notes below.

Address Sanitizer captured a **heap-use-after-free** in
`MeterTapProcessor::processBlock`: the audio callback read a meter after
`JuceEngine::removeRow` destroyed the owning `RowState` on the main thread.
The processor can remain in a retained JUCE graph render sequence after row
deletion. Previously it held only raw pointers into that row's meter state.
Evidence: `/tmp/pro4-asan-report.48577` (allocation, deletion and invalid-read
stacks). This is a real native lifetime defect, not a model-output error.

The processor now retains shared ownership of its meter state for its own
lifetime. Its audio callback still accesses immutable pointer targets with no
new per-block ownership operations, locks, allocation or musical changes.
Retarget operations now assert the existing stable-address invariant instead of
writing pointer fields concurrently with rendering. Both row and group creation
supply ownership. The identical correction is applied to the shared
iOS/macOS/Windows engine and its Android copy.

A separate setup race was also confirmed under the debugger: controller
attachment preceded project initialization (one initial row was observed where
the fixture required six). The opt-in evaluation snapshot now exposes
`project_ready`, and the new test waits on that condition before editing.
This field is not part of provider context, public responses or persistence.
The native test also asserts that its entire acceptance sequence completed.

Verification so far:

- Full native rebuild under Address Sanitizer: passed, no sanitizer report.
- Full normal native rebuild: **three consecutive passes**, each with the
  `all_checks_completed` marker. Apply/readback, undo/redo, injected-failure
  rollback, generated references, stale positional hints, and deleted generated
  destinations are covered.
- AI backend suite: **342 passed**, including legacy/provider/profiler guards.
- Relevant client/MIDI/persistence/transaction tests: **271 passed**.
- Unchanged older native identity/undo/rollback test: passed with the fix
  (`/tmp/pro4-baseline-meter-fixed.log`), using isolated project storage.
- Cross-platform meter-ownership source guards: **5 passed**. These are
  supplemental source checks, not substitutes for native execution.
- `git diff --check`: passed. Normal non-sanitized build restored and verified
  not to link the sanitizer runtime.

Logs: `/tmp/pro4-rebuild-asan-fixed.log`,
`/tmp/pro4-rebuild-meter-fixed-normal2.log`,
`/tmp/pro4-meter-fixed-repeat-{1,2}.log`,
`/tmp/pro4-rebuild-readiness-backend.log`,
`/tmp/pro4-meter-fix-client-tests.log`,
`/tmp/pro4-meter-contract-tests2.log`.

Native execution/sanitizer evidence is macOS-specific; Android, iOS and Windows
device execution was not performed. The matching native ownership code and
source guards do not imply those platforms have been runtime-tested.

The capacity instruction candidate is still inactive and no live comparison
calls were made. No prompts, schemas, deadlines, billing, provider behavior or
infrastructure were changed during this correction. No commit, push, PR update
or deployment. Obsolete owned debugger/test processes were stopped; other app
processes and projects were left alone.

## Follow-up: local row-identity correction

The editor now captures the intended stable destination row ID before MIDI clip
creation, independently of the produced clip. Both referenced and unreferenced
outputs retain that destination for verification. Final verification resolves
the row's current position from its stable identity. Row deletion no longer
retires a bound MIDI creation expectation merely because its old numeric index
matches another row being deleted. Actual destination deletion still retires it.
Clip identity, note/instrument/duration checks and rollback are retained.

The corrected native run reached successful **apply, undo, and redo** assertions
for the valid four-row rebuild. It subsequently stalled; a checkpoint rerun
crashed during the injected-failure portion. The OS crash report identifies
`EXC_BAD_ACCESS` on `io.flutter.raster` (Metal/DisplayList frames), not the prior
`v3_readback_mismatch`. This identifies the crashing thread, **not a proven root
cause or proof that the failure is harmless/environment-only**.

Test-only explicit frame pumping and an offstage run also failed to complete;
those ineffective workarounds were removed. No production graphics changes were
made. The expanded native test adds referenced outputs, existing destinations
with stale positional hints, distinct notes per destination, and removal of a
generated destination, but the complete expanded test is **not yet green**.
Rollback, the added cases, and complete native acceptance remain pending.

After the correction: **342 AI backend tests passed** (including legacy/provider
and profiler baselines); **247 relevant client tests plus 24 row-identity,
transaction and resource-lifecycle tests passed**. `git diff --check` passed.
Logs: `/tmp/pro4-row-rebuild-fixed-backend.log`,
`/tmp/pro4-row-rebuild-fixed-client.log`,
`/tmp/pro4-row-rebuild-identity-tests.log`, and
`/tmp/pro4-row-rebuild-fixed-native2.log` (apply/undo/redo checkpoints and crash).

The prompt candidate remains inactive; no model comparison calls were made.
Do not adopt the prompt or claim release readiness until the native regression
completes. The manually running app was not restarted and is not proof of the
new fix. No commit, push, PR update, deployment, or deadline change occurred.

### Native isolation follow-up

- Full rebuild with failure injection disabled still crashed. The injected
  malformed action is not required to trigger the crash.
- Substituting the built-in `mixroom.neon_lead` instrument also crashed, so
  sampled-guitar loading alone does not explain it.
- Load-only control passed (13 seconds): six synthetic rows, no AI commands.
- Seed-only control passed (13 seconds): six explicit MIDI creations, no row
  deletion, rebuild, or undo.
- Single-deletion control passed (13 seconds): six seeded clips followed by
  deleting one row, with five remaining clips verified.
- Full-rebuild/no-undo control passed (13 seconds), including exact four-row,
  four-clip, per-part note and instrument readback and ten seconds of UI frames.
- Allowing two seconds of UI frames after each handoff did not resolve the
  full test: rebuild and undo checkpoints passed, then redo crashed. That
  ineffective pacing workaround was removed.
- Crash sites vary across Flutter raster/text rendering, platform message
  dispatch, and Dart runtime memory teardown. No native root cause is proven;
  these results do not establish that the problem is harmless or environmental.
- The seed-undo control crashed at startup before project-load/undo checkpoints
  (one second; `SkPath`/`CanvasPath` finalization on `DartWorker`). It provides
  **no undo result** and prevents attributing all crashes to rebuild or undo.
  Passing individual controls does not establish a reliable native test gate.

The test-only `PRO4_REBUILD_CONTROL` selector provides `load`, `seed`, `delete`,
`rebuild` (no undo), and `seed-undo` isolation runs. Leaving it unset always runs
the full regression.
`PRO4_REBUILD_INSTRUMENT` substitutes an instrument for isolation only;
`PRO4_REBUILD_INJECT_FAILURE=false` skips only the injected-failure subcase.
Neither is a runtime app setting. Controls cannot replace the full acceptance
gate. Logs remain outside the repository in `/tmp/pro4-row-rebuild-*.log`.
No additional production-code changes were made during this isolation pass.

### Controlled comparison with the previously passing test

The existing `ai_v3_midi_creation_identity_test.dart` was run unchanged through
`pro4_native_baseline_control_test.dart`. The wrapper changes only project
storage to a temporary directory; the original actions and assertions are
unchanged. It **passed**, including undo/redo, stale-plan rejection, generated
clip bindings and injected-failure rollback (three seconds).

The full new rebuild test with default settings still crashed. A controlled
rerun with only the latest row-identity fix removed also crashed at startup
(one second), before project-load/AI checkpoints. Thus the latest correction
is not necessary to trigger the native crash; this does **not** identify the
root cause or certify the full rebuild regression.

The application source was restored exactly afterward. SHA-256 before and
after: `fecdf20717ba251e2085456487a675b1a411e34f8ea2ab090b7cad1be3bd800f`.
No earlier PRO-4 changes were removed. The manually running app was untouched.

Evidence: `/tmp/pro4-native-unchanged-baseline.log`,
`/tmp/pro4-native-rebuild-comparison.log`, and
`/tmp/pro4-native-rebuild-without-fix-verified.log`.
The preliminary `without-fix.log` run is excluded from the comparison because
source verification was still being completed during that build.

Next investigation should use the unchanged passing test as the baseline and
isolate the new test's setup/execution differences. Do not infer a native-engine
fix from crash-stack locations or start live prompt comparison yet.

### Repeated baseline and framework-error controls

The older test was repeated unchanged in three fresh native processes:
**two passed, one timed out at three minutes**. The timed-out run reported
`LiveTestWidgetsFlutterBinding.postTest` asserting `!_expectingFrame`, so it
had an outstanding frame request. A native stack sample showed the main thread
servicing events/platform messages and the raster thread waiting for events;
it does not identify the exact Dart await or establish a native deadlock.
Logs: `/tmp/pro4-native-baseline-repeat-{1,2,3}.log`;
sample: `/tmp/pro4-baseline-hang.sample.txt`.

This corrects the earlier assumption that the older test was a reliably green
control. The timeout is not proven to share a cause with the native crashes.

Moving new-test storage initialization to the passing wrapper's `setUpAll`
lifecycle did not prevent the crash and was reverted. Removing the existing
framework-error filter exposed an accessibility assertion requiring matching
`value`/`increasedValue` for a SemanticsNode increase action. However, disabling
forced test semantics also failed to prevent a native crash. Neither experiment
established a root cause; both were reverted. Logs:
`/tmp/pro4-rebuild-lifecycle-control.log`,
`/tmp/pro4-rebuild-framework-errors.log`,
`/tmp/pro4-rebuild-no-forced-semantics.log`.

No application changes were made in this follow-up. Do not classify the crashes
as merely a new-test defect, remove undo/rollback gates, or adopt prompt changes
on this evidence. The next useful diagnostic is capturing the native invalid
memory access at its origin rather than further variations of the AI fixture.

The remaining sections document the original pre-fix gate findings.

## Status

Stopped at the approved deterministic compatibility gate. No active prompt,
schema, validation, executor, timeout, infrastructure, or billing change was
made in this step. No live model calls, commit, push, PR update, or deployment.
The capacity-instruction candidate remains evaluation-only and is not imported
by runtime code. Existing unrelated PRO-4 changes were preserved.

## Confirmed failures

The manual request asked to remove everything and rebuild as relaxing jazz.
The metadata-only backend trace showed six `row.delete` commands followed by
four `row.create`/`midi.create_clip` pairs. Command index 5 was rejected by the
last-row invariant. The full original plan was not retained. The shared fixture
is explicitly synthetic; it preserves that observed ordering and exact request,
not invented claims about the original notes or arguments.

The valid synthetic order is: delete five old rows, create a replacement row and
clip, delete the final old row, then create the remaining three row/clip pairs.
Backend envelope/semantics and client parsing/preparation accept this sequence,
including with the initial six-row capacity full.

Native editor execution creates four replacement rows and four clips, but final
verification returns `v3_readback_mismatch` and rolls back. A temporary diagnostic
at verification (before rollback) established:

| New clip | Expected row index | Actual row index |
| --- | ---: | ---: |
| First | 1 | 0 |
| Second | 1 | 1 |
| Third | 2 | 2 |
| Fourth | 3 | 3 |

The first clip is created after the surviving old row. Deleting that old row
correctly shifts the new clip from index 1 to index 0. Its `midi_clip_created`
expectation retains index 1. The verifier requires both the bound clip identity
and that stale numeric row index, so it rejects the valid result. This is a
client execution/readback disagreement, not an LLM latency issue.

Relevant code is the `midi_compose` identity binding, row-deletion expectation
maintenance, and `midi_clip_created` final verification in the editor.
Temporary runtime diagnostic statements were removed after confirmation.

## Added coverage and results

- Shared Python/Dart fixtures: observed invalid order; valid full/spare capacity;
  one row with and without room; deleted stable IDs and generated references;
  capacity overflow; a partial rebuild preserving an unrelated row.
- Backend tests validate full provider envelopes and normal strict semantics.
- Candidate tests require exactly one capacity-paragraph replacement in each
  instruction variant; final language guidance remains untouched.
- Full AI backend suite: **342 passed**, including frozen legacy checks and two
  deterministic profiler runs matching existing baselines. The first sandboxed
  run could not bind loopback sockets; the permitted rerun passed.
- Relevant client/contract/MIDI/action-flow/persistence suite: **247 passed**,
  including all **9 shared row-rebuild cases**.
- Native regression: **fails reproducibly** at the intended four-row result
  assertion because execution rolled back to six original rows. The diagnostic
  rerun confirmed the exact stale-index comparison above.
- The native test includes successful undo/redo and injected-failure rollback
  assertions, but those are **not reached yet**. Do not claim they passed.
- No profiler baseline changes. `git diff --check` passed. No new Python
  bytecode artifacts or dependency-lock changes were found.

Local logs: `/tmp/pro4-row-rebuild-backend-tests.log`,
`/tmp/pro4-row-rebuild-client-tests.log`, `/tmp/pro4-row-rebuild-native.log`.
The native fixture uses a separate system-temporary project root, not the open
manual-test project. Its desired-success regression remains intentionally red.

## Next isolated correction

Fix created-clip destination verification to follow stable row identity across
ordered topology changes, while still enforcing the intended destination,
instrument, notes, timing, and clip identity. Do not drop the destination check
or reorder model commands. Cover both referenced and unreferenced clip outputs,
deletion before/after creation, deleted destinations, and genuine wrong-row
placement. Then rerun native execution/readback, undo/redo, and failure rollback.

Only after that gate passes should the approved 20-baseline/20-candidate model
comparison run. It has **not** been run, and there is no adoption evidence yet.
Keep the original adoption gates; no additional trials or prompt reminders.

The evaluation approach follows the official OpenAI guidance to use task-specific
tests and clear criteria rather than subjective impressions:
[Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices).
