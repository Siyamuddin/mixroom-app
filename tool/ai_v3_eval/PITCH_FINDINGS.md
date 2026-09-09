# PRO-4 pitch investigation — local results, 2026-09-07

## Decision

Subsequent adjacent-range-summary experiment: **13/20 baseline versus 17/20
candidate**, with six versus two pitch failures and one truncation each. It
remains evaluation-only because it missed the 18/20 gate. See
[the separate presentation experiment](PITCH_PRESENTATION_EVAL.md); its larger
synthetic catalog differs from the earlier paragraph experiment below.

Keep the existing generation instructions. The isolated candidate failed its
adoption gates. Precise server-derived pitch feedback is implemented locally for
the existing single repair attempt, but it is not a demonstrated reliable cure.
End-to-end acceptance has **not passed**. Do not treat this report as release approval.

### Follow-up: deterministic client transaction fix

The two-section execution failure was reproduced without a model: two ordinary,
unreferenced MIDI creations on the same guitar row, each 32 beats long, both
executed but were then rolled back. Before the fix, the offline native test
expected two clips and read back zero. After the fix, the same test passes,
including exact note/timing checks and atomic undo/redo.

Cause: ordinary creations omit `command_id` unless another command references
their output. Without a runtime clip ID, the final verifier matches new clips by
row, instrument, and duration. Both sections match, so `candidates.length != 1`
rejects a valid result. This is an identity-tracking defect, not invalid music.

Fix: capture clip IDs before each V3 creation and bind its single new clip to
the expectation identified by `producer_action_index`, even for unreferenced
outputs. Existing referenced-output binding and strict content verification
remain in place. No provider body, public schema, backend behavior, pitches,
timeouts, or old-client path changes. No additional provider calls were made.

The original live failure remains recorded below; its full plan was not retained.
The deterministic test proves the matching two-section defect and its correction,
not that every historical transaction failure had this cause. Live end-to-end
acceptance and first-pass pitch reliability are not claimed by this offline fix.

Regression: `integration_test/ai_v3_midi_creation_identity_test.dart` creates only
a new synthetic project, never deletes other projects, and calls the editor's
local prepared-handoff execution directly (no bridge or model request).
Logs: `/tmp/pro4-midi-identity-before.log`, `/tmp/pro4-midi-identity-after.log`,
and `/tmp/pro4-midi-identity-final.log`.

Final follow-up gates passed: the expanded native regression covers two sequential
sections, indistinguishable layered clips, referenced output bindings, exact
notes/durations, undo/redo, stale-plan rejection, and rollback after a later
failure. All 216 selected client tests and all 299 backend tests also passed.
Generated macOS dependency-lock changes from the test build were reverted;
`git diff --check` passed. No commit, push, PR update, or deployment.

## Confirmed cause

The synthetic clarification/follow-up reproduced pitches 36 and 38 in command
index 0 (`midi.create_clip`), resolved to `sfz.guitar.clean_electric`, whose
advertised range is 40–86. This matches the bundled ElectricGuitar SFZ range.
The constructed provider context contains that range unchanged. No deterministic
metadata, remapping, or instrument-resolution defect was established for this
failure, so no sample, cache, or catalog change was made.

The historical full rejected plan was not retained. Its exact command sequence
cannot be reconstructed; the new synthetic reproduction supplies attribution,
not proof of every detail of the historical plan. The original request,
clarification, and follow-up are preserved in `evaluate_pitch.py`.

## Local implementation

- Pitch errors attach zero-based command index/type, effective instrument ID,
  distinct sorted rejected pitches, and allowed intervals. Existing validated
  command, MIDI pitch, identifier, and range limits bound the details.
- Only the existing pitch repair request receives those details, as JSON data.
  The original request/context remain present; the full rejected plan is not added.
- No new public response, analytics, usage-record, or persistent-log fields.
  First-pass provider bodies and tool schemas are unchanged by this work.
- Validation, shared deadlines, one-repair limit, settlement, and safe rejection
  remain intact. No application pitch shifting/clamping or instrument substitution.
- `pitch_candidate.py` is evaluation-only; neither runtime instruction variant
  imports or adopts it. Pre-existing language/boundary edits remain intact.

## Controlled comparison

40 synthetic initial-generation calls: 20 baseline and 20 candidate, interleaved,
five scenarios with four repetitions. Same provider adapter as the local bridge,
but directly invoked to exclude handler repair from first-pass scoring.
Settings: gpt-5.6-luna, low reasoning, 8192 output tokens, 55-second deadline.

