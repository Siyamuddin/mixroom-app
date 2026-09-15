# Existing MIDI-note input capacity

The client no longer rejects complete project snapshots solely because they
contain more than 512 MIDI notes. Contract 6 exempts only
`clips[].midi_notes` from its generic 512-item list guard. Other collections,
depth, node-complexity, finite-number, and semantic validation remain guarded.
This is not unlimited input: the existing 140,000-byte core-context and
180,000-byte incoming-request envelopes remain unchanged.

The client checks complete UTF-8 serialized input before authentication/network
access. Oversize input is rejected explicitly, never sampled or truncated.
Backend capacity rejections also receive the actionable client capacity message.

Generated-note budgets (512 capable / 256 fallback), action budgets
(32 capable / 16 fallback), schemas, prompts, provider settings, entitlements,
and deadlines are unchanged. No new capability marker is necessary: the server
accepts more existing context without increasing any client's output budget.
An older backend can still reject a larger snapshot safely.

Offline regressions cover snapshots of 300, 512, 513, 600, and 1,024 notes,
exact note preservation, proxy forwarding, UTF-8 oversize rejection without
authentication/network/provider/quota calls, and the user-facing failure message.
The 300-to-600 snapshot sequence models continuation after an additive edit;
it is not a claim of native execution or live model acceptance.

Existing project row/clip/library caps are intentionally unchanged.

## Native acceptance (2026-09-08)

The isolated native test uses `input_notes_local_fixture.py` on port 8771 and
`integration_test/ai_v3_generated_midi_budget_local_test.dart` with
`AI_V3_INPUT_NOTES_LOCAL_TEST=true` (instead of the generated-budget test flag).
Use the same other local flags documented in `GENERATED_MIDI_BUDGET.md`, pointing
all local endpoints at 8771, and set `LLM_MAX_OUTPUT_TOKENS=16384` on the bridge.
Restart this three-request fake fixture before each run.

The app creates two 512-note clips with two separately valid output plans, then
requests a track rename while preserving the complete 1,024-note project. The
fake provider asserts exact input note arrays in the actual constructed provider
body. The real backend validates each plan; the real client prepares and executes
it. Accepted assertions include clip/note preservation, rename readback,
undo/redo, save/reopen, and native offline WAV signal/placement checks.

The first setup run failed before the capacity check because the clip destination
was not yet an instrument row. A subsequent run passed all assertions. The test
now waits for the editor's existing `project_ready` signal and expected clip
count, rather than relying only on controller attachment and a fixed delay.
An intermediate readiness check used fields from a different snapshot format;
that test-only mistake was corrected to use the existing readiness signal.
The final run with this readiness signal passed all assertions in 16 seconds
after build, including persistence of the renamed row after reopening.
Final logs: `/tmp/pro4-input-native-app-final.log` and
`/tmp/pro4-input-native-bridge-final.log`. The dedicated fake bridge was stopped.

The passing run used three requests, one fake-provider attempt each, three usage
finalizations, and no release or repair. Its third request carried 98,142 bytes
of core context and 99,959 bytes of incoming request, including all 1,024 notes.
Fake usage and latency are not live-provider measurements.

All projects and WAV exports are temporary synthetic artifacts. Project #132 and
the existing manual bridge are untouched. No live provider calls, production
access, commit, push, or deployment occurred.