| Result | Baseline | Candidate |
| --- | ---: | ---: |
| Structurally valid, correct section count and instrument | 17/20 | 15/20 |
| Pitch violations | 2 | 2 |
| Truncated provider output | 1 | 1 |
| Provider timeouts | 0 | 2 |
| Wrong-language replies among valid plans | 1 | 1 |
| Valid scope/instrument plus English reply | 16/20 | 14/20 |
| Other scope/instrument failures among valid plans | 0 | 0 |
| Median latency | 17.200 s | 13.685 s |
| p95 latency (nearest rank, all attempts) | 22.779 s | 55.019 s |
| Maximum latency | 47.079 s | 55.073 s |

Backend validation, section count/length/start, and ordered instrument resolution
were checked by code. The instrument grader was corrected to resolve generated
rows through `row.create.arguments.lane.instrument_id`; stored results were
rechecked without rerunning the model. Language was manually reviewed, not
model-graded: baseline drums repetition 2 and candidate low-guitar repetition 2
were German. Language of invalid/unparseable plans is not counted as passing.
No musical-quality claim is made from structural checks.

The candidate fails both the +2-success and 18/20 gates. These small samples do
not establish population failure rates or latency distributions.

Limitation: the live drum fixture advertises a synthetic contiguous 35–81 range,
not an actual sparse native remap. Native sampled-pitch/remapping tests ran
separately; the live comparison does not fully satisfy that planned scenario.

## Repair results — separate from generation

Two independent replay probes used the captured baseline pitch failure, precise
feedback, and a 34-second budget derived from the original remaining deadline.
One repeated the pitch failure (15.149 s); one produced a valid two-section plan
at beats 0 and 32, each 32 beats long (13.319 s). These are replay probes, not two
retries within one user request. One success out of two is insufficient evidence
of reliable recovery.

## Native acceptance — failed, safely rolled back

A new synthetic empty guitar project was created; existing projects were not
deleted or resized. The app and bridge were rebuilt/restarted locally.

1. Original 16-bar request: first-pass pitch failure; repair then failed the
   arrangement limit. Backend 502 after 35.449 s, two provider attempts.
2. Follow-up: first-pass arrangement-limit failure; repair returned a valid
   two-command plan. Backend 200 after 39.667 s, two provider attempts.
3. Client preparation succeeded. Both guitar instruments loaded, but execution
   raised `AiV3TransactionFailure(rollbackIncomplete=false, cause=StateError)`.
   Saved readback contains zero clips and undo depth zero.

The integration test also encountered existing Flutter semantics assertions.
Those do not erase the separate observed execution rollback. The underlying
StateError message was not retained in the existing privacy-filtered error log;
its precise cause remains unconfirmed. Do not attribute it to pitch validation
without further evidence. No successful app acceptance is claimed.

## Verification and next action

The complete backend suite passed **299 tests**. Relevant client/editor,
serialization, and native-sample tests passed **226 tests**. Frozen compatibility
checks, deterministic profiler baselines (including twice-run comparison), and
`git diff --check` passed. The native live acceptance test failed as described
above. New tests cover precise feedback/privacy,
ordered instrument changes, generated-row resolution, endpoints, gaps, rejected
pitch deduplication, and unrestricted instruments. Existing retry/timeout,
settlement, boundary, language, and transaction rollback tests remain in place.

The proposed offline two-section replay has now identified and corrected the
client identity defect (see follow-up above). Keep the separate pitch-generation
reliability issue open; do not adopt the failed prompt candidate or weaken
readback verification.

Raw synthetic outputs and diagnostics remain outside the repository:

- `/tmp/pro4-pitch-comparison.json`
- `/tmp/pro4-pitch-repair-probes.json`
- `/tmp/pro4-pitch-native-test.log`
- `/tmp/pro4-pitch-native-backend.log`
- `/tmp/pro4-pitch-native-readback.json`
- `/tmp/pro4-pitch-backend-final.log`
- `/tmp/pro4-pitch-client-tests.log`
- `/tmp/pro4-pitch-profile-final.json`

No commit, push, PR update, deployment, production-log query, timeout change, or
infrastructure mutation was performed. Live synthetic calls incurred normal
provider usage. The native app retains its existing telemetry/sync behavior;
this was not a claim of whole-app network isolation.
